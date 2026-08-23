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
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.Tags;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.MFA;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;

procedure S3_Server_Application_Corpus is
   package HTTP_Server renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Sockets renames Flyology.IO.Sockets;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Buckets renames Flyology.Object_Storage.S3.Buckets;
   package Checksum_Policy renames
     Flyology.Object_Storage.S3.Checksum_Policy;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Attributes renames Flyology.Object_Storage.S3.Attributes;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Listings renames Flyology.Object_Storage.S3.Listings;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package Multipart_Uploads renames
     Flyology.Object_Storage.S3.Multipart_Uploads;
   package Backends renames Flyology.Object_Storage.Backends;
   package Tagging renames Flyology.Object_Storage.S3.Tagging;
   package Tags renames Flyology.Object_Storage.Tags;
   package Versioning renames Flyology.Object_Storage.S3.Versioning;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package MFA renames Flyology.Object_Storage.Server.MFA;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Containers.Count_Type;
   use type Ada.Calendar.Time;
   use type Flyology.Object_Storage.Status;
   use type Flyology.Object_Storage.Metadata_Time;
   use type Flyology.Object_Storage.Checksum_Algorithm;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;
   use type MFA.Authorization_Status;
   use type Tags.Tag_Vectors.Vector;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Access_Key : constant String := "AKIDEXAMPLE";
   Secret_Key : constant String :=
     "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
   Timestamp  : constant String := "20130524T000000Z";
   Region     : constant String := "us-east-1";
   Host       : constant String := "localhost:9000";

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

   Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 8,
      Object_Capacity => 16,
      Byte_Capacity   => 24 * 1_024 * 1_024);
   Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Access_Key, Secret_Key, Principal => "test-principal");
   MFA_Policy : aliased Test_MFA_Verifier;
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
      Second_Value : String := "") return String
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
   begin
      return "PUT " & Target & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if Header_Name'Length = 0 then ""
         else Header_Name & ": " & Header_Value & CRLF) &
        (if Second_Value'Length = 0 then ""
         else Header_Name & ": " & Second_Value & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
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
      Extra_Headers : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
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
      begin
         return Method & " " & Target & "?" & Query_Text & " HTTP/1.1" &
           CRLF & "Host: " & Host & CRLF & "x-amz-date: " & Timestamp &
           CRLF & "x-amz-content-sha256: " & Payload_Hash & CRLF &
           "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
           Extra_Headers & "Content-Length: " &
           Ada.Strings.Fixed.Trim
             (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
           "Connection: close" & CRLF & CRLF & Payload;
      end;
   end Signed_Query_Body_Request;

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
      Use_Null_MFA : Boolean := False)
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
            if Use_Null_MFA then
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
      Use_Null_MFA : Boolean := False) return String
   is (US.To_String
         (Run_Unbounded
            (US.To_Unbounded_String (Input), Receive_Max, Scheme,
             Use_Null_MFA)));

   function Has (Value, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Value, Pattern) /= 0);

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
                        "x-amz-expected-bucket-owner", "123456789012")),
                  "NotImplemented"),
               "ListMultipartUploads silently accepted expected owner");
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
      begin
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
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("POST", "/test-bucket/multipart-object", Query, Document,
                  "x-amz-checksum-algorithm: CRC64NVME" & CRLF &
                  "x-amz-checksum-type: FULL_OBJECT" & CRLF &
                  "x-amz-mp-object-size: 14" & CRLF),
               Receive_Max => 2);
            Parsed : constant Multipart.Complete_Multipart_Upload_Result :=
              Multipart.Parse_Complete_Result (Response_Body (Response));
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
                 ("/invalid-ownership-create", "",
                  "x-amz-object-ownership", "bogus")),
            "<Code>InvalidArgument</Code>"),
         "CreateBucket accepted invalid object ownership");
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
                 ("/oversized-create", String'(1 .. 65 * 1_024 => 'x'))),
            "<Code>EntityTooLarge</Code>"),
         "CreateBucket body size limit was not enforced");
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

   Check_Cancellation_Propagation;
   Check_Deadline_Propagation;
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
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("attributes", ""),
         SigV4.Pair ("x-id", "GetObjectAttributes"));
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
            "501 Not Implemented"),
         "GetObjectAttributes silently ignored a concrete version");
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
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectSize" & CRLF &
                  "x-amz-request-payer: owner" & CRLF)),
            "400 Bad Request"),
         "GetObjectAttributes accepted an invalid request payer");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectSize" & CRLF &
                  "x-amz-request-payer: requester" & CRLF)),
            "501 Not Implemented"),
         "GetObjectAttributes silently ignored requester-pays");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectSize" & CRLF &
                  "x-amz-server-side-encryption-customer-algorithm: " &
                  "AES256" & CRLF)),
            "400 Bad Request"),
         "GetObjectAttributes accepted an incomplete SSE-C group");
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("GET", "/test-bucket/object",
                  (1 => SigV4.Pair ("attributes", "")), "",
                  "x-amz-object-attributes: ObjectSize" & CRLF &
                  "x-amz-server-side-encryption-customer-algorithm: " &
                  "AES256" & CRLF &
                  "x-amz-server-side-encryption-customer-key: " &
                  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" & CRLF &
                  "x-amz-server-side-encryption-customer-key-md5: " &
                  "AAAAAAAAAAAAAAAAAAAAAA==" & CRLF)),
            "501 Not Implemented"),
         "GetObjectAttributes silently ignored a valid SSE-C group");
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
      Valid_MD5 : constant String := "SLw5gP7IN3lXnRzCSb/wzw==";
      Malformed_MD5 : constant String := "f++GbNyGMfP1p6OC2Va1xA==";
   begin
      Require
        (Has
           (Run
              (Signed_Query_Body_Request
                 ("PUT", "/test-bucket/object", Query, Document,
                  "Content-MD5: " & Valid_MD5 & CRLF &
                  "Content-Type: application/xml; charset=utf-8" & CRLF)),
            "200 OK"),
         "PutObjectTagging rejected a valid tagging document");
      declare
         Response : constant String :=
           Run (Signed_Query_Request ("GET", "/test-bucket/object", Query));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Type: application/xml")
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
           "501 Not Implemented"),
         "GetObjectTagging silently accepted versioning");
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
      Require
        (Has
           (Run
              (Signed_Query_Request
                 ("DELETE", "/test-bucket/object", Query)),
            "204 No Content"),
         "DeleteObjectTagging failed");
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
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256",
                  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                  "AAAAAAAAAAAAAAAAAAAAAA==")),
            "400 Bad Request"),
         "HeadObject accepted SSE-C headers for an unencrypted object");
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
            "501 Not Implemented"),
         "HeadObject accepted a real versionId without versioning");
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
            "501 Not Implemented"),
         "GetObject silently ignored a non-null version ID");
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
           (Run
              (Signed_Head_SSE_C_Request
                 ("AES256",
                  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                  "AAAAAAAAAAAAAAAAAAAAAA==", Method => "GET")),
            "501 Not Implemented"),
         "GetObject silently ignored a valid SSE-C header group");
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
   begin
      Require
        (Has (Run (Signed_Request
          ("PUT", "/delete-bucket/version-preserved", "v")), "200 OK"),
         "versioned DeleteObjects setup failed");
      Require
        (Has (Run (Signed_Request
          ("PUT", "/delete-bucket/version-peer", "p")), "200 OK"),
         "mixed versioned DeleteObjects setup failed");
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("version-preserved"),
          Version_ID => US.To_Unbounded_String ("unsupported-version"),
          others     => <>));
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("version-peer"),
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
         Require
           (Has (Response, "NotImplemented")
            and then Has (Response, "<Key>version-peer</Key>"),
            "mixed versioned DeleteObjects result mismatch");
      end;
      Require
        (Has (Run (Signed_Request
          ("GET", "/delete-bucket/version-preserved", "")), "v"),
         "versioned DeleteObjects removed the current object");
      Require
        (Has (Run (Signed_Request
          ("HEAD", "/delete-bucket/version-peer", "")), "404 Not Found"),
         "versioned DeleteObjects blocked an independent current delete");
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
      Require
        (Has
           (Run
              (Signed_Delete_Objects_Request
                 (Deletions.Serialize_Request (Request),
                  Bucket => "/delete-race-bucket")),
            "501 Not Implemented"),
         "DeleteObjects server raced past versioning publication");
      Require
        (Has
           (Run
              (Signed_Request
                 ("GET", "/delete-race-bucket/object", "")),
            "race-body"),
         "DeleteObjects server versioning race mutated backend state");
      Flyology.Object_Storage.Backends.Memory.Delete_Object
        (Store, "delete-race-bucket", "object", null,
         Ada.Real_Time.Time_Last, Backend_Result);
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
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Version)),
            "501 Not Implemented"),
         "DeleteObject silently ignored versionId");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Version_With_ID)),
            "501 Not Implemented"),
         "DeleteObject misrouted versionId with the SDK operation ID");
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
            "501 Not Implemented"),
         "verified MFA silently enabled object-version deletion");
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
         Require
           (Has
              (Run
                 (Signed_Delete_Object_Request
                    ("/delete-versioned/current")),
               "501 Not Implemented"),
            "DeleteObject silently removed configured-version data");
         Require
           (Has
              (Run
                 (Signed_Request
                    ("HEAD", "/delete-versioned/current", "")),
               "200 OK"),
            "refused configured DeleteObject mutated current data");
         Store.Delete_Object
           ("delete-versioned", "current", null,
            Ada.Real_Time.Time_Last, Backend_Result);
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

   Ada.Text_IO.Put_Line ("S3 server application corpus: OK");
end S3_Server_Application_Corpus;
