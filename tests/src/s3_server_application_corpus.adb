with Ada.Calendar;
with Ada.Containers;
with Ada.Calendar.Formatting;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.MD5;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP.Server;
with Flyology.HTTP.Server.Applications;
with Flyology.IO;
with Flyology.IO.Sockets;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Memory;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Analytics;
with Flyology.Object_Storage.S3.Annotations;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Encryption;
with
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Inventory_Configuration_XML;
with Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_XML;
with Flyology.Object_Storage.S3.Generated_Put_Bucket_Website_XML;
with Flyology.Object_Storage.S3.Generated_Put_Bucket_Logging_XML;
with Flyology.Object_Storage.S3.Intelligent_Tiering;
with Flyology.Object_Storage.S3.Inventory;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Logging;
with Flyology.Object_Storage.S3.Metadata_Configurations;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.Metrics;
with Flyology.Object_Storage.S3.Notifications;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.Replication;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.S3.Website;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.MFA;
with Flyology.Object_Storage.Server.Metadata_Results;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;

procedure S3_Server_Application_Corpus is
   package HTTP_Server renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Sockets renames Flyology.IO.Sockets;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Buckets renames Flyology.Object_Storage.S3.Buckets;
   package Bucket_Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;
   package Checksum_Policy renames
     Flyology.Object_Storage.S3.Checksum_Policy;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Attributes renames Flyology.Object_Storage.S3.Attributes;
   package Analytics renames Flyology.Object_Storage.S3.Analytics;
   package Annotations renames Flyology.Object_Storage.S3.Annotations;
   package ACL renames Flyology.Object_Storage.S3.ACL;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Encryption renames Flyology.Object_Storage.S3.Encryption;
   package Generated_Inventory renames
     Flyology.Object_Storage.S3.
       Generated_Put_Bucket_Inventory_Configuration_XML;
   package Generated_Directory_Buckets renames
     Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_XML;
   package Generated_Website renames
     Flyology.Object_Storage.S3.Generated_Put_Bucket_Website_XML;
   package Generated_Logging renames
     Flyology.Object_Storage.S3.Generated_Put_Bucket_Logging_XML;
   package Intelligent_Tiering renames
     Flyology.Object_Storage.S3.Intelligent_Tiering;
   package Inventory renames Flyology.Object_Storage.S3.Inventory;
   package Lifecycle renames Flyology.Object_Storage.S3.Lifecycle;
   package Listings renames Flyology.Object_Storage.S3.Listings;
   package Logging renames Flyology.Object_Storage.S3.Logging;
   package Metadata_Configurations renames
     Flyology.Object_Storage.S3.Metadata_Configurations;
   package Metadata_Tables renames
     Flyology.Object_Storage.S3.Metadata_Tables;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package Multipart_Uploads renames
     Flyology.Object_Storage.S3.Multipart_Uploads;
   package Metrics renames Flyology.Object_Storage.S3.Metrics;
   package Notifications renames Flyology.Object_Storage.S3.Notifications;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package Replication renames Flyology.Object_Storage.S3.Replication;
   package XML renames Flyology.Object_Storage.S3.XML;
   package Backends renames Flyology.Object_Storage.Backends;
   package Tagging renames Flyology.Object_Storage.S3.Tagging;
   package Tags renames Flyology.Object_Storage.Tags;
   package Versions renames Flyology.Object_Storage.S3.Versions;
   package Versioning renames Flyology.Object_Storage.S3.Versioning;
   package Website renames Flyology.Object_Storage.S3.Website;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package MFA renames Flyology.Object_Storage.Server.MFA;
   package Metadata_Results renames
     Flyology.Object_Storage.Server.Metadata_Results;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Containers.Count_Type;
   use type Ada.Calendar.Time;
   use type Flyology.Object_Storage.Status;
   use type Flyology.Object_Storage.Metadata_Time;
   use type Flyology.Object_Storage.Checksum_Algorithm;
   use type Checksum_Policy.Algorithm;
   use type Bucket_Controls.Abac_Status;
   use type Bucket_Controls.Accelerate_Status;
   use type Bucket_Controls.Payer;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;
   use type Object_Lock.Legal_Hold_Status;
   use type Object_Lock.Object_Lock_Enabled_Status;
   use type Object_Lock.Retention_Mode;
   use type Backends.Version_Delete_Kind;
   use type MFA.Authorization_Status;
   use type Metadata_Configurations.Expiration_State;
   use type Metadata_Configurations.Inventory_Configuration_State;
   use type Tags.Tag_Vectors.Vector;
   use type ACL.Grantee_Type;
   use type ACL.Permission;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Access_Key : constant String := "AKIDEXAMPLE";
   Secret_Key : constant String :=
     "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
   Timestamp  : constant String := "20130524T000000Z";
   Region     : constant String := "us-east-1";
   Host       : constant String := "localhost:9000";
   Maximum_Header_Text_Bytes : constant Positive := 8_192;
   --  The pinned S3 corpus and production admission helper share this exact
   --  header-text bound. Exact-limit and one-past vectors guard compatibility
   --  if that project-policy limit is ever reviewed for change.

   function Content_MD5 (Value : String) return String is
      Digest : constant GNAT.MD5.Binary_Message_Digest :=
        GNAT.MD5.Digest (Value);
      Alphabet : constant String :=
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      Result : String (1 .. 24);
      Output : Positive := Result'First;

      function Byte (Index : Ada.Streams.Stream_Element_Offset)
        return Natural is (Natural (Digest (Index)));

      procedure Encode_Three
        (First : Ada.Streams.Stream_Element_Offset)
      is
         A : constant Natural := Byte (First);
         B : constant Natural := Byte
           (Ada.Streams.Stream_Element_Offset'Succ (First));
         C : constant Natural := Byte
           (Ada.Streams.Stream_Element_Offset'Succ
              (Ada.Streams.Stream_Element_Offset'Succ (First)));
      begin
         Result (Output) := Alphabet (A / 4 + 1);
         Result (Output + 1) := Alphabet ((A mod 4) * 16 + B / 16 + 1);
         Result (Output + 2) := Alphabet ((B mod 16) * 4 + C / 64 + 1);
         Result (Output + 3) := Alphabet (C mod 64 + 1);
         Output := Output + 4;
      end Encode_Three;
   begin
      Encode_Three (1);
      Encode_Three (4);
      Encode_Three (7);
      Encode_Three (10);
      Encode_Three (13);
      declare
         A : constant Natural := Byte (16);
      begin
         Result (21) := Alphabet (A / 4 + 1);
         Result (22) := Alphabet ((A mod 4) * 16 + 1);
         Result (23 .. 24) := "==";
      end;
      return Result;
   end Content_MD5;

   function Checksum_Header
     (Algorithm : Checksum_Policy.Algorithm) return String is
     (case Algorithm is
         when Core.CRC32 => "x-amz-checksum-crc32",
         when Core.CRC32C => "x-amz-checksum-crc32c",
         when Core.CRC64NVME => "x-amz-checksum-crc64nvme",
         when Core.SHA1 => "x-amz-checksum-sha1",
         when Core.SHA256 => "x-amz-checksum-sha256",
         when Core.SHA512 => "x-amz-checksum-sha512",
         when Core.MD5 => "x-amz-checksum-md5",
         when Core.XXHASH64 => "x-amz-checksum-xxhash64",
         when Core.XXHASH3 => "x-amz-checksum-xxhash3",
         when Core.XXHASH128 => "x-amz-checksum-xxhash128");

   function Checksum_Value
     (Algorithm : Checksum_Policy.Algorithm;
      Value     : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Algorithm,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   SSE_Test_Key : constant String :=
     Checksum_Value (Core.SHA256, "object-read-sse-c-key");
   SSE_Test_Key_Bytes : constant Checksums.Decode_Result :=
     Checksums.Decode_Base64 (SSE_Test_Key, Core.SHA256);
   SSE_Test_Key_MD5 : constant String := Checksums.Encode_Base64
     (Checksums.Compute
        (Core.MD5, Checksums.Raw_Bytes (SSE_Test_Key_Bytes.Value)));
   --  This deterministic test/reference vector is derived from the S3 SSE-C
   --  wire contract: the 32-byte key is Base64 encoded and the MD5 is computed
   --  over those decoded bytes. Changing it affects only corpus
   --  reproducibility, while keeping key/digest coupling independently
   --  computed.

   function Storage_Algorithm
     (Algorithm : Checksum_Policy.Algorithm)
      return Flyology.Object_Storage.Checksum_Algorithm is
     (case Algorithm is
         when Core.CRC32 => Flyology.Object_Storage.Checksum_CRC32,
         when Core.CRC32C => Flyology.Object_Storage.Checksum_CRC32C,
         when Core.CRC64NVME => Flyology.Object_Storage.Checksum_CRC64NVME,
         when Core.SHA1 => Flyology.Object_Storage.Checksum_SHA1,
         when Core.SHA256 => Flyology.Object_Storage.Checksum_SHA256,
         when Core.SHA512 => Flyology.Object_Storage.Checksum_SHA512,
         when Core.MD5 => Flyology.Object_Storage.Checksum_MD5,
         when Core.XXHASH64 => Flyology.Object_Storage.Checksum_XXHASH64,
         when Core.XXHASH3 => Flyology.Object_Storage.Checksum_XXHASH3,
         when Core.XXHASH128 => Flyology.Object_Storage.Checksum_XXHASH128);
   type Key_Array is array (Positive range <>) of US.Unbounded_String;
   Listing_Keys : constant Key_Array :=
     (US.To_Unbounded_String ("list/a"),
      US.To_Unbounded_String ("list/b"),
      US.To_Unbounded_String ("list/sub/c"));
   Listing_Buckets : constant Key_Array :=
     (US.To_Unbounded_String ("list-zeta-bucket"),
      US.To_Unbounded_String ("unrelated-bucket"),
      US.To_Unbounded_String ("list-alpha-bucket"));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function S3_Checksum
     (Value : String; Algorithm : Checksums.Algorithm) return String
   is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Value'Length));
   begin
      for Index in Value'Range loop
         Data
           (Ada.Streams.Stream_Element_Offset
              (Index - Value'First + 1)) :=
            Ada.Streams.Stream_Element (Character'Pos (Value (Index)));
      end loop;
      return Checksums.Encode_Base64
        (Checksums.Compute (Algorithm, Data));
   end S3_Checksum;

   function CRC64NVME (Value : String) return String is
     (S3_Checksum (Value, Checksums.Policy.Core.CRC64NVME));

   function SHA256_Checksum (Value : String) return String is
     (S3_Checksum (Value, Checksums.Policy.Core.SHA256));

   function HTTP_Date
     (Value : Flyology.Object_Storage.Unix_Time) return String
   is
      type Short_Name is new String (1 .. 3);
      Weekdays : constant array (Natural range 0 .. 6) of Short_Name :=
        ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun");
      Months : constant array (Ada.Calendar.Month_Number) of Short_Name :=
        (1 => "Jan", 2 => "Feb", 3 => "Mar", 4 => "Apr",
         5 => "May", 6 => "Jun", 7 => "Jul", 8 => "Aug",
         9 => "Sep", 10 => "Oct", 11 => "Nov", 12 => "Dec");
      Epoch : constant Ada.Calendar.Time :=
        Ada.Calendar.Formatting.Time_Of
          (1970, 1, 1, 0, 0, 0, Time_Zone => 0);
      Date : constant Ada.Calendar.Time := Epoch + Duration (Value);
      Image : constant String := Ada.Calendar.Formatting.Image
        (Date, Include_Time_Fraction => False, Time_Zone => 0);
      Month : constant Ada.Calendar.Month_Number :=
        Ada.Calendar.Formatting.Month (Date, Time_Zone => 0);
   begin
      return String
        (Weekdays (Natural ((Value / 86_400 + 3) mod 7))) & ", " &
        Image (Image'First + 8 .. Image'First + 9) & " " &
        String (Months (Month)) & " " &
        Image (Image'First .. Image'First + 3) & " " &
        Image (Image'First + 11 .. Image'First + 18) & " GMT";
   end HTTP_Date;

   type Memory_Transport is limited new HTTP_Server.Transport with record
      Input       : US.Unbounded_String;
      Output      : US.Unbounded_String;
      Receive_Max : Natural := Natural'Last;
   end record;

   overriding procedure Receive
     (Item    : in out Memory_Transport;
      Data    : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token);

   overriding procedure Send_All
     (Item    : in out Memory_Transport;
      Data    : Ada.Streams.Stream_Element_Array;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token);

   overriding procedure Receive
     (Item    : in out Memory_Transport;
      Data    : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
      Available : constant String := US.To_String (Item.Input);
      Count     : Natural;
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Available'Length = 0 then
         return;
      end if;
      Count := Natural'Min
        (Natural (Data'Length),
         Natural'Min (Available'Length, Item.Receive_Max));
      for Index in 1 .. Count loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Index - 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Available (Index)));
      end loop;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count - 1);
      Item.Input :=
        (if Count = Available'Length then US.Null_Unbounded_String
         else US.To_Unbounded_String
           (Available (Count + 1 .. Available'Last)));
   end Receive;

   overriding procedure Send_All
     (Item    : in out Memory_Transport;
      Data    : Ada.Streams.Stream_Element_Array;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
   begin
      for Value of Data loop
         US.Append (Item.Output, Character'Val (Value));
      end loop;
   end Send_All;

   function Fixed_Clock return Ada.Calendar.Time is
     (Ada.Calendar.Formatting.Time_Of
        (2013, 5, 24, 0, 0, 0, Time_Zone => 0));

   type MFA_Mode is
     (MFA_Allow_Root, MFA_Reject_Root, MFA_Unavailable, MFA_Raise);

   type Test_MFA_Verifier is limited new MFA.Verifier with record
      Mode  : MFA_Mode := MFA_Allow_Root;
      Calls : Natural := 0;
   end record;

   overriding procedure Verify
     (Item    : in out Test_MFA_Verifier;
      Principal : String;
      Credential : String;
      Secure_Transport : Boolean;
      Result  : out MFA.Authorization_Status)
   is
   begin
      Item.Calls := Item.Calls + 1;
      if Item.Mode = MFA_Raise then
         raise Program_Error with "MFA verifier sentinel";
      elsif not Secure_Transport then
         Result := MFA.Insecure_Transport;
      elsif Item.Mode = MFA_Unavailable then
         Result := MFA.Verifier_Unavailable;
      elsif Item.Mode = MFA_Reject_Root
        or else Principal /= "test-principal"
      then
         Result := MFA.Not_Root_Owner;
      elsif Credential = "device 123456" then
         Result := MFA.Authorized;
      else
         Result := MFA.Invalid_Credential;
      end if;
   end Verify;

   type Metadata_Provider_Mode is
     (Metadata_Provider_Succeeds, Metadata_Provider_Fails,
      Metadata_Provider_Raises);

   type Test_Metadata_Provider is limited new Metadata_Results.Provider with
   record
      Mode             : Metadata_Provider_Mode := Metadata_Provider_Succeeds;
      Create_Legacy_Calls : Natural := 0;
      Create_Current_Calls : Natural := 0;
      Inventory_Calls  : Natural := 0;
      Journal_Calls    : Natural := 0;
      Annotation_Calls : Natural := 0;
      Inventory_Observed          : Boolean := False;
      Journal_Observed            : Boolean := False;
      Annotation_Observed         : Boolean := False;
      Inventory_Previous_Observed : Boolean := False;
      Journal_Previous_Observed   : Boolean := False;
      Annotation_Previous_Observed : Boolean := False;
   end record;

   overriding procedure Create_Legacy
     (Item          : in out Test_Metadata_Provider;
      Bucket        : String;
      Request       : Metadata_Tables.S3_Tables_Destination;
      Configuration : out
        Metadata_Configurations.Metadata_Configuration_Request;
      Legacy_Result : out
        Metadata_Tables.Metadata_Table_Configuration_Result;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Flyology.Object_Storage.Status);

   overriding procedure Create_Current
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Request        : Metadata_Configurations.
        Metadata_Configuration_Request;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status);

   overriding procedure Update_Inventory
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Configuration  : Metadata_Configurations.
        Metadata_Configuration_Request;
      Previous       : Metadata_Configurations.Metadata_Configuration;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status);

   overriding procedure Update_Journal
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Configuration  : Metadata_Configurations.
        Metadata_Configuration_Request;
      Previous       : Metadata_Configurations.Metadata_Configuration;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status);

   overriding procedure Update_Annotation
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Configuration  : Metadata_Configurations.
        Metadata_Configuration_Request;
      Previous       : Metadata_Configurations.Metadata_Configuration;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status);

   function Metadata_Request return
     Metadata_Configurations.Metadata_Configuration_Request is
     (Metadata_Configurations.Parse_Create
        ("<MetadataConfiguration>" &
         "<JournalTableConfiguration><RecordExpiration>" &
         "<Expiration>ENABLED</Expiration><Days>30</Days>" &
         "</RecordExpiration><EncryptionConfiguration>" &
         "<SseAlgorithm>AES256</SseAlgorithm>" &
         "</EncryptionConfiguration></JournalTableConfiguration>" &
         "</MetadataConfiguration>", XML.Default_Limits));

   function Metadata_Result
     (Status : String) return
      Metadata_Configurations.Metadata_Configuration is
     (Metadata_Configurations.Parse
        ("<GetBucketMetadataConfigurationResult>" &
         "<MetadataConfigurationResult><DestinationResult>" &
         "<TableBucketType>customer</TableBucketType>" &
         "<TableBucketArn>arn:metadata</TableBucketArn>" &
         "<TableNamespace>metadata</TableNamespace>" &
         "</DestinationResult><JournalTableConfigurationResult>" &
         "<TableStatus>" & Status & "</TableStatus>" &
         "<TableName>journal</TableName><RecordExpiration>" &
         "<Expiration>ENABLED</Expiration><Days>30</Days>" &
         "</RecordExpiration></JournalTableConfigurationResult>" &
         "<InventoryTableConfigurationResult>" &
         "<ConfigurationState>ENABLED</ConfigurationState>" &
         "</InventoryTableConfigurationResult>" &
         "<AnnotationTableConfigurationResult>" &
         "<ConfigurationState>DISABLED</ConfigurationState>" &
         "</AnnotationTableConfigurationResult>" &
         "</MetadataConfigurationResult>" &
         "</GetBucketMetadataConfigurationResult>", XML.Default_Limits));

   function Legacy_Metadata_Result return
     Metadata_Tables.Metadata_Table_Configuration_Result is
     (Metadata_Tables.Parse
        ("<GetBucketMetadataTableConfigurationResult>" &
         "<MetadataTableConfigurationResult>" &
         "<S3TablesDestinationResult>" &
         "<TableBucketArn>arn:legacy</TableBucketArn>" &
         "<TableName>legacy</TableName>" &
         "<TableArn>arn:legacy:table</TableArn>" &
         "<TableNamespace>legacy</TableNamespace>" &
         "</S3TablesDestinationResult>" &
         "</MetadataTableConfigurationResult><Status>ACTIVE</Status>" &
         "</GetBucketMetadataTableConfigurationResult>",
         XML.Default_Limits));

   procedure Complete_Metadata_Provider_Call
     (Item   : Test_Metadata_Provider;
      Result : out Flyology.Object_Storage.Status) is
   begin
      if Item.Mode = Metadata_Provider_Raises then
         raise Program_Error with "metadata provider sentinel";
      elsif Item.Mode = Metadata_Provider_Fails then
         Result := Flyology.Object_Storage.Backend_Unavailable;
      else
         Result := Flyology.Object_Storage.Success;
      end if;
   end Complete_Metadata_Provider_Call;

   overriding procedure Create_Legacy
     (Item          : in out Test_Metadata_Provider;
      Bucket        : String;
      Request       : Metadata_Tables.S3_Tables_Destination;
      Configuration : out
        Metadata_Configurations.Metadata_Configuration_Request;
      Legacy_Result : out
        Metadata_Tables.Metadata_Table_Configuration_Result;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Flyology.Object_Storage.Status)
   is
      pragma Unreferenced (Bucket, Request, Token, Deadline);
   begin
      Item.Create_Legacy_Calls := Item.Create_Legacy_Calls + 1;
      Configuration := Metadata_Request;
      Legacy_Result := Legacy_Metadata_Result;
      Current_Result := Metadata_Result ("LEGACY");
      Complete_Metadata_Provider_Call (Item, Result);
   end Create_Legacy;

   overriding procedure Create_Current
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Request        : Metadata_Configurations.
        Metadata_Configuration_Request;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status)
   is
      pragma Unreferenced (Bucket, Request, Token, Deadline);
   begin
      Item.Create_Current_Calls := Item.Create_Current_Calls + 1;
      Current_Result := Metadata_Result ("CURRENT");
      Complete_Metadata_Provider_Call (Item, Result);
   end Create_Current;

   overriding procedure Update_Inventory
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Configuration  : Metadata_Configurations.
        Metadata_Configuration_Request;
      Previous       : Metadata_Configurations.Metadata_Configuration;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status)
   is
      pragma Unreferenced (Bucket, Token, Deadline);
   begin
      Item.Inventory_Calls := Item.Inventory_Calls + 1;
      Item.Inventory_Previous_Observed :=
        US.To_String (Previous.Journal.Table_Status) = "LEGACY";
      Item.Inventory_Observed :=
        Configuration.Inventory.Is_Set
        and then Configuration.Inventory.Configuration_State =
          Metadata_Configurations.Inventory_Enabled
        and then Configuration.Journal.Expiration.Expiration =
          Metadata_Configurations.Expiration_Enabled
        and then Configuration.Journal.Encryption.Is_Set
        and then not Configuration.Annotation.Is_Set;
      Current_Result := Metadata_Result ("INVENTORY");
      Complete_Metadata_Provider_Call (Item, Result);
   end Update_Inventory;

   overriding procedure Update_Journal
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Configuration  : Metadata_Configurations.
        Metadata_Configuration_Request;
      Previous       : Metadata_Configurations.Metadata_Configuration;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status)
   is
      pragma Unreferenced (Bucket, Token, Deadline);
   begin
      Item.Journal_Calls := Item.Journal_Calls + 1;
      Item.Journal_Previous_Observed :=
        US.To_String (Previous.Journal.Table_Status) = "INVENTORY";
      Item.Journal_Observed :=
        Configuration.Journal.Expiration.Expiration =
          Metadata_Configurations.Expiration_Disabled
        and then Configuration.Journal.Encryption.Is_Set
        and then Configuration.Inventory.Is_Set
        and then Configuration.Inventory.Configuration_State =
          Metadata_Configurations.Inventory_Enabled
        and then not Configuration.Annotation.Is_Set;
      Current_Result := Metadata_Result ("JOURNAL");
      Complete_Metadata_Provider_Call (Item, Result);
   end Update_Journal;

   overriding procedure Update_Annotation
     (Item           : in out Test_Metadata_Provider;
      Bucket         : String;
      Configuration  : Metadata_Configurations.
        Metadata_Configuration_Request;
      Previous       : Metadata_Configurations.Metadata_Configuration;
      Current_Result : out
        Metadata_Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Flyology.Object_Storage.Status)
   is
      pragma Unreferenced (Bucket, Token, Deadline);
   begin
      Item.Annotation_Calls := Item.Annotation_Calls + 1;
      Item.Annotation_Previous_Observed :=
        US.To_String (Previous.Journal.Table_Status) = "JOURNAL";
      Item.Annotation_Observed :=
        Configuration.Annotation.Is_Set
        and then US.To_String (Configuration.Annotation.Role.Value) =
          "metadata-role"
        and then Configuration.Inventory.Is_Set
        and then Configuration.Inventory.Configuration_State =
          Metadata_Configurations.Inventory_Enabled
        and then Configuration.Journal.Expiration.Expiration =
          Metadata_Configurations.Expiration_Disabled
        and then Configuration.Journal.Encryption.Is_Set;
      Current_Result := Metadata_Result ("ANNOTATION");
      Complete_Metadata_Provider_Call (Item, Result);
   end Update_Annotation;

   --  Test-reference generation capacity: the established sixteen corpus
   --  generations plus one retained-version CopyObject destination.
   Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 8,
      Object_Capacity => 17,
      Byte_Capacity   => 24 * 1_024 * 1_024);
   Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Access_Key, Secret_Key, Principal => "test-principal");
   MFA_Policy : aliased Test_MFA_Verifier;
   Metadata_Provider : aliased Test_Metadata_Provider;
   Rules : constant Authentication.Policy :=
     (Expected_Region    => US.To_Unbounded_String (Region),
      Maximum_Clock_Skew => 1.0);

   package S3_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type            =>
        Flyology.Object_Storage.Backends.Memory.Store,
      Store                   => Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials             => Credentials,
      MFA_Verifier            => MFA_Policy'Unchecked_Access,
      Rules                   => Rules,
      Clock                   => Fixed_Clock,
      Metadata_Provider       => Metadata_Provider'Unchecked_Access);

   package No_Metadata_App is new
     Flyology.Object_Storage.Server.S3_Applications
       (Backend_Type            =>
          Flyology.Object_Storage.Backends.Memory.Store,
        Store                   => Store,
        Credential_Provider_Type => Static_Credentials.Provider,
        Credentials             => Credentials,
        MFA_Verifier            => MFA_Policy'Unchecked_Access,
        Rules                   => Rules,
        Clock                   => Fixed_Clock);

   package No_MFA_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type            =>
        Flyology.Object_Storage.Backends.Memory.Store,
      Store                   => Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials             => Credentials,
      Rules                   => Rules,
      Clock                   => Fixed_Clock);

   No_Query : constant SigV4.Name_Value_Array (1 .. 0) := (others => <>);

   function Signed_Request
     (Method       : String;
      Target       : String;
      Payload      : String;
      Extra_Headers : String := "";
      Query_Name    : String := "";
      Query_Value   : String := "";
      Hash_Override : String := "";
      Chunked       : Boolean := False;
      Expect        : Boolean := False;
      Corrupt_Signature : Boolean := False) return String
   is
      Payload_Hash : constant String :=
        (if Hash_Override'Length > 0 then Hash_Override
         else SigV4.SHA256_Hex (Payload));

      function Extra_Header_Count return Natural is
         Result : Natural := 0;
         Cursor : Integer := Extra_Headers'First;
      begin
         while Cursor <= Extra_Headers'Last loop
            declare
               Ending : constant Natural := Ada.Strings.Fixed.Index
                 (Extra_Headers, CRLF, From => Cursor);
            begin
               if Ending = 0 then
                  raise Program_Error with
                    "test Extra_Headers must end each field with CRLF";
               end if;
               Result := Result + 1;
               Cursor := Integer (Ending) + CRLF'Length;
            end;
         end loop;
         return Result;
      end Extra_Header_Count;

      Extra_Count : constant Natural := Extra_Header_Count;
      Headers : SigV4.Name_Value_Array (1 .. 3 + Extra_Count);
      Query : constant SigV4.Name_Value_Array :=
        (if Query_Name'Length = 0 then No_Query
         else (1 => SigV4.Pair (Query_Name, Query_Value)));
      Wire_Body : constant String :=
        (if not Chunked then Payload
         elsif Payload'Length = 0 then "0" & CRLF & CRLF
         else Ada.Strings.Fixed.Trim
           (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
           Payload & CRLF & "0" & CRLF & CRLF);
   begin
      Headers (1) := SigV4.Pair ("host", Host);
      Headers (2) := SigV4.Pair ("x-amz-content-sha256", Payload_Hash);
      Headers (3) := SigV4.Pair ("x-amz-date", Timestamp);
      if Extra_Count > 0 then
         declare
            Cursor : Integer := Extra_Headers'First;
         begin
            for Index in 1 .. Extra_Count loop
               declare
                  Ending : constant Natural := Ada.Strings.Fixed.Index
                    (Extra_Headers, CRLF, From => Cursor);
                  Line : constant String :=
                    Extra_Headers (Cursor .. Integer (Ending) - 1);
                  Colon : constant Natural :=
                    Ada.Strings.Fixed.Index (Line, ":");
               begin
                  if Colon = 0 or else Colon = Line'First then
                     raise Program_Error with
                       "test Extra_Headers contains a malformed field";
                  end if;
                  Headers (3 + Index) := SigV4.Pair
                    (Line (Line'First .. Integer (Colon) - 1),
                     Ada.Strings.Fixed.Trim
                       (Line (Integer (Colon) + 1 .. Line'Last),
                        Ada.Strings.Both));
                  Cursor := Integer (Ending) + CRLF'Length;
               end;
            end loop;
         end;
      end if;
      declare
         Signing : constant SigV4.Signing_Result := SigV4.Sign
           (Method, Target, Query, Headers, Payload_Hash, Access_Key,
            Secret_Key, Region, Timestamp);
         Authorization : String := US.To_String (Signing.Authorization);
      begin
         if Corrupt_Signature then
            Authorization (Authorization'Last) :=
              (if Authorization (Authorization'Last) = '0' then '1' else '0');
         end if;
         return Method & " " & Target &
           (if Query_Name'Length = 0 then ""
            else "?" & Query_Name & "=" & Query_Value) &
           " HTTP/1.1" & CRLF &
           "Host: " & Host & CRLF &
           "x-amz-date: " & Timestamp & CRLF &
           "x-amz-content-sha256: " & Payload_Hash & CRLF &
           "Authorization: " & Authorization & CRLF & Extra_Headers &
           (if Expect then "Expect: 100-continue" & CRLF else "") &
           (if Chunked then "Transfer-Encoding: chunked" & CRLF
            else "Content-Length: " &
              Ada.Strings.Fixed.Trim
                (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF) &
           "Connection: close" & CRLF & CRLF & Wire_Body;
      end;
   end Signed_Request;

   function Signed_Request_With_Unsigned_Amazon_Header
     (Target       : String;
      Payload      : String;
      Header_Name  : String;
      Header_Value : String) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      --  This is deliberately the only helper that emits an x-amz-* field
      --  which is absent from SignedHeaders.  It models a control injected
      --  after signing; ordinary request helpers sign every physical field.
      return "PUT " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        Header_Name & ": " & Header_Value & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Expect: 100-continue" & CRLF &
        "Content-Length: " &
        Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Request_With_Unsigned_Amazon_Header;

   function Signed_Put_Declared_Length_Request
     (Target : String; Length : String) return String
   is
      Payload_Hash : constant String := SigV4.Empty_Payload_Hash;
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target & " HTTP/1.1" & CRLF & "Host: " & Host &
        CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: " & Length & CRLF & "Connection: close" & CRLF &
        CRLF;
   end Signed_Put_Declared_Length_Request;

   function Signed_Malformed_Chunk_Put_Request
     (Target : String; Payload : String) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target & " HTTP/1.1" & CRLF & "Host: " & Host &
        CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Transfer-Encoding: chunked" & CRLF & "Connection: close" & CRLF &
        CRLF & Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        Payload & "XX0" & CRLF & CRLF;
   end Signed_Malformed_Chunk_Put_Request;

   function Signed_Undeclared_Trailer_Put_Request
     (Target : String; Payload : String) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target & " HTTP/1.1" & CRLF & "Host: " & Host &
        CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Transfer-Encoding: chunked" & CRLF & "Connection: close" & CRLF &
        CRLF & Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        Payload & CRLF & "0" & CRLF & "x-amz-checksum-crc32: " &
        Checksum_Value (Core.CRC32, Payload) & CRLF & CRLF;
   end Signed_Undeclared_Trailer_Put_Request;

   function Signed_Put_Object_Trailer_Request
     (Target           : String;
      Payload          : String;
      Algorithm        : Checksum_Policy.Algorithm;
      Checksum         : String;
      Include_Trailer  : Boolean := True;
      Duplicate        : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Algorithm_Name : constant String :=
        Checksum_Policy.Wire_Name (Algorithm);
      Checksum_Name : constant String := Checksum_Header (Algorithm);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("content-md5", Content_MD5 (Payload)),
         SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", Algorithm_Name),
         SigV4.Pair ("x-amz-trailer", Checksum_Name));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Wire_Body : US.Unbounded_String;
   begin
      for Value of Payload loop
         US.Append (Wire_Body, "1" & CRLF & Value & CRLF);
      end loop;
      US.Append (Wire_Body, "0" & CRLF);
      if Include_Trailer then
         US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         if Duplicate then
            US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         end if;
      end if;
      US.Append (Wire_Body, CRLF);
      return "PUT " & Target & " HTTP/1.1" & CRLF & "Host: " & Host &
        CRLF & "Content-MD5: " & Content_MD5 (Payload) & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-sdk-checksum-algorithm: " & Algorithm_Name & CRLF &
        "x-amz-trailer: " & Checksum_Name & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Transfer-Encoding: chunked" & CRLF & "Connection: close" & CRLF &
        CRLF & US.To_String (Wire_Body);
   end Signed_Put_Object_Trailer_Request;

   function Signed_Delete_Objects_Request
     (Payload       : String;
      Include_MD5   : Boolean := True;
      MD5_Value     : String := "";
      Extra_Headers : String := "";
      Bucket        : String := "/delete-bucket") return String
   is
      Digest : constant String :=
        (if MD5_Value'Length = 0 then Content_MD5 (Payload) else MD5_Value);
   begin
      return Signed_Request
        ("POST", Bucket, Payload,
         Extra_Headers =>
           (if Include_MD5 then "Content-MD5: " & Digest & CRLF else "") &
           Extra_Headers,
         Query_Name => "delete");
   end Signed_Delete_Objects_Request;

   --  Keep large request bodies on the heap so the signed server corpus does
   --  not turn the Ada secondary stack into an accidental payload limit.
   function Signed_Buffered_Request
     (Method, Target, Payload : String) return US.Unbounded_String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Result : US.Unbounded_String := US.To_Unbounded_String
        (Method & " " & Target & " HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF &
         "x-amz-date: " & Timestamp & CRLF &
         "x-amz-content-sha256: " & Payload_Hash & CRLF &
         "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
         "Content-Length: " &
         Ada.Strings.Fixed.Trim
           (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      US.Append (Result, Payload);
      return Result;
   end Signed_Buffered_Request;

   function Signed_Create_Bucket_Request
     (Target       : String;
      Payload      : String;
      Header_Name  : String := "";
      Header_Value : String := "";
      Second_Value : String := "";
      Corrupt_Signature : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers : constant SigV4.Name_Value_Array :=
        (if Header_Name'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         elsif Second_Value'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair (Header_Name, Header_Value))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair (Header_Name, Header_Value),
            SigV4.Pair (Header_Name, Second_Value)));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Authorization : String := US.To_String (Signing.Authorization);
   begin
      if Corrupt_Signature then
         Authorization (Authorization'Last) :=
           (if Authorization (Authorization'Last) = '0' then '1' else '0');
      end if;
      return "PUT " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if Header_Name'Length = 0 then ""
         else Header_Name & ": " & Header_Value & CRLF) &
        (if Second_Value'Length = 0 then ""
         else Header_Name & ": " & Second_Value & CRLF) &
        "Authorization: " & Authorization & CRLF &
        "Content-Length: " &
          Ada.Strings.Fixed.Trim
            (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Create_Bucket_Request;

   function Signed_Delete_Object_Request
     (Target       : String;
      Query        : SigV4.Name_Value_Array := No_Query;
      Header_Name  : String := "";
      Header_Value : String := "";
      Second_Value : String := "";
      Corrupt_Signature : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Header_Name'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         elsif Second_Value'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair (Header_Name, Header_Value))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair (Header_Name, Header_Value),
            SigV4.Pair (Header_Name, Second_Value)));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("DELETE", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
      Authorization : String := US.To_String (Signing.Authorization);
   begin
      if Corrupt_Signature then
         Authorization (Authorization'Last) :=
           (if Authorization (Authorization'Last) = '0' then '1' else '0');
      end if;
      return "DELETE " & Target &
        (if Query_Text'Length = 0 then "" else "?" & Query_Text) &
        " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if Header_Name'Length = 0 then ""
         else Header_Name & ": " & Header_Value & CRLF) &
        (if Second_Value'Length = 0 then ""
         else Header_Name & ": " & Second_Value & CRLF) &
        "Authorization: " & Authorization & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Delete_Object_Request;

   function Signed_Bucket_Request
     (Method         : String;
      Target         : String;
      Expected_Owner : String := "";
      Second_Owner   : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Expected_Owner'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         elsif Second_Owner'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair
              ("x-amz-expected-bucket-owner", Expected_Owner))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair
              ("x-amz-expected-bucket-owner", Expected_Owner),
            SigV4.Pair
              ("x-amz-expected-bucket-owner", Second_Owner)));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return Method & " " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if Expected_Owner'Length = 0 then ""
         else "x-amz-expected-bucket-owner: " & Expected_Owner & CRLF) &
        (if Second_Owner'Length = 0 then ""
         else "x-amz-expected-bucket-owner: " & Second_Owner & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Bucket_Request;

   function Signed_Head_SSE_C_Request
     (Algorithm : String;
      Key       : String;
      Key_MD5   : String;
      Method    : String := "HEAD") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-algorithm", Algorithm),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-key", Key),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-key-md5", Key_MD5),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, "/test-bucket/object", No_Query, Headers, Payload_Hash,
         Access_Key, Secret_Key, Region, Timestamp);
   begin
      return Method & " /test-bucket/object HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-server-side-encryption-customer-algorithm: " &
        Algorithm & CRLF &
        "x-amz-server-side-encryption-customer-key: " & Key & CRLF &
        "x-amz-server-side-encryption-customer-key-md5: " & Key_MD5 &
        CRLF & "Authorization: " & US.To_String (Signing.Authorization) &
        CRLF & "Content-Length: 0" & CRLF & "Connection: close" & CRLF &
        CRLF;
   end Signed_Head_SSE_C_Request;

   function Signed_Copy_Request
     (Target       : String;
      Copy_Source  : String;
      If_Match     : String := "";
      With_X_ID    : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if If_Match'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-copy-source", Copy_Source),
            SigV4.Pair ("x-amz-date", Timestamp))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-copy-source", Copy_Source),
            SigV4.Pair ("x-amz-copy-source-if-match", If_Match),
            SigV4.Pair ("x-amz-date", Timestamp)));
      Query : constant SigV4.Name_Value_Array :=
        (if With_X_ID
         then (1 => SigV4.Pair ("x-id", "CopyObject"))
         else No_Query);
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target &
        (if With_X_ID then "?x-id=CopyObject" else "") &
        " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-copy-source: " & Copy_Source & CRLF &
        (if If_Match'Length = 0 then ""
         else "x-amz-copy-source-if-match: " & If_Match & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Copy_Request;

   function Signed_Copy_Member_Request
     (Target       : String;
      Copy_Source  : String;
      Header_Name  : String;
      Header_Value : String;
      Second_Value : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Second_Value'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-copy-source", Copy_Source),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair (Header_Name, Header_Value))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-copy-source", Copy_Source),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair (Header_Name, Header_Value),
            SigV4.Pair (Header_Name, Second_Value)));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-copy-source: " & Copy_Source & CRLF &
        Header_Name & ": " & Header_Value & CRLF &
        (if Second_Value'Length = 0 then ""
         else Header_Name & ": " & Second_Value & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Copy_Member_Request;

   function Signed_Copy_Headers_Request
     (Target      : String;
      Copy_Source : String;
      Extra       : SigV4.Name_Value_Array) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : SigV4.Name_Value_Array (1 .. 4 + Extra'Length);
      Request : US.Unbounded_String;
   begin
      Headers (1) := SigV4.Pair ("host", Host);
      Headers (2) := SigV4.Pair ("x-amz-content-sha256", Payload_Hash);
      Headers (3) := SigV4.Pair ("x-amz-copy-source", Copy_Source);
      Headers (4) := SigV4.Pair ("x-amz-date", Timestamp);
      for Index in Extra'Range loop
         Headers (4 + Index - Extra'First + 1) := Extra (Index);
      end loop;
      declare
         Signing : constant SigV4.Signing_Result := SigV4.Sign
           ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
            Secret_Key, Region, Timestamp);
      begin
         Request := US.To_Unbounded_String
           ("PUT " & Target & " HTTP/1.1" & CRLF &
            "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
            "x-amz-content-sha256: " & Payload_Hash & CRLF &
            "x-amz-copy-source: " & Copy_Source & CRLF);
         for Item of Extra loop
            US.Append
              (Request, US.To_String (Item.Name) & ": " &
               US.To_String (Item.Value) & CRLF);
         end loop;
         US.Append
           (Request,
            "Authorization: " & US.To_String (Signing.Authorization) &
            CRLF & "Content-Length: 0" & CRLF & "Connection: close" &
            CRLF & CRLF);
         return US.To_String (Request);
      end;
   end Signed_Copy_Headers_Request;

   function Signed_Duplicate_Copy_Source_Request
     (Target : String) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      First_Source : constant String := "test-bucket/object";
      Second_Source : constant String := "test-bucket/other";
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-copy-source", First_Source),
         SigV4.Pair ("x-amz-copy-source", Second_Source),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-copy-source: " & First_Source & CRLF &
        "x-amz-copy-source: " & Second_Source & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Duplicate_Copy_Source_Request;

   function Signed_Upload_Part_Copy_Request
     (Target      : String;
      Upload_ID   : String;
      Copy_Source : String;
      Copy_Range  : String;
      Encryption  : String := "";
      Part_Number : String := "1") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Encryption'Length = 0
         then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-copy-source", Copy_Source),
            SigV4.Pair ("x-amz-copy-source-range", Copy_Range),
            SigV4.Pair ("x-amz-date", Timestamp))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-copy-source", Copy_Source),
            SigV4.Pair ("x-amz-copy-source-range", Copy_Range),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair ("x-amz-server-side-encryption", Encryption)));
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("partNumber", Part_Number),
         SigV4.Pair ("uploadId", Upload_ID),
         SigV4.Pair ("x-id", "UploadPartCopy"));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
   begin
      return "PUT " & Target & "?" & Query_Text & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-copy-source: " & Copy_Source & CRLF &
        "x-amz-copy-source-range: " & Copy_Range & CRLF &
        (if Encryption'Length = 0 then ""
         else "x-amz-server-side-encryption: " & Encryption & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Upload_Part_Copy_Request;

   function Signed_Query_Request
     (Method : String;
      Target : String;
      Query  : SigV4.Name_Value_Array;
      Extra_Header_Name  : String := "";
      Extra_Header_Value : String := "";
      Second_Header_Name : String := "";
      Second_Header_Value : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Extra_Header_Name'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         elsif Second_Header_Value'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair (Extra_Header_Name, Extra_Header_Value),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         elsif Second_Header_Name'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair (Extra_Header_Name, Extra_Header_Value),
            SigV4.Pair (Extra_Header_Name, Second_Header_Value),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair (Extra_Header_Name, Extra_Header_Value),
            SigV4.Pair (Second_Header_Name, Second_Header_Value),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp)));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
   begin
      return Method & " " & Target & "?" & Query_Text & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if Extra_Header_Name'Length = 0 then ""
         else Extra_Header_Name & ": " & Extra_Header_Value & CRLF) &
        (if Second_Header_Value'Length = 0 then ""
         else (if Second_Header_Name'Length = 0
               then Extra_Header_Name else Second_Header_Name) &
           ": " & Second_Header_Value & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: 0" & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Query_Request;

   function Signed_Query_Body_Request
     (Method        : String;
      Target        : String;
      Query         : SigV4.Name_Value_Array;
      Payload       : String;
      Extra_Headers : String := "";
      Hash_Override : String := "";
      Expect        : Boolean := False;
      Corrupt_Signature : Boolean := False) return String
   is
      Payload_Hash : constant String :=
        (if Hash_Override'Length = 0
         then SigV4.SHA256_Hex (Payload) else Hash_Override);
      Query_Text : constant String := SigV4.Canonical_Query (Query);

      function Extra_Header_Count return Natural is
         Result : Natural := 0;
         Cursor : Integer := Extra_Headers'First;
      begin
         while Cursor <= Extra_Headers'Last loop
            declare
               Ending : constant Natural := Ada.Strings.Fixed.Index
                 (Extra_Headers, CRLF, From => Cursor);
            begin
               if Ending = 0 then
                  raise Program_Error with
                    "test Extra_Headers must end each field with CRLF";
               end if;
               Result := Result + 1;
               Cursor := Integer (Ending) + CRLF'Length;
            end;
         end loop;
         return Result;
      end Extra_Header_Count;

      Extra_Count : constant Natural := Extra_Header_Count;
      Headers : SigV4.Name_Value_Array (1 .. 3 + Extra_Count);
   begin
      Headers (1) := SigV4.Pair ("host", Host);
      Headers (2) := SigV4.Pair ("x-amz-content-sha256", Payload_Hash);
      Headers (3) := SigV4.Pair ("x-amz-date", Timestamp);
      if Extra_Count > 0 then
         declare
            Cursor : Integer := Extra_Headers'First;
         begin
            for Index in 1 .. Extra_Count loop
               declare
                  Ending : constant Natural := Ada.Strings.Fixed.Index
                    (Extra_Headers, CRLF, From => Cursor);
                  Line : constant String :=
                    Extra_Headers (Cursor .. Integer (Ending) - 1);
                  Colon : constant Natural :=
                    Ada.Strings.Fixed.Index (Line, ":");
               begin
                  if Colon = 0 or else Colon = Line'First then
                     raise Program_Error with
                       "test Extra_Headers contains a malformed field";
                  end if;
                  Headers (3 + Index) := SigV4.Pair
                    (Line (Line'First .. Integer (Colon) - 1),
                     Ada.Strings.Fixed.Trim
                       (Line (Integer (Colon) + 1 .. Line'Last),
                        Ada.Strings.Both));
                  Cursor := Integer (Ending) + CRLF'Length;
               end;
            end loop;
         end;
      end if;
      declare
         Signing : constant SigV4.Signing_Result := SigV4.Sign
           (Method, Target, Query, Headers, Payload_Hash, Access_Key,
            Secret_Key, Region, Timestamp);
         Authorization : String := US.To_String (Signing.Authorization);
      begin
         if Corrupt_Signature then
            Authorization (Authorization'Last) :=
              (if Authorization (Authorization'Last) = '0' then '1' else '0');
         end if;
         return Method & " " & Target & "?" & Query_Text & " HTTP/1.1" &
           CRLF & "Host: " & Host & CRLF & "x-amz-date: " & Timestamp &
           CRLF & "x-amz-content-sha256: " & Payload_Hash & CRLF &
           "Authorization: " & Authorization & CRLF & Extra_Headers &
           (if Expect then "Expect: 100-continue" & CRLF else "") &
           "Content-Length: " &
           Ada.Strings.Fixed.Trim
             (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
           "Connection: close" & CRLF & CRLF & Payload;
      end;
   end Signed_Query_Body_Request;

   function Signed_Query_Put_Declared_Length_Request
     (Target : String;
      Query  : SigV4.Name_Value_Array;
      Length : String) return String
   is
      Payload_Hash : constant String := SigV4.Empty_Payload_Hash;
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
   begin
      return "PUT " & Target & "?" & Query_Text & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: " & Length & CRLF & "Connection: close" & CRLF &
        CRLF;
   end Signed_Query_Put_Declared_Length_Request;

   function Signed_Query_Body_Header_Request
     (Method       : String;
      Target       : String;
      Query        : SigV4.Name_Value_Array;
      Payload      : String;
      Header_Name  : String;
      Header_Value : String) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair (Header_Name, Header_Value),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
   begin
      return Method & " " & Target & "?" & Query_Text & " HTTP/1.1" &
        CRLF & "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF & Header_Name &
        ": " & Header_Value & CRLF & "Authorization: " &
        US.To_String (Signing.Authorization) & CRLF & "Content-Length: " &
        Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Query_Body_Header_Request;

   function Signed_Bucket_Tagging_Checksum_Request
     (Payload          : String;
      Algorithm        : Checksum_Policy.Algorithm;
      Checksum         : String;
      Algorithm_Header : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Algorithm_Name : constant String :=
        (if Algorithm_Header'Length > 0
         then Algorithm_Header
         else Checksum_Policy.Wire_Name (Algorithm));
      Checksum_Name : constant String := Checksum_Header (Algorithm);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("content-md5", Content_MD5 (Payload)),
         SigV4.Pair ("host", Host),
         SigV4.Pair (Checksum_Name, Checksum),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", Algorithm_Name));
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("x-id", "PutBucketTagging"));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", "/test-bucket", Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT /test-bucket?" & SigV4.Canonical_Query (Query) &
        " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
        "content-md5: " & Content_MD5 (Payload) & CRLF &
        Checksum_Name & ": " & Checksum & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-sdk-checksum-algorithm: " & Algorithm_Name & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: " &
        Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Bucket_Tagging_Checksum_Request;

   function Signed_Bucket_Tagging_Trailer_Request
     (Payload         : String;
      Algorithm       : Checksum_Policy.Algorithm;
      Checksum        : String;
      Include_Trailer : Boolean := True;
      Duplicate       : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Algorithm_Name : constant String :=
        Checksum_Policy.Wire_Name (Algorithm);
      Checksum_Name : constant String := Checksum_Header (Algorithm);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("content-md5", Content_MD5 (Payload)),
         SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", Algorithm_Name),
         SigV4.Pair ("x-amz-trailer", Checksum_Name));
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("x-id", "PutBucketTagging"));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", "/test-bucket", Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Wire_Body : US.Unbounded_String;
   begin
      for Value of Payload loop
         US.Append (Wire_Body, "1" & CRLF & Value & CRLF);
      end loop;
      US.Append (Wire_Body, "0" & CRLF);
      if Include_Trailer then
         US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         if Duplicate then
            US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         end if;
      end if;
      US.Append (Wire_Body, CRLF);
      return "PUT /test-bucket?" & SigV4.Canonical_Query (Query) &
        " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
        "content-md5: " & Content_MD5 (Payload) & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-sdk-checksum-algorithm: " & Algorithm_Name & CRLF &
        "x-amz-trailer: " & Checksum_Name & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        "Connection: close" & CRLF & CRLF & US.To_String (Wire_Body);
   end Signed_Bucket_Tagging_Trailer_Request;

   function Run_Unbounded
     (Input : US.Unbounded_String;
      Receive_Max : Natural := Natural'Last;
      Scheme      : Flyology.HTTP.Origin_Scheme := Flyology.HTTP.Plain_HTTP;
      Use_Null_MFA : Boolean := False;
      Use_Null_Metadata : Boolean := False)
     return US.Unbounded_String
   is
      Wire : aliased Memory_Transport;
   begin
      Wire.Input := Input;
      Wire.Receive_Max := Receive_Max;
      declare
         Client  : aliased HTTP_Server.Connection (Wire'Access);
         Request : aliased HTTP_Server.Request;
         Closed  : Boolean;
      begin
         HTTP_Server.Read_Request_Head (Client, Request, Closed);
         Require (not Closed, "peer closed before S3 request head");
         declare
            X : Apps.Exchange := Apps.Create
               (Request, Client,
                Sockets.Network_Endpoint (Sockets.Loopback_IPv4, 12_345),
               null, HTTP_Server.Request_Deadline (Client), Scheme);
         begin
            if Use_Null_Metadata then
               No_Metadata_App.Handle (X);
            elsif Use_Null_MFA then
               No_MFA_App.Handle (X);
            else
               S3_App.Handle (X);
            end if;
         end;
      end;
      return Wire.Output;
   end Run_Unbounded;

   function Run_Unbounded
     (Input : String;
      Receive_Max : Natural := Natural'Last) return US.Unbounded_String is
     (Run_Unbounded (US.To_Unbounded_String (Input), Receive_Max));

   function Run
     (Input       : String;
      Receive_Max : Natural := Natural'Last;
      Scheme      : Flyology.HTTP.Origin_Scheme := Flyology.HTTP.Plain_HTTP;
      Use_Null_MFA : Boolean := False;
      Use_Null_Metadata : Boolean := False) return String
   is (US.To_String
         (Run_Unbounded
            (US.To_Unbounded_String (Input), Receive_Max, Scheme,
             Use_Null_MFA, Use_Null_Metadata)));

   function Has (Value, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Value, Pattern) /= 0);

   function Occurrences (Value, Pattern : String) return Natural is
      Result : Natural := 0;
      Cursor : Integer := Value'First;
   begin
      if Pattern'Length = 0 then
         return 0;
      end if;
      while Cursor <= Value'Last loop
         declare
            Found : constant Natural :=
              Ada.Strings.Fixed.Index (Value, Pattern, From => Cursor);
         begin
            exit when Found = 0;
            Result := Result + 1;
            Cursor := Integer (Found) + Pattern'Length;
         end;
      end loop;
      return Result;
   end Occurrences;

   function Has
     (Value : US.Unbounded_String; Pattern : String) return Boolean is
     (US.Index (Value, Pattern) /= 0);

   function Response_Body (Value : String) return String is
      Marker : constant Natural :=
        Ada.Strings.Fixed.Index (Value, CRLF & CRLF);
   begin
      if Marker = 0 or else Marker + 4 > Value'Last then
         return "";
      else
         return Value (Marker + 4 .. Value'Last);
      end if;
   end Response_Body;

   function Signed_Versioning_Request
     (Payload      : String;
      MD5          : String;
      MFA          : String := "";
      Checksum     : String := "";
      Checksum_Value : String := "";
      Checksum_Value_Algorithm : Checksum_Policy.Algorithm := Core.CRC32;
      Owner        : String := "";
      Duplicate_MD5 : String := "";
      Duplicate_MFA : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Header_Count : constant Positive :=
        4 + Boolean'Pos (MFA'Length > 0)
          + Boolean'Pos (Checksum'Length > 0)
          + Boolean'Pos (Checksum_Value'Length > 0)
          + Boolean'Pos (Owner'Length > 0)
          + Boolean'Pos (Duplicate_MD5'Length > 0)
          + Boolean'Pos (Duplicate_MFA'Length > 0);
      Headers : SigV4.Name_Value_Array (1 .. Header_Count);
      Last : Natural := 4;
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versioning", ""));
      Checksum_Name : constant String :=
        Checksum_Header (Checksum_Value_Algorithm);
      Signing : SigV4.Signing_Result;
   begin
      Headers (1) := SigV4.Pair ("content-md5", MD5);
      Headers (2) := SigV4.Pair ("host", Host);
      Headers (3) := SigV4.Pair ("x-amz-content-sha256", Payload_Hash);
      Headers (4) := SigV4.Pair ("x-amz-date", Timestamp);
      if Duplicate_MD5'Length > 0 then
         Last := Last + 1;
         Headers (Last) := SigV4.Pair ("content-md5", Duplicate_MD5);
      end if;
      if MFA'Length > 0 then
         Last := Last + 1;
         Headers (Last) := SigV4.Pair ("x-amz-mfa", MFA);
      end if;
      if Duplicate_MFA'Length > 0 then
         Last := Last + 1;
         Headers (Last) := SigV4.Pair ("x-amz-mfa", Duplicate_MFA);
      end if;
      if Checksum'Length > 0 then
         Last := Last + 1;
         Headers (Last) :=
           SigV4.Pair ("x-amz-sdk-checksum-algorithm", Checksum);
      end if;
      if Checksum_Value'Length > 0 then
         Last := Last + 1;
         Headers (Last) :=
           SigV4.Pair (Checksum_Name, Checksum_Value);
      end if;
      if Owner'Length > 0 then
         Last := Last + 1;
         Headers (Last) :=
           SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      Signing := SigV4.Sign
        ("PUT", "/versioning-bucket", Query, Headers, Payload_Hash,
         Access_Key,
         Secret_Key, Region, Timestamp);
      return "PUT /versioning-bucket?versioning= HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "content-md5: " & MD5 & CRLF &
        (if Duplicate_MD5'Length = 0 then ""
         else "content-md5: " & Duplicate_MD5 & CRLF) &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if MFA'Length = 0 then ""
         else "x-amz-mfa: " & MFA & CRLF) &
        (if Duplicate_MFA'Length = 0 then ""
         else "x-amz-mfa: " & Duplicate_MFA & CRLF) &
        (if Checksum'Length = 0 then ""
         else "x-amz-sdk-checksum-algorithm: " & Checksum & CRLF) &
        (if Checksum_Value'Length = 0 then ""
         else Checksum_Name & ": " & Checksum_Value & CRLF) &
        (if Owner'Length = 0 then ""
         else "x-amz-expected-bucket-owner: " & Owner & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: " &
        Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Versioning_Request;

   function Signed_Versioning_Trailer_Request
     (Payload         : String;
      Algorithm       : Checksum_Policy.Algorithm;
      Checksum        : String;
      Include_Trailer : Boolean := True;
      Duplicate       : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Algorithm_Name : constant String :=
        Checksum_Policy.Wire_Name (Algorithm);
      Checksum_Name : constant String := Checksum_Header (Algorithm);
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("content-md5", Content_MD5 (Payload)),
         SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", Algorithm_Name),
         SigV4.Pair ("x-amz-trailer", Checksum_Name));
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versioning", ""));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", "/versioning-bucket", Query, Headers, Payload_Hash,
         Access_Key,
         Secret_Key, Region, Timestamp);
      Wire_Body : US.Unbounded_String;
   begin
      for Value of Payload loop
         US.Append (Wire_Body, "1" & CRLF & Value & CRLF);
      end loop;
      US.Append (Wire_Body, "0" & CRLF);
      if Include_Trailer then
         US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         if Duplicate then
            US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         end if;
      end if;
      US.Append (Wire_Body, CRLF);
      return "PUT /versioning-bucket?versioning= HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "content-md5: " & Content_MD5 (Payload) & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-sdk-checksum-algorithm: " & Algorithm_Name & CRLF &
        "x-amz-trailer: " & Checksum_Name & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        "Connection: close" & CRLF & CRLF & US.To_String (Wire_Body);
   end Signed_Versioning_Trailer_Request;

   function Signed_Upload_Part_Trailer_Request
     (Target          : String;
      Upload_ID       : String;
      Part_Number     : Positive;
      Payload         : String;
      Algorithm       : Checksum_Policy.Algorithm;
      Checksum        : String;
      Include_Trailer : Boolean := True;
      Duplicate       : Boolean := False) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Algorithm_Name : constant String :=
        Checksum_Policy.Wire_Name (Algorithm);
      Checksum_Name : constant String := Checksum_Header (Algorithm);
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair
           ("partNumber",
            Ada.Strings.Fixed.Trim
              (Positive'Image (Part_Number), Ada.Strings.Both)),
         SigV4.Pair ("uploadId", Upload_ID));
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", Algorithm_Name),
         SigV4.Pair ("x-amz-trailer", Checksum_Name));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Wire_Body : US.Unbounded_String;
   begin
      for Value of Payload loop
         US.Append (Wire_Body, "1" & CRLF & Value & CRLF);
      end loop;
      US.Append (Wire_Body, "0" & CRLF);
      if Include_Trailer then
         US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         if Duplicate then
            US.Append (Wire_Body, Checksum_Name & ": " & Checksum & CRLF);
         end if;
      end if;
      US.Append (Wire_Body, CRLF);
      return "PUT " & Target & "?" & SigV4.Canonical_Query (Query) &
        " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-sdk-checksum-algorithm: " & Algorithm_Name & CRLF &
        "x-amz-trailer: " & Checksum_Name & CRLF & "Authorization: " &
        US.To_String (Signing.Authorization) & CRLF &
        "Transfer-Encoding: chunked" & CRLF & "Connection: close" & CRLF &
        CRLF & US.To_String (Wire_Body);
   end Signed_Upload_Part_Trailer_Request;

   function Signed_Upload_Part_Declared_Length_Request
     (Target      : String;
      Upload_ID   : String;
      Part_Number : Positive;
      Length      : Flyology.Object_Storage.Byte_Count) return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair
           ("partNumber",
            Ada.Strings.Fixed.Trim
              (Positive'Image (Part_Number), Ada.Strings.Both)),
         SigV4.Pair ("uploadId", Upload_ID));
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("PUT", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
   begin
      return "PUT " & Target & "?" & SigV4.Canonical_Query (Query) &
        " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "x-amz-date: " & Timestamp & CRLF & "Authorization: " &
        US.To_String (Signing.Authorization) & CRLF & "Content-Length: " &
        Ada.Strings.Fixed.Trim
          (Flyology.Object_Storage.Byte_Count'Image (Length),
           Ada.Strings.Both) & CRLF & "Connection: close" & CRLF & CRLF;
   end Signed_Upload_Part_Declared_Length_Request;

   procedure Check_Cancellation_Propagation is
      Wire : aliased Memory_Transport;
      Stop : aliased Flyology.Cancellation.Token;
      Propagated : Boolean := False;
   begin
      Wire.Input := US.To_Unbounded_String
        (Signed_Request ("PUT", "/test-bucket/cancelled", "payload"));
      declare
         Client  : aliased HTTP_Server.Connection (Wire'Access);
         Request : aliased HTTP_Server.Request;
         Closed  : Boolean;
      begin
         HTTP_Server.Read_Request_Head (Client, Request, Closed);
         Require (not Closed, "cancel test request head closed");
         Stop.Request;
         declare
            X : Apps.Exchange := Apps.Create
              (Request, Client,
               Sockets.Network_Endpoint (Sockets.Loopback_IPv4, 12_345),
               Stop'Access, HTTP_Server.Request_Deadline (Client));
         begin
            begin
               S3_App.Handle (X);
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Propagated := True;
            end;
         end;
      end;
      Require (Propagated, "request cancellation did not propagate");
      Require
        (not Has (US.To_String (Wire.Output), "InternalError"),
         "request cancellation was mislabeled as an internal error");
   end Check_Cancellation_Propagation;

   procedure Check_Deadline_Propagation is
      use type Ada.Real_Time.Time;
      Wire : aliased Memory_Transport;
      Propagated : Boolean := False;
   begin
      Wire.Input := US.To_Unbounded_String
        (Signed_Request ("PUT", "/test-bucket/timed-out", "payload"));
      declare
         Client  : aliased HTTP_Server.Connection (Wire'Access);
         Request : aliased HTTP_Server.Request;
         Closed  : Boolean;
      begin
         HTTP_Server.Read_Request_Head (Client, Request, Closed);
         Require (not Closed, "deadline test request head closed");
         declare
            X : Apps.Exchange := Apps.Create
              (Request, Client,
               Sockets.Network_Endpoint (Sockets.Loopback_IPv4, 12_345),
               null, Ada.Real_Time.Clock - Ada.Real_Time.Seconds (1));
         begin
            begin
               S3_App.Handle (X);
            exception
               when Flyology.IO.Timeout_Error =>
                  Propagated := True;
            end;
         end;
      end;
      Require (Propagated, "expired request deadline did not propagate");
      Require
        (not Has (US.To_String (Wire.Output), "InternalError"),
         "request timeout was mislabeled as an internal error");
   end Check_Deadline_Propagation;

   procedure Check_Create_Multipart_Admission is
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("uploads", ""));
      Target : constant String := "/test-bucket/create-policy-reject";
      Content_Type_Wire_Name : constant String := "Content-Type";
      Create_Content_Type_Limit : constant Positive :=
        Flyology.Object_Storage.Maximum_System_Metadata_Bytes -
        Content_Type_Wire_Name'Length;
      --  The value limit is derived from the public aggregate metadata budget
      --  after charging the fixed S3 wire-name bytes.  Changing either source
      --  changes CreateMultipartUpload admission compatibility.
      Create_Policy_Header_Limit : constant Positive := 8_192;
      --  Mirrors the pinned S3 singleton-header limit shared by the server and
      --  low-level client.  It bounds signed policy retention and changing it
      --  requires corpus and compatibility review in both layers.
      Grant_Envelope_Bytes : constant Positive := 5;
      --  Derived fixed bytes in the shortest quoted grant envelope, id="".

      procedure Reject
        (Headers : String;
         Code    : String;
         Label   : String;
         Scheme  : Flyology.HTTP.Origin_Scheme := Flyology.HTTP.Plain_HTTP;
         Payload : String := "";
         Corrupt : Boolean := False)
      is
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("POST", Target, Query, Payload, Headers,
               Corrupt_Signature => Corrupt),
            Scheme => Scheme);
      begin
         Require
           (not Has (Response, "200 OK")
            and then Has (Response, "<Code>" & Code & "</Code>"),
            "CreateMultipartUpload accepted " & Label & ": " & Response);
      end Reject;

      procedure Require_No_Upload is
         List_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("prefix", "create-policy-reject"),
            SigV4.Pair ("uploads", ""));
         Response : constant String := Run
           (Signed_Query_Request ("GET", "/test-bucket", List_Query));
         Page : constant Multipart_Uploads.List_Multipart_Uploads_Result :=
           Multipart_Uploads.Parse_List_Multipart_Uploads
             (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK") and then Page.Uploads.Is_Empty,
            "rejected CreateMultipartUpload published an upload: " &
            Response);
      end Require_No_Upload;
   begin
      Reject ("content-type: " & CRLF, "InvalidArgument",
              "empty content type");
      Reject
         ("content-type: " &
         String'
           (1 .. Create_Content_Type_Limit + 1 => 't') &
         CRLF, "InvalidArgument", "content type limit plus one");
      Reject ("x-amz-acl: " & CRLF, "InvalidArgument", "empty ACL");
      Reject ("x-amz-acl: unknown" & CRLF, "InvalidArgument",
              "unknown ACL");
      Reject
        ("x-amz-acl: private" & CRLF & "x-amz-acl: private" & CRLF,
         "InvalidRequest", "duplicate ACL");
      Reject ("x-amz-acl: private" & CRLF, "NotImplemented",
              "unsupported valid ACL");
      Reject
        ("x-amz-grant-read: id=""reader"", " &
         "uri=""http://acs.amazonaws.com/groups/global/AllUsers"", " &
         "emailAddress=""reader@example.test""" & CRLF,
         "NotImplemented", "unsupported valid multi-grantee ACL");
      Reject
        ("x-amz-grant-read: id=reader" & CRLF,
         "InvalidArgument", "unquoted ACL grantee");
      Reject
        ("x-amz-grant-read: account=""reader""" & CRLF,
         "InvalidArgument", "unknown ACL grantee kind");
      Reject
        ("x-amz-grant-read: id=""reader"", id=""reader""" & CRLF,
         "InvalidArgument", "duplicate ACL grantee");
      Reject
        ("x-amz-grant-read: id=""" &
         String'
           (1 .. Create_Policy_Header_Limit - Grant_Envelope_Bytes => 'g') &
         """" & CRLF,
         "NotImplemented", "unsupported exact-bound ACL grant");
      Reject
        ("x-amz-grant-read: id=""" &
         String'
           (1 .. Create_Policy_Header_Limit - Grant_Envelope_Bytes + 1 =>
              'g') &
         """" & CRLF,
         "InvalidArgument", "ACL grant limit plus one");
      Reject
        ("x-amz-acl: private" & CRLF &
         "x-amz-grant-read: id=""reader""" & CRLF,
         "InvalidRequest", "mixed ACL and grant policy");
      Reject ("cache-control: " & CRLF, "InvalidArgument",
              "empty cache policy");
      Reject ("cache-control: no-cache" & CRLF, "NotImplemented",
              "unsupported cache policy");
      Reject ("expires: invalid" & CRLF, "InvalidArgument",
              "malformed expiry");
      Reject
        ("expires: Sun, 06 Nov 1994 08:49:37 GMT" & CRLF,
         "NotImplemented", "unsupported valid expiry");
      Reject ("x-amz-meta-: value" & CRLF, "InvalidArgument",
              "empty metadata key");
      Reject
        ("x-amz-meta-Team: one" & CRLF &
         "x-amz-meta-team: two" & CRLF,
         "InvalidRequest", "case-colliding metadata");
      Reject ("x-amz-meta-team: storage" & CRLF, "NotImplemented",
              "unsupported valid metadata");
      Reject ("x-amz-request-payer: " & CRLF, "InvalidArgument",
              "empty request payer");
      Reject ("x-amz-request-payer: owner" & CRLF, "InvalidArgument",
              "invalid request payer");
      Reject
        ("x-amz-request-payer: requester" & CRLF,
         "NotImplemented", "unsupported requester pays");
      Reject
        ("x-amz-expected-bucket-owner: different-owner" & CRLF,
         "AccessDenied", "mismatched expected owner");
      Reject
        ("x-amz-expected-bucket-owner: " & CRLF,
         "InvalidRequest", "empty expected owner");
      Reject
        ("x-amz-expected-bucket-owner: test-principal" & CRLF &
         "x-amz-acl: private" & CRLF,
         "NotImplemented", "matching owner with unsupported ACL");
      Reject
        ("x-amz-server-side-encryption-customer-algorithm: AES256" &
         CRLF, "InvalidRequest", "incomplete SSE-C group");
      Reject
        ("x-amz-server-side-encryption-customer-algorithm: AES128" &
         CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 & CRLF,
         "InvalidArgument", "invalid SSE-C algorithm",
         Flyology.HTTP.Secure_HTTPS);
      Reject
        ("x-amz-server-side-encryption-customer-algorithm: AES256" &
         CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         Content_MD5 ("different") & CRLF,
         "InvalidDigest", "mismatched SSE-C key digest",
         Flyology.HTTP.Secure_HTTPS);
      Reject
        ("x-amz-server-side-encryption-customer-algorithm: AES256" &
         CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 & CRLF,
         "InvalidRequest", "SSE-C over plaintext");
      Reject
        ("x-amz-server-side-encryption-customer-algorithm: AES256" &
         CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 & CRLF,
         "NotImplemented", "unsupported valid SSE-C",
         Flyology.HTTP.Secure_HTTPS);
      Reject
        ("x-amz-server-side-encryption-aws-kms-key-id: key" & CRLF,
         "InvalidRequest", "KMS companion without mode");
      Reject
        ("x-amz-server-side-encryption: aws:kms" & CRLF &
         "x-amz-server-side-encryption-aws-kms-key-id: key" & CRLF,
         "NotImplemented", "unsupported valid KMS policy");
      Reject
        ("x-amz-server-side-encryption: aws:kms" & CRLF &
         "x-amz-server-side-encryption-context: malformed" & CRLF,
         "InvalidArgument", "malformed KMS context");
      Reject
        ("x-amz-server-side-encryption: aws:kms" & CRLF &
         "x-amz-server-side-encryption-bucket-key-enabled: TRUE" & CRLF,
         "InvalidArgument", "noncanonical bucket-key boolean");
      Reject ("x-amz-storage-class: unknown" & CRLF, "InvalidArgument",
              "unknown storage class");
      Reject ("x-amz-storage-class: STANDARD" & CRLF, "NotImplemented",
              "unsupported explicit storage class");
      Reject ("x-amz-tagging: " & CRLF, "InvalidTag", "empty tag set");
      Reject ("x-amz-tagging: =value" & CRLF, "InvalidTag",
              "invalid tag set");
      Reject ("x-amz-tagging: team=storage" & CRLF, "NotImplemented",
              "unsupported valid tag set");
      Reject ("x-amz-object-lock-mode: invalid" & CRLF,
              "InvalidArgument", "invalid object lock mode");
      Reject ("x-amz-object-lock-mode: GOVERNANCE" & CRLF,
              "InvalidRequest", "incomplete retention group");
      Reject
        ("x-amz-object-lock-mode: GOVERNANCE" & CRLF &
         "x-amz-object-lock-retain-until-date: invalid" & CRLF,
         "InvalidArgument", "malformed retention timestamp");
      Reject
        ("x-amz-object-lock-mode: GOVERNANCE" & CRLF &
         "x-amz-object-lock-retain-until-date: " &
         "2026-09-01T00:00:00Z" & CRLF,
         "NotImplemented", "unsupported valid retention policy");
      Reject ("x-amz-checksum-type: FULL_OBJECT" & CRLF,
              "InvalidRequest", "checksum type without algorithm");
      Reject ("x-amz-checksum-algorithm: UNKNOWN" & CRLF,
              "InvalidRequest", "unknown checksum algorithm");
      Reject
        ("x-amz-checksum-unknown: value" & CRLF,
         "InvalidRequest", "unknown checksum header");
      Reject
        ("x-amz-request-payer: owner" & CRLF &
         "x-amz-expected-bucket-owner: different-owner" & CRLF &
         "x-amz-acl: unknown" & CRLF,
         "SignatureDoesNotMatch", "controls before authentication",
         Corrupt => True);
      Reject ("", "InvalidRequest", "nonempty request body", Payload => " ");
      Require_No_Upload;

      declare
         Boundary_Target : constant String :=
           "/test-bucket/create-content-boundary";
         Exact_Content_Type : constant String :=
           String'(1 .. Create_Content_Type_Limit => 't');
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("POST", Boundary_Target, Query, "",
               "content-type: " & Exact_Content_Type & CRLF));
         function Created_ID return String is
         begin
            Require
              (Has (Response, "200 OK"),
               "CreateMultipartUpload rejected the exact content-type " &
               "bound: " & Response);
            return US.To_String
              (Multipart.Parse_Create_Result
                 (Response_Body (Response)).Upload_ID);
         end Created_ID;
         ID : constant String := Created_ID;
         Abort_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("uploadId", ID));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has
              (Run
                 (Signed_Query_Body_Request
                    ("DELETE", Boundary_Target, Abort_Query, "")),
               "204 No Content"),
            "CreateMultipartUpload rejected the exact content-type bound");
      end;
   end Check_Create_Multipart_Admission;

   procedure Check_Multipart_Server is
      Payload : constant String := "multipart body";
      Expected_Checksum : constant String := CRC64NVME (Payload);
      Part_ETag : constant String := "b6ad3f1edd348582e829c1c38d7d3b3b";
      Create_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("uploads", ""));
      Create_Response : constant String := Run
        (Signed_Query_Body_Request
           ("POST", "/test-bucket/multipart-object", Create_Query, "",
            "Content-Type: text/plain" & CRLF));
      Created : constant Multipart.Create_Multipart_Upload_Result :=
        Multipart.Parse_Create_Result (Response_Body (Create_Response));
      Upload_ID : constant String := US.To_String (Created.Upload_ID);
   begin
      Require
        (Has (Create_Response, "200 OK") and then Upload_ID'Length = 64,
         "CreateMultipartUpload server response mismatch");
      declare
         Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("partNumber", "1"),
            SigV4.Pair ("uploadId", Upload_ID));
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket/multipart-object", Query, Payload),
            Receive_Max => 1);
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "ETag: """ & Part_ETag & """")
            and then Has
              (Response, "x-amz-checksum-crc64nvme: " &
                 Expected_Checksum & CRLF),
            "UploadPart server response mismatch: " & Response);
      end;
      declare
         Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("max-parts", "1"),
            SigV4.Pair ("part-number-marker", "0"),
            SigV4.Pair ("uploadId", Upload_ID),
            SigV4.Pair ("x-id", "ListParts"));
         Response : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket/multipart-object", Query));
         Listed : constant Multipart.List_Parts_Result :=
           Multipart.Parse_List_Parts_Result (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK") and then Listed.Parts.Length = 1
            and then Listed.Parts.First_Element.Number = 1
            and then Listed.Parts.First_Element.Size = 14
            and then US.To_String (Listed.Parts.First_Element.Entity_Tag) =
              '"' & Part_ETag & '"'
            and then US.To_String (Listed.Checksum_Algorithm) =
              "CRC64NVME"
            and then US.To_String (Listed.Checksum_Type) = "FULL_OBJECT"
            and then US.To_String
              (Listed.Parts.First_Element.Checksum_CRC64NVME) =
                Expected_Checksum
            and then not Listed.Is_Truncated,
            "ListParts server response mismatch: " & Response);
      end;
      declare
         procedure Exercise_Checksum
           (Algorithm : Checksum_Policy.Algorithm)
         is
            Name : constant String := Checksum_Policy.Wire_Name (Algorithm);
            Target : constant String :=
              "/test-bucket/upload-part-checksum-" & Name;
            Create_Response : constant String := Run
              (Signed_Query_Body_Request
                 ("POST", Target, Create_Query, "",
                  "x-amz-checksum-algorithm: " & Name & CRLF));
            ID : constant String := US.To_String
              (Multipart.Parse_Create_Result
                 (Response_Body (Create_Response)).Upload_ID);
            Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("partNumber", "1"),
               SigV4.Pair ("uploadId", ID));
            Header_Payload : constant String := "header-" & Name;
            Header_Checksum : constant String :=
              Checksum_Value (Algorithm, Header_Payload);
            --  SHA256 deliberately carries a conflicting SDK selector.  The
            --  concrete individual checksum has the pinned AWS precedence.
            Selector : constant String :=
              (if Algorithm = Core.SHA256 then "CRC32" else Name);
            Header_Response : constant String := Run
              (Signed_Query_Body_Request
                 ("PUT", Target, Query, Header_Payload,
                  "content-md5: " & Content_MD5 (Header_Payload) & CRLF &
                  "x-amz-sdk-checksum-algorithm: " & Selector & CRLF &
                  Checksum_Header (Algorithm) & ": " & Header_Checksum &
                  CRLF &
                  (if Algorithm = Core.CRC32
                   then "x-amz-expected-bucket-owner: test-principal" & CRLF
                   else "")));
            Trailer_Payload : constant String := "trailer-" & Name;
            Trailer_Checksum : constant String :=
              Checksum_Value (Algorithm, Trailer_Payload);
            Trailer_Response : constant String := Run
              (Signed_Upload_Part_Trailer_Request
                 (Target, ID, 2, Trailer_Payload, Algorithm,
                  Trailer_Checksum));
            List_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("uploadId", ID),
               SigV4.Pair ("x-id", "ListParts"));
            List_Response : constant String := Run
              (Signed_Query_Request ("GET", Target, List_Query));
            Abort_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("uploadId", ID),
               SigV4.Pair ("x-id", "AbortMultipartUpload"));

            procedure Reject_Header
              (Value : String; Code : String; Label : String)
            is
               Negative_Query : constant SigV4.Name_Value_Array :=
                 (SigV4.Pair ("partNumber", "3"),
                  SigV4.Pair ("uploadId", ID));
               Response : constant String := Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, Negative_Query, Header_Payload,
                     Value));
            begin
               Require
                 (not Has (Response, "200 OK")
                  and then Has (Response, "<Code>" & Code & "</Code>"),
                  "UploadPart accepted " & Name & " " & Label & ": " &
                    Response);
            end Reject_Header;
         begin
            Require
              (Has (Create_Response, "200 OK")
               and then Has (Header_Response, "200 OK")
               and then Response_Body (Header_Response) = ""
               and then Occurrences (Header_Response, "ETag: ") = 1
               and then Occurrences
                 (Header_Response, Checksum_Header (Algorithm) & ": ") = 1
               and then Has
                 (Header_Response,
                  Checksum_Header (Algorithm) & ": " & Header_Checksum &
                  CRLF)
               and then Has (Trailer_Response, "200 OK")
               and then Response_Body (Trailer_Response) = ""
               and then Occurrences (Trailer_Response, "ETag: ") = 1
               and then Occurrences
                 (Trailer_Response, Checksum_Header (Algorithm) & ": ") = 1
               and then Has
                 (Trailer_Response,
                  Checksum_Header (Algorithm) & ": " & Trailer_Checksum &
                  CRLF),
               "UploadPart rejected valid " & Name & " header/trailer");
            Require
              (Has (List_Response, "200 OK")
               and then Has
                 (Response_Body (List_Response),
                  "<Checksum" & Name & ">" & Header_Checksum &
                  "</Checksum" & Name & ">")
               and then Has
                 (Response_Body (List_Response),
                  "<Checksum" & Name & ">" & Trailer_Checksum &
                  "</Checksum" & Name & ">"),
               "UploadPart did not persist exact " & Name & " parts");
            for Other in Checksum_Policy.Algorithm loop
               if Other /= Algorithm then
                  Require
                    (not Has
                       (Header_Response, Checksum_Header (Other) & ": ")
                     and then not Has
                       (Trailer_Response, Checksum_Header (Other) & ": "),
                     "UploadPart emitted an unselected checksum header");
               end if;
            end loop;
            Require
              (not Has (Header_Response, "x-amz-server-side-encryption:")
               and then not Has
                 (Header_Response,
                  "x-amz-server-side-encryption-customer-algorithm:")
               and then not Has
                 (Header_Response,
                  "x-amz-server-side-encryption-customer-key-MD5:")
               and then not Has
                 (Header_Response,
                  "x-amz-server-side-encryption-aws-kms-key-id:")
               and then not Has
                 (Header_Response,
                  "x-amz-server-side-encryption-bucket-key-enabled:")
               and then not Has (Header_Response, "x-amz-request-charged:"),
               "UploadPart emitted unsupported response metadata");
            Reject_Header
              (Checksum_Header (Algorithm) & ": " & CRLF,
               "InvalidRequest", "present-empty checksum");
            Reject_Header
              (Checksum_Header (Algorithm) & ": " & Header_Checksum & CRLF &
               Checksum_Header (Algorithm) & ": " & Header_Checksum & CRLF,
               "InvalidRequest", "duplicate checksum");
            Reject_Header
              (Checksum_Header (Algorithm) & ": !" & CRLF,
               "InvalidRequest", "malformed checksum");
            Reject_Header
              (Checksum_Header (Algorithm) & ": " &
               Checksum_Value (Algorithm, "different") & CRLF,
               "BadDigest", "mismatched checksum");
            declare
               After_Negatives : constant String := Run
                 (Signed_Query_Request ("GET", Target, List_Query));
               Abort_Response : constant String := Run
                 (Signed_Query_Request ("DELETE", Target, Abort_Query));
            begin
               Require
                 (Has (After_Negatives, "200 OK")
                  and then Response_Body (After_Negatives) =
                    Response_Body (List_Response),
                  "rejected UploadPart changed the staged part set for " &
                    Name);
               Require
                 (Has (Abort_Response, "204 No Content"),
                  "UploadPart checksum upload cleanup failed");
            end;
         end Exercise_Checksum;
      begin
         for Algorithm in Checksum_Policy.Algorithm loop
            Exercise_Checksum (Algorithm);
         end loop;
      end;
      declare
         Part_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("partNumber", "1"),
            SigV4.Pair ("uploadId", Upload_ID));
         Prior_List_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("uploadId", Upload_ID),
            SigV4.Pair ("x-id", "ListParts"));
         Prior_List_Response : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket/multipart-object", Prior_List_Query));
         Prior_Listed : constant Multipart.List_Parts_Result :=
           Multipart.Parse_List_Parts_Result
             (Response_Body (Prior_List_Response));

         procedure Reject
           (Headers : String;
            Code    : String;
            Label   : String;
            Scheme  : Flyology.HTTP.Origin_Scheme :=
              Flyology.HTTP.Plain_HTTP)
         is
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/multipart-object", Part_Query,
                  Payload, Headers), Scheme => Scheme);
         begin
            Require
              (not Has (Response, "200 OK")
               and then Has (Response, "<Code>" & Code & "</Code>"),
               "UploadPart accepted " & Label & ": " & Response);
         end Reject;

         procedure Reject_Wire
           (Request : String; Code : String; Label : String)
         is
            Response : constant String := Run (Request);
         begin
            Require
              (not Has (Response, "200 OK")
               and then Has (Response, "<Code>" & Code & "</Code>"),
               "UploadPart accepted " & Label & ": " & Response);
         end Reject_Wire;

         Key : constant String := Checksum_Value (Core.SHA256, "sse-key");
         Decoded_Key : constant Checksums.Decode_Result :=
           Checksums.Decode_Base64 (Key, Core.SHA256);
         Key_MD5 : constant String := Checksums.Encode_Base64
           (Checksums.Compute
              (Core.MD5, Checksums.Raw_Bytes (Decoded_Key.Value)));
         Overlong : constant String
           (1 .. Maximum_Header_Text_Bytes + 1) := (others => 'x');
      begin
         declare
            Missing_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("partNumber", "1"),
               SigV4.Pair ("uploadId", "missing-upload"));
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/multipart-object", Missing_Query,
                  Payload,
                  "content-md5: malformed" & CRLF &
                  "x-amz-request-payer: requester" & CRLF &
                  "x-amz-expected-bucket-owner: different-owner" & CRLF &
                  "x-amz-checksum-crc64nvme: malformed" & CRLF,
                  Expect => True, Corrupt_Signature => True));
         begin
            Require
              (Has (Response, "<Code>SignatureDoesNotMatch</Code>")
               and then not Has (Response, "100 Continue")
               and then not Has (Response, "NoSuchUpload")
               and then not Has (Response, "InvalidDigest")
               and then not Has (Response, "NotImplemented")
               and then not Has (Response, "AccessDenied"),
               "UploadPart controls ran before authentication: " & Response);
         end;
         Reject
           ("content-md5: malformed" & CRLF, "InvalidDigest",
            "malformed Content-MD5");
         Reject
           ("content-md5: " & Content_MD5 ("different") & CRLF,
            "BadDigest", "mismatched Content-MD5");
         Reject
           ("content-md5: " & Content_MD5 (Payload) & CRLF &
            "content-md5: " & Content_MD5 (Payload) & CRLF,
            "InvalidRequest", "duplicate Content-MD5");
         Reject
           ("x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF,
            "InvalidRequest", "selector without checksum evidence");
         Reject
           ("x-amz-sdk-checksum-algorithm: " & CRLF,
            "InvalidRequest", "empty checksum selector");
         Reject
           ("x-amz-sdk-checksum-algorithm: UNKNOWN" & CRLF,
            "InvalidRequest", "invalid checksum selector");
         Reject
           ("x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-checksum-crc64nvme: " & Expected_Checksum & CRLF,
            "InvalidRequest", "duplicate checksum selector");
         Reject
           ("x-amz-checksum-unknown: value" & CRLF,
            "InvalidRequest", "unknown checksum control");
         Reject
           ("X-Amz-Checksum-Unknown: value" & CRLF &
            "x-amz-checksum-crc64nvme: " & Expected_Checksum & CRLF,
            "InvalidRequest", "case-folded unknown checksum with known");
         Reject
           ("x-amz-checksum-crc32-extra: value" & CRLF,
            "InvalidRequest", "near-name checksum control");
         Reject
           ("x-amz-checksum-type: FULL_OBJECT" & CRLF,
            "InvalidRequest", "unsupported UploadPart checksum type");
         Reject
           ("x-amz-checksum-crc64nvme: " & Expected_Checksum & CRLF &
            "x-amz-checksum-crc32: " &
            Checksum_Value (Core.CRC32, Payload) & CRLF,
            "InvalidRequest", "multiple concrete checksums");
         Reject
           ("x-amz-checksum-crc64nvme: " &
            Checksum_Value (Core.CRC64NVME, "different") & CRLF,
            "BadDigest", "mismatched concrete checksum");
         declare
            Wrong_Hash : constant String (1 .. 64) := (others => '0');
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/multipart-object", Part_Query,
                  Payload, Hash_Override => Wrong_Hash));
         begin
            Require
              (Has
                 (Response,
                  "<Code>XAmzContentSHA256Mismatch</Code>"),
               "UploadPart accepted a mismatched signed payload hash");
         end;
         Reject_Wire
           (Signed_Upload_Part_Trailer_Request
              ("/test-bucket/multipart-object", Upload_ID, 1, Payload,
               Core.CRC64NVME, Expected_Checksum,
               Include_Trailer => False),
            "InvalidRequest", "missing physical checksum trailer");
         Reject_Wire
           (Signed_Upload_Part_Trailer_Request
              ("/test-bucket/multipart-object", Upload_ID, 1, Payload,
               Core.CRC64NVME, Expected_Checksum, Duplicate => True),
            "InvalidRequest", "duplicate physical checksum trailer");
         Reject_Wire
           (Signed_Upload_Part_Trailer_Request
              ("/test-bucket/multipart-object", Upload_ID, 1, Payload,
               Core.CRC64NVME,
               Checksum_Value (Core.CRC64NVME, "different")),
            "BadDigest", "mismatched physical checksum trailer");
         Reject
           ("x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc32" & CRLF,
            "InvalidRequest", "wrong checksum trailer declaration");
         Reject
           ("x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: " & CRLF,
            "InvalidRequest", "empty checksum trailer declaration");
         Reject
           ("x-amz-request-payer: requester" & CRLF,
            "NotImplemented", "unsupported requester pays");
         Reject
           ("x-amz-request-payer: " & CRLF,
            "InvalidArgument", "empty requester payer");
         Reject
           ("x-amz-request-payer: Requester" & CRLF,
            "InvalidArgument", "invalid requester payer");
         Reject
           ("x-amz-request-payer: requester" & CRLF &
            "x-amz-request-payer: requester" & CRLF,
            "InvalidRequest", "duplicate requester payer");
         Reject
           ("x-amz-request-payer: " & Overlong & CRLF,
            "InvalidArgument", "overlong requester payer");
         Reject
           ("x-amz-expected-bucket-owner: different-owner" & CRLF,
            "AccessDenied", "mismatched expected owner");
         Reject
           ("x-amz-expected-bucket-owner: " & CRLF,
            "InvalidRequest", "empty expected owner");
         Reject
           ("x-amz-expected-bucket-owner: test-principal" & CRLF &
            "x-amz-expected-bucket-owner: test-principal" & CRLF,
            "InvalidRequest", "duplicate expected owner");
         Reject
           ("x-amz-expected-bucket-owner: " & Overlong & CRLF,
            "InvalidRequest", "overlong expected owner");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF, "InvalidRequest", "incomplete SSE-C group");
         Reject
           ("x-amz-server-side-encryption-customer-key: " & Key & CRLF &
            "x-amz-server-side-encryption-customer-key-md5: " & Key_MD5 &
            CRLF, "InvalidRequest", "SSE-C group missing algorithm");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidRequest", "SSE-C group missing key");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF, "InvalidRequest", "SSE-C group missing key digest");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF &
            "x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidRequest",
            "duplicate SSE-C algorithm");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidRequest", "duplicate SSE-C key");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF &
            "x-amz-server-side-encryption-customer-key-md5: " & Key_MD5 &
            CRLF, "InvalidRequest", "duplicate SSE-C key digest");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: malformed" &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidDigest", "malformed SSE-C key",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF &
            "x-amz-server-side-encryption-customer-key-md5: malformed" &
            CRLF, "InvalidDigest", "malformed SSE-C key digest",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES128" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidArgument", "invalid SSE-C algorithm",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-decoded-content-length: 14" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF,
            "NotImplemented", "synthetic aws-chunked payload");
         Reject
           ("content-encoding: " & CRLF,
            "InvalidArgument", "empty UploadPart content encoding");
         Reject
           ("content-encoding: aws chunked" & CRLF,
            "InvalidArgument", "malformed UploadPart content coding");
         Reject
           ("content-encoding: aws-chunked," & CRLF,
            "InvalidArgument", "trailing empty content coding");
         Reject
           ("content-encoding: aws-chunked, aws-chunked" & CRLF,
            "InvalidArgument", "duplicate aws-chunked content coding");
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-decoded-content-length: 14" & CRLF &
            "x-amz-sdk-checksum-algorithm: UNKNOWN" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF,
            "InvalidRequest", "aws-chunked invalid checksum selector");
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-decoded-content-length: 14" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc32" & CRLF,
            "InvalidRequest", "aws-chunked wrong trailer declaration");
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF,
            "InvalidRequest", "aws-chunked missing decoded length");
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-decoded-content-length: 14" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF,
            "InvalidRequest", "aws-chunked missing trailer declaration");
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-decoded-content-length: invalid" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF,
            "InvalidArgument", "aws-chunked invalid decoded length");
         Reject
           ("content-encoding: aws-chunked" & CRLF &
            "x-amz-decoded-content-length: 5368709121" & CRLF &
            "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
            "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF,
            "EntityTooLarge", "aws-chunked oversized decoded length");
         Reject
           ("content-encoding: gzip" & CRLF,
            "NotImplemented", "unsupported UploadPart content encoding");

         Reject_Wire
           (Signed_Upload_Part_Declared_Length_Request
              ("/test-bucket/multipart-object", Upload_ID, 1,
               Backends.Maximum_Multipart_Part_Size + 1),
            "EntityTooLarge", "5 GiB+1 declared length");
         declare
            Response : constant String := Run
              (Signed_Upload_Part_Declared_Length_Request
                 ("/test-bucket/multipart-object", Upload_ID, 1,
                  Backends.Maximum_Multipart_Part_Size));
         begin
            Require
              (Has (Response, "503 Service Unavailable")
               and then Has (Response, "<Code>SlowDown</Code>")
               and then not Has (Response, "<Code>EntityTooLarge</Code>"),
               "UploadPart exact 5 GiB scalar missed capacity policy: " &
                 Response);
         end;
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Content_MD5 ("different") & CRLF, "InvalidDigest",
            "mismatched SSE-C key digest", Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidRequest", "SSE-C over plaintext");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "NotImplemented", "unsupported valid SSE-C",
            Flyology.HTTP.Secure_HTTPS);

         declare
            Leading_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("partNumber", "01"),
               SigV4.Pair ("uploadId", Upload_ID));
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/multipart-object", Leading_Query,
                  Payload));
         begin
            Require
              (Has (Response, "<Code>InvalidArgument</Code>"),
               "UploadPart accepted a leading-zero part number");
         end;

         declare
            List_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("uploadId", Upload_ID),
               SigV4.Pair ("x-id", "ListParts"));
            Response : constant String := Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/multipart-object", List_Query));
            Listed : constant Multipart.List_Parts_Result :=
              Multipart.Parse_List_Parts_Result (Response_Body (Response));
         begin
            Require
              (Has (Response, "200 OK") and then Listed.Parts.Length = 1
               and then Listed.Parts.First_Element.Number = 1
               and then Listed.Parts.First_Element.Size = Payload'Length
               and then US.To_String
                 (Listed.Parts.First_Element.Entity_Tag) =
                   '"' & Part_ETag & '"'
               and then US.To_String
                 (Listed.Parts.First_Element.Checksum_CRC64NVME) =
                   Expected_Checksum
               and then Prior_Listed.Parts.Length = 1
               and then US.To_String
                 (Listed.Parts.First_Element.Last_Modified) =
                   US.To_String
                     (Prior_Listed.Parts.First_Element.Last_Modified),
               "rejected UploadPart request changed the prior part");
         end;
      end;
      declare
         Z_Create : constant String := Run
           (Signed_Query_Body_Request
              ("POST", "/test-bucket/multipart-z", Create_Query, ""));
         Nested_Create : constant String := Run
           (Signed_Query_Body_Request
              ("POST", "/test-bucket/nested/active+key", Create_Query,
               ""));

         function Created_ID (Response, Name : String) return String is
         begin
            Require
              (Has (Response, "200 OK"),
               Name & " multipart setup failed: " & Response);
            return US.To_String
              (Multipart.Parse_Create_Result
                 (Response_Body (Response)).Upload_ID);
         end Created_ID;

         Z_ID : constant String := Created_ID (Z_Create, "z-listing");
         Nested_ID : constant String :=
           Created_ID (Nested_Create, "nested-listing");
         First_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("max-uploads", "1"),
            SigV4.Pair ("uploads", ""),
            SigV4.Pair ("x-id", "ListMultipartUploads"));
         First_Response : constant String := Run
           (Signed_Query_Request ("GET", "/test-bucket", First_Query));
         First_Page : constant
           Multipart_Uploads.List_Multipart_Uploads_Result :=
             Multipart_Uploads.Parse_List_Multipart_Uploads
               (Response_Body (First_Response));

         procedure Abort_One (Target, ID : String) is
            Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair ("uploadId", ID));
         begin
            Require
              (Has
                 (Run
                    (Signed_Query_Body_Request
                       ("DELETE", Target, Query, "")),
                  "204 No Content"),
               "ListMultipartUploads corpus cleanup failed");
         end Abort_One;
      begin
         Require
           (Has (First_Response, "200 OK")
            and then First_Page.Uploads.Length = 1
            and then US.To_String (First_Page.Uploads.First_Element.Key) =
              "multipart-object"
            and then US.To_String
              (First_Page.Uploads.First_Element.Upload_ID) = Upload_ID
            and then US.To_String
              (First_Page.Uploads.First_Element.Storage_Class) = "STANDARD"
            and then US.Length
              (First_Page.Uploads.First_Element.Initiated) > 0
            and then First_Page.Is_Truncated
            and then US.To_String (First_Page.Next_Key_Marker) =
              "multipart-object"
            and then US.To_String (First_Page.Next_Upload_ID_Marker) =
              Upload_ID,
            "ListMultipartUploads server first page mismatch: " &
            First_Response);
         declare
            Next_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair
                 ("key-marker", US.To_String (First_Page.Next_Key_Marker)),
               SigV4.Pair ("max-uploads", "10"),
               SigV4.Pair
                 ("upload-id-marker",
                  US.To_String (First_Page.Next_Upload_ID_Marker)),
               SigV4.Pair ("uploads", ""));
            Next_Response : constant String := Run
              (Signed_Query_Request ("GET", "/test-bucket", Next_Query));
            Next_Page : constant
              Multipart_Uploads.List_Multipart_Uploads_Result :=
                Multipart_Uploads.Parse_List_Multipart_Uploads
                  (Response_Body (Next_Response));
         begin
            Require
              (Has (Next_Response, "200 OK")
               and then Next_Page.Uploads.Length = 2
               and then US.To_String (Next_Page.Uploads (1).Key) =
                 "multipart-z"
               and then US.To_String (Next_Page.Uploads (2).Key) =
                 "nested/active+key"
               and then not Next_Page.Is_Truncated,
               "ListMultipartUploads server continuation mismatch: " &
               Next_Response);
         end;
         declare
            Encoded_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("encoding-type", "url"),
               SigV4.Pair ("prefix", "nested/"),
               SigV4.Pair ("uploads", ""));
            Encoded_Response : constant String := Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Encoded_Query));
            Encoded_Page : constant
              Multipart_Uploads.List_Multipart_Uploads_Result :=
                Multipart_Uploads.Parse_List_Multipart_Uploads
                  (Response_Body (Encoded_Response));
         begin
            Require
              (Has (Encoded_Response, "200 OK")
               and then Encoded_Page.Uploads.Length = 1
               and then US.To_String (Encoded_Page.Uploads.First_Element.Key) =
                 "nested/active%2Bkey"
               and then US.To_String (Encoded_Page.Prefix) = "nested/"
               and then US.To_String (Encoded_Page.Encoding_Type) = "url",
               "ListMultipartUploads URL encoding mismatch: " &
               Encoded_Response);
         end;
         declare
            Delimiter_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("delimiter", "/"),
               SigV4.Pair ("uploads", ""));
            Delimiter_Page : constant
              Multipart_Uploads.List_Multipart_Uploads_Result :=
                Multipart_Uploads.Parse_List_Multipart_Uploads
                  (Response_Body
                     (Run
                        (Signed_Query_Request
                           ("GET", "/test-bucket", Delimiter_Query))));
         begin
            Require
              (Delimiter_Page.Uploads.Length = 2
               and then Delimiter_Page.Common_Prefixes.Length = 1
               and then US.To_String
                 (Delimiter_Page.Common_Prefixes.First_Element) = "nested/",
               "ListMultipartUploads delimiter grouping mismatch");
         end;
         declare
            Invalid_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("max-uploads", "0"),
               SigV4.Pair ("uploads", ""));
            Missing_Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair ("uploads", ""));
         begin
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Invalid_Query)),
                  "InvalidArgument"),
               "ListMultipartUploads zero page was accepted");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/absent-bucket", Missing_Query)),
                  "NoSuchBucket"),
               "ListMultipartUploads missing bucket was misreported");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-request-payer", "requester")),
                  "NotImplemented"),
               "ListMultipartUploads silently accepted Requester Pays");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-request-payer", "owner")),
                  "InvalidArgument"),
               "ListMultipartUploads misclassified invalid payer");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-request-payer", "Requester")),
                  "InvalidArgument"),
               "ListMultipartUploads accepted wrong-case payer");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-request-payer", "")),
                  "InvalidArgument"),
               "ListMultipartUploads accepted empty payer");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-request-payer", "requester", "",
                        "requester")),
                  "InvalidRequest"),
               "ListMultipartUploads accepted duplicate payer");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-request-payer", "requester", "", "owner")),
                  "InvalidRequest"),
               "ListMultipartUploads accepted conflicting duplicate payer");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner", "test-principal")),
                  "200 OK"),
               "ListMultipartUploads rejected matching expected owner");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner", "123456789012")),
                  "AccessDenied"),
               "ListMultipartUploads accepted mismatched expected owner");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner", "")),
                  "InvalidRequest"),
               "ListMultipartUploads accepted empty expected owner");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner",
                        String'
                          (1 .. Maximum_Header_Text_Bytes => 'o'))),
                  "AccessDenied"),
               "ListMultipartUploads rejected exact-limit expected owner " &
               "as malformed");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner",
                        String'
                          (1 .. Maximum_Header_Text_Bytes + 1 => 'o'))),
                  "InvalidRequest"),
               "ListMultipartUploads accepted overlong expected owner");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner", "123456789012",
                        "x-amz-request-payer", "owner")),
                  "AccessDenied"),
               "ListMultipartUploads checked payer before expected owner");
            Require
              (Has
                 (Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket", Missing_Query,
                        "x-amz-expected-bucket-owner", "test-principal", "",
                        "test-principal")),
                  "InvalidRequest"),
               "ListMultipartUploads accepted duplicate expected owner");
         end;
         Abort_One ("/test-bucket/multipart-z", Z_ID);
         Abort_One ("/test-bucket/nested/active+key", Nested_ID);
      end;
      declare
         Missing : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("uploadId", "missing"));
         Invalid : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("max-parts", "1001"),
            SigV4.Pair ("uploadId", Upload_ID));
         Valid : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("uploadId", Upload_ID),
            SigV4.Pair ("x-id", "ListParts"));
         Key : constant String :=
           Checksum_Value (Core.SHA256, "list-parts-sse-key");
         Decoded_Key : constant Checksums.Decode_Result :=
           Checksums.Decode_Base64 (Key, Core.SHA256);
         Key_MD5 : constant String := Checksums.Encode_Base64
           (Checksums.Compute
              (Core.MD5, Checksums.Raw_Bytes (Decoded_Key.Value)));

         procedure Reject
           (Headers : String;
            Code    : String;
            Label   : String;
            Scheme  : Flyology.HTTP.Origin_Scheme :=
              Flyology.HTTP.Plain_HTTP)
         is
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/multipart-object", Valid, "",
                  Headers),
               Scheme => Scheme);
         begin
            Require
              (not Has (Response, "200 OK")
               and then Has (Response, "<Code>" & Code & "</Code>"),
               "ListParts accepted " & Label & ": " & Response);
         end Reject;
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket/multipart-object", Valid,
                     "x-amz-expected-bucket-owner", "test-principal")),
               "200 OK"),
            "ListParts rejected matching expected owner");
         Reject
           ("x-amz-expected-bucket-owner: different-owner" & CRLF,
            "AccessDenied", "mismatched expected owner");
         Reject
           ("x-amz-expected-bucket-owner: " & CRLF,
            "InvalidRequest", "empty expected owner");
         Reject
           ("x-amz-expected-bucket-owner: " &
            String'(1 .. Maximum_Header_Text_Bytes => 'o') & CRLF,
            "AccessDenied", "exact-limit mismatched expected owner");
         Reject
           ("x-amz-expected-bucket-owner: " &
            String'(1 .. Maximum_Header_Text_Bytes + 1 => 'o') & CRLF,
            "InvalidRequest", "overlong expected owner");
         Reject
           ("x-amz-expected-bucket-owner: test-principal" & CRLF &
            "x-amz-expected-bucket-owner: test-principal" & CRLF,
            "InvalidRequest", "duplicate expected owner");
         Reject
           ("x-amz-request-payer: requester" & CRLF,
            "NotImplemented", "unsupported requester pays");
         Reject
           ("x-amz-request-payer: Requester" & CRLF,
            "InvalidArgument", "wrong-case request payer");
         Reject
           ("x-amz-request-payer: " & CRLF,
            "InvalidArgument", "empty request payer");
         Reject
           ("x-amz-request-payer: requester" & CRLF &
            "x-amz-request-payer: requester" & CRLF,
            "InvalidRequest", "duplicate request payer");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF, "InvalidRequest", "incomplete SSE-C group");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF &
            "x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidRequest", "duplicate SSE-C algorithm",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES128" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidArgument", "invalid SSE-C algorithm",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: malformed" &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidDigest", "malformed SSE-C key",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Content_MD5 ("different") & CRLF, "InvalidDigest",
            "mismatched SSE-C digest", Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "InvalidRequest", "SSE-C over plaintext");
         Reject
           ("x-amz-server-side-encryption-customer-algorithm: AES256" &
            CRLF & "x-amz-server-side-encryption-customer-key: " & Key &
            CRLF & "x-amz-server-side-encryption-customer-key-md5: " &
            Key_MD5 & CRLF, "NotImplemented", "unsupported valid SSE-C",
            Flyology.HTTP.Secure_HTTPS);
         Reject
           ("x-amz-server-side-encryption: AES256" & CRLF,
            "NotImplemented", "unmodeled encryption control");
         declare
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/multipart-object", Missing, "",
                  "x-amz-request-payer: owner" & CRLF &
                  "x-amz-expected-bucket-owner: different-owner" & CRLF &
                  "x-amz-server-side-encryption-customer-algorithm: " &
                  "AES256" & CRLF,
                  Corrupt_Signature => True));
         begin
            Require
              (Has (Response, "<Code>SignatureDoesNotMatch</Code>")
               and then not Has (Response, "NoSuchUpload")
               and then not Has (Response, "InvalidArgument")
               and then not Has (Response, "AccessDenied")
               and then not Has (Response, "NotImplemented"),
               "ListParts controls ran before authentication: " & Response);
         end;
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket/multipart-object", Missing)),
               "NoSuchUpload"),
            "ListParts missing upload was not reported");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket/multipart-object", Invalid)),
               "InvalidArgument"),
            "ListParts oversized page was accepted");
      end;
      declare
         Completion : Multipart.Complete_Multipart_Upload_Request;
         Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("uploadId", Upload_ID));
      begin
         Completion.Parts.Append
           (Multipart.Completed_Part'
              (Number     => 1,
               Entity_Tag => US.To_Unbounded_String
                 ('"' & Part_ETag & '"'),
               others     => <>));
         declare
            Document : constant String :=
              Multipart.Serialize_Complete_Request (Completion);
            Missing_Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair ("uploadId", "missing-completion"));
            Complete_Body_Limit : constant Positive := 2 * 1_024 * 1_024;
            --  Mirrors the server's existing project-policy admission ceiling
            --  so this corpus gates both accepted wire compatibility at the
            --  boundary and rejection at one byte beyond it.

            procedure Reject_Control
              (Headers         : String;
               Code            : String;
               Label           : String;
               Against_Missing : Boolean := False;
               Corrupt         : Boolean := False;
               Payload         : String := Document)
            is
               Selected_Query : constant SigV4.Name_Value_Array :=
                 (if Against_Missing then Missing_Query else Query);
               Value : constant String := Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-object",
                     Selected_Query, Payload, Headers,
                     Corrupt_Signature => Corrupt));
            begin
               Require
                 (not Has (Value, "200 OK")
                  and then Has (Value, "<Code>" & Code & "</Code>")
                  and then
                    (not Against_Missing
                     or else not Has (Value, "<Code>NoSuchUpload</Code>")),
                  "CompleteMultipartUpload accepted " & Label & ": " &
                  Value);
            end Reject_Control;

            Wrong_Size : constant String := Run
              (Signed_Query_Body_Header_Request
                 ("POST", "/test-bucket/multipart-object", Query, Document,
                  "x-amz-mp-object-size", "15"));
            Failed_Match : constant String := Run
              (Signed_Query_Body_Header_Request
                 ("POST", "/test-bucket/multipart-object", Query, Document,
                  "If-Match", "*"));
            Wrong_Type : constant String := Run
              (Signed_Query_Body_Header_Request
                 ("POST", "/test-bucket/multipart-object", Query, Document,
                  "x-amz-checksum-type", "COMPOSITE"));
            Wrong_Algorithm : constant String := Run
              (Signed_Query_Body_Header_Request
                 ("POST", "/test-bucket/multipart-object", Query, Document,
                  "x-amz-checksum-algorithm", "CRC32"));
         begin
            Reject_Control
              ("x-amz-request-payer: owner" & CRLF,
               "InvalidArgument", "invalid request payer");
            Reject_Control
              ("x-amz-request-payer: " & CRLF,
               "InvalidArgument", "empty request payer");
            Reject_Control
              ("x-amz-request-payer: requester" & CRLF &
               "x-amz-request-payer: requester" & CRLF,
               "InvalidRequest", "duplicate request payer");
            Reject_Control
              ("x-amz-request-payer: requester" & CRLF,
               "NotImplemented", "unsupported requester pays");
            Reject_Control
              ("x-amz-expected-bucket-owner: different-owner" & CRLF,
               "AccessDenied", "mismatched expected owner");
            Reject_Control
              ("x-amz-expected-bucket-owner: " & CRLF,
               "InvalidRequest", "empty expected owner");
            Reject_Control
              ("x-amz-expected-bucket-owner: test-principal" & CRLF &
               "x-amz-expected-bucket-owner: test-principal" & CRLF,
               "InvalidRequest", "duplicate expected owner");
            Reject_Control
              ("x-amz-expected-bucket-owner: test-principal" & CRLF &
               "x-amz-mp-object-size: invalid" & CRLF,
               "InvalidArgument", "matching owner with malformed size");
            Reject_Control
              ("if-match: bad,etag" & CRLF,
               "InvalidArgument", "malformed destination If-Match");
            Reject_Control
              ("if-match: *, ""other""" & CRLF,
               "InvalidArgument", "mixed wildcard destination If-Match");
            Reject_Control
              ("if-none-match: " & CRLF,
               "InvalidArgument", "empty destination If-None-Match");
            Reject_Control
              ("x-amz-mp-object-size: " & CRLF,
               "InvalidArgument", "empty expected object size");
            Reject_Control
              ("x-amz-checksum-algorithm: UNKNOWN" & CRLF,
               "InvalidRequest", "unknown checksum algorithm");
            Reject_Control
              ("x-amz-checksum-type: UNKNOWN" & CRLF,
               "InvalidRequest", "unknown checksum type");
            Reject_Control
              ("x-amz-checksum-unknown: value" & CRLF,
               "InvalidRequest", "unknown checksum value header");
            Reject_Control
              ("x-amz-checksum-crc64nvme: malformed" & CRLF,
               "InvalidRequest", "malformed checksum digest");
            Reject_Control
              ("x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF, "InvalidRequest", "incomplete SSE-C group");
            Reject_Control
              ("x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF &
               "x-amz-server-side-encryption-customer-key: " &
               SSE_Test_Key & CRLF &
               "x-amz-server-side-encryption-customer-key-md5: " &
               SSE_Test_Key_MD5 & CRLF,
               "InvalidRequest", "SSE-C on an unencrypted upload");
            Reject_Control
              ("x-amz-server-side-encryption: AES256" & CRLF,
               "NotImplemented", "unsupported server-side encryption");
            Reject_Control
              ("if-match: bad,etag" & CRLF,
               "InvalidArgument", "missing-upload malformed condition",
               Against_Missing => True);
            Reject_Control
              ("x-amz-mp-object-size: invalid" & CRLF,
               "InvalidArgument", "missing-upload malformed size",
               Against_Missing => True);
            Reject_Control
              ("x-amz-checksum-algorithm: UNKNOWN" & CRLF,
               "InvalidRequest", "missing-upload unknown algorithm",
               Against_Missing => True);
            Reject_Control
              ("x-amz-checksum-type: UNKNOWN" & CRLF,
               "InvalidRequest", "missing-upload unknown checksum type",
               Against_Missing => True);
            Reject_Control
              ("x-amz-checksum-crc64nvme: malformed" & CRLF,
               "InvalidRequest", "missing-upload malformed checksum",
               Against_Missing => True);
            declare
               Auth_Response : constant String := Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-object", Missing_Query,
                     Document,
                     "x-amz-request-payer: owner" & CRLF &
                     "x-amz-expected-bucket-owner: different-owner" & CRLF &
                     "x-amz-mp-object-size: invalid" & CRLF,
                     Corrupt_Signature => True));
            begin
               Require
                 (Has (Auth_Response, "<Code>SignatureDoesNotMatch</Code>")
                  and then not Has (Auth_Response, "NoSuchUpload")
                  and then not Has (Auth_Response, "InvalidArgument")
                  and then not Has (Auth_Response, "AccessDenied"),
                  "CompleteMultipartUpload controls ran before " &
                  "authentication: " & Auth_Response);
            end;
            declare
               Exact_Document : constant String :=
                 Document &
                 String'
                   (1 .. Complete_Body_Limit - Document'Length => ' ');
               One_Past_Document : constant String := Exact_Document & ' ';
               Exact_Response : constant String := Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-object", Missing_Query,
                     Exact_Document));
               One_Past_Response : constant String := Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-object", Missing_Query,
                     One_Past_Document));
            begin
               Require
                 (Has (Exact_Response, "<Code>NoSuchUpload</Code>")
                  and then not Has
                    (Exact_Response, "<Code>EntityTooLarge</Code>"),
                  "CompleteMultipartUpload rejected its exact body limit: " &
                  Exact_Response);
               Require
                 (Has (One_Past_Response, "<Code>EntityTooLarge</Code>"),
                  "CompleteMultipartUpload accepted its body limit plus " &
                  "one: " & One_Past_Response);
            end;
            declare
               Response : constant String := Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-object", Query,
                     Document,
                     "x-amz-checksum-algorithm: CRC64NVME" & CRLF &
                     "x-amz-checksum-type: FULL_OBJECT" & CRLF &
                     "x-amz-mp-object-size: 14" & CRLF),
                  Receive_Max => 2);
               Parsed : constant
                 Multipart.Complete_Multipart_Upload_Result :=
                   Multipart.Parse_Complete_Result
                     (Response_Body (Response));
            begin
               Require
                 (Has (Wrong_Size, "InvalidRequest")
                  and then Has (Failed_Match, "PreconditionFailed")
                  and then Has (Wrong_Type, "<Code>BadDigest</Code>")
                  and then Has
                    (Wrong_Algorithm, "<Code>InvalidRequest</Code>")
                  and then Has (Response, "200 OK")
                  and then Has (Response, "<ETag>""")
                  and then Has (Response, "-1""</ETag>")
                  and then US.To_String (Parsed.Checksum_CRC64NVME) =
                    Expected_Checksum
                  and then US.To_String (Parsed.Checksum_Type) =
                    "FULL_OBJECT",
                  "CompleteMultipartUpload server response mismatch: " &
                  Response);
            end;
         end;
      end;
      declare
         Response : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket/multipart-object", No_Query,
               "x-amz-checksum-mode", "ENABLED"));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Length: 14" & CRLF)
            and then Has (Response, "Content-Type: text/plain" & CRLF)
            and then Has
              (Response, "x-amz-checksum-crc64nvme: " &
                 Expected_Checksum & CRLF)
            and then Has
              (Response, "x-amz-checksum-type: FULL_OBJECT" & CRLF)
            and then Has (Response, Payload),
            "completed multipart object/checksum was not published exactly");
      end;
      declare
         Part_One : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("partNumber", "1"));
         Part_Two : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("partNumber", "2"));
         Part_Response : constant String := Run
           (Signed_Query_Request
              ("HEAD", "/test-bucket/multipart-object", Part_One,
               "x-amz-checksum-mode", "ENABLED"));
         Ranged_Response : constant String := Run
           (Signed_Query_Request
              ("HEAD", "/test-bucket/multipart-object", Part_One,
               "Range", "bytes=2-5"));
         Missing_Response : constant String := Run
           (Signed_Query_Request
              ("HEAD", "/test-bucket/multipart-object", Part_Two));
      begin
         Require
           (Has (Part_Response, "200 OK")
            and then Has (Part_Response, "Content-Length: 14" & CRLF)
            and then Has
              (Part_Response, "x-amz-mp-parts-count: 1" & CRLF)
            and then Has
              (Part_Response, "x-amz-checksum-crc64nvme: " &
                 Expected_Checksum & CRLF)
            and then Has
              (Part_Response, "x-amz-checksum-type: FULL_OBJECT" & CRLF)
            and then not Has (Part_Response, Payload),
            "HeadObject completed-part selection mismatch: " &
            Part_Response);
         Require
           (Has (Ranged_Response, "HTTP/1.1 200 ")
            and then not Has (Ranged_Response, "Content-Range:")
            and then Has (Ranged_Response, "Content-Length: 4" & CRLF)
            and then Has
              (Ranged_Response, "x-amz-mp-parts-count: 1" & CRLF),
            "HeadObject completed-part range mismatch: " &
            Ranged_Response);
         Require
           (Has (Missing_Response, "HTTP/1.1 416 ")
            and then Has
              (Missing_Response, "Content-Range: bytes */14" & CRLF),
            "HeadObject missing completed part mismatch: " &
            Missing_Response);
      end;

      declare
         Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("attributes", ""));
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("GET", "/test-bucket/multipart-object", Query, "",
               "x-amz-object-attributes: ETag,Checksum,ObjectParts," &
               "ObjectSize" & CRLF & "x-amz-max-parts: 1" & CRLF &
               "x-amz-part-number-marker: 0" & CRLF));
         Parsed : constant Attributes.Get_Object_Attributes_Result :=
           Attributes.Parse_Result (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then Parsed.Has_Entity_Tag
            and then Ada.Strings.Fixed.Index
              (US.To_String (Parsed.Entity_Tag), "-1") > 0
            and then Parsed.Object_Size.Is_Set
            and then Parsed.Object_Size.Value = 14
            and then Parsed.Has_Checksum
            and then US.To_String (Parsed.Checksum.CRC64NVME) =
              Expected_Checksum
            and then US.To_String (Parsed.Checksum.Kind) = "FULL_OBJECT"
            and then Parsed.Has_Object_Parts
            and then Parsed.Object_Parts.Total_Parts_Count.Value = 1
            and then Parsed.Object_Parts.Max_Parts.Value = 1
            and then Parsed.Object_Parts.Part_Number_Marker.Value = 0
            and then Parsed.Object_Parts.Has_Is_Truncated
            and then not Parsed.Object_Parts.Is_Truncated
            and then Parsed.Object_Parts.Parts.Length = 1
            and then Parsed.Object_Parts.Parts.First_Element.Number.Value = 1
            and then Parsed.Object_Parts.Parts.First_Element.Size.Value = 14
            and then US.To_String
              (Parsed.Object_Parts.Parts.First_Element.Checksums.CRC64NVME) =
                Expected_Checksum,
            "GetObjectAttributes lost completed multipart metadata: " &
            Response);
      end;

      declare
         Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("attributes", ""));
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("GET", "/test-bucket/multipart-object", Query, "",
               "x-amz-object-attributes: ObjectParts" & CRLF &
               "x-amz-max-parts: 0" & CRLF &
               "x-amz-part-number-marker: 0" & CRLF));
         Parsed : constant Attributes.Get_Object_Attributes_Result :=
           Attributes.Parse_Result (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then Parsed.Has_Object_Parts
            and then Parsed.Object_Parts.Total_Parts_Count.Is_Set
            and then Parsed.Object_Parts.Total_Parts_Count.Value = 1
            and then Parsed.Object_Parts.Part_Number_Marker.Is_Set
            and then Parsed.Object_Parts.Part_Number_Marker.Value = 0
            and then Parsed.Object_Parts.Max_Parts.Is_Set
            and then Parsed.Object_Parts.Max_Parts.Value = 0
            and then Parsed.Object_Parts.Has_Is_Truncated
            and then not Parsed.Object_Parts.Is_Truncated
            and then not Parsed.Object_Parts.Next_Part_Number_Marker.Is_Set
            and then Parsed.Object_Parts.Parts.Is_Empty,
            "GetObjectAttributes MaxParts zero behavior mismatch: " &
            Response);
      end;

      declare
         Copy_Create : constant String := Run
           (Signed_Query_Body_Request
              ("POST", "/test-bucket/multipart-copy", Create_Query, "",
               "Content-Type: text/plain" & CRLF));
         Copy_ID : constant String := US.To_String
           (Multipart.Parse_Create_Result
              (Response_Body (Copy_Create)).Upload_ID);
         Copy_Response : constant String := Run
           (Signed_Upload_Part_Copy_Request
              ("/test-bucket/multipart-copy", Copy_ID,
               "test-bucket/multipart-object", "bytes=10-13"));
         Encrypted_Response : constant String := Run
           (Signed_Upload_Part_Copy_Request
              ("/test-bucket/multipart-copy", Copy_ID,
               "test-bucket/multipart-object", "bytes=10-13", "AES256"));
         Leading_Response : constant String := Run
           (Signed_Upload_Part_Copy_Request
              ("/test-bucket/multipart-copy", Copy_ID,
               "test-bucket/multipart-object", "bytes=10-13",
               Part_Number => "01"));
         Copy_ETag : constant String :=
           "841a2d689ad86bd1611447453c22c6fc";
         Completion : Multipart.Complete_Multipart_Upload_Request;
         Complete_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("uploadId", Copy_ID));
      begin
         Require
           (Has (Copy_Response, "200 OK")
            and then Has (Copy_Response, "<CopyPartResult")
            and then not Has (Copy_Response, "<ChecksumType>")
            and then Has
              (Copy_Response,
               "<ETag>&quot;" & Copy_ETag & "&quot;</ETag>"),
            "UploadPartCopy server response mismatch: " & Copy_Response);
         Require
           (Has (Encrypted_Response, "501 Not Implemented")
            and then Has
              (Encrypted_Response, "<Code>NotImplemented</Code>"),
            "UploadPartCopy silently accepted unsupported encryption");
         Require
           (Has (Leading_Response, "400 Bad Request")
            and then Has
              (Leading_Response, "<Code>InvalidArgument</Code>"),
            "UploadPartCopy accepted a leading-zero part number");
         Completion.Parts.Append
           (Multipart.Completed_Part'
              (Number     => 1,
               Entity_Tag => US.To_Unbounded_String
                 ('"' & Copy_ETag & '"'),
               others     => <>));
         declare
            Complete_Response : constant String := Run
              (Signed_Query_Body_Request
                 ("POST", "/test-bucket/multipart-copy", Complete_Query,
                  Multipart.Serialize_Complete_Request (Completion)));
            Get_Response : constant String := Run
              (Signed_Request
                 ("GET", "/test-bucket/multipart-copy", ""));
         begin
            Require
              (Has (Complete_Response, "200 OK")
               and then Has (Get_Response, "200 OK")
               and then Has (Get_Response, "Content-Length: 4" & CRLF)
               and then Has (Get_Response, "body"),
               "ranged UploadPartCopy did not complete exact bytes");
         end;
      end;

      --  UploadPart has a request checksum body to validate, while
      --  UploadPartCopy does not. Both nevertheless retain the checksum
      --  selected when the upload was initiated.
      declare
         type Payload_Access is access all String;
         Large_Source : constant Payload_Access :=
           new String'(1 .. 5 * 1_024 * 1_024 + 1 => 'c');
         Source_Response : constant String := US.To_String
           (Run_Unbounded
              (Signed_Buffered_Request
              ("PUT", "/test-bucket/multipart-composite-source",
               Large_Source.all)));
         Composite_Create : constant String := Run
           (Signed_Query_Body_Request
              ("POST", "/test-bucket/multipart-composite-copy",
               Create_Query, "",
               "x-amz-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF));
         Composite_ID : constant String := US.To_String
           (Multipart.Parse_Create_Result
              (Response_Body (Composite_Create)).Upload_ID);
         Part_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("partNumber", "1"),
            SigV4.Pair ("uploadId", Composite_ID));
         Missing_Checksum : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket/multipart-composite-copy", Part_Query,
               Payload));
         Copy_Response : constant String := Run
           (Signed_Upload_Part_Copy_Request
              ("/test-bucket/multipart-composite-copy", Composite_ID,
               "test-bucket/multipart-composite-source",
               "bytes=0-5242879"));
         Tail_Copy_Response : constant String := Run
           (Signed_Upload_Part_Copy_Request
              ("/test-bucket/multipart-composite-copy", Composite_ID,
               "test-bucket/multipart-composite-source",
               "bytes=5242880-5242880", Part_Number => "2"));
         Expected_Part_Checksum : constant String :=
           SHA256_Checksum
             (Large_Source.all
                (Large_Source.all'First .. Large_Source.all'Last - 1));
         Expected_Tail_Checksum : constant String := SHA256_Checksum ("c");
      begin
         Require
           (Has (Source_Response, "200 OK")
            and then Has (Composite_Create, "200 OK")
            and then Has (Missing_Checksum, "400 Bad Request")
            and then Has
              (Missing_Checksum, "<Code>InvalidRequest</Code>"),
            "direct composite UploadPart omitted its required checksum");
         Require
           (Has (Copy_Response, "200 OK")
            and then Has (Tail_Copy_Response, "200 OK"),
            "configured composite UploadPartCopy checksum mismatch: " &
            Copy_Response & Tail_Copy_Response);
         declare
            Copied : constant Multipart.Copy_Part_Result :=
              Multipart.Parse_Copy_Part_Result
                (Response_Body (Copy_Response));
            Copied_Tail : constant Multipart.Copy_Part_Result :=
              Multipart.Parse_Copy_Part_Result
                (Response_Body (Tail_Copy_Response));
            List_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("uploadId", Composite_ID),
               SigV4.Pair ("x-id", "ListParts"));
            List_Response : constant String := Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/multipart-composite-copy",
                  List_Query));
            Listed : constant Multipart.List_Parts_Result :=
              Multipart.Parse_List_Parts_Result
                (Response_Body (List_Response));
            Completion : Multipart.Complete_Multipart_Upload_Request;
         begin
            Require
              (US.To_String (Copied.Checksum_SHA256) =
                 Expected_Part_Checksum
               and then Has (List_Response, "200 OK")
               and then US.To_String (Listed.Checksum_Algorithm) = "SHA256"
               and then US.To_String (Listed.Checksum_Type) = "COMPOSITE"
               and then Listed.Parts.Length = 2
               and then US.To_String
                 (Listed.Parts.First_Element.Checksum_SHA256) =
                   Expected_Part_Checksum
               and then US.To_String
                 (Listed.Parts.Last_Element.Checksum_SHA256) =
                   Expected_Tail_Checksum,
               "ListParts lost copied composite checksum");
            Completion.Parts.Append
              (Multipart.Completed_Part'
                 (Number => 1,
                  Entity_Tag => Copied.Entity_Tag,
                  Checksum_SHA256 =>
                    US.To_Unbounded_String (Expected_Part_Checksum),
                  others => <>));
            Completion.Parts.Append
              (Multipart.Completed_Part'
                 (Number => 2,
                  Entity_Tag => Copied_Tail.Entity_Tag,
                  Checksum_SHA256 =>
                    US.To_Unbounded_String (Expected_Tail_Checksum),
                  others => <>));
            declare
               Complete_Query : constant SigV4.Name_Value_Array :=
                 (1 => SigV4.Pair ("uploadId", Composite_ID));
               Document : constant String :=
                 Multipart.Serialize_Complete_Request (Completion);
               Complete_Response : constant String := Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-composite-copy",
                     Complete_Query, Document));
            begin
               Require
                 (Has (Complete_Response, "200 OK"),
                  "composite completion failed: " & Complete_Response);
               declare
                  Completed : constant
                    Multipart.Complete_Multipart_Upload_Result :=
                      Multipart.Parse_Complete_Result
                        (Response_Body (Complete_Response));
                  Completed_Checksum : constant String :=
                    US.To_String (Completed.Checksum_SHA256);
                  Head_Response : constant String := Run
                    (Signed_Query_Request
                       ("HEAD", "/test-bucket/multipart-composite-copy",
                        No_Query, "x-amz-checksum-mode", "ENABLED"));
                  Part_Two : constant SigV4.Name_Value_Array :=
                    (1 => SigV4.Pair ("partNumber", "2"));
                  Part_Head_Response : constant String := Run
                    (Signed_Query_Request
                       ("HEAD", "/test-bucket/multipart-composite-copy",
                        Part_Two, "x-amz-checksum-mode", "ENABLED"));
                  Part_Range_Response : constant String := Run
                    (Signed_Query_Request
                       ("HEAD", "/test-bucket/multipart-composite-copy",
                        Part_Two, "Range", "bytes=0-0",
                        "x-amz-checksum-mode", "ENABLED"));
                  Aligned_Range_Response : constant String := Run
                    (Signed_Query_Request
                       ("HEAD", "/test-bucket/multipart-composite-copy",
                        No_Query, "Range", "bytes=0-5242879",
                        "x-amz-checksum-mode", "ENABLED"));
                  Aligned_Get_Response : constant String := Run
                    (Signed_Query_Request
                       ("GET", "/test-bucket/multipart-composite-copy",
                        No_Query, "Range", "bytes=5242880-5242880",
                        "x-amz-checksum-mode", "ENABLED"));
                  Get_Response : constant US.Unbounded_String :=
                    Run_Unbounded
                    (Signed_Query_Request
                       ("GET", "/test-bucket/multipart-composite-copy",
                        No_Query, "x-amz-checksum-mode", "ENABLED"));
                  Cleanup_Response : constant String := Run
                    (Signed_Request
                       ("DELETE",
                        "/test-bucket/multipart-composite-source", ""));
               begin
                  Require
                    (Completed_Checksum'Length > 2
                     and then Completed_Checksum
                       (Completed_Checksum'Last - 1 ..
                        Completed_Checksum'Last) = "-2"
                     and then US.To_String (Completed.Checksum_Type) =
                       "COMPOSITE"
                     and then Has
                       (Head_Response, "x-amz-checksum-sha256: " &
                          Completed_Checksum & CRLF)
                     and then Has
                       (Head_Response,
                        "x-amz-checksum-type: COMPOSITE" & CRLF)
                     and then Has
                       (Get_Response, "x-amz-checksum-sha256: " &
                          Completed_Checksum & CRLF)
                     and then Has
                       (Get_Response,
                        "x-amz-checksum-type: COMPOSITE" & CRLF)
                     and then Has
                       (Get_Response, "Content-Length: 5242881" & CRLF)
                     and then Has (Get_Response, String'(1 .. 64 => 'c'))
                     and then Has
                       (Part_Head_Response, "x-amz-checksum-sha256: " &
                          Expected_Tail_Checksum & CRLF)
                     and then not Has
                       (Part_Head_Response, Expected_Tail_Checksum & "-")
                     and then Has
                       (Part_Head_Response,
                        "x-amz-checksum-type: COMPOSITE" & CRLF)
                     and then Has
                       (Part_Head_Response,
                        "x-amz-mp-parts-count: 2" & CRLF)
                     and then Has
                       (Part_Range_Response, "Content-Length: 1" & CRLF)
                     and then Has
                       (Part_Range_Response, "x-amz-checksum-sha256: " &
                          Expected_Tail_Checksum & CRLF)
                     and then Has
                       (Part_Range_Response,
                        "x-amz-mp-parts-count: 2" & CRLF)
                     and then Has
                       (Aligned_Range_Response,
                        "Content-Length: 5242880" & CRLF)
                     and then not Has
                       (Aligned_Range_Response, "x-amz-checksum-")
                     and then Has
                       (Aligned_Get_Response, "206 Partial Content")
                     and then Has
                       (Aligned_Get_Response, "Content-Length: 1" & CRLF)
                     and then not Has
                       (Aligned_Get_Response, "x-amz-checksum-")
                     and then Has (Cleanup_Response, "204 No Content"),
                     "HeadObject/GetObject multipart checksum mismatch");
               end;
            end;
         end;
      end;

      declare
         Abort_Create : constant String := Run
           (Signed_Query_Body_Request
              ("POST", "/test-bucket/abort-object", Create_Query, ""));
         Abort_ID : constant String := US.To_String
           (Multipart.Parse_Create_Result
              (Response_Body (Abort_Create)).Upload_ID);
         function Initiated_HTTP_Date return String is
            Options : constant Backends.List_Multipart_Uploads_Options :=
              (Prefix => US.To_Unbounded_String ("abort-object"),
               others => <>);
            Page : Backends.Multipart_Upload_Page;
            Result : Flyology.Object_Storage.Status;
         begin
            Store.List_Multipart_Uploads
              ("test-bucket", Options, null, Ada.Real_Time.Time_Last,
               Page, Result);
            Require
              (Result = Flyology.Object_Storage.Success
               and then Page.Uploads.Length = 1
               and then US.To_String (Page.Uploads.First_Element.Upload_ID) =
                 Abort_ID,
               "AbortMultipartUpload initiation lookup failed");
            return HTTP_Date (Page.Uploads.First_Element.Initiated);
         end Initiated_HTTP_Date;
         Initiated : constant String := Initiated_HTTP_Date;
         Abort_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("uploadId", Abort_ID));
         Invalid_Date : constant String := Run
           (Signed_Query_Body_Request
              ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
               "x-amz-if-match-initiated-time: not-a-date" & CRLF));
         Wrong_Time : constant String := Run
           (Signed_Query_Body_Request
               ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
                "x-amz-if-match-initiated-time: " &
               "Thu, 01 Jan 1970 00:00:00 GMT" & CRLF));
         Wrong_Owner : constant String := Run
           (Signed_Query_Body_Request
              ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
               "x-amz-expected-bucket-owner: another-principal" & CRLF));
         Invalid_Payer : constant String := Run
           (Signed_Query_Body_Request
              ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
               "x-amz-request-payer: owner" & CRLF));
         Requester_Pays : constant String := Run
           (Signed_Query_Body_Request
              ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
               "x-amz-request-payer: requester" & CRLF));
         Duplicate_Time : constant String := Run
           (Signed_Query_Body_Request
               ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
                "x-amz-if-match-initiated-time: " &
               Initiated & CRLF &
                "x-amz-if-match-initiated-time: " &
               Initiated & CRLF));
         Response : constant String := Run
           (Signed_Query_Body_Request
               ("DELETE", "/test-bucket/abort-object", Abort_Query, "",
                "x-amz-if-match-initiated-time: " &
               Initiated & CRLF));
      begin
         Require
           (Has (Invalid_Date, "400 Bad Request")
            and then Has (Invalid_Date, "<Code>InvalidArgument</Code>"),
            "AbortMultipartUpload invalid date mismatch: " & Invalid_Date);
         Require
           (Has (Wrong_Time, "HTTP/1.1 412")
            and then Has (Wrong_Time, "<Code>PreconditionFailed</Code>"),
            "AbortMultipartUpload wrong time mismatch: " & Wrong_Time);
         Require
           (Has (Wrong_Owner, "403 Forbidden"),
            "AbortMultipartUpload wrong owner mismatch: " & Wrong_Owner);
         Require
           (Has (Invalid_Payer, "400 Bad Request"),
            "AbortMultipartUpload invalid payer mismatch: " & Invalid_Payer);
         Require
           (Has (Requester_Pays, "501 Not Implemented"),
            "AbortMultipartUpload requester-pays mismatch: " &
            Requester_Pays);
         Require
           (Has (Duplicate_Time, "400 Bad Request"),
            "AbortMultipartUpload duplicate time mismatch: " &
            Duplicate_Time);
         Require
           (Has (Response, "204 No Content"),
            "AbortMultipartUpload success mismatch: " & Response);
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("DELETE", "/test-bucket/abort-object", Abort_Query,
                     "")),
               "NoSuchUpload"),
            "aborted multipart upload remained visible");
      end;

      declare
         Duplicate : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("uploadId", "a"),
            SigV4.Pair ("uploadId", "b"));
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("POST", "/test-bucket/multipart-object", Duplicate,
                     "")),
               "InvalidArgument"),
            "duplicate multipart query parameter was accepted");
      end;
   end Check_Multipart_Server;

   procedure Check_Metadata_Server is
      V2_Create : constant String :=
        "<MetadataConfiguration>" &
        "<JournalTableConfiguration><RecordExpiration>" &
        "<Expiration>ENABLED</Expiration><Days>30</Days>" &
        "</RecordExpiration><EncryptionConfiguration>" &
        "<SseAlgorithm>AES256</SseAlgorithm>" &
        "</EncryptionConfiguration></JournalTableConfiguration>" &
        "</MetadataConfiguration>";
      V1_Create : constant String :=
        "<MetadataTableConfiguration><S3TablesDestination>" &
        "<TableBucketArn>arn:request</TableBucketArn>" &
        "<TableName>request</TableName>" &
        "</S3TablesDestination></MetadataTableConfiguration>";
      Inventory_Update : constant String :=
        "<InventoryTableConfiguration>" &
        "<ConfigurationState>ENABLED</ConfigurationState>" &
        "</InventoryTableConfiguration>";
      Journal_Update : constant String :=
        "<JournalTableConfiguration><RecordExpiration>" &
        "<Expiration>DISABLED</Expiration>" &
        "</RecordExpiration></JournalTableConfiguration>";
      Annotation_Update : constant String :=
        "<AnnotationTableConfiguration>" &
        "<ConfigurationState>ENABLED</ConfigurationState>" &
        "<Role>metadata-role</Role>" &
        "</AnnotationTableConfiguration>";

      function Query
        (Subresource, Operation_ID : String)
         return SigV4.Name_Value_Array is
        (SigV4.Pair (Subresource, ""),
         SigV4.Pair ("x-id", Operation_ID));

      function Headers
        (Document          : String;
         Require_Algorithm : Boolean := True;
         Owner             : String := "") return String is
        ("Content-MD5: " & Content_MD5 (Document) & CRLF &
         (if Require_Algorithm then
            "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
            "x-amz-checksum-sha256: " &
            Checksum_Value (Core.SHA256, Document) & CRLF
          else "") &
         (if Owner'Length = 0 then ""
          else "x-amz-expected-bucket-owner: " & Owner & CRLF));

      function Mutation
        (Method, Subresource, Operation_ID, Document : String;
         Require_Algorithm : Boolean := True;
         Owner             : String := "") return String is
        (Signed_Query_Body_Request
           (Method, "/test-bucket", Query (Subresource, Operation_ID),
            Document, Headers (Document, Require_Algorithm, Owner)));

      function Control
        (Method, Subresource, Operation_ID : String;
         Owner : String := "") return String is
        (Signed_Query_Request
           (Method, "/test-bucket", Query (Subresource, Operation_ID),
            Extra_Header_Name =>
              (if Owner'Length = 0
               then "" else "x-amz-expected-bucket-owner"),
            Extra_Header_Value => Owner));

      procedure Require_Status
        (Request, Status, Label : String;
         Pattern : String := "")
      is
         Response : constant String := Run (Request);
      begin
         Require
           (Has (Response, Status)
            and then (Pattern'Length = 0 or else Has (Response, Pattern)),
            Label & ": " & Response);
      end Require_Status;

      Initial_Calls : Natural;
   begin
      Require_Status
        (Control
           ("DELETE", "metadataConfiguration",
            "DeleteBucketMetadataConfiguration"),
         "204 No Content", "initial metadata cleanup failed");

      Initial_Calls := Metadata_Provider.Create_Current_Calls;
      declare
         Response : constant String := Run
           (Mutation
              ("POST", "metadataConfiguration",
               "CreateBucketMetadataConfiguration", V2_Create),
            Use_Null_Metadata => True);
      begin
         Require
           (Has (Response, "501 Not Implemented")
            and then Metadata_Provider.Create_Current_Calls = Initial_Calls,
            "null metadata provider mutated state or invoked provider");
      end;

      Require_Status
        (Mutation
           ("POST", "metadataTable",
            "CreateBucketMetadataTableConfiguration", V1_Create,
            Require_Algorithm => False),
         "200 OK", "legacy metadata create failed");
      Require
        (Metadata_Provider.Create_Legacy_Calls = 1,
         "legacy metadata provider call count changed");
      Require_Status
        (Control
           ("GET", "metadataTable",
            "GetBucketMetadataTableConfiguration"),
         "200 OK", "legacy metadata read failed", "arn:legacy");
      Require_Status
        (Control
           ("GET", "metadataConfiguration",
            "GetBucketMetadataConfiguration"),
         "200 OK", "current view of legacy metadata failed", "LEGACY");

      Require_Status
        (Mutation
           ("PUT", "metadataInventoryTable",
            "UpdateBucketMetadataInventoryTableConfiguration",
            Inventory_Update),
         "200 OK", "metadata inventory update failed");
      Require_Status
        (Mutation
           ("PUT", "metadataJournalTable",
            "UpdateBucketMetadataJournalTableConfiguration",
            Journal_Update),
         "200 OK", "metadata journal update failed");
      Require_Status
        (Mutation
           ("PUT", "metadataAnnotationTable",
            "UpdateBucketMetadataAnnotationTableConfiguration",
            Annotation_Update),
         "200 OK", "metadata annotation update failed");
      Require
        (Metadata_Provider.Inventory_Calls = 1
         and then Metadata_Provider.Journal_Calls = 1
         and then Metadata_Provider.Annotation_Calls = 1
         and then Metadata_Provider.Inventory_Observed
         and then Metadata_Provider.Journal_Observed
         and then Metadata_Provider.Annotation_Observed
         and then Metadata_Provider.Inventory_Previous_Observed
         and then Metadata_Provider.Journal_Previous_Observed
         and then Metadata_Provider.Annotation_Previous_Observed,
         "metadata updates lost a member or changed provider call counts");
      Require_Status
        (Control
           ("GET", "metadataConfiguration",
            "GetBucketMetadataConfiguration"),
         "200 OK", "updated metadata read failed", "ANNOTATION");
      Require_Status
        (Control
           ("GET", "metadataTable",
            "GetBucketMetadataTableConfiguration"),
         "200 OK", "updates changed the legacy metadata result",
         "arn:legacy");

      Metadata_Provider.Mode := Metadata_Provider_Fails;
      Require_Status
        (Mutation
           ("PUT", "metadataInventoryTable",
            "UpdateBucketMetadataInventoryTableConfiguration",
            Inventory_Update),
         "503 Service Unavailable", "provider failure was not bounded");
      Metadata_Provider.Mode := Metadata_Provider_Succeeds;
      Require
        (Metadata_Provider.Inventory_Calls = 2,
         "failed metadata update replayed or skipped its provider call");
      Metadata_Provider.Mode := Metadata_Provider_Raises;
      Require_Status
        (Mutation
           ("PUT", "metadataJournalTable",
            "UpdateBucketMetadataJournalTableConfiguration",
            Journal_Update),
         "503 Service Unavailable", "provider exception was not bounded",
         "SlowDown");
      Metadata_Provider.Mode := Metadata_Provider_Succeeds;
      Require
        (Metadata_Provider.Journal_Calls = 2,
         "exceptional metadata update replayed or skipped provider call");
      Require_Status
        (Control
           ("GET", "metadataConfiguration",
            "GetBucketMetadataConfiguration"),
         "200 OK", "provider failure changed retained metadata",
         "ANNOTATION");

      Require_Status
        (Control
           ("DELETE", "metadataTable",
            "DeleteBucketMetadataTableConfiguration"),
         "204 No Content", "legacy metadata delete failed");
      Require_Status
        (Control
           ("GET", "metadataTable",
            "GetBucketMetadataTableConfiguration"),
         "200 OK", "absent legacy metadata read failed");
      Require_Status
        (Control
           ("GET", "metadataConfiguration",
            "GetBucketMetadataConfiguration"),
         "404 Not Found", "absent current metadata read failed",
         "NoSuchConfiguration");

      Require_Status
        (Mutation
           ("POST", "metadataConfiguration",
            "CreateBucketMetadataConfiguration", V2_Create),
         "200 OK", "current metadata create failed");
      Require
        (Metadata_Provider.Create_Current_Calls = Initial_Calls + 1,
         "current metadata provider call count changed");
      Require_Status
        (Control
           ("GET", "metadataTable",
            "GetBucketMetadataTableConfiguration"),
         "405 Method Not Allowed",
         "legacy read accepted current metadata state");
      Require_Status
        (Control
           ("DELETE", "metadataTable",
            "DeleteBucketMetadataTableConfiguration"),
         "405 Method Not Allowed",
         "legacy delete accepted current metadata state");

      Initial_Calls := Metadata_Provider.Inventory_Calls;
      declare
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket",
               Query
                 ("metadataInventoryTable",
                  "UpdateBucketMetadataInventoryTableConfiguration"),
               Inventory_Update,
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Inventory_Update) & CRLF));
      begin
         Require
           (Has (Response, "400 Bad Request")
            and then Has (Response, "InvalidDigest")
            and then Metadata_Provider.Inventory_Calls = Initial_Calls,
            "missing metadata Content-MD5 invoked provider");
      end;
      declare
         Digest : constant String := Content_MD5 (Inventory_Update);
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket",
               Query
                 ("metadataInventoryTable",
                  "UpdateBucketMetadataInventoryTableConfiguration"),
               Inventory_Update,
               "Content-MD5: " & Digest & CRLF &
               "Content-MD5: " & Digest & CRLF &
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Inventory_Update) & CRLF));
      begin
         Require
           (Has (Response, "400 Bad Request")
            and then Has (Response, "InvalidRequest")
            and then Metadata_Provider.Inventory_Calls = Initial_Calls,
            "duplicate metadata Content-MD5 invoked provider");
      end;
      declare
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket",
               Query
                 ("metadataInventoryTable",
                  "UpdateBucketMetadataInventoryTableConfiguration"),
               Inventory_Update,
               "Content-MD5: " & Content_MD5 (Inventory_Update) & CRLF &
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, "different") & CRLF));
      begin
         Require
           (Has (Response, "400 Bad Request")
            and then Has (Response, "BadDigest")
            and then Metadata_Provider.Inventory_Calls = Initial_Calls,
            "mismatched metadata checksum invoked provider");
      end;
      declare
         Response : constant String := Run
           (Mutation
              ("PUT", "metadataInventoryTable",
               "UpdateBucketMetadataInventoryTableConfiguration",
               Inventory_Update, Owner => "wrong-owner"));
      begin
         Require
           (Has (Response, "403 Forbidden")
            and then Metadata_Provider.Inventory_Calls = Initial_Calls,
            "expected-owner rejection invoked metadata provider");
      end;
      declare
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket",
               Query
                 ("metadataInventoryTable",
                  "UpdateBucketMetadataInventoryTableConfiguration"),
               Inventory_Update,
               "Content-MD5: " & Content_MD5 (Inventory_Update) & CRLF));
      begin
         Require
           (Has (Response, "400 Bad Request")
            and then Metadata_Provider.Inventory_Calls = Initial_Calls,
            "missing algorithm checksum invoked metadata provider");
      end;
      Require_Status
        (Signed_Query_Body_Request
           ("POST", "/test-bucket",
            Query
              ("metadataConfiguration",
               "CreateBucketMetadataConfiguration"),
            "<MetadataConfiguration><Unknown/></MetadataConfiguration>",
            Headers
              ("<MetadataConfiguration><Unknown/>" &
               "</MetadataConfiguration>")),
         "400 Bad Request", "malformed metadata XML was accepted",
         "MalformedXML");
      Require_Status
        (Signed_Query_Request
           ("GET", "/test-bucket",
            (SigV4.Pair ("metadataConfiguration", ""),
             SigV4.Pair ("x-id", "GetBucketMetadataTableConfiguration"))),
         "400 Bad Request", "cross-operation metadata query was accepted",
         "InvalidArgument");

      Require_Status
        (Control
           ("DELETE", "metadataConfiguration",
            "DeleteBucketMetadataConfiguration"),
         "204 No Content", "current metadata delete failed");
      Initial_Calls := Metadata_Provider.Inventory_Calls;
      Require_Status
        (Mutation
           ("PUT", "metadataInventoryTable",
            "UpdateBucketMetadataInventoryTableConfiguration",
            Inventory_Update),
         "404 Not Found", "absent metadata update was not rejected",
         "NoSuchConfiguration");
      Require
        (Metadata_Provider.Inventory_Calls = Initial_Calls,
         "absent metadata update invoked provider");
      Require_Status
        (Control
           ("DELETE", "metadataConfiguration",
            "DeleteBucketMetadataConfiguration"),
         "204 No Content", "absent metadata delete was not idempotent");
   end Check_Metadata_Server;

begin
   declare
      Response : constant String := Run
        ("PUT /test-bucket HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF &
         "Expect: 100-continue" & CRLF &
         "Content-Length: 4" & CRLF &
         "Connection: close" & CRLF & CRLF & "data");
   begin
      Require (Has (Response, "403 Forbidden"),
               "unsigned request was not rejected");
      Require (not Has (Response, "100 Continue"),
               "body was accepted before authentication");
   end;

   declare
      type Method_Array is array (Positive range <>) of String (1 .. 6);
      Methods : constant Method_Array := ("PUT   ", "GET   ", "DELETE");
   begin
      for Method of Methods loop
         declare
            Verb : constant String :=
              Ada.Strings.Fixed.Trim (Method, Ada.Strings.Right);
            Operation_ID : constant String :=
              (if Verb = "PUT" then "PutBucketTagging"
               elsif Verb = "GET" then "GetBucketTagging"
               else "DeleteBucketTagging");
            Response : constant String := Run
              (Verb & " /test-bucket?tagging=&tagging= HTTP/1.1" & CRLF &
               "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
               "Connection: close" & CRLF & CRLF);
            ID_Only_Response : constant String := Run
              (Verb & " /test-bucket?x-id=" & Operation_ID &
               " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
               "Content-Length: 0" & CRLF & "Connection: close" & CRLF &
               CRLF);
         begin
            Require
              (Has (Response, "403 Forbidden")
               and then not Has (Response, "InvalidArgument"),
               "malformed bucket-tagging query bypassed authentication for " &
                 Verb);
            Require
              (Has (ID_Only_Response, "403 Forbidden")
               and then not Has (ID_Only_Response, "InvalidArgument"),
               "x-id-only bucket-tagging query bypassed authentication for " &
                 Verb);
         end;
      end loop;
   end;

   declare
      Response : constant String := Run
        ("POST /test-bucket/object?uploadId=a&uploadId=b HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden")
         and then not Has (Response, "InvalidArgument"),
         "malformed multipart query bypassed authentication");
   end;

   declare
      Response : constant String := Run
        ("DELETE /test-bucket/object?versionId=a&versionId=b HTTP/1.1" &
         CRLF & "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden")
         and then not Has (Response, "InvalidArgument"),
         "malformed DeleteObject query bypassed authentication");
   end;

   declare
      Response : constant String := Run
        ("GET /test-bucket/object?tagging=&unknown=value HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden")
         and then not Has (Response, "InvalidArgument"),
         "malformed object-tagging query bypassed authentication");
   end;

   declare
      Response : constant String := Run
        ("GET /test-bucket/object?%74agging HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden"),
         "encoded object-tagging subresource bypassed authentication");
   end;

   declare
      Response : constant String := Run
        ("GET /?max-buckets=1&max-buckets=2 HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden")
         and then not Has (Response, "InvalidArgument"),
         "malformed ListBuckets query bypassed authentication");
   end;

   declare
      Response : constant String := Run
        ("HEAD /test-bucket/object?partNumber=0 HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden")
         and then not Has (Response, "InvalidArgument"),
         "malformed HeadObject query bypassed authentication");
   end;

   declare
      Response : constant String := Run
        ("GET /test-bucket/object?attributes&attributes HTTP/1.1" & CRLF &
         "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
         "Connection: close" & CRLF & CRLF);
   begin
      Require
        (Has (Response, "403 Forbidden")
         and then not Has (Response, "InvalidArgument"),
         "malformed GetObjectAttributes query bypassed authentication");
   end;

   declare
      Response : constant String := Run
        (Signed_Request ("PUT", "/absent-bucket/object", "payload"));
   begin
      Require
        (Has (Response, "404 Not Found")
         and then Has (Response, "<Code>NoSuchBucket</Code>")
         and then not Has (Response, "<Code>NoSuchKey</Code>"),
         "PutObject on an absent bucket did not return NoSuchBucket");
   end;

   declare
      Wrong_Root : constant String := "<WrongRoot/>";
      Wrong_Region : constant String :=
        "<CreateBucketConfiguration>" &
        "<LocationConstraint>us-west-2</LocationConstraint>" &
        "</CreateBucketConfiguration>";
      Empty_Constraint : constant String :=
        "<CreateBucketConfiguration><LocationConstraint/>" &
        "</CreateBucketConfiguration>";
      Directory : constant String :=
        "<CreateBucketConfiguration>" &
        "<Location><Type>AvailabilityZone</Type>" &
        "<Name>usw2-az1</Name></Location>" &
        "<Bucket><DataRedundancy>SingleAvailabilityZone" &
        "</DataRedundancy><Type>Directory</Type></Bucket>" &
        "</CreateBucketConfiguration>";
      Tagged_Document : constant String :=
        "<CreateBucketConfiguration><Tags><Tag><Key>team</Key>" &
        "<Value>storage</Value></Tag></Tags>" &
        "</CreateBucketConfiguration>";
      Empty_Configuration : constant String :=
        "<CreateBucketConfiguration/>";
      Create_Bucket_Body_Limit : constant Positive := 64 * 1_024;
      Exact_Limit_Document : constant String :=
        Empty_Configuration & String'
          (1 .. Create_Bucket_Body_Limit - Empty_Configuration'Length => ' ');
      One_Past_Document : constant String := Exact_Limit_Document & ' ';
      --  This test/reference limit mirrors the server's established
      --  project-policy ceiling. Exact and one-past oracles intentionally fail
      --  together if that wire-compatibility choice is reviewed for change.
   begin
      declare
         Response : constant String :=
           Run
             (Signed_Create_Bucket_Request
                ("/malformed-create", Wrong_Root));
      begin
         Require
           (Has (Response, "400 Bad Request")
            and then Has (Response, "<Code>MalformedXML</Code>"),
            "CreateBucket accepted an invalid XML root");
      end;
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/wrong-region-create", Wrong_Region)),
            "<Code>IllegalLocationConstraintException</Code>"),
         "CreateBucket accepted a mismatched location constraint");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/empty-constraint-create", Empty_Constraint)),
            "<Code>MalformedXML</Code>"),
         "CreateBucket accepted an empty location constraint");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/directory-create", Directory)),
            "501 Not Implemented"),
         "CreateBucket silently accepted directory-bucket configuration");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/tagged-create", Tagged_Document)),
            "501 Not Implemented"),
         "CreateBucket silently accepted unpersisted tags");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/public-create", "", "x-amz-acl", "public-read")),
            "501 Not Implemented"),
         "CreateBucket silently accepted an unsupported public ACL");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/invalid-acl-create", "", "x-amz-acl", "bogus")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket accepted an invalid canned ACL");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/duplicate-acl-create", "", "x-amz-acl", "private",
                  "private")),
            "400 Bad Request"),
         "CreateBucket accepted duplicate ACL fields");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/empty-acl-create", "", "x-amz-acl", "")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket treated an empty ACL as absent");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/invalid-ownership-create", "",
                  "x-amz-object-ownership", "bogus")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket accepted invalid object ownership");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/empty-ownership-create", "",
                  "x-amz-object-ownership", "")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket treated empty object ownership as absent");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/lock-create", "",
                  "x-amz-bucket-object-lock-enabled", "true")),
            "501 Not Implemented"),
         "CreateBucket silently accepted Object Lock");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/invalid-lock-create", "",
                  "x-amz-bucket-object-lock-enabled", "yes")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket accepted an invalid Object Lock value");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/empty-lock-create", "",
                  "x-amz-bucket-object-lock-enabled", "")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket misclassified empty Object Lock");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/namespace-create", "", "x-amz-bucket-namespace",
                  "global")),
            "501 Not Implemented"),
         "CreateBucket silently accepted bucket namespace controls");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/invalid-namespace-create", "",
                  "x-amz-bucket-namespace", "bogus")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket accepted an invalid bucket namespace");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/empty-namespace-create", "",
                  "x-amz-bucket-namespace", "")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket misclassified an empty bucket namespace");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/grant-create", "", "x-amz-grant-read", "id=reader")),
            "501 Not Implemented"),
         "CreateBucket silently accepted an ACL grant");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/duplicate-grant-create", "", "x-amz-grant-read",
                  "id=reader", "id=reader")),
            "<Code>InvalidRequest</Code>"),
         "CreateBucket accepted duplicate ACL grant fields");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/empty-grant-create", "", "x-amz-grant-read", "")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket misclassified an empty ACL grant");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/exact-limit-create", Exact_Limit_Document)),
            "200 OK"),
         "CreateBucket rejected the exact body-size limit");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/one-past-create", One_Past_Document)),
            "<Code>EntityTooLarge</Code>"),
         "CreateBucket accepted one byte beyond the body-size limit");
      declare
         Value : constant String := Run
           (Signed_Create_Bucket_Request
              ("/auth-precedence-create", "", "x-amz-acl", "",
               Corrupt_Signature => True));
      begin
         Require
           (Has (Value, "<Code>SignatureDoesNotMatch</Code>"),
            "CreateBucket controls ran before authentication: " & Value);
      end;
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("DELETE", "/exact-limit-create")),
            "204 No Content"),
         "exact-limit CreateBucket cleanup failed");
      Require
        (Has
           (Run (Signed_Bucket_Request ("HEAD", "/wrong-region-create")),
            "404 Not Found"),
         "rejected CreateBucket request mutated backend state");
      Require
        (Has
           (Run (Signed_Bucket_Request ("HEAD", "/malformed-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/tagged-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/public-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/empty-acl-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/empty-ownership-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/empty-lock-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/empty-namespace-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/empty-grant-create")),
            "404 Not Found")
         and then Has
           (Run (Signed_Bucket_Request ("HEAD", "/one-past-create")),
            "404 Not Found")
         and then Has
           (Run
              (Signed_Bucket_Request
                 ("HEAD", "/auth-precedence-create")),
            "404 Not Found"),
         "rejected CreateBucket controls mutated backend state");
   end;

   Require
     (Has
        (Run
           (Signed_Create_Bucket_Request
              ("/configured-create", "<CreateBucketConfiguration/>")),
         "200 OK"),
      "valid empty CreateBucket configuration failed");
   Require
     (Has
        (Run
           (Signed_Bucket_Request ("DELETE", "/configured-create")),
         "204 No Content"),
      "configured CreateBucket cleanup failed");
   Require
     (Has
        (Run
           (Signed_Create_Bucket_Request
              ("/private-create", "", "x-amz-acl", "private")),
         "200 OK"),
      "CreateBucket rejected the supported private ACL");
   Require
     (Has
        (Run (Signed_Bucket_Request ("DELETE", "/private-create")),
         "204 No Content"),
      "private CreateBucket cleanup failed");
   Require
     (Has
        (Run
           (Signed_Create_Bucket_Request
              ("/owned-create", "", "x-amz-object-ownership",
               "BucketOwnerEnforced")),
         "200 OK"),
      "CreateBucket rejected BucketOwnerEnforced");
   Require
     (Has
        (Run (Signed_Bucket_Request ("DELETE", "/owned-create")),
         "204 No Content"),
      "owned CreateBucket cleanup failed");

   Require
     (Has (Run (Signed_Request ("PUT", "/test-bucket", ""), 1),
           "200 OK"),
      "signed choppy CreateBucket failed");
   declare
      Response : constant String :=
        Run (Signed_Bucket_Request ("HEAD", "/test-bucket"));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "x-amz-bucket-region: us-east-1")
         and then Response_Body (Response) = "",
         "signed HeadBucket metadata mismatch");
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("HEAD", "/test-bucket", "test-principal")),
            "200 OK"),
         "HeadBucket rejected the authenticated owner");
      declare
         Rejected : constant String :=
           Run
             (Signed_Bucket_Request
                ("HEAD", "/test-bucket", "different-owner"));
      begin
         Require
           (Has (Rejected, "403 Forbidden")
            and then Has
              (Rejected, "x-amz-bucket-region: us-east-1")
            and then Response_Body (Rejected) = "",
            "HeadBucket ignored the expected owner precondition");
      end;
      declare
         Missing : constant String :=
           Run (Signed_Bucket_Request ("HEAD", "/absent-bucket"));
      begin
         Require
           (Has (Missing, "404 Not Found")
            and then Has (Missing, "x-amz-bucket-region: us-east-1")
            and then Response_Body (Missing) = "",
            "HeadBucket absent-bucket metadata mismatch");
      end;
      declare
         Duplicate : constant String :=
           Run
             (Signed_Bucket_Request
                ("HEAD", "/test-bucket", "test-principal",
                 "test-principal"));
      begin
         Require
           (Has (Duplicate, "400 Bad Request")
            and then Has
              (Duplicate, "x-amz-bucket-region: us-east-1")
            and then Response_Body (Duplicate) = "",
            "HeadBucket accepted a duplicate expected owner header: " &
              Duplicate);
      end;
   end;

   declare
      Bucket_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("acl", ""));
      Bucket_ID_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("acl", ""), SigV4.Pair ("x-id", "GetBucketAcl"));
      Bucket_Put_ID_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("acl", ""), SigV4.Pair ("x-id", "PutBucketAcl"));
      Object_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("acl", ""));
      Object_Version_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("acl", ""), SigV4.Pair ("versionId", "null"));
      Object_Put_ID_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("acl", ""), SigV4.Pair ("x-id", "PutObjectAcl"));
      Empty_Content_MD5 : constant String :=
        "1B2M2Y8AsgTpgAmY7PhCfg==";

      function Private_ACL_Headers
        (Additional : String := "") return String is
        ("x-amz-acl: private" & CRLF &
         "Content-MD5: " & Empty_Content_MD5 & CRLF & Additional);

      function Encoded_ACL_Request
        (Method, Target : String) return String
      is
         Request : constant String :=
           Signed_Query_Request (Method, Target, Object_Query);
         Marker : constant Natural :=
           Ada.Strings.Fixed.Index (Request, "?acl=");
      begin
         if Marker = 0 then
            raise Program_Error with "ACL test signer omitted its query";
         end if;
         --  SigV4 decodes query components before canonicalization, so this
         --  wire spelling has the same valid signature as the plain name.
         return Request (Request'First .. Marker - 1) & "?%61cl=" &
           Request (Marker + 5 .. Request'Last);
      end Encoded_ACL_Request;

      procedure Check_Private_ACL (Response, Label_Text : String) is
         Policy : constant ACL.Access_Control_Policy :=
           ACL.Parse (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Type: application/xml"),
            Label_Text & " did not return an XML success");
         Require
           (Policy.Is_Set and then Policy.Policy_Owner.Is_Set
            and then Policy.Policy_Owner.ID.Is_Set
            and then US.To_String (Policy.Policy_Owner.ID.Value) =
              "test-principal"
            and then Policy.ACL.Is_Set and then Policy.ACL.Grants.Length = 1,
            Label_Text & " did not derive the private tenant ACL");
         declare
            Grant : constant ACL.Grant :=
              Policy.ACL.Grants.First_Element;
         begin
            Require
              (Grant.Principal.Is_Set
               and then Grant.Principal.Kind = ACL.Canonical_User
               and then Grant.Principal.ID.Is_Set
               and then US.To_String (Grant.Principal.ID.Value) =
                 "test-principal"
               and then Grant.Allowed.Is_Set
               and then Grant.Allowed.Value = ACL.Full_Control,
               Label_Text & " did not derive the private tenant ACL");
         end;
      end Check_Private_ACL;
   begin
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/test-bucket/acl-object", "acl payload")),
            "200 OK"),
         "ACL server fixture PutObject failed");
      Check_Private_ACL
        (Run (Signed_Query_Request
          ("GET", "/test-bucket", Bucket_Query)),
         "GetBucketAcl");
      Check_Private_ACL
        (Run (Signed_Query_Request
          ("GET", "/test-bucket", Bucket_ID_Query)),
         "GetBucketAcl x-id");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  Private_ACL_Headers)),
            "200 OK"),
         "PutBucketAcl rejected the private canned ACL");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Put_ID_Query, "",
                  Private_ACL_Headers)),
            "200 OK"),
         "PutBucketAcl rejected its exact x-id");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("x-id", "PutObjectAcl")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutBucketAcl accepted the object operation id");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("acl", "")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutBucketAcl accepted a duplicate acl query");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("unexpected", "1")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutBucketAcl accepted an extra query member");
      Check_Private_ACL
        (Run (Signed_Query_Request
          ("GET", "/test-bucket", Bucket_Query)),
         "GetBucketAcl after private replacement");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  "x-amz-acl: public-read" & CRLF &
                  "Content-MD5: " & Empty_Content_MD5 & CRLF)),
            "501 Not Implemented"),
         "PutBucketAcl accepted a non-private canned ACL");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  "x-amz-grant-read: id=""test-principal""" & CRLF &
                  "Content-MD5: " & Empty_Content_MD5 & CRLF)),
            "501 Not Implemented"),
         "PutBucketAcl accepted an explicit grant");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  Private_ACL_Headers
                    ("x-amz-expected-bucket-owner: different-owner" &
                     CRLF))),
            "403 Forbidden"),
         "PutBucketAcl ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/absent-bucket", Bucket_Query, "",
                  Private_ACL_Headers)),
            "<Code>NoSuchBucket</Code>"),
         "PutBucketAcl did not verify bucket existence");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  "x-amz-acl: private" & CRLF &
                  "Content-MD5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketAcl accepted a mismatched empty-body digest");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  "x-amz-acl: private" & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAcl accepted a missing Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  Private_ACL_Headers
                    ("x-amz-acl: private" & CRLF))),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAcl accepted duplicate canned ACL fields");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  Private_ACL_Headers
                    ("Content-MD5: " & Empty_Content_MD5 & CRLF))),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAcl accepted duplicate Content-MD5 fields");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  Private_ACL_Headers
                    ("x-amz-grant-read: id=""test-principal""" &
                     CRLF))),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAcl accepted conflicting ACL modes");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query, "",
                  Private_ACL_Headers
                    ("x-amz-sdk-checksum-algorithm: SHA256" & CRLF))),
            "501 Not Implemented"),
         "PutBucketAcl accepted an additional checksum algorithm");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Bucket_Query,
                  "<AccessControlPolicy/>")),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAcl accepted XML policy mode");
      Check_Private_ACL
        (Run
           (Signed_Query_Request
              ("GET", "/test-bucket", Bucket_Query,
               "x-amz-expected-bucket-owner", "test-principal")),
         "GetBucketAcl expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Bucket_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketAcl ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Bucket_Query,
                  "x-amz-request-payer", "requester")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketAcl accepted RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("acl", ""), SigV4.Pair ("acl", "")))),
            "400 Bad Request"),
         "GetBucketAcl accepted a duplicate acl query");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("x-id", "GetObjectAcl")))),
            "400 Bad Request"),
         "GetBucketAcl accepted the object operation id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Bucket_Query)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketAcl did not distinguish an absent bucket");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Bucket_Query, "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketAcl accepted a request body");
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/test-bucket", "", Query_Name => "acl",
                  Corrupt_Signature => True)),
            "<Code>SignatureDoesNotMatch</Code>"),
         "GetBucketAcl validation ran before authentication");

      Check_Private_ACL
        (Run (Signed_Query_Request
          ("GET", "/test-bucket/acl-object", Object_Query)),
         "GetObjectAcl");
      Check_Private_ACL
        (Run (Encoded_ACL_Request
          ("GET", "/test-bucket/acl-object")),
         "GetObjectAcl encoded subresource");
      Check_Private_ACL
        (Run
           (Signed_Query_Request
              ("GET", "/test-bucket/acl-object", Object_Version_Query)),
         "GetObjectAcl null version");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object", Object_Query, "",
                  Private_ACL_Headers)),
            "200 OK"),
         "PutObjectAcl rejected the private canned ACL");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object", Object_Put_ID_Query, "",
                  Private_ACL_Headers)),
            "200 OK"),
         "PutObjectAcl rejected its exact x-id");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("x-id", "PutBucketAcl")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutObjectAcl accepted the bucket operation id");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("acl", "")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutObjectAcl accepted a duplicate acl query");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("unexpected", "1")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutObjectAcl accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("versionId", "")), "",
                  Private_ACL_Headers)),
            "400 Bad Request"),
         "PutObjectAcl accepted an empty version selector");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object", Object_Version_Query, "",
                  Private_ACL_Headers)),
            "200 OK"),
         "PutObjectAcl rejected the null version selector");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket/acl-object", Object_Query, "",
                 Private_ACL_Headers
                   ("x-amz-request-payer: requester" & CRLF)));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "x-amz-request-charged: requester"),
            "PutObjectAcl requester-pays response mismatch");
      end;
      Check_Private_ACL
        (Run (Signed_Query_Request
          ("GET", "/test-bucket/acl-object", Object_Query)),
         "GetObjectAcl after private replacement");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object", Object_Query, "",
                  "x-amz-acl: public-read" & CRLF &
                  "Content-MD5: " & Empty_Content_MD5 & CRLF)),
            "501 Not Implemented"),
         "PutObjectAcl accepted a non-private canned ACL");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object", Object_Query, "",
                  "x-amz-acl: private" & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectAcl accepted a missing Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/acl-object", Object_Query, "",
                  "x-amz-acl: private" & CRLF &
                  "Content-MD5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutObjectAcl accepted a mismatched empty-body digest");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/missing-acl-object", Object_Query, "",
                  Private_ACL_Headers)),
            "<Code>NoSuchKey</Code>"),
         "PutObjectAcl did not verify object existence");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/absent-bucket/object", Object_Query, "",
                  Private_ACL_Headers)),
            "<Code>NoSuchBucket</Code>"),
         "PutObjectAcl did not distinguish an absent bucket");
      Check_Private_ACL
        (Run
           (Signed_Query_Request
              ("GET", "/test-bucket/acl-object", Object_Query,
               "x-amz-request-payer", "requester")),
         "GetObjectAcl RequestPayer");
      Check_Private_ACL
        (Run
           (Signed_Query_Request
              ("GET", "/test-bucket/acl-object", Object_Query,
               "x-amz-expected-bucket-owner", "test-principal")),
         "GetObjectAcl expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/acl-object", Object_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetObjectAcl ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/acl-object", Object_Query,
                  "x-amz-request-payer", "owner")),
            "<Code>InvalidRequest</Code>"),
         "GetObjectAcl accepted an invalid RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/acl-object", Object_Query,
                  "x-amz-request-payer", "requester",
                  Second_Header_Value => "requester")),
            "<Code>InvalidRequest</Code>"),
         "GetObjectAcl accepted duplicate RequestPayer fields");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/missing-acl-object", Object_Query)),
            "<Code>NoSuchKey</Code>"),
         "GetObjectAcl did not distinguish an absent object");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket/object", Object_Query)),
            "<Code>NoSuchBucket</Code>"),
         "GetObjectAcl did not distinguish an absent bucket");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/acl-object",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetObjectAcl accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/acl-object",
                  (SigV4.Pair ("acl", ""),
                   SigV4.Pair ("versionId", "")))),
            "400 Bad Request"),
         "GetObjectAcl accepted an empty version selector");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/acl-object", Object_Query,
                  "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "GetObjectAcl accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("PUT", "/test-bucket/acl-mutation-guard", Object_Query)),
            "400 Bad Request"),
         "PutObjectAcl accepted a missing canned ACL");
      Require
        (Has
           (Run
              (Encoded_ACL_Request
                 ("PUT", "/test-bucket/encoded-acl-mutation-guard")),
            "400 Bad Request"),
         "encoded PutObjectAcl accepted a missing canned ACL");
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/test-bucket/acl-mutation-guard", "")),
            "<Code>NoSuchKey</Code>"),
         "unsupported PutObjectAcl reached PutObject storage");
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/test-bucket/encoded-acl-mutation-guard", "")),
            "<Code>NoSuchKey</Code>"),
         "encoded PutObjectAcl reached PutObject storage");
      Require
        (Has
           (Run
              (Signed_Request
                 ("DELETE", "/test-bucket/acl-object", "")),
            "204 No Content"),
         "ACL server fixture cleanup failed");
   end;

   declare
      First_ETag : constant String :=
        """8b04d5e3775d298e78455efc5ca404d5""";
      Second_ETag : constant String :=
        """a9f0e61a137d86aa9db53465e0801612""";
      Created : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "first",
            Extra_Headers => "If-None-Match: *" & CRLF));
      Collision : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "collision",
            Extra_Headers => "If-None-Match: *" & CRLF));
      Replaced : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "second",
            Extra_Headers => "If-Match: " & First_ETag & CRLF));
      Stale : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "stale",
            Extra_Headers => "If-Match: " & First_ETag & CRLF));
      Missing : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-missing", "missing",
            Extra_Headers => "If-Match: " & Second_ETag & CRLF));
      Malformed : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "malformed",
            Extra_Headers => "If-Match: ""unterminated" & CRLF));
      Empty : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "empty",
            Extra_Headers => "If-Match:" & CRLF));
      Duplicate_Match : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "duplicate",
            Extra_Headers =>
              "If-Match: " & Second_ETag & CRLF &
              "If-Match: " & Second_ETag & CRLF));
      Duplicate_None : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "duplicate",
            Extra_Headers =>
              "If-None-Match: ""other""" & CRLF &
              "If-None-Match: ""other""" & CRLF));
      Combined : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/conditional-put", "third",
            Extra_Headers =>
              "If-Match: " & Second_ETag & CRLF &
              "If-None-Match: ""other""" & CRLF));
      Observed : constant String := Run
        (Signed_Request ("GET", "/test-bucket/conditional-put", ""));
      Cleanup : constant String := Run
        (Signed_Request ("DELETE", "/test-bucket/conditional-put", ""));
   begin
      Require
        (Has (Created, "200 OK") and then Has (Created, First_ETag),
         "signed create-if-absent PutObject failed");
      Require
        (Has (Collision, "HTTP/1.1 412 ")
         and then Has (Collision, "<Code>PreconditionFailed</Code>"),
         "signed If-None-Match collision was not PreconditionFailed");
      Require
        (Has (Replaced, "200 OK") and then Has (Replaced, Second_ETag),
         "signed matching If-Match PutObject failed");
      Require
        (Has (Stale, "HTTP/1.1 412 ")
         and then Has (Missing, "HTTP/1.1 412 "),
         "signed stale or missing If-Match was accepted");
      Require
        (Has (Malformed, "400 Bad Request")
         and then Has (Empty, "400 Bad Request")
         and then Has (Duplicate_Match, "400 Bad Request")
         and then Has (Duplicate_None, "400 Bad Request"),
         "strict PutObject condition header validation failed");
      Require
        (Has (Combined, "200 OK")
         and then Has (Observed, "200 OK")
         and then Response_Body (Observed) = "third",
         "combined PutObject predicates did not publish exact final body");
      Require (Has (Cleanup, "204 No Content"),
               "conditional PutObject corpus cleanup failed");
   end;

   declare
      Payload : constant String := "complete put tuple";
      Last_Checksum : US.Unbounded_String;
   begin
      for Algorithm in Checksum_Policy.Algorithm loop
         declare
            Digest : constant String := Checksum_Value (Algorithm, Payload);
            Algorithm_Name : constant String :=
              Checksum_Policy.Wire_Name (Algorithm);
            Response : constant String := Run
              (Signed_Request
                 ("PUT", "/test-bucket/put-complete", Payload,
                  Extra_Headers =>
                    "Cache-Control: max-age=60" & CRLF &
                    "Content-Disposition: inline" & CRLF &
                    "Content-Encoding: identity" & CRLF &
                    "Content-Language: en-CA" & CRLF &
                    "Content-MD5: " & Content_MD5 (Payload) & CRLF &
                    "Content-Type: application/put" & CRLF &
                    "Expires: Fri, 24 May 2013 00:00:00 GMT" & CRLF &
                    "x-amz-sdk-checksum-algorithm: " & Algorithm_Name &
                    CRLF & Checksum_Header (Algorithm) & ": " & Digest &
                    CRLF & "x-amz-website-redirect-location: /put" & CRLF &
                    "x-amz-meta-team: storage" & CRLF &
                    "x-amz-storage-class: STANDARD" & CRLF &
                    "x-amz-tagging: stage=server&algorithm=" &
                    Algorithm_Name & CRLF &
                    "x-amz-expected-bucket-owner: test-principal" & CRLF),
               Receive_Max => 1);
            Info : Flyology.Object_Storage.Object_Information;
            Tags_Value : Flyology.Object_Storage.Object_Tag_Set;
            Status : Flyology.Object_Storage.Status;
         begin
            Require
              (Has (Response, "200 OK")
               and then Has
                 (Response, Checksum_Header (Algorithm) & ": " & Digest &
                    CRLF)
               and then Has
                 (Response, "x-amz-checksum-type: FULL_OBJECT" & CRLF)
               and then Has
                 (Response, "x-amz-object-size: 18" & CRLF)
               and then Response_Body (Response) = "",
               "complete PutObject checksum response " & Algorithm_Name &
                 ": " & Response);
            Store.Head_Object
              ("test-bucket", "put-complete", null,
               Ada.Real_Time.Time_Last, Info, Status);
            Store.Get_Object_Tags
              ("test-bucket", "put-complete", null,
               Ada.Real_Time.Time_Last, Tags_Value, Status);
            Require
              (Status = Flyology.Object_Storage.Success
               and then Info.Size = Payload'Length
               and then US.To_String (Info.Content_Type) = "application/put"
               and then Info.Metadata.Cache_Control.Is_Set
               and then US.To_String (Info.Metadata.Cache_Control.Value) =
                 "max-age=60"
               and then Info.Metadata.Content_Disposition.Is_Set
               and then US.To_String
                 (Info.Metadata.Content_Disposition.Value) = "inline"
               and then Info.Metadata.Content_Encoding.Is_Set
               and then US.To_String (Info.Metadata.Content_Encoding.Value) =
                 "identity"
               and then Info.Metadata.Content_Language.Is_Set
               and then US.To_String (Info.Metadata.Content_Language.Value) =
                 "en-CA"
               and then Info.Metadata.Expires.Is_Set
               and then Info.Metadata.Website_Redirect_Location.Is_Set
               and then US.To_String
                 (Info.Metadata.Website_Redirect_Location.Value) = "/put"
               and then Info.Metadata.User.Length = 1
               and then US.To_String (Info.Metadata.User.Items (1).Key) =
                 "team"
               and then US.To_String (Info.Metadata.User.Items (1).Value) =
                 "storage"
               and then Info.Checksum.Algorithm =
                 Storage_Algorithm (Algorithm)
               and then US.To_String (Info.Checksum.Value) = Digest
               and then Tags_Value.Length = 2
               and then US.To_String (Tags_Value.Items (1).Value) = "server"
               and then US.To_String (Tags_Value.Items (2).Value) =
                 Algorithm_Name,
               "complete PutObject tuple persistence " & Algorithm_Name);
            Last_Checksum := US.To_Unbounded_String (Digest);
         end;
      end loop;

      declare
         Expected_Entity_Tag : constant String :=
           """1ecc80380555e9370144fbf65a47c423""";
         Expected_ETag : constant String :=
           "ETag: " & Expected_Entity_Tag & CRLF;
         Head_Response : constant String := Run
           (Signed_Request
              ("HEAD", "/test-bucket/put-complete", "",
               Extra_Headers => "x-amz-checksum-mode: ENABLED" & CRLF));
         Get_Response : constant String := Run
           (Signed_Request
              ("GET", "/test-bucket/put-complete", "",
               Extra_Headers => "x-amz-checksum-mode: ENABLED" & CRLF));
         Failed_Response : constant String := Run
           (Signed_Request
              ("HEAD", "/test-bucket/put-complete", "",
               Extra_Headers => "If-Match: ""other""" & CRLF));
         Unsatisfied_Response : constant String := Run
           (Signed_Request
              ("HEAD", "/test-bucket/put-complete", "",
               Extra_Headers => "Range: bytes=99-100" & CRLF));
         Not_Modified_Response : constant String := Run
           (Signed_Request
              ("HEAD", "/test-bucket/put-complete", "",
               Extra_Headers =>
                 "If-None-Match: " & Expected_Entity_Tag & CRLF));

         function Has_Complete_Metadata (Response : String) return Boolean is
           (Has (Response, Expected_ETag)
            and then Has (Response, "Content-Type: application/put" & CRLF)
            and then Has (Response, "Cache-Control: max-age=60" & CRLF)
            and then Has (Response, "Content-Disposition: inline" & CRLF)
            and then Has (Response, "Content-Encoding: identity" & CRLF)
            and then Has (Response, "Content-Language: en-CA" & CRLF)
            and then Has
              (Response, "Expires: Fri, 24 May 2013 00:00:00 GMT" & CRLF)
            and then Has
              (Response,
               "x-amz-website-redirect-location: /put" & CRLF)
            and then Has
              (Response, "x-amz-meta-team: storage" & CRLF)
            and then Has
              (Response,
               "x-amz-checksum-xxhash128: " &
                 US.To_String (Last_Checksum) & CRLF)
            and then Has
              (Response, "x-amz-checksum-type: FULL_OBJECT" & CRLF)
            and then not Has (Response, "x-amz-tagging-count:"));

         function Has_Representation_Metadata
           (Response : String) return Boolean is
           (Has (Response, "Cache-Control:")
            or else Has (Response, "Content-Disposition:")
            or else Has (Response, "Content-Encoding:")
            or else Has (Response, "Content-Language:")
            or else Has (Response, "Expires:")
            or else Has (Response, "x-amz-website-redirect-location:")
            or else Has (Response, "x-amz-meta-"));
      begin
         Require
           (Has (Head_Response, "200 OK")
            and then Has_Complete_Metadata (Head_Response)
            and then Response_Body (Head_Response) = "",
            "HeadObject did not project the complete immutable Put tuple: " &
              Head_Response);
         Require
           (Has (Get_Response, "200 OK")
            and then Has_Complete_Metadata (Get_Response)
            and then Response_Body (Get_Response) = Payload,
            "GetObject did not project the complete immutable Put tuple: " &
              Get_Response);
         Require
           (Has (Failed_Response, "HTTP/1.1 412 ")
            and then not Has_Representation_Metadata (Failed_Response),
            "HeadObject 412 inherited stored representation metadata: " &
              Failed_Response);
         Require
           (Has (Unsatisfied_Response, "HTTP/1.1 416 ")
            and then not Has_Representation_Metadata
              (Unsatisfied_Response),
            "HeadObject 416 inherited stored representation metadata: " &
              Unsatisfied_Response);
         Require
           (Has (Not_Modified_Response, "HTTP/1.1 304 ")
            and then Has (Not_Modified_Response, Expected_ETag)
            and then not Has_Representation_Metadata
              (Not_Modified_Response),
            "HeadObject 304 projected more than validators: " &
              Not_Modified_Response);
      end;

      declare
         MD5_Rejected : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-complete", "mutated",
               Extra_Headers =>
                 "Content-MD5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF));
         Checksum_Rejected : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-complete", "mutated",
               Extra_Headers =>
                 "x-amz-sdk-checksum-algorithm: XXHASH128" & CRLF &
                 "x-amz-checksum-xxhash128: " &
                 US.To_String (Last_Checksum) & CRLF));
         Observed : constant String := Run
           (Signed_Request ("GET", "/test-bucket/put-complete", ""));
         Cleanup : constant String := Run
           (Signed_Request ("DELETE", "/test-bucket/put-complete", ""));
      begin
         Require
           (Has (MD5_Rejected, "<Code>BadDigest</Code>")
            and then Has (Checksum_Rejected, "<Code>BadDigest</Code>")
            and then Response_Body (Observed) = Payload
            and then Has (Cleanup, "204 No Content"),
            "PutObject integrity failure mutated the prior object");
      end;
   end;

   declare
      Wrong_Hash : constant String (1 .. 64) := (others => '0');
      Unsupported : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("x-amz-acl", "private"),
         SigV4.Pair ("x-amz-grant-full-control", "id=owner"),
         SigV4.Pair ("x-amz-grant-read", "id=reader"),
         SigV4.Pair ("x-amz-grant-read-acp", "id=reader"),
         SigV4.Pair ("x-amz-grant-write-acp", "id=writer"),
         SigV4.Pair ("x-amz-write-offset-bytes", "0"),
         SigV4.Pair ("x-amz-server-side-encryption", "AES256"),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-algorithm", "AES256"),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-key", "a2V5"),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-key-md5",
            "bWQ1bWQ1bWQ1bWQ1bWQ1bQ=="),
         SigV4.Pair
           ("x-amz-server-side-encryption-aws-kms-key-id", "key-id"),
         SigV4.Pair ("x-amz-server-side-encryption-context", "e30="),
         SigV4.Pair
           ("x-amz-server-side-encryption-bucket-key-enabled", "true"),
         SigV4.Pair ("x-amz-request-payer", "requester"),
         SigV4.Pair ("x-amz-object-lock-mode", "GOVERNANCE"),
         SigV4.Pair
           ("x-amz-object-lock-retain-until-date",
            "2013-05-24T00:00:00Z"),
         SigV4.Pair ("x-amz-object-lock-legal-hold", "ON"));
      Duplicated : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("x-amz-acl", "private"),
         SigV4.Pair ("cache-control", "no-cache"),
         SigV4.Pair ("content-disposition", "inline"),
         SigV4.Pair ("content-encoding", "identity"),
         SigV4.Pair ("content-language", "en"),
         SigV4.Pair ("content-md5", Content_MD5 ("mutating")),
         SigV4.Pair ("content-type", "application/test"),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", "CRC32"),
         SigV4.Pair ("x-amz-checksum-crc32", "Ur8Evw=="),
         SigV4.Pair ("x-amz-trailer", "x-amz-checksum-crc32"),
         SigV4.Pair ("expires", "Fri, 24 May 2013 00:00:00 GMT"),
         SigV4.Pair ("if-match", "*"),
         SigV4.Pair ("if-none-match", "*"),
         SigV4.Pair ("x-amz-grant-full-control", "id=owner"),
         SigV4.Pair ("x-amz-grant-read", "id=reader"),
         SigV4.Pair ("x-amz-grant-read-acp", "id=reader"),
         SigV4.Pair ("x-amz-grant-write-acp", "id=writer"),
         SigV4.Pair ("x-amz-write-offset-bytes", "0"),
         SigV4.Pair ("x-amz-server-side-encryption", "AES256"),
         SigV4.Pair ("x-amz-storage-class", "STANDARD"),
         SigV4.Pair ("x-amz-website-redirect-location", "/redirect"),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-algorithm", "AES256"),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-key", "a2V5"),
         SigV4.Pair
           ("x-amz-server-side-encryption-customer-key-md5",
            "bWQ1bWQ1bWQ1bWQ1bWQ1bQ=="),
         SigV4.Pair
           ("x-amz-server-side-encryption-aws-kms-key-id", "key-id"),
         SigV4.Pair ("x-amz-server-side-encryption-context", "e30="),
         SigV4.Pair
           ("x-amz-server-side-encryption-bucket-key-enabled", "true"),
         SigV4.Pair ("x-amz-request-payer", "requester"),
         SigV4.Pair ("x-amz-tagging", "stage=duplicate"),
         SigV4.Pair ("x-amz-object-lock-mode", "GOVERNANCE"),
         SigV4.Pair
           ("x-amz-object-lock-retain-until-date",
            "2013-05-24T00:00:00Z"),
         SigV4.Pair ("x-amz-object-lock-legal-hold", "ON"),
         SigV4.Pair ("x-amz-expected-bucket-owner", "test-principal"),
         SigV4.Pair ("x-amz-meta-team", "storage"));
      Created : constant String := Run
        (Signed_Request ("PUT", "/test-bucket/put-policy", "prior"));
      Tampered : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("X-AmZ-TaGgInG", "stage=injected"),
         SigV4.Pair ("x-amz-meta-team", "injected"),
         SigV4.Pair ("x-amz-sdk-checksum-algorithm", "CRC32"),
         SigV4.Pair ("x-amz-checksum-crc32", "Ur8Evw=="),
         SigV4.Pair ("x-amz-trailer", "x-amz-checksum-crc32"),
         SigV4.Pair
           ("x-amz-expected-bucket-owner", "test-principal"),
         SigV4.Pair ("x-amz-storage-class", "STANDARD"),
         SigV4.Pair ("x-amz-acl", "private"),
         SigV4.Pair ("x-amz-server-side-encryption", "AES256"),
         SigV4.Pair ("x-amz-object-lock-mode", "GOVERNANCE"));
   begin
      Require (Has (Created, "200 OK"), "PutObject policy setup failed");
      for Item of Tampered loop
         declare
            Name : constant String := US.To_String (Item.Name);
            Response : constant String := Run
              (Signed_Request_With_Unsigned_Amazon_Header
                 ("/test-bucket/put-policy", "mutating", Name,
                  US.To_String (Item.Value)));
         begin
            Require
              (Has (Response, "400 Bad Request")
               and then Has
                 (Response, "<Code>AuthorizationHeaderMalformed</Code>")
               and then not Has (Response, "100 Continue"),
               "unsigned Amazon control reached PutObject semantics: " &
                 Name & ": " & Response);
         end;
      end loop;
      for Item of Unsupported loop
         declare
            Name : constant String := US.To_String (Item.Name);
            Response : constant String := Run
              (Signed_Request
                 ("PUT", "/test-bucket/put-policy", "mutating",
                  Extra_Headers => Name & ": " & US.To_String (Item.Value) &
                    CRLF,
                  Hash_Override => Wrong_Hash));
         begin
            Require
              (Has (Response, "501 Not Implemented")
               and then Has (Response, "<Code>NotImplemented</Code>"),
               "PutObject did not reject unsupported " & Name &
                 " after authentication: " & Response);
         end;
      end loop;
      for Item of Duplicated loop
         declare
            Name : constant String := US.To_String (Item.Name);
            Header : constant String := Name & ": " &
              US.To_String (Item.Value) & CRLF;
            Response : constant String := Run
              (Signed_Request
                 ("PUT", "/test-bucket/put-policy", "mutating",
                  Extra_Headers => Header & Header,
                  Hash_Override => Wrong_Hash));
         begin
            Require
              (Has (Response, "400 Bad Request")
               and then Has (Response, "<Code>InvalidRequest</Code>"),
               "PutObject accepted duplicate physical " & Name & ": " &
                 Response);
         end;
      end loop;
      declare
         Owner_Mismatch : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers =>
                 "x-amz-expected-bucket-owner: another-owner" & CRLF,
               Hash_Override => Wrong_Hash));
         Nonstandard : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers => "x-amz-storage-class: STANDARD_IA" & CRLF,
               Hash_Override => Wrong_Hash));
         Invalid_Storage : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers => "x-amz-storage-class: INVALID" & CRLF,
               Hash_Override => Wrong_Hash));
         Invalid_ACL : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers => "x-amz-acl: invalid" & CRLF,
               Hash_Override => Wrong_Hash));
         Invalid_Payer : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers => "x-amz-request-payer: invalid" & CRLF,
               Hash_Override => Wrong_Hash));
         Invalid_SSE : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers =>
                 "x-amz-server-side-encryption: invalid" & CRLF,
               Hash_Override => Wrong_Hash));
         Invalid_Lock : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers => "x-amz-object-lock-mode: invalid" & CRLF,
               Hash_Override => Wrong_Hash));
         Invalid_Hold : constant String := Run
           (Signed_Request
              ("PUT", "/test-bucket/put-policy", "mutating",
               Extra_Headers =>
                 "x-amz-object-lock-legal-hold: invalid" & CRLF,
               Hash_Override => Wrong_Hash));
         Observed : constant String := Run
           (Signed_Request ("GET", "/test-bucket/put-policy", ""));
      begin
         Require
           (Has (Owner_Mismatch, "403 Forbidden"),
            "PutObject ignored expected owner mismatch");
         Require
           (Has (Nonstandard, "501 Not Implemented")
            and then Has (Invalid_Storage, "400 Bad Request")
            and then Has (Invalid_ACL, "400 Bad Request")
            and then Has (Invalid_Payer, "400 Bad Request")
            and then Has (Invalid_SSE, "400 Bad Request")
            and then Has (Invalid_Lock, "400 Bad Request")
            and then Has (Invalid_Hold, "400 Bad Request"),
            "PutObject modeled enumeration validation failed");
         Require
           (Response_Body (Observed) = "prior",
            "rejected PutObject policy member mutated prior body");
      end;
      declare
         Cleanup : constant String := Run
           (Signed_Request ("DELETE", "/test-bucket/put-policy", ""));
      begin
         Require
           (Has (Cleanup, "204 No Content"),
            "PutObject policy cleanup failed");
      end;
   end;

   declare
      function User_Headers (Count : Positive) return String is
         Result : US.Unbounded_String;
      begin
         for Index in 1 .. Count loop
            US.Append
              (Result, "x-amz-meta-k" &
                 Ada.Strings.Fixed.Trim
                   (Positive'Image (Index), Ada.Strings.Both) &
                 ": v" & CRLF);
         end loop;
         return US.To_String (Result);
      end User_Headers;

      function Repeated_Headers (Count : Positive) return String is
         Result : US.Unbounded_String;
      begin
         for Index in 1 .. Count loop
            US.Append (Result, "x-amz-meta-repeated: v" & CRLF);
         end loop;
         return US.To_String (Result);
      end Repeated_Headers;

      Wrong_Hash : constant String (1 .. 64) := (others => '0');
      Ten_Tags : constant String :=
        "k1=v&k2=v&k3=v&k4=v&k5=v&k6=v&k7=v&k8=v&k9=v&k10=v";
      Eleven_Tags : constant String := Ten_Tags & "&k11=v";
      Exact_Object_Limit : constant String := Run
        (Signed_Put_Declared_Length_Request
           ("/test-bucket/put-size-limit", "5368709120"));
      Over_Object_Limit : constant String := Run
        (Signed_Put_Declared_Length_Request
           ("/test-bucket/put-size-limit", "5368709121"));
      Size_Limit_Observed : constant String := Run
        (Signed_Request ("GET", "/test-bucket/put-size-limit", ""));
      Exact_System : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "system",
            Extra_Headers => "Content-Type: " &
              String'(1 .. 2_036 => 'x') & CRLF));
      System_Plus_One : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "Content-Type: " &
              String'(1 .. 2_037 => 'x') & CRLF,
            Hash_Override => Wrong_Hash));
      Exact_User : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "user",
            Extra_Headers => "x-amz-meta-k: " &
              String'(1 .. 2_047 => 'v') & CRLF));
      User_Plus_One : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "x-amz-meta-k: " &
              String'(1 .. 2_048 => 'v') & CRLF,
            Hash_Override => Wrong_Hash));
      Sixty_Four_User : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "entries",
            Extra_Headers => User_Headers (64)));
      Sixty_Five_User : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => User_Headers (65),
            Hash_Override => Wrong_Hash));
      Worst_Case_Payload : constant String := "supported header set";
      Worst_Case_Checksum : constant String :=
        Checksum_Value (Core.CRC32, Worst_Case_Payload);
      Worst_Case_Put : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-header-capacity", Worst_Case_Payload,
            Extra_Headers =>
              User_Headers (64) &
              "Cache-Control: max-age=1" & CRLF &
              "Content-Disposition: inline" & CRLF &
              "Content-Encoding: identity" & CRLF &
              "Content-Language: en" & CRLF &
              "Content-MD5: " & Content_MD5 (Worst_Case_Payload) & CRLF &
              "Content-Type: application/test" & CRLF &
              "Expires: Fri, 24 May 2013 00:00:00 GMT" & CRLF &
              "If-None-Match: *" & CRLF &
              "x-amz-checksum-crc32: " & Worst_Case_Checksum & CRLF &
              "x-amz-expected-bucket-owner: test-principal" & CRLF &
              "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
              "x-amz-storage-class: STANDARD" & CRLF &
              "x-amz-tagging: profile=maximum" & CRLF &
              "x-amz-website-redirect-location: /maximum" & CRLF));
      Exact_Unique_Auth_Bound : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-auth-bound", "bad",
            Extra_Headers => User_Headers (125),
            Hash_Override => Wrong_Hash,
            Expect => True));
      Over_Unique_Auth_Bound : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-auth-bound", "bad",
            Extra_Headers => User_Headers (126),
            Hash_Override => Wrong_Hash,
            Expect => True));
      Exact_Physical_Auth_Bound : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-auth-bound", "bad",
            Extra_Headers => Repeated_Headers (253),
            Hash_Override => Wrong_Hash,
            Expect => True));
      Over_Physical_Auth_Bound : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-auth-bound", "bad",
            Extra_Headers => Repeated_Headers (254),
            Hash_Override => Wrong_Hash,
            Expect => True));
      Auth_Bound_Observed : constant String := Run
        (Signed_Request ("GET", "/test-bucket/put-auth-bound", ""));
      Ten_Tag_Result : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "tags",
            Extra_Headers => "x-amz-tagging: " & Ten_Tags & CRLF));
      Eleven_Tag_Result : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "x-amz-tagging: " & Eleven_Tags & CRLF,
            Hash_Override => Wrong_Hash));
      Malformed_Tag : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "x-amz-tagging: key=%ZZ" & CRLF,
            Hash_Override => Wrong_Hash));
      Case_Collision : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "x-amz-meta-Team: one" & CRLF &
              "x-amz-meta-team: two" & CRLF,
            Hash_Override => Wrong_Hash));
      Invalid_Expires : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "Expires: not-a-date" & CRLF,
            Hash_Override => Wrong_Hash));
      Invalid_Encoding : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "Content-Encoding: gzip," & CRLF,
            Hash_Override => Wrong_Hash));
      SDK_Mismatch : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
              "x-amz-checksum-crc32: " & Checksum_Value (Core.CRC32, "bad") &
              CRLF,
            Hash_Override => Wrong_Hash));
      SDK_Missing_Value : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: CRC32" & CRLF,
            Hash_Override => Wrong_Hash));
      Invalid_MD5 : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers => "Content-MD5: not-base64" & CRLF,
            Hash_Override => Wrong_Hash));
      Encoding_Result : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "encoding",
            Extra_Headers => "Content-Encoding: gzip, br" & CRLF));
      Observed : constant String := Run
        (Signed_Request ("GET", "/test-bucket/put-budget", ""));
      Info : Flyology.Object_Storage.Object_Information;
      Capacity_Info : Flyology.Object_Storage.Object_Information;
      Capacity_Tags : Flyology.Object_Storage.Object_Tag_Set;
      Head_Status : Flyology.Object_Storage.Status;
      Capacity_Status : Flyology.Object_Storage.Status;
   begin
      Store.Head_Object
        ("test-bucket", "put-budget", null, Ada.Real_Time.Time_Last,
         Info, Head_Status);
      Require
        (Has (Exact_Object_Limit, "503 Service Unavailable")
         and then not Has
           (Exact_Object_Limit, "<Code>EntityTooLarge</Code>")
         and then Has
           (Over_Object_Limit, "<Code>EntityTooLarge</Code>")
         and then Has (Size_Limit_Observed, "404 Not Found"),
         "PutObject 5 GiB exact/+1 scalar boundary failed");
      Require
        (Has (Exact_System, "200 OK")
         and then Has (System_Plus_One, "400 Bad Request")
         and then Has (System_Plus_One, "<Code>InvalidArgument</Code>")
         and then Has (Exact_User, "200 OK")
         and then Has (User_Plus_One, "400 Bad Request")
         and then Has (User_Plus_One, "<Code>InvalidArgument</Code>")
         and then Has (Sixty_Four_User, "200 OK")
         and then Has (Sixty_Five_User, "400 Bad Request")
         and then Has (Sixty_Five_User, "<Code>InvalidArgument</Code>"),
         "PutObject metadata exact/+1 budgets failed");
      Store.Head_Object
        ("test-bucket", "put-header-capacity", null,
         Ada.Real_Time.Time_Last, Capacity_Info, Capacity_Status);
      Store.Get_Object_Tags
        ("test-bucket", "put-header-capacity", null,
         Ada.Real_Time.Time_Last, Capacity_Tags, Capacity_Status);
      Require
        (Has (Worst_Case_Put, "200 OK")
         and then Capacity_Status = Flyology.Object_Storage.Success
         and then Capacity_Info.Size = Worst_Case_Payload'Length
         and then Capacity_Info.Metadata.User.Length = 64
         and then Capacity_Info.Checksum.Algorithm =
           Flyology.Object_Storage.Checksum_CRC32
         and then US.To_String (Capacity_Info.Checksum.Value) =
           Worst_Case_Checksum
         and then Capacity_Tags.Length = 1
         and then US.To_String (Capacity_Tags.Items (1).Value) = "maximum",
         "supported worst-case PutObject header set did not persist exactly");
      Require
        (Has (Exact_Unique_Auth_Bound, "<Code>InvalidArgument</Code>")
         and then Has
           (Over_Unique_Auth_Bound,
            "<Code>AuthorizationHeaderMalformed</Code>")
         and then not Has (Over_Unique_Auth_Bound, "100 Continue")
         and then Has
           (Exact_Physical_Auth_Bound, "<Code>InvalidRequest</Code>")
         and then Has
           (Over_Physical_Auth_Bound,
            "<Code>AuthorizationHeaderMalformed</Code>")
         and then not Has (Over_Physical_Auth_Bound, "100 Continue")
         and then Has (Auth_Bound_Observed, "404 Not Found"),
         "SigV4 unique/physical signed-header bounds did not fail closed");
      Require
        (Has (Ten_Tag_Result, "200 OK")
         and then Has (Eleven_Tag_Result, "<Code>InvalidTag</Code>")
         and then Has (Malformed_Tag, "<Code>InvalidTag</Code>")
         and then Has (Case_Collision, "<Code>InvalidRequest</Code>")
         and then Has (Invalid_Expires, "<Code>InvalidArgument</Code>")
         and then Has (Invalid_Encoding, "<Code>InvalidArgument</Code>"),
         "PutObject tag or metadata syntax boundary failed");
      Require
        (Has (SDK_Mismatch, "<Code>InvalidRequest</Code>")
         and then Has (SDK_Missing_Value, "<Code>InvalidRequest</Code>")
         and then Has (Invalid_MD5, "<Code>InvalidDigest</Code>"),
         "PutObject checksum-group preflight failed");
      Require
        (Has (Encoding_Result, "200 OK")
         and then Response_Body (Observed) = "encoding"
         and then Head_Status = Flyology.Object_Storage.Success
         and then Info.Metadata.Content_Encoding.Is_Set
         and then US.To_String (Info.Metadata.Content_Encoding.Value) =
           "gzip, br",
         "PutObject did not preserve ordinary content encoding exactly");
      declare
         Cleanup : constant String := Run
           (Signed_Request ("DELETE", "/test-bucket/put-budget", ""));
         Capacity_Cleanup : constant String := Run
           (Signed_Request
              ("DELETE", "/test-bucket/put-header-capacity", ""));
      begin
         Require
           (Has (Cleanup, "204 No Content")
            and then Has (Capacity_Cleanup, "204 No Content"),
            "PutObject budget cleanup failed");
      end;
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("location", ""),
         SigV4.Pair ("x-id", "GetBucketLocation"));
      Response : constant String :=
        Run (Signed_Query_Request ("GET", "/test-bucket", Query));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "Content-Type: application/xml")
         and then Buckets.Parse_Location_Constraint
           (Response_Body (Response)) = "",
         "GetBucketLocation did not return null us-east-1 constraint");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Query,
                  "x-amz-expected-bucket-owner", "test-principal")),
            "200 OK"),
         "GetBucketLocation rejected the authenticated owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketLocation ignored the expected owner precondition");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket",
                  (1 => SigV4.Pair ("location", "")))),
            "404 Not Found"),
         "GetBucketLocation did not check bucket existence");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Query, "unexpected")),
            "400 Bad Request"),
         "GetBucketLocation accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("location", ""),
                   SigV4.Pair ("location", "")))),
            "400 Bad Request"),
         "GetBucketLocation accepted a duplicate subresource");
   end;

   declare
      Put_ABAC_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("abac", ""),
         SigV4.Pair ("x-id", "PutBucketAbac"));
      Get_ABAC_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("abac", ""),
         SigV4.Pair ("x-id", "GetBucketAbac"));
      Put_Acceleration_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("accelerate", ""),
         SigV4.Pair ("x-id", "PutBucketAccelerateConfiguration"));
      Get_Acceleration_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("accelerate", ""),
         SigV4.Pair ("x-id", "GetBucketAccelerateConfiguration"));
      Put_Payment_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("requestPayment", ""),
         SigV4.Pair ("x-id", "PutBucketRequestPayment"));
      Get_Payment_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("requestPayment", ""),
         SigV4.Pair ("x-id", "GetBucketRequestPayment"));
      Enabled_ABAC : constant String :=
        Bucket_Controls.Serialize_Abac (Bucket_Controls.Abac_Enabled);
      Empty_ABAC : constant String :=
        Bucket_Controls.Serialize_Abac
          (Bucket_Controls.Abac_Status_Absent);
      Suspended_Acceleration : constant String :=
        Bucket_Controls.Serialize_Accelerate
          (Bucket_Controls.Accelerate_Suspended);
      Requester_Payment : constant String :=
        Bucket_Controls.Serialize_Request_Payment
          (Bucket_Controls.Requester);
   begin
      Require
        (Bucket_Controls.Parse_Abac
           (Response_Body
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket", Get_ABAC_Query)))) =
           Bucket_Controls.Abac_Disabled,
         "GetBucketAbac did not expose the disabled bucket default");
      Require
        (Bucket_Controls.Parse_Accelerate
           (Response_Body
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket", Get_Acceleration_Query)))) =
           Bucket_Controls.Accelerate_Status_Absent,
         "GetBucketAccelerateConfiguration invented initial state");
      Require
        (Bucket_Controls.Parse_Request_Payment
           (Response_Body
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket", Get_Payment_Query)))) =
           Bucket_Controls.Bucket_Owner,
         "GetBucketRequestPayment did not expose bucket-owner payment");

      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_ABAC_Query, Enabled_ABAC,
                  "Content-MD5: " & Content_MD5 (Enabled_ABAC) & CRLF)),
            "200 OK"),
         "PutBucketAbac rejected an enabled configuration");
      Require
        (Bucket_Controls.Parse_Abac
           (Response_Body
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket", Get_ABAC_Query)))) =
           Bucket_Controls.Abac_Enabled,
         "GetBucketAbac did not return the replaced state");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_ABAC_Query, Empty_ABAC)),
            "200 OK")
         and then
           Bucket_Controls.Parse_Abac
             (Response_Body
                (Run
                   (Signed_Query_Request
                      ("GET", "/test-bucket", Get_ABAC_Query)))) =
             Bucket_Controls.Abac_Status_Absent,
         "PutBucketAbac did not preserve an omitted Status");

      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Payment_Query,
                  Requester_Payment)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketRequestPayment accepted a missing checksum");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Acceleration_Query,
                  Suspended_Acceleration,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Suspended_Acceleration) &
                  CRLF)),
            "200 OK"),
         "PutBucketAccelerateConfiguration rejected a valid checksum");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Get_Acceleration_Query,
                 "x-amz-request-payer", "requester"));
      begin
         Require
           (Has (Response, "200 OK")
            and then not Has (Response, "x-amz-request-charged:")
            and then Bucket_Controls.Parse_Accelerate
              (Response_Body (Response)) =
                Bucket_Controls.Accelerate_Suspended,
            "owner-pays acceleration GET reported a requester charge");
      end;

      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Payment_Query,
                  Requester_Payment,
                  "Content-MD5: " & Content_MD5 (Requester_Payment) &
                  CRLF)),
            "200 OK"),
         "PutBucketRequestPayment rejected requester payment");
      Require
        (Bucket_Controls.Parse_Request_Payment
           (Response_Body
              (Run
                 (Signed_Query_Request
                    ("GET", "/test-bucket", Get_Payment_Query)))) =
           Bucket_Controls.Requester,
         "GetBucketRequestPayment did not return requester payment");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Get_Acceleration_Query,
                 "x-amz-request-payer", "requester"));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "x-amz-request-charged: requester")
            and then Bucket_Controls.Parse_Accelerate
              (Response_Body (Response)) =
                Bucket_Controls.Accelerate_Suspended,
            "requester-pays acceleration GET omitted its charge marker");
      end;

      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Acceleration_Query,
                  Suspended_Acceleration,
                  "Content-MD5: " & Content_MD5 (Suspended_Acceleration) &
                  CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAccelerateConfiguration accepted Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_ABAC_Query, Enabled_ABAC,
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Empty_ABAC) & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketAbac accepted a mismatched checksum");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Payment_Query,
                  "<RequestPaymentConfiguration/>",
                  "Content-MD5: " &
                  Content_MD5 ("<RequestPaymentConfiguration/>") &
                  CRLF)),
            "<Code>MalformedXML</Code>"),
         "PutBucketRequestPayment accepted a missing Payer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_ABAC_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketAbac ignored the expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Acceleration_Query,
                  "x-amz-request-payer", "owner")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketAccelerateConfiguration accepted an invalid payer");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Get_Payment_Query,
                  "unexpected")),
            "400 Bad Request"),
         "GetBucketRequestPayment accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (1 => SigV4.Pair ("x-id", "GetBucketAbac")))),
            "400 Bad Request"),
         "GetBucketAbac accepted x-id without its subresource");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("accelerate", ""),
                   SigV4.Pair ("requestPayment", "")))),
            "400 Bad Request"),
         "bucket scalar controls accepted mixed subresources");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Get_Payment_Query)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketRequestPayment did not check bucket existence");
   end;

   declare
      Replication_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("replication", ""),
         SigV4.Pair ("x-id", "PutBucketReplication"));
      Replication_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("replication", ""),
         SigV4.Pair ("x-id", "GetBucketReplication"));
      Replication_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("replication", ""),
         SigV4.Pair ("x-id", "DeleteBucketReplication"));
      Website_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("website", ""),
         SigV4.Pair ("x-id", "PutBucketWebsite"));
      Website_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("website", ""),
         SigV4.Pair ("x-id", "GetBucketWebsite"));
      Website_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("website", ""),
         SigV4.Pair ("x-id", "DeleteBucketWebsite"));
      Replication_Document : constant String :=
        "<ReplicationConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Role>role</Role><Rule><Status>Enabled" &
        "</Status><Destination><Bucket>arn:aws:s3:::replica</Bucket>" &
        "</Destination></Rule></ReplicationConfiguration>";
      Replacement_Replication : constant String :=
        "<ReplicationConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Role>replacement</Role><Rule><Status>Disabled" &
        "</Status><Destination><Bucket>arn:aws:s3:::second</Bucket>" &
        "</Destination></Rule></ReplicationConfiguration>";
      Website_Document : constant String :=
        "<WebsiteConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><IndexDocument><Suffix>index.html</Suffix>" &
        "</IndexDocument></WebsiteConfiguration>";
      Replacement_Website : constant String :=
        "<WebsiteConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><ErrorDocument><Key>error.html</Key>" &
        "</ErrorDocument></WebsiteConfiguration>";
      Canonical_Replication : constant String :=
        Replication.Serialize
          (Replication.Parse (Replication_Document, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Replacement_Replication : constant String :=
        Replication.Serialize
          (Replication.Parse
             (Replacement_Replication, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Website : constant String :=
        Generated_Website.Serialize
          (Website.Parse (Website_Document, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Replacement_Website : constant String :=
        Generated_Website.Serialize
          (Website.Parse (Replacement_Website, XML.Default_Limits),
           XML.Default_Limits);

      function Put
        (Query : SigV4.Name_Value_Array;
         Document : String;
         Extra : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Query, Document,
               "content-md5: " & Content_MD5 (Document) & CRLF &
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Document) & CRLF & Extra)));

      function Declared_Oversize
        (Query : SigV4.Name_Value_Array;
         Document : String) return String
      is
         Payload_Hash : constant String := SigV4.Empty_Payload_Hash;
         Headers : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("content-md5", Content_MD5 (Document)),
            SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-checksum-sha256",
                        Checksum_Value (Core.SHA256, Document)),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair ("x-amz-sdk-checksum-algorithm", "SHA256"));
         Signing : constant SigV4.Signing_Result :=
           SigV4.Sign
             ("PUT", "/test-bucket", Query, Headers, Payload_Hash,
              Access_Key, Secret_Key, Region, Timestamp);
         Query_Text : constant String := SigV4.Canonical_Query (Query);
      begin
         return
           "PUT /test-bucket?" & Query_Text & " HTTP/1.1" & CRLF &
           "Host: " & Host & CRLF &
           "content-md5: " & Content_MD5 (Document) & CRLF &
           "x-amz-checksum-sha256: " &
           Checksum_Value (Core.SHA256, Document) & CRLF &
           "x-amz-content-sha256: " & Payload_Hash & CRLF &
           "x-amz-date: " & Timestamp & CRLF &
           "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
           "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
           "Content-Length: " &
           Ada.Strings.Fixed.Trim
             (Natural'Image
                (XML.Default_Limits.Maximum_Document_Bytes + 1),
              Ada.Strings.Both) & CRLF &
           "Connection: close" & CRLF & CRLF;
      end Declared_Oversize;
   begin
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Replication_Get)),
            "<Code>ReplicationConfigurationNotFoundError</Code>"),
         "GetBucketReplication did not distinguish absent configuration");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Website_Get)),
            "<Code>NoSuchWebsiteConfiguration</Code>"),
         "GetBucketWebsite did not distinguish absent configuration");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Replication_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketReplication confused bucket absence");
      Require
        (Has
           (Put
              (Replication_Put, Replication_Document,
               "x-amz-bucket-object-lock-token: token" & CRLF),
            "200 OK"),
         "PutBucketReplication rejected valid canonical input");
      Require
        (Has (Put (Website_Put, Website_Document), "200 OK"),
         "PutBucketWebsite rejected valid canonical input");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Replication_Get))) =
           Canonical_Replication,
         "GetBucketReplication lost canonical state");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Website_Get))) =
           Canonical_Website,
         "GetBucketWebsite lost canonical state");
      Require
        (Has
           (Put
              (Replication_Put, Replacement_Replication,
               "x-amz-bucket-object-lock-token: replacement" & CRLF),
            "200 OK")
         and then
           Response_Body
             (Run
                (Signed_Query_Request
                   ("GET", "/test-bucket", Replication_Get))) =
             Canonical_Replacement_Replication,
         "PutBucketReplication did not replace canonical state");
      Require
        (Has (Put (Website_Put, Replacement_Website), "200 OK")
         and then
           Response_Body
             (Run
                (Signed_Query_Request
                   ("GET", "/test-bucket", Website_Get))) =
             Canonical_Replacement_Website,
         "PutBucketWebsite did not replace canonical state");
      Require
        (Has
           (Put
              (Replication_Put, "<ReplicationConfiguration/>",
               "x-amz-bucket-object-lock-token: token" & CRLF),
            "<Code>MalformedXML</Code>"),
         "PutBucketReplication accepted malformed XML");
      Require
        (Has
           (Put
              (Website_Put,
               "<WebsiteConfiguration><IndexDocument/>" &
               "</WebsiteConfiguration>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketWebsite accepted malformed XML");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Replication_Put,
                  Replication_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Replication_Document) &
                  CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketReplication accepted missing Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Website_Put, Website_Document,
                  "content-md5: " & Content_MD5 (Website_Document) &
                  CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketWebsite accepted missing checksum selection");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Website_Put, Website_Document,
                  "content-md5: " & Content_MD5 (Website_Document) &
                  CRLF &
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, "different") & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketWebsite accepted a mismatched checksum");
      Require
        (Has
           (Put
              (Website_Put, Website_Document,
               "x-amz-bucket-object-lock-token: token" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketWebsite accepted replication object-lock token");
      Require
        (Has
           (Put
              (Replication_Put, Replication_Document,
               "x-amz-bucket-object-lock-token: one" & CRLF &
               "x-amz-bucket-object-lock-token: two" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketReplication accepted duplicate object-lock token");
      Require
        (Has
           (Put
              (Replication_Put, Replication_Document,
               "x-amz-expected-bucket-owner: different-owner" & CRLF &
               "x-amz-bucket-object-lock-token: token" & CRLF),
            "403 Forbidden"),
         "PutBucketReplication ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Website_Get,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketWebsite ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("replication", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketReplication accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("website", ""),
                   SigV4.Pair ("x-id", "GetBucketReplication")))),
            "400 Bad Request"),
         "GetBucketWebsite accepted a cross-family x-id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("replication", ""),
                   SigV4.Pair ("x-id", "")))),
            "400 Bad Request"),
         "GetBucketReplication accepted an empty x-id");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket",
                  (SigV4.Pair ("website", ""),
                   SigV4.Pair ("unexpected", "1")),
                  "<bad/>", Corrupt_Signature => True)),
            "403 Forbidden"),
         "website query validation ran before authentication");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Replication_Put, "<bad/>",
                  Corrupt_Signature => True)),
            "403 Forbidden"),
         "replication body validation ran before authentication");
      Require
        (Has
           (Run (Declared_Oversize (Replication_Put, Replication_Document)),
            "<Code>EntityTooLarge</Code>"),
         "PutBucketReplication accepted an oversized document");
      Require
        (Has
           (Run (Declared_Oversize (Website_Put, Website_Document)),
            "<Code>EntityTooLarge</Code>"),
         "PutBucketWebsite accepted an oversized document");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Replication_Get, "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketReplication accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("DELETE", "/test-bucket", Website_Delete,
                  "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "DeleteBucketWebsite accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Replication_Delete)),
            "204 No Content")
         and then Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Replication_Get)),
            "<Code>ReplicationConfigurationNotFoundError</Code>")
         and then Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Replication_Delete)),
            "204 No Content"),
         "DeleteBucketReplication lost delete or idempotency behavior");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Website_Delete)),
            "204 No Content")
         and then Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Website_Get)),
            "<Code>NoSuchWebsiteConfiguration</Code>")
         and then Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Website_Delete)),
            "204 No Content"),
         "DeleteBucketWebsite lost delete or idempotency behavior");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Website_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketWebsite confused bucket absence");
   end;

   declare
      Put_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("x-id", "PutBucketTagging"));
      Get_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("x-id", "GetBucketTagging"));
      Delete_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("x-id", "DeleteBucketTagging"));
      Value : Tags.Tag_Set;
   begin
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("PUT", "/test-bucket",
                  (1 => SigV4.Pair ("x-id", "PutBucketTagging")))),
            "400 Bad Request"),
         "PutBucketTagging accepted x-id without tagging subresource");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (1 => SigV4.Pair ("x-id", "GetBucketTagging")))),
            "400 Bad Request"),
         "GetBucketTagging accepted x-id without tagging subresource");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket",
                  (1 => SigV4.Pair ("x-id", "DeleteBucketTagging")))),
            "400 Bad Request"),
         "DeleteBucketTagging accepted x-id without tagging subresource");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query)),
            "<Code>NoSuchTagSet</Code>"),
         "GetBucketTagging did not distinguish an absent tag set");

      Value.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("project"),
            Value => US.To_Unbounded_String ("flyology")));
      Value.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("environment"),
            Value => US.To_Unbounded_String ("test")));
      declare
         Document : constant String := Tagging.Serialize_Bucket (Value);
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Put_Query, Document,
               "Content-MD5: " & Content_MD5 (Document) & CRLF),
            Receive_Max => 1);
         Get_Response : constant String := Run
           (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
         Observed : constant Tags.Tag_Set :=
           Tagging.Parse_Bucket (Response_Body (Get_Response));
      begin
         Require
           (Has (Response, "200 OK") and then Response_Body (Response) = "",
            "PutBucketTagging success mismatch: " & Response);
         Require
           (Has (Get_Response, "200 OK") and then Observed = Value,
            "GetBucketTagging snapshot mismatch: " & Get_Response);
      end;

      Value.Clear;
      Value.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("replacement"),
            Value => US.Null_Unbounded_String));
      declare
         Document : constant String := Tagging.Serialize_Bucket (Value);
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket",
               (1 => SigV4.Pair ("tagging", "")), Document,
               "Content-MD5: " & Content_MD5 (Document) & CRLF));
         Get_Response : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket",
               (1 => SigV4.Pair ("tagging", ""))));
      begin
         Require
           (Has (Response, "200 OK")
            and then Tagging.Parse_Bucket (Response_Body (Get_Response)) =
              Value,
            "PutBucketTagging did not replace the complete set");
      end;

      declare
         Document : constant String := Tagging.Serialize_Bucket (Value);
      begin
         for Algorithm in Checksum_Policy.Algorithm loop
            declare
               Response : constant String := Run
                 (Signed_Bucket_Tagging_Checksum_Request
                    (Document, Algorithm,
                     Checksum_Value (Algorithm, Document)));
            begin
               Require
                 (Has (Response, "200 OK")
                  and then Response_Body (Response) = "",
                  "PutBucketTagging rejected " &
                    Checksum_Policy.Wire_Name (Algorithm) & ": " & Response);
            end;
         end loop;
         Require
           (Has
              (Run
                 (Signed_Bucket_Tagging_Trailer_Request
                    (Document, Core.SHA256,
                     Checksum_Value (Core.SHA256, Document))),
               "200 OK"),
            "PutBucketTagging rejected a physical checksum trailer");
         Require
           (Has
              (Run
                 (Signed_Bucket_Tagging_Trailer_Request
                    (Document, Core.SHA256,
                     Checksum_Value (Core.SHA256, Document),
                     Include_Trailer => False)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted a missing declared trailer");
         Require
           (Has
              (Run
                 (Signed_Bucket_Tagging_Trailer_Request
                    (Document, Core.SHA256,
                     Checksum_Value (Core.SHA256, Document),
                     Duplicate => True)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted duplicate physical trailers");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted a missing Content-MD5");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
               "<Code>BadDigest</Code>"),
            "PutBucketTagging accepted a mismatched Content-MD5");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF &
                     "Content-MD5: " & Content_MD5 (Document) & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted duplicate Content-MD5 fields");
         Require
           (Has
              (Run
                 (Signed_Bucket_Tagging_Checksum_Request
                    (Document, Core.SHA256,
                     "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
               "<Code>BadDigest</Code>"),
            "PutBucketTagging accepted a mismatched optional checksum");
         Require
           (Has
              (Run
                 (Signed_Bucket_Tagging_Checksum_Request
                    (Document, Core.SHA256, "not-base64")),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted noncanonical checksum Base64");
         Require
           (Has
              (Run
                 (Signed_Bucket_Tagging_Checksum_Request
                    (Document, Core.SHA256,
                     Checksum_Value (Core.SHA256, Document), "SHA1")),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted an algorithm/header mismatch");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF &
                     "x-amz-sdk-checksum-algorithm: SHA256" & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted an SDK algorithm without a checksum");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF &
                     "x-amz-checksum-sha256: " &
                     Checksum_Value (Core.SHA256, Document) & CRLF &
                     "x-amz-checksum-sha256: " &
                     Checksum_Value (Core.SHA256, Document) & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted a duplicate checksum field");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF &
                     "x-amz-checksum-sha1: " &
                     Checksum_Value (Core.SHA1, Document) & CRLF &
                     "x-amz-checksum-sha256: " &
                     Checksum_Value (Core.SHA256, Document) & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted multiple checksum algorithms");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF &
                     "x-amz-request-payer: requester" & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "PutBucketTagging accepted non-modeled RequestPayer");
      end;

      declare
         Document : constant String :=
           "<Tagging><TagSet><Tag><Key>missing-value</Key></Tag>" &
           "</TagSet></Tagging>";
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF)),
               "<Code>MalformedXML</Code>"),
            "PutBucketTagging accepted malformed XML");
      end;
      declare
         Document : constant String :=
           "<Tagging xmlns=""urn:not-s3""><TagSet><Tag>" &
           "<Key>project</Key><Value>flyology</Value></Tag>" &
           "</TagSet></Tagging>";
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF)),
               "<Code>MalformedXML</Code>"),
            "PutBucketTagging accepted the wrong XML namespace");
      end;
      declare
         Document : constant String :=
           "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<TagSet><Tag><Key>aws:reserved</Key>" &
           "<Value>x</Value></Tag></TagSet></Tagging>";
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/test-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF)),
               "<Code>InvalidTag</Code>"),
            "PutBucketTagging accepted an invalid tag");
      end;
      declare
         Document : constant String := Tagging.Serialize_Bucket (Value);
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", "/absent-bucket", Put_Query, Document,
                     "Content-MD5: " & Content_MD5 (Document) & CRLF)),
               "<Code>NoSuchBucket</Code>"),
            "PutBucketTagging did not check bucket existence");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketTagging ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query,
                  "x-amz-request-payer", "requester")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketTagging accepted non-modeled RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Get_Query, "unexpected")),
            "400 Bad Request"),
         "GetBucketTagging accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket",
                  (SigV4.Pair ("tagging", ""),
                   SigV4.Pair ("unexpected", "x")), "",
                  "Content-MD5: 1B2M2Y8AsgTpgAmY7PhCfg==" & CRLF)),
            "400 Bad Request"),
         "PutBucketTagging accepted an extra query parameter");

      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "DeleteBucketTagging ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query,
                  "x-amz-request-payer", "requester")),
            "<Code>InvalidRequest</Code>"),
         "DeleteBucketTagging accepted non-modeled RequestPayer");
      declare
         Snapshot : constant String := Run
           (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
      begin
         Require
           (Has (Snapshot, "200 OK")
            and then Tagging.Parse_Bucket (Response_Body (Snapshot)) = Value,
            "invalid bucket-tagging requests mutated the stored tag set");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket",
                  (SigV4.Pair ("tagging", ""),
                   SigV4.Pair ("unexpected", "x")))),
            "400 Bad Request"),
         "DeleteBucketTagging accepted an extra query parameter");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("DELETE", "/test-bucket", Delete_Query, "unexpected")),
            "400 Bad Request"),
         "DeleteBucketTagging accepted a request body");
      declare
         Response : constant String := Run
           (Signed_Query_Request
              ("DELETE", "/test-bucket", Delete_Query));
      begin
         Require
           (Has (Response, "204 No Content")
            and then Response_Body (Response) = "",
            "DeleteBucketTagging success mismatch: " & Response);
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query)),
            "<Code>NoSuchTagSet</Code>"),
         "DeleteBucketTagging left a visible tag set");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeleteBucketTagging was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Delete_Query)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketTagging did not distinguish an absent bucket");
   end;

   declare
      Put_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("publicAccessBlock", ""),
         SigV4.Pair ("x-id", "PutPublicAccessBlock"));
      Get_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("publicAccessBlock", ""),
         SigV4.Pair ("x-id", "GetPublicAccessBlock"));
      Delete_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("publicAccessBlock", ""),
         SigV4.Pair ("x-id", "DeletePublicAccessBlock"));
      Empty_Document : constant String :=
        "<PublicAccessBlockConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/""/>";
      Full_Document : constant String :=
        "<PublicAccessBlockConfiguration>" &
        "<BlockPublicAcls>true</BlockPublicAcls>" &
        "<IgnorePublicAcls>false</IgnorePublicAcls>" &
        "<RestrictPublicBuckets>true</RestrictPublicBuckets>" &
        "</PublicAccessBlockConfiguration>";
   begin
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query)),
            "<Code>NoSuchPublicAccessBlockConfiguration</Code>"),
         "GetPublicAccessBlock did not distinguish absent configuration");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket", Put_Query, Empty_Document));
      begin
         Require
           (Has (Response, "200 OK"),
            "PutPublicAccessBlock rejected a present empty configuration: " &
            Response);
      end;
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "<PublicAccessBlockConfiguration")
            and then not Has (Response, "BlockPublicAcls"),
            "GetPublicAccessBlock lost the present empty configuration");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Query, Full_Document)),
            "200 OK"),
         "PutPublicAccessBlock rejected a valid configuration");
      for Algorithm in Checksum_Policy.Algorithm loop
         declare
            Digest : constant String :=
              Checksum_Value (Algorithm, Full_Document);
            Response : constant String :=
              Run
                (Signed_Query_Body_Request
                   ("PUT", "/test-bucket", Put_Query, Full_Document,
                    "x-amz-sdk-checksum-algorithm: " &
                    Checksum_Policy.Wire_Name (Algorithm) & CRLF &
                    Checksum_Header (Algorithm) & ": " & Digest & CRLF));
         begin
            Require
              (Has (Response, "200 OK"),
               "PutPublicAccessBlock rejected checksum " &
               Checksum_Policy.Wire_Name (Algorithm) & ": " & Response);
         end;
      end loop;
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket", Put_Query, Full_Document,
                 "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
                 "x-amz-checksum-crc32: " &
                 Checksum_Value (Core.CRC32, Empty_Document) & CRLF));
      begin
         Require
           (Has (Response, "<Code>BadDigest</Code>"),
            "PutPublicAccessBlock accepted a checksum mismatch: " &
            Response);
      end;
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
      begin
         Require
           (Has (Response, "<BlockPublicAcls>true</BlockPublicAcls>")
            and then Has
              (Response, "<IgnorePublicAcls>false</IgnorePublicAcls>")
            and then Has
              (Response,
               "<RestrictPublicBuckets>true</RestrictPublicBuckets>")
            and then not Has (Response, "BlockPublicPolicy"),
            "GetPublicAccessBlock did not preserve member presence");
      end;
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket", Put_Query,
                 "<PublicAccessBlockConfiguration>" &
                 "<BlockPublicAcls>yes</BlockPublicAcls>" &
                 "</PublicAccessBlockConfiguration>"));
      begin
         Require
           (Has (Response, "<Code>MalformedXML</Code>"),
            "PutPublicAccessBlock accepted an invalid Boolean: " & Response);
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Query, Full_Document,
                  "content-md5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutPublicAccessBlock accepted a mismatched Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetPublicAccessBlock ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("publicAccessBlock", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetPublicAccessBlock accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Get_Query, "unexpected")),
            "400 Bad Request"),
         "GetPublicAccessBlock accepted a request body");
      Require
        (Has
           (Run (Signed_Query_Request
              ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeletePublicAccessBlock failed");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query)),
            "NoSuchPublicAccessBlockConfiguration"),
         "DeletePublicAccessBlock left visible state");
      Require
        (Has
           (Run (Signed_Query_Request
              ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeletePublicAccessBlock was not idempotent");
      Require
        (Has
           (Run (Signed_Query_Request
              ("DELETE", "/absent-bucket", Delete_Query)),
            "<Code>NoSuchBucket</Code>"),
         "DeletePublicAccessBlock did not distinguish an absent bucket");
   end;

   declare
      Put_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("cors", ""),
         SigV4.Pair ("x-id", "PutBucketCors"));
      Get_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("cors", ""),
         SigV4.Pair ("x-id", "GetBucketCors"));
      Delete_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("cors", ""),
         SigV4.Pair ("x-id", "DeleteBucketCors"));
      Document : constant String :=
        "<CORSConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><CORSRule><ID>browser</ID>" &
        "<AllowedMethod>GET</AllowedMethod><AllowedOrigin>*</AllowedOrigin>" &
        "<ExposeHeader>ETag</ExposeHeader><MaxAgeSeconds>60</MaxAgeSeconds>" &
        "</CORSRule></CORSConfiguration>";
      Canonical : constant String :=
        Bucket_Controls.Serialize_CORS
          (Bucket_Controls.Parse_CORS (Document));
   begin
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query)),
            "<Code>NoSuchCORSConfiguration</Code>"),
         "GetBucketCors did not distinguish absent configuration");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket", Put_Query, Document));
      begin
         Require
           (Has (Response, "200 OK"),
            "PutBucketCors rejected a valid configuration: " &
            Response_Body (Response));
      end;
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Type: application/xml")
            and then Response_Body (Response) = Canonical,
            "GetBucketCors did not return the canonical configuration");
      end;
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket", Put_Query, Document,
                 "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                 "x-amz-checksum-sha256: " &
                 Checksum_Value (Core.SHA256, Document) & CRLF));
      begin
         Require
           (Has (Response, "200 OK"),
            "PutBucketCors rejected a valid SDK checksum: " & Response);
      end;
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket", Put_Query,
                 "<CORSConfiguration><CORSRule>" &
                 "<AllowedOrigin>*</AllowedOrigin>" &
                 "</CORSRule></CORSConfiguration>"));
      begin
         Require
           (Has (Response, "<Code>MalformedXML</Code>"),
            "PutBucketCors accepted a rule without AllowedMethod: " &
            Response_Body (Response));
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Query, Document,
                  "content-md5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketCors accepted a mismatched Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketCors ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("cors", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketCors accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeleteBucketCors failed");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query)),
            "NoSuchCORSConfiguration"),
         "DeleteBucketCors left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeleteBucketCors was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Delete_Query)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketCors did not distinguish an absent bucket");
   end;

   declare
      Namespace : constant String :=
        "http://s3.amazonaws.com/doc/2006-03-01/";
      Current_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("notification", ""),
         SigV4.Pair ("x-id", "PutBucketNotificationConfiguration"));
      Legacy_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("notification", ""),
         SigV4.Pair ("x-id", "PutBucketNotification"));
      Current_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("notification", ""),
         SigV4.Pair ("x-id", "GetBucketNotificationConfiguration"));
      Legacy_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("notification", ""),
         SigV4.Pair ("x-id", "GetBucketNotification"));
      Empty_Document : constant String :=
        "<NotificationConfiguration xmlns=""" & Namespace &
        """></NotificationConfiguration>";
      Topic_Document : constant String :=
        "<NotificationConfiguration xmlns=""" & Namespace & """>" &
        "<TopicConfiguration><Topic>arn:aws:sns:us-east-1:" &
        "123456789012:topic</Topic><Event>s3:ObjectCreated:*</Event>" &
        "</TopicConfiguration></NotificationConfiguration>";
      Legacy_Only_Document : constant String :=
        "<NotificationConfiguration xmlns=""" & Namespace & """>" &
        "<CloudFunctionConfiguration><InvocationRole>legacy-role" &
        "</InvocationRole><Event>s3:ObjectCreated:Put</Event>" &
        "</CloudFunctionConfiguration></NotificationConfiguration>";
      Canonical_Empty : constant String :=
        Notifications.Serialize
          (Notifications.Parse (Empty_Document, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Topic : constant String :=
        Notifications.Serialize
          (Notifications.Parse (Topic_Document, XML.Default_Limits),
           XML.Default_Limits);

      function Put_Current
        (Document : String; Extra : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Current_Put, Document, Extra)));

      function Put_Legacy
        (Document : String; Extra : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Legacy_Put, Document,
               "content-md5: " & Content_MD5 (Document) & CRLF & Extra)));
   begin
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Current_Get))) = Canonical_Empty,
         "GetBucketNotificationConfiguration did not return empty state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Legacy_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketNotification confused bucket absence with empty state");
      Require
        (Has (Put_Current (Topic_Document), "<Code>NotImplemented</Code>"),
         "current notification PUT skipped destination validation");
      Require
        (Has
           (Put_Current
              (Topic_Document,
               "x-amz-skip-destination-validation: true" & CRLF),
            "200 OK"),
         "current notification PUT rejected explicit validation skip");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Legacy_Get))) = Canonical_Topic,
         "legacy notification GET lost shared current state");
      Require
        (Has (Put_Legacy (Topic_Document), "<Code>NotImplemented</Code>"),
         "legacy notification PUT claimed destination validation");
      Require
        (Has
           (Put_Legacy (Legacy_Only_Document),
            "<Code>NotImplemented</Code>"),
         "legacy notification PUT misclassified a deprecated-only shape");
      Require
        (Has (Put_Legacy (Empty_Document), "200 OK"),
         "legacy notification PUT rejected the empty configuration");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Put, Topic_Document,
                  "content-md5: " & Content_MD5 (Empty_Document) & CRLF)),
            "<Code>BadDigest</Code>"),
         "legacy notification PUT accepted a Content-MD5 mismatch");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Put, Empty_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Empty_Document) & CRLF)),
            "200 OK"),
         "legacy notification PUT rejected a generated checksum");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Put, Topic_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Empty_Document) & CRLF)),
            "<Code>BadDigest</Code>"),
         "legacy notification PUT accepted a generated checksum mismatch");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Current_Get))) = Canonical_Empty,
         "notification checksum failures changed retained state");
      Require
        (Has
           (Put_Current
              ("<NotificationConfiguration>"),
            "<Code>MalformedXML</Code>"),
         "current notification PUT accepted malformed XML");
      Require
        (Has
           (Put_Current
              (Empty_Document,
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Empty_Document) & CRLF),
            "<Code>InvalidRequest</Code>"),
         "current notification PUT accepted legacy checksum transport");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Put, Empty_Document)),
            "<Code>InvalidRequest</Code>"),
         "legacy notification PUT accepted missing checksum transport");
      Require
        (Has
           (Put_Current
              (Topic_Document,
               "x-amz-skip-destination-validation: false" & CRLF),
            "<Code>NotImplemented</Code>"),
         "current notification PUT treated false as a validation skip");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("notification", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "notification GET accepted an extra query member");
   end;

   declare
      Namespace : constant String :=
        "http://s3.amazonaws.com/doc/2006-03-01/";
      Encryption_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("encryption", ""),
         SigV4.Pair ("x-id", "PutBucketEncryption"));
      Encryption_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("encryption", ""),
         SigV4.Pair ("x-id", "GetBucketEncryption"));
      Encryption_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("encryption", ""),
         SigV4.Pair ("x-id", "DeleteBucketEncryption"));
      Ownership_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("ownershipControls", ""),
         SigV4.Pair ("x-id", "PutBucketOwnershipControls"));
      Ownership_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("ownershipControls", ""),
         SigV4.Pair ("x-id", "GetBucketOwnershipControls"));
      Ownership_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("ownershipControls", ""),
         SigV4.Pair ("x-id", "DeleteBucketOwnershipControls"));
      Encryption_Document : constant String :=
        "<ServerSideEncryptionConfiguration xmlns=""" & Namespace &
        """><Rule><ApplyServerSideEncryptionByDefault>" &
        "<SSEAlgorithm>aws:kms</SSEAlgorithm>" &
        "<KMSMasterKeyID>key</KMSMasterKeyID>" &
        "</ApplyServerSideEncryptionByDefault></Rule>" &
        "</ServerSideEncryptionConfiguration>";
      Ownership_Document : constant String :=
        "<OwnershipControls xmlns=""" & Namespace & """>" &
        "<Rule><ObjectOwnership>BucketOwnerPreferred</ObjectOwnership>" &
        "</Rule></OwnershipControls>";
      Canonical_Encryption : constant String :=
        Encryption.Serialize (Encryption.Parse (Encryption_Document));
      Canonical_Ownership : constant String :=
        Bucket_Controls.Serialize_Ownership_Controls
          (Bucket_Controls.Parse_Ownership_Controls (Ownership_Document));

      function Put
        (Query : SigV4.Name_Value_Array;
         Document : String;
         Extra : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Query, Document,
               "content-md5: " & Content_MD5 (Document) & CRLF & Extra)));
   begin
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Encryption_Get)),
            "<SSEAlgorithm>AES256</SSEAlgorithm>"),
         "GetBucketEncryption did not return the SSE-S3 default");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket", Ownership_Get)),
            "OwnershipControlsNotFoundError"),
         "GetBucketOwnershipControls did not report absence");
      Require
        (Has (Put (Encryption_Put, Encryption_Document), "200 OK"),
         "PutBucketEncryption rejected a valid configuration");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Encryption_Get))) =
           Canonical_Encryption,
         "GetBucketEncryption did not return canonical state");
      Require
        (Has (Put (Ownership_Put, Ownership_Document), "200 OK"),
         "PutBucketOwnershipControls rejected a valid configuration");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Ownership_Get))) =
           Canonical_Ownership,
         "GetBucketOwnershipControls did not return canonical state");
      Require
        (Has (Put (Encryption_Put, "<bad/>"), "<Code>MalformedXML</Code>"),
         "PutBucketEncryption accepted malformed XML");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Ownership_Put,
                  Ownership_Document)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketOwnershipControls accepted a missing Content-MD5");
      Require
        (Has
           (Put
              (Ownership_Put, Ownership_Document,
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" &
               "AAAAAAAAAAA=" & CRLF),
            "<Code>BadDigest</Code>"),
         "PutBucketOwnershipControls accepted a checksum mismatch");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Encryption_Get,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketEncryption ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("ownershipControls", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketOwnershipControls accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Encryption_Delete)),
            "204 No Content"),
         "DeleteBucketEncryption failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Encryption_Get)),
            "<SSEAlgorithm>AES256</SSEAlgorithm>"),
         "DeleteBucketEncryption did not restore SSE-S3");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Ownership_Delete)),
            "204 No Content"),
         "DeleteBucketOwnershipControls failed");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket", Ownership_Get)),
            "OwnershipControlsNotFoundError"),
         "DeleteBucketOwnershipControls left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Ownership_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketOwnershipControls did not distinguish absent bucket");
   end;

   declare
      Lifecycle_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("lifecycle", ""),
         SigV4.Pair ("x-id", "PutBucketLifecycleConfiguration"));
      Legacy_Lifecycle_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("lifecycle", ""),
         SigV4.Pair ("x-id", "PutBucketLifecycle"));
      Lifecycle_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("lifecycle", ""),
         SigV4.Pair ("x-id", "GetBucketLifecycleConfiguration"));
      Legacy_Lifecycle_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("lifecycle", ""),
         SigV4.Pair ("x-id", "GetBucketLifecycle"));
      Lifecycle_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("lifecycle", ""),
         SigV4.Pair ("x-id", "DeleteBucketLifecycle"));
      Logging_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("logging", ""),
         SigV4.Pair ("x-id", "PutBucketLogging"));
      Logging_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("logging", ""),
         SigV4.Pair ("x-id", "GetBucketLogging"));
      Namespace : constant String :=
        "http://s3.amazonaws.com/doc/2006-03-01/";
      Lifecycle_Document : constant String :=
        "<LifecycleConfiguration xmlns=""" & Namespace & """>" &
        "<Rule><Prefix>legacy/</Prefix><Status>Enabled</Status></Rule>" &
        "</LifecycleConfiguration>";
      Legacy_Lifecycle_Document : constant String :=
        Lifecycle_Document;
      Missing_Prefix_Lifecycle_Document : constant String :=
        "<LifecycleConfiguration xmlns=""" & Namespace & """>" &
        "<Rule><Status>Enabled</Status></Rule>" &
        "</LifecycleConfiguration>";
      Filter_Lifecycle_Document : constant String :=
        "<LifecycleConfiguration xmlns=""" & Namespace & """>" &
        "<Rule><Prefix>legacy/</Prefix>" &
        "<Filter><Prefix>current/</Prefix></Filter>" &
        "<Status>Enabled</Status></Rule></LifecycleConfiguration>";
      Logging_Document : constant String :=
        "<BucketLoggingStatus xmlns=""" & Namespace & """>" &
        "<LoggingEnabled><TargetBucket>log-target</TargetBucket>" &
        "<TargetPrefix>logs/</TargetPrefix></LoggingEnabled>" &
        "</BucketLoggingStatus>";
      Disabled_Logging : constant String :=
        "<BucketLoggingStatus xmlns=""" & Namespace &
        """></BucketLoggingStatus>";
      Canonical_Lifecycle : constant String :=
        Lifecycle.Serialize
          (Lifecycle.Parse (Lifecycle_Document),
           Flyology.Object_Storage.S3.XML.Default_Limits);
      Canonical_Logging : constant String :=
        Generated_Logging.Serialize
          (Logging.Parse
             (Logging_Document,
              Flyology.Object_Storage.S3.XML.Default_Limits),
           Flyology.Object_Storage.S3.XML.Default_Limits);
      Canonical_Disabled_Logging : constant String :=
        Generated_Logging.Serialize
          (Logging.Parse
             (Disabled_Logging,
              Flyology.Object_Storage.S3.XML.Default_Limits),
           Flyology.Object_Storage.S3.XML.Default_Limits);

      function Put_Lifecycle
        (Document : String;
         Extra    : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Lifecycle_Put, Document,
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Document) & CRLF & Extra)));

      function Put_Legacy_Lifecycle
        (Document : String;
         Extra    : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Legacy_Lifecycle_Put, Document,
               "content-md5: " & Content_MD5 (Document) & CRLF & Extra)));

      function Put_Logging
        (Document : String;
         Extra    : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Logging_Put, Document,
               "content-md5: " & Content_MD5 (Document) & CRLF &
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Document) & CRLF & Extra)));
   begin
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Lifecycle_Get)),
            "<Code>NoSuchLifecycleConfiguration</Code>"),
         "GetBucketLifecycleConfiguration did not report absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Lifecycle_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketLifecycleConfiguration confused bucket and state " &
         "absence");
      Require
        (Has (Put_Lifecycle (Lifecycle_Document), "200 OK"),
         "PutBucketLifecycleConfiguration rejected an absent transition " &
         "minimum");
      Require
        (Has (Put_Legacy_Lifecycle (Legacy_Lifecycle_Document), "200 OK"),
         "PutBucketLifecycle rejected valid legacy checksum transport");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Lifecycle_Put,
                  Legacy_Lifecycle_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value
                    (Core.SHA256, Legacy_Lifecycle_Document) & CRLF)),
            "200 OK"),
         "PutBucketLifecycle rejected generated checksum transport");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Lifecycle_Put,
                  Legacy_Lifecycle_Document,
                  "content-md5: " & Content_MD5 ("different") & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketLifecycle accepted a mismatched Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Lifecycle_Put,
                  Legacy_Lifecycle_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, "different") & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketLifecycle accepted a generated checksum mismatch");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Legacy_Lifecycle_Put,
                  Legacy_Lifecycle_Document)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLifecycle accepted missing checksum transport");
      Require
        (Has
           (Put_Legacy_Lifecycle
              (Legacy_Lifecycle_Document,
               "x-amz-transition-default-minimum-object-size: " &
               "varies_by_storage_class" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLifecycle accepted a current-only transition header");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Lifecycle_Get));
      begin
         Require
           (Response_Body (Response) = Canonical_Lifecycle
            and then not Has
              (Response,
               "x-amz-transition-default-minimum-object-size:"),
            "GetBucketLifecycleConfiguration invented a transition " &
            "minimum");
      end;
      Require
        (Has
           (Put_Lifecycle
              (Lifecycle_Document,
               "x-amz-transition-default-minimum-object-size: " &
               "varies_by_storage_class" & CRLF),
            "200 OK"),
         "PutBucketLifecycleConfiguration rejected valid state");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Lifecycle_Get));
      begin
         Require
           (Response_Body (Response) = Canonical_Lifecycle
            and then Has
              (Response,
               "x-amz-transition-default-minimum-object-size: " &
               "varies_by_storage_class")
            and then not Has (Response, "all_storage_classes_128K"),
            "GetBucketLifecycleConfiguration lost the varying transition " &
            "minimum");
      end;
      Require
        (Has
           (Put_Lifecycle
              (Lifecycle_Document,
               "x-amz-transition-default-minimum-object-size: " &
               "all_storage_classes_128K" & CRLF),
            "200 OK"),
         "PutBucketLifecycleConfiguration rejected a 128K transition " &
         "minimum");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Lifecycle_Get));
      begin
         Require
           (Response_Body (Response) = Canonical_Lifecycle
            and then Has
              (Response,
               "x-amz-transition-default-minimum-object-size: " &
               "all_storage_classes_128K")
            and then not Has (Response, "varies_by_storage_class"),
            "GetBucketLifecycleConfiguration did not replace the " &
            "transition minimum");
      end;
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Legacy_Lifecycle_Get));
      begin
         Require
           (Response_Body (Response) = Canonical_Lifecycle
            and then not Has
              (Response,
               "x-amz-transition-default-minimum-object-size:"),
            "GetBucketLifecycle alias returned a configuration-only " &
            "transition header");
      end;
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket",
                 (1 => SigV4.Pair ("lifecycle", ""))));
      begin
         Require
           (Response_Body (Response) = Canonical_Lifecycle
            and then Has
              (Response,
               "x-amz-transition-default-minimum-object-size: " &
               "all_storage_classes_128K"),
            "bare lifecycle query did not select the modern response");
      end;
      Require
        (Has
           (Put_Lifecycle
              (Lifecycle_Document,
               "x-amz-transition-default-minimum-object-size: invalid" &
               CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLifecycleConfiguration accepted an invalid transition " &
         "minimum");
      Require
        (Has
           (Put_Lifecycle
              ("<LifecycleConfiguration><Rule/></LifecycleConfiguration>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketLifecycleConfiguration accepted malformed XML");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Lifecycle_Put,
                  Lifecycle_Document)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLifecycleConfiguration accepted a missing checksum");
      Require
        (Has
           (Put_Lifecycle
               (Lifecycle_Document,
               "content-md5: " & Content_MD5 (Lifecycle_Document) & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLifecycleConfiguration accepted Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Lifecycle_Put,
                  Lifecycle_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, "different") & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketLifecycleConfiguration accepted a checksum mismatch");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Lifecycle_Get,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketLifecycleConfiguration ignored expected owner");
      Require
        (Has
           (Put_Lifecycle
              (Lifecycle_Document,
               "x-amz-expected-bucket-owner: different-owner" & CRLF),
            "403 Forbidden"),
         "PutBucketLifecycleConfiguration ignored expected owner");
      Require
        (Has
           (Put_Lifecycle
              (Lifecycle_Document,
               "x-amz-request-payer: requester" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLifecycleConfiguration accepted RequestPayer");
      Require
        (Has
           (Put_Legacy_Lifecycle (Filter_Lifecycle_Document),
            "<Code>MalformedXML</Code>"),
         "PutBucketLifecycle accepted a current-only Filter");
      Require
        (Has
           (Put_Legacy_Lifecycle (Missing_Prefix_Lifecycle_Document),
            "<Code>MalformedXML</Code>"),
         "PutBucketLifecycle accepted a lifecycle rule without Prefix");
      Require
        (Has (Put_Lifecycle (Filter_Lifecycle_Document), "200 OK"),
         "PutBucketLifecycleConfiguration rejected its Filter member");
      Require
        (Has (Put_Legacy_Lifecycle (""), "<Code>MalformedXML</Code>"),
         "PutBucketLifecycle accepted an absent lifecycle body");
      Require
        (Has (Put_Lifecycle (""), "<Code>MalformedXML</Code>"),
         "PutBucketLifecycleConfiguration accepted an absent body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("lifecycle", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketLifecycleConfiguration accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Lifecycle_Delete)),
            "204 No Content"),
         "DeleteBucketLifecycle failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Lifecycle_Get)),
            "NoSuchLifecycleConfiguration"),
         "DeleteBucketLifecycle left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Lifecycle_Delete)),
            "204 No Content"),
         "DeleteBucketLifecycle was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Lifecycle_Delete,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "DeleteBucketLifecycle ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Lifecycle_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketLifecycle did not distinguish an absent bucket");

      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Logging_Get))) =
           Canonical_Disabled_Logging,
         "GetBucketLogging did not return disabled state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Logging_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketLogging confused bucket absence with disabled state");
      Require
        (Has (Put_Logging (Logging_Document), "200 OK"),
         "PutBucketLogging rejected valid state");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Logging_Get))) =
           Canonical_Logging,
         "GetBucketLogging lost canonical state");
      Require
        (Has (Put_Logging (Disabled_Logging), "200 OK"),
         "PutBucketLogging rejected canonical disabled state");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Logging_Get))) =
           Canonical_Disabled_Logging,
         "GetBucketLogging lost explicitly disabled state");
      Require
        (Has
           (Put_Logging
              ("<BucketLoggingStatus><LoggingEnabled/>" &
               "</BucketLoggingStatus>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketLogging accepted malformed XML");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Logging_Put,
                  Logging_Document,
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Logging_Document) & CRLF)),
            "200 OK"),
         "PutBucketLogging rejected an omitted optional Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Logging_Put,
                  Logging_Document,
                  "content-md5: " & Content_MD5 (Logging_Document) & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLogging accepted a missing checksum");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Logging_Put,
                  Logging_Document,
                  "content-md5: invalid" & CRLF &
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Logging_Document) & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLogging accepted an invalid Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Logging_Put,
                  Logging_Document,
                  "content-md5: " & Content_MD5 (Logging_Document) & CRLF &
                  "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, "different") & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketLogging accepted a checksum mismatch");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Logging_Get,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketLogging ignored expected owner");
      Require
        (Has
           (Put_Logging
              (Logging_Document,
               "x-amz-expected-bucket-owner: different-owner" & CRLF),
            "403 Forbidden"),
         "PutBucketLogging ignored expected owner");
      Require
        (Has
           (Put_Logging
              (Logging_Document,
               "x-amz-request-payer: requester" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketLogging accepted unmodeled RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("logging", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketLogging accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Logging_Get,
                  "x-amz-request-payer", "requester")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketLogging accepted unmodeled RequestPayer");
   end;

   declare
      Namespace : constant String :=
        "http://s3.amazonaws.com/doc/2006-03-01/";
      Analytics_ID : constant String := "server analytics";
      Metrics_ID : constant String := "server metrics";
      Analytics_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("analytics", ""),
         SigV4.Pair ("id", Analytics_ID));
      Analytics_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("analytics", ""),
         SigV4.Pair ("id", Analytics_ID),
         SigV4.Pair ("x-id", "GetBucketAnalyticsConfiguration"));
      Analytics_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("analytics", ""),
         SigV4.Pair ("id", Analytics_ID));
      Analytics_Empty : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("analytics", ""),
         SigV4.Pair ("id", ""));
      Metrics_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("metrics", ""),
         SigV4.Pair ("id", Metrics_ID),
         SigV4.Pair ("x-id", "PutBucketMetricsConfiguration"));
      Metrics_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("metrics", ""),
         SigV4.Pair ("id", Metrics_ID));
      Metrics_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("metrics", ""),
         SigV4.Pair ("id", Metrics_ID),
         SigV4.Pair ("x-id", "DeleteBucketMetricsConfiguration"));
      Metrics_Empty : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("metrics", ""),
         SigV4.Pair ("id", ""));
      Intelligent_Tiering_ID : constant String := "server tiering";
      Intelligent_Tiering_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("intelligent-tiering", ""),
         SigV4.Pair ("id", Intelligent_Tiering_ID));
      Intelligent_Tiering_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("intelligent-tiering", ""),
         SigV4.Pair ("id", Intelligent_Tiering_ID),
         SigV4.Pair
           ("x-id", "GetBucketIntelligentTieringConfiguration"));
      Intelligent_Tiering_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("intelligent-tiering", ""),
         SigV4.Pair ("id", Intelligent_Tiering_ID));
      Intelligent_Tiering_Empty : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("intelligent-tiering", ""),
         SigV4.Pair ("id", ""));
      Inventory_ID : constant String := "server inventory";
      Inventory_Put : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("inventory", ""),
         SigV4.Pair ("id", Inventory_ID),
         SigV4.Pair ("x-id", "PutBucketInventoryConfiguration"));
      Inventory_Get : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("inventory", ""),
         SigV4.Pair ("id", Inventory_ID));
      Inventory_Delete : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("inventory", ""),
         SigV4.Pair ("id", Inventory_ID),
         SigV4.Pair ("x-id", "DeleteBucketInventoryConfiguration"));
      Inventory_Empty : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("inventory", ""),
         SigV4.Pair ("id", ""));
      Analytics_List : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("analytics", ""),
         SigV4.Pair ("x-id", "ListBucketAnalyticsConfigurations"));
      Metrics_List : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("metrics", ""),
         SigV4.Pair ("x-id", "ListBucketMetricsConfigurations"));
      Intelligent_Tiering_List : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("intelligent-tiering", ""),
         SigV4.Pair
           ("x-id", "ListBucketIntelligentTieringConfigurations"));
      Inventory_List : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("inventory", ""),
         SigV4.Pair ("x-id", "ListBucketInventoryConfigurations"));
      Analytics_Document : constant String :=
        "<AnalyticsConfiguration xmlns=""" & Namespace & """>" &
        "<Id>stored analytics</Id><StorageClassAnalysis/>" &
        "</AnalyticsConfiguration>";
      First_Analytics_Document : constant String :=
        "<AnalyticsConfiguration xmlns=""" & Namespace & """>" &
        "<Id>first analytics</Id><StorageClassAnalysis/>" &
        "</AnalyticsConfiguration>";
      Last_Analytics_Document : constant String :=
        "<AnalyticsConfiguration xmlns=""" & Namespace & """>" &
        "<Id>last analytics</Id><StorageClassAnalysis/>" &
        "</AnalyticsConfiguration>";
      Metrics_Document : constant String :=
        "<MetricsConfiguration xmlns=""" & Namespace & """>" &
        "<Id>stored metrics</Id></MetricsConfiguration>";
      Intelligent_Tiering_Document : constant String :=
        "<IntelligentTieringConfiguration xmlns=""" & Namespace & """>" &
        "<Id>stored tiering</Id><Status>Enabled</Status>" &
        "<Tiering><Days>90</Days><AccessTier>ARCHIVE_ACCESS</AccessTier>" &
        "</Tiering></IntelligentTieringConfiguration>";
      Inventory_Document : constant String :=
        "<InventoryConfiguration xmlns=""" & Namespace & """>" &
        "<Destination><S3BucketDestination>" &
        "<Bucket>arn:aws:s3:::reports</Bucket><Format>CSV</Format>" &
        "</S3BucketDestination></Destination><IsEnabled>true</IsEnabled>" &
        "<Id>stored inventory</Id><IncludedObjectVersions>All" &
        "</IncludedObjectVersions><Schedule><Frequency>Daily</Frequency>" &
        "</Schedule></InventoryConfiguration>";
      Canonical_Analytics : constant String :=
        Analytics.Serialize
          (Analytics.Parse (Analytics_Document, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Metrics : constant String :=
        Metrics.Serialize
          (Metrics.Parse (Metrics_Document, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Intelligent_Tiering : constant String :=
        Intelligent_Tiering.Serialize
          (Intelligent_Tiering.Parse
             (Intelligent_Tiering_Document, XML.Default_Limits),
           XML.Default_Limits);
      Canonical_Inventory : constant String :=
        Generated_Inventory.Serialize
          (Inventory.Parse (Inventory_Document, XML.Default_Limits),
           XML.Default_Limits);

      function Put
        (Query : SigV4.Name_Value_Array;
         Document : String;
         Extra : String := "";
         Corrupt_Signature : Boolean := False) return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Query, Document, Extra,
               Corrupt_Signature => Corrupt_Signature)));

      function List_Get
        (Bucket, Family, Operation_ID : String;
         Continuation_Token : String := "";
         Has_Continuation_Token : Boolean := False;
         Extra_Header_Name : String := "";
         Extra_Header_Value : String := "";
         Second_Header_Value : String := "") return String is
        (Run
           (Signed_Query_Request
              ("GET", "/" & Bucket,
               (if Has_Continuation_Token then
                  (SigV4.Pair (Family, ""),
                   SigV4.Pair
                     ("continuation-token", Continuation_Token),
                   SigV4.Pair ("x-id", Operation_ID))
                else
                  (SigV4.Pair (Family, ""),
                   SigV4.Pair ("x-id", Operation_ID))),
               Extra_Header_Name, Extra_Header_Value,
               Second_Header_Value => Second_Header_Value)));
   begin
      declare
         Analytics_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Analytics_List));
         Metrics_Response : constant String :=
           List_Get
             ("test-bucket", "metrics",
              "ListBucketMetricsConfigurations", "",
              Has_Continuation_Token => True);
         Intelligent_Tiering_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Intelligent_Tiering_List));
         Inventory_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Inventory_List));
         Analytics_Page : constant Analytics.Analytics_Configuration_Page :=
           Analytics.Parse_List
             (Response_Body (Analytics_Response), XML.Default_Limits);
         Metrics_Page : constant Metrics.Metrics_Configuration_Page :=
           Metrics.Parse_List
             (Response_Body (Metrics_Response), XML.Default_Limits);
         Intelligent_Tiering_Page : constant
           Intelligent_Tiering.Intelligent_Tiering_Configuration_Page :=
           Intelligent_Tiering.Parse_List
             (Response_Body (Intelligent_Tiering_Response),
              XML.Default_Limits);
         Inventory_Page : constant Inventory.Inventory_Configuration_Page :=
           Inventory.Parse_List
             (Response_Body (Inventory_Response), XML.Default_Limits);
      begin
         Require
           (Has (Analytics_Response, "200 OK")
            and then Analytics_Page.Has_Is_Truncated
            and then not Analytics_Page.Is_Truncated
            and then Analytics_Page.Configurations.Is_Empty,
            "ListBucketAnalyticsConfigurations lost the empty page");
         Require
           (Has (Metrics_Response, "200 OK")
            and then Metrics_Page.Has_Is_Truncated
            and then not Metrics_Page.Is_Truncated
            and then Metrics_Page.Configurations.Is_Empty
            and then Metrics_Page.Continuation_Token.Is_Set
            and then
              US.Length (Metrics_Page.Continuation_Token.Value) = 0,
            "ListBucketMetricsConfigurations lost an explicit empty token");
         Require
           (Has (Intelligent_Tiering_Response, "200 OK")
            and then Intelligent_Tiering_Page.Has_Is_Truncated
            and then not Intelligent_Tiering_Page.Is_Truncated
            and then Intelligent_Tiering_Page.Configurations.Is_Empty,
            "ListBucketIntelligentTieringConfigurations lost the empty page");
         Require
           (Has (Inventory_Response, "200 OK")
            and then Inventory_Page.Has_Is_Truncated
            and then not Inventory_Page.Is_Truncated
            and then Inventory_Page.Configurations.Is_Empty,
            "ListBucketInventoryConfigurations lost the empty page");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Analytics_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "GetBucketAnalyticsConfiguration did not report absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Analytics_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketAnalyticsConfiguration confused bucket and state " &
         "absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Metrics_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "GetBucketMetricsConfiguration did not report absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Metrics_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketMetricsConfiguration confused bucket and state absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "GetBucketIntelligentTieringConfiguration did not report absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Intelligent_Tiering_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketIntelligentTieringConfiguration confused bucket absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Inventory_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "GetBucketInventoryConfiguration did not report absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Inventory_Get)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketInventoryConfiguration confused bucket and state absence");
      Require
        (Has (Put (Analytics_Empty, Analytics_Document), "200 OK"),
         "PutBucketAnalyticsConfiguration rejected an empty id");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Analytics_Empty))) =
           Canonical_Analytics,
         "GetBucketAnalyticsConfiguration lost an empty id");
      declare
         Page : constant Analytics.Analytics_Configuration_Page :=
           Analytics.Parse_List
             (Response_Body
                (Run
                   (Signed_Query_Request
                      ("GET", "/test-bucket", Analytics_List))),
              XML.Default_Limits);
      begin
         Require
           (Page.Configurations.Length = 1,
            "ListBucketAnalyticsConfigurations omitted an empty identifier");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Analytics_Empty)),
            "204 No Content"),
         "DeleteBucketAnalyticsConfiguration rejected an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Analytics_Empty)),
            "<Code>NoSuchConfiguration</Code>"),
         "empty analytics id remained configured after deletion");
      Require
        (Has (Put (Metrics_Empty, Metrics_Document), "200 OK"),
         "PutBucketMetricsConfiguration rejected an empty id");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Metrics_Empty))) =
           Canonical_Metrics,
         "GetBucketMetricsConfiguration lost an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Metrics_Empty)),
            "204 No Content"),
         "DeleteBucketMetricsConfiguration rejected an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Metrics_Empty)),
            "<Code>NoSuchConfiguration</Code>"),
         "empty metrics id remained configured after deletion");
      Require
        (Has
           (Put (Intelligent_Tiering_Empty, Intelligent_Tiering_Document),
            "200 OK"),
         "PutBucketIntelligentTieringConfiguration rejected an empty id");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Empty))) =
           Canonical_Intelligent_Tiering,
         "GetBucketIntelligentTieringConfiguration lost an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Intelligent_Tiering_Empty)),
            "204 No Content"),
         "DeleteBucketIntelligentTieringConfiguration rejected an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Empty)),
            "<Code>NoSuchConfiguration</Code>"),
         "empty Intelligent-Tiering id remained configured after deletion");
      Require
        (Has (Put (Inventory_Empty, Inventory_Document), "200 OK"),
         "PutBucketInventoryConfiguration rejected an empty id");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Inventory_Empty))) =
           Canonical_Inventory,
         "GetBucketInventoryConfiguration lost an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Inventory_Empty)),
            "204 No Content"),
         "DeleteBucketInventoryConfiguration rejected an empty id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Inventory_Empty)),
            "<Code>NoSuchConfiguration</Code>"),
         "empty inventory id remained configured after deletion");
      Require
        (Has (Put (Analytics_Put, Analytics_Document), "200 OK"),
         "PutBucketAnalyticsConfiguration rejected valid XML");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Analytics_Get))) =
           Canonical_Analytics,
         "GetBucketAnalyticsConfiguration lost canonical state");
      Require
        (Has (Put (Metrics_Put, Metrics_Document), "200 OK"),
         "PutBucketMetricsConfiguration rejected valid XML");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Metrics_Get))) =
           Canonical_Metrics,
         "GetBucketMetricsConfiguration lost canonical state");
      Require
        (Has
           (Put (Intelligent_Tiering_Put, Intelligent_Tiering_Document),
            "200 OK"),
         "PutBucketIntelligentTieringConfiguration rejected valid XML");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Get))) =
           Canonical_Intelligent_Tiering,
         "GetBucketIntelligentTieringConfiguration lost canonical state");
      Require
        (Has (Put (Inventory_Put, Inventory_Document), "200 OK"),
         "PutBucketInventoryConfiguration rejected valid XML");
      Require
        (Response_Body
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Inventory_Get))) =
           Canonical_Inventory,
         "GetBucketInventoryConfiguration lost canonical state");
      Require
        (Has
           (Put
              ((SigV4.Pair ("analytics", ""),
                SigV4.Pair ("id", "00-analytics-order")),
               First_Analytics_Document),
            "200 OK"),
         "analytics list ordering fixture rejected its first entry");
      Require
        (Has
           (Put
              ((SigV4.Pair ("analytics", ""),
                SigV4.Pair ("id", "zz-analytics-order")),
               Last_Analytics_Document),
            "200 OK"),
         "analytics list ordering fixture rejected its last entry");
      declare
         Analytics_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Analytics_List));
         Metrics_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Metrics_List));
         Intelligent_Tiering_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Intelligent_Tiering_List));
         Inventory_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket", Inventory_List));
         Analytics_Page : constant Analytics.Analytics_Configuration_Page :=
           Analytics.Parse_List
             (Response_Body (Analytics_Response), XML.Default_Limits);
         Metrics_Page : constant Metrics.Metrics_Configuration_Page :=
           Metrics.Parse_List
             (Response_Body (Metrics_Response), XML.Default_Limits);
         Intelligent_Tiering_Page : constant
           Intelligent_Tiering.Intelligent_Tiering_Configuration_Page :=
           Intelligent_Tiering.Parse_List
             (Response_Body (Intelligent_Tiering_Response),
              XML.Default_Limits);
         Inventory_Page : constant Inventory.Inventory_Configuration_Page :=
           Inventory.Parse_List
             (Response_Body (Inventory_Response), XML.Default_Limits);
      begin
         Require
           (Analytics_Page.Configurations.Length = 3
            and then
              US.To_String (Analytics_Page.Configurations.Element (1).ID) =
                "first analytics"
            and then
              US.To_String (Analytics_Page.Configurations.Element (2).ID) =
                "stored analytics"
            and then
              US.To_String (Analytics_Page.Configurations.Element (3).ID) =
                "last analytics",
            "ListBucketAnalyticsConfigurations lost identifier ordering");
         Require
           (Metrics_Page.Configurations.Length = 1
            and then
              US.To_String (Metrics_Page.Configurations.First_Element.ID) =
                "stored metrics",
            "ListBucketMetricsConfigurations lost canonical state");
         Require
           (Intelligent_Tiering_Page.Configurations.Length = 1
            and then
              US.To_String
                (Intelligent_Tiering_Page.Configurations.First_Element.ID) =
                  "stored tiering",
            "ListBucketIntelligentTieringConfigurations lost canonical state");
         Require
           (Inventory_Page.Configurations.Length = 1
            and then
              US.To_String (Inventory_Page.Configurations.First_Element.ID) =
                "stored inventory",
            "ListBucketInventoryConfigurations lost canonical state");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket",
                  (SigV4.Pair ("analytics", ""),
                   SigV4.Pair ("id", "00-analytics-order")))),
            "204 No Content"),
         "analytics list ordering fixture cleanup failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket",
                  (SigV4.Pair ("analytics", ""),
                   SigV4.Pair ("id", "zz-analytics-order")))),
            "204 No Content"),
         "analytics list ordering fixture cleanup failed");
      Require
        (Has
           (List_Get
              ("absent-bucket", "analytics",
               "ListBucketAnalyticsConfigurations"),
            "<Code>NoSuchBucket</Code>"),
         "ListBucketAnalyticsConfigurations confused bucket absence");
      Require
        (Has
           (List_Get
              ("test-bucket", "inventory",
               "ListBucketInventoryConfigurations",
               Extra_Header_Name => "x-amz-expected-bucket-owner",
               Extra_Header_Value => "different-owner"),
            "403 Forbidden"),
         "ListBucketInventoryConfigurations ignored expected owner");
      Require
        (Has
           (List_Get
              ("test-bucket", "metrics",
               "ListBucketMetricsConfigurations",
               Extra_Header_Name => "x-amz-expected-bucket-owner",
               Extra_Header_Value => "owner",
               Second_Header_Value => "owner"),
            "<Code>InvalidRequest</Code>"),
         "ListBucketMetricsConfigurations accepted duplicate owner headers");
      Require
        (Has
           (List_Get
              ("test-bucket", "intelligent-tiering",
               "ListBucketIntelligentTieringConfigurations",
               Extra_Header_Name => "content-type",
               Extra_Header_Value => "application/xml"),
            "<Code>InvalidRequest</Code>"),
         "ListBucketIntelligentTieringConfigurations accepted a header");
      Require
        (Has
           (List_Get
              ("test-bucket", "analytics",
               "ListBucketAnalyticsConfigurations",
               Extra_Header_Name => "x-amz-mfa",
               Extra_Header_Value => "device 123456"),
            "<Code>InvalidRequest</Code>"),
         "ListBucketAnalyticsConfigurations accepted an MFA header");
      Require
        (Has
           (List_Get
              ("test-bucket", "inventory",
               "ListBucketInventoryConfigurations",
               Extra_Header_Name =>
                 "x-amz-server-side-encryption-customer-algorithm",
               Extra_Header_Value => "AES256"),
            "<Code>InvalidRequest</Code>"),
         "ListBucketInventoryConfigurations accepted encryption controls");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Inventory_List, "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "ListBucketInventoryConfigurations accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("analytics", ""),
                   SigV4.Pair ("unexpected", "1"),
                   SigV4.Pair
                     ("x-id", "ListBucketAnalyticsConfigurations")))),
            "<Code>InvalidArgument</Code>"),
         "ListBucketAnalyticsConfigurations accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("metrics", ""),
                   SigV4.Pair ("unexpected", "1"),
                   SigV4.Pair
                     ("x-id", "ListBucketMetricsConfigurations")),
                  "", Corrupt_Signature => True)),
            "403 Forbidden"),
         "configuration-list query validation ran before authentication");
      Require
        (Has
           (Put
              (Analytics_Put,
               "<AnalyticsConfiguration><Id>bad</Id>" &
               "</AnalyticsConfiguration>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketAnalyticsConfiguration accepted malformed XML");
      Require
        (Has
           (Put (Metrics_Put, "<MetricsConfiguration/>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketMetricsConfiguration accepted malformed XML");
      Require
        (Has
           (Put
              (Intelligent_Tiering_Put,
               "<IntelligentTieringConfiguration/>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketIntelligentTieringConfiguration accepted malformed XML");
      Require
        (Has
           (Put (Inventory_Put, "<InventoryConfiguration/>"),
            "<Code>MalformedXML</Code>"),
         "PutBucketInventoryConfiguration accepted malformed XML");
      Require
        (Has
           (Put
              (Analytics_Put, Analytics_Document,
               "content-md5: " & Content_MD5 (Analytics_Document) & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAnalyticsConfiguration accepted Content-MD5");
      Require
        (Has
           (Put
              (Metrics_Put, Metrics_Document,
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Metrics_Document) & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketMetricsConfiguration accepted checksum controls");
      Require
        (Has
           (Put
              (Intelligent_Tiering_Put, Intelligent_Tiering_Document,
               "content-md5: " &
               Content_MD5 (Intelligent_Tiering_Document) & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketIntelligentTieringConfiguration accepted Content-MD5");
      Require
        (Has
           (Put
              (Inventory_Put, Inventory_Document,
               "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
               "x-amz-checksum-sha256: " &
               Checksum_Value (Core.SHA256, Inventory_Document) & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketInventoryConfiguration accepted checksum controls");
      Require
        (Has
           (Put
              (Analytics_Put, Analytics_Document,
               "x-amz-request-payer: requester" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketAnalyticsConfiguration accepted RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Metrics_Get,
                  "x-amz-request-payer", "requester")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketMetricsConfiguration accepted RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Analytics_Get,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketAnalyticsConfiguration ignored expected owner");
      Require
        (Has
           (Put
              (Metrics_Put, Metrics_Document,
               "x-amz-expected-bucket-owner: different-owner" & CRLF),
            "403 Forbidden"),
         "PutBucketMetricsConfiguration ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Get,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketIntelligentTieringConfiguration ignored expected owner");
      Require
        (Has
           (Put
              (Inventory_Put, Inventory_Document,
               "x-amz-expected-bucket-owner: different-owner" & CRLF),
            "403 Forbidden"),
         "PutBucketInventoryConfiguration ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("analytics", ""),
                   SigV4.Pair ("x-id",
                               "GetBucketAnalyticsConfiguration")))),
            "400 Bad Request"),
         "GetBucketAnalyticsConfiguration accepted a missing id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("metrics", ""),
                   SigV4.Pair ("id", Metrics_ID),
                   SigV4.Pair ("id", "duplicate"),
                   SigV4.Pair
                     ("x-id", "GetBucketMetricsConfiguration")))),
            "400 Bad Request"),
         "GetBucketMetricsConfiguration accepted a duplicate id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("analytics", ""),
                   SigV4.Pair ("id", Analytics_ID),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketAnalyticsConfiguration accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("metrics", ""),
                   SigV4.Pair ("id", Metrics_ID),
                   SigV4.Pair
                     ("x-id", "GetBucketAnalyticsConfiguration")))),
            "400 Bad Request"),
         "GetBucketMetricsConfiguration accepted a cross-family x-id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("intelligent-tiering", ""),
                   SigV4.Pair
                     ("x-id",
                      "GetBucketIntelligentTieringConfiguration")))),
            "400 Bad Request"),
         "GetBucketIntelligentTieringConfiguration accepted a missing id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("inventory", ""),
                   SigV4.Pair ("id", Inventory_ID),
                   SigV4.Pair ("id", "duplicate")))),
            "400 Bad Request"),
         "GetBucketInventoryConfiguration accepted a duplicate id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("intelligent-tiering", ""),
                   SigV4.Pair ("id", Intelligent_Tiering_ID),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketIntelligentTieringConfiguration accepted an extra query");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("inventory", ""),
                   SigV4.Pair ("id", Inventory_ID),
                   SigV4.Pair
                     ("x-id",
                      "GetBucketIntelligentTieringConfiguration")))),
            "400 Bad Request"),
         "GetBucketInventoryConfiguration accepted a cross-family x-id");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("intelligent-tiering", ""),
                   SigV4.Pair ("id", Intelligent_Tiering_ID),
                   SigV4.Pair ("x-id", "")))),
            "400 Bad Request"),
         "GetBucketIntelligentTieringConfiguration accepted an empty x-id");
      Require
        (Has
           (Put
              ((SigV4.Pair ("analytics", ""),
                SigV4.Pair ("x-id", "PutBucketAnalyticsConfiguration")),
               "<bad/>", Corrupt_Signature => True),
            "403 Forbidden"),
         "point-configuration validation ran before authentication");
      Require
        (Has
           (Put
              ((SigV4.Pair ("intelligent-tiering", ""),
                SigV4.Pair
                  ("x-id", "PutBucketIntelligentTieringConfiguration")),
               "<bad/>", Corrupt_Signature => True),
            "403 Forbidden"),
         "Intelligent-Tiering query validation ran before authentication");
      Require
        (Has
           (Run
              (Signed_Query_Put_Declared_Length_Request
                 ("/test-bucket", Analytics_Put,
                  Ada.Strings.Fixed.Trim
                    (Natural'Image
                       (XML.Default_Limits.Maximum_Document_Bytes + 1),
                     Ada.Strings.Both))),
            "<Code>EntityTooLarge</Code>"),
         "PutBucketAnalyticsConfiguration accepted an oversized document");
      Require
        (Has
           (Run
              (Signed_Query_Put_Declared_Length_Request
                 ("/test-bucket", Inventory_Put,
                  Ada.Strings.Fixed.Trim
                    (Natural'Image
                       (XML.Default_Limits.Maximum_Document_Bytes + 1),
                     Ada.Strings.Both))),
            "<Code>EntityTooLarge</Code>"),
         "PutBucketInventoryConfiguration accepted an oversized document");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Get,
                  "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketIntelligentTieringConfiguration accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("DELETE", "/test-bucket", Inventory_Delete,
                  "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "DeleteBucketInventoryConfiguration accepted a request body");
      declare
         Limit_Bucket : constant String := "configuration-limit-bucket";
         Result       : Flyology.Object_Storage.Status;

         function Identifier
           (Prefix : String; Index : Positive) return String is
           (Prefix & Ada.Strings.Fixed.Trim
              (Positive'Image (Index), Ada.Strings.Both));

         function Limit_Put
           (Family, Identifier : String; Document : String) return String is
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Limit_Bucket,
                  (SigV4.Pair (Family, ""),
                   SigV4.Pair ("id", Identifier)),
                  Document)));
      begin
         Store.Create_Bucket
           (Limit_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "point-configuration limit bucket creation failed");
         for Index in 1 .. 1_000 loop
            Store.Put_Bucket_Analytics_Configuration
              (Limit_Bucket, Identifier ("analytics-", Index),
               Canonical_Analytics, null, Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "analytics limit fixture reached its bound early");
            Store.Put_Bucket_Metrics_Configuration
              (Limit_Bucket, Identifier ("metrics-", Index),
               Canonical_Metrics, null, Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "metrics limit fixture reached its bound early");
            Store.Put_Bucket_Intelligent_Tiering_Configuration
              (Limit_Bucket, Identifier ("tiering-", Index),
               Canonical_Intelligent_Tiering, null,
               Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "Intelligent-Tiering limit fixture reached its bound early");
            Store.Put_Bucket_Inventory_Configuration
              (Limit_Bucket, Identifier ("inventory-", Index),
               Canonical_Inventory, null, Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "inventory limit fixture reached its bound early");
         end loop;
         declare
            Response : constant String :=
              Limit_Put
                ("analytics", "analytics-over-limit", Analytics_Document);
         begin
            Require
              (Has (Response, "400 Bad Request")
               and then Has
                 (Response, "<Code>TooManyConfigurations</Code>"),
               "PutBucketAnalyticsConfiguration lost its modeled limit " &
               "error");
         end;
         Require
           (Has (Limit_Put ("analytics", "analytics-1",
                            Analytics_Document),
                 "200 OK"),
            "analytics limit rejected replacement of an existing id");
         declare
            Response : constant String :=
              Limit_Put ("metrics", "metrics-over-limit", Metrics_Document);
         begin
            Require
              (Has (Response, "400 Bad Request")
               and then Has
                 (Response, "<Code>TooManyConfigurations</Code>"),
               "PutBucketMetricsConfiguration lost its modeled limit " &
               "error");
         end;
         Require
           (Has (Limit_Put ("metrics", "metrics-1", Metrics_Document),
                 "200 OK"),
            "metrics limit rejected replacement of an existing id");
         declare
            Response : constant String :=
              Limit_Put
                ("intelligent-tiering", "tiering-over-limit",
                 Intelligent_Tiering_Document);
         begin
            Require
              (Has (Response, "400 Bad Request")
               and then Has
                 (Response, "<Code>TooManyConfigurations</Code>"),
               "PutBucketIntelligentTieringConfiguration lost its modeled " &
               "limit error");
         end;
         Require
           (Has
              (Limit_Put
                 ("intelligent-tiering", "tiering-1",
                  Intelligent_Tiering_Document),
               "200 OK"),
            "Intelligent-Tiering limit rejected replacement of an id");
         declare
            Response : constant String :=
              Limit_Put
                ("inventory", "inventory-over-limit", Inventory_Document);
         begin
            Require
              (Has (Response, "400 Bad Request")
               and then Has
                 (Response, "<Code>TooManyConfigurations</Code>"),
               "PutBucketInventoryConfiguration lost its modeled limit " &
               "error");
         end;
         Require
           (Has
              (Limit_Put
                 ("inventory", "inventory-1", Inventory_Document),
               "200 OK"),
            "inventory limit rejected replacement of an existing id");
         declare
            Analytics_Response : constant String :=
              List_Get
                (Limit_Bucket, "analytics",
                 "ListBucketAnalyticsConfigurations");
            Metrics_Response : constant String :=
              List_Get
                (Limit_Bucket, "metrics",
                 "ListBucketMetricsConfigurations");
            Intelligent_Tiering_Response : constant String :=
              List_Get
                (Limit_Bucket, "intelligent-tiering",
                 "ListBucketIntelligentTieringConfigurations");
            Inventory_Response : constant String :=
              List_Get
                (Limit_Bucket, "inventory",
                 "ListBucketInventoryConfigurations");
            Analytics_Page : constant
              Analytics.Analytics_Configuration_Page :=
              Analytics.Parse_List
                (Response_Body (Analytics_Response), XML.Default_Limits);
            Metrics_Page : constant Metrics.Metrics_Configuration_Page :=
              Metrics.Parse_List
                (Response_Body (Metrics_Response), XML.Default_Limits);
            Intelligent_Tiering_Page : constant
              Intelligent_Tiering.Intelligent_Tiering_Configuration_Page :=
              Intelligent_Tiering.Parse_List
                (Response_Body (Intelligent_Tiering_Response),
                 XML.Default_Limits);
            Inventory_Page : constant
              Inventory.Inventory_Configuration_Page :=
              Inventory.Parse_List
                (Response_Body (Inventory_Response), XML.Default_Limits);
            Analytics_Token : constant String :=
              US.To_String (Analytics_Page.Next_Continuation_Token.Value);
            Analytics_Next_Response : constant String :=
              List_Get
                (Limit_Bucket, "analytics",
                 "ListBucketAnalyticsConfigurations", Analytics_Token,
                 Has_Continuation_Token => True);
            Analytics_Next_Page : constant
              Analytics.Analytics_Configuration_Page :=
              Analytics.Parse_List
                (Response_Body (Analytics_Next_Response),
                 XML.Default_Limits);
         begin
            Require
              (Analytics_Page.Configurations.Length = 100
               and then Analytics_Page.Is_Truncated
               and then Analytics_Page.Next_Continuation_Token.Is_Set,
               "ListBucketAnalyticsConfigurations lost its 100-entry page");
            Require
              (Metrics_Page.Configurations.Length = 100
               and then Metrics_Page.Is_Truncated
               and then Metrics_Page.Next_Continuation_Token.Is_Set,
               "ListBucketMetricsConfigurations lost its 100-entry page");
            Require
              (Inventory_Page.Configurations.Length = 100
               and then Inventory_Page.Is_Truncated
               and then Inventory_Page.Next_Continuation_Token.Is_Set,
               "ListBucketInventoryConfigurations lost its 100-entry page");
            Require
              (Intelligent_Tiering_Page.Configurations.Length = 1_000
               and then not Intelligent_Tiering_Page.Is_Truncated
               and then
                 not Intelligent_Tiering_Page.Next_Continuation_Token.Is_Set,
               "ListBucketIntelligentTieringConfigurations lost its " &
               "established 1,000-entry ceiling");
            Require
              (Analytics_Next_Page.Configurations.Length = 100
               and then Analytics_Next_Page.Continuation_Token.Is_Set
               and then
                 US.To_String
                   (Analytics_Next_Page.Continuation_Token.Value) =
                     Analytics_Token,
               "ListBucketAnalyticsConfigurations lost its opaque cursor");
            Require
              (Has
                 (List_Get
                    (Limit_Bucket, "metrics",
                     "ListBucketMetricsConfigurations", Analytics_Token,
                     Has_Continuation_Token => True),
                  "<Code>InvalidArgument</Code>"),
               "configuration continuation token crossed a family");
            Require
              (Has
                 (List_Get
                    ("other-bucket", "analytics",
                     "ListBucketAnalyticsConfigurations", Analytics_Token,
                     Has_Continuation_Token => True),
                  "<Code>InvalidArgument</Code>"),
               "configuration continuation token crossed a bucket");
            Require
              (Has
                 (List_Get
                    (Limit_Bucket, "analytics",
                     "ListBucketAnalyticsConfigurations", "malformed",
                     Has_Continuation_Token => True),
                  "<Code>InvalidArgument</Code>"),
               "malformed configuration continuation token was accepted");
         end;
         Store.Delete_Bucket
           (Limit_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "point-configuration limit bucket cleanup failed");
      end;
      declare
         Budget_Bucket : constant String := "configuration-budget-bucket";
         Document_Budget : constant Positive :=
           XML.Default_Limits.Maximum_Document_Bytes;
         Metrics_Prefix : constant String :=
           "<MetricsConfiguration xmlns=""" & Namespace & """>" &
           "<Id>budget</Id><Filter><Prefix>";
         Metrics_Suffix : constant String :=
           "</Prefix></Filter></MetricsConfiguration>";
         Analytics_Prefix : constant String :=
           "<AnalyticsConfiguration xmlns=""" & Namespace & """>" &
           "<Id>budget</Id><Filter><Prefix>";
         Analytics_Suffix : constant String :=
           "</Prefix></Filter><StorageClassAnalysis/>" &
           "</AnalyticsConfiguration>";
         Result : Flyology.Object_Storage.Status;
         type Document_Access is access all String;

         function Sized_Document
           (Prefix, Suffix : String;
            Total_Length   : Positive;
            Fill           : Character) return Document_Access
         is
            Result : constant Document_Access :=
              new String (1 .. Total_Length);
            Prefix_Last : constant Natural := Prefix'Length;
            Suffix_First : constant Positive :=
              Total_Length - Suffix'Length + 1;
         begin
            Result.all (1 .. Prefix_Last) := Prefix;
            Result.all (Prefix_Last + 1 .. Suffix_First - 1) :=
              (others => Fill);
            Result.all (Suffix_First .. Total_Length) := Suffix;
            return Result;
         end Sized_Document;
      begin
         Store.Create_Bucket
           (Budget_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "configuration listing budget bucket creation failed");
         declare
            First_Length : constant Positive := Document_Budget / 2 - 1;
            Second_Length : constant Positive :=
              Document_Budget - 2 - First_Length;
            First_Document : constant Document_Access :=
              Sized_Document
                (Metrics_Prefix, Metrics_Suffix, First_Length, 'a');
            Second_Document : constant Document_Access :=
              Sized_Document
                (Metrics_Prefix, Metrics_Suffix, Second_Length, 'b');
         begin
            Store.Put_Bucket_Metrics_Configuration
              (Budget_Bucket, "", First_Document.all, null,
               Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "first listing budget fixture was rejected");
            Store.Put_Bucket_Metrics_Configuration
              (Budget_Bucket, "b", Second_Document.all, null,
               Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "second listing budget fixture was rejected");
         end;
         declare
            Response : constant Document_Access :=
              new String'
                (List_Get
                   (Budget_Bucket, "metrics",
                    "ListBucketMetricsConfigurations"));
            Response_Marker : constant Natural :=
              Ada.Strings.Fixed.Index (Response.all, CRLF & CRLF);
            Response_Document : String renames
              Response.all (Response_Marker + 4 .. Response.all'Last);
            Page : constant Metrics.Metrics_Configuration_Page :=
              Metrics.Parse_List (Response_Document, XML.Default_Limits);
            Token : constant String :=
              US.To_String (Page.Next_Continuation_Token.Value);
            Next_Response : constant Document_Access :=
              new String'
                (List_Get
                   (Budget_Bucket, "metrics",
                    "ListBucketMetricsConfigurations", Token,
                    Has_Continuation_Token => True));
            Next_Response_Marker : constant Natural :=
              Ada.Strings.Fixed.Index (Next_Response.all, CRLF & CRLF);
            Next_Response_Document : String renames
              Next_Response.all
                (Next_Response_Marker + 4 .. Next_Response.all'Last);
            Next_Page : constant Metrics.Metrics_Configuration_Page :=
              Metrics.Parse_List
                (Next_Response_Document, XML.Default_Limits);
         begin
            Require
              (Has (Response.all, "200 OK")
               and then Response_Marker > 0
               and then Response_Document'Length <= Document_Budget
               and then Page.Configurations.Length = 1
               and then Page.Is_Truncated
               and then Page.Next_Continuation_Token.Is_Set,
               "configuration listing did not reserve its XML envelope");
            Require
              (Next_Response_Marker > 0
               and then Next_Page.Configurations.Length = 1
               and then not Next_Page.Is_Truncated
               and then Next_Page.Continuation_Token.Is_Set
               and then
                 US.To_String (Next_Page.Continuation_Token.Value) = Token,
               "an empty-identifier cursor restarted the listing");
         end;
         Store.Delete_Bucket_Metrics_Configuration
           (Budget_Bucket, "", null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "first listing budget fixture cleanup failed");
         Store.Delete_Bucket_Metrics_Configuration
           (Budget_Bucket, "b", null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "second listing budget fixture cleanup failed");
         declare
            First_Length : constant Positive := Document_Budget / 2 - 1;
            Second_Length : constant Positive :=
              Document_Budget - 2 - First_Length;
            First_Document : constant Document_Access :=
              Sized_Document
                (Metrics_Prefix, Metrics_Suffix, First_Length, 'c');
            Second_Document : constant Document_Access :=
              Sized_Document
                (Metrics_Prefix, Metrics_Suffix, Second_Length, 'd');
            Large_Binary_ID : constant String :=
              'b' & Character'Val (0) & String'(1 .. 1_023 => 'x');
         begin
            Store.Put_Bucket_Metrics_Configuration
              (Budget_Bucket, Large_Binary_ID, First_Document.all, null,
               Ada.Real_Time.Time_Last, Result);
            Store.Put_Bucket_Metrics_Configuration
              (Budget_Bucket, "c", Second_Document.all, null,
               Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "large binary cursor fixtures were rejected");
            declare
               Response : constant Document_Access :=
                 new String'
                   (List_Get
                      (Budget_Bucket, "metrics",
                       "ListBucketMetricsConfigurations"));
               Marker : constant Natural :=
                 Ada.Strings.Fixed.Index (Response.all, CRLF & CRLF);
               Document : String renames
                 Response.all (Marker + 4 .. Response.all'Last);
               Page : constant Metrics.Metrics_Configuration_Page :=
                 Metrics.Parse_List (Document, XML.Default_Limits);
               Cursor : constant String :=
                 US.To_String (Page.Next_Continuation_Token.Value);
               Next_Response : constant Document_Access :=
                 new String'
                   (List_Get
                      (Budget_Bucket, "metrics",
                       "ListBucketMetricsConfigurations", Cursor,
                       Has_Continuation_Token => True));
               Next_Marker : constant Natural :=
                 Ada.Strings.Fixed.Index (Next_Response.all, CRLF & CRLF);
               Next_Document : String renames
                 Next_Response.all
                   (Next_Marker + 4 .. Next_Response.all'Last);
               Next_Page : constant Metrics.Metrics_Configuration_Page :=
                 Metrics.Parse_List (Next_Document, XML.Default_Limits);
            begin
               Require
                 (Marker > 0 and then Page.Configurations.Length = 1
                  and then Page.Is_Truncated and then Cursor'Length = 135
                  and then Next_Marker > 0
                  and then Next_Page.Configurations.Length = 1
                  and then not Next_Page.Is_Truncated,
                  "configuration cursor did not preserve a large binary id");
               Store.Delete_Bucket_Metrics_Configuration
                 (Budget_Bucket, Large_Binary_ID, null,
                  Ada.Real_Time.Time_Last, Result);
               Require
                 (Result = Flyology.Object_Storage.Success,
                  "configuration cursor marker deletion failed");
               Require
                 (Has
                    (List_Get
                       (Budget_Bucket, "metrics",
                        "ListBucketMetricsConfigurations", Cursor,
                        Has_Continuation_Token => True),
                     "<Code>InvalidArgument</Code>"),
                  "deleted marker did not invalidate configuration cursor");
            end;
            Store.Delete_Bucket_Metrics_Configuration
              (Budget_Bucket, "c", null, Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "large binary cursor fixture cleanup failed");
         end;
         declare
            Only_Document : constant Document_Access :=
              Sized_Document
                (Analytics_Prefix, Analytics_Suffix,
                 Document_Budget - 4, 'c');
            Response : US.Unbounded_String;
         begin
            Store.Put_Bucket_Analytics_Configuration
              (Budget_Bucket, "only", Only_Document.all, null,
               Ada.Real_Time.Time_Last, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "single over-envelope listing fixture was rejected");
            Response := US.To_Unbounded_String
              (List_Get
                 (Budget_Bucket, "analytics",
                  "ListBucketAnalyticsConfigurations"));
            Require
              (Has (US.To_String (Response), "500 Internal Server Error")
               and then Has
                 (US.To_String (Response), "<Code>InternalError</Code>")
               and then not Has
                 (US.To_String (Response), "<AnalyticsConfiguration"),
               "an over-envelope configuration produced a partial page");
         end;
         Store.Delete_Bucket
           (Budget_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "configuration listing budget bucket cleanup failed");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Analytics_Delete)),
            "204 No Content"),
         "DeleteBucketAnalyticsConfiguration failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Analytics_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "DeleteBucketAnalyticsConfiguration left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Analytics_Delete)),
            "204 No Content"),
         "DeleteBucketAnalyticsConfiguration was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Analytics_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketAnalyticsConfiguration confused bucket absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Metrics_Delete)),
            "204 No Content"),
         "DeleteBucketMetricsConfiguration failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Metrics_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "DeleteBucketMetricsConfiguration left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Metrics_Delete)),
            "204 No Content"),
         "DeleteBucketMetricsConfiguration was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Metrics_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketMetricsConfiguration confused bucket absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Intelligent_Tiering_Delete)),
            "204 No Content"),
         "DeleteBucketIntelligentTieringConfiguration failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Intelligent_Tiering_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "DeleteBucketIntelligentTieringConfiguration left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Intelligent_Tiering_Delete)),
            "204 No Content"),
         "DeleteBucketIntelligentTieringConfiguration was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Intelligent_Tiering_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketIntelligentTieringConfiguration confused bucket " &
         "absence");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Inventory_Delete)),
            "204 No Content"),
         "DeleteBucketInventoryConfiguration failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Inventory_Get)),
            "<Code>NoSuchConfiguration</Code>"),
         "DeleteBucketInventoryConfiguration left visible state");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Inventory_Delete)),
            "204 No Content"),
         "DeleteBucketInventoryConfiguration was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Inventory_Delete)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketInventoryConfiguration confused bucket absence");
   end;

   declare
      Put_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("policy", ""),
         SigV4.Pair ("x-id", "PutBucketPolicy"));
      Get_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("policy", ""),
         SigV4.Pair ("x-id", "GetBucketPolicy"));
      Delete_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("policy", ""),
         SigV4.Pair ("x-id", "DeleteBucketPolicy"));
      Status_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("policyStatus", ""),
         SigV4.Pair ("x-id", "GetBucketPolicyStatus"));
      First : constant String :=
        "{""Version"":""2012-10-17"",""Statement"":[]}";
      Second : constant String := "{""Statement"":[]}";
      Public_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*""}}";
      Fixed_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":{" &
        """AWS"":""arn:aws:iam::123456789012:role/reader""}," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*""}}";
      Conditioned_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""StringEquals"":{" &
        """aws:SourceVpc"":""vpc-12345678""}}}}";
      Role_Session_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""StringLike"":{" &
        """aws:userid"":""AROA12345678901234567:*""}}}}";
      Open_User_ID_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""StringLike"":{" &
        """aws:userid"":""user:*""}}}}";
      Invalid_IP_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""IpAddress"":{" &
        """aws:SourceIp"":""::::/32""}}}}";
      Mixed_Policy : constant String :=
        "{""Statement"":[{""Effect"":""Allow"",""Principal"":{" &
        """AWS"":""arn:aws:iam::123456789012:role/reader""}," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*""},{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/public/*""}]}";
      Wildcard_Deny_Policy : constant String :=
        "{""Statement"":{""Effect"":""Deny"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/private/*""}}";
      Duplicate_Condition_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""StringEquals"":{" &
        """aws:SourceVpc"":""vpc-12345678""},""StringEquals"":{" &
        """aws:SourceVpc"":""*""}}}}";
      Duplicate_Condition_Key_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""StringEquals"":{" &
        """aws:SourceVpc"":""vpc-12345678"",""aws:SourceVpc"":""*""}}}}";
      Narrow_IP_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""IpAddress"":{" &
        """aws:SourceIp"":""203.0.113.0/24""}}}}";
      Broad_IP_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""IpAddress"":{" &
        """aws:SourceIp"":""0.0.0.0/1""}}}}";
      Fixed_Access_Point_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""ArnLike"":{" &
        """s3:DataAccessPointArn"":""arn:aws:s3:us-west-2:" &
        "123456789012:accesspoint/*""}}}}";
      Open_Access_Point_Account_Policy : constant String :=
        "{""Statement"":{""Effect"":""Allow"",""Principal"":""*""," &
        """Action"":""s3:GetObject"",""Resource"":""arn:aws:s3:::" &
        "test-bucket/*"",""Condition"":{""ArnLike"":{" &
        """s3:DataAccessPointArn"":""arn:aws:s3:us-west-2:" &
        "*:accesspoint/*""}}}}";

      function Put
        (Document : String; Extra : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("PUT", "/test-bucket", Put_Query, Document,
               "content-md5: " & Content_MD5 (Document) & CRLF & Extra)));

      procedure Require_Status
        (Policy : String; Expected_Public : Boolean)
      is
         Response : constant String :=
           (if Has (Put (Policy), "200 OK")
            then Run
              (Signed_Query_Request ("GET", "/test-bucket", Status_Query))
            else "");
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Type: application/xml")
            and then Has
              (Response,
               "<IsPublic>" &
               (if Expected_Public then "true" else "false") &
               "</IsPublic>"),
            "GetBucketPolicyStatus returned the wrong assessment");
      end Require_Status;

      procedure Require_Malformed_Status (Policy : String) is
         Response : constant String :=
           (if Has (Put (Policy), "200 OK")
            then Run
              (Signed_Query_Request ("GET", "/test-bucket", Status_Query))
            else "");
      begin
         Require
           (Has (Response, "<Code>InternalError</Code>"),
            "GetBucketPolicyStatus accepted ambiguous policy members");
      end Require_Malformed_Status;
   begin
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query)),
            "<Code>NoSuchBucketPolicy</Code>"),
         "GetBucketPolicy did not distinguish an absent policy");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Status_Query)),
            "<Code>NoSuchBucketPolicy</Code>"),
         "GetBucketPolicyStatus did not distinguish an absent policy");
      Require
        (Has (Put (""), "200 OK"),
         "PutBucketPolicy rejected a present empty policy");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Status_Query)),
            "<Code>InternalError</Code>"),
         "GetBucketPolicyStatus accepted malformed persisted bytes");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Type: application/json")
            and then Response_Body (Response) = "",
            "GetBucketPolicy lost a present empty policy");
      end;
      Require
        (Has
           (Put
              (First,
               "x-amz-confirm-remove-self-bucket-access: true" & CRLF),
            "200 OK"),
         "PutBucketPolicy rejected a valid policy");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Response_Body (Response) = First,
            "GetBucketPolicy did not preserve exact policy bytes");
      end;
      Require_Status (Public_Policy, True);
      Require_Status (Fixed_Policy, False);
      Require_Status (Conditioned_Policy, False);
      Require_Status (Role_Session_Policy, True);
      Require_Status (Open_User_ID_Policy, True);
      Require_Status (Invalid_IP_Policy, True);
      Require_Status (Narrow_IP_Policy, False);
      Require_Status (Broad_IP_Policy, True);
      Require_Status (Fixed_Access_Point_Policy, False);
      Require_Status (Open_Access_Point_Account_Policy, True);
      Require_Status (Mixed_Policy, True);
      Require_Status (Wildcard_Deny_Policy, False);
      Require_Malformed_Status (Duplicate_Condition_Policy);
      Require_Malformed_Status (Duplicate_Condition_Key_Policy);
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Status_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketPolicyStatus ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("policyStatus", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketPolicyStatus accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Status_Query, "unexpected")),
            "400 Bad Request"),
         "GetBucketPolicyStatus accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Status_Query,
                  "x-amz-request-payer", "requester")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketPolicyStatus accepted non-modeled RequestPayer");
      Require
        (Has (Put (First), "200 OK"),
         "PutBucketPolicy did not restore the policy fixture");
      for Algorithm in Checksum_Policy.Algorithm loop
         declare
            Response : constant String :=
              Put
                (Second,
                 "x-amz-sdk-checksum-algorithm: " &
                 Checksum_Policy.Wire_Name (Algorithm) & CRLF &
                 Checksum_Header (Algorithm) & ": " &
                 Checksum_Value (Algorithm, Second) & CRLF);
         begin
            Require
              (Has (Response, "200 OK"),
               "PutBucketPolicy rejected checksum " &
               Checksum_Policy.Wire_Name (Algorithm) & ": " & Response);
         end;
      end loop;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Query, First)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketPolicy accepted a missing Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket", Put_Query, First,
                  "content-md5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutBucketPolicy accepted a mismatched Content-MD5");
      Require
        (Has
           (Put
              (First,
               "x-amz-confirm-remove-self-bucket-access: yes" & CRLF),
            "<Code>InvalidArgument</Code>"),
         "PutBucketPolicy accepted an invalid self-access confirmation");
      Require
        (Has
           (Put (First, "x-amz-request-payer: requester" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "PutBucketPolicy accepted non-modeled RequestPayer");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Get_Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetBucketPolicy ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket",
                  (SigV4.Pair ("policy", ""),
                   SigV4.Pair ("unexpected", "1")))),
            "400 Bad Request"),
         "GetBucketPolicy accepted an extra query member");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket", Get_Query, "unexpected")),
            "400 Bad Request"),
         "GetBucketPolicy accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeleteBucketPolicy failed");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Get_Query)),
            "NoSuchBucketPolicy"),
         "DeleteBucketPolicy left a visible policy");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket", Delete_Query)),
            "204 No Content"),
         "DeleteBucketPolicy was not idempotent");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/absent-bucket", Delete_Query)),
            "<Code>NoSuchBucket</Code>"),
         "DeleteBucketPolicy did not distinguish an absent bucket");
   end;

   declare
      use Flyology.Object_Storage;
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versioning", ""));
      Enabled_Document : constant String :=
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Status>Enabled</Status></VersioningConfiguration>";
      Suspended_Document : constant String :=
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Status>Suspended</Status>" &
        "</VersioningConfiguration>";
      MFA_Document : constant String :=
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<MfaDelete>Enabled</MfaDelete>" &
        "<Status>Enabled</Status></VersioningConfiguration>";
      Empty_Document : constant String :=
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/""/>";
   begin
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/versioning-bucket", "")),
            "200 OK"),
         "versioning corpus bucket creation failed");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/versioning-bucket", Query));
         Value : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then
              Value.Status =
                Flyology.Object_Storage.Versioning_Unconfigured,
            "GetBucketVersioning did not preserve initial absence");
      end;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Empty_Document, Content_MD5 (Empty_Document))),
            "200 OK"),
         "PutBucketVersioning rejected an empty optional configuration");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/versioning-bucket", Query));
         Value : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse_Response (Response_Body (Response));
      begin
         Require
           (Value.Status = Flyology.Object_Storage.Versioning_Unconfigured,
            "empty versioning update changed configured state");
      end;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document))),
            "200 OK"),
         "PutBucketVersioning rejected enabled status");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/versioning-bucket", Query,
                 "x-amz-expected-bucket-owner", "test-principal"));
         Value : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then
              Value.Status = Flyology.Object_Storage.Versioning_Enabled,
            "GetBucketVersioning did not return enabled status");
      end;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document)),
               1),
            "200 OK"),
         "fragmented PutBucketVersioning did not suspend status");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/versioning-bucket", Query));
         Value : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse (Response_Body (Response));
      begin
         Require
           (Value.Status = Flyology.Object_Storage.Versioning_Suspended,
            "suspended versioning configuration was not visible");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/versioning-bucket", Query,
                  Enabled_Document)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketVersioning accepted a missing Content-MD5");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 ("different document"))),
            "<Code>BadDigest</Code>"),
         "PutBucketVersioning accepted a mismatched Content-MD5");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, String'(1 .. 24 => 'A'))),
            "<Code>InvalidRequest</Code>"),
         "PutBucketVersioning accepted malformed Content-MD5 syntax");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 ("<malformed", Content_MD5 ("different document"))),
            "<Code>BadDigest</Code>"),
         "PutBucketVersioning parsed unverified body bytes");
      declare
         Malformed : constant String :=
           "<VersioningConfiguration xmlns=""" &
           "http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<Status>Disabled</Status>" &
           "</VersioningConfiguration>";
         Response : constant String :=
           Run
             (Signed_Versioning_Request
                (Malformed, Content_MD5 (Malformed)));
      begin
         if not Has (Response, "<Code>MalformedXML</Code>") then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "unexpected invalid-versioning response: " & Response);
         end if;
         Require
           (Has (Response, "<Code>MalformedXML</Code>"),
            "PutBucketVersioning accepted an invalid status");
      end;
      declare
         Foreign_Namespace : constant String :=
           "<VersioningConfiguration xmlns=""urn:foreign"">" &
           "<Status>Enabled</Status></VersioningConfiguration>";
         Attributed : constant String :=
           "<VersioningConfiguration xmlns=""" &
           "http://s3.amazonaws.com/doc/2006-03-01/"" extra=""x"">" &
           "<Status>Enabled</Status></VersioningConfiguration>";
      begin
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Foreign_Namespace, Content_MD5 (Foreign_Namespace))),
               "<Code>MalformedXML</Code>"),
            "PutBucketVersioning accepted a foreign namespace");
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Attributed, Content_MD5 (Attributed))),
               "<Code>MalformedXML</Code>"),
            "PutBucketVersioning accepted an element attribute");
      end;
      declare
         Oversized : constant String :=
           String'(1 .. Versioning.Maximum_Document_Bytes + 1 => 'x');
      begin
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Oversized, Content_MD5 (Oversized))),
               "<Code>EntityTooLarge</Code>"),
            "PutBucketVersioning accepted an oversized document");
      end;
      declare
         Calls : constant Natural := MFA_Policy.Calls;
      begin
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Enabled_Document, Content_MD5 (Enabled_Document),
                     MFA => "device 123456")),
               "<Code>InvalidRequest</Code>"),
            "PutBucketVersioning accepted MFA over cleartext HTTP");
         Require
           (MFA_Policy.Calls = Calls,
            "insecure MFA credential reached the verifier");
      end;
      declare
         Calls : constant Natural := MFA_Policy.Calls;
         Overlong : constant String
           (1 .. MFA.Maximum_Credential_Bytes + 1) := (others => 'x');
      begin
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Enabled_Document, Content_MD5 (Enabled_Document),
                     MFA => Overlong),
                  Scheme => Flyology.HTTP.Secure_HTTPS),
               "<Code>AccessDenied</Code>"),
            "PutBucketVersioning accepted an overlong MFA credential");
         Require
           (MFA_Policy.Calls = Calls,
            "overlong MFA credential reached the verifier");
      end;
      declare
         Calls : constant Natural := MFA_Policy.Calls;
         Response : constant String :=
           Run
             (Signed_Versioning_Request
                (Enabled_Document, Content_MD5 (Enabled_Document),
                 MFA => "device 123456",
                 Duplicate_MFA => "device 123456"),
              Scheme => Flyology.HTTP.Secure_HTTPS);
      begin
         Require
           (Has (Response, "<Code>InvalidRequest</Code>"),
            "PutBucketVersioning accepted duplicate MFA headers: " &
            Response);
         Require
           (MFA_Policy.Calls = Calls,
            "duplicate MFA headers reached the verifier");
      end;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (MFA_Document, Content_MD5 (MFA_Document),
                  MFA => "device 123456"),
             Scheme => Flyology.HTTP.Secure_HTTPS),
            "200 OK"),
         "PutBucketVersioning rejected verified root MFA Delete enable");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/versioning-bucket", Query));
         Value : constant Bucket_Versioning_Configuration :=
           Versioning.Parse_Response (Response_Body (Response));
      begin
         Require
           (Value.Status = Versioning_Enabled
            and then Value.MFA_Delete = MFA_Delete_Enabled,
            "GetBucketVersioning lost verified MFA Delete state");
      end;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document))),
            "<Code>AccessDenied</Code>"),
         "MFA-enabled versioning changed without a credential");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document),
                  MFA => "device 000000"),
             Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "MFA-enabled versioning accepted an invalid credential");
      MFA_Policy.Mode := MFA_Reject_Root;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document),
                  MFA => "device 123456"),
             Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "PutBucketVersioning treated an authenticated non-root as owner");
      MFA_Policy.Mode := MFA_Unavailable;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document),
                  MFA => "device 123456"),
             Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "PutBucketVersioning did not fail closed without an MFA verifier");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document),
                  MFA => "device 123456"),
             Scheme => Flyology.HTTP.Secure_HTTPS,
             Use_Null_MFA => True),
            "<Code>AccessDenied</Code>"),
         "null MFA verifier configuration did not fail closed");
      MFA_Policy.Mode := MFA_Raise;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Suspended_Document, Content_MD5 (Suspended_Document),
                  MFA => "device 123456"),
             Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "PutBucketVersioning exposed an MFA verifier exception");
      MFA_Policy.Mode := MFA_Allow_Root;
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/versioning-bucket", Query));
         Value : constant Bucket_Versioning_Configuration :=
           Versioning.Parse_Response (Response_Body (Response));
      begin
         Require
           (Value.Status = Versioning_Enabled
            and then Value.MFA_Delete = MFA_Delete_Enabled,
            "rejected MFA requests changed versioning configuration");
      end;
      declare
         MFA_Only_Document : constant String :=
           "<VersioningConfiguration xmlns=""" &
           "http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<MfaDelete>Disabled</MfaDelete>" &
           "</VersioningConfiguration>";
      begin
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (MFA_Only_Document, Content_MD5 (MFA_Only_Document),
                     MFA => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
               "<Code>InvalidRequest</Code>"),
            "PutBucketVersioning accepted MfaDelete without Status");
      end;
      declare
         Disable_Document : constant String :=
           "<VersioningConfiguration xmlns=""" &
           "http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<MfaDelete>Disabled</MfaDelete>" &
           "<Status>Suspended</Status></VersioningConfiguration>";
      begin
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Disable_Document, Content_MD5 (Disable_Document),
                     MFA => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
               "200 OK"),
            "PutBucketVersioning rejected verified MFA Delete disable");
      end;
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document))),
            "200 OK"),
         "disabled MFA Delete still required a credential");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document),
                  Checksum => "CRC32")),
            "<Code>InvalidRequest</Code>"),
         "PutBucketVersioning accepted an SDK algorithm without a value");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document),
                  Checksum_Value => "AAAAAA==")),
            "<Code>BadDigest</Code>"),
         "PutBucketVersioning accepted a mismatched checksum value");
      for Algorithm in Checksum_Policy.Algorithm loop
         Require
           (Has
              (Run
                 (Signed_Versioning_Request
                    (Enabled_Document, Content_MD5 (Enabled_Document),
                     Checksum => Checksum_Policy.Wire_Name (Algorithm),
                     Checksum_Value =>
                       Checksum_Value (Algorithm, Enabled_Document),
                     Checksum_Value_Algorithm => Algorithm)),
               "200 OK"),
            "PutBucketVersioning rejected " &
            Checksum_Policy.Wire_Name (Algorithm));
      end loop;
      Require
        (Has
           (Run
              (Signed_Versioning_Trailer_Request
                 (Enabled_Document, Core.SHA256,
                  Checksum_Value (Core.SHA256, Enabled_Document))),
            "200 OK"),
         "PutBucketVersioning rejected a physical checksum trailer");
      Require
        (Has
           (Run
              (Signed_Versioning_Trailer_Request
                 (Enabled_Document, Core.SHA256,
                  Checksum_Value (Core.SHA256, "different document"))),
            "<Code>BadDigest</Code>"),
         "PutBucketVersioning accepted a mismatched checksum trailer");
      Require
        (Has
           (Run
              (Signed_Versioning_Trailer_Request
                 (Enabled_Document, Core.SHA256,
                  Checksum_Value (Core.SHA256, Enabled_Document),
                  Include_Trailer => False)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketVersioning accepted a missing declared trailer");
      Require
        (Has
           (Run
              (Signed_Versioning_Trailer_Request
                 (Enabled_Document, Core.SHA256,
                  Checksum_Value (Core.SHA256, Enabled_Document),
                  Duplicate => True)),
            "<Code>InvalidRequest</Code>"),
         "PutBucketVersioning accepted a duplicate physical trailer");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document),
                  Checksum => "SHA256",
                  Checksum_Value =>
                    Checksum_Value (Core.CRC32, Enabled_Document))),
            "200 OK"),
         "PutBucketVersioning did not give an individual checksum " &
         "precedence over the SDK selector");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document),
                  Checksum => "sha256",
                  Checksum_Value =>
                    Checksum_Value (Core.CRC32, Enabled_Document))),
            "<Code>InvalidRequest</Code>"),
         "PutBucketVersioning accepted an invalid checksum algorithm");
      Require
        (Has
           (Run
              (Signed_Versioning_Request
                 (Enabled_Document, Content_MD5 (Enabled_Document),
                  Owner => "different-owner")),
            "403 Forbidden"),
         "PutBucketVersioning ignored expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/versioning-bucket",
                  (SigV4.Pair ("versioning", ""),
                   SigV4.Pair ("versioning", "")))),
            "<Code>InvalidArgument</Code>"),
         "GetBucketVersioning accepted duplicate subresources");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/versioning-bucket",
                  (SigV4.Pair ("versioning", ""),
                   SigV4.Pair ("x-id", "PutBucketVersioning")))),
            "<Code>InvalidArgument</Code>"),
         "GetBucketVersioning accepted a mismatched operation ID");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/versioning-bucket",
                  (1 => SigV4.Pair ("versioning", "bogus")))),
            "<Code>InvalidArgument</Code>"),
         "GetBucketVersioning accepted a nonempty subresource value");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/versioning-bucket", Query, "unexpected")),
            "<Code>InvalidRequest</Code>"),
         "GetBucketVersioning accepted a request body");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/absent-bucket", Query)),
            "<Code>NoSuchBucket</Code>"),
         "GetBucketVersioning did not classify a missing bucket");
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("DELETE", "/versioning-bucket")),
            "204 No Content"),
         "versioning corpus bucket cleanup failed");
   end;

   declare
      Payload : constant String := "trailer put";
   begin
      for Algorithm in Checksum_Policy.Algorithm loop
         declare
            Digest : constant String := Checksum_Value (Algorithm, Payload);
            Response : constant String := Run
              (Signed_Put_Object_Trailer_Request
                 ("/test-bucket/put-trailer", Payload, Algorithm, Digest),
               Receive_Max => 1);
         begin
            Require
              (Has (Response, "200 OK")
               and then Has
                 (Response, Checksum_Header (Algorithm) & ": " & Digest &
                    CRLF),
               "PutObject physical trailer checksum " &
                 Checksum_Policy.Wire_Name (Algorithm) & ": " & Response);
         end;
      end loop;
      declare
         Info : Flyology.Object_Storage.Object_Information;
         Head_Status : Flyology.Object_Storage.Status;
         Missing : constant String := Run
           (Signed_Put_Object_Trailer_Request
              ("/test-bucket/put-trailer", "bad", Core.SHA256,
               Checksum_Value (Core.SHA256, "bad"),
               Include_Trailer => False));
         Duplicate : constant String := Run
           (Signed_Put_Object_Trailer_Request
              ("/test-bucket/put-trailer", "bad", Core.SHA256,
               Checksum_Value (Core.SHA256, "bad"), Duplicate => True));
         Mismatch : constant String := Run
           (Signed_Put_Object_Trailer_Request
              ("/test-bucket/put-trailer", "bad", Core.SHA256,
               Checksum_Value (Core.SHA256, Payload)));
         Observed : constant String := Run
           (Signed_Request ("GET", "/test-bucket/put-trailer", ""));
      begin
         Store.Head_Object
           ("test-bucket", "put-trailer", null, Ada.Real_Time.Time_Last,
            Info, Head_Status);
         Require
           (Has (Missing, "400 Bad Request")
            and then Has (Duplicate, "400 Bad Request")
            and then Has (Mismatch, "<Code>BadDigest</Code>")
            and then Response_Body (Observed) = Payload
            and then Head_Status = Flyology.Object_Storage.Success
            and then not Info.Metadata.Content_Encoding.Is_Set,
            "invalid PutObject physical trailer mutated the object");
         declare
            Cleanup : constant String := Run
              (Signed_Request ("DELETE", "/test-bucket/put-trailer", ""));
         begin
            Require
              (Has (Cleanup, "204 No Content"),
               "PutObject trailer cleanup failed");
         end;
      end;
   end;

   declare
      Payload : constant String := "bad";
      Trailer_Headers : constant String :=
        "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
        "x-amz-trailer: x-amz-checksum-crc32" & CRLF;
      Decoded_Without_Encoding : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers =>
              "x-amz-decoded-content-length: 3" & CRLF,
            Chunked => True));
      Duplicate_Encoding : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers =>
              "Content-Encoding: aws-chunked, aws-chunked" & CRLF &
              "x-amz-decoded-content-length: 3" & CRLF & Trailer_Headers,
            Chunked => True));
      Missing_Decoded : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers => "Content-Encoding: aws-chunked" & CRLF &
              Trailer_Headers,
            Chunked => True));
      Missing_Trailer : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers => "Content-Encoding: aws-chunked" & CRLF &
              "x-amz-decoded-content-length: 3" & CRLF,
            Chunked => True));
      Malformed_Decoded : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers => "Content-Encoding: aws-chunked" & CRLF &
              "x-amz-decoded-content-length: 3x" & CRLF & Trailer_Headers,
            Chunked => True));
      Exact_Limit : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers => "Content-Encoding: aws-chunked" & CRLF &
              "x-amz-decoded-content-length: 5368709120" & CRLF &
              Trailer_Headers,
            Chunked => True));
      Over_Limit : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers => "Content-Encoding: aws-chunked" & CRLF &
              "x-amz-decoded-content-length: 5368709121" & CRLF &
              Trailer_Headers,
            Chunked => True));
      Inner_AWS_Frames : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-trailer-invalid", Payload,
            Extra_Headers => "Content-Encoding: aws-chunked" & CRLF &
              "x-amz-decoded-content-length: 3" & CRLF & Trailer_Headers));
      Malformed_Chunk : constant String := Run
        (Signed_Malformed_Chunk_Put_Request
           ("/test-bucket/put-trailer-invalid", Payload));
      Undeclared_Trailer : constant String := Run
        (Signed_Undeclared_Trailer_Put_Request
           ("/test-bucket/put-trailer-invalid", Payload));
      Observed : constant String := Run
        (Signed_Request ("GET", "/test-bucket/put-trailer-invalid", ""));
   begin
      Require
        (Has (Decoded_Without_Encoding, "<Code>InvalidRequest</Code>"),
         "PutObject accepted decoded length without aws-chunked: " &
           Decoded_Without_Encoding);
      Require
        (Has (Duplicate_Encoding, "<Code>InvalidArgument</Code>"),
         "PutObject accepted duplicate aws-chunked: " & Duplicate_Encoding);
      Require
        (Has (Missing_Decoded, "<Code>InvalidRequest</Code>"),
         "PutObject accepted aws-chunked without decoded length: " &
           Missing_Decoded);
      Require
        (Has (Missing_Trailer, "<Code>InvalidRequest</Code>"),
         "PutObject accepted aws-chunked without checksum trailer: " &
           Missing_Trailer);
      Require
        (Has (Malformed_Decoded, "<Code>InvalidArgument</Code>"),
         "PutObject accepted malformed decoded length: " & Malformed_Decoded);
      Require
        (Has (Exact_Limit, "501 Not Implemented")
         and then not Has (Exact_Limit, "<Code>EntityTooLarge</Code>"),
         "PutObject did not validate then reject exact-limit aws-chunked: " &
           Exact_Limit);
      Require
        (Has (Over_Limit, "<Code>EntityTooLarge</Code>"),
         "PutObject accepted decoded limit plus one: " & Over_Limit);
      Require
        (Has (Inner_AWS_Frames, "501 Not Implemented"),
         "PutObject accepted undecoded inner aws-chunked frames: " &
           Inner_AWS_Frames);
      Require
        (Has (Malformed_Chunk, "<Code>InvalidRequest</Code>"),
         "PutObject did not map malformed chunk framing to InvalidRequest: " &
           Malformed_Chunk);
      Require
        (Has (Undeclared_Trailer, "<Code>InvalidRequest</Code>"),
         "PutObject accepted an undeclared physical trailer: " &
           Undeclared_Trailer);
      Require
        (Has (Observed, "404 Not Found"),
         "rejected aws-chunked PutObject published an object: " & Observed);
   end;

   for Name of Listing_Buckets loop
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/" & US.To_String (Name), "")),
            "200 OK"),
         "ListBuckets setup create failed");
   end loop;

   declare
      Response : constant String := Run (Signed_Request ("GET", "/", ""));
      Page : constant Buckets.List_Buckets_Result :=
        Buckets.Parse_List_Buckets (Response_Body (Response));
      Optional_Metadata_Leaked : Boolean := False;
   begin
      for Item of Page.Buckets loop
         Optional_Metadata_Leaked := Optional_Metadata_Leaked
           or else US.Length (Item.Bucket_Region) > 0
           or else US.Length (Item.Bucket_ARN) > 0;
      end loop;
      Require
        (Has (Response, "200 OK")
         and then not Optional_Metadata_Leaked,
         "unpaginated ListBuckets invented optional bucket metadata");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("continuation-token", ""),
         SigV4.Pair ("max-buckets", "1"),
         SigV4.Pair ("prefix", ""));
      Response : constant String :=
        Run (Signed_Query_Request ("GET", "/", Query));
      Page : constant Buckets.List_Buckets_Result :=
        Buckets.Parse_List_Buckets (Response_Body (Response));
   begin
      Require
        (Has (Response, "200 OK")
         and then Page.Has_Prefix
         and then US.Length (Page.Prefix) = 0
         and then Page.Buckets.Length = 1
         and then US.Length
           (Page.Buckets.First_Element.Bucket_Region) > 0,
         "ListBuckets lost present empty pagination members");
   end;

   declare
      First_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("max-buckets", "1"),
         SigV4.Pair ("prefix", "list-"),
         SigV4.Pair ("bucket-region", Region),
         SigV4.Pair ("x-id", "ListBuckets"));
      First_Response : constant String :=
        Run (Signed_Query_Request ("GET", "/", First_Query));
      First_Page : constant Buckets.List_Buckets_Result :=
        Buckets.Parse_List_Buckets (Response_Body (First_Response));
   begin
      Require
        (Has (First_Response, "200 OK")
         and then First_Page.Has_Owner
         and then US.To_String (First_Page.Owner.ID) = "test-principal"
         and then First_Page.Buckets.Length = 1
         and then US.To_String (First_Page.Buckets.First_Element.Name) =
           "list-alpha-bucket"
         and then US.Length
           (First_Page.Buckets.First_Element.Creation_Date) > 0
         and then US.To_String
           (First_Page.Buckets.First_Element.Bucket_Region) = Region
         and then US.Length (First_Page.Continuation_Token) > 0,
         "ListBuckets first page metadata mismatch");

      declare
         Next_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("max-buckets", "1"),
            SigV4.Pair ("prefix", "list-"),
            SigV4.Pair ("bucket-region", Region),
            SigV4.Pair
              ("continuation-token",
               US.To_String (First_Page.Continuation_Token)));
         Next_Response : constant String :=
           Run (Signed_Query_Request ("GET", "/", Next_Query));
         Next_Page : constant Buckets.List_Buckets_Result :=
           Buckets.Parse_List_Buckets (Response_Body (Next_Response));
      begin
         Require
           (Next_Page.Buckets.Length = 1
            and then US.To_String (Next_Page.Buckets.First_Element.Name) =
              "list-zeta-bucket"
            and then US.Length (Next_Page.Continuation_Token) = 0,
            "ListBuckets continuation page mismatch");
      end;

      declare
         Rebound_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("prefix", "other-"),
            SigV4.Pair
              ("continuation-token",
               US.To_String (First_Page.Continuation_Token)));
      begin
         Require
           (Has
              (Run (Signed_Query_Request ("GET", "/", Rebound_Query)),
               "400 Bad Request"),
            "ListBuckets token was not bound to its prefix");
      end;
   end;

   declare
      Duplicate : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("max-buckets", "1"),
         SigV4.Pair ("max-buckets", "2"));
      Other_Region : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("bucket-region", "us-west-2"));
      Oversized_Token : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair
           ("continuation-token", String'(1 .. 1_025 => 't')));
      Region_Response : constant String :=
        Run (Signed_Query_Request ("GET", "/", Other_Region));
      Region_Page : constant Buckets.List_Buckets_Result :=
        Buckets.Parse_List_Buckets (Response_Body (Region_Response));
   begin
      Require
        (Has (Run (Signed_Query_Request ("GET", "/", Duplicate)),
              "400 Bad Request"),
         "duplicate ListBuckets parameter was accepted");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Oversized_Token)),
            "400 Bad Request"),
         "oversized ListBuckets token was accepted");
      Require
        (Has (Region_Response, "200 OK")
         and then Region_Page.Buckets.Is_Empty,
         "ListBuckets region filter leaked another region");
      Require
        (Has (Run (Signed_Request ("GET", "/", "unexpected")),
              "400 Bad Request"),
         "ListBuckets accepted a request body");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("max-directory-buckets", "1"));
      Response : constant String :=
        Run (Signed_Query_Request ("GET", "/", Query));
      Page : constant Buckets.List_Buckets_Result :=
        Generated_Directory_Buckets.Parse
          (Response_Body (Response), XML.Default_Limits, 1);
      Explicit_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("x-id", "ListDirectoryBuckets"));
      Continuation_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("continuation-token", "not-issued"),
         SigV4.Pair ("max-directory-buckets", "1"));
      Duplicate_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("max-directory-buckets", "1"),
         SigV4.Pair ("max-directory-buckets", "2"));
      Malformed_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("max-directory-buckets", "1x"));
      Zero_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("max-directory-buckets", "0"));
      Over_Maximum_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("max-directory-buckets", "1001"));
      Unknown_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("max-directory-buckets", "1"),
         SigV4.Pair ("unexpected", "value"));
   begin
      Require
        (Has (Response, "200 OK")
         and then Page.Buckets.Is_Empty
         and then not Has (Response, "list-alpha-bucket")
         and then not Has (Response, "list-zeta-bucket"),
         "ListDirectoryBuckets leaked general-purpose buckets");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Explicit_Query)),
            "200 OK"),
         "explicit ListDirectoryBuckets operation ID was rejected");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Continuation_Query)),
            "400 Bad Request"),
         "ListDirectoryBuckets accepted an unissued continuation token");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Duplicate_Query)),
            "400 Bad Request"),
         "ListDirectoryBuckets accepted a duplicate maximum");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Malformed_Query)),
            "400 Bad Request"),
         "ListDirectoryBuckets accepted a malformed maximum");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Zero_Query)),
            "200 OK"),
         "ListDirectoryBuckets rejected the modeled zero maximum");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Over_Maximum_Query)),
            "400 Bad Request"),
         "ListDirectoryBuckets accepted a maximum above the model bound");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/", Unknown_Query)),
            "400 Bad Request"),
         "ListDirectoryBuckets accepted an unknown parameter");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/", Query, "unexpected")),
            "400 Bad Request"),
         "ListDirectoryBuckets accepted a request body");
   end;

   Check_Cancellation_Propagation;
   Check_Deadline_Propagation;
   Check_Create_Multipart_Admission;
   Check_Multipart_Server;

   declare
      Response : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/object", "hello world",
            Extra_Headers => "Content-Type: text/plain" & CRLF,
            Expect => True),
         Receive_Max => 2);
   begin
      Require (Has (Response, "100 Continue"),
               "authenticated Expect request was not admitted");
      Require (Has (Response, "200 OK"), "PutObject failed");
      Require
        (Has (Response, "ETag: ""5eb63bbbe01eeed093cb22bb8f5acdc3""")
         and then Has
           (Response, "x-amz-checksum-crc64nvme: " &
              Checksum_Value (Core.CRC64NVME, "hello world") & CRLF)
         and then Has
           (Response, "x-amz-checksum-type: FULL_OBJECT" & CRLF)
         and then Has (Response, "x-amz-object-size: 11" & CRLF),
         "PutObject ETag mismatch");
   end;

   declare
      Document : constant String :=
        "<RestoreRequest><Days>1</Days></RestoreRequest>";
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("restore", ""),
         SigV4.Pair ("x-id", "RestoreObject"));

      function Restore
        (Target : String := "/test-bucket/object";
         Request_Query : SigV4.Name_Value_Array := Query;
         Payload : String := Document;
         Extra : String := "") return String is
        (Run
           (Signed_Query_Body_Request
              ("POST", Target, Request_Query, Payload, Extra)));
   begin
      declare
         Response : constant String := Restore;
      begin
         Require
           (Has (Response, "403 Forbidden")
            and then Has
              (Response, "<Code>ObjectAlreadyInActiveTierError</Code>"),
            "RestoreObject did not reject an active-tier object");
      end;
      Require
        (Has
           (Restore
              (Request_Query =>
                 (SigV4.Pair ("restore", ""),
                  SigV4.Pair ("versionId", "null"),
                  SigV4.Pair ("x-id", "RestoreObject"))),
            "<Code>ObjectAlreadyInActiveTierError</Code>"),
         "RestoreObject did not bind the selected null generation");
      declare
         Response : constant String :=
           Restore
             (Request_Query =>
                (SigV4.Pair ("restore", ""),
                 SigV4.Pair ("versionId", "missing-version"),
                 SigV4.Pair ("x-id", "RestoreObject")));
      begin
         Require
           (Has (Response, "404 Not Found")
            and then Has (Response, "<Code>NoSuchVersion</Code>"),
            "RestoreObject did not distinguish a missing version");
      end;
      Require
        (Has
           (Restore (Target => "/test-bucket/missing-object"),
            "<Code>NoSuchKey</Code>"),
         "RestoreObject did not distinguish a missing key");
      Require
        (Has
           (Restore (Target => "/absent-bucket/object"),
            "<Code>NoSuchBucket</Code>"),
         "RestoreObject did not distinguish a missing bucket");
      declare
         Response : constant String :=
           Restore
             (Extra =>
                "x-amz-expected-bucket-owner: different-owner" & CRLF);
      begin
         Require
           (Has (Response, "<Code>AccessDenied</Code>")
            and then not Has
              (Response, "<Code>ObjectAlreadyInActiveTierError</Code>"),
            "RestoreObject ignored the expected bucket owner");
      end;
      Require
        (Has
           (Restore
              (Extra => "x-amz-request-payer: invalid" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "RestoreObject accepted an invalid request payer");
      declare
         Response : constant String :=
           Restore (Extra => "x-amz-request-payer: requester" & CRLF);
      begin
         Require
           (Has (Response, "<Code>ObjectAlreadyInActiveTierError</Code>")
            and then not Has (Response, "x-amz-request-charged:"),
            "RestoreObject emitted a success-only charged header on " &
            "rejection");
      end;
      Require
        (Has
           (Restore
              (Extra =>
                 "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                 "x-amz-checksum-sha256: " &
                 Checksum_Value (Core.SHA256, Document) & CRLF),
            "<Code>ObjectAlreadyInActiveTierError</Code>"),
         "RestoreObject rejected a matching request checksum");
      Require
        (Has
           (Restore
              (Extra =>
                 "x-amz-sdk-checksum-algorithm: SHA1" & CRLF &
                 "x-amz-checksum-sha256: " &
                 Checksum_Value (Core.SHA256, Document) & CRLF),
            "<Code>ObjectAlreadyInActiveTierError</Code>"),
         "RestoreObject did not prefer the individual checksum");
      Require
        (Has
           (Restore
              (Extra =>
                 "x-amz-checksum-sha256: " &
                 Checksum_Value (Core.SHA256, "different") & CRLF),
            "<Code>BadDigest</Code>"),
         "RestoreObject accepted a mismatched individual checksum");
      Require
        (Has
           (Restore (Extra => "content-md5: malformed" & CRLF),
            "<Code>InvalidDigest</Code>"),
         "RestoreObject accepted a malformed Content-MD5");
      Require
        (Has
           (Restore
              (Extra =>
                 "content-md5: " & Content_MD5 ("different") & CRLF),
            "<Code>BadDigest</Code>"),
         "RestoreObject accepted a mismatched Content-MD5");
      Require
        (Has
           (Restore (Payload => "<"),
            "<Code>MalformedXML</Code>"),
         "RestoreObject accepted malformed XML");
      Require
        (Has
           (Restore
              (Payload =>
                 "<RestoreRequest><Type>SELECT</Type>" &
                 "<Days>1</Days></RestoreRequest>"),
            "<Code>MalformedXML</Code>"),
         "RestoreObject accepted an unsupported Select request");
      Require
        (Has
           (Restore
              (Payload =>
                 "<RestoreRequest xmlns=""http://s3.amazonaws.com/doc/" &
                 "2006-03-01/""><Days xmlns="""">1</Days>" &
                 "</RestoreRequest>"),
            "<Code>MalformedXML</Code>"),
         "RestoreObject accepted mixed XML namespaces");
      Require
        (Has
           (Restore
              (Payload =>
                 "<RestoreRequest><GlacierJobParameters>" &
                 "<Tier>Standard</Tier></GlacierJobParameters>" &
                 "</RestoreRequest>"),
            "<Code>MalformedXML</Code>"),
         "RestoreObject accepted GlacierJobParameters without Days");
      Require
        (Has
           (Restore
              (Payload =>
                 "<RestoreRequest><Tier>Standard</Tier></RestoreRequest>"),
            "<Code>ObjectAlreadyInActiveTierError</Code>"),
         "RestoreObject rejected a valid Tier-only request");
      Require
        (Has
           (Restore (Payload => "<RestoreRequest/>"),
            "<Code>ObjectAlreadyInActiveTierError</Code>"),
         "RestoreObject rejected a valid empty request");
      Require
        (Has
           (Restore
              (Extra =>
                 "x-amz-expected-bucket-owner: test-principal" & CRLF &
                 "x-amz-expected-bucket-owner: test-principal" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "RestoreObject accepted duplicate expected-owner headers");
      Require
        (Has
           (Restore
              (Request_Query =>
                 (SigV4.Pair ("restore", ""),
                  SigV4.Pair ("restore", ""))),
            "<Code>InvalidArgument</Code>"),
         "RestoreObject accepted a duplicate restore query");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("POST", "/test-bucket/object", Query, "")),
            "<Code>InvalidRequest</Code>"),
         "RestoreObject accepted an empty request body");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("attributes", ""),
         SigV4.Pair ("x-id", "GetObjectAttributes"));
      procedure Reject_Control
        (Headers : String;
         Code    : String;
         Label   : String;
         Scheme  : Flyology.HTTP.Origin_Scheme := Flyology.HTTP.Plain_HTTP)
      is
         Value : constant String := Run
           (Signed_Query_Body_Request
              ("GET", "/test-bucket/object", Query, "",
               "x-amz-object-attributes: ObjectSize" & CRLF & Headers),
            Scheme => Scheme);
      begin
         Require
           (not Has (Value, "200 OK")
            and then Has (Value, "<Code>" & Code & "</Code>"),
            "GetObjectAttributes accepted " & Label & ": " & Value);
      end Reject_Control;

      Response : constant String := Run
        (Signed_Query_Request
           ("GET", "/test-bucket/object", Query,
            "x-amz-object-attributes",
            "ETag,Checksum,ObjectParts,StorageClass,ObjectSize"));
      Parsed : constant Attributes.Get_Object_Attributes_Result :=
        Attributes.Parse_Result (Response_Body (Response));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "Content-Type: application/xml")
         and then Has (Response, "Last-Modified:")
         and then Parsed.Has_Entity_Tag
         and then US.To_String (Parsed.Entity_Tag) =
           "5eb63bbbe01eeed093cb22bb8f5acdc3"
         and then Parsed.Object_Size.Is_Set
         and then Parsed.Object_Size.Value = 11
         and then Parsed.Has_Checksum
         and then US.To_String (Parsed.Checksum.CRC64NVME) =
           Checksum_Value (Core.CRC64NVME, "hello world")
         and then US.To_String (Parsed.Checksum.Kind) = "FULL_OBJECT"
         and then not Parsed.Has_Object_Parts
         and then not Parsed.Has_Storage_Class,
         "GetObjectAttributes ordinary object response mismatch: " &
         Response);

      declare
         Checksum_Only : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket/object",
               (1 => SigV4.Pair ("attributes", "")),
               "x-amz-object-attributes", "Checksum"));
         Checksum_Result : constant Attributes.Get_Object_Attributes_Result :=
           Attributes.Parse_Result (Response_Body (Checksum_Only));
      begin
         Require
           (Has (Checksum_Only, "200 OK")
            and then not Checksum_Result.Has_Entity_Tag
            and then Checksum_Result.Has_Checksum
            and then US.To_String
              (Checksum_Result.Checksum.CRC64NVME) =
                Checksum_Value (Core.CRC64NVME, "hello world")
            and then not Checksum_Result.Has_Object_Parts
            and then not Checksum_Result.Has_Storage_Class
            and then not Checksum_Result.Object_Size.Is_Set,
            "GetObjectAttributes omitted the default object checksum");
      end;

      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/missing",
                  (1 => SigV4.Pair ("attributes", "")),
                  "x-amz-object-attributes", "ObjectSize")),
            "NoSuchKey"),
         "GetObjectAttributes did not report an absent object");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object",
                  (SigV4.Pair ("attributes", ""),
                   SigV4.Pair ("versionId", "null")),
                  "x-amz-object-attributes", "ObjectSize")),
            "200 OK"),
         "GetObjectAttributes rejected the null version");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object",
                  (SigV4.Pair ("attributes", ""),
                   SigV4.Pair ("versionId", "version-1")),
                  "x-amz-object-attributes", "ObjectSize")),
            "404 Not Found"),
         "GetObjectAttributes did not route a concrete version selector");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")))),
            "400 Bad Request"),
         "GetObjectAttributes accepted a missing selection header");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")),
                  "x-amz-object-attributes", "ETag,ETag")),
            "400 Bad Request"),
         "GetObjectAttributes accepted a duplicate selection value");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ETag" & CRLF &
                  "x-amz-object-attributes: ObjectSize" & CRLF)),
            "400 Bad Request"),
         "GetObjectAttributes accepted a duplicate selection header");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectParts" & CRLF &
                  "x-amz-max-parts: 1001" & CRLF)),
            "400 Bad Request"),
         "GetObjectAttributes accepted an oversized part page");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectParts" & CRLF &
                  "x-amz-part-number-marker: 10001" & CRLF)),
            "400 Bad Request"),
         "GetObjectAttributes accepted an oversized part marker");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectSize" & CRLF &
                  "x-amz-expected-bucket-owner: test-principal" & CRLF)),
            "200 OK"),
         "GetObjectAttributes rejected the authenticated owner");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectSize" & CRLF &
                  "x-amz-expected-bucket-owner: different-owner" & CRLF)),
            "403 Forbidden"),
         "GetObjectAttributes ignored the expected owner");
      Reject_Control
        ("x-amz-request-payer: owner" & CRLF, "InvalidRequest",
         "invalid request payer");
      Reject_Control
        ("x-amz-request-payer: Requester" & CRLF, "InvalidRequest",
         "wrong-case request payer");
      Reject_Control
        ("x-amz-request-payer: " & CRLF, "InvalidRequest",
         "empty request payer");
      Reject_Control
        ("x-amz-request-payer: requester" & CRLF &
         "x-amz-request-payer: requester" & CRLF,
         "InvalidRequest", "duplicate request payer");
      Reject_Control
        ("x-amz-request-payer: requester" & CRLF, "NotImplemented",
         "unsupported requester pays");
      Reject_Control
        ("x-amz-expected-bucket-owner: " & CRLF, "InvalidRequest",
         "empty expected owner");
      Reject_Control
        ("x-amz-expected-bucket-owner: test-principal" & CRLF &
         "x-amz-expected-bucket-owner: test-principal" & CRLF,
         "InvalidRequest", "duplicate expected owner");
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF,
         "InvalidRequest", "incomplete SSE-C group");
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF &
         "x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 &
         CRLF, "InvalidRequest", "duplicate SSE-C algorithm",
         Flyology.HTTP.Secure_HTTPS);
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES128" & CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 &
         CRLF, "InvalidArgument", "invalid SSE-C algorithm",
         Flyology.HTTP.Secure_HTTPS);
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF &
         "x-amz-server-side-encryption-customer-key: malformed" & CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 &
         CRLF, "InvalidDigest", "malformed SSE-C key",
         Flyology.HTTP.Secure_HTTPS);
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         Content_MD5 ("different") & CRLF, "InvalidDigest",
         "mismatched SSE-C digest", Flyology.HTTP.Secure_HTTPS);
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 &
         CRLF, "InvalidRequest", "SSE-C over plaintext");
      Reject_Control
        ("x-amz-server-side-encryption-customer-algorithm: AES256" & CRLF &
         "x-amz-server-side-encryption-customer-key: " & SSE_Test_Key &
         CRLF &
         "x-amz-server-side-encryption-customer-key-md5: " &
         SSE_Test_Key_MD5 &
         CRLF, "NotImplemented", "unsupported valid SSE-C",
         Flyology.HTTP.Secure_HTTPS);
      Reject_Control
        ("x-amz-server-side-encryption: AES256" & CRLF, "NotImplemented",
         "unmodeled encryption control");
      declare
         Value : constant String := Run
           (Signed_Query_Body_Request
              ("GET", "/test-bucket/missing", Query, "",
               "x-amz-object-attributes: ObjectSize" & CRLF &
               "x-amz-request-payer: owner" & CRLF &
               "x-amz-expected-bucket-owner: different-owner" & CRLF &
               "x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF,
               Corrupt_Signature => True));
      begin
         Require
           (Has (Value, "<Code>SignatureDoesNotMatch</Code>")
            and then not Has (Value, "NoSuchKey")
            and then not Has (Value, "InvalidRequest")
            and then not Has (Value, "AccessDenied")
            and then not Has (Value, "NotImplemented"),
            "GetObjectAttributes controls ran before authentication: " &
            Value);
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "unexpected",
                  "x-amz-object-attributes: ObjectSize" & CRLF)),
            "400 Bad Request"),
         "GetObjectAttributes accepted a request body");
   end;

   declare
      Alpha_Name    : constant String := "alpha";
      Beta_Name     : constant String := "beta";
      Rejected_Name : constant String := "rejected";
      Alpha_Payload : constant String := "alpha annotation payload";
      Beta_Payload  : constant String := "beta annotation payload";
      Alpha_ETag    : constant String := GNAT.MD5.Digest (Alpha_Payload);
      Alpha_Checksum : constant String :=
        Checksum_Value (Core.SHA256, Alpha_Payload);
      Source_ETag : constant String :=
        """5eb63bbbe01eeed093cb22bb8f5acdc3""";

      function Query
        (Name, Operation : String) return SigV4.Name_Value_Array is
        (SigV4.Pair ("annotation", ""),
         SigV4.Pair ("annotationName", Name),
         SigV4.Pair ("x-id", Operation));

      function Put_Request
        (Name, Payload, Checksum : String) return String is
        (Signed_Query_Body_Request
           ("PUT", "/test-bucket/object",
            Query (Name, "PutObjectAnnotation"), Payload,
            "Content-MD5: " & Content_MD5 (Payload) & CRLF &
            "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
            "x-amz-checksum-sha256: " & Checksum & CRLF));

      function Get_Request (Target, Name : String) return String is
        (Signed_Query_Request
           ("GET", Target, Query (Name, "GetObjectAnnotation"),
            "x-amz-checksum-mode", "ENABLED"));

      function Delete_Request
        (Name, Condition : String) return String is
        (Signed_Query_Request
           ("DELETE", "/test-bucket/object",
            Query (Name, "DeleteObjectAnnotation"),
            "x-amz-object-if-match", Condition));
   begin
      declare
         Response : constant String :=
           Run (Put_Request (Alpha_Name, Alpha_Payload, Alpha_Checksum));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "ETag: """ & Alpha_ETag & """")
            and then Has
              (Response,
               "x-amz-checksum-sha256: " & Alpha_Checksum & CRLF)
            and then Has
              (Response, "x-amz-checksum-type: FULL_OBJECT" & CRLF)
            and then not Has (Response, "x-amz-object-version-id:"),
            "PutObjectAnnotation response binding mismatch: invalid-request=" &
              Boolean'Image (Has (Response, "<Code>InvalidRequest</Code>")) &
              ", invalid-argument=" &
              Boolean'Image (Has (Response, "<Code>InvalidArgument</Code>")) &
              ", bad-digest=" &
              Boolean'Image (Has (Response, "<Code>BadDigest</Code>")) &
              ", signature=" &
              Boolean'Image
                (Has (Response, "<Code>SignatureDoesNotMatch</Code>")) &
              ", payload-hash=" &
              Boolean'Image
                (Has
                   (Response,
                    "<Code>XAmzContentSHA256Mismatch</Code>")));
      end;

      declare
         Response : constant String :=
           Run
             (Put_Request
                (Rejected_Name, "rejected annotation payload",
                 Checksum_Value (Core.SHA256, "different")));
      begin
         Require
           (Has (Response, "<Code>BadDigest</Code>"),
            "PutObjectAnnotation accepted a mismatched checksum");
         Require
           (Has
              (Run
                 (Get_Request
                    ("/test-bucket/object", Rejected_Name)),
               "<Code>NoSuchAnnotation</Code>"),
            "rejected annotation checksum published state");
      end;

      Require
        (Has
           (Run
              (Put_Request
                 (Beta_Name, Beta_Payload,
                  Checksum_Value (Core.SHA256, Beta_Payload))),
            "200 OK"),
         "second PutObjectAnnotation failed");

      declare
         Response : constant String :=
           Run (Get_Request ("/test-bucket/object", Alpha_Name));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, Alpha_Payload)
            and then Has (Response, "ETag: """ & Alpha_ETag & """")
            and then Has
              (Response,
               "x-amz-checksum-sha256: " & Alpha_Checksum & CRLF)
            and then not Has (Response, "x-amz-object-version-id:"),
            "GetObjectAnnotation lost body, checksum, ETag, or version");
      end;

      declare
         First_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("annotation", ""),
            SigV4.Pair ("maxAnnotationResults", "1"),
            SigV4.Pair ("x-id", "ListObjectAnnotations"));
         First_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/test-bucket/object", First_Query));
         First : constant Annotations.Annotation_Page :=
           Annotations.Parse_List
             (Response_Body (First_Response), XML.Default_Limits);
         Token : constant String := US.To_String
           (First.Next_Continuation_Token.Value);
      begin
         Require
           (Has (First_Response, "200 OK")
            and then First.Annotations.Length = 1
            and then US.To_String
              (First.Annotations.First_Element.Name) = Alpha_Name
            and then First.Annotations.First_Element.Size =
              Alpha_Payload'Length
            and then First.Annotations.First_Element.Entity_Tag.Is_Set
            and then US.To_String
              (First.Annotations.First_Element.Entity_Tag.Value) =
                '"' & Alpha_ETag & '"'
            and then First.Annotations.First_Element.Checksums.Length = 1
            and then First.Annotations.First_Element.Checksums.First_Element =
              Core.SHA256
            and then First.Next_Continuation_Token.Is_Set
            and then Token'Length > 0
            and then Token /= Alpha_Name
            and then not Has
              (First_Response, "x-amz-object-version-id:"),
            "ListObjectAnnotations first page mismatch");
         declare
            Next_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("annotation", ""),
               SigV4.Pair ("continuationToken", Token),
               SigV4.Pair ("maxAnnotationResults", "1"),
               SigV4.Pair ("x-id", "ListObjectAnnotations"));
            Next_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/test-bucket/object", Next_Query));
            Next : constant Annotations.Annotation_Page :=
              Annotations.Parse_List
                (Response_Body (Next_Response), XML.Default_Limits);
         begin
            Require
              (Next.Annotations.Length = 1
               and then US.To_String
                 (Next.Annotations.First_Element.Name) = Beta_Name
               and then not Next.Next_Continuation_Token.Is_Set,
               "ListObjectAnnotations continuation order mismatch");
         end;
      end;

      Require
        (Has
           (Run (Delete_Request (Beta_Name, """wrong""")),
            "HTTP/1.1 412 "),
         "DeleteObjectAnnotation ignored a mismatched object condition");
      Require
        (Has
           (Run (Get_Request ("/test-bucket/object", Beta_Name)),
            Beta_Payload),
         "failed DeleteObjectAnnotation changed retained state");
      declare
         Response : constant String :=
           Run (Delete_Request (Beta_Name, Source_ETag));
      begin
         Require
           (Has (Response, "204 No Content")
            and then not Has (Response, "x-amz-object-version-id:"),
            "DeleteObjectAnnotation matching condition failed");
      end;
      Require
        (Has
           (Run (Get_Request ("/test-bucket/object", Beta_Name)),
            "<Code>NoSuchAnnotation</Code>"),
         "DeleteObjectAnnotation left the removed annotation visible");

      declare
         Response : constant String :=
           Run
             (Signed_Copy_Member_Request
                ("/test-bucket/copied", "test-bucket/object",
                 "x-amz-object-annotation-directive", "COPY"));
         Copied : constant String :=
           Run (Get_Request ("/test-bucket/copied", Alpha_Name));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Copied, "200 OK")
            and then Has (Copied, Alpha_Payload)
            and then Has
              (Copied,
               "x-amz-checksum-sha256: " & Alpha_Checksum & CRLF),
            "CopyObject COPY did not copy annotation state");
      end;
      Require
        (Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copied", "test-bucket/object",
                  "x-amz-object-annotation-directive", "EXCLUDE")),
            "200 OK"),
         "CopyObject rejected the EXCLUDE annotation directive");
      Require
        (Has
           (Run (Get_Request ("/test-bucket/copied", Alpha_Name)),
            "<Code>NoSuchAnnotation</Code>"),
         "CopyObject EXCLUDE retained destination annotation state");
      Require
        (Has
           (Run (Get_Request ("/test-bucket/object", Alpha_Name)),
            Alpha_Payload),
         "CopyObject EXCLUDE changed source annotation state");
   end;

   declare
      ETag : constant String :=
        """5eb63bbbe01eeed093cb22bb8f5acdc3""";
      Response : constant String := Run
        (Signed_Copy_Request
           ("/test-bucket/copied", "test-bucket/object",
            With_X_ID => True));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "<CopyObjectResult")
         and then Has (Response, "<ETag>&quot;" &
           "5eb63bbbe01eeed093cb22bb8f5acdc3&quot;</ETag>")
         and then Has (Response, "<LastModified>"),
         "CopyObject response mismatch: " & Response);
      declare
         Get_Response : constant String := Run
           (Signed_Request ("GET", "/test-bucket/copied", ""));
      begin
         Require
           (Has (Get_Response, "200 OK")
            and then Has (Get_Response, "Content-Type: text/plain")
            and then Has (Get_Response, "hello world"),
            "CopyObject did not preserve body and content type");
      end;
      Require
        (Has
           (Run
              (Signed_Copy_Request
                 ("/test-bucket/copy-match", "test-bucket/object", ETag)),
            "200 OK"),
         "CopyObject rejected a matching source ETag");
      declare
         Failed_Response : constant String := Run
           (Signed_Copy_Request
              ("/test-bucket/copy-failed", "test-bucket/object",
               """wrong"""));
      begin
         Require
           (Has (Failed_Response, "HTTP/1.1 412 ")
            and then Has (Failed_Response, "PreconditionFailed"),
            "CopyObject failed-condition response mismatch: " &
            Failed_Response);
      end;
      declare
         Missing_Key : constant String := Run
           (Signed_Copy_Request
              ("/test-bucket/copy-missing", "test-bucket/missing"));
         Missing_Bucket : constant String := Run
           (Signed_Copy_Request
              ("/test-bucket/copy-missing-bucket",
               "missing-source-bucket/object"));
      begin
         Require
           (Has (Missing_Key, "NoSuchKey")
            and then Has
              (Missing_Key, "<Resource>/test-bucket/missing</Resource>"),
            "CopyObject source absence resource mismatch");
         Require
           (Has (Missing_Bucket, "NoSuchBucket")
            and then Has
              (Missing_Bucket,
               "<Resource>/missing-source-bucket/object</Resource>"),
            "CopyObject source-bucket absence resource mismatch");
      end;
      Require
        (Has
           (Run
              (Signed_Copy_Request
                 ("/test-bucket/object", "test-bucket/object")),
            "InvalidRequest"),
         "metadata-preserving CopyObject accepted a self copy");

      Require
        (Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-date-ok", "test-bucket/object",
                  "x-amz-copy-source-if-modified-since",
                  "Sat, 01 Jan 2000 00:00:00 GMT")),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-date-failed", "test-bucket/object",
                  "x-amz-copy-source-if-modified-since",
                  "Tue, 01 Jan 2030 00:00:00 GMT")),
            "HTTP/1.1 412 ")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-date-invalid", "test-bucket/object",
                  "x-amz-copy-source-if-unmodified-since", "not-a-date")),
            "400 Bad Request"),
         "CopyObject source date-condition semantics mismatch");
      Require
        (Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copied", "test-bucket/object", "if-match",
                  ETag)),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copied", "test-bucket/object", "if-match",
                  """stale""")),
            "HTTP/1.1 412 ")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-create-only", "test-bucket/object",
                  "if-none-match", "*")),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-create-only", "test-bucket/object",
                  "if-none-match", "*")),
            "HTTP/1.1 412 "),
         "CopyObject destination conditions were not atomic");
      Require
        (Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-source-none-failed",
                  "test-bucket/object", "x-amz-copy-source-if-none-match",
                  ETag)),
            "HTTP/1.1 412 ")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-missing-destination",
                  "test-bucket/object", "if-match", ETag)),
            "HTTP/1.1 412 "),
         "CopyObject source If-None-Match or missing If-Match mismatch");
      Require
        (Has
           (Run
              (Signed_Copy_Headers_Request
                 ("/test-bucket/copy-etag-date-precedence-a",
                  "test-bucket/object",
                  (SigV4.Pair ("x-amz-copy-source-if-match", ETag),
                   SigV4.Pair
                     ("x-amz-copy-source-if-unmodified-since",
                      "Sat, 01 Jan 2000 00:00:00 GMT")))),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Headers_Request
                 ("/test-bucket/copy-etag-date-precedence-b",
                  "test-bucket/object",
                  (SigV4.Pair ("x-amz-copy-source-if-none-match", ETag),
                   SigV4.Pair
                     ("x-amz-copy-source-if-modified-since",
                      "Sat, 01 Jan 2000 00:00:00 GMT")))),
            "HTTP/1.1 412 "),
         "CopyObject ETag/date precedence mismatch");
      declare
         Empty_Conditions : constant Key_Array :=
           (US.To_Unbounded_String ("x-amz-copy-source-if-match"),
            US.To_Unbounded_String ("x-amz-copy-source-if-none-match"),
            US.To_Unbounded_String ("if-match"),
            US.To_Unbounded_String ("if-none-match"));
         Status : Flyology.Object_Storage.Status;
         Info   : Flyology.Object_Storage.Object_Information;
      begin
         for Header of Empty_Conditions loop
            Require
              (Has
                 (Run
                    (Signed_Copy_Member_Request
                       ("/test-bucket/copy-empty-condition",
                        "test-bucket/object", US.To_String (Header), "")),
                  "400 Bad Request"),
               "CopyObject accepted empty condition " &
               US.To_String (Header));
         end loop;
         Store.Head_Object
           ("test-bucket", "copy-empty-condition", null,
            Ada.Real_Time.Time_Last, Info, Status);
         Require
           (Status = Flyology.Object_Storage.Not_Found,
            "empty CopyObject condition published a destination");
      end;
      Require
        (Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-owner", "test-bucket/object",
                  "x-amz-expected-bucket-owner", "test-principal")),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-owner", "test-bucket/object",
                  "x-amz-source-expected-bucket-owner", "other")),
            "403 Forbidden")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-owner", "test-bucket/object",
                  "x-amz-expected-bucket-owner", "other")),
            "403 Forbidden"),
         "CopyObject expected-owner policy mismatch");

      declare
         Status : Flyology.Object_Storage.Status;
         Info   : Flyology.Object_Storage.Object_Information;
      begin
         Require
           (Has
              (Run
                 (Signed_Copy_Member_Request
                    ("/test-bucket/copy-invalid-copy-metadata",
                     "test-bucket/object", "cache-control", "max-age=60")),
               "400 Bad Request")
            and then Has
              (Run
                 (Signed_Copy_Member_Request
                    ("/test-bucket/copy-invalid-copy-metadata",
                     "test-bucket/object", "x-amz-meta-team", "storage")),
               "400 Bad Request"),
            "COPY silently ignored supplied replacement metadata");
         Store.Head_Object
           ("test-bucket", "copy-invalid-copy-metadata", null,
            Ada.Real_Time.Time_Last, Info, Status);
         Require
           (Status = Flyology.Object_Storage.Not_Found,
            "invalid COPY metadata mutated the destination");
      end;

      declare
         Complete_Headers : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("x-amz-metadata-directive", "REPLACE"),
            SigV4.Pair ("cache-control", "max-age=60"),
            SigV4.Pair ("content-disposition", "inline"),
            SigV4.Pair ("content-encoding", "identity"),
            SigV4.Pair ("content-language", "en"),
            SigV4.Pair ("content-type", "application/json"),
            SigV4.Pair
              ("expires", "Fri, 01 Jan 1960 12:34:60 GMT"),
            SigV4.Pair
              ("x-amz-website-redirect-location", "/explicit"),
            SigV4.Pair ("x-amz-meta-team", "storage"),
            SigV4.Pair ("x-amz-tagging-directive", "REPLACE"),
            SigV4.Pair ("x-amz-tagging", "team=storage%2Fcore"),
            SigV4.Pair ("x-amz-checksum-algorithm", "SHA256"));
         Complete_Response : constant String := Run
           (Signed_Copy_Headers_Request
              ("/test-bucket/copy-complete", "test-bucket/object",
               Complete_Headers));
         Info : Flyology.Object_Storage.Object_Information;
         Status : Flyology.Object_Storage.Status;
         Copied_Tags : Flyology.Object_Storage.Object_Tag_Set;
      begin
         Require
           (Has (Complete_Response, "200 OK")
            and then Has
              (Complete_Response, "<ChecksumType>FULL_OBJECT</ChecksumType>")
            and then Has
              (Complete_Response,
               "<ChecksumSHA256>" & SHA256_Checksum ("hello world") &
               "</ChecksumSHA256>")
            and then not Has (Complete_Response, "x-amz-expiration")
            and then not Has
              (Complete_Response, "x-amz-copy-source-version-id")
            and then not Has (Complete_Response, "x-amz-version-id")
            and then not Has
              (Complete_Response, "x-amz-server-side-encryption")
            and then not Has (Complete_Response, "x-amz-request-charged"),
            "complete CopyObject response omitted selected checksum");
         Store.Head_Object
           ("test-bucket", "copy-complete", null, Ada.Real_Time.Time_Last,
            Info, Status);
         Store.Get_Object_Tags
           ("test-bucket", "copy-complete", null,
            Ada.Real_Time.Time_Last, Copied_Tags, Status);
         Require
           (Status = Flyology.Object_Storage.Success
            and then US.To_String (Info.Content_Type) = "application/json"
            and then Info.Metadata.Cache_Control.Is_Set
            and then US.To_String (Info.Metadata.Cache_Control.Value) =
              "max-age=60"
            and then Info.Metadata.Content_Disposition.Is_Set
            and then US.To_String
              (Info.Metadata.Content_Disposition.Value) = "inline"
            and then Info.Metadata.Content_Encoding.Is_Set
            and then US.To_String (Info.Metadata.Content_Encoding.Value) =
              "identity"
            and then Info.Metadata.Content_Language.Is_Set
            and then US.To_String (Info.Metadata.Content_Language.Value) =
              "en"
            and then Info.Metadata.Expires.Is_Set
            and then Info.Metadata.Expires.Value = -315_573_900
            and then Info.Metadata.Website_Redirect_Location.Is_Set
            and then Info.Metadata.User.Length = 1
            and then US.To_String (Info.Metadata.User.Items (1).Key) = "team"
            and then Copied_Tags.Length = 1
            and then US.To_String (Copied_Tags.Items (1).Value) =
              "storage/core"
            and then Info.Checksum.Algorithm =
              Flyology.Object_Storage.Checksum_SHA256,
            "CopyObject REPLACE did not atomically persist full tuple");

         declare
            Default_Response : constant String := Run
              (Signed_Copy_Request
                 ("/test-bucket/copy-default", "test-bucket/copy-complete"));
         begin
            Require
              (Has (Default_Response, "<ChecksumSHA256>")
               and then Has
                 (Default_Response,
                  "<ChecksumType>FULL_OBJECT</ChecksumType>"),
               "default CopyObject did not inherit source checksum choice");
         end;
         Store.Head_Object
           ("test-bucket", "copy-default", null, Ada.Real_Time.Time_Last,
            Info, Status);
         Store.Get_Object_Tags
           ("test-bucket", "copy-default", null,
            Ada.Real_Time.Time_Last, Copied_Tags, Status);
         Require
           (Status = Flyology.Object_Storage.Success
            and then Info.Metadata.Cache_Control.Is_Set
            and then not Info.Metadata.Website_Redirect_Location.Is_Set
            and then Info.Metadata.User.Length = 1
            and then Copied_Tags.Length = 1
            and then Info.Checksum.Algorithm =
              Flyology.Object_Storage.Checksum_SHA256,
            "default CopyObject lost metadata/tags/checksum or copied " &
            "redirect");

         Require
           (Has
              (Run
                 (Signed_Copy_Headers_Request
                    ("/test-bucket/copy-empty-replace",
                     "test-bucket/copy-complete",
                     (SigV4.Pair
                        ("x-amz-metadata-directive", "REPLACE"),
                      SigV4.Pair
                        ("x-amz-tagging-directive", "REPLACE")))),
               "200 OK"),
            "CopyObject empty replacement was rejected");
         Store.Head_Object
           ("test-bucket", "copy-empty-replace", null,
            Ada.Real_Time.Time_Last, Info, Status);
         Store.Get_Object_Tags
           ("test-bucket", "copy-empty-replace", null,
            Ada.Real_Time.Time_Last, Copied_Tags, Status);
         Require
           (Status = Flyology.Object_Storage.Success
            and then US.To_String (Info.Content_Type) =
              "application/octet-stream"
            and then not Info.Metadata.Cache_Control.Is_Set
            and then Info.Metadata.User.Length = 0
            and then Copied_Tags.Length = 0,
            "CopyObject empty REPLACE retained source metadata or tags");
      end;

      declare
         Algorithms : constant array (Positive range <>) of
           Checksum_Policy.Algorithm :=
             (Core.CRC32, Core.CRC32C, Core.CRC64NVME, Core.SHA1,
              Core.SHA256, Core.SHA512, Core.MD5, Core.XXHASH64,
              Core.XXHASH3, Core.XXHASH128);
      begin
         for Algorithm of Algorithms loop
            declare
               Name : constant String := Checksum_Policy.Wire_Name
                 (Algorithm);
               Response_Value : constant String := Run
                 (Signed_Copy_Member_Request
                    ("/test-bucket/copy-checksum", "test-bucket/object",
                     "x-amz-checksum-algorithm", Name));
            begin
               Require
                 (Has (Response_Value, "200 OK")
                  and then Has
                    (Response_Value,
                     "<ChecksumType>FULL_OBJECT</ChecksumType>")
                  and then Has
                    (Response_Value,
                     "<Checksum" & Name & ">" &
                     Checksum_Value (Algorithm, "hello world") &
                     "</Checksum" & Name & ">"),
                  "CopyObject rejected direct checksum " & Name);
            end;
         end loop;
      end;

      Require
        (Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-policy", "test-bucket/object",
                  "x-amz-acl", "private")),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-public", "test-bucket/object",
                  "x-amz-acl", "public-read")),
            "501 Not Implemented")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-policy", "test-bucket/object",
                  "x-amz-storage-class", "STANDARD")),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-glacier", "test-bucket/object",
                  "x-amz-storage-class", "GLACIER")),
            "501 Not Implemented")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-policy", "test-bucket/object",
                  "x-amz-object-annotation-directive", "COPY")),
            "200 OK")
         and then Has
           (Run
              (Signed_Copy_Member_Request
                 ("/test-bucket/copy-policy", "test-bucket/object",
                  "x-amz-object-annotation-directive", "EXCLUDE")),
            "200 OK"),
         "CopyObject ACL/storage-class/annotation disposition mismatch");

      declare
         Encryption_Algorithms : constant Key_Array :=
           (US.To_Unbounded_String ("AES256"),
            US.To_Unbounded_String ("aws:kms"),
            US.To_Unbounded_String ("aws:kms:dsse"),
            US.To_Unbounded_String ("aws:fsx"),
            US.To_Unbounded_String ("aws:backup"));
      begin
         for Algorithm of Encryption_Algorithms loop
            Require
              (Has
                 (Run
                    (Signed_Copy_Member_Request
                       ("/test-bucket/copy-encrypted",
                        "test-bucket/object", "x-amz-server-side-encryption",
                        US.To_String (Algorithm))),
                  "501 Not Implemented"),
               "modeled CopyObject encryption value was not validated: " &
               US.To_String (Algorithm));
         end loop;
      end;

      declare
         Invalid : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("x-amz-metadata-directive", "MERGE"),
            SigV4.Pair ("x-amz-tagging-directive", "MERGE"),
            SigV4.Pair ("x-amz-checksum-algorithm", "UNKNOWN"),
            SigV4.Pair ("x-amz-request-payer", "owner"),
            SigV4.Pair ("x-amz-object-annotation-directive", "MERGE"),
            SigV4.Pair ("x-amz-server-side-encryption", "UNKNOWN"),
            SigV4.Pair
              ("x-amz-server-side-encryption-customer-algorithm", "AES256"),
            SigV4.Pair ("x-amz-copy-source-if-match", "bare"),
            SigV4.Pair ("if-none-match", "bare"),
            SigV4.Pair ("expires", "not-a-date"),
            SigV4.Pair ("x-amz-tagging", "missing-equals"));
      begin
         for Item of Invalid loop
            declare
               Invalid_Response : constant String := Run
                 (Signed_Copy_Member_Request
                    ("/test-bucket/copy-invalid-member",
                     "test-bucket/object", US.To_String (Item.Name),
                     US.To_String (Item.Value)));
            begin
               Require
                 (Has (Invalid_Response, "400 Bad Request"),
                  "CopyObject accepted malformed member " &
                  US.To_String (Item.Name) & ": " & Invalid_Response);
            end;
         end loop;
      end;

      declare
         Duplicate_Headers : constant Key_Array :=
           (US.To_Unbounded_String ("x-amz-acl"),
            US.To_Unbounded_String ("cache-control"),
            US.To_Unbounded_String ("x-amz-checksum-algorithm"),
            US.To_Unbounded_String ("content-disposition"),
            US.To_Unbounded_String ("content-encoding"),
            US.To_Unbounded_String ("content-language"),
            US.To_Unbounded_String ("content-type"),
            US.To_Unbounded_String ("x-amz-copy-source-if-match"),
            US.To_Unbounded_String
              ("x-amz-copy-source-if-modified-since"),
            US.To_Unbounded_String ("x-amz-copy-source-if-none-match"),
            US.To_Unbounded_String
              ("x-amz-copy-source-if-unmodified-since"),
            US.To_Unbounded_String ("expires"),
            US.To_Unbounded_String ("x-amz-grant-full-control"),
            US.To_Unbounded_String ("x-amz-grant-read"),
            US.To_Unbounded_String ("x-amz-grant-read-acp"),
            US.To_Unbounded_String ("x-amz-grant-write-acp"),
            US.To_Unbounded_String ("if-match"),
            US.To_Unbounded_String ("if-none-match"),
            US.To_Unbounded_String ("x-amz-meta-team"),
            US.To_Unbounded_String ("x-amz-metadata-directive"),
            US.To_Unbounded_String ("x-amz-tagging-directive"),
            US.To_Unbounded_String ("x-amz-object-annotation-directive"),
            US.To_Unbounded_String ("x-amz-server-side-encryption"),
            US.To_Unbounded_String ("x-amz-storage-class"),
            US.To_Unbounded_String ("x-amz-website-redirect-location"),
            US.To_Unbounded_String
              ("x-amz-server-side-encryption-customer-algorithm"),
            US.To_Unbounded_String
              ("x-amz-server-side-encryption-customer-key"),
            US.To_Unbounded_String
              ("x-amz-server-side-encryption-customer-key-md5"),
            US.To_Unbounded_String
              ("x-amz-server-side-encryption-aws-kms-key-id"),
            US.To_Unbounded_String
              ("x-amz-server-side-encryption-context"),
            US.To_Unbounded_String
              ("x-amz-server-side-encryption-bucket-key-enabled"),
            US.To_Unbounded_String
              ("x-amz-copy-source-server-side-encryption-" &
               "customer-algorithm"),
            US.To_Unbounded_String
              ("x-amz-copy-source-server-side-encryption-customer-key"),
            US.To_Unbounded_String
              ("x-amz-copy-source-server-side-encryption-customer-key-md5"),
            US.To_Unbounded_String ("x-amz-request-payer"),
            US.To_Unbounded_String ("x-amz-tagging"),
            US.To_Unbounded_String ("x-amz-object-lock-mode"),
            US.To_Unbounded_String
              ("x-amz-object-lock-retain-until-date"),
            US.To_Unbounded_String ("x-amz-object-lock-legal-hold"),
            US.To_Unbounded_String ("x-amz-expected-bucket-owner"),
            US.To_Unbounded_String
              ("x-amz-source-expected-bucket-owner"));
         Status : Flyology.Object_Storage.Status;
         Info   : Flyology.Object_Storage.Object_Information;
      begin
         declare
            Duplicate_Source_Response : constant String := Run
              (Signed_Duplicate_Copy_Source_Request
                 ("/test-bucket/copy-duplicate-member"));
         begin
            Require
              (Has (Duplicate_Source_Response, "400 Bad Request"),
               "CopyObject accepted duplicate copy source: " &
               Duplicate_Source_Response);
         end;
         for Header of Duplicate_Headers loop
            Require
              (Has
                 (Run
                    (Signed_Copy_Member_Request
                       ("/test-bucket/copy-duplicate-member",
                        "test-bucket/object", US.To_String (Header),
                        "first", "second")),
                  "400 Bad Request"),
               "CopyObject accepted duplicate modeled header " &
               US.To_String (Header));
         end loop;
         Store.Head_Object
           ("test-bucket", "copy-duplicate-member", null,
            Ada.Real_Time.Time_Last, Info, Status);
         Require
           (Status = Flyology.Object_Storage.Not_Found,
            "duplicate CopyObject member mutated the destination");
      end;

      declare
         Unsupported : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("x-amz-grant-full-control", "id=owner"),
            SigV4.Pair ("x-amz-grant-read", "id=reader"),
            SigV4.Pair ("x-amz-grant-read-acp", "id=reader"),
            SigV4.Pair ("x-amz-grant-write-acp", "id=writer"),
            SigV4.Pair ("x-amz-server-side-encryption", "AES256"),
            SigV4.Pair
              ("x-amz-server-side-encryption-aws-kms-key-id", "kms-key"),
            SigV4.Pair
              ("x-amz-server-side-encryption-context", "e30="),
            SigV4.Pair
              ("x-amz-server-side-encryption-bucket-key-enabled", "true"),
            SigV4.Pair ("x-amz-request-payer", "requester"),
            SigV4.Pair ("x-amz-object-lock-mode", "GOVERNANCE"),
            SigV4.Pair
              ("x-amz-object-lock-retain-until-date",
               "2030-01-01T00:00:00Z"),
            SigV4.Pair ("x-amz-object-lock-legal-hold", "ON"));
      begin
         for Item of Unsupported loop
            Require
              (Has
                 (Run
                    (Signed_Copy_Member_Request
                       ("/test-bucket/copy-unsupported",
                        "test-bucket/object", US.To_String (Item.Name),
                        US.To_String (Item.Value))),
                  "501 Not Implemented"),
               "CopyObject silently ignored unsupported member " &
               US.To_String (Item.Name));
         end loop;
         Require
           (Has
              (Run
                 (Signed_Copy_Headers_Request
                    ("/test-bucket/copy-unsupported",
                     "test-bucket/object",
                     (SigV4.Pair
                        ("x-amz-server-side-encryption-customer-algorithm",
                         "AES256"),
                      SigV4.Pair
                        ("x-amz-server-side-encryption-customer-key",
                         "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
                      SigV4.Pair
                        ("x-amz-server-side-encryption-customer-key-md5",
                         "AAAAAAAAAAAAAAAAAAAAAA==")))),
               "501 Not Implemented")
            and then Has
              (Run
                 (Signed_Copy_Headers_Request
                    ("/test-bucket/copy-unsupported",
                     "test-bucket/object",
                     (SigV4.Pair
                        ("x-amz-copy-source-server-side-encryption-" &
                         "customer-algorithm", "AES256"),
                      SigV4.Pair
                        ("x-amz-copy-source-server-side-encryption-" &
                         "customer-key",
                         "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
                      SigV4.Pair
                        ("x-amz-copy-source-server-side-encryption-" &
                         "customer-key-md5",
                         "AAAAAAAAAAAAAAAAAAAAAA==")))),
               "501 Not Implemented"),
            "CopyObject accepted a modeled SSE-C policy");
         declare
            Status : Flyology.Object_Storage.Status;
            Info   : Flyology.Object_Storage.Object_Information;
         begin
            Store.Head_Object
              ("test-bucket", "copy-unsupported", null,
               Ada.Real_Time.Time_Last, Info, Status);
            Require
              (Status = Flyology.Object_Storage.Not_Found,
               "unsupported CopyObject member mutated the destination");
         end;
      end;

      declare
         Created : constant Key_Array :=
           (US.To_Unbounded_String ("copied"),
            US.To_Unbounded_String ("copy-match"),
            US.To_Unbounded_String ("copy-date-ok"),
            US.To_Unbounded_String ("copy-etag-date-precedence-a"),
            US.To_Unbounded_String ("copy-create-only"),
            US.To_Unbounded_String ("copy-owner"),
            US.To_Unbounded_String ("copy-complete"),
            US.To_Unbounded_String ("copy-default"),
            US.To_Unbounded_String ("copy-empty-replace"),
            US.To_Unbounded_String ("copy-checksum"),
            US.To_Unbounded_String ("copy-policy"));
         Delete_Status : Flyology.Object_Storage.Status;
      begin
         for Created_Key of Created loop
            Store.Delete_Object
              ("test-bucket", US.To_String (Created_Key), null,
               Ada.Real_Time.Time_Last, Delete_Status);
            Require
              (Delete_Status = Flyology.Object_Storage.Success,
               "CopyObject corpus cleanup failed for " &
               US.To_String (Created_Key));
         end loop;
      end;
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("tagging", ""));
      Versioned : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("versionId", "unsupported"));
      Unknown : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""),
         SigV4.Pair ("unknown", "value"));
      Duplicate : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("tagging", ""), SigV4.Pair ("tagging", ""));
      Document : constant String :=
        "<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value>" &
        "</Tag></TagSet></Tagging>";
      Malformed : constant String :=
        "<Tagging><TagSet><Tag><Key>broken</Key></Tag></TagSet></Tagging>";
      Valid_MD5 : constant String := Content_MD5 (Document);
      Malformed_MD5 : constant String := Content_MD5 (Malformed);
      Exact_Limit_Document : constant String :=
        Document & String'
          (1 .. Tagging.Maximum_Document_Bytes - Document'Length => ' ');
      Exact_Limit_MD5 : constant String := Content_MD5 (Exact_Limit_Document);
      One_Past_Document : constant String := Exact_Limit_Document & ' ';
      --  These test/reference bodies derive directly from the public tagging
      --  document bound and S3 Content-MD5 rule. They guard inclusive-boundary
      --  compatibility without duplicating the selected 16 KiB policy value.

      procedure Reject_Tagging_Control
        (Method            : String;
         Headers           : String;
         Code              : String;
         Label             : String;
         Corrupt_Signature : Boolean := False)
      is
         Value : constant String := Run
           (Signed_Query_Body_Request
              (Method, "/test-bucket/object", Query, "", Headers,
               Corrupt_Signature => Corrupt_Signature));
      begin
         Require
           (Has (Value, "<Code>" & Code & "</Code>"),
            Method & " object tagging accepted " & Label & ": " & Value);
      end Reject_Tagging_Control;
   begin
      declare
         Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/test-bucket/object", Query, Document,
                 "Content-MD5: " & Valid_MD5 & CRLF &
                 "Content-Type: application/xml; charset=utf-8" & CRLF));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "x-amz-version-id: null" & CRLF),
            "PutObjectTagging rejected an unversioned tagging document");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Exact_Limit_Document,
                  "Content-MD5: " & Exact_Limit_MD5 & CRLF &
                  "Content-Type: application/xml" & CRLF)),
            "200 OK"),
         "PutObjectTagging rejected the exact document-size limit");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, One_Past_Document,
                  "Content-MD5: " & Content_MD5 (One_Past_Document) & CRLF &
                  "Content-Type: application/xml" & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectTagging accepted one byte beyond the document limit");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket/object", Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Type: application/xml")
            and then Has (Response, "x-amz-version-id: null" & CRLF)
            and then Has (Response, "<Key>team</Key>")
            and then Has (Response, "<Value>storage</Value>"),
            "GetObjectTagging did not return the committed tags");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Document,
                  "Content-MD5: AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutObjectTagging accepted a mismatched Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Document,
                  "Content-MD5: " & Valid_MD5 & CRLF &
                  "Content-MD5: " & Valid_MD5 & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectTagging accepted duplicate Content-MD5 headers");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Document,
                  "Content-MD5: " & Valid_MD5 & CRLF &
                  "Content-Type: application/xml" & CRLF &
                  "Content-Type: application/xml" & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectTagging accepted duplicate content-type headers");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/object", Query)),
            "<Key>team</Key>"),
         "a rejected PutObjectTagging changed existing tags");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Malformed,
                  "Content-MD5: " & Malformed_MD5 & CRLF)),
            "<Code>MalformedXML</Code>"),
         "PutObjectTagging accepted malformed XML with a valid digest");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Document,
                  "Content-MD5: " & Valid_MD5 & CRLF &
                  "Content-Type: application/xmlbad" & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectTagging accepted an invalid content type");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Document)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectTagging accepted a missing Content-MD5");
      Require
        (Has (Run (Signed_Query_Request
           ("GET", "/test-bucket/object", Unknown)),
           "<Code>InvalidArgument</Code>"),
         "GetObjectTagging accepted an unknown query member");
      Require
        (Has (Run (Signed_Query_Request
           ("GET", "/test-bucket/object", Duplicate)),
           "<Code>InvalidArgument</Code>"),
         "GetObjectTagging accepted duplicate tagging controls");
      Require
        (Has (Run (Signed_Query_Request
           ("GET", "/test-bucket/object", Versioned)),
           "<Code>NoSuchKey</Code>"),
         "GetObjectTagging did not route an unknown exact version");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", Query,
                  "x-amz-expected-bucket-owner", "different-owner")),
            "403 Forbidden"),
         "GetObjectTagging ignored the expected bucket owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", Query,
                  "x-amz-request-payer", "requester")),
            "501 Not Implemented"),
         "GetObjectTagging silently accepted Requester Pays");
      declare
         Methods : constant Key_Array :=
           (US.To_Unbounded_String ("PUT"),
            US.To_Unbounded_String ("GET"),
            US.To_Unbounded_String ("DELETE"));
      begin
         for Method of Methods loop
            declare
               Name : constant String := US.To_String (Method);
            begin
               Reject_Tagging_Control
                 (Name, "x-amz-request-payer: owner" & CRLF,
                  "InvalidArgument", "an invalid request payer");
               Reject_Tagging_Control
                 (Name, "x-amz-request-payer: " & CRLF,
                  "InvalidArgument", "an empty request payer");
               Reject_Tagging_Control
                 (Name,
                  "x-amz-request-payer: requester" & CRLF &
                  "x-amz-request-payer: requester" & CRLF,
                  "InvalidRequest", "duplicate request-payer headers");
               Reject_Tagging_Control
                 (Name, "x-amz-request-payer: requester" & CRLF,
                  "NotImplemented", "the Requester Pays exclusion");
               Reject_Tagging_Control
                 (Name,
                  "x-amz-sdk-checksum-algorithm: UNKNOWN" & CRLF,
                  "InvalidArgument", "an invalid SDK checksum algorithm");
               Reject_Tagging_Control
                 (Name,
                  "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
                  "x-amz-sdk-checksum-algorithm: CRC32" & CRLF,
                  "InvalidRequest", "duplicate SDK checksum algorithms");
               Reject_Tagging_Control
                 (Name,
                  "x-amz-sdk-checksum-algorithm: CRC32" & CRLF,
                  "NotImplemented", "the SDK checksum exclusion");
               Reject_Tagging_Control
                 (Name, "x-amz-expected-bucket-owner: " & CRLF,
                  "InvalidRequest", "an empty expected owner");
               Reject_Tagging_Control
                 (Name,
                  "x-amz-expected-bucket-owner: test-principal" & CRLF &
                  "x-amz-expected-bucket-owner: test-principal" & CRLF,
                  "InvalidRequest", "duplicate expected-owner headers");
               Reject_Tagging_Control
                 (Name,
                  "x-amz-request-payer: owner" & CRLF &
                  "x-amz-sdk-checksum-algorithm: UNKNOWN" & CRLF,
                  "SignatureDoesNotMatch",
                  "controls before authentication",
                  Corrupt_Signature => True);
            end;
         end loop;
      end;
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/object", Query)),
            "<Key>team</Key>"),
         "rejected object-tagging controls changed the committed tag set");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object", Query, "unexpected")),
            "400 Bad Request"),
         "GetObjectTagging accepted a request body");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/missing-tagged", Query)),
            "<Code>NoSuchKey</Code>"),
         "GetObjectTagging misreported a missing key");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/missing-bucket/object", Query)),
            "<Code>NoSuchBucket</Code>"),
         "GetObjectTagging misreported a missing bucket");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("DELETE", "/test-bucket/object", Query));
      begin
         Require
           (Has (Response, "204 No Content")
            and then Has (Response, "x-amz-version-id: null" & CRLF),
            "DeleteObjectTagging omitted the unversioned identity");
      end;
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket/object", Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "<TagSet></TagSet>")
            and then not Has (Response, "<Key>"),
            "DeleteObjectTagging did not atomically clear the tag set");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("DELETE", "/test-bucket/object", Query, "unexpected")),
            "400 Bad Request"),
         "DeleteObjectTagging accepted a request body");
   end;

   declare
      Put_Response : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/sdk-x-id", "sdk body",
            Query_Name => "x-id", Query_Value => "PutObject"));
      Get_Response : constant String := Run
        (Signed_Request
           ("GET", "/test-bucket/sdk-x-id", "",
            Query_Name => "x-id", Query_Value => "GetObject"));
      Head_Response : constant String := Run
        (Signed_Request
           ("HEAD", "/test-bucket/sdk-x-id", "",
            Query_Name => "x-id", Query_Value => "HeadObject"));
      Delete_Response : constant String := Run
        (Signed_Request
           ("DELETE", "/test-bucket/sdk-x-id", "",
            Query_Name => "x-id", Query_Value => "DeleteObject"));
   begin
      Require
        (Has (Put_Response, "200 OK")
         and then Has (Get_Response, "200 OK")
         and then Has (Get_Response, "sdk body")
         and then Has (Head_Response, "200 OK")
         and then Has (Delete_Response, "204 No Content"),
         "AWS SDK x-id ordinary operation routing failed");
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/test-bucket/object", "",
                  Query_Name => "x-id", Query_Value => "PutObject")),
            "400 Bad Request"),
         "mismatched AWS SDK x-id operation was accepted");
   end;

   declare
      Response : constant String := Run
        (Signed_Request ("HEAD", "/test-bucket/object", ""));
   begin
      Require
        (Has (Response, "200 OK"),
         "HeadObject failed: " & Response);
      Require
        (Has (Response, "ETag: ""5eb63bbbe01eeed093cb22bb8f5acdc3"""),
         "HeadObject ETag mismatch");
      Require
        (Has (Response, "Content-Length: 11" & CRLF),
         "HeadObject did not declare the stored object length");
      Require
        (Has (Response, "Last-Modified: ")
         and then Has (Response, " GMT" & CRLF),
         "HeadObject did not emit an HTTP Last-Modified value");
      Require
        (not Has (Response, "Transfer-Encoding:"),
         "HeadObject used streaming transfer coding");
      Require (not Has (Response, "hello world"),
               "HeadObject emitted an object body");
   end;

   declare
      Matching_ETag : constant String :=
        """5eb63bbbe01eeed093cb22bb8f5acdc3""";
      Range_Response : constant String := Run
        (Signed_Request
           ("HEAD", "/test-bucket/object", "",
            Extra_Headers => "Range: bytes=1-4" & CRLF));
      Unsatisfied_Response : constant String := Run
        (Signed_Request
           ("HEAD", "/test-bucket/object", "",
            Extra_Headers => "Range: bytes=99-100" & CRLF));
      Failed_Match_Response : constant String := Run
        (Signed_Request
           ("HEAD", "/test-bucket/object", "",
            Extra_Headers => "If-Match: ""different""" & CRLF));

      function Head_With (Headers : String) return String is
        (Run
           (Signed_Request
              ("HEAD", "/test-bucket/object", "",
               Extra_Headers => Headers)));
   begin
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/test-bucket/object", "",
                  Extra_Headers => "If-Match: " & Matching_ETag & CRLF)),
            "200 OK"),
         "HeadObject rejected a matching If-Match");
      Require
        (Has (Failed_Match_Response, "HTTP/1.1 412 "),
         "HeadObject ignored a failing If-Match: " & Failed_Match_Response);
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/test-bucket/object", "",
                  Extra_Headers =>
                    "If-None-Match: " & Matching_ETag & CRLF)),
            "HTTP/1.1 304 "),
         "HeadObject ignored a matching If-None-Match");
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/test-bucket/object", "",
                  Extra_Headers =>
                    "If-None-Match: ""different""" & CRLF)),
            "200 OK"),
         "HeadObject rejected a nonmatching If-None-Match");
      Require
        (Has
           (Head_With
              ("If-None-Match: W/" & Matching_ETag & CRLF),
            "HTTP/1.1 304 "),
         "HeadObject did not use weak comparison for If-None-Match");
      Require
        (Has (Head_With ("If-None-Match: *" & CRLF), "HTTP/1.1 304 "),
         "HeadObject rejected wildcard If-None-Match");
      Require
        (Has
           (Head_With
              ("If-Match: " & Matching_ETag & CRLF &
               "If-Unmodified-Since: Thu, 01 Jan 1970 00:00:00 GMT" &
               CRLF),
            "200 OK"),
         "HeadObject If-Match did not override If-Unmodified-Since");
      Require
        (Has
           (Head_With
              ("If-None-Match: ""different""" & CRLF &
               "If-Modified-Since: Fri, 01 Jan 2099 00:00:00 GMT" &
               CRLF),
            "200 OK"),
         "HeadObject If-None-Match did not override If-Modified-Since");
      Require
        (Has
           (Head_With
              ("If-Modified-Since: Fri, 01 Jan 2099 00:00:00 GMT" &
               CRLF),
            "HTTP/1.1 304 "),
         "HeadObject ignored a future If-Modified-Since");
      Require
        (Has
           (Head_With
              ("If-Modified-Since: Thu, 01 Jan 1970 00:00:00 GMT" &
               CRLF),
            "200 OK"),
         "HeadObject rejected a past If-Modified-Since");
      Require
        (Has
           (Head_With
              ("If-Unmodified-Since: Thu, 01 Jan 1970 00:00:00 GMT" &
               CRLF),
            "HTTP/1.1 412 "),
         "HeadObject ignored a failed If-Unmodified-Since");
      Require
        (Has
           (Head_With
              ("If-Unmodified-Since: Fri, 01 Jan 2099 00:00:00 GMT" &
               CRLF),
            "200 OK"),
         "HeadObject rejected a future If-Unmodified-Since");
      Require
        (Has
           (Head_With
              ("If-Unmodified-Since: Thursday, 01-Jan-14 00:00:00 GMT" &
               CRLF),
            "HTTP/1.1 412 "),
         "HeadObject rejected an RFC 850 conditional date");
      Require
        (Has
           (Head_With
              ("If-Modified-Since: Fri Jan  1 00:00:00 2099" & CRLF),
            "HTTP/1.1 304 "),
         "HeadObject rejected an asctime conditional date");
      Require
        (Has
           (Head_With
              ("If-Modified-Since: Sun, 31 Feb 1994 08:49:37 GMT" &
               CRLF),
            "400 Bad Request"),
         "HeadObject accepted an impossible conditional date");
      Require
        (Has
           (Head_With ("If-Match: *, ""different""" & CRLF),
            "400 Bad Request"),
         "HeadObject accepted a mixed wildcard entity-tag list");
      Require
        (Has
           (Head_With
              ("If-Match: " & Matching_ETag & CRLF &
               "If-Match: " & Matching_ETag & CRLF),
            "400 Bad Request"),
         "HeadObject accepted duplicate conditional headers");
      Require
        (Has (Range_Response, "HTTP/1.1 200 ")
         and then not Has (Range_Response, "Content-Range:")
         and then Has (Range_Response, "Content-Length: 4" & CRLF)
         and then not Has (Range_Response, "hello world"),
         "HeadObject range response mismatch: " & Range_Response);
      Require
        (Has (Unsatisfied_Response, "HTTP/1.1 416 ")
         and then Has (Unsatisfied_Response, "Content-Range: bytes */11"),
         "HeadObject unsatisfied range response mismatch");
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/test-bucket/object", "",
                  Extra_Headers => "Range: units=1-4" & CRLF)),
            "400 Bad Request"),
         "HeadObject accepted a malformed Range");
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/test-bucket/object", "",
                  Extra_Headers =>
                    "Range: bytes=0-1" & CRLF &
                    "Range: bytes=2-3" & CRLF)),
            "400 Bad Request"),
         "HeadObject accepted a duplicate Range");
   end;

   declare
      X_ID : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("x-id", "HeadObject"));

      function Head_Control
        (Headers           : String;
         Scheme            : Flyology.HTTP.Origin_Scheme :=
           Flyology.HTTP.Plain_HTTP;
         Corrupt_Signature : Boolean := False) return String is
        (Run
           (Signed_Query_Body_Request
              ("HEAD", "/test-bucket/object", X_ID, "", Headers,
               Corrupt_Signature => Corrupt_Signature),
            Scheme => Scheme));
   begin
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("HEAD", "/test-bucket/object", "test-principal")),
            "200 OK"),
         "HeadObject rejected the expected bucket owner");
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("HEAD", "/test-bucket/object", "another-principal")),
            "403 Forbidden"),
         "HeadObject ignored an expected-owner mismatch");
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("HEAD", "/test-bucket/object", "test-principal",
                  "test-principal")),
            "400 Bad Request"),
         "HeadObject accepted duplicate expected-owner headers");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", X_ID,
                  "x-amz-checksum-mode", "ENABLED")),
            "200 OK"),
         "HeadObject rejected enabled checksum mode");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", X_ID,
                  "x-amz-checksum-mode", "DISABLED")),
            "400 Bad Request"),
         "HeadObject accepted invalid checksum mode");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", X_ID,
                  "x-amz-request-payer", "requester")),
            "200 OK"),
         "HeadObject rejected requester-pays acknowledgement");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", X_ID,
                  "x-amz-request-payer", "invalid")),
            "400 Bad Request"),
         "HeadObject accepted invalid request-payer policy");
      Require
        (Has
           (Head_Control ("x-amz-request-payer: " & CRLF),
            "400 Bad Request"),
         "HeadObject accepted an empty request payer");
      Require
        (Has
           (Head_Control
              ("x-amz-request-payer: requester" & CRLF &
               "x-amz-request-payer: requester" & CRLF),
            "400 Bad Request"),
         "HeadObject accepted duplicate request-payer headers");
      Require
        (Has
           (Head_Control ("x-amz-checksum-mode: " & CRLF),
            "400 Bad Request"),
         "HeadObject accepted an empty checksum mode");
      Require
        (Has
           (Head_Control ("x-amz-expected-bucket-owner: " & CRLF),
            "400 Bad Request"),
         "HeadObject accepted an empty expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", X_ID,
                  "x-amz-server-side-encryption", "AES256")),
            "400 Bad Request"),
         "HeadObject accepted a write-only encryption method header");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", X_ID,
                  "x-amz-server-side-encryption-customer-algorithm",
                  "AES256")),
            "400 Bad Request"),
         "HeadObject accepted an incomplete SSE-C group");
      Require
        (Has
           (Head_Control
              ("x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF &
               "x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF & "x-amz-server-side-encryption-customer-key: " &
               SSE_Test_Key & CRLF &
               "x-amz-server-side-encryption-customer-key-md5: " &
               SSE_Test_Key_MD5 & CRLF,
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "400 Bad Request"),
         "HeadObject accepted duplicate SSE-C headers");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256",
                  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                  "AAAAAAAAAAAAAAAAAAAAAA=="),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "400 Bad Request"),
         "HeadObject accepted an SSE-C key/digest mismatch");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256", SSE_Test_Key, SSE_Test_Key_MD5)),
            "400 Bad Request"),
         "HeadObject accepted SSE-C over plaintext");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256", SSE_Test_Key, SSE_Test_Key_MD5),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "400 Bad Request"),
         "HeadObject accepted SSE-C for an unencrypted object");
      Require
        (Has
           (Head_Control
              ("x-amz-request-payer: invalid" & CRLF &
               "x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF,
               Corrupt_Signature => True),
            "403 Forbidden"),
         "HeadObject controls ran before authentication");
      Require
        (Has
           (Run
              (Signed_Request
                  ("HEAD", "/test-bucket/object", "",
                   Extra_Headers =>
                    "If-Modified-Since: Fri, 01 Jan 2099 00:00:00 GMT" &
                    CRLF)),
            "HTTP/1.1 304 "),
         "HeadObject ignored a future If-Modified-Since date");
   end;

   declare
      Version : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versionId", "version-one"));
      Null_Version : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versionId", "null"));
      Part : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("partNumber", "1"));
      Missing_Part : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("partNumber", "2"));
      Override : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("response-cache-control", "no-store"),
         SigV4.Pair ("response-content-disposition", "attachment"),
         SigV4.Pair ("response-content-encoding", "identity"),
         SigV4.Pair ("response-content-language", "en-CA"),
         SigV4.Pair ("response-content-type", "application/octet-stream"),
         SigV4.Pair ("response-expires", "Fri, 24 May 2013 01:00:00 GMT"));
      Invalid_Override : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair
           ("response-content-disposition",
            "attachment" & Character'Val (1) & "unsafe"));
      Duplicate : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("partNumber", "1"),
         SigV4.Pair ("partNumber", "2"));
      Unknown : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("unknown", "value"));
   begin
      Require
        (Has
           (Run (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Version)),
            "404 Not Found"),
         "HeadObject found an unknown exact generation");
      declare
         Response : constant String := Run
           (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Null_Version));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "x-amz-version-id: null" & CRLF),
            "HeadObject rejected the null unversioned selector");
      end;
      declare
         Response : constant String := Run
           (Signed_Query_Request ("HEAD", "/test-bucket/object", Part));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Length: 11" & CRLF)
            and then not Has (Response, "x-amz-mp-parts-count:"),
            "HeadObject implicit ordinary-object part 1 mismatch");
      end;
      Require
        (Has
           (Run (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Missing_Part)),
            "HTTP/1.1 416 "),
         "HeadObject accepted an absent ordinary-object part");
      declare
         Response : constant String := Run
           (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Override));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Cache-Control: no-store" & CRLF)
            and then Has (Response, "Content-Disposition: attachment" & CRLF)
            and then Has (Response, "Content-Encoding: identity" & CRLF)
            and then Has (Response, "Content-Language: en-CA" & CRLF)
            and then Has
              (Response, "Content-Type: application/octet-stream" & CRLF)
            and then Has
              (Response,
               "Expires: Fri, 24 May 2013 01:00:00 GMT" & CRLF),
            "HeadObject response overrides were not emitted exactly");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("HEAD", "/test-bucket/object", Invalid_Override)),
            "400 Bad Request"),
         "HeadObject accepted a control byte in a response override");
      Require
        (Has
           (Run (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Duplicate)),
            "400 Bad Request"),
         "HeadObject accepted a duplicate query member");
      Require
        (Has
           (Run (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Unknown)),
            "400 Bad Request"),
         "HeadObject accepted an unknown query member");
   end;

   declare
      Response : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/chunked", "Wikipedia",
            Chunked => True),
         Receive_Max => 1);
   begin
      Require (Has (Response, "200 OK"), "chunked PutObject failed");
   end;

   declare
      Response : constant String := Run
        (Signed_Request ("GET", "/test-bucket/object", ""));
   begin
      Require (Has (Response, "200 OK"), "GetObject failed");
      Require
        (Has (Response, "Content-Length: 11" & CRLF)
         and then not Has (Response, "Transfer-Encoding:"),
         "GetObject did not use exact fixed-length framing");
      Require (Has (Response, "hello world"),
               "GetObject did not stream the stored payload");
   end;

   declare
      Response : constant String := Run
        (Signed_Request
           ("GET", "/test-bucket/object", "",
            Extra_Headers => "Range: bytes=-5" & CRLF));
   begin
      Require (Has (Response, "206 Partial Content"),
               "suffix range did not return 206");
      Require (Has (Response, "Content-Range: bytes 6-10/11"),
               "suffix range metadata mismatch");
      Require
        (Has (Response, "Content-Length: 5" & CRLF)
         and then not Has (Response, "Transfer-Encoding:"),
         "range response did not use exact fixed-length framing");
      Require (Has (Response, "world"), "suffix range body mismatch");
   end;

   declare
      ETag : constant String := "5eb63bbbe01eeed093cb22bb8f5acdc3";

      function Get_With (Headers : String) return String is
        (Run
           (Signed_Request
              ("GET", "/test-bucket/object", "",
               Extra_Headers => Headers)));
   begin
      Require
        (Has
           (Get_With ("If-Match: """ & ETag & """" & CRLF),
            "200 OK")
         and then Has
           (Get_With ("If-Match: """ & ETag & """" & CRLF),
            "hello world"),
         "GetObject rejected a matching If-Match");
      Require
        (Has (Get_With ("If-Match: ""wrong""" & CRLF),
              "HTTP/1.1 412 "),
         "GetObject accepted a failed If-Match");
      Require
        (Has
           (Get_With ("If-None-Match: W/""" & ETag & """" & CRLF),
            "HTTP/1.1 304 ")
         and then not Has
           (Get_With ("If-None-Match: W/""" & ETag & """" & CRLF),
            "hello world"),
         "GetObject weak If-None-Match did not suppress the body");
      Require
        (Has (Get_With ("If-None-Match: *" & CRLF), "HTTP/1.1 304 "),
         "GetObject wildcard If-None-Match did not suppress the body");
      Require
        (Has
           (Get_With
              ("If-Modified-Since: Fri, 01 Jan 2099 00:00:00 GMT" &
               CRLF),
            "HTTP/1.1 304 "),
         "GetObject ignored a future If-Modified-Since");
      Require
        (Has
           (Get_With
              ("If-Unmodified-Since: Thu, 01 Jan 1970 00:00:00 GMT" &
               CRLF),
            "HTTP/1.1 412 "),
         "GetObject ignored a failed If-Unmodified-Since");
      Require
        (Has
           (Get_With
              ("If-Match: """ & ETag & """" & CRLF &
               "If-Unmodified-Since: Thu, 01 Jan 1970 00:00:00 GMT" &
               CRLF),
            "200 OK"),
         "If-Match did not take precedence over If-Unmodified-Since");
      Require
        (Has
           (Get_With
              ("If-None-Match: ""other""" & CRLF &
               "If-Modified-Since: Fri, 01 Jan 2099 00:00:00 GMT" &
               CRLF),
            "200 OK"),
         "If-None-Match did not take precedence over If-Modified-Since");
      Require
        (Has
           (Get_With ("If-Match: *, ""other""" & CRLF),
            "400 Bad Request"),
         "GetObject accepted a mixed wildcard entity-tag list");
      Require
        (Has
           (Get_With
              ("If-Modified-Since: Sun, 31 Feb 1994 08:49:37 GMT" & CRLF),
            "400 Bad Request"),
         "GetObject accepted an impossible conditional date");
      Require
        (Has
           (Get_With
              ("If-Match: """ & ETag & """" & CRLF &
               "If-Match: """ & ETag & """" & CRLF),
            "400 Bad Request"),
         "GetObject accepted duplicate conditional headers");

      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("GET", "/test-bucket/object", "test-principal")),
            "200 OK"),
         "GetObject rejected its actual expected owner");
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("GET", "/test-bucket/object", "another-principal")),
            "403 Forbidden"),
         "GetObject ignored an expected-owner mismatch");
      Require
        (Has
           (Run
              (Signed_Bucket_Request
                 ("GET", "/test-bucket/object", "test-principal",
                  "test-principal")),
            "400 Bad Request"),
         "GetObject accepted duplicate expected-owner headers");
   end;

   declare
      X_ID : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("x-id", "GetObject"));
      Overrides : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("response-cache-control", "no-cache"),
         SigV4.Pair ("response-content-disposition", "attachment"),
         SigV4.Pair ("response-content-encoding", "identity"),
         SigV4.Pair ("response-content-language", "en-CA"),
         SigV4.Pair ("response-content-type", "text/plain"),
         SigV4.Pair ("response-expires",
                     "Fri, 01 Jan 2099 00:00:00 GMT"),
         SigV4.Pair ("x-id", "GetObject"));
      Version_Null : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versionId", "null"));
      Version_Other : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versionId", "version-one"));
      Part : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("partNumber", "1"));
      Unknown : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("unknown", "value"));
      Response : constant String := Run
        (Signed_Query_Request
           ("GET", "/test-bucket/object", Overrides));

      function Get_Control
        (Headers           : String;
         Scheme            : Flyology.HTTP.Origin_Scheme :=
           Flyology.HTTP.Plain_HTTP;
         Corrupt_Signature : Boolean := False) return String is
        (Run
           (Signed_Query_Body_Request
              ("GET", "/test-bucket/object", X_ID, "", Headers,
               Corrupt_Signature => Corrupt_Signature),
            Scheme => Scheme));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "Cache-Control: no-cache" & CRLF)
         and then Has (Response, "Content-Disposition: attachment" & CRLF)
         and then Has (Response, "Content-Encoding: identity" & CRLF)
         and then Has (Response, "Content-Language: en-CA" & CRLF)
         and then Has (Response, "Content-Type: text/plain" & CRLF)
         and then Has
           (Response, "Expires: Fri, 01 Jan 2099 00:00:00 GMT" & CRLF)
         and then Has (Response, "hello world"),
         "GetObject response overrides were not projected exactly");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/object", Version_Null)),
            "200 OK"),
         "GetObject rejected the null unversioned version ID");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/object", Version_Other)),
            "404 Not Found"),
         "GetObject found an unknown exact generation");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/object", Part)),
            "501 Not Implemented"),
         "GetObject silently ignored partNumber");
      Require
        (Has
           (Run (Signed_Query_Request
              ("GET", "/test-bucket/object", Unknown)),
            "400 Bad Request"),
         "GetObject accepted an unknown query member");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", X_ID,
                  "x-amz-request-payer", "requester")),
            "200 OK"),
         "GetObject rejected valid requester-pays syntax");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", X_ID,
                  "x-amz-request-payer", "owner")),
            "400 Bad Request"),
         "GetObject accepted an invalid request payer");
      Require
        (Has
           (Get_Control ("x-amz-request-payer: " & CRLF),
            "<Code>InvalidRequest</Code>"),
         "GetObject accepted an empty request payer");
      Require
        (Has
           (Get_Control
              ("x-amz-request-payer: requester" & CRLF &
               "x-amz-request-payer: requester" & CRLF),
            "<Code>InvalidRequest</Code>"),
         "GetObject accepted duplicate request-payer headers");
      Require
        (Has
           (Get_Control ("x-amz-checksum-mode: " & CRLF),
            "<Code>InvalidRequest</Code>"),
         "GetObject accepted an empty checksum mode");
      Require
        (Has
           (Get_Control ("x-amz-expected-bucket-owner: " & CRLF),
            "<Code>InvalidRequest</Code>"),
         "GetObject accepted an empty expected owner");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", X_ID,
                  "x-amz-checksum-mode", "ENABLED")),
            "200 OK"),
         "GetObject rejected enabled checksum mode");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", X_ID,
                  "x-amz-checksum-mode", "DISABLED")),
            "400 Bad Request"),
         "GetObject accepted an invalid checksum mode");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", X_ID,
                  "x-amz-server-side-encryption", "AES256")),
            "400 Bad Request"),
         "GetObject accepted a write-only encryption method header");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket/object", X_ID,
                  "x-amz-server-side-encryption-customer-algorithm",
                  "AES256")),
            "400 Bad Request"),
         "GetObject accepted an incomplete SSE-C header group");
      Require
        (Has
           (Get_Control
              ("x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF &
               "x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF & "x-amz-server-side-encryption-customer-key: " &
               SSE_Test_Key & CRLF &
               "x-amz-server-side-encryption-customer-key-md5: " &
               SSE_Test_Key_MD5 & CRLF,
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>InvalidRequest</Code>"),
         "GetObject accepted duplicate SSE-C headers");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256",
                  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                  "AAAAAAAAAAAAAAAAAAAAAA==", Method => "GET"),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>InvalidDigest</Code>"),
         "GetObject accepted an SSE-C key/digest mismatch");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES128", SSE_Test_Key, SSE_Test_Key_MD5,
                  Method => "GET"),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>InvalidArgument</Code>"),
         "GetObject accepted an invalid SSE-C algorithm");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256", "malformed", SSE_Test_Key_MD5,
                  Method => "GET"),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>InvalidDigest</Code>"),
         "GetObject accepted a malformed SSE-C key");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256", SSE_Test_Key, SSE_Test_Key_MD5,
                  Method => "GET")),
            "<Code>InvalidRequest</Code>"),
         "GetObject accepted SSE-C over plaintext");
      Require
        (Has
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256", SSE_Test_Key, SSE_Test_Key_MD5,
                  Method => "GET"),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "501 Not Implemented"),
         "GetObject did not classify valid secure SSE-C explicitly");
      Require
        (Has
           (Get_Control
              ("x-amz-request-payer: invalid" & CRLF &
               "x-amz-server-side-encryption-customer-algorithm: AES256" &
               CRLF,
               Corrupt_Signature => True),
            "<Code>SignatureDoesNotMatch</Code>"),
         "GetObject controls ran before authentication");
   end;

   declare
      Wrong_Hash : constant String := String'(1 .. 64 => '0');
      Response : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/object", "corrupt",
            Hash_Override => Wrong_Hash));
   begin
      Require (Has (Response, "400 Bad Request"),
               "payload hash mismatch was not rejected");
      Require (Has (Response, "XAmzContentSHA256Mismatch"),
               "payload hash mismatch did not use typed S3 error");
      Require
        (Has (Run (Signed_Request ("GET", "/test-bucket/object", "")),
              "hello world"),
         "hash-mismatched upload changed the committed object");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Require
        (Has (Run (Signed_Request ("PUT", "/delete-bucket", "")),
              "200 OK"),
         "DeleteObjects bucket setup failed");
      Require
        (Has (Run (Signed_Request
          ("PUT", "/delete-bucket/multi-a", "a")), "200 OK"),
         "DeleteObjects setup A failed");
      Require
        (Has (Run (Signed_Request
          ("PUT", "/delete-bucket/multi-b", "b")), "200 OK"),
         "DeleteObjects setup B failed");
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("multi-a"),
          Version_ID => US.Null_Unbounded_String,
          others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("multi-b"),
          Version_ID => US.Null_Unbounded_String,
          others     => <>));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
         Response : constant String := Run
           (Signed_Request
              ("POST", "/delete-bucket", Payload,
               Extra_Headers =>
                 "Content-MD5: " & Content_MD5 (Payload) & CRLF,
               Query_Name => "delete"));
      begin
         Require
           (Has (Response, "200 OK"),
            "DeleteObjects failed: " & Response);
         Require
           (Has (Response, "<Key>multi-a</Key>")
            and then Has (Response, "<Key>multi-b</Key>"),
            "DeleteObjects response omitted deleted keys");
      end;
      Require
        (Has (Run (Signed_Request
          ("HEAD", "/delete-bucket/multi-a", "")), "404 Not Found"),
         "DeleteObjects left its first key visible");
      Require
        (Has (Run (Signed_Request
          ("HEAD", "/delete-bucket/multi-b", "")), "404 Not Found"),
         "DeleteObjects left its second key visible");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Request.Quiet := True;
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("already-absent"),
          Version_ID => US.Null_Unbounded_String,
          others     => <>));
      declare
         Response : constant String := Run
           (Signed_Request
              ("POST", "/delete-bucket",
               Deletions.Serialize_Request (Request),
               Extra_Headers =>
                 "Content-MD5: " &
                 Content_MD5 (Deletions.Serialize_Request (Request)) & CRLF,
               Query_Name => "delete"));
      begin
         Require (Has (Response, "200 OK"), "quiet DeleteObjects failed");
         Require
           (not Has (Response, "<Deleted>"),
            "quiet DeleteObjects emitted a success entry");
      end;
      Request.Quiet := False;
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
         Response : constant String :=
           Run (Signed_Delete_Objects_Request (Payload));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "<Key>already-absent</Key>"),
            "DeleteObjects did not report an idempotent missing-key success");
      end;
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
      Bucket  : constant String := "batch-versioned-bucket";
      Exact_Info    : Flyology.Object_Storage.Object_Information;
      Current_Info  : Flyology.Object_Storage.Object_Information;
      Mismatch_Info : Flyology.Object_Storage.Object_Information;
      Storage_Result : Flyology.Object_Storage.Status;
   begin
      Require
        (Has
           (Run (Signed_Create_Bucket_Request ("/" & Bucket, "")),
            "200 OK"),
         "generation-aware DeleteObjects bucket setup failed");
      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          others => <>),
         null, Ada.Real_Time.Time_Last, Storage_Result);
      Require
        (Storage_Result = Flyology.Object_Storage.Success,
         "generation-aware DeleteObjects versioning setup failed");
      Require
        (Has
           (Run (Signed_Request
              ("PUT", "/" & Bucket & "/exact", "exact-body")),
            "200 OK"),
         "generation-aware DeleteObjects exact setup failed");
      Require
        (Has
           (Run (Signed_Request
              ("PUT", "/" & Bucket & "/current", "current-body")),
            "200 OK"),
         "generation-aware DeleteObjects current setup failed");
      Require
        (Has
           (Run (Signed_Request
              ("PUT", "/" & Bucket & "/mismatch", "preserve")),
            "200 OK"),
         "generation-aware DeleteObjects mismatch setup failed");
      Store.Head_Object
        (Bucket, "exact", null, Ada.Real_Time.Time_Last,
         Exact_Info, Storage_Result);
      Store.Head_Object
        (Bucket, "current", null, Ada.Real_Time.Time_Last,
         Current_Info, Storage_Result);
      Store.Head_Object
        (Bucket, "mismatch", null, Ada.Real_Time.Time_Last,
         Mismatch_Info, Storage_Result);
      Require
        (Storage_Result = Flyology.Object_Storage.Success
         and then US.Length (Exact_Info.Version) > 0
         and then US.Length (Current_Info.Version) > 0
         and then US.Length (Mismatch_Info.Version) > 0,
         "generation-aware DeleteObjects identities were not retained");
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("exact"),
          Version_ID => Exact_Info.Version,
          others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("current"),
          Version_ID => US.Null_Unbounded_String,
          others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("missing"),
          Version_ID => US.To_Unbounded_String ("missing-generation"),
          others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("mismatch"),
          Version_ID => Mismatch_Info.Version,
          Has_ETag   => True,
          ETag       => US.To_Unbounded_String ("not-the-etag"),
          others     => <>));
      declare
         Payload  : constant String := Deletions.Serialize_Request (Request);
         Response : constant String :=
           Run
             (Signed_Delete_Objects_Request
                (Payload, Bucket => "/" & Bucket));
         Parsed : constant Deletions.Delete_Objects_Result :=
           Deletions.Parse_Result (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then Parsed.Deleted.Length = 3
            and then Parsed.Errors.Length = 1,
            "generation-aware DeleteObjects result cardinality mismatch: " &
              Response);
         Require
           (US.To_String (Parsed.Deleted (1).Key) = "exact"
            and then US."="
              (Parsed.Deleted (1).Version_ID, Exact_Info.Version)
            and then not Parsed.Deleted (1).Delete_Marker.Is_Set
            and then
              US.To_String (Parsed.Deleted (2).Key) = "current"
            and then US.Length (Parsed.Deleted (2).Version_ID) = 0
            and then Parsed.Deleted (2).Delete_Marker.Is_Set
            and then Parsed.Deleted (2).Delete_Marker.Value
            and then
              US.Length
                (Parsed.Deleted (2).Delete_Marker_Version_ID) > 0
            and then US.To_String (Parsed.Deleted (3).Key) = "missing"
            and then US.To_String (Parsed.Deleted (3).Version_ID) =
              "missing-generation"
            and then not Parsed.Deleted (3).Delete_Marker.Is_Set,
            "generation-aware DeleteObjects success identities mismatch");
         Require
           (US.To_String (Parsed.Errors (1).Key) = "mismatch"
            and then US."="
              (Parsed.Errors (1).Version_ID, Mismatch_Info.Version)
            and then US.To_String (Parsed.Errors (1).Code) =
              "PreconditionFailed",
            "generation-aware DeleteObjects conditional error mismatch");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/" & Bucket & "/exact",
                  (1 => SigV4.Pair
                     ("versionId", US.To_String (Exact_Info.Version))))),
            "404 Not Found"),
         "generation-aware DeleteObjects retained its exact target");
      Require
        (Has
           (Run (Signed_Request
              ("HEAD", "/" & Bucket & "/current", "")),
            "404 Not Found"),
         "generation-aware DeleteObjects did not publish a current marker");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/" & Bucket & "/mismatch",
                  (1 => SigV4.Pair
                     ("versionId", US.To_String (Mismatch_Info.Version))))),
            "preserve"),
         "generation-aware DeleteObjects changed a rejected exact target");
      declare
         MFA_Exact : Flyology.Object_Storage.Object_Information;
         MFA_Request : Deletions.Delete_Objects_Request;
      begin
         Require
           (Has
              (Run (Signed_Request
                 ("PUT", "/" & Bucket & "/mfa-current", "current")),
               "200 OK"),
            "MFA DeleteObjects current setup failed");
         Require
           (Has
              (Run (Signed_Request
                 ("PUT", "/" & Bucket & "/mfa-exact", "exact")),
               "200 OK"),
            "MFA DeleteObjects exact setup failed");
         Store.Head_Object
           (Bucket, "mfa-exact", null, Ada.Real_Time.Time_Last,
            MFA_Exact, Storage_Result);
         Store.Put_Bucket_Versioning
           (Bucket,
            (MFA_Delete => Flyology.Object_Storage.MFA_Delete_Enabled,
             others => <>), null, Ada.Real_Time.Time_Last, Storage_Result,
            MFA_Validated => True);
         Require
           (Storage_Result = Flyology.Object_Storage.Success,
            "MFA DeleteObjects policy setup failed");
         MFA_Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key => US.To_Unbounded_String ("mfa-current"),
               Version_ID => US.Null_Unbounded_String,
               others => <>));
         MFA_Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key => US.To_Unbounded_String ("mfa-exact"),
               Version_ID => MFA_Exact.Version,
               others => <>));
         declare
            Response : constant String :=
              Run
                (Signed_Delete_Objects_Request
                   (Deletions.Serialize_Request (MFA_Request),
                    Bucket => "/" & Bucket));
         begin
            Require
              (Has (Response, "403 Forbidden")
               and then Has (Response, "<Code>AccessDenied</Code>"),
               "MFA DeleteObjects did not reject the complete request");
         end;
         Require
           (Has
              (Run (Signed_Request
                 ("GET", "/" & Bucket & "/mfa-current", "")),
               "current"),
            "rejected MFA DeleteObjects changed its current sibling");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/" & Bucket & "/mfa-exact",
                     (1 => SigV4.Pair
                        ("versionId", US.To_String (MFA_Exact.Version))))),
               "exact"),
            "rejected MFA DeleteObjects changed its exact target");
         Store.Put_Bucket_Versioning
           (Bucket,
            (MFA_Delete => Flyology.Object_Storage.MFA_Delete_Disabled,
             others => <>), null, Ada.Real_Time.Time_Last, Storage_Result,
            MFA_Validated => True);
         Require
           (Storage_Result = Flyology.Object_Storage.Success,
            "MFA DeleteObjects policy cleanup failed");
      end;
      declare
         Page     : Backends.List_Versions_Page;
         Entries  : Backends.Delete_Object_Entries;
         Outcomes : Backends.Delete_Object_Outcomes;
      begin
         Store.List_Object_Versions
           (Bucket, (others => <>), null, Ada.Real_Time.Time_Last,
            Page, Storage_Result);
         Require
           (Storage_Result = Flyology.Object_Storage.Success
            and then not Page.Is_Truncated,
            "generation-aware DeleteObjects cleanup listing failed");
         for Version of Page.Entries loop
            Entries.Append
              (Backends.Delete_Object_Entry'
                 (Key => Version.Key,
                  Selector =>
                    (Kind => Backends.Exact_Version,
                     ID   => Version.Version_ID),
                  Conditions => Backends.No_Delete_Object_Conditions));
         end loop;
         Store.Delete_Objects
           (Bucket, Entries, (others => <>), null,
            Ada.Real_Time.Time_Last, Outcomes, Storage_Result);
         Require
           (Storage_Result = Flyology.Object_Storage.Success
            and then Outcomes.Length = Entries.Length,
            "generation-aware DeleteObjects cleanup batch failed");
      end;
      Store.Delete_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Storage_Result);
      Require
        (Storage_Result = Flyology.Object_Storage.Success,
         "generation-aware DeleteObjects bucket cleanup failed");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("unsupported-version"),
            Version_ID => US.To_Unbounded_String ("version-id"),
            others     => <>));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
         Response : constant String :=
           Run
             (Signed_Delete_Objects_Request
                (Payload, Bucket => "/missing-delete-objects-bucket"));
      begin
         Require
           (Has (Response, "404 Not Found")
            and then Has (Response, "<Code>NoSuchBucket</Code>"),
            "all-unsupported DeleteObjects masked a missing bucket: " &
            Response);
      end;
   end;

   declare
      Malformed : constant String :=
        "<Delete><Object><VersionId>v</VersionId></Object></Delete>";
      Response : constant String := Run
        (Signed_Request
           ("POST", "/delete-bucket", Malformed,
            Extra_Headers =>
              "Content-MD5: " & Content_MD5 (Malformed) & CRLF,
            Query_Name => "delete"));
   begin
      Require
         (Has (Response, "400 Bad Request")
          and then Has (Response, "MalformedXML"),
         "malformed DeleteObjects XML response mismatch: " & Response);
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Request.Quiet := True;
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("checksum-absent"),
            Version_ID => US.Null_Unbounded_String,
            others     => <>));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
      begin
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload, Include_MD5 => False)),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted a missing Content-MD5");
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload, MD5_Value => "not-base64")),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted a malformed Content-MD5");
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload, MD5_Value => Content_MD5 (Payload & "x"))),
               "<Code>BadDigest</Code>"),
            "DeleteObjects misreported a mismatched Content-MD5");
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload,
                     Extra_Headers =>
                       "Content-MD5: " & Content_MD5 (Payload) & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted duplicate Content-MD5 fields");

         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload,
                     Extra_Headers =>
                       "x-amz-sdk-checksum-algorithm: CRC32" & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted a checksum algorithm without a value");

         for Algorithm in Checksum_Policy.Algorithm loop
            declare
               Response : constant String :=
                 Run
                   (Signed_Delete_Objects_Request
                      (Payload,
                       Extra_Headers =>
                         "x-amz-sdk-checksum-algorithm: " &
                         Checksum_Policy.Wire_Name (Algorithm) & CRLF &
                         Checksum_Header (Algorithm) & ": " &
                         Checksum_Value (Algorithm, Payload) & CRLF));
            begin
               Require
                 (Has (Response, "200 OK"),
                  "DeleteObjects rejected " &
                  Checksum_Policy.Wire_Name (Algorithm) &
                  " checksum: " & Response);
            end;
         end loop;

         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload,
                     Extra_Headers =>
                       "x-amz-checksum-crc32: " &
                       Checksum_Value (Core.CRC32, Payload) & CRLF)),
               "200 OK"),
            "DeleteObjects rejected an inferred checksum algorithm");
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload,
                     Extra_Headers =>
                       "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                       "x-amz-checksum-crc32: " &
                       Checksum_Value (Core.CRC32, Payload) & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted an SDK checksum/header mismatch");
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload,
                     Extra_Headers =>
                       "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
                       "x-amz-checksum-crc32: not-base64" & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted malformed optional checksum Base64");
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload,
                     Extra_Headers =>
                       "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
                       "x-amz-checksum-crc32: " &
                       Checksum_Value (Core.CRC32, Payload & "x") & CRLF)),
               "<Code>BadDigest</Code>"),
            "DeleteObjects misreported an optional checksum mismatch");
      end;
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/delete-bucket/integrity-preserved", "keep")),
            "200 OK"),
         "DeleteObjects integrity setup failed");
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("integrity-preserved"),
            Version_ID => US.Null_Unbounded_String,
            others     => <>));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
      begin
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload, MD5_Value => Content_MD5 (Payload & "x"))),
               "<Code>BadDigest</Code>"),
            "DeleteObjects integrity failure was not rejected");
      end;
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/delete-bucket/integrity-preserved", "")),
            "keep"),
         "rejected DeleteObjects integrity check mutated backend state");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/delete-bucket/control-key", "controls")),
            "200 OK"),
         "DeleteObjects control setup failed");
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("control-key"),
            Version_ID => US.Null_Unbounded_String,
            others     => <>));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
         Response : constant String :=
           Run
             (Signed_Delete_Objects_Request
                (Payload,
                 Extra_Headers =>
                   "x-amz-request-payer: requester" & CRLF &
                   "x-amz-bypass-governance-retention: true" & CRLF &
                   "x-amz-mfa: device 123456" & CRLF &
                   "x-amz-expected-bucket-owner: test-principal" & CRLF));
      begin
         Require
           (Has (Response, "200 OK"),
            "DeleteObjects rejected inactive valid policy controls: " &
            Response);
      end;
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/delete-bucket/control-key", "")),
            "404 Not Found"),
         "DeleteObjects valid inactive controls prevented deletion");

      Require
        (Has
           (Run
              (Signed_Delete_Objects_Request
                 (Deletions.Serialize_Request (Request),
                  Extra_Headers => "x-amz-request-payer: owner" & CRLF)),
            "<Code>InvalidArgument</Code>"),
         "DeleteObjects accepted an invalid request-payer value");
      Require
        (Has
           (Run
              (Signed_Delete_Objects_Request
                 (Deletions.Serialize_Request (Request),
                  Extra_Headers =>
                    "x-amz-bypass-governance-retention: yes" & CRLF)),
            "<Code>InvalidArgument</Code>"),
         "DeleteObjects accepted an invalid governance bypass value");
      Require
        (Has
           (Run
              (Signed_Delete_Objects_Request
                 (Deletions.Serialize_Request (Request),
                  Extra_Headers =>
                    "x-amz-expected-bucket-owner: different-owner" & CRLF)),
            "403 Forbidden"),
         "DeleteObjects ignored a mismatched expected owner");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
      Quoted_Tag : constant String :=
        """18557a5990586964ca9cc6f9869a7b5a""";
   begin
      for Key of
        Key_Array'
          (US.To_Unbounded_String ("condition-quoted"),
           US.To_Unbounded_String ("condition-unquoted"),
           US.To_Unbounded_String ("condition-wildcard"),
           US.To_Unbounded_String ("condition-mismatch"))
      loop
         Require
           (Has
              (Run
                 (Signed_Request
                    ("PUT", "/delete-bucket/" & US.To_String (Key),
                     "etag-body")),
               "200 OK"),
            "DeleteObjects condition setup failed");
      end loop;
      Request.Quiet := True;
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-quoted"),
            Version_ID => US.Null_Unbounded_String,
            Has_ETag   => True,
            ETag       => US.To_Unbounded_String (Quoted_Tag),
            others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-unquoted"),
            Version_ID => US.Null_Unbounded_String,
            Has_ETag   => True,
            ETag       => US.To_Unbounded_String
              ("18557a5990586964ca9cc6f9869a7b5a"),
            others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-wildcard"),
            Version_ID => US.Null_Unbounded_String,
            Has_ETag   => True,
            ETag       => US.To_Unbounded_String ("*"),
            others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-mismatch"),
            Version_ID => US.Null_Unbounded_String,
            Has_ETag   => True,
            ETag       => US.To_Unbounded_String ("different"),
            others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-absent"),
            Version_ID => US.Null_Unbounded_String,
            Has_ETag   => True,
            ETag       => US.To_Unbounded_String ("*"),
            others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-invalid-etag"),
            Version_ID => US.Null_Unbounded_String,
            Has_ETag   => True,
            ETag       => US.To_Unbounded_String ("bad,tag"),
            others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key                    =>
              US.To_Unbounded_String ("condition-valid-date"),
            Version_ID             => US.Null_Unbounded_String,
            Has_Last_Modified_Time => True,
            Last_Modified_Time     =>
              US.To_Unbounded_String ("Wed, 21 Oct 2015 07:28:00 GMT"),
            others                 => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key                    =>
              US.To_Unbounded_String ("condition-invalid-date"),
            Version_ID             => US.Null_Unbounded_String,
            Has_Last_Modified_Time => True,
            Last_Modified_Time     => US.To_Unbounded_String ("not-a-date"),
            others                 => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("condition-size"),
            Version_ID => US.Null_Unbounded_String,
            Has_Size   => True,
            Size       => 9,
            others     => <>));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
         Response : constant String :=
           Run (Signed_Delete_Objects_Request (Payload));
         Mismatch_Position : constant Natural :=
           Ada.Strings.Fixed.Index (Response, "condition-mismatch");
         Absent_Position : constant Natural :=
           Ada.Strings.Fixed.Index (Response, "condition-absent");
         Invalid_ETag_Position : constant Natural :=
           Ada.Strings.Fixed.Index (Response, "condition-invalid-etag");
      begin
         Require
           (Has (Response, "200 OK")
            and then not Has (Response, "<Deleted>")
            and then Has (Response, "PreconditionFailed")
            and then Has (Response, "NoSuchKey")
            and then Has (Response, "The ETag condition is invalid")
            and then Has
              (Response, "The LastModifiedTime condition is invalid")
            and then Has (Response, "directory bucket"),
            "DeleteObjects conditional result mismatch: " & Response);
         Require
           (Mismatch_Position > 0
            and then Mismatch_Position < Absent_Position
            and then Absent_Position < Invalid_ETag_Position,
            "DeleteObjects errors lost request ordering");
      end;
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/delete-bucket/condition-quoted", "")),
            "404 Not Found")
         and then
           Has
             (Run
                (Signed_Request
                   ("HEAD", "/delete-bucket/condition-unquoted", "")),
              "404 Not Found")
         and then
           Has
             (Run
                (Signed_Request
                   ("HEAD", "/delete-bucket/condition-wildcard", "")),
              "404 Not Found"),
         "DeleteObjects matching conditions did not delete their objects");
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/delete-bucket/condition-mismatch", "")),
            "200 OK"),
         "DeleteObjects condition mismatch removed the object");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
      Configuration : Flyology.Object_Storage.Bucket_Versioning_Configuration;
      Backend_Result : Flyology.Object_Storage.Status;
   begin
      Require
        (Has
           (Run (Signed_Request ("PUT", "/delete-race-bucket", "")),
            "200 OK"),
         "DeleteObjects server race bucket setup failed");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/delete-race-bucket/object", "race-body")),
            "200 OK"),
         "DeleteObjects server race object setup failed");
      Flyology.Object_Storage.Backends.Memory.Get_Bucket_Versioning
        (Store, "delete-race-bucket", null, Ada.Real_Time.Time_Last,
         Configuration, Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Success
         and then Configuration.Status =
           Flyology.Object_Storage.Versioning_Unconfigured,
         "DeleteObjects server race did not begin unversioned");
      Flyology.Object_Storage.Backends.Memory.Put_Bucket_Versioning
        (Store, "delete-race-bucket",
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          MFA_Delete => Flyology.Object_Storage.MFA_Delete_Unconfigured),
         null, Ada.Real_Time.Time_Last, Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Success,
         "DeleteObjects server race did not publish versioning");
      Request.Objects.Append
        (Deletions.Object_Identifier'
           (Key        => US.To_Unbounded_String ("object"),
            Version_ID => US.Null_Unbounded_String,
            others     => <>));
      declare
         Response : constant String :=
           Run
             (Signed_Delete_Objects_Request
                (Deletions.Serialize_Request (Request),
                 Bucket => "/delete-race-bucket"));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "<DeleteMarker>true</DeleteMarker>")
            and then Has (Response, "<DeleteMarkerVersionId>"),
            "DeleteObjects did not observe published versioning: " &
              Response);
      end;
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/delete-race-bucket/object", "")),
            "404 Not Found"),
         "DeleteObjects server versioning race did not publish a marker");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/delete-race-bucket/object",
                  (1 => SigV4.Pair ("versionId", "null")))),
            "race-body"),
         "DeleteObjects server marker lost the retained null generation");
      declare
         Page     : Backends.List_Versions_Page;
         Entries  : Backends.Delete_Object_Entries;
         Outcomes : Backends.Delete_Object_Outcomes;
      begin
         Store.List_Object_Versions
           ("delete-race-bucket", (others => <>), null,
            Ada.Real_Time.Time_Last, Page, Backend_Result);
         for Version of Page.Entries loop
            Entries.Append
              (Backends.Delete_Object_Entry'
                 (Key => Version.Key,
                  Selector =>
                    (if US.To_String (Version.Version_ID) = "null"
                     then Backends.Null_Version_Selector
                     else (Kind => Backends.Exact_Version,
                           ID   => Version.Version_ID)),
                  Conditions => Backends.No_Delete_Object_Conditions));
         end loop;
         Store.Delete_Objects
           ("delete-race-bucket", Entries, (others => <>), null,
            Ada.Real_Time.Time_Last, Outcomes, Backend_Result);
         Require
           (Backend_Result = Flyology.Object_Storage.Success
            and then Outcomes.Length = Entries.Length,
            "DeleteObjects server versioning race cleanup batch failed");
      end;
      Flyology.Object_Storage.Backends.Memory.Delete_Bucket
        (Store, "delete-race-bucket", null, Ada.Real_Time.Time_Last,
         Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Success,
         "DeleteObjects server race cleanup failed");
   end;

   for Key of Listing_Keys loop
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/test-bucket/" & US.To_String (Key), "x")),
            "200 OK"),
         "ListObjectsV2 setup failed");
   end loop;

   declare
      Response : constant String :=
        Run (Signed_Request ("GET", "/test-bucket", ""));
      Listing : constant Listings.List_Objects_Result :=
        Listings.Parse_List_Objects (Response_Body (Response));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "<Marker></Marker>")
         and then Has (Response, "<Key>list/a</Key>")
         and then Has (Response, "<Key>list/sub/c</Key>")
         and then Has (Response, "<Owner><ID>test-principal</ID></Owner>")
         and then not Has (Response, "<KeyCount>")
         and then not Has (Response, "ContinuationToken"),
         "ListObjects v1 default response mismatch");
      Require
        (not Listing.Contents.Is_Empty
         and then Listing.Contents.First_Element.Has_Owner
         and then US.To_String
           (Listing.Contents.First_Element.Owner.ID) = "test-principal",
         "ListObjects v1 owner projection mismatch");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("max-keys", "2"),
         SigV4.Pair ("prefix", "list/"),
         SigV4.Pair ("x-id", "ListObjects"));
      Response : constant String := Run
        (Signed_Query_Request ("GET", "/test-bucket", Query));
   begin
      Require
        (Has (Response, "<IsTruncated>true</IsTruncated>")
         and then Has (Response, "<Key>list/a</Key>")
         and then Has (Response, "<Key>list/b</Key>")
         and then not Has (Response, "<Key>list/sub/c</Key>")
         and then not Has (Response, "<NextMarker>"),
         "ListObjects v1 first marker page mismatch");
      declare
         Next_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("marker", "list/b"),
            SigV4.Pair ("max-keys", "2"),
            SigV4.Pair ("prefix", "list/"));
         Next : constant String := Run
           (Signed_Query_Request ("GET", "/test-bucket", Next_Query));
      begin
         Require
           (Has (Next, "<Marker>list/b</Marker>")
            and then Has (Next, "<Key>list/sub/c</Key>")
            and then Has (Next, "<IsTruncated>false</IsTruncated>"),
            "ListObjects v1 marker continuation mismatch");
      end;
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("delimiter", "/"),
         SigV4.Pair ("encoding-type", "url"),
         SigV4.Pair ("max-keys", "1"),
         SigV4.Pair ("prefix", "list/"));
      Response : constant String := Run
        (Signed_Query_Request ("GET", "/test-bucket", Query));
   begin
      Require
        (Has (Response, "<IsTruncated>true</IsTruncated>")
         and then Has (Response, "<Delimiter>/</Delimiter>")
         and then Has (Response, "<Prefix>list/</Prefix>")
         and then Has (Response, "<Key>list/a</Key>")
         and then Has (Response, "<NextMarker>list/a</NextMarker>"),
         "ListObjects v1 delimiter next marker mismatch");
   end;

   declare
      Zero : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("max-keys", "0"));
      Duplicate : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("prefix", "a"), SigV4.Pair ("prefix", "b"));
   begin
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Zero)),
            "<IsTruncated>false</IsTruncated>"),
         "ListObjects v1 zero-sized page mismatch");
      Require
        (Has
           (Run
              (Signed_Query_Request ("GET", "/test-bucket", Duplicate)),
            "InvalidArgument"),
         "duplicate ListObjects v1 parameter was accepted");
      Require
        (Has
           (Run
              (Signed_Query_Request ("GET", "/missing-bucket", Zero)),
            "NoSuchBucket"),
         "ListObjects v1 absent bucket mismatch");
   end;

   declare
      Empty_Values : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("delimiter", ""),
         SigV4.Pair ("marker", ""),
         SigV4.Pair ("max-keys", "0"),
         SigV4.Pair ("prefix", ""));
      Response : constant String := Run
        (Signed_Query_Request ("GET", "/test-bucket", Empty_Values));
      Listing : constant Listings.List_Objects_Result :=
        Listings.Parse_List_Objects (Response_Body (Response));
   begin
      Require
        (Has (Response, "200 OK")
         and then Listing.Has_Prefix
         and then Listing.Has_Delimiter
         and then Listing.Has_Marker
         and then US.Length (Listing.Delimiter) = 0
         and then Listing.Max_Keys = 0,
         "ListObjects v1 explicit-empty presence mismatch");
   end;

   declare
      Zero : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("max-keys", "0"));

      function Header_Response
        (Name, Value : String; Second : String := "") return String is
        (Run
           (Signed_Query_Request
              ("GET", "/test-bucket", Zero, Name, Value,
               Second_Header_Value => Second)));
   begin
      declare
         Response : constant String := Header_Response
           ("x-amz-request-payer", "requester");
      begin
         Require
           (Has (Response, "200 OK")
            and then not Has (Response, "x-amz-request-charged"),
            "ListObjects v1 owner requester-payer behavior mismatch");
      end;
      Require
        (Has
           (Header_Response ("x-amz-request-payer", "owner"),
            "InvalidArgument"),
         "ListObjects v1 invalid requester payer was accepted");
      Require
        (Has
           (Header_Response
              ("x-amz-expected-bucket-owner", "test-principal"),
            "200 OK"),
         "ListObjects v1 matching expected owner was rejected");
      Require
        (Has
           (Header_Response
              ("x-amz-expected-bucket-owner", "different-owner"),
            "403 Forbidden"),
         "ListObjects v1 mismatched expected owner was accepted");
      declare
         Response : constant String := Header_Response
           ("x-amz-optional-object-attributes", "RestoreStatus");
      begin
         Require
           (Has (Response, "200 OK")
            and then not Has (Response, "<RestoreStatus>"),
            "ListObjects v1 nonarchival RestoreStatus behavior mismatch");
      end;
      Require
        (Has
           (Header_Response
              ("x-amz-optional-object-attributes", "Invalid"),
            "InvalidArgument"),
         "ListObjects v1 invalid optional attributes were accepted");
      Require
        (Has
           (Header_Response
              ("x-amz-request-payer", "requester", "requester"),
            "InvalidRequest"),
         "ListObjects v1 duplicate modeled header was accepted");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("list-type", "2"),
         SigV4.Pair ("max-keys", "2"),
         SigV4.Pair ("prefix", "list/"));
      Response : constant String := Run
        (Signed_Query_Request ("GET", "/test-bucket", Query));
      First : constant Listings.List_Objects_V2_Result :=
        Listings.Parse_List_Objects_V2 (Response_Body (Response));
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "Content-Length:")
         and then not Has (Response, "Transfer-Encoding:"),
         "ListObjectsV2 response framing mismatch");
      Require
        (First.Key_Count = 2
         and then First.Contents.Length = 2
         and then US.To_String (First.Contents (1).Key) = "list/a"
         and then US.To_String (First.Contents (2).Key) = "list/b"
         and then First.Contents (1).Size = 1
         and then US.To_String (First.Contents (1).Entity_Tag) =
           """9dd4e461268c8034f5c8564e155c67a6"""
         and then US.To_String (First.Contents (1).Storage_Class) =
           "STANDARD"
         and then First.Is_Truncated
         and then US.Length (First.Next_Continuation_Token) > 0,
         "ListObjectsV2 first page mismatch");
      declare
         Next_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair
              ("continuation-token",
               US.To_String (First.Next_Continuation_Token)),
            SigV4.Pair ("list-type", "2"),
            SigV4.Pair ("max-keys", "2"),
            SigV4.Pair ("prefix", "list/"));
         Next_Response : constant String := Run
           (Signed_Query_Request ("GET", "/test-bucket", Next_Query));
         Next : constant Listings.List_Objects_V2_Result :=
           Listings.Parse_List_Objects_V2 (Response_Body (Next_Response));
      begin
         Require
           (Next.Key_Count = 1
            and then Next.Contents.Length = 1
            and then US.To_String (Next.Contents.First_Element.Key) =
              "list/sub/c"
            and then not Next.Is_Truncated,
            "ListObjectsV2 continuation page mismatch");
      end;
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("delimiter", "/"),
         SigV4.Pair ("encoding-type", "url"),
         SigV4.Pair ("list-type", "2"),
         SigV4.Pair ("prefix", "list/"));
      Response : constant String := Run
        (Signed_Query_Request ("GET", "/test-bucket", Query));
      Listing : constant Listings.List_Objects_V2_Result :=
        Listings.Parse_List_Objects_V2 (Response_Body (Response));
   begin
      Require
        (Listing.Key_Count = 3
         and then Listing.Contents.Length = 2
         and then Listing.Common_Prefixes.Length = 1
         and then US.To_String (Listing.Prefix) = "list/"
         and then US.To_String (Listing.Delimiter) = "/"
         and then US.To_String (Listing.Contents (1).Key) = "list/a"
         and then US.To_String (Listing.Common_Prefixes.First_Element) =
           "list/sub/",
         "ListObjectsV2 delimiter or URL encoding mismatch");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("continuation-token", ""),
         SigV4.Pair ("list-type", "2"),
         SigV4.Pair ("prefix", "list/"));
      Listing : constant Listings.List_Objects_V2_Result :=
        Listings.Parse_List_Objects_V2
          (Response_Body
             (Run
                (Signed_Query_Request ("GET", "/test-bucket", Query))));
   begin
      Require
        (Listing.Has_Continuation_Token
         and then US.Length (Listing.Continuation_Token) = 0
         and then Listing.Contents.Length = 3,
         "ListObjectsV2 present empty continuation token mismatch");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("delimiter", ""),
         SigV4.Pair ("list-type", "2"),
         SigV4.Pair ("start-after", ""));
      Listing : constant Listings.List_Objects_V2_Result :=
        Listings.Parse_List_Objects_V2
          (Response_Body
             (Run
                (Signed_Query_Request ("GET", "/test-bucket", Query))));
   begin
      Require
        (Listing.Has_Delimiter
         and then US.Length (Listing.Delimiter) = 0
         and then Listing.Has_Start_After
         and then US.Length (Listing.Start_After) = 0,
         "ListObjectsV2 present empty delimiter/start-after mismatch");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("list-type", "2"),
         SigV4.Pair ("prefix", "list/"),
         SigV4.Pair ("start-after", "list/a"));
      Listing : constant Listings.List_Objects_V2_Result :=
        Listings.Parse_List_Objects_V2
          (Response_Body
             (Run
                (Signed_Query_Request ("GET", "/test-bucket", Query))));
   begin
      Require
        (Listing.Contents.Length = 2
         and then US.To_String (Listing.Contents.First_Element.Key) =
           "list/b",
         "ListObjectsV2 StartAfter was not exclusive");
   end;

   declare
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("list-type", "2"), SigV4.Pair ("max-keys", "0"));
      Listing : constant Listings.List_Objects_V2_Result :=
        Listings.Parse_List_Objects_V2
          (Response_Body
             (Run
                (Signed_Query_Request ("GET", "/test-bucket", Query))));
   begin
      Require
        (Listing.Key_Count = 0 and then not Listing.Is_Truncated
         and then US.Length (Listing.Next_Continuation_Token) = 0,
         "ListObjectsV2 zero-sized page mismatch");
   end;

   declare
      Bad_Token : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("continuation-token", "not-a-token"),
         SigV4.Pair ("list-type", "2"));
      Duplicate : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("list-type", "2"),
         SigV4.Pair ("prefix", "a"), SigV4.Pair ("prefix", "b"));
      Owner : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("fetch-owner", "true"),
         SigV4.Pair ("list-type", "2"));
      Basic : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("list-type", "2"));
   begin
      Require
        (Has
           (Run
              (Signed_Query_Request ("GET", "/test-bucket", Bad_Token)),
            "InvalidArgument"),
         "invalid ListObjectsV2 token was accepted");
      Require
        (Has
           (Run
              (Signed_Query_Request ("GET", "/test-bucket", Duplicate)),
            "InvalidArgument"),
         "duplicate ListObjectsV2 parameter was accepted");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket", Owner));
         Listing : constant Listings.List_Objects_V2_Result :=
           Listings.Parse_List_Objects_V2 (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then not Listing.Contents.Is_Empty
            and then Listing.Contents.First_Element.Has_Owner
            and then US.To_String
              (Listing.Contents.First_Element.Owner.ID) = "test-principal"
            and then US.Length
              (Listing.Contents.First_Element.Owner.Display_Name) = 0,
            "ListObjectsV2 FetchOwner projection mismatch");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Basic,
                  "x-amz-expected-bucket-owner", "test-principal")),
            "200 OK"),
         "ListObjectsV2 matching expected owner was rejected");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Basic,
                  "x-amz-expected-bucket-owner", "other-principal")),
            "403 Forbidden"),
         "ListObjectsV2 mismatched expected owner was accepted");
      declare
         Response : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket", Basic,
               "x-amz-request-payer", "requester"));
      begin
         Require
           (Has (Response, "200 OK")
            and then not Has (Response, "x-amz-request-charged:"),
            "owner ListObjectsV2 requester acknowledgement mismatch");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Basic,
                  "x-amz-request-payer", "owner")),
            "InvalidArgument"),
         "invalid ListObjectsV2 request payer was accepted");
      declare
         Response : constant String := Run
           (Signed_Query_Request
              ("GET", "/test-bucket", Basic,
               "x-amz-optional-object-attributes", "RestoreStatus"));
      begin
         Require
           (Has (Response, "200 OK")
            and then not Has (Response, "<RestoreStatus>"),
            "non-archival ListObjectsV2 restore projection mismatch");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Basic,
                  "x-amz-optional-object-attributes", "Unknown")),
            "InvalidArgument"),
         "invalid ListObjectsV2 optional attributes were accepted");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/test-bucket", Basic,
                  "x-amz-expected-bucket-owner", "test-principal",
                  Second_Header_Value => "test-principal")),
            "InvalidRequest"),
         "duplicate ListObjectsV2 expected owner was accepted");
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/missing-bucket", Basic)),
            "404 Not Found"),
         "ListObjectsV2 absent bucket mismatch");
   end;

   declare
      Bucket : constant String := "version-list-bucket";
      Result : Flyology.Object_Storage.Status;
      Outcome : Backends.Version_Delete_Outcome;
      Retained_ID : US.Unbounded_String;
      First_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("max-keys", "2"),
         SigV4.Pair ("prefix", "alpha"),
         SigV4.Pair ("versions", ""));
   begin
      Require
        (Has
           (Run (Signed_Create_Bucket_Request ("/" & Bucket, "")),
            "200 OK"),
         "ListObjectVersions bucket setup failed");
      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          others => <>),
         null,
         Ada.Real_Time.Time_Last, Result);
      Require (Result = Flyology.Object_Storage.Success,
               "ListObjectVersions versioning setup failed");
      Require
        (Has
           (Run (Signed_Request ("PUT", "/" & Bucket & "/alpha", "one")),
            "200 OK"),
         "ListObjectVersions first generation setup failed");
      Require
        (Has
           (Run (Signed_Request ("PUT", "/" & Bucket & "/alpha", "two")),
            "200 OK"),
         "ListObjectVersions second generation setup failed");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/" & Bucket & "/encoded+key", "encoded")),
            "200 OK"),
         "ListObjectVersions encoded-key setup failed");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/" & Bucket & "/nested/key", "nested")),
            "200 OK"),
         "ListObjectVersions delimited-key setup failed");
      declare
         Response : constant String :=
           Run
             (Signed_Delete_Object_Request
                ("/" & Bucket & "/alpha"));
      begin
         Require
           (Has (Response, "204 No Content")
            and then Has (Response, "x-amz-delete-marker: true" & CRLF)
            and then Has (Response, "x-amz-version-id:"),
            "versioned DeleteObject marker setup failed");
      end;

      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/" & Bucket, First_Query));
         First : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Length:")
            and then not Has (Response, "Transfer-Encoding:")
            and then First.Has_Name
            and then US.To_String (First.Name) = Bucket
            and then First.Has_Prefix
            and then US.To_String (First.Prefix) = "alpha"
            and then First.Max_Keys = 2
            and then First.Is_Truncated
            and then First.Has_Next_Key_Marker
            and then First.Has_Next_Version_ID_Marker
            and then First.Versions.Length = 1
            and then First.Delete_Markers.Length = 1
            and then US.To_String (First.Versions (1).Key) = "alpha"
            and then US.To_String (First.Versions (1).Entity_Tag) =
              """b8a9f715dbb64fd5c56e7783c6820a61"""
            and then First.Versions (1).Size = 3
            and then First.Delete_Markers (1).Is_Latest,
            "ListObjectVersions first server page mismatch");
         declare
            Version_Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair
                 ("versionId",
                  US.To_String (First.Versions (1).Version_ID)));
            Head_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("HEAD", "/" & Bucket & "/alpha", Version_Query));
         begin
            Require
              (Has (Head_Response, "200 OK")
               and then Has (Head_Response, "Content-Length: 3" & CRLF)
               and then Has
                 (Head_Response,
                  "x-amz-version-id: " &
                    US.To_String (First.Versions (1).Version_ID) & CRLF),
               "version-selected HeadObject server mismatch");
         end;
         declare
            Next_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair
                 ("key-marker", US.To_String (First.Next_Key_Marker)),
               SigV4.Pair ("max-keys", "2"),
               SigV4.Pair ("prefix", "alpha"),
               SigV4.Pair
                 ("version-id-marker",
                  US.To_String (First.Next_Version_ID_Marker)),
               SigV4.Pair ("versions", ""));
            Next_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket, Next_Query));
            Next : constant Versions.List_Object_Versions_Result :=
              Versions.Parse_List_Object_Versions
                (Response_Body (Next_Response));
         begin
            Retained_ID := Next.Versions (1).Version_ID;
            Require
              (Has (Next_Response, "200 OK")
               and then not Next.Is_Truncated
               and then Next.Versions.Length = 1
               and then Next.Delete_Markers.Is_Empty
               and then not Next.Has_Next_Key_Marker
               and then not Next.Has_Next_Version_ID_Marker,
               "ListObjectVersions paired-cursor server page mismatch");
            declare
               Version_Query : constant SigV4.Name_Value_Array :=
                 (1 => SigV4.Pair
                    ("versionId",
                     US.To_String (Next.Versions (1).Version_ID)));
               Get_Response : constant String :=
                 Run
                   (Signed_Query_Request
                      ("GET", "/" & Bucket & "/alpha", Version_Query));
            begin
               Require
                 (Has (Get_Response, "200 OK")
                  and then Response_Body (Get_Response) = "one"
                  and then Has
                    (Get_Response,
                     "x-amz-version-id: " &
                       US.To_String (Next.Versions (1).Version_ID) & CRLF),
                  "version-selected GetObject server mismatch");
            end;
            declare
               Source_ID : constant String :=
                 US.To_String (Next.Versions (1).Version_ID);
               Copy_Response : constant String :=
                 Run
                   (Signed_Copy_Request
                      ("/" & Bucket & "/copied-retained",
                       "/" & Bucket & "/alpha?versionId=" & Source_ID));
               Malformed_Response : constant String :=
                 Run
                   (Signed_Copy_Request
                      ("/" & Bucket & "/copy-invalid",
                       "/" & Bucket & "/alpha?versionId="));
               Extra_Query_Response : constant String :=
                 Run
                   (Signed_Copy_Request
                      ("/" & Bucket & "/copy-extra-query",
                       "/" & Bucket & "/alpha?versionId=" & Source_ID &
                         "&x-id=GetObject"));
               Copied_Get : constant String :=
                 Run
                   (Signed_Request
                      ("GET", "/" & Bucket & "/copied-retained", ""));
               Cleanup_Info : Flyology.Object_Storage.Object_Information;
            begin
               if not Has (Copy_Response, "200 OK")
                 or else not Has
                   (Copy_Response,
                    "x-amz-copy-source-version-id: " & Source_ID & CRLF)
                 or else not Has (Copy_Response, "x-amz-version-id:")
                 or else Response_Body (Copied_Get) /= "one"
               then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "unexpected versioned CopyObject response: " &
                       Copy_Response);
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "unexpected copied retained GET: " & Copied_Get);
               end if;
               Require
                 (Has (Copy_Response, "200 OK")
                  and then Has
                    (Copy_Response,
                     "x-amz-copy-source-version-id: " & Source_ID & CRLF)
                  and then Has (Copy_Response, "x-amz-version-id:")
                  and then
                    Response_Body (Copied_Get) = "one",
                  "version-selected CopyObject identity or body mismatch");
               Require
                 (Has (Malformed_Response, "400 Bad Request")
                  and then Has
                    (Malformed_Response, "<Code>InvalidArgument</Code>")
                  and then Has
                    (Run
                       (Signed_Request
                          ("HEAD", "/" & Bucket & "/copy-invalid", "")),
                     "404 Not Found"),
                  "malformed CopyObject version query mutated storage");
               Require
                 (Has (Extra_Query_Response, "400 Bad Request")
                  and then Has
                    (Extra_Query_Response, "<Code>InvalidArgument</Code>")
                  and then Has
                    (Run
                       (Signed_Request
                          ("HEAD", "/" & Bucket & "/copy-extra-query", "")),
                     "404 Not Found"),
                  "multi-field CopyObject version query mutated storage");
               Store.Head_Object
                 (Bucket, "copied-retained", null, Ada.Real_Time.Time_Last,
                  Cleanup_Info, Result);
               Require
                 (Result = Flyology.Object_Storage.Success
                  and then US.Length (Cleanup_Info.Version) > 0,
                  "versioned CopyObject cleanup identity lookup failed");
               Store.Delete_Selected_Object
                 (Bucket, "copied-retained",
                  (Kind => Backends.Exact_Version,
                   ID   => Cleanup_Info.Version),
                  Backends.No_Delete_Object_Conditions, False, null,
                  Ada.Real_Time.Time_Last, Outcome, Result);
               Require
                 (Result = Flyology.Object_Storage.Success
                  and then Outcome.Kind = Backends.Object_Version_Removed,
                  "versioned CopyObject retained-destination cleanup failed");
            end;
            declare
               Version_Query : constant SigV4.Name_Value_Array :=
                 (1 => SigV4.Pair
                    ("versionId", US.To_String (Retained_ID)));
               Delete_Response : constant String :=
                 Run
                   (Signed_Delete_Object_Request
                      ("/" & Bucket & "/alpha", Version_Query,
                       Header_Name => "if-match",
                       Header_Value => """mismatch"""));
               Get_Response : constant String :=
                 Run
                   (Signed_Query_Request
                      ("GET", "/" & Bucket & "/alpha", Version_Query));
            begin
               if not Has (Delete_Response, "HTTP/1.1 412 ")
                 or else not Has
                   (Delete_Response, "<Code>PreconditionFailed</Code>")
                 or else Response_Body (Get_Response) /= "one"
               then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "unexpected conditional exact DeleteObject response: " &
                       Delete_Response);
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "unexpected retained generation response: " &
                       Get_Response);
               end if;
               Require
                 (Has (Delete_Response, "HTTP/1.1 412 ")
                  and then Has
                    (Delete_Response, "<Code>PreconditionFailed</Code>")
                  and then Response_Body (Get_Response) = "one",
                  "conditional exact DeleteObject rejection mutated data");
            end;
         end;

         declare
            Target_ID : constant String := US.To_String (Retained_ID);
            Other_ID  : constant String :=
              US.To_String (First.Versions (1).Version_ID);
            Exact_ACL_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("acl", ""),
               SigV4.Pair ("versionId", Target_ID));
            Missing_ACL_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("acl", ""),
               SigV4.Pair ("versionId", "unknown-generation"));
            Target_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("tagging", ""),
               SigV4.Pair ("versionId", Target_ID));
            Other_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("tagging", ""),
               SigV4.Pair ("versionId", Other_ID));
            Unknown_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("tagging", ""),
               SigV4.Pair ("versionId", "unknown-generation"));
            Document : constant String :=
              "<Tagging><TagSet><Tag><Key>generation</Key>" &
              "<Value>retained</Value></Tag></TagSet></Tagging>";
            Put_ACL_Response : constant String :=
              Run
                (Signed_Query_Body_Request
                   ("PUT", "/" & Bucket & "/alpha", Exact_ACL_Query, "",
                    "x-amz-acl: private" & CRLF &
                    "Content-MD5: " & Content_MD5 ("") & CRLF));
            Get_ACL_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Exact_ACL_Query));
            Missing_ACL_Response : constant String :=
              Run
                (Signed_Query_Body_Request
                   ("PUT", "/" & Bucket & "/alpha", Missing_ACL_Query, "",
                    "x-amz-acl: private" & CRLF &
                    "Content-MD5: " & Content_MD5 ("") & CRLF));
            Put_Response : constant String :=
              Run
                (Signed_Query_Body_Request
                   ("PUT", "/" & Bucket & "/alpha", Target_Query,
                    Document,
                    "Content-MD5: " & Content_MD5 (Document) & CRLF));
            Get_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Target_Query));
            Other_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Other_Query));
            Delete_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("DELETE", "/" & Bucket & "/alpha", Target_Query));
            Cleared_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Target_Query));
            Missing_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Unknown_Query));
            Missing_Put_Response : constant String :=
              Run
                (Signed_Query_Body_Request
                   ("PUT", "/" & Bucket & "/alpha", Unknown_Query,
                    Document,
                    "Content-MD5: " & Content_MD5 (Document) & CRLF));
            Missing_Delete_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("DELETE", "/" & Bucket & "/alpha", Unknown_Query));
         begin
            Require
              (Has (Put_ACL_Response, "200 OK")
               and then Has (Get_ACL_Response, "200 OK")
               and then Has
                 (Get_ACL_Response, "<Permission>FULL_CONTROL</Permission>")
               and then Has
                 (Missing_ACL_Response, "<Code>NoSuchKey</Code>"),
               "exact-version PutObjectAcl selection mismatch");
            Require
              (Has (Put_Response, "200 OK")
               and then Has
                 (Put_Response, "x-amz-version-id: " & Target_ID & CRLF)
               and then Has (Get_Response, "200 OK")
               and then Has
                 (Get_Response, "x-amz-version-id: " & Target_ID & CRLF)
               and then Has (Get_Response, "<Key>generation</Key>")
               and then Has (Get_Response, "<Value>retained</Value>"),
               "exact-version object tagging route or identity mismatch");
            Require
              (Has (Other_Response, "200 OK")
               and then Has
                 (Other_Response, "x-amz-version-id: " & Other_ID & CRLF)
               and then Has (Other_Response, "<TagSet></TagSet>")
               and then not Has (Other_Response, "<Key>"),
               "exact-version object tagging isolation mismatch");
            Require
              (Has (Delete_Response, "204 No Content")
               and then Has
                 (Delete_Response,
                  "x-amz-version-id: " & Target_ID & CRLF)
               and then Has (Cleared_Response, "<TagSet></TagSet>")
               and then not Has (Cleared_Response, "<Key>"),
               "exact-version DeleteObjectTagging mismatch");
            Require
              (Has (Missing_Response, "<Code>NoSuchKey</Code>")
               and then not Has
                 (Missing_Response, "x-amz-version-id:")
               and then Has
                 (Missing_Put_Response, "<Code>NoSuchKey</Code>")
               and then not Has
                 (Missing_Put_Response, "x-amz-version-id:")
               and then Has
                 (Missing_Delete_Response, "<Code>NoSuchKey</Code>")
               and then not Has
                 (Missing_Delete_Response, "x-amz-version-id:"),
               "unknown exact-version tagging leaked success identity");
         end;

         declare
            Marker_Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair
                 ("versionId",
                  US.To_String (First.Delete_Markers (1).Version_ID)));
            Delete_Response : constant String :=
              Run
                (Signed_Delete_Object_Request
                   ("/" & Bucket & "/alpha", Marker_Query));
         begin
            Require
              (Has (Delete_Response, "204 No Content")
               and then Has
                 (Delete_Response, "x-amz-delete-marker: true" & CRLF)
               and then Has
                 (Delete_Response,
                  "x-amz-version-id: " &
                    US.To_String (First.Delete_Markers (1).Version_ID) &
                    CRLF)
               and then Has
                 (Run
                    (Signed_Request
                       ("HEAD", "/" & Bucket & "/alpha", "")),
                  "200 OK"),
               "exact DeleteObject marker removal mismatch");
         end;

         declare
            Current_ID : constant String :=
              US.To_String (First.Versions (1).Version_ID);
            Current_Query : constant SigV4.Name_Value_Array :=
              (1 => SigV4.Pair ("tagging", ""));
            Exact_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("tagging", ""),
               SigV4.Pair ("versionId", Current_ID));
            Document : constant String :=
              "<Tagging><TagSet><Tag><Key>generation</Key>" &
              "<Value>current</Value></Tag></TagSet></Tagging>";
            Put_Response : constant String :=
              Run
                (Signed_Query_Body_Request
                   ("PUT", "/" & Bucket & "/alpha", Current_Query,
                    Document,
                    "Content-MD5: " & Content_MD5 (Document) & CRLF));
            Current_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Current_Query));
            Exact_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", "/" & Bucket & "/alpha", Exact_Query));
            Delete_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("DELETE", "/" & Bucket & "/alpha", Current_Query));
         begin
            Require
              (Has (Put_Response, "200 OK")
               and then Has
                 (Put_Response, "x-amz-version-id: " & Current_ID & CRLF)
               and then Has
                 (Current_Response,
                  "x-amz-version-id: " & Current_ID & CRLF)
               and then Has (Current_Response, "<Value>current</Value>")
               and then Has
                 (Exact_Response,
                  "x-amz-version-id: " & Current_ID & CRLF)
               and then Has (Exact_Response, "<Value>current</Value>")
               and then Has (Delete_Response, "204 No Content")
               and then Has
                 (Delete_Response,
                  "x-amz-version-id: " & Current_ID & CRLF),
               "current-version object tagging identity or isolation " &
               "mismatch");
         end;
      end;

      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Suspended,
          others => <>),
         null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Flyology.Object_Storage.Success,
         "null-version tagging suspension setup failed");
      declare
         Put_Object_Response : constant String :=
           Run (Signed_Request ("PUT", "/" & Bucket & "/alpha", "null"));
         Null_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("tagging", ""),
            SigV4.Pair ("versionId", "null"));
         Document : constant String :=
           "<Tagging><TagSet><Tag><Key>generation</Key>" &
           "<Value>null</Value></Tag></TagSet></Tagging>";
         Put_Tags_Response : constant String :=
           Run
             (Signed_Query_Body_Request
                ("PUT", "/" & Bucket & "/alpha", Null_Query, Document,
                 "Content-MD5: " & Content_MD5 (Document) & CRLF));
         Get_Tags_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/" & Bucket & "/alpha", Null_Query));
         Current_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("tagging", ""));
         Current_Get_Tags_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/" & Bucket & "/alpha", Current_Query));
         Delete_Tags_Response : constant String :=
           Run
             (Signed_Query_Request
                ("DELETE", "/" & Bucket & "/alpha", Null_Query));
         Copy_Response : constant String :=
           Run
             (Signed_Copy_Request
                ("/" & Bucket & "/copied-null",
                 "/" & Bucket & "/alpha?versionId=null"));
         Delete_Object_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("versionId", "null"));
         Delete_Object_Response : constant String :=
           Run
             (Signed_Delete_Object_Request
                ("/" & Bucket & "/alpha", Delete_Object_Query));
      begin
         Require
           (Has (Put_Object_Response, "200 OK")
            and then Has
              (Put_Object_Response, "x-amz-version-id: null" & CRLF)
            and then Has (Put_Tags_Response, "200 OK")
            and then Has
              (Put_Tags_Response, "x-amz-version-id: null" & CRLF)
            and then Has
              (Get_Tags_Response, "x-amz-version-id: null" & CRLF)
            and then Has (Get_Tags_Response, "<Value>null</Value>")
            and then Has
              (Current_Get_Tags_Response,
               "x-amz-version-id: null" & CRLF)
            and then Has
              (Current_Get_Tags_Response, "<Value>null</Value>")
            and then Has (Delete_Tags_Response, "204 No Content")
            and then Has
              (Delete_Tags_Response, "x-amz-version-id: null" & CRLF)
            and then Has (Copy_Response, "200 OK")
            and then Has
              (Copy_Response,
               "x-amz-copy-source-version-id: null" & CRLF)
            and then Has
              (Copy_Response, "x-amz-version-id: null" & CRLF)
            and then Has (Delete_Object_Response, "204 No Content")
            and then Has
              (Delete_Object_Response, "x-amz-version-id: null" & CRLF),
            "null-version PutObject or tagging identity mismatch");
         Store.Delete_Selected_Object
           (Bucket, "copied-null", Backends.Null_Version_Selector,
            Backends.No_Delete_Object_Conditions, False, null,
            Ada.Real_Time.Time_Last, Outcome, Result);
         Require
           (Result = Flyology.Object_Storage.Success
            and then Outcome.Kind = Backends.Object_Version_Removed
            and then Outcome.Is_Null_Version,
            "null CopyObject destination cleanup failed");
      end;
      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          others => <>),
         null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Flyology.Object_Storage.Success,
         "null-version tagging restore failed");

      declare
         Zero_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("max-keys", "0"),
            SigV4.Pair ("versions", ""));
         Zero : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions
             (Response_Body
                (Run
                   (Signed_Query_Request
                      ("GET", "/" & Bucket, Zero_Query))));
      begin
         Require
           (Zero.Max_Keys = 0 and then not Zero.Is_Truncated
            and then Zero.Versions.Is_Empty
            and then Zero.Delete_Markers.Is_Empty,
            "ListObjectVersions zero-sized server page mismatch");
      end;

      declare
         Encoded_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("encoding-type", "url"),
            SigV4.Pair ("prefix", "encoded+"),
            SigV4.Pair ("versions", ""),
            SigV4.Pair ("x-id", "ListObjectVersions"));
         Encoded_Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions
             (Response_Body
                (Run
                   (Signed_Query_Request
                      ("GET", "/" & Bucket, Encoded_Query))));
      begin
         Require
           (Encoded_Page.Has_Encoding_Type
            and then US.To_String (Encoded_Page.Encoding_Type) = "url"
            and then Encoded_Page.Has_Prefix
            and then US.To_String (Encoded_Page.Prefix) = "encoded%2B"
            and then Encoded_Page.Versions.Length = 1
            and then US.To_String (Encoded_Page.Versions (1).Key) =
              "encoded%2Bkey",
            "ListObjectVersions URL encoding or x-id routing mismatch");
      end;

      declare
         Duplicate : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("versions", ""), SigV4.Pair ("versions", ""));
         Unpaired : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("version-id-marker", "v1"),
            SigV4.Pair ("versions", ""));
         Delimiter : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("delimiter", "/"), SigV4.Pair ("versions", ""));
         Delimiter_Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/" & Bucket, Delimiter));
         Delimiter_Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions
             (Response_Body (Delimiter_Response));
      begin
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/" & Bucket, Duplicate)),
               "InvalidArgument"),
            "ListObjectVersions duplicate marker was accepted");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/" & Bucket, Unpaired)),
               "InvalidArgument"),
            "ListObjectVersions unpaired cursor was accepted");
         Require
           (Has (Delimiter_Response, "200 OK")
            and then Delimiter_Page.Versions.Length = 3
            and then Delimiter_Page.Common_Prefixes.Length = 1
            and then US.To_String
              (Delimiter_Page.Common_Prefixes (1)) = "nested/",
            "ListObjectVersions delimiter projection mismatch");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/" & Bucket, First_Query,
                     "x-amz-expected-bucket-owner", "other-principal")),
               "403 Forbidden"),
            "ListObjectVersions mismatched owner was accepted");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/" & Bucket, First_Query,
                     "x-amz-request-payer", "owner")),
               "InvalidArgument"),
            "ListObjectVersions invalid request payer was accepted");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/" & Bucket, First_Query,
                     "x-amz-optional-object-attributes", "Unknown")),
               "InvalidArgument"),
            "ListObjectVersions invalid optional attributes were accepted");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", "/missing-version-list-bucket", First_Query)),
               "404 Not Found"),
            "ListObjectVersions absent bucket mismatch");
      end;

      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          MFA_Delete => Flyology.Object_Storage.MFA_Delete_Enabled),
         null, Ada.Real_Time.Time_Last, Result,
         MFA_Validated => True);
      Require
        (Result = Flyology.Object_Storage.Success,
         "ListObjectVersions MFA Delete setup failed");
      declare
         Version_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("versionId", US.To_String (Retained_ID)));
      begin
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    ("/" & Bucket & "/alpha", Version_Query)),
               "403 Forbidden"),
            "MFA Delete admitted an exact version without MFA");
         declare
            Response : constant String :=
              Run
                (Signed_Delete_Object_Request
                   ("/" & Bucket & "/alpha", Version_Query,
                    Header_Name => "x-amz-mfa",
                    Header_Value => "device 123456"),
                 Scheme => Flyology.HTTP.Secure_HTTPS);
         begin
            Require
              (Has (Response, "204 No Content")
               and then Has
                 (Response,
                  "x-amz-version-id: " & US.To_String (Retained_ID) & CRLF),
               "MFA-attested exact DeleteObject mismatch");
         end;
      end;

      declare
         Page : Backends.List_Versions_Page;
         Options : constant Backends.List_Versions_Options := (others => <>);
      begin
         Store.List_Object_Versions
           (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Require
           (Result = Flyology.Object_Storage.Success
            and then Page.Entries.Length = 3,
            "ListObjectVersions cleanup inventory mismatch");
         for Generation of Page.Entries loop
            Store.Delete_Selected_Object
               (Bucket, US.To_String (Generation.Key),
                (Kind => Backends.Exact_Version, ID => Generation.Version_ID),
               Backends.No_Delete_Object_Conditions, True, null,
               Ada.Real_Time.Time_Last, Outcome, Result);
            Require
              (Result = Flyology.Object_Storage.Success,
               "ListObjectVersions cleanup generation failed");
         end loop;
         Store.Delete_Bucket
           (Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Flyology.Object_Storage.Success,
            "ListObjectVersions bucket cleanup failed");
      end;
   end;

   Check_Metadata_Server;

   Require
     (Has
        (Run
           (Signed_Request
              ("GET", "/test-bucket/object", "",
               Corrupt_Signature => True)),
         "403 Forbidden"),
      "corrupt signature was not rejected");

   declare
      Response : constant String :=
        Run (Signed_Bucket_Request ("DELETE", "/test-bucket"));
   begin
      Require
        (Has (Response, "409 Conflict")
         and then Has (Response, "<Code>BucketNotEmpty</Code>"),
         "DeleteBucket removed a nonempty bucket");
   end;
   Require
     (Has
        (Run (Signed_Request ("DELETE", "/test-bucket", "unexpected")),
         "400 Bad Request"),
      "DeleteBucket accepted a request body");

   declare
      Response : constant String := Run
        (Signed_Request
           ("GET", "/test-bucket/object", "",
            Extra_Headers => "Range: bytes=99-100" & CRLF));
   begin
      Require (Has (Response, "HTTP/1.1 416 "),
               "unsatisfiable range did not return 416: " & Response);
      Require (Has (Response, "Content-Range: bytes */11"),
               "unsatisfiable range omitted the object size");
   end;

   declare
      Version : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versionId", "version-one"));
      Version_With_ID : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("versionId", "version-one"),
         SigV4.Pair ("x-id", "DeleteObject"));
      Duplicate_Version : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("versionId", "one"),
         SigV4.Pair ("versionId", "two"));
      Unknown : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("unknown", "value"));
   begin
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/test-bucket/delete-policy", "preserve")),
            "200 OK"),
         "DeleteObject policy setup failed");
      declare
         Response : constant String :=
           Run
             (Signed_Delete_Object_Request
                ("/test-bucket/delete-policy", Version));
      begin
         Require
           (Has (Response, "204 No Content")
            and then Has
              (Response, "x-amz-version-id: version-one" & CRLF)
            and then not Has (Response, "x-amz-delete-marker:"),
            "DeleteObject missing exact-version result mismatch");
      end;
      declare
         Response : constant String :=
           Run
             (Signed_Delete_Object_Request
                ("/test-bucket/delete-policy", Version_With_ID));
      begin
         Require
           (Has (Response, "204 No Content")
            and then Has
              (Response, "x-amz-version-id: version-one" & CRLF),
            "DeleteObject misrouted versionId with the SDK operation ID");
      end;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Duplicate_Version)),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted duplicate versionId fields");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Unknown)),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an unknown query field");
      declare
         Response : constant String :=
           Run
             (Signed_Delete_Object_Request
                ("/test-bucket/delete-policy", Header_Name => "if-match",
                 Header_Value => """etag"""));
      begin
         Require
           (Has (Response, "HTTP/1.1 412 ")
            and then Has (Response, "<Code>PreconditionFailed</Code>"),
            "DeleteObject did not atomically reject a mismatched If-Match: " &
            Response);
      end;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "if-match",
                  Header_Value => "bad,etag")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted a malformed If-Match");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "if-match",
                  Header_Value => "bad,etag",
                  Corrupt_Signature => True)),
            "<Code>SignatureDoesNotMatch</Code>"),
         "DeleteObject evaluated malformed semantics before authentication");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "if-match",
                  Header_Value => "")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an empty If-Match value");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-request-payer",
                  Header_Value => "owner")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an invalid request payer");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-request-payer",
                  Header_Value => "")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an empty request payer");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-request-payer",
                  Header_Value => "requester")),
            "501 Not Implemented"),
         "DeleteObject silently ignored Requester Pays");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-bypass-governance-retention",
                  Header_Value => "yes")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an invalid governance bypass value");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-bypass-governance-retention",
                  Header_Value => "")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an empty governance bypass value");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-bypass-governance-retention",
                  Header_Value => "true")),
            "501 Not Implemented"),
         "DeleteObject silently ignored governance bypass");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/test-bucket/delete-bypass-false", "false")),
            "200 OK"),
         "DeleteObject false governance-bypass setup failed");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-bypass-false",
                  Header_Name => "x-amz-bypass-governance-retention",
                  Header_Value => "false")),
            "204 No Content"),
         "DeleteObject treated false governance bypass as a bypass request");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-size",
                  Header_Value => "-1")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an invalid conditional size");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-size",
                  Header_Value => "")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an empty conditional size");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-size",
                  Header_Value => "8")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject applied a directory-only size predicate");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-last-modified-time",
                  Header_Value => "Wed, 21 Oct 2015 07:28:00 GMT")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject applied a directory-only time predicate");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-last-modified-time",
                  Header_Value => "not-a-date")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted a malformed modification time");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-last-modified-time",
                  Header_Value => "")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an empty modification time");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "")),
            "<Code>InvalidArgument</Code>"),
         "DeleteObject accepted an empty MFA credential");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456")),
            "<Code>InvalidRequest</Code>"),
         "DeleteObject accepted MFA over cleartext HTTP");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 000000"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "DeleteObject accepted an invalid MFA credential");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS,
                Use_Null_MFA => True),
            "<Code>AccessDenied</Code>"),
         "DeleteObject did not fail closed without an MFA verifier");
      declare
         Calls : constant Natural := MFA_Policy.Calls;
         Overlong : constant String (1 .. 2_049) := (others => 'x');
      begin
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    ("/test-bucket/delete-policy",
                     Header_Name => "x-amz-mfa",
                     Header_Value => Overlong),
                   Scheme => Flyology.HTTP.Secure_HTTPS),
               "<Code>AccessDenied</Code>"),
            "DeleteObject accepted an overlong MFA credential");
         Require
           (MFA_Policy.Calls = Calls,
            "overlong DeleteObject MFA credential reached the verifier");
      end;
      declare
         Calls : constant Natural := MFA_Policy.Calls;
      begin
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    ("/test-bucket/delete-policy",
                     Header_Name => "x-amz-mfa",
                     Header_Value => "device 123456",
                     Second_Value => "device 123456"),
                   Scheme => Flyology.HTTP.Secure_HTTPS),
               "<Code>InvalidRequest</Code>"),
            "DeleteObject accepted duplicate MFA headers");
         Require
           (MFA_Policy.Calls = Calls,
            "duplicate DeleteObject MFA headers reached the verifier");
      end;
      MFA_Policy.Mode := MFA_Reject_Root;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "DeleteObject treated an authenticated non-root as owner");
      MFA_Policy.Mode := MFA_Unavailable;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "DeleteObject did not fail closed for an unavailable MFA verifier");
      MFA_Policy.Mode := MFA_Raise;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
            "<Code>AccessDenied</Code>"),
         "DeleteObject exposed an MFA verifier exception");
      MFA_Policy.Mode := MFA_Allow_Root;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Version,
                  Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
            "204 No Content"),
         "verified MFA exact-version deletion was rejected");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/test-bucket/delete-mfa", "mfa-body")),
            "200 OK"),
         "DeleteObject verified-MFA setup failed");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-mfa", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456"),
                Scheme => Flyology.HTTP.Secure_HTTPS),
            "204 No Content"),
         "DeleteObject rejected a verified optional MFA credential");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "if-match",
                  Header_Value => "*", Second_Value => "*")),
            "<Code>InvalidRequest</Code>"),
         "DeleteObject accepted duplicate conditional headers");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-expected-bucket-owner",
                  Header_Value => "test-principal",
                  Second_Value => "test-principal")),
            "<Code>InvalidRequest</Code>"),
         "DeleteObject accepted duplicate expected-owner fields");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-expected-bucket-owner",
                  Header_Value => "")),
            "<Code>InvalidRequest</Code>"),
         "DeleteObject accepted an empty expected-owner field");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/test-bucket/delete-match", "match-body")),
            "200 OK"),
         "DeleteObject matching condition setup failed");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-match", Header_Name => "if-match",
                  Header_Value =>
                    '"' & GNAT.MD5.Digest ("match-body") & '"')),
            "204 No Content"),
         "DeleteObject rejected an exact matching generation");
      declare
         Response : constant String :=
           Run
             (Signed_Delete_Object_Request
                ("/test-bucket/delete-match", Header_Name => "if-match",
                 Header_Value => "*"));
      begin
         Require
           (Has (Response, "404 Not Found")
            and then Has (Response, "<Code>NoSuchKey</Code>"),
            "conditioned missing DeleteObject was not NoSuchKey");
      end;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-expected-bucket-owner",
                  Header_Value => "different-owner")),
            "403 Forbidden"),
         "DeleteObject ignored a mismatched expected owner");
      Require
        (Has
           (Run (Signed_Request ("HEAD", "/test-bucket/delete-policy", "")),
            "200 OK"),
         "rejected DeleteObject controls mutated backend state");
      Require
        (Has
           (Run
              (Signed_Request
                 ("DELETE", "/test-bucket/delete-policy", "unexpected")),
            "400 Bad Request"),
         "DeleteObject accepted a request body");
      Require
        (Has
           (Run (Signed_Request ("HEAD", "/test-bucket/delete-policy", "")),
            "200 OK"),
         "rejected DeleteObject body mutated backend state");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-expected-bucket-owner",
                  Header_Value => "test-principal")),
            "204 No Content"),
         "DeleteObject rejected the authenticated bucket owner");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy")),
            "204 No Content"),
         "DeleteObject was not idempotent for an absent key");
      Require
        (Has
           (Run
              (Signed_Create_Bucket_Request
                 ("/delete-versioned", "")),
            "200 OK"),
         "configured DeleteObject bucket creation failed");
      Require
        (Has
           (Run
              (Signed_Request
                 ("PUT", "/delete-versioned/current", "preserve")),
            "200 OK"),
         "configured DeleteObject object setup failed");
      declare
         Backend_Result : Flyology.Object_Storage.Status;
      begin
         Store.Put_Bucket_Versioning
           ("delete-versioned",
            (Status => Flyology.Object_Storage.Versioning_Enabled,
             MFA_Delete =>
               Flyology.Object_Storage.MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Backend_Result);
         Require
           (Backend_Result = Flyology.Object_Storage.Success,
            "configured DeleteObject versioning setup failed");
         declare
            Response : constant String :=
              Run
                (Signed_Delete_Object_Request
                   ("/delete-versioned/current"));
         begin
            Require
              (Has (Response, "204 No Content")
               and then Has
                 (Response, "x-amz-delete-marker: true" & CRLF)
               and then Has (Response, "x-amz-version-id:"),
               "configured DeleteObject marker response mismatch");
         end;
         Require
           (Has
              (Run
                 (Signed_Request
                    ("HEAD", "/delete-versioned/current", "")),
               "404 Not Found"),
            "configured DeleteObject marker did not hide current data");
         declare
            Page : Backends.List_Versions_Page;
            Options : constant Backends.List_Versions_Options :=
              (others => <>);
            Delete_Outcome : Backends.Version_Delete_Outcome;
         begin
            Store.List_Object_Versions
              ("delete-versioned", Options, null,
               Ada.Real_Time.Time_Last, Page, Backend_Result);
            Require
              (Backend_Result = Flyology.Object_Storage.Success
               and then Page.Entries.Length = 2,
               "configured DeleteObject cleanup inventory mismatch");
            for Generation of Page.Entries loop
               Store.Delete_Selected_Object
                 ("delete-versioned", "current",
                  (if US.To_String (Generation.Version_ID) = "null"
                   then Backends.Null_Version_Selector
                   else
                     (Kind => Backends.Exact_Version,
                      ID => Generation.Version_ID)),
                  Backends.No_Delete_Object_Conditions, True, null,
                  Ada.Real_Time.Time_Last, Delete_Outcome, Backend_Result);
               Require
                 (Backend_Result = Flyology.Object_Storage.Success,
                  "configured DeleteObject cleanup generation failed");
            end loop;
         end;
         Store.Delete_Bucket
           ("delete-versioned", null, Ada.Real_Time.Time_Last,
            Backend_Result);
         Require
           (Backend_Result = Flyology.Object_Storage.Success,
            "configured DeleteObject fixture cleanup failed");
      end;
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/absent-bucket/delete-policy")),
            "<Code>NoSuchBucket</Code>"),
         "DeleteObject misreported an absent bucket as an absent key");
   end;

   Require
     (Has (Run (Signed_Request ("DELETE", "/test-bucket/object", "")),
           "204 No Content"),
      "DeleteObject failed");
   Require
     (Has (Run (Signed_Request ("DELETE", "/test-bucket/chunked", "")),
           "204 No Content"),
      "chunked object cleanup failed");
   Require
     (Has (Run (Signed_Request ("DELETE", "/test-bucket/copied", "")),
           "204 No Content"),
      "copied object cleanup failed");
   Require
     (Has (Run (Signed_Request ("DELETE", "/test-bucket/copy-match", "")),
           "204 No Content"),
      "conditional copy cleanup failed");
   Require
     (Has
        (Run
           (Signed_Request
              ("DELETE", "/test-bucket/multipart-object", "")),
         "204 No Content"),
      "multipart object cleanup failed");
   Require
     (Has
        (Run
           (Signed_Request
              ("DELETE", "/test-bucket/multipart-copy", "")),
         "204 No Content"),
      "multipart copy object cleanup failed");
   Require
     (Has
        (Run
           (Signed_Request
              ("DELETE", "/test-bucket/multipart-composite-copy", "")),
         "204 No Content"),
      "multipart composite copy object cleanup failed");
   Require
     (Has
        (Run
           (Signed_Request
              ("DELETE", "/test-bucket/version-preserved", "")),
         "204 No Content"),
      "version-preserved object cleanup failed");
   for Key of Listing_Keys loop
      Require
        (Has
           (Run
              (Signed_Request
                 ("DELETE", "/test-bucket/" & US.To_String (Key), "")),
            "204 No Content"),
         "listing object cleanup failed");
   end loop;
   for Name of Listing_Buckets loop
      Require
        (Has
           (Run
              (Signed_Request
                 ("DELETE", "/" & US.To_String (Name), "")),
            "204 No Content"),
         "ListBuckets setup cleanup failed");
   end loop;
   Require
     (Has
        (Run
           (Signed_Bucket_Request
              ("DELETE", "/test-bucket", "different-owner")),
         "403 Forbidden"),
      "DeleteBucket ignored the expected owner precondition");
   Require
     (Has
        (Run
           (Signed_Bucket_Request
              ("DELETE", "/test-bucket", "test-principal",
               "test-principal")),
         "400 Bad Request"),
      "DeleteBucket accepted a duplicate expected owner header");
   declare
      Response : constant String :=
        Run
          (Signed_Bucket_Request
             ("DELETE", "/test-bucket", "test-principal"));
   begin
      Require
        (Has (Response, "204 No Content")
         and then Response_Body (Response) = "",
         "DeleteBucket success mismatch");
   end;
   Require
     (Has
        (Run (Signed_Bucket_Request ("DELETE", "/test-bucket")),
         "404 Not Found"),
      "DeleteBucket absent-bucket mismatch");

   declare
      Bucket : constant String := "object-lock-server-bucket";
      Key : constant String := "retained-object";
      Target : constant String := "/" & Bucket & "/" & Key;
      Configuration_Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("object-lock", ""));
      Duplicate_Configuration_Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("object-lock", ""),
         SigV4.Pair ("object-lock", ""));
      Configuration_Document : constant String :=
        Object_Lock.Serialize_Configuration
          ((Is_Set  => True,
            Enabled => Object_Lock.Object_Lock_Enabled,
            Rule    => (others => <>)));
      Rule_Document : constant String :=
        Object_Lock.Serialize_Configuration
          ((Is_Set  => True,
            Enabled => Object_Lock.Object_Lock_Enabled,
            Rule    =>
              (Is_Set => True,
               Default_Value => (others => <>))));
      Hold_On_Document : constant String :=
        Object_Lock.Serialize_Legal_Hold
          ((Is_Set => True, Status => Object_Lock.Legal_Hold_On));
      Hold_Off_Document : constant String :=
        Object_Lock.Serialize_Legal_Hold
          ((Is_Set => True, Status => Object_Lock.Legal_Hold_Off));
      Retention_Document : constant String :=
        Object_Lock.Serialize_Retention
          ((Is_Set            => True,
            Mode              => Object_Lock.Governance_Retention,
            Retain_Until_Date =>
              US.To_Unbounded_String
                ("2099-01-01T01:00:00.500+01:00")));
      Zero_Fraction_Retention_Document : constant String :=
        Object_Lock.Serialize_Retention
          ((Is_Set            => True,
            Mode              => Object_Lock.Governance_Retention,
            Retain_Until_Date =>
              US.To_Unbounded_String
                ("2000-01-01T00:00:00.000Z")));
      Negative_Offset_Retention_Document : constant String :=
        Object_Lock.Serialize_Retention
          ((Is_Set            => True,
            Mode              => Object_Lock.Governance_Retention,
            Retain_Until_Date =>
              US.To_Unbounded_String
                ("1999-12-31T23:00:00.500-01:00")));
      Backend_Result : Flyology.Object_Storage.Status;
      First_Info : Flyology.Object_Storage.Object_Information;
      Second_Info : Flyology.Object_Storage.Object_Information;
   begin
      Require
        (Has
           (Run (Signed_Create_Bucket_Request ("/" & Bucket, "")),
            "200 OK"),
         "Object Lock bucket setup failed");
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/" & Bucket, Configuration_Query)),
            "<Code>ObjectLockConfigurationNotFoundError</Code>"),
         "GetObjectLockConfiguration did not preserve initial absence");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Configuration_Document,
                  "Content-MD5: " & Content_MD5 (Configuration_Document) &
                  CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectLockConfiguration enabled an unversioned bucket");

      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          others => <>),
         null, Ada.Real_Time.Time_Last, Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Success,
         "Object Lock versioning prerequisite setup failed");

      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Configuration_Document)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectLockConfiguration accepted a missing Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Configuration_Document,
                  "Content-MD5: " & Content_MD5 ("different") & CRLF)),
            "<Code>BadDigest</Code>"),
         "PutObjectLockConfiguration accepted a mismatched Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Configuration_Document,
                  "Content-MD5: " & Content_MD5 (Configuration_Document) &
                  CRLF & "Content-MD5: " &
                  Content_MD5 (Configuration_Document) & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectLockConfiguration accepted duplicate Content-MD5");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Configuration_Document,
                  "Content-MD5: " & Content_MD5 (Configuration_Document) &
                  CRLF & "x-amz-bucket-object-lock-token: first" & CRLF &
                  "x-amz-bucket-object-lock-token: second" & CRLF)),
            "<Code>InvalidRequest</Code>"),
         "PutObjectLockConfiguration accepted duplicate lock tokens");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Duplicate_Configuration_Query,
                  Configuration_Document,
                  "Content-MD5: " & Content_MD5 (Configuration_Document) &
                  CRLF)),
            "<Code>InvalidArgument</Code>"),
         "PutObjectLockConfiguration accepted a duplicate subresource");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  "<ObjectLockConfiguration>",
                  "Content-MD5: " &
                  Content_MD5 ("<ObjectLockConfiguration>") & CRLF)),
            "<Code>MalformedXML</Code>"),
         "PutObjectLockConfiguration accepted malformed XML");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Rule_Document,
                  "Content-MD5: " & Content_MD5 (Rule_Document) & CRLF)),
            "<Code>NotImplemented</Code>"),
         "PutObjectLockConfiguration accepted a default retention rule");

      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/" & Bucket, Configuration_Query,
                  Configuration_Document,
                  "Content-MD5: " & Content_MD5 (Configuration_Document) &
                  CRLF & "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                  "x-amz-checksum-sha256: " &
                  Checksum_Value (Core.SHA256, Configuration_Document) &
                  CRLF)),
            "200 OK"),
         "PutObjectLockConfiguration rejected verified checksums");
      declare
         Response : constant String :=
           Run
             (Signed_Query_Request
                ("GET", "/" & Bucket,
                 (SigV4.Pair ("object-lock", ""),
                  SigV4.Pair
                    ("x-id", "GetObjectLockConfiguration"))));
         Configuration : constant
           Object_Lock.Object_Lock_Configuration :=
             Object_Lock.Parse_Configuration (Response_Body (Response));
      begin
         Require
           (Has (Response, "200 OK")
            and then Configuration.Is_Set
            and then Configuration.Enabled =
              Object_Lock.Object_Lock_Enabled
            and then not Configuration.Rule.Is_Set,
            "GetObjectLockConfiguration response mismatch");
      end;
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("GET", "/" & Bucket,
                  (SigV4.Pair ("object-lock", ""),
                   SigV4.Pair
                     ("x-id", "PutObjectLockConfiguration")))),
            "<Code>InvalidArgument</Code>"),
         "GetObjectLockConfiguration accepted a mismatched operation ID");

      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Flyology.Object_Storage.Versioning_Suspended,
          others => <>),
         null, Ada.Real_Time.Time_Last, Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Invalid_Request,
         "enabled Object Lock allowed versioning suspension");

      Require
        (Has
           (Run (Signed_Request ("PUT", Target, "first generation")),
            "200 OK"),
         "Object Lock first version setup failed");
      Store.Head_Object
        (Bucket, Key, null, Ada.Real_Time.Time_Last, First_Info,
         Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Success
         and then US.Length (First_Info.Version) > 0,
         "Object Lock first version identity was not retained");
      Require
        (Has
           (Run (Signed_Request ("PUT", Target, "second generation")),
            "200 OK"),
         "Object Lock second version setup failed");
      Store.Head_Object
        (Bucket, Key, null, Ada.Real_Time.Time_Last, Second_Info,
         Backend_Result);
      Require
        (Backend_Result = Flyology.Object_Storage.Success
         and then US.Length (Second_Info.Version) > 0
         and then US.To_String (First_Info.Version) /=
           US.To_String (Second_Info.Version),
         "Object Lock second version identity was not distinct");

      declare
         First_ID : constant String := US.To_String (First_Info.Version);
         Second_ID : constant String := US.To_String (Second_Info.Version);
         First_Hold_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("legal-hold", ""),
            SigV4.Pair ("versionId", First_ID));
         Second_Hold_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("legal-hold", ""),
            SigV4.Pair ("versionId", Second_ID));
         First_Retention_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("retention", ""),
            SigV4.Pair ("versionId", First_ID));
         Second_Retention_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("retention", ""),
            SigV4.Pair ("versionId", Second_ID));
      begin
         declare
            Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, First_Hold_Query));
            Value : constant Object_Lock.Legal_Hold :=
              Object_Lock.Parse_Legal_Hold (Response_Body (Response));
         begin
            Require
              (Has (Response, "200 OK")
               and then Value.Is_Set
               and then Value.Status = Object_Lock.Legal_Hold_Off,
               "GetObjectLegalHold did not preserve initial OFF state");
         end;
         declare
            Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, First_Retention_Query));
            Value : constant Object_Lock.Retention :=
              Object_Lock.Parse_Retention (Response_Body (Response));
         begin
            Require
              (Has (Response, "200 OK")
               and then Value.Is_Set
               and then Value.Mode = Object_Lock.Retention_Mode_Absent
               and then US.Length (Value.Retain_Until_Date) = 0,
               "GetObjectRetention did not preserve initial absence");
         end;

         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, First_Hold_Query, Hold_On_Document,
                     "Content-MD5: " & Content_MD5 (Hold_On_Document) &
                     CRLF)),
               "200 OK"),
            "PutObjectLegalHold rejected an exact selected version");
         declare
            First_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, First_Hold_Query));
            Second_Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, Second_Hold_Query));
            First_Value : constant Object_Lock.Legal_Hold :=
              Object_Lock.Parse_Legal_Hold
                (Response_Body (First_Response));
            Second_Value : constant Object_Lock.Legal_Hold :=
              Object_Lock.Parse_Legal_Hold
                (Response_Body (Second_Response));
         begin
            Require
              (First_Value.Status = Object_Lock.Legal_Hold_On
               and then Second_Value.Status = Object_Lock.Legal_Hold_Off,
               "legal-hold exact-version selection leaked across versions");
         end;

         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target,
                     (SigV4.Pair ("legal-hold", ""),
                      SigV4.Pair ("legal-hold", "")),
                     Hold_On_Document,
                     "Content-MD5: " & Content_MD5 (Hold_On_Document) &
                     CRLF)),
               "<Code>InvalidArgument</Code>"),
            "PutObjectLegalHold accepted a duplicate subresource");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, Second_Hold_Query, "<LegalHold>",
                     "Content-MD5: " & Content_MD5 ("<LegalHold>") &
                     CRLF)),
               "<Code>MalformedXML</Code>"),
            "PutObjectLegalHold accepted malformed XML");

         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, Second_Retention_Query,
                     Retention_Document,
                     "Content-MD5: " & Content_MD5 (Retention_Document) &
                     CRLF &
                     "x-amz-bypass-governance-retention: true" & CRLF)),
               "<Code>NotImplemented</Code>"),
            "PutObjectRetention accepted governance bypass");
         declare
            Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, Second_Retention_Query));
            Value : constant Object_Lock.Retention :=
              Object_Lock.Parse_Retention (Response_Body (Response));
         begin
            Require
              (Value.Mode = Object_Lock.Retention_Mode_Absent,
               "rejected governance bypass changed retained state");
         end;
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, Second_Retention_Query,
                     Retention_Document,
                     "Content-MD5: " & Content_MD5 (Retention_Document) &
                     CRLF & "x-amz-checksum-sha256: " &
                     Checksum_Value (Core.SHA256, "different") & CRLF)),
               "<Code>BadDigest</Code>"),
            "PutObjectRetention accepted a mismatched checksum");
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, Second_Retention_Query,
                     Retention_Document,
                     "Content-MD5: " & Content_MD5 (Retention_Document) &
                     CRLF & "x-amz-checksum-sha256: not-base64" & CRLF)),
               "<Code>InvalidRequest</Code>"),
            "PutObjectRetention accepted malformed checksum syntax");
         declare
            Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, Second_Retention_Query));
            Value : constant Object_Lock.Retention :=
              Object_Lock.Parse_Retention (Response_Body (Response));
         begin
            Require
              (Value.Mode = Object_Lock.Retention_Mode_Absent,
               "rejected retention checksum changed retained state");
         end;
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, Second_Retention_Query,
                     Retention_Document,
                     "Content-MD5: " & Content_MD5 (Retention_Document) &
                     CRLF &
                     "x-amz-bypass-governance-retention: false" & CRLF &
                     "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                     "x-amz-checksum-sha256: " &
                     Checksum_Value (Core.SHA256, Retention_Document) &
                     CRLF)),
               "200 OK"),
            "PutObjectRetention rejected verified exact-version state");
         declare
            Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target,
                    (SigV4.Pair ("retention", ""),
                     SigV4.Pair ("versionId", Second_ID),
                     SigV4.Pair ("x-id", "GetObjectRetention"))));
            Value : constant Object_Lock.Retention :=
              Object_Lock.Parse_Retention (Response_Body (Response));
         begin
            Require
              (Has (Response, "200 OK")
               and then Value.Mode = Object_Lock.Governance_Retention
               and then US.To_String (Value.Retain_Until_Date) =
                 "2099-01-01T01:00:00.500+01:00",
               "GetObjectRetention lost exact retained state");
         end;
         declare
            Retention : Flyology.Object_Storage.Object_Retention;
            Identity : Backends.Version_Identity;
         begin
            Store.Get_Object_Retention
              (Bucket, Key, null, Ada.Real_Time.Time_Last,
               Retention, Identity, Backend_Result,
               Selector =>
                 (Kind => Backends.Exact_Version,
                  ID => Second_Info.Version));
            Require
              (Backend_Result = Flyology.Object_Storage.Success
               and then Retention.Retain_Until = 4_070_908_801
               and then US.To_String (Retention.Exact_Text) =
                 "2099-01-01T01:00:00.500+01:00",
               "fractional retention deadline was not rounded upward");
         end;
         declare
            Response : constant String :=
              Run
                (Signed_Query_Request
                   ("GET", Target, First_Retention_Query));
            Value : constant Object_Lock.Retention :=
              Object_Lock.Parse_Retention (Response_Body (Response));
         begin
            Require
              (Value.Mode = Object_Lock.Retention_Mode_Absent,
               "retention exact-version selection leaked across versions");
         end;
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, First_Retention_Query,
                     Zero_Fraction_Retention_Document,
                     "Content-MD5: " &
                     Content_MD5 (Zero_Fraction_Retention_Document) &
                     CRLF)),
               "200 OK"),
            "PutObjectRetention rejected an all-zero fraction");
         declare
            Retention : Flyology.Object_Storage.Object_Retention;
            Identity : Backends.Version_Identity;
         begin
            Store.Get_Object_Retention
              (Bucket, Key, null, Ada.Real_Time.Time_Last,
               Retention, Identity, Backend_Result,
               Selector =>
                 (Kind => Backends.Exact_Version,
                  ID => First_Info.Version));
            Require
              (Backend_Result = Flyology.Object_Storage.Success
               and then Retention.Retain_Until = 946_684_800
               and then US.To_String (Retention.Exact_Text) =
                 "2000-01-01T00:00:00.000Z",
               "all-zero retention fraction changed the deadline");
         end;
         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, First_Retention_Query,
                     Negative_Offset_Retention_Document,
                     "Content-MD5: " &
                     Content_MD5 (Negative_Offset_Retention_Document) &
                     CRLF)),
               "200 OK"),
            "PutObjectRetention rejected a negative offset");
         declare
            Retention : Flyology.Object_Storage.Object_Retention;
            Identity : Backends.Version_Identity;
         begin
            Store.Get_Object_Retention
              (Bucket, Key, null, Ada.Real_Time.Time_Last,
               Retention, Identity, Backend_Result,
               Selector =>
                 (Kind => Backends.Exact_Version,
                  ID => First_Info.Version));
            Require
              (Backend_Result = Flyology.Object_Storage.Success
               and then Retention.Retain_Until = 946_684_801
               and then US.To_String (Retention.Exact_Text) =
                 "1999-12-31T23:00:00.500-01:00",
               "negative-offset retention deadline was not normalized");
         end;
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", Target,
                     (SigV4.Pair ("retention", ""),
                      SigV4.Pair ("versionId", "")))),
               "<Code>InvalidArgument</Code>"),
            "GetObjectRetention accepted an empty version selector");
         Require
           (Has
              (Run
                 (Signed_Query_Request
                    ("GET", Target,
                     (SigV4.Pair ("retention", ""),
                      SigV4.Pair ("versionId", Second_ID),
                      SigV4.Pair ("x-id", "PutObjectRetention")))),
               "<Code>InvalidArgument</Code>"),
            "GetObjectRetention accepted a mismatched operation ID");

         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    (Target,
                     (1 => SigV4.Pair ("versionId", First_ID)))),
               "403 Forbidden"),
            "DeleteObject removed a version under legal hold");
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    (Target,
                     (1 => SigV4.Pair ("versionId", Second_ID)),
                     Header_Name => "x-amz-mfa",
                     Header_Value => "device 123456")),
               "<Code>InvalidRequest</Code>"),
            "DeleteObject admitted an MFA credential over cleartext");
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    (Target,
                     (1 => SigV4.Pair ("versionId", Second_ID)),
                     Header_Name => "x-amz-mfa",
                     Header_Value => "device 123456"),
               Scheme => Flyology.HTTP.Secure_HTTPS),
            "403 Forbidden"),
            "MFA authorization bypassed active retention");
         Require
           (Has
              (Run (Signed_Delete_Object_Request (Target)),
               "204 No Content"),
            "current DeleteObject did not publish a protected marker");
         Require
           (Has
               (Run
                 (Signed_Query_Request
                    ("GET", Target, Second_Retention_Query)),
               "2099-01-01T01:00:00.500+01:00"),
            "current deletion changed the retained exact version");

         Require
           (Has
              (Run
                 (Signed_Query_Body_Request
                    ("PUT", Target, First_Hold_Query, Hold_Off_Document,
                     "Content-MD5: " & Content_MD5 (Hold_Off_Document) &
                     CRLF)),
               "200 OK"),
            "PutObjectLegalHold did not clear the selected hold");
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    (Target,
                     (1 => SigV4.Pair ("versionId", First_ID)))),
               "204 No Content"),
            "cleared legal hold still prevented exact deletion");
      end;
   end;

   Ada.Text_IO.Put_Line ("S3 server application corpus: OK");
end S3_Server_Application_Corpus;
