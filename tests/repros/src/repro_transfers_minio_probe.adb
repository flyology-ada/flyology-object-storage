--  MinIO interop probe for the TRANSFERS discovery observations.  Needs a
--  running MinIO from the image pinned in tests/scripts/test-minio.sh:
--
--    docker run --detach --rm --name flyology-review-transfers-$$ \
--      --publish 127.0.0.1::9000 \
--      --env MINIO_ROOT_USER=FLYOLOGYS3ORACLE \
--      --env MINIO_ROOT_PASSWORD=flyology-s3-oracle-secret-key-tests \
--      quay.io/minio/minio@sha256:14cea493... server /data --address :9000
--
--    cd tests/repros
--    FLYOLOGY_REPRO_MINIO_PORT=<mapped port> \
--    AWS_ACCESS_KEY_ID=FLYOLOGYS3ORACLE \
--    AWS_SECRET_ACCESS_KEY=flyology-s3-oracle-secret-key-tests \
--      ./run.sh repro_transfers_minio_probe 300
--
--  It settles three interop questions the discovery report could not:
--   (1) does MinIO accept the CompleteMultipartUpload x-amz-checksum-* header
--       that Upload_Multipart_File sends WITHOUT the "-N" composite suffix
--       (transfers.adb:897-944), for a two-part COMPOSITE upload, and does it
--       echo the "-N" form back so the client's own verification at
--       transfers.adb:1146-1156 succeeds -- for CRC32 and for SHA256;
--   (2) does the client's strict ListParts rule
--       Is_Truncated = (Next_Part_Number_Marker > 0)
--       (s3-multipart.adb:1636-1637) accept every MinIO page of a real
--       two-part upload, including the last, untruncated one;
--   (3) what MinIO does with max-parts above 1000, which the typed client
--       cannot even express (List_Parts_Parameters.Max_Parts is
--       S3.Core.Page_Size, "Natural range 0 .. 1_000",
--       low_level.ads:7184 / s3-core.ads:28), probed with a raw signed
--       request instead.
--
--  A "_probe" name keeps this program out of run-all.sh: it needs a server.

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.IO.Sockets;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.SigV4;
with Repro_Support; use Repro_Support;

procedure Repro_Transfers_Minio_Probe is

   package US renames Ada.Strings.Unbounded;
   package Env renames Ada.Environment_Variables;
   package Sockets renames Flyology.IO.Sockets;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Policy renames Flyology.Object_Storage.S3.Checksum_Policy;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   use type Ada.Streams.Stream_Element_Offset;
   use type Transfers.Upload_Outcome_Kind;
   use type Transfers.Download_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type SigV4.Name_Value_Array;

   subtype Byte_Count is Flyology.Object_Storage.Byte_Count;

   MiB : constant Byte_Count := 1_024 * 1_024;

   Part_Size : constant Byte_Count := 5 * MiB;
   Tail_Size : constant Byte_Count := 1_024;
   Object_Size : constant Byte_Count := Part_Size + Tail_Size;

   Scratch : constant String := "/private/tmp/claude-501/repro-transfers-minio";
   Source_Path : constant String := Scratch & "/two-part.bin";

   Bucket : constant String := "flyology-review-transfers";

   No_Query : constant SigV4.Name_Value_Array (1 .. 0) := [];
   No_Headers : constant SigV4.Name_Value_Array (1 .. 0) := [];

   function Port_Text return String is
   begin
      if not Env.Exists ("FLYOLOGY_REPRO_MINIO_PORT") then
         raise Program_Error with
           "FLYOLOGY_REPRO_MINIO_PORT is not set";
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

   --  Build one complete SigV4-signed request head for MinIO.  Query pairs
   --  go on the wire exactly as SigV4 canonicalizes them, so signature and
   --  wire agree.
   function Signed_Head
     (Method       : String;
      Path         : String;
      Query        : SigV4.Name_Value_Array := No_Query;
      Payload_Hash : String := SigV4.Empty_Payload_Hash;
      Length       : Byte_Count := 0;
      Extra        : SigV4.Name_Value_Array := No_Headers;
      Content_Type : String := "") return String
   is
      Stamp : constant String := Timestamp;
      Headers : constant SigV4.Name_Value_Array :=
        SigV4.Name_Value_Array'
          [SigV4.Pair ("host", Host_Value),
           SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
           SigV4.Pair ("x-amz-date", Stamp)] & Extra;

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
      Signature : constant SigV4.Signing_Result :=
        SigV4.Sign
          (Method, Path, Query, Headers, Payload_Hash,
           Access_Key, Secret_Key, Region, Stamp);
      Canonical : constant String := SigV4.Canonical_Query (Query);
      Target : constant String :=
        Path & (if Canonical'Length = 0 then "" else "?" & Canonical);
   begin
      return
        Method & " " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host_Value & CRLF &
        "x-amz-date: " & Stamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        Extra_Lines &
        (if Content_Type = "" then ""
         else "Content-Type: " & Content_Type & CRLF) &
        "Authorization: " & US.To_String (Signature.Authorization) & CRLF &
        "Content-Length: " & Image_64 (Long_Long_Integer (Length)) & CRLF &
        "Connection: close" & CRLF & CRLF;
   end Signed_Head;

   --  One raw exchange with MinIO.  Body_Length bytes of Fill follow the head.
   function Exchange
     (Head        : String;
      Body_Length : Byte_Count := 0;
      Fill        : Character := 'z';
      Body_Text   : String := "") return String
   is
      Peer   : Sockets.Socket_Type;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 65_536);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : US.Unbounded_String;
      Chunk  : constant Ada.Streams.Stream_Element_Array (1 .. 65_536) :=
        [others => Ada.Streams.Stream_Element (Character'Pos (Fill))];
      Sent   : Byte_Count := 0;
   begin
      Sockets.Create_Socket (Peer);
      Sockets.Connect_Socket
        (Peer,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Port (Endpoint_Port)));
      Sockets.Send_All (Peer, Bytes (Head), Timeout => 60.0);
      if Body_Text'Length > 0 then
         Sockets.Send_All (Peer, Bytes (Body_Text), Timeout => 60.0);
      else
         while Sent < Body_Length loop
            declare
               Take : constant Byte_Count :=
                 Byte_Count'Min (Byte_Count (Chunk'Length), Body_Length - Sent);
            begin
               Sockets.Send_All
                 (Peer,
                  Chunk (1 .. Ada.Streams.Stream_Element_Offset (Take)),
                  Timeout => 60.0);
               Sent := Sent + Take;
            end;
         end loop;
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

   function Element (Document, Name : String) return String is
      Open  : constant String := "<" & Name & ">";
      Close : constant String := "</" & Name & ">";
      From  : constant Natural := Ada.Strings.Fixed.Index (Document, Open);
      Stop  : Natural;
   begin
      if From = 0 then
         return "";
      end if;
      Stop := Ada.Strings.Fixed.Index
        (Document (From + Open'Length .. Document'Last), Close);
      if Stop = 0 then
         return "";
      end if;
      return Document (From + Open'Length .. Stop - 1);
   end Element;

   procedure Write_Source is
      File  : Ada.Streams.Stream_IO.File_Type;
      Chunk : constant Ada.Streams.Stream_Element_Array (1 .. 65_536) :=
        [others => 7];
      Left  : Byte_Count := Object_Size;
   begin
      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Source_Path);
      while Left > 0 loop
         declare
            Take : constant Byte_Count :=
              Byte_Count'Min (Byte_Count (Chunk'Length), Left);
         begin
            Ada.Streams.Stream_IO.Write
              (File, Chunk (1 .. Ada.Streams.Stream_Element_Offset (Take)));
            Left := Left - Take;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
   end Write_Source;

   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("http://" & Host_Value);
   HTTP   : aliased HTTP_Client.Client (Capacity => 1);
   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials (Access_Key, Secret_Key);

   Upload_ID : US.Unbounded_String;

   ------------------------------------------------------------------
   --  (1) two-part COMPOSITE upload through the high-level client
   ------------------------------------------------------------------
   procedure Probe_Composite (Algorithm : Policy.Algorithm) is
      Name : constant String := Policy.Wire_Name (Algorithm);
      Key  : constant String :=
        "two-part-" & Ada.Characters.Handling.To_Lower (Name);
      Back : constant String := Scratch & "/back-" &
        Ada.Characters.Handling.To_Lower (Name) & ".bin";
      Selection : constant Transfers.Upload_Checksum_Selection :=
        (Enabled   => True,
         Algorithm => Algorithm,
         Kind      => Policy.Composite);
   begin
      Note ("--- COMPOSITE " & Name & ", " &
            Image_64 (Long_Long_Integer (Object_Size)) & " bytes, part size " &
            Image_64 (Long_Long_Integer (Part_Size)) & " (2 parts) ---");
      declare
         Result : constant Transfers.Upload_Outcome :=
           Transfers.Upload_File
             (HTTP, Origin, Bucket, Key, Source_Path, Identity, Region,
              Low_Level.Path_Style, "application/octet-stream",
              Timeout => 240.0,
              Multipart_Part_Size => Part_Size,
              Checksum => Selection);
      begin
         if Result.Kind = Transfers.File_Uploaded then
            Note (Name & " CompleteMultipartUpload: HTTP " &
                  Image (Result.Status) & ", no error code");
            Note (Name & " completion echoed checksum: """ &
                  US.To_String (Result.Checksum) & """");
            Note (Name & " completion echoed ChecksumType: """ &
                  US.To_String (Result.Checksum_Type) & """");
            Note (Name & " ETag: " & US.To_String (Result.Entity_Tag));
            Check (Result.Status = 200,
                   "MinIO accepts CompleteMultipartUpload with the "
                   & "unsuffixed x-amz-checksum-" & Name & " header ("
                   & Name & ")");
         else
            Note (Name & " CompleteMultipartUpload REJECTED: HTTP " &
                  Image (Result.Status) & ", code """ &
                  US.To_String (Result.Error.Code) & """, message """ &
                  US.To_String (Result.Error.Message) & """");
            Check (False,
                   "MinIO accepts the default two-part COMPOSITE upload ("
                   & Name & ")");
            return;
         end if;
      exception
         when Occurrence : Low_Level.Invalid_Response =>
            Note (Name & " Upload_File raised Invalid_Response: " &
                  Ada.Exceptions.Exception_Message (Occurrence));
            Check (False,
                   "MinIO's CompleteMultipartUpload answer satisfies the "
                   & "client's own checksum verification (" & Name & ")");
            return;
      end;
      declare
         Result : constant Transfers.Download_Outcome :=
           Transfers.Download_File
             (HTTP, Origin, Bucket, Key, Back, Identity, Region,
              Low_Level.Path_Style, Timeout => 240.0);
      begin
         Note (Name & " Download_File: HTTP " & Image (Result.Status) &
               ", bytes " &
               (if Result.Kind = Transfers.File_Downloaded
                then Image_64 (Long_Long_Integer (Result.Bytes))
                else "n/a"));
         Check (Result.Kind = Transfers.File_Downloaded
                and then Result.Status = 200
                and then Result.Bytes = Object_Size,
                "Download_File round-trips the composite object (" &
                Name & ")");
      end;
      if Ada.Directories.Exists (Back) then
         Check (Byte_Count (Ada.Directories.Size (Back)) = Object_Size,
                "downloaded file has the uploaded size (" & Name & ")");
         Ada.Directories.Delete_File (Back);
      end if;
   end Probe_Composite;


   ------------------------------------------------------------------
   --  (1b) does MinIO actually VALIDATE the completion checksum header,
   --  and does it accept the "-N" suffixed form as well as the bare one?
   ------------------------------------------------------------------
   procedure Probe_Completion_Header_Forms is
      Fill : constant Ada.Streams.Stream_Element := 7;

      function Part_Digest (Size : Byte_Count) return Checksums.Digest_Value is
         Context : Checksums.Context (Kind => Core.CRC32);
         Chunk   : constant Ada.Streams.Stream_Element_Array (1 .. 65_536) :=
           [others => Fill];
         Left    : Byte_Count := Size;
      begin
         Checksums.Reset (Context);
         while Left > 0 loop
            declare
               Take : constant Byte_Count :=
                 Byte_Count'Min (Byte_Count (Chunk'Length), Left);
            begin
               Checksums.Update
                 (Context,
                  Chunk (1 .. Ada.Streams.Stream_Element_Offset (Take)));
               Left := Left - Take;
            end;
         end loop;
         return Checksums.Finish (Context);
      end Part_Digest;

      First_Digest  : constant Checksums.Digest_Value := Part_Digest (Part_Size);
      Second_Digest : constant Checksums.Digest_Value := Part_Digest (Tail_Size);
      Object_Digest : constant Checksums.Digest_Value :=
        Checksums.Composite (Core.CRC32, [First_Digest, Second_Digest]);
      Bare     : constant String := Checksums.Encode_Base64 (Object_Digest);
      Suffixed : constant String :=
        Checksums.Encode_Object (Object_Digest, Policy.Composite, 2);

      --  Run one whole COMPOSITE multipart upload by hand and return the raw
      --  CompleteMultipartUpload response, using Completion_Checksum as the
      --  x-amz-checksum-crc32 request header value.
      function Run (Key, Completion_Checksum : String) return String is
         Tags : array (1 .. 2) of US.Unbounded_String;
         Digests : constant array (1 .. 2) of US.Unbounded_String :=
           [US.To_Unbounded_String (Checksums.Encode_Base64 (First_Digest)),
            US.To_Unbounded_String (Checksums.Encode_Base64 (Second_Digest))];
         Identifier : US.Unbounded_String;
         Initiate : constant String :=
           Exchange
             (Signed_Head
                ("POST", "/" & Bucket & "/" & Key,
                 [SigV4.Pair ("uploads", "")],
                 Extra =>
                   [SigV4.Pair ("x-amz-checksum-algorithm", "CRC32"),
                    SigV4.Pair ("x-amz-checksum-type", "COMPOSITE")]));
      begin
         Identifier := US.To_Unbounded_String
           (Element (Body_Of (Initiate), "UploadId"));
         if US.Length (Identifier) = 0 then
            return "initiate failed: " & Escape (Initiate);
         end if;
         for Number in 1 .. 2 loop
            declare
               Size : constant Byte_Count :=
                 (if Number = 1 then Part_Size else Tail_Size);
               Answer : constant String :=
                 Exchange
                   (Signed_Head
                      ("PUT", "/" & Bucket & "/" & Key,
                       [SigV4.Pair ("partNumber", Image (Number)),
                        SigV4.Pair ("uploadId", US.To_String (Identifier))],
                       Payload_Hash => SigV4.Unsigned_Payload,
                       Length => Size,
                       Extra =>
                         [SigV4.Pair ("x-amz-checksum-algorithm", "CRC32"),
                          SigV4.Pair
                            ("x-amz-checksum-crc32",
                             US.To_String (Digests (Number)))]),
                    Body_Length => Size, Fill => Character'Val (Fill));
            begin
               if Status_Code (Answer) /= 200 then
                  return "UploadPart " & Image (Number) & " failed: " &
                    Escape (Answer);
               end if;
               Tags (Number) :=
                 US.To_Unbounded_String (Header_Value (Answer, "ETag"));
            end;
         end loop;
         declare
            Document : constant String :=
              "<CompleteMultipartUpload>" &
              "<Part><PartNumber>1</PartNumber><ETag>" &
              US.To_String (Tags (1)) & "</ETag><ChecksumCRC32>" &
              US.To_String (Digests (1)) &
              "</ChecksumCRC32></Part>" &
              "<Part><PartNumber>2</PartNumber><ETag>" &
              US.To_String (Tags (2)) & "</ETag><ChecksumCRC32>" &
              US.To_String (Digests (2)) &
              "</ChecksumCRC32></Part>" &
              "</CompleteMultipartUpload>";
            Answer : constant String :=
              Exchange
                (Signed_Head
                   ("POST", "/" & Bucket & "/" & Key,
                    [SigV4.Pair ("uploadId", US.To_String (Identifier))],
                    Payload_Hash => SigV4.SHA256_Hex (Document),
                    Length => Byte_Count (Document'Length),
                    Extra =>
                      [SigV4.Pair
                         ("x-amz-checksum-crc32", Completion_Checksum),
                       SigV4.Pair ("x-amz-checksum-type", "COMPOSITE"),
                       SigV4.Pair
                         ("x-amz-mp-object-size",
                          Image_64 (Long_Long_Integer (Object_Size)))],
                    Content_Type => "application/xml"),
                 Body_Text => Document);
         begin
            return Answer;
         end;
      end Run;

      procedure Report (Label, Key, Value : String) is
         Answer : constant String := Run (Key, Value);
      begin
         Note (Label & " (x-amz-checksum-crc32: " & Value & "): HTTP " &
               Image (Status_Code (Answer)) &
               ", Code <" & Element (Body_Of (Answer), "Code") &
               ">, ChecksumCRC32 <" &
               Element (Body_Of (Answer), "ChecksumCRC32") &
               ">, ChecksumType <" &
               Element (Body_Of (Answer), "ChecksumType") & ">");
      end Report;
   begin
      Note ("--- does MinIO validate the CompleteMultipartUpload checksum "
            & "header? ---");
      Note ("client-computed composite digest: bare """ & Bare &
            """, suffixed """ & Suffixed & """");
      Report ("bare digest, the form Upload_File sends",
              "completion-bare", Bare);
      Report ("suffixed digest", "completion-suffixed", Suffixed);
      Report ("deliberately wrong bare digest", "completion-wrong",
              "AAAAAA==");
   end Probe_Completion_Header_Forms;

   ------------------------------------------------------------------
   --  (2)/(3) ListParts against a real two-part MinIO upload
   ------------------------------------------------------------------
   Parts_Key : constant String := "listparts-probe";

   procedure Build_Parts_Fixture is
      Initiate : constant String :=
        Exchange
          (Signed_Head
             ("POST", "/" & Bucket & "/" & Parts_Key,
              [SigV4.Pair ("uploads", "")]));
   begin
      Note ("CreateMultipartUpload (raw): HTTP " &
            Image (Status_Code (Initiate)));
      Upload_ID := US.To_Unbounded_String
        (Element (Body_Of (Initiate), "UploadId"));
      Check (US.Length (Upload_ID) > 0, "MinIO returned an upload id");
      if US.Length (Upload_ID) = 0 then
         Note ("initiate body: " & Escape (Body_Of (Initiate)));
         return;
      end if;
      for Number in 1 .. 2 loop
         declare
            Size : constant Byte_Count :=
              (if Number = 1 then Part_Size else Tail_Size);
            Answer : constant String :=
              Exchange
                (Signed_Head
                   ("PUT", "/" & Bucket & "/" & Parts_Key,
                    [SigV4.Pair ("partNumber", Image (Number)),
                     SigV4.Pair ("uploadId", US.To_String (Upload_ID))],
                    Payload_Hash => SigV4.Unsigned_Payload,
                    Length => Size),
                 Body_Length => Size);
         begin
            Note ("UploadPart " & Image (Number) & " (raw): HTTP " &
                  Image (Status_Code (Answer)) & ", ETag " &
                  Header_Value (Answer, "ETag"));
            Check (Status_Code (Answer) = 200,
                   "raw UploadPart " & Image (Number) & " succeeded");
         end;
      end loop;
   end Build_Parts_Fixture;

   procedure Report_Page
     (Label : String; Max : Core.Page_Size; Marker : Natural)
   is
      Parameters : Low_Level.List_Parts_Parameters;
   begin
      Parameters.Upload_ID := Upload_ID;
      Parameters.Max_Parts := Max;
      Parameters.Part_Number_Marker := Marker;
      declare
         Outcome : constant Low_Level.List_Parts_Outcome :=
           Transfers.List_Parts_Page
             (HTTP, Origin, Bucket, Parts_Key, Parameters, Identity, Region,
              Low_Level.Path_Style, Timeout => 60.0);
      begin
         if Outcome.Kind = Low_Level.Parts_Listed then
            Note (Label & ": HTTP " & Image (Outcome.Status) &
                  ", parts " &
                  Image (Natural (Outcome.Result.Listing.Parts.Length)) &
                  ", MaxParts " &
                  Image (Natural (Outcome.Result.Listing.Max_Parts)) &
                  ", PartNumberMarker " &
                  Image (Natural
                    (Outcome.Result.Listing.Part_Number_Marker)) &
                  ", NextPartNumberMarker " &
                  Image (Natural
                    (Outcome.Result.Listing.Next_Part_Number_Marker)) &
                  ", IsTruncated " &
                  Boolean'Image (Outcome.Result.Listing.Is_Truncated));
            Check (True, Label & " was accepted by the client");
         else
            Note (Label & " REJECTED: HTTP " & Image (Outcome.Status) &
                  ", code """ & US.To_String (Outcome.Error.Code) & """");
            Check (False, Label & " was accepted by the client");
         end if;
      end;
   exception
      when Occurrence : others =>
         Note (Label & " raised " &
               Ada.Exceptions.Exception_Name (Occurrence) & ": " &
               Ada.Exceptions.Exception_Message (Occurrence));
         Check (False, Label & " was accepted by the client");
   end Report_Page;

   procedure Probe_List_Parts is
   begin
      Note ("--- ListParts against a real MinIO two-part upload ---");
      Report_Page ("ListParts default page (max-parts 1000)", 1_000, 0);
      Report_Page ("ListParts page walk, page 1 (max-parts 1)", 1, 0);
      Report_Page ("ListParts page walk, page 2 (max-parts 1, marker 1)",
                   1, 1);
      Report_Page ("ListParts page walk, page 3 (max-parts 1, marker 2)",
                   1, 2);
      Note ("List_Parts_Parameters.Max_Parts is S3.Core.Page_Size = "
            & "Natural range 0 .. " & Image (Natural (Core.Page_Size'Last)) &
            ", so the typed client cannot send max-parts above 1000; "
            & "probing MinIO with a raw signed request instead");
      declare
         Answer : constant String :=
           Exchange
             (Signed_Head
                ("GET", "/" & Bucket & "/" & Parts_Key,
                 [SigV4.Pair ("max-parts", "2000"),
                  SigV4.Pair ("uploadId", US.To_String (Upload_ID))]));
      begin
         Note ("raw ListParts max-parts=2000: HTTP " &
               Image (Status_Code (Answer)) &
               ", MaxParts echo <" & Element (Body_Of (Answer), "MaxParts") &
               ">, IsTruncated <" &
               Element (Body_Of (Answer), "IsTruncated") &
               ">, NextPartNumberMarker <" &
               Element (Body_Of (Answer), "NextPartNumberMarker") &
               ">, Code <" & Element (Body_Of (Answer), "Code") & ">");
      end;
      declare
         Answer : constant String :=
           Exchange
             (Signed_Head
                ("DELETE", "/" & Bucket & "/" & Parts_Key,
                 [SigV4.Pair ("uploadId", US.To_String (Upload_ID))]));
      begin
         Note ("AbortMultipartUpload (raw): HTTP " &
               Image (Status_Code (Answer)));
      end;
   end Probe_List_Parts;

begin
   if not Env.Exists ("AWS_ACCESS_KEY_ID")
     or else not Env.Exists ("AWS_SECRET_ACCESS_KEY")
   then
      Note ("AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are not set");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;
   Note ("MinIO endpoint http://" & Host_Value);
   Ada.Directories.Create_Path (Scratch);
   Write_Source;
   Note ("source file " & Source_Path & " is " &
         Image_64 (Long_Long_Integer (Object_Size)) & " bytes");

   declare
      Created : constant String := Exchange (Signed_Head ("PUT", "/" & Bucket));
   begin
      Note ("CreateBucket: HTTP " & Image (Status_Code (Created)) &
            " (200 = created, 409 = already there)");
      Check (Status_Code (Created) = 200 or else Status_Code (Created) = 409,
             "test bucket exists on MinIO");
   end;

   HTTP_Client.Configure (HTTP, Origin);

   Probe_Composite (Core.CRC32);
   Probe_Composite (Core.SHA256);
   Probe_Completion_Header_Forms;
   Build_Parts_Fixture;
   if US.Length (Upload_ID) > 0 then
      Probe_List_Parts;
   end if;

   if Ada.Directories.Exists (Source_Path) then
      Ada.Directories.Delete_File (Source_Path);
   end if;
   Finish;
end Repro_Transfers_Minio_Probe;
