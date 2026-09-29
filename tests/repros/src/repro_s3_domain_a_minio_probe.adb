--  Live MinIO probe for S3-DOMAIN-A-1, -2 and -4.  Needs a running MinIO
--  from the image pinned in tests/scripts/test-minio.sh:
--
--    IMG=quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f332\
--    1eff8e708c1e2960462bd8936e
--    docker run --detach --rm --name flyology-review-domain-a-$$ \
--      --publish 127.0.0.1::9000 \
--      --env MINIO_ROOT_USER=FLYOLOGYS3ORACLE \
--      --env MINIO_ROOT_PASSWORD=flyology-s3-oracle-secret-key-tests \
--      "$IMG" server /data --address :9000
--
--    cd tests/repros
--    FLYOLOGY_REPRO_MINIO_PORT=<mapped port> \
--    AWS_ACCESS_KEY_ID=FLYOLOGYS3ORACLE \
--    AWS_SECRET_ACCESS_KEY=flyology-s3-oracle-secret-key-tests \
--      ./run.sh repro_s3_domain_a_minio_probe 300
--
--  A "_probe" name keeps this program out of run-all.sh: it needs a server.
--
--  It settles three things the in-process programs can only assert about
--  crafted documents:
--
--   (1) S3-DOMAIN-A-1: MinIO accepts PutObject with
--       "x-amz-storage-class: REDUCED_REDUNDANCY" on a versioning-enabled
--       bucket and echoes that class inside <Version> of a valid
--       ListVersionsResult; the crate's own high-level
--       Client.Objects.List_Versions_Page then cannot read the page at all.
--
--   (2) S3-DOMAIN-A-2: MinIO emits <NextMarker> on a truncated ListObjects
--       v1 page WITHOUT a delimiter (three keys, max-keys=1), and the
--       crate's own high-level Client.Objects.List_V1_Page then cannot read
--       the first page.  The same request with delimiter=/ succeeds, which
--       isolates the cause to Validate's delimiter condition.
--
--   (2b) S3-DOMAIN-A-7: a second versioned bucket holding only STANDARD
--       objects, so the marker rule at versions.adb:1031-1039 is exercised
--       on its own: MinIO's untruncated ?versions page carries an empty
--       <NextVersionIdMarker> with no <NextKeyMarker>, and the crate
--       rejects it whatever the storage classes are.
--
--   (3) S3-DOMAIN-A-4: what MinIO answers to GET ?inventory, ?metrics and
--       ?analytics, recorded so the report can say whether a pinned
--       third-party server could have caught the root-element mismatch.
--
--  The assertions are on (1) and (2).  (3) is recorded, not asserted:
--  MinIO does not implement those operations, so only AWS can settle the
--  root names, and repro_s3_domain_a_4.adb carries that case.

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.IO.Sockets;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Objects;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.SigV4;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_A_Minio_Probe is

   package US renames Ada.Strings.Unbounded;
   package Env renames Ada.Environment_Variables;
   package Sockets renames Flyology.IO.Sockets;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Client_Objects renames Flyology.Object_Storage.Client.Objects;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;

   use type Ada.Streams.Stream_Element_Offset;
   use type Client_Objects.List_Outcome_Kind;
   use type SigV4.Name_Value_Array;

   No_Query : constant SigV4.Name_Value_Array (1 .. 0) := [];
   No_Headers : constant SigV4.Name_Value_Array (1 .. 0) := [];

   NS : constant String := "http://s3.amazonaws.com/doc/2006-03-01/";

   Versions_Bucket : constant String := "flyology-review-domain-a-versions";
   Standard_Bucket : constant String := "flyology-review-domain-a-standard";
   V1_Bucket       : constant String := "flyology-review-domain-a-v1";

   function Port_Text return String is
   begin
      if not Env.Exists ("FLYOLOGY_REPRO_MINIO_PORT") then
         raise Program_Error with "FLYOLOGY_REPRO_MINIO_PORT is not set";
      end if;
      return Trim (Env.Value ("FLYOLOGY_REPRO_MINIO_PORT"));
   end Port_Text;

   function Access_Key return String is
     (Trim (Env.Value ("AWS_ACCESS_KEY_ID")));
   function Secret_Key return String is
     (Trim (Env.Value ("AWS_SECRET_ACCESS_KEY")));

   Endpoint_Port : constant Natural := Natural'Value (Port_Text);
   Host_Value : constant String := "127.0.0.1:" & Image (Endpoint_Port);
   Region : constant String := "us-east-1";

   function Timestamp return String is
      Text : constant String :=
        Ada.Calendar.Formatting.Image (Ada.Calendar.Clock, Time_Zone => 0);
   begin
      return Text (1 .. 4) & Text (6 .. 7) & Text (9 .. 10) & "T" &
        Text (12 .. 13) & Text (15 .. 16) & Text (18 .. 19) & "Z";
   end Timestamp;

   function Bytes (Value : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Value'Length));
   begin
      for Offset in 0 .. Value'Length - 1 loop
         Result (Result'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Value (Value'First + Offset)));
      end loop;
      return Result;
   end Bytes;

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   --  One complete SigV4-signed request, head and body, sent over a raw
   --  socket.  Only used for fixture setup and for the ?inventory /
   --  ?metrics / ?analytics probes; every assertion below goes through the
   --  crate's own typed client.
   function Exchange
     (Method    : String;
      Path      : String;
      Query     : SigV4.Name_Value_Array := No_Query;
      Body_Text : String := "";
      Extra     : SigV4.Name_Value_Array := No_Headers) return String
   is
      Stamp : constant String := Timestamp;
      Hash  : constant String := SigV4.SHA256_Hex (Body_Text);
      Headers : constant SigV4.Name_Value_Array :=
        SigV4.Name_Value_Array'
          [SigV4.Pair ("host", Host_Value),
           SigV4.Pair ("x-amz-content-sha256", Hash),
           SigV4.Pair ("x-amz-date", Stamp)] & Extra;
      Signature : constant SigV4.Signing_Result :=
        SigV4.Sign
          (Method, Path, Query, Headers, Hash,
           Access_Key, Secret_Key, Region, Stamp);
      Canonical : constant String := SigV4.Canonical_Query (Query);
      Target : constant String :=
        Path & (if Canonical'Length = 0 then "" else "?" & Canonical);

      function Extra_Lines return String is
         Text : US.Unbounded_String;
      begin
         for Item of Extra loop
            US.Append
              (Text,
               US.To_String (Item.Name) & ": " &
               US.To_String (Item.Value) & CRLF);
         end loop;
         return US.To_String (Text);
      end Extra_Lines;

      Head : constant String :=
        Method & " " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host_Value & CRLF &
        "x-amz-date: " & Stamp & CRLF &
        "x-amz-content-sha256: " & Hash & CRLF &
        Extra_Lines &
        "Authorization: " & US.To_String (Signature.Authorization) & CRLF &
        "Content-Length: " & Image (Body_Text'Length) & CRLF &
        "Connection: close" & CRLF & CRLF;

      Peer   : Sockets.Socket_Type;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 65_536);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : US.Unbounded_String;
   begin
      Sockets.Create_Socket (Peer);
      Sockets.Connect_Socket
        (Peer,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Port (Endpoint_Port)));
      Sockets.Send_All (Peer, Bytes (Head), Timeout => 60.0);
      if Body_Text'Length > 0 then
         Sockets.Send_All (Peer, Bytes (Body_Text), Timeout => 60.0);
      end if;
      begin
         loop
            Sockets.Receive (Peer, Buffer, Last, Timeout => 60.0);
            exit when Last < Buffer'First;
            for Index in Buffer'First .. Last loop
               US.Append (Result, Character'Val (Buffer (Index)));
            end loop;
         end loop;
      exception
         when Flyology.IO.Timeout_Error =>
            null;
      end;
      Sockets.Close_Socket (Peer);
      return US.To_String (Result);
   end Exchange;

   function Root_Element (Document : String) return String is
      From : Natural := 0;
   begin
      for Index in Document'Range loop
         if Document (Index) = '<'
           and then Index < Document'Last
           and then Document (Index + 1) not in '?' | '!' | '/'
         then
            From := Index + 1;
            exit;
         end if;
      end loop;
      if From = 0 then
         return "";
      end if;
      for Index in From .. Document'Last loop
         if Document (Index) in ' ' | '>' | '/' then
            return Document (From .. Index - 1);
         end if;
      end loop;
      return "";
   end Root_Element;

   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("http://" & Host_Value);
   HTTP : aliased HTTP_Client.Client (Capacity => 1);
   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials (Access_Key, Secret_Key);

   Versioning_Body : constant String :=
     "<VersioningConfiguration xmlns=""" & NS & """>" &
     "<Status>Enabled</Status></VersioningConfiguration>";

   Versioning_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("versioning", ""));
   Versions_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("versions", ""));

   procedure Setup is
   begin
      Note ("--- fixture setup over raw signed HTTP ---");
      Note ("CreateBucket " & Versions_Bucket & " -> " &
            Image (Status_Code (Exchange ("PUT", "/" & Versions_Bucket))));
      declare
         Response : constant String := Exchange
           ("PUT", "/" & Versions_Bucket, Versioning_Query, Versioning_Body,
            SigV4.Name_Value_Array'
              (1 => SigV4.Pair
                 ("content-md5", MD5_Base64 (Versioning_Body))));
      begin
         Note ("PutBucketVersioning Enabled -> " &
               Image (Status_Code (Response)));
      end;
      declare
         Response : constant String := Exchange
           ("PUT", "/" & Versions_Bucket & "/obj-reduced-redundancy",
            No_Query, "x",
            SigV4.Name_Value_Array'
              (1 => SigV4.Pair
                 ("x-amz-storage-class", "REDUCED_REDUNDANCY")));
      begin
         Note ("PutObject x-amz-storage-class: REDUCED_REDUNDANCY -> " &
               Image (Status_Code (Response)));
         Check (Status_Code (Response) = 200,
                "MinIO accepts REDUCED_REDUNDANCY on PutObject");
      end;
      declare
         Response : constant String := Exchange
           ("PUT", "/" & Versions_Bucket & "/obj-standard-ia",
            No_Query, "x",
            SigV4.Name_Value_Array'
              (1 => SigV4.Pair ("x-amz-storage-class", "STANDARD_IA")));
      begin
         Note ("PutObject x-amz-storage-class: STANDARD_IA -> " &
               Image (Status_Code (Response)) &
               " (recorded, not asserted)");
      end;
      Note ("PutObject obj-standard -> " &
            Image (Status_Code
                     (Exchange ("PUT",
                                "/" & Versions_Bucket & "/obj-standard",
                                No_Query, "x"))));

      Note ("CreateBucket " & Standard_Bucket & " -> " &
            Image (Status_Code (Exchange ("PUT", "/" & Standard_Bucket))));
      Note ("PutBucketVersioning Enabled -> " &
            Image (Status_Code
                     (Exchange
                        ("PUT", "/" & Standard_Bucket, Versioning_Query,
                         Versioning_Body,
                         SigV4.Name_Value_Array'
                           (1 => SigV4.Pair
                              ("content-md5",
                               MD5_Base64 (Versioning_Body)))))));
      Note ("PutObject only-standard (default class) -> " &
            Image (Status_Code
                     (Exchange ("PUT",
                                "/" & Standard_Bucket & "/only-standard",
                                No_Query, "x"))));

      Note ("CreateBucket " & V1_Bucket & " -> " &
            Image (Status_Code (Exchange ("PUT", "/" & V1_Bucket))));
      declare
         Keys : constant array (1 .. 3) of String (1 .. 2) :=
           ["k1", "k2", "k3"];
      begin
         for Key of Keys loop
            Note ("  PutObject " & Key & " -> " &
                  Image (Status_Code
                           (Exchange ("PUT", "/" & V1_Bucket & "/" & Key,
                                      No_Query, "y"))));
         end loop;
      end;
   end Setup;

   procedure Show_Raw_Versions is
      Response : constant String :=
        Exchange ("GET", "/" & Versions_Bucket, Versions_Query);
      Payload  : constant String := Body_Of (Response);
   begin
      Note ("--- what MinIO puts on the wire for GET ?versions ---");
      Note ("status " & Image (Status_Code (Response)) &
            ", root <" & Root_Element (Payload) & ">, " &
            Image (Payload'Length) & " bytes");
      Note (Payload);
      Check (Contains (Payload,
                       "<StorageClass>REDUCED_REDUNDANCY</StorageClass>"),
             "MinIO reports REDUCED_REDUNDANCY inside <Version>");
   end Show_Raw_Versions;

   procedure Probe_List_Versions (Bucket, Description : String) is
   begin
      declare
         Outcome : constant Client_Objects.List_Versions_Outcome :=
           Client_Objects.List_Versions_Page
             (HTTP, Origin, Bucket, Identity, Region);
      begin
         Note ("List_Versions_Page " & Bucket & ": kind " &
               Client_Objects.List_Outcome_Kind'Image (Outcome.Kind) &
               " status " & Image (Natural (Outcome.Status)));
         Check (Outcome.Kind = Client_Objects.Page_Available,
                "List_Versions_Page returns a page for " & Description);
         if Outcome.Kind = Client_Objects.Page_Available then
            Note ("  versions " &
                  Image (Natural (Outcome.Page.Versions.Length)));
         end if;
      end;
   exception
      when E : Low_Level.Invalid_Response =>
         Note ("List_Versions_Page " & Bucket &
               ": raised Invalid_Response: " &
               Ada.Exceptions.Exception_Message (E));
         Check (False,
                "List_Versions_Page returns a page for " & Description);
   end Probe_List_Versions;

   procedure Probe_List_V1 (Delimiter : String; Assert_OK : Boolean) is
      Label : constant String :=
        (if Delimiter = "" then "no delimiter" else "delimiter=" & Delimiter);
   begin
      declare
         Outcome : constant Client_Objects.List_V1_Outcome :=
           Client_Objects.List_V1_Page
             (HTTP, Origin, V1_Bucket, Identity, Region,
              Delimiter => Delimiter, Maximum => 1);
      begin
         Note ("List_V1_Page max-keys=1 " & Label & ": kind " &
               Client_Objects.List_Outcome_Kind'Image (Outcome.Kind) &
               " status " & Image (Natural (Outcome.Status)));
         if Assert_OK then
            Check (Outcome.Kind = Client_Objects.Page_Available,
                   "List_V1_Page returns the first page (" & Label & ")");
         end if;
         if Outcome.Kind = Client_Objects.Page_Available then
            Note ("  objects " &
                  Image (Natural (Outcome.Page.Contents.Length)) &
                  " truncated " &
                  Boolean'Image (Outcome.Page.Is_Truncated) &
                  " next_marker """ &
                  US.To_String (Outcome.Next_Marker) & """");
         end if;
      end;
   exception
      when E : Low_Level.Invalid_Response =>
         Note ("List_V1_Page max-keys=1 " & Label &
               ": raised Invalid_Response: " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_OK then
            Check (False,
                   "List_V1_Page returns the first page (" & Label & ")");
         end if;
   end Probe_List_V1;

   procedure Probe_Configuration_Listings is
      subtype Query_Name is String (1 .. 19);
      Names : constant array (1 .. 4) of Query_Name :=
        ["inventory          ", "metrics            ",
         "analytics          ", "intelligent-tiering"];
   begin
      Note ("--- S3-DOMAIN-A-4: does MinIO implement the configuration " &
            "listings at all? (recorded, not asserted) ---");
      for Name of Names loop
         declare
            Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair (Trim (Name), ""));
            Response : constant String :=
              Exchange ("GET", "/" & Versions_Bucket, Query);
            Payload : constant String := Body_Of (Response);
         begin
            Note ("GET /" & Versions_Bucket & "?" & Trim (Name) & " -> " &
                  Image (Status_Code (Response)) & ", root <" &
                  Root_Element (Payload) & ">");
         end;
      end loop;
   end Probe_Configuration_Listings;

begin
   Note ("MinIO endpoint http://" & Host_Value);
   Setup;
   Show_Raw_Versions;
   HTTP_Client.Configure (HTTP, Origin);
   Note ("--- Client.Objects.List_Versions_Page against MinIO ---");
   --  S3-DOMAIN-A-1: one REDUCED_REDUNDANCY version present.
   Probe_List_Versions
     (Versions_Bucket, "a MinIO bucket holding a REDUCED_REDUNDANCY version");
   --  S3-DOMAIN-A-7: only STANDARD versions, so only the next-marker rule
   --  can reject this one.
   Probe_List_Versions
     (Standard_Bucket, "a MinIO bucket holding only STANDARD versions");
   Note ("--- Client.Objects.List_V1_Page against MinIO ---");
   --  Control: with a delimiter the very same MinIO page is accepted.
   Probe_List_V1 ("/", True);
   --  The finding.
   Probe_List_V1 ("", True);
   Probe_Configuration_Listings;
   Finish;
end Repro_S3_Domain_A_Minio_Probe;
