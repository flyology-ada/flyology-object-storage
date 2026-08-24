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
with Flyology.Buffers;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Objects;
with Flyology.Object_Storage.Client.Scoped;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.Tags;

procedure S3_Implementation_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Buffers renames Flyology.Buffers;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Client_Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Client_Objects renames Flyology.Object_Storage.Client.Objects;
   package Scoped renames Flyology.Object_Storage.Client.Scoped;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package Attributes renames Flyology.Object_Storage.S3.Attributes;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Checksum_Policy renames Checksums.Policy;
   package S3_Core renames Flyology.Object_Storage.S3.Core;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Tags renames Flyology.Object_Storage.Tags;
   package Stream_IO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Kind;
   use type Stream_IO.Count;
   use type US.Unbounded_String;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Delete_Objects_Outcome_Kind;
   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.Get_Object_Attributes_Outcome_Kind;
   use type Low_Level.Head_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Upload_Part_Copy_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
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
   use type Client_Buckets.Delete_Tags_Outcome_Kind;
   use type Tags.Tag_Vectors.Vector;
   use type Client_Objects.Delete_Outcome_Kind;
   use type Scoped.Delete_Result_Kind;
   use type Scoped.Deletion_Disposition;
   use type Scoped.Create_Multipart_Result_Kind;
   use type Scoped.Multipart_Creation_Disposition;
   use type Scoped.Upload_Part_Result_Kind;
   use type Scoped.Part_Upload_Disposition;
   use type Client_Objects.List_Outcome_Kind;
   use type Client_Objects.Whole_Get_Outcome_Kind;
   use type Client_Objects.Tagging_Outcome_Kind;
   use type Flyology.Object_Storage.Object_Tag_Set;
   use type Client_Buckets.Set_Versioning_Outcome_Kind;
   use type Client_Buckets.Get_Versioning_Outcome_Kind;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;

   Access_Key : constant String := "FLYOLOGYS3ORACLE";
   Secret_Key : constant String := "flyology-s3-oracle-secret-key-tests";
   Payload    : aliased constant String :=
     String'(1 .. 6 * 1_024 * 1_024 => 'm');

   function Temporary_Path (Name : String) return String is
      Variable : constant String := "FLYOLOGY_S3_CORPUS_TEMP_DIR";
      Root : constant String :=
        (if Ada.Environment_Variables.Exists (Variable)
         then Ada.Environment_Variables.Value (Variable)
         else "/tmp");
   begin
      if Root'Length = 0
        or else not Ada.Directories.Exists (Root)
        or else Ada.Directories.Kind (Root) /= Ada.Directories.Directory
      then
         raise Program_Error with
           "S3 implementation corpus temporary directory is unavailable";
      end if;
      return Ada.Directories.Compose (Root, Name);
   end Temporary_Path;

   function Repeated_Digest
     (Algorithm : Checksum_Policy.Algorithm;
      Length    : Natural) return Checksums.Digest_Value
   is
      Context : Checksums.Context (Algorithm);
      Buffer : constant Stream_Element_Array (1 .. 64 * 1_024) :=
        (others => Stream_Element (Character'Pos ('m')));
      Remaining : Natural := Length;
   begin
      while Remaining > 0 loop
         declare
            Count : constant Natural :=
              Natural'Min (Remaining, Natural (Buffer'Length));
         begin
            Checksums.Update
              (Context,
               Buffer
                 (Buffer'First ..
                    Buffer'First + Stream_Element_Offset (Count - 1)));
            Remaining := Remaining - Count;
         end;
      end loop;
      return Checksums.Finish (Context);
   end Repeated_Digest;

   First_Part_Length : constant Natural := 5 * 1_024 * 1_024;
   Second_Part_Length : constant Natural := Payload'Length - First_Part_Length;
   First_SHA256_Digest : constant Checksums.Digest_Value :=
     Repeated_Digest (Checksum_Policy.Core.SHA256, First_Part_Length);
   Second_SHA256_Digest : constant Checksums.Digest_Value :=
     Repeated_Digest (Checksum_Policy.Core.SHA256, Second_Part_Length);
   First_SHA256 : constant String :=
     Checksums.Encode_Base64 (First_SHA256_Digest);
   Second_SHA256 : constant String :=
     Checksums.Encode_Base64 (Second_SHA256_Digest);
   Composite_SHA256_Digest : constant Checksums.Digest_Value :=
     Checksums.Composite
       (Checksum_Policy.Core.SHA256,
        Checksums.Digest_Array'
          (1 => First_SHA256_Digest, 2 => Second_SHA256_Digest));
   Composite_SHA256_Raw : constant String :=
     Checksums.Encode_Base64 (Composite_SHA256_Digest);
   Composite_SHA256_Object : constant String :=
     Checksums.Encode_Object
       (Composite_SHA256_Digest, Checksum_Policy.Composite, 2);
   Full_CRC32 : constant String :=
     Checksums.Encode_Base64
       (Repeated_Digest (Checksum_Policy.Core.CRC32, Payload'Length));
   Full_SHA256 : constant String :=
     Checksums.Encode_Base64
       (Repeated_Digest (Checksum_Policy.Core.SHA256, Payload'Length));

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

   function Check_List_Parts_Pagination return Boolean is
      Name : constant String := "FLYOLOGY_LIST_PARTS_PAGINATION_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "seaweedfs-4.43-repeats-marker-page"
      then
         return False;
      else
         raise Program_Error with "unknown ListParts pagination oracle mode";
      end if;
   end Check_List_Parts_Pagination;

   function Check_List_Objects_V1_Pagination return Boolean is
      Name : constant String := "FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-next-marker-without-delimiter"
        or else Ada.Environment_Variables.Value (Name) =
          "seaweedfs-4.43-next-marker-without-delimiter"
        or else Ada.Environment_Variables.Value (Name) =
          "minio-2025-next-marker-without-delimiter"
      then
         return False;
      else
         raise Program_Error with "unknown ListObjects v1 oracle mode";
      end if;
   end Check_List_Objects_V1_Pagination;

   type Delete_Object_Oracle_Mode_Kind is
     (Complete_Delete_Object,
      Conditioned_Missing_Is_412,
      MinIO_2025_Ignores_If_Match);

   function Delete_Object_Oracle_Mode
     return Delete_Object_Oracle_Mode_Kind
   is
      Name : constant String := "FLYOLOGY_DELETE_OBJECT_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return Complete_Delete_Object;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-conditioned-missing-412"
        or else Ada.Environment_Variables.Value (Name) =
          "seaweedfs-4.43-conditioned-missing-412"
      then
         return Conditioned_Missing_Is_412;
      elsif Ada.Environment_Variables.Value (Name) =
        "minio-2025-ignores-if-match"
      then
         return MinIO_2025_Ignores_If_Match;
      else
         raise Program_Error with "unknown DeleteObject oracle mode";
      end if;
   end Delete_Object_Oracle_Mode;

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

   type Head_Object_Oracle_Mode_Kind is
     (Complete_Head_Object,
      RustFS_RC3_Incomplete_Head_Object,
      SeaweedFS_443_Whole_Size_Parts_And_Range,
      MinIO_2025_Uses_206_For_Part_And_Range);

   function Head_Object_Oracle_Mode return Head_Object_Oracle_Mode_Kind is
      Name : constant String := "FLYOLOGY_HEAD_OBJECT_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return Complete_Head_Object;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-ignores-overrides-parts-and-range"
      then
         return RustFS_RC3_Incomplete_Head_Object;
      elsif Ada.Environment_Variables.Value (Name) =
        "seaweedfs-4.43-returns-whole-size-for-parts-and-range"
      then
         return SeaweedFS_443_Whole_Size_Parts_And_Range;
      elsif Ada.Environment_Variables.Value (Name) =
        "minio-2025-uses-206-for-part-and-range"
      then
         return MinIO_2025_Uses_206_For_Part_And_Range;
      else
         raise Program_Error with "unknown HeadObject oracle mode";
      end if;
   end Head_Object_Oracle_Mode;

   function Check_Head_Object_Overrides return Boolean is
     (Head_Object_Oracle_Mode /= RustFS_RC3_Incomplete_Head_Object);

   type Multipart_Checksum_Oracle_Mode_Kind is
     (Complete_Multipart_Checksums,
      RustFS_RC3_Multipart_Checksum_Divergence,
      SeaweedFS_443_Multipart_Checksum_Divergence);

   function Read_Multipart_Checksum_Oracle_Mode
      return Multipart_Checksum_Oracle_Mode_Kind
   is
      Name : constant String :=
        "FLYOLOGY_MULTIPART_CHECKSUM_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return Complete_Multipart_Checksums;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-omits-listparts-checksums"
      then
         return RustFS_RC3_Multipart_Checksum_Divergence;
      elsif Ada.Environment_Variables.Value (Name) =
        "seaweedfs-4.43-omits-multipart-checksum-metadata"
      then
         return SeaweedFS_443_Multipart_Checksum_Divergence;
      else
         raise Program_Error with
           "unknown multipart checksum oracle mode";
      end if;
   end Read_Multipart_Checksum_Oracle_Mode;

   Multipart_Checksum_Oracle_Mode : constant
     Multipart_Checksum_Oracle_Mode_Kind :=
       Read_Multipart_Checksum_Oracle_Mode;

   type Put_Object_Oracle_Mode_Kind is
     (Complete_Put_Object,
      RustFS_RC3_Omits_Checksum_Type,
      SeaweedFS_443_Omits_Checksum_Type);

   function Read_Put_Object_Oracle_Mode return Put_Object_Oracle_Mode_Kind is
      Name : constant String := "FLYOLOGY_PUT_OBJECT_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return Complete_Put_Object;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-omits-checksum-type"
      then
         return RustFS_RC3_Omits_Checksum_Type;
      elsif Ada.Environment_Variables.Value (Name) =
        "seaweedfs-4.43-omits-checksum-type"
      then
         return SeaweedFS_443_Omits_Checksum_Type;
      else
         raise Program_Error with "unknown PutObject oracle mode";
      end if;
   end Read_Put_Object_Oracle_Mode;

   Put_Object_Oracle_Mode : constant Put_Object_Oracle_Mode_Kind :=
     Read_Put_Object_Oracle_Mode;

   type Conditional_Get_Oracle_Mode_Kind is
     (Complete_Conditional_Get,
      RustFS_RC3_Bodyless_Stale_Get_412);

   function Read_Conditional_Get_Oracle_Mode
      return Conditional_Get_Oracle_Mode_Kind
   is
      Name : constant String :=
        "FLYOLOGY_CONDITIONAL_GET_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return Complete_Conditional_Get;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-bodyless-stale-if-match-412"
      then
         return RustFS_RC3_Bodyless_Stale_Get_412;
      else
         raise Program_Error with
           "unknown conditional GetObject oracle mode";
      end if;
   end Read_Conditional_Get_Oracle_Mode;

   Conditional_Get_Oracle_Mode : constant
     Conditional_Get_Oracle_Mode_Kind :=
       Read_Conditional_Get_Oracle_Mode;

   type Copy_Object_Oracle_Mode_Kind is
     (Complete_Copy_Object,
      SeaweedFS_443_Bare_Result_ETag);

   function Read_Copy_Object_Oracle_Mode
      return Copy_Object_Oracle_Mode_Kind
   is
      Name : constant String := "FLYOLOGY_COPY_OBJECT_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return Complete_Copy_Object;
      elsif Ada.Environment_Variables.Value (Name) =
        "seaweedfs-4.43-bare-result-etag"
      then
         return SeaweedFS_443_Bare_Result_ETag;
      else
         raise Program_Error with "unknown CopyObject oracle mode";
      end if;
   end Read_Copy_Object_Oracle_Mode;

   Copy_Object_Oracle_Mode : constant Copy_Object_Oracle_Mode_Kind :=
     Read_Copy_Object_Oracle_Mode;

   type Upload_Source
     (Value : not null access constant String) is
     new HTTP_Client.Request_Body_Source with record
      Position : Natural := 0;
      Chunk    : Positive := 997;
      First    : Positive := Value'First;
      Length   : Natural := Value'Length;
   end record;

   overriding function Declared_Length
     (Item : Upload_Source) return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Item.Length)));

   overriding procedure Read
     (Item     : in out Upload_Source;
      Data     : out Stream_Element_Array;
      Last     : out Stream_Element_Offset;
      Finished : out Boolean;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
      Remaining : constant Natural := Item.Length - Item.Position;
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
                      (Item.First + Item.Position + Offset)));
         end loop;
         Last := Data'First + Stream_Element_Offset (Count - 1);
         Item.Position := Item.Position + Count;
      end if;
      Finished := Item.Position = Item.Length;
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

      function Composite_Create_Parameters
        return Low_Level.Create_Multipart_Parameters
      is
         Result : Low_Level.Create_Multipart_Parameters;
      begin
         Result.Checksum_Algorithm := US.To_Unbounded_String ("SHA256");
         Result.Checksum_Type := US.To_Unbounded_String ("COMPOSITE");
         return Result;
      end Composite_Create_Parameters;

      function Composite_Complete_Parameters
        return Low_Level.Complete_Multipart_Parameters
      is
         Result : Low_Level.Complete_Multipart_Parameters;
      begin
         Result.Checksum_SHA256 :=
           US.To_Unbounded_String (Composite_SHA256_Raw);
         Result.Checksum_Type := US.To_Unbounded_String ("COMPOSITE");
         Result.Mpu_Object_Size :=
           (Is_Set => True,
            Value => Flyology.Object_Storage.Byte_Count (Payload'Length));
         return Result;
      end Composite_Complete_Parameters;

      procedure Check_Bucket_Tags is
         Value : Tags.Tag_Set;
         Replacement : Tags.Tag_Set;
      begin
         Value.Append
           (Tags.Tag'
              (Key   => US.To_Unbounded_String ("corpus"),
               Value => US.To_Unbounded_String ("flyology")));
         Replacement.Append
           (Tags.Tag'
              (Key   => US.To_Unbounded_String ("replacement"),
               Value => US.To_Unbounded_String ("complete")));
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
         declare
            Put_Result : constant Client_Buckets.Put_Tags_Outcome :=
              Client_Buckets.Put_Tags
                (HTTP, Origin, Bucket, Replacement, Identity,
                 Timeout => 30.0);
            Get_Result : constant Client_Buckets.Get_Tags_Outcome :=
              Client_Buckets.Get_Tags
                (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
         begin
            if Put_Result.Kind /= Client_Buckets.Tags_Replaced
              or else Get_Result.Kind /= Client_Buckets.Tags_Found
              or else Get_Result.Value /= Replacement
            then
               raise Program_Error with
                 "S3 implementation did not atomically replace bucket tags";
            end if;
         end;
         declare
            Delete_Result : constant Client_Buckets.Delete_Tags_Outcome :=
              Client_Buckets.Delete_Tags
                (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
            Get_Result : constant Client_Buckets.Get_Tags_Outcome :=
              Client_Buckets.Get_Tags
                (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
         begin
            if Delete_Result.Kind /= Client_Buckets.Tags_Deleted
              or else Get_Result.Kind /= Client_Buckets.Get_Tags_Rejected
              or else US.To_String (Get_Result.Error.Code) /= "NoSuchTagSet"
            then
               raise Program_Error with
                 "S3 implementation rejected bucket tag deletion lifecycle";
            end if;
         end;
         declare
            Delete_Result : constant Client_Buckets.Delete_Tags_Outcome :=
              Client_Buckets.Delete_Tags
                (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
         begin
            if Delete_Result.Kind /= Client_Buckets.Tags_Deleted then
               raise Program_Error with
                 "S3 implementation did not make bucket tag deletion " &
                 "idempotent";
            end if;
         end;
      end Check_Bucket_Tags;

      procedure Upload_High_Level_File is
         Local_Path : constant String :=
           Temporary_Path
             ("flyology-object-storage-" & Bucket & "-" & Key & ".bin");
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
                 Multipart_Part_Size => 5 * 1_024 * 1_024,
                 Checksum =>
                   (if Multipart_Checksum_Oracle_Mode /=
                         SeaweedFS_443_Multipart_Checksum_Divergence
                    then
                      (Enabled => True,
                       Algorithm => Checksum_Policy.Core.CRC32,
                       Kind => Checksum_Policy.Full_Object)
                    else (Enabled => False, others => <>)));
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
              or else
                (Multipart_Checksum_Oracle_Mode /=
                   SeaweedFS_443_Multipart_Checksum_Divergence
                 and then
                   (US.To_String (Result.Checksum) /= Full_CRC32
                    or else US.To_String (Result.Checksum_Type) /=
                      "FULL_OBJECT"))
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
                 or else
                   (Outcome.Result.Listing.Contents.First_Element.Has_Owner
                    and then US.Length
                      (Outcome.Result.Listing.Contents.First_Element.Owner.ID)
                        = 0)
               then
                  raise Program_Error with
                    "S3 implementation failed typed ListObjects v1";
               end if;
            end;
         end;
         declare
            Outcome : constant Client_Objects.List_V1_Outcome :=
              Client_Objects.List_V1_Page
                (HTTP, Origin, Bucket, Identity, Prefix => Key,
                 Maximum => 1, Timeout => 30.0);
         begin
            if Outcome.Kind /= Client_Objects.Page_Available
              or else Outcome.Page.Contents.Length /= 1
              or else US.To_String
                (Outcome.Page.Contents.First_Element.Key) /= Key
              or else
                (Outcome.Page.Contents.First_Element.Has_Owner
                 and then US.Length
                   (Outcome.Page.Contents.First_Element.Owner.ID) = 0)
            then
               raise Program_Error with
                 "S3 implementation failed high-level ListObjects v1";
            end if;
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
         declare
            Outcome : constant Client_Objects.List_Outcome :=
              Client_Objects.List_Page
                (HTTP, Origin, Bucket, Identity, Prefix => Key,
                 Maximum => 1, Fetch_Owner => True, Timeout => 30.0);
         begin
            if Outcome.Kind /= Client_Objects.Page_Available
              or else Outcome.Page.Contents.Length /= 1
              or else US.To_String
                (Outcome.Page.Contents.First_Element.Key) /= Key
              or else not Outcome.Page.Contents.First_Element.Has_Owner
              or else US.Length
                (Outcome.Page.Contents.First_Element.Owner.ID) = 0
            then
               raise Program_Error with
                 "S3 implementation failed high-level ListObjectsV2";
            end if;
         end;
      end Require_Listed_Object;

      procedure Require_High_Level_List_Pagination is
         --  Use the complete bucket namespace so the fixture has multiple
         --  independently verified objects on every permissive oracle.
         First : constant Client_Objects.List_Outcome :=
           Client_Objects.List_Page
             (HTTP, Origin, Bucket, Identity, Maximum => 1,
              Timeout => 30.0);
      begin
         if First.Kind /= Client_Objects.Page_Available
           or else First.Page.Contents.Length /= 1
           or else not First.Page.Is_Truncated
           or else not First.Page.Has_Next_Continuation_Token
           or else US.Length (First.Page.Next_Continuation_Token) = 0
         then
            raise Program_Error with
              "S3 implementation failed high-level first list page: kind=" &
              Client_Objects.List_Outcome_Kind'Image (First.Kind) &
              (if First.Kind = Client_Objects.Page_Available
               then " count=" & First.Page.Contents.Length'Image &
                 " truncated=" & First.Page.Is_Truncated'Image &
                 " token-present=" &
                 First.Page.Has_Next_Continuation_Token'Image &
                 " token-length=" &
                 US.Length (First.Page.Next_Continuation_Token)'Image
               else " status=" & First.Status'Image);
         end if;
         declare
            First_Key : constant String := US.To_String
              (First.Page.Contents.First_Element.Key);
            Next : constant Client_Objects.List_Outcome :=
              Client_Objects.List_Page
                (HTTP, Origin, Bucket, Identity, Maximum => 1,
                 Continuation_Token => US.To_String
                   (First.Page.Next_Continuation_Token),
                 Timeout => 30.0);
         begin
            if Next.Kind /= Client_Objects.Page_Available
              or else Next.Page.Contents.Length /= 1
              or else US.To_String
                (Next.Page.Contents.First_Element.Key) <= First_Key
            then
               raise Program_Error with
                 "S3 implementation failed high-level continuation page";
            end if;
         end;
         if Check_List_Objects_V1_Pagination then
            declare
               V1_First : constant Client_Objects.List_V1_Outcome :=
                 Client_Objects.List_V1_Page
                   (HTTP, Origin, Bucket, Identity, Maximum => 1,
                    Timeout => 30.0);
            begin
               if V1_First.Kind /= Client_Objects.Page_Available
                 or else V1_First.Page.Contents.Length /= 1
                 or else not V1_First.Page.Is_Truncated
                 or else not V1_First.Has_Next_Marker
                 or else US.Length (V1_First.Next_Marker) = 0
               then
                  raise Program_Error with
                    "S3 implementation failed ListObjects v1 first page";
               end if;
               declare
                  First_Key : constant String := US.To_String
                    (V1_First.Page.Contents.First_Element.Key);
                  V1_Next : constant Client_Objects.List_V1_Outcome :=
                    Client_Objects.List_V1_Page
                      (HTTP, Origin, Bucket, Identity, Maximum => 1,
                       Marker => US.To_String (V1_First.Next_Marker),
                       Timeout => 30.0);
               begin
                  if V1_Next.Kind /= Client_Objects.Page_Available
                    or else V1_Next.Page.Contents.Length /= 1
                    or else US.To_String
                      (V1_Next.Page.Contents.First_Element.Key) <= First_Key
                  then
                     raise Program_Error with
                       "S3 implementation failed ListObjects v1 continuation";
                  end if;
               end;
            end;
         end if;
      end Require_High_Level_List_Pagination;

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
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                    Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Object_Found then
                  raise Program_Error with
                    "S3 implementation rejected HeadObject full surface: " &
                    Outcome.Status'Image & " " &
                    US.To_String (Outcome.Error.Code) & " " &
                    US.To_String (Outcome.Error.Message);
               elsif Outcome.Status /= 200
                 or else Outcome.Result.Content_Length /=
                   Flyology.Object_Storage.Byte_Count (Payload'Length)
                 or else US.Length (Outcome.Result.Content_Range) /= 0
                 or else
                   (Check_Head_Object_Overrides
                    and then
                      (US.To_String (Outcome.Result.Cache_Control) /=
                         "no-store"
                       or else US.To_String
                         (Outcome.Result.Content_Disposition) /= "attachment"
                       or else US.To_String
                         (Outcome.Result.Content_Encoding) /= "identity"
                       or else US.To_String
                         (Outcome.Result.Content_Language) /= "en-CA"
                       or else US.To_String (Outcome.Result.Content_Type) /=
                         "application/octet-stream"
                       or else US.To_String (Outcome.Result.Expires) /=
                         "Fri, 01 Jan 2099 00:00:00 GMT"))
               then
                  raise Program_Error with
                    "S3 implementation HeadObject full request/result " &
                    "surface mismatch: status=" & Outcome.Status'Image &
                    " length=" & Outcome.Result.Content_Length'Image &
                    " range=" &
                    US.To_String (Outcome.Result.Content_Range) &
                    " parts_set=" &
                    Outcome.Result.Parts_Count.Is_Set'Image &
                    " parts=" &
                    (if Outcome.Result.Parts_Count.Is_Set
                     then Outcome.Result.Parts_Count.Value'Image else "-") &
                    " cache=" &
                    US.To_String (Outcome.Result.Cache_Control) &
                    " disposition=" & US.To_String
                      (Outcome.Result.Content_Disposition) &
                    " encoding=" &
                    US.To_String (Outcome.Result.Content_Encoding) &
                    " language=" &
                    US.To_String (Outcome.Result.Content_Language) &
                    " type=" & US.To_String (Outcome.Result.Content_Type) &
                    " expires=" & US.To_String (Outcome.Result.Expires);
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("null");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
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
                 or else Outcome.Status /= 200
                 or else US.To_String (Outcome.Result.Checksum_SHA256) /=
                   Composite_SHA256_Object
                 or else
                   (US.Length (Outcome.Result.Checksum_Type) > 0
                    and then US.To_String
                      (Outcome.Result.Checksum_Type) /= "COMPOSITE")
               then
                  raise Program_Error with
                    "S3 implementation HeadObject version/payer/checksum " &
                    "policy mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Part_Number := (Is_Set => True, Value => 1);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                    Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Object_Found then
                  raise Program_Error with
                    "S3 implementation HeadObject part one mismatch: " &
                    "kind=" & Outcome.Kind'Image &
                    " status=" & Outcome.Status'Image &
                    " code=" & US.To_String (Outcome.Error.Code) &
                    " message=" & US.To_String (Outcome.Error.Message);
               elsif Outcome.Status /=
                 (if Head_Object_Oracle_Mode =
                      MinIO_2025_Uses_206_For_Part_And_Range
                  then 206 else 200)
                 or else
                   (case Head_Object_Oracle_Mode is
                      when Complete_Head_Object =>
                        Outcome.Result.Content_Length /= 5 * 1_024 * 1_024
                        or else not Outcome.Result.Parts_Count.Is_Set
                        or else Outcome.Result.Parts_Count.Value /= 2
                        or else US.Length
                          (Outcome.Result.Content_Range) /= 0,
                      when RustFS_RC3_Incomplete_Head_Object =>
                        Outcome.Result.Content_Length /= Payload'Length
                        or else Outcome.Result.Parts_Count.Is_Set
                        or else US.Length
                          (Outcome.Result.Content_Range) /= 0,
                      when SeaweedFS_443_Whole_Size_Parts_And_Range =>
                        Outcome.Result.Content_Length /= Payload'Length
                        or else not Outcome.Result.Parts_Count.Is_Set
                        or else Outcome.Result.Parts_Count.Value /= 2
                        or else US.Length
                          (Outcome.Result.Content_Range) /= 0,
                      when MinIO_2025_Uses_206_For_Part_And_Range =>
                        Outcome.Result.Content_Length /= 5 * 1_024 * 1_024
                        or else not Outcome.Result.Parts_Count.Is_Set
                        or else Outcome.Result.Parts_Count.Value /= 2
                        or else US.To_String
                          (Outcome.Result.Content_Range) /=
                            "bytes 0-5242879/6291456")
               then
                  raise Program_Error with
                    "S3 implementation HeadObject part one mismatch: " &
                    "kind=" & Outcome.Kind'Image &
                    " status=" & Outcome.Status'Image &
                    " length=" & Outcome.Result.Content_Length'Image &
                    " parts_set=" &
                    Outcome.Result.Parts_Count.Is_Set'Image &
                    " parts=" &
                    (if Outcome.Result.Parts_Count.Is_Set
                     then Outcome.Result.Parts_Count.Value'Image else "-");
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Byte_Range_Header :=
              US.To_Unbounded_String ("bytes=0-15");
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                    Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Object_Found then
                  raise Program_Error with
                    "S3 implementation HeadObject range mismatch: " &
                    "kind=" & Outcome.Kind'Image &
                    " status=" & Outcome.Status'Image &
                    " code=" & US.To_String (Outcome.Error.Code) &
                    " message=" & US.To_String (Outcome.Error.Message);
               elsif
                 (case Head_Object_Oracle_Mode is
                    when Complete_Head_Object =>
                      Outcome.Status /= 200
                      or else Outcome.Result.Content_Length /= 16
                      or else US.Length (Outcome.Result.Content_Range) /= 0,
                    when RustFS_RC3_Incomplete_Head_Object |
                         SeaweedFS_443_Whole_Size_Parts_And_Range =>
                      Outcome.Status /= 200
                      or else Outcome.Result.Content_Length /= Payload'Length
                      or else US.Length (Outcome.Result.Content_Range) /= 0,
                    when MinIO_2025_Uses_206_For_Part_And_Range =>
                      Outcome.Status /= 206
                      or else Outcome.Result.Content_Length /= 16
                      or else US.To_String (Outcome.Result.Content_Range) /=
                        "bytes 0-15/6291456")
               then
                  raise Program_Error with
                    "S3 implementation HeadObject range mismatch: " &
                    "kind=" & Outcome.Kind'Image &
                    " status=" & Outcome.Status'Image &
                    " length=" & Outcome.Result.Content_Length'Image &
                    " range=" &
                    US.To_String (Outcome.Result.Content_Range);
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
                 Part_Number => (Is_Set => True, Value => 2),
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Transfers.Object_Found
              or else Outcome.Status /=
                (if Head_Object_Oracle_Mode =
                     MinIO_2025_Uses_206_For_Part_And_Range
                 then 206 else 200)
              or else
                (case Head_Object_Oracle_Mode is
                   when Complete_Head_Object =>
                     Outcome.Bytes /= 1_024 * 1_024
                     or else not Outcome.Details.Parts_Count.Is_Set
                     or else Outcome.Details.Parts_Count.Value /= 2
                     or else US.Length (Outcome.Details.Content_Range) /= 0,
                   when RustFS_RC3_Incomplete_Head_Object =>
                     Outcome.Bytes /= Payload'Length
                     or else Outcome.Details.Parts_Count.Is_Set
                     or else US.Length (Outcome.Details.Content_Range) /= 0,
                   when SeaweedFS_443_Whole_Size_Parts_And_Range =>
                     Outcome.Bytes /= Payload'Length
                     or else not Outcome.Details.Parts_Count.Is_Set
                     or else Outcome.Details.Parts_Count.Value /= 2
                     or else US.Length (Outcome.Details.Content_Range) /= 0,
                   when MinIO_2025_Uses_206_For_Part_And_Range =>
                     Outcome.Bytes /= 1_024 * 1_024
                     or else not Outcome.Details.Parts_Count.Is_Set
                     or else Outcome.Details.Parts_Count.Value /= 2
                     or else US.To_String
                       (Outcome.Details.Content_Range) /=
                         "bytes 5242880-6291455/6291456")
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
              or else
                Outcome.Status /=
                  (case Head_Object_Oracle_Mode is
                     when Complete_Head_Object => 416,
                     when RustFS_RC3_Incomplete_Head_Object => 500,
                     when SeaweedFS_443_Whole_Size_Parts_And_Range => 400,
                     when MinIO_2025_Uses_206_For_Part_And_Range => 416)
            then
               raise Program_Error with
                 "S3 implementation HeadObject absent part mismatch: " &
                 "kind=" & Outcome.Kind'Image &
                 " status=" & Outcome.Status'Image;
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
           Temporary_Path
             ("flyology-object-storage-get-" & Bucket & "-" & Key & ".bin");
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

      procedure Require_Exact_Object
        (Object_Key : String;
         Expected   : String)
      is
         Download_Path : constant String :=
           Temporary_Path
             ("flyology-object-storage-copy-oracle-" & Bucket & "-" &
              Key & ".bin");
         Input : Stream_IO.File_Type;
      begin
         declare
            Result : constant Transfers.Download_Outcome :=
              Transfers.Download_File
                (HTTP, Origin, Bucket, Object_Key, Download_Path, Identity,
                 Timeout => 60.0);
         begin
            if Result.Kind /= Transfers.File_Downloaded
              or else Result.Status /= 200
              or else Result.Bytes /=
                Flyology.Object_Storage.Byte_Count (Expected'Length)
            then
               raise Program_Error with
                 "CopyObject publication oracle could not read " &
                 Object_Key;
            end if;
         end;
         Stream_IO.Open (Input, Stream_IO.In_File, Download_Path);
         if Stream_IO.Size (Input) /= Stream_IO.Count (Expected'Length) then
            raise Program_Error with
              "CopyObject publication oracle returned the wrong size";
         end if;
         declare
            Data  : Stream_Element_Array (1 .. 64 * 1_024);
            Last  : Stream_Element_Offset;
            Total : Natural := 0;
         begin
            loop
               Stream_IO.Read (Input, Data, Last);
               exit when Last < Data'First;
               for Index in Data'First .. Last loop
                  if Character'Val (Data (Index)) /=
                    Expected
                      (Expected'First + Total +
                         Natural (Index - Data'First))
                  then
                     raise Program_Error with
                       "CopyObject publication oracle changed body bytes";
                  end if;
               end loop;
               Total := Total + Natural (Last - Data'First + 1);
            end loop;
            if Total /= Expected'Length then
               raise Program_Error with
                 "CopyObject publication oracle returned the wrong length";
            end if;
         end;
         Stream_IO.Close (Input);
         Ada.Directories.Delete_File (Download_Path);
      exception
         when others =>
            if Stream_IO.Is_Open (Input) then
               Stream_IO.Close (Input);
            end if;
            if Ada.Directories.Exists (Download_Path) then
               Ada.Directories.Delete_File (Download_Path);
            end if;
            raise;
      end Require_Exact_Object;

      procedure Require_Object_Absent (Object_Key : String) is
         Outcome : constant Transfers.Head_Outcome :=
           Transfers.Head_Object
             (HTTP, Origin, Bucket, Object_Key, Identity, Timeout => 30.0);
      begin
         if Outcome.Kind /= Transfers.Head_Rejected
           or else Outcome.Status /= 404
         then
            raise Program_Error with
              "DeleteObjects absence oracle still found " & Object_Key;
         end if;
      end Require_Object_Absent;

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

         function Checksum_Count
           (Value : Attributes.Checksum_Values) return Natural is
           (Boolean'Pos (US.Length (Value.CRC32) > 0) +
            Boolean'Pos (US.Length (Value.CRC32C) > 0) +
            Boolean'Pos (US.Length (Value.CRC64NVME) > 0) +
            Boolean'Pos (US.Length (Value.SHA1) > 0) +
            Boolean'Pos (US.Length (Value.SHA256) > 0) +
            Boolean'Pos (US.Length (Value.SHA512) > 0) +
            Boolean'Pos (US.Length (Value.MD5) > 0) +
            Boolean'Pos (US.Length (Value.XXHASH64) > 0) +
            Boolean'Pos (US.Length (Value.XXHASH3) > 0) +
            Boolean'Pos (US.Length (Value.XXHASH128) > 0));
      begin
         Parameters.Has_Max_Parts := True;
         Parameters.Max_Parts := 1;
         Parameters.Has_Part_Number_Marker := True;
         Parameters.Part_Number_Marker := 0;
         Parameters.Attributes :=
           (Entity_Tag => True,
            Checksum => True,
            Object_Parts => Multipart_Checksum_Oracle_Mode /=
              RustFS_RC3_Multipart_Checksum_Divergence,
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
            end if;

            case Multipart_Checksum_Oracle_Mode is
               when Complete_Multipart_Checksums |
                    RustFS_RC3_Multipart_Checksum_Divergence =>
                  if not Outcome.Result.Attributes.Has_Checksum
                    or else Checksum_Count
                      (Outcome.Result.Attributes.Checksum) /= 1
                    or else US.To_String
                      (Outcome.Result.Attributes.Checksum.SHA256) /=
                        Composite_SHA256_Object
                    or else US.To_String
                      (Outcome.Result.Attributes.Checksum.Kind) /=
                        "COMPOSITE"
                  then
                     raise Program_Error with
                       "S3 implementation returned invalid object " &
                       "attributes checksum";
                  end if;
               when SeaweedFS_443_Multipart_Checksum_Divergence =>
                  if Outcome.Result.Attributes.Has_Checksum then
                     raise Program_Error with
                       "SeaweedFS checksum omission changed";
                  end if;
            end case;

            if Multipart_Checksum_Oracle_Mode /=
                RustFS_RC3_Multipart_Checksum_Divergence
            then
               if not Outcome.Result.Attributes.Has_Object_Parts
                 or else not Outcome.Result.Attributes.Object_Parts.
                   Total_Parts_Count.Is_Set
                 or else Outcome.Result.Attributes.Object_Parts.
                   Total_Parts_Count.Value /= 2
                 or else Outcome.Result.Attributes.Object_Parts.Parts.Length /=
                   1
                 or else Outcome.Result.Attributes.Object_Parts.Parts.
                   First_Element.Number.Value /= 1
                 or else Outcome.Result.Attributes.Object_Parts.Parts.
                   First_Element.Size.Value /=
                     Flyology.Object_Storage.Byte_Count (5 * 1_024 * 1_024)
                 or else
                   (case Multipart_Checksum_Oracle_Mode is
                      when Complete_Multipart_Checksums =>
                        Checksum_Count
                          (Outcome.Result.Attributes.Object_Parts.Parts.
                             First_Element.Checksums) /= 1
                        or else US.To_String
                          (Outcome.Result.Attributes.Object_Parts.Parts.
                             First_Element.Checksums.SHA256) /= First_SHA256,
                      when SeaweedFS_443_Multipart_Checksum_Divergence =>
                        Checksum_Count
                          (Outcome.Result.Attributes.Object_Parts.Parts.
                             First_Element.Checksums) /= 0,
                      when RustFS_RC3_Multipart_Checksum_Divergence => False)
               then
                  raise Program_Error with
                    "S3 implementation returned invalid completed-part " &
                    "attributes";
               end if;
            end if;
         end;

         if Multipart_Checksum_Oracle_Mode =
           RustFS_RC3_Multipart_Checksum_Divergence
         then
            Parameters.Attributes :=
              (Object_Parts => True, others => False);
            declare
               Rejected : Boolean := False;
            begin
               begin
                  declare
                     Prepared : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Get_Object_Attributes
                         (Origin, Low_Level.Path_Style, Bucket, Key,
                          Parameters, Identity, "us-east-1", Timestamp);
                     Ignored : constant
                       Low_Level.Get_Object_Attributes_Outcome :=
                         Low_Level.Execute_Get_Object_Attributes
                           (HTTP, Prepared, Timeout => 30.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Rejected := True;
               end;
               if not Rejected then
                  raise Program_Error with
                    "RustFS malformed part checksum response changed";
               end if;
            end;
         end if;

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
         Size : Flyology.Object_Storage.Byte_Count;
         Expected_SHA256 : String := "")
      is
         Parameters : Low_Level.List_Parts_Parameters;

         function Bare_ETag (Value : String) return String is
           (if Value'Length >= 2
              and then Value (Value'First) = '"'
              and then Value (Value'Last) = '"'
            then Value (Value'First + 1 .. Value'Last - 1)
            else Value);

         function Checksum_Count
           (Value : Multipart.Listed_Part) return Natural is
           (Boolean'Pos (US.Length (Value.Checksum_CRC32) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_CRC32C) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_CRC64NVME) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_SHA1) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_SHA256) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_SHA512) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_MD5) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_XXHASH64) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_XXHASH3) > 0) +
            Boolean'Pos (US.Length (Value.Checksum_XXHASH128) > 0));
      begin
         Parameters.Max_Parts := 1;
         Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
         declare
            Outcome : constant Low_Level.List_Parts_Outcome :=
              Transfers.List_Parts_Page
                (HTTP, Origin, Bucket, Object_Key, Parameters, Identity,
                 Timeout => 30.0);
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
            elsif Expected_SHA256'Length > 0
              and then
                (case Multipart_Checksum_Oracle_Mode is
                   when Complete_Multipart_Checksums =>
                     US.To_String
                       (Outcome.Result.Listing.Checksum_Algorithm) /=
                         "SHA256"
                     or else US.To_String
                       (Outcome.Result.Listing.Checksum_Type) /= "COMPOSITE"
                     or else Checksum_Count
                       (Outcome.Result.Listing.Parts.First_Element) /= 1
                     or else US.To_String
                       (Outcome.Result.Listing.Parts.First_Element.
                          Checksum_SHA256) /= Expected_SHA256,
                   when RustFS_RC3_Multipart_Checksum_Divergence |
                        SeaweedFS_443_Multipart_Checksum_Divergence =>
                     US.Length
                       (Outcome.Result.Listing.Checksum_Algorithm) /= 0
                     or else US.Length
                       (Outcome.Result.Listing.Checksum_Type) /= 0
                     or else Checksum_Count
                       (Outcome.Result.Listing.Parts.First_Element) /= 0)
            then
               raise Program_Error with
                 "S3 implementation ListParts checksum mismatch: algorithm=" &
                 US.To_String
                   (Outcome.Result.Listing.Checksum_Algorithm) &
                 " type=" &
                 US.To_String (Outcome.Result.Listing.Checksum_Type) &
                 " checksum=" & US.To_String
                   (Outcome.Result.Listing.Parts.First_Element.
                      Checksum_SHA256);
            end if;
         end;
      end Require_Listed_Part;

      procedure Require_Two_Listed_Parts
        (Object_Key, Upload_ID : String) is
         Parameters : Low_Level.List_Parts_Parameters;
         First_Number : S3_Core.Part_Number;
      begin
         Parameters.Max_Parts := 1;
         Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
         declare
            First : constant Low_Level.List_Parts_Outcome :=
              Transfers.List_Parts_Page
                (HTTP, Origin, Bucket, Object_Key, Parameters, Identity,
                 Timeout => 30.0);
         begin
            if First.Kind /= Low_Level.Parts_Listed
              or else Natural (First.Result.Listing.Parts.Length) /= 1
              or else not First.Result.Listing.Is_Truncated
              or else First.Result.Listing.Next_Part_Number_Marker /=
                First.Result.Listing.Parts.First_Element.Number
            then
               raise Program_Error with
                 "S3 implementation ListParts first continuation mismatch";
            end if;
            First_Number := First.Result.Listing.Parts.First_Element.Number;
            Parameters.Part_Number_Marker :=
              First.Result.Listing.Next_Part_Number_Marker;
         end;
         declare
            Second : constant Low_Level.List_Parts_Outcome :=
              Transfers.List_Parts_Page
                (HTTP, Origin, Bucket, Object_Key, Parameters, Identity,
                 Timeout => 30.0);
         begin
            if Second.Kind /= Low_Level.Parts_Listed
              or else Natural (Second.Result.Listing.Parts.Length) /= 1
              or else Second.Result.Listing.Is_Truncated
              or else Second.Result.Listing.Parts.First_Element.Number <=
                First_Number
            then
               raise Program_Error with
                 "S3 implementation ListParts second continuation mismatch";
            end if;
         end;
      end Require_Two_Listed_Parts;

      procedure Require_Listed_Upload
        (Object_Key, Upload_ID : String; Present : Boolean)
      is
         Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Object_Key);
         Parameters.Max_Uploads := 1;
         declare
            Outcome : constant Low_Level.List_Multipart_Uploads_Outcome :=
              Transfers.List_Multipart_Uploads_Page
                (HTTP, Origin, Bucket, Parameters, Identity,
                 Timeout => 30.0);
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
         Parameters : Low_Level.Create_Multipart_Parameters;
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Transfers.Create_Multipart_Upload
             (HTTP, Origin, Bucket, Copy_Key, Parameters, Identity,
              Timeout => 30.0);
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
            Rejected : Boolean := False;
         begin
            begin
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Copy_Object
                      (Origin, Low_Level.Path_Style, Bucket, Copy_Key,
                       Parameters, Identity, "us-east-1", Timestamp);
                  Copied : constant Low_Level.Copy_Object_Outcome :=
                    Low_Level.Execute_Copy_Object
                      (HTTP, Prepared, Timeout => 60.0);
               begin
                  if Copy_Object_Oracle_Mode /= Complete_Copy_Object then
                     raise Program_Error with
                       "malformed CopyObject result was accepted";
                  elsif Copied.Kind /= Low_Level.Object_Copied
                    or else US.Length
                      (Copied.Result.Copy_Result.Entity_Tag) = 0
                    or else US.Length
                      (Copied.Result.Copy_Result.Last_Modified) = 0
                  then
                     raise Program_Error with
                       "S3 implementation rejected typed CopyObject";
                  end if;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  if Copy_Object_Oracle_Mode = Complete_Copy_Object then
                     raise;
                  end if;
                  Rejected := True;
            end;
            if Copy_Object_Oracle_Mode /= Complete_Copy_Object
              and then not Rejected
            then
               raise Program_Error with
                 "malformed CopyObject result was not rejected";
            end if;
         end;
         Require_Exact_Object (Copy_Key, Payload);
         declare
            Rejected : Boolean := False;
         begin
            begin
               declare
                  Copied : constant Transfers.Copy_Outcome :=
                    Transfers.Copy_Object
                      (HTTP, Origin, Bucket, Key & "-high level+%25", Bucket,
                       Convenience_Key, Identity, Timeout => 60.0);
               begin
                  if Copy_Object_Oracle_Mode /= Complete_Copy_Object then
                     raise Program_Error with
                       "malformed high-level CopyObject result was accepted";
                  elsif Copied.Kind = Transfers.Copy_Rejected then
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
            exception
               when Low_Level.Invalid_Response =>
                  if Copy_Object_Oracle_Mode = Complete_Copy_Object then
                     raise;
                  end if;
                  Rejected := True;
            end;
            if Copy_Object_Oracle_Mode /= Complete_Copy_Object
              and then not Rejected
            then
               raise Program_Error with
                 "malformed high-level CopyObject result was not rejected";
            end if;
         end;
         Require_Exact_Object (Convenience_Key, Payload);
      end Copy_Whole_Object;

      procedure Delete_Many is
         First_Key  : constant String := Key & "-delete-many-a";
         Second_Key : constant String := Key & "-delete-many-b";
         Request    : Deletions.Delete_Objects_Request;
         Parameters : Low_Level.Delete_Objects_Parameters;

         procedure Create_Copy (Destination : String) is
            Rejected : Boolean := False;
         begin
            begin
               declare
                  Copied : constant Transfers.Copy_Outcome :=
                    Transfers.Copy_Object
                      (HTTP, Origin, Bucket, Key, Bucket, Destination,
                       Identity, Timeout => 60.0);
               begin
                  if Copy_Object_Oracle_Mode /= Complete_Copy_Object then
                     raise Program_Error with
                       "malformed setup CopyObject result was accepted";
                  elsif Copied.Kind /= Transfers.Object_Copied then
                     raise Program_Error with
                       "S3 implementation could not set up DeleteObjects";
                  end if;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  if Copy_Object_Oracle_Mode = Complete_Copy_Object then
                     raise;
                  end if;
                  Rejected := True;
            end;
            if Copy_Object_Oracle_Mode /= Complete_Copy_Object
              and then not Rejected
            then
               raise Program_Error with
                 "malformed setup CopyObject result was not rejected";
            end if;
            Require_Exact_Object (Destination, Payload);
         end Create_Copy;
      begin
         Create_Copy (First_Key);
         Create_Copy (Second_Key);
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String (First_Key),
               Version_ID => US.Null_Unbounded_String,
               others     => <>));
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String (Second_Key),
               Version_ID => US.Null_Unbounded_String,
               others     => <>));
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
         Require_Object_Absent (First_Key);
         Require_Object_Absent (Second_Key);
      end Delete_Many;

      procedure Require_Conditional_Put is
         First_Value : aliased constant String := "conditional-first";
         Collision_Value : aliased constant String :=
           "conditional-collision";
         Second_Value : aliased constant String := "conditional-second";
         Stale_Value : aliased constant String := "conditional-stale";
         Object_Key : constant String := Key & "-conditional-put";

         function Put
           (Value         : not null access constant String;
            If_Match      : String := "";
            If_None_Match : String := "")
            return Low_Level.Put_Object_Outcome
         is
            Parameters : Low_Level.Put_Object_Parameters;
            Source     : Upload_Source (Value);
         begin
            Parameters.If_Match := US.To_Unbounded_String (If_Match);
            Parameters.If_None_Match :=
              US.To_Unbounded_String (If_None_Match);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Object
                   (Origin, Low_Level.Path_Style, Bucket, Object_Key,
                    Parameters, SigV4.SHA256_Hex (Value.all), Identity,
                    "us-east-1", Timestamp);
            begin
               return Low_Level.Execute_Put_Object
                 (HTTP, Prepared, Source, Timeout => 30.0);
            end;
         end Put;

         procedure Require_Body
           (Expected_Body, Expected_ETag : String)
         is
            Parameters : constant Low_Level.Get_Object_Parameters :=
              (If_Match => US.To_Unbounded_String (Expected_ETag),
               others   => <>);
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, Bucket, Object_Key,
                 Parameters, Identity, "us-east-1", Timestamp);
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (HTTP, Prepared, Timeout => 30.0);
            Result : constant Low_Level.Get_Object_Head_Outcome :=
              Low_Level.Decode_Get_Object_Response_Head (Response);
            Received : US.Unbounded_String;
            Buffer : Stream_Element_Array (1 .. 8);
            Last : Stream_Element_Offset;
            Finished : Boolean := False;
         begin
            if Result.Kind /= Low_Level.Object_Opened
              or else Result.Status /= 200
              or else US.To_String (Result.Result.Entity_Tag) /= Expected_ETag
            then
               raise Program_Error with
                 "conditional PutObject returned the wrong generation";
            end if;
            while not Finished loop
               HTTP_Client.Read_Body (Response, Buffer, Last, Finished);
               for Index in Buffer'First .. Last loop
                  US.Append (Received, Character'Val (Buffer (Index)));
               end loop;
            end loop;
            if US.To_String (Received) /= Expected_Body then
               raise Program_Error with
                 "conditional PutObject changed the committed bytes";
            end if;
         end Require_Body;

         procedure Require_Stale_Get_Rejected
           (Expected_ETag : String)
         is
            Parameters : constant Low_Level.Get_Object_Parameters :=
              (If_Match => US.To_Unbounded_String (Expected_ETag),
               others   => <>);
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, Bucket, Object_Key,
                 Parameters, Identity, "us-east-1", Timestamp);
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (HTTP, Prepared, Timeout => 30.0);
            Result : constant Low_Level.Get_Object_Head_Outcome :=
              Low_Level.Decode_Get_Object_Response_Head (Response);
         begin
            case Conditional_Get_Oracle_Mode is
               when Complete_Conditional_Get =>
                  if Result.Kind /= Low_Level.Get_Object_Rejected
                    or else Result.Status /= 412
                    or else US.To_String (Result.Error.Code) /=
                      "PreconditionFailed"
                  then
                     raise Program_Error with
                       "S3 implementation accepted stale " &
                       "generation-bound Get";
                  end if;
               when RustFS_RC3_Bodyless_Stale_Get_412 =>
                  if Result.Kind /= Low_Level.Get_Object_Rejected
                    or else Result.Status /= 412
                    or else US.To_String (Result.Error.Code) /= "HTTP412"
                  then
                     raise Program_Error with
                       "pinned RustFS bodyless stale If-Match 412 changed";
                  end if;
            end case;
         end Require_Stale_Get_Rejected;

         Created : constant Low_Level.Put_Object_Outcome :=
           Put (First_Value'Access, If_None_Match => "*");
      begin
         if Created.Kind /= Low_Level.Object_Put
           or else Created.Status /= 200
           or else US.Length (Created.Result.Entity_Tag) = 0
         then
            raise Program_Error with
              "S3 implementation rejected create-if-absent PutObject";
         end if;
         declare
            First_ETag : constant String :=
              US.To_String (Created.Result.Entity_Tag);
            Collision : constant Low_Level.Put_Object_Outcome :=
              Put (Collision_Value'Access, If_None_Match => "*");
         begin
            if Collision.Kind /= Low_Level.Put_Object_Rejected
              or else Collision.Status /= 412
            then
               raise Program_Error with
                 "S3 implementation accepted an If-None-Match collision";
            end if;
            Require_Body (First_Value, First_ETag);
            declare
               Replaced : constant Low_Level.Put_Object_Outcome :=
                 Put (Second_Value'Access, If_Match => First_ETag);
            begin
               if Replaced.Kind /= Low_Level.Object_Put
                 or else Replaced.Status /= 200
                 or else US.Length (Replaced.Result.Entity_Tag) = 0
               then
                  raise Program_Error with
                    "S3 implementation rejected matching If-Match";
               end if;
               declare
                  Second_ETag : constant String :=
                    US.To_String (Replaced.Result.Entity_Tag);
                  Stale : constant Low_Level.Put_Object_Outcome :=
                    Put (Stale_Value'Access, If_Match => First_ETag);
               begin
                  if Stale.Kind /= Low_Level.Put_Object_Rejected
                    or else Stale.Status /= 412
                  then
                     raise Program_Error with
                       "S3 implementation accepted stale If-Match";
                  end if;
                  Require_Stale_Get_Rejected (First_ETag);
                  Require_Body (Second_Value, Second_ETag);
               end;
            end;
         end;
      end Require_Conditional_Put;

      procedure Require_Complete_Put_Tuple is
         Object_Key : constant String := Key & "-complete-put-tuple";
         Options    : Client_Objects.Complete_Put_Options;
         Source     : Upload_Source (Payload'Access);

         function Has_Metadata
           (Values : Low_Level.Metadata_Entry_Vectors.Vector;
            Name, Value : String) return Boolean
         is
         begin
            for Item of Values loop
               if US.To_String (Item.Name) = Name
                 and then US.To_String (Item.Value) = Value
               then
                  return True;
               end if;
            end loop;
            return False;
         end Has_Metadata;

         procedure Require_Metadata
           (Result : Low_Level.Head_Object_Result)
         is
            procedure Require
              (Name, Actual, Expected : String) is
            begin
               if Actual /= Expected then
                  raise Program_Error with
                    "S3 implementation changed complete PutObject " & Name &
                    ": expected=" & Expected & " actual=" & Actual;
               end if;
            end Require;
         begin
            if Result.Content_Length /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
            then
               raise Program_Error with
                 "S3 implementation changed complete PutObject size";
            end if;
            Require
              ("Content-Type", US.To_String (Result.Content_Type),
               "application/octet-stream");
            Require
              ("Cache-Control", US.To_String (Result.Cache_Control),
               "public, max-age=60");
            Require
              ("Content-Disposition",
               US.To_String (Result.Content_Disposition),
               "attachment; filename=oracle.bin");
            Require
              ("Content-Encoding", US.To_String (Result.Content_Encoding),
               "identity");
            Require
              ("Content-Language", US.To_String (Result.Content_Language),
               "en-CA");
            Require
              ("SHA256 checksum", US.To_String (Result.Checksum_SHA256),
               Full_SHA256);
            Require
              ("checksum type", US.To_String (Result.Checksum_Type),
               (case Put_Object_Oracle_Mode is
                   when Complete_Put_Object => "FULL_OBJECT",
                   when RustFS_RC3_Omits_Checksum_Type |
                        SeaweedFS_443_Omits_Checksum_Type => ""));
            if Natural (Result.Metadata.Length) /= 2
              or else not Has_Metadata
                (Result.Metadata, "project", "flyology-object-storage")
              or else not Has_Metadata
                (Result.Metadata, "purpose", "put-object-oracle")
            then
               raise Program_Error with
                 "S3 implementation changed complete PutObject user " &
                 "metadata";
            end if;
         end Require_Metadata;
      begin
         Options.Content_Type :=
           US.To_Unbounded_String ("application/octet-stream");
         Options.Metadata.Cache_Control :=
           (Is_Set => True,
            Value  => US.To_Unbounded_String ("public, max-age=60"));
         Options.Metadata.Content_Disposition :=
           (Is_Set => True,
            Value  =>
              US.To_Unbounded_String ("attachment; filename=oracle.bin"));
         Options.Metadata.Content_Encoding :=
           (Is_Set => True,
            Value  => US.To_Unbounded_String ("identity"));
         Options.Metadata.Content_Language :=
           (Is_Set => True, Value => US.To_Unbounded_String ("en-CA"));
         Options.Metadata.User.Length := 2;
         Options.Metadata.User.Items (1) :=
           (Key   => US.To_Unbounded_String ("project"),
            Value => US.To_Unbounded_String ("flyology-object-storage"));
         Options.Metadata.User.Items (2) :=
           (Key   => US.To_Unbounded_String ("purpose"),
            Value => US.To_Unbounded_String ("put-object-oracle"));
         Options.Tags.Length := 2;
         Options.Tags.Items (1) :=
           (Key   => US.To_Unbounded_String ("operation"),
            Value => US.To_Unbounded_String ("PutObject"));
         Options.Tags.Items (2) :=
           (Key   => US.To_Unbounded_String ("scope"),
            Value => US.To_Unbounded_String ("complete tuple"));
         Options.Checksum :=
           (Algorithm => Flyology.Object_Storage.Checksum_SHA256,
            Method    => Flyology.Object_Storage.Full_Object_Checksum,
            Value     => US.To_Unbounded_String (Full_SHA256));
         Options.Conditions.If_None_Match := US.To_Unbounded_String ("*");

         declare
            Published : constant Client_Objects.Complete_Put_Outcome :=
              Client_Objects.Put_Object
                (HTTP, Origin, Bucket, Object_Key, Source,
                 SigV4.SHA256_Hex (Payload), Identity, Options,
                 Timeout => 60.0);
         begin
            if Published.Kind /= Low_Level.Object_Put
              or else Published.Status /= 200
              or else US.Length (Published.Result.Entity_Tag) = 0
              or else US.To_String (Published.Result.Checksum_SHA256) /=
                Full_SHA256
              or else US.To_String (Published.Result.Checksum_Type) /=
                "FULL_OBJECT"
            then
               raise Program_Error with
                 "S3 implementation rejected complete PutObject tuple";
            end if;

            declare
               Parameters : Low_Level.Head_Object_Parameters;
            begin
               Parameters.Checksum_Mode := True;
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Head_Object
                      (Origin, Low_Level.Path_Style, Bucket, Object_Key,
                       Parameters, Identity, "us-east-1", Timestamp);
                  Head : constant Low_Level.Head_Object_Outcome :=
                    Low_Level.Execute_Head_Object
                      (HTTP, Prepared, Timeout => 30.0);
               begin
                  if Head.Kind /= Low_Level.Object_Found
                    or else Head.Status /= 200
                    or else Head.Result.Entity_Tag /=
                      Published.Result.Entity_Tag
                  then
                     raise Program_Error with
                       "S3 implementation changed complete PutObject HEAD " &
                       "generation";
                  end if;
                  Require_Metadata (Head.Result);
               end;
            end;

            declare
               Parameters : Low_Level.Get_Object_Parameters;
               Received   : US.Unbounded_String;
               Buffer     : Stream_Element_Array (1 .. 64 * 1_024);
               Last       : Stream_Element_Offset;
               Finished   : Boolean := False;
            begin
               Parameters.If_Match := Published.Result.Entity_Tag;
               Parameters.Checksum_Mode := True;
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Get_Object
                      (Origin, Low_Level.Path_Style, Bucket, Object_Key,
                       Parameters, Identity, "us-east-1", Timestamp);
                  Response : HTTP_Client.Response :=
                    Low_Level.Execute_Get_Object
                      (HTTP, Prepared, Timeout => 60.0);
                  Opened : constant Low_Level.Get_Object_Head_Outcome :=
                    Low_Level.Decode_Get_Object_Response_Head (Response);
               begin
                  if Opened.Kind /= Low_Level.Object_Opened
                    or else Opened.Status /= 200
                    or else Opened.Result.Entity_Tag /=
                      Published.Result.Entity_Tag
                    or else not Opened.Result.Content_Length.Is_Set
                    or else Opened.Result.Content_Length.Value /=
                      Flyology.Object_Storage.Byte_Count (Payload'Length)
                    or else US.To_String (Opened.Result.Checksum_SHA256) /=
                      Full_SHA256
                    or else US.To_String (Opened.Result.Checksum_Type) /=
                      (case Put_Object_Oracle_Mode is
                          when Complete_Put_Object => "FULL_OBJECT",
                          when RustFS_RC3_Omits_Checksum_Type |
                               SeaweedFS_443_Omits_Checksum_Type => "")
                  then
                     raise Program_Error with
                       "S3 implementation changed generation-bound " &
                       "PutObject GET tuple";
                  end if;
                  while not Finished loop
                     HTTP_Client.Read_Body
                       (Response, Buffer, Last, Finished);
                     for Index in Buffer'First .. Last loop
                        US.Append
                          (Received, Character'Val (Buffer (Index)));
                     end loop;
                  end loop;
                  if US.To_String (Received) /= Payload then
                     raise Program_Error with
                       "S3 implementation changed complete PutObject bytes";
                  end if;
               end;
            end;

            declare
               Tagging : constant Client_Objects.Tagging_Outcome :=
                 Client_Objects.Get_Tags
                   (HTTP, Origin, Bucket, Object_Key, Identity,
                    Timeout => 30.0);
            begin
               if Tagging.Kind /= Client_Objects.Tags_Read
                 or else Tagging.Result.Tags /= Options.Tags
               then
                  raise Program_Error with
                    "S3 implementation changed complete PutObject tags";
               end if;
            end;
         end;
      end Require_Complete_Put_Tuple;
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
         Created : constant Scoped.Create_Multipart_Result :=
           Transfers.Create_Multipart_Upload
             (HTTP, Origin, Bucket, Key, Composite_Create_Parameters,
              Identity, Timeout => 30.0);
      begin
         if Created.Kind /= Scoped.Create_Multipart_Response_Available
           or else Created.Disposition /= Scoped.Multipart_Upload_Created
           or else Created.Response.Kind /= Low_Level.Created
         then
            raise Program_Error with
              "S3 implementation rejected CreateMultipartUpload";
         end if;
         declare
            Upload_ID : constant String :=
              US.To_String (Created.Response.Result.Upload_ID);
            First_Length : constant Natural := 5 * 1_024 * 1_024;
            Second_First : constant Positive :=
              Payload'First + First_Length;
            Second_Length : constant Natural := Payload'Length - First_Length;

            function Upload
              (Number : S3_Core.Part_Number;
               First  : Positive;
               Length : Natural)
               return US.Unbounded_String
            is
               Parameters : Low_Level.Upload_Part_Parameters;
               --  Derived test geometry: one acquired token contains this
               --  exact multipart range and no second body can be in flight.
               Pool : aliased Buffers.Pool
                 (Block_Size => Length, Capacity => 1);
               Payload_Buffer : Buffers.Unique_Buffer (Pool'Access);

               procedure Fill
                 (Data : in out Ada.Streams.Stream_Element_Array;
                  Used : in out Natural) is
               begin
                  for Offset in 0 .. Length - 1 loop
                     Data
                       (Data'First +
                          Ada.Streams.Stream_Element_Offset (Offset)) :=
                       Ada.Streams.Stream_Element
                         (Character'Pos (Payload (First + Offset)));
                  end loop;
                  Used := Length;
               end Fill;
            begin
               Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
               Parameters.Part_Number := Number;
               Parameters.Checksum_Algorithm :=
                 US.To_Unbounded_String ("SHA256");
               Parameters.Checksum_SHA256 := US.To_Unbounded_String
                 (if Number = 1 then First_SHA256 else Second_SHA256);
               Parameters.Payload_SHA256 := US.To_Unbounded_String
                 (SigV4.SHA256_Hex
                    (Payload (First .. First + Length - 1)));
               Buffers.Acquire (Payload_Buffer);
               Buffers.With_Writable_Data (Payload_Buffer, Fill'Access);
               declare
                  Uploaded : constant Scoped.Upload_Part_Result :=
                    Transfers.Upload_Part
                      (HTTP, Origin, Bucket, Key, Parameters, Payload_Buffer,
                       Identity, "us-east-1", Low_Level.Path_Style,
                       Timeout => 60.0);
               begin
                  if Uploaded.Kind /=
                    Scoped.Upload_Part_Response_Available
                    or else Uploaded.Disposition /= Scoped.Part_Published
                    or else Uploaded.Response.Kind /= Low_Level.Part_Uploaded
                    or else not Buffers.Has_Buffer (Payload_Buffer)
                  then
                     raise Program_Error with
                       "S3 implementation rejected UploadPart" &
                       Number'Image;
                  elsif US.To_String
                    (Uploaded.Response.Result.Checksum_SHA256) /=
                    (if Number = 1 then First_SHA256 else Second_SHA256)
                  then
                     raise Program_Error with
                       "S3 implementation UploadPart checksum mismatch" &
                       Number'Image;
                  end if;
                  return Uploaded.Response.Result.Entity_Tag;
               end;
            end Upload;
         begin
            if Check_List_Multipart_Uploads then
               Require_Listed_Upload (Key, Upload_ID, True);
            end if;
            declare
               First_ETag : constant US.Unbounded_String :=
                 Upload (1, Payload'First, First_Length);
            begin
               Require_Listed_Part
                 (Key, Upload_ID, US.To_String (First_ETag),
                  Flyology.Object_Storage.Byte_Count (First_Length),
                  First_SHA256);
               declare
                  Second_ETag : constant US.Unbounded_String :=
                    Upload (2, Second_First, Second_Length);
                  Completion : Multipart.Complete_Multipart_Upload_Request;
               begin
                  if Check_List_Parts_Pagination then
                     Require_Two_Listed_Parts (Key, Upload_ID);
                  end if;
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 1,
                        Entity_Tag => First_ETag,
                        Checksum_SHA256 =>
                          US.To_Unbounded_String (First_SHA256),
                        others     => <>));
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 2,
                        Entity_Tag => Second_ETag,
                        Checksum_SHA256 =>
                          US.To_Unbounded_String (Second_SHA256),
                        others     => <>));
                  declare
                     Prepared_Complete : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Complete_Multipart_Upload
                         (Origin, Low_Level.Path_Style, Bucket, Key,
                          Upload_ID, Completion,
                          Composite_Complete_Parameters, Identity,
                          "us-east-1", Timestamp);
                     Completed : constant
                       Low_Level.Complete_Multipart_Outcome :=
                         Low_Level.Execute_Complete_Multipart_Upload
                           (HTTP, Prepared_Complete, Timeout => 30.0);
                  begin
                     if Completed.Kind /= Low_Level.Completed
                       or else US.To_String (Completed.Result.Key) /= Key
                       or else
                         (case Multipart_Checksum_Oracle_Mode is
                            when Complete_Multipart_Checksums |
                                 RustFS_RC3_Multipart_Checksum_Divergence =>
                              US.To_String
                                (Completed.Result.Checksum_SHA256) /=
                                  Composite_SHA256_Object
                              or else
                                (US.Length
                                   (Completed.Result.Checksum_Type) > 0
                                 and then US.To_String
                                   (Completed.Result.Checksum_Type) /=
                                     "COMPOSITE"),
                            when
                              SeaweedFS_443_Multipart_Checksum_Divergence =>
                                US.Length
                                  (Completed.Result.Checksum_SHA256) /= 0
                                or else US.Length
                                  (Completed.Result.Checksum_Type) /= 0)
                     then
                        raise Program_Error with
                          "S3 implementation CompleteMultipartUpload " &
                          "checksum mismatch: kind=" & Completed.Kind'Image &
                          " status=" & Completed.Status'Image &
                          (if Completed.Kind = Low_Level.Completed
                           then " key=" & US.To_String (Completed.Result.Key) &
                             " checksum=" & US.To_String
                               (Completed.Result.Checksum_SHA256) &
                             " type=" & US.To_String
                               (Completed.Result.Checksum_Type)
                           else " code=" & US.To_String
                             (Completed.Error.Code) & " message=" &
                             US.To_String (Completed.Error.Message));
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
      Require_High_Level_List_Pagination;
      Delete_Many;
      Require_Conditional_Put;
      Require_Complete_Put_Tuple;
      declare
         Abort_Key : constant String := Key & "-aborted";
         Parameters : Low_Level.Create_Multipart_Parameters;
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Transfers.Create_Multipart_Upload
             (HTTP, Origin, Bucket, Abort_Key, Parameters, Identity,
              Timeout => 30.0);
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

   procedure Delete_Empty_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String);

   procedure Require_Bucket_Versioning
     (Origin : Flyology.HTTP.Origin; Bucket : String)
   is
      Probe      : constant String := Bucket & "-versioning";
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
   begin
      Create_Bucket (Origin, Probe, "");
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Initial : constant Client_Buckets.Get_Versioning_Outcome :=
           Client_Buckets.Get_Versioning
             (HTTP, Origin, Probe, Identity, Timeout => 30.0);
         Enabled : constant Client_Buckets.Set_Versioning_Outcome :=
           Client_Buckets.Set_Versioning_Configuration
             (HTTP, Origin, Probe,
              (Status => Flyology.Object_Storage.Versioning_Enabled,
               MFA_Delete =>
                 Flyology.Object_Storage.MFA_Delete_Unconfigured),
              Identity, Checksum_Algorithm => "SHA256",
              Timeout => 30.0);
         Enabled_Value : constant Client_Buckets.Get_Versioning_Outcome :=
           Client_Buckets.Get_Versioning
             (HTTP, Origin, Probe, Identity, Timeout => 30.0);
         Suspended : constant Client_Buckets.Set_Versioning_Outcome :=
           Client_Buckets.Set_Versioning
             (HTTP, Origin, Probe,
              Flyology.Object_Storage.Versioning_Suspended,
              Identity, Timeout => 30.0);
         Suspended_Value : constant Client_Buckets.Get_Versioning_Outcome :=
           Client_Buckets.Get_Versioning
             (HTTP, Origin, Probe, Identity, Timeout => 30.0);
      begin
         if Initial.Kind /= Client_Buckets.Versioning_Found
           or else
             Initial.Configuration.Status /=
               Flyology.Object_Storage.Versioning_Unconfigured
           or else Enabled.Kind /= Client_Buckets.Versioning_Updated
           or else Enabled_Value.Kind /= Client_Buckets.Versioning_Found
           or else
             Enabled_Value.Configuration.Status /=
               Flyology.Object_Storage.Versioning_Enabled
           or else Suspended.Kind /= Client_Buckets.Versioning_Updated
           or else Suspended_Value.Kind /= Client_Buckets.Versioning_Found
           or else
             Suspended_Value.Configuration.Status /=
               Flyology.Object_Storage.Versioning_Suspended
         then
            raise Program_Error with
              "bucket versioning configuration oracle mismatch";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
      Delete_Empty_Bucket (Origin, Probe, "");
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Require_Bucket_Versioning;

   type Durable_Routing_Phase is
     (Complete_Durable_Routing,
      Prepare_Durable_Restart,
      Verify_Durable_Restart);

   procedure Require_Durable_Version_Routing
     (Origin : Flyology.HTTP.Origin;
      Bucket, Timestamp : String;
      Phase : Durable_Routing_Phase)
   is
      --  Test-oracle identities: test-flyology-server.sh assigns these exact
      --  names to the authenticated endpoints whose catalogs survive a
      --  process restart.
      Implementation_Variable : constant String :=
        "FLYOLOGY_S3_IMPLEMENTATION";
      Files_Implementation  : constant String := "flyology-files";
      SQLite_Implementation : constant String := "flyology-sqlite";
   begin
      if not Ada.Environment_Variables.Exists (Implementation_Variable)
        or else
          Ada.Environment_Variables.Value (Implementation_Variable) not in
            Files_Implementation | SQLite_Implementation
      then
         if Phase = Complete_Durable_Routing then
            return;
         end if;
         raise Program_Error with
           "durable restart routing requires a persistent implementation";
      end if;

      declare
         Probe        : constant String := Bucket & "-durable-versions";
         Object_Key   : constant String := "retained/object";
         Batch_Key    : constant String := "retained/batch-peer";
         Copy_Key     : constant String := "retained/copied";
         Multipart_Key : constant String := "retained/multipart";
         First_Value  : aliased constant String := "durable-first";
         Second_Value : aliased constant String := "durable-second";
         Batch_Value  : aliased constant String := "durable-batch-peer";
         --  Test-reference size: a one-part completion may be below the
         --  nonfinal multipart minimum, while 4 KiB still crosses many source
         --  read boundaries without making the restart oracle expensive.
         Multipart_Value : aliased constant String :=
           String'(1 .. 4 * 1_024 => 'm');
         Multipart_Digest : constant Checksums.Digest_Value :=
           Repeated_Digest
             (Checksum_Policy.Core.SHA256, Multipart_Value'Length);
         Multipart_Checksum : constant String :=
           Checksums.Encode_Base64 (Multipart_Digest);
         Multipart_Composite : constant Checksums.Digest_Value :=
           Checksums.Composite
             (Checksum_Policy.Core.SHA256,
              Checksums.Digest_Array'(1 => Multipart_Digest));
         Multipart_Composite_Raw : constant String :=
           Checksums.Encode_Base64 (Multipart_Composite);
         Multipart_Composite_Object : constant String :=
           Checksums.Encode_Object
             (Multipart_Composite, Checksum_Policy.Composite, 1);
         HTTP         : aliased HTTP_Client.Client (Capacity => 1);
         Identity     : constant Low_Level.Credentials :=
           Low_Level.Make_Credentials (Access_Key, Secret_Key);
         First_ID     : US.Unbounded_String;
         Second_ID    : US.Unbounded_String;
         Batch_ID     : US.Unbounded_String;
         Copy_ID      : US.Unbounded_String;
         Marker_ID    : US.Unbounded_String;
         First_ETag   : US.Unbounded_String;
         --  Test-reference bound: each asserted page contains exactly the
         --  two retained entries under examination and must not truncate.
         Version_Page_Bound : constant S3_Core.Page_Size := 2;

         function Put
           (Key   : String;
            Value : not null access constant String)
            return Low_Level.Put_Object_Outcome
         is
            Source : Upload_Source (Value);
         begin
            return Client_Objects.Put_Object
              (HTTP, Origin, Probe, Key, Source,
               SigV4.SHA256_Hex (Value.all), Identity, Timeout => 30.0);
         end Put;

         procedure Require_Whole
           (Version_ID, Expected : String)
         is
            Result : constant Client_Objects.Whole_Get_Outcome :=
              Client_Objects.Get_Whole
                (HTTP, Origin, Probe, Object_Key, Expected'Length, Identity,
                 Version_ID => Version_ID, Timeout => 30.0);
         begin
            if Result.Kind /= Client_Objects.Whole_Object_Read
              or else Result.Status /= 200
              or else US.To_String (Result.Result.Version_ID) /= Version_ID
              or else Flyology.Bytes.To_Byte_String (Result.Object_Bytes) /=
                Expected
            then
               raise Program_Error with
                 "durable version-addressed GetObject mismatch";
            end if;
         end Require_Whole;

         procedure Require_Current
           (Version_ID, Expected : String)
         is
            Result : constant Client_Objects.Whole_Get_Outcome :=
              Client_Objects.Get_Whole
                (HTTP, Origin, Probe, Object_Key, Expected'Length, Identity,
                 Timeout => 30.0);
         begin
            if Result.Kind /= Client_Objects.Whole_Object_Read
              or else Result.Status /= 200
              or else US.To_String (Result.Result.Version_ID) /= Version_ID
              or else Flyology.Bytes.To_Byte_String (Result.Object_Bytes) /=
                Expected
            then
               raise Program_Error with
                 "durable current-generation GetObject mismatch";
            end if;
         end Require_Current;

         procedure Require_Attributes
           (Version_ID, Expected_Header_ETag : String;
            Expected_Size : Flyology.Object_Storage.Byte_Count)
         is
            Selection : constant
              Flyology.Object_Storage.S3.Attributes.Attribute_Selection :=
                (Entity_Tag => True, Object_Size => True, others => False);
            Outcome : constant Client_Objects.Get_Attributes_Outcome :=
              Client_Objects.Get_Attributes
                (HTTP, Origin, Probe, Object_Key, Identity,
                 Attributes => Selection, Version_ID => Version_ID,
                 Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Object_Attributes_Found
              or else Outcome.Status /= 200
              or else US.To_String (Outcome.Result.Version_ID) /= Version_ID
              or else not Outcome.Result.Attributes.Has_Entity_Tag
              or else '"' & US.To_String
                (Outcome.Result.Attributes.Entity_Tag) & '"' /=
                  Expected_Header_ETag
              or else not Outcome.Result.Attributes.Object_Size.Is_Set
              or else Outcome.Result.Attributes.Object_Size.Value /=
                Expected_Size
            then
               raise Program_Error with
                 "durable version-addressed GetObjectAttributes mismatch";
            end if;
         end Require_Attributes;

         procedure Require_Durable_Multipart is
            Upload_ID : US.Unbounded_String;
            Part_ETag : US.Unbounded_String;
         begin
            if Phase /= Verify_Durable_Restart then
               declare
                  Parameters : Low_Level.Create_Multipart_Parameters;
               begin
                  Parameters.Content_Type :=
                    US.To_Unbounded_String ("application/octet-stream");
                  Parameters.Checksum_Algorithm :=
                    US.To_Unbounded_String ("SHA256");
                  Parameters.Checksum_Type :=
                    US.To_Unbounded_String ("COMPOSITE");
                  declare
                     Created : constant Low_Level.Create_Multipart_Outcome :=
                       Transfers.Create_Multipart_Upload
                         (HTTP, Origin, Probe, Multipart_Key, Parameters,
                          Identity, Timeout => 30.0);
                  begin
                     if Created.Kind /= Low_Level.Created
                       or else Created.Status /= 200
                       or else US.Length (Created.Result.Upload_ID) = 0
                     then
                        raise Program_Error with
                          "durable CreateMultipartUpload mismatch";
                     end if;
                     Upload_ID := Created.Result.Upload_ID;
                  end;
               end;

               declare
                  Parameters : Low_Level.Upload_Part_Parameters;
                  Source     : Upload_Source (Multipart_Value'Access);
               begin
                  Parameters.Upload_ID := Upload_ID;
                  Parameters.Part_Number := 1;
                  Parameters.Payload_SHA256 := US.To_Unbounded_String
                    (SigV4.SHA256_Hex (Multipart_Value));
                  Parameters.Checksum_Algorithm :=
                    US.To_Unbounded_String ("SHA256");
                  Parameters.Checksum_SHA256 :=
                    US.To_Unbounded_String (Multipart_Checksum);
                  declare
                     Uploaded : constant Low_Level.Upload_Part_Outcome :=
                       Transfers.Upload_Part
                         (HTTP, Origin, Probe, Multipart_Key, Parameters,
                          Source, Identity, Timeout => 30.0);
                  begin
                     if Uploaded.Kind /= Low_Level.Part_Uploaded
                       or else Uploaded.Status /= 200
                       or else US.Length (Uploaded.Result.Entity_Tag) = 0
                       or else US.To_String
                         (Uploaded.Result.Checksum_SHA256) /=
                           Multipart_Checksum
                     then
                        raise Program_Error with
                          "durable UploadPart mismatch";
                     end if;
                  end;
               end;
            end if;

            declare
               Parameters : Low_Level.List_Multipart_Uploads_Parameters;
            begin
               Parameters.Prefix := US.To_Unbounded_String (Multipart_Key);
               Parameters.Max_Uploads := 1;
               declare
                  Listed : constant
                    Low_Level.List_Multipart_Uploads_Outcome :=
                      Transfers.List_Multipart_Uploads_Page
                        (HTTP, Origin, Probe, Parameters, Identity,
                         Timeout => 30.0);
               begin
                  if Listed.Kind /= Low_Level.Multipart_Uploads_Listed
                    or else Listed.Status /= 200
                    or else Listed.Result.Listing.Is_Truncated
                    or else Listed.Result.Listing.Uploads.Length /= 1
                    or else US.To_String
                      (Listed.Result.Listing.Uploads (1).Key) /= Multipart_Key
                    or else US.Length
                      (Listed.Result.Listing.Uploads (1).Upload_ID) = 0
                  then
                     raise Program_Error with
                       "durable multipart upload listing mismatch";
                  end if;
                  Upload_ID := Listed.Result.Listing.Uploads (1).Upload_ID;
               end;
            end;

            declare
               Parameters : Low_Level.List_Parts_Parameters;
            begin
               Parameters.Upload_ID := Upload_ID;
               Parameters.Max_Parts := 1;
               declare
                  Listed : constant Low_Level.List_Parts_Outcome :=
                    Transfers.List_Parts_Page
                      (HTTP, Origin, Probe, Multipart_Key, Parameters,
                       Identity, Timeout => 30.0);
               begin
                  if Listed.Kind /= Low_Level.Parts_Listed
                    or else Listed.Status /= 200
                    or else Listed.Result.Listing.Is_Truncated
                    or else Listed.Result.Listing.Parts.Length /= 1
                    or else Listed.Result.Listing.Parts (1).Number /= 1
                    or else Listed.Result.Listing.Parts (1).Size /=
                      Multipart_Value'Length
                    or else US.To_String
                      (Listed.Result.Listing.Parts (1).Checksum_SHA256) /=
                        Multipart_Checksum
                    or else US.Length
                      (Listed.Result.Listing.Parts (1).Entity_Tag) = 0
                  then
                     raise Program_Error with
                       "durable multipart part listing mismatch";
                  end if;
                  Part_ETag := Listed.Result.Listing.Parts (1).Entity_Tag;
               end;
            end;

            if Phase = Prepare_Durable_Restart then
               return;
            end if;

            declare
               Completion : Multipart.Complete_Multipart_Upload_Request;
               Parameters : Low_Level.Complete_Multipart_Parameters;
            begin
               Completion.Parts.Append
                 (Multipart.Completed_Part'
                    (Number          => 1,
                     Entity_Tag      => Part_ETag,
                     Checksum_SHA256 =>
                       US.To_Unbounded_String (Multipart_Checksum),
                     others          => <>));
               Parameters.Checksum_SHA256 :=
                 US.To_Unbounded_String (Multipart_Composite_Raw);
               Parameters.Checksum_Type :=
                 US.To_Unbounded_String ("COMPOSITE");
               Parameters.Mpu_Object_Size :=
                 (Is_Set => True, Value => Multipart_Value'Length);
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Complete_Multipart_Upload
                      (Origin, Low_Level.Path_Style, Probe, Multipart_Key,
                       US.To_String (Upload_ID), Completion, Parameters,
                       Identity, "us-east-1", Timestamp);
                  Completed : constant Low_Level.Complete_Multipart_Outcome :=
                    Low_Level.Execute_Complete_Multipart_Upload
                      (HTTP, Prepared, Timeout => 30.0);
               begin
                  if Completed.Kind /= Low_Level.Completed
                    or else Completed.Status /= 200
                    or else US.To_String (Completed.Result.Key) /=
                      Multipart_Key
                    or else US.To_String
                      (Completed.Result.Checksum_SHA256) /=
                        Multipart_Composite_Object
                    or else US.Length (Completed.Result.Version_ID) = 0
                  then
                     raise Program_Error with
                       "durable CompleteMultipartUpload mismatch: kind=" &
                       Completed.Kind'Image & " status=" &
                       Completed.Status'Image &
                       (if Completed.Kind = Low_Level.Completed
                        then " key=" & US.To_String (Completed.Result.Key) &
                          " checksum=" & US.To_String
                            (Completed.Result.Checksum_SHA256) &
                          " version=" & US.To_String
                            (Completed.Result.Version_ID)
                        else " code=" & US.To_String
                          (Completed.Error.Code));
                  end if;
                  declare
                     Whole : constant Client_Objects.Whole_Get_Outcome :=
                       Client_Objects.Get_Whole
                         (HTTP, Origin, Probe, Multipart_Key,
                          Multipart_Value'Length, Identity,
                          Version_ID =>
                            US.To_String (Completed.Result.Version_ID),
                          Timeout => 30.0);
                     Removed : constant Client_Objects.Delete_Outcome :=
                       Client_Objects.Delete
                         (HTTP, Origin, Probe, Multipart_Key, Identity,
                          Version_ID =>
                            US.To_String (Completed.Result.Version_ID),
                          Timeout => 30.0);
                  begin
                     if Whole.Kind /= Client_Objects.Whole_Object_Read
                       or else Whole.Status /= 200
                       or else Flyology.Bytes.To_Byte_String
                         (Whole.Object_Bytes) /= Multipart_Value
                       or else Removed.Kind /= Client_Objects.Object_Removed
                       or else Removed.Status /= 204
                     then
                        raise Program_Error with
                          "durable multipart completion bytes mismatch";
                     end if;
                  end;
               end;
            end;
         end Require_Durable_Multipart;
      begin
         HTTP_Client.Configure (HTTP, Origin);
         if Phase /= Verify_Durable_Restart then
            Create_Bucket (Origin, Probe, "");
            declare
               Enabled : constant Client_Buckets.Set_Versioning_Outcome :=
                 Client_Buckets.Set_Versioning
                   (HTTP, Origin, Probe,
                    Flyology.Object_Storage.Versioning_Enabled, Identity,
                    Timeout => 30.0);
            begin
               if Enabled.Kind /= Client_Buckets.Versioning_Updated then
                  raise Program_Error with
                    "durable version-routing bucket enablement failed";
               end if;
            end;

            declare
               First  : constant Low_Level.Put_Object_Outcome :=
                 Put (Object_Key, First_Value'Access);
               Second : constant Low_Level.Put_Object_Outcome :=
                 Put (Object_Key, Second_Value'Access);
               Batch : constant Low_Level.Put_Object_Outcome :=
                 Put (Batch_Key, Batch_Value'Access);
            begin
               if First.Kind /= Low_Level.Object_Put
                 or else First.Status /= 200
                 or else US.Length (First.Result.Version_ID) = 0
                 or else Second.Kind /= Low_Level.Object_Put
                 or else Second.Status /= 200
                 or else US.Length (Second.Result.Version_ID) = 0
                 or else First.Result.Version_ID = Second.Result.Version_ID
                 or else Batch.Kind /= Low_Level.Object_Put
                 or else Batch.Status /= 200
                 or else US.Length (Batch.Result.Version_ID) = 0
               then
                  raise Program_Error with
                    "durable version-routing PutObject generations mismatch";
               end if;
            end;
         end if;

         declare
            Page : constant Client_Objects.List_Versions_Outcome :=
              Client_Objects.List_Versions_Page
                (HTTP, Origin, Probe, Identity, Prefix => Object_Key,
                 Maximum => Version_Page_Bound, Timeout => 30.0);
         begin
            if Page.Kind /= Client_Objects.Page_Available
              or else Page.Status /= 200
              or else Page.Page.Is_Truncated
              or else Page.Page.Versions.Length /= 2
              or else not Page.Page.Delete_Markers.Is_Empty
              or else US.To_String (Page.Page.Versions (1).Key) /= Object_Key
              or else not Page.Page.Versions (1).Has_Version_ID
              or else US.Length (Page.Page.Versions (1).Version_ID) = 0
              or else not Page.Page.Versions (1).Is_Latest
              or else not Page.Page.Versions (2).Has_Version_ID
              or else US.Length (Page.Page.Versions (2).Version_ID) = 0
              or else Page.Page.Versions (1).Version_ID =
                Page.Page.Versions (2).Version_ID
              or else Page.Page.Versions (2).Is_Latest
              or else not Page.Page.Versions (2).Has_Entity_Tag
              or else US.Length (Page.Page.Versions (2).Entity_Tag) = 0
            then
               raise Program_Error with
                 "durable ListObjectVersions retained ordering mismatch";
            end if;
            Second_ID := Page.Page.Versions (1).Version_ID;
            First_ID := Page.Page.Versions (2).Version_ID;
            First_ETag := Page.Page.Versions (2).Entity_Tag;
         end;

         if Phase /= Verify_Durable_Restart then
            declare
               Parameters : Low_Level.Copy_Object_Parameters;
            begin
               Parameters.Copy_Source := US.To_Unbounded_String
                 (Probe & "/" & Object_Key & "?versionId=" &
                  US.To_String (First_ID));
               Parameters.Metadata_Directive :=
                 US.To_Unbounded_String ("COPY");
               Parameters.Tagging_Directive :=
                 US.To_Unbounded_String ("COPY");
               Parameters.Checksum_Algorithm :=
                 US.To_Unbounded_String ("SHA256");
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Copy_Object
                      (Origin, Low_Level.Path_Style, Probe, Copy_Key,
                       Parameters, Identity, "us-east-1", Timestamp);
                  Copied : constant Low_Level.Copy_Object_Outcome :=
                    Low_Level.Execute_Copy_Object
                      (HTTP, Prepared, Timeout => 30.0);
               begin
                  if Copied.Kind /= Low_Level.Object_Copied
                    or else Copied.Status /= 200
                    or else Copied.Result.Copy_Source_Version_ID /= First_ID
                    or else US.Length (Copied.Result.Version_ID) = 0
                    or else US.Length
                      (Copied.Result.Copy_Result.Entity_Tag) = 0
                    or else US.Length
                      (Copied.Result.Copy_Result.Checksum_SHA256) = 0
                  then
                     raise Program_Error with
                       "durable exact-source CopyObject mismatch";
                  end if;
               end;
            end;
         end if;

         declare
            --  Test-reference bound: the copied key has exactly one retained
            --  generation and the page must therefore be complete.
            Copy_Page_Bound : constant S3_Core.Page_Size := 1;
            Page : constant Client_Objects.List_Versions_Outcome :=
              Client_Objects.List_Versions_Page
                (HTTP, Origin, Probe, Identity, Prefix => Copy_Key,
                 Maximum => Copy_Page_Bound, Timeout => 30.0);
         begin
            if Page.Kind /= Client_Objects.Page_Available
              or else Page.Status /= 200
              or else Page.Page.Is_Truncated
              or else Page.Page.Versions.Length /= 1
              or else not Page.Page.Delete_Markers.Is_Empty
              or else US.To_String (Page.Page.Versions (1).Key) /= Copy_Key
              or else not Page.Page.Versions (1).Has_Version_ID
              or else US.Length (Page.Page.Versions (1).Version_ID) = 0
              or else not Page.Page.Versions (1).Is_Latest
            then
               raise Program_Error with
                 "durable copied generation listing mismatch";
            end if;
            Copy_ID := Page.Page.Versions (1).Version_ID;
         end;

         declare
            --  Test-reference bound: the peer key has exactly one retained
            --  generation and the page must therefore be complete.
            Batch_Page_Bound : constant S3_Core.Page_Size := 1;
            Page : constant Client_Objects.List_Versions_Outcome :=
              Client_Objects.List_Versions_Page
                (HTTP, Origin, Probe, Identity, Prefix => Batch_Key,
                 Maximum => Batch_Page_Bound, Timeout => 30.0);
         begin
            if Page.Kind /= Client_Objects.Page_Available
              or else Page.Status /= 200
              or else Page.Page.Is_Truncated
              or else Page.Page.Versions.Length /= 1
              or else not Page.Page.Delete_Markers.Is_Empty
              or else US.To_String (Page.Page.Versions (1).Key) /= Batch_Key
              or else not Page.Page.Versions (1).Has_Version_ID
              or else US.Length (Page.Page.Versions (1).Version_ID) = 0
              or else not Page.Page.Versions (1).Is_Latest
            then
               raise Program_Error with
                 "durable batch peer generation listing mismatch";
            end if;
            Batch_ID := Page.Page.Versions (1).Version_ID;
         end;

         Require_Whole (US.To_String (First_ID), First_Value);
         Require_Current (US.To_String (Second_ID), Second_Value);
         declare
            Copied : constant Client_Objects.Whole_Get_Outcome :=
              Client_Objects.Get_Whole
                (HTTP, Origin, Probe, Copy_Key, First_Value'Length, Identity,
                 Version_ID => US.To_String (Copy_ID), Timeout => 30.0);
         begin
            if Copied.Kind /= Client_Objects.Whole_Object_Read
              or else Copied.Status /= 200
              or else US.To_String (Copied.Result.Version_ID) /=
                US.To_String (Copy_ID)
              or else Flyology.Bytes.To_Byte_String (Copied.Object_Bytes) /=
                First_Value
            then
               raise Program_Error with
                 "durable copied generation bytes mismatch";
            end if;
         end;
         Require_Attributes
           (US.To_String (First_ID), US.To_String (First_ETag),
            First_Value'Length);
         Require_Durable_Multipart;

         if Phase = Prepare_Durable_Restart then
            HTTP_Client.Shutdown (HTTP);
            Ada.Text_IO.Put_Line
              ("durable backend restart fixture prepared");
            return;
         end if;

         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Version_ID := Second_ID;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, Probe, Object_Key,
                    Parameters, Identity, "us-east-1", Timestamp);
               Head : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Head.Kind /= Low_Level.Object_Found
                 or else Head.Status /= 200
                 or else Head.Result.Version_ID /= Second_ID
                 or else Head.Result.Content_Length /= Second_Value'Length
               then
                  raise Program_Error with
                    "durable version-addressed HeadObject mismatch";
               end if;
            end;
         end;

         declare
            Request    : Deletions.Delete_Objects_Request;
            Parameters : Low_Level.Delete_Objects_Parameters;
         begin
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String (Object_Key),
                  Version_ID => Second_ID,
                  others     => <>));
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String (Batch_Key),
                  Version_ID => Batch_ID,
                  others     => <>));
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String (Copy_Key),
                  Version_ID => Copy_ID,
                  others     => <>));
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Objects
                   (Origin, Low_Level.Path_Style, Probe, Request, Parameters,
                    Identity, "us-east-1", Timestamp);
               Removed : constant Low_Level.Delete_Objects_Outcome :=
                 Low_Level.Execute_Delete_Objects
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Removed.Kind /= Low_Level.Objects_Deleted
                 or else Removed.Status /= 200
                 or else Removed.Result.Result.Deleted.Length /= 3
                 or else not Removed.Result.Result.Errors.Is_Empty
                 or else US.To_String
                   (Removed.Result.Result.Deleted (1).Key) /= Object_Key
                 or else Removed.Result.Result.Deleted (1).Version_ID /=
                   Second_ID
                 or else Removed.Result.Result.Deleted (1).Delete_Marker.Is_Set
                 or else US.To_String
                   (Removed.Result.Result.Deleted (2).Key) /= Batch_Key
                 or else Removed.Result.Result.Deleted (2).Version_ID /=
                   Batch_ID
                 or else Removed.Result.Result.Deleted (2).Delete_Marker.Is_Set
                 or else US.To_String
                   (Removed.Result.Result.Deleted (3).Key) /= Copy_Key
                 or else Removed.Result.Result.Deleted (3).Version_ID /=
                   Copy_ID
                 or else Removed.Result.Result.Deleted (3).Delete_Marker.Is_Set
               then
                  raise Program_Error with
                    "durable exact-generation DeleteObjects mismatch";
               end if;
            end;
         end;
         Require_Current (US.To_String (First_ID), First_Value);
         declare
            Missing : constant Client_Objects.Whole_Get_Outcome :=
              Client_Objects.Get_Whole
                (HTTP, Origin, Probe, Batch_Key, Batch_Value'Length,
                 Identity, Timeout => 30.0);
         begin
            if Missing.Kind /= Client_Objects.Whole_Get_Rejected
              or else Missing.Status /= 404
              or else US.To_String (Missing.Error.Code) /= "NoSuchKey"
            then
               raise Program_Error with
                 "durable DeleteObjects left its peer generation visible";
            end if;
         end;

         declare
            Deleted : constant Client_Objects.Delete_Outcome :=
              Client_Objects.Delete
                (HTTP, Origin, Probe, Object_Key, Identity,
                 Timeout => 30.0);
         begin
            if Deleted.Kind /= Client_Objects.Object_Removed
              or else Deleted.Status /= 204
              or else not Deleted.Delete_Marker.Is_Set
              or else not Deleted.Delete_Marker.Value
              or else US.Length (Deleted.Version_ID) = 0
            then
               raise Program_Error with
                 "durable delete-marker publication response mismatch";
            end if;
            Marker_ID := Deleted.Version_ID;
         end;

         declare
            Missing : constant Client_Objects.Whole_Get_Outcome :=
              Client_Objects.Get_Whole
                (HTTP, Origin, Probe, Object_Key, First_Value'Length,
                 Identity, Timeout => 30.0);
         begin
            if Missing.Kind /= Client_Objects.Whole_Get_Rejected
              or else Missing.Status /= 404
              or else US.To_String (Missing.Error.Code) /= "NoSuchKey"
            then
               raise Program_Error with
                 "durable delete marker did not hide the current object";
            end if;
         end;
         Require_Whole (US.To_String (First_ID), First_Value);

         declare
            Page : constant Client_Objects.List_Versions_Outcome :=
              Client_Objects.List_Versions_Page
                (HTTP, Origin, Probe, Identity, Prefix => Object_Key,
                 Maximum => Version_Page_Bound, Timeout => 30.0);
         begin
            if Page.Kind /= Client_Objects.Page_Available
              or else Page.Page.Versions.Length /= 1
              or else Page.Page.Delete_Markers.Length /= 1
              or else Page.Page.Versions (1).Version_ID /= First_ID
              or else Page.Page.Versions (1).Is_Latest
              or else Page.Page.Delete_Markers (1).Version_ID /= Marker_ID
              or else not Page.Page.Delete_Markers (1).Is_Latest
            then
               raise Program_Error with
                 "durable delete-marker version listing mismatch";
            end if;
         end;

         declare
            Removed_Marker : constant Client_Objects.Delete_Outcome :=
              Client_Objects.Delete
                (HTTP, Origin, Probe, Object_Key, Identity,
                 Version_ID => US.To_String (Marker_ID), Timeout => 30.0);
         begin
            if Removed_Marker.Kind /= Client_Objects.Object_Removed
              or else Removed_Marker.Version_ID /= Marker_ID
              or else not Removed_Marker.Delete_Marker.Is_Set
              or else not Removed_Marker.Delete_Marker.Value
            then
               raise Program_Error with
                 "durable exact delete-marker removal response mismatch";
            end if;
         end;
         Require_Current (US.To_String (First_ID), First_Value);

         declare
            Removed_First : constant Client_Objects.Delete_Outcome :=
              Client_Objects.Delete
                (HTTP, Origin, Probe, Object_Key, Identity,
                 Version_ID => US.To_String (First_ID), Timeout => 30.0);
         begin
            if Removed_First.Kind /= Client_Objects.Object_Removed
              or else Removed_First.Version_ID /= First_ID
            then
               raise Program_Error with
                 "durable final version removal response mismatch";
            end if;
         end;
         HTTP_Client.Shutdown (HTTP);
         Delete_Empty_Bucket (Origin, Probe, "");
      exception
         when others =>
            HTTP_Client.Shutdown (HTTP);
            raise;
      end;
   end Require_Durable_Version_Routing;

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
         Head : constant Transfers.Head_Outcome :=
           Transfers.Head_Object
             (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
      begin
         if Head.Kind /= Transfers.Object_Found
           or else US.Length (Head.Entity_Tag) = 0
         then
            raise Program_Error with
              "S3 implementation could not bind DeleteObject generation";
         end if;
         declare
            Mismatch : constant Scoped.Delete_Result :=
              Client_Objects.Delete
                (HTTP, Origin, Bucket, Key, Identity,
                 If_Match => """definitely-stale""", Timeout => 30.0);
            Preserved : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
         begin
            if Delete_Object_Oracle_Mode = MinIO_2025_Ignores_If_Match then
               if Mismatch.Kind /= Scoped.Delete_Response_Available
                 or else Mismatch.Disposition /= Scoped.Deletion_Completed
                 or else Mismatch.Response.Kind /= Low_Level.Object_Deleted
                 or else Preserved.Kind /= Transfers.Head_Rejected
                 or else Preserved.Status /= 404
               then
                  raise Program_Error with
                    "MinIO DeleteObject If-Match divergence changed";
               end if;
            else
               if Mismatch.Kind /= Scoped.Delete_Response_Available
                 or else Mismatch.Disposition /=
                   Scoped.Definitely_Not_Deleted
                 or else Mismatch.Response.Kind /=
                   Low_Level.Delete_Object_Rejected
                 or else Mismatch.Response.Status /= 412
                 or else Preserved.Kind /= Transfers.Object_Found
                 or else US.To_String (Preserved.Entity_Tag) /=
                   US.To_String (Head.Entity_Tag)
               then
                  raise Program_Error with
                    "S3 implementation violated mismatched DeleteObject";
               end if;
            end if;
         end;
         if Delete_Object_Oracle_Mode = MinIO_2025_Ignores_If_Match then
            declare
               Missing_Conditional : constant Scoped.Delete_Result :=
                 Client_Objects.Delete
                   (HTTP, Origin, Bucket, Key, Identity,
                    If_Match => "*", Timeout => 30.0);
               Missing_Idempotent : constant Scoped.Delete_Result :=
                 Client_Objects.Delete
                   (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
            begin
               if Missing_Conditional.Kind /= Scoped.Delete_Response_Available
                 or else Missing_Conditional.Disposition /=
                   Scoped.Deletion_Completed
                 or else Missing_Conditional.Response.Kind /=
                   Low_Level.Object_Deleted
                 or else Missing_Idempotent.Kind /=
                   Scoped.Delete_Response_Available
                 or else Missing_Idempotent.Disposition /=
                   Scoped.Deletion_Completed
                 or else Missing_Idempotent.Response.Kind /=
                   Low_Level.Object_Deleted
               then
                  raise Program_Error with
                    "MinIO missing DeleteObject divergence changed";
               end if;
            end;
         else
            declare
               Deleted : constant Scoped.Delete_Result :=
                 Client_Objects.Delete
                   (HTTP, Origin, Bucket, Key, Identity,
                    If_Match => US.To_String (Head.Entity_Tag),
                    Timeout => 30.0);
               Missing_Conditional : constant Scoped.Delete_Result :=
                 Client_Objects.Delete
                   (HTTP, Origin, Bucket, Key, Identity,
                    If_Match => "*", Timeout => 30.0);
               Missing_Idempotent : constant Scoped.Delete_Result :=
                 Client_Objects.Delete
                   (HTTP, Origin, Bucket, Key, Identity, Timeout => 30.0);
            begin
               if Deleted.Kind /= Scoped.Delete_Response_Available
                 or else Deleted.Disposition /= Scoped.Deletion_Completed
                 or else Deleted.Response.Kind /= Low_Level.Object_Deleted
                 or else Missing_Conditional.Kind /=
                   Scoped.Delete_Response_Available
                 or else Missing_Conditional.Disposition /=
                   Scoped.Definitely_Not_Deleted
                 or else Missing_Conditional.Response.Kind /=
                   Low_Level.Delete_Object_Rejected
                 or else Missing_Conditional.Response.Status /=
                   (if Delete_Object_Oracle_Mode =
                         Conditioned_Missing_Is_412
                    then 412 else 404)
                 or else US.To_String
                   (Missing_Conditional.Response.Error.Code) /=
                   (if Delete_Object_Oracle_Mode =
                         Conditioned_Missing_Is_412
                    then "PreconditionFailed" else "NoSuchKey")
                 or else Missing_Idempotent.Kind /=
                   Scoped.Delete_Response_Available
                 or else Missing_Idempotent.Disposition /=
                   Scoped.Deletion_Completed
                 or else Missing_Idempotent.Response.Kind /=
                   Low_Level.Object_Deleted
               then
                  raise Program_Error with
                    "S3 implementation DeleteObject condition/missing " &
                    "mismatch";
               end if;
            end;
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
        "YYYYMMDDTHHMMSSZ " &
        "[setup|cleanup|restart-prepare|restart-verify]";
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
         Require_Bucket_Versioning (Origin, Bucket);
         Require_Durable_Version_Routing
           (Origin, Bucket, Timestamp, Complete_Durable_Routing);
         Ada.Text_IO.Put_Line
           ("S3 implementation setup: bucket created, located, headed, " &
            "listed, and versioning-configured; durable backend routing " &
            "checked when selected");
      elsif Ada.Command_Line.Argument (4) = "restart-prepare" then
         Require_Durable_Version_Routing
           (Origin, Bucket, Timestamp, Prepare_Durable_Restart);
      elsif Ada.Command_Line.Argument (4) = "restart-verify" then
         Require_Durable_Version_Routing
           (Origin, Bucket, Timestamp, Verify_Durable_Restart);
         Ada.Text_IO.Put_Line
           ("durable backend restart fixture verified and removed");
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
         Delete_One
           (Origin, Bucket, "native-object-conditional-put", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-complete-put-tuple", Timestamp);
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
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-conditional-put", Timestamp);
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-complete-put-tuple", Timestamp);
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
