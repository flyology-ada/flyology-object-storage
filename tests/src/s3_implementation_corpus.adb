with Ada.Command_Line;
with Ada.Containers;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Objects;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.Tags;

procedure S3_Implementation_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Client_Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Client_Objects renames Flyology.Object_Storage.Client.Objects;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package S3_Core renames Flyology.Object_Storage.S3.Core;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Tags renames Flyology.Object_Storage.Tags;
   package Stream_IO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Ada.Containers.Count_Type;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Delete_Objects_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.Get_Object_Attributes_Outcome_Kind;
   use type Low_Level.Head_Object_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Upload_Part_Copy_Outcome_Kind;
   use type Transfers.Download_Outcome_Kind;
   use type Transfers.Copy_Outcome_Kind;
   use type Transfers.Head_Outcome_Kind;
   use type Transfers.Upload_Outcome_Kind;
   use type Client_Buckets.Head_Outcome_Kind;
   use type Client_Buckets.Create_Outcome_Kind;
   use type Client_Buckets.Delete_Outcome_Kind;
   use type Client_Buckets.Location_Outcome_Kind;
   use type Client_Buckets.List_Outcome_Kind;
   use type Client_Buckets.Put_Tags_Outcome_Kind;
   use type Client_Buckets.Get_Tags_Outcome_Kind;
   use type Tags.Tag_Vectors.Vector;
   use type Client_Objects.Delete_Outcome_Kind;
   use type Client_Objects.Tagging_Outcome_Kind;
   use type Flyology.Object_Storage.Object_Tag_Set;

   Access_Key : constant String := "FLYOLOGYS3ORACLE";
   Secret_Key : constant String := "flyology-s3-oracle-secret-key-tests";
   Payload    : aliased constant String :=
     String'(1 .. 6 * 1_024 * 1_024 => 'm');

   function Check_List_Multipart_Uploads return Boolean is
      Name : constant String :=
        "FLYOLOGY_LIST_MULTIPART_UPLOADS_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "seaweedfs-4.43-invalid-pagination"
      then
         return False;
      else
         raise Program_Error with
           "unknown ListMultipartUploads oracle mode";
      end if;
   end Check_List_Multipart_Uploads;

   function Check_Missing_Object_Attributes return Boolean is
      Name : constant String :=
        "FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-missing-error-message"
      then
         return False;
      elsif Ada.Environment_Variables.Value (Name) =
        "minio-2025-lowercase-root"
      then
         return False;
      else
         raise Program_Error with
           "unknown GetObjectAttributes oracle mode";
      end if;
   end Check_Missing_Object_Attributes;

   function Check_Get_Object_Attributes return Boolean is
      Name : constant String :=
        "FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name)
        or else Ada.Environment_Variables.Value (Name) =
          "rustfs-rc3-missing-error-message"
      then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "minio-2025-lowercase-root"
      then
         return False;
      else
         raise Program_Error with
           "unknown GetObjectAttributes oracle mode";
      end if;
   end Check_Get_Object_Attributes;

   type Upload_Source
     (Value : not null access constant String) is
     new HTTP_Client.Request_Body_Source with record
      Position : Natural := 0;
      Chunk    : Positive := 997;
   end record;

   overriding function Declared_Length
     (Item : Upload_Source) return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Item.Value'Length)));

   overriding procedure Read
     (Item     : in out Upload_Source;
      Data     : out Stream_Element_Array;
      Last     : out Stream_Element_Offset;
      Finished : out Boolean;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
      Remaining : constant Natural := Item.Value'Length - Item.Position;
      Count : constant Natural := Natural'Min
        (Remaining, Natural'Min (Natural (Data'Length), Item.Chunk));
   begin
      Data := (others => 0);
      if Count = 0 then
         Last := Data'First - 1;
      else
         for Offset in 0 .. Count - 1 loop
            Data (Data'First + Stream_Element_Offset (Offset)) :=
              Stream_Element
                (Character'Pos
                   (Item.Value
                      (Item.Value'First + Item.Position + Offset)));
         end loop;
         Last := Data'First + Stream_Element_Offset (Count - 1);
         Item.Position := Item.Position + Count;
      end if;
      Finished := Item.Position = Item.Value'Length;
   end Read;

   procedure Run
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Key       : String;
      Timestamp : String)
   is
      HTTP     : aliased HTTP_Client.Client (Capacity => 1);
      Identity : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);

      procedure Check_Bucket_Tags is
         Value : Tags.Tag_Set;
      begin
         Value.Append
           (Tags.Tag'
              (Key   => US.To_Unbounded_String ("corpus"),
               Value => US.To_Unbounded_String ("flyology")));
         declare
            Put_Result : constant Client_Buckets.Put_Tags_Outcome :=
              Client_Buckets.Put_Tags
                (HTTP, Origin, Bucket, Value, Identity, Timeout => 30.0);
            Get_Result : constant Client_Buckets.Get_Tags_Outcome :=
              Client_Buckets.Get_Tags
                (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
         begin
            if Put_Result.Kind /= Client_Buckets.Tags_Replaced
              or else Get_Result.Kind /= Client_Buckets.Tags_Found
              or else Get_Result.Value /= Value
            then
               raise Program_Error with
                 "S3 implementation rejected bucket tagging round trip";
            end if;
         end;
      end Check_Bucket_Tags;

      procedure Upload_High_Level_File is
         Local_Path : constant String :=
           "/tmp/flyology-object-storage-" & Key & ".bin";
         Download_Path : constant String := Local_Path & ".download";
         File : Stream_IO.File_Type;
         Buffer : constant Stream_Element_Array (1 .. 64 * 1_024) :=
           (others => Stream_Element (Character'Pos ('m')));
         Remaining : Natural := Payload'Length;

         procedure Require_Downloaded_Payload is
            Input : Stream_IO.File_Type;
            Data  : Stream_Element_Array (1 .. 64 * 1_024);
            Last  : Stream_Element_Offset;
            Total : Flyology.Object_Storage.Byte_Count := 0;
         begin
            Stream_IO.Open (Input, Stream_IO.In_File, Download_Path);
            loop
               Stream_IO.Read (Input, Data, Last);
               exit when Last < Data'First;
               for Index in Data'First .. Last loop
                  if Data (Index) /= Stream_Element (Character'Pos ('m')) then
                     raise Program_Error with
                       "high-level download changed object bytes";
                  end if;
               end loop;
               Total := Total
                 + Flyology.Object_Storage.Byte_Count
                     (Last - Data'First + 1);
            end loop;
            Stream_IO.Close (Input);
            if Total /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
            then
               raise Program_Error with
                 "high-level download returned the wrong byte count";
            end if;
         exception
            when others =>
               if Stream_IO.Is_Open (Input) then
                  Stream_IO.Close (Input);
               end if;
               raise;
         end Require_Downloaded_Payload;
      begin
         Stream_IO.Create (File, Stream_IO.Out_File, Local_Path);
         while Remaining > 0 loop
            declare
               Count : constant Natural :=
                 Natural'Min (Remaining, Natural (Buffer'Length));
            begin
               Stream_IO.Write
                 (File,
                  Buffer
                    (Buffer'First ..
                       Buffer'First + Stream_Element_Offset (Count - 1)));
               Remaining := Remaining - Count;
            end;
         end loop;
         Stream_IO.Close (File);
         declare
            Result : constant Transfers.Upload_Outcome :=
              Transfers.Upload_File
                (HTTP, Origin, Bucket, Key & "-high level+%25", Local_Path,
                 Identity, Content_Type => "application/octet-stream",
                 Timeout => 60.0,
                 Multipart_Threshold => 5 * 1_024 * 1_024,
                 Multipart_Part_Size => 5 * 1_024 * 1_024);
         begin
            if Result.Kind = Transfers.Upload_Rejected then
               raise Program_Error with
                 "S3 implementation rejected high-level file upload: "
                 & Result.Status'Image & " "
                 & US.To_String (Result.Error.Code) & " "
                 & US.To_String (Result.Error.Message);
            elsif Result.Bytes /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Result.Entity_Tag) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid high-level upload "
                 & "metadata: bytes="
                 & Flyology.Object_Storage.Byte_Count'Image (Result.Bytes)
                 & " etag=" & US.To_String (Result.Entity_Tag);
            end if;
         end;
         declare
            Result : constant Transfers.Download_Outcome :=
              Transfers.Download_File
                (HTTP, Origin, Bucket, Key & "-high level+%25",
                 Download_Path, Identity, Timeout => 60.0);
         begin
            if Result.Kind = Transfers.Download_Rejected then
               raise Program_Error with
                 "S3 implementation rejected high-level file download: "
                 & Result.Status'Image & " "
                 & US.To_String (Result.Error.Code) & " "
                 & US.To_String (Result.Error.Message);
            elsif Result.Bytes /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Result.Entity_Tag) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid high-level download "
                 & "metadata: bytes="
                 & Flyology.Object_Storage.Byte_Count'Image (Result.Bytes)
                 & " etag=" & US.To_String (Result.Entity_Tag);
            end if;
         end;
         Require_Downloaded_Payload;
         Ada.Directories.Delete_File (Local_Path);
         Ada.Directories.Delete_File (Download_Path);
      exception
         when others =>
            if Stream_IO.Is_Open (File) then
               Stream_IO.Close (File);
            end if;
            if Ada.Directories.Exists (Local_Path) then
               Ada.Directories.Delete_File (Local_Path);
            end if;
            if Ada.Directories.Exists (Download_Path) then
               Ada.Directories.Delete_File (Download_Path);
            end if;
            raise;
      end Upload_High_Level_File;

      procedure Require_Listed_Object is
         Parameters : Low_Level.List_Objects_V2_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Key);
         declare
            V1_Parameters : Low_Level.List_Objects_Parameters;
         begin
            V1_Parameters.Prefix := US.To_Unbounded_String (Key);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects
                   (Origin, Low_Level.Path_Style, Bucket, V1_Parameters,
                    Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.List_Objects_Outcome :=
                 Low_Level.Execute_List_Objects
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Listed
                 or else Outcome.Result.Listing.Contents.Length /= 1
                 or else US.To_String
                   (Outcome.Result.Listing.Contents.First_Element.Key) /= Key
                 or else
                   Outcome.Result.Listing.Contents.First_Element.Size /=
                     Flyology.Object_Storage.Byte_Count (Payload'Length)
               then
                  raise Program_Error with
                    "S3 implementation failed typed ListObjects v1";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Objects_V2
                (Origin, Low_Level.Path_Style, Bucket, Parameters,
                 Identity, "us-east-1", Timestamp);
            Outcome : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Listed
              or else Outcome.Listing.Contents.Length /= 1
              or else US.To_String
                (Outcome.Listing.Contents.First_Element.Key) /= Key
              or else Outcome.Listing.Contents.First_Element.Size /=
                Flyology.Object_Storage.Byte_Count (Payload'Length)
            then
               raise Program_Error with
                 "S3 implementation did not expose the completed object";
            end if;
         end;
      end Require_Listed_Object;

      procedure Require_Head_Object is
         Baseline : Low_Level.Head_Object_Result;
      begin
         declare
            Parameters : Low_Level.Head_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Object
                (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                 Identity, "us-east-1", Timestamp);
            Outcome : constant Low_Level.Head_Object_Outcome :=
              Low_Level.Execute_Head_Object
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Object_Found
              or else Outcome.Result.Content_Length /=
                Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Outcome.Result.Entity_Tag) = 0
              or else US.Length (Outcome.Result.Last_Modified) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid typed HeadObject " &
                 "metadata";
            end if;
            Baseline := Outcome.Result;
         end;
         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.If_Match := Baseline.Entity_Tag;
            Parameters.Byte_Range_Header :=
              US.To_Unbounded_String ("bytes=0-15");
            Parameters.Response_Cache_Control :=
              US.To_Unbounded_String ("no-store");
            Parameters.Response_Content_Disposition :=
              US.To_Unbounded_String ("attachment");
            Parameters.Response_Content_Encoding :=
              US.To_Unbounded_String ("identity");
            Parameters.Response_Content_Language :=
              US.To_Unbounded_String ("en-CA");
            Parameters.Response_Content_Type :=
              US.To_Unbounded_String ("application/octet-stream");
            Parameters.Response_Expires := US.To_Unbounded_String
              ("Fri, 01 Jan 2099 00:00:00 GMT");
            Parameters.Version_ID := US.To_Unbounded_String ("null");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Part_Number := (Is_Set => True, Value => 1);
            Parameters.Checksum_Mode := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                    Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Object_Found
                 or else Outcome.Status /= 206
                 or else Outcome.Result.Content_Length /= 16
                 or else US.To_String (Outcome.Result.Content_Range) /=
                   "bytes 0-15/5242880"
                 or else not Outcome.Result.Parts_Count.Is_Set
                 or else Outcome.Result.Parts_Count.Value /= 2
                 or else US.To_String (Outcome.Result.Cache_Control) /=
                   "no-store"
                 or else US.To_String
                   (Outcome.Result.Content_Disposition) /= "attachment"
                 or else US.To_String (Outcome.Result.Content_Encoding) /=
                   "identity"
                 or else US.To_String (Outcome.Result.Content_Language) /=
                   "en-CA"
                 or else US.To_String (Outcome.Result.Content_Type) /=
                   "application/octet-stream"
                 or else US.To_String (Outcome.Result.Expires) /=
                   "Fri, 01 Jan 2099 00:00:00 GMT"
               then
                  raise Program_Error with
                    "S3 implementation HeadObject full request/result " &
                    "surface mismatch";
               end if;
            end;
         end;
         declare
            Outcome : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Object_Found
              or else Outcome.Bytes /=
                Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Outcome.Entity_Tag) = 0
              or else US.Length (Outcome.Last_Modified) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid HeadObject metadata";
            end if;
         end;
         declare
            Outcome : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key, Identity,
                 Version_ID => "null",
                 If_Match => US.To_String (Baseline.Entity_Tag),
                 Checksum_Mode => True,
                 Byte_Range_Header => "bytes=0-15",
                 Request_Payer => "requester",
                 Part_Number => (Is_Set => True, Value => 2),
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Object_Found
              or else Outcome.Status /= 206
              or else Outcome.Bytes /= 16
              or else US.To_String (Outcome.Details.Content_Range) /=
                "bytes 0-15/1048576"
              or else not Outcome.Details.Parts_Count.Is_Set
              or else Outcome.Details.Parts_Count.Value /= 2
            then
               raise Program_Error with
                 "S3 implementation convenience HeadObject part two " &
                 "mismatch";
            end if;
         end;
         declare
            Outcome : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key, Identity,
                 If_None_Match => US.To_String (Baseline.Entity_Tag),
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Head_Rejected
              or else Outcome.Status /= 304
            then
               raise Program_Error with
                 "S3 implementation HeadObject If-None-Match mismatch";
            end if;
         end;
         declare
            Outcome : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key, Identity,
                 If_Unmodified_Since =>
                   "Thu, 01 Jan 1970 00:00:00 GMT",
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Head_Rejected
              or else Outcome.Status /= 412
            then
               raise Program_Error with
                 "S3 implementation HeadObject If-Unmodified-Since " &
                 "mismatch";
            end if;
         end;
         declare
            Outcome : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key, Identity,
                 Part_Number => (Is_Set => True, Value => 3),
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Head_Rejected
              or else Outcome.Status /= 416
            then
               raise Program_Error with
                 "S3 implementation HeadObject absent part mismatch";
            end if;
         end;
         declare
            Outcome : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key & "-missing", Identity,
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Head_Rejected
              or else Outcome.Status /= 404
            then
               raise Program_Error with
                 "S3 implementation HeadObject missing-key mismatch";
            end if;
         end;
      end Require_Head_Object;

      procedure Require_Get_Object is
         Download_Path : constant String :=
           "/tmp/flyology-object-storage-get-" & Key & ".bin";
         Head : constant Transfers.Head_Outcome :=
           Transfers.Head_Object
             (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);

         procedure Write_Marker is
            Output : Stream_IO.File_Type;
            Marker : constant Stream_Element_Array :=
              (1 => Stream_Element (Character'Pos ('p')),
               2 => Stream_Element (Character'Pos ('p')),
               3 => Stream_Element (Character'Pos ('p')));
         begin
            Stream_IO.Create (Output, Stream_IO.Out_File, Download_Path);
            Stream_IO.Write (Output, Marker);
            Stream_IO.Close (Output);
         exception
            when others =>
               if Stream_IO.Is_Open (Output) then
                  Stream_IO.Close (Output);
               end if;
               raise;
         end Write_Marker;

         procedure Require_File
           (Expected_Length : Natural; Expected : Character)
         is
            Input : Stream_IO.File_Type;
            Data  : Stream_Element_Array (1 .. 257);
            Last  : Stream_Element_Offset;
            Total : Natural := 0;
         begin
            Stream_IO.Open (Input, Stream_IO.In_File, Download_Path);
            loop
               Stream_IO.Read (Input, Data, Last);
               exit when Last < Data'First;
               for Index in Data'First .. Last loop
                  if Character'Val (Data (Index)) /= Expected then
                     raise Program_Error with
                       "GetObject oracle changed selected bytes";
                  end if;
               end loop;
               Total := Total + Natural (Last - Data'First + 1);
            end loop;
            Stream_IO.Close (Input);
            if Total /= Expected_Length then
               raise Program_Error with
                 "GetObject oracle returned wrong interval length";
            end if;
         exception
            when others =>
               if Stream_IO.Is_Open (Input) then
                  Stream_IO.Close (Input);
               end if;
               raise;
         end Require_File;
      begin
         if Head.Kind /= Transfers.Object_Found
           or else US.Length (Head.Entity_Tag) = 0
         then
            raise Program_Error with
              "GetObject oracle setup did not return an entity tag";
         end if;
         declare
            Result : constant Transfers.Download_Outcome :=
              Transfers.Download_File
                (HTTP, Origin, Bucket, Key, Download_Path, Identity,
                 Timeout => 30.0,
                 If_Match => US.To_String (Head.Entity_Tag),
                 If_Unmodified_Since =>
                   "Thu, 01 Jan 1970 00:00:00 GMT",
                 Byte_Range_Header => "bytes=1048573-1049600");
         begin
            if Result.Kind /= Transfers.File_Downloaded
              or else Result.Status /= 206
              or else Result.Bytes /= 1_028
            then
               raise Program_Error with
                 "GetObject oracle rejected a valid conditional range";
            end if;
         end;
         Require_File (1_028, 'm');

         Write_Marker;
         declare
            Result : constant Transfers.Download_Outcome :=
              Transfers.Download_File
                (HTTP, Origin, Bucket, Key, Download_Path, Identity,
                 Timeout => 30.0,
                 If_None_Match => US.To_String (Head.Entity_Tag));
         begin
            if Result.Kind /= Transfers.Download_Rejected
              or else Result.Status /= 304
            then
               raise Program_Error with
                 "GetObject oracle conditional not-modified mismatch";
            end if;
         end;
         Require_File (3, 'p');

         Write_Marker;
         declare
            Result : constant Transfers.Download_Outcome :=
              Transfers.Download_File
                (HTTP, Origin, Bucket, Key, Download_Path, Identity,
                 Timeout => 30.0, If_Match => """not-the-etag""");
         begin
            if Result.Kind /= Transfers.Download_Rejected
              or else Result.Status /= 412
            then
               raise Program_Error with
                 "GetObject oracle precondition failure mismatch";
            end if;
         end;
         Require_File (3, 'p');
         Ada.Directories.Delete_File (Download_Path);
      exception
         when others =>
            if Ada.Directories.Exists (Download_Path) then
               Ada.Directories.Delete_File (Download_Path);
            end if;
            raise;
      end Require_Get_Object;

      procedure Require_Object_Tagging is
         Wanted : Flyology.Object_Storage.Object_Tag_Set :=
           Flyology.Object_Storage.Empty_Object_Tags;
      begin
         Wanted.Length := 2;
         Wanted.Items (1) :=
           (Key => US.To_Unbounded_String ("environment"),
            Value => US.To_Unbounded_String ("production"));
         Wanted.Items (2) :=
           (Key => US.To_Unbounded_String ("team"),
            Value => US.To_Unbounded_String ("storage/core"));
         declare
            Outcome : constant Client_Objects.Tagging_Outcome :=
              Client_Objects.Put_Tags
                (HTTP, Origin, Bucket, Key, Wanted, Identity,
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Client_Objects.Tags_Replaced then
               raise Program_Error with
                 "S3 implementation rejected PutObjectTagging";
            end if;
         end;
         declare
            Outcome : constant Client_Objects.Tagging_Outcome :=
              Client_Objects.Get_Tags
                (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
         begin
            if Outcome.Kind /= Client_Objects.Tags_Read
              or else Outcome.Result.Tags /= Wanted
            then
               raise Program_Error with
                 "S3 implementation changed GetObjectTagging values/order";
            end if;
         end;
         declare
            Outcome : constant Client_Objects.Tagging_Outcome :=
              Client_Objects.Delete_Tags
                (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
         begin
            if Outcome.Kind /= Client_Objects.Tags_Cleared then
               raise Program_Error with
                 "S3 implementation rejected DeleteObjectTagging";
            end if;
         end;
         declare
            Outcome : constant Client_Objects.Tagging_Outcome :=
              Client_Objects.Get_Tags
                (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
         begin
            if Outcome.Kind /= Client_Objects.Tags_Read
              or else Outcome.Result.Tags.Length /= 0
            then
               raise Program_Error with
                 "S3 implementation retained deleted object tags";
            end if;
         end;
      end Require_Object_Tagging;

      procedure Require_Get_Object_Attributes is
         Parameters : Low_Level.Get_Object_Attributes_Parameters;
      begin
         Parameters.Has_Max_Parts := True;
         Parameters.Max_Parts := 1;
         Parameters.Has_Part_Number_Marker := True;
         Parameters.Part_Number_Marker := 0;
         Parameters.Attributes :=
           (Entity_Tag => True, Checksum => True, Object_Parts => True,
            Storage_Class => True, Object_Size => True);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Attributes
                (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                 Identity, "us-east-1", Timestamp);
            Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
              Low_Level.Execute_Get_Object_Attributes
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Object_Attributes_Found then
               raise Program_Error with
                 "S3 implementation rejected GetObjectAttributes: " &
                 Outcome.Status'Image & " " &
                 US.To_String (Outcome.Error.Code) & " " &
                 US.To_String (Outcome.Error.Message);
            elsif not Outcome.Result.Attributes.Has_Entity_Tag
              or else US.Length (Outcome.Result.Attributes.Entity_Tag) = 0
              or else not Outcome.Result.Attributes.Object_Size.Is_Set
              or else Outcome.Result.Attributes.Object_Size.Value /=
                Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Outcome.Result.Last_Modified) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid object attributes";
            elsif Outcome.Result.Attributes.Has_Object_Parts
              and then
                ((Outcome.Result.Attributes.Object_Parts.
                    Total_Parts_Count.Is_Set
                  and then Outcome.Result.Attributes.Object_Parts.
                    Total_Parts_Count.Value /= 1)
                 or else Outcome.Result.Attributes.Object_Parts.Parts.Length >
                   1
                 or else
                   (not Outcome.Result.Attributes.Object_Parts.Parts.Is_Empty
                    and then
                      (Outcome.Result.Attributes.Object_Parts.Parts.
                         First_Element.Number.Value /= 1
                       or else Outcome.Result.Attributes.Object_Parts.Parts.
                         First_Element.Size.Value /=
                           Flyology.Object_Storage.Byte_Count
                             (Payload'Length))))
            then
               raise Program_Error with
                 "S3 implementation returned invalid completed-part " &
                 "attributes";
            end if;
         end;

         declare
            Selection : constant
              Flyology.Object_Storage.S3.Attributes.Attribute_Selection :=
                (Entity_Tag => True, Object_Size => True, others => False);
            Outcome : constant Client_Objects.Get_Attributes_Outcome :=
              Client_Objects.Get_Attributes
                (HTTP, Origin, Bucket, Key, Identity,
                 Attributes => Selection, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Object_Attributes_Found
              or else not Outcome.Result.Attributes.Has_Entity_Tag
              or else not Outcome.Result.Attributes.Object_Size.Is_Set
              or else Outcome.Result.Attributes.Object_Size.Value /=
                Flyology.Object_Storage.Byte_Count (Payload'Length)
            then
               raise Program_Error with
                 "high-level GetObjectAttributes result mismatch";
            end if;
         end;

         if Check_Missing_Object_Attributes then
            Parameters := (others => <>);
            Parameters.Attributes.Object_Size := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Attributes
                   (Origin, Low_Level.Path_Style, Bucket, Key & "-missing",
                    Parameters, Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
                 Low_Level.Execute_Get_Object_Attributes
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Get_Object_Attributes_Rejected
                 or else Outcome.Status /= 404
               then
                  raise Program_Error with
                    "S3 implementation GetObjectAttributes missing-key " &
                    "mismatch";
               end if;
            end;
         end if;
      end Require_Get_Object_Attributes;

      procedure Require_Listed_Part
        (Object_Key, Upload_ID, Entity_Tag : String;
         Size : Flyology.Object_Storage.Byte_Count)
      is
         Parameters : Low_Level.List_Parts_Parameters;

         function Bare_ETag (Value : String) return String is
           (if Value'Length >= 2
              and then Value (Value'First) = '"'
              and then Value (Value'Last) = '"'
            then Value (Value'First + 1 .. Value'Last - 1)
            else Value);
      begin
         Parameters.Max_Parts := 1;
         Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Parts
                (Origin, Low_Level.Path_Style, Bucket, Object_Key,
                 Parameters, Identity, "us-east-1", Timestamp);
            Outcome : constant Low_Level.List_Parts_Outcome :=
              Low_Level.Execute_List_Parts
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Parts_Listed then
               raise Program_Error with
                 "S3 implementation rejected typed ListParts: " &
                 Outcome.Status'Image & " " &
                 US.To_String (Outcome.Error.Code) & " " &
                 US.To_String (Outcome.Error.Message);
            elsif Outcome.Result.Listing.Parts.Length /= 1 then
               raise Program_Error with
                 "S3 implementation ListParts count mismatch:" &
                 Outcome.Result.Listing.Parts.Length'Image;
            elsif Outcome.Result.Listing.Parts.First_Element.Number /= 1
              or else Outcome.Result.Listing.Parts.First_Element.Size /= Size
              or else Bare_ETag
                (US.To_String
                   (Outcome.Result.Listing.Parts.First_Element.Entity_Tag)) /=
                  Bare_ETag (Entity_Tag)
              or else Outcome.Result.Listing.Is_Truncated
            then
               raise Program_Error with
                 "S3 implementation ListParts value mismatch: number=" &
                 Outcome.Result.Listing.Parts.First_Element.Number'Image &
                 " size=" &
                 Outcome.Result.Listing.Parts.First_Element.Size'Image &
                 " etag=" & US.To_String
                   (Outcome.Result.Listing.Parts.First_Element.Entity_Tag) &
                 " expected_etag=" & Entity_Tag & " truncated=" &
                 Outcome.Result.Listing.Is_Truncated'Image;
            end if;
         end;
      end Require_Listed_Part;

      procedure Require_Listed_Upload
        (Object_Key, Upload_ID : String; Present : Boolean)
      is
         Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Object_Key);
         Parameters.Max_Uploads := 1;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Multipart_Uploads
                (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
                 "us-east-1", Timestamp);
            Outcome : constant Low_Level.List_Multipart_Uploads_Outcome :=
              Low_Level.Execute_List_Multipart_Uploads
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Multipart_Uploads_Listed then
               raise Program_Error with
                 "S3 implementation rejected typed ListMultipartUploads: " &
                 Outcome.Status'Image & " " &
                 US.To_String (Outcome.Error.Code) & " " &
                 US.To_String (Outcome.Error.Message);
            elsif Present
              and then
                (Outcome.Result.Listing.Uploads.Length /= 1
                 or else US.To_String
                   (Outcome.Result.Listing.Uploads.First_Element.Key) /=
                     Object_Key
                 or else US.To_String
                   (Outcome.Result.Listing.Uploads.First_Element.Upload_ID) /=
                     Upload_ID
                 or else Outcome.Result.Listing.Is_Truncated)
            then
               raise Program_Error with
                 "S3 implementation ListMultipartUploads active value " &
                 "mismatch: count=" &
                 Outcome.Result.Listing.Uploads.Length'Image &
                 (if Outcome.Result.Listing.Uploads.Is_Empty then ""
                  else " key=" & US.To_String
                    (Outcome.Result.Listing.Uploads.First_Element.Key) &
                    " id=" &
                    US.To_String
                      (Outcome.Result.Listing.Uploads.First_Element.Upload_ID))
                 &
                 " expected-key=" & Object_Key & " expected-id=" &
                 Upload_ID & " truncated=" &
                 Outcome.Result.Listing.Is_Truncated'Image;
            elsif not Present
              and then not Outcome.Result.Listing.Uploads.Is_Empty
            then
               raise Program_Error with
                 "S3 implementation listed a retired multipart upload";
            end if;
         end;
      end Require_Listed_Upload;

      procedure Copy_With_Multipart is
         Copy_Key : constant String := Key & "-copy-part";
         Prepared_Create : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Low_Level.Path_Style, Bucket, Copy_Key, Identity,
              "us-east-1", Timestamp);
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Create, Timeout => 30.0);
      begin
         if Created.Kind /= Low_Level.Created then
            raise Program_Error with
              "S3 implementation rejected copy-part initiation";
         end if;
         declare
            Upload_ID : constant String :=
              US.To_String (Created.Result.Upload_ID);
            Parameters : Low_Level.Upload_Part_Copy_Parameters;
         begin
            if Check_List_Multipart_Uploads then
               Require_Listed_Upload (Copy_Key, Upload_ID, True);
            end if;
            Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
            Parameters.Copy_Source :=
              US.To_Unbounded_String (Bucket & "/" & Key);
            declare
               Prepared_Copy : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part_Copy
                   (Origin, Low_Level.Path_Style, Bucket, Copy_Key,
                    Parameters, Identity, "us-east-1", Timestamp);
               Copied : constant Low_Level.Upload_Part_Copy_Outcome :=
                 Low_Level.Execute_Upload_Part_Copy
                   (HTTP, Prepared_Copy, Timeout => 60.0);
            begin
               if Copied.Kind /= Low_Level.Part_Copied then
                  raise Program_Error with
                    "S3 implementation rejected UploadPartCopy";
               end if;
               Require_Listed_Part
                 (Copy_Key, Upload_ID,
                  US.To_String (Copied.Result.Copy_Part.Entity_Tag),
                  Flyology.Object_Storage.Byte_Count (Payload'Length));
               declare
                  Completion : Multipart.Complete_Multipart_Upload_Request;
               begin
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 1,
                        Entity_Tag => Copied.Result.Copy_Part.Entity_Tag,
                        others     => <>));
                  declare
                     Prepared_Complete : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Complete_Multipart_Upload
                         (Origin, Low_Level.Path_Style, Bucket, Copy_Key,
                          Upload_ID, Completion, Identity, "us-east-1",
                          Timestamp);
                     Completed : constant
                       Low_Level.Complete_Multipart_Outcome :=
                         Low_Level.Execute_Complete_Multipart_Upload
                           (HTTP, Prepared_Complete, Timeout => 30.0);
                  begin
                     if Completed.Kind /= Low_Level.Completed
                       or else US.To_String (Completed.Result.Key) /= Copy_Key
                     then
                        raise Program_Error with
                          "S3 implementation rejected copied-part completion";
                     end if;
                     if Check_List_Multipart_Uploads then
                        Require_Listed_Upload (Copy_Key, Upload_ID, False);
                     end if;
                  end;
               end;
            end;
         end;
      end Copy_With_Multipart;

      procedure Copy_Whole_Object is
         Copy_Key : constant String := Key & "-copy-object";
         Convenience_Key : constant String := Key & "-copy-convenience";
         Parameters : Low_Level.Copy_Object_Parameters;
      begin
         Parameters.Copy_Source :=
           US.To_Unbounded_String (Bucket & "/" & Key);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Copy_Object
                (Origin, Low_Level.Path_Style, Bucket, Copy_Key, Parameters,
                 Identity, "us-east-1", Timestamp);
            Copied : constant Low_Level.Copy_Object_Outcome :=
              Low_Level.Execute_Copy_Object
                (HTTP, Prepared, Timeout => 60.0);
         begin
            if Copied.Kind /= Low_Level.Object_Copied
              or else US.Length (Copied.Result.Copy_Result.Entity_Tag) = 0
              or else US.Length
                (Copied.Result.Copy_Result.Last_Modified) = 0
            then
               raise Program_Error with
                 "S3 implementation rejected typed CopyObject";
            end if;
         end;
         declare
            Copied : constant Transfers.Copy_Outcome :=
              Transfers.Copy_Object
                (HTTP, Origin, Bucket, Key & "-high level+%25", Bucket,
                 Convenience_Key, Identity, Timeout => 60.0);
         begin
            if Copied.Kind = Transfers.Copy_Rejected then
               raise Program_Error with
                 "S3 implementation rejected high-level CopyObject: " &
                 Copied.Status'Image & " " &
                 US.To_String (Copied.Error.Code) & " " &
                 US.To_String (Copied.Error.Message);
            elsif US.Length (Copied.Entity_Tag) = 0
              or else US.Length (Copied.Last_Modified) = 0
            then
               raise Program_Error with
                 "S3 implementation returned incomplete high-level " &
                 "CopyObject metadata";
            end if;
         end;
      end Copy_Whole_Object;

      procedure Delete_Many is
         First_Key  : constant String := Key & "-delete-many-a";
         Second_Key : constant String := Key & "-delete-many-b";
         Request    : Deletions.Delete_Objects_Request;
         Parameters : Low_Level.Delete_Objects_Parameters;

         procedure Create_Copy (Destination : String) is
            Copied : constant Transfers.Copy_Outcome :=
              Transfers.Copy_Object
                (HTTP, Origin, Bucket, Key, Bucket, Destination, Identity,
                 Timeout => 60.0);
         begin
            if Copied.Kind /= Transfers.Object_Copied then
               raise Program_Error with
                 "S3 implementation could not set up DeleteObjects";
            end if;
         end Create_Copy;
      begin
         Create_Copy (First_Key);
         Create_Copy (Second_Key);
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String (First_Key),
               Version_ID => US.Null_Unbounded_String));
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String (Second_Key),
               Version_ID => US.Null_Unbounded_String));
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Objects
                (Origin, Low_Level.Path_Style, Bucket, Request, Parameters,
                 Identity, "us-east-1", Timestamp);
            Deleted : constant Low_Level.Delete_Objects_Outcome :=
              Low_Level.Execute_Delete_Objects
                (HTTP, Prepared, Timeout => 60.0);
         begin
            if Deleted.Kind /= Low_Level.Objects_Deleted
              or else Deleted.Result.Result.Deleted.Length /= 2
              or else not Deleted.Result.Result.Errors.Is_Empty
            then
               raise Program_Error with
                 "S3 implementation rejected typed DeleteObjects";
            end if;
         end;
      end Delete_Many;
   begin
      HTTP_Client.Configure (HTTP, Origin);
      Check_Bucket_Tags;
      declare
         Parameters : Low_Level.List_Objects_Parameters;
         Prepared : Low_Level.Prepared_Request;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Key);
         Prepared := Low_Level.Prepare_List_Objects
           (Origin, Low_Level.Path_Style, Bucket, Parameters,
            Identity, "us-east-1", Timestamp);
         declare
            Outcome : constant Low_Level.List_Objects_Outcome :=
              Low_Level.Execute_List_Objects
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Listed
              or else not Outcome.Result.Listing.Contents.Is_Empty
            then
               raise Program_Error with
                 "S3 implementation preflight v1 list result mismatch";
            end if;
         end;
      end;
      declare
         Parameters : Low_Level.List_Objects_V2_Parameters;
         Prepared : Low_Level.Prepared_Request;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Key);
         Prepared := Low_Level.Prepare_List_Objects_V2
           (Origin, Low_Level.Path_Style, Bucket, Parameters,
            Identity, "us-east-1", Timestamp);
         declare
            Outcome : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Listed
              or else not Outcome.Listing.Contents.Is_Empty
            then
               raise Program_Error with
                 "S3 implementation preflight list result mismatch";
            end if;
         end;
      end;
      declare
         Prepared_Create : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Low_Level.Path_Style, Bucket, Key, Identity,
              "us-east-1", Timestamp);
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Create, Timeout => 30.0);
      begin
         if Created.Kind /= Low_Level.Created then
            raise Program_Error with
              "S3 implementation rejected CreateMultipartUpload";
         end if;
         declare
            Upload_ID : constant String :=
              US.To_String (Created.Result.Upload_ID);
            First_Payload : aliased constant String :=
              Payload (Payload'First .. Payload'First + 5 * 1_024 * 1_024 - 1);
            Second_Payload : aliased constant String :=
              Payload (First_Payload'Last + 1 .. Payload'Last);

            function Upload
              (Number : S3_Core.Part_Number;
               Value  : not null access constant String)
               return US.Unbounded_String
            is
               Parameters : Low_Level.Upload_Part_Parameters;
               Source : Upload_Source (Value);
            begin
               Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
               Parameters.Part_Number := Number;
               Parameters.Payload_SHA256 := US.To_Unbounded_String
                 (SigV4.SHA256_Hex (Value.all));
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Upload_Part
                      (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                       Identity, "us-east-1", Timestamp);
                  Uploaded : constant Low_Level.Upload_Part_Outcome :=
                    Low_Level.Execute_Upload_Part
                      (HTTP, Prepared, Source, Timeout => 60.0);
               begin
                  if Uploaded.Kind /= Low_Level.Part_Uploaded then
                     raise Program_Error with
                       "S3 implementation rejected UploadPart" &
                       Number'Image;
                  end if;
                  return Uploaded.Result.Entity_Tag;
               end;
            end Upload;
         begin
            if Check_List_Multipart_Uploads then
               Require_Listed_Upload (Key, Upload_ID, True);
            end if;
            declare
               First_ETag : constant US.Unbounded_String :=
                 Upload (1, First_Payload'Access);
            begin
               Require_Listed_Part
                 (Key, Upload_ID, US.To_String (First_ETag),
                  Flyology.Object_Storage.Byte_Count (First_Payload'Length));
               declare
                  Second_ETag : constant US.Unbounded_String :=
                    Upload (2, Second_Payload'Access);
                  Completion : Multipart.Complete_Multipart_Upload_Request;
               begin
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 1,
                        Entity_Tag => First_ETag,
                        others     => <>));
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 2,
                        Entity_Tag => Second_ETag,
                        others     => <>));
                  declare
                     Prepared_Complete : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Complete_Multipart_Upload
                         (Origin, Low_Level.Path_Style, Bucket, Key,
                          Upload_ID, Completion, Identity, "us-east-1",
                          Timestamp);
                     Completed : constant
                       Low_Level.Complete_Multipart_Outcome :=
                         Low_Level.Execute_Complete_Multipart_Upload
                           (HTTP, Prepared_Complete, Timeout => 30.0);
                  begin
                     if Completed.Kind /= Low_Level.Completed
                       or else US.To_String (Completed.Result.Key) /= Key
                     then
                        raise Program_Error with
                          "S3 implementation rejected CompleteMultipartUpload";
                     end if;
                     if Check_List_Multipart_Uploads then
                        Require_Listed_Upload (Key, Upload_ID, False);
                     end if;
                  end;
               end;
            end;
         end;
      end;
      Require_Listed_Object;
      Require_Head_Object;
      if Check_Get_Object_Attributes then
         Require_Get_Object_Attributes;
      end if;
      Require_Get_Object;
      Require_Object_Tagging;
      Copy_With_Multipart;
      Upload_High_Level_File;
      Copy_Whole_Object;
      Delete_Many;
      declare
         Abort_Key : constant String := Key & "-aborted";
         Prepared_Create : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Low_Level.Path_Style, Bucket, Abort_Key, Identity,
              "us-east-1", Timestamp);
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Create, Timeout => 30.0);
      begin
         if Created.Kind /= Low_Level.Created then
            raise Program_Error with
              "S3 implementation rejected abort-corpus initiation";
         end if;
         declare
            Aborted : constant Low_Level.Abort_Multipart_Outcome :=
              Transfers.Abort_Multipart_Upload
                (HTTP, Origin, Bucket, Abort_Key,
                 US.To_String (Created.Result.Upload_ID), Identity,
                 Timeout => 30.0);
         begin
            if Aborted.Kind /= Low_Level.Aborted then
               raise Program_Error with
                 "S3 implementation rejected AbortMultipartUpload";
            end if;
         end;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Run;

   procedure Require_Head_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Parameters : Low_Level.Head_Bucket_Parameters;
      Prepared   : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Head_Bucket
          (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
           "us-east-1", Timestamp);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Low_Level.Head_Bucket_Outcome :=
           Low_Level.Execute_Head_Bucket
             (HTTP, Prepared, Timeout => 30.0);
      begin
         if Outcome.Kind /= Low_Level.Bucket_Found
           or else
             (US.Length (Outcome.Result.Bucket_Region) /= 0
              and then US.To_String (Outcome.Result.Bucket_Region) /=
                "us-east-1")
         then
            raise Program_Error with
              "S3 implementation returned invalid HeadBucket metadata";
         end if;
      end;
      declare
         Outcome : constant Client_Buckets.Head_Outcome :=
           Client_Buckets.Head
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
      begin
         if Outcome.Kind /= Client_Buckets.Bucket_Available
           or else US.To_String (Outcome.Region) /= "us-east-1"
         then
            raise Program_Error with
              "high-level HeadBucket metadata mismatch";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Require_Head_Bucket;

   procedure Require_Bucket_Location
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Prepared   : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Location
          (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
           "us-east-1", Timestamp);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Low_Level.Get_Bucket_Location_Outcome :=
           Low_Level.Execute_Get_Bucket_Location
             (HTTP, Prepared, Timeout => 30.0);
      begin
         if Outcome.Kind /= Low_Level.Bucket_Location_Found
           or else
             (US.Length (Outcome.Result.Location_Constraint) /= 0
              and then US.To_String
                (Outcome.Result.Location_Constraint) /= "us-east-1")
         then
            raise Program_Error with
              "S3 implementation returned wrong GetBucketLocation value";
         end if;
      end;
      declare
         Outcome : constant Client_Buckets.Location_Outcome :=
           Client_Buckets.Get_Location
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
      begin
         if Outcome.Kind /= Client_Buckets.Location_Found
           or else US.To_String (Outcome.Region) /= "us-east-1"
           or else
             (US.Length (Outcome.Legacy_Constraint) /= 0
              and then US.To_String
                (Outcome.Legacy_Constraint) /= "us-east-1")
         then
            raise Program_Error with
              "high-level bucket-location normalization mismatch";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Require_Bucket_Location;

   procedure Require_Listed_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      pragma Unreferenced (Timestamp);
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Found      : Boolean := False;
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Client_Buckets.List_Outcome :=
           Client_Buckets.List_Page
             (HTTP, Origin, Identity, Maximum => 1_000,
              Timeout => 30.0);
      begin
         if Outcome.Kind /= Client_Buckets.Page_Available then
            raise Program_Error with
              "S3 implementation rejected ListBuckets: " &
              Outcome.Status'Image & " " &
              US.To_String (Outcome.Error.Code) & " " &
              US.To_String (Outcome.Error.Message);
         end if;
         for Value of Outcome.Page.Buckets loop
            if US.To_String (Value.Name) = Bucket then
               Found := True;
               exit;
            end if;
         end loop;
         if not Found then
            raise Program_Error with
              "S3 implementation did not list the created bucket";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Require_Listed_Bucket;

   procedure Create_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      pragma Unreferenced (Timestamp);
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Client_Buckets.Create_Outcome :=
           Client_Buckets.Create
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
      begin
         if Outcome.Kind /= Client_Buckets.Creation_Completed then
            raise Program_Error with
              "S3 implementation rejected high-level CreateBucket";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Create_Bucket;

   procedure Delete_One
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Key       : String;
      Timestamp : String)
   is
      pragma Unreferenced (Timestamp);
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Client_Objects.Delete_Outcome :=
           Client_Objects.Delete
             (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
      begin
         if Outcome.Kind /= Client_Objects.Object_Removed then
            raise Program_Error with
              "S3 implementation rejected high-level DeleteObject";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Delete_One;

   procedure Delete_Empty_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      pragma Unreferenced (Timestamp);
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Client_Buckets.Delete_Outcome :=
           Client_Buckets.Delete
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
      begin
         if Outcome.Kind /= Client_Buckets.Deletion_Completed then
            raise Program_Error with
              "S3 implementation rejected high-level DeleteBucket";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Delete_Empty_Bucket;

   protected type Task_Result is
      procedure Report (Passed : Boolean; Detail : String := "");
      entry Wait (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Done         : Boolean := False;
      Passed_Value : Boolean := False;
      Detail_Value : US.Unbounded_String;
   end Task_Result;

   protected body Task_Result is
      procedure Report (Passed : Boolean; Detail : String := "") is
      begin
         Passed_Value := Passed;
         Detail_Value := US.To_Unbounded_String (Detail);
         Done := True;
      end Report;

      entry Wait
        (Passed : out Boolean; Detail : out US.Unbounded_String) when Done
      is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait;
   end Task_Result;

begin
   if Ada.Command_Line.Argument_Count not in 3 .. 4 then
      raise Program_Error with
        "usage: s3_implementation_corpus ENDPOINT BUCKET " &
        "YYYYMMDDTHHMMSSZ [setup|cleanup]";
   end if;
   declare
      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin (Ada.Command_Line.Argument (1));
      Bucket : constant String := Ada.Command_Line.Argument (2);
      Timestamp : constant String := Ada.Command_Line.Argument (3);
      Lightweight_Result : Task_Result;
      Passed : Boolean;
      Detail : US.Unbounded_String;
   begin
      if Ada.Command_Line.Argument_Count = 3 then
         Run (Origin, Bucket, "native-object", Timestamp);
         declare
            task Lightweight_Client is
               pragma Task_Info (Flyology.Lightweight_Task);
            end Lightweight_Client;

            task body Lightweight_Client is
            begin
               Run (Origin, Bucket, "lightweight-object", Timestamp);
               Lightweight_Result.Report (True);
            exception
               when Occurrence : others =>
                  Lightweight_Result.Report
                    (False,
                     Ada.Exceptions.Exception_Information (Occurrence));
            end Lightweight_Client;
         begin
            Lightweight_Result.Wait (Passed, Detail);
         end;
         if not Passed then
            raise Program_Error with US.To_String (Detail);
         end if;
         Ada.Text_IO.Put_Line
           ("S3 implementation corpus: native and lightweight clients OK");
      elsif Ada.Command_Line.Argument (4) = "setup" then
         Create_Bucket (Origin, Bucket, Timestamp);
         declare
            task Lightweight_Client is
               pragma Task_Info (Flyology.Lightweight_Task);
            end Lightweight_Client;

            task body Lightweight_Client is
            begin
               Require_Head_Bucket (Origin, Bucket, Timestamp);
               Require_Bucket_Location (Origin, Bucket, Timestamp);
               Require_Listed_Bucket (Origin, Bucket, Timestamp);
               Lightweight_Result.Report (True);
            exception
               when Occurrence : others =>
                  Lightweight_Result.Report
                    (False,
                     Ada.Exceptions.Exception_Information (Occurrence));
            end Lightweight_Client;
         begin
            Lightweight_Result.Wait (Passed, Detail);
         end;
         if not Passed then
            raise Program_Error with US.To_String (Detail);
         end if;
         Require_Head_Bucket (Origin, Bucket, Timestamp);
         Require_Bucket_Location (Origin, Bucket, Timestamp);
         Require_Listed_Bucket (Origin, Bucket, Timestamp);
         Ada.Text_IO.Put_Line
           ("S3 implementation setup: bucket created, located, headed, " &
            "and listed");
      elsif Ada.Command_Line.Argument (4) = "cleanup" then
         Delete_One (Origin, Bucket, "native-object", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-copy-part", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-copy-object", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-copy-convenience", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-high level+%25", Timestamp);
         declare
            task Lightweight_Client is
               pragma Task_Info (Flyology.Lightweight_Task);
            end Lightweight_Client;

            task body Lightweight_Client is
            begin
               Delete_One
                 (Origin, Bucket, "lightweight-object", Timestamp);
               Delete_One
                 (Origin, Bucket, "lightweight-object-copy-part", Timestamp);
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-copy-object", Timestamp);
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-copy-convenience", Timestamp);
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-high level+%25", Timestamp);
               Lightweight_Result.Report (True);
            exception
               when Occurrence : others =>
                  Lightweight_Result.Report
                    (False,
                     Ada.Exceptions.Exception_Information (Occurrence));
            end Lightweight_Client;
         begin
            Lightweight_Result.Wait (Passed, Detail);
         end;
         if not Passed then
            raise Program_Error with US.To_String (Detail);
         end if;
         Delete_Empty_Bucket (Origin, Bucket, Timestamp);
         Ada.Text_IO.Put_Line
           ("S3 implementation cleanup: objects and bucket deleted");
      else
         raise Program_Error with "unknown corpus mode";
      end if;
   end;
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("S3 implementation corpus failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_Implementation_Corpus;
