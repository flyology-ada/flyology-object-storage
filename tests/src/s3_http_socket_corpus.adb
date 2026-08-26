with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.Buffers;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.IO.Sockets;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Buckets.Testing;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Objects;
with Flyology.Object_Storage.Client.Objects.Testing;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.Client.Transfers.Testing;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Encryption;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;
with Flyology.Operations;

procedure S3_HTTP_Socket_Corpus is
   use Flyology.Object_Storage.Client;
   use Flyology.Object_Storage.Client.Objects;
   use Flyology.Object_Storage.Client.Buckets;
   use Flyology.Object_Storage.Client.Transfers;
   package Client_API renames Flyology.Object_Storage.Client;
   package Objects_Testing renames
     Flyology.Object_Storage.Client.Objects.Testing;
   package Buckets_Testing renames
     Flyology.Object_Storage.Client.Buckets.Testing;
   package Transfers_Testing renames
     Flyology.Object_Storage.Client.Transfers.Testing;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Objects renames Flyology.Object_Storage.Client.Objects;
   package Buffers renames Flyology.Buffers;
   package Operations renames Flyology.Operations;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Client_Buckets renames
     Flyology.Object_Storage.Client.Buckets;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package ACL renames Flyology.Object_Storage.S3.ACL;
   package Encryption renames Flyology.Object_Storage.S3.Encryption;
   package Metadata_Tables renames
     Flyology.Object_Storage.S3.Metadata_Tables;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Bucket_Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;
   package Checksum_Policy renames Checksums.Policy;
   package Listings renames Flyology.Object_Storage.S3.Listings;
   package Model renames Flyology.Object_Storage.S3.Model;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package S3_Tagging renames Flyology.Object_Storage.S3.Tagging;
   package Tags renames Flyology.Object_Storage.Tags;
   package Sockets renames Flyology.IO.Sockets;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Ada.Containers.Count_Type;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Objects.List_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Upload_Part_Copy_Outcome_Kind;
   use type Low_Level.Put_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Get_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type Low_Level.Delete_Objects_Outcome_Kind;
   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Delete_Object_Annotation_Outcome_Kind;
   use type Low_Level.Put_Object_Legal_Hold_Outcome_Kind;
   use type Low_Level.Put_Object_Retention_Outcome_Kind;
   use type Low_Level.Put_Object_Lock_Configuration_Outcome_Kind;
   use type Objects.Delete_Outcome_Kind;
   use type Low_Level.Put_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Get_Bucket_Versioning_Outcome_Kind;
   use type Client_Buckets.Set_Versioning_Outcome_Kind;
   use type Client_Buckets.Get_Versioning_Outcome_Kind;
   use type Client_Buckets.Create_Outcome_Kind;
   use type Client_Buckets.Head_Outcome_Kind;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;
   use type Low_Level.Head_Object_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Object_Tagging_Outcome_Kind;
   use type Objects.Tagging_Outcome_Kind;
   use type Objects.Whole_Get_Outcome_Kind;
   use type Conditional_Put_Result_Kind;
   use type Failure_Reason;
   use type Publication_Disposition;
   use type Part_Upload_Disposition;
   use type List_Objects_Result_Kind;
   use type List_Buckets_Result_Kind;
   use type Create_Bucket_Result_Kind;
   use type Bucket_Creation_Disposition;
   use type Delete_Bucket_Result_Kind;
   use type Bucket_Deletion_Disposition;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Bucket_Tag_Mutation_Disposition;
   use type Put_Bucket_Tagging_Result_Kind;
   use type Get_Bucket_Tagging_Result_Kind;
   use type Delete_Bucket_Tagging_Result_Kind;
   use type Head_Bucket_Result_Kind;
   use type Get_Bucket_Location_Result_Kind;
   use type Get_Bucket_Policy_Result_Kind;
   use type Get_Bucket_Policy_Status_Result_Kind;
   use type Put_Bucket_Policy_Result_Kind;
   use type Delete_Bucket_Policy_Result_Kind;
   use type Bucket_Policy_Mutation_Disposition;
   use type Get_Public_Access_Block_Result_Kind;
   use type Get_Bucket_Ownership_Controls_Result_Kind;
   use type Get_Bucket_Encryption_Result_Kind;
   use type Put_Bucket_Encryption_Result_Kind;
   use type Put_Bucket_CORS_Result_Kind;
   use type Bucket_CORS_Mutation_Disposition;
   use type Delete_Bucket_Encryption_Result_Kind;
   use type Bucket_Encryption_Mutation_Disposition;
   use type Delete_Bucket_Lifecycle_Result_Kind;
   use type Bucket_Lifecycle_Mutation_Disposition;
   use type Put_Bucket_Ownership_Controls_Result_Kind;
   use type Bucket_Ownership_Controls_Mutation_Disposition;
   use type Delete_Ownership_Controls_Result_Kind;
   use type Put_Public_Access_Block_Result_Kind;
   use type Put_Bucket_ABAC_Result_Kind;
   use type ABAC_Mutation_Disposition;
   use type Put_Bucket_Accelerate_Configuration_Result_Kind;
   use type Acceleration_Mutation_Disposition;
   use type Put_Bucket_Request_Payment_Result_Kind;
   use type Request_Payment_Mutation_Disposition;
   use type Delete_Public_Access_Block_Result_Kind;
   use type Public_Access_Block_Mutation_Disposition;
   use type Get_Bucket_Versioning_Result_Kind;
   use type Put_Bucket_Versioning_Result_Kind;
   use type List_Objects_V2_Result_Kind;
   use type List_Object_Versions_Result_Kind;
   use type Get_Object_Attributes_Result_Kind;
   use type List_Parts_Result_Kind;
   use type List_Multipart_Uploads_Result_Kind;
   use type Copy_Result_Kind;
   use type Upload_Part_Result_Kind;
   use type Upload_Part_Copy_Result_Kind;
   use type Multipart_Completion_Disposition;
   use type Multipart_Completion_Result_Kind;
   use type Multipart_Abort_Disposition;
   use type Multipart_Abort_Result_Kind;
   use type Whole_Get_Result_Kind;
   use type Range_Get_Result_Kind;
   use type Head_Result_Kind;
   use type Delete_Result_Kind;
   use type Deletion_Disposition;
   use type Delete_Objects_Result_Kind;
   use type Delete_Objects_Disposition;
   use type Put_Object_Tagging_Result_Kind;
   use type Get_Object_Tagging_Result_Kind;
   use type Delete_Object_Tagging_Result_Kind;
   use type Object_Tag_Mutation_Disposition;
   use type Get_Legal_Hold_Result_Kind;
   use type Put_Legal_Hold_Result_Kind;
   use type Legal_Hold_Mutation_Disposition;
   use type Get_Retention_Result_Kind;
   use type Put_Retention_Result_Kind;
   use type Retention_Mutation_Disposition;
   use type Get_Object_Lock_Configuration_Result_Kind;
   use type Put_Object_Lock_Configuration_Result_Kind;
   use type Object_Lock_Configuration_Mutation_Disposition;
   use type Create_Multipart_Result_Kind;
   use type Multipart_Creation_Disposition;
   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Flyology.Object_Storage.Object_Tag_Set;
   use type Low_Level.Get_Object_Attributes_Outcome_Kind;
   use type Low_Level.Get_Object_ACL_Outcome_Kind;
   use type Low_Level.Get_Object_Legal_Hold_Outcome_Kind;
   use type Low_Level.Get_Object_Retention_Outcome_Kind;
   use type Low_Level.Get_Object_Lock_Configuration_Outcome_Kind;
   use type Object_Lock.Legal_Hold_Status;
   use type Object_Lock.Object_Lock_Enabled_Status;
   use type Object_Lock.Retention_Mode;
   use type Buckets.Get_Tags_Outcome_Kind;
   use type Buckets.Delete_Tags_Outcome_Kind;
   use type Buckets.Delete_Outcome_Kind;
   use type Low_Level.Delete_Bucket_CORS_Outcome_Kind;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;
   use type Bucket_Controls.Abac_Status;
   use type Bucket_Controls.Accelerate_Status;
   use type Bucket_Controls.Payer;
   use type Bucket_Controls.Object_Ownership;
   use type ACL.Grantee_Type;
   use type ACL.Permission;
   use type Encryption.Encryption_Algorithm;
   use type Encryption.Blocked_Encryption_Type;
   use type Tags.Tag_Vectors.Vector;
   use type Transfers.Download_Outcome_Kind;
   use type Transfers.Upload_Outcome_Kind;
   use type Transfers.Copy_Outcome_Kind;
   use type Transfers.Head_Outcome_Kind;
   use type Sockets.Selector_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Upload_Payload : aliased constant String :=
     String'(1 .. 120 * 1_024 => 'u');
   Download_Payload : constant String :=
     String'(1 .. 120 * 1_024 => 'd');
   Conditional_First : aliased constant String := "conditional-first";
   Conditional_Collision : aliased constant String :=
     "conditional-collision";
   Conditional_Second : aliased constant String := "conditional-second";
   Conditional_Stale : aliased constant String := "conditional-stale";
   Convenience_Put_Payload : aliased constant String := "convenience put";
   Lost_Put_Payload : aliased constant String := "lost put response";
   Lost_Upload_Payload : aliased constant String := "lost upload response";
   Put_Response_Vector_Payload : aliased constant String := "v";

   type Read_Checksum_Spec is record
      Header : US.Unbounded_String;
      Value  : US.Unbounded_String;
   end record;

   type Read_Checksum_Spec_Array is array (Positive range <>) of
     Read_Checksum_Spec;

   Read_Checksums : constant Read_Checksum_Spec_Array :=
     ((US.To_Unbounded_String ("x-amz-checksum-crc32"),
       US.To_Unbounded_String ("AAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-crc32c"),
       US.To_Unbounded_String ("AAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-crc64nvme"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha1"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha256"),
       US.To_Unbounded_String
         ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha512"),
       US.To_Unbounded_String (String'(1 .. 86 => 'A') & "==")),
      (US.To_Unbounded_String ("x-amz-checksum-md5"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash64"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash3"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash128"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")));

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

   type Rewindable_Probe is
     new HTTP_Client.Rewindable_Request_Body_Source with null record;

   overriding function Declared_Length
     (Item : Rewindable_Probe) return HTTP_Client.Body_Length;

   overriding procedure Read
     (Item     : in out Rewindable_Probe;
      Data     : out Stream_Element_Array;
      Last     : out Stream_Element_Offset;
      Finished : out Boolean;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token);

   overriding procedure Rewind (Item : in out Rewindable_Probe);

   overriding function Declared_Length
     (Item : Rewindable_Probe) return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length (0));

   overriding procedure Read
     (Item     : in out Rewindable_Probe;
      Data     : out Stream_Element_Array;
      Last     : out Stream_Element_Offset;
      Finished : out Boolean;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Item, Timeout, Token);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      Finished := True;
   end Read;

   overriding procedure Rewind (Item : in out Rewindable_Probe) is
      pragma Unreferenced (Item);
   begin
      null;
   end Rewind;

   function Bytes (Value : String) return Stream_Element_Array is
      Result : Stream_Element_Array
        (1 .. Stream_Element_Offset (Value'Length));
   begin
      for Offset in 0 .. Value'Length - 1 loop
         Result (Result'First + Stream_Element_Offset (Offset)) :=
           Stream_Element (Character'Pos (Value (Value'First + Offset)));
      end loop;
      return Result;
   end Bytes;

   function Buffer_String (Item : Buffers.Unique_Buffer) return String is
      Value : US.Unbounded_String;

      procedure Copy (Data : Stream_Element_Array) is
      begin
         for Element of Data loop
            US.Append (Value, Character'Val (Element));
         end loop;
      end Copy;
   begin
      Buffers.With_Readable_Data (Item, Copy'Access);
      return US.To_String (Value);
   end Buffer_String;

   High_Level_File_Payload : constant String := "high-level file payload";
   High_Level_CRC32 : constant String :=
     Checksums.Encode_Base64
       (Checksums.Compute
          (Checksum_Policy.Core.CRC32, Bytes (High_Level_File_Payload)));
   Convenience_Put_CRC32 : constant String :=
     Checksums.Encode_Base64
       (Checksums.Compute
          (Checksum_Policy.Core.CRC32, Bytes (Convenience_Put_Payload)));
   Convenience_Put_MD5 : constant String :=
     Checksums.Encode_Base64
       (Checksums.Compute
          (Checksum_Policy.Core.MD5, Bytes (Convenience_Put_Payload)));
   Put_Response_Vector_SHA256 : constant String :=
     Checksums.Encode_Base64
       (Checksums.Compute
          (Checksum_Policy.Core.SHA256,
           Bytes (Put_Response_Vector_Payload)));
   Lost_Upload_SHA256 : constant String :=
     Checksums.Encode_Base64
       (Checksums.Compute
          (Checksum_Policy.Core.SHA256, Bytes (Lost_Upload_Payload)));
   High_Level_SHA256_Digest : constant Checksums.Digest_Value :=
     Checksums.Compute
       (Checksum_Policy.Core.SHA256, Bytes (High_Level_File_Payload));
   High_Level_SHA256 : constant String :=
     Checksums.Encode_Base64 (High_Level_SHA256_Digest);
   High_Level_SHA256_Composite_Digest : constant Checksums.Digest_Value :=
     Checksums.Composite
       (Checksum_Policy.Core.SHA256,
        Checksums.Digest_Array'(1 => High_Level_SHA256_Digest));
   High_Level_SHA256_Composite_Raw : constant String :=
     Checksums.Encode_Base64 (High_Level_SHA256_Composite_Digest);
   High_Level_SHA256_Composite : constant String :=
     Checksums.Encode_Object
       (High_Level_SHA256_Composite_Digest, Checksum_Policy.Composite, 1);
   Wrong_SHA256_Digest : constant Checksums.Digest_Value :=
     Checksums.Compute
       (Checksum_Policy.Core.SHA256, Bytes ("wrong response"));
   Wrong_SHA256 : constant String :=
     Checksums.Encode_Base64 (Wrong_SHA256_Digest);
   Wrong_SHA256_Composite : constant String :=
     Checksums.Encode_Object
       (Checksums.Composite
          (Checksum_Policy.Core.SHA256,
           Checksums.Digest_Array'(1 => Wrong_SHA256_Digest)),
        Checksum_Policy.Composite, 1);

   procedure Write_File (Path, Value : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Value'Length > 0 then
         SIO.Write (File, Bytes (Value));
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_File;

   procedure Delete_If_Present (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Present;

   function Read_File (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
      begin
         if Size = 0 then
            SIO.Close (File);
            return "";
         elsif Size > SIO.Count (Natural'Last) then
            raise Program_Error with "test file is too large";
         end if;
         declare
            Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
            Last : Stream_Element_Offset;
            Result : String (1 .. Natural (Size));
         begin
            SIO.Read (File, Data, Last);
            if Last /= Data'Last then
               raise Program_Error with "short test file read";
            end if;
            for Index in Result'Range loop
               Result (Index) := Character'Val
                 (Data
                    (Data'First
                     + Stream_Element_Offset (Index - Result'First)));
            end loop;
            SIO.Close (File);
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_File;

   procedure Require_No_Download_Temporary (Path : String) is
      Search : Ada.Directories.Search_Type;
      Active : Boolean := False;
      Found  : Boolean;
      Directory : constant String := Ada.Directories.Containing_Directory
        (Path);
      Pattern : constant String := Ada.Directories.Simple_Name (Path)
        & ".flyology-*.part";
   begin
      Ada.Directories.Start_Search (Search, Directory, Pattern);
      Active := True;
      Found := Ada.Directories.More_Entries (Search);
      Ada.Directories.End_Search (Search);
      Active := False;
      if Found then
         raise Program_Error with "download temporary file was not removed";
      end if;
   exception
      when others =>
         if Active then
            Ada.Directories.End_Search (Search);
         end if;
         raise;
   end Require_No_Download_Temporary;

   function Decimal (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal;

   type Put_Response_Header_Spec is record
      Name  : US.Unbounded_String;
      Value : US.Unbounded_String;
   end record;

   type Put_Response_Header_Spec_Array is array (Positive range <>) of
     Put_Response_Header_Spec;

   Put_Response_Headers : constant Put_Response_Header_Spec_Array :=
     ((US.To_Unbounded_String ("x-amz-expiration"),
       US.To_Unbounded_String ("expiry")),
      (US.To_Unbounded_String ("etag"),
       US.To_Unbounded_String ("""vector""")),
      (US.To_Unbounded_String ("x-amz-checksum-crc32"),
       US.To_Unbounded_String ("AAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-crc32c"),
       US.To_Unbounded_String ("AAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-crc64nvme"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha1"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha256"),
       US.To_Unbounded_String
         ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha512"),
       US.To_Unbounded_String (String'(1 .. 86 => 'A') & "==")),
      (US.To_Unbounded_String ("x-amz-checksum-md5"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash64"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash3"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash128"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-type"),
       US.To_Unbounded_String ("FULL_OBJECT")),
      (US.To_Unbounded_String ("x-amz-server-side-encryption"),
       US.To_Unbounded_String ("aws:kms")),
      (US.To_Unbounded_String ("x-amz-version-id"),
       US.To_Unbounded_String ("version")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-customer-algorithm"),
       US.To_Unbounded_String ("AES256")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-customer-key-md5"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-aws-kms-key-id"),
       US.To_Unbounded_String ("kms-key")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-context"),
       US.To_Unbounded_String ("e30=")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-bucket-key-enabled"),
       US.To_Unbounded_String ("true")),
      (US.To_Unbounded_String ("x-amz-object-size"),
       US.To_Unbounded_String ("0")),
      (US.To_Unbounded_String ("x-amz-request-charged"),
       US.To_Unbounded_String ("requester")));

   Upload_Response_Headers : constant Put_Response_Header_Spec_Array :=
     ((US.To_Unbounded_String ("x-amz-server-side-encryption"),
       US.To_Unbounded_String ("aws:kms")),
      (US.To_Unbounded_String ("etag"),
       US.To_Unbounded_String ("opaque-part-etag")),
      (US.To_Unbounded_String ("x-amz-checksum-crc32"),
       US.To_Unbounded_String ("AAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-crc32c"),
       US.To_Unbounded_String ("AAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-crc64nvme"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha1"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha256"),
       US.To_Unbounded_String
         ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-sha512"),
       US.To_Unbounded_String (String'(1 .. 86 => 'A') & "==")),
      (US.To_Unbounded_String ("x-amz-checksum-md5"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash64"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash3"),
       US.To_Unbounded_String ("AAAAAAAAAAA=")),
      (US.To_Unbounded_String ("x-amz-checksum-xxhash128"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-customer-algorithm"),
       US.To_Unbounded_String ("AES256")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-customer-key-md5"),
       US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-aws-kms-key-id"),
       US.To_Unbounded_String ("kms-key")),
      (US.To_Unbounded_String
         ("x-amz-server-side-encryption-bucket-key-enabled"),
       US.To_Unbounded_String ("true")),
      (US.To_Unbounded_String ("x-amz-request-charged"),
       US.To_Unbounded_String ("requester")));

   function HTTP_Response
     (Status, Payload      : String;
      Extra_Headers        : String := "";
      Omit_Content_Length  : Boolean := False) return String is
     ("HTTP/1.1 " & Status & CRLF &
      (if Omit_Content_Length then ""
       else "Content-Length: " & Decimal (Payload'Length) & CRLF) &
      Extra_Headers & "Connection: close" & CRLF & CRLF & Payload);

   protected type Coordination is
      procedure Publish (Value : Sockets.Port);
      entry Wait_Ready (Value : out Sockets.Port);
      procedure Complete (Passed : Boolean; Detail : String := "");
      entry Wait_Done (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Port_Value   : Sockets.Port := Sockets.Any_Port;
      Ready        : Boolean := False;
      Done         : Boolean := False;
      Passed_Value : Boolean := False;
      Detail_Value : US.Unbounded_String;
   end Coordination;

   protected body Coordination is
      procedure Publish (Value : Sockets.Port) is
      begin
         Port_Value := Value;
         Ready := True;
      end Publish;

      entry Wait_Ready (Value : out Sockets.Port) when Ready or Done is
      begin
         if not Ready then
            raise Program_Error with
              "raw S3 socket server failed before publishing its port: " &
              US.To_String (Detail_Value);
         end if;
         Value := Port_Value;
      end Wait_Ready;

      procedure Complete (Passed : Boolean; Detail : String := "") is
      begin
         Passed_Value := Passed;
         Detail_Value := US.To_Unbounded_String (Detail);
         Done := True;
      end Complete;

      entry Wait_Done
        (Passed : out Boolean; Detail : out US.Unbounded_String) when Done is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait_Done;
   end Coordination;

   State : Coordination;

   protected type Client_Results is
      procedure Report (Passed : Boolean; Detail : String := "");
      entry Wait_All
        (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Count        : Natural := 0;
      Passed_Value : Boolean := True;
      Detail_Value : US.Unbounded_String;
   end Client_Results;

   protected body Client_Results is
      procedure Report (Passed : Boolean; Detail : String := "") is
      begin
         Count := Count + 1;
         Passed_Value := Passed_Value and Passed;
         if not Passed and then US.Length (Detail_Value) = 0 then
            Detail_Value := US.To_Unbounded_String (Detail);
         end if;
      end Report;

      entry Wait_All
        (Passed : out Boolean; Detail : out US.Unbounded_String)
        when Count = 2
      is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait_All;
   end Client_Results;

   Clients : Client_Results;

   task Raw_S3_Server is
      pragma Task_Info (Flyology.Native_Task);
   end Raw_S3_Server;

   task body Raw_S3_Server is
      Listener : Sockets.Socket_Type;
      Peer     : Sockets.Socket_Type;
      Address  : Sockets.Endpoint;
      Status   : Sockets.Selector_Status;
      Port     : Sockets.Port;

      function Header_Value (Header, Name : String) return String is
         Marker : constant String := CRLF & Name & ":";
         Position : constant Natural :=
           Ada.Strings.Fixed.Index (Header, Marker);
         First : Natural := Position + Marker'Length;
         Last  : Natural;
      begin
         if Position = 0 then
            return "";
         end if;
         while First <= Header'Last and then Header (First) = ' ' loop
            First := First + 1;
         end loop;
         Last := Ada.Strings.Fixed.Index
           (Header, CRLF, From => First) - 1;
         if Last < First then
            return "";
         end if;
         return Header (First .. Last);
      end Header_Value;

      function Exact_Header_Value (Header, Name : String) return String is
         Lower : constant String := Ada.Characters.Handling.To_Lower (Header);
         Marker : constant String := CRLF &
           Ada.Characters.Handling.To_Lower (Name) & ":";
         Position : constant Natural :=
           Ada.Strings.Fixed.Index (Lower, Marker);
         First : Natural := Position + Marker'Length;
         Last  : Natural;
      begin
         if Position = 0 then
            return "";
         end if;
         while First <= Header'Last and then Header (First) = ' ' loop
            First := First + 1;
         end loop;
         Last := Ada.Strings.Fixed.Index
           (Header, CRLF, From => First) - 1;
         if Last < First then
            return "";
         end if;
         return Header (First .. Last);
      end Exact_Header_Value;

      function Is_Signed (Lower_Header, Name : String) return Boolean is
         Lower_Name : constant String :=
           Ada.Characters.Handling.To_Lower (Name);
      begin
         return Ada.Strings.Fixed.Index
           (Lower_Header, "signedheaders=" & Lower_Name & ";") /= 0
           or else Ada.Strings.Fixed.Index
             (Lower_Header, ";" & Lower_Name & ";") /= 0
           or else Ada.Strings.Fixed.Index
             (Lower_Header, ";" & Lower_Name & ",") /= 0;
      end Is_Signed;

      procedure Serve
        (Response           : String;
         Expected_Method    : String;
         Expected_Target    : String;
         Expected_Body_Root : String := "";
         Expected_Content_Type : String := "";
         Expected_Content_MD5 : String := "";
         Expected_Copy_Source : String := "";
         Expected_Copy_If_Match : String := "";
         Expected_If_Match : String := "";
         Expected_If_Match_Last_Modified_Time : String := "";
         Expected_If_Match_Size : String := "";
         Expected_Object_If_Match : String := "";
         Expected_If_Modified_Since : String := "";
         Expected_If_None_Match : String := "";
         Expected_If_Unmodified_Since : String := "";
         Expected_Range : String := "";
         Expected_Checksum_Mode : String := "";
         Expected_Request_Payer : String := "";
         Expected_Bucket_Owner : String := "";
         Expected_MFA : String := "";
         Expected_Governance_Bypass : String := "";
         Expected_Confirm_Remove_Self_Access : String := "";
         Expected_SDK_Checksum : String := "";
         Expected_Checksum_CRC32 : String := "";
         Expected_Cache_Control : String := "";
         Expected_Content_Disposition : String := "";
         Expected_Content_Encoding : String := "";
         Expected_Content_Language : String := "";
         Expected_Expires : String := "";
         Expected_Tagging : String := "";
         Expected_User_Metadata_Name : String := "";
         Expected_User_Metadata_Value : String := "";
         Expected_Website_Redirect : String := "";
         Expected_Object_Attributes : String := "";
         Expected_Get_Object_Attributes : String := "";
         Expected_Max_Parts : String := "";
         Expected_Part_Marker : String := "";
         Expected_Checksum_Algorithm_Header : String := "";
         Expected_Checksum_Algorithm : String := "";
         Expected_Checksum_Header : String := "";
         Expected_Checksum : String := "";
         Expected_Checksum_Type : String := "";
         Expected_Mpu_Object_Size : String := "";
         Expected_Body_Exact : String := "";
         Expected_Object_Lock_Token : String := "";
         Require_Zero_Content_Length : Boolean := False;
         Fragmented         : Boolean := False;
         Reuse_Peer         : Boolean := False;
         Keep_Open          : Boolean := False)
      is
         Buffer : Stream_Element_Array (1 .. 4_096);
         Last   : Stream_Element_Offset;
         Head   : US.Unbounded_String;
      begin
         if not Reuse_Peer then
            Sockets.Accept_Socket
              (Listener, Peer, Address, Timeout => 5.0, Status => Status);
            if Status /= Sockets.Completed then
               raise Program_Error with "socket accept timed out";
            end if;
         elsif not Sockets.Is_Open (Peer) then
            raise Program_Error with "socket peer is unavailable for reuse";
         end if;
         loop
            Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);
            if Last < Buffer'First then
               raise Program_Error with "client closed before request head";
            end if;
            for Index in Buffer'First .. Last loop
               US.Append (Head, Character'Val (Buffer (Index)));
            end loop;
            exit when Ada.Strings.Fixed.Index
              (US.To_String (Head), CRLF & CRLF) /= 0;
         end loop;
         declare
            Request : constant String := US.To_String (Head);
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index (Request, CRLF & CRLF);
            Header : constant String :=
              Request (Request'First .. Separator + 3);
            Lower   : constant String :=
              Ada.Characters.Handling.To_Lower (Header);
            Target : constant String :=
              Ada.Characters.Handling.To_Lower
                (Expected_Method & " " & Expected_Target & " http/1.1") &
              CRLF;
            Length_Text : constant String :=
              Header_Value (Lower, "content-length");
            Expected_Length : constant Natural :=
              (if Length_Text'Length = 0
               then 0 else Natural'Value (Length_Text));
            Request_Body : US.Unbounded_String;
         begin
            if Ada.Strings.Fixed.Index (Lower, Target) /= 1
              or else Ada.Strings.Fixed.Index
                (Lower, "host: 127.0.0.1:" & Decimal (Natural (Port))) = 0
              or else Ada.Strings.Fixed.Index
                (Lower, "authorization: aws4-hmac-sha256 credential=") = 0
              or else
                (Require_Zero_Content_Length
                 and then Header_Value (Lower, "content-length") /= "0")
              or else
                (if Expected_Tagging'Length > 0 then
                    Exact_Header_Value (Header, "content-md5") /=
                      Expected_Content_MD5
                    or else Exact_Header_Value (Header, "content-type") /=
                      Expected_Content_Type
                    or else Exact_Header_Value (Header, "cache-control") /=
                      Expected_Cache_Control
                    or else Exact_Header_Value
                      (Header, "content-disposition") /=
                        Expected_Content_Disposition
                    or else Exact_Header_Value
                      (Header, "content-encoding") /= Expected_Content_Encoding
                    or else Exact_Header_Value
                      (Header, "content-language") /= Expected_Content_Language
                    or else Exact_Header_Value (Header, "expires") /=
                      Expected_Expires
                    or else Exact_Header_Value (Header, "if-none-match") /=
                      Expected_If_None_Match
                    or else Exact_Header_Value
                      (Header, "x-amz-expected-bucket-owner") /=
                        Expected_Bucket_Owner
                    or else Header_Value
                      (Lower, "x-amz-sdk-checksum-algorithm") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_SDK_Checksum)
                    or else Header_Value
                      (Header, "x-amz-checksum-crc32") /=
                        Expected_Checksum_CRC32
                    or else Exact_Header_Value (Header, "x-amz-tagging") /=
                      Expected_Tagging
                    or else Exact_Header_Value
                      (Header, "x-amz-meta-" & Expected_User_Metadata_Name) /=
                        Expected_User_Metadata_Value
                    or else Exact_Header_Value
                      (Header, "x-amz-website-redirect-location") /=
                        Expected_Website_Redirect
                    or else not Is_Signed (Lower, "content-md5")
                    or else not Is_Signed (Lower, "content-type")
                    or else not Is_Signed (Lower, "cache-control")
                    or else not Is_Signed (Lower, "content-disposition")
                    or else not Is_Signed (Lower, "content-encoding")
                    or else not Is_Signed (Lower, "content-language")
                    or else not Is_Signed (Lower, "expires")
                    or else not Is_Signed (Lower, "if-none-match")
                    or else not Is_Signed
                      (Lower, "x-amz-expected-bucket-owner")
                    or else not Is_Signed
                      (Lower, "x-amz-sdk-checksum-algorithm")
                    or else not Is_Signed (Lower, "x-amz-checksum-crc32")
                    or else not Is_Signed (Lower, "x-amz-meta-" &
                      Expected_User_Metadata_Name)
                    or else not Is_Signed (Lower, "x-amz-tagging")
                    or else not Is_Signed
                      (Lower, "x-amz-website-redirect-location")
                 elsif Expected_Checksum_Algorithm_Header'Length > 0
                   or else Expected_Checksum_Header'Length > 0
                   or else Expected_Checksum_Type'Length > 0
                   or else Expected_Mpu_Object_Size'Length > 0
                 then
                    (Expected_Checksum_Algorithm_Header'Length > 0
                     and then Header_Value
                       (Lower, Expected_Checksum_Algorithm_Header) /=
                         Ada.Characters.Handling.To_Lower
                           (Expected_Checksum_Algorithm))
                    or else
                      (Expected_Checksum_Header'Length > 0
                       and then Header_Value
                         (Header, Expected_Checksum_Header) /=
                           Expected_Checksum)
                    or else
                      (Expected_Checksum_Type'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-checksum-type") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Checksum_Type))
                    or else
                      (Expected_Mpu_Object_Size'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-mp-object-size") /=
                           Expected_Mpu_Object_Size)
                    or else
                      (Expected_Checksum_Algorithm_Header'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower,
                          ";" & Expected_Checksum_Algorithm_Header & ";") = 0
                       and then Ada.Strings.Fixed.Index
                         (Lower,
                          ";" & Expected_Checksum_Algorithm_Header & ",") = 0)
                    or else
                      (Expected_Checksum_Header'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";" & Expected_Checksum_Header & ";") = 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";" & Expected_Checksum_Header & ",") = 0)
                    or else
                      (Expected_Checksum_Type'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-checksum-type;") = 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-checksum-type,") = 0)
                    or else
                      (Expected_Mpu_Object_Size'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-mp-object-size;") = 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-mp-object-size,") = 0)
                 elsif Expected_Get_Object_Attributes'Length > 0 then
                    Header_Value (Lower, "x-amz-object-attributes") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Get_Object_Attributes)
                    or else Header_Value (Lower, "x-amz-max-parts") /=
                      Ada.Characters.Handling.To_Lower (Expected_Max_Parts)
                    or else Header_Value
                      (Lower, "x-amz-part-number-marker") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Part_Marker)
                    or else Header_Value
                      (Lower, "x-amz-request-payer") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Request_Payer)
                    or else Header_Value
                      (Lower, "x-amz-expected-bucket-owner") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Bucket_Owner)
                    or else Ada.Strings.Fixed.Index
                      (Lower, ";x-amz-object-attributes") = 0
                 elsif Expected_Copy_Source'Length > 0 then
                    Header_Value (Lower, "x-amz-copy-source") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Copy_Source)
                    or else Header_Value
                      (Lower, "x-amz-copy-source-if-match") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Copy_If_Match)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=host;x-amz-content-sha256;" &
                       "x-amz-copy-source" &
                       (if Expected_Copy_If_Match'Length = 0 then ";"
                        else ";x-amz-copy-source-if-match;") &
                       "x-amz-date") = 0
                 elsif Expected_Content_MD5'Length > 0 then
                    Header_Value (Lower, "content-md5")'Length = 0
                    or else
                      (Expected_Content_MD5 /= "*"
                       and then Header_Value (Lower, "content-md5") /=
                         Ada.Characters.Handling.To_Lower
                           (Expected_Content_MD5))
                    or else
                      (Expected_Bucket_Owner'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-expected-bucket-owner") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Bucket_Owner))
                    or else
                      (Expected_Request_Payer'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-request-payer") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Request_Payer))
                    or else
                      (Expected_Object_Lock_Token'Length > 0
                       and then Exact_Header_Value
                         (Header, "x-amz-bucket-object-lock-token") /=
                           Expected_Object_Lock_Token)
                    or else
                      (Expected_MFA'Length > 0
                       and then Header_Value (Lower, "x-amz-mfa") /=
                         Ada.Characters.Handling.To_Lower (Expected_MFA))
                    or else
                      (Expected_Governance_Bypass'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-bypass-governance-retention") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Governance_Bypass))
                    or else
                      (Expected_Confirm_Remove_Self_Access'Length > 0
                       and then Header_Value
                         (Lower,
                          "x-amz-confirm-remove-self-bucket-access") /=
                            Ada.Characters.Handling.To_Lower
                              (Expected_Confirm_Remove_Self_Access))
                    or else
                      (Expected_SDK_Checksum'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-sdk-checksum-algorithm") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_SDK_Checksum))
                    or else
                      (Expected_Checksum_CRC32'Length > 0
                       and then
                         (Header_Value
                            (Lower, "x-amz-checksum-crc32")'Length = 0
                          or else
                            (Expected_Checksum_CRC32 /= "*"
                             and then Header_Value
                               (Lower, "x-amz-checksum-crc32") /=
                                 Ada.Characters.Handling.To_Lower
                                   (Expected_Checksum_CRC32))))
                    or else Ada.Strings.Fixed.Index
                      (Lower, "signedheaders=content-md5;host;") = 0
                    or else Ada.Strings.Fixed.Index
                      (Lower, ";x-amz-content-sha256;x-amz-date") = 0
                    or else
                      (Expected_Bucket_Owner'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-expected-bucket-owner") = 0)
                    or else
                      (Expected_Request_Payer'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-request-payer") = 0)
                    or else
                      (Expected_Object_Lock_Token'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-bucket-object-lock-token") = 0)
                    or else
                      (Expected_MFA'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-mfa") = 0)
                    or else
                      (Expected_Governance_Bypass'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-bypass-governance-retention;") = 0)
                    or else
                      (Expected_Confirm_Remove_Self_Access'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower,
                          ";x-amz-confirm-remove-self-bucket-access") = 0)
                    or else
                      (Expected_SDK_Checksum'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-sdk-checksum-algorithm") = 0)
                    or else
                      (Expected_Checksum_CRC32'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-checksum-crc32;") = 0)
                 elsif Expected_Method = "DELETE"
                   and then
                     (Expected_If_Match'Length > 0
                      or else Expected_If_Match_Last_Modified_Time'Length > 0
                      or else Expected_If_Match_Size'Length > 0
                      or else Expected_Object_If_Match'Length > 0
                      or else Expected_Request_Payer'Length > 0
                      or else Expected_Bucket_Owner'Length > 0
                      or else Expected_MFA'Length > 0
                      or else Expected_Governance_Bypass'Length > 0)
                 then
                    Header_Value (Lower, "if-match") /=
                      Ada.Characters.Handling.To_Lower (Expected_If_Match)
                    or else Header_Value
                      (Lower, "x-amz-if-match-last-modified-time") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_If_Match_Last_Modified_Time)
                    or else Header_Value
                      (Lower, "x-amz-if-match-size") /=
                        Expected_If_Match_Size
                    or else Header_Value
                      (Lower, "x-amz-object-if-match") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Object_If_Match)
                    or else Header_Value
                      (Lower, "x-amz-request-payer") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Request_Payer)
                    or else Header_Value
                      (Lower, "x-amz-expected-bucket-owner") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Bucket_Owner)
                    or else Header_Value (Lower, "x-amz-mfa") /=
                      Ada.Characters.Handling.To_Lower (Expected_MFA)
                    or else Header_Value
                      (Lower, "x-amz-bypass-governance-retention") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Governance_Bypass)
                    or else
                      (Expected_If_Match'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-match;") = 0)
                    or else
                      (Expected_If_Match_Last_Modified_Time'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-if-match-last-modified-time;") = 0)
                    or else
                      (Expected_If_Match_Size'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-if-match-size;") = 0)
                    or else
                      (Expected_Object_If_Match'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-object-if-match;") = 0)
                    or else
                      (Expected_Request_Payer'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-request-payer") = 0)
                    or else
                      (Expected_Bucket_Owner'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-expected-bucket-owner") = 0)
                    or else
                      (Expected_MFA'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-mfa") = 0)
                    or else
                      (Expected_Governance_Bypass'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-bypass-governance-retention;") = 0)
                 elsif Expected_Request_Payer'Length > 0
                   or else Expected_Bucket_Owner'Length > 0
                   or else Expected_Object_Attributes'Length > 0
                 then
                    Header_Value (Lower, "x-amz-request-payer") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Request_Payer)
                    or else Header_Value
                      (Lower, "x-amz-expected-bucket-owner") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Bucket_Owner)
                    or else Header_Value
                      (Lower, "x-amz-optional-object-attributes") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Object_Attributes)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=host;x-amz-content-sha256;" &
                       "x-amz-date" &
                       (if Expected_Bucket_Owner'Length > 0 then
                           ";x-amz-expected-bucket-owner"
                        else "") &
                       (if Expected_Object_Attributes'Length > 0 then
                           ";x-amz-optional-object-attributes"
                        else "") &
                       (if Expected_Request_Payer'Length > 0 then
                           ";x-amz-request-payer"
                        else "")) = 0
                 elsif Expected_If_Match'Length > 0
                   or else Expected_If_Modified_Since'Length > 0
                   or else Expected_If_None_Match'Length > 0
                   or else Expected_If_Unmodified_Since'Length > 0
                   or else Expected_Range'Length > 0
                   or else Expected_Checksum_Mode'Length > 0
                 then
                    Header_Value (Lower, "if-match") /=
                      Ada.Characters.Handling.To_Lower (Expected_If_Match)
                    or else Header_Value (Lower, "if-modified-since") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_If_Modified_Since)
                    or else Header_Value (Lower, "if-none-match") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_If_None_Match)
                    or else Header_Value (Lower, "if-unmodified-since") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_If_Unmodified_Since)
                    or else Header_Value (Lower, "range") /=
                      Ada.Characters.Handling.To_Lower (Expected_Range)
                    or else Header_Value
                      (Lower, "x-amz-checksum-mode") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Checksum_Mode)
                    or else Ada.Strings.Fixed.Index
                      (Lower, "signedheaders=host;") = 0
                    or else
                      (Expected_If_Match'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-match;") = 0)
                    or else
                      (Expected_If_Modified_Since'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-modified-since;") = 0)
                    or else
                      (Expected_If_None_Match'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-none-match;") = 0)
                    or else
                      (Expected_If_Unmodified_Since'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-unmodified-since;") = 0)
                    or else
                      (Expected_Range'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";range;") = 0)
                    or else
                      (Expected_Checksum_Mode'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-checksum-mode;") = 0)
                    or else Ada.Strings.Fixed.Index
                      (Lower, ";x-amz-content-sha256;x-amz-date") = 0
                 elsif Expected_Content_MD5'Length > 0 then
                    Header_Value (Lower, "content-md5") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Content_MD5)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=content-md5;host;" &
                       "x-amz-content-sha256;x-amz-date") = 0
                    or else
                      (Expected_Confirm_Remove_Self_Access'Length > 0
                       and then Header_Value
                         (Lower,
                          "x-amz-confirm-remove-self-bucket-access") /=
                            Ada.Characters.Handling.To_Lower
                              (Expected_Confirm_Remove_Self_Access))
                    or else
                      (Expected_Confirm_Remove_Self_Access'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower,
                          ";x-amz-confirm-remove-self-bucket-access") = 0)
                 elsif Expected_Content_Type'Length = 0 then
                    Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=host;x-amz-content-sha256;" &
                       "x-amz-date") = 0
                 else
                    Header_Value (Lower, "content-type") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Content_Type)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=content-type;host;" &
                       "x-amz-content-sha256;x-amz-date") = 0)
            then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "expected signed request: " & Expected_Method & " " &
                  Expected_Target);
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, "observed head: " & Header);
               raise Program_Error with "unexpected signed S3 request head";
            end if;
            if Separator + 4 <= Request'Last then
               US.Append
                 (Request_Body, Request (Separator + 4 .. Request'Last));
            end if;
            while US.Length (Request_Body) < Expected_Length loop
               Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);
               if Last < Buffer'First then
                  raise Program_Error with
                    "client closed before complete request body";
               end if;
               for Index in Buffer'First .. Last loop
                  US.Append
                    (Request_Body, Character'Val (Buffer (Index)));
               end loop;
            end loop;
            if US.Length (Request_Body) /= Expected_Length then
               raise Program_Error with "request body length mismatch";
            elsif Expected_Body_Root'Length > 0
              or else Expected_Body_Exact'Length > 0
            then
               declare
                  Body_Text : constant String := US.To_String (Request_Body);
                  Expected_Hash : constant String :=
                    SigV4.SHA256_Hex (Body_Text);
               begin
                  if (Expected_Body_Root'Length > 0
                      and then Ada.Strings.Fixed.Index
                        (Body_Text, Expected_Body_Root) = 0)
                    or else (Expected_Body_Exact'Length > 0
                             and then Body_Text /= Expected_Body_Exact)
                    or else Header_Value
                      (Lower, "x-amz-content-sha256") /= Expected_Hash
                  then
                     raise Program_Error with
                       "signed S3 request body mismatch";
                  end if;
               end;
            end if;
         end;
         if Response'Length = 0 then
            null;
         elsif Fragmented then
            for Character_Value of Response loop
               Sockets.Send_All
                 (Peer, Bytes (String'(1 => Character_Value)), Timeout => 5.0);
            end loop;
         else
            Sockets.Send_All (Peer, Bytes (Response), Timeout => 5.0);
         end if;
         if not Keep_Open then
            Sockets.Close_Socket (Peer);
         end if;
      end Serve;

      procedure Serve_Put_Response
        (Key     : String;
         Headers : String;
         Payload : String := "") is
      begin
         Serve
           (HTTP_Response ("200 OK", Payload, Headers),
            "PUT", "/example-bucket/" & Key,
            Put_Response_Vector_Payload);
      end Serve_Put_Response;

      function Valid_Put_Response_Headers (Index : Positive) return String is
         Name : constant String :=
           US.To_String (Put_Response_Headers (Index).Name);
         Value : constant String :=
           US.To_String (Put_Response_Headers (Index).Value);
         Line : constant String := Name & ": " & Value & CRLF;
         ETag : constant String := "ETag: ""vector""" & CRLF;
         Customer_Algorithm : constant String :=
           "x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF;
         Customer_MD5 : constant String :=
           "x-amz-server-side-encryption-customer-key-md5: " &
           "AAAAAAAAAAAAAAAAAAAAAA==" & CRLF;
         KMS : constant String :=
           "x-amz-server-side-encryption: aws:kms" & CRLF;
      begin
         case Index is
            when 2 =>
               return Line;
            when 3 .. 12 =>
               return ETag & Line & "x-amz-checksum-type: FULL_OBJECT" &
                 CRLF;
            when 13 =>
               return ETag & "x-amz-checksum-crc32: AAAAAA==" & CRLF & Line;
            when 16 | 17 =>
               return ETag & Customer_Algorithm & Customer_MD5;
            when 18 .. 20 =>
               return ETag & KMS & Line;
            when others =>
               return ETag & Line;
         end case;
      end Valid_Put_Response_Headers;

      procedure Serve_Upload_Response
        (Key     : String;
         Headers : String;
         Payload : String := "") is
      begin
         Serve
           (HTTP_Response ("200 OK", Payload, Headers), "PUT",
            "/example-bucket/" & Key &
              "?partNumber=1&uploadId=socket-upload-response",
            Put_Response_Vector_Payload);
      end Serve_Upload_Response;

      function Valid_Upload_Response_Headers
        (Index : Positive) return String
      is
         Name : constant String :=
           US.To_String (Upload_Response_Headers (Index).Name);
         Value : constant String :=
           US.To_String (Upload_Response_Headers (Index).Value);
         Line : constant String := Name & ": " & Value & CRLF;
         ETag : constant String := "ETag: opaque-part-etag" & CRLF;
         Customer_Algorithm : constant String :=
           "x-amz-server-side-encryption-customer-algorithm: AES256" &
           CRLF;
         Customer_MD5 : constant String :=
           "x-amz-server-side-encryption-customer-key-md5: " &
           "AAAAAAAAAAAAAAAAAAAAAA==" & CRLF;
         KMS : constant String :=
           "x-amz-server-side-encryption: aws:kms" & CRLF;
      begin
         case Index is
            when 2 =>
               return Line;
            when 13 =>
               return ETag & Line & Customer_MD5;
            when 14 =>
               return ETag & Customer_Algorithm & Line;
            when 15 | 16 =>
               return ETag & KMS & Line;
            when others =>
               return ETag & Line;
         end case;
      end Valid_Upload_Response_Headers;

      Success_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/"">" &
        "<Name>example-bucket</Name><KeyCount>0</KeyCount>" &
        "<MaxKeys>2</MaxKeys><IsTruncated>false</IsTruncated>" &
        "</ListBucketResult>";
      Wrong_List_V2_Bucket_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/"">" &
        "<Name>wrong-bucket</Name><KeyCount>0</KeyCount>" &
        "<MaxKeys>2</MaxKeys><IsTruncated>false</IsTruncated>" &
        "</ListBucketResult>";
      First_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-page/</Prefix><KeyCount>1</KeyCount>" &
        "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
        "<NextContinuationToken>opaque-next</NextContinuationToken>" &
        "<Contents><Key>socket-page/a</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      Second_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-page/</Prefix>" &
        "<ContinuationToken>opaque-next</ContinuationToken>" &
        "<KeyCount>1</KeyCount><MaxKeys>1</MaxKeys>" &
        "<IsTruncated>false</IsTruncated>" &
        "<Contents><Key>socket-page/b</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      List_Buckets_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Owner><ID>socket-owner</ID></Owner>" &
        "<Buckets><Bucket><Name>socket-bucket</Name>" &
        "<CreationDate>2026-08-22T01:02:03.000Z</CreationDate>" &
        "<BucketRegion>us-east-1</BucketRegion>" &
        "<BucketArn>arn:aws:s3:::socket-bucket</BucketArn>" &
        "</Bucket></Buckets><ContinuationToken>socket-next" &
        "</ContinuationToken><Prefix>socket-</Prefix>" &
        "</ListAllMyBucketsResult>";
      Wrong_List_Buckets_Prefix_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Owner><ID>socket-owner</ID></Owner>" &
        "<Buckets><Bucket><Name>socket-bucket</Name>" &
        "<CreationDate>2026-08-22T01:02:03.000Z</CreationDate>" &
        "<BucketRegion>us-east-1</BucketRegion>" &
        "</Bucket></Buckets><Prefix>other-</Prefix>" &
        "</ListAllMyBucketsResult>";
      Oversized_List_Buckets_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Buckets>" &
        "<Bucket><Name>socket-a</Name></Bucket>" &
        "<Bucket><Name>socket-b</Name></Bucket>" &
        "</Buckets><Prefix>socket-</Prefix>" &
        "</ListAllMyBucketsResult>";
      Wrong_List_Buckets_Name_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Buckets>" &
        "<Bucket><Name>outside</Name></Bucket>" &
        "</Buckets><Prefix>socket-</Prefix>" &
        "</ListAllMyBucketsResult>";
      Wrong_List_Buckets_Region_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Buckets><Bucket><Name>socket-bucket</Name>" &
        "<BucketRegion>eu-west-1</BucketRegion></Bucket></Buckets>" &
        "<Prefix>socket-</Prefix></ListAllMyBucketsResult>";
      Second_List_Buckets_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Owner><ID>socket-owner</ID></Owner>" &
        "<Buckets><Bucket><Name>socket-second</Name>" &
        "<CreationDate>2026-08-22T01:02:04.000Z</CreationDate>" &
        "<BucketRegion>us-east-1</BucketRegion>" &
        "</Bucket></Buckets><Prefix>socket-</Prefix>" &
        "</ListAllMyBucketsResult>";
      V1_Success_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket/</Prefix><Marker>before</Marker>" &
        "<Delimiter>/</Delimiter><MaxKeys>2</MaxKeys>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>false</IsTruncated></ListBucketResult>";
      Wrong_V1_Bucket_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>wrong-bucket</Name>" &
        "<Prefix>socket/</Prefix><Marker>before</Marker>" &
        "<Delimiter>/</Delimiter><MaxKeys>2</MaxKeys>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>false</IsTruncated></ListBucketResult>";
      V1_First_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix><Marker></Marker>" &
        "<EncodingType>url</EncodingType>" &
        "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
        "<Contents><Key>socket-v1/a%20/%25%C3%A9</Key>" &
        "<Size>1</Size></Contents>" &
        "</ListBucketResult>";
      V1_Second_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix>" &
        "<Marker>socket-v1/a%20/%25%C3%A9</Marker>" &
        "<EncodingType>url</EncodingType>" &
        "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
        "<Contents><Key>socket-v1/b</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      V1_Delimiter_First_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix><Marker></Marker>" &
        "<NextMarker>socket-v1/group%20%25/%C3%A9</NextMarker>" &
        "<MaxKeys>1</MaxKeys><Delimiter>/</Delimiter>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>true</IsTruncated>" &
        "<CommonPrefixes><Prefix>socket-v1/group%20%25/%C3%A9/" &
        "</Prefix></CommonPrefixes></ListBucketResult>";
      V1_Delimiter_Second_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix>" &
        "<Marker>socket-v1/group%20%25/%C3%A9</Marker>" &
        "<MaxKeys>1</MaxKeys><Delimiter>/</Delimiter>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>false</IsTruncated></ListBucketResult>";
      V1_Malformed_Encoding_XML : constant String :=
        "<ListBucketResult><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix><Marker></Marker>" &
        "<EncodingType>url</EncodingType><MaxKeys>1</MaxKeys>" &
        "<IsTruncated>true</IsTruncated>" &
        "<Contents><Key>socket-v1/%GG</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      Versions_Complete_XML : constant String :=
        "<ListVersionsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><IsTruncated>true</IsTruncated>" &
        "<KeyMarker>logs/a</KeyMarker>" &
        "<VersionIdMarker>v+1</VersionIdMarker>" &
        "<NextKeyMarker>logs/next</NextKeyMarker>" &
        "<NextVersionIdMarker>v-next</NextVersionIdMarker>" &
        "<Version><ETag>&quot;socket-version&quot;</ETag>" &
        "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
        "<ChecksumAlgorithm>CRC32C</ChecksumAlgorithm>" &
        "<ChecksumType>FULL_OBJECT</ChecksumType>" &
        "<Size>4294967297</Size><StorageClass>STANDARD</StorageClass>" &
        "<Key>logs/object</Key><VersionId>v-object</VersionId>" &
        "<IsLatest>false</IsLatest>" &
        "<LastModified>2026-08-23T01:02:03.123Z</LastModified>" &
        "<Owner><DisplayName>socket-owner</DisplayName>" &
        "<ID>socket-owner-id</ID></Owner>" &
        "<RestoreStatus><IsRestoreInProgress>false" &
        "</IsRestoreInProgress>" &
        "<RestoreExpiryDate>2026-08-24T01:02:03Z" &
        "</RestoreExpiryDate></RestoreStatus></Version>" &
        "<DeleteMarker><Owner><ID>socket-owner-id</ID></Owner>" &
        "<Key>logs/deleted</Key><VersionId>v-delete</VersionId>" &
        "<IsLatest>true</IsLatest>" &
        "<LastModified>2026-08-23T02:03:04Z</LastModified>" &
        "</DeleteMarker><Name>example-bucket</Name>" &
        "<Prefix>logs/</Prefix><Delimiter>/</Delimiter>" &
        "<MaxKeys>3</MaxKeys>" &
        "<CommonPrefixes><Prefix>logs/group/</Prefix>" &
        "</CommonPrefixes><EncodingType>url</EncodingType>" &
        "</ListVersionsResult>";
      Versions_Empty_Echo_XML : constant String :=
        "<ListVersionsResult><IsTruncated>false</IsTruncated>" &
        "<KeyMarker></KeyMarker><VersionIdMarker></VersionIdMarker>" &
        "<Name>example-bucket</Name><Prefix></Prefix>" &
        "<Delimiter></Delimiter><MaxKeys>1</MaxKeys>" &
        "</ListVersionsResult>";
      Versions_Paged_First_XML : constant String :=
        "<ListVersionsResult><IsTruncated>true</IsTruncated>" &
        "<NextKeyMarker>paged/a%20/%25%C3%A9</NextKeyMarker>" &
        "<NextVersionIdMarker>v+1</NextVersionIdMarker>" &
        "<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
        "<Key>paged/a</Key><VersionId>v0</VersionId>" &
        "<IsLatest>false</IsLatest>" &
        "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>" &
        "<Name>example-bucket</Name><Prefix>paged/</Prefix>" &
        "<MaxKeys>1</MaxKeys><EncodingType>url</EncodingType>" &
        "</ListVersionsResult>";
      Versions_Paged_Second_XML : constant String :=
        "<ListVersionsResult><IsTruncated>false</IsTruncated>" &
        "<KeyMarker>paged/a%20/%25%C3%A9</KeyMarker>" &
        "<VersionIdMarker>v+1</VersionIdMarker>" &
        "<Name>example-bucket</Name><Prefix>paged/</Prefix>" &
        "<MaxKeys>1</MaxKeys><EncodingType>url</EncodingType>" &
        "</ListVersionsResult>";
      Versions_Bad_Marker_XML : constant String :=
        "<ListVersionsResult><IsTruncated>true</IsTruncated>" &
        "<NextKeyMarker>%GG</NextKeyMarker>" &
        "<NextVersionIdMarker>v-next</NextVersionIdMarker>" &
        "<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
        "<Key>bad-marker/item</Key><VersionId>v0</VersionId>" &
        "<IsLatest>false</IsLatest>" &
        "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>" &
        "<Name>example-bucket</Name><Prefix>bad-marker/</Prefix>" &
        "<MaxKeys>1</MaxKeys><EncodingType>url</EncodingType>" &
        "</ListVersionsResult>";

      function Final_Versions_XML
        (Name, Prefix : String;
         Maximum     : Positive := 1;
         Encoding    : Boolean := False) return String is
        ("<ListVersionsResult><IsTruncated>false</IsTruncated>" &
         "<Name>" & Name & "</Name><Prefix>" & Prefix & "</Prefix>" &
         "<MaxKeys>" & Decimal (Maximum) & "</MaxKeys>" &
         (if Encoding then "<EncodingType>url</EncodingType>" else "") &
         "</ListVersionsResult>");
      Error_XML : constant String :=
        "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
      Precondition_XML : constant String :=
        "<Error><Code>PreconditionFailed</Code>" &
        "<Message>condition failed</Message></Error>";
      function Create_Result_XML
        (Bucket, Key, Upload_ID : String) return String is
        ("<InitiateMultipartUploadResult>" &
         "<Bucket>" & Bucket & "</Bucket><Key>" & Key & "</Key>" &
         "<UploadId>" & Upload_ID & "</UploadId>" &
         "</InitiateMultipartUploadResult>");
      Create_XML : constant String :=
        Create_Result_XML ("example-bucket", "object key", "socket-upload");
      Lost_Create_List_XML : constant String :=
        "<ListMultipartUploadsResult>" &
        "<Bucket>example-bucket</Bucket><Prefix>create-lost</Prefix>" &
        "<MaxUploads>1000</MaxUploads><IsTruncated>false</IsTruncated>" &
        "<Upload><UploadId>lost-create-id</UploadId>" &
        "<Key>create-lost</Key>" &
        "<Initiated>2026-08-23T00:00:00Z</Initiated></Upload>" &
        "</ListMultipartUploadsResult>";
      Complete_XML : constant String :=
        "<CompleteMultipartUploadResult>" &
        "<Bucket>example-bucket</Bucket><Key>object key</Key>" &
        "<ETag>&quot;whole&quot;</ETag>" &
        "</CompleteMultipartUploadResult>";
      Embedded_Error_XML : constant String :=
        "<Error><Code>InternalError</Code>" &
        "<Message>late failure</Message></Error>";
      No_Such_Upload_XML : constant String :=
        "<Error><Code>NoSuchUpload</Code>" &
        "<Message>upload is absent</Message></Error>";
      List_Uploads_XML : constant String :=
        "<ListMultipartUploadsResult>" &
        "<Bucket>example-bucket</Bucket><KeyMarker>before</KeyMarker>" &
        "<UploadIdMarker>upload-before</UploadIdMarker>" &
        "<Prefix>socket/</Prefix><Delimiter>/</Delimiter>" &
        "<MaxUploads>2</MaxUploads><IsTruncated>false</IsTruncated>" &
        "<Upload><UploadId>socket-upload</UploadId><Key>socket/key</Key>" &
        "<Initiated>2026-08-21T00:00:00Z</Initiated>" &
        "<StorageClass>STANDARD</StorageClass></Upload>" &
        "</ListMultipartUploadsResult>";
      List_Uploads_Empty_XML : constant String :=
        "<ListMultipartUploadsResult><Bucket>example-bucket</Bucket>" &
        "<MaxUploads>1000</MaxUploads><IsTruncated>false</IsTruncated>" &
        "</ListMultipartUploadsResult>";
      List_Uploads_Wrong_Bucket_XML : constant String :=
        "<ListMultipartUploadsResult><Bucket>wrong-bucket</Bucket>" &
        "<MaxUploads>1000</MaxUploads><IsTruncated>false</IsTruncated>" &
        "</ListMultipartUploadsResult>";

      function Empty_List_Uploads_XML
        (Bucket, Key_Marker, Upload_ID_Marker, Prefix, Delimiter,
         Encoding_Type : String;
         Maximum : Positive) return String is
        ("<ListMultipartUploadsResult><Bucket>" & Bucket & "</Bucket>" &
         "<KeyMarker>" & Key_Marker & "</KeyMarker>" &
         "<UploadIdMarker>" & Upload_ID_Marker & "</UploadIdMarker>" &
         "<Prefix>" & Prefix & "</Prefix><Delimiter>" & Delimiter &
         "</Delimiter><MaxUploads>" & Decimal (Maximum) &
         "</MaxUploads><IsTruncated>false</IsTruncated>" &
         (if Encoding_Type'Length = 0 then ""
          else "<EncodingType>" & Encoding_Type & "</EncodingType>") &
         "</ListMultipartUploadsResult>");

      List_Uploads_First_Page_XML : constant String :=
        "<ListMultipartUploadsResult><Bucket>example-bucket</Bucket>" &
        "<KeyMarker></KeyMarker><UploadIdMarker></UploadIdMarker>" &
        "<NextKeyMarker>paged/key</NextKeyMarker>" &
        "<NextUploadIdMarker>id-1</NextUploadIdMarker>" &
        "<Prefix>paged/</Prefix><MaxUploads>1</MaxUploads>" &
        "<IsTruncated>true</IsTruncated>" &
        "<Upload><UploadId>id-1</UploadId><Key>paged/key</Key>" &
        "<Initiated>2026-08-21T00:00:00Z</Initiated>" &
        "</Upload></ListMultipartUploadsResult>";
      List_Uploads_Second_Page_XML : constant String :=
        "<ListMultipartUploadsResult><Bucket>example-bucket</Bucket>" &
        "<KeyMarker>paged/key</KeyMarker>" &
        "<UploadIdMarker>id-1</UploadIdMarker>" &
        "<Prefix>paged/</Prefix><MaxUploads>1</MaxUploads>" &
        "<IsTruncated>false</IsTruncated>" &
        "<Upload><UploadId>id-2</UploadId><Key>paged/key</Key>" &
        "<Initiated>2026-08-21T00:00:01Z</Initiated>" &
        "</Upload></ListMultipartUploadsResult>";
      List_Parts_First_XML : constant String :=
        "<ListPartsResult><Bucket>example-bucket</Bucket>" &
        "<Key>paged-parts</Key><UploadId>paged-upload</UploadId>" &
        "<PartNumberMarker>0</PartNumberMarker><MaxParts>1</MaxParts>" &
        "<IsTruncated>true</IsTruncated>" &
        "<NextPartNumberMarker>1</NextPartNumberMarker>" &
        "<Part><PartNumber>1</PartNumber>" &
        "<LastModified>2026-08-21T00:00:00Z</LastModified>" &
        "<ETag>&quot;part-1&quot;</ETag><Size>1</Size></Part>" &
        "</ListPartsResult>";
      List_Parts_Second_XML : constant String :=
        "<ListPartsResult><Bucket>example-bucket</Bucket>" &
        "<Key>paged-parts</Key><UploadId>paged-upload</UploadId>" &
        "<PartNumberMarker>1</PartNumberMarker><MaxParts>1</MaxParts>" &
        "<IsTruncated>false</IsTruncated>" &
        "<Part><PartNumber>2</PartNumber>" &
        "<LastModified>2026-08-21T00:00:01Z</LastModified>" &
        "<ETag>&quot;part-2&quot;</ETag><Size>1</Size></Part>" &
        "</ListPartsResult>";
      List_Parts_Wrong_Key_XML : constant String :=
        "<ListPartsResult><Bucket>example-bucket</Bucket>" &
        "<Key>wrong-key</Key><UploadId>paged-upload</UploadId>" &
        "<PartNumberMarker>0</PartNumberMarker><MaxParts>1</MaxParts>" &
        "<IsTruncated>false</IsTruncated></ListPartsResult>";
      List_Parts_Empty_XML : constant String :=
        "<ListPartsResult><Bucket>example-bucket</Bucket>" &
        "<Key>paged-parts</Key><UploadId>paged-upload</UploadId>" &
        "<PartNumberMarker>0</PartNumberMarker><MaxParts>1</MaxParts>" &
        "<IsTruncated>false</IsTruncated></ListPartsResult>";

      function Empty_List_Parts_XML
        (Bucket, Key, Upload_ID : String;
         Marker : Multipart.Part_Marker_Value;
         Maximum : Flyology.Object_Storage.S3.Core.Page_Size)
         return String is
        ("<ListPartsResult><Bucket>" & Bucket & "</Bucket><Key>" & Key &
         "</Key><UploadId>" & Upload_ID & "</UploadId>" &
         "<PartNumberMarker>" & Decimal (Marker) &
         "</PartNumberMarker><MaxParts>" & Decimal (Maximum) &
         "</MaxParts><IsTruncated>false</IsTruncated>" &
         "</ListPartsResult>");
      Copy_XML : constant String :=
        "<CopyObjectResult>" &
        "<LastModified>2026-08-21T17:00:00.000Z</LastModified>" &
        "<ETag>&quot;high-level-copy&quot;</ETag>" &
        "</CopyObjectResult>";
      Copy_Part_XML : constant String :=
        "<CopyPartResult>" &
        "<LastModified>2026-08-21T17:00:00.000Z</LastModified>" &
        "<ETag>&quot;copied-part&quot;</ETag>" &
        "</CopyPartResult>";
      Attributes_XML : constant String :=
        "<GetObjectAttributesResponse>" &
        "<ETag>&quot;socket-attributes&quot;</ETag>" &
        "<ObjectParts><PartsCount>2</PartsCount>" &
        "<PartNumberMarker>1</PartNumberMarker>" &
        "<MaxParts>1</MaxParts><IsTruncated>true</IsTruncated>" &
        "<NextPartNumberMarker>2</NextPartNumberMarker>" &
        "<Part><PartNumber>2</PartNumber><Size>7</Size></Part>" &
        "</ObjectParts><ObjectSize>14</ObjectSize>" &
        "</GetObjectAttributesResponse>";
      Tagging_XML : constant String :=
        "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<TagSet><Tag><Key>project</Key><Value>flyology</Value></Tag>" &
        "</TagSet></Tagging>";
      Delete_Objects_XML : constant String :=
        "<DeleteResult xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Deleted><Key>socket-delete-a</Key><VersionId>version-a</VersionId>" &
        "<DeleteMarker>false</DeleteMarker>" &
        "<DeleteMarkerVersionId>marker-a</DeleteMarkerVersionId>" &
        "</Deleted><Error><Key>socket-delete-b</Key>" &
        "<VersionId>version-b</VersionId><Code>AccessDenied</Code>" &
        "<Message>denied</Message></Error></DeleteResult>";
   begin
      Sockets.Create_Socket (Listener);
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Any_Port));
      Sockets.Listen_Socket (Listener);
      Port := Sockets.Get_Socket_Name (Listener).Port;
      State.Publish (Port);
      for Round in 1 .. 2 loop
         Serve
           (HTTP_Response
              ("200 OK", "", "etag: ""scoped-generation""" & CRLF),
            "PUT", "/example-bucket/scoped-put",
            Expected_Body_Root => "scoped-put-body",
            Expected_If_None_Match => "*");
         Serve
           (HTTP_Response
              ("412 Precondition Failed",
               "<Error><Code>PreconditionFailed</Code>" &
                 "<Message>condition failed</Message></Error>"),
            "PUT", "/example-bucket/scoped-cas",
            Expected_Body_Root => "scoped-cas-body",
            Expected_If_Match => """scoped-generation""");
         Serve
           (HTTP_Response
              ("200 OK", "scoped-get-body",
               "etag: ""scoped-generation""" & CRLF &
                 "x-amz-version-id: scoped-version" & CRLF),
            "GET", "/example-bucket/scoped-get",
            Expected_If_Match => """scoped-generation""");
         Serve
           (HTTP_Response
              ("200 OK", String'(1 .. 112 => 'x'),
               "etag: ""oversized-generation""" & CRLF),
            "GET", "/example-bucket/scoped-oversized");
         Serve
           (HTTP_Response
              ("206 Partial Content", "2345",
               "content-range: bytes 2-5/10" & CRLF &
                 "etag: ""range-generation""" & CRLF),
            "GET", "/example-bucket/scoped-range",
            Expected_If_Match => """range-generation""",
            Expected_Range => "bytes=2-5");
         Serve
           (HTTP_Response
              ("206 Partial Content", "6789",
               "content-range: bytes 6-9/10" & CRLF &
                 "etag: ""range-generation""" & CRLF),
            "GET", "/example-bucket/scoped-range-open",
            Expected_If_Match => """range-generation""",
            Expected_Range => "bytes=6-");
         Serve
           (HTTP_Response
              ("206 Partial Content", "789",
               "content-range: bytes 7-9/10" & CRLF &
                 "etag: ""range-generation""" & CRLF),
            "GET", "/example-bucket/scoped-range-suffix",
            Expected_If_Match => """range-generation""",
            Expected_Range => "bytes=-3");
         Serve
           (HTTP_Response
              ("206 Partial Content", "3456",
               "content-range: bytes 3-6/10" & CRLF &
                 "etag: ""range-generation""" & CRLF),
            "GET", "/example-bucket/scoped-range-wrong",
            Expected_If_Match => """range-generation""",
            Expected_Range => "bytes=2-5");
         Serve
           (HTTP_Response
              ("412 Precondition Failed",
               "<Error><Code>PreconditionFailed</Code>" &
                 "<Message>condition failed</Message></Error>"),
            "GET", "/example-bucket/scoped-range-rejected",
            Expected_If_Match => """stale-generation""",
            Expected_Range => "bytes=2-5");
         Serve
           (HTTP_Response
              ("206 Partial Content", "2345",
               "content-range: bytes 2-5/10" & CRLF &
                 "etag: ""range-generation""" & CRLF &
                 "etag: ""range-generation""" & CRLF),
            "GET", "/example-bucket/scoped-range-duplicate",
            Expected_If_Match => """range-generation""",
            Expected_Range => "bytes=2-5");
         Serve
           (HTTP_Response
              ("206 Partial Content", "23456",
               "content-range: bytes 2-6/10" & CRLF &
                 "etag: ""range-generation""" & CRLF),
            "GET", "/example-bucket/scoped-range-oversized",
            Expected_If_Match => """range-generation""",
            Expected_Range => "bytes=2-6");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "content-length: 10" & CRLF &
                 "etag: ""head-generation""" & CRLF &
                 "last-modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
                 "x-amz-version-id: head-version" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/scoped-head?versionId=head-version",
            Expected_If_Match => """head-generation""");
         Serve
           (HTTP_Response
              ("404 Not Found", "",
               "x-amz-request-id: scoped-head-request" & CRLF &
                 "x-amz-id-2: scoped-head-host" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/scoped-head-missing");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "content-length: 10" & CRLF &
                 "etag: ""head-generation""" & CRLF &
                 "etag: ""head-generation""" & CRLF &
                 "last-modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/scoped-head-duplicate");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "location: /typed-created" & CRLF &
                 "x-amz-bucket-arn: arn:aws:s3:::typed-created" & CRLF),
            "PUT", "/typed-created",
            Expected_Body_Root => "<CreateBucketConfiguration",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK", "", "location: /convenience-created" & CRLF),
            "PUT", "/convenience-created",
            Expected_Body_Root => "<CreateBucketConfiguration");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "location: /duplicate-create-a" & CRLF &
                 "location: /duplicate-create-b" & CRLF),
            "PUT", "/duplicate-create",
            Expected_Body_Root => "<CreateBucketConfiguration");
         Serve
           (HTTP_Response
              ("200 OK", "", "location: /restart-created" & CRLF),
            "PUT", "/restart-created",
            Expected_Body_Root => "<CreateBucketConfiguration");
         Serve
           (HTTP_Response
              ("409 Conflict",
               "<Error><Code>BucketAlreadyOwnedByYou</Code>" &
                 "<Message>already owned</Message></Error>",
               "x-amz-request-id: restarted-create-request" & CRLF),
            "PUT", "/restart-existing",
            Expected_Body_Root => "<CreateBucketConfiguration");
         Serve
           (HTTP_Response ("204 No Content", ""),
            "DELETE",
            "/typed-deleted",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""),
            "DELETE",
            "/composed-deleted",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("409 Conflict",
               "<Error><Code>BucketNotEmpty</Code>"
               & "<Message>not empty</Message></Error>",
               "x-amz-request-id: restarted-delete-request" & CRLF),
            "DELETE",
            "/restart-nonempty",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<LocationConstraint xmlns=""http://s3.amazonaws.com/doc/" &
                 "2006-03-01/"">us-west-2</LocationConstraint>"),
            "GET",
            "/typed-location?location",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK",
               "<LocationConstraint xmlns=""http://s3.amazonaws.com/doc/" &
                 "2006-03-01/""></LocationConstraint>"),
            "GET",
            "/composed-location?location",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden",
               "<Error><Code>AccessDenied</Code>" &
                 "<Message>denied</Message></Error>",
               "x-amz-request-id: restarted-location-request" & CRLF),
            "GET",
            "/restart-location?location",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-bucket-arn: arn:aws:s3:::example-bucket" & CRLF &
                 "x-amz-bucket-location-type: AvailabilityZone" & CRLF &
                 "x-amz-bucket-location-name: use1-az1" & CRLF &
                 "x-amz-bucket-region: us-east-1" & CRLF &
                 "x-amz-access-point-alias: false" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("404 Not Found", "",
               "x-amz-request-id: head-bucket-request" & CRLF &
                 "x-amz-id-2: head-bucket-host" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/missing-bucket",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-bucket-region: us-east-1" & CRLF &
                 "x-amz-bucket-region: us-west-2" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/duplicate-bucket",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-bucket-region: us-east-1" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/restart-bucket",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", "",
               "x-amz-request-id: restarted-head-bucket-request" & CRLF &
                 "x-amz-id-2: restarted-head-bucket-host" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/restarted-bucket",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-delete-marker: true" & CRLF &
                 "x-amz-version-id: scoped-deleted-version" & CRLF &
                 "x-amz-request-charged: requester" & CRLF),
            "DELETE",
            "/example-bucket/scoped-delete?" &
              "versionId=scoped-delete-version",
            Expected_If_Match => """scoped-delete-generation""",
            Expected_Request_Payer => "requester");
         Serve
           (HTTP_Response ("412 Precondition Failed", Precondition_XML),
            "DELETE", "/example-bucket/scoped-delete-stale",
            Expected_If_Match => """stale-delete-generation""");
         Serve
           (HTTP_Response
              ("409 Conflict",
               "<Error><Code>OperationAborted</Code>" &
                 "<Message>conflict</Message></Error>"),
            "DELETE", "/example-bucket/scoped-delete-conflict");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-version-id: duplicate-a" & CRLF &
                 "x-amz-version-id: duplicate-b" & CRLF),
            "DELETE", "/example-bucket/scoped-delete-duplicate");
         Serve
           (HTTP_Response ("200 OK", List_Buckets_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: list-buckets-request" & CRLF &
               "x-amz-id-2: list-buckets-host" & CRLF),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", List_Buckets_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: scoped-list-buckets-request" & CRLF &
               "x-amz-id-2: scoped-list-buckets-host" & CRLF),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", Wrong_List_Buckets_Prefix_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response
              ("200 OK", List_Buckets_XML,
               "x-amz-request-id: duplicate-a" & CRLF &
               "x-amz-request-id: duplicate-b" & CRLF),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", Oversized_List_Buckets_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", Wrong_List_Buckets_Name_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", Wrong_List_Buckets_Region_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", List_Buckets_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response ("200 OK", Second_List_Buckets_XML),
            "GET", "/?bucket-region=us-east-1&" &
              "continuation-token=socket-next&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response
              ("200 OK", V1_Success_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: v1-socket-request" & CRLF &
               "x-amz-id-2: v1-socket-host" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response
              ("200 OK", V1_Success_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: v1-scoped-request" & CRLF &
               "x-amz-id-2: v1-scoped-host" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", Wrong_V1_Bucket_XML),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response
              ("200 OK", V1_Success_XML,
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response
              ("200 OK", V1_Success_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", V1_First_Page_XML), "GET",
            "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Second_Page_XML), "GET",
            "/example-bucket?encoding-type=url&" &
              "marker=socket-v1%2Fa%20%2F%25%C3%A9&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_First_Page_XML), "GET",
            "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=socket-v1%2F",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", V1_Second_Page_XML), "GET",
            "/example-bucket?encoding-type=url&" &
              "marker=socket-v1%2Fa%20%2F%25%C3%A9&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Delimiter_First_XML), "GET",
            "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "max-keys=1&prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Delimiter_Second_XML), "GET",
            "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=socket-v1%2Fgroup%20%25%2F%C3%A9&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Malformed_Encoding_XML), "GET",
            "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response
              ("200 OK", Success_XML,
               "x-amz-request-charged: requester" & CRLF), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK", Success_XML,
               "x-amz-request-charged: requester" & CRLF), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", Wrong_List_V2_Bucket_XML), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response
              ("200 OK", Success_XML,
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: socket-request" & CRLF &
               "x-amz-id-2: socket-host" & CRLF),
            "GET", "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", String'(1 .. 256 => 'x')), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", First_Page_XML), "GET",
            "/example-bucket?list-type=2&max-keys=1&" &
              "prefix=socket-page%2F");
         Serve
           (HTTP_Response ("200 OK", Second_Page_XML), "GET",
            "/example-bucket?continuation-token=opaque-next&" &
              "list-type=2&max-keys=1&prefix=socket-page%2F");
         Serve
           (HTTP_Response ("200 OK", First_Page_XML), "GET",
            "/example-bucket?list-type=2&max-keys=1&" &
              "prefix=socket-page%2F");
         Serve
           (HTTP_Response ("200 OK", Second_Page_XML), "GET",
            "/example-bucket?continuation-token=opaque-next&" &
              "list-type=2&max-keys=1&prefix=socket-page%2F");
         Serve
           (HTTP_Response
              ("200 OK", List_Uploads_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&key-marker=before&" &
              "max-uploads=2&prefix=socket%2F&" &
              "upload-id-marker=upload-before&uploads",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: list-uploads-request" & CRLF &
               "x-amz-id-2: list-uploads-host" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&key-marker=before&" &
              "max-uploads=2&prefix=socket%2F&" &
              "upload-id-marker=upload-before&uploads",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", List_Uploads_Wrong_Bucket_XML),
            "GET", "/example-bucket?max-uploads=1000&uploads");
         Serve
           (HTTP_Response
              ("200 OK", List_Uploads_Empty_XML,
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?max-uploads=1000&uploads");
         Serve
           (HTTP_Response
              ("200 OK", List_Uploads_Empty_XML,
               "x-amz-request-charged:" & CRLF),
            "GET", "/example-bucket?max-uploads=1000&uploads");
         Serve
           (HTTP_Response
              ("200 OK", List_Uploads_Empty_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?max-uploads=1000&uploads");
         declare
            Query : constant String :=
              "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "key-marker=a%2Bb&max-uploads=7&" &
              "prefix=photos%2FJan%20%26&" &
              "upload-id-marker=upload%2B%2F%3D&uploads";
         begin
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("wrong-bucket", "a%2Bb", "upload+/=",
                     "photos/Jan%20%26", "/", "url", 7)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("example-bucket", "wrong-marker", "upload+/=",
                     "photos/Jan%20%26", "/", "url", 7)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("example-bucket", "a%2Bb", "wrong-upload",
                     "photos/Jan%20%26", "/", "url", 7)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("example-bucket", "a%2Bb", "upload+/=", "wrong",
                     "/", "url", 7)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("example-bucket", "a%2Bb", "upload+/=",
                     "photos/Jan%20%26", "!", "url", 7)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("example-bucket", "a%2Bb", "upload+/=",
                     "photos/Jan%20%26", "/", "url", 6)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
            Serve
              (HTTP_Response
                 ("200 OK", Empty_List_Uploads_XML
                    ("example-bucket", "a%2Bb", "upload+/=",
                     "photos/Jan%20%26", "/", "", 7)),
               "GET", Query, Expected_Request_Payer => "requester",
               Expected_Bucket_Owner => "123456789012");
         end;
         Serve
           (HTTP_Response ("200 OK", List_Uploads_First_Page_XML), "GET",
            "/example-bucket?max-uploads=1&prefix=paged%2F&uploads",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", List_Uploads_Second_Page_XML), "GET",
            "/example-bucket?key-marker=paged%2Fkey&max-uploads=1&" &
              "prefix=paged%2F&upload-id-marker=id-1&uploads");
         Serve
           (HTTP_Response ("200 OK", List_Parts_First_XML), "GET",
            "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", List_Parts_Second_XML), "GET",
            "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=1&uploadId=paged-upload");
         Serve
           (HTTP_Response ("200 OK", List_Parts_Wrong_Key_XML), "GET",
            "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", List_Parts_Empty_XML,
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", List_Parts_Empty_XML,
               "x-amz-request-charged:" & CRLF),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", List_Parts_Empty_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", Empty_List_Parts_XML
                 ("wrong-bucket", "paged-parts", "paged-upload", 0, 1)),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", Empty_List_Parts_XML
                 ("example-bucket", "paged-parts", "wrong-upload", 0, 1)),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", Empty_List_Parts_XML
                 ("example-bucket", "paged-parts", "paged-upload", 1, 1)),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response
              ("200 OK", Empty_List_Parts_XML
                 ("example-bucket", "paged-parts", "paged-upload", 0, 2)),
            "GET", "/example-bucket/paged-parts?max-parts=1&" &
              "part-number-marker=0&uploadId=paged-upload");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?versioning",
            Expected_Body_Root => "<VersioningConfiguration",
            Expected_Bucket_Owner => "123456789012",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK",
               "<VersioningConfiguration>" &
               "<Status>Enabled</Status>" &
               "</VersioningConfiguration>"),
            "GET", "/example-bucket?versioning",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?versioning",
            Expected_Body_Root => "<Status>Suspended</Status>",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK",
               "<VersioningConfiguration>" &
               "<Status>Suspended</Status>" &
               "</VersioningConfiguration>"),
            "GET", "/example-bucket?versioning", Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK",
               "<VersioningConfiguration>" &
                 "<Status>Enabled</Status>" &
                 "</VersioningConfiguration>"),
            "GET", "/typed-versioning?versioning",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK", "<VersioningConfiguration/>"),
            "GET", "/composed-versioning?versioning",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden",
               "<Error><Code>AccessDenied</Code>" &
                 "<Message>denied</Message></Error>",
               "x-amz-request-id: restarted-versioning-request" & CRLF),
            "GET", "/restart-versioning?versioning",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/typed-put-versioning?versioning",
            Expected_Body_Root => "<Status>Enabled</Status>",
            Expected_Bucket_Owner => "123456789012",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/composed-put-versioning?versioning",
            Expected_Body_Root => "<Status>Suspended</Status>",
            Expected_Bucket_Owner => "123456789012",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("403 Forbidden",
               "<Error><Code>AccessDenied</Code>" &
                 "<Message>denied</Message></Error>",
               "x-amz-request-id: restarted-put-versioning-request" & CRLF),
            "PUT", "/restart-put-versioning?versioning",
            Expected_Body_Root => "<Status>Enabled</Status>",
            Expected_Bucket_Owner => "123456789012",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", Omit_Content_Length => True),
            "HEAD", "/example-bucket");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""model-stream""" & CRLF),
            "PUT", "/example-bucket/model-stream", "u");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "ETag: ""typed-put""" & CRLF &
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF &
               "x-amz-server-side-encryption: aws:kms" & CRLF &
               "x-amz-server-side-encryption-aws-kms-key-id: kms-key" &
               CRLF &
               "x-amz-version-id: put-version" & CRLF &
               "x-amz-server-side-encryption-bucket-key-enabled: true" &
               CRLF & "x-amz-object-size: 1" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/typed-put", "u");
         Serve_Put_Response
           ("put-response-minimal", "ETag: ""vector""" & CRLF);
         Serve_Put_Response
           ("put-response-body", "ETag: ""vector""" & CRLF, "x");
         for Index in Put_Response_Headers'Range loop
            declare
               Name : constant String :=
                 US.To_String (Put_Response_Headers (Index).Name);
               Value : constant String :=
                 US.To_String (Put_Response_Headers (Index).Value);
               Baseline : constant String :=
                 (if Name = "etag" then "" else "ETag: ""vector""" & CRLF);
            begin
               Serve_Put_Response
                 ("put-response-valid-" & Decimal (Index),
                  Valid_Put_Response_Headers (Index));
               Serve_Put_Response
                 ("put-response-empty-" & Decimal (Index),
                  Baseline & Name & ":" & CRLF);
               Serve_Put_Response
                 ("put-response-duplicate-" & Decimal (Index),
                  Baseline & Name & ": " & Value & CRLF &
                    Name & ": " & Value & CRLF);
            end;
         end loop;
         Serve_Put_Response
           ("put-size-zero",
            "ETag: ""vector""" & CRLF & "x-amz-object-size: 0" & CRLF);
         Serve_Put_Response
           ("put-size-maximum",
            "ETag: ""vector""" & CRLF &
              "x-amz-object-size: 9223372036854775807" & CRLF);
         Serve_Put_Response
           ("put-size-leading-zero",
            "ETag: ""vector""" & CRLF & "x-amz-object-size: 00" & CRLF);
         Serve_Put_Response
           ("put-size-negative",
            "ETag: ""vector""" & CRLF & "x-amz-object-size: -1" & CRLF);
         Serve_Put_Response
           ("put-size-overflow",
            "ETag: ""vector""" & CRLF &
              "x-amz-object-size: 9223372036854775808" & CRLF);
         Serve_Put_Response
           ("put-bucket-key-invalid-case",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: aws:kms" & CRLF &
              "x-amz-server-side-encryption-bucket-key-enabled: TRUE" &
              CRLF);
         Serve_Put_Response
           ("put-bucket-key-invalid-digit",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: aws:kms" & CRLF &
              "x-amz-server-side-encryption-bucket-key-enabled: 1" & CRLF);
         Serve_Put_Response
           ("put-checksum-without-type",
            "ETag: ""vector""" & CRLF &
              "x-amz-checksum-crc32: AAAAAA==" & CRLF);
         Serve_Put_Response
           ("put-checksum-type-without-value",
            "ETag: ""vector""" & CRLF &
              "x-amz-checksum-type: FULL_OBJECT" & CRLF);
         Serve_Put_Response
           ("put-checksum-composite",
            "ETag: ""vector""" & CRLF &
              "x-amz-checksum-crc32: AAAAAA==" & CRLF &
              "x-amz-checksum-type: COMPOSITE" & CRLF);
         Serve_Put_Response
           ("put-checksum-multiple",
            "ETag: ""vector""" & CRLF &
              "x-amz-checksum-crc32: AAAAAA==" & CRLF &
              "x-amz-checksum-sha256: " &
              "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" & CRLF &
              "x-amz-checksum-type: FULL_OBJECT" & CRLF);
         for Index in 3 .. 12 loop
            Serve_Put_Response
              ("put-checksum-malformed-" & Decimal (Index),
               "ETag: ""vector""" & CRLF &
                 US.To_String (Put_Response_Headers (Index).Name) &
                 ": AAAA" & CRLF &
                 "x-amz-checksum-type: FULL_OBJECT" & CRLF);
         end loop;
         Serve_Put_Response ("put-etag-missing", "");
         Serve_Put_Response ("put-etag-unquoted", "ETag: vector" & CRLF);
         Serve_Put_Response
           ("put-etag-weak", "ETag: W/""vector""" & CRLF);
         Serve_Put_Response
           ("put-encryption-invalid-enum",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: unknown" & CRLF);
         Serve_Put_Response
           ("put-request-charged-invalid-enum",
            "ETag: ""vector""" & CRLF &
              "x-amz-request-charged: owner" & CRLF);
         Serve_Put_Response
           ("put-ssec-invalid-algorithm",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption-customer-algorithm: AES128" &
              CRLF &
              "x-amz-server-side-encryption-customer-key-md5: " &
              "AAAAAAAAAAAAAAAAAAAAAA==" & CRLF);
         Serve_Put_Response
           ("put-ssec-invalid-md5",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption-customer-algorithm: AES256" &
              CRLF &
              "x-amz-server-side-encryption-customer-key-md5: AAAA" &
              CRLF);
         Serve_Put_Response
           ("put-kms-context-invalid-base64",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: aws:kms" & CRLF &
              "x-amz-server-side-encryption-context: not-base64" & CRLF);
         Serve_Put_Response
           ("put-expiration-over-limit",
            "ETag: ""vector""" & CRLF & "x-amz-expiration: " &
              String'(1 .. 8_193 => 'e') & CRLF);
         Serve_Put_Response
           ("put-version-over-limit",
            "ETag: ""vector""" & CRLF & "x-amz-version-id: " &
              String'(1 .. 8_193 => 'v') & CRLF);
         Serve_Put_Response
           ("put-kms-key-over-limit",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: aws:kms" & CRLF &
              "x-amz-server-side-encryption-aws-kms-key-id: " &
              String'(1 .. 8_193 => 'k') & CRLF);
         Serve_Put_Response
           ("put-ssec-incomplete",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption-customer-algorithm: AES256" &
              CRLF);
         Serve_Put_Response
           ("put-kms-key-without-encryption",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption-aws-kms-key-id: kms-key" & CRLF);
         Serve_Put_Response
           ("put-bucket-key-without-encryption",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption-bucket-key-enabled: true" &
              CRLF);
         Serve_Put_Response
           ("put-dsse-bucket-key",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: aws:kms:dsse" & CRLF &
              "x-amz-server-side-encryption-bucket-key-enabled: true" &
              CRLF);
         Serve_Put_Response
           ("put-mixed-customer-kms",
            "ETag: ""vector""" & CRLF &
              "x-amz-server-side-encryption: aws:kms" & CRLF &
              "x-amz-server-side-encryption-customer-algorithm: AES256" &
              CRLF &
              "x-amz-server-side-encryption-customer-key-md5: " &
              "AAAAAAAAAAAAAAAAAAAAAA==" & CRLF);
         Serve_Upload_Response
           ("upload-response-minimal", "ETag: opaque-part-etag" & CRLF);
         Serve_Upload_Response
           ("upload-response-composed-first",
            "ETag: composed-part-first" & CRLF);
         Serve_Upload_Response
           ("upload-response-composed-second",
            "ETag: composed-part-second" & CRLF);
         Serve_Upload_Response
           ("upload-response-body", "ETag: opaque-part-etag" & CRLF, "x");
         for Index in Upload_Response_Headers'Range loop
            declare
               Name : constant String :=
                 US.To_String (Upload_Response_Headers (Index).Name);
               Value : constant String :=
                 US.To_String (Upload_Response_Headers (Index).Value);
               Baseline : constant String :=
                 (if Name = "etag" then ""
                  else "ETag: opaque-part-etag" & CRLF);
            begin
               Serve_Upload_Response
                 ("upload-response-valid-" & Decimal (Index),
                  Valid_Upload_Response_Headers (Index));
               Serve_Upload_Response
                 ("upload-response-empty-" & Decimal (Index),
                  Baseline & Name & ":" & CRLF);
               Serve_Upload_Response
                 ("upload-response-duplicate-" & Decimal (Index),
                  Baseline & Name & ": " & Value & CRLF &
                    Name & ": " & Value & CRLF);
            end;
         end loop;
         for Index in 3 .. 12 loop
            Serve_Upload_Response
              ("upload-checksum-malformed-" & Decimal (Index),
               "ETag: opaque-part-etag" & CRLF &
                 US.To_String (Upload_Response_Headers (Index).Name) &
                 ": AAAA" & CRLF);
         end loop;
         Serve_Upload_Response
           ("upload-checksum-multiple", "ETag: opaque-part-etag" & CRLF &
            "x-amz-checksum-crc32: AAAAAA==" & CRLF &
            "x-amz-checksum-sha256: " &
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" & CRLF);
         Serve_Upload_Response
           ("upload-ssec-incomplete", "ETag: opaque-part-etag" & CRLF &
            "x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF);
         Serve_Upload_Response
           ("upload-kms-key-without-encryption",
            "ETag: opaque-part-etag" & CRLF &
            "x-amz-server-side-encryption-aws-kms-key-id: kms-key" & CRLF);
         Serve_Upload_Response
           ("upload-bucket-key-without-encryption",
            "ETag: opaque-part-etag" & CRLF &
            "x-amz-server-side-encryption-bucket-key-enabled: true" & CRLF);
         Serve_Upload_Response
           ("upload-dsse-bucket-key", "ETag: opaque-part-etag" & CRLF &
            "x-amz-server-side-encryption: aws:kms:dsse" & CRLF &
            "x-amz-server-side-encryption-bucket-key-enabled: true" & CRLF);
         Serve_Upload_Response
           ("upload-mixed-customer-kms", "ETag: opaque-part-etag" & CRLF &
            "x-amz-server-side-encryption: aws:kms" & CRLF &
            "x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            "AAAAAAAAAAAAAAAAAAAAAA==" & CRLF);
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: bound-part" & CRLF &
               "x-amz-checksum-sha256: " &
               Put_Response_Vector_SHA256 & CRLF),
            "PUT", "/example-bucket/upload-bind-exact?partNumber=1&" &
              "uploadId=socket-upload-response",
            Put_Response_Vector_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => Put_Response_Vector_SHA256);
         --  Prime a reused connection, accept exactly one one-shot part PUT,
         --  then lose its response.  The next request must be ListParts
         --  reconciliation; a transparent retry desynchronizes this oracle.
         Serve
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF &
            "ETag: ""lost-prime""" & CRLF &
            "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
            "Connection: keep-alive" & CRLF & CRLF,
            "HEAD", "/example-bucket/lost-upload-prime",
            Keep_Open => True);
         Serve
           ("", "PUT", "/example-bucket/lost-upload?partNumber=1&" &
              "uploadId=lost-upload-id", Lost_Upload_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => Lost_Upload_SHA256,
            Reuse_Peer => True);
         Serve
           (HTTP_Response
              ("200 OK",
               "<ListPartsResult><Bucket>example-bucket</Bucket>" &
               "<Key>lost-upload</Key><UploadId>lost-upload-id</UploadId>" &
               "<PartNumberMarker>0</PartNumberMarker>" &
               "<MaxParts>1000</MaxParts><IsTruncated>false" &
               "</IsTruncated><Part><PartNumber>1</PartNumber>" &
               "<LastModified>2026-08-21T17:00:00Z</LastModified>" &
               "<ETag>&quot;lost-part&quot;</ETag><Size>" &
               Decimal (Lost_Upload_Payload'Length) & "</Size>" &
               "<ChecksumSHA256>" & Lost_Upload_SHA256 &
               "</ChecksumSHA256></Part><ChecksumAlgorithm>SHA256" &
               "</ChecksumAlgorithm><ChecksumType>COMPOSITE</ChecksumType>" &
               "</ListPartsResult>"),
            "GET", "/example-bucket/lost-upload?max-parts=1000&" &
              "part-number-marker=0&uploadId=lost-upload-id");
         --  Accept the exact one-shot completion body, publish the object,
         --  and lose the response. The client must reconcile with GET next;
         --  a transparent completion replay desynchronizes this oracle.
         Serve
           ("", "POST",
            "/example-bucket/lost-upload?uploadId=lost-upload-id",
            "<CompleteMultipartUpload");
         Serve
           (HTTP_Response
              ("200 OK", Lost_Upload_Payload,
               "ETag: ""lost-whole""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-sha256: " & Lost_Upload_SHA256 & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "GET", "/example-bucket/lost-upload",
            Expected_If_Match => """lost-whole""",
            Expected_Checksum_Mode => "ENABLED");
         --  Accept exactly one one-shot abort and lose its response. The next
         --  request must be exact-upload ListParts reconciliation; a replayed
         --  DELETE desynchronizes this oracle.
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("example-bucket", "lost-abort", "lost-abort-id")),
            "POST", "/example-bucket/lost-abort?uploads");
         Serve
           ("", "DELETE",
            "/example-bucket/lost-abort?uploadId=lost-abort-id");
         Serve
           (HTTP_Response ("404 Not Found", No_Such_Upload_XML), "GET",
            "/example-bucket/lost-abort?max-parts=1000&" &
              "part-number-marker=0&uploadId=lost-abort-id");
         --  Prime a reused connection, accept exactly one one-shot copied
         --  part, and lose its response. The next request must be ListParts
         --  reconciliation; a transparent retry desynchronizes this oracle.
         Serve
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF &
            "ETag: ""lost-copy-prime""" & CRLF &
            "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
            "Connection: keep-alive" & CRLF & CRLF,
            "HEAD", "/example-bucket/lost-copy-part-prime",
            Keep_Open => True);
         Serve
           ("", "PUT", "/example-bucket/lost-copy-part?partNumber=1&" &
              "uploadId=lost-copy-part-id",
            Expected_Copy_Source => "source-bucket/source-key",
            Reuse_Peer => True);
         Serve
           (HTTP_Response
              ("200 OK",
               "<ListPartsResult><Bucket>example-bucket</Bucket>" &
               "<Key>lost-copy-part</Key>" &
               "<UploadId>lost-copy-part-id</UploadId>" &
               "<PartNumberMarker>0</PartNumberMarker>" &
               "<MaxParts>1000</MaxParts><IsTruncated>false" &
               "</IsTruncated><Part><PartNumber>1</PartNumber>" &
               "<LastModified>2026-08-21T17:00:00Z</LastModified>" &
               "<ETag>&quot;lost-copy-part&quot;</ETag><Size>17</Size>" &
               "</Part></ListPartsResult>"),
            "GET", "/example-bucket/lost-copy-part?max-parts=1000&" &
              "part-number-marker=0&uploadId=lost-copy-part-id");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: bound-part" & CRLF &
               "x-amz-checksum-crc32: AAAAAA==" & CRLF),
            "PUT", "/example-bucket/upload-bind-wrong-algorithm?" &
              "partNumber=1&uploadId=socket-upload-response",
            Put_Response_Vector_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => Put_Response_Vector_SHA256);
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: bound-part" & CRLF &
               "x-amz-checksum-sha256: " & Wrong_SHA256 & CRLF),
            "PUT", "/example-bucket/upload-bind-wrong-value?partNumber=1&" &
              "uploadId=socket-upload-response",
            Put_Response_Vector_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => Put_Response_Vector_SHA256);
         Serve
           (HTTP_Response
              ("200 OK", "",
               "ETag: ""convenience-put""" & CRLF &
               "x-amz-checksum-crc32: " & Convenience_Put_CRC32 & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF &
               "x-amz-object-size: " &
               Decimal (Convenience_Put_Payload'Length) & CRLF),
            "PUT", "/example-bucket/convenience-put",
            Convenience_Put_Payload,
            Expected_Content_Type => "text/plain",
            Expected_Content_MD5 => Convenience_Put_MD5,
            Expected_If_None_Match => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => Convenience_Put_CRC32,
            Expected_Cache_Control => "no-cache",
            Expected_Content_Disposition => "inline",
            Expected_Content_Encoding => "gzip",
            Expected_Content_Language => "en-CA",
            Expected_Expires => "Fri, 24 May 2013 00:00:00 GMT",
            Expected_Tagging => "team%2Bname=storage%2Fada",
            Expected_User_Metadata_Name => "project",
            Expected_User_Metadata_Value => "flyology",
            Expected_Website_Redirect => "/next");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "ETag: ""composable-put-first""" & CRLF &
               "x-amz-checksum-crc32: " & Convenience_Put_CRC32 & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "PUT", "/example-bucket/composable-put-first",
            Convenience_Put_Payload,
            Expected_Content_Type => "text/plain",
            Expected_Content_MD5 => Convenience_Put_MD5,
            Expected_If_None_Match => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => Convenience_Put_CRC32,
            Expected_Cache_Control => "no-cache",
            Expected_Content_Disposition => "inline",
            Expected_Content_Encoding => "gzip",
            Expected_Content_Language => "en-CA",
            Expected_Expires => "Fri, 24 May 2013 00:00:00 GMT",
            Expected_Tagging => "team%2Bname=storage%2Fada",
            Expected_User_Metadata_Name => "project",
            Expected_User_Metadata_Value => "flyology",
            Expected_Website_Redirect => "/next");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "ETag: ""composable-put-second""" & CRLF &
               "x-amz-checksum-crc32: " & Convenience_Put_CRC32 & CRLF),
            "PUT", "/example-bucket/composable-put-second",
            Convenience_Put_Payload,
            Expected_Content_Type => "text/plain",
            Expected_Content_MD5 => Convenience_Put_MD5,
            Expected_If_None_Match => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => Convenience_Put_CRC32,
            Expected_Cache_Control => "no-cache",
            Expected_Content_Disposition => "inline",
            Expected_Content_Encoding => "gzip",
            Expected_Content_Language => "en-CA",
            Expected_Expires => "Fri, 24 May 2013 00:00:00 GMT",
            Expected_Tagging => "team%2Bname=storage%2Fada",
            Expected_User_Metadata_Name => "project",
            Expected_User_Metadata_Value => "flyology",
            Expected_Website_Redirect => "/next");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "ETag: ""composable-put-mismatch""" & CRLF &
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "PUT", "/example-bucket/composable-put-mismatch",
            Convenience_Put_Payload,
            Expected_Content_Type => "text/plain",
            Expected_Content_MD5 => Convenience_Put_MD5,
            Expected_If_None_Match => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => Convenience_Put_CRC32,
            Expected_Cache_Control => "no-cache",
            Expected_Content_Disposition => "inline",
            Expected_Content_Encoding => "gzip",
            Expected_Content_Language => "en-CA",
            Expected_Expires => "Fri, 24 May 2013 00:00:00 GMT",
            Expected_Tagging => "team%2Bname=storage%2Fada",
            Expected_User_Metadata_Name => "project",
            Expected_User_Metadata_Value => "flyology",
            Expected_Website_Redirect => "/next");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""conditional-first""" & CRLF),
            "PUT", "/example-bucket/conditional-put", "conditional-first",
            Expected_If_None_Match => "*");
         Serve
           (HTTP_Response ("412 Precondition Failed", Precondition_XML),
            "PUT", "/example-bucket/conditional-put",
            "conditional-collision", Expected_If_None_Match => "*");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 17" & CRLF &
               "ETag: ""conditional-first""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/conditional-put");
         Serve
           (HTTP_Response
              ("200 OK", "conditional-first",
               "ETag: ""conditional-first""" & CRLF),
            "GET", "/example-bucket/conditional-put",
            Expected_If_Match => """conditional-first""");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""conditional-second""" & CRLF),
            "PUT", "/example-bucket/conditional-put", "conditional-second",
            Expected_If_Match => """conditional-first""");
         Serve
           (HTTP_Response ("412 Precondition Failed", Precondition_XML),
            "PUT", "/example-bucket/conditional-put", "conditional-stale",
            Expected_If_Match => """conditional-first""");
         Serve
           (HTTP_Response ("412 Precondition Failed", Precondition_XML),
            "GET", "/example-bucket/conditional-put",
            Expected_If_Match => """conditional-first""");
         Serve
           (HTTP_Response
              ("200 OK", "conditional-second",
               "ETag: ""conditional-second""" & CRLF),
            "GET", "/example-bucket/conditional-put",
            Expected_If_Match => """conditional-second""");
         Serve
           (HTTP_Response ("200 OK", "", "ETag: *" & CRLF),
            "PUT", "/example-bucket/conditional-put", "conditional-stale",
            Expected_If_Match => """conditional-second""");
         Serve
           (HTTP_Response
              ("200 OK", "conditional-second", "ETag: *" & CRLF),
            "GET", "/example-bucket/conditional-put",
            Expected_If_Match => """conditional-second""");
         --  Accept exactly one one-shot conditional PutObject and close
         --  without a response. The next accepted request is the caller's
         --  generation-bound reconciliation read, so a transparent replay
         --  fails this sequence.
         Serve
           ("HTTP/1.1 404 Not Found" & CRLF &
            "Content-Length: 0" & CRLF &
            "Connection: keep-alive" & CRLF & CRLF,
            "HEAD", "/example-bucket/lost-put", Keep_Open => True);
         Serve
           ("", "PUT", "/example-bucket/lost-put", Lost_Put_Payload,
            Expected_If_None_Match => "*", Reuse_Peer => True);
         Serve
           (HTTP_Response
              ("200 OK", Lost_Put_Payload,
               "ETag: ""lost-put-generation""" & CRLF),
            "GET", "/example-bucket/lost-put",
            Expected_If_Match => """lost-put-generation""");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-version-id: tag-put-version" & CRLF),
            "PUT", "/example-bucket/typed-tagged?tagging", "<Tagging",
            Expected_Content_MD5 => "FHvgEqWnwx8BYbDb/UMn6Q==");
         Serve
           (HTTP_Response
              ("400 Bad Request",
               "<Error><Code>InvalidTag</Code>" &
               "<Message>invalid tag</Message></Error>"),
            "PUT", "/example-bucket/typed-tagged?tagging", "<Tagging",
            Expected_Content_MD5 => "FHvgEqWnwx8BYbDb/UMn6Q==");
         Serve
           (HTTP_Response
              ("200 OK",
               "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
               "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag>" &
               "</TagSet></Tagging>",
               "x-amz-version-id: tag-get-version" & CRLF),
            "GET", "/example-bucket/typed-tagged?tagging",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK",
               "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
               "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag>" &
               "</TagSet></Tagging>",
               "x-amz-version-id: tag-get-restart-version" & CRLF),
            "GET", "/example-bucket/typed-tagged?tagging");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-version-id: tag-delete-version" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/typed-tagged?tagging");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-version-id: tag-delete-restart-version" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/typed-tagged?tagging");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/example-bucket/convenient-tagged?tagging", "<Tagging",
            Expected_Content_MD5 => "FHvgEqWnwx8BYbDb/UMn6Q==");
         Serve
           (HTTP_Response
              ("200 OK",
               "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
               "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag>" &
               "</TagSet></Tagging>"),
            "GET", "/example-bucket/convenient-tagged?tagging");
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket/convenient-tagged?tagging");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-delete-marker: true" & CRLF &
               "x-amz-version-id: deleted-socket-version" & CRLF &
               "x-amz-request-charged: requester" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/typed-delete?" &
              "versionId=socket%20version",
            Expected_If_Match => """socket-etag""",
            Expected_If_Match_Last_Modified_Time =>
              "Wed, 21 Oct 2015 07:28:00 GMT",
            Expected_If_Match_Size => "42",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Governance_Bypass => "true",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("204 No Content", "", "x-amz-delete-marker:" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/empty-delete-marker-output");
         Serve
           (HTTP_Response
              ("204 No Content", "", "x-amz-version-id:" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/empty-delete-version-output");
         Serve
           (HTTP_Response
              ("204 No Content", "", "x-amz-request-charged:" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/empty-delete-charged-output");
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket/convenient-delete",
            Expected_If_Match => "*",
            Expected_If_Match_Last_Modified_Time =>
              "Wed, 21 Oct 2015 07:28:00 GMT",
            Expected_If_Match_Size => "7",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Governance_Bypass => "false");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-version-id: first" & CRLF &
               "x-amz-version-id: second" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/duplicate-delete-output");
         Serve
           (HTTP_Response
              ("409 Conflict",
               "<Error><Code>OperationAborted</Code>" &
               "<Message>conflict</Message></Error>"),
            "DELETE", "/example-bucket/conflict-delete");
         --  Prime one reusable HTTP/1.1 connection, accept a conditional
         --  delete on that connection, and then lose the response.  The next
         --  accepted request must be reconciliation HEAD; a transparent
         --  replay would instead fail this exact request sequence.
         Serve
           ("HTTP/1.1 200 OK" & CRLF &
            "Content-Length: 1" & CRLF &
            "ETag: ""lost-delete-etag""" & CRLF &
            "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
            "Connection: keep-alive" & CRLF & CRLF,
            "HEAD", "/example-bucket/lost-delete",
            Keep_Open => True);
         Serve
           ("", "DELETE", "/example-bucket/lost-delete",
            Expected_If_Match => "*", Require_Zero_Content_Length => True,
            Reuse_Peer => True);
         Serve
           (HTTP_Response
              ("404 Not Found", "", Omit_Content_Length => True),
            "HEAD", "/example-bucket/lost-delete");
         Serve
           (HTTP_Response
              ("200 OK", Delete_Objects_XML,
               "x-amz-request-charged: requester" & CRLF),
            "POST", "/example-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_MFA => "device 123456",
            Expected_Governance_Bypass => "true",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*", Fragmented => True);
         Serve
           (HTTP_Response
              ("404 Not Found",
               "<Error><Code>NoSuchBucket</Code>" &
               "<Message>missing bucket</Message></Error>",
               "x-amz-request-id: delete-missing-request" & CRLF),
            "POST", "/missing-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", Delete_Objects_XML),
            "POST", "/example-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", Delete_Objects_XML),
            "POST", "/example-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", Delete_Objects_XML,
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "POST", "/example-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", Attributes_XML,
               "x-amz-delete-marker: false" & CRLF &
               "Last-Modified: Fri, 24 May 2013 00:00:00 GMT" & CRLF &
               "x-amz-version-id: socket version" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/object%20key?attributes&" &
              "versionId=socket%20version",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Get_Object_Attributes =>
              "ETag,ObjectParts,ObjectSize",
            Expected_Max_Parts => "1", Expected_Part_Marker => "1",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Attributes_XML),
            "GET", "/example-bucket/convenience-attributes?attributes",
            Expected_Get_Object_Attributes =>
              "ETag,Checksum,ObjectParts,StorageClass,ObjectSize");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-id: attributes-request" & CRLF &
               "x-amz-id-2: attributes-host" & CRLF),
            "GET", "/example-bucket/missing-attributes?attributes",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response
              ("200 OK", Attributes_XML,
               "x-amz-version-id: scoped-version" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/scoped-attributes?attributes&" &
              "versionId=scoped-version",
            Expected_Request_Payer => "requester",
            Expected_Get_Object_Attributes => "ObjectSize",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Attributes_XML),
            "GET", "/example-bucket/scoped-attributes-restart?attributes",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/example-bucket/scoped-attributes-error?attributes",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response
              ("200 OK", Attributes_XML,
               "x-amz-version-id: wrong-version" & CRLF),
            "GET", "/example-bucket/scoped-attributes-wrong?attributes&" &
              "versionId=expected-version",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response
              ("200 OK", Attributes_XML,
               "x-amz-version-id: duplicate" & CRLF &
               "x-amz-version-id: duplicate" & CRLF),
            "GET", "/example-bucket/scoped-attributes-duplicate?attributes",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response
              ("200 OK", Attributes_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/scoped-attributes-payer?attributes",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level""" & CRLF),
            "PUT", "/example-bucket/high%20level%2Bfile%2525",
            High_Level_File_Payload, "application/test");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level-full""" & CRLF &
               "x-amz-checksum-crc32: " & High_Level_CRC32 & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "PUT", "/example-bucket/high-level-checksum-full",
            High_Level_File_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "CRC32",
            Expected_Checksum_Header => "x-amz-checksum-crc32",
            Expected_Checksum => High_Level_CRC32);
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level-sha256""" & CRLF &
               "x-amz-checksum-sha256: " & High_Level_SHA256 & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "PUT", "/example-bucket/high-level-checksum-sha256",
            High_Level_File_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => High_Level_SHA256);
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level-put-mismatch""" & CRLF &
               "x-amz-checksum-sha256: " &
               (if Round = 1 then Wrong_SHA256 else High_Level_SHA256) &
               CRLF & "x-amz-checksum-type: " &
               (if Round = 1 then "FULL_OBJECT" else "COMPOSITE") & CRLF),
            "PUT", "/example-bucket/high-level-put-mismatch",
            High_Level_File_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => High_Level_SHA256);
         Serve
           (HTTP_Response
              ("200 OK",
               "<InitiateMultipartUploadResult>" &
               "<Bucket>example-bucket</Bucket>" &
               "<Key>high-level-checksum-composite</Key>" &
               "<UploadId>high-level-checksum-upload</UploadId>" &
               "</InitiateMultipartUploadResult>"),
            "POST", "/example-bucket/high-level-checksum-composite?uploads",
            Expected_Checksum_Algorithm_Header =>
              "x-amz-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Type => "COMPOSITE");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level-part""" & CRLF &
               "x-amz-checksum-sha256: " & High_Level_SHA256 & CRLF),
            "PUT", "/example-bucket/high-level-checksum-composite?" &
              "partNumber=1&uploadId=high-level-checksum-upload",
            High_Level_File_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => High_Level_SHA256);
         Serve
           (HTTP_Response
              ("200 OK",
               "<CompleteMultipartUploadResult>" &
               "<Bucket>example-bucket</Bucket>" &
               "<Key>high-level-checksum-composite</Key>" &
               "<ETag>&quot;high-level-composite&quot;</ETag>" &
               "<ChecksumSHA256>" & High_Level_SHA256_Composite &
               "</ChecksumSHA256>" &
               "</CompleteMultipartUploadResult>"),
            "POST", "/example-bucket/high-level-checksum-composite?" &
              "uploadId=high-level-checksum-upload",
            High_Level_SHA256,
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => High_Level_SHA256_Composite_Raw,
            Expected_Checksum_Type => "COMPOSITE",
            Expected_Mpu_Object_Size => "23");
         Serve
           (HTTP_Response
              ("200 OK",
               "<InitiateMultipartUploadResult>" &
               "<Bucket>example-bucket</Bucket>" &
               "<Key>high-level-checksum-mismatch</Key>" &
               "<UploadId>high-level-mismatch-upload</UploadId>" &
               "</InitiateMultipartUploadResult>"),
            "POST", "/example-bucket/high-level-checksum-mismatch?uploads",
            Expected_Checksum_Algorithm_Header =>
              "x-amz-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Type => "COMPOSITE");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level-part""" & CRLF &
               "x-amz-checksum-sha256: " & High_Level_SHA256 & CRLF),
            "PUT", "/example-bucket/high-level-checksum-mismatch?" &
              "partNumber=1&uploadId=high-level-mismatch-upload",
            High_Level_File_Payload,
            Expected_Checksum_Algorithm_Header =>
              "x-amz-sdk-checksum-algorithm",
            Expected_Checksum_Algorithm => "SHA256",
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => High_Level_SHA256);
         Serve
           (HTTP_Response
              ("200 OK",
               "<CompleteMultipartUploadResult>" &
               "<Bucket>example-bucket</Bucket>" &
               "<Key>high-level-checksum-mismatch</Key>" &
               "<ETag>&quot;high-level-mismatch&quot;</ETag>" &
               "<ChecksumSHA256>" &
               (if Round = 1
                then Wrong_SHA256_Composite
                else High_Level_SHA256_Composite) &
               "</ChecksumSHA256><ChecksumType>" &
               (if Round = 1 then "COMPOSITE" else "FULL_OBJECT") &
               "</ChecksumType>" &
               "</CompleteMultipartUploadResult>"),
            "POST", "/example-bucket/high-level-checksum-mismatch?" &
              "uploadId=high-level-mismatch-upload",
            High_Level_SHA256,
            Expected_Checksum_Header => "x-amz-checksum-sha256",
            Expected_Checksum => High_Level_SHA256_Composite_Raw,
            Expected_Checksum_Type => "COMPOSITE",
            Expected_Mpu_Object_Size => "23");
         Serve
           (HTTP_Response ("404 Not Found", Error_XML),
            "DELETE", "/example-bucket/high-level-checksum-mismatch?" &
              "uploadId=high-level-mismatch-upload");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""empty""" & CRLF),
            "PUT", "/example-bucket/high-level-empty");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "PUT", "/example-bucket/high-level-rejected",
            "high-level file payload");
         Serve
           (HTTP_Response
              ("200 OK", Download_Payload,
               "ETag: ""download-large""" & CRLF),
            "GET", "/example-bucket/download%20large%2B%2525");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""download-empty""" & CRLF),
            "GET", "/example-bucket/download-empty");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/example-bucket/download-rejected");
         Serve
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Length: 64" & CRLF
            & "ETag: ""download-truncated""" & CRLF
            & "Connection: close" & CRLF & CRLF & "short",
            "GET", "/example-bucket/download-truncated");
         Serve
           (HTTP_Response
              ("206 Partial Content", "partial",
               "Content-Range: bytes 0-6/42" & CRLF &
               "ETag: ""download-partial""" & CRLF),
            "GET", "/example-bucket/download-unexpected-range");
         Serve
           (HTTP_Response
              ("206 Partial Content", "partial",
               "Content-Range: bytes 7-13/42" & CRLF &
               "ETag: ""download-range""" & CRLF),
            "GET", "/example-bucket/download-range",
            Expected_Range => "bytes=7-13");
         Serve
           (HTTP_Response
              ("304 Not Modified", "", Omit_Content_Length => True),
            "GET", "/example-bucket/download-not-modified",
            Expected_If_None_Match => """download-range""");
         Serve
           (HTTP_Response ("412 Precondition Failed", "precondition failed"),
            "GET", "/example-bucket/download-precondition",
            Expected_If_Match => """different""");
         Serve
           (HTTP_Response ("206 Partial Content", "x"),
            "GET", "/example-bucket/download-missing-content-range",
            Expected_Range => "bytes=0-0");
         Serve
           (HTTP_Response
              ("206 Partial Content", "xx",
               "Content-Range: bytes 0-0/2" & CRLF),
            "GET", "/example-bucket/download-length-mismatch",
            Expected_Range => "bytes=0-0");
         Serve
           (HTTP_Response
              ("206 Partial Content", "x",
               "Content-Range: bytes 2-1/3" & CRLF),
            "GET", "/example-bucket/download-invalid-content-range",
            Expected_Range => "bytes=0-0");
         Serve
           (HTTP_Response
              ("200 OK", "x", "Content-Range: bytes 0-0/1" & CRLF),
            "GET", "/example-bucket/download-unsolicited-content-range");
         Serve
           (HTTP_Response
              ("200 OK", Copy_Part_XML,
               "x-amz-copy-source-version-id: source-version" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/copy-part-sync?partNumber=1&" &
              "uploadId=copy-upload",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response ("200 OK", Copy_Part_XML), "PUT",
            "/example-bucket/copy-part-restart-one?partNumber=1&" &
              "uploadId=copy-upload",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response ("200 OK", Copy_Part_XML), "PUT",
            "/example-bucket/copy-part-restart-two?partNumber=1&" &
              "uploadId=copy-upload",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", Copy_Part_XML,
               "x-amz-copy-source-version-id: first" & CRLF &
               "x-amz-copy-source-version-id: second" & CRLF),
            "PUT", "/example-bucket/copy-part-invalid-duplicate?" &
              "partNumber=1&uploadId=copy-upload",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", Copy_Part_XML,
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/copy-part-invalid-charged?" &
              "partNumber=1&uploadId=copy-upload",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML), "PUT",
            "/example-bucket/copy-part-rejected?partNumber=1&" &
              "uploadId=copy-upload",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", Copy_XML,
               "x-amz-version-id: destination-version" & CRLF &
               "x-amz-copy-source-version-id: source-version" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/copied%20object%2B%2525",
            Expected_Copy_Source =>
              "source-bucket/source%20key%2B%2525",
            Expected_Copy_If_Match => """source-etag""",
            Expected_Request_Payer => "requester");
         Serve
           (HTTP_Response ("200 OK", Copy_XML), "PUT",
            "/example-bucket/copy-restart-one",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response ("200 OK", Copy_XML), "PUT",
            "/example-bucket/copy-restart-two",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", Copy_XML,
               "x-amz-version-id: first" & CRLF &
               "x-amz-version-id: second" & CRLF),
            "PUT", "/example-bucket/copy-invalid-duplicate",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", Copy_XML, "x-amz-version-id:" & CRLF),
            "PUT", "/example-bucket/copy-invalid-empty",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", Copy_XML,
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/copy-invalid-charged",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response ("412 Precondition Failed", Error_XML),
            "PUT", "/example-bucket/copy-rejected",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 4" & CRLF &
               "ETag: ""head-etag""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "Content-Type: application/test" & CRLF &
               "x-amz-version-id: head-version" & CRLF &
               "x-amz-checksum-sha256: " &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=-3" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF &
               "x-amz-mp-parts-count: 3" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head%20object%2B%2525?" &
              "partNumber=3&response-cache-control=no-cache&" &
              "response-content-disposition=attachment&" &
              "response-content-encoding=gzip&" &
              "response-content-language=en-CA&response-content-type=" &
              "application%2Ftest&response-expires=Fri%2C%2021%20Aug%20" &
              "2026%2018%3A00%3A00%20GMT&versionId=version%20one",
            Expected_If_Match => """expected-etag""",
            Expected_If_Modified_Since =>
              "Fri, 21 Aug 2026 16:00:00 GMT",
            Expected_If_None_Match => """other-etag""",
            Expected_If_Unmodified_Since =>
              "Fri, 21 Aug 2026 18:00:00 GMT",
            Expected_Range => "bytes=1-4",
            Expected_Checksum_Mode => "ENABLED");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 42" & CRLF &
               "ETag: ""head-policy""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-policy",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("404 Not Found", "",
               "x-amz-request-id: head-request" & CRLF &
               "x-amz-id-2: head-host" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-missing");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 1" & CRLF &
               "ETag: ""checksum-etag""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-sha256: not-base64" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-invalid-checksum");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 1" & CRLF &
               "ETag: ""first""" & CRLF &
               "ETag: ""second""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-duplicate-header");
         Serve
           ("HTTP/1.1 200 OK" & CRLF &
            "Transfer-Encoding: chunked" & CRLF &
            "ETag: ""framed""" & CRLF &
            "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
            "Connection: close" & CRLF & CRLF,
            "HEAD", "/example-bucket/head-transfer-encoding");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 7" & CRLF &
               "x-amz-delete-marker: false" & CRLF &
               "x-amz-archive-status: ARCHIVE_ACCESS" & CRLF &
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF &
               "ETag: ""typed-head""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-missing-meta: 2" & CRLF &
               "x-amz-meta-project: flyology" & CRLF &
               "x-amz-meta-stage: typed" & CRLF &
               "x-amz-server-side-encryption: aws:backup" & CRLF &
               "x-amz-server-side-encryption-customer-algorithm: " &
               "AES256" & CRLF &
               "x-amz-storage-class: AWS_BACKUP_WARM" & CRLF &
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-replication-status: COMPLETED" & CRLF &
               "x-amz-mp-parts-count: 3" & CRLF &
               "x-amz-tagging-count: 2" & CRLF &
               "x-amz-object-lock-mode: COMPLIANCE" & CRLF &
               "x-amz-object-lock-legal-hold: OFF" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/typed-head");
         Serve
           (HTTP_Response
              ("206 Partial Content", "getdata",
               "Accept-Ranges: bytes" & CRLF &
               "Content-Range: bytes 1-7/9" & CRLF &
               "ETag: ""typed-get""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-sha256: " &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=-3" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF &
               "x-amz-meta-project: flyology" & CRLF &
               "x-amz-meta-stage: get" & CRLF &
               "x-amz-server-side-encryption: aws:backup" & CRLF &
               "x-amz-storage-class: AWS_BACKUP_WARM" & CRLF &
               "x-amz-replication-status: COMPLETED" & CRLF &
               "x-amz-mp-parts-count: 3" & CRLF &
               "x-amz-tagging-count: 2" & CRLF &
               "x-amz-object-lock-mode: COMPLIANCE" & CRLF &
               "x-amz-object-lock-legal-hold: OFF" & CRLF),
            "GET", "/example-bucket/typed-get?versionId=version%20one",
            Expected_If_Match => """expected-etag""",
            Expected_Checksum_Mode => "ENABLED");
         Serve
           (HTTP_Response
              ("200 OK", "full",
               "ETag: ""typed-get-full""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-crc64nvme: AAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "GET", "/example-bucket/typed-get-full",
            Expected_Checksum_Mode => "ENABLED");
         for Index in Read_Checksums'Range loop
            declare
               Header : constant String :=
                 US.To_String (Read_Checksums (Index).Header);
               Value : constant String :=
                 US.To_String (Read_Checksums (Index).Value);
               Common : constant String :=
                 "ETag: ""read-full""" & CRLF &
                 "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF;
            begin
               Serve
                 (HTTP_Response
                    ("200 OK", "full", Common & Header & ": " & Value &
                     CRLF & "x-amz-checksum-type: FULL_OBJECT" & CRLF),
                  "GET", "/example-bucket/read-full-" & Decimal (Index),
                  Expected_Checksum_Mode => "ENABLED");
               Serve
                 (HTTP_Response
                    ("200 OK", "x", Common & Header & ": AAAA" & CRLF &
                     "x-amz-checksum-type: FULL_OBJECT" & CRLF),
                  "GET", "/example-bucket/read-malformed-" & Decimal (Index),
                  Expected_Checksum_Mode => "ENABLED");
               Serve
                 (HTTP_Response
                    ("200 OK", "x", Common & Header & ": " & Value & CRLF &
                     "x-amz-checksum-type: COMPOSITE" & CRLF),
                  "GET", "/example-bucket/read-wrong-type-" &
                    Decimal (Index),
                  Expected_Checksum_Mode => "ENABLED");
            end;
         end loop;
         Serve
           (HTTP_Response
              ("304 Not Modified", "",
               "x-amz-request-id: get-request" & CRLF &
               "x-amz-id-2: get-host" & CRLF,
               Omit_Content_Length => True),
            "GET", "/example-bucket/typed-get-missing");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-sha256: not-base64" & CRLF),
            "GET", "/example-bucket/typed-get-invalid");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-sha256: " &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF),
            "GET", "/example-bucket/typed-get-multiple");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-crc64nvme: AAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF),
            "GET", "/example-bucket/typed-get-illegal-pair");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-crc64nvme: AAAAAAAAAAA=-1" & CRLF),
            "GET", "/example-bucket/typed-get-inferred-illegal-pair");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-type: COMPOSITE" & CRLF),
            "GET", "/example-bucket/typed-get-type-only");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?tagging", "<Tagging",
            Expected_Content_MD5 => "2VvoA0oifGYAP5yZrGu55w==");
         Serve
           (HTTP_Response
              ("400 Bad Request",
               "<Error><Code>InvalidTag</Code>" &
               "<Message>invalid tag</Message></Error>"),
            "PUT", "/example-bucket?tagging", "<Tagging",
            Expected_Content_MD5 => "2VvoA0oifGYAP5yZrGu55w==");
         Serve
           (HTTP_Response ("200 OK", Tagging_XML), "GET",
            "/example-bucket?tagging", Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Tagging_XML), "GET",
            "/example-bucket?tagging", Fragmented => True);
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket?tagging");
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket?tagging");
         Serve
           (HTTP_Response
              ("404 Not Found",
               "<Error><Code>NoSuchTagSet</Code>" &
               "<Message>The TagSet does not exist</Message></Error>"),
            "GET", "/example-bucket?tagging", Fragmented => True);
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket?tagging");
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("example-bucket", "scoped-create", "scoped-create-id"),
               "x-amz-request-id: scoped-create-request" & CRLF),
            "POST", "/example-bucket/scoped-create?uploads",
            Fragmented => True);
         Serve
           ("", "POST", "/example-bucket/create-lost?uploads",
            Keep_Open => False);
         Serve
           (HTTP_Response ("200 OK", Lost_Create_List_XML), "GET",
            "/example-bucket?max-uploads=1000&prefix=create-lost&uploads");
         Serve
           (HTTP_Response
              ("200 OK", Create_XML,
               "x-amz-abort-date: Fri, 24 May 2013 00:00:00 GMT" & CRLF &
               "x-amz-abort-rule-id: cleanup" & CRLF &
               "x-amz-server-side-encryption: aws:kms" & CRLF &
               "x-amz-server-side-encryption-aws-kms-key-id: kms-key" &
               CRLF & "x-amz-server-side-encryption-context: e30=" & CRLF &
               "x-amz-server-side-encryption-bucket-key-enabled: true" &
               CRLF & "x-amz-request-charged: requester" & CRLF &
               "x-amz-checksum-algorithm: CRC32C" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "POST", "/example-bucket/object%20key?uploads",
            Expected_Request_Payer => "requester",
            Expected_Checksum_Algorithm_Header =>
              "x-amz-checksum-algorithm",
            Expected_Checksum_Algorithm => "CRC32C",
            Expected_Checksum_Type => "FULL_OBJECT", Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("wrong-bucket", "create-wrong-bucket", "bad-bucket")),
            "POST", "/example-bucket/create-wrong-bucket?uploads");
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("example-bucket", "wrong-key", "bad-key")),
            "POST", "/example-bucket/create-wrong-key?uploads");
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("example-bucket", "create-duplicate", "bad-duplicate"),
               "x-amz-checksum-algorithm: CRC32C" & CRLF &
               "x-amz-checksum-algorithm: CRC32C" & CRLF),
            "POST", "/example-bucket/create-duplicate?uploads");
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("example-bucket", "create-empty", "bad-empty"),
               "x-amz-request-charged:" & CRLF),
            "POST", "/example-bucket/create-empty?uploads");
         Serve
           (HTTP_Response
              ("200 OK",
               Create_Result_XML
                 ("example-bucket", "create-bool", "bad-bool"),
               "x-amz-server-side-encryption-bucket-key-enabled: True" &
               CRLF),
            "POST", "/example-bucket/create-bool?uploads");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""socket-part""" & CRLF),
            "PUT",
            "/example-bucket/object%20key?partNumber=1&" &
            "uploadId=socket-upload", "u");
         Serve
           (HTTP_Response ("200 OK", Complete_XML), "POST",
            "/example-bucket/object%20key?uploadId=socket-upload",
            "<CompleteMultipartUpload", Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Embedded_Error_XML), "POST",
            "/example-bucket/object%20key?uploadId=socket-upload",
            "<CompleteMultipartUpload");
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True), "DELETE",
            "/example-bucket/object%20key?uploadId=socket-upload");
         Serve
           (HTTP_Response ("404 Not Found", No_Such_Upload_XML), "DELETE",
            "/example-bucket/object%20key?uploadId=socket-upload");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF,
               Omit_Content_Length => True),
            "DELETE",
            "/example-bucket/object%20key?uploadId=socket-upload");
         Serve
           (HTTP_Response
              ("200 OK", Versions_Complete_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "key-marker=logs%2Fa&max-keys=3&prefix=logs%2F&" &
              "version-id-marker=v%2B1&versions",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Versions_Empty_Echo_XML),
            "GET", "/example-bucket?max-keys=1&versions",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML
                 ("example-bucket", "omitted-max/", Maximum => 1_000)),
            "GET", "/example-bucket?prefix=omitted-max%2F&versions");
         Serve
           (HTTP_Response ("200 OK", Versions_Paged_First_XML),
            "GET", "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=paged%2F&versions", Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Versions_Paged_Second_XML),
            "GET", "/example-bucket?encoding-type=url&" &
              "key-marker=paged%2Fa%20%2F%25%C3%A9&max-keys=1&" &
              "prefix=paged%2F&version-id-marker=v%2B1&versions");
         Serve
           (HTTP_Response ("200 OK", Versions_Bad_Marker_XML),
            "GET", "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=bad-marker%2F&versions");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: versions-request" & CRLF &
               "x-amz-id-2: versions-host" & CRLF),
            "GET", "/example-bucket?max-keys=1&prefix=error%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML ("example-bucket", "duplicate/"),
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?max-keys=1&prefix=duplicate%2F&" &
              "versions");
         Serve
           (HTTP_Response
              ("200 OK", Final_Versions_XML ("wrong-bucket", "bucket/")),
            "GET", "/example-bucket?max-keys=1&prefix=bucket%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK", Final_Versions_XML ("example-bucket", "wrong/")),
            "GET", "/example-bucket?max-keys=1&prefix=right%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML
                 ("example-bucket", "maximum/", Maximum => 2)),
            "GET", "/example-bucket?max-keys=1&prefix=maximum%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML ("example-bucket", "encoding/")),
            "GET", "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=encoding%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK", Final_Versions_XML ("example-bucket", "surprise/")),
            "GET", "/example-bucket?max-keys=1&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               "<ListVersionsResult><Unknown/></ListVersionsResult>"),
            "GET", "/example-bucket?max-keys=1&prefix=malformed%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML
                 ("example-bucket", "oversized/" &
                    String'(1 .. 256 => 'x'))),
            "GET", "/example-bucket?max-keys=1&prefix=oversized%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK", Final_Versions_XML ("example-bucket", "scoped/"),
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?max-keys=1&prefix=scoped%2F&versions",
            Expected_Request_Payer => "requester");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/example-bucket?max-keys=1&" &
              "prefix=scoped-error%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML ("wrong-bucket", "scoped-wrong/")),
            "GET", "/example-bucket?max-keys=1&" &
              "prefix=scoped-wrong%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML ("example-bucket", "scoped-duplicate/"),
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?max-keys=1&" &
              "prefix=scoped-duplicate%2F&versions");
         Serve
           (HTTP_Response
              ("200 OK",
               Final_Versions_XML ("example-bucket", "scoped-payer/"),
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?max-keys=1&" &
              "prefix=scoped-payer%2F&versions");
         Serve
           (HTTP_Response ("200 OK", Versions_Paged_First_XML),
            "GET", "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=paged%2F&versions", Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Versions_Paged_Second_XML),
            "GET", "/example-bucket?encoding-type=url&" &
              "key-marker=paged%2Fa%20%2F%25%C3%A9&max-keys=1&" &
              "prefix=paged%2F&version-id-marker=v%2B1&versions");
         Serve
           (HTTP_Response ("204 No Content", ""),
            "DELETE", "/example-bucket?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""),
            "DELETE", "/typed-delete-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""),
            "DELETE", "/composed-delete-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-delete-cors" & CRLF),
            "DELETE", "/restart-delete-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("500 Internal Server Error",
               "<Error><Code>InternalError</Code><Message>" &
               String'(1 .. 256 => 'x') & "</Message></Error>"),
            "DELETE", "/bounded-delete-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?analytics&id=config%20id",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/typed-delete-encryption?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/composed-delete-encryption?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-delete-encryption" & CRLF),
            "DELETE", "/restart-delete-encryption?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?id=config%20id&intelligent-tiering",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?id=config%20id&inventory",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/typed-delete-lifecycle?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/composed-delete-lifecycle?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-delete-lifecycle" & CRLF),
            "DELETE", "/restart-delete-lifecycle?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-request-id: duplicate-lifecycle" & CRLF &
               "x-amz-request-id: duplicate-lifecycle" & CRLF),
            "DELETE", "/invalid-delete-lifecycle?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("204 No Content", "", "x-amz-id-2: " & CRLF),
            "DELETE", "/empty-host-delete-lifecycle?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("500 Internal Server Error",
               "<Error><Code>InternalError</Code><Message>" &
               String'(1 .. 256 => 'x') & "</Message></Error>"),
            "DELETE", "/bounded-delete-lifecycle?lifecycle",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?metadataConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?metadataTable",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?id=config%20id&metrics",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?ownershipControls",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/composed-delete-ownership?ownershipControls",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-delete-ownership" & CRLF),
            "DELETE", "/restart-delete-ownership?ownershipControls",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/typed-delete-policy?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/composed-delete-policy?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-delete-policy-request" & CRLF),
            "DELETE", "/restart-delete-policy?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?replication",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?website",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/example-bucket?publicAccessBlock",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("204 No Content", ""), "DELETE",
            "/composed-delete-public-access?publicAccessBlock",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-delete-public-access" & CRLF),
            "DELETE", "/restart-delete-public-access?publicAccessBlock",
            Expected_Bucket_Owner => "123456789012");
         --  Pinned-model reference fixtures for the five qualified GETs.
         --  Spellings and values cover every public result field; changing
         --  them requires paired client assertions and has no product-policy
         --  effect.
         Serve
           (HTTP_Response
              ("200 OK",
               "<AccelerateConfiguration><Status>Enabled</Status>" &
               "</AccelerateConfiguration>",
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?accelerate",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", "{""Statement"":[]}"),
            "GET", "/example-bucket?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", "{""Version"":""2012-10-17""}"),
            "GET", "/composed-policy?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-policy-request" & CRLF),
            "GET", "/restart-policy?policy",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<PolicyStatus><IsPublic>false</IsPublic></PolicyStatus>"),
            "GET", "/example-bucket?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<PolicyStatus><IsPublic>false</IsPublic></PolicyStatus>"),
            "GET", "/typed-policy-status?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<PolicyStatus><IsPublic>true</IsPublic></PolicyStatus>"),
            "GET", "/composed-policy-status?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-policy-status" & CRLF),
            "GET", "/restart-policy-status?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<PolicyStatus><IsPublic>false</IsPublic></PolicyStatus>",
               "x-amz-request-id: first-policy-status" & CRLF &
               "x-amz-request-id: second-policy-status" & CRLF),
            "GET", "/duplicate-policy-status-header?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
               ("200 OK",
                "<PolicyStatus><IsPublic>false</IsPublic></PolicyStatus>",
               "x-amz-id-2:" & CRLF),
            "GET", "/empty-policy-status-header?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<PolicyStatus><IsPublic>false</IsPublic></PolicyStatus>"),
            "GET", "/bounded-policy-status?policyStatus",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<RequestPaymentConfiguration>" &
               "<Payer>BucketOwner</Payer>" &
               "</RequestPaymentConfiguration>"),
            "GET", "/example-bucket?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<RequestPaymentConfiguration>" &
               "<Payer>Requester</Payer>" &
               "</RequestPaymentConfiguration>"),
            "GET", "/typed-request-payment?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<RequestPaymentConfiguration>" &
               "<Payer>BucketOwner</Payer>" &
               "</RequestPaymentConfiguration>"),
            "GET", "/composed-request-payment?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-request-payment" & CRLF),
            "GET", "/restart-request-payment?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<RequestPaymentConfiguration>" &
               "<Payer>Requester</Payer>" &
               "</RequestPaymentConfiguration>",
               "x-amz-request-id: first-request-payment" & CRLF &
               "x-amz-request-id: second-request-payment" & CRLF),
            "GET", "/duplicate-request-payment-header?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<RequestPaymentConfiguration>" &
               "<Payer>Requester</Payer>" &
               "</RequestPaymentConfiguration>",
               "x-amz-id-2:" & CRLF),
            "GET", "/empty-request-payment-header?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<RequestPaymentConfiguration>" &
               "<Payer>Requester</Payer>" &
               "</RequestPaymentConfiguration>"),
            "GET", "/bounded-request-payment?requestPayment",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<PublicAccessBlockConfiguration>" &
               "<BlockPublicAcls>true</BlockPublicAcls>" &
               "<IgnorePublicAcls>false</IgnorePublicAcls>" &
               "<BlockPublicPolicy>true</BlockPublicPolicy>" &
               "<RestrictPublicBuckets>false</RestrictPublicBuckets>" &
               "</PublicAccessBlockConfiguration>"),
            "GET", "/example-bucket?publicAccessBlock",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<PublicAccessBlockConfiguration>" &
               "<BlockPublicAcls>false</BlockPublicAcls>" &
               "<IgnorePublicAcls>true</IgnorePublicAcls>" &
               "<BlockPublicPolicy>false</BlockPublicPolicy>" &
               "<RestrictPublicBuckets>true</RestrictPublicBuckets>" &
               "</PublicAccessBlockConfiguration>"),
            "GET", "/composed-public-access?publicAccessBlock",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-get-public-access" & CRLF),
            "GET", "/restart-public-access?publicAccessBlock",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<AbacStatus><Status>Enabled</Status></AbacStatus>"),
            "GET", "/example-bucket?abac",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT", "/example-bucket?cors",
            Expected_Body_Root => "<CORSConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: typed-put-cors" & CRLF),
            "PUT", "/typed-put-cors?cors",
            Expected_Body_Root => "<CORSConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT", "/composed-cors?cors",
            Expected_Body_Root => "<CORSConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-put-cors" & CRLF),
            "PUT", "/restart-put-cors?cors",
            Expected_Body_Root => "<CORSConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<OwnershipControls><Rule><ObjectOwnership>" &
                 "BucketOwnerPreferred</ObjectOwnership></Rule><Rule>" &
                 "<ObjectOwnership>BucketOwnerEnforced</ObjectOwnership>" &
                 "</Rule></OwnershipControls>",
               "x-amz-request-id: ownership-request" & CRLF &
               "x-amz-id-2: ownership-host" & CRLF),
            "GET", "/example-bucket?ownershipControls",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", ""),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: ownership-error-request" & CRLF &
               "x-amz-id-2: ownership-error-host" & CRLF),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              ("200 OK", "<OwnershipControls><Rule><ObjectOwnership>" &
                 "ObjectWriter</ObjectOwnership></Rule></OwnershipControls>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              ("200 OK", "<OwnershipControls><Rule><ObjectOwnership>" &
                 "ObjectWriter</ObjectOwnership></Rule></OwnershipControls>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              ("200 OK", "<OwnershipControls><Rule><ObjectOwnership>" &
                 "ObjectWriter</ObjectOwnership></Rule></OwnershipControls>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              ("200 OK", "<OwnershipControls/>"),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              --  26 text bytes plus 39 markup bytes are exactly one past
              --  the paired caller-selected 64-byte document limit.
              ("200 OK", "<OwnershipControls>" &
                 String'(1 .. 26 => ' ') & "</OwnershipControls>"),
            "GET", "/example-bucket?ownershipControls");
         Serve
           (HTTP_Response
              ("200 OK", "<OwnershipControls><Rule><ObjectOwnership>" &
                 "BucketOwnerEnforced</ObjectOwnership></Rule>" &
                 "</OwnershipControls>"),
            "GET", "/composed-ownership?ownershipControls",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-get-ownership" & CRLF),
            "GET", "/restart-ownership?ownershipControls",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration><CORSRule><ID>socket-rule" &
                 "</ID><AllowedHeader>*</AllowedHeader><AllowedMethod>GET" &
                 "</AllowedMethod><AllowedMethod>PUT</AllowedMethod>" &
                 "<AllowedOrigin>https://example.test</AllowedOrigin>" &
                 "<ExposeHeader>etag</ExposeHeader><MaxAgeSeconds>" &
                 "999999999999999999999999</MaxAgeSeconds></CORSRule>" &
                 "</CORSConfiguration>",
               "x-amz-request-id: cors-request" & CRLF &
               "x-amz-id-2: cors-host" & CRLF),
            "GET", "/example-bucket?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-id: cors-error-request" & CRLF &
               "x-amz-id-2: cors-error-host" & CRLF),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration/>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration/>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration/>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration><CORSRule>" &
                 "<AllowedMethod>GET</AllowedMethod></CORSRule>" &
                 "</CORSConfiguration>"),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              --  This test payload deliberately exceeds the paired 64-byte
              --  caller-selected document ceiling; 64 is test policy only.
              ("200 OK", "<CORSConfiguration>" &
                 String'(1 .. 64 => ' ') & "</CORSConfiguration>"),
            "GET", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration><CORSRule>" &
                 "<AllowedMethod>GET</AllowedMethod>" &
                 "<AllowedOrigin>https://typed.example</AllowedOrigin>" &
                 "</CORSRule></CORSConfiguration>"),
            "GET", "/typed-get-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration><CORSRule>" &
                 "<AllowedMethod>PUT</AllowedMethod>" &
                 "<AllowedOrigin>https://composed.example</AllowedOrigin>" &
                 "</CORSRule></CORSConfiguration>"),
            "GET", "/composed-get-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-get-cors" & CRLF),
            "GET", "/restart-get-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<CORSConfiguration>" &
                 String'(1 .. 64 => ' ') & "</CORSConfiguration>"),
            "GET", "/bounded-get-cors?cors",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "<ServerSideEncryptionConfiguration><Rule>" &
                 "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>" &
                 "aws:kms</SSEAlgorithm><KMSMasterKeyID>socket-key" &
                 "</KMSMasterKeyID></ApplyServerSideEncryptionByDefault>" &
                 "<BucketKeyEnabled>true</BucketKeyEnabled>" &
                 "<BlockedEncryptionTypes><EncryptionType>SSE-C" &
                 "</EncryptionType></BlockedEncryptionTypes></Rule>" &
                 "</ServerSideEncryptionConfiguration>",
               "x-amz-request-id: encryption-request" & CRLF &
               "x-amz-id-2: encryption-host" & CRLF),
            "GET", "/example-bucket?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-id: encryption-error-request" & CRLF &
               "x-amz-id-2: encryption-error-host" & CRLF),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              ("200 OK", "<ServerSideEncryptionConfiguration><Rule/>" &
                 "</ServerSideEncryptionConfiguration>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              ("200 OK", "<ServerSideEncryptionConfiguration><Rule/>" &
                 "</ServerSideEncryptionConfiguration>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              ("200 OK", "<ServerSideEncryptionConfiguration><Rule/>" &
                 "</ServerSideEncryptionConfiguration>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              ("200 OK", "<ServerSideEncryptionConfiguration><Rule>" &
                 "<ApplyServerSideEncryptionByDefault/>" &
                 "</Rule></ServerSideEncryptionConfiguration>"),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              --  Test-only oversized payload paired with the caller's
              --  explicit 64-byte document ceiling below.
              ("200 OK", "<ServerSideEncryptionConfiguration>" &
                 String'(1 .. 64 => ' ') &
                 "</ServerSideEncryptionConfiguration>"),
            "GET", "/example-bucket?encryption");
         Serve
           (HTTP_Response
              ("200 OK", "<ServerSideEncryptionConfiguration><Rule>" &
                 "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>" &
                 "AES256</SSEAlgorithm>" &
                 "</ApplyServerSideEncryptionByDefault></Rule>" &
                 "</ServerSideEncryptionConfiguration>"),
            "GET", "/composed-encryption?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-get-encryption" & CRLF),
            "GET", "/restart-encryption?encryption",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK",
               "<GetBucketMetadataTableConfigurationResult>" &
                 "<MetadataTableConfigurationResult>" &
                 "<S3TablesDestinationResult>" &
                 "<TableBucketArn>socket-bucket-arn</TableBucketArn>" &
                 "<TableName>socket-table</TableName>" &
                 "<TableArn>socket-table-arn</TableArn>" &
                 "<TableNamespace>socket-namespace</TableNamespace>" &
                 "</S3TablesDestinationResult>" &
                 "</MetadataTableConfigurationResult>" &
                 "<Status>future:READY/v2</Status>" &
                 "<Error><ErrorCode></ErrorCode>" &
                 "<ErrorMessage>socket detail</ErrorMessage></Error>" &
                 "</GetBucketMetadataTableConfigurationResult>",
               "x-amz-request-id: metadata-table-request" & CRLF &
               "x-amz-id-2: metadata-table-host" & CRLF),
            "GET", "/example-bucket?metadataTable",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-id: metadata-table-error-request" & CRLF &
               "x-amz-id-2: metadata-table-error-host" & CRLF),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              ("200 OK",
               "<GetBucketMetadataTableConfigurationResult>" &
                 "<MetadataTableConfigurationResult>" &
                 "<S3TablesDestinationResult><TableBucketArn/>" &
                 "<TableName/><TableArn/><TableNamespace/>" &
                 "</S3TablesDestinationResult>" &
                 "</MetadataTableConfigurationResult><Status/>" &
                 "</GetBucketMetadataTableConfigurationResult>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              ("200 OK",
               "<GetBucketMetadataTableConfigurationResult>" &
                 "<MetadataTableConfigurationResult>" &
                 "<S3TablesDestinationResult><TableBucketArn/>" &
                 "<TableName/><TableArn/><TableNamespace/>" &
                 "</S3TablesDestinationResult>" &
                 "</MetadataTableConfigurationResult><Status/>" &
                 "</GetBucketMetadataTableConfigurationResult>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              ("200 OK",
               "<GetBucketMetadataTableConfigurationResult>" &
                 "<MetadataTableConfigurationResult>" &
                 "<S3TablesDestinationResult><TableBucketArn/>" &
                 "<TableName/><TableArn/><TableNamespace/>" &
                 "</S3TablesDestinationResult>" &
                 "</MetadataTableConfigurationResult><Status/>" &
                 "</GetBucketMetadataTableConfigurationResult>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              ("200 OK",
               "<GetBucketMetadataTableConfigurationResult>" &
                 "<MetadataTableConfigurationResult/>" &
                 "<Status>ACTIVE</Status>" &
                 "</GetBucketMetadataTableConfigurationResult>"),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              --  Test-only oversized payload paired with the caller's
              --  explicit 64-byte document ceiling below.
              ("200 OK", "<GetBucketMetadataTableConfigurationResult>" &
                 String'(1 .. 64 => ' ') &
                 "</GetBucketMetadataTableConfigurationResult>"),
            "GET", "/example-bucket?metadataTable");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy><Owner>" &
                 "<DisplayName>socket-owner</DisplayName><ID>owner-id</ID>" &
                 "</Owner><AccessControlList><Grant><Grantee" &
                 " xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""" &
                 " xsi:type=""Group""><URI>socket-group</URI></Grantee>" &
                 "<Permission>READ</Permission></Grant>" &
                 "</AccessControlList></AccessControlPolicy>",
               "x-amz-request-id: acl-request" & CRLF &
               "x-amz-id-2: acl-host" & CRLF),
            "GET", "/example-bucket?acl",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-id: acl-error-request" & CRLF &
               "x-amz-id-2: acl-error-host" & CRLF),
            "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy><AccessControlList>" &
                 "<Grant><Grantee/></Grant></AccessControlList>" &
                 "</AccessControlPolicy>"),
            "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              --  Test-only oversized payload paired with the caller's
              --  explicit 64-byte document ceiling below.
              ("200 OK", "<AccessControlPolicy>" &
                 String'(1 .. 64 => ' ') & "</AccessControlPolicy>"),
            "GET", "/example-bucket?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy><Owner><ID>object-owner" &
                 "</ID></Owner><AccessControlList><Grant><Grantee" &
                 " xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""" &
                 " xsi:type=""CanonicalUser""><ID>principal</ID></Grantee>" &
                 "<Permission>FULL_CONTROL</Permission></Grant>" &
                 "</AccessControlList></AccessControlPolicy>",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-id: object-acl-request" & CRLF &
               "x-amz-id-2: object-acl-host" & CRLF),
            "GET", "/example-bucket/a%20b?acl&versionId=v%2F1",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "GET",
            "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-id: object-acl-error-request" & CRLF &
               "x-amz-id-2: object-acl-error-host" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-charged: charged" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-charged:" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy/>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              ("200 OK", "<AccessControlPolicy><AccessControlList>" &
                 "<Grant><Grantee/></Grant></AccessControlList>" &
                 "</AccessControlPolicy>"),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response
              --  Test-only oversized payload paired with the caller's
              --  explicit 64-byte document ceiling below.
              ("200 OK", "<AccessControlPolicy>" &
                 String'(1 .. 64 => ' ') & "</AccessControlPolicy>"),
            "GET", "/example-bucket/a%20b?acl");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT", "/example-bucket?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?publicAccessBlock",
            Expected_Body_Root => "<PublicAccessBlockConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT", "/example-bucket?policy",
            Expected_Body_Root => "policy",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_Confirm_Remove_Self_Access => "true");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/composed-public-access?publicAccessBlock",
            Expected_Body_Root => "<PublicAccessBlockConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-put-public-access" & CRLF),
            "PUT", "/restart-public-access?publicAccessBlock",
            Expected_Body_Root => "<PublicAccessBlockConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/typed-abac-put?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/composed-abac-put?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-abac-put" & CRLF),
            "PUT", "/restart-abac-put?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "PUT", "/duplicate-abac-put?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-id-2:" & CRLF),
            "PUT", "/empty-abac-put?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              --  Test-only payload is deliberately larger than the
              --  caller-selected 64-byte response ceiling below.
              ("200 OK", String'(1 .. 96 => 'x')),
            "PUT", "/oversized-abac-put?abac",
            Expected_Body_Root => "<AbacStatus",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");

         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/typed-accelerate-put?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/composed-accelerate-put?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-accelerate-put" & CRLF),
            "PUT", "/restart-accelerate-put?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "PUT", "/duplicate-accelerate-put?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-id-2:" & CRLF),
            "PUT", "/empty-accelerate-put?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              --  Test-only payload is deliberately larger than the
              --  caller-selected 64-byte response ceiling below.
              ("200 OK", String'(1 .. 96 => 'x')),
            "PUT", "/oversized-accelerate-put?accelerate",
            Expected_Body_Root => "<AccelerateConfiguration",
            Expected_Bucket_Owner => "123456789012");

         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/typed-request-payment-put?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/composed-request-payment-put?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-request-payment-put" & CRLF),
            "PUT", "/restart-request-payment-put?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "PUT", "/duplicate-request-payment-put?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-id-2:" & CRLF),
            "PUT", "/empty-request-payment-put?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              --  Test-only payload is deliberately larger than the
              --  caller-selected 64-byte response ceiling below.
              ("200 OK", String'(1 .. 96 => 'x')),
            "PUT", "/oversized-request-payment-put?requestPayment",
            Expected_Body_Root => "<RequestPaymentConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/low-level-policy?policy",
            Expected_Body_Root => "low-level-policy-document",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?encryption",
            Expected_Body_Root => "<ServerSideEncryptionConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: typed-put-encryption" & CRLF),
            "PUT", "/typed-put-encryption?encryption",
            Expected_Body_Root => "<ServerSideEncryptionConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/composed-encryption?encryption",
            Expected_Body_Root => "<ServerSideEncryptionConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-put-encryption" & CRLF),
            "PUT", "/restart-put-encryption?encryption",
            Expected_Body_Root => "<ServerSideEncryptionConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT", "/typed-policy?policy",
            Expected_Body_Root => "typed-policy",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT", "/composed-policy?policy",
            Expected_Body_Root => "composed-policy-document",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-put-policy-request" & CRLF),
            "PUT", "/restart-put-policy?policy",
            Expected_Body_Root => "restart-policy-document",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: put-ownership-request" & CRLF &
               "x-amz-id-2: put-ownership-host" & CRLF),
            "PUT", "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", "x"), "PUT",
            "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id: first" & CRLF &
                 "x-amz-request-id: second" & CRLF),
            "PUT", "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-id-2: first" & CRLF &
                 "x-amz-id-2: second" & CRLF),
            "PUT", "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id:" & CRLF),
            "PUT", "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace body is semantically bodyless but one
              --  byte above the caller-selected 64-byte response ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/example-bucket?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/composed-ownership?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: restarted-put-ownership" & CRLF),
            "PUT", "/restart-ownership?ownershipControls",
            Expected_Body_Root => "<OwnershipControls",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "POST",
            "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: create-metadata-table-request" & CRLF &
               "x-amz-id-2: create-metadata-table-host" & CRLF),
            "POST", "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*");
         --  Pinned DeleteObjectAnnotation model fixtures cover every request
         --  and response member.  Opaque values are deliberately distinct so
         --  projection or response-field swaps fail the shared wire oracle.
         Serve
           (HTTP_Response ("200 OK", "x"), "POST",
            "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id: first" & CRLF &
                 "x-amz-request-id: second" & CRLF),
            "POST", "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-id-2: first" & CRLF &
                 "x-amz-id-2: second" & CRLF),
            "POST", "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id:" & CRLF),
            "POST", "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace body is semantically bodyless but one
              --  byte above the paired caller-selected 64-byte ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "POST", "/example-bucket?metadataTable",
            Expected_Body_Root => "<MetadataTableConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-object-version-id: socket-generation" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket%20success&versionId=version%20one",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_If_Match => "socket-etag");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: annotation-request" & CRLF &
               "x-amz-id-2: annotation-host" & CRLF),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-rejection");
         Serve
           (HTTP_Response ("204 No Content", "x"),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-body");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-object-version-id: first" & CRLF &
               "x-amz-object-version-id: second" & CRLF),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-duplicate-version");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-duplicate-charged");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-object-version-id:" & CRLF),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-empty-version");
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-duplicate-request");
         Serve
           (HTTP_Response
              --  Test-only body is one byte above the paired caller-selected
              --  64-byte response ceiling.
              ("204 No Content", String'(1 .. 65 => 'x')),
            "DELETE",
            "/example-bucket/object%20key?annotation&" &
              "annotationName=socket-oversized");
         --  Pinned PutObjectLegalHold fixtures cover the owned body, all
         --  physical controls, the sole output, and one lost-response lane.
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF),
            "PUT",
            "/example-bucket/object%20key?legal-hold&" &
              "versionId=version%20one",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket/object%20key?legal-hold&versionId=absent",
            Expected_Content_MD5 => "1B2M2Y8AsgTpgAmY7PhCfg==",
            Require_Zero_Content_Length => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: put-legal-request" & CRLF &
               "x-amz-id-2: put-legal-host" & CRLF),
            "PUT",
            "/example-bucket/object%20key?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", "x"), "PUT",
            "/example-bucket/object%20key?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/object%20key?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-charged:" & CRLF),
            "PUT", "/example-bucket/object%20key?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id: first" & CRLF &
                 "x-amz-request-id: second" & CRLF),
            "PUT", "/example-bucket/object%20key?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace body is semantically bodyless but one
              --  byte above the paired caller-selected 64-byte ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/example-bucket/object%20key?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           ("", "PUT",
            "/example-bucket/object%20key?legal-hold&versionId=lost",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*", Keep_Open => False);
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF),
            "PUT",
            "/example-bucket/composable-legal?legal-hold&" &
              "versionId=typed%20one",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "PUT", "/example-bucket/composable-legal?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/example-bucket/sync-legal?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace body is semantically bodyless but one
              --  byte above the paired 64-byte operation sink ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/example-bucket/bounded-legal?legal-hold",
            Expected_Body_Root => "<LegalHold",
            Expected_Content_MD5 => "*");
         --  Pinned PutObjectRetention fixtures cover the owned body, every
         --  physical control, sole output, and a lost-response ambiguity lane.
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF),
            "PUT",
            "/example-bucket/object%20key?retention&" &
              "versionId=version%20one",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Governance_Bypass => "true",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket/object%20key?retention&versionId=absent",
            Expected_Content_MD5 => "1B2M2Y8AsgTpgAmY7PhCfg==",
            Expected_Governance_Bypass => "false",
            Require_Zero_Content_Length => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: put-retention-request" & CRLF &
               "x-amz-id-2: put-retention-host" & CRLF),
            "PUT", "/example-bucket/object%20key?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", "x"), "PUT",
            "/example-bucket/object%20key?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/object%20key?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-charged:" & CRLF),
            "PUT", "/example-bucket/object%20key?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id: first" & CRLF &
                 "x-amz-request-id: second" & CRLF),
            "PUT", "/example-bucket/object%20key?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace is semantically bodyless but one byte
              --  above the paired caller-selected 64-byte response ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/example-bucket/object%20key?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           ("", "PUT",
            "/example-bucket/object%20key?retention&versionId=lost",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*", Keep_Open => False);
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF),
            "PUT",
            "/example-bucket/composable-retention?retention&" &
              "versionId=typed%20one",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "PUT", "/example-bucket/composable-retention?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/example-bucket/sync-retention?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace body is semantically bodyless but one
              --  byte above the paired 64-byte operation sink ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/example-bucket/bounded-retention?retention",
            Expected_Body_Root => "<Retention",
            Expected_Content_MD5 => "*");
         --  Pinned PutObjectLockConfiguration fixtures cover exact owned XML,
         --  token and checksum projection, strict singleton output handling,
         --  and the post-admission lost-response ambiguity boundary.
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Body_Exact =>
              "<ObjectLockConfiguration xmlns=""http://s3.amazonaws.com/" &
              "doc/2006-03-01/""><ObjectLockEnabled>Enabled" &
              "</ObjectLockEnabled><Rule><DefaultRetention><Mode>" &
              "GOVERNANCE</Mode><Days>30</Days></DefaultRetention>" &
              "</Rule></ObjectLockConfiguration>",
            Expected_Content_MD5 => "Kr478VnRcOkuIl6e8I6oQQ==",
            Expected_Object_Lock_Token => "socket-lock-token",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "+/bKJQ==");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?object-lock",
            Expected_Content_MD5 => "1B2M2Y8AsgTpgAmY7PhCfg==",
            Require_Zero_Content_Length => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: put-lock-config-request" & CRLF &
               "x-amz-id-2: put-lock-config-host" & CRLF),
            "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", "x"), "PUT",
            "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-charged:" & CRLF),
            "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-request-id: first" & CRLF &
                 "x-amz-request-id: second" & CRLF),
            "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           ("", "PUT", "/example-bucket?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*", Keep_Open => False);
         Serve
           (HTTP_Response
              ("200 OK", "",
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/composable-lock?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "PUT", "/composable-lock?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/sync-lock?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              --  Test-only whitespace body is semantically bodyless but one
              --  byte above the paired 64-byte operation sink ceiling.
              ("200 OK", String'(1 .. 65 => ' ')),
            "PUT", "/bounded-lock?object-lock",
            Expected_Body_Root => "<ObjectLockConfiguration",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", "<AccelerateConfiguration/>",
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?accelerate");
         Serve
           (HTTP_Response
              ("200 OK", "<LegalHold><Status>ON</Status></LegalHold>",
               "x-amz-request-id: legal-request" & CRLF &
               "x-amz-id-2: legal-host" & CRLF),
            "GET",
            "/example-bucket/object?legal-hold&versionId=version%20one",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", "<LegalHold/>"),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: legal-error-request" & CRLF &
               "x-amz-id-2: legal-error-host" & CRLF),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response
              ("200 OK", "<LegalHold/>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response
              ("200 OK", "<LegalHold/>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response
              ("200 OK", "<LegalHold/>", "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response ("200 OK", "<LegalHold><Unknown/></LegalHold>"),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response
              --  42 text bytes plus 23 markup bytes are one past the paired
              --  caller-selected 64-byte document limit.
              ("200 OK", "<LegalHold>" & String'(1 .. 42 => ' ') &
               "</LegalHold>"),
            "GET", "/example-bucket/object?legal-hold");
         Serve
           (HTTP_Response
              ("200 OK", "<LegalHold><Status>ON</Status></LegalHold>"),
            "GET",
            "/example-bucket/composable-legal?legal-hold&" &
              "versionId=typed%20one");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/example-bucket/composable-legal?legal-hold");
         Serve
           (HTTP_Response
              ("200 OK", "<LegalHold><Status>OFF</Status></LegalHold>"),
            "GET", "/example-bucket/sync-legal?legal-hold");
         Serve
           (HTTP_Response
              --  42 text bytes plus 23 markup bytes are one past the paired
              --  64-byte operation sink ceiling.
              ("200 OK", "<LegalHold>" & String'(1 .. 42 => ' ') &
               "</LegalHold>"),
            "GET", "/example-bucket/bounded-legal?legal-hold");
         Serve
           (HTTP_Response
              ("200 OK", "<Retention><Mode>GOVERNANCE</Mode>" &
               "<RetainUntilDate>2027-01-02T03:04:05Z" &
               "</RetainUntilDate></Retention>",
               "x-amz-request-id: retention-request" & CRLF &
               "x-amz-id-2: retention-host" & CRLF),
            "GET",
            "/example-bucket/object?retention&versionId=version%20one",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", "<Retention/>"),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: retention-error-request" & CRLF &
               "x-amz-id-2: retention-error-host" & CRLF),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response
              ("200 OK", "<Retention/>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response
              ("200 OK", "<Retention/>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response
              ("200 OK", "<Retention/>", "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response ("200 OK", "<Retention><Unknown/></Retention>"),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response
              --  42 text bytes plus 23 markup bytes are one past the paired
              --  caller-selected 64-byte document limit.
              ("200 OK", "<Retention>" & String'(1 .. 42 => ' ') &
               "</Retention>"),
            "GET", "/example-bucket/object?retention");
         Serve
           (HTTP_Response
              ("200 OK", "<Retention><Mode>GOVERNANCE</Mode>" &
               "<RetainUntilDate>2028-02-29T23:59:59Z" &
               "</RetainUntilDate></Retention>"),
            "GET",
            "/example-bucket/composable-retention?retention&" &
              "versionId=typed%20one");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/example-bucket/composable-retention?retention");
         Serve
           (HTTP_Response
              ("200 OK", "<Retention><Mode>COMPLIANCE</Mode>" &
               "<RetainUntilDate>2029-01-02T03:04:05Z" &
               "</RetainUntilDate></Retention>"),
            "GET", "/example-bucket/sync-retention?retention");
         Serve
           (HTTP_Response
              --  42 text bytes plus 23 markup bytes are one past the paired
              --  64-byte operation sink ceiling.
              ("200 OK", "<Retention>" & String'(1 .. 42 => ' ') &
               "</Retention>"),
            "GET", "/example-bucket/bounded-retention?retention");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration>" &
                 "<ObjectLockEnabled>Enabled</ObjectLockEnabled><Rule>" &
                 "<DefaultRetention><Years>-0002</Years><Days>" &
                 "+123456789012345678901234567890</Days>" &
                 "<Mode>COMPLIANCE</Mode></DefaultRetention></Rule>" &
                 "</ObjectLockConfiguration>",
               "x-amz-request-id: lock-configuration-request" & CRLF &
               "x-amz-id-2: lock-configuration-host" & CRLF),
            "GET", "/example-bucket?object-lock",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", "<ObjectLockConfiguration/>"),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: lock-configuration-error-request" &
                 CRLF &
               "x-amz-id-2: lock-configuration-error-host" & CRLF),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration/>",
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration/>",
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration/>",
               "x-amz-request-id:" & CRLF),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration><Unknown/>" &
                 "</ObjectLockConfiguration>"),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              --  14 text bytes plus 51 markup bytes are exactly one past
              --  the paired caller-selected 64-byte document limit.
              ("200 OK", "<ObjectLockConfiguration>" &
                 String'(1 .. 14 => ' ') &
                 "</ObjectLockConfiguration>"),
            "GET", "/example-bucket?object-lock");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration>" &
                 "<ObjectLockEnabled>Enabled</ObjectLockEnabled>" &
                 "</ObjectLockConfiguration>"),
            "GET", "/composable-lock?object-lock");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/composable-lock?object-lock");
         Serve
           (HTTP_Response
              ("200 OK", "<ObjectLockConfiguration>" &
                 "<ObjectLockEnabled>Enabled</ObjectLockEnabled>" &
                 "</ObjectLockConfiguration>"),
            "GET", "/sync-lock?object-lock");
         Serve
           (HTTP_Response ("200 OK", String'(1 .. 65 => ' ')),
            "GET", "/bounded-lock?object-lock");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: cors-request" & CRLF &
               "x-amz-id-2: cors-host" & CRLF),
            "DELETE", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: first" & CRLF &
               "x-amz-request-id: second" & CRLF),
            "DELETE", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-id-2: first" & CRLF &
               "x-amz-id-2: second" & CRLF),
            "DELETE", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id:" & CRLF),
            "DELETE", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("403 Forbidden", "<Error><Unknown/></Error>"),
            "DELETE", "/example-bucket?cors");
         Serve
           (HTTP_Response
              ("500 Internal Server Error",
               "<Error><Code>InternalError</Code><Message>" &
               String'(1 .. 256 => 'x') & "</Message></Error>"),
            "DELETE", "/example-bucket?cors");
      end loop;
      Sockets.Close_Socket (Listener);
      State.Complete (True);
   exception
      when Occurrence : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "raw S3 socket server failure: " &
            Ada.Exceptions.Exception_Information (Occurrence));
         if Sockets.Is_Open (Peer) then
            Sockets.Close_Socket (Peer);
         end if;
         if Sockets.Is_Open (Listener) then
            Sockets.Close_Socket (Listener);
         end if;
         State.Complete
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Raw_S3_Server;

   procedure Run_Client is
      Port       : Sockets.Port;
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity   : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
      State.Wait_Ready (Port);
      Parameters.Max_Keys := 2;
      Parameters.Request_Payer := US.To_Unbounded_String ("requester");
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String ("123456789012");
      Parameters.Include_Restore_Status := True;
      declare
         Origin : constant Flyology.HTTP.Origin := Flyology.HTTP.Parse_Origin
           ("http://127.0.0.1:" & Decimal (Natural (Port)));
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Objects_V2
             (Origin, Low_Level.Path_Style, "example-bucket", Parameters,
              Identity, "us-east-1", "20130524T000000Z");

         procedure Require_Configuration_Deletion
           (Result    : Buckets.Delete_Outcome;
            Operation : String) is
         begin
            if Result.Kind /= Buckets.Deletion_Completed
              or else Result.Status /= 204
            then
               raise Program_Error with Operation & " socket mismatch";
            end if;
         end Require_Configuration_Deletion;

         procedure Require_Put_Response
           (Key           : String;
            Expected_Valid : Boolean;
            Expected_Size : String := "";
            Projection_Index : Natural := 0;
            Expected_Checksum_Type : String := "")
         is
            Parameters : Low_Level.Put_Object_Parameters;
            Rejected : Boolean := False;
         begin
            --  Pinned PutObject output position 22 is RequestCharged; its
            --  positive projection must be bound to an admitted requester-
            --  pays input or the response is intentionally invalid.
            if Projection_Index = 22 then
               Parameters.Request_Payer :=
                 US.To_Unbounded_String ("requester");
            end if;
            begin
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Put_Object
                      (Origin, Low_Level.Path_Style, "example-bucket", Key,
                       Parameters,
                       SigV4.SHA256_Hex (Put_Response_Vector_Payload),
                       Identity, "us-east-1", "20130524T000000Z");
                  Source : Upload_Source
                    (Put_Response_Vector_Payload'Access);
                  Result : constant Low_Level.Put_Object_Outcome :=
                    Low_Level.Execute_Put_Object
                      (HTTP, Prepared, Source, Timeout => 5.0);

                  function Projected_Text return String is
                  begin
                     case Projection_Index is
                        when 1 =>
                           return US.To_String (Result.Result.Expiration);
                        when 2 =>
                           return US.To_String (Result.Result.Entity_Tag);
                        when 3 =>
                           return US.To_String (Result.Result.Checksum_CRC32);
                        when 4 =>
                           return US.To_String (Result.Result.Checksum_CRC32C);
                        when 5 =>
                           return US.To_String
                             (Result.Result.Checksum_CRC64NVME);
                        when 6 =>
                           return US.To_String (Result.Result.Checksum_SHA1);
                        when 7 =>
                           return US.To_String (Result.Result.Checksum_SHA256);
                        when 8 =>
                           return US.To_String (Result.Result.Checksum_SHA512);
                        when 9 =>
                           return US.To_String (Result.Result.Checksum_MD5);
                        when 10 =>
                           return US.To_String
                             (Result.Result.Checksum_XXHASH64);
                        when 11 =>
                           return US.To_String
                             (Result.Result.Checksum_XXHASH3);
                        when 12 =>
                           return US.To_String
                             (Result.Result.Checksum_XXHASH128);
                        when 13 =>
                           return US.To_String (Result.Result.Checksum_Type);
                        when 14 =>
                           return US.To_String
                             (Result.Result.Server_Side_Encryption);
                        when 15 =>
                           return US.To_String (Result.Result.Version_ID);
                        when 16 =>
                           return US.To_String
                             (Result.Result.SSE_Customer_Algorithm);
                        when 17 =>
                           return US.To_String
                             (Result.Result.SSE_Customer_Key_MD5);
                        when 18 =>
                           return US.To_String (Result.Result.SSE_KMS_Key_ID);
                        when 19 =>
                           return US.To_String
                             (Result.Result.SSE_KMS_Encryption_Context);
                        when 22 =>
                           return US.To_String (Result.Result.Request_Charged);
                        when others =>
                           return "";
                     end case;
                  end Projected_Text;
               begin
                  if not Expected_Valid then
                     raise Program_Error with
                       "malformed raw PutObject response was accepted: " & Key;
                  elsif Result.Kind /= Low_Level.Object_Put
                    or else US.To_String (Result.Result.Entity_Tag) /=
                      """vector"""
                    or else
                      (Expected_Size'Length > 0
                       and then
                         (not Result.Result.Size.Is_Set
                          or else Result.Result.Size.Value /=
                            Long_Long_Integer'Value (Expected_Size)))
                    or else
                      (Expected_Checksum_Type'Length > 0
                       and then US.To_String (Result.Result.Checksum_Type) /=
                         Expected_Checksum_Type)
                  then
                     raise Program_Error with
                       "valid raw PutObject response mismatch: " & Key;
                  end if;
                  if Projection_Index in Put_Response_Headers'Range then
                     if Projection_Index = 20 then
                        if not Result.Result.Bucket_Key_Enabled.Is_Set
                          or else not Result.Result.Bucket_Key_Enabled.Value
                        then
                           raise Program_Error with
                             "raw PutObject boolean projection mismatch";
                        end if;
                     elsif Projection_Index = 21 then
                        if not Result.Result.Size.Is_Set
                          or else Result.Result.Size.Value /= 0
                        then
                           raise Program_Error with
                             "raw PutObject size projection mismatch";
                        end if;
                     elsif Projected_Text /= US.To_String
                       (Put_Response_Headers (Projection_Index).Value)
                     then
                        raise Program_Error with
                          "raw PutObject header projection mismatch: " & Key;
                     end if;
                  end if;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  if Expected_Valid then
                     raise Program_Error with
                       "valid raw PutObject response was rejected: " & Key;
                  end if;
                  Rejected := True;
            end;
            if not Expected_Valid and then not Rejected then
               raise Program_Error with
                 "raw PutObject response did not reject: " & Key;
            end if;
         end Require_Put_Response;

         procedure Require_Upload_Response
           (Key              : String;
            Expected_Valid   : Boolean;
            Projection_Index : Natural := 0;
            Bind_SHA256      : Boolean := False)
         is
            Upload_Parameters : Low_Level.Upload_Part_Parameters;
            Source : Upload_Source (Put_Response_Vector_Payload'Access);
            Rejected : Boolean := False;
         begin
            Upload_Parameters.Upload_ID :=
              US.To_Unbounded_String ("socket-upload-response");
            Upload_Parameters.Payload_SHA256 := US.To_Unbounded_String
              (SigV4.SHA256_Hex (Put_Response_Vector_Payload));
            if Bind_SHA256 then
               Upload_Parameters.Checksum_Algorithm :=
                 US.To_Unbounded_String ("SHA256");
               Upload_Parameters.Checksum_SHA256 :=
                 US.To_Unbounded_String (Put_Response_Vector_SHA256);
            end if;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Origin, Low_Level.Path_Style, "example-bucket", Key,
                    Upload_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
            begin
               if Key = "upload-response-minimal" then
                  declare
                     --  Derived test geometry: the sole token holds exactly
                     --  this fixed request fixture while the synchronous
                     --  wrapper waits on its owner-driven operation.
                     Pool : aliased Buffers.Pool
                       (Block_Size => Put_Response_Vector_Payload'Length,
                        Capacity => 1);
                     Payload_Buffer : Buffers.Unique_Buffer (Pool'Access);
                  begin
                     Buffers.Acquire (Payload_Buffer);
                     Buffers.Copy_From
                       (Payload_Buffer, Bytes (Put_Response_Vector_Payload));
                     declare
                        Result : constant Upload_Part_Result :=
                          Transfers.Upload_Part
                            (HTTP, Origin, "example-bucket", Key,
                             Upload_Parameters, Payload_Buffer, Identity,
                             Timeout => 5.0);
                     begin
                        if Result.Kind /=
                          Upload_Part_Response_Available
                          or else Result.Disposition /= Part_Published
                          or else Result.Response.Kind /=
                            Low_Level.Part_Uploaded
                          or else not Buffers.Has_Buffer (Payload_Buffer)
                          or else Buffer_String (Payload_Buffer) /=
                            Put_Response_Vector_Payload
                        then
                           raise Program_Error with
                             "composable UploadPart success/ownership " &
                             "mismatch";
                        end if;
                     end;
                     declare
                        --  Parent, HTTP exchange, and one transport child.
                        Set : aliased Operations.Completion_Set (3);
                        Operation : Upload_Part_Operation :=
                          Upload_Part
                            (Set'Access, HTTP'Access, Origin,
                             "example-bucket",
                             "upload-response-composed-first",
                             Upload_Parameters, Payload_Buffer, Identity,
                             HTTP_Client.Deadline_After (5.0));
                        Result : Upload_Part_Result;
                     begin
                        Operations.Wait_All (Set);
                        Finish
                          (Operation, Result, Payload_Buffer);
                        if Result.Kind /=
                          Upload_Part_Response_Available
                          or else Result.Disposition /= Part_Published
                          or else US.To_String
                            (Result.Response.Result.Entity_Tag) /=
                              "composed-part-first"
                          or else not Buffers.Has_Buffer (Payload_Buffer)
                        then
                           raise Program_Error with
                             "composed UploadPart constructor mismatch";
                        end if;

                        Upload_Part
                          (HTTP'Access,
                           Origin,
                           "example-bucket",
                           "upload-response-composed-second",
                           Upload_Parameters,
                           Payload_Buffer,
                           Identity,
                           HTTP_Client.Deadline_After (5.0),
                           Operation => Operation);
                        Operations.Wait_All (Set);
                        Finish
                          (Operation, Result, Payload_Buffer);
                        if Result.Kind /=
                          Upload_Part_Response_Available
                          or else Result.Disposition /= Part_Published
                          or else US.To_String
                            (Result.Response.Result.Entity_Tag) /=
                              "composed-part-second"
                          or else not Buffers.Has_Buffer (Payload_Buffer)
                          or else Buffer_String (Payload_Buffer) /=
                            Put_Response_Vector_Payload
                        then
                           raise Program_Error with
                             "composed UploadPart restart mismatch";
                        end if;
                     end;
                  end;
                  return;
               end if;
               begin
                  declare
                     Result : constant Low_Level.Upload_Part_Outcome :=
                       Low_Level.Execute_Upload_Part
                         (HTTP, Prepared, Source, Timeout => 5.0);

                     function Projected_Text return String is
                     begin
                        case Projection_Index is
                           when 1 =>
                              return US.To_String
                                (Result.Result.Server_Side_Encryption);
                           when 2 =>
                              return US.To_String (Result.Result.Entity_Tag);
                           when 3 =>
                              return US.To_String
                                (Result.Result.Checksum_CRC32);
                           when 4 =>
                              return US.To_String
                                (Result.Result.Checksum_CRC32C);
                           when 5 =>
                              return US.To_String
                                (Result.Result.Checksum_CRC64NVME);
                           when 6 =>
                              return US.To_String
                                (Result.Result.Checksum_SHA1);
                           when 7 =>
                              return US.To_String
                                (Result.Result.Checksum_SHA256);
                           when 8 =>
                              return US.To_String
                                (Result.Result.Checksum_SHA512);
                           when 9 =>
                              return US.To_String (Result.Result.Checksum_MD5);
                           when 10 =>
                              return US.To_String
                                (Result.Result.Checksum_XXHASH64);
                           when 11 =>
                              return US.To_String
                                (Result.Result.Checksum_XXHASH3);
                           when 12 =>
                              return US.To_String
                                (Result.Result.Checksum_XXHASH128);
                           when 13 =>
                              return US.To_String
                                (Result.Result.SSE_Customer_Algorithm);
                           when 14 =>
                              return US.To_String
                                (Result.Result.SSE_Customer_Key_MD5);
                           when 15 =>
                              return US.To_String
                                (Result.Result.SSE_KMS_Key_ID);
                           when 16 =>
                              return US.To_String
                                (Result.Result.Bucket_Key_Enabled);
                           when 17 =>
                              return US.To_String
                                (Result.Result.Request_Charged);
                           when others =>
                              return "";
                        end case;
                     end Projected_Text;
                  begin
                     if not Expected_Valid then
                        raise Program_Error with
                          "malformed raw UploadPart response was accepted: " &
                          Key;
                     elsif Result.Kind /= Low_Level.Part_Uploaded
                       or else US.Length (Result.Result.Entity_Tag) = 0
                       or else
                         (Projection_Index in Upload_Response_Headers'Range
                          and then Projected_Text /= US.To_String
                            (Upload_Response_Headers
                               (Projection_Index).Value))
                     then
                        raise Program_Error with
                          "valid raw UploadPart response mismatch: " & Key;
                     end if;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     if Expected_Valid then
                        raise Program_Error with
                          "valid raw UploadPart response was rejected: " &
                          Key;
                     end if;
                     Rejected := True;
               end;
            end;
            if not Expected_Valid and then not Rejected then
               raise Program_Error with
                 "raw UploadPart response did not reject: " & Key;
            end if;
         end Require_Upload_Response;

         function Conditional_Put
           (Value         : not null access constant String;
            If_Match      : String := "";
            If_None_Match : String := "")
            return Low_Level.Put_Object_Outcome
         is
            Source : Upload_Source (Value);
         begin
            if If_None_Match = "*" and then If_Match'Length = 0 then
               return Objects.Put_If_Absent
                 (HTTP, Origin, "example-bucket", "conditional-put",
                  Source, SigV4.SHA256_Hex (Value.all), Identity,
                  Timeout => 5.0);
            elsif If_Match'Length > 0
              and then If_None_Match'Length = 0
            then
               return Objects.Put_If_Matches
                 (HTTP, Origin, "example-bucket", "conditional-put",
                  If_Match, Source, SigV4.SHA256_Hex (Value.all), Identity,
                  Timeout => 5.0);
            end if;
            raise Program_Error with "invalid conditional PutObject test";
         end Conditional_Put;

         procedure Require_Conditional_Get
           (Expected_Body, Expected_ETag : String)
         is
            Result : constant Objects.Whole_Get_Outcome :=
              Objects.Get_Whole
                (HTTP, Origin, "example-bucket", "conditional-put",
                 Expected_Body'Length, Identity,
                 Expected_Entity_Tag => Expected_ETag, Timeout => 5.0);
         begin
            if Result.Kind /= Objects.Whole_Object_Read
              or else Result.Status /= 200
              or else not Result.Result.Content_Length.Is_Set
              or else Result.Result.Content_Length.Value /=
                Expected_Body'Length
              or else US.To_String (Result.Result.Entity_Tag) /=
                Expected_ETag
            then
               raise Program_Error with
                 "conditional PutObject GetObject head mismatch";
            end if;
            if Flyology.Bytes.To_Byte_String (Result.Object_Bytes) /=
              Expected_Body
            then
               raise Program_Error with
                 "conditional PutObject GetObject body mismatch";
            end if;
         end Require_Conditional_Get;

         procedure Require_Stale_Get_Rejected (Expected_ETag : String) is
            Result : constant Objects.Whole_Get_Outcome :=
              Objects.Get_Whole
                (HTTP, Origin, "example-bucket", "conditional-put", 64,
                 Identity, Expected_Entity_Tag => Expected_ETag,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Objects.Whole_Get_Rejected
              or else Result.Status /= 412
              or else US.To_String (Result.Error.Code) /=
                "PreconditionFailed"
            then
               raise Program_Error with
                 "stale generation-bound GetObject was not rejected";
            end if;
         end Require_Stale_Get_Rejected;

         procedure Require_Rewindable_Put_Rejected is
            Source : Rewindable_Probe;
            Outcome : Low_Level.Put_Object_Outcome;
         begin
            begin
               Outcome := Objects.Put_If_Absent
                 (HTTP, Origin, "example-bucket", "conditional-put",
                  Source, SigV4.SHA256_Hex (""), Identity,
                  Timeout => 5.0);
               raise Program_Error with
                 "rewindable conditional PutObject source was accepted";
            exception
               when Low_Level.Invalid_Request =>
                  null;
            end;
            if Outcome.Status /= 500 then
               raise Program_Error with
                 "rejected conditional PutObject changed its outcome";
            end if;
         end Require_Rewindable_Put_Rejected;

         procedure Require_Invalid_Condition_Rejected is
            function Is_Rejected (Entity_Tag : String) return Boolean is
               Source : Upload_Source (Conditional_Stale'Access);
            begin
               declare
                  Unexpected : constant Low_Level.Put_Object_Outcome :=
                    Objects.Put_If_Matches
                      (HTTP, Origin, "example-bucket", "conditional-put",
                       Entity_Tag, Source,
                       SigV4.SHA256_Hex (Conditional_Stale), Identity,
                       Timeout => 5.0);
               begin
                  raise Program_Error with
                    "invalid conditional PutObject entity tag returned" &
                    Unexpected.Status'Image;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  return True;
            end Is_Rejected;
         begin
            if not Is_Rejected ("*")
              or else not Is_Rejected ("W/""weak""")
              or else not Is_Rejected
                ('"' & Character'Val (16#7F#) & '"')
            then
               raise Program_Error with
                 "invalid conditional PutObject entity tag was admitted";
            end if;
         end Require_Invalid_Condition_Rejected;

         procedure Require_Invalid_Generation_Rejected is
            Put_Rejected : Boolean := False;
            Get_Rejected : Boolean := False;
         begin
            begin
               declare
                  Source : Upload_Source (Conditional_Stale'Access);
                  Unexpected : constant Low_Level.Put_Object_Outcome :=
                    Objects.Put_If_Matches
                      (HTTP, Origin, "example-bucket", "conditional-put",
                       """conditional-second""", Source,
                       SigV4.SHA256_Hex (Conditional_Stale), Identity,
                       Timeout => 5.0);
               begin
                  raise Program_Error with
                    "malformed PutObject generation was accepted" &
                    Unexpected.Status'Image;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Put_Rejected := True;
            end;
            begin
               declare
                  Unexpected : constant Objects.Whole_Get_Outcome :=
                    Objects.Get_Whole
                      (HTTP, Origin, "example-bucket", "conditional-put", 64,
                       Identity,
                       Expected_Entity_Tag => """conditional-second""",
                       Timeout => 5.0);
               begin
                  raise Program_Error with
                    "malformed GetObject generation was accepted" &
                    Unexpected.Status'Image;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Get_Rejected := True;
            end;
            if not Put_Rejected or else not Get_Rejected then
               raise Program_Error with
                 "malformed synchronous generation response was accepted";
            end if;
         end Require_Invalid_Generation_Rejected;

         procedure Run_Conditional_Put_Lifecycle is
            Created : constant Low_Level.Put_Object_Outcome :=
              Conditional_Put
                (Conditional_First'Access, If_None_Match => "*");
            Collision : constant Low_Level.Put_Object_Outcome :=
              Conditional_Put
                (Conditional_Collision'Access, If_None_Match => "*");
         begin
            if Created.Kind /= Low_Level.Object_Put
              or else Created.Status /= 200
              or else US.To_String (Created.Result.Entity_Tag) /=
                """conditional-first"""
              or else Collision.Kind /= Low_Level.Put_Object_Rejected
              or else Collision.Status /= 412
              or else US.To_String (Collision.Error.Code) /=
                "PreconditionFailed"
            then
               raise Program_Error with
                 "conditional create/collision socket mismatch";
            end if;
            declare
               Parameters : Low_Level.Head_Object_Parameters;
               Request : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "conditional-put", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Request, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Found
                 or else Result.Status /= 200
                 or else Result.Result.Content_Length /=
                   Conditional_First'Length
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """conditional-first"""
               then
                  raise Program_Error with
                    "conditional collision changed HeadObject state";
               end if;
            end;
            Require_Conditional_Get
              (Conditional_First, """conditional-first""");
            declare
               Replaced : constant Low_Level.Put_Object_Outcome :=
                 Conditional_Put
                   (Conditional_Second'Access,
                    If_Match => """conditional-first""");
               Stale : constant Low_Level.Put_Object_Outcome :=
                 Conditional_Put
                   (Conditional_Stale'Access,
                    If_Match => """conditional-first""");
            begin
               if Replaced.Kind /= Low_Level.Object_Put
                 or else Replaced.Status /= 200
                 or else US.To_String (Replaced.Result.Entity_Tag) /=
                   """conditional-second"""
                 or else Stale.Kind /= Low_Level.Put_Object_Rejected
                 or else Stale.Status /= 412
                 or else US.To_String (Stale.Error.Code) /=
                   "PreconditionFailed"
               then
                  raise Program_Error with
                    "conditional replace/stale socket mismatch";
               end if;
            end;
            Require_Stale_Get_Rejected ("""conditional-first""");
            Require_Conditional_Get
              (Conditional_Second, """conditional-second""");
            Require_Invalid_Generation_Rejected;
         end Run_Conditional_Put_Lifecycle;

         procedure Require_Tag_Header_Boundaries is
            Roman_Eight : constant String :=
              Character'Val (16#E2#) & Character'Val (16#85#) &
              Character'Val (16#A7#);
            Superscript_Two : constant String :=
              Character'Val (16#C2#) & Character'Val (16#B2#);

            function Repeat (Value : String; Count : Natural) return String is
               Result : String (1 .. Value'Length * Count);
               Last   : Natural := 0;
            begin
               for Iteration in 1 .. Count loop
                  Result (Last + 1 .. Last + Value'Length) := Value;
                  Last := Last + Value'Length;
               end loop;
               return Result;
            end Repeat;

            Small : Flyology.Object_Storage.Object_Tag_Set;
            Exact : Flyology.Object_Storage.Object_Tag_Set;
            Parsed : Flyology.Object_Storage.Object_Tag_Set;
            Rejected : Boolean := False;
         begin
            Small.Length := 3;
            Small.Items (1) :=
              (Key   => US.To_Unbounded_String ("a_b"),
               Value => US.To_Unbounded_String ("x+y"));
            Small.Items (2) :=
              (Key   => US.To_Unbounded_String ("number"),
               Value => US.To_Unbounded_String
                 (Roman_Eight & Superscript_Two));
            Small.Items (3) :=
              (Key   => US.To_Unbounded_String ("reserved"),
               Value => US.To_Unbounded_String (" /="));
            declare
               Header : constant String := S3_Tagging.Serialize_Header (Small);
            begin
               if Header /=
                 "a_b=x%2By&number=%E2%85%A7%C2%B2&reserved=%20%2F%3D"
               then
                  raise Program_Error with
                    "PutObject tag header reserved-byte encoding mismatch";
               end if;
               Parsed := S3_Tagging.Parse_Header (Header);
               if Parsed /= Small then
                  raise Program_Error with
                    "PutObject tag header round trip mismatch";
               end if;
            end;
            begin
               Parsed := S3_Tagging.Parse_Header ("a=1&a=2");
               raise Program_Error with
                 "duplicate PutObject tag header key was accepted";
            exception
               when S3_Tagging.Malformed_Tagging_Query =>
                  null;
            end;

            --  Two 3,449-byte encoded pairs, two separators, and a
            --  1,292-byte third pair total exactly the 8 KiB wire bound.
            Exact.Length := 3;
            for Index in 1 .. 2 loop
               Exact.Items (Index) :=
                 (Key   => US.To_Unbounded_String
                    (Repeat (Roman_Eight, 127) & Decimal (Index)),
                  Value => US.To_Unbounded_String
                    (Repeat (Roman_Eight, 256)));
            end loop;
            Exact.Items (3) :=
              (Key   => US.To_Unbounded_String ("3"),
               Value => US.To_Unbounded_String
                 (Repeat (Roman_Eight, 143) & "abc"));
            declare
               Header : constant String := S3_Tagging.Serialize_Header (Exact);
            begin
               if Header'Length /= S3_Tagging.Maximum_Query_Bytes
                 or else S3_Tagging.Parse_Header (Header) /= Exact
               then
                  raise Program_Error with
                    "exact-bound PutObject tag header mismatch";
               end if;
            end;
            Exact.Items (3).Value := US.To_Unbounded_String
              (Repeat (Roman_Eight, 143) & "abcd");
            begin
               declare
                  Unexpected : constant String :=
                    S3_Tagging.Serialize_Header (Exact);
                  pragma Unreferenced (Unexpected);
               begin
                  null;
               end;
            exception
               when S3_Tagging.Invalid_Tag =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "over-bound PutObject tag header was accepted";
            end if;
         end Require_Tag_Header_Boundaries;

         procedure Run_Lost_Put_Reconciliation is
            Head_Parameters : Low_Level.Head_Object_Parameters;
            Head_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Object
                (Origin, Low_Level.Path_Style, "example-bucket", "lost-put",
                 Head_Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Options : Objects.Complete_Put_Options :=
              Objects.Default_Complete_Put_Options;
            Lost_Response : Boolean := False;
         begin
            declare
               Before : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Head_Prepared, Timeout => 5.0);
            begin
               if Before.Kind /= Low_Level.Head_Object_Rejected
                 or else Before.Status /= 404
               then
                  raise Program_Error with
                    "lost-response PutObject priming HEAD mismatch";
               end if;
            end;
            Options.Conditions.If_None_Match := US.To_Unbounded_String ("*");
            begin
               declare
                  Source : Upload_Source (Lost_Put_Payload'Access);
                  Ignored : constant Low_Level.Put_Object_Outcome :=
                    Objects.Put_Object
                      (HTTP, Origin, "example-bucket", "lost-put", Source,
                       SigV4.SHA256_Hex (Lost_Put_Payload), Identity,
                       Options => Options, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request | Program_Error |
                    Constraint_Error =>
                  raise;
               when others =>
                  --  The server accepted the body but returned no response.
                  --  The synchronous API must leave this publication unknown.
                  Lost_Response := True;
            end;
            if not Lost_Response then
               raise Program_Error with
                 "lost PutObject response was classified conclusively";
            end if;
            declare
               After : constant Objects.Whole_Get_Outcome :=
                 Objects.Get_Whole
                   (HTTP, Origin, "example-bucket", "lost-put",
                    Lost_Put_Payload'Length, Identity,
                    Expected_Entity_Tag => """lost-put-generation""",
                    Timeout => 5.0);
            begin
               if After.Kind /= Objects.Whole_Object_Read
                 or else After.Status /= 200
                 or else US.To_String (After.Result.Entity_Tag) /=
                   """lost-put-generation"""
                 or else Flyology.Bytes.To_Byte_String
                   (After.Object_Bytes) /= Lost_Put_Payload
               then
                  raise Program_Error with
                    "lost PutObject response reconciliation mismatch";
               end if;
            end;
         end Run_Lost_Put_Reconciliation;
      begin
         HTTP_Client.Configure (HTTP, Origin);
         declare
            --  Test-reference geometry: two tokens cover one retained request
            --  and one response destination. A 96-byte block holds every
            --  success and modeled error fixture, while the maintained
            --  112-byte response proves the typed overflow lane; changing
            --  either changes corpus scope.
            Pool : aliased Buffers.Pool (Block_Size => 96, Capacity => 2);
            Payload_Buffer : Buffers.Unique_Buffer (Pool'Access);
            Destination : aliased Buffers.Unique_Buffer (Pool'Access);
         begin
            Buffers.Acquire (Payload_Buffer);
            Buffers.Copy_From
              (Payload_Buffer, Bytes ("scoped-put-body"));
            declare
               --  Object, HTTP exchange, and its single transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Conditional_Put_Operation :=
                 Put_If_Absent
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "scoped-put", Payload_Buffer,
                    SigV4.SHA256_Hex ("scoped-put-body"), Identity,
                    HTTP_Client.Deadline_After (5.0));
               Result : Conditional_Put_Result;
            begin
               if Buffers.Has_Buffer (Payload_Buffer) then
                  raise Program_Error with
                    "scoped PutObject did not move its input token";
               end if;
               Operations.Wait_All (Set);
               Finish (Operation, Result, Payload_Buffer);
               if Result.Kind /= Put_Response_Available
                 or else Result.Disposition /= Published
                 or else Result.Response.Kind /= Low_Level.Object_Put
                 or else US.To_String
                   (Result.Response.Result.Entity_Tag) /=
                     """scoped-generation"""
                 or else not Buffers.Has_Buffer (Payload_Buffer)
                 or else Buffer_String (Payload_Buffer) /= "scoped-put-body"
               then
                  raise Program_Error with
                    "scoped PutObject success/ownership mismatch";
               end if;
            end;

            Buffers.Copy_From
              (Payload_Buffer, Bytes ("scoped-cas-body"));
            declare
               Result : constant Conditional_Put_Result :=
                 Objects.Put_If_Matches
                   (HTTP, Origin, "example-bucket", "scoped-cas",
                    """scoped-generation""", Payload_Buffer,
                    SigV4.SHA256_Hex ("scoped-cas-body"), Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= Put_Response_Available
                 or else Result.Disposition /= Precondition_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Put_Object_Rejected
                 or else not Buffers.Has_Buffer (Payload_Buffer)
                 or else Buffer_String (Payload_Buffer) /= "scoped-cas-body"
               then
                  raise Program_Error with
                    "synchronous composable CAS mapping mismatch: kind=" &
                    Conditional_Put_Result_Kind'Image (Result.Kind) &
                    " disposition=" &
                    Publication_Disposition'Image
                      (Result.Disposition) & " failure=" &
                    Failure_Reason'Image (Result.Failure) &
                    " buffer=" & Boolean'Image
                      (Buffers.Has_Buffer (Payload_Buffer)) &
                    (if Result.Kind = Put_Exchange_Failed
                     then " http=" &
                       HTTP_Client.Exchange_Result_Kind'Image
                         (Result.HTTP_Result) & " phase=" &
                       HTTP_Client.Exchange_Phase'Image (Result.HTTP_Phase) &
                       " detail=" & US.To_String (Result.Detail)
                     else "");
               end if;
            end;

            Buffers.Acquire (Destination);
            declare
               --  Object, HTTP exchange, and its single transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Whole_Get_Operation := Get_Whole
                 (Set'Access, HTTP'Access, Origin, "example-bucket",
                  "scoped-get", Destination'Access, Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Expected_Entity_Tag => """scoped-generation""");
               Result : Whole_Get_Result;
            begin
               if Buffers.Has_Buffer (Destination) then
                  raise Program_Error with
                    "scoped GetObject did not move its output token";
               end if;
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Whole_Get_Response_Available
                 or else Result.Response.Kind /= Low_Level.Object_Opened
                 or else US.To_String (Result.Response.Result.Entity_Tag) /=
                   """scoped-generation"""
                 or else US.To_String (Result.Response.Result.Version_ID) /=
                   "scoped-version"
                 or else Buffer_String (Destination) /= "scoped-get-body"
               then
                  raise Program_Error with
                    "scoped same-response GetObject mismatch";
               end if;
            end;

            declare
               Result : constant Whole_Get_Result :=
                 Objects.Get_Whole
                   (HTTP, Origin, "example-bucket", "scoped-oversized",
                    Destination, Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Whole_Get_Exchange_Failed
                 or else Result.Failure /= Response_Too_Large
                 or else not Result.Required_Body_Length.Known
                 or else Result.Required_Body_Length.Bytes /= 112
                 or else Buffers.Length (Destination) /= 0
               then
                  raise Program_Error with
                    "scoped GetObject capacity mapping mismatch";
               end if;
            end;

            declare
               --  Object, HTTP exchange, and its single transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Range_Get_Operation := Get_Range
                 (Set'Access, HTTP'Access, Origin, "example-bucket",
                  "scoped-range",
                  (Kind  => Flyology.Object_Storage.Bounded_Range,
                   First => 2, Last => 5, Count => 0),
                  Destination'Access, Identity,
                  HTTP_Client.Deadline_After (5.0),
                  """range-generation""");
               Result : Range_Get_Result;
            begin
               if Buffers.Has_Buffer (Destination) then
                  raise Program_Error with
                    "scoped range GetObject did not move its output token";
               end if;
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Range_Get_Response_Available
                 or else Result.Response.Kind /= Low_Level.Object_Opened
                 or else not Result.Has_Resolved_Range
                 or else Result.Resolved.First /= 2
                 or else Result.Resolved.Last /= 5
                 or else Result.Resolved.Total_Length /= 10
                 or else Buffer_String (Destination) /= "2345"
               then
                  raise Program_Error with
                    "scoped bounded range binding mismatch";
               end if;
            end;

            declare
               Result : constant Range_Get_Result :=
                 Objects.Get_Range
                   (HTTP, Origin, "example-bucket", "scoped-range-open",
                    (Kind  => Flyology.Object_Storage.Open_Ended_Range,
                     First => 6, Last => 0, Count => 0),
                    Destination, Identity, """range-generation""",
                    Timeout => 5.0);
            begin
               if Result.Kind /= Range_Get_Response_Available
                 or else not Result.Has_Resolved_Range
                 or else Result.Resolved.First /= 6
                 or else Result.Resolved.Last /= 9
                 or else Result.Resolved.Total_Length /= 10
                 or else Buffer_String (Destination) /= "6789"
               then
                  raise Program_Error with
                    "synchronous open-ended range binding mismatch";
               end if;
            end;

            declare
               Result : constant Range_Get_Result :=
                 Objects.Get_Range
                   (HTTP, Origin, "example-bucket", "scoped-range-suffix",
                    (Kind  => Flyology.Object_Storage.Suffix_Range,
                     First => 0, Last => 0, Count => 3),
                    Destination, Identity, """range-generation""",
                    Timeout => 5.0);
            begin
               if Result.Kind /= Range_Get_Response_Available
                 or else not Result.Has_Resolved_Range
                 or else Result.Resolved.First /= 7
                 or else Result.Resolved.Last /= 9
                 or else Result.Resolved.Total_Length /= 10
                 or else Buffer_String (Destination) /= "789"
               then
                  raise Program_Error with
                    "synchronous suffix range binding mismatch";
               end if;
            end;

            declare
               Result : constant Range_Get_Result :=
                 Objects.Get_Range
                   (HTTP, Origin, "example-bucket", "scoped-range-wrong",
                    (Kind  => Flyology.Object_Storage.Bounded_Range,
                     First => 2, Last => 5, Count => 0),
                    Destination, Identity, """range-generation""",
                    Timeout => 5.0);
            begin
               if Result.Kind /= Range_Get_Exchange_Failed
                 or else Result.Failure /=
                   Corrupt_Or_Invalid_Response
                 or else Buffers.Length (Destination) /= 0
               then
                  raise Program_Error with
                    "range GetObject accepted the wrong returned interval";
               end if;
            end;

            declare
               Result : constant Range_Get_Result :=
                 Objects.Get_Range
                   (HTTP, Origin, "example-bucket",
                    "scoped-range-rejected",
                    (Kind  => Flyology.Object_Storage.Bounded_Range,
                     First => 2, Last => 5, Count => 0),
                    Destination, Identity, """stale-generation""",
                    Timeout => 5.0);
            begin
               if Result.Kind /= Range_Get_Response_Available
                 or else Result.Response.Kind /=
                   Low_Level.Get_Object_Rejected
                 or else Result.Response.Status /= 412
                 or else Result.Has_Resolved_Range
                 or else Buffers.Length (Destination) /= 0
               then
                  raise Program_Error with
                    "range GetObject rejection mapping mismatch";
               end if;
            end;

            declare
               Result : constant Range_Get_Result :=
                 Objects.Get_Range
                   (HTTP, Origin, "example-bucket",
                    "scoped-range-duplicate",
                    (Kind  => Flyology.Object_Storage.Bounded_Range,
                     First => 2, Last => 5, Count => 0),
                    Destination, Identity, """range-generation""",
                    Timeout => 5.0);
            begin
               if Result.Kind /= Range_Get_Exchange_Failed
                 or else Result.Failure /=
                   Corrupt_Or_Invalid_Response
                 or else Buffers.Length (Destination) /= 0
               then
                  raise Program_Error with
                    "range GetObject accepted duplicate singleton metadata";
               end if;
            end;

            declare
               --  Test-reference capacity: four bytes is one less than the
               --  maintained five-byte range response, proving exact required
               --  length restoration without introducing product policy.
               Small_Pool : aliased Buffers.Pool
                 (Block_Size => 4, Capacity => 1);
               Small : aliased Buffers.Unique_Buffer (Small_Pool'Access);
            begin
               Buffers.Acquire (Small);
               declare
                  Result : constant Range_Get_Result :=
                    Objects.Get_Range
                      (HTTP, Origin, "example-bucket",
                       "scoped-range-oversized",
                       (Kind  => Flyology.Object_Storage.Bounded_Range,
                        First => 2, Last => 6, Count => 0),
                       Small, Identity, """range-generation""",
                       Timeout => 5.0);
               begin
                  if Result.Kind /= Range_Get_Exchange_Failed
                    or else Result.Failure /= Response_Too_Large
                    or else not Result.Required_Body_Length.Known
                    or else Result.Required_Body_Length.Bytes /= 5
                    or else Buffers.Length (Small) /= 0
                  then
                     raise Program_Error with
                       "range GetObject capacity mapping mismatch";
                  end if;
               end;
            end;

            declare
               Parameters : Low_Level.Head_Object_Parameters :=
                 (others => <>);
            begin
               Parameters.If_Match :=
                 US.To_Unbounded_String ("""head-generation""");
               Parameters.Version_ID :=
                 US.To_Unbounded_String ("head-version");
               declare
                  --  Object, HTTP exchange, and its single transport child.
                  Set : aliased Operations.Completion_Set (3);
                  Operation : Head_Operation := Head_Object
                    (Set'Access, HTTP'Access, Origin, "example-bucket",
                     "scoped-head", Parameters, Identity,
                     HTTP_Client.Deadline_After (5.0));
                  Result : Head_Result;
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /= Head_Response_Available
                    or else Result.Response.Kind /= Low_Level.Object_Found
                    or else Result.Response.Result.Content_Length /= 10
                    or else US.To_String
                      (Result.Response.Result.Entity_Tag) /=
                        """head-generation"""
                    or else US.To_String
                      (Result.Response.Result.Version_ID) /= "head-version"
                  then
                     raise Program_Error with
                       "scoped HeadObject response mismatch";
                  end if;
               end;
            end;

            declare
               Parameters : constant Low_Level.Head_Object_Parameters :=
                 (others => <>);
               Result : constant Head_Result := Objects.Head_Object
                 (HTTP, Origin, "example-bucket", "scoped-head-missing",
                  Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Head_Response_Available
                 or else Result.Response.Kind /=
                   Low_Level.Head_Object_Rejected
                 or else Result.Response.Status /= 404
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "scoped-head-request"
                 or else US.To_String (Result.Response.Error.Host_ID) /=
                   "scoped-head-host"
               then
                  raise Program_Error with
                    "synchronous HeadObject rejection mismatch";
               end if;
            end;

            declare
               Parameters : constant Low_Level.Head_Object_Parameters :=
                 (others => <>);
               Result : constant Head_Result := Objects.Head_Object
                 (HTTP, Origin, "example-bucket", "scoped-head-duplicate",
                  Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Head_Exchange_Failed
                 or else Result.Failure /=
                   Corrupt_Or_Invalid_Response
               then
                  raise Program_Error with
                    "HeadObject accepted duplicate singleton metadata";
               end if;
            end;

            declare
               Parameters : Low_Level.Create_Bucket_Parameters :=
                 (others => <>);
            begin
               Parameters.Configuration.Location_Constraint :=
                 US.To_Unbounded_String ("us-west-2");
               declare
                  Result : constant Create_Bucket_Result :=
                    Buckets.Create
                      (HTTP, Origin, "typed-created", Parameters, Identity,
                       Region => "us-west-2", Timeout => 5.0);
               begin
                  if Result.Kind /= Create_Bucket_Response_Available
                    or else Result.Disposition /=
                      Bucket_Creation_Completed
                    or else Result.Failure /= No_Failure
                    or else Result.Admission /= HTTP_Client.Response_Observed
                    or else Result.Response.Kind /= Low_Level.Bucket_Created
                    or else US.To_String (Result.Response.Result.Location) /=
                      "/typed-created"
                    or else US.To_String
                      (Result.Response.Result.Bucket_ARN) /=
                        "arn:aws:s3:::typed-created"
                  then
                     if Result.Kind = Create_Bucket_Exchange_Failed
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "CreateBucket HTTP failure: " &
                           HTTP_Client.Exchange_Result_Kind'Image
                             (Result.HTTP_Result) & " / " &
                           HTTP_Client.Exchange_Phase'Image
                             (Result.HTTP_Phase) & " / " &
                           US.To_String (Result.Detail));
                     end if;
                     raise Program_Error with
                       "composable CreateBucket response mismatch: kind=" &
                       Create_Bucket_Result_Kind'Image
                         (Result.Kind) & " disposition=" &
                       Bucket_Creation_Disposition'Image
                         (Result.Disposition) & " failure=" &
                       Failure_Reason'Image (Result.Failure) &
                       " admission=" &
                       HTTP_Client.Admission_Certainty'Image
                         (Result.Admission) &
                       (if Result.Kind =
                           Create_Bucket_Response_Available
                        then " response=" &
                          Low_Level.Create_Bucket_Outcome_Kind'Image
                            (Result.Response.Kind) & " status=" &
                          Natural'Image (Result.Response.Status) &
                          (if Result.Response.Kind = Low_Level.Bucket_Created
                           then " location=" &
                             US.To_String
                               (Result.Response.Result.Location) &
                             " arn=" &
                             US.To_String
                               (Result.Response.Result.Bucket_ARN)
                           else "")
                        else " http=" &
                          HTTP_Client.Exchange_Result_Kind'Image
                            (Result.HTTP_Result) & " phase=" &
                          HTTP_Client.Exchange_Phase'Image
                            (Result.HTTP_Phase) & " detail=" &
                          US.To_String (Result.Detail));
                  end if;
               end;
            end;

            declare
               Result : constant Buckets.Create_Outcome :=
                 Buckets.Create
                   (HTTP, Origin, "convenience-created", Identity,
                    Region => "us-west-2", Timeout => 5.0);
            begin
               if Result.Kind /= Buckets.Creation_Completed
                 or else US.To_String (Result.Location) /=
                   "/convenience-created"
               then
                  raise Program_Error with
                    "synchronous CreateBucket response mismatch";
               end if;
            end;

            declare
               Parameters : Low_Level.Create_Bucket_Parameters :=
                 (others => <>);
            begin
               Parameters.Configuration.Location_Constraint :=
                 US.To_Unbounded_String ("us-west-2");
               declare
                  Result : constant Create_Bucket_Result :=
                    Buckets.Create
                      (HTTP, Origin, "duplicate-create", Parameters, Identity,
                       Region => "us-west-2", Timeout => 5.0);
               begin
                  if Result.Kind /= Create_Bucket_Exchange_Failed
                    or else Result.Disposition /=
                      Bucket_Creation_Outcome_Unknown
                    or else Result.Failure /=
                      Corrupt_Or_Invalid_Response
                  then
                     raise Program_Error with
                       "CreateBucket accepted duplicate response metadata";
                  end if;
               end;
            end;

            declare
               Parameters : Low_Level.Create_Bucket_Parameters :=
                 (others => <>);
               --  CreateBucket parent, HTTP exchange, and transport child.
               Set : aliased Operations.Completion_Set (3);
               Result : Create_Bucket_Result;
            begin
               Parameters.Configuration.Location_Constraint :=
                 US.To_Unbounded_String ("us-west-2");
               declare
                  Operation : Create_Bucket_Operation :=
                    Create
                      (Set'Access, HTTP'Access, Origin, "restart-created",
                       Parameters, Identity,
                       HTTP_Client.Deadline_After (5.0), "us-west-2");
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Disposition /=
                    Bucket_Creation_Completed
                  then
                     raise Program_Error with
                       "composed CreateBucket first result mismatch";
                  end if;
                  Create
                    (HTTP'Access,
                     Origin,
                     "restart-existing",
                     Parameters,
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     "us-west-2",
                     Operation => Operation);
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /= Create_Bucket_Response_Available
                    or else Result.Disposition /=
                      Bucket_Definitely_Not_Created
                    or else Result.Failure /= Invalid_Request
                    or else Result.Response.Kind /=
                      Low_Level.Create_Bucket_Rejected
                    or else US.To_String (Result.Response.Error.Request_ID) /=
                      "restarted-create-request"
                  then
                     raise Program_Error with
                       "composed CreateBucket restart mismatch";
                  end if;
               end;
            end;

            declare
               Stop : aliased Flyology.Cancellation.Token;
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Buckets.Create_Outcome :=
                       Buckets.Create
                         (HTTP, Origin, "cancelled-create", Identity,
                          Region => "us-west-2", Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               begin
                  declare
                     Ignored : constant Buckets.Create_Outcome :=
                       Buckets.Create
                         (HTTP, Origin, "timed-out-create", Identity,
                          Region => "us-west-2", Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Cancelled or else not Timed_Out then
                  raise Program_Error with
                    "high-level CreateBucket ignored cancellation/deadline";
               end if;
            end;

            declare
               Parameters : constant Low_Level.Delete_Bucket_Parameters :=
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012"));
               Result     : constant Delete_Bucket_Result :=
                 Buckets.Delete
                   (HTTP,
                    Origin,
                    "typed-deleted",
                    Parameters,
                    Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Bucket_Response_Available
                 or else Result.Disposition /= Bucket_Deletion_Completed
                 or else Result.Failure /= No_Failure
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.Response.Kind /= Low_Level.Bucket_Deleted
               then
                  raise Program_Error
                    with "typed DeleteBucket response mismatch";
               end if;
            end;

            declare
               Parameters : constant Low_Level.Delete_Bucket_Parameters :=
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012"));
               --  DeleteBucket parent, HTTP exchange, and transport child.
               Set        : aliased Operations.Completion_Set (3);
               Result     : Delete_Bucket_Result;
            begin
               declare
                  Operation : Delete_Bucket_Operation :=
                    Buckets.Delete
                      (Set'Access,
                       HTTP'Access,
                       Origin,
                       "composed-deleted",
                       Parameters,
                       Identity,
                       HTTP_Client.Deadline_After (5.0));
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Disposition /= Bucket_Deletion_Completed then
                     raise Program_Error
                       with "composed DeleteBucket first result mismatch";
                  end if;
                  Buckets.Delete
                    (HTTP'Access,
                     Origin,
                     "restart-nonempty",
                     Parameters,
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     Operation => Operation);
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /= Delete_Bucket_Response_Available
                    or else Result.Disposition /= Bucket_Definitely_Not_Deleted
                    or else Result.Failure /= Invalid_Request
                    or else Result.Response.Kind
                            /= Low_Level.Delete_Bucket_Rejected
                    or else US.To_String (Result.Response.Error.Request_ID)
                            /= "restarted-delete-request"
                  then
                     raise Program_Error
                       with "composed DeleteBucket restart mismatch";
                  end if;
               end;
            end;

            declare
               Parameters : constant
                 Low_Level.Get_Bucket_Location_Parameters :=
                   (Expected_Bucket_Owner =>
                      US.To_Unbounded_String ("123456789012"));
               Result : constant Get_Bucket_Location_Result :=
                 Buckets.Get_Location
                   (HTTP,
                    Origin,
                    "typed-location",
                    Parameters,
                    Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /=
                    Get_Bucket_Location_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.Response.Kind /=
                   Low_Level.Bucket_Location_Found
                 or else US.To_String
                   (Result.Response.Result.Location_Constraint) /=
                     "us-west-2"
               then
                  raise Program_Error
                    with "typed GetBucketLocation response mismatch";
               end if;
            end;

            declare
               Parameters : constant
                 Low_Level.Get_Bucket_Location_Parameters :=
                   (Expected_Bucket_Owner =>
                      US.To_Unbounded_String ("123456789012"));
               --  Location parent, HTTP exchange, and transport child.
               Set : aliased Operations.Completion_Set (3);
               Result : Get_Bucket_Location_Result;
            begin
               declare
                  Operation : Get_Bucket_Location_Operation :=
                    Get_Location
                      (Set'Access,
                       HTTP'Access,
                       Origin,
                       "composed-location",
                       Parameters,
                       Identity,
                       HTTP_Client.Deadline_After (5.0));
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /=
                       Get_Bucket_Location_Response_Available
                    or else Result.Failure /= No_Failure
                    or else Result.Response.Kind /=
                      Low_Level.Bucket_Location_Found
                    or else US.Length
                      (Result.Response.Result.Location_Constraint) /= 0
                  then
                     raise Program_Error with
                       "composed GetBucketLocation first result mismatch";
                  end if;
                  Get_Location
                    (HTTP'Access,
                     Origin,
                     "restart-location",
                     Parameters,
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     Operation => Operation);
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /=
                       Get_Bucket_Location_Response_Available
                    or else Result.Failure /= Authorization_Failed
                    or else Result.Response.Kind /=
                      Low_Level.Get_Bucket_Location_Rejected
                    or else US.To_String (Result.Response.Error.Request_ID) /=
                      "restarted-location-request"
                  then
                     raise Program_Error with
                       "composed GetBucketLocation restart mismatch";
                  end if;
               end;
            end;

            declare
               Parameters : constant Low_Level.Head_Bucket_Parameters :=
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012"));
               Result : constant Head_Bucket_Result :=
                 Buckets.Head
                   (HTTP, Origin, "example-bucket", Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= Head_Bucket_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.Response.Kind /= Low_Level.Bucket_Found
                 or else US.To_String
                   (Result.Response.Result.Bucket_ARN) /=
                     "arn:aws:s3:::example-bucket"
                 or else US.To_String
                   (Result.Response.Result.Bucket_Region) /= "us-east-1"
                 or else not Result.Response.Result.Access_Point_Alias.Is_Set
                 or else Result.Response.Result.Access_Point_Alias.Value
               then
                  raise Program_Error with
                    "composable HeadBucket response mismatch";
               end if;
            end;

            declare
               Result : constant Buckets.Head_Outcome :=
                 Buckets.Head
                   (HTTP, Origin, "missing-bucket", Identity,
                    Expected_Bucket_Owner => "123456789012",
                    Timeout => 5.0);
            begin
               if Result.Kind /= Buckets.Head_Rejected
                 or else Result.Status /= 404
                 or else US.To_String (Result.Error.Request_ID) /=
                   "head-bucket-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "head-bucket-host"
               then
                  raise Program_Error with
                    "synchronous HeadBucket rejection mismatch";
               end if;
            end;

            declare
               Parameters : constant Low_Level.Head_Bucket_Parameters :=
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012"));
               Result : constant Head_Bucket_Result :=
                 Buckets.Head
                   (HTTP, Origin, "duplicate-bucket", Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= Head_Bucket_Exchange_Failed
                 or else Result.Failure /=
                   Corrupt_Or_Invalid_Response
               then
                  raise Program_Error with
                    "HeadBucket accepted duplicate singleton metadata";
               end if;
            end;

            declare
               Parameters : constant Low_Level.Head_Bucket_Parameters :=
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012"));
               --  HeadBucket parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Head_Bucket_Operation :=
                 Head
                   (Set'Access, HTTP'Access, Origin, "restart-bucket",
                    Parameters, Identity, HTTP_Client.Deadline_After (5.0));
               Result : Head_Bucket_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Head_Bucket_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Bucket_Found
               then
                  raise Program_Error with
                    "composed HeadBucket first result mismatch";
               end if;
               Head
                 (HTTP'Access,
                  Origin,
                  "restarted-bucket",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Head_Bucket_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Head_Bucket_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-head-bucket-request"
               then
                  raise Program_Error with
                    "composed HeadBucket restart mismatch";
               end if;
            end;

            declare
               Stop : aliased Flyology.Cancellation.Token;
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Buckets.Head_Outcome :=
                       Buckets.Head
                         (HTTP, Origin, "cancelled-bucket", Identity,
                          Timeout => 5.0, Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               begin
                  declare
                     Ignored : constant Buckets.Head_Outcome :=
                       Buckets.Head
                         (HTTP, Origin, "timed-out-bucket", Identity,
                          Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Cancelled or else not Timed_Out then
                  raise Program_Error with
                    "high-level HeadBucket ignored cancellation/deadline";
               end if;
            end;

            declare
               Parameters : Low_Level.Delete_Object_Parameters :=
                 (others => <>);
            begin
               Parameters.Version_ID :=
                 US.To_Unbounded_String ("scoped-delete-version");
               Parameters.If_Match := US.To_Unbounded_String
                 ("""scoped-delete-generation""");
               Parameters.Request_Payer :=
                 US.To_Unbounded_String ("requester");
               declare
                  --  Object, HTTP exchange, and its single transport child.
                  Set : aliased Operations.Completion_Set (3);
                  Operation : Delete_Operation := Delete
                    (Set'Access, HTTP'Access, Origin, "example-bucket",
                     "scoped-delete", Parameters, Identity,
                     HTTP_Client.Deadline_After (5.0));
                  Result : Delete_Result;
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /= Delete_Response_Available
                    or else Result.Disposition /= Deletion_Completed
                    or else Result.Failure /= No_Failure
                    or else Result.Admission /= HTTP_Client.Response_Observed
                    or else Result.Response.Kind /= Low_Level.Object_Deleted
                    or else not Result.Response.Result.Delete_Marker.Is_Set
                    or else not Result.Response.Result.Delete_Marker.Value
                    or else US.To_String
                      (Result.Response.Result.Version_ID) /=
                        "scoped-deleted-version"
                    or else US.To_String
                      (Result.Response.Result.Request_Charged) /= "requester"
                  then
                     raise Program_Error with
                       "scoped DeleteObject success/certainty mismatch";
                  end if;
               end;
            end;

            declare
               Result : constant Delete_Result := Objects.Delete
                 (HTTP, Origin, "example-bucket", "scoped-delete-stale",
                  Identity, If_Match => """stale-delete-generation""",
                  Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Response_Available
                 or else Result.Disposition /= Definitely_Not_Deleted
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Delete_Object_Rejected
                 or else Result.Response.Status /= 412
               then
                  raise Program_Error with
                    "synchronous scoped DeleteObject precondition mismatch";
               end if;
            end;

            declare
               Result : constant Delete_Result := Objects.Delete
                 (HTTP, Origin, "example-bucket", "scoped-delete-conflict",
                  Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Response_Available
                 or else Result.Disposition /=
                   Deletion_Outcome_Unknown
                 or else Result.Failure /= Unavailable_Or_Retryable
                 or else Result.Response.Kind /=
                   Low_Level.Delete_Object_Rejected
                 or else Result.Response.Status /= 409
               then
                  raise Program_Error with
                    "scoped DeleteObject conflict certainty mismatch";
               end if;
            end;

            declare
               Result : constant Delete_Result := Objects.Delete
                 (HTTP, Origin, "example-bucket", "scoped-delete-duplicate",
                  Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Exchange_Failed
                 or else Result.Disposition /=
                   Deletion_Outcome_Unknown
                 or else Result.Failure /=
                   Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
               then
                  raise Program_Error with
                    "scoped DeleteObject accepted duplicate output metadata";
               end if;
            end;

            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Result : constant Delete_Result := Objects.Delete
                    (HTTP, Origin, "example-bucket",
                     "scoped-delete-cancelled", Identity, Timeout => 5.0,
                     Token => Stop'Access);
               begin
                  if Result.Kind /= Delete_Exchange_Failed
                    or else Result.Disposition /=
                      Deletion_Cancelled_Before_Admission
                    or else Result.Failure /= Client_API.Cancelled
                    or else Result.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission DeleteObject cancellation mismatch";
                  end if;
               end;
            end;

            declare
               Result : constant Delete_Result := Objects.Delete
                 (HTTP, Origin, "example-bucket", "scoped-delete-timeout",
                  Identity, Timeout => 0.0);
            begin
               if Result.Kind /= Delete_Exchange_Failed
                 or else Result.Disposition /= Definitely_Not_Deleted
                 or else Result.Failure /= Timed_Out
                 or else Result.Admission /= HTTP_Client.Not_Admitted
               then
                  raise Program_Error with
                    "pre-admission DeleteObject deadline mismatch";
               end if;
            end;

            declare
               procedure Must_Reject_Range
                 (Requested : Flyology.Object_Storage.Byte_Range;
                  Entity_Tag : String;
                  Message : String)
               is
                  Raised : Boolean := False;
               begin
                  begin
                     declare
                        Ignored : constant Range_Get_Result :=
                          Objects.Get_Range
                            (HTTP, Origin, "example-bucket",
                             "scoped-range-invalid", Requested, Destination,
                             Identity, Entity_Tag, Timeout => 5.0);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Low_Level.Invalid_Request =>
                        Raised := True;
                  end;
                  if not Raised
                    or else not Buffers.Has_Buffer (Destination)
                    or else Buffers.Length (Destination) /= 0
                  then
                     raise Program_Error with Message;
                  end if;
               end Must_Reject_Range;
            begin
               Must_Reject_Range
                 (Flyology.Object_Storage.Whole_Object,
                  """range-generation""",
                  "Get_Range admitted a whole-object request");
               Must_Reject_Range
                 ((Kind  => Flyology.Object_Storage.Suffix_Range,
                   First => 0, Last => 0, Count => 0),
                  """range-generation""",
                  "Get_Range admitted an empty suffix");
               Must_Reject_Range
                 ((Kind  => Flyology.Object_Storage.Bounded_Range,
                   First => 2, Last => 5, Count => 0),
                  "weak-generation",
                  "Get_Range admitted a non-strong generation validator");
            end;

            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Result : constant Range_Get_Result :=
                    Objects.Get_Range
                      (HTTP, Origin, "example-bucket",
                       "scoped-range-cancelled",
                       (Kind  => Flyology.Object_Storage.Bounded_Range,
                        First => 2, Last => 5, Count => 0),
                       Destination, Identity, """range-generation""",
                       Timeout => 5.0, Token => Stop'Access);
               begin
                  if Result.Kind /= Range_Get_Exchange_Failed
                    or else Result.Failure /= Client_API.Cancelled
                    or else not Buffers.Has_Buffer (Destination)
                    or else Buffers.Length (Destination) /= 0
                  then
                     raise Program_Error with
                       "pre-admission range cancellation mapping mismatch";
                  end if;
               end;
            end;

            declare
               Result : constant Range_Get_Result :=
                 Objects.Get_Range
                   (HTTP, Origin, "example-bucket", "scoped-range-timeout",
                    (Kind  => Flyology.Object_Storage.Bounded_Range,
                     First => 2, Last => 5, Count => 0),
                    Destination, Identity, """range-generation""",
                    Timeout => 0.0);
            begin
               if Result.Kind /= Range_Get_Exchange_Failed
                 or else Result.Failure /= Timed_Out
                 or else not Buffers.Has_Buffer (Destination)
                 or else Buffers.Length (Destination) /= 0
               then
                  raise Program_Error with
                    "pre-admission range deadline mapping mismatch";
               end if;
            end;

            declare
               Stop : aliased Flyology.Cancellation.Token;
               Parameters : constant Low_Level.Head_Object_Parameters :=
                 (others => <>);
            begin
               Stop.Request;
               declare
                  Result : constant Head_Result := Objects.Head_Object
                    (HTTP, Origin, "example-bucket", "scoped-head-cancelled",
                     Parameters, Identity, Timeout => 5.0,
                     Token => Stop'Access);
               begin
                  if Result.Kind /= Head_Exchange_Failed
                    or else Result.Failure /= Client_API.Cancelled
                  then
                     raise Program_Error with
                       "pre-admission HeadObject cancellation mismatch";
                  end if;
               end;
            end;

            declare
               Parameters : constant Low_Level.Head_Object_Parameters :=
                 (others => <>);
               Result : constant Head_Result := Objects.Head_Object
                 (HTTP, Origin, "example-bucket", "scoped-head-timeout",
                  Parameters, Identity, Timeout => 0.0);
            begin
               if Result.Kind /= Head_Exchange_Failed
                 or else Result.Failure /= Timed_Out
               then
                  raise Program_Error with
                    "pre-admission HeadObject deadline mismatch";
               end if;
            end;
         end;
         declare
            Bucket_Parameters : constant Low_Level.List_Buckets_Parameters :=
              (Max_Buckets            => 1,
               Has_Max_Buckets        => True,
               Continuation_Token     => US.Null_Unbounded_String,
               Has_Continuation_Token => False,
               Prefix                 => US.To_Unbounded_String ("socket-"),
               Has_Prefix             => True,
               Bucket_Region          =>
                 US.To_Unbounded_String ("us-east-1"));
            Bucket_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Buckets
                (Origin, Low_Level.Path_Style, Bucket_Parameters, Identity,
                 "us-east-1", "20130524T000000Z");
         begin
            declare
               Result : constant Low_Level.List_Buckets_Outcome :=
                 Low_Level.Execute_List_Buckets
                   (HTTP, Bucket_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Buckets_Listed
                 or else not Result.Result.Has_Owner
                 or else US.To_String (Result.Result.Owner.ID) /=
                   "socket-owner"
                 or else Natural (Result.Result.Buckets.Length) /= 1
                 or else US.To_String
                   (Result.Result.Buckets.First_Element.Name) /=
                     "socket-bucket"
                 or else US.To_String
                   (Result.Result.Buckets.First_Element.Creation_Date) /=
                     "2026-08-22T01:02:03.000Z"
                 or else US.To_String
                   (Result.Result.Buckets.First_Element.Bucket_Region) /=
                     "us-east-1"
                 or else US.To_String
                   (Result.Result.Continuation_Token) /= "socket-next"
                 or else US.To_String (Result.Result.Prefix) /= "socket-"
               then
                  raise Program_Error with
                    "typed ListBuckets socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.List_Buckets_Outcome :=
                 Low_Level.Execute_List_Buckets
                   (HTTP, Bucket_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.List_Buckets_Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "list-buckets-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "list-buckets-host"
               then
                  raise Program_Error with
                    "typed ListBuckets socket error mismatch";
               end if;
            end;
            declare
               Result : constant List_Buckets_Result :=
                 Buckets.List_Page
                   (HTTP, Origin, Bucket_Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= List_Buckets_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Buckets_Listed
                 or else Natural (Result.Response.Result.Buckets.Length) /= 1
                 or else US.To_String
                   (Result.Response.Result.Buckets.First_Element.Name) /=
                     "socket-bucket"
               then
                  raise Program_Error with
                    "composable ListBuckets socket success mismatch";
               end if;
            end;
            declare
               Result : constant List_Buckets_Result :=
                 Buckets.List_Page
                   (HTTP, Origin, Bucket_Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= List_Buckets_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.List_Buckets_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "scoped-list-buckets-request"
                 or else US.To_String (Result.Response.Error.Host_ID) /=
                   "scoped-list-buckets-host"
               then
                  raise Program_Error with
                    "composable ListBuckets socket error mismatch";
               end if;
            end;
            declare
               procedure Require_Invalid_List_Buckets (Message : String) is
                  Result : constant List_Buckets_Result :=
                    Buckets.List_Page
                      (HTTP, Origin, Bucket_Parameters, Identity,
                       Timeout => 5.0);
               begin
                  if Result.Kind /= List_Buckets_Exchange_Failed
                    or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                    or else Result.Admission /= HTTP_Client.Response_Observed
                  then
                     raise Program_Error with Message;
                  end if;
               end Require_Invalid_List_Buckets;
            begin
               Require_Invalid_List_Buckets
                 ("ListBuckets accepted a wrong echoed prefix");
               Require_Invalid_List_Buckets
                 ("ListBuckets accepted a duplicate singleton header");
               Require_Invalid_List_Buckets
                 ("ListBuckets accepted more than the prepared maximum");
               Require_Invalid_List_Buckets
                 ("ListBuckets accepted a bucket outside the prepared " &
                  "prefix");
               Require_Invalid_List_Buckets
                 ("ListBuckets accepted returned metadata outside the " &
                  "prepared region");
            end;
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Result : constant List_Buckets_Result :=
                    Buckets.List_Page
                      (HTTP, Origin, Bucket_Parameters, Identity,
                       Timeout => 5.0, Token => Stop'Access);
               begin
                  if Result.Kind /= List_Buckets_Exchange_Failed
                    or else Result.Failure /= Client_API.Cancelled
                    or else Result.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission ListBuckets cancellation mismatch";
                  end if;
               end;
            end;
            declare
               Stop      : aliased Flyology.Cancellation.Token;
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Buckets.List_Outcome :=
                       Buckets.List_Page
                         (HTTP, Origin, Identity, Maximum => 1,
                          Prefix => "socket-",
                          Bucket_Region => "us-east-1", Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               begin
                  declare
                     Ignored : constant Buckets.List_Outcome :=
                       Buckets.List_Page
                         (HTTP, Origin, Identity, Maximum => 1,
                          Prefix => "socket-",
                          Bucket_Region => "us-east-1", Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Cancelled or else not Timed_Out then
                  raise Program_Error with
                    "high-level ListBuckets ignored cancellation/deadline";
               end if;
            end;
            declare
               Page_Parameters : Low_Level.List_Buckets_Parameters :=
                 Bucket_Parameters;
               --  Listing parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : List_Buckets_Operation :=
                 List_Page
                   (Set'Access, HTTP'Access, Origin, Page_Parameters,
                    Identity, HTTP_Client.Deadline_After (5.0));
               Result : List_Buckets_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Buckets_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Buckets_Listed
                 or else not Result.Response.Result.Has_Continuation_Token
               then
                  raise Program_Error with
                    "composed ListBuckets first page mismatch";
               end if;
               Page_Parameters.Continuation_Token :=
                 Result.Response.Result.Continuation_Token;
               Page_Parameters.Has_Continuation_Token := True;
               List_Page
                 (HTTP'Access,
                  Origin,
                  Page_Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Buckets_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Buckets_Listed
                 or else Natural (Result.Response.Result.Buckets.Length) /= 1
                 or else US.To_String
                   (Result.Response.Result.Buckets.First_Element.Name) /=
                     "socket-second"
                 or else Result.Response.Result.Has_Continuation_Token
               then
                  raise Program_Error with
                    "composed ListBuckets restart mismatch";
               end if;
            end;
         end;
         declare
            V1_Parameters : Low_Level.List_Objects_Parameters;
         begin
            V1_Parameters.Prefix := US.To_Unbounded_String ("socket/");
            V1_Parameters.Delimiter := US.To_Unbounded_String ("/");
            V1_Parameters.Marker := US.To_Unbounded_String ("before");
            V1_Parameters.Max_Keys := 2;
            V1_Parameters.URL_Encoding := True;
            V1_Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            V1_Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            V1_Parameters.Include_Restore_Status := True;
            declare
               V1_Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    V1_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Objects_Outcome :=
                 Low_Level.Execute_List_Objects
                   (HTTP, V1_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Listed
                 or else US.To_String (Result.Result.Listing.Prefix) /=
                   "socket/"
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "typed ListObjects socket success mismatch";
               end if;
            end;
            declare
               V1_Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    V1_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Objects_Outcome :=
                 Low_Level.Execute_List_Objects
                   (HTTP, V1_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Rejected
                 or else US.To_String (Result.Error.Request_ID) /=
                   "v1-socket-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "v1-socket-host"
               then
                  raise Program_Error with
                    "typed ListObjects socket error mismatch";
               end if;
            end;
            declare
               Result : constant List_Objects_Result :=
                 Objects.List_V1_Page
                   (HTTP, Origin, "example-bucket", V1_Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= List_Objects_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Listed
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "composable ListObjects socket success mismatch";
               end if;
            end;
            declare
               Result : constant List_Objects_Result :=
                 Objects.List_V1_Page
                   (HTTP, Origin, "example-bucket", V1_Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= List_Objects_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /= Low_Level.Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "v1-scoped-request"
                 or else US.To_String (Result.Response.Error.Host_ID) /=
                   "v1-scoped-host"
               then
                  raise Program_Error with
                    "composable ListObjects socket error mismatch";
               end if;
            end;
            declare
               procedure Require_Invalid_List_Objects
                 (Parameters : Low_Level.List_Objects_Parameters;
                  Message    : String)
               is
                  --  Listing parent, HTTP exchange, and one transport child.
                  Set : aliased Operations.Completion_Set (3);
                  Operation : List_Objects_Operation :=
                    List_V1_Page
                      (Set'Access, HTTP'Access, Origin, "example-bucket",
                       Parameters, Identity,
                       HTTP_Client.Deadline_After (5.0));
                  Result : List_Objects_Result;
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /= List_Objects_Exchange_Failed
                    or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                    or else Result.Admission /= HTTP_Client.Response_Observed
                  then
                     raise Program_Error with Message;
                  end if;
               end Require_Invalid_List_Objects;
            begin
               Require_Invalid_List_Objects
                 (V1_Parameters,
                  "ListObjects accepted a wrong echoed bucket");
               Require_Invalid_List_Objects
                 (V1_Parameters,
                  "ListObjects accepted a duplicate singleton header");
               declare
                  No_Payer : Low_Level.List_Objects_Parameters :=
                    V1_Parameters;
               begin
                  No_Payer.Request_Payer := US.Null_Unbounded_String;
                  Require_Invalid_List_Objects
                    (No_Payer,
                     "ListObjects accepted an unrequested payer charge");
               end;
            end;
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Result : constant List_Objects_Result :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", V1_Parameters,
                       Identity, Timeout => 5.0, Token => Stop'Access);
               begin
                  if Result.Kind /= List_Objects_Exchange_Failed
                    or else Result.Failure /= Client_API.Cancelled
                    or else Result.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission ListObjects cancellation mismatch";
                  end if;
               end;
            end;
            declare
               Special_Key : constant String :=
                 "socket-v1/a /%" & Character'Val (16#C3#) &
                 Character'Val (16#A9#);
               Page_Parameters : Low_Level.List_Objects_Parameters :=
                 (Prefix       => US.To_Unbounded_String ("socket-v1/"),
                  Has_Prefix   => True,
                  Max_Keys     => 1,
                  Has_Max_Keys => True,
                  URL_Encoding => True,
                  others       => <>);
               --  Listing parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : List_Objects_Operation :=
                 List_V1_Page
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Page_Parameters, Identity,
                    HTTP_Client.Deadline_After (5.0));
               Result : List_Objects_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Objects_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Listed
                 or else not Result.Response.Result.Listing.Is_Truncated
                 or else Natural
                   (Result.Response.Result.Listing.Contents.Length) /= 1
               then
                  raise Program_Error with
                    "composed ListObjects first page mismatch";
               end if;
               Page_Parameters.Marker :=
                 US.To_Unbounded_String (Special_Key);
               Page_Parameters.Has_Marker := True;
               List_V1_Page
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  Page_Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Objects_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Listed
                 or else Result.Response.Result.Listing.Is_Truncated
                 or else Natural
                   (Result.Response.Result.Listing.Contents.Length) /= 1
                 or else US.To_String
                   (Result.Response.Result.Listing.Contents.First_Element.Key)
                     /= "socket-v1/b"
               then
                  raise Program_Error with
                    "composed ListObjects restart mismatch";
               end if;
            end;
         end;
         declare
            Stop      : aliased Flyology.Cancellation.Token;
            Cancelled : Boolean := False;
            Timed_Out : Boolean := False;
         begin
            Stop.Request;
            begin
               declare
                  Ignored : constant Objects.List_V1_Outcome :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-v1/", Maximum => 1,
                       Timeout => 5.0, Token => Stop'Access);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Cancelled := True;
            end;
            begin
               declare
                  Ignored : constant Objects.List_V1_Outcome :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-v1/", Maximum => 1,
                       Timeout => 0.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.IO.Timeout_Error =>
                  Timed_Out := True;
            end;
            if not Cancelled or else not Timed_Out then
               raise Program_Error with
                 "high-level ListObjects v1 ignored cancellation/deadline";
            end if;
         end;
         declare
            Special_Key : constant String :=
              "socket-v1/a /%" & Character'Val (16#C3#) &
              Character'Val (16#A9#);
            First : constant Objects.List_V1_Outcome :=
              Objects.List_V1_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "socket-v1/", Maximum => 1,
                 URL_Encoding => True, Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else Natural (First.Page.Contents.Length) /= 1
              or else not First.Page.Is_Truncated
              or else First.Page.Has_Next_Marker
              or else not First.Has_Next_Marker
              or else US.To_String (First.Next_Marker) /= Special_Key
            then
               raise Program_Error with
                 "high-level ListObjects v1 lost derived marker";
            end if;
            declare
               Next : constant Objects.List_V1_Outcome :=
                 Objects.List_V1_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "socket-v1/", Maximum => 1,
                    Marker => US.To_String (First.Next_Marker),
                    URL_Encoding => True,
                    Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Natural (Next.Page.Contents.Length) /= 1
                 or else US.To_String
                   (Next.Page.Contents.First_Element.Key) /= "socket-v1/b"
                 or else Next.Page.Is_Truncated
                 or else Next.Has_Next_Marker
               then
                  raise Program_Error with
                    "high-level ListObjects v1 continuation mismatch";
               end if;
            end;
         end;
         declare
            Delimiter_Marker : constant String :=
              "socket-v1/group %/" & Character'Val (16#C3#) &
              Character'Val (16#A9#);
            First : constant Objects.List_V1_Outcome :=
              Objects.List_V1_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "socket-v1/", Delimiter => "/", Maximum => 1,
                 URL_Encoding => True, Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else Natural (First.Page.Common_Prefixes.Length) /= 1
              or else not First.Page.Has_Next_Marker
              or else not First.Has_Next_Marker
              or else US.To_String (First.Next_Marker) /= Delimiter_Marker
            then
               raise Program_Error with
                 "high-level ListObjects v1 lost decoded NextMarker";
            end if;
            declare
               Next : constant Objects.List_V1_Outcome :=
                 Objects.List_V1_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "socket-v1/", Delimiter => "/", Maximum => 1,
                    Marker => US.To_String (First.Next_Marker),
                    URL_Encoding => True, Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Next.Page.Is_Truncated
                 or else Next.Has_Next_Marker
               then
                  raise Program_Error with
                    "high-level ListObjects v1 delimiter " &
                    "continuation mismatch";
               end if;
            end;
         end;
         declare
            Rejected : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Objects.List_V1_Outcome :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-v1/", Maximum => 1,
                       URL_Encoding => True, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "high-level ListObjects v1 accepted malformed URL marker";
            end if;
         end;
         declare
            Result : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Listed
              or else Result.Listing.Key_Count /= 0
              or else US.To_String (Result.Request_Charged) /= "requester"
            then
               raise Program_Error with "socket success result mismatch";
            end if;
         end;
         declare
            Result : constant List_Objects_V2_Result :=
              Objects.List_Page
                (HTTP, Origin, "example-bucket", Parameters, Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= List_Objects_V2_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /= Low_Level.Listed
              or else Result.Response.Listing.Key_Count /= 0
              or else US.To_String (Result.Response.Request_Charged) /=
                "requester"
            then
               raise Program_Error with
                 "typed ListObjectsV2 socket success mismatch";
            end if;
         end;
         declare
            procedure Require_Invalid_List_Objects_V2
              (Message : String) is
               --  Listing parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : List_Objects_V2_Operation :=
                 List_Page
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Parameters, Identity, HTTP_Client.Deadline_After (5.0));
               Result : List_Objects_V2_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Objects_V2_Exchange_Failed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                 or else Result.Admission /= HTTP_Client.Response_Observed
               then
                  raise Program_Error with Message;
               end if;
            end Require_Invalid_List_Objects_V2;
         begin
            Require_Invalid_List_Objects_V2
              ("ListObjectsV2 accepted a wrong echoed bucket");
            Require_Invalid_List_Objects_V2
              ("ListObjectsV2 accepted a duplicate singleton header");
         end;
         declare
            Stop : aliased Flyology.Cancellation.Token;
         begin
            Stop.Request;
            declare
               Result : constant List_Objects_V2_Result :=
                 Objects.List_Page
                   (HTTP, Origin, "example-bucket", Parameters, Identity,
                    Timeout => 5.0, Token => Stop'Access);
            begin
               if Result.Kind /= List_Objects_V2_Exchange_Failed
                 or else Result.Failure /= Client_API.Cancelled
                 or else Result.Admission /= HTTP_Client.Not_Admitted
               then
                  raise Program_Error with
                    "pre-admission ListObjectsV2 cancellation mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Rejected
              or else US.To_String (Result.Error.Request_ID) /=
                "socket-request"
              or else US.To_String (Result.Error.Host_ID) /= "socket-host"
            then
               raise Program_Error with "socket error result mismatch";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.List_Objects_V2_Outcome :=
                    Low_Level.Execute_List_Objects_V2
                      (HTTP, Prepared, Timeout => 5.0,
                       Limits =>
                         (Maximum_Document_Bytes => 64,
                          Maximum_Depth          => 8,
                          Maximum_Elements       => 32,
                          Maximum_Text_Bytes     => 64));
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with "oversized socket response accepted";
            end if;
         end;
         declare
            Stop      : aliased Flyology.Cancellation.Token;
            Cancelled : Boolean := False;
            Timed_Out : Boolean := False;
         begin
            Stop.Request;
            begin
               declare
                  Ignored : constant Objects.List_Outcome :=
                    Objects.List_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-page/", Maximum => 1,
                       Timeout => 5.0, Token => Stop'Access);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Cancelled := True;
            end;
            begin
               declare
                  Ignored : constant Objects.List_Outcome :=
                    Objects.List_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-page/", Maximum => 1,
                       Timeout => 0.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.IO.Timeout_Error =>
                  Timed_Out := True;
            end;
            if not Cancelled or else not Timed_Out then
               raise Program_Error with
                 "high-level ListObjectsV2 ignored cancellation/deadline";
            end if;
         end;
         declare
            First : constant Objects.List_Outcome :=
              Objects.List_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "socket-page/", Maximum => 1, Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else Natural (First.Page.Contents.Length) /= 1
              or else not First.Page.Is_Truncated
              or else not First.Page.Has_Next_Continuation_Token
              or else US.To_String (First.Page.Next_Continuation_Token) /=
                "opaque-next"
            then
               raise Program_Error with
                 "high-level ListObjectsV2 lost truncated-page token";
            end if;
            declare
               Next : constant Objects.List_Outcome :=
                 Objects.List_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "socket-page/", Maximum => 1,
                    Continuation_Token => US.To_String
                      (First.Page.Next_Continuation_Token),
                    Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Natural (Next.Page.Contents.Length) /= 1
                 or else US.To_String
                   (Next.Page.Contents.First_Element.Key) /= "socket-page/b"
                 or else Next.Page.Is_Truncated
                 or else Next.Page.Has_Next_Continuation_Token
               then
                  raise Program_Error with
                    "high-level ListObjectsV2 continuation mismatch";
               end if;
            end;
         end;
         declare
            Page_Parameters : Low_Level.List_Objects_V2_Parameters :=
              (Prefix => US.To_Unbounded_String ("socket-page/"),
               Max_Keys => 1,
               others => <>);
            --  Listing parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
            Operation : List_Objects_V2_Operation :=
              List_Page
                (Set'Access, HTTP'Access, Origin, "example-bucket",
                 Page_Parameters, Identity,
                 HTTP_Client.Deadline_After (5.0));
            Result : List_Objects_V2_Result;
         begin
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= List_Objects_V2_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /= Low_Level.Listed
              or else not Result.Response.Listing.Is_Truncated
              or else Natural
                (Result.Response.Listing.Contents.Length) /= 1
              or else not
                Result.Response.Listing.Has_Next_Continuation_Token
            then
               raise Program_Error with
                 "composed ListObjectsV2 first page mismatch";
            end if;
            Page_Parameters.Continuation_Token :=
              Result.Response.Listing.Next_Continuation_Token;
            Page_Parameters.Has_Continuation_Token := True;
            List_Page
              (HTTP'Access,
               Origin,
               "example-bucket",
               Page_Parameters,
               Identity,
               HTTP_Client.Deadline_After (5.0),
               Operation => Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= List_Objects_V2_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /= Low_Level.Listed
              or else Result.Response.Listing.Is_Truncated
              or else Natural
                (Result.Response.Listing.Contents.Length) /= 1
              or else US.To_String
                (Result.Response.Listing.Contents.First_Element.Key) /=
                  "socket-page/b"
            then
               raise Program_Error with
                 "composed ListObjectsV2 continuation mismatch";
            end if;
         end;
         declare
            List_Parameters : Low_Level.List_Multipart_Uploads_Parameters;
         begin
            List_Parameters.Delimiter := US.To_Unbounded_String ("/");
            List_Parameters.Key_Marker :=
              US.To_Unbounded_String ("before");
            List_Parameters.Max_Uploads := 2;
            List_Parameters.Prefix := US.To_Unbounded_String ("socket/");
            List_Parameters.Upload_ID_Marker :=
              US.To_Unbounded_String ("upload-before");
            List_Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            List_Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            declare
               Result : constant List_Multipart_Uploads_Result :=
                 Transfers.List_Multipart_Uploads_Page
                   (HTTP, Origin, "example-bucket", List_Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Multipart_Uploads_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Multipart_Uploads_Listed
                 or else Natural
                   (Result.Response.Result.Listing.Uploads.Length) /= 1
                 or else US.To_String
                   (Result.Response.Result.Listing.Uploads.First_Element.
                      Upload_ID) /= "socket-upload"
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "typed ListMultipartUploads socket success mismatch";
               end if;
            end;
            declare
               Prepared_Uploads : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Multipart_Uploads
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    List_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Multipart_Uploads_Outcome :=
                 Low_Level.Execute_List_Multipart_Uploads
                   (HTTP, Prepared_Uploads, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.List_Multipart_Uploads_Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "list-uploads-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "list-uploads-host"
               then
                  raise Program_Error with
                    "typed ListMultipartUploads socket error mismatch";
               end if;
            end;
         end;
         declare
            Uploads_Parameters : Low_Level.List_Multipart_Uploads_Parameters;

            procedure Require_Invalid_Uploads (Message : String) is
               --  Listing parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : List_Multipart_Uploads_Operation :=
                 List_Multipart_Uploads_Page
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Uploads_Parameters, Identity,
                    HTTP_Client.Deadline_After (5.0));
               Result : List_Multipart_Uploads_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Multipart_Uploads_Exchange_Failed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                 or else Result.Admission /= HTTP_Client.Response_Observed
               then
                  raise Program_Error with Message;
               end if;
            end Require_Invalid_Uploads;
         begin
            Require_Invalid_Uploads
              ("ListMultipartUploads accepted a wrong echoed bucket");
            Require_Invalid_Uploads
              ("ListMultipartUploads accepted duplicate singleton header");
            Require_Invalid_Uploads
              ("ListMultipartUploads accepted present-empty header");
            Require_Invalid_Uploads
              ("ListMultipartUploads accepted charged response without " &
               "request payer");

            Uploads_Parameters.Delimiter := US.To_Unbounded_String ("/");
            Uploads_Parameters.URL_Encoding := True;
            Uploads_Parameters.Key_Marker := US.To_Unbounded_String ("a+b");
            Uploads_Parameters.Max_Uploads := 7;
            Uploads_Parameters.Prefix :=
              US.To_Unbounded_String ("photos/Jan &");
            Uploads_Parameters.Upload_ID_Marker :=
              US.To_Unbounded_String ("upload+/=");
            Uploads_Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Uploads_Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            for Echo_Index in 1 .. 7 loop
               Require_Invalid_Uploads
                 ((case Echo_Index is
                     when 1 => "wrong ListMultipartUploads bucket accepted",
                     when 2 =>
                       "wrong ListMultipartUploads key marker accepted",
                     when 3 =>
                       "wrong ListMultipartUploads upload marker accepted",
                     when 4 => "wrong ListMultipartUploads prefix accepted",
                     when 5 =>
                       "wrong ListMultipartUploads delimiter accepted",
                     when 6 => "wrong ListMultipartUploads maximum accepted",
                     when others =>
                       "wrong ListMultipartUploads encoding accepted"));
            end loop;
         end;
         declare
            Uploads_Parameters : Low_Level.List_Multipart_Uploads_Parameters :=
              (Max_Uploads => 1,
               Prefix => US.To_Unbounded_String ("paged/"),
               others => <>);
            --  Listing parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
            Operation : List_Multipart_Uploads_Operation :=
              List_Multipart_Uploads_Page
                (Set'Access, HTTP'Access, Origin, "example-bucket",
                 Uploads_Parameters, Identity,
                 HTTP_Client.Deadline_After (5.0));
            Result : List_Multipart_Uploads_Result;
         begin
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Cancelled : constant
                    List_Multipart_Uploads_Result :=
                      Transfers.List_Multipart_Uploads_Page
                        (HTTP, Origin, "example-bucket", Uploads_Parameters,
                         Identity, Timeout => 5.0, Token => Stop'Access);
               begin
                  if Cancelled.Kind /=
                    List_Multipart_Uploads_Exchange_Failed
                    or else Cancelled.Failure /= Client_API.Cancelled
                    or else Cancelled.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission ListMultipartUploads cancellation " &
                       "mismatch";
                  end if;
               end;
            end;
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= Multipart_Uploads_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /=
                Low_Level.Multipart_Uploads_Listed
              or else not Result.Response.Result.Listing.Is_Truncated
              or else Natural
                (Result.Response.Result.Listing.Uploads.Length) /= 1
              or else US.Length
                (Result.Response.Result.Listing.Next_Key_Marker) = 0
              or else US.Length
                (Result.Response.Result.Listing.Next_Upload_ID_Marker) = 0
            then
               raise Program_Error with
                 "composed ListMultipartUploads first page mismatch";
            end if;
            Uploads_Parameters.Key_Marker :=
              Result.Response.Result.Listing.Next_Key_Marker;
            Uploads_Parameters.Upload_ID_Marker :=
              Result.Response.Result.Listing.Next_Upload_ID_Marker;
            List_Multipart_Uploads_Page
              (HTTP'Access,
               Origin,
               "example-bucket",
               Uploads_Parameters,
               Identity,
               HTTP_Client.Deadline_After (5.0),
               Operation => Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= Multipart_Uploads_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /=
                Low_Level.Multipart_Uploads_Listed
              or else Result.Response.Result.Listing.Is_Truncated
              or else Natural
                (Result.Response.Result.Listing.Uploads.Length) /= 1
              or else US.To_String
                (Result.Response.Result.Listing.Uploads.First_Element.
                   Upload_ID) /= "id-2"
            then
               raise Program_Error with
                 "composed ListMultipartUploads continuation mismatch";
            end if;
         end;
         declare
            Parts_Parameters : Low_Level.List_Parts_Parameters :=
              (Max_Parts => 1,
               Upload_ID => US.To_Unbounded_String ("paged-upload"),
               others => <>);
            --  ListParts parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
            Operation : List_Parts_Operation :=
              List_Parts_Page
                (Set'Access, HTTP'Access, Origin, "example-bucket",
                 "paged-parts", Parts_Parameters, Identity,
                 HTTP_Client.Deadline_After (5.0));
            Result : List_Parts_Result;
         begin
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Cancelled : constant List_Parts_Result :=
                    Transfers.List_Parts_Page
                      (HTTP, Origin, "example-bucket", "paged-parts",
                       Parts_Parameters, Identity, Timeout => 5.0,
                       Token => Stop'Access);
               begin
                  if Cancelled.Kind /= List_Parts_Exchange_Failed
                    or else Cancelled.Failure /= Client_API.Cancelled
                    or else Cancelled.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission ListParts cancellation mismatch";
                  end if;
               end;
            end;
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= List_Parts_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /= Low_Level.Parts_Listed
              or else not Result.Response.Result.Listing.Is_Truncated
              or else Natural
                (Result.Response.Result.Listing.Parts.Length) /= 1
              or else
                Result.Response.Result.Listing.Next_Part_Number_Marker /= 1
            then
               raise Program_Error with
                 "composed ListParts first page mismatch";
            end if;
            Parts_Parameters.Part_Number_Marker :=
              Result.Response.Result.Listing.Next_Part_Number_Marker;
            List_Parts_Page
              (HTTP'Access,
               Origin,
               "example-bucket",
               "paged-parts",
               Parts_Parameters,
               Identity,
               HTTP_Client.Deadline_After (5.0),
               Operation => Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= List_Parts_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Response.Kind /= Low_Level.Parts_Listed
              or else Result.Response.Result.Listing.Is_Truncated
              or else Natural
                (Result.Response.Result.Listing.Parts.Length) /= 1
              or else
                Result.Response.Result.Listing.Parts.First_Element.Number /= 2
            then
               raise Program_Error with
                 "composed ListParts continuation mismatch";
            end if;
            Parts_Parameters.Part_Number_Marker := 0;
            for Case_Index in 1 .. 4 loop
               List_Parts_Page
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "paged-parts",
                  Parts_Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Parts_Exchange_Failed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                 or else Result.Admission /= HTTP_Client.Response_Observed
               then
                  raise Program_Error with
                    (case Case_Index is
                        when 1 => "ListParts accepted a wrong echoed key",
                        when 2 =>
                          "ListParts accepted duplicate singleton header",
                        when 3 =>
                          "ListParts accepted present-empty header",
                        when others =>
                          "ListParts accepted charged response without " &
                          "request payer");
               end if;
            end loop;
            for Echo_Index in 1 .. 4 loop
               List_Parts_Page
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "paged-parts",
                  Parts_Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= List_Parts_Exchange_Failed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                 or else Result.Admission /= HTTP_Client.Response_Observed
               then
                  raise Program_Error with
                    (case Echo_Index is
                        when 1 => "wrong ListParts bucket accepted",
                        when 2 => "wrong ListParts upload ID accepted",
                        when 3 => "wrong ListParts marker accepted",
                        when others => "wrong ListParts maximum accepted");
               end if;
            end loop;
         end;
         declare
            Put_Parameters : constant
              Low_Level.Put_Bucket_Versioning_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               MFA => US.Null_Unbounded_String,
               Configuration =>
                 (Status     =>
                    Flyology.Object_Storage.Versioning_Enabled,
                  MFA_Delete =>
                    Flyology.Object_Storage.MFA_Delete_Unconfigured),
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Put_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Versioning
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Put_Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Put_Result : constant
              Low_Level.Put_Bucket_Versioning_Outcome :=
                Low_Level.Execute_Put_Bucket_Versioning
                  (HTTP, Put_Prepared, Timeout => 5.0);
            Get_Parameters : constant
              Low_Level.Get_Bucket_Versioning_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Get_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Versioning
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Get_Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Get_Result : constant
              Low_Level.Get_Bucket_Versioning_Outcome :=
                Low_Level.Execute_Get_Bucket_Versioning
                  (HTTP, Get_Prepared, Timeout => 5.0);
         begin
            if Put_Result.Kind /= Low_Level.Bucket_Versioning_Updated then
               raise Program_Error with
                 "typed PutBucketVersioning socket result mismatch";
            elsif Get_Result.Kind /= Low_Level.Bucket_Versioning_Found
              or else
                Get_Result.Configuration.Status /=
                  Flyology.Object_Storage.Versioning_Enabled
            then
               raise Program_Error with
                 "typed GetBucketVersioning socket result mismatch";
            end if;
         end;
         declare
            Set_Result : constant Client_Buckets.Set_Versioning_Outcome :=
              Client_Buckets.Set_Versioning_Configuration
                (HTTP, Origin, "example-bucket",
                 (Status => Flyology.Object_Storage.Versioning_Suspended,
                  MFA_Delete =>
                    Flyology.Object_Storage.MFA_Delete_Unconfigured),
                 Identity, Checksum_Algorithm => "SHA256",
                 Expected_Bucket_Owner => "123456789012",
                 Timeout => 5.0);
            Get_Result : constant Client_Buckets.Get_Versioning_Outcome :=
              Client_Buckets.Get_Versioning
                (HTTP, Origin, "example-bucket", Identity,
                 Timeout => 5.0);
         begin
            if Set_Result.Kind /= Client_Buckets.Versioning_Updated
              or else Get_Result.Kind /= Client_Buckets.Versioning_Found
              or else
                Get_Result.Configuration.Status /=
                  Flyology.Object_Storage.Versioning_Suspended
            then
               raise Program_Error with
                 "convenience bucket versioning socket result mismatch";
            end if;
         end;
         declare
            Parameters : constant
              Low_Level.Get_Bucket_Versioning_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Versioning_Result :=
              Client_Buckets.Get_Versioning
                (HTTP,
                 Origin,
                 "typed-versioning",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Versioning_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /=
                Low_Level.Bucket_Versioning_Found
              or else Result.Response.Configuration.Status /=
                Flyology.Object_Storage.Versioning_Enabled
            then
               raise Program_Error with
                 "typed GetBucketVersioning response mismatch";
            end if;
         end;
         declare
            Parameters : constant
              Low_Level.Get_Bucket_Versioning_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            --  Versioning parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_Versioning_Result;
         begin
            declare
               Operation : Get_Bucket_Versioning_Operation :=
                 Get_Versioning
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-versioning",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_Versioning_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Bucket_Versioning_Found
                 or else Result.Response.Configuration.Status /=
                   Flyology.Object_Storage.Versioning_Unconfigured
               then
                  raise Program_Error with
                    "composed GetBucketVersioning first result mismatch";
               end if;
               Get_Versioning
                 (HTTP'Access,
                  Origin,
                  "restart-versioning",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_Versioning_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Bucket_Versioning_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-versioning-request"
               then
                  raise Program_Error with
                    "composed GetBucketVersioning restart mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant
              Low_Level.Put_Bucket_Versioning_Parameters :=
                (Content_MD5        => US.Null_Unbounded_String,
                 Checksum_Algorithm => US.Null_Unbounded_String,
                 MFA                => US.Null_Unbounded_String,
                 Configuration      =>
                   (Status     =>
                      Flyology.Object_Storage.Versioning_Enabled,
                    MFA_Delete =>
                      Flyology.Object_Storage.MFA_Delete_Unconfigured),
                 Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Result : constant Put_Bucket_Versioning_Result :=
              Client_Buckets.Set_Versioning_Configuration
                (HTTP,
                 Origin,
                 "typed-put-versioning",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Put_Bucket_Versioning_Response_Available
              or else Result.Disposition /=
                Bucket_Versioning_Mutation_Completed
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /=
                Low_Level.Bucket_Versioning_Updated
            then
               raise Program_Error with
                 "typed PutBucketVersioning response mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Put_Bucket_Versioning_Parameters :=
              (Content_MD5        => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               MFA                => US.Null_Unbounded_String,
               Configuration      =>
                 (Status     =>
                    Flyology.Object_Storage.Versioning_Suspended,
                  MFA_Delete =>
                    Flyology.Object_Storage.MFA_Delete_Unconfigured),
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Versioning parent, HTTP exchange, and transport child.
            Set    : aliased Operations.Completion_Set (3);
            Result : Put_Bucket_Versioning_Result;
         begin
            declare
               Operation : Put_Bucket_Versioning_Operation :=
                 Set_Versioning_Configuration
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-put-versioning",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_Versioning_Response_Available
                 or else Result.Disposition /=
                   Bucket_Versioning_Mutation_Completed
               then
                  raise Program_Error with
                    "composed PutBucketVersioning first result mismatch";
               end if;
               Parameters.Configuration.Status :=
                 Flyology.Object_Storage.Versioning_Enabled;
               Set_Versioning_Configuration
                 (HTTP'Access,
                  Origin,
                  "restart-put-versioning",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_Versioning_Response_Available
                 or else Result.Disposition /=
                   Bucket_Versioning_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Put_Bucket_Versioning_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-put-versioning-request"
               then
                  raise Program_Error with
                    "composed PutBucketVersioning restart mismatch";
               end if;
            end;
         end;
         declare
            Values : constant Low_Level.Model_Value_Array :=
              (1 =>
                 (Member_Name =>
                    US.To_Unbounded_String ("Bucket"),
                  Map_Key => US.Null_Unbounded_String,
                  Value => US.To_Unbounded_String ("example-bucket")));
            Prepared_Head : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Request
                (Model.Head_Bucket_Operation, Origin,
                 Low_Level.Path_Style, Values, "", False, "", Identity,
                 "us-east-1", "20130524T000000Z");
            Response : constant HTTP_Client.Response :=
              Low_Level.Execute_Model_Request
                (HTTP, Prepared_Head, Timeout => 5.0);
         begin
            if HTTP_Client.Status (Response) /= 200
              or else not HTTP_Client.Body_Complete (Response)
            then
               raise Program_Error with
                 "generic model execution result mismatch";
            end if;
         end;
         declare
            Values : constant Low_Level.Model_Value_Array :=
              ((Member_Name => US.To_Unbounded_String ("Bucket"),
                Map_Key => US.Null_Unbounded_String,
                Value => US.To_Unbounded_String ("example-bucket")),
               (Member_Name => US.To_Unbounded_String ("Key"),
                Map_Key => US.Null_Unbounded_String,
                Value => US.To_Unbounded_String ("model-stream")));
            Prepared_Put : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Streaming_Request
                (Model.Put_Object_Operation, Origin,
                 Low_Level.Path_Style, Values,
                 SigV4.SHA256_Hex (Upload_Payload), Identity,
                 "us-east-1", "20130524T000000Z");
            Source : Upload_Source (Upload_Payload'Access);
            Response : constant HTTP_Client.Response :=
              Low_Level.Execute_Model_Request
                (HTTP, Prepared_Put, Source, Timeout => 5.0);
         begin
            if HTTP_Client.Status (Response) /= 200
              or else HTTP_Client.Header (Response, "etag") /=
                """model-stream"""
            then
               raise Program_Error with
                 "generic streaming model execution result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Put_Object_Parameters;
         begin
            Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-put", Parameters,
                    SigV4.SHA256_Hex (Upload_Payload), Identity,
                    "us-east-1", "20130524T000000Z");
               Source : Upload_Source (Upload_Payload'Access);
               Result : constant Low_Level.Put_Object_Outcome :=
                 Low_Level.Execute_Put_Object
                   (HTTP, Prepared, Source, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Put
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """typed-put"""
                 or else US.To_String (Result.Result.Checksum_Type) /=
                   "FULL_OBJECT"
                 or else US.To_String
                   (Result.Result.Server_Side_Encryption) /= "aws:kms"
                 or else US.To_String (Result.Result.SSE_KMS_Key_ID) /=
                   "kms-key"
                 or else not Result.Result.Bucket_Key_Enabled.Is_Set
                 or else not Result.Result.Bucket_Key_Enabled.Value
                 or else not Result.Result.Size.Is_Set
                 or else Result.Result.Size.Value /= 1
               then
                  raise Program_Error with "typed PutObject result mismatch";
               end if;
            end;
         end;
         Require_Put_Response ("put-response-minimal", True);
         Require_Put_Response ("put-response-body", False);
         for Index in Put_Response_Headers'Range loop
            Require_Put_Response
              ("put-response-valid-" & Decimal (Index), True,
               Projection_Index => Index);
            Require_Put_Response
              ("put-response-empty-" & Decimal (Index), False);
            Require_Put_Response
              ("put-response-duplicate-" & Decimal (Index), False);
         end loop;
         Require_Put_Response ("put-size-zero", True, "0");
         Require_Put_Response
           ("put-size-maximum", True, "9223372036854775807");
         Require_Put_Response ("put-size-leading-zero", False);
         Require_Put_Response ("put-size-negative", False);
         Require_Put_Response ("put-size-overflow", False);
         Require_Put_Response ("put-bucket-key-invalid-case", False);
         Require_Put_Response ("put-bucket-key-invalid-digit", False);
         Require_Put_Response
           ("put-checksum-without-type", True,
            Expected_Checksum_Type => "FULL_OBJECT");
         Require_Put_Response ("put-checksum-type-without-value", False);
         Require_Put_Response ("put-checksum-composite", False);
         Require_Put_Response ("put-checksum-multiple", False);
         for Index in 3 .. 12 loop
            Require_Put_Response
              ("put-checksum-malformed-" & Decimal (Index), False);
         end loop;
         Require_Put_Response ("put-etag-missing", False);
         Require_Put_Response ("put-etag-unquoted", False);
         Require_Put_Response ("put-etag-weak", False);
         Require_Put_Response ("put-encryption-invalid-enum", False);
         Require_Put_Response ("put-request-charged-invalid-enum", False);
         Require_Put_Response ("put-ssec-invalid-algorithm", False);
         Require_Put_Response ("put-ssec-invalid-md5", False);
         Require_Put_Response ("put-kms-context-invalid-base64", False);
         Require_Put_Response ("put-expiration-over-limit", False);
         Require_Put_Response ("put-version-over-limit", False);
         Require_Put_Response ("put-kms-key-over-limit", False);
         Require_Put_Response ("put-ssec-incomplete", False);
         Require_Put_Response ("put-kms-key-without-encryption", False);
         Require_Put_Response ("put-bucket-key-without-encryption", False);
         Require_Put_Response ("put-dsse-bucket-key", False);
         Require_Put_Response ("put-mixed-customer-kms", False);
         declare
            Upload_Parameters : Low_Level.Upload_Part_Parameters;
            Source : Rewindable_Probe;
            Rejected : Boolean := False;
         begin
            Upload_Parameters.Upload_ID :=
              US.To_Unbounded_String ("socket-upload-response");
            Upload_Parameters.Payload_SHA256 := US.To_Unbounded_String
              (SigV4.SHA256_Hex (""));
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "upload-rewindable", Upload_Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Upload_Part_Outcome :=
                       Low_Level.Execute_Upload_Part
                         (HTTP, Prepared, Source, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Request => Rejected := True;
               end;
            end;
            if not Rejected then
               raise Program_Error with
                 "rewindable UploadPart source reached HTTP admission";
            end if;
         end;
         Require_Upload_Response ("upload-response-minimal", True);
         Require_Upload_Response ("upload-response-body", False);
         for Index in Upload_Response_Headers'Range loop
            Require_Upload_Response
              ("upload-response-valid-" & Decimal (Index), True,
               Projection_Index => Index);
            Require_Upload_Response
              ("upload-response-empty-" & Decimal (Index), False);
            Require_Upload_Response
              ("upload-response-duplicate-" & Decimal (Index), False);
         end loop;
         for Index in 3 .. 12 loop
            Require_Upload_Response
              ("upload-checksum-malformed-" & Decimal (Index), False);
         end loop;
         Require_Upload_Response ("upload-checksum-multiple", False);
         Require_Upload_Response ("upload-ssec-incomplete", False);
         Require_Upload_Response
           ("upload-kms-key-without-encryption", False);
         Require_Upload_Response
           ("upload-bucket-key-without-encryption", False);
         Require_Upload_Response ("upload-dsse-bucket-key", False);
         Require_Upload_Response ("upload-mixed-customer-kms", False);
         Require_Upload_Response
           ("upload-bind-exact", True, Bind_SHA256 => True);
         declare
            Prime : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "lost-upload-prime",
                 Identity, Timeout => 5.0);
            Upload_Parameters : Low_Level.Upload_Part_Parameters;
            --  Derived test geometry: one token holds the exact fixed lost-
            --  response part while typed Finish restores it for
            --  reconciliation.
            Pool : aliased Buffers.Pool
              (Block_Size => Lost_Upload_Payload'Length, Capacity => 1);
            Payload_Buffer : Buffers.Unique_Buffer (Pool'Access);
         begin
            if Prime.Kind /= Transfers.Object_Found
              or else US.To_String (Prime.Entity_Tag) /= """lost-prime"""
            then
               raise Program_Error with
                 "UploadPart lost-response connection prime failed";
            end if;
            Upload_Parameters.Upload_ID :=
              US.To_Unbounded_String ("lost-upload-id");
            Upload_Parameters.Payload_SHA256 := US.To_Unbounded_String
              (SigV4.SHA256_Hex (Lost_Upload_Payload));
            Upload_Parameters.Checksum_Algorithm :=
              US.To_Unbounded_String ("SHA256");
            Upload_Parameters.Checksum_SHA256 :=
              US.To_Unbounded_String (Lost_Upload_SHA256);
            Buffers.Acquire (Payload_Buffer);
            Buffers.Copy_From
              (Payload_Buffer, Bytes (Lost_Upload_Payload));
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Cancelled : constant Upload_Part_Result :=
                    Transfers.Upload_Part
                      (HTTP, Origin, "example-bucket", "upload-cancelled",
                       Upload_Parameters, Payload_Buffer, Identity,
                       Timeout => 5.0, Token => Stop'Access);
               begin
                  if Cancelled.Kind /= Upload_Part_Exchange_Failed
                    or else Cancelled.Disposition /=
                      Part_Cancelled_Before_Admission
                    or else Cancelled.Admission /= HTTP_Client.Not_Admitted
                    or else not Buffers.Has_Buffer (Payload_Buffer)
                    or else Buffer_String (Payload_Buffer) /=
                      Lost_Upload_Payload
                  then
                     raise Program_Error with
                       "pre-admission UploadPart cancellation/ownership " &
                       "mismatch";
                  end if;
               end;
            end;
            declare
               Result : constant Upload_Part_Result :=
                 Transfers.Upload_Part
                   (HTTP, Origin, "example-bucket", "lost-upload",
                    Upload_Parameters, Payload_Buffer, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= Upload_Part_Exchange_Failed
                 or else Result.Disposition /= Part_Outcome_Unknown
                 or else Result.Admission /= HTTP_Client.Possibly_Admitted
                 or else not Buffers.Has_Buffer (Payload_Buffer)
                 or else Buffer_String (Payload_Buffer) /= Lost_Upload_Payload
               then
                  raise Program_Error with
                    "lost UploadPart response certainty/ownership mismatch";
               end if;
            end;

            declare
               List_Parameters : Low_Level.List_Parts_Parameters;
            begin
               List_Parameters.Upload_ID :=
                 US.To_Unbounded_String ("lost-upload-id");
               declare
                  Prepared_List : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_List_Parts
                      (Origin, Low_Level.Path_Style, "example-bucket",
                       "lost-upload", List_Parameters, Identity,
                       "us-east-1", "20130524T000000Z");
                  Listed : constant Low_Level.List_Parts_Outcome :=
                    Low_Level.Execute_List_Parts
                      (HTTP, Prepared_List, Timeout => 5.0);
               begin
                  if Listed.Kind /= Low_Level.Parts_Listed
                    or else Natural
                      (Listed.Result.Listing.Parts.Length) /= 1
                  then
                     raise Program_Error with
                       "UploadPart lost-response reconciliation failed";
                  end if;
                  declare
                     Part : constant Multipart.Listed_Part :=
                       Listed.Result.Listing.Parts.First_Element;
                     Completion :
                       Multipart.Complete_Multipart_Upload_Request;
                  begin
                     if Part.Number /= 1
                       or else Part.Size /= Lost_Upload_Payload'Length
                       or else US.To_String (Part.Entity_Tag) /=
                         """lost-part"""
                       or else US.To_String (Part.Checksum_SHA256) /=
                         Lost_Upload_SHA256
                     then
                        raise Program_Error with
                          "UploadPart reconciliation tuple mismatch";
                     end if;
                     Completion.Parts.Append
                       (Multipart.Completed_Part'
                          (Number => Part.Number,
                           Entity_Tag => Part.Entity_Tag,
                           Checksum_SHA256 => Part.Checksum_SHA256,
                           others => <>));
                     declare
                        Parameters : Low_Level.Complete_Multipart_Parameters;
                        Stop : aliased Flyology.Cancellation.Token;
                     begin
                        Stop.Request;
                        declare
                           Cancelled : constant
                             Multipart_Completion_Result :=
                               Transfers.Complete_Multipart_Upload
                                 (HTTP, Origin, "example-bucket",
                                  "lost-upload", "lost-upload-id",
                                  Completion, Parameters, Identity,
                                  Timeout => 5.0, Token => Stop'Access);
                        begin
                           if Cancelled.Kind /=
                             Complete_Multipart_Exchange_Failed
                             or else Cancelled.Disposition /=

                                 Completion_Cancelled_Before_Admission
                             or else Cancelled.Admission /=
                               HTTP_Client.Not_Admitted
                           then
                              raise Program_Error with
                                "pre-admission multipart completion " &
                                "cancellation mismatch";
                           end if;
                        end;
                        declare
                           Completed : constant
                             Multipart_Completion_Result :=
                               Transfers.Complete_Multipart_Upload
                                 (HTTP, Origin, "example-bucket",
                                  "lost-upload", "lost-upload-id",
                                  Completion, Parameters, Identity,
                                  Timeout => 5.0);
                        begin
                           if Completed.Kind /=
                             Complete_Multipart_Exchange_Failed
                             or else Completed.Disposition /=
                               Completion_Outcome_Unknown
                             or else Completed.Admission /=
                               HTTP_Client.Possibly_Admitted
                           then
                              raise Program_Error with
                                "lost multipart completion certainty " &
                                "mismatch";
                           end if;
                        end;
                     end;
                     declare
                        Whole : constant Objects.Whole_Get_Outcome :=
                          Objects.Get_Whole
                            (HTTP, Origin, "example-bucket", "lost-upload",
                             1_024, Identity,
                             Expected_Entity_Tag => """lost-whole""",
                             Checksum_Mode => True, Timeout => 5.0);
                     begin
                        if Whole.Kind /= Objects.Whole_Object_Read
                          or else US.To_String
                            (Whole.Result.Entity_Tag) /= """lost-whole"""
                          or else US.To_String
                            (Whole.Result.Checksum_SHA256) /=
                              Lost_Upload_SHA256
                          or else Flyology.Bytes.To_Byte_String
                            (Whole.Object_Bytes) /= Lost_Upload_Payload
                        then
                           raise Program_Error with
                             "generation-bound completed object mismatch";
                        end if;
                     end;
                  end;
               end;
            end;
         end;
         declare
            Create_Parameters : Low_Level.Create_Multipart_Parameters;
            Created : constant Low_Level.Create_Multipart_Outcome :=
              Transfers.Create_Multipart_Upload
                (HTTP, Origin, "example-bucket", "lost-abort",
                 Create_Parameters, Identity, Timeout => 5.0);
         begin
            if Created.Kind /= Low_Level.Created
              or else US.To_String (Created.Result.Upload_ID) /=
                "lost-abort-id"
            then
               raise Program_Error with
                 "AbortMultipartUpload lost-response setup failed";
            end if;
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Cancelled : constant Multipart_Abort_Result :=
                    Transfers.Abort_Multipart_Upload
                      (HTTP, Origin, "example-bucket", "lost-abort",
                       "lost-abort-id", Identity, Timeout => 5.0,
                       Token => Stop'Access);
               begin
                  if Cancelled.Kind /=
                    Abort_Multipart_Exchange_Failed
                    or else Cancelled.Disposition /=
                      Abort_Cancelled_Before_Admission
                    or else Cancelled.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission lost AbortMultipartUpload " &
                       "cancellation mismatch";
                  end if;
               end;
            end;
            declare
               Aborted : constant Multipart_Abort_Result :=
                 Transfers.Abort_Multipart_Upload
                   (HTTP, Origin, "example-bucket", "lost-abort",
                    "lost-abort-id", Identity, Timeout => 5.0);
            begin
               if Aborted.Kind /= Abort_Multipart_Exchange_Failed
                 or else Aborted.Disposition /= Abort_Outcome_Unknown
                 or else Aborted.Admission /= HTTP_Client.Possibly_Admitted
               then
                  raise Program_Error with
                    "lost AbortMultipartUpload response certainty mismatch";
               end if;
            end;
            declare
               List_Parameters : Low_Level.List_Parts_Parameters;
            begin
               List_Parameters.Upload_ID :=
                 US.To_Unbounded_String ("lost-abort-id");
               declare
                  Listed : constant List_Parts_Result :=
                    Transfers.List_Parts_Page
                      (HTTP, Origin, "example-bucket", "lost-abort",
                       List_Parameters, Identity, Timeout => 5.0);
               begin
                  if Listed.Kind /= List_Parts_Response_Available
                    or else Listed.Failure /= Not_Found
                    or else Listed.Response.Kind /=
                      Low_Level.List_Parts_Rejected
                    or else Listed.Response.Status /= 404
                    or else US.To_String (Listed.Response.Error.Code) /=
                      "NoSuchUpload"
                  then
                     raise Program_Error with
                       "lost AbortMultipartUpload reconciliation failed";
                  end if;
               end;
            end;
         end;
         declare
            Prime : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "lost-copy-part-prime",
                 Identity, Timeout => 5.0);
            Parameters : Low_Level.Upload_Part_Copy_Parameters;
         begin
            if Prime.Kind /= Transfers.Object_Found
              or else US.To_String (Prime.Entity_Tag) /=
                """lost-copy-prime"""
            then
               raise Program_Error with
                 "UploadPartCopy lost-response connection prime failed";
            end if;
            Parameters.Upload_ID :=
              US.To_Unbounded_String ("lost-copy-part-id");
            Parameters.Copy_Source :=
              US.To_Unbounded_String ("source-bucket/source-key");
            declare
               Result : constant Upload_Part_Copy_Result :=
                 Transfers.Upload_Part_Copy
                   (HTTP, Origin, "example-bucket", "lost-copy-part",
                    Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Upload_Part_Copy_Exchange_Failed
                 or else Result.Disposition /= Outcome_Unknown
                 or else Result.Admission /= HTTP_Client.Possibly_Admitted
               then
                  raise Program_Error with
                    "lost UploadPartCopy response certainty mismatch";
               end if;
            end;
            declare
               List_Parameters : Low_Level.List_Parts_Parameters;
            begin
               List_Parameters.Upload_ID :=
                 US.To_Unbounded_String ("lost-copy-part-id");
               declare
                  Listed : constant List_Parts_Result :=
                    Transfers.List_Parts_Page
                      (HTTP, Origin, "example-bucket", "lost-copy-part",
                       List_Parameters, Identity, Timeout => 5.0);
               begin
                  if Listed.Kind /= List_Parts_Response_Available
                    or else Listed.Response.Kind /= Low_Level.Parts_Listed
                    or else Natural
                      (Listed.Response.Result.Listing.Parts.Length) /= 1
                    or else Listed.Response.Result.Listing.Parts
                      .First_Element.Number /= 1
                    or else US.To_String
                      (Listed.Response.Result.Listing.Parts
                         .First_Element.Entity_Tag) /= """lost-copy-part"""
                  then
                     raise Program_Error with
                       "UploadPartCopy lost-response reconciliation failed";
                  end if;
               end;
            end;
         end;
         Require_Upload_Response
           ("upload-bind-wrong-algorithm", False, Bind_SHA256 => True);
         Require_Upload_Response
           ("upload-bind-wrong-value", False, Bind_SHA256 => True);
         declare
            Options : Objects.Complete_Put_Options :=
              Objects.Default_Complete_Put_Options;
            Source : Upload_Source (Convenience_Put_Payload'Access);
         begin
            Options.Content_MD5 :=
              US.To_Unbounded_String (Convenience_Put_MD5);
            Options.Content_Type := US.To_Unbounded_String ("text/plain");
            Options.Metadata.Cache_Control :=
              (Is_Set => True, Value => US.To_Unbounded_String ("no-cache"));
            Options.Metadata.Content_Disposition :=
              (Is_Set => True, Value => US.To_Unbounded_String ("inline"));
            Options.Metadata.Content_Encoding :=
              (Is_Set => True, Value => US.To_Unbounded_String ("gzip"));
            Options.Metadata.Content_Language :=
              (Is_Set => True, Value => US.To_Unbounded_String ("en-CA"));
            Options.Metadata.Expires :=
              (Is_Set => True, Value => 1_369_353_600);
            Options.Metadata.Website_Redirect_Location :=
              (Is_Set => True, Value => US.To_Unbounded_String ("/next"));
            Options.Metadata.User.Length := 1;
            Options.Metadata.User.Items (1) :=
              (Key   => US.To_Unbounded_String ("project"),
               Value => US.To_Unbounded_String ("flyology"));
            Options.Tags.Length := 1;
            Options.Tags.Items (1) :=
              (Key   => US.To_Unbounded_String ("team+name"),
               Value => US.To_Unbounded_String ("storage/ada"));
            Options.Checksum :=
              (Algorithm => Flyology.Object_Storage.Checksum_CRC32,
               Method    => Flyology.Object_Storage.Full_Object_Checksum,
               Value     => US.To_Unbounded_String (Convenience_Put_CRC32));
            Options.Conditions.If_None_Match := US.To_Unbounded_String ("*");
            Options.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            declare
               Result : constant Low_Level.Put_Object_Outcome :=
                 Objects.Put_Object
                   (HTTP, Origin, "example-bucket", "convenience-put",
                    Source, SigV4.SHA256_Hex (Convenience_Put_Payload),
                    Identity, Options => Options, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Put
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """convenience-put"""
                 or else US.To_String (Result.Result.Checksum_CRC32) /=
                   Convenience_Put_CRC32
                 or else US.To_String (Result.Result.Checksum_Type) /=
                   "FULL_OBJECT"
                 or else not Result.Result.Size.Is_Set
                 or else Result.Result.Size.Value /=
                   Convenience_Put_Payload'Length
               then
                  raise Program_Error with
                    "convenience PutObject result mismatch";
               end if;
            end;
            declare
               Parameters : Low_Level.Put_Object_Parameters;
               --  Test-reference geometry: the sole token owns the exact
               --  complete-object fixture throughout each serial operation.
               Pool : aliased Buffers.Pool
                 (Block_Size => Convenience_Put_Payload'Length,
                  Capacity => 1);
               Payload_Buffer : Buffers.Unique_Buffer (Pool'Access);
            begin
               Parameters.Content_MD5 := Options.Content_MD5;
               Parameters.Content_Type := Options.Content_Type;
               Parameters.Cache_Control :=
                 Options.Metadata.Cache_Control.Value;
               Parameters.Content_Disposition :=
                 Options.Metadata.Content_Disposition.Value;
               Parameters.Content_Encoding :=
                 Options.Metadata.Content_Encoding.Value;
               Parameters.Content_Language :=
                 Options.Metadata.Content_Language.Value;
               Parameters.Expires := US.To_Unbounded_String
                 ("Fri, 24 May 2013 00:00:00 GMT");
               Parameters.Website_Redirect_Location :=
                 Options.Metadata.Website_Redirect_Location.Value;
               Parameters.Metadata.Append
                 (Low_Level.Metadata_Entry'
                    (Name  => US.To_Unbounded_String ("project"),
                     Value => US.To_Unbounded_String ("flyology")));
               Parameters.Tagging := US.To_Unbounded_String
                 ("team%2Bname=storage%2Fada");
               Parameters.Checksum_Algorithm :=
                 US.To_Unbounded_String ("CRC32");
               Parameters.Checksum_CRC32 :=
                 US.To_Unbounded_String (Convenience_Put_CRC32);
               Parameters.If_None_Match := US.To_Unbounded_String ("*");
               Parameters.Expected_Bucket_Owner :=
                 US.To_Unbounded_String ("123456789012");
               Buffers.Acquire (Payload_Buffer);
               Buffers.Copy_From
                 (Payload_Buffer, Bytes (Convenience_Put_Payload));
               declare
                  --  Object, HTTP exchange, and one transport child.
                  Set : aliased Operations.Completion_Set (3);
                  Operation : Conditional_Put_Operation :=
                    Put_Object
                      (Set'Access, HTTP'Access, Origin, "example-bucket",
                       "composable-put-first", Parameters, Payload_Buffer,
                       SigV4.SHA256_Hex (Convenience_Put_Payload), Identity,
                       HTTP_Client.Deadline_After (5.0));
                  Result : Conditional_Put_Result;
               begin
                  if Buffers.Has_Buffer (Payload_Buffer) then
                     raise Program_Error with
                       "composable complete PutObject retained caller token";
                  end if;
                  Operations.Wait_All (Set);
                  Finish (Operation, Result, Payload_Buffer);
                  if Result.Kind /= Put_Response_Available
                    or else Result.Disposition /= Published
                    or else Result.Response.Kind /= Low_Level.Object_Put
                    or else US.To_String
                      (Result.Response.Result.Entity_Tag) /=
                        """composable-put-first"""
                    or else not Buffers.Has_Buffer (Payload_Buffer)
                  then
                     raise Program_Error with
                       "composable complete PutObject constructor mismatch";
                  end if;

                  Put_Object
                    (HTTP'Access,
                     Origin,
                     "example-bucket",
                     "composable-put-second",
                     Parameters,
                     Payload_Buffer,
                     SigV4.SHA256_Hex (Convenience_Put_Payload),
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     Operation => Operation);
                  Operations.Wait_All (Set);
                  Finish (Operation, Result, Payload_Buffer);
                  if Result.Kind /= Put_Response_Available
                    or else Result.Disposition /= Published
                    or else US.To_String
                      (Result.Response.Result.Entity_Tag) /=
                        """composable-put-second"""
                    or else US.To_String
                      (Result.Response.Result.Checksum_Type) /= "FULL_OBJECT"
                    or else not Buffers.Has_Buffer (Payload_Buffer)
                    or else Buffer_String (Payload_Buffer) /=
                      Convenience_Put_Payload
                  then
                     raise Program_Error with
                       "composable complete PutObject restart mismatch";
                  end if;
               end;

               declare
                  Result : constant Conditional_Put_Result :=
                    Objects.Put_Object
                      (HTTP, Origin, "example-bucket",
                       "composable-put-mismatch", Payload_Buffer,
                       SigV4.SHA256_Hex (Convenience_Put_Payload), Identity,
                       Options => Options, Timeout => 5.0);
               begin
                  if Result.Kind /= Put_Exchange_Failed
                    or else Result.Disposition /= Outcome_Unknown
                    or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                    or else not Buffers.Has_Buffer (Payload_Buffer)
                    or else Buffer_String (Payload_Buffer) /=
                      Convenience_Put_Payload
                  then
                     raise Program_Error with
                       "composable PutObject checksum binding mismatch";
                  end if;
               end;
            end;
         end;
         declare
            Options : Objects.Complete_Put_Options :=
              Objects.Default_Complete_Put_Options;

            procedure Require_Invalid_Options is
               Source : Upload_Source (Convenience_Put_Payload'Access);
               Rejected : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Put_Object_Outcome :=
                       Objects.Put_Object
                         (HTTP, Origin, "example-bucket", "invalid-put",
                          Source,
                          SigV4.SHA256_Hex (Convenience_Put_Payload),
                          Identity, Options => Options, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Request =>
                     Rejected := True;
               end;
               if not Rejected then
                  raise Program_Error with
                    "invalid convenience PutObject options were admitted";
               end if;
            end Require_Invalid_Options;
         begin
            Options.Checksum :=
              (Algorithm => Flyology.Object_Storage.Checksum_CRC32,
               Method    => Flyology.Object_Storage.Composite_Checksum,
               Value     => US.To_Unbounded_String (Convenience_Put_CRC32));
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Checksum.Method :=
              Flyology.Object_Storage.Full_Object_Checksum;
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Checksum.Value := US.To_Unbounded_String ("AAAAAA==");
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Checksum :=
              (Algorithm => Flyology.Object_Storage.Checksum_CRC32,
               Method    => Flyology.Object_Storage.Full_Object_Checksum,
               Value     => US.Null_Unbounded_String);
            Require_Invalid_Options;
            Options.Checksum.Value := US.To_Unbounded_String ("AAAA");
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Content_MD5 := US.To_Unbounded_String ("not-base64");
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Conditions.If_Match := US.To_Unbounded_String ("bad");
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Content_Type := US.To_Unbounded_String
              (String'
                 (1 .. Flyology.Object_Storage.Maximum_System_Metadata_Bytes
                    => 'x'));
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Metadata.User.Items (1) :=
              (Key   => US.To_Unbounded_String ("hidden"),
               Value => US.To_Unbounded_String ("value"));
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Tags.Length := 1;
            Options.Tags.Items (1) :=
              (Key   => US.To_Unbounded_String ("bad&"),
               Value => US.Null_Unbounded_String);
            Require_Invalid_Options;
            Options := Objects.Default_Complete_Put_Options;
            Options.Tags.Length := 3;
            declare
               Roman_Eight : constant String :=
                 Character'Val (16#E2#) & Character'Val (16#85#) &
                 Character'Val (16#A7#);
               function Repeat
                 (Value : String; Count : Natural) return String
               is
                  Result : String (1 .. Value'Length * Count);
                  Last   : Natural := 0;
               begin
                  for Iteration in 1 .. Count loop
                     Result (Last + 1 .. Last + Value'Length) := Value;
                     Last := Last + Value'Length;
                  end loop;
                  return Result;
               end Repeat;
            begin
               for Index in 1 .. 2 loop
                  Options.Tags.Items (Index) :=
                    (Key   => US.To_Unbounded_String
                       (Repeat (Roman_Eight, 127) & Decimal (Index)),
                     Value => US.To_Unbounded_String
                       (Repeat (Roman_Eight, 256)));
               end loop;
               Options.Tags.Items (3) :=
                 (Key   => US.To_Unbounded_String ("3"),
                  Value => US.To_Unbounded_String
                    (Repeat (Roman_Eight, 143) & "abcd"));
            end;
            Require_Invalid_Options;
            declare
               Source : Rewindable_Probe;
               Rejected : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Put_Object_Outcome :=
                       Objects.Put_Object
                         (HTTP, Origin, "example-bucket", "invalid-put",
                          Source, SigV4.SHA256_Hex (""), Identity,
                          Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Request =>
                     Rejected := True;
               end;
               if not Rejected then
                  raise Program_Error with
                    "rewindable convenience PutObject source was admitted";
               end if;
            end;
         end;
         Require_Rewindable_Put_Rejected;
         Require_Invalid_Condition_Rejected;
         Require_Tag_Header_Boundaries;
         Run_Conditional_Put_Lifecycle;
         Run_Lost_Put_Reconciliation;
         declare
            Tags : Flyology.Object_Storage.Object_Tag_Set;
            Put_Parameters : Low_Level.Put_Object_Tagging_Parameters;
            Get_Parameters : Low_Level.Get_Object_Tagging_Parameters;
            Delete_Parameters : Low_Level.Delete_Object_Tagging_Parameters;
            --  Derived capacity: the parent, HTTP exchange, and HTTP's one
            --  active transport child are the only simultaneous operations.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            Tags.Length := 1;
            Tags.Items (1) :=
              (Key => US.To_Unbounded_String ("team"),
               Value => US.To_Unbounded_String ("storage"));
            declare
               Operation : Put_Object_Tagging_Operation :=
                 Put_Tags
                    (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "typed-tagged", Tags, Put_Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Object_Tagging_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Object_Tagging_Response_Available
                 or else Result.Disposition /=
                   Object_Tag_Mutation_Completed
                 or else Result.Response.Kind /= Low_Level.Tags_Put
                 or else US.To_String (Result.Response.Result.Version_ID) /=
                   "tag-put-version"
               then
                  raise Program_Error with
                    "typed PutObjectTagging socket result mismatch";
               end if;
               Put_Tags
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "typed-tagged",
                  Tags,
                  Put_Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Object_Tagging_Response_Available
                 or else Result.Disposition /=
                   Object_Tag_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Invalid_Request
                 or else Result.Response.Kind /=
                   Low_Level.Object_Tagging_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "InvalidTag"
               then
                  raise Program_Error with
                    "typed PutObjectTagging restart mismatch";
               end if;
            end;
            declare
               Operation : Get_Object_Tagging_Operation :=
                 Get_Tags
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "typed-tagged", Get_Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Object_Tagging_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Object_Tagging_Response_Available
                 or else Result.Response.Kind /= Low_Level.Tags_Gotten
                 or else Result.Response.Result.Tags /= Tags
                 or else US.To_String
                   (Result.Response.Result.Version_ID) /=
                   "tag-get-version"
               then
                  raise Program_Error with
                    "typed GetObjectTagging socket result mismatch";
               end if;
               Get_Tags
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "typed-tagged",
                  Get_Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Object_Tagging_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Tags_Gotten
                 or else Result.Response.Result.Tags /= Tags
                 or else US.To_String
                   (Result.Response.Result.Version_ID) /=
                   "tag-get-restart-version"
               then
                  raise Program_Error with
                    "typed GetObjectTagging restart mismatch";
               end if;
            end;
            declare
               Operation : Delete_Object_Tagging_Operation :=
                 Delete_Tags
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "typed-tagged", Delete_Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Delete_Object_Tagging_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                   Delete_Object_Tagging_Response_Available
                 or else Result.Disposition /=
                   Object_Tag_Mutation_Completed
                 or else Result.Response.Kind /= Low_Level.Tags_Deleted
                 or else US.To_String
                   (Result.Response.Result.Version_ID) /=
                   "tag-delete-version"
               then
                  raise Program_Error with
                    "typed DeleteObjectTagging socket result mismatch";
               end if;
               Delete_Tags
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "typed-tagged",
                  Delete_Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                   Delete_Object_Tagging_Response_Available
                 or else Result.Disposition /=
                   Object_Tag_Mutation_Completed
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Tags_Deleted
                 or else US.To_String
                   (Result.Response.Result.Version_ID) /=
                   "tag-delete-restart-version"
               then
                  raise Program_Error with
                    "typed DeleteObjectTagging restart mismatch";
               end if;
            end;
            declare
               Put_Result : constant Objects.Tagging_Outcome :=
                 Objects.Put_Tags
                   (HTTP, Origin, "example-bucket", "convenient-tagged",
                    Tags, Identity, Timeout => 5.0);
               Get_Result : constant Objects.Tagging_Outcome :=
                 Objects.Get_Tags
                   (HTTP, Origin, "example-bucket", "convenient-tagged",
                    Identity, Timeout => 5.0);
               Delete_Result : constant Objects.Tagging_Outcome :=
                 Objects.Delete_Tags
                   (HTTP, Origin, "example-bucket", "convenient-tagged",
                    Identity, Timeout => 5.0);
            begin
               if Put_Result.Kind /= Objects.Tags_Replaced
                 or else Get_Result.Kind /= Objects.Tags_Read
                 or else Get_Result.Result.Tags /= Tags
                 or else Delete_Result.Kind /= Objects.Tags_Cleared
               then
                  raise Program_Error with
                    "convenient object tagging socket flow mismatch";
               end if;
            end;
            declare
               Stop : aliased Flyology.Cancellation.Token;
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Objects.Tagging_Outcome :=
                       Objects.Put_Tags
                         (HTTP, Origin, "example-bucket", "cancelled-tagged",
                          Tags, Identity, Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               begin
                  declare
                     Ignored : constant Objects.Tagging_Outcome :=
                       Objects.Delete_Tags
                         (HTTP, Origin, "example-bucket", "expired-tagged",
                          Identity, Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Cancelled or else not Timed_Out then
                  raise Program_Error with
                    "object tagging ignored cancellation/deadline";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Delete_Object_Parameters;
         begin
            Parameters.Version_ID :=
              US.To_Unbounded_String ("socket version");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Bypass_Governance_Retention :=
              (Is_Set => True, Value => True);
            Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Parameters.If_Match :=
              US.To_Unbounded_String ("""socket-etag""");
            Parameters.If_Match_Last_Modified_Time :=
              US.To_Unbounded_String ("Wed, 21 Oct 2015 07:28:00 GMT");
            Parameters.If_Match_Size := (Is_Set => True, Value => 42);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-delete", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.Delete_Object_Outcome :=
                 Low_Level.Execute_Delete_Object
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Deleted
                 or else not Result.Result.Delete_Marker.Is_Set
                 or else not Result.Result.Delete_Marker.Value
                 or else US.To_String (Result.Result.Version_ID) /=
                   "deleted-socket-version"
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "typed DeleteObject socket result mismatch";
               end if;
            end;
         end;
         declare
            procedure Reject_Empty_Output (Key, Description : String) is
               Parameters : Low_Level.Delete_Object_Parameters;
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Object
                   (Origin, Low_Level.Path_Style, "example-bucket", Key,
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Rejected : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Delete_Object_Outcome :=
                       Low_Level.Execute_Delete_Object
                         (HTTP, Prepared, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Rejected := True;
               end;
               if not Rejected then
                  raise Program_Error with
                    "DeleteObject accepted an empty " & Description &
                    " response header";
               end if;
            end Reject_Empty_Output;
         begin
            Reject_Empty_Output
              ("empty-delete-marker-output", "delete-marker");
            Reject_Empty_Output
              ("empty-delete-version-output", "version-id");
            Reject_Empty_Output
              ("empty-delete-charged-output", "request-charged");
         end;
         declare
            Result : constant Objects.Delete_Outcome :=
              Objects.Delete
                (HTTP, Origin, "example-bucket", "convenient-delete",
                 Identity, If_Match => "*",
                 Expected_Bucket_Owner => "123456789012",
                 Request_Payer => "requester", Timeout => 5.0,
                 Bypass_Governance_Retention =>
                   (Is_Set => True, Value => False),
                 If_Match_Last_Modified_Time =>
                   "Wed, 21 Oct 2015 07:28:00 GMT",
                 If_Match_Size => (Is_Set => True, Value => 7));
         begin
            if Result.Kind /= Objects.Object_Removed
              or else Result.Status /= 204
            then
               raise Program_Error with
                 "convenience DeleteObject socket result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Delete_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "duplicate-delete-output", Parameters, Identity,
                 "us-east-1", "20130524T000000Z");
            Rejected : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Delete_Object_Outcome :=
                    Low_Level.Execute_Delete_Object
                      (HTTP, Prepared, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeleteObject accepted duplicate singleton outputs";
            end if;
         end;
         declare
            Result : constant Objects.Delete_Outcome :=
              Objects.Delete
                (HTTP, Origin, "example-bucket", "conflict-delete",
                 Identity, Timeout => 5.0);
         begin
            if Result.Kind /= Objects.Delete_Rejected
              or else Result.Status /= 409
              or else US.To_String (Result.Error.Code) /= "OperationAborted"
            then
               raise Program_Error with
                 "DeleteObject socket conflict was not typed";
            end if;
         end;
         declare
            Head_Parameters : Low_Level.Head_Object_Parameters;
            Delete_Parameters : Low_Level.Delete_Object_Parameters;
            Head_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "lost-delete", Head_Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Lost_Response : Boolean := False;
         begin
            declare
               Before : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Head_Prepared, Timeout => 5.0);
            begin
               if Before.Kind /= Low_Level.Object_Found
                 or else Before.Status /= 200
               then
                  raise Program_Error with
                    "lost-response DeleteObject priming HEAD mismatch";
               end if;
            end;
            Delete_Parameters.If_Match := US.To_Unbounded_String ("*");
            declare
               Delete_Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "lost-delete", Delete_Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Delete_Object_Outcome :=
                       Low_Level.Execute_Delete_Object
                         (HTTP, Delete_Prepared, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when others =>
                     --  No response means publication is unknown, never a
                     --  typed precondition rejection or replayed 404.
                     Lost_Response := True;
               end;
            end;
            if not Lost_Response then
               raise Program_Error with
                 "lost DeleteObject response was classified conclusively";
            end if;
            declare
               After : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Head_Prepared, Timeout => 5.0);
            begin
               if After.Kind /= Low_Level.Head_Object_Rejected
                 or else After.Status /= 404
               then
                  raise Program_Error with
                    "lost-response DeleteObject reconciliation mismatch";
               end if;
            end;
         end;
         declare
            Request : Deletions.Delete_Objects_Request;
            Parameters : Low_Level.Delete_Objects_Parameters;
         begin
            Request.Quiet := True;
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key                    =>
                    US.To_Unbounded_String ("socket-delete-a"),
                  Version_ID             =>
                    US.To_Unbounded_String ("version-a"),
                  Has_ETag               => True,
                  ETag                   => US.To_Unbounded_String ("*"),
                  Has_Last_Modified_Time => True,
                  Last_Modified_Time     => US.To_Unbounded_String
                    ("Wed, 21 Oct 2015 07:28:00 GMT"),
                  Has_Size               => True,
                  Size                   => 7));
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String ("socket-delete-b"),
                  Version_ID => US.To_Unbounded_String ("version-b"),
                  others     => <>));
            Parameters.MFA := US.To_Unbounded_String ("device 123456");
            Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            Parameters.Bypass_Governance_Retention :=
              (Is_Set => True, Value => True);
            Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Parameters.Checksum_Algorithm :=
              US.To_Unbounded_String ("CRC32");
            declare
               Result : constant Delete_Objects_Result :=
                 Objects.Delete_Objects
                   (HTTP, Origin, "example-bucket", Request, Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Objects_Response_Available
                 or else Result.Disposition /= Batch_Processed
                 or else Result.Response.Kind /= Low_Level.Objects_Deleted
                 or else Natural
                   (Result.Response.Result.Result.Deleted.Length) /= 1
                 or else Natural
                   (Result.Response.Result.Result.Errors.Length) /= 1
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /=
                   "requester"
                 or else US.To_String
                   (Result.Response.Result.Result.Deleted.First_Element.Key) /=
                     "socket-delete-a"
                 or else US.To_String
                   (Result.Response.Result.Result.Deleted.First_Element
                      .Version_ID) /=
                     "version-a"
                 or else not
                   Result.Response.Result.Result.Deleted.First_Element
                     .Delete_Marker.Is_Set
                 or else Result.Response.Result.Result.Deleted.First_Element
                   .Delete_Marker.Value
                 or else US.To_String
                   (Result.Response.Result.Result.Deleted.First_Element
                      .Delete_Marker_Version_ID) /= "marker-a"
                 or else US.To_String
                   (Result.Response.Result.Result.Errors.First_Element.Key) /=
                     "socket-delete-b"
                 or else US.To_String
                   (Result.Response.Result.Result.Errors.First_Element
                      .Version_ID) /=
                     "version-b"
                 or else US.To_String
                   (Result.Response.Result.Result.Errors.First_Element.Code) /=
                     "AccessDenied"
                 or else US.To_String
                   (Result.Response.Result.Result.Errors.First_Element
                      .Message) /=
                     "denied"
               then
                  raise Program_Error with
                    "typed DeleteObjects socket result mismatch";
               end if;
            end;
            Request.Objects.Clear;
            Request.Quiet := False;
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String ("unsupported"),
                  Version_ID => US.To_Unbounded_String ("version-id"),
                  others     => <>));
            Parameters := (others => <>);
            declare
               Result : constant Delete_Objects_Result :=
                 Objects.Delete_Objects
                   (HTTP, Origin, "missing-bucket", Request, Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Objects_Response_Available
                 or else Result.Disposition /=
                   Batch_Definitely_Not_Processed
                 or else Result.Response.Kind /=
                   Low_Level.Delete_Objects_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "NoSuchBucket"
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "delete-missing-request"
               then
                  raise Program_Error with
                    "all-unsupported DeleteObjects socket classification " &
                    "mismatch";
               end if;
            end;
            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Result : constant Delete_Objects_Result :=
                    Objects.Delete_Objects
                      (HTTP, Origin, "example-bucket", Request, Parameters,
                       Identity, Timeout => 5.0, Token => Stop'Access);
               begin
                  if Result.Kind /= Delete_Objects_Exchange_Failed
                    or else Result.Disposition /=
                      Batch_Cancelled_Before_Admission
                    or else Result.Failure /= Client_API.Cancelled
                    or else Result.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission DeleteObjects cancellation mismatch";
                  end if;
               end;
            end;
            declare
               --  Batch parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Delete_Objects_Operation :=
                 Delete_Objects
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Request, Parameters, Identity,
                    HTTP_Client.Deadline_After (5.0));
               Result : Delete_Objects_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Objects_Response_Available
                 or else Result.Disposition /= Batch_Processed
               then
                  raise Program_Error with
                    "direct DeleteObjects completion mismatch";
               end if;
               Delete_Objects
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  Request,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Objects_Response_Available
                 or else Result.Disposition /= Batch_Processed
               then
                  raise Program_Error with
                    "direct DeleteObjects restart mismatch";
               end if;
            end;
            declare
               Result : constant Delete_Objects_Result :=
                 Objects.Delete_Objects
                   (HTTP, Origin, "example-bucket", Request, Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Delete_Objects_Exchange_Failed
                 or else Result.Disposition /= Batch_Outcome_Unknown
                 or else Result.Failure /=
                   Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
               then
                  raise Program_Error with
                    "DeleteObjects accepted duplicate response metadata";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
         begin
            Parameters.Version_ID :=
              US.To_Unbounded_String ("socket version");
            Parameters.Has_Max_Parts := True;
            Parameters.Max_Parts := 1;
            Parameters.Has_Part_Number_Marker := True;
            Parameters.Part_Number_Marker := 1;
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Parameters.Attributes :=
              (Entity_Tag => True, Checksum => False,
               Object_Parts => True, Storage_Class => False,
               Object_Size => True);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Attributes
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "object key", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.Get_Object_Attributes_Outcome :=
                 Low_Level.Execute_Get_Object_Attributes
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Attributes_Found
                 or else not Result.Result.Delete_Marker.Is_Set
                 or else Result.Result.Delete_Marker.Value
                 or else US.To_String (Result.Result.Version_ID) /=
                   "socket version"
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
                 or else not Result.Result.Attributes.Has_Object_Parts
                 or else Natural
                   (Result.Result.Attributes.Object_Parts.Parts.Length) /= 1
                 or else Result.Result.Attributes.Object_Size.Value /= 14
               then
                  raise Program_Error with
                    "typed GetObjectAttributes result mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Objects.Get_Attributes_Outcome :=
              Objects.Get_Attributes
                (HTTP, Origin, "example-bucket", "convenience-attributes",
                 Identity, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Attributes_Found
              or else US.To_String (Result.Result.Attributes.Entity_Tag) /=
                """socket-attributes"""
              or else Result.Result.Attributes.Object_Size.Value /= 14
            then
               raise Program_Error with
                 "convenience GetObjectAttributes result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
         begin
            Parameters.Attributes.Object_Size := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Attributes
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "missing-attributes", Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Get_Object_Attributes_Outcome :=
                 Low_Level.Execute_Get_Object_Attributes
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /=
                 Low_Level.Get_Object_Attributes_Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "attributes-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "attributes-host"
               then
                  raise Program_Error with
                    "GetObjectAttributes socket rejection mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
            --  Attributes parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
         begin
            Parameters.Version_ID :=
              US.To_Unbounded_String ("scoped-version");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Attributes.Object_Size := True;
            declare
               Operation : Get_Object_Attributes_Operation :=
                 Get_Attributes
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "scoped-attributes", Parameters, Identity,
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Object_Attributes_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 Get_Object_Attributes_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Attributes_Found
                 or else US.To_String
                   (Result.Response.Result.Version_ID) /= "scoped-version"
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "composable GetObjectAttributes success mismatch";
               end if;
               Parameters.Version_ID := US.Null_Unbounded_String;
               Parameters.Request_Payer := US.Null_Unbounded_String;
               Get_Attributes
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "scoped-attributes-restart",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 Get_Object_Attributes_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Attributes_Found
               then
                  raise Program_Error with
                    "composable GetObjectAttributes restart mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
         begin
            Parameters.Attributes.Object_Size := True;
            declare
               Result : constant Get_Object_Attributes_Result :=
                 Objects.Get_Attributes
                   (HTTP, Origin, "example-bucket",
                    "scoped-attributes-error", Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /=
                 Get_Object_Attributes_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Object_Attributes_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "composable GetObjectAttributes rejection mismatch";
               end if;
            end;
         end;
         declare
            procedure Require_Invalid_Get_Object_Attributes
              (Key, Version_ID, Message : String) is
               Parameters : Low_Level.Get_Object_Attributes_Parameters;
               --  Attributes parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
            begin
               Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
               Parameters.Attributes.Object_Size := True;
               declare
                  Operation : Get_Object_Attributes_Operation :=
                    Get_Attributes
                      (Set'Access, HTTP'Access, Origin, "example-bucket", Key,
                       Parameters, Identity,
                       HTTP_Client.Deadline_After (5.0));
                  Result : Get_Object_Attributes_Result;
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /=
                    Get_Object_Attributes_Exchange_Failed
                    or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                    or else Result.Admission /= HTTP_Client.Response_Observed
                  then
                     raise Program_Error with Message;
                  end if;
               end;
            end Require_Invalid_Get_Object_Attributes;
         begin
            Require_Invalid_Get_Object_Attributes
              ("scoped-attributes-wrong", "expected-version",
               "GetObjectAttributes accepted a mismatched version");
            Require_Invalid_Get_Object_Attributes
              ("scoped-attributes-duplicate", "",
               "GetObjectAttributes accepted duplicate response metadata");
            Require_Invalid_Get_Object_Attributes
              ("scoped-attributes-payer", "",
               "GetObjectAttributes accepted unrequested payer admission");
         end;
         declare
            Stop : aliased Flyology.Cancellation.Token;
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
         begin
            Stop.Request;
            Parameters.Attributes.Object_Size := True;
            declare
               Result : constant Get_Object_Attributes_Result :=
                 Objects.Get_Attributes
                   (HTTP, Origin, "example-bucket",
                    "cancelled-attributes", Parameters, Identity,
                    Timeout => 5.0, Token => Stop'Access);
            begin
               if Result.Kind /=
                 Get_Object_Attributes_Exchange_Failed
                 or else Result.Failure /= Client_API.Cancelled
                 or else Result.Admission /= HTTP_Client.Not_Admitted
               then
                  raise Program_Error with
                    "pre-admission GetObjectAttributes cancellation mismatch";
               end if;
            end;
         end;
         declare
            Upload_Path : constant String :=
              "/tmp/flyology-object-storage-upload-"
              & Decimal (Natural (Port)) & ".bin";
            Empty_Path : constant String := Upload_Path & ".empty";

            procedure Check_High_Level_Uploads is
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
               Invalid_Selection : Boolean := False;
               Empty_Composite : Boolean := False;
               Unsupported_Multipart : Boolean := False;
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket", "cancelled",
                          Upload_Path, Identity, Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               if not Cancelled then
                  raise Program_Error with
                    "high-level upload ignored pre-cancellation";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket", "timed-out",
                          Upload_Path, Identity, Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Timed_Out then
                  raise Program_Error with
                    "high-level upload ignored zero timeout";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket", "invalid-checksum",
                          Upload_Path, Identity, Timeout => 5.0,
                          Checksum =>
                            (Enabled => True,
                             Algorithm => Checksum_Policy.Core.CRC64NVME,
                             Kind => Checksum_Policy.Composite));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Constraint_Error => Invalid_Selection := True;
               end;
               if not Invalid_Selection then
                  raise Program_Error with
                    "high-level upload accepted unsupported checksum policy";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket", "empty-composite",
                          Empty_Path, Identity, Timeout => 5.0,
                          Checksum =>
                            (Enabled => True,
                             Algorithm => Checksum_Policy.Core.SHA256,
                             Kind => Checksum_Policy.Composite));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Constraint_Error => Empty_Composite := True;
               end;
               if not Empty_Composite then
                  raise Program_Error with
                    "high-level upload accepted empty composite checksum";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket",
                          "unsupported-multipart-checksum", Upload_Path,
                          Identity, Timeout => 5.0,
                          Multipart_Threshold => 1,
                          Checksum =>
                            (Enabled => True,
                             Algorithm => Checksum_Policy.Core.SHA256,
                             Kind => Checksum_Policy.Full_Object));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Constraint_Error => Unsupported_Multipart := True;
               end;
               if not Unsupported_Multipart then
                  raise Program_Error with
                    "high-level upload accepted multipart full SHA256";
               end if;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high level+file%25", Upload_Path, Identity,
                       Content_Type => "application/test", Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 23
                    or else US.To_String (Result.Entity_Tag) /=
                      """high-level"""
                  then
                     raise Program_Error with
                       "high-level file upload result mismatch";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high-level-checksum-full", Upload_Path, Identity,
                       Timeout => 5.0,
                       Checksum =>
                         (Enabled => True,
                          Algorithm => Checksum_Policy.Core.CRC32,
                          Kind => Checksum_Policy.Full_Object));
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 23
                    or else US.To_String (Result.Entity_Tag) /=
                      """high-level-full"""
                    or else US.To_String (Result.Checksum) /=
                      High_Level_CRC32
                    or else US.To_String (Result.Checksum_Type) /=
                      "FULL_OBJECT"
                  then
                     raise Program_Error with
                       "high-level full checksum upload mismatch";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high-level-checksum-sha256", Upload_Path, Identity,
                       Timeout => 5.0,
                       Checksum =>
                         (Enabled => True,
                          Algorithm => Checksum_Policy.Core.SHA256,
                          Kind => Checksum_Policy.Full_Object));
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 23
                    or else US.To_String (Result.Entity_Tag) /=
                      """high-level-sha256"""
                    or else US.To_String (Result.Checksum) /=
                      High_Level_SHA256
                    or else US.To_String (Result.Checksum_Type) /=
                      "FULL_OBJECT"
                  then
                     raise Program_Error with
                       "high-level direct SHA256 checksum upload mismatch";
                  end if;
               end;
               declare
                  Rejected_Mismatch : Boolean := False;
               begin
                  begin
                     declare
                        Ignored : constant Transfers.Upload_Outcome :=
                          Transfers.Upload_File
                            (HTTP, Origin, "example-bucket",
                             "high-level-put-mismatch", Upload_Path,
                             Identity, Timeout => 5.0,
                             Checksum =>
                               (Enabled => True,
                                Algorithm => Checksum_Policy.Core.SHA256,
                                Kind => Checksum_Policy.Full_Object));
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Low_Level.Invalid_Response =>
                        Rejected_Mismatch := True;
                  end;
                  if not Rejected_Mismatch then
                     raise Program_Error with
                       "high-level PutObject trusted a mismatched checksum";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high-level-checksum-composite", Upload_Path,
                       Identity, Timeout => 5.0,
                       Checksum =>
                         (Enabled => True,
                          Algorithm => Checksum_Policy.Core.SHA256,
                          Kind => Checksum_Policy.Composite));
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 23
                    or else US.To_String (Result.Entity_Tag) /=
                      """high-level-composite"""
                    or else US.To_String (Result.Checksum) /=
                      High_Level_SHA256_Composite
                    or else US.To_String (Result.Checksum_Type) /=
                      "COMPOSITE"
                  then
                     raise Program_Error with
                       "high-level composite checksum upload mismatch";
                  end if;
               end;
               declare
                  Rejected_Mismatch : Boolean := False;
               begin
                  begin
                     declare
                        Ignored : constant Transfers.Upload_Outcome :=
                          Transfers.Upload_File
                            (HTTP, Origin, "example-bucket",
                             "high-level-checksum-mismatch", Upload_Path,
                             Identity, Timeout => 5.0,
                             Checksum =>
                               (Enabled => True,
                                Algorithm => Checksum_Policy.Core.SHA256,
                                Kind => Checksum_Policy.Composite));
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Low_Level.Invalid_Response =>
                        Rejected_Mismatch := True;
                  end;
                  if not Rejected_Mismatch then
                     raise Program_Error with
                       "high-level upload trusted a mismatched checksum";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket", "high-level-empty",
                       Empty_Path, Identity, Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 0
                    or else US.To_String (Result.Entity_Tag) /= """empty"""
                  then
                     raise Program_Error with
                       "high-level empty upload result mismatch";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high-level-rejected", Upload_Path, Identity,
                       Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.Upload_Rejected
                    or else Result.Status /= 403
                    or else US.To_String (Result.Error.Code) /=
                      "AccessDenied"
                  then
                     raise Program_Error with
                       "high-level upload rejection mismatch";
                  end if;
               end;
            end Check_High_Level_Uploads;
         begin
            Write_File (Upload_Path, High_Level_File_Payload);
            Write_File (Empty_Path, "");
            begin
               Check_High_Level_Uploads;
            exception
               when others =>
                  Delete_If_Present (Upload_Path);
                  Delete_If_Present (Empty_Path);
                  raise;
            end;
            Delete_If_Present (Upload_Path);
            Delete_If_Present (Empty_Path);
         end;
         declare
            Download_Path : constant String :=
              "/tmp/flyology-object-storage-download-"
              & Decimal (Natural (Port)) & ".bin";
            Empty_Path : constant String := Download_Path & ".empty";
            Rejected_Path : constant String := Download_Path & ".rejected";
            Truncated_Path : constant String := Download_Path & ".truncated";
            Partial_Path : constant String := Download_Path & ".partial";
            Range_Path : constant String := Download_Path & ".range";
            Not_Modified_Path : constant String :=
              Download_Path & ".not-modified";
            Precondition_Path : constant String :=
              Download_Path & ".precondition";
            Invalid_Path : constant String := Download_Path & ".invalid";

            procedure Cleanup is
            begin
               Delete_If_Present (Download_Path);
               Delete_If_Present (Empty_Path);
               Delete_If_Present (Rejected_Path);
               Delete_If_Present (Truncated_Path);
               Delete_If_Present (Partial_Path);
               Delete_If_Present (Range_Path);
               Delete_If_Present (Not_Modified_Path);
               Delete_If_Present (Precondition_Path);
               Delete_If_Present (Invalid_Path);
            end Cleanup;

            procedure Check_High_Level_Downloads is
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
               Truncated : Boolean := False;
               Partial   : Boolean := False;
               Stop : aliased Flyology.Cancellation.Token;

               procedure Require_Invalid_Interval
                 (Key : String; Range_Header : String := "")
               is
                  Raised : Boolean := False;
               begin
                  Write_File (Invalid_Path, "preserve-invalid-interval");
                  begin
                     declare
                        Ignored : constant Transfers.Download_Outcome :=
                          Transfers.Download_File
                            (HTTP, Origin, "example-bucket", Key,
                             Invalid_Path, Identity, Timeout => 5.0,
                             Byte_Range_Header => Range_Header);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Low_Level.Invalid_Response =>
                        Raised := True;
                  end;
                  if not Raised
                    or else Read_File (Invalid_Path) /=
                      "preserve-invalid-interval"
                  then
                     raise Program_Error with
                       "invalid GetObject interval was accepted";
                  end if;
                  Require_No_Download_Temporary (Invalid_Path);
               end Require_Invalid_Interval;
            begin
               Write_File (Download_Path, "preserved-before-start");
               Stop.Request;
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket", "cancelled",
                          Download_Path, Identity, Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               if not Cancelled
                 or else Read_File (Download_Path) /= "preserved-before-start"
               then
                  raise Program_Error with
                    "high-level download pre-cancellation was not atomic";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket", "timed-out",
                          Download_Path, Identity, Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Timed_Out
                 or else Read_File (Download_Path) /= "preserved-before-start"
               then
                  raise Program_Error with
                    "high-level download zero-timeout was not atomic";
               end if;
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket",
                       "download large+%25", Download_Path, Identity,
                       Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Downloaded
                    or else Result.Bytes /= Download_Payload'Length
                    or else US.To_String (Result.Entity_Tag) /=
                      """download-large"""
                    or else Read_File (Download_Path) /= Download_Payload
                  then
                     raise Program_Error with
                       "high-level large download result mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Download_Path);

               Write_File (Empty_Path, "replace-me");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-empty",
                       Empty_Path, Identity, Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Downloaded
                    or else Result.Bytes /= 0
                    or else US.To_String (Result.Entity_Tag) /=
                      """download-empty"""
                    or else Read_File (Empty_Path)'Length /= 0
                  then
                     raise Program_Error with
                       "high-level empty download result mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Empty_Path);

               Write_File (Rejected_Path, "preserve-rejected");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-rejected",
                       Rejected_Path, Identity, Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.Download_Rejected
                    or else Result.Status /= 403
                    or else US.To_String (Result.Error.Code) /= "AccessDenied"
                    or else Read_File (Rejected_Path) /= "preserve-rejected"
                  then
                     raise Program_Error with
                       "high-level download rejection mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Rejected_Path);

               Write_File (Truncated_Path, "preserve-truncated");
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket",
                          "download-truncated", Truncated_Path, Identity,
                          Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.HTTP.Protocol_Error =>
                     Truncated := True;
               end;
               if not Truncated
                 or else Read_File (Truncated_Path) /= "preserve-truncated"
               then
                  raise Program_Error with
                    "truncated download replaced the destination";
               end if;
               Require_No_Download_Temporary (Truncated_Path);

               Write_File (Partial_Path, "preserve-partial");
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket",
                          "download-unexpected-range", Partial_Path,
                          Identity, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Partial := True;
               end;
               if not Partial
                 or else Read_File (Partial_Path) /= "preserve-partial"
               then
                  raise Program_Error with
                    "partial download replaced the whole-file destination";
               end if;
               Require_No_Download_Temporary (Partial_Path);

               Write_File (Range_Path, "replace-range");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-range",
                       Range_Path, Identity, Timeout => 5.0,
                       Byte_Range_Header => "bytes=7-13");
               begin
                  if Result.Kind /= Transfers.File_Downloaded
                    or else Result.Status /= 206
                    or else Result.Bytes /= 7
                    or else US.To_String (Result.Entity_Tag) /=
                      """download-range"""
                    or else Read_File (Range_Path) /= "partial"
                  then
                     raise Program_Error with
                       "high-level ranged download result mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Range_Path);

               Write_File (Not_Modified_Path, "preserve-not-modified");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket",
                       "download-not-modified", Not_Modified_Path, Identity,
                       Timeout => 5.0,
                       If_None_Match => """download-range""");
               begin
                  if Result.Kind /= Transfers.Download_Rejected
                    or else Result.Status /= 304
                    or else US.To_String (Result.Error.Code) /= "HTTP304"
                    or else Read_File (Not_Modified_Path) /=
                      "preserve-not-modified"
                  then
                     raise Program_Error with
                       "high-level conditional 304 download mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Not_Modified_Path);

               Write_File (Precondition_Path, "preserve-precondition");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket",
                       "download-precondition", Precondition_Path, Identity,
                       Timeout => 5.0, If_Match => """different""");
               begin
                  if Result.Kind /= Transfers.Download_Rejected
                    or else Result.Status /= 412
                    or else US.To_String (Result.Error.Code) /= "HTTP412"
                    or else Read_File (Precondition_Path) /=
                      "preserve-precondition"
                  then
                     raise Program_Error with
                       "high-level conditional 412 download mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Precondition_Path);

               Require_Invalid_Interval
                 ("download-missing-content-range", "bytes=0-0");
               Require_Invalid_Interval
                 ("download-length-mismatch", "bytes=0-0");
               Require_Invalid_Interval
                 ("download-invalid-content-range", "bytes=0-0");
               Require_Invalid_Interval
                 ("download-unsolicited-content-range");
            end Check_High_Level_Downloads;
         begin
            begin
               Check_High_Level_Downloads;
            exception
               when others =>
                  Cleanup;
                  raise;
            end;
            Cleanup;
         end;
         declare
            Parameters : Low_Level.Upload_Part_Copy_Parameters;
         begin
            Parameters.Upload_ID := US.To_Unbounded_String ("copy-upload");
            Parameters.Copy_Source :=
              US.To_Unbounded_String ("source-bucket/source-key");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            declare
               Result : constant Upload_Part_Copy_Result :=
                 Transfers.Upload_Part_Copy
                   (HTTP, Origin, "example-bucket", "copy-part-sync",
                    Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /=
                 Upload_Part_Copy_Response_Available
                 or else Result.Disposition /= Published
                 or else Result.Failure /= No_Failure
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.Response.Kind /= Low_Level.Part_Copied
                 or else Result.Response.Status /= 200
                 or else US.To_String
                   (Result.Response.Result.Copy_Source_Version_ID) /=
                     "source-version"
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
                 or else US.To_String
                   (Result.Response.Result.Copy_Part.Entity_Tag) /=
                     """copied-part"""
               then
                  raise Program_Error with
                    "typed composable UploadPartCopy result mismatch";
               end if;
            end;

            declare
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               declare
                  Result : constant Upload_Part_Copy_Result :=
                    Transfers.Upload_Part_Copy
                      (HTTP, Origin, "example-bucket", "copy-part-cancelled",
                       Parameters, Identity, Timeout => 5.0,
                       Token => Stop'Access);
               begin
                  if Result.Kind /= Upload_Part_Copy_Exchange_Failed
                    or else Result.Disposition /=
                      Cancelled_Before_Publication
                    or else Result.Failure /= Client_API.Cancelled
                    or else Result.Admission /= HTTP_Client.Not_Admitted
                  then
                     raise Program_Error with
                       "pre-admission UploadPartCopy cancellation mismatch";
                  end if;
               end;
            end;

            Parameters.Request_Payer := US.Null_Unbounded_String;
            declare
               --  Copy-part parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Upload_Part_Copy_Operation :=
                 Upload_Part_Copy
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "copy-part-restart-one", Parameters, Identity,
                    HTTP_Client.Deadline_After (5.0));
               Result : Upload_Part_Copy_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 Upload_Part_Copy_Response_Available
                 or else Result.Disposition /= Published
               then
                  raise Program_Error with
                    "direct UploadPartCopy first completion mismatch";
               end if;
               Upload_Part_Copy
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "copy-part-restart-two",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 Upload_Part_Copy_Response_Available
                 or else Result.Disposition /= Published
               then
                  raise Program_Error with
                    "direct UploadPartCopy restart mismatch";
               end if;

               for Case_Index in 1 .. 2 loop
                  Upload_Part_Copy
                    (HTTP'Access,
                     Origin,
                     "example-bucket",
                     (if Case_Index = 1
                      then "copy-part-invalid-duplicate"
                      else "copy-part-invalid-charged"),
                     Parameters,
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     Operation => Operation);
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /= Upload_Part_Copy_Exchange_Failed
                    or else Result.Disposition /= Outcome_Unknown
                    or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                    or else Result.Admission /= HTTP_Client.Response_Observed
                  then
                     raise Program_Error with
                       "invalid complete UploadPartCopy response accepted";
                  end if;
               end loop;
            end;

            declare
               Result : constant Upload_Part_Copy_Result :=
                 Transfers.Upload_Part_Copy
                   (HTTP, Origin, "example-bucket", "copy-part-rejected",
                    Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /=
                 Upload_Part_Copy_Response_Available
                 or else Result.Disposition /=
                   Definitely_Not_Published
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.Response.Kind /= Low_Level.Copy_Part_Rejected
                 or else Result.Response.Status /= 403
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "typed UploadPartCopy rejection mismatch";
               end if;
            end;
         end;
         declare
            Options : Low_Level.Copy_Object_Parameters;
         begin
            Options.Copy_Source_If_Match :=
              US.To_Unbounded_String ("""source-etag""");
            Options.Request_Payer := US.To_Unbounded_String ("requester");
            declare
               Result : constant Copy_Result :=
                 Transfers.Copy_Object
                   (HTTP, Origin, "source-bucket", "source key+%25",
                    "example-bucket", "copied object+%25", Options, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /= Copy_Response_Available
                 or else Result.Disposition /= Published
                 or else Result.Failure /= No_Failure
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.Response.Kind /= Low_Level.Object_Copied
                 or else Result.Response.Status /= 200
                 or else US.To_String
                   (Result.Response.Result.Copy_Result.Last_Modified) /=
                   "2026-08-21T17:00:00.000Z"
                 or else US.To_String (Result.Response.Result.Version_ID) /=
                   "destination-version"
                 or else US.To_String
                   (Result.Response.Result.Copy_Source_Version_ID) /=
                   "source-version"
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
                 or else US.To_String
                   (Result.Response.Result.Copy_Result.Entity_Tag) /=
                     """high-level-copy"""
               then
                  raise Program_Error with
                    "typed composable CopyObject result mismatch";
               end if;
            end;
         end;
         declare
            Options : Low_Level.Copy_Object_Parameters;
            Stop : aliased Flyology.Cancellation.Token;
         begin
            Stop.Request;
            declare
               Result : constant Copy_Result := Transfers.Copy_Object
                 (HTTP, Origin, "source-bucket", "source-key",
                  "example-bucket", "copy-cancelled", Options, Identity,
                  Timeout => 5.0, Token => Stop'Access);
            begin
               if Result.Kind /= Copy_Exchange_Failed
                 or else Result.Disposition /=
                   Cancelled_Before_Publication
                 or else Result.Failure /= Client_API.Cancelled
                 or else Result.Admission /= HTTP_Client.Not_Admitted
               then
                  raise Program_Error with
                    "pre-admission CopyObject cancellation mismatch";
               end if;
            end;
         end;
         declare
            Options : Low_Level.Copy_Object_Parameters;
            --  Copy parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
            Operation : Copy_Operation := Copy_Object
              (Set'Access, HTTP'Access, Origin, "source-bucket", "source-key",
               "example-bucket", "copy-restart-one", Options, Identity,
               HTTP_Client.Deadline_After (5.0));
            Result : Copy_Result;
         begin
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= Copy_Response_Available
              or else Result.Disposition /= Published
            then
               raise Program_Error with
                 "direct CopyObject first completion mismatch";
            end if;
            Copy_Object
              (HTTP'Access,
               Origin,
               "source-bucket",
               "source-key",
               "example-bucket",
               "copy-restart-two",
               Options,
               Identity,
               HTTP_Client.Deadline_After (5.0),
               Operation => Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= Copy_Response_Available
              or else Result.Disposition /= Published
            then
               raise Program_Error with
                 "direct CopyObject restart mismatch";
            end if;
            for Case_Index in 1 .. 3 loop
               Copy_Object
                 (HTTP'Access,
                  Origin,
                  "source-bucket",
                  "source-key",
                  "example-bucket",
                  (case Case_Index is
                     when 1 => "copy-invalid-duplicate",
                     when 2 => "copy-invalid-empty",
                     when others => "copy-invalid-charged"),
                  Options,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Copy_Exchange_Failed
                 or else Result.Disposition /= Outcome_Unknown
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                 or else Result.Admission /= HTTP_Client.Response_Observed
               then
                  raise Program_Error with
                    "invalid complete CopyObject response was accepted";
               end if;
            end loop;
         end;
         declare
            Result : constant Transfers.Copy_Outcome :=
              Transfers.Copy_Object
                (HTTP, Origin, "source-bucket", "source-key",
                 "example-bucket", "copy-rejected", Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Copy_Rejected
              or else Result.Status /= 412
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
            then
               raise Program_Error with
                 "high-level CopyObject rejection mismatch";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Transfers.Copy_Outcome :=
                    Transfers.Copy_Object
                      (HTTP, Origin, "source-bucket",
                       String'(1 .. 8_192 => 'x'), "example-bucket",
                       "copy-too-large", Identity, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "oversized high-level CopyObject source was accepted";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Transfers.Copy_Outcome :=
                    Transfers.Copy_Object
                      (HTTP, Origin, "source/bucket", "source-key",
                       "example-bucket", "copy-invalid-source", Identity,
                       Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "ambiguous high-level CopyObject source was accepted";
            end if;
         end;
         declare
            Result : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "head object+%25",
                 Identity, Version_ID => "version one",
                 If_Match => """expected-etag""", Checksum_Mode => True,
                 Timeout => 5.0,
                 If_Modified_Since =>
                   "Fri, 21 Aug 2026 16:00:00 GMT",
                 If_None_Match => """other-etag""",
                 If_Unmodified_Since =>
                   "Fri, 21 Aug 2026 18:00:00 GMT",
                 Byte_Range_Header => "bytes=1-4",
                 Response_Cache_Control => "no-cache",
                 Response_Content_Disposition => "attachment",
                 Response_Content_Encoding => "gzip",
                 Response_Content_Language => "en-CA",
                 Response_Content_Type => "application/test",
                 Response_Expires => "Fri, 21 Aug 2026 18:00:00 GMT",
                 Part_Number => (Is_Set => True, Value => 3));
         begin
            if Result.Kind /= Transfers.Object_Found
              or else Result.Status /= 200
              or else Result.Bytes /= 4
              or else US.To_String (Result.Entity_Tag) /= """head-etag"""
              or else US.To_String (Result.Last_Modified) /=
                "Fri, 21 Aug 2026 17:00:00 GMT"
              or else US.To_String (Result.Content_Type) /=
                "application/test"
              or else US.To_String (Result.Version_ID) /= "head-version"
              or else US.To_String (Result.Checksum_SHA256) /=
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=-3"
              or else US.To_String (Result.Checksum_Type) /= "COMPOSITE"
              or else not Result.Details.Parts_Count.Is_Set
              or else Result.Details.Parts_Count.Value /= 3
              or else US.Length (Result.Details.Content_Range) /= 0
            then
               raise Program_Error with "high-level HeadObject mismatch";
            end if;
         end;
         declare
            Result : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "head-policy", Identity,
                 Request_Payer => "requester",
                 Expected_Bucket_Owner => "123456789012",
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Object_Found
              or else Result.Status /= 200
              or else Result.Bytes /= 42
            then
               raise Program_Error with
                 "high-level HeadObject owner/payer mismatch";
            end if;
         end;
         declare
            Result : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "head-missing", Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Head_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "HTTP404"
              or else US.To_String (Result.Error.Request_ID) /=
                "head-request"
              or else US.To_String (Result.Error.Host_ID) /= "head-host"
            then
               raise Program_Error with
                 "bodyless high-level HeadObject rejection mismatch";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Transfers.Head_Outcome :=
                    Transfers.Head_Object
                      (HTTP, Origin, "example-bucket",
                       "head-invalid-checksum", Identity, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "invalid HeadObject checksum was accepted";
            end if;
         end;
         for Index in 1 .. 2 loop
            declare
               Key : constant String :=
                 (if Index = 1 then "head-duplicate-header"
                  else "head-transfer-encoding");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Transfers.Head_Outcome :=
                       Transfers.Head_Object
                         (HTTP, Origin, "example-bucket", Key,
                          Identity, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with
                    "invalid HeadObject singleton/framing was accepted";
               end if;
            end;
         end loop;
         declare
            Parameters : Low_Level.Head_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "typed-head", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Head_Object_Outcome :=
              Low_Level.Execute_Head_Object
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Found
              or else Result.Status /= 200
              or else Result.Result.Content_Length /= 7
              or else US.To_String (Result.Result.Entity_Tag) /=
                """typed-head"""
              or else Natural (Result.Result.Metadata.Length) /= 2
              or else US.To_String
                (Result.Result.Metadata.First_Element.Name) /= "project"
              or else not Result.Result.Parts_Count.Is_Set
              or else Result.Result.Parts_Count.Value /= 3
              or else US.To_String (Result.Result.Server_Side_Encryption) /=
                "aws:backup"
              or else US.To_String (Result.Result.Storage_Class) /=
                "AWS_BACKUP_WARM"
            then
               raise Program_Error with "typed HeadObject result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
         begin
            Parameters.If_Match :=
              US.To_Unbounded_String ("""expected-etag""");
            Parameters.Version_ID :=
              US.To_Unbounded_String ("version one");
            Parameters.Checksum_Mode := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-get", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Response : HTTP_Client.Response :=
                 Low_Level.Execute_Get_Object
                   (HTTP, Prepared, Timeout => 5.0);
               Result : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Response_Head (Response);
               Received : US.Unbounded_String;
               Buffer : Stream_Element_Array (1 .. 3);
               Last : Stream_Element_Offset;
               Finished : Boolean := False;
            begin
               if Result.Kind /= Low_Level.Object_Opened
                 or else Result.Status /= 206
                 or else not Result.Result.Content_Length.Is_Set
                 or else Result.Result.Content_Length.Value /= 7
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """typed-get"""
                 or else US.To_String (Result.Result.Content_Range) /=
                   "bytes 1-7/9"
                 or else Natural (Result.Result.Metadata.Length) /= 2
                 or else US.To_String
                   (Result.Result.Metadata.First_Element.Name) /= "project"
                 or else US.To_String (Result.Result.Checksum_Type) /=
                   "COMPOSITE"
                 or else US.To_String (Result.Result.Checksum_SHA256) /=
                   "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=-3"
                 or else US.To_String
                   (Result.Result.Server_Side_Encryption) /= "aws:backup"
                 or else US.To_String (Result.Result.Storage_Class) /=
                   "AWS_BACKUP_WARM"
               then
                  raise Program_Error with "typed GetObject head mismatch";
               end if;
               while not Finished loop
                  HTTP_Client.Read_Body
                    (Response, Buffer, Last, Finished);
                  for Index in Buffer'First .. Last loop
                     US.Append (Received, Character'Val (Buffer (Index)));
                  end loop;
               end loop;
               if US.To_String (Received) /= "getdata" then
                  raise Program_Error with "typed GetObject body mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
         begin
            Parameters.Checksum_Mode := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-get-full", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Response : HTTP_Client.Response :=
                 Low_Level.Execute_Get_Object
                   (HTTP, Prepared, Timeout => 5.0);
               Result : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Response_Head (Response);
               Received : US.Unbounded_String;
               Buffer : Stream_Element_Array (1 .. 3);
               Last : Stream_Element_Offset;
               Finished : Boolean := False;
            begin
               if Result.Kind /= Low_Level.Object_Opened
                 or else Result.Status /= 200
                 or else US.To_String (Result.Result.Checksum_Type) /=
                   "FULL_OBJECT"
                 or else US.To_String
                   (Result.Result.Checksum_CRC64NVME) /= "AAAAAAAAAAA="
               then
                  raise Program_Error with
                    "full-object GetObject checksum mismatch";
               end if;
               while not Finished loop
                  HTTP_Client.Read_Body
                    (Response, Buffer, Last, Finished);
                  for Index in Buffer'First .. Last loop
                     US.Append (Received, Character'Val (Buffer (Index)));
                  end loop;
               end loop;
               if US.To_String (Received) /= "full" then
                  raise Program_Error with
                    "full-object GetObject body mismatch";
               end if;
            end;
         end;
         declare
            procedure Require_Valid_Full_Object (Index : Positive) is
               Parameters : Low_Level.Get_Object_Parameters;
            begin
               Parameters.Checksum_Mode := True;
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Get_Object
                      (Origin, Low_Level.Path_Style, "example-bucket",
                       "read-full-" & Decimal (Index), Parameters, Identity,
                       "us-east-1", "20130524T000000Z");
                  Response : HTTP_Client.Response :=
                    Low_Level.Execute_Get_Object
                      (HTTP, Prepared, Timeout => 5.0);
                  Result : constant Low_Level.Get_Object_Head_Outcome :=
                    Low_Level.Decode_Get_Object_Response_Head (Response);
                  Received : US.Unbounded_String;
                  Buffer : Stream_Element_Array (1 .. 3);
                  Last : Stream_Element_Offset;
                  Finished : Boolean := False;

                  function Projected_Checksum return String is
                  begin
                     case Index is
                        when 1 =>
                           return US.To_String (Result.Result.Checksum_CRC32);
                        when 2 =>
                           return US.To_String (Result.Result.Checksum_CRC32C);
                        when 3 =>
                           return US.To_String
                             (Result.Result.Checksum_CRC64NVME);
                        when 4 =>
                           return US.To_String (Result.Result.Checksum_SHA1);
                        when 5 =>
                           return US.To_String (Result.Result.Checksum_SHA256);
                        when 6 =>
                           return US.To_String (Result.Result.Checksum_SHA512);
                        when 7 =>
                           return US.To_String (Result.Result.Checksum_MD5);
                        when 8 =>
                           return US.To_String
                             (Result.Result.Checksum_XXHASH64);
                        when 9 =>
                           return US.To_String
                             (Result.Result.Checksum_XXHASH3);
                        when 10 =>
                           return US.To_String
                             (Result.Result.Checksum_XXHASH128);
                        when others =>
                           return "";
                     end case;
                  end Projected_Checksum;
               begin
                  if Result.Kind /= Low_Level.Object_Opened
                    or else Result.Status /= 200
                    or else US.To_String (Result.Result.Checksum_Type) /=
                      "FULL_OBJECT"
                    or else Projected_Checksum /=
                      US.To_String (Read_Checksums (Index).Value)
                  then
                     raise Program_Error with
                       "ordinary FULL_OBJECT GetObject mismatch" &
                         Positive'Image (Index);
                  end if;
                  while not Finished loop
                     HTTP_Client.Read_Body
                       (Response, Buffer, Last, Finished);
                     for Offset in Buffer'First .. Last loop
                        US.Append
                          (Received, Character'Val (Buffer (Offset)));
                     end loop;
                  end loop;
                  if US.To_String (Received) /= "full" then
                     raise Program_Error with
                       "ordinary FULL_OBJECT GetObject body mismatch";
                  end if;
               end;
            end Require_Valid_Full_Object;

            procedure Reject_Invalid_Get
              (Key : String; Message : String)
            is
               Parameters : Low_Level.Get_Object_Parameters;
            begin
               Parameters.Checksum_Mode := True;
               declare
                  Prepared : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Get_Object
                      (Origin, Low_Level.Path_Style, "example-bucket", Key,
                       Parameters, Identity, "us-east-1",
                       "20130524T000000Z");
                  Response : HTTP_Client.Response :=
                    Low_Level.Execute_Get_Object
                      (HTTP, Prepared, Timeout => 5.0);
                  Raised : Boolean := False;
               begin
                  begin
                     declare
                        Ignored : constant
                          Low_Level.Get_Object_Head_Outcome :=
                            Low_Level.Decode_Get_Object_Response_Head
                              (Response);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Low_Level.Invalid_Response => Raised := True;
                  end;
                  if not Raised then
                     raise Program_Error with Message;
                  end if;
               end;
            end Reject_Invalid_Get;
         begin
            for Index in Read_Checksums'Range loop
               Require_Valid_Full_Object (Index);
               Reject_Invalid_Get
                 ("read-malformed-" & Decimal (Index),
                  "GetObject accepted malformed FULL_OBJECT checksum" &
                    Positive'Image (Index));
               Reject_Invalid_Get
                 ("read-wrong-type-" & Decimal (Index),
                  "GetObject accepted raw checksum as COMPOSITE" &
                    Positive'Image (Index));
            end loop;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "typed-get-missing", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (HTTP, Prepared, Timeout => 5.0);
            Result : constant Low_Level.Get_Object_Head_Outcome :=
              Low_Level.Decode_Get_Object_Response_Head (Response);
         begin
            if Result.Kind /= Low_Level.Get_Object_Rejected
              or else Result.Status /= 304
              or else US.To_String (Result.Error.Code) /= "HTTP304"
              or else US.To_String (Result.Error.Request_ID) /=
                "get-request"
              or else US.To_String (Result.Error.Host_ID) /= "get-host"
              or else not HTTP_Client.Body_Complete (Response)
            then
               raise Program_Error with
                 "typed GetObject bodyless rejection mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "typed-get-invalid", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (HTTP, Prepared, Timeout => 5.0);
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Get_Object_Head_Outcome :=
                    Low_Level.Decode_Get_Object_Response_Head (Response);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "typed GetObject accepted an invalid checksum";
            end if;
         end;
         declare
            procedure Reject_Invalid_Get
              (Key : String; Message : String) is
               Parameters : Low_Level.Get_Object_Parameters;
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Origin, Low_Level.Path_Style, "example-bucket", Key,
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Response : HTTP_Client.Response :=
                 Low_Level.Execute_Get_Object
                   (HTTP, Prepared, Timeout => 5.0);
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Object_Head_Outcome :=
                         Low_Level.Decode_Get_Object_Response_Head (Response);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Reject_Invalid_Get;
         begin
            Reject_Invalid_Get
              ("typed-get-multiple",
               "GetObject accepted multiple checksum algorithm headers");
            Reject_Invalid_Get
              ("typed-get-illegal-pair",
               "GetObject accepted composite CRC64NVME metadata");
            Reject_Invalid_Get
              ("typed-get-inferred-illegal-pair",
               "GetObject inferred composite CRC64NVME without " &
                 "ChecksumType");
            Reject_Invalid_Get
              ("typed-get-type-only",
               "GetObject accepted checksum type without an algorithm");
         end;
         declare
            Value : Tags.Tag_Set;
         begin
            declare
               Stop : aliased Flyology.Cancellation.Token;
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Buckets.Delete_Tags_Outcome :=
                       Buckets.Delete_Tags
                         (HTTP, Origin, "example-bucket", Identity,
                          Timeout => 5.0, Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               begin
                  declare
                     Ignored : constant Buckets.Delete_Tags_Outcome :=
                       Buckets.Delete_Tags
                         (HTTP, Origin, "example-bucket", Identity,
                          Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Cancelled or else not Timed_Out then
                  raise Program_Error with
                    "DeleteBucketTagging ignored cancellation/deadline";
               end if;
            end;
            Value.Append
              (Tags.Tag'
                 (Key   => US.To_Unbounded_String ("project"),
                  Value => US.To_Unbounded_String ("flyology")));
            declare
               Set : aliased Operations.Completion_Set (3);
               Put_Parameters : constant
                 Low_Level.Put_Bucket_Tagging_Parameters :=
                 (others => <>);
               Operation : Put_Bucket_Tagging_Operation :=
                 Put_Tags
                   (Set'Access, HTTP'Access, Origin, "example-bucket", Value,
                    Put_Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Put_Result : Put_Bucket_Tagging_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Put_Result);
               if Put_Result.Kind /=
                   Put_Bucket_Tagging_Response_Available
                 or else Put_Result.Disposition /=
                   Bucket_Tag_Mutation_Completed
                 or else Put_Result.Failure /= No_Failure
                 or else Put_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Put_Result.Response.Kind /=
                   Low_Level.Bucket_Tags_Replaced
               then
                  raise Program_Error with
                    "scoped PutBucketTagging socket mismatch";
               end if;
               Put_Tags
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  Value,
                  Put_Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Put_Result);
               if Put_Result.Kind /=
                   Put_Bucket_Tagging_Response_Available
                 or else Put_Result.Disposition /=
                   Bucket_Tag_Mutation_Definitely_Not_Applied
                 or else Put_Result.Failure /= Invalid_Request
                 or else Put_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Put_Result.Response.Kind /=
                   Low_Level.Put_Bucket_Tagging_Rejected
                 or else US.To_String (Put_Result.Response.Error.Code) /=
                   "InvalidTag"
               then
                  raise Program_Error with
                    "scoped PutBucketTagging restart mismatch";
               end if;
            end;
            declare
               Set : aliased Operations.Completion_Set (3);
               Parameters : constant
                 Low_Level.Get_Bucket_Tagging_Parameters :=
                 (others => <>);
               Operation : Get_Bucket_Tagging_Operation :=
                 Get_Tags
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Get_Result : Get_Bucket_Tagging_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Get_Result);
               if Get_Result.Kind /=
                   Get_Bucket_Tagging_Response_Available
                 or else Get_Result.Failure /= No_Failure
                 or else Get_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Get_Result.Response.Kind /=
                   Low_Level.Bucket_Tags_Found
                 or else Get_Result.Response.Result.Value /= Value
               then
                  raise Program_Error with
                    "scoped GetBucketTagging socket mismatch";
               end if;
               Get_Tags
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Get_Result);
               if Get_Result.Kind /=
                   Get_Bucket_Tagging_Response_Available
                 or else Get_Result.Failure /= No_Failure
                 or else Get_Result.Response.Kind /=
                   Low_Level.Bucket_Tags_Found
                 or else Get_Result.Response.Result.Value /= Value
               then
                  raise Program_Error with
                    "scoped GetBucketTagging restart mismatch";
               end if;
            end;
            declare
               Set : aliased Operations.Completion_Set (3);
               Parameters : constant
                 Low_Level.Delete_Bucket_Tagging_Parameters :=
                 (others => <>);
               Operation : Delete_Bucket_Tagging_Operation :=
                 Delete_Tags
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Delete_Result : Delete_Bucket_Tagging_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Delete_Result);
               if Delete_Result.Kind /=
                   Delete_Bucket_Tagging_Response_Available
                 or else Delete_Result.Disposition /=
                   Bucket_Tag_Mutation_Completed
                 or else Delete_Result.Failure /= No_Failure
                 or else Delete_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Delete_Result.Response.Kind /=
                   Low_Level.Bucket_Tags_Deleted
               then
                  raise Program_Error with
                    "scoped DeleteBucketTagging socket mismatch";
               end if;
               Delete_Tags
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Delete_Result);
               if Delete_Result.Kind /=
                   Delete_Bucket_Tagging_Response_Available
                 or else Delete_Result.Disposition /=
                   Bucket_Tag_Mutation_Completed
                 or else Delete_Result.Failure /= No_Failure
                 or else Delete_Result.Response.Kind /=
                   Low_Level.Bucket_Tags_Deleted
               then
                  raise Program_Error with
                    "scoped DeleteBucketTagging restart mismatch";
               end if;
            end;
            declare
               Get_Result : constant Buckets.Get_Tags_Outcome :=
                 Buckets.Get_Tags
                   (HTTP, Origin, "example-bucket", Identity,
                    Timeout => 5.0);
               Delete_Result : constant Buckets.Delete_Tags_Outcome :=
                 Buckets.Delete_Tags
                   (HTTP, Origin, "example-bucket", Identity,
                    Timeout => 5.0);
            begin
               if Get_Result.Kind /= Buckets.Get_Tags_Rejected
                 or else US.To_String (Get_Result.Error.Code) /=
                   "NoSuchTagSet"
                 or else Delete_Result.Kind /= Buckets.Tags_Deleted
               then
                  raise Program_Error with
                    "synchronous composable bucket-tag mapping mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Create_Multipart_Parameters;
            --  Multipart parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
            Operation : Create_Multipart_Operation :=
              Create_Multipart_Upload
                (Set'Access, HTTP'Access, Origin, "example-bucket",
                 "scoped-create", Parameters, Identity,
                 --  Test/reference value: reuse this corpus's established
                 --  loopback deadline; it does not set production policy.
                 HTTP_Client.Deadline_After (5.0));
            Result : Create_Multipart_Result;
         begin
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            if Result.Kind /= Create_Multipart_Response_Available
              or else Result.Disposition /= Multipart_Upload_Created
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /= Low_Level.Created
              or else US.To_String (Result.Response.Result.Upload_ID) /=
                "scoped-create-id"
            then
               raise Program_Error with
                 "scoped CreateMultipartUpload success/certainty mismatch";
            end if;
         end;
         declare
            Stop : aliased Flyology.Cancellation.Token;
            Parameters : Low_Level.Create_Multipart_Parameters;
         begin
            Stop.Request;
            declare
               --  Test/reference value: retain the established five-second
               --  loopback budget; this does not affect the public default.
               Result : constant Create_Multipart_Result :=
                 Transfers.Create_Multipart_Upload
                   (HTTP, Origin, "example-bucket", "create-cancelled",
                    Parameters, Identity, Timeout => 5.0,
                    Token => Stop'Access);
            begin
               if Result.Kind /= Create_Multipart_Exchange_Failed
                 or else Result.Disposition /=
                   Creation_Cancelled_Before_Admission
                 or else Result.Failure /= Client_API.Cancelled
                 or else Result.Admission /= HTTP_Client.Not_Admitted
               then
                  raise Program_Error with
                    "pre-admission CreateMultipartUpload cancellation " &
                    "mismatch";
               end if;
            end;
         end;
         declare
            Create_Parameters : Low_Level.Create_Multipart_Parameters;
            List_Parameters : Low_Level.List_Multipart_Uploads_Parameters;
            Result : constant Create_Multipart_Result :=
              Transfers.Create_Multipart_Upload
                (HTTP, Origin, "example-bucket", "create-lost",
                 Create_Parameters, Identity, Timeout => 5.0);
         begin
            if Result.Kind /= Create_Multipart_Exchange_Failed
              or else Result.Disposition /= Creation_Outcome_Unknown
              or else Result.Admission /= HTTP_Client.Possibly_Admitted
            then
               raise Program_Error with
                 "lost CreateMultipartUpload was classified conclusively";
            end if;
            List_Parameters.Prefix := US.To_Unbounded_String ("create-lost");
            declare
               Listed : constant Low_Level.List_Multipart_Uploads_Outcome :=
                 Transfers.List_Multipart_Uploads_Page
                   (HTTP, Origin, "example-bucket", List_Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Listed.Kind /= Low_Level.Multipart_Uploads_Listed
                 or else Natural (Listed.Result.Listing.Uploads.Length) /= 1
                 or else US.To_String
                   (Listed.Result.Listing.Uploads.First_Element.Key) /=
                     "create-lost"
                 or else US.To_String
                   (Listed.Result.Listing.Uploads.First_Element.Upload_ID) /=
                     "lost-create-id"
               then
                  raise Program_Error with
                    "CreateMultipartUpload lost-response reconciliation " &
                    "failed";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Create_Multipart_Parameters;
         begin
            Parameters.Server_Side_Encryption :=
              US.To_Unbounded_String ("aws:kms");
            Parameters.SSE_KMS_Key_ID := US.To_Unbounded_String ("kms-key");
            Parameters.SSE_KMS_Encryption_Context :=
              US.To_Unbounded_String ("e30=");
            Parameters.Bucket_Key_Enabled := (Is_Set => True, Value => True);
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Checksum_Algorithm :=
              US.To_Unbounded_String ("CRC32C");
            Parameters.Checksum_Type :=
              US.To_Unbounded_String ("FULL_OBJECT");
            declare
               Result : constant Create_Multipart_Result :=
                 Transfers.Create_Multipart_Upload
                   (HTTP, Origin, "example-bucket", "object key", Parameters,
                    Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Create_Multipart_Response_Available
                 or else Result.Disposition /= Multipart_Upload_Created
                 or else Result.Response.Kind /= Low_Level.Created
                 or else US.To_String (Result.Response.Result.Upload_ID) /=
                   "socket-upload"
                 or else US.To_String
                   (Result.Response.Result.Abort_Rule_ID) /=
                   "cleanup"
                 or else US.To_String
                   (Result.Response.Result.Server_Side_Encryption) /= "aws:kms"
                 or else US.To_String
                   (Result.Response.Result.SSE_KMS_Key_ID) /=
                   "kms-key"
                 or else US.To_String
                   (Result.Response.Result.SSE_KMS_Encryption_Context) /=
                     "e30="
                 or else not
                   Result.Response.Result.Bucket_Key_Enabled.Is_Set
                 or else not Result.Response.Result.Bucket_Key_Enabled.Value
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /=
                   "requester"
                 or else US.To_String
                   (Result.Response.Result.Checksum_Algorithm) /=
                   "CRC32C"
                 or else US.To_String
                   (Result.Response.Result.Checksum_Type) /=
                   "FULL_OBJECT"
               then
                  raise Program_Error with
                    "socket CreateMultipartUpload result mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Create_Multipart_Parameters;
            procedure Require_Invalid (Key, Message : String) is
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Create_Multipart_Outcome :=
                       Transfers.Create_Multipart_Upload
                         (HTTP, Origin, "example-bucket", Key, Parameters,
                          Identity, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Require_Invalid;
         begin
            Require_Invalid
              ("create-wrong-bucket",
               "CreateMultipartUpload accepted wrong response bucket");
            Require_Invalid
              ("create-wrong-key",
               "CreateMultipartUpload accepted wrong response key");
            Require_Invalid
              ("create-duplicate",
               "CreateMultipartUpload accepted duplicate response header");
            Require_Invalid
              ("create-empty",
               "CreateMultipartUpload accepted present-empty response header");
            Require_Invalid
              ("create-bool",
               "CreateMultipartUpload accepted noncanonical boolean header");
         end;
         declare
            Completion : Multipart.Complete_Multipart_Upload_Request;
         begin
            declare
               Parameters : Low_Level.Upload_Part_Parameters;
               Source : Upload_Source (Upload_Payload'Access);
            begin
               Parameters.Upload_ID :=
                 US.To_Unbounded_String ("socket-upload");
               Parameters.Payload_SHA256 := US.To_Unbounded_String
                 (SigV4.SHA256_Hex (Upload_Payload));
               declare
                  Uploaded : constant Low_Level.Upload_Part_Outcome :=
                    Transfers.Upload_Part
                      (HTTP, Origin, "example-bucket", "object key",
                       Parameters, Source, Identity, Timeout => 5.0);
               begin
                  if Uploaded.Kind /= Low_Level.Part_Uploaded
                    or else US.To_String (Uploaded.Result.Entity_Tag) /=
                      """socket-part"""
                  then
                     raise Program_Error with
                       "socket UploadPart result mismatch";
                  end if;
               end;
            end;
            Completion.Parts.Append
              (Multipart.Completed_Part'
                 (Number => 1,
                  Entity_Tag => US.To_Unbounded_String ("""part"""),
                  others => <>));
            declare
               Parameters : Low_Level.Complete_Multipart_Parameters;
               --  Completion parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
               Operation : Complete_Multipart_Operation :=
                 Complete_Multipart_Upload
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "object key", "socket-upload", Completion, Parameters,
                    Identity, HTTP_Client.Deadline_After (5.0));
               Result : Multipart_Completion_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 Complete_Multipart_Response_Available
                 or else Result.Disposition /= Multipart_Completed
                 or else Result.Response.Kind /= Low_Level.Completed
                 or else US.To_String (Result.Response.Result.Entity_Tag) /=
                   """whole"""
               then
                  raise Program_Error with
                    "composed CompleteMultipartUpload result mismatch";
               end if;
               Complete_Multipart_Upload
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  "object key",
                  "socket-upload",
                  Completion,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 Complete_Multipart_Response_Available
                 or else Result.Disposition /=
                   Completion_Outcome_Unknown
                 or else Result.Response.Kind /= Low_Level.Complete_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "InternalError"
               then
                  raise Program_Error with
                    "composed embedded multipart error mismatch";
               end if;
               declare
                  Stop : aliased Flyology.Cancellation.Token;
               begin
                  Stop.Request;
                  declare
                     Cancelled : constant Multipart_Abort_Result :=
                       Transfers.Abort_Multipart_Upload
                         (HTTP, Origin, "example-bucket", "object key",
                          "socket-upload", Identity, Timeout => 5.0,
                          Token => Stop'Access);
                  begin
                     if Cancelled.Kind /=
                       Abort_Multipart_Exchange_Failed
                       or else Cancelled.Disposition /=
                         Abort_Cancelled_Before_Admission
                       or else Cancelled.Admission /= HTTP_Client.Not_Admitted
                     then
                        raise Program_Error with
                          "pre-admission AbortMultipartUpload cancellation " &
                          "mismatch";
                     end if;
                  end;
               end;
               declare
                  Abort_Parameters : constant
                    Low_Level.Abort_Multipart_Parameters :=
                      (others => US.Null_Unbounded_String);
                  --  Abort parent, HTTP exchange, and one transport child.
                  Abort_Set : aliased Operations.Completion_Set (3);
                  Abort_Operation : Abort_Multipart_Operation :=
                    Abort_Multipart_Upload
                      (Abort_Set'Access, HTTP'Access, Origin,
                       "example-bucket", "object key", "socket-upload",
                       Abort_Parameters, Identity,
                       HTTP_Client.Deadline_After (5.0));
                  Abort_Result : Multipart_Abort_Result;
               begin
                  Operations.Wait_All (Abort_Set);
                  Finish (Abort_Operation, Abort_Result);
                  if Abort_Result.Kind /=
                    Abort_Multipart_Response_Available
                    or else Abort_Result.Disposition /=
                      Multipart_Aborted
                    or else Abort_Result.Response.Kind /= Low_Level.Aborted
                  then
                     raise Program_Error with
                       "composed AbortMultipartUpload result mismatch";
                  end if;
                  Abort_Multipart_Upload
                    (HTTP'Access,
                     Origin,
                     "example-bucket",
                     "object key",
                     "socket-upload",
                     Abort_Parameters,
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     Operation => Abort_Operation);
                  Operations.Wait_All (Abort_Set);
                  Finish (Abort_Operation, Abort_Result);
                  if Abort_Result.Kind /=
                    Abort_Multipart_Response_Available
                    or else Abort_Result.Disposition /=
                      Abort_Outcome_Unknown
                    or else Abort_Result.Response.Kind /=
                      Low_Level.Abort_Rejected
                    or else US.To_String
                      (Abort_Result.Response.Error.Code) /= "NoSuchUpload"
                  then
                     raise Program_Error with
                       "composed AbortMultipartUpload rejection mismatch";
                  end if;
                  Abort_Multipart_Upload
                    (HTTP'Access,
                     Origin,
                     "example-bucket",
                     "object key",
                     "socket-upload",
                     Abort_Parameters,
                     Identity,
                     HTTP_Client.Deadline_After (5.0),
                     Operation => Abort_Operation);
                  Operations.Wait_All (Abort_Set);
                  Finish (Abort_Operation, Abort_Result);
                  if Abort_Result.Kind /=
                    Abort_Multipart_Exchange_Failed
                    or else Abort_Result.Disposition /=
                      Abort_Outcome_Unknown
                    or else Abort_Result.HTTP_Result /=
                      HTTP_Client.Response_Invalid
                    or else Abort_Result.Admission /=
                      HTTP_Client.Response_Observed
                  then
                     raise Program_Error with
                       "composed AbortMultipartUpload physical header " &
                       "validation mismatch";
                  end if;
               end;
            end;
         end;
         declare
            Parameters : Low_Level.List_Object_Versions_Parameters;
         begin
            Parameters.Delimiter := US.To_Unbounded_String ("/");
            Parameters.Has_Delimiter := True;
            Parameters.URL_Encoding := True;
            Parameters.Key_Marker := US.To_Unbounded_String ("logs/a");
            Parameters.Has_Key_Marker := True;
            Parameters.Max_Keys := 3;
            Parameters.Has_Max_Keys := True;
            Parameters.Prefix := US.To_Unbounded_String ("logs/");
            Parameters.Has_Prefix := True;
            Parameters.Version_ID_Marker := US.To_Unbounded_String ("v+1");
            Parameters.Has_Version_ID_Marker := True;
            Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Include_Restore_Status := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Object_Versions
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Parameters, Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.List_Object_Versions_Outcome :=
                 Low_Level.Execute_List_Object_Versions
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Listed
                 or else Result.Status /= 200
                 or else Natural (Result.Result.Listing.Versions.Length) /= 1
                 or else Natural
                   (Result.Result.Listing.Delete_Markers.Length) /= 1
                 or else Natural
                   (Result.Result.Listing.Common_Prefixes.Length) /= 1
                 or else Result.Result.Listing.Versions.First_Element.Size /=
                   4_294_967_297
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "typed ListObjectVersions socket success mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Objects.List_Versions_Outcome :=
              Objects.List_Versions_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Maximum => 1, Timeout => 5.0);
         begin
            if Result.Kind /= Objects.Page_Available
              or else Result.Status /= 200
              or else not Result.Page.Versions.Is_Empty
              or else not Result.Page.Delete_Markers.Is_Empty
              or else not Result.Page.Common_Prefixes.Is_Empty
              or else not Result.Page.Has_Key_Marker
              or else US.Length (Result.Page.Key_Marker) /= 0
              or else not Result.Page.Has_Version_ID_Marker
              or else US.Length (Result.Page.Version_ID_Marker) /= 0
              or else not Result.Page.Has_Prefix
              or else US.Length (Result.Page.Prefix) /= 0
              or else not Result.Page.Has_Delimiter
              or else US.Length (Result.Page.Delimiter) /= 0
            then
               raise Program_Error with
               "ListObjectVersions empty echo compatibility mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.List_Object_Versions_Parameters;
         begin
            Parameters.Max_Keys := 2;
            Parameters.Has_Max_Keys := False;
            Parameters.Prefix := US.To_Unbounded_String ("omitted-max/");
            Parameters.Has_Prefix := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Object_Versions
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Parameters, Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.List_Object_Versions_Outcome :=
                 Low_Level.Execute_List_Object_Versions
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Listed
                 or else Result.Result.Listing.Max_Keys /= 1_000
               then
                  raise Program_Error with
                    "ListObjectVersions omitted MaxKeys binding mismatch";
               end if;
            end;
         end;
         declare
            Logical_Key : constant String :=
              "paged/a /%" & Character'Val (16#C3#) &
              Character'Val (16#A9#);
            First : constant Objects.List_Versions_Outcome :=
              Objects.List_Versions_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "paged/", Maximum => 1, URL_Encoding => True,
                 Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else not First.Page.Is_Truncated
              or else not First.Has_Next_Markers
              or else US.To_String (First.Next_Key_Marker) /= Logical_Key
              or else US.To_String (First.Next_Version_ID_Marker) /= "v+1"
            then
               raise Program_Error with
                 "ListObjectVersions logical continuation mismatch";
            end if;
            declare
               Next : constant Objects.List_Versions_Outcome :=
                 Objects.List_Versions_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "paged/", Maximum => 1,
                    Key_Marker => US.To_String (First.Next_Key_Marker),
                    Version_ID_Marker =>
                      US.To_String (First.Next_Version_ID_Marker),
                    URL_Encoding => True, Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Next.Page.Is_Truncated
                 or else Next.Has_Next_Markers
               then
                  raise Program_Error with
                    "ListObjectVersions second page mismatch";
               end if;
            end;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Objects.List_Versions_Outcome :=
                    Objects.List_Versions_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "bad-marker/", Maximum => 1,
                       URL_Encoding => True, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "ListObjectVersions accepted malformed encoded cursor";
            end if;
         end;
         declare
            Parameters : Low_Level.List_Object_Versions_Parameters;
         begin
            Parameters.Max_Keys := 1;
            Parameters.Has_Max_Keys := True;
            Parameters.Prefix := US.To_Unbounded_String ("error/");
            Parameters.Has_Prefix := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Object_Versions
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Parameters, Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.List_Object_Versions_Outcome :=
                 Low_Level.Execute_List_Object_Versions
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "versions-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "versions-host"
               then
                  raise Program_Error with
                    "typed ListObjectVersions socket error mismatch";
               end if;
            end;
         end;
         declare
            procedure Must_Reject
              (Prefix        : String;
               Message       : String;
               URL_Encoding  : Boolean := False;
               Omit_Prefix   : Boolean := False;
               Small_Limits  : Boolean := False)
            is
               Parameters : Low_Level.List_Object_Versions_Parameters;
               Raised : Boolean := False;
            begin
               Parameters.Max_Keys := 1;
               Parameters.Has_Max_Keys := True;
               Parameters.Prefix := US.To_Unbounded_String (Prefix);
               Parameters.Has_Prefix := not Omit_Prefix;
               Parameters.URL_Encoding := URL_Encoding;
               begin
                  declare
                     Prepared : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_List_Object_Versions
                         (Origin, Low_Level.Path_Style, "example-bucket",
                          Parameters, Identity, "us-east-1",
                          "20130524T000000Z");
                     Ignored : constant
                       Low_Level.List_Object_Versions_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_List_Object_Versions
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_List_Object_Versions
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject;
         begin
            Must_Reject
              ("duplicate/",
               "ListObjectVersions accepted duplicate response header");
            Must_Reject
              ("bucket/", "ListObjectVersions accepted wrong bucket echo");
            Must_Reject
              ("right/", "ListObjectVersions accepted wrong prefix echo");
            Must_Reject
              ("maximum/", "ListObjectVersions accepted wrong MaxKeys echo");
            Must_Reject
              ("encoding/", "ListObjectVersions accepted missing encoding",
               URL_Encoding => True);
            Must_Reject
              ("", "ListObjectVersions accepted unexpected nonempty echo",
               Omit_Prefix => True);
            Must_Reject
              ("malformed/", "ListObjectVersions accepted malformed XML");
            Must_Reject
              ("oversized/", "ListObjectVersions accepted oversized XML",
               Small_Limits => True);
         end;
         declare
            Parameters : Low_Level.List_Object_Versions_Parameters;
         begin
            Parameters.Prefix := US.To_Unbounded_String ("scoped/");
            Parameters.Has_Prefix := True;
            Parameters.Max_Keys := 1;
            Parameters.Has_Max_Keys := True;
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            declare
               Result : constant List_Object_Versions_Result :=
                 Objects.List_Versions_Page
                   (HTTP, Origin, "example-bucket", Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /=
                 List_Object_Versions_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Listed
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "typed composable ListObjectVersions success mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.List_Object_Versions_Parameters;
         begin
            Parameters.Prefix := US.To_Unbounded_String ("scoped-error/");
            Parameters.Has_Prefix := True;
            Parameters.Max_Keys := 1;
            Parameters.Has_Max_Keys := True;
            declare
               Result : constant List_Object_Versions_Result :=
                 Objects.List_Versions_Page
                   (HTTP, Origin, "example-bucket", Parameters, Identity,
                    Timeout => 5.0);
            begin
               if Result.Kind /=
                 List_Object_Versions_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /= Low_Level.Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "composable ListObjectVersions rejection mismatch";
               end if;
            end;
         end;
         declare
            procedure Require_Invalid_List_Object_Versions
              (Prefix, Message : String) is
               Parameters : Low_Level.List_Object_Versions_Parameters;
               --  Listing parent, HTTP exchange, and one transport child.
               Set : aliased Operations.Completion_Set (3);
            begin
               Parameters.Prefix := US.To_Unbounded_String (Prefix);
               Parameters.Has_Prefix := True;
               Parameters.Max_Keys := 1;
               Parameters.Has_Max_Keys := True;
               declare
                  Operation : List_Object_Versions_Operation :=
                    List_Versions_Page
                      (Set'Access, HTTP'Access, Origin, "example-bucket",
                       Parameters, Identity,
                       HTTP_Client.Deadline_After (5.0));
                  Result : List_Object_Versions_Result;
               begin
                  Operations.Wait_All (Set);
                  Finish (Operation, Result);
                  if Result.Kind /=
                    List_Object_Versions_Exchange_Failed
                    or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
                    or else Result.Admission /= HTTP_Client.Response_Observed
                  then
                     raise Program_Error with Message;
                  end if;
               end;
            end Require_Invalid_List_Object_Versions;
         begin
            Require_Invalid_List_Object_Versions
              ("scoped-wrong/",
               "composable ListObjectVersions accepted a wrong bucket");
            Require_Invalid_List_Object_Versions
              ("scoped-duplicate/",
               "composable ListObjectVersions accepted duplicate headers");
            Require_Invalid_List_Object_Versions
              ("scoped-payer/",
               "composable ListObjectVersions accepted unrequested payer");
         end;
         declare
            Stop : aliased Flyology.Cancellation.Token;
            Parameters : Low_Level.List_Object_Versions_Parameters;
         begin
            Stop.Request;
            Parameters.Max_Keys := 1;
            Parameters.Has_Max_Keys := True;
            declare
               Result : constant List_Object_Versions_Result :=
                 Objects.List_Versions_Page
                   (HTTP, Origin, "example-bucket", Parameters, Identity,
                    Timeout => 5.0, Token => Stop'Access);
            begin
               if Result.Kind /=
                 List_Object_Versions_Exchange_Failed
                 or else Result.Failure /= Client_API.Cancelled
                 or else Result.Admission /= HTTP_Client.Not_Admitted
               then
                  raise Program_Error with
                    "pre-admission ListObjectVersions cancellation mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.List_Object_Versions_Parameters;
            --  Listing parent, HTTP exchange, and one transport child.
            Set : aliased Operations.Completion_Set (3);
         begin
            Parameters.Prefix := US.To_Unbounded_String ("paged/");
            Parameters.Has_Prefix := True;
            Parameters.Max_Keys := 1;
            Parameters.Has_Max_Keys := True;
            Parameters.URL_Encoding := True;
            declare
               Operation : List_Object_Versions_Operation :=
                 List_Versions_Page
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    Parameters, Identity, HTTP_Client.Deadline_After (5.0));
               Result : List_Object_Versions_Result;
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 List_Object_Versions_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Listed
                 or else not Result.Response.Result.Listing.Is_Truncated
               then
                  raise Program_Error with
                    "composed ListObjectVersions first page mismatch";
               end if;
               Parameters.Key_Marker := US.To_Unbounded_String
                 (Listings.Decode_URL_Value
                    (US.To_String
                       (Result.Response.Result.Listing.Next_Key_Marker)));
               Parameters.Has_Key_Marker := True;
               Parameters.Version_ID_Marker :=
                 Result.Response.Result.Listing.Next_Version_ID_Marker;
               Parameters.Has_Version_ID_Marker := True;
               List_Versions_Page
                 (HTTP'Access,
                  Origin,
                  "example-bucket",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                 List_Object_Versions_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /= Low_Level.Listed
                 or else Result.Response.Result.Listing.Is_Truncated
               then
                  raise Program_Error with
                    "composed ListObjectVersions paired restart mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Buckets.Delete_Outcome :=
              Buckets.Delete_CORS
                (HTTP, Origin, "example-bucket", Identity,
                 Expected_Bucket_Owner => "123456789012",
                 Timeout => 5.0);
         begin
            if Result.Kind /= Buckets.Deletion_Completed
              or else Result.Status /= 204
            then
               raise Program_Error with
                 "DeleteBucketCors convenience success mismatch";
            end if;
         end;
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket_Encryption
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Parameters,
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            --  Parent, HTTP exchange, and HTTP's one active transport child.
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Delete_Bucket_CORS_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
            Result : Delete_Bucket_CORS_Result;
         begin
            declare
               Typed_Result : constant Delete_Bucket_CORS_Result :=
                 Buckets.Delete_CORS
                   (HTTP,
                    Origin,
                    "typed-delete-cors",
                    Parameters,
                    Identity,
                    Timeout => 5.0);
            begin
               if Typed_Result.Kind /=
                    Delete_Bucket_CORS_Response_Available
                 or else Typed_Result.Disposition /=
                   Bucket_CORS_Mutation_Completed
                 or else Typed_Result.Failure /= No_Failure
                 or else Typed_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Typed_Result.Response.Kind /=
                   Low_Level.Bucket_CORS_Deleted
               then
                  raise Program_Error with
                    "typed DeleteBucketCors response mismatch";
               end if;
            end;
            begin
               Low_Level.Delete_Bucket_CORS
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeleteBucketCors accepted an encryption request";
            end if;

            declare
               Operation : Delete_Bucket_CORS_Operation :=
                 Delete_CORS
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-delete-cors",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_CORS_Response_Available
                 or else Result.Disposition /=
                   Bucket_CORS_Mutation_Completed
               then
                  raise Program_Error with
                    "composed DeleteBucketCors mismatch";
               end if;
               Delete_CORS
                 (HTTP'Access,
                  Origin,
                  "restart-delete-cors",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_CORS_Response_Available
                 or else Result.Disposition /=
                   Bucket_CORS_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-delete-cors"
               then
                  raise Program_Error with
                    "restarted DeleteBucketCors mismatch";
               end if;
               Delete_CORS
                 (HTTP'Access,
                  Origin,
                  "bounded-delete-cors",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Limits =>
                    --  Test-only caller policy paired with the oversized
                    --  server fixture above.
                    (Maximum_Document_Bytes => 64,
                     Maximum_Depth          => 8,
                     Maximum_Elements       => 32,
                     Maximum_Text_Bytes     => 64),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_CORS_Exchange_Failed
                 or else Result.Disposition /=
                   Bucket_CORS_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded DeleteBucketCors response mismatch";
               end if;
            end;
         end;
         Require_Configuration_Deletion
           (Buckets.Delete_Analytics_Configuration
              (HTTP, Origin, "example-bucket", "config id", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketAnalyticsConfiguration");
         Require_Configuration_Deletion
           (Buckets.Delete_Encryption
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketEncryption");
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket_Ownership_Controls
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Parameters,
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Delete_Bucket_Encryption_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
            Result : Delete_Bucket_Encryption_Result;
         begin
            declare
               Typed_Result : constant Delete_Bucket_Encryption_Result :=
                 Buckets.Delete_Encryption
                   (HTTP,
                    Origin,
                    "typed-delete-encryption",
                    Parameters,
                    Identity,
                    Timeout => 5.0);
            begin
               if Typed_Result.Kind /=
                    Delete_Bucket_Encryption_Response_Available
                 or else Typed_Result.Disposition /=
                   Bucket_Encryption_Mutation_Completed
                 or else Typed_Result.Failure /= No_Failure
                 or else Typed_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Typed_Result.Response.Kind /=
                   Low_Level.Configuration_Deleted
               then
                  raise Program_Error with
                    "typed DeleteBucketEncryption response mismatch";
               end if;
            end;
            begin
               Low_Level.Delete_Bucket_Encryption
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeleteBucketEncryption accepted an ownership-controls " &
                 "request";
            end if;

            declare
               Operation : Delete_Bucket_Encryption_Operation :=
                 Delete_Encryption
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-delete-encryption",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Encryption_Response_Available
                 or else Result.Disposition /=
                   Bucket_Encryption_Mutation_Completed
               then
                  raise Program_Error with
                    "composed DeleteBucketEncryption mismatch";
               end if;
               Delete_Encryption
                 (HTTP'Access,
                  Origin,
                  "restart-delete-encryption",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Encryption_Response_Available
                 or else Result.Disposition /=
                   Bucket_Encryption_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-delete-encryption"
               then
                  raise Program_Error with
                    "restarted DeleteBucketEncryption mismatch";
               end if;
            end;
         end;
         Require_Configuration_Deletion
           (Buckets.Delete_Intelligent_Tiering_Configuration
              (HTTP, Origin, "example-bucket", "config id", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketIntelligentTieringConfiguration");
         Require_Configuration_Deletion
           (Buckets.Delete_Inventory_Configuration
              (HTTP, Origin, "example-bucket", "config id", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketInventoryConfiguration");
         Require_Configuration_Deletion
           (Buckets.Delete_Lifecycle
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketLifecycle");
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket_Encryption
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Parameters,
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            --  Parent, HTTP exchange, and HTTP's one active transport child.
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Delete_Bucket_Lifecycle_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
            Result : Delete_Bucket_Lifecycle_Result;
         begin
            declare
               Typed_Result : constant Delete_Bucket_Lifecycle_Result :=
                 Buckets.Delete_Lifecycle
                   (HTTP,
                    Origin,
                    "typed-delete-lifecycle",
                    Parameters,
                    Identity,
                    Timeout => 5.0);
            begin
               if Typed_Result.Kind /=
                    Delete_Bucket_Lifecycle_Response_Available
                 or else Typed_Result.Disposition /=
                   Bucket_Lifecycle_Mutation_Completed
                 or else Typed_Result.Failure /= No_Failure
                 or else Typed_Result.Admission /=
                   HTTP_Client.Response_Observed
                 or else Typed_Result.Response.Kind /=
                   Low_Level.Configuration_Deleted
               then
                  raise Program_Error with
                    "typed DeleteBucketLifecycle response mismatch";
               end if;
            end;
            begin
               Low_Level.Delete_Bucket_Lifecycle
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeleteBucketLifecycle accepted an encryption request";
            end if;

            declare
               Operation : Delete_Bucket_Lifecycle_Operation :=
                 Delete_Lifecycle
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-delete-lifecycle",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Lifecycle_Response_Available
                 or else Result.Disposition /=
                   Bucket_Lifecycle_Mutation_Completed
               then
                  raise Program_Error with
                    "composed DeleteBucketLifecycle mismatch";
               end if;
               Delete_Lifecycle
                 (HTTP'Access,
                  Origin,
                  "restart-delete-lifecycle",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Lifecycle_Response_Available
                 or else Result.Disposition /=
                   Bucket_Lifecycle_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-delete-lifecycle"
               then
                  raise Program_Error with
                    "restarted DeleteBucketLifecycle mismatch";
               end if;
               Delete_Lifecycle
                 (HTTP'Access,
                  Origin,
                  "invalid-delete-lifecycle",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Lifecycle_Exchange_Failed
                 or else Result.Disposition /=
                   Bucket_Lifecycle_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
               then
                  raise Program_Error with
                    "DeleteBucketLifecycle accepted duplicate response " &
                    "identifier";
               end if;
               Delete_Lifecycle
                 (HTTP'Access,
                  Origin,
                  "empty-host-delete-lifecycle",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Lifecycle_Exchange_Failed
                 or else Result.Disposition /=
                   Bucket_Lifecycle_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
               then
                  raise Program_Error with
                    "DeleteBucketLifecycle accepted an empty host " &
                    "identifier";
               end if;
               Delete_Lifecycle
                 (HTTP'Access,
                  Origin,
                  "bounded-delete-lifecycle",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Limits =>
                    --  Test-only caller policy paired with the oversized
                    --  server fixture above.
                    (Maximum_Document_Bytes => 64,
                     Maximum_Depth          => 8,
                     Maximum_Elements       => 32,
                     Maximum_Text_Bytes     => 64),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Lifecycle_Exchange_Failed
                 or else Result.Disposition /=
                   Bucket_Lifecycle_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /=
                   HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded DeleteBucketLifecycle response mismatch";
               end if;
            end;
         end;
         Require_Configuration_Deletion
           (Buckets.Delete_Metadata_Configuration
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketMetadataConfiguration");
         Require_Configuration_Deletion
           (Buckets.Delete_Metadata_Table_Configuration
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketMetadataTableConfiguration");
         Require_Configuration_Deletion
           (Buckets.Delete_Metrics_Configuration
              (HTTP, Origin, "example-bucket", "config id", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketMetricsConfiguration");
         Require_Configuration_Deletion
           (Buckets.Delete_Ownership_Controls
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketOwnershipControls");
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Public_Access_Block
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Parameters,
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Delete_Ownership_Controls_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
            Result : Delete_Ownership_Controls_Result;
         begin
            begin
               Low_Level.Delete_Bucket_Ownership_Controls
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeleteBucketOwnershipControls accepted a public-access " &
                 "request";
            end if;

            declare
               Operation : Delete_Ownership_Controls_Operation :=
                 Delete_Ownership_Controls
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-delete-ownership",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Ownership_Controls_Response_Available
                 or else Result.Disposition /=
                   Bucket_Ownership_Controls_Mutation_Completed
               then
                  raise Program_Error with
                    "composed DeleteBucketOwnershipControls mismatch";
               end if;
               Delete_Ownership_Controls
                 (HTTP'Access,
                  Origin,
                  "restart-delete-ownership",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Ownership_Controls_Response_Available
                 or else Result.Disposition /=
                   Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-delete-ownership"
               then
                  raise Program_Error with
                    "restarted DeleteBucketOwnershipControls mismatch";
               end if;
            end;
         end;
         Require_Configuration_Deletion
           (Buckets.Delete_Policy
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketPolicy");
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Public_Access_Block
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Delete_Bucket_Policy_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Delete_Bucket_Policy
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeleteBucketPolicy accepted another configuration " &
                 "deletion";
            end if;
         end;
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Result : constant Delete_Bucket_Policy_Result :=
              Buckets.Delete_Policy
                (HTTP,
                 Origin,
                 "typed-delete-policy",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Delete_Bucket_Policy_Response_Available
              or else Result.Disposition /=
                Bucket_Policy_Mutation_Completed
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /= Low_Level.Configuration_Deleted
            then
               raise Program_Error with
                 "typed DeleteBucketPolicy response mismatch";
            end if;
         end;
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            --  Policy parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Delete_Bucket_Policy_Result;
         begin
            declare
               Operation : Delete_Bucket_Policy_Operation :=
                 Delete_Policy
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-delete-policy",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Policy_Response_Available
                 or else Result.Disposition /=
                   Bucket_Policy_Mutation_Completed
               then
                  raise Program_Error with
                    "composed DeleteBucketPolicy first result mismatch";
               end if;
               Delete_Policy
                 (HTTP'Access,
                  Origin,
                  "restart-delete-policy",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Delete_Bucket_Policy_Response_Available
                 or else Result.Disposition /=
                   Bucket_Policy_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Delete_Configuration_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-delete-policy-request"
               then
                  raise Program_Error with
                    "composed DeleteBucketPolicy restart mismatch";
               end if;
            end;
         end;
         Require_Configuration_Deletion
           (Buckets.Delete_Replication
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketReplication");
         Require_Configuration_Deletion
           (Buckets.Delete_Website
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeleteBucketWebsite");
         Require_Configuration_Deletion
           (Buckets.Delete_Public_Access_Block
              (HTTP, Origin, "example-bucket", Identity,
               Expected_Bucket_Owner => "123456789012", Timeout => 5.0),
            "DeletePublicAccessBlock");
         declare
            Parameters : constant
              Low_Level.Delete_Bucket_Configuration_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            --  Parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Delete_Public_Access_Block_Result;
         begin
            declare
               Operation : Delete_Public_Access_Block_Operation :=
                 Delete_Public_Access_Block
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-delete-public-access",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Delete_Public_Access_Block_Response_Available
                 or else Result.Disposition /=
                   Public_Access_Block_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed DeletePublicAccessBlock result mismatch";
               end if;
               Delete_Public_Access_Block
                 (HTTP'Access,
                  Origin,
                  "restart-delete-public-access",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Delete_Public_Access_Block_Response_Available
                 or else Result.Disposition /=
                   Public_Access_Block_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-delete-public-access"
               then
                  raise Program_Error with
                    "restarted DeletePublicAccessBlock result mismatch";
               end if;
            end;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket_Policy
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Delete_Public_Access_Block_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Delete_Public_Access_Block
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "DeletePublicAccessBlock accepted a policy request";
            end if;
         end;
         --  These paired assertions are the native/lightweight transport
         --  oracle for the five reference responses served above.
         declare
            Result : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
              Buckets.Get_Accelerate_Configuration
                (HTTP, Origin, "example-bucket", Identity,
                 Expected_Bucket_Owner => "123456789012",
                 Request_Payer => "requester", Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Configuration /=
                Bucket_Controls.Accelerate_Enabled
              or else US.To_String (Result.Request_Charged) /= "requester"
            then
               raise Program_Error with
                 "GetBucketAccelerateConfiguration socket mismatch";
            end if;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Bucket_Policy_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Bucket_Policy
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetBucketPolicy accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Policy_Result :=
              Buckets.Get_Policy
                (HTTP, Origin, "example-bucket", Parameters, Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Policy_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /= Low_Level.Bucket_Control_Found
              or else US.To_String (Result.Response.Policy) /=
                "{""Statement"":[]}"
            then
               raise Program_Error with "GetBucketPolicy socket mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Policy parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_Policy_Result;
         begin
            declare
               Operation : Get_Bucket_Policy_Operation :=
                 Get_Policy
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-policy",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_Policy_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Bucket_Control_Found
                 or else US.To_String (Result.Response.Policy) /=
                   "{""Version"":""2012-10-17""}"
               then
                  raise Program_Error with
                    "composed GetBucketPolicy first result mismatch";
               end if;
               Get_Policy
                 (HTTP'Access,
                  Origin,
                  "restart-policy",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_Policy_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Bucket_Control_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-policy-request"
               then
                  raise Program_Error with
                    "composed GetBucketPolicy restart mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Low_Level.Get_Bucket_Policy_Status_Outcome :=
              Buckets.Get_Policy_Status
                (HTTP, Origin, "example-bucket", Identity,
                 Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Is_Public.Is_Set
              or else Result.Is_Public.Value
            then
               raise Program_Error with
                 "GetBucketPolicyStatus socket mismatch";
            end if;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Bucket_Policy_Status_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Bucket_Policy_Status
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetBucketPolicyStatus accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Policy_Status_Result :=
              Buckets.Get_Policy_Status
                (HTTP,
                 Origin,
                 "typed-policy-status",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Policy_Status_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Response.Is_Public.Is_Set
              or else Result.Response.Is_Public.Value
            then
               raise Program_Error with
                 "typed GetBucketPolicyStatus response mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Policy-status parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_Policy_Status_Result;
         begin
            declare
               Operation : Get_Bucket_Policy_Status_Operation :=
                 Get_Policy_Status
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-policy-status",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Bucket_Policy_Status_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Bucket_Control_Found
                 or else not Result.Response.Is_Public.Is_Set
                 or else not Result.Response.Is_Public.Value
               then
                  raise Program_Error with
                    "composed GetBucketPolicyStatus first result mismatch";
               end if;
               Get_Policy_Status
                 (HTTP'Access,
                  Origin,
                  "restart-policy-status",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Bucket_Policy_Status_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Bucket_Control_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-policy-status"
               then
                  raise Program_Error with
                    "composed GetBucketPolicyStatus restart mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Policy_Status_Result :=
              Buckets.Get_Policy_Status
                (HTTP,
                 Origin,
                 "duplicate-policy-status-header",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Policy_Status_Exchange_Failed
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
            then
               raise Program_Error with
                 "duplicate GetBucketPolicyStatus response header admitted";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Policy_Status_Result :=
              Buckets.Get_Policy_Status
                (HTTP,
                 Origin,
                 "empty-policy-status-header",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Policy_Status_Exchange_Failed
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
            then
               raise Program_Error with
                 "empty GetBucketPolicyStatus host ID admitted";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Policy_Status_Result :=
              Buckets.Get_Policy_Status
                (HTTP,
                 Origin,
                 "bounded-policy-status",
                 Parameters,
                 Identity,
                 Timeout => 5.0,
                 Limits =>
                   --  Test-only one-byte ceiling is deliberately below the
                   --  valid policy-status XML response.
                   (Maximum_Document_Bytes => 1,
                    others => <>));
         begin
            if Result.Kind /= Get_Bucket_Policy_Status_Exchange_Failed
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
            then
               raise Program_Error with
                 "GetBucketPolicyStatus response limit was not enforced";
            end if;
         end;
         declare
            Result : constant
              Low_Level.Get_Bucket_Request_Payment_Outcome :=
                Buckets.Get_Request_Payment
                  (HTTP, Origin, "example-bucket", Identity,
                   Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Payment /= Bucket_Controls.Bucket_Owner
            then
               raise Program_Error with
                 "GetBucketRequestPayment socket mismatch";
            end if;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Bucket_Request_Payment_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Bucket_Request_Payment
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetBucketRequestPayment accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Request_Payment_Result :=
              Buckets.Get_Request_Payment
                (HTTP,
                 Origin,
                 "typed-request-payment",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Request_Payment_Response_Available
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Response.Payment /= Bucket_Controls.Requester
            then
               raise Program_Error with
                 "typed GetBucketRequestPayment response mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  ABAC parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_Request_Payment_Result;
         begin
            declare
               Operation : Get_Bucket_Request_Payment_Operation :=
                 Get_Request_Payment
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-request-payment",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Bucket_Request_Payment_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Bucket_Control_Found
                 or else Result.Response.Payment /=
                   Bucket_Controls.Bucket_Owner
               then
                  raise Program_Error with
                    "composed GetBucketRequestPayment first result mismatch";
               end if;
               Get_Request_Payment
                 (HTTP'Access,
                  Origin,
                  "restart-request-payment",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Bucket_Request_Payment_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Bucket_Control_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-request-payment"
               then
                  raise Program_Error with
                    "composed GetBucketRequestPayment restart mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Request_Payment_Result :=
              Buckets.Get_Request_Payment
                (HTTP,
                 Origin,
                 "duplicate-request-payment-header",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Request_Payment_Exchange_Failed
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
            then
               raise Program_Error with
                 "duplicate GetBucketRequestPayment response header " &
                 "admitted";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Request_Payment_Result :=
              Buckets.Get_Request_Payment
                (HTTP,
                 Origin,
                 "empty-request-payment-header",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Get_Bucket_Request_Payment_Exchange_Failed
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.HTTP_Result /= HTTP_Client.Response_Invalid
            then
               raise Program_Error with
                 "empty GetBucketRequestPayment host ID admitted";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Get_Bucket_Request_Payment_Result :=
              Buckets.Get_Request_Payment
                (HTTP,
                 Origin,
                 "bounded-request-payment",
                 Parameters,
                 Identity,
                 Timeout => 5.0,
                 Limits =>
                   --  Test-only one-byte ceiling is deliberately below the
                   --  valid requester-payment XML response.
                   (Maximum_Document_Bytes => 1,
                    others => <>));
         begin
            if Result.Kind /= Get_Bucket_Request_Payment_Exchange_Failed
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
            then
               raise Program_Error with
                 "GetBucketRequestPayment response limit was not enforced";
            end if;
         end;
         declare
            Result : constant Low_Level.Get_Public_Access_Block_Outcome :=
              Buckets.Get_Public_Access_Block
                (HTTP, Origin, "example-bucket", Identity,
                 Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Configuration.Block_Public_ACLs.Is_Set
              or else not Result.Configuration.Block_Public_ACLs.Value
              or else not Result.Configuration.Ignore_Public_ACLs.Is_Set
              or else Result.Configuration.Ignore_Public_ACLs.Value
              or else not Result.Configuration.Block_Public_Policy.Is_Set
              or else not Result.Configuration.Block_Public_Policy.Value
              or else not
                Result.Configuration.Restrict_Public_Buckets.Is_Set
              or else Result.Configuration.Restrict_Public_Buckets.Value
            then
               raise Program_Error with
                 "GetPublicAccessBlock socket mismatch";
            end if;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Public_Access_Block_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Public_Access_Block
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetPublicAccessBlock accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Public_Access_Block_Result;
         begin
            declare
               Operation : Get_Public_Access_Block_Operation :=
                 Get_Public_Access_Block
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-public-access",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Public_Access_Block_Response_Available
                 or else Result.Failure /= No_Failure
                 or else not
                   Result.Response.Configuration.Block_Public_ACLs.Is_Set
                 or else
                   Result.Response.Configuration.Block_Public_ACLs.Value
                 or else not
                   Result.Response.Configuration.Ignore_Public_ACLs.Is_Set
                 or else not
                   Result.Response.Configuration.Ignore_Public_ACLs.Value
                 or else not
                   Result.Response.Configuration.Block_Public_Policy.Is_Set
                 or else
                   Result.Response.Configuration.Block_Public_Policy.Value
                 or else not Result.Response.Configuration.
                   Restrict_Public_Buckets.Is_Set
                 or else not Result.Response.Configuration.
                   Restrict_Public_Buckets.Value
               then
                  raise Program_Error with
                    "composed GetPublicAccessBlock result mismatch";
               end if;
               Get_Public_Access_Block
                 (HTTP'Access,
                  Origin,
                  "restart-public-access",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Public_Access_Block_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-get-public-access"
               then
                  raise Program_Error with
                    "restarted GetPublicAccessBlock result mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Low_Level.Get_Bucket_Abac_Outcome :=
              Buckets.Get_ABAC
                (HTTP, Origin, "example-bucket", Identity,
                 Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Configuration /= Bucket_Controls.Abac_Enabled
            then
               raise Program_Error with "GetBucketAbac socket mismatch";
            end if;
         end;
         declare
            function Configuration return Bucket_Controls.CORS_Configuration
            is
            begin
               return Value : Bucket_Controls.CORS_Configuration :=
                 (Is_Set => True, others => <>)
               do
                  declare
                     Rule : Bucket_Controls.CORS_Rule := (others => <>);
                  begin
                     Rule.ID :=
                       (Is_Set => True,
                        Value => US.To_Unbounded_String ("socket-rule"));
                     Rule.Allowed_Headers.Append ("x-test");
                     Rule.Allowed_Methods.Append ("GET");
                     Rule.Allowed_Origins.Append ("https://example.test");
                     Rule.Expose_Headers.Append ("etag");
                     Rule.Max_Age_Seconds :=
                       (Is_Set => True,
                        Text => US.To_Unbounded_String ("3600"));
                     Value.Rules.Append (Rule);
                  end;
               end return;
            end Configuration;

            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
         begin
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Bucket_CORS
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Configuration,
                    (Content_MD5 => US.Null_Unbounded_String,
                     Checksum_Algorithm => US.To_Unbounded_String ("CRC32"),
                     Expected_Bucket_Owner =>
                       US.To_Unbounded_String ("123456789012")),
                    Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.Execute_Put_Bucket_CORS
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Bucket_Control_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "low-level one-shot PutBucketCors mismatch";
               end if;
            end;
            declare
               Result : constant Put_Bucket_CORS_Result :=
                 Buckets.Set_CORS
                   (HTTP, Origin, "typed-put-cors", Configuration,
                    Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Put_Bucket_CORS_Response_Available
                 or else Result.Disposition /=
                   Bucket_CORS_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "typed-put-cors"
               then
                  raise Program_Error with
                    "typed PutBucketCors response mismatch";
               end if;
            end;
            declare
               Set : aliased Operations.Completion_Set (3);
               Result : Put_Bucket_CORS_Result;
               Value : Bucket_Controls.CORS_Configuration := Configuration;
               Operation : Put_Bucket_CORS_Operation :=
                 Set_CORS
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-cors",
                    Value,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Value.Rules.Clear;
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_CORS_Response_Available
                 or else Result.Disposition /= Bucket_CORS_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed PutBucketCors result mismatch";
               end if;
               Set_CORS
                 (HTTP'Access,
                  Origin,
                  "restart-put-cors",
                  Configuration,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_CORS_Response_Available
                 or else Result.Disposition /=
                   Bucket_CORS_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-put-cors"
               then
                  raise Program_Error with
                    "restarted PutBucketCors result mismatch";
               end if;
            end;
            declare
               Prepared : aliased Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Bucket_Abac
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Bucket_Controls.Abac_Enabled, (others => <>), Identity,
                    "us-east-1", "20130524T000000Z");
               Set : aliased Operations.Completion_Set (3);
               Parent : aliased Put_Bucket_CORS_Operation
                 (Set'Access, HTTP'Access, null);
               Child : HTTP_Client.Exchange_Operation (Set'Access);
               Rejected : Boolean := False;
            begin
               begin
                  Low_Level.Put_Bucket_CORS
                    (HTTP'Access, Prepared'Access, Parent'Access,
                     Parent'Access, HTTP_Client.Deadline_After (5.0),
                     Operation => Child);
               exception
                  when Low_Level.Invalid_Request => Rejected := True;
               end;
               if not Rejected then
                  raise Program_Error with
                    "PutBucketCors accepted a prepared ABAC request";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Ownership_Controls
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant
              Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
                Low_Level.Execute_Get_Bucket_Ownership_Controls
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Configuration.Is_Set
              or else Result.Configuration.Rules.Length /= 2
              or else Result.Configuration.Rules.Element (1).Ownership /=
                Bucket_Controls.Bucket_Owner_Preferred
              or else Result.Configuration.Rules.Element (2).Ownership /=
                Bucket_Controls.Bucket_Owner_Enforced
            then
               raise Program_Error with
                 "GetBucketOwnershipControls socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Ownership_Controls
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant
              Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
                Low_Level.Execute_Get_Bucket_Ownership_Controls
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Configuration.Is_Set
              or else not Result.Configuration.Rules.Is_Empty
            then
               raise Program_Error with
                 "GetBucketOwnershipControls outer absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Ownership_Controls
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant
              Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
                Low_Level.Execute_Get_Bucket_Ownership_Controls
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Bucket_Control_Rejected
              or else Result.Status /= 403
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "ownership-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "ownership-error-host"
            then
               raise Program_Error with
                 "GetBucketOwnershipControls socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Ownership
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Bucket_Ownership_Controls
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Get_Bucket_Ownership_Controls
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Get_Bucket_Ownership_Controls
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Ownership;
         begin
            Must_Reject_Ownership
              ("GetBucketOwnershipControls accepted duplicate request ID");
            Must_Reject_Ownership
              ("GetBucketOwnershipControls accepted duplicate host ID");
            Must_Reject_Ownership
              ("GetBucketOwnershipControls accepted empty request ID");
            Must_Reject_Ownership
              ("GetBucketOwnershipControls accepted malformed success XML");
            Must_Reject_Ownership
              ("GetBucketOwnershipControls accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (others => <>),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Bucket_Ownership_Controls_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Bucket_Ownership_Controls
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetBucketOwnershipControls accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_Ownership_Controls_Result;
         begin
            declare
               Operation : Get_Bucket_Ownership_Controls_Operation :=
                 Get_Ownership_Controls
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-ownership",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Bucket_Ownership_Controls_Response_Available
                 or else Result.Failure /= No_Failure
                 or else not Result.Response.Configuration.Is_Set
                 or else Result.Response.Configuration.Rules.Length /= 1
                 or else Result.Response.Configuration.Rules.Element (1).
                   Ownership /= Bucket_Controls.Bucket_Owner_Enforced
               then
                  raise Program_Error with
                    "composed GetBucketOwnershipControls result mismatch";
               end if;
               Get_Ownership_Controls
                 (HTTP'Access,
                  Origin,
                  "restart-ownership",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Get_Bucket_Ownership_Controls_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-get-ownership"
               then
                  raise Program_Error with
                    "restarted GetBucketOwnershipControls result mismatch";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_CORS
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_CORS_Outcome :=
              Low_Level.Execute_Get_Bucket_CORS
                (HTTP, Prepared, Timeout => 5.0);
            Rule : constant Bucket_Controls.CORS_Rule :=
              Result.Configuration.Rules.Element (1);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Configuration.Is_Set
              or else Result.Configuration.Rules.Length /= 1
              or else not Rule.ID.Is_Set
              or else US.To_String (Rule.ID.Value) /= "socket-rule"
              or else Rule.Allowed_Headers.Length /= 1
              or else Rule.Allowed_Headers.Element (1) /= "*"
              or else Rule.Allowed_Methods.Length /= 2
              or else Rule.Allowed_Methods.Element (2) /= "PUT"
              or else Rule.Allowed_Origins.Element (1) /=
                "https://example.test"
              or else Rule.Expose_Headers.Element (1) /= "etag"
              or else not Rule.Max_Age_Seconds.Is_Set
              or else US.To_String (Rule.Max_Age_Seconds.Text) /=
                "999999999999999999999999"
            then
               raise Program_Error with
                 "GetBucketCors socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_CORS
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_CORS_Outcome :=
              Low_Level.Execute_Get_Bucket_CORS
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Configuration.Is_Set
              or else not Result.Configuration.Rules.Is_Empty
            then
               raise Program_Error with
                 "GetBucketCors outer absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_CORS
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_CORS_Outcome :=
              Low_Level.Execute_Get_Bucket_CORS
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Bucket_Control_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "cors-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "cors-error-host"
            then
               raise Program_Error with
                 "GetBucketCors socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_CORS
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Bucket_CORS
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Get_Bucket_CORS_Outcome :=
                       (if Small_Limits
                        then Low_Level.Execute_Get_Bucket_CORS
                          (HTTP, Prepared, Timeout => 5.0,
                           Limits =>
                             --  Test-only caller policy paired with the
                             --  oversized server fixture above.
                             (Maximum_Document_Bytes => 64,
                              Maximum_Depth          => 8,
                              Maximum_Elements       => 32,
                              Maximum_Text_Bytes     => 64))
                        else Low_Level.Execute_Get_Bucket_CORS
                          (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_CORS;
         begin
            Must_Reject_CORS
              ("GetBucketCors accepted duplicate request ID");
            Must_Reject_CORS
              ("GetBucketCors accepted duplicate host ID");
            Must_Reject_CORS
              ("GetBucketCors accepted empty request ID");
            Must_Reject_CORS
              ("GetBucketCors accepted malformed success XML");
            Must_Reject_CORS
              ("GetBucketCors accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Encryption
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (others => <>),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            --  Parent, HTTP exchange, and HTTP's one active transport child.
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Bucket_CORS_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Bucket_CORS
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetBucketCors accepted an encryption request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Parent, HTTP exchange, and HTTP's one active transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_CORS_Result;
         begin
            declare
               Typed_Result : constant Get_Bucket_CORS_Result :=
                 Buckets.Get_CORS
                   (HTTP,
                    Origin,
                    "typed-get-cors",
                    Parameters,
                    Identity,
                    Timeout => 5.0);
            begin
               if Typed_Result.Kind /= Get_Bucket_CORS_Response_Available
                 or else Typed_Result.Failure /= No_Failure
                 or else not Typed_Result.Response.Configuration.Is_Set
                 or else Typed_Result.Response.Configuration.Rules.Length /= 1
                 or else Typed_Result.Response.Configuration.Rules.Element
                   (1).Allowed_Origins.Element (1) /=
                     "https://typed.example"
               then
                  raise Program_Error with
                    "typed GetBucketCors result mismatch";
               end if;
            end;
            declare
               Operation : Get_Bucket_CORS_Operation :=
                 Get_CORS
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-get-cors",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_CORS_Response_Available
                 or else Result.Failure /= No_Failure
                 or else not Result.Response.Configuration.Is_Set
                 or else Result.Response.Configuration.Rules.Length /= 1
                 or else Result.Response.Configuration.Rules.Element
                   (1).Allowed_Methods.Element (1) /= "PUT"
               then
                  raise Program_Error with
                    "composed GetBucketCors result mismatch";
               end if;
               Get_CORS
                 (HTTP'Access,
                  Origin,
                  "restart-get-cors",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_CORS_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-get-cors"
               then
                  raise Program_Error with
                    "restarted GetBucketCors result mismatch";
               end if;
               Get_CORS
                 (HTTP'Access,
                  Origin,
                  "bounded-get-cors",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Limits =>
                    --  Test-only caller policy paired with the oversized
                    --  server fixture above.
                    (Maximum_Document_Bytes => 64,
                     Maximum_Depth          => 8,
                     Maximum_Elements       => 32,
                     Maximum_Text_Bytes     => 64),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_CORS_Exchange_Failed
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded GetBucketCors response mismatch";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Encryption
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_Encryption_Outcome :=
              Low_Level.Execute_Get_Bucket_Encryption
                (HTTP, Prepared, Timeout => 5.0);
            Rule : constant Encryption.Encryption_Rule :=
              Result.Configuration.Rules.Element (1);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Configuration.Is_Set
              or else Result.Configuration.Rules.Length /= 1
              or else not Rule.Default_Encryption.Is_Set
              or else Rule.Default_Encryption.Algorithm /=
                Encryption.KMS_Encryption
              or else not Rule.Default_Encryption.KMS_Master_Key_ID.Is_Set
              or else US.To_String
                (Rule.Default_Encryption.KMS_Master_Key_ID.Value) /=
                  "socket-key"
              or else not Rule.Bucket_Key_Enabled.Is_Set
              or else not Rule.Bucket_Key_Enabled.Value
              or else not Rule.Blocked_Types.Is_Set
              or else not Rule.Blocked_Types.Types_Is_Set
              or else Rule.Blocked_Types.Types.Length /= 1
              or else Rule.Blocked_Types.Types.Element (1) /=
                Encryption.SSE_C_Blocked
            then
               raise Program_Error with
                 "GetBucketEncryption socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Encryption
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_Encryption_Outcome :=
              Low_Level.Execute_Get_Bucket_Encryption
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Configuration.Is_Set
              or else not Result.Configuration.Rules.Is_Empty
            then
               raise Program_Error with
                 "GetBucketEncryption outer absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Encryption
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_Encryption_Outcome :=
              Low_Level.Execute_Get_Bucket_Encryption
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Bucket_Control_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "encryption-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "encryption-error-host"
            then
               raise Program_Error with
                 "GetBucketEncryption socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Encryption
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Bucket_Encryption
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Bucket_Encryption_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Get_Bucket_Encryption
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               --  Test-only caller policy paired with the
                               --  oversized server fixture above.
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Get_Bucket_Encryption
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Encryption;
         begin
            Must_Reject_Encryption
              ("GetBucketEncryption accepted duplicate request ID");
            Must_Reject_Encryption
              ("GetBucketEncryption accepted duplicate host ID");
            Must_Reject_Encryption
              ("GetBucketEncryption accepted empty request ID");
            Must_Reject_Encryption
              ("GetBucketEncryption accepted malformed success XML");
            Must_Reject_Encryption
              ("GetBucketEncryption accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (others => <>),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Get_Bucket_Encryption_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Get_Bucket_Encryption
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "GetBucketEncryption accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Set : aliased Operations.Completion_Set (3);
            Result : Get_Bucket_Encryption_Result;
         begin
            declare
               Operation : Get_Bucket_Encryption_Operation :=
                 Get_Encryption
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-encryption",
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_Encryption_Response_Available
                 or else Result.Failure /= No_Failure
                 or else not Result.Response.Configuration.Is_Set
                 or else Result.Response.Configuration.Rules.Length /= 1
                 or else Result.Response.Configuration.Rules.Element (1).
                   Default_Encryption.Algorithm /= Encryption.AES256_Encryption
               then
                  raise Program_Error with
                    "composed GetBucketEncryption result mismatch";
               end if;
               Get_Encryption
                 (HTTP'Access,
                  Origin,
                  "restart-encryption",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Bucket_Encryption_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-get-encryption"
               then
                  raise Program_Error with
                    "restarted GetBucketEncryption result mismatch";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
                Low_Level.Execute_Get_Bucket_Metadata_Table_Configuration
                  (HTTP, Prepared, Timeout => 5.0);
            Configuration : constant
              Metadata_Tables.Metadata_Table_Configuration_Result :=
                Result.Configuration;
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Configuration.Is_Set
              or else US.To_String
                (Configuration.Destination.Table_Bucket_ARN) /=
                  "socket-bucket-arn"
              or else US.To_String
                (Configuration.Destination.Table_Name) /= "socket-table"
              or else US.To_String
                (Configuration.Destination.Table_ARN) /= "socket-table-arn"
              or else US.To_String
                (Configuration.Destination.Table_Namespace) /=
                  "socket-namespace"
              or else US.To_String (Configuration.Status) /=
                "future:READY/v2"
              or else not Configuration.Error.Is_Set
              or else not Configuration.Error.Code.Is_Set
              or else US.To_String (Configuration.Error.Code.Value) /= ""
              or else not Configuration.Error.Message.Is_Set
              or else US.To_String (Configuration.Error.Message.Value) /=
                "socket detail"
            then
               raise Program_Error with
                 "metadata-table socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
                Low_Level.Execute_Get_Bucket_Metadata_Table_Configuration
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Configuration.Is_Set
            then
               raise Program_Error with
                 "metadata-table socket outer absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
                Low_Level.Execute_Get_Bucket_Metadata_Table_Configuration
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Bucket_Control_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "metadata-table-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "metadata-table-error-host"
            then
               raise Program_Error with
                 "metadata-table socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Metadata_Table
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.
                         Get_Bucket_Metadata_Table_Configuration_Outcome :=
                           (if Small_Limits
                            then
                              Low_Level.
                                Execute_Get_Bucket_Metadata_Table_Configuration
                                  (HTTP, Prepared, Timeout => 5.0,
                                   Limits =>
                                     --  Test-only caller policy paired with
                                     --  the oversized server fixture above.
                                     (Maximum_Document_Bytes => 64,
                                      Maximum_Depth          => 8,
                                      Maximum_Elements       => 32,
                                      Maximum_Text_Bytes     => 64))
                            else
                              Low_Level.
                                Execute_Get_Bucket_Metadata_Table_Configuration
                                  (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Metadata_Table;
         begin
            Must_Reject_Metadata_Table
              ("metadata-table read accepted duplicate request ID");
            Must_Reject_Metadata_Table
              ("metadata-table read accepted duplicate host ID");
            Must_Reject_Metadata_Table
              ("metadata-table read accepted empty request ID");
            Must_Reject_Metadata_Table
              ("metadata-table read accepted malformed success XML");
            Must_Reject_Metadata_Table
              ("metadata-table read accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_ACL
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_ACL_Outcome :=
              Low_Level.Execute_Get_Bucket_ACL
                (HTTP, Prepared, Timeout => 5.0);
            Grant : constant ACL.Grant := Result.Policy.ACL.Grants.Element (1);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else not Result.Policy.Is_Set
              or else not Result.Policy.Policy_Owner.Is_Set
              or else US.To_String
                (Result.Policy.Policy_Owner.Display_Name.Value) /=
                  "socket-owner"
              or else US.To_String (Result.Policy.Policy_Owner.ID.Value) /=
                "owner-id"
              or else not Result.Policy.ACL.Is_Set
              or else Result.Policy.ACL.Grants.Length /= 1
              or else not Grant.Principal.Is_Set
              or else Grant.Principal.Kind /= ACL.Group_Grantee
              or else US.To_String (Grant.Principal.URI.Value) /=
                "socket-group"
              or else not Grant.Allowed.Is_Set
              or else Grant.Allowed.Value /= ACL.Read
            then
               raise Program_Error with "GetBucketAcl socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_ACL
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_ACL_Outcome :=
              Low_Level.Execute_Get_Bucket_ACL
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Found
              or else Result.Policy.Is_Set
            then
               raise Program_Error with "GetBucketAcl outer absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_ACL
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Bucket_ACL_Outcome :=
              Low_Level.Execute_Get_Bucket_ACL
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Bucket_Control_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "acl-error-request"
              or else US.To_String (Result.Error.Host_ID) /= "acl-error-host"
            then
               raise Program_Error with
                 "GetBucketAcl socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_ACL
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Bucket_ACL
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Get_Bucket_ACL_Outcome :=
                       (if Small_Limits
                        then Low_Level.Execute_Get_Bucket_ACL
                          (HTTP, Prepared, Timeout => 5.0,
                           Limits =>
                             --  Test-only caller policy paired with the
                             --  oversized server fixture above.
                             (Maximum_Document_Bytes => 64,
                              Maximum_Depth          => 8,
                              Maximum_Elements       => 32,
                              Maximum_Text_Bytes     => 64))
                        else Low_Level.Execute_Get_Bucket_ACL
                          (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_ACL;
         begin
            Must_Reject_ACL ("GetBucketAcl accepted duplicate request ID");
            Must_Reject_ACL ("GetBucketAcl accepted duplicate host ID");
            Must_Reject_ACL ("GetBucketAcl accepted empty request ID");
            Must_Reject_ACL ("GetBucketAcl accepted malformed success XML");
            Must_Reject_ACL
              ("GetBucketAcl accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_ACL
                (Origin, Low_Level.Path_Style, "example-bucket", "a b",
                 (Version_ID => US.To_Unbounded_String ("v/1"),
                  Request_Payer => US.To_Unbounded_String ("requester"),
                  Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Get_Object_ACL_Outcome :=
              Low_Level.Execute_Get_Object_ACL
                (HTTP, Prepared, Timeout => 5.0);
            Grant : constant ACL.Grant :=
              Result.Result.Policy.ACL.Grants.Element (1);
         begin
            if Result.Kind /= Low_Level.Object_ACL_Found
              or else not Result.Result.Policy.Is_Set
              or else not Result.Result.Policy.Policy_Owner.Is_Set
              or else US.To_String
                (Result.Result.Policy.Policy_Owner.ID.Value) /= "object-owner"
              or else Result.Result.Policy.ACL.Grants.Length /= 1
              or else not Grant.Principal.Is_Set
              or else Grant.Principal.Kind /= ACL.Canonical_User
              or else US.To_String (Grant.Principal.ID.Value) /= "principal"
              or else not Grant.Allowed.Is_Set
              or else Grant.Allowed.Value /= ACL.Full_Control
              or else US.To_String (Result.Result.Request_Charged) /=
                "requester"
            then
               raise Program_Error with "GetObjectAcl socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_ACL
                (Origin, Low_Level.Path_Style, "example-bucket", "a b",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Object_ACL_Outcome :=
              Low_Level.Execute_Get_Object_ACL
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_ACL_Found
              or else Result.Result.Policy.Is_Set
              or else US.Length (Result.Result.Request_Charged) /= 0
            then
               raise Program_Error with "GetObjectAcl outer absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_ACL
                (Origin, Low_Level.Path_Style, "example-bucket", "a b",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Object_ACL_Outcome :=
              Low_Level.Execute_Get_Object_ACL
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Object_ACL_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "object-acl-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "object-acl-error-host"
            then
               raise Program_Error with
                 "GetObjectAcl socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Object_ACL
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_ACL
                   (Origin, Low_Level.Path_Style, "example-bucket", "a b",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Get_Object_ACL_Outcome :=
                       (if Small_Limits
                        then Low_Level.Execute_Get_Object_ACL
                          (HTTP, Prepared, Timeout => 5.0,
                           Limits =>
                             --  Test-only caller policy paired with the
                             --  oversized server fixture above.
                             (Maximum_Document_Bytes => 64,
                              Maximum_Depth          => 8,
                              Maximum_Elements       => 32,
                              Maximum_Text_Bytes     => 64))
                        else Low_Level.Execute_Get_Object_ACL
                          (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Object_ACL;
         begin
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted duplicate request-charged header");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted altered request-charged header");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted empty request-charged header");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted duplicate request ID");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted duplicate host ID");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted empty request ID");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted malformed success XML");
            Must_Reject_Object_ACL
              ("GetObjectAcl accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Abac : constant Low_Level.Put_Bucket_Control_Outcome :=
              Buckets.Set_ABAC
                (HTTP, Origin, "example-bucket", Bucket_Controls.Abac_Enabled,
                 Identity, Checksum_Algorithm => "CRC32",
                 Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
            Accelerate : constant Low_Level.Put_Bucket_Control_Outcome :=
              Buckets.Set_Accelerate_Configuration
                (HTTP, Origin, "example-bucket",
                 Bucket_Controls.Accelerate_Suspended, Identity,
                 Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
            Payment : constant Low_Level.Put_Bucket_Control_Outcome :=
              Buckets.Set_Request_Payment
                (HTTP, Origin, "example-bucket", Bucket_Controls.Bucket_Owner,
                 Identity, Expected_Bucket_Owner => "123456789012",
                 Timeout => 5.0);
            Public_Access : constant Low_Level.Put_Bucket_Control_Outcome :=
              Buckets.Set_Public_Access_Block
                (HTTP, Origin, "example-bucket",
                 (Block_Public_ACLs => (Is_Set => True, Value => True),
                  Ignore_Public_ACLs => (Is_Set => True, Value => False),
                  Block_Public_Policy => (Is_Set => True, Value => True),
                  Restrict_Public_Buckets =>
                    (Is_Set => True, Value => False)),
                 Identity, Expected_Bucket_Owner => "123456789012",
                 Timeout => 5.0);
            Policy : constant Low_Level.Put_Bucket_Control_Outcome :=
              Buckets.Set_Policy
                (HTTP, Origin, "example-bucket", "policy", Identity,
                 Confirm_Remove_Self_Access =>
                   (Is_Set => True, Value => True),
                 Expected_Bucket_Owner => "123456789012", Timeout => 5.0);
         begin
            if Abac.Kind /= Low_Level.Bucket_Control_Updated
              or else Accelerate.Kind /= Low_Level.Bucket_Control_Updated
              or else Payment.Kind /= Low_Level.Bucket_Control_Updated
              or else Public_Access.Kind /= Low_Level.Bucket_Control_Updated
              or else Policy.Kind /= Low_Level.Bucket_Control_Updated
            then
               raise Program_Error with "bucket-control PUT socket mismatch";
            end if;
         end;
         declare
            Value : constant
              Bucket_Controls.Public_Access_Block_Configuration :=
                (Block_Public_ACLs => (Is_Set => True, Value => True),
                 Ignore_Public_ACLs => (Is_Set => True, Value => True),
                 Block_Public_Policy => (Is_Set => True, Value => False),
                 Restrict_Public_Buckets =>
                   (Is_Set => True, Value => False));
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Set : aliased Operations.Completion_Set (3);
            Result : Put_Public_Access_Block_Result;
         begin
            declare
               Operation : Put_Public_Access_Block_Operation :=
                 Set_Public_Access_Block
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-public-access",
                    Value,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Public_Access_Block_Response_Available
                 or else Result.Disposition /=
                   Public_Access_Block_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed PutPublicAccessBlock result mismatch";
               end if;
               Set_Public_Access_Block
                 (HTTP'Access,
                  Origin,
                  "restart-public-access",
                  Value,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Public_Access_Block_Response_Available
                 or else Result.Disposition /=
                   Public_Access_Block_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-put-public-access"
               then
                  raise Program_Error with
                    "restarted PutPublicAccessBlock result mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Put_Bucket_ABAC_Result :=
              Buckets.Set_ABAC
                (HTTP,
                 Origin,
                 "typed-abac-put",
                 Bucket_Controls.Abac_Enabled,
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /=
                 Put_Bucket_ABAC_Response_Available
              or else Result.Disposition /=
                ABAC_Mutation_Completed
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
            then
               raise Program_Error with
                 "typed PutBucketAbac result mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  ABAC parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Put_Bucket_ABAC_Result;
         begin
            declare
               Operation : Put_Bucket_ABAC_Operation :=
                 Set_ABAC
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-abac-put",
                    Bucket_Controls.Abac_Disabled,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_ABAC_Response_Available
                 or else Result.Disposition /=
                   ABAC_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed PutBucketAbac result mismatch";
               end if;
               Set_ABAC
                 (HTTP'Access,
                  Origin,
                  "restart-abac-put",
                  Bucket_Controls.Abac_Enabled,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_ABAC_Response_Available
                 or else Result.Disposition /=
                   ABAC_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-abac-put"
               then
                  raise Program_Error with
                    "restarted PutBucketAbac result mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));

            procedure Check_Invalid_Response
              (Bucket : String;
               Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
                 Flyology.Object_Storage.S3.XML.Default_Limits)
            is
               Result : constant Put_Bucket_ABAC_Result :=
                 Buckets.Set_ABAC
                   (HTTP,
                    Origin,
                    Bucket,
                    Bucket_Controls.Abac_Enabled,
                    Parameters,
                    Identity,
                    Timeout => 5.0,
                    Limits => Limits);
            begin
               if Result.Kind /= Put_Bucket_ABAC_Exchange_Failed
                 or else Result.Disposition /=
                   ABAC_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
               then
                  raise Program_Error with
                    "PutBucketAbac admitted an invalid response";
               end if;
            end Check_Invalid_Response;
         begin
            Check_Invalid_Response ("duplicate-abac-put");
            Check_Invalid_Response ("empty-abac-put");
            Check_Invalid_Response
              ("oversized-abac-put",
               --  Test-only caller policy paired with the 96-byte fixture.
               (Maximum_Document_Bytes => 64,
                Maximum_Depth          => 8,
                Maximum_Elements       => 32,
                Maximum_Text_Bytes     => 64));
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Request_Payment
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Bucket_Controls.Requester,
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Put_Bucket_ABAC_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Put_Bucket_ABAC
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "PutBucketAbac accepted a prepared request-payment request";
            end if;
         end;

         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant
              Put_Bucket_Accelerate_Configuration_Result :=
                Buckets.Set_Accelerate_Configuration
                  (HTTP,
                   Origin,
                   "typed-accelerate-put",
                   Bucket_Controls.Accelerate_Enabled,
                   Parameters,
                   Identity,
                   Timeout => 5.0);
         begin
            if Result.Kind /=
                 Put_Bucket_Accelerate_Configuration_Response_Available
              or else Result.Disposition /=
                Acceleration_Mutation_Completed
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
            then
               raise Program_Error with
                 "typed PutBucketAccelerateConfiguration result mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Acceleration parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Put_Bucket_Accelerate_Configuration_Result;
         begin
            declare
               Operation : Put_Bucket_Accelerate_Configuration_Operation :=
                 Set_Accelerate_Configuration
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-accelerate-put",
                    Bucket_Controls.Accelerate_Suspended,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_Accelerate_Configuration_Response_Available
                 or else Result.Disposition /=
                   Acceleration_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed PutBucketAccelerateConfiguration result " &
                    "mismatch";
               end if;
               Set_Accelerate_Configuration
                 (HTTP'Access,
                  Origin,
                  "restart-accelerate-put",
                  Bucket_Controls.Accelerate_Enabled,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_Accelerate_Configuration_Response_Available
                 or else Result.Disposition /=
                   Acceleration_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-accelerate-put"
               then
                  raise Program_Error with
                    "restarted PutBucketAccelerateConfiguration result " &
                    "mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));

            procedure Check_Invalid_Response
              (Bucket : String;
               Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
                 Flyology.Object_Storage.S3.XML.Default_Limits)
            is
               Result : constant
                 Put_Bucket_Accelerate_Configuration_Result :=
                   Buckets.Set_Accelerate_Configuration
                     (HTTP,
                      Origin,
                      Bucket,
                      Bucket_Controls.Accelerate_Enabled,
                      Parameters,
                      Identity,
                      Timeout => 5.0,
                      Limits => Limits);
            begin
               if Result.Kind /=
                    Put_Bucket_Accelerate_Configuration_Exchange_Failed
                 or else Result.Disposition /=
                   Acceleration_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
               then
                  raise Program_Error with
                    "PutBucketAccelerateConfiguration admitted an invalid " &
                    "response";
               end if;
            end Check_Invalid_Response;
         begin
            Check_Invalid_Response ("duplicate-accelerate-put");
            Check_Invalid_Response ("empty-accelerate-put");
            Check_Invalid_Response
              ("oversized-accelerate-put",
               --  Test-only caller policy paired with the 96-byte fixture.
               (Maximum_Document_Bytes => 64,
                Maximum_Depth          => 8,
                Maximum_Elements       => 32,
                Maximum_Text_Bytes     => 64));
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Request_Payment
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Bucket_Controls.Requester,
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Put_Bucket_Accelerate_Configuration_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Put_Bucket_Accelerate_Configuration
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "PutBucketAccelerateConfiguration accepted a prepared " &
                 "request-payment request";
            end if;
         end;

         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Put_Bucket_Request_Payment_Result :=
              Buckets.Set_Request_Payment
                (HTTP,
                 Origin,
                 "typed-request-payment-put",
                 Bucket_Controls.Requester,
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /=
                 Put_Bucket_Request_Payment_Response_Available
              or else Result.Disposition /=
                Request_Payment_Mutation_Completed
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
            then
               raise Program_Error with
                 "typed PutBucketRequestPayment result mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Requester-payment parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Put_Bucket_Request_Payment_Result;
         begin
            declare
               Operation : Put_Bucket_Request_Payment_Operation :=
                 Set_Request_Payment
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-request-payment-put",
                    Bucket_Controls.Bucket_Owner,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_Request_Payment_Response_Available
                 or else Result.Disposition /=
                   Request_Payment_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed PutBucketRequestPayment result mismatch";
               end if;
               Set_Request_Payment
                 (HTTP'Access,
                  Origin,
                  "restart-request-payment-put",
                  Bucket_Controls.Requester,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_Request_Payment_Response_Available
                 or else Result.Disposition /=
                   Request_Payment_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-request-payment-put"
               then
                  raise Program_Error with
                    "restarted PutBucketRequestPayment result mismatch";
               end if;
            end;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));

            procedure Check_Invalid_Response
              (Bucket : String;
               Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
                 Flyology.Object_Storage.S3.XML.Default_Limits)
            is
               Result : constant Put_Bucket_Request_Payment_Result :=
                 Buckets.Set_Request_Payment
                   (HTTP,
                    Origin,
                    Bucket,
                    Bucket_Controls.Requester,
                    Parameters,
                    Identity,
                    Timeout => 5.0,
                    Limits => Limits);
            begin
               if Result.Kind /= Put_Bucket_Request_Payment_Exchange_Failed
                 or else Result.Disposition /=
                   Request_Payment_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
               then
                  raise Program_Error with
                    "PutBucketRequestPayment admitted an invalid response";
               end if;
            end Check_Invalid_Response;
         begin
            Check_Invalid_Response ("duplicate-request-payment-put");
            Check_Invalid_Response ("empty-request-payment-put");
            Check_Invalid_Response
              ("oversized-request-payment-put",
               --  Test-only caller policy paired with the 96-byte fixture.
               (Maximum_Document_Bytes => 64,
                Maximum_Depth          => 8,
                Maximum_Elements       => 32,
                Maximum_Text_Bytes     => 64));
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Bucket_Controls.Abac_Enabled,
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Put_Bucket_Request_Payment_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Put_Bucket_Request_Payment
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "PutBucketRequestPayment accepted a prepared ABAC request";
            end if;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Bucket_Controls.Abac_Enabled,
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Put_Public_Access_Block_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Put_Public_Access_Block
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "PutPublicAccessBlock accepted a prepared ABAC request";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Policy
                (Origin,
                 Low_Level.Path_Style,
                 "low-level-policy",
                 "low-level-policy-document",
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Confirm_Remove_Self_Access => (others => <>),
                  Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Execute_Put_Bucket_Policy
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Bucket_Control_Updated
              or else Result.Status /= 200
            then
               raise Program_Error with
                 "low-level one-shot PutBucketPolicy mismatch";
            end if;
         end;
         declare
            function Configuration
              return Encryption.Encryption_Configuration
            is
            begin
               return Value : Encryption.Encryption_Configuration :=
                 (Is_Set => True, others => <>)
               do
                  declare
                     Rule : Encryption.Encryption_Rule := (others => <>);
                  begin
                     Rule.Default_Encryption :=
                       (Is_Set => True,
                        Algorithm => Encryption.KMS_Encryption,
                        KMS_Master_Key_ID =>
                          (Is_Set => True,
                           Value => US.To_Unbounded_String ("socket-key")));
                     Rule.Bucket_Key_Enabled :=
                       (Is_Set => True, Value => True);
                     Rule.Blocked_Types.Is_Set := True;
                     Rule.Blocked_Types.Types_Is_Set := True;
                     Rule.Blocked_Types.Types.Append
                       (Encryption.SSE_C_Blocked);
                     Value.Rules.Append (Rule);
                  end;
               end return;
            end Configuration;

            Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
         begin
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Bucket_Encryption
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Configuration,
                    (Content_MD5 => US.Null_Unbounded_String,
                     Checksum_Algorithm => US.To_Unbounded_String ("CRC32"),
                     Expected_Bucket_Owner =>
                       US.To_Unbounded_String ("123456789012")),
                    Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.Execute_Put_Bucket_Encryption
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Bucket_Control_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "low-level one-shot PutBucketEncryption mismatch";
               end if;
            end;
            declare
               Result : constant Put_Bucket_Encryption_Result :=
                 Buckets.Set_Encryption
                   (HTTP, Origin, "typed-put-encryption", Configuration,
                    Parameters, Identity, Timeout => 5.0);
            begin
               if Result.Kind /= Put_Bucket_Encryption_Response_Available
                 or else Result.Disposition /=
                   Bucket_Encryption_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "typed-put-encryption"
               then
                  raise Program_Error with
                    "typed PutBucketEncryption response mismatch";
               end if;
            end;
            declare
               Set : aliased Operations.Completion_Set (3);
               Result : Put_Bucket_Encryption_Result;
               Value : Encryption.Encryption_Configuration := Configuration;
               Operation : Put_Bucket_Encryption_Operation :=
                 Set_Encryption
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-encryption",
                    Value,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Value.Rules.Clear;
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_Encryption_Response_Available
                 or else Result.Disposition /=
                   Bucket_Encryption_Mutation_Completed
                 or else Result.Failure /= No_Failure
               then
                  raise Program_Error with
                    "composed PutBucketEncryption result mismatch";
               end if;
               Set_Encryption
                 (HTTP'Access,
                  Origin,
                  "restart-put-encryption",
                  Configuration,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_Encryption_Response_Available
                 or else Result.Disposition /=
                   Bucket_Encryption_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-put-encryption"
               then
                  raise Program_Error with
                    "restarted PutBucketEncryption result mismatch";
               end if;
            end;
            declare
               Prepared : aliased Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Bucket_Abac
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    Bucket_Controls.Abac_Enabled, (others => <>), Identity,
                    "us-east-1", "20130524T000000Z");
               Set : aliased Operations.Completion_Set (3);
               Parent : aliased Put_Bucket_Encryption_Operation
                 (Set'Access, HTTP'Access, null);
               Child : HTTP_Client.Exchange_Operation (Set'Access);
               Rejected : Boolean := False;
            begin
               begin
                  Low_Level.Put_Bucket_Encryption
                    (HTTP'Access, Prepared'Access, Parent'Access,
                     Parent'Access, HTTP_Client.Deadline_After (5.0),
                     Operation => Child);
               exception
                  when Low_Level.Invalid_Request => Rejected := True;
               end;
               if not Rejected then
                  raise Program_Error with
                    "PutBucketEncryption accepted a prepared ABAC request";
               end if;
            end;
         end;
         declare
            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Abac
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 Bucket_Controls.Abac_Enabled,
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Put_Bucket_Policy_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Put_Bucket_Policy
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "PutBucketPolicy accepted a prepared ABAC request";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Policy_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Confirm_Remove_Self_Access => (others => <>),
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Result : constant Put_Bucket_Policy_Result :=
              Buckets.Set_Policy
                (HTTP,
                 Origin,
                 "typed-policy",
                 "typed-policy",
                 Parameters,
                 Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Put_Bucket_Policy_Response_Available
              or else Result.Disposition /=
                Bucket_Policy_Mutation_Completed
              or else Result.Failure /= No_Failure
              or else Result.Admission /= HTTP_Client.Response_Observed
              or else Result.Response.Kind /=
                Low_Level.Bucket_Control_Updated
            then
               raise Program_Error with
                 "typed PutBucketPolicy response mismatch";
            end if;
         end;
         declare
            Parameters : constant Low_Level.Put_Bucket_Policy_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               Confirm_Remove_Self_Access => (others => <>),
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            --  Policy parent, HTTP exchange, and transport child.
            Set : aliased Operations.Completion_Set (3);
            Result : Put_Bucket_Policy_Result;
            Policy : String := "composed-policy-document";
         begin
            declare
               Operation : Put_Bucket_Policy_Operation :=
                 Set_Policy
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-policy",
                    Policy,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Policy := (others => 'x');
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_Policy_Response_Available
                 or else Result.Disposition /=
                   Bucket_Policy_Mutation_Completed
               then
                  raise Program_Error with
                    "composed PutBucketPolicy first result mismatch";
               end if;
               Set_Policy
                 (HTTP'Access,
                  Origin,
                  "restart-put-policy",
                  "restart-policy-document",
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Bucket_Policy_Response_Available
                 or else Result.Disposition /=
                   Bucket_Policy_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Put_Bucket_Control_Rejected
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-put-policy-request"
               then
                  raise Program_Error with
                    "composed PutBucketPolicy restart mismatch";
               end if;
            end;
         end;
         declare
            function Configuration
              return Bucket_Controls.Ownership_Controls_Configuration
            is
            begin
               return Value :
                 Bucket_Controls.Ownership_Controls_Configuration :=
                   (Is_Set => True, others => <>)
               do
                  Value.Rules.Append
                    (Bucket_Controls.Ownership_Control_Rule'
                       (Ownership => Bucket_Controls.Bucket_Owner_Preferred));
                  Value.Rules.Append
                    (Bucket_Controls.Ownership_Control_Rule'
                       (Ownership => Bucket_Controls.Object_Writer));
               end return;
            end Configuration;

            function Prepare
              (Checksum : String := ""; Owner : String := "")
               return Low_Level.Prepared_Request is
              (Low_Level.Prepare_Put_Bucket_Ownership_Controls
                 (Origin, Low_Level.Path_Style, "example-bucket",
                  Configuration,
                  (Content_MD5 => US.Null_Unbounded_String,
                   Checksum_Algorithm => US.To_Unbounded_String (Checksum),
                   Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                  Identity, "us-east-1", "20130524T000000Z"));

            procedure Must_Reject_Put_Ownership
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request := Prepare;
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
                       (if Small_Limits
                        then Low_Level.Execute_Put_Bucket_Ownership_Controls
                          (HTTP, Prepared, Timeout => 5.0,
                           Limits =>
                             --  Test-only caller response ceiling paired
                             --  with the 65-byte server fixture above.
                             (Maximum_Document_Bytes => 64,
                              Maximum_Depth          => 8,
                              Maximum_Elements       => 32,
                              Maximum_Text_Bytes     => 64))
                        else
                          Low_Level.Execute_Put_Bucket_Ownership_Controls
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Put_Ownership;
         begin
            declare
               Result : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.Execute_Put_Bucket_Ownership_Controls
                   (HTTP, Prepare ("CRC32", "123456789012"),
                    Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Bucket_Control_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "PutBucketOwnershipControls socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.Execute_Put_Bucket_Ownership_Controls
                   (HTTP, Prepare, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Put_Bucket_Control_Rejected
                 or else Result.Status /= 403
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "put-ownership-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "put-ownership-host"
               then
                  raise Program_Error with
                    "PutBucketOwnershipControls socket rejection mismatch";
               end if;
            end;
            Must_Reject_Put_Ownership
              ("PutBucketOwnershipControls accepted success body");
            Must_Reject_Put_Ownership
              ("PutBucketOwnershipControls accepted duplicate request ID");
            Must_Reject_Put_Ownership
              ("PutBucketOwnershipControls accepted duplicate host ID");
            Must_Reject_Put_Ownership
              ("PutBucketOwnershipControls accepted empty request ID");
            Must_Reject_Put_Ownership
              ("PutBucketOwnershipControls accepted oversized response",
               Small_Limits => True);
         end;
         declare
            function Configuration
              return Bucket_Controls.Ownership_Controls_Configuration
            is
            begin
               return Value :
                 Bucket_Controls.Ownership_Controls_Configuration :=
                   (Is_Set => True, others => <>)
               do
                  Value.Rules.Append
                    (Bucket_Controls.Ownership_Control_Rule'
                       (Ownership =>
                          Bucket_Controls.Bucket_Owner_Enforced));
               end return;
            end Configuration;

            Prepared : aliased Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Public_Access_Block
                (Origin,
                 Low_Level.Path_Style,
                 "example-bucket",
                 (others => <>),
                 (others => <>),
                 Identity,
                 "us-east-1",
                 "20130524T000000Z");
            Set : aliased Operations.Completion_Set (3);
            Parent : aliased Put_Bucket_Ownership_Controls_Operation
              (Set'Access, HTTP'Access, null);
            Child : HTTP_Client.Exchange_Operation (Set'Access);
            Rejected : Boolean := False;
         begin
            begin
               Low_Level.Put_Bucket_Ownership_Controls
                 (HTTP'Access,
                  Prepared'Access,
                  Parent'Access,
                  Parent'Access,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Child);
            exception
               when Low_Level.Invalid_Request => Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "PutBucketOwnershipControls accepted a public-access request";
            end if;

            declare
               Parameters : constant Low_Level.Put_Bucket_Control_Parameters :=
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012"));
               Result : Put_Bucket_Ownership_Controls_Result;
               Operation : Put_Bucket_Ownership_Controls_Operation :=
                 Set_Ownership_Controls
                   (Set'Access,
                    HTTP'Access,
                    Origin,
                    "composed-ownership",
                    Configuration,
                    Parameters,
                    Identity,
                    HTTP_Client.Deadline_After (5.0));
            begin
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_Ownership_Controls_Response_Available
                 or else Result.Disposition /=
                   Bucket_Ownership_Controls_Mutation_Completed
               then
                  raise Program_Error with
                    "composed PutBucketOwnershipControls result mismatch";
               end if;
               Set_Ownership_Controls
                 (HTTP'Access,
                  Origin,
                  "restart-ownership",
                  Configuration,
                  Parameters,
                  Identity,
                  HTTP_Client.Deadline_After (5.0),
                  Operation => Operation);
               Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                    Put_Bucket_Ownership_Controls_Response_Available
                 or else Result.Disposition /=
                   Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else US.To_String (Result.Response.Error.Request_ID) /=
                   "restarted-put-ownership"
               then
                  raise Program_Error with
                    "restarted PutBucketOwnershipControls result mismatch";
               end if;
            end;
         end;
         declare
            function Prepare
              (Checksum : String := ""; Owner : String := "")
               return Low_Level.Prepared_Request is
              (Low_Level.
                 Prepare_Create_Bucket_Metadata_Table_Configuration
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (Table_Bucket_ARN =>
                       US.To_Unbounded_String ("socket-table-bucket"),
                     Table_Name => US.To_Unbounded_String ("socket-table")),
                    (Content_MD5 => US.Null_Unbounded_String,
                     Checksum_Algorithm =>
                       US.To_Unbounded_String (Checksum),
                     Expected_Bucket_Owner =>
                       US.To_Unbounded_String (Owner)),
                    Identity, "us-east-1", "20130524T000000Z"));

            procedure Must_Reject_Create_Metadata_Table
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request := Prepare;
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
                       (if Small_Limits
                        then Low_Level.
                          Execute_Create_Bucket_Metadata_Table_Configuration
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               --  Test-only caller response ceiling paired
                               --  with the 65-byte server fixture above.
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                        else Low_Level.
                          Execute_Create_Bucket_Metadata_Table_Configuration
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response => Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Create_Metadata_Table;
         begin
            declare
               Result : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.
                   Execute_Create_Bucket_Metadata_Table_Configuration
                     (HTTP, Prepare ("CRC32", "123456789012"),
                      Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Bucket_Control_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "CreateBucketMetadataTableConfiguration socket success " &
                    "mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.
                   Execute_Create_Bucket_Metadata_Table_Configuration
                     (HTTP, Prepare, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Put_Bucket_Control_Rejected
                 or else Result.Status /= 403
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "create-metadata-table-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "create-metadata-table-host"
               then
                  raise Program_Error with
                    "CreateBucketMetadataTableConfiguration socket " &
                    "rejection mismatch";
               end if;
            end;
            Must_Reject_Create_Metadata_Table
              ("metadata-table create accepted success body");
            Must_Reject_Create_Metadata_Table
              ("metadata-table create accepted duplicate request ID");
            Must_Reject_Create_Metadata_Table
              ("metadata-table create accepted duplicate host ID");
            Must_Reject_Create_Metadata_Table
              ("metadata-table create accepted empty request ID");
            Must_Reject_Create_Metadata_Table
              ("metadata-table create accepted oversized response",
               Small_Limits => True);
         end;
         declare
            function Prepare
              (Annotation : String;
               Full_Conditions : Boolean := False)
               return Low_Level.Prepared_Request is
              (Low_Level.Prepare_Delete_Object_Annotation
                 (Origin, Low_Level.Path_Style, "example-bucket",
                  "object key", Annotation,
                  (Version_ID =>
                     (if Full_Conditions
                      then US.To_Unbounded_String ("version one")
                      else US.Null_Unbounded_String),
                   Request_Payer =>
                     (if Full_Conditions
                      then US.To_Unbounded_String ("requester")
                      else US.Null_Unbounded_String),
                   Expected_Bucket_Owner =>
                     (if Full_Conditions
                      then US.To_Unbounded_String ("123456789012")
                      else US.Null_Unbounded_String),
                   Object_If_Match =>
                     (if Full_Conditions
                      then US.To_Unbounded_String ("socket-etag")
                      else US.Null_Unbounded_String)),
                  Identity, "us-east-1", "20130524T000000Z"));

            procedure Must_Reject_Delete_Annotation
              (Annotation, Message : String;
               Small_Limits : Boolean := False)
            is
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Delete_Object_Annotation_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Delete_Object_Annotation
                            (HTTP, Prepare (Annotation), Timeout => 5.0,
                             Limits =>
                               --  Test-only caller response ceiling paired
                               --  with the 65-byte server fixture above.
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Delete_Object_Annotation
                            (HTTP, Prepare (Annotation), Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response |
                       Flyology.HTTP.Protocol_Error =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Delete_Annotation;
         begin
            declare
               Result : constant
                 Low_Level.Delete_Object_Annotation_Outcome :=
                   Low_Level.Execute_Delete_Object_Annotation
                     (HTTP, Prepare ("socket success", True),
                      Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Annotation_Deleted
                 or else Result.Status /= 204
                 or else US.To_String
                   (Result.Result.Object_Version_ID) /= "socket-generation"
                 or else US.To_String
                   (Result.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "DeleteObjectAnnotation socket success mismatch";
               end if;
            end;
            declare
               Result : constant
                 Low_Level.Delete_Object_Annotation_Outcome :=
                   Low_Level.Execute_Delete_Object_Annotation
                     (HTTP, Prepare ("socket-rejection"), Timeout => 5.0);
            begin
               if Result.Kind /=
                   Low_Level.Delete_Object_Annotation_Rejected
                 or else Result.Status /= 403
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "annotation-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "annotation-host"
               then
                  raise Program_Error with
                    "DeleteObjectAnnotation socket rejection mismatch";
               end if;
            end;
            Must_Reject_Delete_Annotation
              ("socket-body",
               "DeleteObjectAnnotation accepted success body");
            Must_Reject_Delete_Annotation
              ("socket-duplicate-version",
               "DeleteObjectAnnotation accepted duplicate version");
            Must_Reject_Delete_Annotation
              ("socket-duplicate-charged",
               "DeleteObjectAnnotation accepted duplicate charged");
            Must_Reject_Delete_Annotation
              ("socket-empty-version",
               "DeleteObjectAnnotation accepted empty version");
            Must_Reject_Delete_Annotation
              ("socket-duplicate-request",
               "DeleteObjectAnnotation accepted duplicate request ID");
            Must_Reject_Delete_Annotation
              ("socket-oversized",
               "DeleteObjectAnnotation accepted oversized response",
               Small_Limits => True);
         end;
         declare
            function Prepare
              (Version : String := ""; Full_Controls : Boolean := False;
               Present : Boolean := True)
               return Low_Level.Prepared_Request is
              (Low_Level.Prepare_Put_Object_Legal_Hold
                 (Origin, Low_Level.Path_Style, "example-bucket",
                  "object key",
                  (Is_Set => Present,
                   Status =>
                     (if Present then Object_Lock.Legal_Hold_On
                      else Object_Lock.Legal_Hold_Status_Absent)),
                  (Request_Payer =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("requester")
                      else US.Null_Unbounded_String),
                   Version_ID => US.To_Unbounded_String (Version),
                   Content_MD5 => US.Null_Unbounded_String,
                   Checksum_Algorithm =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("CRC32")
                      else US.Null_Unbounded_String),
                   Expected_Bucket_Owner =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("123456789012")
                      else US.Null_Unbounded_String)),
                  Identity, "us-east-1", "20130524T000000Z"));

            procedure Must_Reject_Put_Legal_Hold
              (Message : String; Small_Limits : Boolean := False)
            is
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Put_Object_Legal_Hold_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Put_Object_Legal_Hold
                            (HTTP, Prepare, Timeout => 5.0,
                             Limits =>
                               --  Test-only caller response ceiling paired
                               --  with the 65-byte server fixture above.
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Put_Object_Legal_Hold
                            (HTTP, Prepare, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response |
                       Flyology.HTTP.Protocol_Error =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Put_Legal_Hold;
         begin
            Objects_Testing.Check_Legal_Hold_Pre_Admission_Rejection
              (HTTP'Access, Prepared,
               --  Test/reference loopback budget, not production policy.
               HTTP_Client.Deadline_After (5.0));
            declare
               Result : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
                 Low_Level.Execute_Put_Object_Legal_Hold
                   (HTTP, Prepare ("version one", True), Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Legal_Hold_Updated
                 or else Result.Status /= 200
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "PutObjectLegalHold socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
                 Low_Level.Execute_Put_Object_Legal_Hold
                   (HTTP, Prepare ("absent", Present => False),
                    Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Legal_Hold_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "PutObjectLegalHold absent socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
                 Low_Level.Execute_Put_Object_Legal_Hold
                   (HTTP, Prepare, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Put_Object_Legal_Hold_Rejected
                 or else Result.Status /= 403
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "put-legal-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "put-legal-host"
               then
                  raise Program_Error with
                    "PutObjectLegalHold socket rejection mismatch";
               end if;
            end;
            Must_Reject_Put_Legal_Hold
              ("PutObjectLegalHold accepted success body");
            Must_Reject_Put_Legal_Hold
              ("PutObjectLegalHold accepted duplicate charged");
            Must_Reject_Put_Legal_Hold
              ("PutObjectLegalHold accepted empty charged");
            Must_Reject_Put_Legal_Hold
              ("PutObjectLegalHold accepted duplicate request ID");
            Must_Reject_Put_Legal_Hold
              ("PutObjectLegalHold accepted oversized response",
               Small_Limits => True);
            declare
               Ambiguous : Boolean := False;
            begin
               begin
                  declare
                     Unexpected : constant
                       Low_Level.Put_Object_Legal_Hold_Outcome :=
                         Low_Level.Execute_Put_Object_Legal_Hold
                           (HTTP, Prepare ("lost"), Timeout => 5.0);
                     pragma Unreferenced (Unexpected);
                  begin
                     raise Program_Error with
                       "lost PutObjectLegalHold returned a definite outcome";
                  end;
               exception
                  when Low_Level.Invalid_Request |
                       Low_Level.Invalid_Response |
                       Program_Error =>
                     raise;
                  when others =>
                     Ambiguous := True;
               end;
               if not Ambiguous then
                  raise Program_Error with
                    "lost PutObjectLegalHold was not ambiguous";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
            Value : constant Object_Lock.Legal_Hold :=
              (Is_Set => True, Status => Object_Lock.Legal_Hold_On);
            --  Derived capacity: the legal-hold parent, HTTP exchange, and
            --  HTTP's one active transport child are the only simultaneous
            --  operations in this test/reference composition.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("typed one");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            declare
               Operation : Put_Legal_Hold_Operation :=
                 Put_Legal_Hold
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "composable-legal", Value, Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Legal_Hold_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Legal_Hold_Response_Available
                 or else Result.Disposition /= Legal_Hold_Mutation_Completed
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Legal_Hold_Updated
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "composable PutObjectLegalHold result mismatch";
               end if;

               Parameters := (others => <>);
               Put_Legal_Hold
                 (HTTP'Access, Origin, "example-bucket", "composable-legal",
                  Value, Parameters, Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0), Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Legal_Hold_Response_Available
                 or else Result.Disposition /=
                   Legal_Hold_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Put_Object_Legal_Hold_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "established PutObjectLegalHold restart mismatch";
               end if;
            end;

            declare
               Result : constant Put_Legal_Hold_Result :=
                 Put_Legal_Hold
                   (HTTP, Origin, "example-bucket", "sync-legal", Value,
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    Timeout => 5.0);
            begin
               if Result.Kind /= Put_Legal_Hold_Response_Available
                 or else Result.Disposition /= Legal_Hold_Mutation_Completed
                 or else Result.Response.Kind /=
                   Low_Level.Object_Legal_Hold_Updated
               then
                  raise Program_Error with
                    "typed synchronous PutObjectLegalHold mismatch";
               end if;
            end;

            declare
               Operation : Put_Legal_Hold_Operation :=
                 Put_Legal_Hold
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "bounded-legal", Value, (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Legal_Hold_Result;
            begin
               --  Test-only ceiling forces the composable sink failure path;
               --  production retains the shared S3 XML document limit.
               Objects_Testing.Set_Response_Limit (Operation, 64);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Legal_Hold_Exchange_Failed
                 or else Result.Disposition /=
                   Legal_Hold_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded composable PutObjectLegalHold mismatch";
               end if;
            end;
         end;
         declare
            function Prepare
              (Version : String := ""; Full_Controls : Boolean := False;
               Present : Boolean := True; Bypass_Set : Boolean := False;
               Bypass : Boolean := False)
               return Low_Level.Prepared_Request is
              (Low_Level.Prepare_Put_Object_Retention
                 (Origin, Low_Level.Path_Style, "example-bucket",
                  "object key",
                  (Is_Set => Present,
                   Mode =>
                     (if Present then Object_Lock.Governance_Retention
                      else Object_Lock.Retention_Mode_Absent),
                   Retain_Until_Date =>
                     (if Present
                      then US.To_Unbounded_String
                        ("2028-02-29T23:59:59Z")
                      else US.Null_Unbounded_String)),
                  (Request_Payer =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("requester")
                      else US.Null_Unbounded_String),
                   Version_ID => US.To_Unbounded_String (Version),
                   Bypass_Governance_Retention =>
                     (Is_Set => Bypass_Set, Value => Bypass),
                   Content_MD5 => US.Null_Unbounded_String,
                   Checksum_Algorithm =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("CRC32")
                      else US.Null_Unbounded_String),
                   Expected_Bucket_Owner =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("123456789012")
                      else US.Null_Unbounded_String)),
                  Identity, "us-east-1", "20130524T000000Z"));

            procedure Must_Reject_Put_Retention
              (Message : String; Small_Limits : Boolean := False)
            is
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Put_Object_Retention_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Put_Object_Retention
                            (HTTP, Prepare, Timeout => 5.0,
                             Limits =>
                               --  Test-only caller response ceiling paired
                               --  with the 65-byte server fixture above.
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Put_Object_Retention
                            (HTTP, Prepare, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response |
                       Flyology.HTTP.Protocol_Error =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Put_Retention;
         begin
            Objects_Testing.Check_Retention_Pre_Admission_Rejection
              (HTTP'Access, Prepared,
               --  Test/reference loopback budget, not production policy.
               HTTP_Client.Deadline_After (5.0));
            declare
               Result : constant Low_Level.Put_Object_Retention_Outcome :=
                 Low_Level.Execute_Put_Object_Retention
                   (HTTP, Prepare
                      ("version one", True, Bypass_Set => True,
                       Bypass => True),
                    Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Retention_Updated
                 or else Result.Status /= 200
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "PutObjectRetention socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.Put_Object_Retention_Outcome :=
                 Low_Level.Execute_Put_Object_Retention
                   (HTTP, Prepare
                      ("absent", Present => False, Bypass_Set => True,
                       Bypass => False),
                    Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Retention_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "PutObjectRetention absent socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.Put_Object_Retention_Outcome :=
                 Low_Level.Execute_Put_Object_Retention
                   (HTTP, Prepare, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Put_Object_Retention_Rejected
                 or else Result.Status /= 403
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "put-retention-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "put-retention-host"
               then
                  raise Program_Error with
                    "PutObjectRetention socket rejection mismatch";
               end if;
            end;
            Must_Reject_Put_Retention
              ("PutObjectRetention accepted success body");
            Must_Reject_Put_Retention
              ("PutObjectRetention accepted duplicate charged");
            Must_Reject_Put_Retention
              ("PutObjectRetention accepted empty charged");
            Must_Reject_Put_Retention
              ("PutObjectRetention accepted duplicate request ID");
            Must_Reject_Put_Retention
              ("PutObjectRetention accepted oversized response",
               Small_Limits => True);
            declare
               Ambiguous : Boolean := False;
            begin
               begin
                  declare
                     Unexpected : constant
                       Low_Level.Put_Object_Retention_Outcome :=
                         Low_Level.Execute_Put_Object_Retention
                           (HTTP, Prepare ("lost"), Timeout => 5.0);
                     pragma Unreferenced (Unexpected);
                  begin
                     raise Program_Error with
                       "lost PutObjectRetention returned a definite outcome";
                  end;
               exception
                  when Low_Level.Invalid_Request |
                       Low_Level.Invalid_Response |
                       Program_Error =>
                     raise;
                  when others =>
                     Ambiguous := True;
               end;
               if not Ambiguous then
                  raise Program_Error with
                    "lost PutObjectRetention was not ambiguous";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Put_Object_Retention_Parameters;
            Value : constant Object_Lock.Retention :=
              (Is_Set => True,
               Mode => Object_Lock.Governance_Retention,
               Retain_Until_Date =>
                 US.To_Unbounded_String ("2028-02-29T23:59:59Z"));
            --  Derived capacity: the retention parent, HTTP exchange, and
            --  HTTP's one active transport child are the only simultaneous
            --  operations in this test/reference composition.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("typed one");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            declare
               Operation : Put_Retention_Operation :=
                 Put_Retention
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "composable-retention", Value, Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Retention_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Retention_Response_Available
                 or else Result.Disposition /= Retention_Mutation_Completed
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Retention_Updated
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "composable PutObjectRetention result mismatch";
               end if;

               Parameters := (others => <>);
               Put_Retention
                 (HTTP'Access, Origin, "example-bucket",
                  "composable-retention", Value, Parameters, Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0), Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Retention_Response_Available
                 or else Result.Disposition /=
                   Retention_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Put_Object_Retention_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "established PutObjectRetention restart mismatch";
               end if;
            end;

            declare
               Result : constant Put_Retention_Result :=
                 Put_Retention
                   (HTTP, Origin, "example-bucket", "sync-retention", Value,
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    Timeout => 5.0);
            begin
               if Result.Kind /= Put_Retention_Response_Available
                 or else Result.Disposition /= Retention_Mutation_Completed
                 or else Result.Response.Kind /=
                   Low_Level.Object_Retention_Updated
               then
                  raise Program_Error with
                    "typed synchronous PutObjectRetention mismatch";
               end if;
            end;

            declare
               Operation : Put_Retention_Operation :=
                 Put_Retention
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "bounded-retention", Value, (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Retention_Result;
            begin
               --  Test-only ceiling forces the composable sink failure path;
               --  production retains the shared S3 XML document limit.
               Objects_Testing.Set_Response_Limit (Operation, 64);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Retention_Exchange_Failed
                 or else Result.Disposition /=
                   Retention_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded composable PutObjectRetention mismatch";
               end if;
            end;
         end;
         declare
            function Prepare
              (Full_Controls : Boolean := False;
               Present : Boolean := True)
               return Low_Level.Prepared_Request is
              (Low_Level.Prepare_Put_Object_Lock_Configuration
                 (Origin, Low_Level.Path_Style, "example-bucket",
                  (Is_Set => Present,
                   Enabled =>
                     (if Present then Object_Lock.Object_Lock_Enabled
                      else Object_Lock.Object_Lock_Enabled_Absent),
                   Rule =>
                     (Is_Set => Present,
                      Default_Value =>
                        (Is_Set => Present,
                         Mode =>
                           (if Present
                            then Object_Lock.Governance_Retention
                            else Object_Lock.Retention_Mode_Absent),
                         Days =>
                           (Is_Set => Present,
                            Text =>
                              (if Present
                               then US.To_Unbounded_String ("30")
                               else US.Null_Unbounded_String)),
                         Years => (others => <>)))),
                  (Request_Payer =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("requester")
                      else US.Null_Unbounded_String),
                   Token =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("socket-lock-token")
                      else US.Null_Unbounded_String),
                   Content_MD5 => US.Null_Unbounded_String,
                   Checksum_Algorithm =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("CRC32")
                      else US.Null_Unbounded_String),
                   Expected_Bucket_Owner =>
                     (if Full_Controls
                      then US.To_Unbounded_String ("123456789012")
                      else US.Null_Unbounded_String)),
                  Identity, "us-east-1", "20130524T000000Z"));

            procedure Must_Reject_Put_Lock_Configuration
              (Message : String; Small_Limits : Boolean := False)
            is
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Put_Object_Lock_Configuration_Outcome :=
                         (if Small_Limits
                          then
                            Low_Level.Execute_Put_Object_Lock_Configuration
                              (HTTP, Prepare, Timeout => 5.0,
                               Limits =>
                                 --  Test-only caller response ceiling paired
                                 --  with the 65-byte server fixture above.
                                 (Maximum_Document_Bytes => 64,
                                  Maximum_Depth          => 8,
                                  Maximum_Elements       => 32,
                                  Maximum_Text_Bytes     => 64))
                          else
                            Low_Level.Execute_Put_Object_Lock_Configuration
                              (HTTP, Prepare, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response |
                       Flyology.HTTP.Protocol_Error =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Put_Lock_Configuration;
         begin
            Buckets_Testing.
              Check_Object_Lock_Configuration_Pre_Admission_Rejection
                (HTTP'Access, Prepared,
                 --  Test/reference loopback budget, not production policy.
                 HTTP_Client.Deadline_After (5.0));
            declare
               Result : constant
                 Low_Level.Put_Object_Lock_Configuration_Outcome :=
                   Low_Level.Execute_Put_Object_Lock_Configuration
                     (HTTP, Prepare (Full_Controls => True), Timeout => 5.0);
            begin
               if Result.Kind /=
                   Low_Level.Object_Lock_Configuration_Updated
                 or else Result.Status /= 200
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "PutObjectLockConfiguration socket success mismatch";
               end if;
            end;
            declare
               Result : constant
                 Low_Level.Put_Object_Lock_Configuration_Outcome :=
                   Low_Level.Execute_Put_Object_Lock_Configuration
                     (HTTP, Prepare (Present => False), Timeout => 5.0);
            begin
               if Result.Kind /=
                   Low_Level.Object_Lock_Configuration_Updated
                 or else Result.Status /= 200
               then
                  raise Program_Error with
                    "PutObjectLockConfiguration absent success mismatch";
               end if;
            end;
            declare
               Result : constant
                 Low_Level.Put_Object_Lock_Configuration_Outcome :=
                   Low_Level.Execute_Put_Object_Lock_Configuration
                     (HTTP, Prepare, Timeout => 5.0);
            begin
               if Result.Kind /=
                   Low_Level.Put_Object_Lock_Configuration_Rejected
                 or else Result.Status /= 403
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "put-lock-config-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "put-lock-config-host"
               then
                  raise Program_Error with
                    "PutObjectLockConfiguration rejection mismatch";
               end if;
            end;
            Must_Reject_Put_Lock_Configuration
              ("PutObjectLockConfiguration accepted success body");
            Must_Reject_Put_Lock_Configuration
              ("PutObjectLockConfiguration accepted duplicate charged");
            Must_Reject_Put_Lock_Configuration
              ("PutObjectLockConfiguration accepted empty charged");
            Must_Reject_Put_Lock_Configuration
              ("PutObjectLockConfiguration accepted duplicate request ID");
            Must_Reject_Put_Lock_Configuration
              ("PutObjectLockConfiguration accepted oversized response",
               Small_Limits => True);
            declare
               Ambiguous : Boolean := False;
            begin
               begin
                  declare
                     Unexpected : constant
                       Low_Level.Put_Object_Lock_Configuration_Outcome :=
                         Low_Level.Execute_Put_Object_Lock_Configuration
                           (HTTP, Prepare, Timeout => 5.0);
                     pragma Unreferenced (Unexpected);
                  begin
                     raise Program_Error with
                       "lost PutObjectLockConfiguration returned outcome";
                  end;
               exception
                  when Low_Level.Invalid_Request |
                       Low_Level.Invalid_Response |
                       Program_Error =>
                     raise;
                  when others =>
                     Ambiguous := True;
               end;
               if not Ambiguous then
                  raise Program_Error with
                    "lost PutObjectLockConfiguration was not ambiguous";
               end if;
            end;
         end;
         declare
            --  Test/reference payload mirrors the maintained low-level wire
            --  fixture; 30 days is not a production retention policy.
            Value : constant Object_Lock.Object_Lock_Configuration :=
              (Is_Set  => True,
               Enabled => Object_Lock.Object_Lock_Enabled,
               Rule    =>
                 (Is_Set => True,
                  Default_Value =>
                    (Is_Set => True,
                     Mode   => Object_Lock.Governance_Retention,
                     Days   =>
                       (Is_Set => True,
                        Text => US.To_Unbounded_String ("30")),
                     Years  => (others => <>))));
            Parameters : Low_Level.Put_Object_Lock_Configuration_Parameters :=
              (Request_Payer => US.To_Unbounded_String ("requester"),
               others => <>);
            --  Derived capacity: provider parent, HTTP exchange, and HTTP's
            --  one active transport child are the only simultaneous items.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            declare
               Operation : Put_Object_Lock_Configuration_Operation :=
                 Put_Object_Lock_Configuration
                   (Set'Access, HTTP'Access, Origin, "composable-lock", Value,
                    Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Object_Lock_Configuration_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                   Put_Object_Lock_Configuration_Response_Available
                 or else Result.Disposition /=
                   Object_Lock_Configuration_Mutation_Completed
                 or else Result.Response.Kind /=
                   Low_Level.Object_Lock_Configuration_Updated
                 or else US.To_String
                   (Result.Response.Result.Request_Charged) /= "requester"
               then
                  raise Program_Error with
                    "composable PutObjectLockConfiguration mismatch";
               end if;

               Parameters := (others => <>);
               Put_Object_Lock_Configuration
                 (HTTP'Access, Origin, "composable-lock", Value, Parameters,
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0), Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                   Put_Object_Lock_Configuration_Response_Available
                 or else Result.Disposition /=
                   Object_Lock_Configuration_Mutation_Definitely_Not_Applied
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Put_Object_Lock_Configuration_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "established PutObjectLockConfiguration restart mismatch";
               end if;
            end;

            declare
               Result : constant Put_Object_Lock_Configuration_Result :=
                 Put_Object_Lock_Configuration
                   (HTTP, Origin, "sync-lock", Value, (others => <>),
                    Identity,
                    --  Test/reference loopback budget, not production policy.
                    Timeout => 5.0);
            begin
               if Result.Kind /=
                   Put_Object_Lock_Configuration_Response_Available
                 or else Result.Disposition /=
                   Object_Lock_Configuration_Mutation_Completed
                 or else Result.Response.Kind /=
                   Low_Level.Object_Lock_Configuration_Updated
               then
                  raise Program_Error with
                    "typed synchronous PutObjectLockConfiguration mismatch";
               end if;
            end;

            declare
               Operation : Put_Object_Lock_Configuration_Operation :=
                 Put_Object_Lock_Configuration
                   (Set'Access, HTTP'Access, Origin, "bounded-lock", Value,
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Put_Object_Lock_Configuration_Result;
            begin
               --  Test-only ceiling forces the composable sink failure path;
               --  production retains the shared S3 XML document limit.
               Buckets_Testing.Set_Response_Limit (Operation, 64);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Put_Object_Lock_Configuration_Exchange_Failed
                 or else Result.Disposition /=
                   Object_Lock_Configuration_Mutation_Outcome_Unknown
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded composable PutObjectLockConfiguration mismatch";
               end if;
            end;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
                    Buckets.Get_Accelerate_Configuration
                      (HTTP, Origin, "example-bucket", Identity,
                       Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "GetBucketAccelerateConfiguration accepted duplicate " &
                 "request-charged headers";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Legal_Hold
                (Origin, Low_Level.Path_Style, "example-bucket", "object",
                 (Version_ID => US.To_Unbounded_String ("version one"),
                  Request_Payer => US.To_Unbounded_String ("requester"),
                  Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
              Low_Level.Execute_Get_Object_Legal_Hold
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Legal_Hold_Found
              or else not Result.Legal_Hold.Is_Set
              or else Result.Legal_Hold.Status /= Object_Lock.Legal_Hold_On
            then
               raise Program_Error with
                 "GetObjectLegalHold socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Legal_Hold
                (Origin, Low_Level.Path_Style, "example-bucket", "object",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
              Low_Level.Execute_Get_Object_Legal_Hold
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Legal_Hold_Found
              or else not Result.Legal_Hold.Is_Set
              or else Result.Legal_Hold.Status /=
                Object_Lock.Legal_Hold_Status_Absent
            then
               raise Program_Error with
                 "GetObjectLegalHold absent status mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Legal_Hold
                (Origin, Low_Level.Path_Style, "example-bucket", "object",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
              Low_Level.Execute_Get_Object_Legal_Hold
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Object_Legal_Hold_Rejected
              or else Result.Status /= 403
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "legal-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "legal-error-host"
            then
               raise Program_Error with
                 "GetObjectLegalHold socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Legal_Hold
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Legal_Hold
                   (Origin, Low_Level.Path_Style, "example-bucket", "object",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Object_Legal_Hold_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Get_Object_Legal_Hold
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Get_Object_Legal_Hold
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Legal_Hold;
         begin
            Must_Reject_Legal_Hold
              ("GetObjectLegalHold accepted duplicate request identifier");
            Must_Reject_Legal_Hold
              ("GetObjectLegalHold accepted duplicate host identifier");
            Must_Reject_Legal_Hold
              ("GetObjectLegalHold accepted empty request identifier");
            Must_Reject_Legal_Hold
              ("GetObjectLegalHold accepted malformed success XML");
            Must_Reject_Legal_Hold
              ("GetObjectLegalHold accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
            --  Derived capacity: the legal-hold parent, HTTP exchange, and
            --  HTTP's one active transport child are the only simultaneous
            --  operations in this test/reference composition.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("typed one");
            declare
               Operation : Get_Legal_Hold_Operation :=
                 Get_Legal_Hold
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "composable-legal", Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Legal_Hold_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Legal_Hold_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Legal_Hold_Found
                 or else not Result.Response.Legal_Hold.Is_Set
                 or else Result.Response.Legal_Hold.Status /=
                   Object_Lock.Legal_Hold_On
               then
                  raise Program_Error with
                    "composable GetObjectLegalHold result mismatch";
               end if;

               Parameters := (others => <>);
               Get_Legal_Hold
                 (HTTP'Access, Origin, "example-bucket", "composable-legal",
                  Parameters, Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0), Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Legal_Hold_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Object_Legal_Hold_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "established GetObjectLegalHold restart mismatch";
               end if;
            end;

            declare
               Result : constant Get_Legal_Hold_Result :=
                 Get_Legal_Hold
                   (HTTP, Origin, "example-bucket", "sync-legal",
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    Timeout => 5.0);
            begin
               if Result.Kind /= Get_Legal_Hold_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Legal_Hold_Found
                 or else Result.Response.Legal_Hold.Status /=
                   Object_Lock.Legal_Hold_Off
               then
                  raise Program_Error with
                    "typed synchronous GetObjectLegalHold mismatch";
               end if;
            end;

            declare
               Operation : Get_Legal_Hold_Operation :=
                 Get_Legal_Hold
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "bounded-legal", (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Legal_Hold_Result;
            begin
               --  Test-only ceiling forces the composable sink failure path;
               --  production retains the shared S3 XML document limit.
               Objects_Testing.Set_Response_Limit (Operation, 64);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Legal_Hold_Exchange_Failed
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded composable GetObjectLegalHold mismatch";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Retention
                (Origin, Low_Level.Path_Style, "example-bucket", "object",
                 (Version_ID => US.To_Unbounded_String ("version one"),
                  Request_Payer => US.To_Unbounded_String ("requester"),
                  Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Get_Object_Retention_Outcome :=
              Low_Level.Execute_Get_Object_Retention
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Retention_Found
              or else not Result.Retention.Is_Set
              or else Result.Retention.Mode /=
                Object_Lock.Governance_Retention
              or else US.To_String (Result.Retention.Retain_Until_Date) /=
                "2027-01-02T03:04:05Z"
            then
               raise Program_Error with
                 "GetObjectRetention socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Retention
                (Origin, Low_Level.Path_Style, "example-bucket", "object",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Object_Retention_Outcome :=
              Low_Level.Execute_Get_Object_Retention
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Retention_Found
              or else not Result.Retention.Is_Set
              or else Result.Retention.Mode /=
                Object_Lock.Retention_Mode_Absent
              or else US.Length (Result.Retention.Retain_Until_Date) /= 0
            then
               raise Program_Error with
                 "GetObjectRetention nested absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Retention
                (Origin, Low_Level.Path_Style, "example-bucket", "object",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Get_Object_Retention_Outcome :=
              Low_Level.Execute_Get_Object_Retention
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Get_Object_Retention_Rejected
              or else Result.Status /= 403
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "retention-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "retention-error-host"
            then
               raise Program_Error with
                 "GetObjectRetention socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Retention
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Retention
                   (Origin, Low_Level.Path_Style, "example-bucket", "object",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Object_Retention_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Get_Object_Retention
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Get_Object_Retention
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Retention;
         begin
            Must_Reject_Retention
              ("GetObjectRetention accepted duplicate request identifier");
            Must_Reject_Retention
              ("GetObjectRetention accepted duplicate host identifier");
            Must_Reject_Retention
              ("GetObjectRetention accepted empty request identifier");
            Must_Reject_Retention
              ("GetObjectRetention accepted malformed success XML");
            Must_Reject_Retention
              ("GetObjectRetention accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            Parameters : Low_Level.Get_Object_Retention_Parameters;
            --  Derived capacity: the retention parent, HTTP exchange, and
            --  HTTP's one active transport child are the only simultaneous
            --  operations in this test/reference composition.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("typed one");
            declare
               Operation : Get_Retention_Operation :=
                 Get_Retention
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "composable-retention", Parameters, Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Retention_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Retention_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Retention_Found
                 or else not Result.Response.Retention.Is_Set
                 or else Result.Response.Retention.Mode /=
                   Object_Lock.Governance_Retention
                 or else US.To_String
                   (Result.Response.Retention.Retain_Until_Date) /=
                   "2028-02-29T23:59:59Z"
               then
                  raise Program_Error with
                    "composable GetObjectRetention result mismatch";
               end if;

               Parameters := (others => <>);
               Get_Retention
                 (HTTP'Access, Origin, "example-bucket",
                  "composable-retention", Parameters, Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0), Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Retention_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Object_Retention_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "established GetObjectRetention restart mismatch";
               end if;
            end;

            declare
               Result : constant Get_Retention_Result :=
                 Get_Retention
                   (HTTP, Origin, "example-bucket", "sync-retention",
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    Timeout => 5.0);
            begin
               if Result.Kind /= Get_Retention_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Retention_Found
                 or else Result.Response.Retention.Mode /=
                   Object_Lock.Compliance_Retention
               then
                  raise Program_Error with
                    "typed synchronous GetObjectRetention mismatch";
               end if;
            end;

            declare
               Operation : Get_Retention_Operation :=
                 Get_Retention
                   (Set'Access, HTTP'Access, Origin, "example-bucket",
                    "bounded-retention", (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Retention_Result;
            begin
               --  Test-only ceiling forces the composable sink failure path;
               --  production retains the shared S3 XML document limit.
               Objects_Testing.Set_Response_Limit (Operation, 64);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Retention_Exchange_Failed
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded composable GetObjectRetention mismatch";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Lock_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String ("123456789012")),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant
              Low_Level.Get_Object_Lock_Configuration_Outcome :=
                Low_Level.Execute_Get_Object_Lock_Configuration
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Lock_Configuration_Found
              or else not Result.Configuration.Is_Set
              or else Result.Configuration.Enabled /=
                Object_Lock.Object_Lock_Enabled
              or else not Result.Configuration.Rule.Is_Set
              or else not Result.Configuration.Rule.Default_Value.Is_Set
              or else Result.Configuration.Rule.Default_Value.Mode /=
                Object_Lock.Compliance_Retention
              or else not Result.Configuration.Rule.Default_Value.Days.Is_Set
              or else US.To_String
                (Result.Configuration.Rule.Default_Value.Days.Text) /=
                "+123456789012345678901234567890"
              or else not Result.Configuration.Rule.Default_Value.Years.Is_Set
              or else US.To_String
                (Result.Configuration.Rule.Default_Value.Years.Text) /=
                "-0002"
            then
               raise Program_Error with
                 "GetObjectLockConfiguration socket success mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Lock_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant
              Low_Level.Get_Object_Lock_Configuration_Outcome :=
                Low_Level.Execute_Get_Object_Lock_Configuration
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Lock_Configuration_Found
              or else not Result.Configuration.Is_Set
              or else Result.Configuration.Enabled /=
                Object_Lock.Object_Lock_Enabled_Absent
              or else Result.Configuration.Rule.Is_Set
            then
               raise Program_Error with
                 "GetObjectLockConfiguration nested absence mismatch";
            end if;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Lock_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (others => <>), Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant
              Low_Level.Get_Object_Lock_Configuration_Outcome :=
                Low_Level.Execute_Get_Object_Lock_Configuration
                  (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /=
                Low_Level.Get_Object_Lock_Configuration_Rejected
              or else Result.Status /= 403
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "lock-configuration-error-request"
              or else US.To_String (Result.Error.Host_ID) /=
                "lock-configuration-error-host"
            then
               raise Program_Error with
                 "GetObjectLockConfiguration socket rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_Lock_Configuration
              (Message : String; Small_Limits : Boolean := False)
            is
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Lock_Configuration
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Object_Lock_Configuration_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Get_Object_Lock_Configuration
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Get_Object_Lock_Configuration
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_Lock_Configuration;
         begin
            Must_Reject_Lock_Configuration
              ("GetObjectLockConfiguration accepted duplicate request " &
               "identifier");
            Must_Reject_Lock_Configuration
              ("GetObjectLockConfiguration accepted duplicate host " &
               "identifier");
            Must_Reject_Lock_Configuration
              ("GetObjectLockConfiguration accepted empty request " &
               "identifier");
            Must_Reject_Lock_Configuration
              ("GetObjectLockConfiguration accepted malformed success XML");
            Must_Reject_Lock_Configuration
              ("GetObjectLockConfiguration accepted oversized success XML",
               Small_Limits => True);
         end;
         declare
            --  Derived capacity: provider parent, HTTP exchange, and HTTP's
            --  one active transport child are the only simultaneous items.
            Set : aliased Flyology.Operations.Completion_Set (3);
         begin
            declare
               Operation : Get_Object_Lock_Configuration_Operation :=
                 Get_Object_Lock_Configuration
                   (Set'Access, HTTP'Access, Origin, "composable-lock",
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Object_Lock_Configuration_Result;
            begin
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                   Get_Object_Lock_Configuration_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Lock_Configuration_Found
                 or else Result.Response.Configuration.Enabled /=
                   Object_Lock.Object_Lock_Enabled
               then
                  raise Program_Error with
                    "composable GetObjectLockConfiguration mismatch";
               end if;

               Get_Object_Lock_Configuration
                 (HTTP'Access, Origin, "composable-lock", (others => <>),
                  Identity,
                  --  Test/reference loopback budget, not production policy.
                  HTTP_Client.Deadline_After (5.0), Operation => Operation);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /=
                   Get_Object_Lock_Configuration_Response_Available
                 or else Result.Failure /= Authorization_Failed
                 or else Result.Response.Kind /=
                   Low_Level.Get_Object_Lock_Configuration_Rejected
                 or else US.To_String (Result.Response.Error.Code) /=
                   "AccessDenied"
               then
                  raise Program_Error with
                    "established GetObjectLockConfiguration restart mismatch";
               end if;
            end;

            declare
               Result : constant Get_Object_Lock_Configuration_Result :=
                 Get_Object_Lock_Configuration
                   (HTTP, Origin, "sync-lock", (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    Timeout => 5.0);
            begin
               if Result.Kind /=
                   Get_Object_Lock_Configuration_Response_Available
                 or else Result.Failure /= No_Failure
                 or else Result.Response.Kind /=
                   Low_Level.Object_Lock_Configuration_Found
                 or else Result.Response.Configuration.Enabled /=
                   Object_Lock.Object_Lock_Enabled
               then
                  raise Program_Error with
                    "typed synchronous GetObjectLockConfiguration mismatch";
               end if;
            end;

            declare
               Operation : Get_Object_Lock_Configuration_Operation :=
                 Get_Object_Lock_Configuration
                   (Set'Access, HTTP'Access, Origin, "bounded-lock",
                    (others => <>), Identity,
                    --  Test/reference loopback budget, not production policy.
                    HTTP_Client.Deadline_After (5.0));
               Result : Get_Object_Lock_Configuration_Result;
            begin
               --  Test-only ceiling forces the composable sink failure path;
               --  production retains the shared S3 XML document limit.
               Buckets_Testing.Set_Response_Limit (Operation, 64);
               Flyology.Operations.Wait_All (Set);
               Finish (Operation, Result);
               if Result.Kind /= Get_Object_Lock_Configuration_Exchange_Failed
                 or else Result.Failure /= Corrupt_Or_Invalid_Response
                 or else Result.Admission /= HTTP_Client.Response_Observed
                 or else Result.HTTP_Result /= HTTP_Client.Response_Sink_Failed
               then
                  raise Program_Error with
                    "bounded composable GetObjectLockConfiguration mismatch";
               end if;
            end;
         end;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket_CORS
                (Origin, Low_Level.Path_Style, "example-bucket",
                 (Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity, "us-east-1", "20130524T000000Z");
            Result : constant Low_Level.Delete_Bucket_CORS_Outcome :=
              Low_Level.Execute_Delete_Bucket_CORS
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Delete_Bucket_CORS_Rejected
              or else Result.Status /= 403
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
              or else US.To_String (Result.Error.Request_ID) /=
                "cors-request"
              or else US.To_String (Result.Error.Host_ID) /= "cors-host"
            then
               raise Program_Error with
                 "DeleteBucketCors typed rejection mismatch";
            end if;
         end;
         declare
            procedure Must_Reject_CORS
              (Message : String; Small_Limits : Boolean := False)
            is
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Prepared : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Delete_Bucket_CORS
                         (Origin, Low_Level.Path_Style, "example-bucket",
                          (Expected_Bucket_Owner =>
                             US.Null_Unbounded_String),
                          Identity, "us-east-1", "20130524T000000Z");
                     Ignored : constant
                       Low_Level.Delete_Bucket_CORS_Outcome :=
                         (if Small_Limits
                          then Low_Level.Execute_Delete_Bucket_CORS
                            (HTTP, Prepared, Timeout => 5.0,
                             Limits =>
                               (Maximum_Document_Bytes => 64,
                                Maximum_Depth          => 8,
                                Maximum_Elements       => 32,
                                Maximum_Text_Bytes     => 64))
                          else Low_Level.Execute_Delete_Bucket_CORS
                            (HTTP, Prepared, Timeout => 5.0));
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Must_Reject_CORS;
         begin
            Must_Reject_CORS
              ("DeleteBucketCors accepted duplicate response identifier");
            Must_Reject_CORS
              ("DeleteBucketCors accepted duplicate host identifier");
            Must_Reject_CORS
              ("DeleteBucketCors accepted empty response identifier");
            Must_Reject_CORS
              ("DeleteBucketCors accepted malformed error body");
            Must_Reject_CORS
              ("DeleteBucketCors accepted oversized error body",
               Small_Limits => True);
         end;
         HTTP_Client.Shutdown (HTTP);
      end;
   end Run_Client;

   procedure Run_And_Report is
   begin
      Run_Client;
      Clients.Report (True);
   exception
      when Occurrence : others =>
         Clients.Report
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Run_And_Report;

   Server_Passed : Boolean;
   Client_Passed : Boolean;
   Server_Detail : US.Unbounded_String;
   Client_Detail : US.Unbounded_String;
begin
   Objects_Testing.Check_Put_Certainty_Corpus;
   Objects_Testing.Check_Delete_Certainty_Corpus;
   Objects_Testing.Check_Delete_Objects_Certainty_Corpus;
   Transfers_Testing.Check_Create_Multipart_Certainty_Corpus;
   Transfers_Testing.Check_Upload_Part_Certainty_Corpus;
   Transfers_Testing.Check_Upload_Part_Copy_Certainty_Corpus;
   Transfers_Testing.Check_Complete_Multipart_Certainty_Corpus;
   Transfers_Testing.Check_Abort_Multipart_Certainty_Corpus;
   Objects_Testing.Check_List_Objects_Result_Corpus;
   Buckets_Testing.Check_List_Buckets_Result_Corpus;
   Buckets_Testing.Check_Create_Bucket_Certainty_Corpus;
   Buckets_Testing.Check_Delete_Bucket_Certainty_Corpus;
   Buckets_Testing.Check_Head_Bucket_Result_Corpus;
   Buckets_Testing.Check_Get_Bucket_Location_Result_Corpus;
   Buckets_Testing.Check_Get_Bucket_Policy_Result_Corpus;
   Buckets_Testing.Check_Get_Bucket_Policy_Status_Result_Corpus;
   Buckets_Testing.Check_Get_Bucket_Request_Payment_Result_Corpus;
   Buckets_Testing.Check_Bucket_Policy_Certainty_Corpus;
   Buckets_Testing.Check_Public_Access_Block_Certainty_Corpus;
   Buckets_Testing.Check_ABAC_Certainty_Corpus;
   Buckets_Testing.Check_Acceleration_Certainty_Corpus;
   Buckets_Testing.Check_Request_Payment_Certainty_Corpus;
   Buckets_Testing.Check_Ownership_Controls_Certainty_Corpus;
   Buckets_Testing.Check_Bucket_Encryption_Result_Corpus;
   Buckets_Testing.Check_Delete_Bucket_Lifecycle_Certainty_Corpus;
   Buckets_Testing.Check_Bucket_CORS_Result_Corpus;
   Buckets_Testing.Check_Object_Lock_Configuration_Certainty_Corpus;
   Buckets_Testing.Check_Get_Bucket_Versioning_Result_Corpus;
   Buckets_Testing.Check_Put_Bucket_Versioning_Certainty_Corpus;
   Buckets_Testing.Check_Bucket_Tagging_Certainty_Corpus;
   Objects_Testing.Check_Object_Tagging_Certainty_Corpus;
   Objects_Testing.Check_Legal_Hold_Certainty_Corpus;
   Objects_Testing.Check_Retention_Certainty_Corpus;
   Transfers_Testing.Check_List_Parts_Result_Corpus;
   Transfers_Testing.Check_List_Multipart_Uploads_Result_Corpus;
   Transfers_Testing.Check_Copy_Result_Corpus;
   Run_And_Report;
   declare
      task Lightweight_Client is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Lightweight_Client;

      task body Lightweight_Client is
      begin
         Run_And_Report;
      end Lightweight_Client;
   begin
      null;
   end;
   Clients.Wait_All (Client_Passed, Client_Detail);
   State.Wait_Done (Server_Passed, Server_Detail);
   if not Client_Passed then
      raise Program_Error with US.To_String (Client_Detail);
   elsif not Server_Passed then
      raise Program_Error with US.To_String (Server_Detail);
   end if;
   Ada.Text_IO.Put_Line ("S3 HTTP socket corpus: OK");
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("S3 HTTP socket corpus failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_HTTP_Socket_Corpus;
