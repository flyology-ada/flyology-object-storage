with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.MD5;
with GNAT.SHA256;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.IO;
with Flyology.Object_Storage.Checksum_Engine;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.IMF_Dates;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Object_Reads;
with Flyology.Object_Storage.S3.Requests;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.S3.Wire_Core;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;

package body Flyology.Object_Storage.Server.S3_Applications is

   package Apps renames Flyology.HTTP.Server.Applications;
   package US renames Ada.Strings.Unbounded;
   package Requests renames S3.Requests;
   package Buckets renames S3.Buckets;
   package Bucket_Controls renames S3.Bucket_Controls;
   package Attributes renames S3.Attributes;
   package Checksum_Policy renames S3.Checksum_Policy;
   package Checksums renames S3.Checksums;
   package Encoding renames S3.SigV4_Encoding;
   package Deletions renames S3.Deletions;
   package IMF_Dates renames S3.IMF_Dates;
   package Listings renames S3.Listings;
   package Multipart renames S3.Multipart;
   package Multipart_Uploads renames S3.Multipart_Uploads;
   package Model renames S3.Model;
   package Object_Reads renames S3.Object_Reads;
   package Tagging renames S3.Tagging;
   package Versions renames S3.Versions;
   package Versioning renames S3.Versioning;
   package XML renames S3.XML;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Calendar.Time;
   use type Apps.Response_State;
   use type Authentication.Outcome_Status;
   use type Backends.Length_Kind;
   use type Backends.Copy_Metadata_Directive;
   use type Backends.Copy_Tagging_Directive;
   use type Backends.Version_Delete_Kind;
   use type Flyology.HTTP.Origin_Scheme;
   use type MFA.Authorization_Status;
   use type MFA.Verifier_Access;
   use type Multipart.Multipart_Query_Kind;
   use type Requests.Target_Kind;
   use type Requests.Target_Status;
   use type S3.Core.Range_Parse_Status;

   Payload_Hash_Mismatch : exception;
   Content_MD5_Mismatch : exception;
   Body_Checksum_Invalid : exception;
   Body_Checksum_Mismatch : exception;
   Malformed_Body_Framing : exception;
   Body_Entity_Too_Large : exception;

   Maximum_Create_Bucket_Body : constant Byte_Count := 64 * 1_024;
   --  Existing project-policy admission ceiling for the buffered
   --  CreateBucket configuration. It keeps request memory bounded; changing
   --  it changes accepted wire inputs and requires compatibility review.
   Maximum_Versioning_Body : constant Byte_Count :=
     Versioning.Maximum_Document_Bytes;
   --  Derived from the versioning codec's public document ceiling so the
   --  server and parser cannot drift; changing that source changes admission.
   Maximum_Delete_Objects_Body : constant Byte_Count :=
     Deletions.Maximum_Document_Bytes;
   --  Derived from the multi-delete codec's public document ceiling so the
   --  server and parser cannot drift; changing that source changes admission.
   Maximum_Complete_Multipart_Body : constant Byte_Count :=
     2 * 1_024 * 1_024;
   --  Existing project-policy ceiling for the buffered completion manifest.
   --  It bounds request memory; changing it changes accepted wire inputs.
   Maximum_Object_Tagging_Body : constant Byte_Count :=
     Tagging.Maximum_Document_Bytes;
   --  Derived from the object-tagging codec's public document ceiling so the
   --  server and parser cannot drift; changing that source changes admission.
   Maximum_Bucket_Tagging_Body : constant Byte_Count :=
     Tagging.Maximum_Bucket_Document_Bytes;
   --  Derived from the bucket-tagging codec's public document ceiling so the
   --  server and parser cannot drift; changing that source changes admission.
   Maximum_Public_Access_Block_Body : constant Byte_Count :=
     Byte_Count (XML.Default_Limits.Maximum_Document_Bytes);
   --  Derived from the shared caller-overridable XML resource policy used by
   --  the PublicAccessBlock codec; changing that source changes admission.

   function Decimal (Value : Byte_Count) return String is
     (Ada.Strings.Fixed.Trim
        (Byte_Count'Image (Value), Ada.Strings.Both));

   function Storage_Algorithm
     (Value : Checksum_Policy.Algorithm) return Checksum_Algorithm is
     (case Value is
         when S3.Core.CRC32     => Checksum_CRC32,
         when S3.Core.CRC32C    => Checksum_CRC32C,
         when S3.Core.CRC64NVME => Checksum_CRC64NVME,
         when S3.Core.SHA1      => Checksum_SHA1,
         when S3.Core.SHA256    => Checksum_SHA256,
         when S3.Core.SHA512    => Checksum_SHA512,
         when S3.Core.MD5       => Checksum_MD5,
         when S3.Core.XXHASH64  => Checksum_XXHASH64,
         when S3.Core.XXHASH3   => Checksum_XXHASH3,
         when S3.Core.XXHASH128 => Checksum_XXHASH128);

   function Storage_Method
     (Value : Checksum_Policy.Checksum_Type) return Checksum_Method is
     (case Value is
         when Checksum_Policy.Composite   => Composite_Checksum,
         when Checksum_Policy.Full_Object => Full_Object_Checksum);

   function Wire_Algorithm (Value : Checksum_Algorithm) return String is
     (case Value is
         when No_Checksum        => "",
         when Checksum_CRC32     => "CRC32",
         when Checksum_CRC32C    => "CRC32C",
         when Checksum_CRC64NVME => "CRC64NVME",
         when Checksum_SHA1      => "SHA1",
         when Checksum_SHA256    => "SHA256",
         when Checksum_SHA512    => "SHA512",
         when Checksum_MD5       => "MD5",
         when Checksum_XXHASH64  => "XXHASH64",
         when Checksum_XXHASH3   => "XXHASH3",
         when Checksum_XXHASH128 => "XXHASH128");

   function Wire_Method (Value : Checksum_Method) return String is
     (case Value is
         when No_Checksum_Method => "",
         when Composite_Checksum => "COMPOSITE",
         when Full_Object_Checksum => "FULL_OBJECT");

   function Checksum_Header_Name
     (Value : Checksum_Algorithm) return String is
     (case Value is
         when No_Checksum        => "",
         when Checksum_CRC32     => "x-amz-checksum-crc32",
         when Checksum_CRC32C    => "x-amz-checksum-crc32c",
         when Checksum_CRC64NVME => "x-amz-checksum-crc64nvme",
         when Checksum_SHA1      => "x-amz-checksum-sha1",
         when Checksum_SHA256    => "x-amz-checksum-sha256",
         when Checksum_SHA512    => "x-amz-checksum-sha512",
         when Checksum_MD5       => "x-amz-checksum-md5",
         when Checksum_XXHASH64  => "x-amz-checksum-xxhash64",
         when Checksum_XXHASH3   => "x-amz-checksum-xxhash3",
         when Checksum_XXHASH128 => "x-amz-checksum-xxhash128");

   procedure Set_Checksum_Headers
     (X : in out Apps.Exchange; Value : Checksum_Information) is
   begin
      if Value.Algorithm /= No_Checksum then
         Apps.Set_Header
           (X, Checksum_Header_Name (Value.Algorithm),
            US.To_String (Value.Value));
         Apps.Set_Header
           (X, "x-amz-checksum-type", Wire_Method (Value.Method));
      end if;
   end Set_Checksum_Headers;

   function Attribute_Checksum
     (Value        : Checksum_Information;
      Include_Kind : Boolean := True) return Attributes.Checksum_Values
   is
      Result : Attributes.Checksum_Values;
   begin
      case Value.Algorithm is
         when No_Checksum => null;
         when Checksum_CRC32 => Result.CRC32 := Value.Value;
         when Checksum_CRC32C => Result.CRC32C := Value.Value;
         when Checksum_CRC64NVME => Result.CRC64NVME := Value.Value;
         when Checksum_SHA1 => Result.SHA1 := Value.Value;
         when Checksum_SHA256 => Result.SHA256 := Value.Value;
         when Checksum_SHA512 => Result.SHA512 := Value.Value;
         when Checksum_MD5 => Result.MD5 := Value.Value;
         when Checksum_XXHASH64 => Result.XXHASH64 := Value.Value;
         when Checksum_XXHASH3 => Result.XXHASH3 := Value.Value;
         when Checksum_XXHASH128 => Result.XXHASH128 := Value.Value;
      end case;
      if Include_Kind then
         Result.Kind := US.To_Unbounded_String (Wire_Method (Value.Method));
      end if;
      return Result;
   end Attribute_Checksum;

   function Encode_Content_MD5
     (Digest : GNAT.MD5.Binary_Message_Digest) return String
   is
      Alphabet : constant String :=
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      Result : String (1 .. 24);
      Output : Positive := Result'First;

      function Byte (Index : Ada.Streams.Stream_Element_Offset)
        return Natural is (Natural (Digest (Index)));

      procedure Encode_Three (First : Ada.Streams.Stream_Element_Offset) is
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
   end Encode_Content_MD5;

   function Content_MD5 (Value : String) return String is
     (Encode_Content_MD5 (GNAT.MD5.Digest (Value)));

   function Valid_Tagging_Content_Type (Value : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Value);
   begin
      return Lower = "application/xml"
        or else Ada.Strings.Fixed.Index (Lower, "application/xml;") = 1;
   end Valid_Tagging_Content_Type;

   function Last_Modified (Value : Unix_Time) return String is
      Epoch : constant Ada.Calendar.Time :=
        Ada.Calendar.Formatting.Time_Of
          (1970, 1, 1, 0, 0, 0, Time_Zone => 0);
      Image : constant String := Ada.Calendar.Formatting.Image
        (Epoch + Duration (Value), Include_Time_Fraction => False,
         Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 9) & "T" &
        Image (Image'First + 11 .. Image'First + 18) & ".000Z";
   end Last_Modified;

   function HTTP_Last_Modified (Value : Unix_Time) return String is
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
   end HTTP_Last_Modified;

   procedure Send_Error
     (X        : in out Apps.Exchange;
      Status   : Positive;
      Code     : String;
      Message  : String;
      Resource : String)
   is
      Value : constant S3.Errors.Error_Response :=
        (Code       => US.To_Unbounded_String (Code),
         Message    => US.To_Unbounded_String (Message),
         Resource   => US.To_Unbounded_String (Resource),
         Request_ID => US.To_Unbounded_String (Apps.Request_ID (X)),
         Host_ID    => US.Null_Unbounded_String);
   begin
      Apps.Respond
        (X, Status, "application/xml", S3.Errors.Serialize (Value));
   end Send_Error;

   procedure Send_Authentication_Error
     (X        : in out Apps.Exchange;
      Outcome  : Authentication.Outcome;
      Resource : String)
   is
   begin
      case Outcome.Status is
         when Authentication.Missing_Credentials =>
            Send_Error
              (X, 403, "AccessDenied", "Access Denied", Resource);
         when Authentication.Malformed_Credentials =>
            Send_Error
              (X, 400, "AuthorizationHeaderMalformed",
               "The authorization header is malformed", Resource);
         when Authentication.Request_Time_Too_Skewed =>
            Send_Error
              (X, 403, "RequestTimeTooSkewed",
               "The difference between the request time and the current " &
               "time is too large", Resource);
         when Authentication.Wrong_Region =>
            Send_Error
              (X, 400, "AuthorizationHeaderMalformed",
               "The authorization region is not valid for this endpoint",
               Resource);
         when Authentication.Insecure_Unsigned_Payload =>
            Send_Error
              (X, 400, "InvalidRequest",
               "UNSIGNED-PAYLOAD requires a secure transport", Resource);
         when Authentication.Credential_Rejected =>
            Send_Error
              (X, 403, "SignatureDoesNotMatch",
               "The request signature does not match", Resource);
         when Authentication.Authenticated =>
            raise Program_Error with "authenticated outcome mapped as error";
      end case;
   end Send_Authentication_Error;

   procedure Send_Backend_Error
     (X         : in out Apps.Exchange;
      Result    : Status;
      Is_Bucket : Boolean;
      Resource  : String)
   is
   begin
      case Result is
         when Success =>
            raise Program_Error with
              "successful backend result mapped as error";
         when Not_Found =>
            Send_Error
              (X, 404,
               (if Is_Bucket then "NoSuchBucket" else "NoSuchKey"),
               (if Is_Bucket
                then "The specified bucket does not exist"
                else "The specified key does not exist"),
               Resource);
         when Bucket_Not_Found =>
            Send_Error
              (X, 404, "NoSuchBucket",
               "The specified bucket does not exist", Resource);
         when Tag_Set_Not_Found =>
            Send_Error
              (X, 404, "NoSuchTagSet",
               "The bucket has no tag set", Resource);
         when Already_Exists =>
            Send_Error
              (X, 409, "BucketAlreadyOwnedByYou",
               "The requested bucket already exists", Resource);
         when Bucket_Not_Empty =>
            Send_Error
              (X, 409, "BucketNotEmpty",
               "The bucket you tried to delete is not empty", Resource);
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
         when Invalid_Request =>
            Send_Error
              (X, 400, "InvalidRequest", "Invalid request", Resource);
         when Invalid_Range =>
            Send_Error
              (X, 416, "InvalidRange",
               "The requested range is not satisfiable", Resource);
         when Invalid_Part =>
            Send_Error
              (X, 400, "InvalidPart",
               "One or more of the specified parts could not be found",
               Resource);
         when Invalid_Part_Order =>
            Send_Error
              (X, 400, "InvalidPartOrder",
               "The list of parts was not in ascending order", Resource);
         when Entity_Too_Small =>
            Send_Error
              (X, 400, "EntityTooSmall",
               "A non-final multipart part was smaller than 5 MiB", Resource);
         when Entity_Too_Large =>
            Send_Error
              (X, 400, "EntityTooLarge",
               "Your proposed upload exceeds the maximum allowed size",
               Resource);
         when Bad_Digest =>
            Send_Error
              (X, 400, "BadDigest",
               "The checksum you specified did not match", Resource);
         when Source_Bucket_Not_Found =>
            Send_Error
              (X, 404, "NoSuchBucket",
               "The specified copy source bucket does not exist", Resource);
         when Source_Not_Found =>
            Send_Error
              (X, 404, "NoSuchKey",
               "The specified copy source does not exist", Resource);
         when Precondition_Failed =>
            Send_Error
              (X, 412, "PreconditionFailed",
               "At least one request precondition failed", Resource);
         when Not_Modified =>
            Apps.Respond (X, 304, "", "");
         when Conflict =>
            Send_Error
              (X, 409, "OperationAborted",
               "A conflicting operation is currently in progress", Resource);
         when Access_Denied =>
            Send_Error
              (X, 403, "AccessDenied", "Access Denied", Resource);
         when Not_Implemented =>
            Send_Error
              (X, 501, "NotImplemented",
               "The configured backend does not support this operation",
               Resource);
      end case;
   end Send_Backend_Error;

   procedure Handle (X : in out Apps.Exchange) is
      type Operation_Kind is
        (Unsupported,
         List_Buckets,
         Create_Bucket, Get_Bucket_Location, Head_Bucket, Delete_Bucket,
         Put_Bucket_Tagging, Get_Bucket_Tagging, Delete_Bucket_Tagging,
         Put_Public_Access_Block, Get_Public_Access_Block,
         Delete_Public_Access_Block,
         Put_Bucket_Versioning, Get_Bucket_Versioning,
         Put_Object, Copy_Object, Get_Object, Head_Object, Delete_Object,
         Put_Object_Tagging, Get_Object_Tagging, Delete_Object_Tagging,
         Get_Object_Attributes,
         Delete_Objects,
         List_Objects, List_Objects_V2, List_Object_Versions,
         List_Multipart_Uploads,
         Create_Multipart, Put_Multipart_Part, Copy_Multipart_Part,
         Complete_Multipart, Abort_Multipart, List_Multipart_Parts);

      function Is_Valid_Tagging_Query
        (Query, Request_Method : String) return Boolean
      is
         Operation : Tagging.Tagging_Operation;
      begin
         if Request_Method = "PUT" then
            Operation := Tagging.Put_Object_Tagging;
         elsif Request_Method = "GET" then
            Operation := Tagging.Get_Object_Tagging;
         elsif Request_Method = "DELETE" then
            Operation := Tagging.Delete_Object_Tagging;
         else
            return False;
         end if;
         declare
            Parsed_Query : constant Tagging.Tagging_Query :=
              Tagging.Parse_Query (Query, Operation);
            pragma Unreferenced (Parsed_Query);
         begin
            return True;
         end;
      exception
         when Tagging.Malformed_Tagging_Query =>
            return False;
      end Is_Valid_Tagging_Query;

      Target_Text : constant String := Apps.Request_Target (X);
      Method      : constant String := Apps.Request_Method (X);
      Parsed      : constant Requests.Target_Result :=
        Requests.Parse_Target (Target_Text);
      Query_Text  : constant String :=
        Requests.Query_String (Target_Text, Parsed);
      Is_Ordinary_Operation_Query : constant Boolean :=
        (Parsed.Kind = Requests.Bucket_Target
         and then
           ((Method = "PUT" and then Query_Text = "x-id=CreateBucket")
            or else
              (Method = "HEAD" and then Query_Text = "x-id=HeadBucket")
            or else
              (Method = "DELETE" and then Query_Text = "x-id=DeleteBucket")))
        or else
          (Parsed.Kind = Requests.Object_Target
           and then
             ((Method = "PUT" and then Query_Text = "x-id=PutObject")
              or else
                (Method = "PUT" and then Query_Text = "x-id=CopyObject")
              or else
                (Method = "GET" and then Query_Text = "x-id=GetObject")
              or else
                (Method = "HEAD" and then Query_Text = "x-id=HeadObject")
              or else
                (Method = "DELETE"
                 and then Query_Text = "x-id=DeleteObject")));
      Is_Delete_Objects_Query : constant Boolean :=
        Query_Text = "delete"
        or else Query_Text = "delete="
        or else Query_Text = "delete=&x-id=DeleteObjects"
        or else Query_Text = "x-id=DeleteObjects&delete=";
      Is_Get_Bucket_Location_Query : constant Boolean :=
        Query_Text = "location"
        or else Query_Text = "location="
        or else Query_Text = "location=&x-id=GetBucketLocation"
        or else Query_Text = "x-id=GetBucketLocation&location=";
      Is_Put_Bucket_Tagging_Query : constant Boolean :=
        Query_Text = "tagging"
        or else Query_Text = "tagging="
        or else Query_Text = "tagging=&x-id=PutBucketTagging"
        or else Query_Text = "x-id=PutBucketTagging&tagging=";
      Is_Get_Bucket_Tagging_Query : constant Boolean :=
        Query_Text = "tagging"
        or else Query_Text = "tagging="
        or else Query_Text = "tagging=&x-id=GetBucketTagging"
        or else Query_Text = "x-id=GetBucketTagging&tagging=";
      Is_Delete_Bucket_Tagging_Query : constant Boolean :=
        Query_Text = "tagging"
        or else Query_Text = "tagging="
        or else Query_Text = "tagging=&x-id=DeleteBucketTagging"
        or else Query_Text = "x-id=DeleteBucketTagging&tagging=";
      Is_Public_Access_Block_Query : constant Boolean :=
        Query_Text = "publicAccessBlock"
        or else Query_Text = "publicAccessBlock="
        or else Query_Text =
          "publicAccessBlock=&x-id=" &
            (if Method = "PUT" then "PutPublicAccessBlock"
             elsif Method = "GET" then "GetPublicAccessBlock"
             else "DeletePublicAccessBlock")
        or else Query_Text =
          "x-id=" &
            (if Method = "PUT" then "PutPublicAccessBlock"
             elsif Method = "GET" then "GetPublicAccessBlock"
             else "DeletePublicAccessBlock") &
          "&publicAccessBlock=";
      Padded_Query : constant String := '&' & Query_Text & '&';
      Has_Bucket_Tagging_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&tagging&") /= 0
        or else Ada.Strings.Fixed.Index (Padded_Query, "&tagging=") /= 0;
      Has_Bucket_Tagging_Operation_ID : constant Boolean :=
        (Method = "PUT"
         and then Ada.Strings.Fixed.Index
           (Padded_Query, "&x-id=PutBucketTagging&") /= 0)
        or else
          (Method = "GET"
           and then Ada.Strings.Fixed.Index
             (Padded_Query, "&x-id=GetBucketTagging&") /= 0)
        or else
          (Method = "DELETE"
           and then Ada.Strings.Fixed.Index
             (Padded_Query, "&x-id=DeleteBucketTagging&") /= 0);
      Looks_Like_Bucket_Tagging_Query : constant Boolean :=
        Has_Bucket_Tagging_Query or else Has_Bucket_Tagging_Operation_ID;
      Has_Public_Access_Block_Query : constant Boolean :=
        Ada.Strings.Fixed.Index
          (Padded_Query, "&publicAccessBlock&") /= 0
        or else Ada.Strings.Fixed.Index
          (Padded_Query, "&publicAccessBlock=") /= 0;
      Has_Public_Access_Block_Operation_ID : constant Boolean :=
        Ada.Strings.Fixed.Index
          (Padded_Query, "&x-id=PutPublicAccessBlock&") /= 0
        or else Ada.Strings.Fixed.Index
          (Padded_Query, "&x-id=GetPublicAccessBlock&") /= 0
        or else Ada.Strings.Fixed.Index
          (Padded_Query, "&x-id=DeletePublicAccessBlock&") /= 0;
      Looks_Like_Public_Access_Block_Query : constant Boolean :=
        Has_Public_Access_Block_Query
        or else Has_Public_Access_Block_Operation_ID;
      Has_Tagging_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&tagging") /= 0
        or else
          (Parsed.Kind = Requests.Object_Target
           and then Is_Valid_Tagging_Query (Query_Text, Method));
      Is_Bucket_Versioning_Query : constant Boolean :=
        Query_Text = "versioning"
        or else Query_Text = "versioning="
        or else
          Query_Text =
            "versioning=&x-id=" &
              (if Method = "PUT"
               then "PutBucketVersioning" else "GetBucketVersioning")
        or else
          Query_Text =
            "x-id=" &
              (if Method = "PUT"
               then "PutBucketVersioning" else "GetBucketVersioning") &
            "&versioning=";
      Has_Bucket_Versioning_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&versioning&") /= 0
        or else Ada.Strings.Fixed.Index (Padded_Query, "&versioning=") /= 0;
      Has_Upload_ID_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&uploadId=") /= 0
        or else Ada.Strings.Fixed.Index (Padded_Query, "&uploadId&") /= 0;
      Is_List_Objects_V2_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&list-type=2&") /= 0
        or else
          Ada.Strings.Fixed.Index
            (Padded_Query, "&x-id=ListObjectsV2&") /= 0;
      Is_List_Object_Versions_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&versions&") /= 0
        or else Ada.Strings.Fixed.Index (Padded_Query, "&versions=&") /= 0
        or else Ada.Strings.Fixed.Index
          (Padded_Query, "&x-id=ListObjectVersions&") /= 0;
      Is_List_Multipart_Uploads_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&uploads&") /= 0
        or else Ada.Strings.Fixed.Index (Padded_Query, "&uploads=&") /= 0
        or else Ada.Strings.Fixed.Index
          (Padded_Query, "&x-id=ListMultipartUploads&") /= 0;
      Is_Get_Object_Attributes_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&attributes&") /= 0
        or else Ada.Strings.Fixed.Index (Padded_Query, "&attributes=&") /= 0
        or else Ada.Strings.Fixed.Index
          (Padded_Query, "&x-id=GetObjectAttributes&") /= 0;
      Operation   : Operation_Kind := Unsupported;
      Multipart_Query_Invalid : Boolean := False;
      Delete_Object_Query_Invalid : Boolean := False;
      Delete_Request : Deletions.Delete_Object_Request;
      Object_Read_Query_Invalid : Boolean := False;
      Bucket_Versioning_Query_Invalid : Boolean := False;
      Bucket_Tagging_Query_Invalid : Boolean := False;
      Public_Access_Block_Query_Invalid : Boolean := False;
      Object_Read_Request : Object_Reads.Object_Read_Request;
      Tagging_Query_Invalid : Boolean := False;
      Tagging_Request : Tagging.Tagging_Query;
      Attributes_Query_Invalid : Boolean := False;
      Attributes_Request : Attributes.Attributes_Query;
      Has_Copy_Source : constant Boolean :=
        Apps.Request_Header_Count (X, "x-amz-copy-source") > 0;

      --  S3 defines the exact `null` wire value as the distinguished null
      --  generation.  All object-version routes share this protocol mapping;
      --  every other present value remains an opaque backend identity.
      function To_Version_Selector
        (Has_Version_ID : Boolean;
         Version_ID     : US.Unbounded_String)
         return Backends.Version_Selector is
        (if not Has_Version_ID
         then Backends.Current_Version_Selector
         elsif US.To_String (Version_ID) = "null"
         then Backends.Null_Version_Selector
         else
           (Kind => Backends.Exact_Version,
            ID   => Version_ID));

      function Read_Version_Selector return Backends.Version_Selector is
        (To_Version_Selector
           (Object_Read_Request.Has_Version_ID,
            Object_Read_Request.Version_ID));

      function Delete_Version_Selector return Backends.Version_Selector is
        (To_Version_Selector
           (Delete_Request.Has_Version_ID, Delete_Request.Version_ID));

      function Tagging_Version_Selector return Backends.Version_Selector is
        (To_Version_Selector
           (Tagging_Request.Has_Version_ID, Tagging_Request.Version_ID));

      function Attributes_Version_Selector return Backends.Version_Selector is
        (To_Version_Selector
           (Attributes_Request.Has_Version_ID,
           Attributes_Request.Version_ID));

      function Storage_Optional
        (Value : Bucket_Controls.Optional_Boolean)
         return Optional_Configuration_Boolean is
        (Is_Set => Value.Is_Set, Value => Value.Value);

      function Storage_Public_Access_Block
        (Value : Bucket_Controls.Public_Access_Block_Configuration)
         return Bucket_Public_Access_Block_Configuration is
        (Block_Public_ACLs       =>
           Storage_Optional (Value.Block_Public_ACLs),
         Ignore_Public_ACLs      =>
           Storage_Optional (Value.Ignore_Public_ACLs),
         Block_Public_Policy     =>
           Storage_Optional (Value.Block_Public_Policy),
         Restrict_Public_Buckets =>
           Storage_Optional (Value.Restrict_Public_Buckets));

      function Wire_Optional
        (Value : Optional_Configuration_Boolean)
         return Bucket_Controls.Optional_Boolean is
        (Is_Set => Value.Is_Set, Value => Value.Value);

      function Wire_Public_Access_Block
        (Value : Bucket_Public_Access_Block_Configuration)
         return Bucket_Controls.Public_Access_Block_Configuration is
        (Block_Public_ACLs       => Wire_Optional (Value.Block_Public_ACLs),
         Ignore_Public_ACLs      => Wire_Optional (Value.Ignore_Public_ACLs),
         Block_Public_Policy     =>
           Wire_Optional (Value.Block_Public_Policy),
         Restrict_Public_Buckets =>
           Wire_Optional (Value.Restrict_Public_Buckets));

      function Has_Encryption_Header return Boolean is
      begin
         for Index in 1 .. Apps.Request_Header_Count (X) loop
            declare
               Name : constant String := Ada.Characters.Handling.To_Lower
                 (Apps.Request_Header_Name (X, Index));
            begin
               if (Name'Length >= 28
                   and then Name (Name'First .. Name'First + 27) =
                     "x-amz-server-side-encryption")
                 or else
                   (Name'Length >= 40
                    and then Name (Name'First .. Name'First + 39) =
                      "x-amz-copy-source-server-side-encryption")
               then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Has_Encryption_Header;

      function Checksum_Header_Count return Natural is
         Result : Natural := 0;
      begin
         for Index in 1 .. Apps.Request_Header_Count (X) loop
            declare
               Name : constant String := Ada.Characters.Handling.To_Lower
                 (Apps.Request_Header_Name (X, Index));
            begin
               if Name'Length >= 15
                 and then Name (Name'First .. Name'First + 14) =
                   "x-amz-checksum-"
               then
                  Result := Result + 1;
               end if;
            end;
         end loop;
         return Result;
      end Checksum_Header_Count;

      function Has_Checksum_Header return Boolean is
        (Checksum_Header_Count > 0);

      function Checksum_Value_Header_Count return Natural is
         Result : Natural := 0;
      begin
         for Algorithm in Checksum_CRC32 .. Checksum_XXHASH128 loop
            Result := Result + Apps.Request_Header_Count
              (X, Checksum_Header_Name (Algorithm));
         end loop;
         return Result;
      end Checksum_Value_Header_Count;

      function Checksum_Value_Algorithm return Checksum_Algorithm is
      begin
         for Algorithm in Checksum_CRC32 .. Checksum_XXHASH128 loop
            if Apps.Request_Header_Count
              (X, Checksum_Header_Name (Algorithm)) > 0
            then
               return Algorithm;
            end if;
         end loop;
         return No_Checksum;
      end Checksum_Value_Algorithm;

      function Parse_Checksum_Algorithm
        (Text : String; Valid : out Boolean) return Checksum_Algorithm
      is
         Parsed : constant Checksum_Policy.Algorithm_Parse_Result :=
           Checksum_Policy.Parse_Algorithm (Text);
      begin
         Valid := Parsed.Valid;
         return
           (if Parsed.Valid then Storage_Algorithm (Parsed.Value)
            else No_Checksum);
      end Parse_Checksum_Algorithm;

      function Parse_Checksum_Method
        (Text : String; Valid : out Boolean) return Checksum_Method
      is
         Parsed : constant Checksum_Policy.Type_Parse_Result :=
           Checksum_Policy.Parse_Type (Text);
      begin
         Valid := Parsed.Valid;
         return
           (if Parsed.Valid then Storage_Method (Parsed.Value)
            else No_Checksum_Method);
      end Parse_Checksum_Method;

      Maximum_Expected_Owner_Bytes : constant Positive := 8_192;
      --  Pinned S3 request-header bound shared with the low-level client. This
      --  project-policy limit prevents unbounded owner controls; changing it
      --  changes which signed requests are admitted and requires new corpus
      --  and compatibility review.

      procedure Check_Expected_Bucket_Owner
        (Principal : String; Accepted : out Boolean)
      is
         Count : constant Natural := Apps.Request_Header_Count
           (X, "x-amz-expected-bucket-owner");
      begin
         Accepted := False;
         if Count > 1 then
            Send_Error
              (X, 400, "InvalidRequest",
               "The expected bucket owner header is duplicated",
               Target_Text);
         elsif Count = 1
           and then Apps.Request_Header
             (X, "x-amz-expected-bucket-owner")'Length
               not in 1 .. Maximum_Expected_Owner_Bytes
         then
            Send_Error
              (X, 400, "InvalidRequest",
               "The expected bucket owner header is invalid", Target_Text);
         elsif Count = 1
           and then Apps.Request_Header
             (X, "x-amz-expected-bucket-owner") /= Principal
         then
            Send_Error
              (X, 403, "AccessDenied", "Access Denied", Target_Text);
         else
            Accepted := True;
         end if;
      end Check_Expected_Bucket_Owner;

      function Copy_Result_XML
        (Root : String; Value : Object_Information) return String
      is
         Checksum_Type_XML : constant String :=
           (if Value.Checksum.Algorithm = No_Checksum
              or else Root /= "CopyObjectResult"
            then ""
            else "<ChecksumType>" & Wire_Method (Value.Checksum.Method) &
              "</ChecksumType>");
         Checksum_XML : constant String :=
           (if Value.Checksum.Algorithm = No_Checksum then ""
            else Checksum_Type_XML & "<Checksum" &
              Wire_Algorithm (Value.Checksum.Algorithm) &
              ">" & US.To_String (Value.Checksum.Value) & "</Checksum" &
              Wire_Algorithm (Value.Checksum.Algorithm) & ">");
      begin
         return
           "<" & Root &
           " xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<LastModified>" & Last_Modified (Value.Modified) &
           "</LastModified><ETag>&quot;" &
           US.To_String (Value.Entity_Tag) & "&quot;</ETag>" & Checksum_XML &
           "</" & Root & ">";
      end Copy_Result_XML;

      --  Project every retained metadata field from the same immutable
      --  Object_Information snapshot that supplies the body and generation.
      --  Content-Type is passed separately to Begin_Stream so that the HTTP
      --  application owns its singleton framing header.
      procedure Set_Object_Metadata_Headers
        (Info : Object_Information)
      is
         procedure Set_Optional
           (Name : String; Value : Optional_Metadata_Value) is
         begin
            if Value.Is_Set then
               Apps.Set_Header (X, Name, US.To_String (Value.Value));
            end if;
         end Set_Optional;
      begin
         Set_Optional ("Cache-Control", Info.Metadata.Cache_Control);
         Set_Optional
           ("Content-Disposition", Info.Metadata.Content_Disposition);
         Set_Optional ("Content-Encoding", Info.Metadata.Content_Encoding);
         Set_Optional ("Content-Language", Info.Metadata.Content_Language);
         if Info.Metadata.Expires.Is_Set then
            Apps.Set_Header
              (X, "Expires", IMF_Dates.Image (Info.Metadata.Expires.Value));
         end if;
         Set_Optional
           ("x-amz-website-redirect-location",
            Info.Metadata.Website_Redirect_Location);
         for Index in 1 .. Info.Metadata.User.Length loop
            Apps.Set_Header
              (X,
               "x-amz-meta-" &
                 US.To_String
                   (Info.Metadata.User.Items
                      (User_Metadata_Index (Index)).Key),
               US.To_String
                 (Info.Metadata.User.Items
                    (User_Metadata_Index (Index)).Value));
         end loop;
      end Set_Object_Metadata_Headers;

      package Request_IO is
         type Request_Source
           (Checksum_Kind : Checksum_Policy.Algorithm := S3.Core.CRC64NVME)
         is limited new Backends.Byte_Source with record
            Length_Value : Backends.Source_Length :=
              (Kind => Backends.Unknown);
            Expected_Hash : US.Unbounded_String;
            Check_Hash    : Boolean := False;
            Hash          : GNAT.SHA256.Context :=
              GNAT.SHA256.Initial_Context;
            Check_Content_MD5 : Boolean := False;
            Expected_Content_MD5 : US.Unbounded_String;
            Content_MD5_Hash : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
            Check_Body_Checksum : Boolean := False;
            Checksum_From_Trailer : Boolean := False;
            Reject_Unexpected_Trailers : Boolean := False;
            Expected_Body_Checksum : US.Unbounded_String;
            Body_Checksum_Hash : Checksums.Context (Checksum_Kind);
            Observed      : Byte_Count := 0;
            Maximum       : Byte_Count := Byte_Count'Last;
            Completed     : Boolean := False;
         end record;

         overriding function Declared_Length
           (Item : Request_Source) return Backends.Source_Length;

         overriding procedure Read
           (Item     : in out Request_Source;
            Data     : out Ada.Streams.Stream_Element_Array;
            Last     : out Ada.Streams.Stream_Element_Offset;
            Finished : out Boolean;
            Token    : access Flyology.Cancellation.Token;
            Deadline : Ada.Real_Time.Time);
      end Request_IO;

      package body Request_IO is
         overriding function Declared_Length
           (Item : Request_Source) return Backends.Source_Length is
           (Item.Length_Value);

         overriding procedure Read
           (Item     : in out Request_Source;
            Data     : out Ada.Streams.Stream_Element_Array;
            Last     : out Ada.Streams.Stream_Element_Offset;
            Finished : out Boolean;
            Token    : access Flyology.Cancellation.Token;
            Deadline : Ada.Real_Time.Time)
         is
            pragma Unreferenced (Token, Deadline);
            Chunk_Length : Byte_Count := 0;
         begin
            if Item.Completed then
               Last := Data'First - 1;
               Finished := True;
               return;
            end if;
            begin
               Apps.Read_Body (X, Data, Last, Finished);
            exception
               when Flyology.HTTP.Protocol_Error =>
                  raise Malformed_Body_Framing;
            end;
            if Last >= Data'First then
               Chunk_Length := Byte_Count (Last - Data'First + 1);
               if Chunk_Length > Item.Maximum
                 or else Item.Observed > Item.Maximum - Chunk_Length
               then
                  raise Body_Entity_Too_Large;
               elsif Item.Length_Value.Kind = Backends.Known
                 and then
                   (Chunk_Length > Item.Length_Value.Bytes
                    or else Item.Observed >
                      Item.Length_Value.Bytes - Chunk_Length)
               then
                  raise Malformed_Body_Framing;
               end if;
               Item.Observed := Item.Observed + Chunk_Length;
               GNAT.SHA256.Update (Item.Hash, Data (Data'First .. Last));
               if Item.Check_Content_MD5 then
                  GNAT.MD5.Update
                    (Item.Content_MD5_Hash, Data (Data'First .. Last));
               end if;
               if Item.Check_Body_Checksum then
                  Checksums.Update
                    (Item.Body_Checksum_Hash, Data (Data'First .. Last));
               end if;
            end if;
            if Finished then
               Item.Completed := True;
               if Item.Checksum_From_Trailer
                 and then not Apps.Body_Complete (X)
               then
                  raise Body_Checksum_Invalid;
               elsif Item.Length_Value.Kind = Backends.Known
                 and then Item.Observed /= Item.Length_Value.Bytes
               then
                  raise Malformed_Body_Framing;
               elsif Item.Check_Hash
                 and then GNAT.SHA256.Digest (Item.Hash) /=
                   Encoding.Lowercase (US.To_String (Item.Expected_Hash))
               then
                  raise Payload_Hash_Mismatch;
               end if;
               if Item.Check_Content_MD5 then
                  declare
                     Digest : constant GNAT.MD5.Binary_Message_Digest :=
                       GNAT.MD5.Digest (Item.Content_MD5_Hash);
                  begin
                     if Encode_Content_MD5 (Digest) /=
                       US.To_String (Item.Expected_Content_MD5)
                     then
                        raise Content_MD5_Mismatch;
                     end if;
                  end;
               end if;
               if Item.Reject_Unexpected_Trailers
                 and then not Item.Checksum_From_Trailer
                 and then Apps.Request_Trailer_Count (X) > 0
               then
                  raise Body_Checksum_Invalid;
               end if;
               if Item.Check_Body_Checksum then
                  if Item.Checksum_From_Trailer
                    and then
                      (Apps.Request_Trailer_Count (X) /= 1
                       or else Apps.Request_Trailer_Count
                         (X, Checksum_Header_Name
                            (Storage_Algorithm (Item.Checksum_Kind))) /= 1)
                  then
                     raise Body_Checksum_Invalid;
                  end if;
                  declare
                     Supplied : constant String :=
                       (if Item.Checksum_From_Trailer
                        then Apps.Request_Trailer
                          (X, Checksum_Header_Name
                             (Storage_Algorithm (Item.Checksum_Kind)))
                        else US.To_String (Item.Expected_Body_Checksum));
                     Computed : constant String :=
                       Checksums.Encode_Base64
                         (Checksums.Finish (Item.Body_Checksum_Hash));
                  begin
                     if not Checksum_Engine.Valid_Digest
                       (Supplied, Storage_Algorithm (Item.Checksum_Kind))
                     then
                        raise Body_Checksum_Invalid;
                     elsif Supplied /= Computed then
                        raise Body_Checksum_Mismatch;
                     end if;
                  end;
               end if;
            elsif Last < Data'First then
               raise Malformed_Body_Framing;
            end if;
         end Read;
      end Request_IO;

      package Response_IO is
         type Response_Sink is limited new Backends.Byte_Sink with record
            Started  : Boolean := False;
            Expected : Byte_Count := 0;
            Observed : Byte_Count := 0;
            Include_Checksum : Boolean := False;
            Suppress_Composite_Checksum : Boolean := False;
         end record;

         overriding procedure Begin_Object
           (Item           : in out Response_Sink;
            Info           : Object_Information;
            First          : Byte_Count;
            Content_Length : Byte_Count;
            Partial        : Boolean;
            Token          : access Flyology.Cancellation.Token;
            Deadline       : Ada.Real_Time.Time);

         overriding procedure Write
           (Item     : in out Response_Sink;
            Data     : Ada.Streams.Stream_Element_Array;
            Token    : access Flyology.Cancellation.Token;
            Deadline : Ada.Real_Time.Time);
      end Response_IO;

      package body Response_IO is
         overriding procedure Begin_Object
           (Item           : in out Response_Sink;
            Info           : Object_Information;
            First          : Byte_Count;
            Content_Length : Byte_Count;
            Partial        : Boolean;
            Token          : access Flyology.Cancellation.Token;
            Deadline       : Ada.Real_Time.Time)
         is
            pragma Unreferenced (Token, Deadline);
            Entity_Tag : constant String := US.To_String (Info.Entity_Tag);
            Content_Type : constant String :=
              (if Object_Read_Request.Has_Response_Content_Type
               then US.To_String
                 (Object_Read_Request.Response_Content_Type)
               else US.To_String (Info.Content_Type));

            procedure Set_Override
              (Name : String;
               Has_Value : Boolean;
               Value : US.Unbounded_String) is
            begin
               if Has_Value then
                  Apps.Set_Header (X, Name, US.To_String (Value));
               end if;
            end Set_Override;
         begin
            if Item.Started then
               raise Program_Error with "backend began an object twice";
            elsif Partial
              and then
                (Content_Length = 0
                 or else First >= Info.Size
                 or else Content_Length > Info.Size - First)
            then
               raise Program_Error with "backend announced an invalid range";
            elsif not Partial
              and then (First /= 0 or else Content_Length /= Info.Size)
            then
               raise Program_Error with
                 "backend announced an invalid whole-object response";
            end if;
            Apps.Set_Header (X, "Accept-Ranges", "bytes");
            if Entity_Tag'Length > 0 then
               Apps.Set_Header (X, "ETag", '"' & Entity_Tag & '"');
            end if;
            Apps.Set_Header
              (X, "Last-Modified", HTTP_Last_Modified (Info.Modified));
            if US.Length (Info.Version) > 0 then
               Apps.Set_Header
                 (X, "x-amz-version-id", US.To_String (Info.Version));
            elsif Object_Read_Request.Has_Version_ID then
               Apps.Set_Header (X, "x-amz-version-id", "null");
            end if;
            if Item.Include_Checksum
              and then not
                (Item.Suppress_Composite_Checksum
                 and then Info.Checksum.Method = Composite_Checksum)
            then
               Set_Checksum_Headers (X, Info.Checksum);
            end if;
            Set_Object_Metadata_Headers (Info);
            if Partial then
               Apps.Set_Header
                 (X, "Content-Range",
                  "bytes " & Decimal (First) & "-" &
                  Decimal (First + Content_Length - 1) & "/" &
                  Decimal (Info.Size));
            end if;
            Set_Override
              ("Cache-Control",
               Object_Read_Request.Has_Response_Cache_Control,
               Object_Read_Request.Response_Cache_Control);
            Set_Override
              ("Content-Disposition",
               Object_Read_Request.Has_Response_Content_Disposition,
               Object_Read_Request.Response_Content_Disposition);
            Set_Override
              ("Content-Encoding",
               Object_Read_Request.Has_Response_Content_Encoding,
               Object_Read_Request.Response_Content_Encoding);
            Set_Override
              ("Content-Language",
               Object_Read_Request.Has_Response_Content_Language,
               Object_Read_Request.Response_Content_Language);
            Set_Override
              ("Expires", Object_Read_Request.Has_Response_Expires,
               Object_Read_Request.Response_Expires);
            Apps.Begin_Stream
              (X, (if Partial then 206 else 200),
               Content_Type,
               Flyology.HTTP.Body_Size (Content_Length));
            Item.Started  := True;
            Item.Expected := Content_Length;
         end Begin_Object;

         overriding procedure Write
           (Item     : in out Response_Sink;
            Data     : Ada.Streams.Stream_Element_Array;
            Token    : access Flyology.Cancellation.Token;
            Deadline : Ada.Real_Time.Time)
         is
            pragma Unreferenced (Token, Deadline);
            Count : constant Byte_Count := Byte_Count (Data'Length);
         begin
            if not Item.Started or else Data'Length = 0 then
               raise Program_Error with "invalid backend response fragment";
            elsif Count > Item.Expected
              or else Item.Observed > Item.Expected - Count
            then
               raise Program_Error with
                 "backend exceeded its announced response length";
            end if;
            Apps.Write_Chunk (X, Data);
            Item.Observed := Item.Observed + Count;
         end Write;
      end Response_IO;

      function Body_Length (Valid : out Boolean) return Backends.Source_Length
      is
         Count : constant Natural :=
           Apps.Request_Header_Count (X, "content-length");
      begin
         if Count = 0 then
            Valid := True;
            return (Kind => Backends.Unknown);
         elsif Count /= 1 then
            Valid := False;
            return (Kind => Backends.Unknown);
         end if;
         declare
            Parsed_Length : constant S3.Wire_Core.Byte_Count_Result :=
              S3.Wire_Core.Parse_Byte_Count
                (Apps.Request_Header (X, "content-length"));
         begin
            if not Parsed_Length.Valid then
               Valid := False;
               return (Kind => Backends.Unknown);
            end if;
            Valid := True;
            return (Kind => Backends.Known, Bytes => Parsed_Length.Value);
         end;
      end Body_Length;

      function Read_Document
        (Source : in out Request_IO.Request_Source) return String
      is
         Buffer   : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
         Last     : Ada.Streams.Stream_Element_Offset;
         Finished : Boolean := False;
         Document : US.Unbounded_String;
      begin
         while not Finished loop
            Source.Read
              (Buffer, Last, Finished, Apps.Cancellation (X),
               Apps.Deadline (X));
            for Index in Buffer'First .. Last loop
               US.Append (Document, Character'Val (Buffer (Index)));
            end loop;
         end loop;
         return US.To_String (Document);
      end Read_Document;

      type Document_Checksum_Status is
        (Document_Checksum_OK,
         Document_Checksum_Group_Invalid,
         Document_Checksum_Value_Invalid,
         Document_Checksum_Mismatch);

      function Checksum_Header_Name
        (Algorithm : Checksum_Policy.Algorithm) return String is
        (case Algorithm is
            when S3.Core.CRC32 => "x-amz-checksum-crc32",
            when S3.Core.CRC32C => "x-amz-checksum-crc32c",
            when S3.Core.CRC64NVME => "x-amz-checksum-crc64nvme",
            when S3.Core.SHA1 => "x-amz-checksum-sha1",
            when S3.Core.SHA256 => "x-amz-checksum-sha256",
            when S3.Core.SHA512 => "x-amz-checksum-sha512",
            when S3.Core.MD5 => "x-amz-checksum-md5",
            when S3.Core.XXHASH64 => "x-amz-checksum-xxhash64",
            when S3.Core.XXHASH3 => "x-amz-checksum-xxhash3",
            when S3.Core.XXHASH128 => "x-amz-checksum-xxhash128");

      function Verify_Document_Checksum
        (Document : String) return Document_Checksum_Status
      is
         SDK_Count : constant Natural := Apps.Request_Header_Count
           (X, "x-amz-sdk-checksum-algorithm");
         Trailer_Declaration_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-trailer");
         CRC32_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-crc32");
         CRC32C_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-crc32c");
         CRC64_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-crc64nvme");
         SHA1_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-sha1");
         SHA256_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-sha256");
         SHA512_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-sha512");
         MD5_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-md5");
         XXHASH64_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-xxhash64");
         XXHASH3_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-xxhash3");
         XXHASH128_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-checksum-xxhash128");
         Checksum_Count : constant Natural :=
           CRC32_Count + CRC32C_Count + CRC64_Count + SHA1_Count +
           SHA256_Count + SHA512_Count + MD5_Count + XXHASH64_Count +
           XXHASH3_Count + XXHASH128_Count;

         function Count_For
           (Algorithm : Checksum_Policy.Algorithm) return Natural is
           (case Algorithm is
               when S3.Core.CRC32 => CRC32_Count,
               when S3.Core.CRC32C => CRC32C_Count,
               when S3.Core.CRC64NVME => CRC64_Count,
               when S3.Core.SHA1 => SHA1_Count,
               when S3.Core.SHA256 => SHA256_Count,
               when S3.Core.SHA512 => SHA512_Count,
               when S3.Core.MD5 => MD5_Count,
               when S3.Core.XXHASH64 => XXHASH64_Count,
               when S3.Core.XXHASH3 => XXHASH3_Count,
               when S3.Core.XXHASH128 => XXHASH128_Count);

         function Concrete_Algorithm return
           Checksum_Policy.Algorithm_Parse_Result is
         begin
            for Algorithm in Checksum_Policy.Algorithm loop
               if Count_For (Algorithm) = 1 then
                  return (Valid => True, Value => Algorithm);
               end if;
            end loop;
            return (Valid => False);
         end Concrete_Algorithm;

         SDK_Algorithm : constant Checksum_Policy.Algorithm_Parse_Result :=
           (if SDK_Count = 1
            then Checksum_Policy.Parse_Algorithm
              (Apps.Request_Header (X, "x-amz-sdk-checksum-algorithm"))
            else (Valid => False));
         Concrete : constant Checksum_Policy.Algorithm_Parse_Result :=
           Concrete_Algorithm;
         Has_Trailer : constant Boolean := Trailer_Declaration_Count = 1;
         Selected : Checksum_Policy.Algorithm_Parse_Result :=
           (Valid => False);
         Supplied : US.Unbounded_String;
      begin
         if SDK_Count > 1 or else Trailer_Declaration_Count > 1
           or else CRC32_Count > 1 or else CRC32C_Count > 1
           or else CRC64_Count > 1 or else SHA1_Count > 1
           or else SHA256_Count > 1 or else SHA512_Count > 1
           or else MD5_Count > 1 or else XXHASH64_Count > 1
           or else XXHASH3_Count > 1 or else XXHASH128_Count > 1
           or else Checksum_Count > 1
           or else (SDK_Count = 1 and then not SDK_Algorithm.Valid)
         then
            return Document_Checksum_Group_Invalid;
         elsif Has_Trailer then
            if SDK_Count /= 1 or else Checksum_Count /= 0
              or else Apps.Request_Trailer_Count (X) /= 1
              or else Ada.Characters.Handling.To_Lower
                (Apps.Request_Header (X, "x-amz-trailer")) /=
                  Checksum_Header_Name (SDK_Algorithm.Value)
              or else Apps.Request_Trailer_Count
                (X, Checksum_Header_Name (SDK_Algorithm.Value)) /= 1
            then
               return Document_Checksum_Group_Invalid;
            end if;
            Selected := SDK_Algorithm;
            Supplied := US.To_Unbounded_String
              (Apps.Request_Trailer
                 (X, Checksum_Header_Name (Selected.Value)));
         elsif Apps.Request_Trailer_Count (X) > 0
           or else (SDK_Count = 1 and then Checksum_Count = 0)
         then
            return Document_Checksum_Group_Invalid;
         elsif Checksum_Count = 0 then
            return Document_Checksum_OK;
         else
            --  The operation contract says an individual checksum takes
            --  precedence over the SDK algorithm selector.
            Selected := Concrete;
            Supplied := US.To_Unbounded_String
              (Apps.Request_Header
                 (X, Checksum_Header_Name (Selected.Value)));
         end if;

         declare
            Decoded : constant Checksums.Decode_Result :=
              Checksums.Decode_Base64
                (US.To_String (Supplied), Selected.Value);
         begin
            if not Decoded.Valid then
               return Document_Checksum_Value_Invalid;
            end if;
            declare
               Computed : constant Checksums.Digest_Value :=
                 Checksums.Compute
                   (Selected.Value,
                    Flyology.Bytes.To_Array
                      (Flyology.Bytes.From_Byte_String (Document)));
            begin
               return
                 (if Checksums.Equivalent (Decoded.Value, Computed)
                  then Document_Checksum_OK
                  else Document_Checksum_Mismatch);
            end;
         end;
      end Verify_Document_Checksum;

      function Verify_MFA_Credential
        (Principal, Credential : String) return MFA.Authorization_Status
      is
         Request : MFA.Authorization_Request;
         Build   : MFA.Request_Status;
         Result  : MFA.Authorization_Status := MFA.Verifier_Unavailable;
      begin
         MFA.Initialize
           (Request, Principal, Credential,
            Apps.Request_Scheme (X) = Flyology.HTTP.Secure_HTTPS, Build);
         case Build is
            when MFA.Principal_Invalid =>
               Result := MFA.Not_Root_Owner;
            when MFA.Credential_Missing =>
               Result := MFA.Missing_Credential;
            when MFA.Credential_Invalid =>
               Result := MFA.Invalid_Credential;
            when MFA.Request_Ready =>
               if Apps.Request_Scheme (X) /= Flyology.HTTP.Secure_HTTPS then
                  Result := MFA.Insecure_Transport;
               elsif MFA_Verifier = null then
                  Result := MFA.Verifier_Unavailable;
               else
                  begin
                     MFA_Verifier.all.Authorize (Request, Result);
                  exception
                     when others =>
                        Result := MFA.Verifier_Unavailable;
                  end;
               end if;
         end case;
         MFA.Clear (Request);
         return Result;
      exception
         when others =>
            MFA.Clear (Request);
            return MFA.Verifier_Unavailable;
      end Verify_MFA_Credential;

      procedure Send_MFA_Error (Result : MFA.Authorization_Status) is
      begin
         if Result = MFA.Insecure_Transport then
            Send_Error
              (X, 400, "InvalidRequest",
               "MFA-protected requests require HTTPS", Target_Text);
         elsif Result = MFA.Authorized then
            raise Program_Error with "authorized MFA result mapped as error";
         else
            --  Missing devices, invalid one-time credentials, non-root
            --  principals, and unavailable verifiers are intentionally
            --  indistinguishable at the S3 boundary.
            Send_Error
              (X, 403, "AccessDenied", "Access Denied", Target_Text);
         end if;
      end Send_MFA_Error;

      Auth       : Authentication.Outcome;
      Accepted   : Boolean;
      Length_OK  : Boolean;
      Length     : Backends.Source_Length;
      Info       : Object_Information;
      Publication_Identity : Backends.Version_Identity;
      Result     : Status;
   begin
      if Parsed.Status /= Requests.Target_Parsed then
         Send_Error
           (X, 400, "InvalidURI", "Could not parse the specified URI",
            Target_Text);
         return;
      elsif Parsed.Has_Query
        and then not Is_Ordinary_Operation_Query
        and then not
          (Parsed.Kind = Requests.Service_Target and then Method = "GET")
        and then not
          (Parsed.Kind = Requests.Bucket_Target
           and then Method = "POST"
           and then Is_Delete_Objects_Query)
        and then not
           (Parsed.Kind = Requests.Bucket_Target
           and then Method in "PUT" | "GET" | "DELETE"
           and then Looks_Like_Bucket_Tagging_Query)
        and then not
          (Parsed.Kind = Requests.Bucket_Target
           and then Method in "PUT" | "GET" | "DELETE"
           and then Looks_Like_Public_Access_Block_Query)
        and then not
          (Parsed.Kind = Requests.Object_Target
           and then Method = "DELETE"
           and then Requests.Query_String (Target_Text, Parsed) =
             "x-id=DeleteObject")
        and then not
          (Parsed.Kind = Requests.Object_Target
           and then Method in "PUT" | "GET" | "DELETE"
           and then Has_Tagging_Query)
        and then not
          (Parsed.Kind = Requests.Object_Target
           and then
             Method in "POST" | "PUT" | "DELETE" | "GET")
        and then not
          (Parsed.Kind = Requests.Object_Target and then Method = "HEAD")
        and then not
          (Parsed.Kind = Requests.Bucket_Target and then Method = "GET")
        and then not
          (Parsed.Kind = Requests.Bucket_Target
           and then Method = "PUT"
           and then Has_Bucket_Versioning_Query)
      then
         Send_Error
           (X, 501, "NotImplemented",
            "The requested S3 operation is not implemented", Target_Text);
         return;
      end if;

      if Parsed.Kind = Requests.Service_Target then
         Operation := (if Method = "GET" then List_Buckets else Unsupported);
      elsif Parsed.Kind = Requests.Bucket_Target then
         Bucket_Tagging_Query_Invalid :=
           Method in "PUT" | "GET" | "DELETE"
           and then Looks_Like_Bucket_Tagging_Query
           and then
             (if Method = "PUT" then not Is_Put_Bucket_Tagging_Query
              elsif Method = "GET" then not Is_Get_Bucket_Tagging_Query
              else not Is_Delete_Bucket_Tagging_Query);
         Bucket_Versioning_Query_Invalid :=
           Method in "GET" | "PUT"
           and then Has_Bucket_Versioning_Query
           and then not Is_Bucket_Versioning_Query;
         Public_Access_Block_Query_Invalid :=
           Method in "PUT" | "GET" | "DELETE"
           and then Looks_Like_Public_Access_Block_Query
           and then not Is_Public_Access_Block_Query;
         Operation :=
           (if Method = "PUT"
             and then Looks_Like_Public_Access_Block_Query
            then Put_Public_Access_Block
            elsif Method = "GET"
              and then Looks_Like_Public_Access_Block_Query
            then Get_Public_Access_Block
            elsif Method = "DELETE"
              and then Looks_Like_Public_Access_Block_Query
            then Delete_Public_Access_Block
            elsif Method = "PUT" and then Looks_Like_Bucket_Tagging_Query
            then Put_Bucket_Tagging
            elsif Method = "GET" and then Looks_Like_Bucket_Tagging_Query
            then Get_Bucket_Tagging
            elsif Method = "DELETE" and then Looks_Like_Bucket_Tagging_Query
            then Delete_Bucket_Tagging
            elsif Method = "PUT"
              and then
                (not Parsed.Has_Query
                 or else Query_Text = "x-id=CreateBucket")
            then Create_Bucket
            elsif Method = "HEAD"
              and then
                (not Parsed.Has_Query or else Query_Text = "x-id=HeadBucket")
            then Head_Bucket
            elsif Method = "DELETE"
              and then
                (not Parsed.Has_Query
                 or else Query_Text = "x-id=DeleteBucket")
            then Delete_Bucket
            elsif Method = "POST" and then Parsed.Has_Query
              and then Is_Delete_Objects_Query
            then Delete_Objects
            elsif Method = "GET" and then Is_Get_Bucket_Location_Query
            then Get_Bucket_Location
            elsif Method = "PUT" and then Has_Bucket_Versioning_Query
            then Put_Bucket_Versioning
            elsif Method = "GET" and then Has_Bucket_Versioning_Query
            then Get_Bucket_Versioning
            elsif Method = "GET" and then Is_List_Objects_V2_Query
            then List_Objects_V2
            elsif Method = "GET" and then Is_List_Object_Versions_Query
            then List_Object_Versions
            elsif Method = "GET" and then Is_List_Multipart_Uploads_Query
            then List_Multipart_Uploads
            elsif Method = "GET" then List_Objects
            else Unsupported);
      elsif Parsed.Kind = Requests.Object_Target then
         if Parsed.Has_Query and then Has_Tagging_Query
           and then Method in "PUT" | "GET" | "DELETE"
         then
            declare
               Tagging_Operation : constant Tagging.Tagging_Operation :=
                 (if Method = "PUT" then Tagging.Put_Object_Tagging
                  elsif Method = "GET" then Tagging.Get_Object_Tagging
                  else Tagging.Delete_Object_Tagging);
            begin
               Tagging_Request :=
                 Tagging.Parse_Query (Query_Text, Tagging_Operation);
               Operation :=
                 (if Method = "PUT" then Put_Object_Tagging
                  elsif Method = "GET" then Get_Object_Tagging
                  else Delete_Object_Tagging);
            exception
               when Tagging.Malformed_Tagging_Query =>
                  Tagging_Query_Invalid := True;
                  Operation :=
                    (if Method = "PUT" then Put_Object_Tagging
                     elsif Method = "GET" then Get_Object_Tagging
                     else Delete_Object_Tagging);
            end;
         elsif not Parsed.Has_Query or else Is_Ordinary_Operation_Query then
            Operation :=
              (if Method = "PUT"
                 and then
                   (Has_Copy_Source or else Query_Text = "x-id=CopyObject")
               then Copy_Object
               elsif Method = "PUT" then Put_Object
               elsif Method = "GET" then Get_Object
               elsif Method = "HEAD" then Head_Object
               elsif Method = "DELETE" then Delete_Object
               else Unsupported);
         elsif Method = "HEAD" then
            begin
               Object_Read_Request := Object_Reads.Parse_Query
                 (Query_Text, Object_Reads.Head_Object);
               Operation := Head_Object;
            exception
               when Object_Reads.Malformed_Object_Read_Request =>
                  Object_Read_Query_Invalid := True;
                  Operation := Head_Object;
            end;
         elsif Method = "GET" and then Is_Get_Object_Attributes_Query then
            begin
               Attributes_Request := Attributes.Parse_Query (Query_Text);
               Operation := Get_Object_Attributes;
            exception
               when Attributes.Malformed_Attributes =>
                  Attributes_Query_Invalid := True;
                  Operation := Get_Object_Attributes;
            end;
         elsif Method = "GET" and then not Has_Upload_ID_Query then
            begin
               Object_Read_Request := Object_Reads.Parse_Query
                 (Query_Text, Object_Reads.Get_Object);
               Operation := Get_Object;
            exception
               when Object_Reads.Malformed_Object_Read_Request =>
                  Object_Read_Query_Invalid := True;
                  Operation := Get_Object;
            end;
         elsif Method = "DELETE" and then not Has_Upload_ID_Query then
            begin
               Delete_Request :=
                 Deletions.Parse_Delete_Object_Query (Query_Text);
               Operation := Delete_Object;
            exception
               when Deletions.Malformed_Delete_Object_Request =>
                  Delete_Object_Query_Invalid := True;
                  Operation := Delete_Object;
            end;
         elsif Method in "POST" | "PUT" | "DELETE" | "GET" then
            begin
               declare
                  Query : constant Multipart.Multipart_Query :=
                    Multipart.Parse_Query (Query_Text);
                  X_ID : constant String :=
                    US.To_String (Query.Operation_ID);
               begin
                  Operation :=
                    (if Query.Kind = Multipart.Create_Upload_Query
                       and then Method = "POST"
                       and then
                         (X_ID'Length = 0
                          or else X_ID = "CreateMultipartUpload")
                     then Create_Multipart
                     elsif Query.Kind = Multipart.Upload_Part_Query
                       and then Method = "PUT"
                       and then
                         (X_ID'Length = 0
                          or else X_ID = "UploadPart"
                          or else X_ID = "UploadPartCopy")
                     then
                       (if Has_Copy_Source or else X_ID = "UploadPartCopy"
                        then Copy_Multipart_Part
                        else Put_Multipart_Part)
                     elsif Query.Kind = Multipart.Existing_Upload_Query
                       and then Method = "POST"
                       and then
                         (X_ID'Length = 0
                          or else X_ID = "CompleteMultipartUpload")
                     then Complete_Multipart
                     elsif Query.Kind = Multipart.Existing_Upload_Query
                       and then Method = "DELETE"
                       and then
                         (X_ID'Length = 0
                          or else X_ID = "AbortMultipartUpload")
                     then Abort_Multipart
                     elsif Query.Kind = Multipart.List_Parts_Query
                       and then Method = "GET"
                       and then
                         (X_ID'Length = 0 or else X_ID = "ListParts")
                     then List_Multipart_Parts
                     elsif Query.Kind = Multipart.Existing_Upload_Query
                       and then Method = "GET" and then X_ID'Length = 0
                     then List_Multipart_Parts
                     else Unsupported);
               end;
            exception
               when Multipart.Malformed_Multipart =>
                  Multipart_Query_Invalid := True;
                  Operation :=
                    (if Method = "PUT" then Put_Multipart_Part
                     elsif Method = "POST" then Complete_Multipart
                     elsif Method = "GET" then List_Multipart_Parts
                     else Abort_Multipart);
            end;
         end if;
      end if;
      if Operation = Unsupported then
         Send_Error
           (X, 501, "NotImplemented",
            "The requested S3 operation is not implemented", Target_Text);
         return;
      end if;

      Apps.Configure_Route
         (X, "s3", Target_Text,
         (if Operation in Create_Bucket | Put_Bucket_Tagging |
         Put_Public_Access_Block |
         Put_Bucket_Versioning | Put_Object |
         Put_Object_Tagging | Delete_Objects | Put_Multipart_Part |
         Complete_Multipart
          then Apps.Stream_Body else Apps.Reject_Body),
         Apps.Required_Authentication, 0, 0, 0, Apps.No_Upgrade);
      Apps.Seal_Route (X);

      Auth := Authentication.Verify_Request (X, Credentials, Rules, Clock);
      if Auth.Status /= Authentication.Authenticated then
         Send_Authentication_Error (X, Auth, Target_Text);
         return;
      end if;
      Apps.Set_Principal (X, US.To_String (Auth.Principal));

      if Operation = Put_Multipart_Part and then Has_Encryption_Header then
         declare
            Algorithm_Count : constant Natural :=
              Apps.Request_Header_Count
                (X, "x-amz-server-side-encryption-customer-algorithm");
            Key_Count : constant Natural :=
              Apps.Request_Header_Count
                (X, "x-amz-server-side-encryption-customer-key");
            MD5_Count : constant Natural :=
              Apps.Request_Header_Count
                (X, "x-amz-server-side-encryption-customer-key-md5");
         begin
            if Algorithm_Count /= 1 or else Key_Count /= 1
              or else MD5_Count /= 1
            then
               Send_Error
                 (X, 400, "InvalidRequest",
                  "The SSE-C request group is invalid", Target_Text);
               return;
            elsif Apps.Request_Header
              (X, "x-amz-server-side-encryption-customer-algorithm") /=
                "AES256"
            then
               Send_Error
                 (X, 400, "InvalidArgument",
                  "The SSE-C algorithm is invalid", Target_Text);
               return;
            elsif Apps.Request_Scheme (X) /= Flyology.HTTP.Secure_HTTPS then
               Send_Error
                 (X, 400, "InvalidRequest",
                  "SSE-C requests require HTTPS", Target_Text);
               return;
            end if;
            if not Checksums.Valid_SSE_C_Key_MD5
              (Apps.Request_Header
                 (X, "x-amz-server-side-encryption-customer-key"),
               Apps.Request_Header
                 (X, "x-amz-server-side-encryption-customer-key-md5"))
            then
               Send_Error
                 (X, 400, "InvalidDigest",
                  "The SSE-C key or digest is invalid", Target_Text);
               return;
            end if;
         end;
         Send_Error
           (X, 501, "NotImplemented",
            "Server-side encryption is not implemented", Target_Text);
         return;
      elsif Has_Encryption_Header
        and then Operation not in Copy_Object | Put_Object | Head_Object |
          Get_Object | Get_Object_Attributes | List_Multipart_Parts |
          Create_Multipart | Complete_Multipart
      then
         Send_Error
           (X, 501, "NotImplemented",
            "Server-side encryption is not implemented", Target_Text);
         return;
      end if;

      if Multipart_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The multipart request query is invalid", Target_Text);
         return;
      elsif Bucket_Versioning_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The bucket versioning request query is invalid", Target_Text);
         return;
      elsif Bucket_Tagging_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The bucket tagging request query is invalid", Target_Text);
         return;
      elsif Public_Access_Block_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The PublicAccessBlock request query is invalid", Target_Text);
         return;
      elsif Delete_Object_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The DeleteObject request query is invalid", Target_Text);
         return;
      elsif Object_Read_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The object-read request query is invalid", Target_Text);
         return;
      elsif Tagging_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The object tagging request query is invalid", Target_Text);
         return;
      elsif Attributes_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The GetObjectAttributes request query is invalid", Target_Text);
         return;
      end if;

      if Operation not in Create_Bucket | Put_Bucket_Tagging |
        Put_Public_Access_Block |
        Put_Bucket_Versioning | Put_Object |
        Put_Object_Tagging | Delete_Objects | Put_Multipart_Part |
        Complete_Multipart
      then
         if not Apps.Body_Complete (X) then
            Send_Error
              (X, 400, "InvalidRequest",
               "This operation does not accept a request body", Target_Text);
            return;
         end if;
      else
         Length := Body_Length (Length_OK);
         if not Length_OK then
            Send_Error
              (X, 400, "InvalidRequest",
               "The Content-Length header is invalid", Target_Text);
            return;
         end if;
         if Operation = Put_Object
           and then Apps.Request_Header_Count (X, "content-type") > 1
         then
            Send_Error
              (X, 400, "InvalidRequest",
               "The Content-Type header is duplicated", Target_Text);
            return;
         end if;
         Apps.Apply_Body_Policy (X, Accepted);
         if not Accepted then
            return;
         end if;
      end if;

      declare
         Bucket : constant String :=
           Requests.Bucket_Name (Target_Text, Parsed);
         Key    : constant String := Requests.Object_Key (Target_Text, Parsed);
      begin
         case Operation is
            when List_Buckets =>
               begin
                  declare
                     Request : constant Buckets.List_Buckets_Request :=
                       Buckets.Parse_List_Buckets_Query (Query_Text);
                     Configured_Region : constant String :=
                       US.To_String (Rules.Expected_Region);
                     Requested_Region : constant String :=
                       US.To_String (Request.Bucket_Region);
                     Effective_Region : constant String :=
                       (if Configured_Region'Length > 0
                        then Configured_Region else Requested_Region);
                     Region_Mismatch : constant Boolean :=
                       Configured_Region'Length > 0
                       and then Requested_Region'Length > 0
                       and then Requested_Region /= Configured_Region;
                     Has_Listing_Parameter : constant Boolean :=
                       Request.Has_Max_Buckets
                       or else Request.Has_Continuation_Token
                       or else Request.Has_Prefix
                       or else Requested_Region'Length > 0;
                     Options : Backends.List_Buckets_Options :=
                       (Prefix  => Request.Prefix,
                        After   => US.Null_Unbounded_String,
                        Maximum => Backends.Bucket_List_Limit
                          (Request.Max_Buckets));
                     Token : Buckets.Continuation_Result;
                     Page  : Backends.Bucket_Page;
                  begin
                     if Configured_Region'Length >
                       Buckets.Maximum_Bucket_Region_Length
                       or else
                         (Configured_Region'Length > 0
                          and then not Encoding.Valid_Scope_Segment
                            (Configured_Region))
                     then
                        Send_Error
                          (X, 500, "InternalError",
                           "The configured S3 region is invalid",
                           Target_Text);
                        return;
                     end if;
                     if Request.Has_Continuation_Token
                       and then US.Length (Request.Continuation_Token) > 0
                     then
                        Token := Buckets.Decode_Continuation
                          (US.To_String (Request.Continuation_Token),
                           US.To_String (Request.Prefix), Requested_Region);
                        if not Token.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The continuation token provided is incorrect",
                              Target_Text);
                           return;
                        end if;
                        Options.After := Token.After;
                     end if;
                     if Region_Mismatch then
                        Page := (others => <>);
                        Result := Success;
                     else
                        Store.List_Buckets
                          (Options, Apps.Cancellation (X), Apps.Deadline (X),
                           Page, Result);
                     end if;
                     if Result /= Success then
                        Send_Backend_Error (X, Result, True, Target_Text);
                        return;
                     end if;
                     declare
                        Response : Buckets.List_Buckets_Result :=
                          (Buckets            => <>,
                           Has_Owner          => True,
                           Owner              =>
                             (Display_Name => US.Null_Unbounded_String,
                              ID           => Auth.Principal),
                           Continuation_Token => US.Null_Unbounded_String,
                           Has_Continuation_Token => False,
                           Prefix             => Request.Prefix,
                           Has_Prefix         => Request.Has_Prefix);
                     begin
                        if Page.Is_Truncated then
                           Response.Has_Continuation_Token := True;
                           Response.Continuation_Token :=
                             US.To_Unbounded_String
                               (Buckets.Encode_Continuation
                                  (US.To_String (Request.Prefix),
                                   Requested_Region,
                                   US.To_String (Page.Next_After)));
                        end if;
                        for Bucket_Value of Page.Buckets loop
                           Response.Buckets.Append
                             (Buckets.Bucket_Entry'
                                (Name => Bucket_Value.Name,
                                 Creation_Date =>
                                   (if Bucket_Value.Created = 0
                                    then US.Null_Unbounded_String
                                    else US.To_Unbounded_String
                                      (Last_Modified
                                         (Bucket_Value.Created))),
                                 Bucket_Region =>
                                   (if Has_Listing_Parameter
                                    then US.To_Unbounded_String
                                      (Effective_Region)
                                    else US.Null_Unbounded_String),
                                 Bucket_ARN => US.Null_Unbounded_String));
                        end loop;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Buckets.Serialize_List_Buckets (Response));
                     end;
                  end;
               exception
                  when Buckets.Malformed_List_Buckets_Request =>
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ListBuckets request is invalid", Target_Text);
               end;

            when Create_Bucket =>
               declare
                  Source : Request_IO.Request_Source :=
                    (Checksum_Kind => S3.Core.CRC64NVME,
                     Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Maximum_Create_Bucket_Body,
                     Completed => False,
                     others    => <>);
                  Document : constant String := Read_Document (Source);
                  Configuration : constant
                    Buckets.Create_Bucket_Configuration :=
                      Buckets.Parse_Create_Configuration
                        (Document,
                         (Maximum_Document_Bytes =>
                            Natural (Maximum_Create_Bucket_Body),
                          Maximum_Depth      => 5,
                          Maximum_Elements   => 256,
                          Maximum_Text_Bytes =>
                            Natural (Maximum_Create_Bucket_Body)));
                  Configured : constant String :=
                    US.To_String (Rules.Expected_Region);
                  Effective_Region : constant String :=
                    (if Configured'Length = 0
                     then "us-east-1" else Configured);
                  Constraint : constant String := US.To_String
                    (Configuration.Location_Constraint);
                  Requested_Region : constant String :=
                    (if Constraint = "EU" then "eu-west-1"
                     elsif Constraint'Length = 0 then "us-east-1"
                     else Constraint);
                  ACL_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-acl");
                  ACL : constant String :=
                    (if ACL_Count = 1
                     then Apps.Request_Header (X, "x-amz-acl") else "");
                  Ownership_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-object-ownership");
                  Ownership : constant String :=
                    (if Ownership_Count = 1
                     then Apps.Request_Header
                       (X, "x-amz-object-ownership") else "");
                  Object_Lock_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-bucket-object-lock-enabled");
                  Object_Lock : constant String :=
                    (if Object_Lock_Count = 1
                     then Apps.Request_Header
                       (X, "x-amz-bucket-object-lock-enabled") else "");
                  Namespace_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-bucket-namespace");
                  Namespace : constant String :=
                    (if Namespace_Count = 1
                     then Apps.Request_Header
                       (X, "x-amz-bucket-namespace") else "");
                  Duplicate_Grant : constant Boolean :=
                    Apps.Request_Header_Count
                      (X, "x-amz-grant-full-control") > 1
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-read") > 1
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-read-acp") > 1
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-write") > 1
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-write-acp") > 1;
                  Has_Grant : constant Boolean :=
                    Apps.Request_Header_Count
                      (X, "x-amz-grant-full-control") > 0
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-read") > 0
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-read-acp") > 0
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-write") > 0
                    or else Apps.Request_Header_Count
                      (X, "x-amz-grant-write-acp") > 0;
                  Empty_Grant : constant Boolean :=
                    (Apps.Request_Header_Count
                       (X, "x-amz-grant-full-control") = 1
                     and then Apps.Request_Header
                       (X, "x-amz-grant-full-control")'Length = 0)
                    or else
                      (Apps.Request_Header_Count (X, "x-amz-grant-read") = 1
                       and then Apps.Request_Header
                         (X, "x-amz-grant-read")'Length = 0)
                    or else
                      (Apps.Request_Header_Count
                         (X, "x-amz-grant-read-acp") = 1
                       and then Apps.Request_Header
                         (X, "x-amz-grant-read-acp")'Length = 0)
                    or else
                      (Apps.Request_Header_Count (X, "x-amz-grant-write") = 1
                       and then Apps.Request_Header
                         (X, "x-amz-grant-write")'Length = 0)
                    or else
                      (Apps.Request_Header_Count
                         (X, "x-amz-grant-write-acp") = 1
                       and then Apps.Request_Header
                         (X, "x-amz-grant-write-acp")'Length = 0);
                  Directory_Configuration : constant Boolean :=
                    US.Length (Configuration.Location_Type) > 0
                    or else US.Length (Configuration.Location_Name) > 0
                    or else US.Length (Configuration.Data_Redundancy) > 0
                    or else US.Length (Configuration.Bucket_Type) > 0;
               begin
                  if ACL_Count > 1 or else Ownership_Count > 1
                    or else Object_Lock_Count > 1
                    or else Namespace_Count > 1 or else Duplicate_Grant
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A CreateBucket header is duplicated", Target_Text);
                     return;
                  elsif (ACL_Count = 1 and then ACL'Length = 0)
                    or else
                      (Ownership_Count = 1 and then Ownership'Length = 0)
                    or else
                      (Object_Lock_Count = 1 and then Object_Lock'Length = 0)
                    or else
                      (Namespace_Count = 1 and then Namespace'Length = 0)
                    or else Empty_Grant
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A CreateBucket control is empty", Target_Text);
                     return;
                  elsif ACL'Length > 0
                    and then ACL /= "private"
                    and then ACL /= "public-read"
                    and then ACL /= "public-read-write"
                    and then ACL /= "authenticated-read"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The canned ACL is invalid", Target_Text);
                     return;
                  elsif Ownership'Length > 0
                    and then Ownership /= "BucketOwnerPreferred"
                    and then Ownership /= "ObjectWriter"
                    and then Ownership /= "BucketOwnerEnforced"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The object ownership value is invalid", Target_Text);
                     return;
                  elsif Object_Lock'Length > 0
                    and then Object_Lock /= "true"
                    and then Object_Lock /= "false"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The Object Lock value is invalid", Target_Text);
                     return;
                  elsif Namespace'Length > 0
                    and then Namespace /= "account-regional"
                    and then Namespace /= "global"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The bucket namespace is invalid", Target_Text);
                     return;
                  elsif Directory_Configuration then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Directory buckets are not implemented", Target_Text);
                     return;
                  elsif not Configuration.Tags.Is_Empty then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Bucket tags are not implemented", Target_Text);
                     return;
                  elsif Has_Grant or else ACL not in "" | "private"
                    or else Object_Lock_Count > 0
                    or else Ownership not in "" | "BucketOwnerEnforced"
                    or else Namespace_Count > 0
                  then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "The requested bucket controls are not implemented",
                        Target_Text);
                     return;
                  elsif Effective_Region /= "us-east-1"
                    and then not
                      Buckets.Valid_Location_Constraint (Effective_Region)
                  then
                     Send_Error
                       (X, 500, "InternalError",
                        "The configured S3 region is invalid", Target_Text);
                     return;
                  elsif Requested_Region /= Effective_Region then
                     Send_Error
                       (X, 400, "IllegalLocationConstraintException",
                        "The location constraint is incompatible with this " &
                        "endpoint", Target_Text);
                     return;
                  end if;
                  Store.Create_Bucket
                    (Bucket, Apps.Cancellation (X), Apps.Deadline (X), Result);
                  if Result = Success then
                     Apps.Set_Header (X, "Location", "/" & Bucket);
                     Apps.Respond (X, 200, "", "");
                  else
                     Send_Backend_Error (X, Result, True, Target_Text);
                  end if;

               end;

            when Head_Bucket =>
               declare
                  Configured : constant String :=
                    US.To_String (Rules.Expected_Region);
                  Region : constant String :=
                    (if Configured'Length = 0
                     then "us-east-1" else Configured);
                  Owner_Accepted : Boolean;
               begin
                  if Region /= "us-east-1"
                    and then not Buckets.Valid_Location_Constraint (Region)
                  then
                     Send_Error
                       (X, 500, "InternalError",
                        "The configured S3 region is invalid", Target_Text);
                  else
                     Apps.Set_Header (X, "x-amz-bucket-region", Region);
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        Store.Head_Bucket
                          (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                           Result);
                        if Result = Success then
                           Apps.Respond (X, 200, "", "");
                        else
                           Send_Backend_Error
                             (X, Result, True, Target_Text);
                        end if;
                     end if;
                  end if;
               end;

            when Get_Bucket_Location =>
               declare
                  Owner_Accepted : Boolean;
               begin
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_Accepted);
                  if Owner_Accepted then
                     Store.Head_Bucket
                       (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                        Result);
                     if Result = Success then
                        declare
                           Configured : constant String :=
                             US.To_String (Rules.Expected_Region);
                           Region : constant String :=
                             (if Configured'Length = 0
                              then "us-east-1" else Configured);
                        begin
                           if Region /= "us-east-1"
                             and then not
                               Buckets.Valid_Location_Constraint (Region)
                           then
                              Send_Error
                                (X, 500, "InternalError",
                                 "The configured S3 region is invalid",
                                 Target_Text);
                           else
                              Apps.Respond
                                (X, 200, "application/xml",
                                 Buckets.Serialize_Location_Constraint
                                   (Region));
                           end if;
                        end;
                     else
                        Send_Backend_Error (X, Result, True, Target_Text);
                     end if;
                  end if;
               end;

            when Put_Bucket_Tagging =>
               declare
                  MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  SDK_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-sdk-checksum-algorithm");
                  Trailer_Declaration_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-trailer");
                  CRC32_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-crc32");
                  CRC32C_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-crc32c");
                  CRC64_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-crc64nvme");
                  SHA1_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-sha1");
                  SHA256_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-sha256");
                  SHA512_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-sha512");
                  Checksum_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-md5");
                  XXHASH64_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-xxhash64");
                  XXHASH3_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-xxhash3");
                  XXHASH128_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-xxhash128");
                  Checksum_Count : constant Natural :=
                    CRC32_Count + CRC32C_Count + CRC64_Count + SHA1_Count +
                    SHA256_Count + SHA512_Count + Checksum_MD5_Count +
                    XXHASH64_Count + XXHASH3_Count + XXHASH128_Count;
                  Owner_Accepted : Boolean;
               begin
                  if MD5_Count > 1 or else Payer_Count > 1
                    or else SDK_Count > 1
                    or else Trailer_Declaration_Count > 1
                    or else CRC32_Count > 1 or else CRC32C_Count > 1
                    or else CRC64_Count > 1
                    or else SHA1_Count > 1 or else SHA256_Count > 1
                    or else SHA512_Count > 1
                    or else Checksum_MD5_Count > 1
                    or else XXHASH64_Count > 1
                    or else XXHASH3_Count > 1
                    or else XXHASH128_Count > 1
                    or else Apps.Request_Header_Count (X, "content-type") > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A PutBucketTagging header is duplicated",
                        Target_Text);
                  elsif MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      (Apps.Request_Header (X, "content-md5"), 16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutBucketTagging requires a valid Content-MD5",
                        Target_Text);
                  elsif Payer_Count > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutBucketTagging does not define RequestPayer",
                        Target_Text);
                  elsif Checksum_Count > 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The PutBucketTagging checksum group is invalid",
                        Target_Text);
                  elsif Length.Kind = Backends.Known
                    and then Length.Bytes > Maximum_Bucket_Tagging_Body
                  then
                     Send_Error
                       (X, 400, "EntityTooLarge",
                        "Your proposed upload exceeds the maximum allowed " &
                        "size", Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        declare
                           Source : Request_IO.Request_Source :=
                             (Checksum_Kind => S3.Core.CRC64NVME,
                              Length_Value  => Length,
                              Expected_Hash => Auth.Payload_Hash,
                              Check_Hash    =>
                                US.To_String (Auth.Payload_Hash) /=
                                  S3.SigV4.Unsigned_Payload,
                              Hash      => GNAT.SHA256.Initial_Context,
                              Observed  => 0,
                              Maximum   => Maximum_Bucket_Tagging_Body,
                              Completed => False,
                              others    => <>);
                           Document : constant String :=
                             Read_Document (Source);

                           type Checksum_Verification is
                             (Checksum_OK, Invalid_Checksum_Group,
                              Invalid_Checksum_Value, Checksum_Mismatch);

                           function Header_Name
                             (Algorithm : Checksum_Policy.Algorithm)
                              return String is
                             (case Algorithm is
                                 when S3.Core.CRC32 =>
                                   "x-amz-checksum-crc32",
                                 when S3.Core.CRC32C =>
                                   "x-amz-checksum-crc32c",
                                 when S3.Core.CRC64NVME =>
                                   "x-amz-checksum-crc64nvme",
                                 when S3.Core.SHA1 =>
                                   "x-amz-checksum-sha1",
                                 when S3.Core.SHA256 =>
                                   "x-amz-checksum-sha256",
                                 when S3.Core.SHA512 =>
                                   "x-amz-checksum-sha512",
                                 when S3.Core.MD5 =>
                                   "x-amz-checksum-md5",
                                 when S3.Core.XXHASH64 =>
                                   "x-amz-checksum-xxhash64",
                                 when S3.Core.XXHASH3 =>
                                   "x-amz-checksum-xxhash3",
                                 when S3.Core.XXHASH128 =>
                                   "x-amz-checksum-xxhash128");

                           function Count_For
                             (Algorithm : Checksum_Policy.Algorithm)
                              return Natural is
                             (case Algorithm is
                                 when S3.Core.CRC32 => CRC32_Count,
                                 when S3.Core.CRC32C => CRC32C_Count,
                                 when S3.Core.CRC64NVME => CRC64_Count,
                                 when S3.Core.SHA1 => SHA1_Count,
                                 when S3.Core.SHA256 => SHA256_Count,
                                 when S3.Core.SHA512 => SHA512_Count,
                                 when S3.Core.MD5 => Checksum_MD5_Count,
                                 when S3.Core.XXHASH64 => XXHASH64_Count,
                                 when S3.Core.XXHASH3 => XXHASH3_Count,
                                 when S3.Core.XXHASH128 => XXHASH128_Count);

                           function Trailer_Count_For
                             (Algorithm : Checksum_Policy.Algorithm)
                              return Natural is
                             (Apps.Request_Trailer_Count
                                (X, Header_Name (Algorithm)));

                           function Selected_Algorithm return
                             Checksum_Policy.Algorithm_Parse_Result
                           is
                           begin
                              if SDK_Count = 1 then
                                 return Checksum_Policy.Parse_Algorithm
                                   (Apps.Request_Header
                                      (X,
                                       "x-amz-sdk-checksum-algorithm"));
                              elsif CRC32_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.CRC32);
                              elsif CRC32C_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.CRC32C);
                              elsif CRC64_Count = 1 then
                                 return
                                   (Valid => True,
                                    Value => S3.Core.CRC64NVME);
                              elsif SHA1_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.SHA1);
                              elsif SHA256_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.SHA256);
                              elsif SHA512_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.SHA512);
                              elsif Checksum_MD5_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.MD5);
                              elsif XXHASH64_Count = 1 then
                                 return
                                   (Valid => True,
                                    Value => S3.Core.XXHASH64);
                              elsif XXHASH3_Count = 1 then
                                 return
                                   (Valid => True, Value => S3.Core.XXHASH3);
                              elsif XXHASH128_Count = 1 then
                                 return
                                   (Valid => True,
                                    Value => S3.Core.XXHASH128);
                              else
                                 return (Valid => False);
                              end if;
                           end Selected_Algorithm;

                           function Verify_Checksum
                              return Checksum_Verification
                           is
                              Selected : constant
                                Checksum_Policy.Algorithm_Parse_Result :=
                                  Selected_Algorithm;
                              Has_Trailer : constant Boolean :=
                                Trailer_Declaration_Count = 1;
                              Actual_Trailer_Count : Natural := 0;
                           begin
                              if SDK_Count > 1
                                or else Trailer_Declaration_Count > 1
                                or else Checksum_Count > 1
                                or else Apps.Request_Trailer_Count (X) > 1
                                or else
                                  (Has_Trailer
                                   and then
                                     (SDK_Count /= 1
                                      or else not Selected.Valid
                                      or else Checksum_Count /= 0
                                      or else
                                        Ada.Characters.Handling.To_Lower
                                          (Apps.Request_Header
                                             (X, "x-amz-trailer")) /=
                                        Header_Name (Selected.Value)))
                                or else
                                  (not Has_Trailer
                                   and then Apps.Request_Trailer_Count (X) > 0)
                                or else
                                  (not Has_Trailer
                                   and then SDK_Count = 1
                                   and then
                                     (not Selected.Valid
                                      or else Checksum_Count /= 1
                                      or else
                                        Count_For (Selected.Value) /= 1))
                              then
                                 return Invalid_Checksum_Group;
                              elsif Has_Trailer then
                                 Actual_Trailer_Count :=
                                   Trailer_Count_For (Selected.Value);
                                 if Actual_Trailer_Count /= 1 then
                                    return Invalid_Checksum_Group;
                                 end if;
                              elsif Checksum_Count = 0 then
                                 return Checksum_OK;
                              elsif not Selected.Valid then
                                 return Invalid_Checksum_Group;
                              end if;
                              declare
                                 Supplied : constant Checksums.Decode_Result :=
                                   Checksums.Decode_Base64
                                     ((if Has_Trailer
                                       then Apps.Request_Trailer
                                         (X, Header_Name (Selected.Value))
                                       else Apps.Request_Header
                                         (X, Header_Name (Selected.Value))),
                                      Selected.Value);
                              begin
                                 if not Supplied.Valid then
                                    return Invalid_Checksum_Value;
                                 end if;
                                 declare
                                    Computed : constant
                                      Checksums.Digest_Value :=
                                        Checksums.Compute
                                          (Selected.Value,
                                           Flyology.Bytes.To_Array
                                             (Flyology.Bytes.From_Byte_String
                                                (Document)));
                                 begin
                                    if Checksums.Equivalent
                                      (Supplied.Value, Computed)
                                    then
                                       return Checksum_OK;
                                    else
                                       return Checksum_Mismatch;
                                    end if;
                                 end;
                              end;
                           end Verify_Checksum;

                           Checksum_Status : constant
                             Checksum_Verification := Verify_Checksum;
                        begin
                           if Content_MD5 (Document) /=
                             Apps.Request_Header (X, "content-md5")
                           then
                              Send_Error
                                (X, 400, "BadDigest",
                                 "The Content-MD5 does not match the body",
                                 Target_Text);
                           elsif Checksum_Status in
                             Invalid_Checksum_Group | Invalid_Checksum_Value
                           then
                              Send_Error
                                (X, 400, "InvalidRequest",
                                 "The PutBucketTagging checksum group is " &
                                 "invalid", Target_Text);
                           elsif Checksum_Status = Checksum_Mismatch then
                              Send_Error
                                (X, 400, "BadDigest",
                                 "The optional checksum does not match the " &
                                 "request body", Target_Text);
                           else
                              declare
                                 Value : constant Tags.Tag_Set :=
                                   Tagging.Parse_Bucket
                                     (Document,
                                      (Maximum_Document_Bytes =>
                                         Natural
                                           (Maximum_Bucket_Tagging_Body),
                                       Maximum_Depth      => 4,
                                       Maximum_Elements   => 152,
                                       Maximum_Text_Bytes =>
                                         Natural
                                           (Maximum_Bucket_Tagging_Body)));
                              begin
                                 Store.Put_Bucket_Tags
                                   (Bucket, Value, Apps.Cancellation (X),
                                    Apps.Deadline (X), Result);
                                 if Result = Success then
                                    Apps.Respond (X, 200, "", "");
                                 else
                                    Send_Backend_Error
                                      (X, Result, True, Target_Text);
                                 end if;
                              end;
                           end if;
                        exception
                           when Tagging.Malformed_Tagging =>
                              Send_Error
                                (X, 400, "MalformedXML",
                                 "The XML provided was not well-formed or " &
                                 "did not validate against the published " &
                                 "schema", Target_Text);
                           when Tagging.Invalid_Tag =>
                              Send_Error
                                (X, 400, "InvalidTag",
                                 "The tag set contains an invalid tag",
                                 Target_Text);
                        end;
                     end if;
                  end if;
               end;

            when Get_Bucket_Tagging =>
               declare
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Owner_Accepted : Boolean;
                  Value : Tags.Tag_Set;
               begin
                  if Payer_Count > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "GetBucketTagging does not define RequestPayer",
                        Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        Store.Get_Bucket_Tags
                          (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                           Value, Result);
                        if Result = Success then
                           Apps.Respond
                             (X, 200, "application/xml",
                              Tagging.Serialize_Bucket (Value));
                        else
                           Send_Backend_Error
                             (X, Result, True, Target_Text);
                        end if;
                     end if;
                  end if;
               end;

            when Delete_Bucket_Tagging =>
               declare
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Owner_Accepted : Boolean;
               begin
                  if Payer_Count > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "DeleteBucketTagging does not define RequestPayer",
                        Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        Store.Delete_Bucket_Tags
                          (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                           Result);
                        if Result = Success then
                           Apps.Respond (X, 204, "", "");
                        else
                           Send_Backend_Error
                             (X, Result, True, Target_Text);
                        end if;
                     end if;
                  end if;
               end;

            when Put_Public_Access_Block =>
               declare
                  MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  SDK_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-sdk-checksum-algorithm");
                  Trailer_Declaration_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-trailer");
                  Checksum_Count : constant Natural :=
                    Checksum_Value_Header_Count;
                  Selected : constant
                    Checksum_Policy.Algorithm_Parse_Result :=
                      (if SDK_Count = 1 then
                         Checksum_Policy.Parse_Algorithm
                           (Apps.Request_Header
                              (X, "x-amz-sdk-checksum-algorithm"))
                       else (Valid => False));
                  Owner_Accepted : Boolean;

                  procedure Process
                    (Algorithm    : Checksum_Policy.Algorithm;
                     Check_Body   : Boolean;
                     From_Trailer : Boolean;
                     Expected     : String)
                  is
                     Source : Request_IO.Request_Source :=
                       (Checksum_Kind => Algorithm,
                        Length_Value  => Length,
                        Expected_Hash => Auth.Payload_Hash,
                        Check_Hash    =>
                          US.To_String (Auth.Payload_Hash) /=
                            S3.SigV4.Unsigned_Payload,
                        Hash      => GNAT.SHA256.Initial_Context,
                        Check_Content_MD5 => MD5_Count = 1,
                        Expected_Content_MD5 =>
                          (if MD5_Count = 1 then
                             US.To_Unbounded_String
                               (Apps.Request_Header (X, "content-md5"))
                           else US.Null_Unbounded_String),
                        Content_MD5_Hash => GNAT.MD5.Initial_Context,
                        Check_Body_Checksum => Check_Body,
                        Checksum_From_Trailer => From_Trailer,
                        Reject_Unexpected_Trailers => True,
                        Expected_Body_Checksum =>
                          US.To_Unbounded_String (Expected),
                        Observed  => 0,
                        Maximum   => Maximum_Public_Access_Block_Body,
                        Completed => False,
                        others    => <>);
                     Document : constant String := Read_Document (Source);
                     Wire_Configuration : Bucket_Controls.
                       Public_Access_Block_Configuration;
                  begin
                     Wire_Configuration := Bucket_Controls.
                       Parse_Public_Access_Block (Document);
                     Store.Put_Bucket_Public_Access_Block
                       (Bucket,
                        Storage_Public_Access_Block (Wire_Configuration),
                        Apps.Cancellation (X), Apps.Deadline (X), Result);
                     if Result = Success then
                        Apps.Respond (X, 200, "", "");
                     else
                        Send_Backend_Error (X, Result, True, Target_Text);
                     end if;
                  exception
                     when Bucket_Controls.Malformed_Configuration =>
                        Send_Error
                          (X, 400, "MalformedXML",
                           "The XML provided was not well-formed or did not " &
                           "validate against the published schema",
                           Target_Text);
                  end Process;
               begin
                  if MD5_Count > 1
                    or else Payer_Count > 1
                    or else SDK_Count > 1
                    or else Trailer_Declaration_Count > 1
                    or else Checksum_Count > 1
                    or else Apps.Request_Header_Count (X, "content-type") > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A PutPublicAccessBlock header is duplicated",
                        Target_Text);
                  elsif MD5_Count = 1
                    and then not S3.Wire_Core.Valid_Base64
                      (Apps.Request_Header (X, "content-md5"), 16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The Content-MD5 header is invalid", Target_Text);
                  elsif Payer_Count > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutPublicAccessBlock does not define RequestPayer",
                        Target_Text);
                  elsif
                    (SDK_Count = 0
                     and then
                       (Trailer_Declaration_Count /= 0
                        or else Checksum_Count /= 0))
                    or else (SDK_Count = 1 and then not Selected.Valid)
                    or else
                      (SDK_Count = 1
                       and then Trailer_Declaration_Count = 1
                       and then
                         (Checksum_Count /= 0
                          or else
                            Ada.Characters.Handling.To_Lower
                              (Apps.Request_Header (X, "x-amz-trailer")) /=
                            Checksum_Header_Name
                              (Storage_Algorithm (Selected.Value))))
                    or else
                      (SDK_Count = 1
                       and then Trailer_Declaration_Count = 0
                       and then
                         (Checksum_Count /= 1
                          or else Apps.Request_Header_Count
                            (X, Checksum_Header_Name
                               (Storage_Algorithm (Selected.Value))) /= 1))
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The PutPublicAccessBlock checksum group is invalid",
                        Target_Text);
                  elsif Length.Kind = Backends.Known
                    and then Length.Bytes > Maximum_Public_Access_Block_Body
                  then
                     Send_Error
                       (X, 400, "EntityTooLarge",
                        "Your proposed upload exceeds the maximum allowed " &
                        "size", Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        if SDK_Count = 0 then
                           Process
                             (S3.Core.CRC64NVME, False, False, "");
                        elsif Trailer_Declaration_Count = 1 then
                           Process (Selected.Value, True, True, "");
                        else
                           Process
                             (Selected.Value, True, False,
                              Apps.Request_Header
                                (X, Checksum_Header_Name
                                   (Storage_Algorithm (Selected.Value))));
                        end if;
                     end if;
                  end if;
               end;

            when Get_Public_Access_Block =>
               declare
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Owner_Accepted : Boolean;
                  Configuration :
                    Bucket_Public_Access_Block_Configuration;
                  Configured : Boolean;
               begin
                  if Payer_Count > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "GetPublicAccessBlock does not define RequestPayer",
                        Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        Store.Get_Bucket_Public_Access_Block
                          (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                           Configuration, Configured, Result);
                        if Result /= Success then
                           Send_Backend_Error
                             (X, Result, True, Target_Text);
                        elsif not Configured then
                           Send_Error
                             (X, 404,
                              "NoSuchPublicAccessBlockConfiguration",
                              "The public access block configuration was " &
                              "not found", Target_Text);
                        else
                           Apps.Respond
                             (X, 200, "application/xml",
                              Bucket_Controls.Serialize_Public_Access_Block
                                (Wire_Public_Access_Block (Configuration)));
                        end if;
                     end if;
                  end if;
               end;

            when Delete_Public_Access_Block =>
               declare
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Owner_Accepted : Boolean;
               begin
                  if Payer_Count > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "DeletePublicAccessBlock does not define " &
                        "RequestPayer", Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        Store.Delete_Bucket_Public_Access_Block
                          (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                           Result);
                        if Result = Success then
                           Apps.Respond (X, 204, "", "");
                        else
                           Send_Backend_Error
                             (X, Result, True, Target_Text);
                        end if;
                     end if;
                  end if;
               end;

            when Put_Bucket_Versioning =>
               declare
                  MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
                  MFA_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-mfa");
                  Owner_Accepted : Boolean := False;
               begin
                  if MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      ((if MD5_Count = 1
                        then Apps.Request_Header (X, "content-md5") else ""),
                       16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutBucketVersioning requires one valid " &
                        "Content-MD5 header",
                        Target_Text);
                  elsif MFA_Count > 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A PutBucketVersioning control header is duplicated",
                        Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        declare
                           Source : Request_IO.Request_Source :=
                             (Checksum_Kind => S3.Core.CRC64NVME,
                              Length_Value  => Length,
                              Expected_Hash => Auth.Payload_Hash,
                              Check_Hash    =>
                                US.To_String (Auth.Payload_Hash) /=
                                  S3.SigV4.Unsigned_Payload,
                              Hash      => GNAT.SHA256.Initial_Context,
                              Observed  => 0,
                              Maximum   => Maximum_Versioning_Body,
                              Completed => False,
                              others    => <>);
                           Document : constant String :=
                             Read_Document (Source);
                           Checksum_Status : constant
                             Document_Checksum_Status :=
                               Verify_Document_Checksum (Document);
                        begin
                           if Apps.Request_Header (X, "content-md5") /=
                             Content_MD5 (Document)
                           then
                              Send_Error
                                (X, 400, "BadDigest",
                                 "The Content-MD5 you specified did not " &
                                 "match", Target_Text);
                           elsif Checksum_Status in
                             Document_Checksum_Group_Invalid |
                             Document_Checksum_Value_Invalid
                           then
                              Send_Error
                                (X, 400, "InvalidRequest",
                                 "The PutBucketVersioning checksum group " &
                                 "is invalid", Target_Text);
                           elsif Checksum_Status =
                             Document_Checksum_Mismatch
                           then
                              Send_Error
                                (X, 400, "BadDigest",
                                 "The optional checksum does not match " &
                                 "the request body", Target_Text);
                           else
                              declare
                                 Configuration : constant
                                   Bucket_Versioning_Configuration :=
                                     Versioning.Parse (Document);
                                 MFA_Result : constant
                                   MFA.Authorization_Status :=
                                     (if MFA_Count = 0
                                      then MFA.Missing_Credential
                                      else Verify_MFA_Credential
                                        (US.To_String (Auth.Principal),
                                         Apps.Request_Header
                                           (X, "x-amz-mfa")));
                              begin
                                 if Configuration.MFA_Delete /=
                                     MFA_Delete_Unconfigured
                                   and then Configuration.Status =
                                     Versioning_Unconfigured
                                 then
                                    Send_Error
                                      (X, 400, "InvalidRequest",
                                       "MfaDelete requires an explicit " &
                                       "Status", Target_Text);
                                 elsif MFA_Count = 1
                                   and then MFA_Result /= MFA.Authorized
                                 then
                                    Send_MFA_Error (MFA_Result);
                                 else
                                    Store.Put_Bucket_Versioning
                                      (Bucket, Configuration,
                                       Apps.Cancellation (X),
                                       Apps.Deadline (X), Result,
                                       MFA_Validated =>
                                         MFA_Result = MFA.Authorized);
                                    if Result = Success then
                                       Apps.Respond (X, 200, "", "");
                                    else
                                       Send_Backend_Error
                                         (X, Result, True, Target_Text);
                                    end if;
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end if;
               exception
                  when Versioning.Malformed_Configuration =>
                     Send_Error
                       (X, 400, "MalformedXML",
                        "The XML provided was not well-formed or did not " &
                        "validate against the published schema", Target_Text);
               end;

            when Get_Bucket_Versioning =>
               declare
                  Owner_Accepted : Boolean;
                  Configuration : Bucket_Versioning_Configuration;
               begin
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_Accepted);
                  if Owner_Accepted then
                     Store.Get_Bucket_Versioning
                       (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                        Configuration, Result);
                     if Result = Success then
                        Apps.Respond
                          (X, 200, "application/xml",
                           Versioning.Serialize_Response (Configuration));
                     else
                        Send_Backend_Error
                          (X, Result, True, Target_Text);
                     end if;
                  end if;
               end;

            when Delete_Bucket =>
               declare
                  Owner_Accepted : Boolean;
               begin
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_Accepted);
                  if Owner_Accepted then
                     Store.Delete_Bucket
                       (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                        Result);
                     if Result = Success then
                        Apps.Respond (X, 204, "", "");
                     else
                        Send_Backend_Error (X, Result, True, Target_Text);
                     end if;
                  end if;
               end;

            when List_Objects =>
               begin
                  declare
                     Owner_Count : constant Natural :=
                       Apps.Request_Header_Count
                         (X, "x-amz-expected-bucket-owner");
                     Payer_Count : constant Natural :=
                       Apps.Request_Header_Count (X, "x-amz-request-payer");
                     Attributes_Count : constant Natural :=
                       Apps.Request_Header_Count
                         (X, "x-amz-optional-object-attributes");
                     Owner_Accepted : Boolean := False;
                     Request : constant Listings.List_Objects_Request :=
                       Listings.Parse_List_Objects_Query (Query_Text);
                     Options : constant Backends.List_Options :=
                       (Prefix    => Request.Prefix,
                        Delimiter => Request.Delimiter,
                        After     => Request.Marker,
                        Maximum   =>
                          Backends.List_Limit (Request.Max_Keys));
                     Page : Backends.List_Page;

                     function Encoded (Value : String) return String is
                       (if Request.URL_Encoding
                        then Encoding.URI_Encode
                          (Value, Encode_Slash => False)
                        else Value);
                  begin
                     if Owner_Count > 1 or else Payer_Count > 1
                       or else Attributes_Count > 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "A ListObjects header is duplicated", Target_Text);
                        return;
                     elsif Payer_Count = 1
                       and then Apps.Request_Header
                         (X, "x-amz-request-payer") /= "requester"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The request payer is invalid", Target_Text);
                        return;
                     elsif Attributes_Count = 1
                       and then Apps.Request_Header
                         (X, "x-amz-optional-object-attributes") /=
                           "RestoreStatus"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The optional object attributes are invalid",
                           Target_Text);
                        return;
                     end if;
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if not Owner_Accepted then
                        return;
                     end if;
                     Store.List_Objects
                       (Bucket, Options, Apps.Cancellation (X),
                        Apps.Deadline (X), Page, Result);
                     if Result /= Success then
                        Send_Backend_Error (X, Result, True, Target_Text);
                        return;
                     end if;
                     declare
                        Response : Listings.List_Objects_Result :=
                          (Name            =>
                             US.To_Unbounded_String (Bucket),
                           Prefix          => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Prefix))),
                           Has_Prefix      => True,
                           Delimiter       => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Delimiter))),
                           Has_Delimiter   => Request.Has_Delimiter,
                           Encoding_Type   =>
                             (if Request.URL_Encoding
                              then US.To_Unbounded_String ("url")
                              else US.Null_Unbounded_String),
                           Has_Encoding_Type => Request.URL_Encoding,
                           Marker          => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Marker))),
                           Has_Marker      => True,
                           Next_Marker     => US.Null_Unbounded_String,
                           Has_Next_Marker => False,
                           Max_Keys        => Natural (Request.Max_Keys),
                           Is_Truncated    => Page.Is_Truncated,
                           Contents        => <>,
                           Common_Prefixes => <>);
                     begin
                        if Page.Is_Truncated
                          and then US.Length (Request.Delimiter) > 0
                        then
                           Response.Next_Marker := US.To_Unbounded_String
                             (Encoded (US.To_String (Page.Next_After)));
                           Response.Has_Next_Marker := True;
                        end if;
                        for Object_Value of Page.Objects loop
                           Response.Contents.Append
                             (Listings.Object_Entry'
                              (Key           => US.To_Unbounded_String
                                 (Encoded (US.To_String (Object_Value.Key))),
                               Last_Modified => US.To_Unbounded_String
                                 (Last_Modified
                                    (Object_Value.Info.Modified)),
                               Entity_Tag    => US.To_Unbounded_String
                                 ('"' & US.To_String
                                   (Object_Value.Info.Entity_Tag) & '"'),
                               Size          => Object_Value.Info.Size,
                               Storage_Class =>
                                 US.To_Unbounded_String ("STANDARD"),
                               Has_Owner      => True,
                               Owner          =>
                                 (Display_Name => US.Null_Unbounded_String,
                                  ID           => Auth.Principal),
                               others        => <>));
                        end loop;
                        for Prefix_Value of Page.Common_Prefixes loop
                           Response.Common_Prefixes.Append
                             (US.To_Unbounded_String
                                (Encoded (US.To_String (Prefix_Value))));
                        end loop;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Listings.Serialize_List_Objects (Response));
                     end;
                  end;
               exception
                  when Listings.Malformed_List_Request =>
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ListObjects request is invalid", Target_Text);
               end;

            when List_Objects_V2 =>
               begin
                  declare
                     Owner_Count : constant Natural :=
                       Apps.Request_Header_Count
                         (X, "x-amz-expected-bucket-owner");
                     Payer_Count : constant Natural :=
                       Apps.Request_Header_Count (X, "x-amz-request-payer");
                     Attributes_Count : constant Natural :=
                       Apps.Request_Header_Count
                         (X, "x-amz-optional-object-attributes");
                     Owner_Accepted : Boolean := False;
                     Request : constant Listings.List_Objects_V2_Request :=
                       Listings.Parse_List_Objects_V2_Query (Query_Text);
                     Options : Backends.List_Options :=
                       (Prefix    => Request.Prefix,
                        Delimiter => Request.Delimiter,
                        After     => Request.Start_After,
                        Maximum   =>
                          Backends.List_Limit (Request.Max_Keys));
                     Token_Result : Listings.Continuation_Result;
                     Page : Backends.List_Page;

                     function Encoded (Value : String) return String is
                       (if Request.URL_Encoding
                        then Encoding.URI_Encode
                          (Value, Encode_Slash => False)
                        else Value);
                  begin
                     if Owner_Count > 1 or else Payer_Count > 1
                       or else Attributes_Count > 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "A ListObjectsV2 header is duplicated",
                           Target_Text);
                        return;
                     elsif Payer_Count = 1
                       and then Apps.Request_Header
                         (X, "x-amz-request-payer") /= "requester"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The request payer is invalid", Target_Text);
                        return;
                     elsif Attributes_Count = 1
                       and then Apps.Request_Header
                         (X, "x-amz-optional-object-attributes") /=
                           "RestoreStatus"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The optional object attributes are invalid",
                           Target_Text);
                        return;
                     end if;
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if not Owner_Accepted then
                        return;
                     end if;
                     if US.Length (Request.Continuation_Token) > 0 then
                        Token_Result := Listings.Decode_Continuation
                          (US.To_String (Request.Continuation_Token), Bucket,
                           US.To_String (Request.Prefix),
                           US.To_String (Request.Delimiter));
                        if not Token_Result.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The continuation token provided is incorrect",
                              Target_Text);
                           return;
                        end if;
                        Options.After := Token_Result.After;
                     end if;
                     Store.List_Objects
                       (Bucket, Options, Apps.Cancellation (X),
                        Apps.Deadline (X), Page, Result);
                     if Result /= Success then
                        Send_Backend_Error (X, Result, True, Target_Text);
                        return;
                     end if;
                     declare
                        Response : Listings.List_Objects_V2_Result :=
                          (Name               =>
                             US.To_Unbounded_String (Bucket),
                           Prefix             => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Prefix))),
                           Delimiter          => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Delimiter))),
                           Has_Delimiter      => Request.Has_Delimiter,
                           Encoding_Type      =>
                             (if Request.URL_Encoding
                              then US.To_Unbounded_String ("url")
                              else US.Null_Unbounded_String),
                           Has_Encoding_Type  => Request.URL_Encoding,
                           Continuation_Token => Request.Continuation_Token,
                           Has_Continuation_Token =>
                             Request.Has_Continuation_Token,
                           Next_Continuation_Token =>
                             US.Null_Unbounded_String,
                           Has_Next_Continuation_Token => False,
                           Start_After        => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Start_After))),
                           Has_Start_After    => Request.Has_Start_After,
                           Key_Count          =>
                             Natural (Page.Objects.Length) +
                             Natural (Page.Common_Prefixes.Length),
                           Max_Keys           => Natural (Request.Max_Keys),
                           Is_Truncated       => Page.Is_Truncated,
                           Contents           => <>,
                           Common_Prefixes    => <>);
                     begin
                        if Page.Is_Truncated then
                           Response.Next_Continuation_Token :=
                             US.To_Unbounded_String
                               (Listings.Encode_Continuation
                                  (Bucket, US.To_String (Request.Prefix),
                                   US.To_String (Request.Delimiter),
                                   US.To_String (Page.Next_After)));
                           Response.Has_Next_Continuation_Token := True;
                        end if;
                        for Object_Value of Page.Objects loop
                           Response.Contents.Append
                             (Listings.Object_Entry'
                              (Key           => US.To_Unbounded_String
                                 (Encoded (US.To_String (Object_Value.Key))),
                               Last_Modified => US.To_Unbounded_String
                                 (Last_Modified
                                    (Object_Value.Info.Modified)),
                               Entity_Tag    => US.To_Unbounded_String
                                 ('"' & US.To_String
                                   (Object_Value.Info.Entity_Tag) & '"'),
                               Size          => Object_Value.Info.Size,
                               Storage_Class =>
                                 US.To_Unbounded_String ("STANDARD"),
                               Has_Owner      => Request.Fetch_Owner,
                               Owner          =>
                                 (Display_Name => US.Null_Unbounded_String,
                                  ID =>
                                    (if Request.Fetch_Owner
                                     then Auth.Principal
                                     else US.Null_Unbounded_String)),
                               others        => <>));
                        end loop;
                        for Prefix_Value of Page.Common_Prefixes loop
                           Response.Common_Prefixes.Append
                             (US.To_Unbounded_String
                                (Encoded (US.To_String (Prefix_Value))));
                        end loop;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Listings.Serialize_List_Objects_V2 (Response));
                     end;
                  end;
               exception
                  when Listings.Malformed_List_Request =>
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ListObjectsV2 request is invalid", Target_Text);
               end;

            when List_Object_Versions =>
               begin
                  declare
                     Owner_Count : constant Natural :=
                       Apps.Request_Header_Count
                         (X, "x-amz-expected-bucket-owner");
                     Payer_Count : constant Natural :=
                       Apps.Request_Header_Count (X, "x-amz-request-payer");
                     Attributes_Count : constant Natural :=
                       Apps.Request_Header_Count
                         (X, "x-amz-optional-object-attributes");
                     Owner_Accepted : Boolean := False;
                     Request : constant
                       Versions.List_Object_Versions_Request :=
                         Versions.Parse_List_Object_Versions_Query
                           (Query_Text);
                     Options : constant Backends.List_Versions_Options :=
                       (Prefix                => Request.Prefix,
                        Delimiter             => Request.Delimiter,
                        Has_Key_Marker        => Request.Has_Key_Marker,
                        Key_Marker            => Request.Key_Marker,
                        Has_Version_ID_Marker =>
                          Request.Has_Version_ID_Marker,
                        Version_ID_Marker     => Request.Version_ID_Marker,
                        Maximum               =>
                          Backends.List_Limit (Request.Max_Keys));
                     Page : Backends.List_Versions_Page;

                     function Encoded (Value : String) return String is
                       (if Request.URL_Encoding
                        then Encoding.URI_Encode
                          (Value, Encode_Slash => False)
                        else Value);
                  begin
                     if Owner_Count > 1 or else Payer_Count > 1
                       or else Attributes_Count > 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "A ListObjectVersions header is duplicated",
                           Target_Text);
                        return;
                     elsif Payer_Count = 1
                       and then Apps.Request_Header
                         (X, "x-amz-request-payer") /= "requester"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The request payer is invalid", Target_Text);
                        return;
                     elsif Attributes_Count = 1
                       and then Apps.Request_Header
                         (X, "x-amz-optional-object-attributes") /=
                           "RestoreStatus"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The optional object attributes are invalid",
                           Target_Text);
                        return;
                     end if;
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if not Owner_Accepted then
                        return;
                     end if;
                     Store.List_Object_Versions
                       (Bucket, Options, Apps.Cancellation (X),
                        Apps.Deadline (X), Page, Result);
                     if Result /= Success then
                        Send_Backend_Error (X, Result, True, Target_Text);
                        return;
                     end if;
                     declare
                        Response : Versions.List_Object_Versions_Result :=
                          (Is_Truncated           => Page.Is_Truncated,
                           Has_Is_Truncated       => True,
                           Key_Marker             => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Key_Marker))),
                           Has_Key_Marker         => Request.Has_Key_Marker,
                           Version_ID_Marker      => Request.Version_ID_Marker,
                           Has_Version_ID_Marker  =>
                             Request.Has_Version_ID_Marker,
                           Next_Key_Marker        => US.Null_Unbounded_String,
                           Has_Next_Key_Marker    => Page.Is_Truncated,
                           Next_Version_ID_Marker => US.Null_Unbounded_String,
                           Has_Next_Version_ID_Marker => Page.Is_Truncated,
                           Versions               => <>,
                           Delete_Markers         => <>,
                           Name                   =>
                             US.To_Unbounded_String (Bucket),
                           Has_Name               => True,
                           Prefix                 => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Prefix))),
                           Has_Prefix             => Request.Has_Prefix,
                           Delimiter              => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Delimiter))),
                           Has_Delimiter          => Request.Has_Delimiter,
                           Max_Keys               => Request.Max_Keys,
                           Has_Max_Keys           => True,
                           Common_Prefixes        => <>,
                           Encoding_Type          =>
                             (if Request.URL_Encoding
                              then US.To_Unbounded_String ("url")
                              else US.Null_Unbounded_String),
                           Has_Encoding_Type      => Request.URL_Encoding);
                     begin
                        if Page.Is_Truncated then
                           Response.Next_Key_Marker :=
                             US.To_Unbounded_String
                               (Encoded
                                  (US.To_String (Page.Next_Key_Marker)));
                           Response.Next_Version_ID_Marker :=
                             Page.Next_Version_ID_Marker;
                        end if;
                        for Generation of Page.Entries loop
                           if Generation.Is_Delete_Marker then
                              Response.Delete_Markers.Append
                                (Versions.Delete_Marker'
                                   (Has_Owner         => True,
                                    Owner             =>
                                      (Display_Name =>
                                         US.Null_Unbounded_String,
                                       ID => Auth.Principal),
                                    Key               =>
                                      US.To_Unbounded_String
                                        (Encoded
                                           (US.To_String (Generation.Key))),
                                    Has_Key           => True,
                                    Version_ID        =>
                                      Generation.Version_ID,
                                    Has_Version_ID    => True,
                                    Is_Latest         => Generation.Is_Latest,
                                    Has_Is_Latest     => True,
                                    Last_Modified     =>
                                      US.To_Unbounded_String
                                        (Last_Modified
                                           (Generation.Info.Modified)),
                                    Has_Last_Modified => True));
                           else
                              declare
                                 Version : Versions.Object_Version :=
                                   (Entity_Tag         =>
                                      US.To_Unbounded_String
                                        ('"' & US.To_String
                                           (Generation.Info.Entity_Tag) & '"'),
                                    Has_Entity_Tag     => True,
                                    Checksum_Algorithms => <>,
                                    Checksum_Type      =>
                                      US.Null_Unbounded_String,
                                    Has_Checksum_Type  => False,
                                    Size               => Generation.Info.Size,
                                    Has_Size           => True,
                                    Storage_Class      =>
                                      US.To_Unbounded_String ("STANDARD"),
                                    Has_Storage_Class  => True,
                                    Key                =>
                                      US.To_Unbounded_String
                                        (Encoded
                                           (US.To_String (Generation.Key))),
                                    Has_Key            => True,
                                    Version_ID         =>
                                      Generation.Version_ID,
                                    Has_Version_ID     => True,
                                    Is_Latest          => Generation.Is_Latest,
                                    Has_Is_Latest      => True,
                                    Last_Modified      =>
                                      US.To_Unbounded_String
                                        (Last_Modified
                                           (Generation.Info.Modified)),
                                    Has_Last_Modified  => True,
                                    Has_Owner          => True,
                                    Owner              =>
                                      (Display_Name =>
                                         US.Null_Unbounded_String,
                                       ID => Auth.Principal),
                                    Has_Restore_Status => False,
                                    Restore_Status     => (others => <>));
                              begin
                                 if Generation.Info.Checksum.Algorithm /=
                                   No_Checksum
                                 then
                                    Version.Checksum_Algorithms.Append
                                      (US.To_Unbounded_String
                                         (Wire_Algorithm
                                            (Generation.Info.Checksum
                                               .Algorithm)));
                                    Version.Checksum_Type :=
                                      US.To_Unbounded_String
                                        (Wire_Method
                                           (Generation.Info.Checksum.Method));
                                    Version.Has_Checksum_Type := True;
                                 end if;
                                 Response.Versions.Append (Version);
                              end;
                           end if;
                        end loop;
                        for Prefix_Value of Page.Common_Prefixes loop
                           Response.Common_Prefixes.Append
                             (US.To_Unbounded_String
                                (Encoded (US.To_String (Prefix_Value))));
                        end loop;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Versions.Serialize_List_Object_Versions
                             (Response));
                     end;
                  end;
               exception
                  when Versions.Malformed_Version_Request =>
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ListObjectVersions request is invalid",
                        Target_Text);
               end;

            when List_Multipart_Uploads =>
               declare
                  Owner_OK : Boolean := False;
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
               begin
                  if Apps.Request_Header_Count
                       (X, "x-amz-expected-bucket-owner") > 1
                    or else Payer_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A ListMultipartUploads header is duplicated",
                        Target_Text);
                     return;
                  end if;
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1 then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Requester Pays is not implemented", Target_Text);
                     return;
                  end if;
                  begin
                     declare
                        Request : constant
                          Multipart_Uploads.List_Multipart_Uploads_Request :=
                            Multipart_Uploads.
                              Parse_List_Multipart_Uploads_Query
                                (Query_Text);
                        Options : constant
                          Backends.List_Multipart_Uploads_Options :=
                            (Prefix    => Request.Prefix,
                             Delimiter => Request.Delimiter,
                             After     =>
                               (Key       => Request.Key_Marker,
                                Upload_ID => Request.Upload_ID_Marker),
                             Maximum   =>
                               Backends.List_Limit (Request.Max_Uploads));
                        Page : Backends.Multipart_Upload_Page;

                        function Encoded (Value : String) return String is
                          (if Request.URL_Encoding
                           then Encoding.URI_Encode
                             (Value, Encode_Slash => False)
                           else Value);
                     begin
                        Store.List_Multipart_Uploads
                          (Bucket, Options, Apps.Cancellation (X),
                           Apps.Deadline (X), Page, Result);
                        if Result /= Success then
                           Send_Backend_Error
                             (X, Result, True, Target_Text);
                           return;
                        end if;
                        declare
                           Response :
                             Multipart_Uploads.List_Multipart_Uploads_Result :=
                               (Bucket => US.To_Unbounded_String (Bucket),
                                Key_Marker => US.To_Unbounded_String
                                  (Encoded
                                     (US.To_String (Request.Key_Marker))),
                                Upload_ID_Marker =>
                                  Request.Upload_ID_Marker,
                                Next_Key_Marker => US.Null_Unbounded_String,
                                Next_Upload_ID_Marker =>
                                  US.Null_Unbounded_String,
                                Prefix => US.To_Unbounded_String
                                  (Encoded (US.To_String (Request.Prefix))),
                                Delimiter => US.To_Unbounded_String
                                  (Encoded
                                     (US.To_String (Request.Delimiter))),
                                Max_Uploads => Request.Max_Uploads,
                                Is_Truncated => Page.Is_Truncated,
                                Uploads => <>,
                                Common_Prefixes => <>,
                                Encoding_Type =>
                                  (if Request.URL_Encoding
                                   then US.To_Unbounded_String ("url")
                                   else US.Null_Unbounded_String));
                        begin
                           if Page.Is_Truncated then
                              Response.Next_Key_Marker :=
                                US.To_Unbounded_String
                                  (Encoded
                                     (US.To_String (Page.Next_After.Key)));
                              Response.Next_Upload_ID_Marker :=
                                Page.Next_After.Upload_ID;
                           end if;
                           for Upload of Page.Uploads loop
                              Response.Uploads.Append
                                (Multipart_Uploads.Upload_Entry'
                                   (Upload_ID => Upload.Upload_ID,
                                    Key => US.To_Unbounded_String
                                      (Encoded (US.To_String (Upload.Key))),
                                    Initiated => US.To_Unbounded_String
                                      (Last_Modified (Upload.Initiated)),
                                    Storage_Class =>
                                      US.To_Unbounded_String ("STANDARD"),
                                    Checksum_Algorithm =>
                                      US.To_Unbounded_String
                                        (Wire_Algorithm
                                           (Upload.Options.Checksum
                                              .Algorithm)),
                                    Checksum_Type =>
                                      US.To_Unbounded_String
                                        (Wire_Method
                                           (Upload.Options.Checksum.Method)),
                                    others => <>));
                           end loop;
                           for Prefix_Value of Page.Common_Prefixes loop
                              Response.Common_Prefixes.Append
                                (US.To_Unbounded_String
                                   (Encoded (US.To_String (Prefix_Value))));
                           end loop;
                           Apps.Respond
                             (X, 200, "application/xml",
                              Multipart_Uploads.
                                Serialize_List_Multipart_Uploads (Response));
                        end;
                     end;
                  exception
                     when Multipart_Uploads.Malformed_List_Request =>
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The ListMultipartUploads request is invalid",
                           Target_Text);
                  end;
               end;

            when Create_Multipart =>
               declare
                  function Count (Name : String) return Natural is
                    (Apps.Request_Header_Count (X, Name));

                  function Duplicate_User_Metadata return Boolean is
                  begin
                     for Index in 1 .. Apps.Request_Header_Count (X) loop
                        declare
                           Name : constant String :=
                             Ada.Characters.Handling.To_Lower
                               (Apps.Request_Header_Name (X, Index));
                        begin
                           if Name'Length >= 11
                             and then Name (Name'First .. Name'First + 10) =
                               "x-amz-meta-"
                             and then Count (Name) > 1
                           then
                              return True;
                           end if;
                        end;
                     end loop;
                     return False;
                  end Duplicate_User_Metadata;

                  function Any_Duplicate return Boolean is
                    (Count ("x-amz-acl") > 1
                     or else Count ("cache-control") > 1
                     or else Count ("content-disposition") > 1
                     or else Count ("content-encoding") > 1
                     or else Count ("content-language") > 1
                     or else Count ("content-type") > 1
                     or else Count ("expires") > 1
                     or else Count ("x-amz-grant-full-control") > 1
                     or else Count ("x-amz-grant-read") > 1
                     or else Count ("x-amz-grant-read-acp") > 1
                     or else Count ("x-amz-grant-write-acp") > 1
                     or else Count ("x-amz-server-side-encryption") > 1
                     or else Count ("x-amz-storage-class") > 1
                     or else Count
                       ("x-amz-website-redirect-location") > 1
                     or else Count
                       ("x-amz-server-side-encryption-customer-algorithm") >
                         1
                     or else Count
                       ("x-amz-server-side-encryption-customer-key") > 1
                     or else Count
                       ("x-amz-server-side-encryption-customer-key-md5") > 1
                     or else Count
                       ("x-amz-server-side-encryption-aws-kms-key-id") > 1
                     or else Count
                       ("x-amz-server-side-encryption-context") > 1
                     or else Count
                       ("x-amz-server-side-encryption-bucket-key-enabled") >
                         1
                     or else Count ("x-amz-request-payer") > 1
                     or else Count ("x-amz-tagging") > 1
                     or else Count ("x-amz-object-lock-mode") > 1
                     or else Count
                       ("x-amz-object-lock-retain-until-date") > 1
                     or else Count
                       ("x-amz-object-lock-legal-hold") > 1
                     or else Count ("x-amz-expected-bucket-owner") > 1
                     or else Count ("x-amz-checksum-algorithm") > 1
                     or else Count ("x-amz-checksum-type") > 1
                     or else Duplicate_User_Metadata);

                  function Valid_Enumeration
                    (Member : Positive; Value : String) return Boolean
                  is
                     Input : constant Model.Shape_Index := Model.Shape_Index
                       (Model.Input_Shape
                          (Model.Create_Multipart_Upload_Operation));
                     Shape : constant Model.Shape_Index :=
                       Model.Member_Shape (Input, Member);
                  begin
                     for Index in 1 .. Model.Enumeration_Count (Shape) loop
                        if Value = Model.Enumeration_Value (Shape, Index) then
                           return True;
                        end if;
                     end loop;
                     return False;
                  end Valid_Enumeration;

                  function Present (Name : String) return Boolean is
                    (Count (Name) = 1);

                  function Valid_Text (Name : String) return Boolean is
                     Value : constant String := Apps.Request_Header (X, Name);
                  begin
                     if Value'Length not in 1 ..
                       Maximum_Expected_Owner_Bytes
                     then
                        return False;
                     end if;
                     for Item of Value loop
                        if Character'Pos (Item) not in 16#20# .. 16#7E# then
                           return False;
                        end if;
                     end loop;
                     return True;
                  end Valid_Text;

                  function Valid_Grant_List (Name : String) return Boolean is
                     Value : constant String := Apps.Request_Header (X, Name);
                     type Grant_Kind is (Canonical_ID, Group_URI, Email);
                     type Grant_Entry is record
                        Kind        : Grant_Kind;
                        Value_First : Positive;
                        Value_Last  : Positive;
                     end record;
                     --  Six bytes is the shortest AWS grant representation,
                     --  id="x".  This capacity is derived from the public
                     --  header bound and cannot truncate an admitted list.
                     Maximum_Grant_Entries : constant Positive :=
                       Maximum_Expected_Owner_Bytes / 6 + 1;
                     type Grant_Entry_Array is
                       array (Positive range 1 .. Maximum_Grant_Entries) of
                         Grant_Entry;
                     Entries : Grant_Entry_Array :=
                       (others =>
                          (Kind        => Canonical_ID,
                           Value_First => 1,
                           Value_Last  => 1));
                     Length : Natural := 0;
                     Position : Natural := Value'First;

                     procedure Skip_Spaces is
                     begin
                        while Position <= Value'Last
                          and then Value (Position) = ' '
                        loop
                           Position := Position + 1;
                        end loop;
                     end Skip_Spaces;

                     function Starts_With (Text : String) return Boolean is
                       (Position + Text'Length - 1 <= Value'Last
                        and then Value
                          (Position .. Position + Text'Length - 1) = Text);
                  begin
                     if not Valid_Text (Name) then
                        return False;
                     end if;
                     loop
                        Skip_Spaces;
                        if Position > Value'Last then
                           return False;
                        end if;
                        declare
                           Kind : Grant_Kind;
                        begin
                           if Starts_With ("id") then
                              Kind := Canonical_ID;
                              Position := Position + 2;
                           elsif Starts_With ("uri") then
                              Kind := Group_URI;
                              Position := Position + 3;
                           elsif Starts_With ("emailAddress") then
                              Kind := Email;
                              Position := Position + 12;
                           else
                              return False;
                           end if;
                           if Position + 1 > Value'Last
                             or else Value (Position) /= '='
                             or else Value (Position + 1) /= '"'
                           then
                              return False;
                           end if;
                           Position := Position + 2;
                           declare
                              First : constant Natural := Position;
                           begin
                              while Position <= Value'Last
                                and then Value (Position) /= '"'
                              loop
                                 Position := Position + 1;
                              end loop;
                              if Position > Value'Last or else Position = First
                              then
                                 return False;
                              end if;
                              for Prior in 1 .. Length loop
                                 if Entries (Prior).Kind = Kind
                                   and then Value
                                     (Entries (Prior).Value_First ..
                                        Entries (Prior).Value_Last) =
                                     Value (First .. Position - 1)
                                 then
                                    return False;
                                 end if;
                              end loop;
                              Length := Length + 1;
                              Entries (Length) :=
                                (Kind        => Kind,
                                 Value_First => First,
                                 Value_Last  => Position - 1);
                           end;
                           Position := Position + 1;
                        end;
                        Skip_Spaces;
                        if Position > Value'Last then
                           return True;
                        elsif Value (Position) /= ',' then
                           return False;
                        end if;
                        Position := Position + 1;
                     end loop;
                  end Valid_Grant_List;

                  function Valid_Canonical_Base64
                    (Value : String) return Boolean
                  is
                     Padding : Natural := 0;
                  begin
                     if Value'Length = 0 or else Value'Length mod 4 /= 0 then
                        return False;
                     end if;
                     if Value (Value'Last) = '=' then
                        Padding := 1;
                        if Value'Length >= 2
                          and then Value (Value'Last - 1) = '='
                        then
                           Padding := 2;
                        end if;
                     end if;
                     return S3.Wire_Core.Valid_Base64
                       (Value, Value'Length / 4 * 3 - Padding);
                  end Valid_Canonical_Base64;

                  --  The accepted retention timestamp grammar is the pinned
                  --  AWS ISO-8601 wire contract. Calendar ranges, fractional
                  --  precision, and zone bounds are externally fixed; a
                  --  change alters signed request compatibility.
                  function Valid_ISO_8601_Timestamp
                    (Value : String) return Boolean
                  is
                     Text : constant String (1 .. Value'Length) := Value;

                     function Decimal
                       (First, Last : Positive) return Natural
                     is
                        Result : Natural := 0;
                     begin
                        for Index in First .. Last loop
                           if Text (Index) not in '0' .. '9' then
                              return Natural'Last;
                           end if;
                           Result := Result * 10 +
                             Character'Pos (Text (Index)) -
                             Character'Pos ('0');
                        end loop;
                        return Result;
                     end Decimal;

                     Year        : Natural;
                     Month       : Natural;
                     Day         : Natural;
                     Hour        : Natural;
                     Minute      : Natural;
                     Second      : Natural;
                     Zone        : Positive := 20;
                     Maximum_Day : Natural;
                  begin
                     if Text'Length not in 20 .. 35
                       or else Text (5) /= '-'
                       or else Text (8) /= '-'
                       or else Text (11) /= 'T'
                       or else Text (14) /= ':'
                       or else Text (17) /= ':'
                     then
                        return False;
                     end if;
                     Year := Decimal (1, 4);
                     Month := Decimal (6, 7);
                     Day := Decimal (9, 10);
                     Hour := Decimal (12, 13);
                     Minute := Decimal (15, 16);
                     Second := Decimal (18, 19);
                     if Year not in 1 .. 9_999
                       or else Month not in 1 .. 12
                       or else Hour > 23
                       or else Minute > 59
                       or else Second > 59
                     then
                        return False;
                     end if;
                     Maximum_Day :=
                       (case Month is
                           when 2 =>
                             (if Year mod 400 = 0
                                or else
                                  (Year mod 4 = 0 and then Year mod 100 /= 0)
                              then 29 else 28),
                           when 4 | 6 | 9 | 11 => 30,
                           when others => 31);
                     if Day not in 1 .. Maximum_Day then
                        return False;
                     end if;
                     if Text (Zone) = '.' then
                        Zone := Zone + 1;
                        declare
                           First_Fraction : constant Positive := Zone;
                        begin
                           while Zone <= Text'Last
                             and then Text (Zone) in '0' .. '9'
                           loop
                              Zone := Zone + 1;
                           end loop;
                           if Zone = First_Fraction
                             or else Zone - First_Fraction > 9
                           then
                              return False;
                           end if;
                        end;
                     end if;
                     if Zone = Text'Last and then Text (Zone) = 'Z' then
                        return True;
                     elsif Zone + 5 = Text'Last
                       and then Text (Zone) in '+' | '-'
                       and then Text (Zone + 3) = ':'
                     then
                        declare
                           Offset_Hour : constant Natural :=
                             Decimal (Zone + 1, Zone + 2);
                           Offset_Minute : constant Natural :=
                             Decimal (Zone + 4, Zone + 5);
                        begin
                           return Offset_Hour <= 23
                             and then Offset_Minute <= 59;
                        end;
                     end if;
                     return False;
                  end Valid_ISO_8601_Timestamp;

                  function Has_User_Metadata return Boolean is
                  begin
                     for Index in 1 .. Apps.Request_Header_Count (X) loop
                        declare
                           Name : constant String :=
                             Ada.Characters.Handling.To_Lower
                               (Apps.Request_Header_Name (X, Index));
                        begin
                           if Name'Length >= 11
                             and then Name (Name'First .. Name'First + 10) =
                               "x-amz-meta-"
                           then
                              return True;
                           end if;
                        end;
                     end loop;
                     return False;
                  end Has_User_Metadata;

                  type Header_Name_Array is
                    array (Positive range <>) of US.Unbounded_String;
                  Unsupported_Text_Headers : constant Header_Name_Array :=
                    [US.To_Unbounded_String ("cache-control"),
                     US.To_Unbounded_String ("content-disposition"),
                     US.To_Unbounded_String ("content-encoding"),
                     US.To_Unbounded_String ("content-language"),
                     US.To_Unbounded_String ("expires"),
                     US.To_Unbounded_String ("x-amz-grant-full-control"),
                     US.To_Unbounded_String ("x-amz-grant-read"),
                     US.To_Unbounded_String ("x-amz-grant-read-acp"),
                     US.To_Unbounded_String ("x-amz-grant-write-acp"),
                     US.To_Unbounded_String
                       ("x-amz-website-redirect-location")];

                  Options : Backends.Multipart_Options :=
                    Backends.Default_Multipart_Options;
                  Upload_ID : US.Unbounded_String;
                  Owner_OK : Boolean := False;
                  Metadata : Object_Metadata := Empty_Object_Metadata;
                  Metadata_OK : Boolean := True;
                  Customer_Algorithm_Count : constant Natural := Count
                    ("x-amz-server-side-encryption-customer-algorithm");
                  Customer_Key_Count : constant Natural := Count
                    ("x-amz-server-side-encryption-customer-key");
                  Customer_MD5_Count : constant Natural := Count
                    ("x-amz-server-side-encryption-customer-key-md5");
                  Has_Customer : constant Boolean :=
                    Customer_Algorithm_Count + Customer_Key_Count +
                      Customer_MD5_Count > 0;
                  Has_KMS : constant Boolean :=
                    Present ("x-amz-server-side-encryption-aws-kms-key-id")
                    or else Present
                      ("x-amz-server-side-encryption-context")
                    or else Present
                      ("x-amz-server-side-encryption-bucket-key-enabled");

                  function Unsupported_Text_Present return Boolean is
                    (Present ("cache-control")
                     or else Present ("content-disposition")
                     or else Present ("content-encoding")
                     or else Present ("content-language")
                     or else Present ("expires")
                     or else Present ("x-amz-grant-full-control")
                     or else Present ("x-amz-grant-read")
                     or else Present ("x-amz-grant-read-acp")
                     or else Present ("x-amz-grant-write-acp")
                     or else Present
                       ("x-amz-website-redirect-location")
                     or else Has_User_Metadata);
               begin
                  if Any_Duplicate
                    or else Count ("x-amz-sdk-checksum-algorithm") > 0
                    or else Checksum_Value_Header_Count > 0
                    or else Checksum_Header_Count /=
                      Count ("x-amz-checksum-algorithm") +
                      Count ("x-amz-checksum-type")
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A CreateMultipartUpload header is duplicated or " &
                        "unknown", Target_Text);
                     return;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  end if;

                  if Present ("content-type") then
                     if Apps.Request_Header (X, "content-type")'Length = 0
                       or else not Valid_Object_Metadata
                         (Empty_Object_Metadata,
                          Apps.Request_Header (X, "content-type"))
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The multipart content type is invalid",
                           Target_Text);
                        return;
                     end if;
                     Options.Content_Type := US.To_Unbounded_String
                       (Apps.Request_Header (X, "content-type"));
                  end if;

                  for Index in 1 .. Apps.Request_Header_Count (X) loop
                     declare
                        Header_Name : constant String :=
                          Apps.Request_Header_Name (X, Index);
                        Name : constant String :=
                          Ada.Characters.Handling.To_Lower (Header_Name);
                     begin
                        if Name'Length >= 11
                          and then Name (Name'First .. Name'First + 10) =
                            "x-amz-meta-"
                        then
                           if Metadata.User.Length =
                             Maximum_User_Metadata_Entries
                           then
                              Metadata_OK := False;
                           else
                              Metadata.User.Length :=
                                Metadata.User.Length + 1;
                              Metadata.User.Items (Metadata.User.Length) :=
                                (Key => US.To_Unbounded_String
                                   (Name (Name'First + 11 .. Name'Last)),
                                 Value => US.To_Unbounded_String
                                   (Apps.Request_Header (X, Header_Name)));
                           end if;
                        end if;
                     end;
                  end loop;
                  Metadata_OK := Metadata_OK and then Valid_Object_Metadata
                    (Metadata, "");
                  if not Metadata_OK then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart user metadata is invalid",
                        Target_Text);
                     return;
                  end if;

                  for Header of Unsupported_Text_Headers loop
                     declare
                        Name : constant String := US.To_String (Header);
                     begin
                        if Present (Name)
                          and then not Valid_Text (Name)
                        then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "A multipart policy header is invalid",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end loop;
                  if (Present ("x-amz-grant-full-control")
                      and then not Valid_Grant_List
                        ("x-amz-grant-full-control"))
                    or else (Present ("x-amz-grant-read")
                      and then not Valid_Grant_List ("x-amz-grant-read"))
                    or else (Present ("x-amz-grant-read-acp")
                      and then not Valid_Grant_List ("x-amz-grant-read-acp"))
                    or else (Present ("x-amz-grant-write-acp")
                      and then not Valid_Grant_List ("x-amz-grant-write-acp"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A multipart ACL grant list is invalid", Target_Text);
                     return;
                  end if;
                  if Present ("expires")
                    and then not IMF_Dates.Parse
                      (Apps.Request_Header (X, "expires")).Valid
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart expiry is invalid", Target_Text);
                     return;
                  end if;

                  if Present ("x-amz-acl")
                    and then not Valid_Enumeration
                      (1, Apps.Request_Header (X, "x-amz-acl"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart canned ACL is invalid", Target_Text);
                     return;
                  elsif Present ("x-amz-acl")
                    and then
                      (Present ("x-amz-grant-full-control")
                       or else Present ("x-amz-grant-read")
                       or else Present ("x-amz-grant-read-acp")
                       or else Present ("x-amz-grant-write-acp"))
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A canned ACL and explicit grants cannot be combined",
                        Target_Text);
                     return;
                  end if;

                  if Present ("x-amz-request-payer")
                    and then not Valid_Enumeration
                      (24, Apps.Request_Header (X, "x-amz-request-payer"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart request payer is invalid",
                        Target_Text);
                     return;
                  end if;

                  if Present ("x-amz-server-side-encryption")
                    and then not Valid_Enumeration
                      (15, Apps.Request_Header
                         (X, "x-amz-server-side-encryption"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart encryption value is invalid",
                        Target_Text);
                     return;
                  elsif Has_Customer then
                     if Customer_Algorithm_Count /= 1
                       or else Customer_Key_Count /= 1
                       or else Customer_MD5_Count /= 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The multipart SSE-C group is incomplete",
                           Target_Text);
                        return;
                     elsif Apps.Request_Header
                       (X, "x-amz-server-side-encryption-customer-" &
                          "algorithm") /= "AES256"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The multipart SSE-C algorithm is invalid",
                           Target_Text);
                        return;
                     elsif Apps.Request_Scheme (X) /=
                       Flyology.HTTP.Secure_HTTPS
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "SSE-C requests require HTTPS", Target_Text);
                        return;
                     elsif not Checksums.Valid_SSE_C_Key_MD5
                       (Apps.Request_Header
                          (X, "x-amz-server-side-encryption-customer-key"),
                        Apps.Request_Header
                          (X, "x-amz-server-side-encryption-customer-" &
                           "key-md5"))
                     then
                        Send_Error
                          (X, 400, "InvalidDigest",
                           "The multipart SSE-C key or digest is invalid",
                           Target_Text);
                        return;
                     end if;
                  end if;
                  if Present
                    ("x-amz-server-side-encryption-aws-kms-key-id")
                    and then not Valid_Text
                      ("x-amz-server-side-encryption-aws-kms-key-id")
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart KMS key identifier is invalid",
                        Target_Text);
                     return;
                  elsif Present
                    ("x-amz-server-side-encryption-context")
                    and then
                      (not Valid_Text
                         ("x-amz-server-side-encryption-context")
                       or else not Valid_Canonical_Base64
                         (Apps.Request_Header
                            (X, "x-amz-server-side-encryption-context")))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart KMS context is invalid", Target_Text);
                     return;
                  end if;
                  if Has_Customer
                    and then
                      (Present ("x-amz-server-side-encryption") or else
                       Has_KMS)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "Multipart encryption groups cannot be combined",
                        Target_Text);
                     return;
                  elsif Has_KMS
                    and then
                      (not Present ("x-amz-server-side-encryption")
                       or else Apps.Request_Header
                         (X, "x-amz-server-side-encryption") not in
                           "aws:kms" | "aws:kms:dsse")
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The multipart KMS group is invalid", Target_Text);
                     return;
                  end if;
                  if Present
                    ("x-amz-server-side-encryption-bucket-key-enabled")
                  then
                     declare
                        Parsed : constant S3.Wire_Core.Boolean_Result :=
                          S3.Wire_Core.Parse_Boolean
                            (Apps.Request_Header
                               (X, "x-amz-server-side-encryption-" &
                                "bucket-key-enabled"));
                     begin
                        if not Parsed.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The multipart bucket-key value is invalid",
                              Target_Text);
                           return;
                        elsif Apps.Request_Header
                          (X, "x-amz-server-side-encryption") /= "aws:kms"
                        then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "A multipart bucket key requires aws:kms",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;

                  if Present ("x-amz-storage-class")
                    and then not Valid_Enumeration
                      (16, Apps.Request_Header (X, "x-amz-storage-class"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart storage class is invalid",
                        Target_Text);
                     return;
                  end if;

                  if Present ("x-amz-tagging") then
                     if Apps.Request_Header (X, "x-amz-tagging")'Length = 0
                     then
                        Send_Error
                          (X, 400, "InvalidTag",
                           "The multipart tag set is invalid", Target_Text);
                        return;
                     end if;
                     begin
                        declare
                           Ignored : constant Object_Tag_Set :=
                             Tagging.Parse_Header
                               (Apps.Request_Header (X, "x-amz-tagging"));
                           pragma Unreferenced (Ignored);
                        begin
                           null;
                        end;
                     exception
                        when Tagging.Malformed_Tagging_Query |
                          Tagging.Invalid_Tag =>
                           Send_Error
                             (X, 400, "InvalidTag",
                              "The multipart tag set is invalid",
                              Target_Text);
                           return;
                     end;
                  end if;

                  if Present ("x-amz-object-lock-mode")
                    and then not Valid_Enumeration
                      (26, Apps.Request_Header
                         (X, "x-amz-object-lock-mode"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart object lock mode is invalid",
                        Target_Text);
                     return;
                  elsif Present ("x-amz-object-lock-legal-hold")
                    and then not Valid_Enumeration
                      (28, Apps.Request_Header
                         (X, "x-amz-object-lock-legal-hold"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart legal hold is invalid", Target_Text);
                     return;
                  elsif Present ("x-amz-object-lock-mode") /=
                    Present ("x-amz-object-lock-retain-until-date")
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The multipart retention group is incomplete",
                        Target_Text);
                     return;
                  elsif Present
                    ("x-amz-object-lock-retain-until-date")
                    and then
                      (not Valid_Text
                         ("x-amz-object-lock-retain-until-date")
                       or else not Valid_ISO_8601_Timestamp
                         (Apps.Request_Header
                            (X, "x-amz-object-lock-retain-until-date")))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The multipart retention date is invalid",
                        Target_Text);
                     return;
                  end if;

                  declare
                     Algorithm_Count : constant Natural :=
                       Count ("x-amz-checksum-algorithm");
                     Type_Count : constant Natural :=
                       Count ("x-amz-checksum-type");
                     Algorithm_Valid : Boolean := False;
                     Method_Valid : Boolean := False;
                     Algorithm : Checksum_Algorithm := No_Checksum;
                     Method : Checksum_Method := No_Checksum_Method;
                  begin
                     if Algorithm_Count = 0 and then Type_Count = 0 then
                        Algorithm := Checksum_CRC64NVME;
                        Method := Full_Object_Checksum;
                        Algorithm_Valid := True;
                        Method_Valid := True;
                     elsif Algorithm_Count = 1 then
                        Algorithm := Parse_Checksum_Algorithm
                          (Apps.Request_Header
                             (X, "x-amz-checksum-algorithm"),
                           Algorithm_Valid);
                        if Type_Count = 1 then
                           Method := Parse_Checksum_Method
                             (Apps.Request_Header
                                (X, "x-amz-checksum-type"), Method_Valid);
                        else
                           Method_Valid := True;
                           Method :=
                             (if Algorithm = Checksum_CRC64NVME
                              then Full_Object_Checksum
                              else Composite_Checksum);
                        end if;
                     end if;
                     if (Algorithm_Count = 0 and then Type_Count /= 0)
                       or else
                         (Algorithm_Count = 1
                          and then
                            (not Algorithm_Valid or else not Method_Valid
                             or else
                               (Method = Full_Object_Checksum
                                and then Algorithm not in
                                  Checksum_CRC32 | Checksum_CRC32C |
                                  Checksum_CRC64NVME)
                             or else
                               (Method = Composite_Checksum
                                and then Algorithm = Checksum_CRC64NVME)))
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The multipart checksum selection is invalid",
                           Target_Text);
                        return;
                     elsif Algorithm_Count <= 1 then
                        Options.Checksum :=
                          (Algorithm => Algorithm, Method => Method,
                           Value => US.Null_Unbounded_String);
                     end if;
                  end;
                  if Present ("x-amz-acl")
                    or else Unsupported_Text_Present
                    or else Has_Encryption_Header
                    or else Present ("x-amz-storage-class")
                    or else Present ("x-amz-request-payer")
                    or else Present ("x-amz-tagging")
                    or else Present ("x-amz-object-lock-mode")
                    or else Present
                      ("x-amz-object-lock-retain-until-date")
                    or else Present ("x-amz-object-lock-legal-hold")
                  then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "This modeled CreateMultipartUpload policy is not " &
                        "implemented", Target_Text);
                     return;
                  end if;
                  Store.Create_Multipart_Upload
                    (Bucket, Key, Options, Apps.Cancellation (X),
                     Apps.Deadline (X), Upload_ID, Result);
                  if Result = Success then
                     Apps.Respond
                       (X, 200, "application/xml",
                        Multipart.Serialize_Create_Result
                          ((Bucket    => US.To_Unbounded_String (Bucket),
                            Key       => US.To_Unbounded_String (Key),
                            Upload_ID => Upload_ID)));
                  else
                     Send_Backend_Error
                       (X, Result, True, Target_Text);
                  end if;
               end;

            when List_Multipart_Parts =>
               declare
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  SSE_Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X,
                       "x-amz-server-side-encryption-customer-algorithm");
                  SSE_Key_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key");
                  SSE_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key-md5");
                  Owner_OK : Boolean := False;
               begin
                  if Apps.Request_Header_Count
                       (X, "x-amz-expected-bucket-owner") > 1
                    or else Payer_Count > 1
                    or else SSE_Algorithm_Count > 1
                    or else SSE_Key_Count > 1
                    or else SSE_MD5_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A ListParts header is duplicated", Target_Text);
                     return;
                  end if;
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1 then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Requester Pays is not implemented", Target_Text);
                     return;
                  elsif SSE_Algorithm_Count > 0
                    or else SSE_Key_Count > 0
                    or else SSE_MD5_Count > 0
                  then
                     if SSE_Algorithm_Count /= 1
                       or else SSE_Key_Count /= 1
                       or else SSE_MD5_Count /= 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The SSE-C header group is incomplete",
                           Target_Text);
                     elsif Apps.Request_Header
                       (X, "x-amz-server-side-encryption-customer-" &
                          "algorithm") /= "AES256"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The SSE-C algorithm is invalid", Target_Text);
                     elsif Apps.Request_Scheme (X) /=
                       Flyology.HTTP.Secure_HTTPS
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "SSE-C requests require HTTPS", Target_Text);
                     elsif not Checksums.Valid_SSE_C_Key_MD5
                       (Apps.Request_Header
                          (X,
                           "x-amz-server-side-encryption-customer-key"),
                        Apps.Request_Header
                          (X, "x-amz-server-side-encryption-customer-" &
                           "key-md5"))
                     then
                        Send_Error
                          (X, 400, "InvalidDigest",
                           "The SSE-C key or digest is invalid", Target_Text);
                     else
                        Send_Error
                          (X, 501, "NotImplemented",
                           "SSE-C ListParts is not implemented", Target_Text);
                     end if;
                     return;
                  elsif Has_Encryption_Header then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "The ListParts encryption header is not implemented",
                        Target_Text);
                     return;
                  end if;
                  declare
                     Query : constant Multipart.Multipart_Query :=
                       Multipart.Parse_Query (Query_Text);
                     Marker : constant Multipart.Part_Marker_Value :=
                       (if Query.Kind = Multipart.List_Parts_Query
                        then Query.Part_Number_Marker else 0);
                     Maximum : constant S3.Core.Page_Size :=
                       (if Query.Kind = Multipart.List_Parts_Query
                        then Query.Max_Parts else S3.Core.Page_Size'Last);
                     Upload_ID : constant String :=
                       (if Query.Kind = Multipart.List_Parts_Query
                        then US.To_String (Query.Listed_Upload_ID)
                        else US.To_String (Query.Existing_Upload_ID));
                     Options : constant
                       Backends.List_Multipart_Parts_Options :=
                         (After => Backends.Multipart_Part_Marker (Marker),
                          Maximum => Backends.List_Limit (Maximum));
                     Page : Backends.Multipart_Part_Page;
                  begin
                     Store.List_Multipart_Parts
                       (Bucket, Key, Upload_ID, Options,
                        Apps.Cancellation (X), Apps.Deadline (X), Page,
                        Result);
                     if Result = Not_Found then
                        Send_Error
                          (X, 404, "NoSuchUpload",
                           "The specified multipart upload does not exist",
                           Target_Text);
                        return;
                     elsif Result /= Success then
                        Send_Backend_Error (X, Result, False, Target_Text);
                        return;
                     end if;
                     declare
                        Response : Multipart.List_Parts_Result :=
                          (Bucket => US.To_Unbounded_String (Bucket),
                           Key => US.To_Unbounded_String (Key),
                           Upload_ID => US.To_Unbounded_String (Upload_ID),
                           Part_Number_Marker => Marker,
                           Next_Part_Number_Marker =>
                             Multipart.Part_Marker_Value (Page.Next_After),
                           Max_Parts => Maximum,
                           Is_Truncated => Page.Is_Truncated,
                           Parts => <>,
                           Has_Initiator => False,
                           Initiator => <>,
                           Has_Owner => False,
                           Owner => <>,
                           Storage_Class =>
                             US.To_Unbounded_String ("STANDARD"),
                           Checksum_Algorithm => US.To_Unbounded_String
                             (Wire_Algorithm (Page.Checksum.Algorithm)),
                           Checksum_Type => US.To_Unbounded_String
                             (Wire_Method (Page.Checksum.Method)));
                     begin
                        for Part of Page.Parts loop
                           declare
                              Value : Multipart.Listed_Part :=
                                (Number => S3.Core.Part_Number (Part.Number),
                                 Last_Modified => US.To_Unbounded_String
                                   (Last_Modified (Part.Info.Modified)),
                                 Entity_Tag => US.To_Unbounded_String
                                   ('"' & US.To_String
                                      (Part.Info.Entity_Tag) & '"'),
                                 Size => Part.Info.Size,
                                 others => <>);
                           begin
                              case Part.Info.Checksum.Algorithm is
                                 when No_Checksum => null;
                                 when Checksum_CRC32 =>
                                    Value.Checksum_CRC32 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_CRC32C =>
                                    Value.Checksum_CRC32C :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_CRC64NVME =>
                                    Value.Checksum_CRC64NVME :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_SHA1 =>
                                    Value.Checksum_SHA1 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_SHA256 =>
                                    Value.Checksum_SHA256 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_SHA512 =>
                                    Value.Checksum_SHA512 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_MD5 =>
                                    Value.Checksum_MD5 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_XXHASH64 =>
                                    Value.Checksum_XXHASH64 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_XXHASH3 =>
                                    Value.Checksum_XXHASH3 :=
                                      Part.Info.Checksum.Value;
                                 when Checksum_XXHASH128 =>
                                    Value.Checksum_XXHASH128 :=
                                      Part.Info.Checksum.Value;
                              end case;
                              Response.Parts.Append (Value);
                           end;
                        end loop;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Multipart.Serialize_List_Parts_Result (Response));
                     end;
                  exception
                     when Multipart.Malformed_Multipart =>
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The ListParts request is invalid", Target_Text);
                  end;
               end;

            when Put_Multipart_Part =>
               declare
                  Query : constant Multipart.Multipart_Query :=
                    Multipart.Parse_Query (Query_Text);
                  Value_Count : constant Natural :=
                    Checksum_Value_Header_Count;
                  SDK_Count : constant Natural := Apps.Request_Header_Count
                    (X, "x-amz-sdk-checksum-algorithm");
                  Trailer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-trailer");
                  Content_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Owner_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-expected-bucket-owner");
                  Value_Algorithm : Checksum_Algorithm :=
                    Checksum_Value_Algorithm;
                  SDK_Algorithm : Checksum_Algorithm := No_Checksum;
                  SDK_Valid : Boolean := False;
                  Verify_Checksum : Boolean := False;
                  Trailer_Checksum : Boolean := False;
                  Supplied_Checksum : US.Unbounded_String;
                  Owner_OK : Boolean := False;
                  Encoding_OK : Boolean := True;
                  AWS_Chunked_Encoding : Boolean := False;
                  Page : Backends.Multipart_Part_Page;
                  Part_Options : Backends.Multipart_Part_Options :=
                    Backends.Default_Multipart_Part_Options;

                  function Valid_Content_Coding (Value : String)
                    return Boolean
                  is
                  begin
                     if Value'Length = 0 then
                        return False;
                     end if;
                     for Item of Value loop
                        if not (Item in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
                                or else Item in
                                  '!' | '#' | '$' | '%' | '&' | ''' | '*' |
                                  '+' | '-' | '.' | '^' | '_' | '`' | '|' |
                                  '~')
                        then
                           return False;
                        end if;
                     end loop;
                     return True;
                  end Valid_Content_Coding;

                  procedure Parse_Content_Encoding is
                  begin
                     if Apps.Request_Header_Count (X, "content-encoding") = 0
                     then
                        return;
                     end if;
                     declare
                        Value : constant String :=
                          Apps.Request_Header (X, "content-encoding");
                        Cursor : Integer := Value'First;
                     begin
                        if Value'Length = 0 then
                           Encoding_OK := False;
                           return;
                        end if;
                        while Cursor <= Value'Last loop
                           declare
                              Comma : constant Natural :=
                                Ada.Strings.Fixed.Index
                                  (Value, ",", From => Cursor);
                              Last : constant Integer :=
                                (if Comma = 0 then Value'Last
                                 else Integer (Comma) - 1);
                              Token : constant String :=
                                Ada.Strings.Fixed.Trim
                                  (Value (Cursor .. Last), Ada.Strings.Both);
                           begin
                              if not Valid_Content_Coding (Token) then
                                 Encoding_OK := False;
                                 return;
                              elsif Ada.Characters.Handling.To_Lower (Token) =
                                "aws-chunked"
                              then
                                 if AWS_Chunked_Encoding then
                                    Encoding_OK := False;
                                    return;
                                 end if;
                                 AWS_Chunked_Encoding := True;
                              end if;
                              exit when Comma = 0;
                              Cursor := Integer (Comma) + 1;
                              if Cursor > Value'Last then
                                 Encoding_OK := False;
                                 return;
                              end if;
                           end;
                        end loop;
                     end;
                  end Parse_Content_Encoding;
               begin
                  if Value_Count > 1 or else SDK_Count > 1
                    or else Trailer_Count > 1
                    or else Content_MD5_Count > 1
                    or else Payer_Count > 1
                    or else Apps.Request_Header_Count
                      (X, "content-encoding") > 1
                    or else Checksum_Header_Count /= Value_Count
                    or else Apps.Request_Header_Count
                      (X, "x-amz-checksum-algorithm") > 0
                    or else Apps.Request_Header_Count
                      (X, "x-amz-checksum-type") > 0
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The UploadPart checksum group is invalid",
                        Target_Text);
                     return;
                  elsif Content_MD5_Count = 1
                    and then not S3.Wire_Core.Valid_Base64
                      (Apps.Request_Header (X, "content-md5"), 16)
                  then
                     Send_Error
                       (X, 400, "InvalidDigest",
                        "The Content-MD5 is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1 then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Requester Pays is not implemented", Target_Text);
                     return;
                  elsif Owner_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-expected-bucket-owner")'Length
                        not in 1 .. Maximum_Expected_Owner_Bytes
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The expected bucket owner is invalid", Target_Text);
                     return;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  end if;

                  Parse_Content_Encoding;
                  if not Encoding_OK then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The content encoding is invalid", Target_Text);
                     return;
                  elsif Apps.Request_Header_Count
                    (X, "content-encoding") = 1
                    and then not AWS_Chunked_Encoding
                  then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "UploadPart content encoding is not implemented",
                        Target_Text);
                     return;
                  elsif not AWS_Chunked_Encoding
                    and then Apps.Request_Header_Count
                      (X, "x-amz-decoded-content-length") > 0
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A decoded content length requires aws-chunked",
                        Target_Text);
                     return;
                  end if;

                  if SDK_Count = 1 then
                     SDK_Algorithm := Parse_Checksum_Algorithm
                       (Apps.Request_Header
                          (X, "x-amz-sdk-checksum-algorithm"), SDK_Valid);
                     if not SDK_Valid then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The UploadPart checksum algorithm is invalid",
                           Target_Text);
                        return;
                     end if;
                  end if;

                  if Value_Count = 1 then
                     if Trailer_Count > 0 then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The UploadPart checksum group is invalid",
                           Target_Text);
                        return;
                     end if;
                     Supplied_Checksum := US.To_Unbounded_String
                       (Apps.Request_Header
                          (X, Checksum_Header_Name (Value_Algorithm)));
                     if not Checksum_Engine.Valid_Digest
                       (US.To_String (Supplied_Checksum), Value_Algorithm)
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The UploadPart checksum value is invalid",
                           Target_Text);
                        return;
                     end if;
                     Verify_Checksum := True;
                  elsif Trailer_Count = 1 then
                     if SDK_Count /= 1
                       or else Ada.Characters.Handling.To_Lower
                         (Apps.Request_Header (X, "x-amz-trailer")) /=
                           Checksum_Header_Name (SDK_Algorithm)
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The UploadPart checksum trailer is invalid",
                           Target_Text);
                        return;
                     end if;
                     Value_Algorithm := SDK_Algorithm;
                     Verify_Checksum := True;
                     Trailer_Checksum := True;
                  elsif SDK_Count = 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The selected UploadPart checksum is missing",
                        Target_Text);
                     return;
                  end if;

                  if AWS_Chunked_Encoding then
                     if Apps.Request_Header_Count
                       (X, "x-amz-decoded-content-length") /= 1
                       or else not Trailer_Checksum
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "aws-chunked requires one decoded length and " &
                           "checksum trailer", Target_Text);
                        return;
                     end if;
                     declare
                        Parsed : constant S3.Wire_Core.Byte_Count_Result :=
                          S3.Wire_Core.Parse_Byte_Count
                            (Apps.Request_Header
                               (X, "x-amz-decoded-content-length"));
                     begin
                        if not Parsed.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The decoded content length is invalid",
                              Target_Text);
                           return;
                        elsif Parsed.Value >
                          Backends.Maximum_Multipart_Part_Size
                        then
                           Send_Error
                             (X, 400, "EntityTooLarge",
                              "Your proposed upload exceeds the maximum " &
                              "allowed size", Target_Text);
                           return;
                        end if;
                     end;
                     Send_Error
                       (X, 501, "NotImplemented",
                        "aws-chunked payloads are not implemented",
                        Target_Text);
                     return;
                  elsif Length.Kind = Backends.Known
                    and then Length.Bytes >
                      Backends.Maximum_Multipart_Part_Size
                  then
                     Send_Error
                       (X, 400, "EntityTooLarge",
                        "Your proposed upload exceeds the maximum allowed " &
                        "size", Target_Text);
                     return;
                  end if;

                  Store.List_Multipart_Parts
                    (Bucket, Key, US.To_String (Query.Upload_ID),
                     (After => 0, Maximum => 0), Apps.Cancellation (X),
                     Apps.Deadline (X), Page, Result);
                  if Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                     return;
                  elsif Result /= Success then
                     Send_Backend_Error (X, Result, False, Target_Text);
                     return;
                  elsif Page.Checksum.Method = Composite_Checksum
                    and then not Verify_Checksum
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A composite UploadPart checksum is required",
                        Target_Text);
                     return;
                  elsif Verify_Checksum
                    and then Value_Algorithm /= Page.Checksum.Algorithm
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The UploadPart checksum differs from initiation",
                        Target_Text);
                     return;
                  end if;
                  if Value_Count = 1 then
                     Part_Options.Expected_Checksum :=
                       (Algorithm => Value_Algorithm,
                        Method    => Page.Checksum.Method,
                        Value     => Supplied_Checksum);
                  end if;

                  declare
                     Selected : constant Checksum_Algorithm :=
                       (if Page.Checksum.Algorithm = No_Checksum
                        then Checksum_CRC64NVME
                        else Page.Checksum.Algorithm);
                     Source : Request_IO.Request_Source
                       (Checksum_Engine.Algorithm_Value (Selected)) :=
                         (Checksum_Kind =>
                            Checksum_Engine.Algorithm_Value (Selected),
                          Length_Value  => Length,
                          Expected_Hash => Auth.Payload_Hash,
                          Check_Hash    =>
                            US.To_String (Auth.Payload_Hash) /=
                              S3.SigV4.Unsigned_Payload,
                          Hash      => GNAT.SHA256.Initial_Context,
                          Check_Content_MD5 => Content_MD5_Count = 1,
                          Expected_Content_MD5 =>
                            (if Content_MD5_Count = 1
                             then US.To_Unbounded_String
                               (Apps.Request_Header (X, "content-md5"))
                             else US.Null_Unbounded_String),
                          Check_Body_Checksum => Verify_Checksum,
                          Checksum_From_Trailer => Trailer_Checksum,
                          Reject_Unexpected_Trailers => True,
                          Expected_Body_Checksum => Supplied_Checksum,
                          Observed  => 0,
                          Maximum   =>
                            Backends.Maximum_Multipart_Part_Size,
                          Completed => False,
                          others    => <>);
                  begin
                     Store.Put_Multipart_Part
                       (Bucket, Key, US.To_String (Query.Upload_ID),
                        Backends.Multipart_Part_Number (Query.Part_Number),
                        Source, Part_Options, Apps.Cancellation (X),
                        Apps.Deadline (X), Info, Result);
                     if Result = Success and then not Source.Completed then
                        raise Program_Error with
                          "backend committed before validating the whole " &
                          "part";
                     end if;
                  end;
                  if Result = Success then
                     Apps.Set_Header
                       (X, "ETag", '"' & US.To_String (Info.Entity_Tag) & '"');
                     if Info.Checksum.Algorithm /= No_Checksum then
                        Apps.Set_Header
                          (X, Checksum_Header_Name (Info.Checksum.Algorithm),
                           US.To_String (Info.Checksum.Value));
                     end if;
                     Apps.Respond (X, 200, "", "");
                  elsif Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                  else
                     Send_Backend_Error (X, Result, False, Target_Text);
                  end if;
               end;

            when Copy_Multipart_Part =>
               if Apps.Request_Header_Count (X, "x-amz-copy-source") /= 1
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-range") > 1
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-match") > 1
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-none-match") > 1
               then
                  Send_Error
                    (X, 400, "InvalidRequest",
                     "An UploadPartCopy header is missing or duplicated",
                     Target_Text);
                  return;
               elsif Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-modified-since") > 0
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-unmodified-since") > 0
               then
                  Send_Error
                    (X, 501, "NotImplemented",
                     "UploadPartCopy date conditions are not implemented",
                     Target_Text);
                  return;
               end if;
               if (Apps.Request_Header_Count
                     (X, "x-amz-copy-source-if-match") = 1
                   and then Apps.Request_Header
                     (X, "x-amz-copy-source-if-match")'Length = 0)
                 or else
                   (Apps.Request_Header_Count
                      (X, "x-amz-copy-source-if-none-match") = 1
                    and then Apps.Request_Header
                      (X, "x-amz-copy-source-if-none-match")'Length = 0)
               then
                  Send_Error
                    (X, 400, "InvalidArgument",
                     "A copy source entity-tag condition is empty",
                     Target_Text);
                  return;
               end if;
               declare
                  Query : constant Multipart.Multipart_Query :=
                    Multipart.Parse_Query (Query_Text);
                  Raw_Source : constant String :=
                    Apps.Request_Header (X, "x-amz-copy-source");
                  Source_Target : constant String :=
                    (if Raw_Source'Length > 0
                       and then Raw_Source (Raw_Source'First) = '/'
                     then Raw_Source else '/' & Raw_Source);
                  Source_Parsed : constant Requests.Target_Result :=
                    Requests.Parse_Target (Source_Target);
                  Requested : Byte_Range := Whole_Object;
                  Conditions : Backends.Copy_Conditions := (others => <>);
               begin
                  if Source_Parsed.Status /= Requests.Target_Parsed
                    or else Source_Parsed.Kind /= Requests.Object_Target
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The copy source is invalid", Target_Text);
                     return;
                  elsif Source_Parsed.Has_Query then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Copying a specific object version is not " &
                        "implemented", Target_Text);
                     return;
                  end if;
                  if Apps.Request_Header_Count
                    (X, "x-amz-copy-source-range") = 1
                  then
                     declare
                        Parsed_Range : constant S3.Core.Range_Parse_Result :=
                          S3.Core.Parse_Range_Header
                            (Apps.Request_Header
                               (X, "x-amz-copy-source-range"));
                     begin
                        if Parsed_Range.Status /= S3.Core.Range_Parsed
                          or else Parsed_Range.Request.Kind /= Bounded_Range
                        then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The copy source range is invalid",
                              Target_Text);
                           return;
                        end if;
                        Requested := Parsed_Range.Request;
                     end;
                  end if;
                  if Apps.Request_Header_Count
                    (X, "x-amz-copy-source-if-match") = 1
                  then
                     Conditions.If_Match := US.To_Unbounded_String
                       (Apps.Request_Header
                          (X, "x-amz-copy-source-if-match"));
                  end if;
                  if Apps.Request_Header_Count
                    (X, "x-amz-copy-source-if-none-match") = 1
                  then
                     Conditions.If_None_Match := US.To_Unbounded_String
                       (Apps.Request_Header
                          (X, "x-amz-copy-source-if-none-match"));
                  end if;

                  Store.Copy_Multipart_Part
                    (Requests.Bucket_Name (Source_Target, Source_Parsed),
                     Requests.Object_Key (Source_Target, Source_Parsed),
                     Bucket, Key, US.To_String (Query.Upload_ID),
                     Backends.Multipart_Part_Number (Query.Part_Number),
                     Requested, Conditions, Apps.Cancellation (X),
                     Apps.Deadline (X), Info, Result);
                  if Result = Success then
                     Apps.Respond
                       (X, 200, "application/xml",
                        Copy_Result_XML ("CopyPartResult", Info));
                  elsif Result in Source_Bucket_Not_Found | Source_Not_Found
                  then
                     Send_Backend_Error
                       (X, Result, False, Source_Target);
                  elsif Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                  else
                     Send_Backend_Error (X, Result, False, Target_Text);
                  end if;
               end;

            when Complete_Multipart =>
               declare
                  Query : constant Multipart.Multipart_Query :=
                    Multipart.Parse_Query (Query_Text);
                  Source : Request_IO.Request_Source :=
                    (Checksum_Kind => S3.Core.CRC64NVME,
                     Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Maximum_Complete_Multipart_Body,
                     Completed => False,
                     others    => <>);
                  Request : constant
                    Multipart.Complete_Multipart_Upload_Request :=
                      Multipart.Parse_Complete_Request
                        (Read_Document (Source));
                  Completion : Backends.Multipart_Part_References;
                  Options : Backends.Complete_Multipart_Options :=
                    Backends.Default_Complete_Multipart_Options;
                  Owner_OK : Boolean := False;
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Size_Count : constant Natural := Apps.Request_Header_Count
                    (X, "x-amz-mp-object-size");
                  Match_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-match");
                  None_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-none-match");
                  SSE_Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X,
                       "x-amz-server-side-encryption-customer-algorithm");
                  SSE_Key_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key");
                  SSE_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key-md5");
                  Value_Count : constant Natural :=
                    Checksum_Value_Header_Count;
                  Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-algorithm");
                  Type_Count : constant Natural := Apps.Request_Header_Count
                    (X, "x-amz-checksum-type");
                  Value_Algorithm : constant Checksum_Algorithm :=
                    Checksum_Value_Algorithm;
                  Requested_Algorithm : Checksum_Algorithm := No_Checksum;
                  Requested_Method : Checksum_Method := No_Checksum_Method;
                  Page : Backends.Multipart_Part_Page;

                  function Bare_ETag (Value : String) return String is
                    (if Value'Length >= 2
                       and then Value (Value'First) = '"'
                       and then Value (Value'Last) = '"'
                     then Value (Value'First + 1 .. Value'Last - 1)
                     else Value);

                  function Part_Checksum_Count
                    (Part : Multipart.Completed_Part) return Natural is
                    (Boolean'Pos (US.Length (Part.Checksum_CRC32) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_CRC32C) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_CRC64NVME) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_SHA1) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_SHA256) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_SHA512) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_MD5) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_XXHASH64) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_XXHASH3) > 0) +
                     Boolean'Pos (US.Length (Part.Checksum_XXHASH128) > 0));

                  function Part_Checksum_Value
                    (Part : Multipart.Completed_Part;
                     Algorithm : Checksum_Algorithm) return US.Unbounded_String
                  is
                    (case Algorithm is
                        when No_Checksum => US.Null_Unbounded_String,
                        when Checksum_CRC32 => Part.Checksum_CRC32,
                        when Checksum_CRC32C => Part.Checksum_CRC32C,
                        when Checksum_CRC64NVME => Part.Checksum_CRC64NVME,
                        when Checksum_SHA1 => Part.Checksum_SHA1,
                        when Checksum_SHA256 => Part.Checksum_SHA256,
                        when Checksum_SHA512 => Part.Checksum_SHA512,
                        when Checksum_MD5 => Part.Checksum_MD5,
                        when Checksum_XXHASH64 => Part.Checksum_XXHASH64,
                        when Checksum_XXHASH3 => Part.Checksum_XXHASH3,
                        when Checksum_XXHASH128 => Part.Checksum_XXHASH128);
               begin
                  if Payer_Count > 1
                    or else Size_Count > 1
                    or else Match_Count > 1
                    or else None_Count > 1
                    or else SSE_Algorithm_Count > 1
                    or else SSE_Key_Count > 1
                    or else SSE_MD5_Count > 1
                    or else Value_Count > 1
                    or else Type_Count > 1
                    or else Algorithm_Count > 1
                    or else Apps.Request_Header_Count
                      (X, "x-amz-sdk-checksum-algorithm") > 0
                    or else Checksum_Header_Count /=
                      Value_Count + Algorithm_Count + Type_Count
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A CompleteMultipartUpload header is duplicated",
                        Target_Text);
                     return;
                  end if;
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1 then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Requester Pays is not implemented", Target_Text);
                     return;
                  elsif SSE_Algorithm_Count + SSE_Key_Count + SSE_MD5_Count > 0
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The multipart upload does not use SSE-C",
                        Target_Text);
                     return;
                  elsif Has_Encryption_Header then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Server-side encryption is not implemented",
                        Target_Text);
                     return;
                  end if;
                  if Match_Count = 1 then
                     Options.Conditions.If_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-match"));
                  end if;
                  if None_Count = 1 then
                     Options.Conditions.If_None_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header (X, "if-none-match"));
                  end if;
                  if (Match_Count = 1
                      and then US.Length (Options.Conditions.If_Match) = 0)
                    or else
                      (None_Count = 1
                       and then
                         US.Length (Options.Conditions.If_None_Match) = 0)
                    or else not Backends.Valid_Write_Conditions
                      (Options.Conditions)
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A multipart destination condition is invalid",
                        Target_Text);
                     return;
                  end if;
                  if Size_Count = 1 then
                     declare
                        Parsed : constant S3.Wire_Core.Byte_Count_Result :=
                          S3.Wire_Core.Parse_Byte_Count
                            (Apps.Request_Header
                               (X, "x-amz-mp-object-size"));
                     begin
                        if not Parsed.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The multipart object size is invalid",
                              Target_Text);
                           return;
                        end if;
                        Options.Expected_Size :=
                          (Kind => Backends.Known, Bytes => Parsed.Value);
                     end;
                  end if;
                  if Algorithm_Count = 1 then
                     declare
                        Valid : Boolean := False;
                     begin
                        Requested_Algorithm := Parse_Checksum_Algorithm
                          (Apps.Request_Header
                             (X, "x-amz-checksum-algorithm"), Valid);
                        if not Valid then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "The multipart checksum algorithm is invalid",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;
                  if Type_Count = 1 then
                     declare
                        Valid : Boolean := False;
                     begin
                        Requested_Method := Parse_Checksum_Method
                          (Apps.Request_Header (X, "x-amz-checksum-type"),
                           Valid);
                        if not Valid then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "The multipart checksum type is invalid",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;
                  if Value_Count = 1
                    and then not Checksum_Engine.Valid_Digest
                      (Apps.Request_Header
                         (X, Checksum_Header_Name (Value_Algorithm)),
                       Value_Algorithm)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The multipart completion checksum is malformed",
                        Target_Text);
                     return;
                  end if;
                  Store.List_Multipart_Parts
                    (Bucket, Key,
                     US.To_String (Query.Existing_Upload_ID),
                     (After => 0, Maximum => 0), Apps.Cancellation (X),
                     Apps.Deadline (X), Page, Result);
                  if Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                     return;
                  elsif Result /= Success then
                     Send_Backend_Error (X, Result, False, Target_Text);
                     return;
                  elsif Value_Count = 1
                    and then
                      (Page.Checksum.Algorithm = No_Checksum
                       or else Value_Algorithm /= Page.Checksum.Algorithm)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The multipart completion checksum is invalid",
                        Target_Text);
                     return;
                  end if;
                  if Algorithm_Count = 1 then
                     if Requested_Algorithm /= Page.Checksum.Algorithm then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The multipart checksum algorithm is invalid",
                           Target_Text);
                        return;
                     end if;
                  end if;
                  if Type_Count = 1 then
                     if Requested_Method /= Page.Checksum.Method then
                        Send_Error
                          (X, 400, "BadDigest",
                           "The multipart checksum type did not match",
                           Target_Text);
                        return;
                     end if;
                  end if;
                  if Value_Count = 1 then
                     Options.Expected_Checksum :=
                       (Algorithm => Value_Algorithm,
                        Method    => Page.Checksum.Method,
                        Value     => US.To_Unbounded_String
                          (Apps.Request_Header
                             (X, Checksum_Header_Name (Value_Algorithm))));
                  end if;
                  for Part of Request.Parts loop
                     declare
                        Count : constant Natural :=
                          Part_Checksum_Count (Part);
                        Value : constant US.Unbounded_String :=
                          Part_Checksum_Value
                            (Part, Page.Checksum.Algorithm);
                     begin
                        if Count > 1
                          or else
                            (Page.Checksum.Algorithm = No_Checksum
                             and then Count > 0)
                          or else
                            (Page.Checksum.Method = Composite_Checksum
                             and then
                               (Count /= 1 or else US.Length (Value) = 0))
                          or else
                            (Page.Checksum.Method = Full_Object_Checksum
                             and then Count = 1
                             and then US.Length (Value) = 0)
                        then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "A completed part checksum is invalid",
                              Target_Text);
                           return;
                        end if;
                        Completion.Append
                          (Backends.Multipart_Part_Reference'
                             (Number => Backends.Multipart_Part_Number
                                (Part.Number),
                              Entity_Tag => US.To_Unbounded_String
                                (Bare_ETag
                                   (US.To_String (Part.Entity_Tag))),
                              Checksum =>
                                (if US.Length (Value) = 0
                                 then No_Checksum_Information
                                 else
                                   (Algorithm => Page.Checksum.Algorithm,
                                    Method    => Page.Checksum.Method,
                                    Value     => Value))));
                     end;
                  end loop;
                  Store.Complete_Multipart_Upload
                    (Bucket, Key,
                     US.To_String (Query.Existing_Upload_ID), Completion,
                     Options,
                     Apps.Cancellation (X), Apps.Deadline (X), Info, Result);
                  if Result = Success then
                     declare
                        Response : Multipart.Complete_Multipart_Upload_Result
                          := (Location => US.To_Unbounded_String
                                ("/" & Bucket & "/" &
                                 Encoding.URI_Encode
                                   (Key, Encode_Slash => False)),
                              Bucket => US.To_Unbounded_String (Bucket),
                              Key => US.To_Unbounded_String (Key),
                              Entity_Tag => US.To_Unbounded_String
                                ('"' & US.To_String (Info.Entity_Tag) & '"'),
                              others => <>);
                     begin
                        case Info.Checksum.Algorithm is
                           when No_Checksum => null;
                           when Checksum_CRC32 =>
                              Response.Checksum_CRC32 := Info.Checksum.Value;
                           when Checksum_CRC32C =>
                              Response.Checksum_CRC32C := Info.Checksum.Value;
                           when Checksum_CRC64NVME =>
                              Response.Checksum_CRC64NVME :=
                                Info.Checksum.Value;
                           when Checksum_SHA1 =>
                              Response.Checksum_SHA1 := Info.Checksum.Value;
                           when Checksum_SHA256 =>
                              Response.Checksum_SHA256 := Info.Checksum.Value;
                           when Checksum_SHA512 =>
                              Response.Checksum_SHA512 := Info.Checksum.Value;
                           when Checksum_MD5 =>
                              Response.Checksum_MD5 := Info.Checksum.Value;
                           when Checksum_XXHASH64 =>
                              Response.Checksum_XXHASH64 :=
                                Info.Checksum.Value;
                           when Checksum_XXHASH3 =>
                              Response.Checksum_XXHASH3 :=
                                Info.Checksum.Value;
                           when Checksum_XXHASH128 =>
                              Response.Checksum_XXHASH128 :=
                                Info.Checksum.Value;
                        end case;
                        Response.Checksum_Type := US.To_Unbounded_String
                          (Wire_Method (Info.Checksum.Method));
                        if US.Length (Info.Version) > 0 then
                           Apps.Set_Header
                             (X, "x-amz-version-id",
                              US.To_String (Info.Version));
                        end if;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Multipart.Serialize_Complete_Result (Response));
                     end;
                  elsif Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                  else
                     Send_Backend_Error (X, Result, False, Target_Text);
                  end if;
               end;

            when Abort_Multipart =>
               declare
                  Query : constant Multipart.Multipart_Query :=
                    Multipart.Parse_Query (Query_Text);
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Initiated_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-if-match-initiated-time");
                  Owner_OK : Boolean := False;
                  Conditions : Backends.Abort_Multipart_Conditions :=
                    Backends.No_Abort_Multipart_Conditions;
               begin
                  if Payer_Count > 1 or else Initiated_Count > 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "An AbortMultipartUpload header is duplicated",
                        Target_Text);
                     return;
                  end if;
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1 then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Requester Pays is not implemented", Target_Text);
                     return;
                  elsif Initiated_Count = 1 then
                     declare
                        Parsed : constant
                          Object_Reads.Conditional_Date_Result :=
                            Object_Reads.Parse_Conditional_Date
                              (Apps.Request_Header
                                 (X, "x-amz-if-match-initiated-time"));
                     begin
                        if not Parsed.Valid
                          or else Parsed.Seconds_Since_Epoch < 0
                        then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The initiation time is invalid", Target_Text);
                           return;
                        end if;
                        Conditions :=
                          (Has_Initiated_Time => True,
                           Initiated_Time => Unix_Time
                             (Parsed.Seconds_Since_Epoch));
                     end;
                  end if;
                  Store.Abort_Multipart_Upload
                    (Bucket, Key,
                     US.To_String (Query.Existing_Upload_ID),
                     Conditions,
                     Apps.Cancellation (X), Apps.Deadline (X), Result);
                  if Result = Success then
                     Apps.Respond (X, 204, "", "");
                  elsif Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                  else
                     Send_Backend_Error (X, Result, False, Target_Text);
                  end if;
               end;

            when Copy_Object =>
               declare
                  function Count (Name : String) return Natural is
                    (Apps.Request_Header_Count (X, Name));

                  function Duplicate_User_Metadata return Boolean is
                  begin
                     for Index in 1 .. Apps.Request_Header_Count (X) loop
                        declare
                           Name : constant String :=
                             Ada.Characters.Handling.To_Lower
                               (Apps.Request_Header_Name (X, Index));
                        begin
                           if Name'Length >= 11
                             and then Name (Name'First .. Name'First + 10) =
                               "x-amz-meta-"
                             and then Count (Name) > 1
                           then
                              return True;
                           end if;
                        end;
                     end loop;
                     return False;
                  end Duplicate_User_Metadata;

                  function Has_User_Metadata_Header return Boolean is
                  begin
                     for Index in 1 .. Apps.Request_Header_Count (X) loop
                        declare
                           Name : constant String :=
                             Ada.Characters.Handling.To_Lower
                               (Apps.Request_Header_Name (X, Index));
                        begin
                           if Name'Length >= 11
                             and then Name (Name'First .. Name'First + 10) =
                               "x-amz-meta-"
                           then
                              return True;
                           end if;
                        end;
                     end loop;
                     return False;
                  end Has_User_Metadata_Header;

                  function Any_Duplicate return Boolean is
                    (Count ("x-amz-copy-source") > 1
                     or else Count ("x-amz-acl") > 1
                     or else Count ("cache-control") > 1
                     or else Count ("x-amz-checksum-algorithm") > 1
                     or else Count ("content-disposition") > 1
                     or else Count ("content-encoding") > 1
                     or else Count ("content-language") > 1
                     or else Count ("content-type") > 1
                     or else Count ("x-amz-decoded-content-length") > 1
                     or else Count ("x-amz-copy-source-if-match") > 1
                     or else Count
                       ("x-amz-copy-source-if-modified-since") > 1
                     or else Count ("x-amz-copy-source-if-none-match") > 1
                     or else Count
                       ("x-amz-copy-source-if-unmodified-since") > 1
                     or else Count ("expires") > 1
                     or else Count ("x-amz-grant-full-control") > 1
                     or else Count ("x-amz-grant-read") > 1
                     or else Count ("x-amz-grant-read-acp") > 1
                     or else Count ("x-amz-grant-write-acp") > 1
                     or else Count ("if-match") > 1
                     or else Count ("if-none-match") > 1
                     or else Count ("x-amz-metadata-directive") > 1
                     or else Count ("x-amz-tagging-directive") > 1
                     or else Count
                       ("x-amz-object-annotation-directive") > 1
                     or else Count ("x-amz-server-side-encryption") > 1
                     or else Count ("x-amz-storage-class") > 1
                     or else Count
                       ("x-amz-website-redirect-location") > 1
                     or else Count
                       ("x-amz-server-side-encryption-customer-algorithm") >
                         1
                     or else Count
                       ("x-amz-server-side-encryption-customer-key") > 1
                     or else Count
                       ("x-amz-server-side-encryption-customer-key-md5") > 1
                     or else Count
                       ("x-amz-server-side-encryption-aws-kms-key-id") > 1
                     or else Count
                       ("x-amz-server-side-encryption-context") > 1
                     or else Count
                       ("x-amz-server-side-encryption-bucket-key-enabled") >
                         1
                     or else Count
                       ("x-amz-copy-source-server-side-encryption-" &
                        "customer-algorithm") > 1
                     or else Count
                       ("x-amz-copy-source-server-side-encryption-" &
                        "customer-key") > 1
                     or else Count
                       ("x-amz-copy-source-server-side-encryption-" &
                        "customer-key-md5") > 1
                     or else Count ("x-amz-request-payer") > 1
                     or else Count ("x-amz-tagging") > 1
                     or else Count ("x-amz-object-lock-mode") > 1
                     or else Count
                       ("x-amz-object-lock-retain-until-date") > 1
                     or else Count
                       ("x-amz-object-lock-legal-hold") > 1
                     or else Count ("x-amz-expected-bucket-owner") > 1
                     or else Count
                       ("x-amz-source-expected-bucket-owner") > 1
                     or else Duplicate_User_Metadata);

                  function Valid_Enumeration
                    (Member : Positive; Value : String) return Boolean
                  is
                     Input : constant Model.Shape_Index := Model.Shape_Index
                       (Model.Input_Shape (Model.Copy_Object_Operation));
                     Shape : constant Model.Shape_Index :=
                       Model.Member_Shape (Input, Member);
                  begin
                     for Index in 1 .. Model.Enumeration_Count (Shape) loop
                        if Value = Model.Enumeration_Value (Shape, Index) then
                           return True;
                        end if;
                     end loop;
                     return False;
                  end Valid_Enumeration;

                  Raw_Source : constant String :=
                    Apps.Request_Header (X, "x-amz-copy-source");
                  Source_Target : constant String :=
                    (if Raw_Source'Length > 0
                       and then Raw_Source (Raw_Source'First) = '/'
                     then Raw_Source else '/' & Raw_Source);
                  Source_Parsed : constant Requests.Target_Result :=
                    Requests.Parse_Target (Source_Target);
                  Copy_Options_Value : Backends.Copy_Options :=
                    Backends.Default_Copy_Options;
                  Source_Read_Request : Object_Reads.Object_Read_Request;
                  Source_Identity : Backends.Version_Identity;
                  Destination_Identity : Backends.Version_Identity;
                  Modified_Date : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if Count
                         ("x-amz-copy-source-if-modified-since") = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-if-modified-since"),
                          Clock)
                       else (Valid => False));
                  Unmodified_Date : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if Count
                         ("x-amz-copy-source-if-unmodified-since") = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-if-unmodified-since"),
                          Clock)
                       else (Valid => False));
                  Metadata_OK : Boolean := True;
                  Owner_OK    : Boolean := False;

                  procedure Set_Metadata_Value
                    (Name : String; Target : out Optional_Metadata_Value) is
                  begin
                     if Count (Name) = 1 then
                        Target :=
                          (Is_Set => True,
                           Value => US.To_Unbounded_String
                             (Apps.Request_Header (X, Name)));
                     else
                        Target := (others => <>);
                     end if;
                  end Set_Metadata_Value;
               begin
                  if Count ("x-amz-copy-source") /= 1 or else Any_Duplicate
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A CopyObject header is missing or duplicated",
                        Target_Text);
                     return;
                  elsif Length.Kind = Backends.Known
                    and then Length.Bytes /= 0
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "CopyObject does not accept a request body",
                        Target_Text);
                     return;
                  elsif Count ("x-amz-copy-source-if-modified-since") = 1
                    and then not Modified_Date.Valid
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The copy source modified date is invalid",
                        Target_Text);
                     return;
                  elsif Count ("x-amz-copy-source-if-unmodified-since") = 1
                    and then not Unmodified_Date.Valid
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The copy source unmodified date is invalid",
                        Target_Text);
                     return;
                  elsif Source_Parsed.Status /= Requests.Target_Parsed
                    or else Source_Parsed.Kind /= Requests.Object_Target
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The copy source is invalid", Target_Text);
                     return;
                  end if;

                  if Source_Parsed.Has_Query then
                     declare
                        Source_Query : constant String :=
                          Requests.Query_String
                            (Source_Target, Source_Parsed);
                     begin
                        if Ada.Strings.Fixed.Index (Source_Query, "&") /= 0
                        then
                           raise Object_Reads.Malformed_Object_Read_Request;
                        end if;
                        Source_Read_Request := Object_Reads.Parse_Query
                          (Source_Query, Object_Reads.Get_Object);
                        if not Source_Read_Request.Has_Version_ID
                          or else Source_Read_Request.Has_Part_Number
                          or else
                            Source_Read_Request.Has_Response_Overrides
                        then
                           raise Object_Reads.Malformed_Object_Read_Request;
                        end if;
                        Copy_Options_Value.Source_Selector :=
                          To_Version_Selector
                            (True, Source_Read_Request.Version_ID);
                     exception
                        when Object_Reads.Malformed_Object_Read_Request =>
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The copy source version is invalid",
                              Target_Text);
                           return;
                     end;
                  end if;

                  if Count ("x-amz-metadata-directive") = 1
                    and then not Valid_Enumeration
                      (23, Apps.Request_Header
                         (X, "x-amz-metadata-directive"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The metadata directive is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-tagging-directive") = 1
                    and then not Valid_Enumeration
                      (24, Apps.Request_Header
                         (X, "x-amz-tagging-directive"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The tagging directive is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-checksum-algorithm") = 1 then
                     declare
                        Valid : Boolean;
                        Algorithm : constant Checksum_Algorithm :=
                          Parse_Checksum_Algorithm
                            (Apps.Request_Header
                               (X, "x-amz-checksum-algorithm"), Valid);
                     begin
                        if not Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The checksum algorithm is invalid",
                              Target_Text);
                           return;
                        end if;
                        Copy_Options_Value.Selected_Checksum := Algorithm;
                     end;
                  end if;

                  if Count ("x-amz-request-payer") = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-server-side-encryption") = 1
                    and then not Valid_Enumeration
                      (26, Apps.Request_Header
                         (X, "x-amz-server-side-encryption"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The encryption algorithm is invalid", Target_Text);
                     return;
                  elsif Count
                      ("x-amz-server-side-encryption-bucket-key-enabled") = 1
                    and then not S3.Wire_Core.Parse_Boolean
                      (Apps.Request_Header
                         (X, "x-amz-server-side-encryption-" &
                          "bucket-key-enabled")).Valid
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The bucket-key flag is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-object-lock-mode") = 1
                    and then not Valid_Enumeration
                      (40, Apps.Request_Header (X, "x-amz-object-lock-mode"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The object-lock mode is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-object-lock-legal-hold") = 1
                    and then not Valid_Enumeration
                      (42, Apps.Request_Header
                         (X, "x-amz-object-lock-legal-hold"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The legal-hold status is invalid", Target_Text);
                     return;
                  end if;

                  declare
                     Source_Match : constant String :=
                       (if Count ("x-amz-copy-source-if-match") = 1
                        then Apps.Request_Header
                          (X, "x-amz-copy-source-if-match") else "");
                     Source_None : constant String :=
                       (if Count ("x-amz-copy-source-if-none-match") = 1
                        then Apps.Request_Header
                          (X, "x-amz-copy-source-if-none-match") else "");
                     Destination_Match : constant String :=
                       (if Count ("if-match") = 1
                        then Apps.Request_Header (X, "if-match") else "");
                     Destination_None : constant String :=
                       (if Count ("if-none-match") = 1
                        then Apps.Request_Header (X, "if-none-match")
                        else "");
                  begin
                     if (Count ("x-amz-copy-source-if-match") = 1
                           and then Source_Match'Length = 0)
                       or else
                         (Count ("x-amz-copy-source-if-none-match") = 1
                          and then Source_None'Length = 0)
                       or else
                         (Count ("if-match") = 1
                          and then Destination_Match'Length = 0)
                       or else
                         (Count ("if-none-match") = 1
                          and then Destination_None'Length = 0)
                       or else not Backends.Valid_Copy_Conditions
                       ((If_Match => US.To_Unbounded_String (Source_Match),
                         If_None_Match =>
                           US.To_Unbounded_String (Source_None),
                         others => <>))
                       or else not Backends.Valid_Write_Conditions
                         ((If_Match =>
                             US.To_Unbounded_String (Destination_Match),
                           If_None_Match =>
                             US.To_Unbounded_String (Destination_None)))
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "A CopyObject entity-tag condition is invalid",
                           Target_Text);
                        return;
                     end if;
                  end;

                  declare
                     Destination_SSE_Count : constant Natural :=
                       Count
                         ("x-amz-server-side-encryption-customer-algorithm") +
                       Count ("x-amz-server-side-encryption-customer-key") +
                       Count
                         ("x-amz-server-side-encryption-customer-key-md5");
                     Source_SSE_Count : constant Natural :=
                       Count
                         ("x-amz-copy-source-server-side-encryption-" &
                          "customer-algorithm") +
                       Count
                         ("x-amz-copy-source-server-side-encryption-" &
                          "customer-key") +
                       Count
                         ("x-amz-copy-source-server-side-encryption-" &
                          "customer-key-md5");
                  begin
                     if Destination_SSE_Count not in 0 | 3
                       or else Source_SSE_Count not in 0 | 3
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The SSE-C header group is incomplete",
                           Target_Text);
                        return;
                     elsif Destination_SSE_Count = 3
                       and then
                         (Apps.Request_Header
                            (X, "x-amz-server-side-encryption-" &
                             "customer-algorithm") /= "AES256"
                          or else not S3.Wire_Core.Valid_Base64
                            (Apps.Request_Header
                               (X, "x-amz-server-side-encryption-" &
                                "customer-key"), 32)
                          or else not S3.Wire_Core.Valid_Base64
                            (Apps.Request_Header
                               (X, "x-amz-server-side-encryption-" &
                                "customer-key-md5"), 16))
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The destination SSE-C group is invalid",
                           Target_Text);
                        return;
                     elsif Source_SSE_Count = 3
                       and then
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-server-side-encryption-" &
                             "customer-algorithm") /= "AES256"
                          or else not S3.Wire_Core.Valid_Base64
                            (Apps.Request_Header
                               (X, "x-amz-copy-source-server-side-" &
                                "encryption-customer-key"), 32)
                          or else not S3.Wire_Core.Valid_Base64
                            (Apps.Request_Header
                               (X, "x-amz-copy-source-server-side-" &
                                "encryption-customer-key-md5"), 16))
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The source SSE-C group is invalid", Target_Text);
                        return;
                     end if;
                  end;

                  if Count ("x-amz-acl") = 1 then
                     declare
                        Value : constant String :=
                          Apps.Request_Header (X, "x-amz-acl");
                     begin
                        if not Valid_Enumeration (1, Value) then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The canned ACL is invalid", Target_Text);
                           return;
                        elsif Value /= "private" then
                           Send_Error
                             (X, 501, "NotImplemented",
                              "This canned ACL is not implemented",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;
                  if Count ("x-amz-storage-class") = 1 then
                     declare
                        Value : constant String :=
                          Apps.Request_Header (X, "x-amz-storage-class");
                     begin
                        if not Valid_Enumeration (27, Value) then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The storage class is invalid", Target_Text);
                           return;
                        elsif Value /= "STANDARD" then
                           Send_Error
                             (X, 501, "NotImplemented",
                              "This storage class is not implemented",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;
                  if Count ("x-amz-object-annotation-directive") = 1
                    and then not Valid_Enumeration
                      (25, Apps.Request_Header
                         (X, "x-amz-object-annotation-directive"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The annotation directive is invalid", Target_Text);
                     return;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Count ("x-amz-source-expected-bucket-owner") = 1
                    and then Apps.Request_Header
                      (X, "x-amz-source-expected-bucket-owner") /=
                        US.To_String (Auth.Principal)
                  then
                     Send_Error
                       (X, 403, "AccessDenied", "Access Denied", Target_Text);
                     return;
                  end if;

                  if Count ("x-amz-grant-full-control") > 0
                    or else Count ("x-amz-grant-read") > 0
                    or else Count ("x-amz-grant-read-acp") > 0
                    or else Count ("x-amz-grant-write-acp") > 0
                    or else Has_Encryption_Header
                    or else Count ("x-amz-request-payer") > 0
                    or else Count ("x-amz-object-lock-mode") > 0
                    or else Count
                      ("x-amz-object-lock-retain-until-date") > 0
                    or else Count ("x-amz-object-lock-legal-hold") > 0
                  then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "This modeled CopyObject member is not implemented",
                        Target_Text);
                     return;
                  end if;

                  Copy_Options_Value.Metadata_Directive :=
                    (if Count ("x-amz-metadata-directive") = 1
                       and then Apps.Request_Header
                         (X, "x-amz-metadata-directive") = "REPLACE"
                     then Backends.Replace_Metadata
                     else Backends.Copy_Metadata);
                  if Copy_Options_Value.Metadata_Directive =
                    Backends.Copy_Metadata
                    and then
                      (Count ("cache-control") > 0
                       or else Count ("content-disposition") > 0
                       or else Count ("content-encoding") > 0
                       or else Count ("content-language") > 0
                       or else Count ("content-type") > 0
                       or else Count ("expires") > 0
                       or else Has_User_Metadata_Header)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "Replacement metadata requires REPLACE",
                        Target_Text);
                     return;
                  end if;
                  Copy_Options_Value.Content_Type :=
                    (if Count ("content-type") = 1
                     then US.To_Unbounded_String
                       (Apps.Request_Header (X, "content-type"))
                     else US.To_Unbounded_String
                       ("application/octet-stream"));

                  Set_Metadata_Value
                    ("cache-control",
                     Copy_Options_Value.Metadata.Cache_Control);
                  Set_Metadata_Value
                    ("content-disposition",
                     Copy_Options_Value.Metadata.Content_Disposition);
                  Set_Metadata_Value
                    ("content-encoding",
                     Copy_Options_Value.Metadata.Content_Encoding);
                  Set_Metadata_Value
                    ("content-language",
                     Copy_Options_Value.Metadata.Content_Language);
                  Set_Metadata_Value
                    ("x-amz-website-redirect-location",
                     Copy_Options_Value.Metadata.Website_Redirect_Location);
                  if Count ("expires") = 1 then
                     declare
                        Parsed_Expires : constant
                          IMF_Dates.Metadata_Time_Result := IMF_Dates.Parse
                            (Apps.Request_Header (X, "expires"));
                     begin
                        if not Parsed_Expires.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The Expires metadata is not canonical",
                              Target_Text);
                           return;
                        end if;
                        Copy_Options_Value.Metadata.Expires :=
                          (Is_Set => True, Value => Parsed_Expires.Value);
                     end;
                  end if;
                  for Index in 1 .. Apps.Request_Header_Count (X) loop
                     declare
                        Header_Name : constant String :=
                          Apps.Request_Header_Name (X, Index);
                        Name : constant String :=
                          Ada.Characters.Handling.To_Lower (Header_Name);
                     begin
                        if Name'Length >= 11
                          and then Name (Name'First .. Name'First + 10) =
                            "x-amz-meta-"
                        then
                           if Copy_Options_Value.Metadata.User.Length =
                             Maximum_User_Metadata_Entries
                           then
                              Metadata_OK := False;
                           else
                              Copy_Options_Value.Metadata.User.Length :=
                                Copy_Options_Value.Metadata.User.Length + 1;
                              Copy_Options_Value.Metadata.User.Items
                                (Copy_Options_Value.Metadata.User.Length) :=
                                  (Key => US.To_Unbounded_String
                                     (Name (Name'First + 11 .. Name'Last)),
                                   Value => US.To_Unbounded_String
                                     (Apps.Request_Header (X, Header_Name)));
                           end if;
                        end if;
                     end;
                  end loop;
                  Metadata_OK := Metadata_OK and then Valid_Object_Metadata
                    (Copy_Options_Value.Metadata,
                     US.To_String (Copy_Options_Value.Content_Type));
                  if not Metadata_OK then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The CopyObject metadata is invalid", Target_Text);
                     return;
                  end if;

                  Copy_Options_Value.Tagging_Directive :=
                    (if Count ("x-amz-tagging-directive") = 1
                       and then Apps.Request_Header
                         (X, "x-amz-tagging-directive") = "REPLACE"
                     then Backends.Replace_Tags else Backends.Copy_Tags);
                  if Count ("x-amz-tagging") = 1
                    and then Copy_Options_Value.Tagging_Directive /=
                      Backends.Replace_Tags
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "x-amz-tagging requires REPLACE", Target_Text);
                     return;
                  elsif Count ("x-amz-tagging") = 1 then
                     begin
                        Copy_Options_Value.Tags := Tagging.Parse_Header
                          (Apps.Request_Header (X, "x-amz-tagging"));
                     exception
                        when Tagging.Malformed_Tagging_Query =>
                           Send_Error
                             (X, 400, "InvalidTag",
                              "The CopyObject tag set is invalid",
                              Target_Text);
                           return;
                     end;
                  end if;

                  if Count ("x-amz-copy-source-if-match") = 1 then
                     Copy_Options_Value.Conditions.If_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-if-match"));
                  end if;
                  if Modified_Date.Valid then
                     Copy_Options_Value.Conditions.If_Modified_Since :=
                       (Is_Set => True,
                        Value => Modified_Date.Seconds_Since_Epoch);
                  end if;
                  if Unmodified_Date.Valid then
                     Copy_Options_Value.Conditions.If_Unmodified_Since :=
                       (Is_Set => True,
                        Value => Unmodified_Date.Seconds_Since_Epoch);
                  end if;
                  if Count ("x-amz-copy-source-if-none-match") = 1 then
                     Copy_Options_Value.Conditions.If_None_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-if-none-match"));
                  end if;
                  if Count ("if-match") = 1 then
                     Copy_Options_Value.Destination_Conditions.If_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header (X, "if-match"));
                  end if;
                  if Count ("if-none-match") = 1 then
                     Copy_Options_Value.Destination_Conditions.If_None_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header (X, "if-none-match"));
                  end if;
                  Store.Copy_Object
                    (Requests.Bucket_Name (Source_Target, Source_Parsed),
                     Requests.Object_Key (Source_Target, Source_Parsed),
                     Bucket, Key, Copy_Options_Value,
                     Apps.Cancellation (X), Apps.Deadline (X), Info,
                     Source_Identity, Destination_Identity, Result);
                  if Result = Success then
                     if Source_Identity.Has_Version_ID then
                        Apps.Set_Header
                          (X, "x-amz-copy-source-version-id",
                           (if Source_Identity.Is_Null_Version then "null"
                            else US.To_String (Source_Identity.Version_ID)));
                     end if;
                     if Destination_Identity.Has_Version_ID then
                        Apps.Set_Header
                          (X, "x-amz-version-id",
                           (if Destination_Identity.Is_Null_Version
                            then "null"
                            else US.To_String
                              (Destination_Identity.Version_ID)));
                     end if;
                     Apps.Respond
                       (X, 200, "application/xml",
                        Copy_Result_XML ("CopyObjectResult", Info));
                  elsif Result in Source_Bucket_Not_Found | Source_Not_Found
                  then
                     Send_Backend_Error
                       (X, Result, False, Source_Target);
                  else
                     --  The only ordinary Not_Found result is the
                     --  destination bucket disappearing before publication.
                     Send_Backend_Error
                       (X, Result, Result = Not_Found, Target_Text);
                  end if;
               end;

            when Put_Object =>
               declare
                  function Count (Name : String) return Natural is
                    (Apps.Request_Header_Count (X, Name));

                  function Duplicate_User_Metadata return Boolean is
                  begin
                     for Index in 1 .. Apps.Request_Header_Count (X) loop
                        declare
                           Name : constant String :=
                             Ada.Characters.Handling.To_Lower
                               (Apps.Request_Header_Name (X, Index));
                        begin
                           if Name'Length >= 11
                             and then Name (Name'First .. Name'First + 10) =
                               "x-amz-meta-"
                             and then Count (Name) > 1
                           then
                              return True;
                           end if;
                        end;
                     end loop;
                     return False;
                  end Duplicate_User_Metadata;

                  function Any_Duplicate return Boolean is
                    (Count ("x-amz-acl") > 1
                     or else Count ("cache-control") > 1
                     or else Count ("content-disposition") > 1
                     or else Count ("content-encoding") > 1
                     or else Count ("content-language") > 1
                     or else Count ("content-md5") > 1
                     or else Count ("content-type") > 1
                     or else Count ("x-amz-sdk-checksum-algorithm") > 1
                     or else Checksum_Value_Header_Count > 1
                     or else Count ("x-amz-trailer") > 1
                     or else Count ("expires") > 1
                     or else Count ("if-match") > 1
                     or else Count ("if-none-match") > 1
                     or else Count ("x-amz-grant-full-control") > 1
                     or else Count ("x-amz-grant-read") > 1
                     or else Count ("x-amz-grant-read-acp") > 1
                     or else Count ("x-amz-grant-write-acp") > 1
                     or else Count ("x-amz-write-offset-bytes") > 1
                     or else Count ("x-amz-server-side-encryption") > 1
                     or else Count ("x-amz-storage-class") > 1
                     or else Count
                       ("x-amz-website-redirect-location") > 1
                     or else Count
                       ("x-amz-server-side-encryption-customer-algorithm") >
                         1
                     or else Count
                       ("x-amz-server-side-encryption-customer-key") > 1
                     or else Count
                       ("x-amz-server-side-encryption-customer-key-md5") > 1
                     or else Count
                       ("x-amz-server-side-encryption-aws-kms-key-id") > 1
                     or else Count
                       ("x-amz-server-side-encryption-context") > 1
                     or else Count
                       ("x-amz-server-side-encryption-bucket-key-enabled") >
                         1
                     or else Count ("x-amz-request-payer") > 1
                     or else Count ("x-amz-tagging") > 1
                     or else Count ("x-amz-object-lock-mode") > 1
                     or else Count
                       ("x-amz-object-lock-retain-until-date") > 1
                     or else Count
                       ("x-amz-object-lock-legal-hold") > 1
                     or else Count ("x-amz-expected-bucket-owner") > 1
                     or else Duplicate_User_Metadata);

                  function Valid_Enumeration
                    (Member : Positive; Value : String) return Boolean
                  is
                     Input : constant Model.Shape_Index := Model.Shape_Index
                       (Model.Input_Shape (Model.Put_Object_Operation));
                     Shape : constant Model.Shape_Index :=
                       Model.Member_Shape (Input, Member);
                  begin
                     for Index in 1 .. Model.Enumeration_Count (Shape) loop
                        if Value = Model.Enumeration_Value (Shape, Index) then
                           return True;
                        end if;
                     end loop;
                     return False;
                  end Valid_Enumeration;

                  Options : Put_Options := Default_Put_Options;
                  Conditions : Write_Conditions := Default_Write_Conditions;
                  Selected : Checksum_Algorithm := Checksum_CRC64NVME;
                  Verify_Checksum : Boolean := False;
                  Trailer_Checksum : Boolean := False;
                  Supplied_Checksum : US.Unbounded_String;
                  Metadata_OK : Boolean := True;
                  Owner_OK : Boolean := False;
                  Encoding_OK : Boolean := True;
                  AWS_Chunked_Encoding : Boolean := False;

                  function Valid_Content_Coding (Value : String)
                    return Boolean
                  is
                  begin
                     if Value'Length = 0 then
                        return False;
                     end if;
                     for Item of Value loop
                        if not (Item in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
                                or else Item in
                                  '!' | '#' | '$' | '%' | '&' | ''' | '*' |
                                  '+' | '-' | '.' | '^' | '_' | '`' | '|' |
                                  '~')
                        then
                           return False;
                        end if;
                     end loop;
                     return True;
                  end Valid_Content_Coding;

                  procedure Parse_Content_Encoding is
                  begin
                     if Count ("content-encoding") = 0 then
                        return;
                     end if;
                     declare
                        Value : constant String :=
                          Apps.Request_Header (X, "content-encoding");
                        Cursor : Integer := Value'First;
                     begin
                        if Value'Length = 0 then
                           Encoding_OK := False;
                           return;
                        end if;
                        while Cursor <= Value'Last loop
                           declare
                              Comma : constant Natural :=
                                Ada.Strings.Fixed.Index
                                  (Value, ",", From => Cursor);
                              Last : constant Integer :=
                                (if Comma = 0 then Value'Last
                                 else Integer (Comma) - 1);
                              Token : constant String := Ada.Strings.Fixed.Trim
                                (Value (Cursor .. Last), Ada.Strings.Both);
                           begin
                              if not Valid_Content_Coding (Token) then
                                 Encoding_OK := False;
                                 return;
                              elsif Ada.Characters.Handling.To_Lower (Token) =
                                "aws-chunked"
                              then
                                 if AWS_Chunked_Encoding then
                                    Encoding_OK := False;
                                    return;
                                 end if;
                                 AWS_Chunked_Encoding := True;
                              end if;
                              exit when Comma = 0;
                              Cursor := Integer (Comma) + 1;
                              if Cursor > Value'Last then
                                 Encoding_OK := False;
                                 return;
                              end if;
                           end;
                        end loop;
                     end;
                  end Parse_Content_Encoding;

                  procedure Set_Metadata_Value
                    (Name : String; Target : out Optional_Metadata_Value) is
                  begin
                     if Count (Name) = 1 then
                        Target :=
                          (Is_Set => True,
                           Value => US.To_Unbounded_String
                             (Apps.Request_Header (X, Name)));
                     else
                        Target := (others => <>);
                     end if;
                  end Set_Metadata_Value;
               begin
                  if Any_Duplicate then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A PutObject header is duplicated", Target_Text);
                     return;
                  elsif Count ("content-md5") = 1
                    and then not S3.Wire_Core.Valid_Base64
                      (Apps.Request_Header (X, "content-md5"), 16)
                  then
                     Send_Error
                       (X, 400, "InvalidDigest",
                        "The Content-MD5 is invalid", Target_Text);
                     return;
                  end if;

                  if Count ("x-amz-sdk-checksum-algorithm") = 1 then
                     declare
                        Valid : Boolean;
                        Parsed : constant Checksum_Algorithm :=
                          Parse_Checksum_Algorithm
                            (Apps.Request_Header
                               (X, "x-amz-sdk-checksum-algorithm"), Valid);
                     begin
                        if not Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The checksum algorithm is invalid",
                              Target_Text);
                           return;
                        end if;
                        Selected := Parsed;
                     end;
                  end if;

                  if Checksum_Value_Header_Count = 1 then
                     if Count ("x-amz-trailer") > 0 then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "A checksum header and trailer cannot be combined",
                           Target_Text);
                        return;
                     end if;
                     if Count ("x-amz-sdk-checksum-algorithm") = 1
                       and then Selected /= Checksum_Value_Algorithm
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The checksum algorithm and value header differ",
                           Target_Text);
                        return;
                     end if;
                     Selected := Checksum_Value_Algorithm;
                     Supplied_Checksum := US.To_Unbounded_String
                       (Apps.Request_Header
                          (X, Checksum_Header_Name (Selected)));
                     if not Checksum_Engine.Valid_Digest
                       (US.To_String (Supplied_Checksum), Selected)
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The checksum value is invalid", Target_Text);
                        return;
                     end if;
                     Verify_Checksum := True;
                  elsif Count ("x-amz-trailer") = 1 then
                     if Count ("x-amz-sdk-checksum-algorithm") /= 1
                       or else Ada.Characters.Handling.To_Lower
                         (Apps.Request_Header (X, "x-amz-trailer")) /=
                           Checksum_Header_Name (Selected)
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The checksum trailer declaration is invalid",
                           Target_Text);
                        return;
                     end if;
                     Verify_Checksum := True;
                     Trailer_Checksum := True;
                  elsif Count ("x-amz-sdk-checksum-algorithm") = 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The selected checksum value is missing", Target_Text);
                     return;
                  end if;

                  Parse_Content_Encoding;
                  if not Encoding_OK then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The content encoding is invalid", Target_Text);
                     return;
                  elsif AWS_Chunked_Encoding then
                     if Count ("x-amz-decoded-content-length") /= 1
                       or else not Trailer_Checksum
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "aws-chunked requires one decoded length and " &
                           "checksum trailer", Target_Text);
                        return;
                     end if;
                     declare
                        Parsed : constant S3.Wire_Core.Byte_Count_Result :=
                          S3.Wire_Core.Parse_Byte_Count
                            (Apps.Request_Header
                               (X, "x-amz-decoded-content-length"));
                     begin
                        if not Parsed.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The decoded content length is invalid",
                              Target_Text);
                           return;
                        elsif Parsed.Value > 5 * 1_024 * 1_024 * 1_024 then
                           Send_Error
                             (X, 400, "EntityTooLarge",
                              "Your proposed upload exceeds the maximum " &
                              "allowed size", Target_Text);
                           return;
                        end if;
                     end;
                     Send_Error
                       (X, 501, "NotImplemented",
                        "aws-chunked payloads are not implemented",
                        Target_Text);
                     return;
                  elsif Count ("x-amz-decoded-content-length") > 0 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A decoded content length requires aws-chunked",
                        Target_Text);
                     return;
                  elsif Length.Kind = Backends.Known
                    and then Length.Bytes > 5 * 1_024 * 1_024 * 1_024
                  then
                     Send_Error
                       (X, 400, "EntityTooLarge",
                        "Your proposed upload exceeds the maximum allowed " &
                        "size", Target_Text);
                     return;
                  end if;

                  if Count ("x-amz-storage-class") = 1 then
                     declare
                        Value : constant String :=
                          Apps.Request_Header (X, "x-amz-storage-class");
                     begin
                        if not Valid_Enumeration (33, Value) then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The storage class is invalid", Target_Text);
                           return;
                        elsif Value /= "STANDARD" then
                           Send_Error
                             (X, 501, "NotImplemented",
                              "This storage class is not implemented",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;
                  if Count ("x-amz-acl") = 1
                    and then not Valid_Enumeration
                      (1, Apps.Request_Header (X, "x-amz-acl"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The canned ACL is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-request-payer") = 1
                    and then not Valid_Enumeration
                      (41, Apps.Request_Header (X, "x-amz-request-payer"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-server-side-encryption") = 1
                    and then not Valid_Enumeration
                      (32, Apps.Request_Header
                         (X, "x-amz-server-side-encryption"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The server-side encryption value is invalid",
                        Target_Text);
                     return;
                  elsif Count ("x-amz-object-lock-mode") = 1
                    and then not Valid_Enumeration
                      (43, Apps.Request_Header (X, "x-amz-object-lock-mode"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The object lock mode is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-object-lock-legal-hold") = 1
                    and then not Valid_Enumeration
                      (45, Apps.Request_Header
                         (X, "x-amz-object-lock-legal-hold"))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The object lock legal hold is invalid", Target_Text);
                     return;
                  elsif Count ("x-amz-acl") > 0
                    or else Count ("x-amz-grant-full-control") > 0
                    or else Count ("x-amz-grant-read") > 0
                    or else Count ("x-amz-grant-read-acp") > 0
                    or else Count ("x-amz-grant-write-acp") > 0
                    or else Count ("x-amz-write-offset-bytes") > 0
                    or else Has_Encryption_Header
                    or else Count ("x-amz-request-payer") > 0
                    or else Count ("x-amz-object-lock-mode") > 0
                    or else Count
                      ("x-amz-object-lock-retain-until-date") > 0
                    or else Count ("x-amz-object-lock-legal-hold") > 0
                  then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "This modeled PutObject member is not implemented",
                        Target_Text);
                     return;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  end if;

                  if Count ("content-type") = 1 then
                     Options.Content_Type := US.To_Unbounded_String
                       (Apps.Request_Header (X, "content-type"));
                  end if;
                  Set_Metadata_Value
                    ("cache-control", Options.Metadata.Cache_Control);
                  Set_Metadata_Value
                    ("content-disposition",
                     Options.Metadata.Content_Disposition);
                  Set_Metadata_Value
                    ("content-encoding", Options.Metadata.Content_Encoding);
                  Set_Metadata_Value
                    ("content-language", Options.Metadata.Content_Language);
                  Set_Metadata_Value
                    ("x-amz-website-redirect-location",
                     Options.Metadata.Website_Redirect_Location);
                  if Count ("expires") = 1 then
                     declare
                        Parsed_Expires : constant
                          IMF_Dates.Metadata_Time_Result := IMF_Dates.Parse
                            (Apps.Request_Header (X, "expires"));
                     begin
                        if not Parsed_Expires.Valid then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The Expires metadata is not canonical",
                              Target_Text);
                           return;
                        end if;
                        Options.Metadata.Expires :=
                          (Is_Set => True, Value => Parsed_Expires.Value);
                     end;
                  end if;
                  for Index in 1 .. Apps.Request_Header_Count (X) loop
                     declare
                        Header_Name : constant String :=
                          Apps.Request_Header_Name (X, Index);
                        Name : constant String :=
                          Ada.Characters.Handling.To_Lower (Header_Name);
                     begin
                        if Name'Length >= 11
                          and then Name (Name'First .. Name'First + 10) =
                            "x-amz-meta-"
                        then
                           if Options.Metadata.User.Length =
                             Maximum_User_Metadata_Entries
                           then
                              Metadata_OK := False;
                           else
                              Options.Metadata.User.Length :=
                                Options.Metadata.User.Length + 1;
                              Options.Metadata.User.Items
                                (Options.Metadata.User.Length) :=
                                  (Key => US.To_Unbounded_String
                                     (Name (Name'First + 11 .. Name'Last)),
                                   Value => US.To_Unbounded_String
                                     (Apps.Request_Header (X, Header_Name)));
                           end if;
                        end if;
                     end;
                  end loop;
                  Metadata_OK := Metadata_OK and then Valid_Object_Metadata
                    (Options.Metadata, US.To_String (Options.Content_Type));
                  if not Metadata_OK then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The PutObject metadata is invalid", Target_Text);
                     return;
                  end if;
                  if Count ("x-amz-tagging") = 1 then
                     begin
                        Options.Tags := Tagging.Parse_Header
                          (Apps.Request_Header (X, "x-amz-tagging"));
                     exception
                        when Tagging.Malformed_Tagging_Query =>
                           Send_Error
                             (X, 400, "InvalidTag",
                              "The PutObject tag set is invalid", Target_Text);
                           return;
                     end;
                  end if;

                  if Count ("if-match") = 1 then
                     Conditions.If_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-match"));
                  end if;
                  if Count ("if-none-match") = 1 then
                     Conditions.If_None_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-none-match"));
                  end if;
                  if (Count ("if-match") = 1
                      and then Apps.Request_Header (X, "if-match") = "")
                    or else
                      (Count ("if-none-match") = 1
                       and then Apps.Request_Header (X, "if-none-match") = "")
                    or else not Backends.Valid_Write_Conditions (Conditions)
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A PutObject entity-tag condition is invalid",
                        Target_Text);
                     return;
                  end if;

                  Options.Checksum :=
                    (Algorithm => Selected,
                     Method    => Full_Object_Checksum,
                     Value     => US.Null_Unbounded_String);
                  declare
                     Source : Request_IO.Request_Source
                       (Checksum_Engine.Algorithm_Value (Selected)) :=
                         (Checksum_Kind =>
                            Checksum_Engine.Algorithm_Value (Selected),
                          Length_Value  => Length,
                          Expected_Hash => Auth.Payload_Hash,
                          Check_Hash    =>
                            US.To_String (Auth.Payload_Hash) /=
                              S3.SigV4.Unsigned_Payload,
                          Hash      => GNAT.SHA256.Initial_Context,
                          Check_Content_MD5 => Count ("content-md5") = 1,
                          Expected_Content_MD5 =>
                            (if Count ("content-md5") = 1
                             then US.To_Unbounded_String
                               (Apps.Request_Header (X, "content-md5"))
                             else US.Null_Unbounded_String),
                          Check_Body_Checksum => Verify_Checksum,
                          Checksum_From_Trailer => Trailer_Checksum,
                          Reject_Unexpected_Trailers => True,
                          Expected_Body_Checksum => Supplied_Checksum,
                          Observed  => 0,
                          Maximum   => 5 * 1_024 * 1_024 * 1_024,
                          Completed => False,
                          others    => <>);
                  begin
                     Store.Put_Object
                       (Bucket, Key, Source, Options, Apps.Cancellation (X),
                        Apps.Deadline (X), Info, Publication_Identity, Result,
                        Conditions);
                     if Result = Success and then not Source.Completed then
                        raise Program_Error with
                          "backend committed before validating the whole body";
                     end if;
                  end;
               end;
               if Result = Success then
                  Apps.Set_Header
                    (X, "ETag", '"' & US.To_String (Info.Entity_Tag) & '"');
                  Set_Checksum_Headers (X, Info.Checksum);
                  if Publication_Identity.Has_Version_ID then
                     Apps.Set_Header
                       (X, "x-amz-version-id",
                        (if Publication_Identity.Is_Null_Version then "null"
                         else US.To_String
                           (Publication_Identity.Version_ID)));
                  end if;
                  Apps.Set_Header
                    (X, "x-amz-object-size", Decimal (Info.Size));
                  Apps.Respond (X, 200, "", "");
               else
                  --  Put_Object can report Not_Found only for its bucket;
                  --  the destination key need not exist before a PUT.
                  Send_Backend_Error (X, Result, True, Target_Text);
               end if;

            when Put_Object_Tagging | Get_Object_Tagging |
                 Delete_Object_Tagging =>
               declare
                  Owner_OK : Boolean := False;
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
                  Kind_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-type");
                  Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-sdk-checksum-algorithm");
                  SDK_Algorithm : constant
                    Checksum_Policy.Algorithm_Parse_Result :=
                      (if Algorithm_Count = 1
                       then Checksum_Policy.Parse_Algorithm
                         (Apps.Request_Header
                            (X, "x-amz-sdk-checksum-algorithm"))
                       else (Valid => False));
                  Identity : Backends.Version_Identity;

                  procedure Set_Version_Header is
                  begin
                     if Identity.Has_Version_ID then
                        Apps.Set_Header
                          (X, "x-amz-version-id",
                           (if Identity.Is_Null_Version
                            then "null"
                            else US.To_String (Identity.Version_ID)));
                     end if;
                  end Set_Version_Header;
               begin
                  if Payer_Count > 1 or else Algorithm_Count > 1
                    or else MD5_Count > 1 or else Kind_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "An object tagging request header is duplicated",
                        Target_Text);
                     return;
                  end if;
                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer is invalid", Target_Text);
                     return;
                  elsif Payer_Count = 1 then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Requester Pays is not implemented", Target_Text);
                     return;
                  elsif Algorithm_Count = 1 and then not SDK_Algorithm.Valid
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The SDK checksum algorithm is invalid", Target_Text);
                     return;
                  elsif Algorithm_Count = 1 or else Has_Checksum_Header then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Object tagging SDK checksums are not implemented",
                        Target_Text);
                     return;
                  end if;

                  if Operation = Put_Object_Tagging then
                     if MD5_Count /= 1 or else Length.Kind /= Backends.Known
                       or else Length.Bytes > Maximum_Object_Tagging_Body
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "PutObjectTagging requires bounded " &
                           "Content-Length " &
                           "and Content-MD5", Target_Text);
                        return;
                     elsif Kind_Count = 1
                       and then not Valid_Tagging_Content_Type
                         (Apps.Request_Header (X, "content-type"))
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "PutObjectTagging requires application/xml",
                           Target_Text);
                        return;
                     end if;
                     declare
                        Source : Request_IO.Request_Source :=
                          (Checksum_Kind => S3.Core.CRC64NVME,
                           Length_Value  => Length,
                           Expected_Hash => Auth.Payload_Hash,
                           Check_Hash    =>
                             US.To_String (Auth.Payload_Hash) /=
                               S3.SigV4.Unsigned_Payload,
                           Hash      => GNAT.SHA256.Initial_Context,
                           Observed  => 0,
                           Maximum   => Maximum_Object_Tagging_Body,
                           Completed => False,
                           others    => <>);
                        Document : constant String := Read_Document (Source);
                     begin
                        if Content_MD5 (Document) /=
                          Apps.Request_Header (X, "content-md5")
                        then
                           Send_Error
                             (X, 400, "BadDigest",
                              "The Content-MD5 did not match the request body",
                              Target_Text);
                           return;
                        end if;
                        declare
                           Tags : constant Object_Tag_Set := Tagging.Parse
                             (Document,
                              (Maximum_Document_Bytes =>
                                 Tagging.Maximum_Document_Bytes,
                               Maximum_Depth      => 5,
                               Maximum_Elements   => 34,
                               Maximum_Text_Bytes =>
                                 Tagging.Maximum_Document_Bytes));
                        begin
                           Store.Put_Object_Tags
                             (Bucket, Key, Tags, Apps.Cancellation (X),
                              Apps.Deadline (X), Identity, Result,
                              Selector => Tagging_Version_Selector);
                        end;
                     exception
                        when Tagging.Malformed_Tagging =>
                           Send_Error
                             (X, 400, "MalformedXML",
                              "The XML provided did not validate against " &
                              "the object tagging schema", Target_Text);
                           return;
                     end;
                     if Result = Success then
                        Set_Version_Header;
                        Apps.Respond (X, 200, "", "");
                     else
                        Send_Backend_Error (X, Result, False, Target_Text);
                     end if;
                  elsif Operation = Get_Object_Tagging then
                     declare
                        Tags : Object_Tag_Set;
                     begin
                        Store.Get_Object_Tags
                          (Bucket, Key, Apps.Cancellation (X),
                           Apps.Deadline (X), Tags, Identity, Result,
                           Selector => Tagging_Version_Selector);
                        if Result = Success then
                           Set_Version_Header;
                           Apps.Respond
                             (X, 200, "application/xml",
                              Tagging.Serialize (Tags));
                        else
                           Send_Backend_Error
                             (X, Result, False, Target_Text);
                        end if;
                     end;
                  else
                     Store.Delete_Object_Tags
                       (Bucket, Key, Apps.Cancellation (X), Apps.Deadline (X),
                        Identity, Result,
                        Selector => Tagging_Version_Selector);
                     if Result = Success then
                        Set_Version_Header;
                        Apps.Respond (X, 204, "", "");
                     else
                        Send_Backend_Error (X, Result, False, Target_Text);
                     end if;
                  end if;
               end;

            when Get_Object_Attributes =>
               declare
                  Selection_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-object-attributes");
                  Max_Parts_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-max-parts");
                  Marker_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-part-number-marker");
                  SSE_Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-" &
                       "algorithm");
                  SSE_Key_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key");
                  SSE_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key-md5");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Owner_OK : Boolean := False;
                  Options : Backends.Object_Attribute_Options :=
                    (After => 0, Maximum => Backends.List_Limit'Last);
                  Snapshot : Backends.Object_Attribute_Snapshot;
                  Selection : Attributes.Attribute_Selection;
                  Valid_Request : Boolean := True;
               begin
                  if Selection_Count /= 1
                    or else Max_Parts_Count > 1
                    or else Marker_Count > 1
                    or else SSE_Algorithm_Count > 1
                    or else SSE_Key_Count > 1
                    or else SSE_MD5_Count > 1
                    or else Payer_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A GetObjectAttributes request header is missing or " &
                        "duplicated", Target_Text);
                     return;
                  end if;

                  begin
                     Selection := Attributes.Parse_Selection
                       (Apps.Request_Header
                          (X, "x-amz-object-attributes"));
                  exception
                     when Attributes.Malformed_Attributes =>
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The requested object attributes are invalid",
                           Target_Text);
                        Valid_Request := False;
                  end;
                  if not Valid_Request then
                     return;
                  end if;

                  if Max_Parts_Count = 1 then
                     declare
                        Parsed_Max : constant S3.Wire_Core.Natural_Result :=
                          S3.Wire_Core.Parse_Natural
                            (Apps.Request_Header (X, "x-amz-max-parts"));
                     begin
                        if not Parsed_Max.Valid
                          or else Parsed_Max.Value >
                            Backends.List_Limit'Last
                        then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The maximum part count is invalid",
                              Target_Text);
                           return;
                        end if;
                        Options.Maximum :=
                          Backends.List_Limit (Parsed_Max.Value);
                     end;
                  end if;
                  if Marker_Count = 1 then
                     declare
                        Parsed_Marker : constant
                          S3.Wire_Core.Natural_Result :=
                            S3.Wire_Core.Parse_Natural
                              (Apps.Request_Header
                                 (X, "x-amz-part-number-marker"));
                     begin
                        if not Parsed_Marker.Valid
                          or else Parsed_Marker.Value >
                            Backends.Multipart_Part_Marker'Last
                        then
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The part number marker is invalid",
                              Target_Text);
                           return;
                        end if;
                        Options.After := Backends.Multipart_Part_Marker
                          (Parsed_Marker.Value);
                     end;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Payer_Count = 1 then
                     if Apps.Request_Header
                       (X, "x-amz-request-payer") /= "requester"
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The request payer header is invalid", Target_Text);
                     else
                        Send_Error
                          (X, 501, "NotImplemented",
                           "Requester-pays GetObjectAttributes is not " &
                           "implemented", Target_Text);
                     end if;
                     return;
                  elsif SSE_Algorithm_Count = 1
                    or else SSE_Key_Count = 1
                    or else SSE_MD5_Count = 1
                  then
                     if SSE_Algorithm_Count /= 1
                       or else SSE_Key_Count /= 1
                       or else SSE_MD5_Count /= 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The SSE-C header group is incomplete",
                           Target_Text);
                     elsif Apps.Request_Header
                       (X, "x-amz-server-side-encryption-customer-" &
                          "algorithm") /= "AES256"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The SSE-C algorithm is invalid", Target_Text);
                     elsif Apps.Request_Scheme (X) /=
                       Flyology.HTTP.Secure_HTTPS
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "SSE-C requests require HTTPS", Target_Text);
                     elsif not Checksums.Valid_SSE_C_Key_MD5
                       (Apps.Request_Header
                          (X,
                           "x-amz-server-side-encryption-customer-key"),
                        Apps.Request_Header
                          (X, "x-amz-server-side-encryption-customer-" &
                           "key-md5"))
                     then
                        Send_Error
                          (X, 400, "InvalidDigest",
                           "The SSE-C key or digest is invalid", Target_Text);
                     else
                        Send_Error
                          (X, 501, "NotImplemented",
                           "SSE-C GetObjectAttributes is not implemented",
                           Target_Text);
                     end if;
                     return;
                  elsif Has_Encryption_Header then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "The GetObjectAttributes encryption header is not " &
                        "implemented", Target_Text);
                     return;
                  end if;

                  Store.Get_Object_Attributes
                    (Bucket, Key, Options, Apps.Cancellation (X),
                     Apps.Deadline (X), Snapshot, Result,
                     Selector => Attributes_Version_Selector);
                  if Result /= Success then
                     Send_Backend_Error (X, Result, False, Target_Text);
                     return;
                  end if;
                  declare
                     Response : Attributes.Get_Object_Attributes_Result;
                  begin
                     if Selection.Entity_Tag then
                        Response.Has_Entity_Tag := True;
                        Response.Entity_Tag := Snapshot.Info.Entity_Tag;
                     end if;
                     if Selection.Object_Size then
                        Response.Object_Size :=
                          (Is_Set => True, Value => Snapshot.Info.Size);
                     end if;
                     if Selection.Checksum
                       and then Snapshot.Info.Checksum.Algorithm /=
                         No_Checksum
                     then
                        Response.Has_Checksum := True;
                        Response.Checksum :=
                          Attribute_Checksum (Snapshot.Info.Checksum);
                     end if;
                     if Selection.Object_Parts and then Snapshot.Is_Multipart
                     then
                        Response.Has_Object_Parts := True;
                        Response.Object_Parts.Total_Parts_Count :=
                          (Is_Set => True, Value => Snapshot.Total_Parts);
                        Response.Object_Parts.Part_Number_Marker :=
                          (Is_Set => True, Value => Natural (Options.After));
                        Response.Object_Parts.Max_Parts :=
                          (Is_Set => True, Value => Natural (Options.Maximum));
                        Response.Object_Parts.Has_Is_Truncated := True;
                        Response.Object_Parts.Is_Truncated :=
                          Snapshot.Is_Truncated;
                        if Snapshot.Is_Truncated then
                           Response.Object_Parts.Next_Part_Number_Marker :=
                             (Is_Set => True,
                              Value => Natural (Snapshot.Next_After));
                        end if;
                        for Part of Snapshot.Parts loop
                           Response.Object_Parts.Parts.Append
                             (Attributes.Object_Part'
                                (Number =>
                                   (Is_Set => True,
                                    Value => Natural (Part.Number)),
                                 Size =>
                                   (Is_Set => True, Value => Part.Size),
                                 Checksums =>
                                   Attribute_Checksum
                                     (Part.Checksum,
                                      Include_Kind => False)));
                        end loop;
                     end if;
                     Apps.Set_Header
                       (X, "Last-Modified",
                        HTTP_Last_Modified (Snapshot.Info.Modified));
                     if US.Length (Snapshot.Info.Version) > 0 then
                        Apps.Set_Header
                          (X, "x-amz-version-id",
                           US.To_String (Snapshot.Info.Version));
                     end if;
                     Apps.Respond
                       (X, 200, "application/xml",
                        Attributes.Serialize_Result (Response));
                  end;
               end;

            when Head_Object =>
               declare
                  If_Match_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-match");
                  If_Modified_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-modified-since");
                  If_None_Match_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-none-match");
                  If_Unmodified_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-unmodified-since");
                  Range_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "range");
                  SSE_Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-algorithm");
                  SSE_Key_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key");
                  SSE_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key-md5");
                  Server_Encryption_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Checksum_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-mode");
                  Modified_Date : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if If_Modified_Count = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Apps.Request_Header (X, "if-modified-since"), Clock)
                       else (Valid => False));
                  Unmodified_Date : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if If_Unmodified_Count = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Apps.Request_Header (X, "if-unmodified-since"),
                          Clock)
                       else (Valid => False));
                  Conditions : Backends.Read_Conditions :=
                    Backends.Default_Read_Conditions;
                  Requested : Byte_Range := Whole_Object;
                  Has_Range : Boolean := False;
                  Valid_SSE_C : Boolean := False;
                  Owner_OK : Boolean := False;
                  Snapshot : Backends.Object_Attribute_Snapshot;
                  Selected_Part : constant Backends.Multipart_Part_Marker :=
                    (if Object_Read_Request.Has_Part_Number
                     then Backends.Multipart_Part_Marker
                       (Object_Read_Request.Part_Number)
                     else 0);

                  function Valid_Response_Field
                    (Present : Boolean;
                     Value   : US.Unbounded_String) return Boolean
                  is
                  begin
                     if not Present then
                        return True;
                     end if;
                     for Item of US.To_String (Value) loop
                        if Character'Pos (Item) < 32
                          or else Character'Pos (Item) = 127
                        then
                           return False;
                        end if;
                     end loop;
                     return True;
                  end Valid_Response_Field;

                  function Valid_Response_Overrides return Boolean is
                    (Valid_Response_Field
                       (Object_Read_Request.Has_Response_Cache_Control,
                        Object_Read_Request.Response_Cache_Control)
                     and then Valid_Response_Field
                       (Object_Read_Request.Has_Response_Content_Disposition,
                        Object_Read_Request.Response_Content_Disposition)
                     and then Valid_Response_Field
                       (Object_Read_Request.Has_Response_Content_Encoding,
                        Object_Read_Request.Response_Content_Encoding)
                     and then Valid_Response_Field
                       (Object_Read_Request.Has_Response_Content_Language,
                        Object_Read_Request.Response_Content_Language)
                     and then Valid_Response_Field
                       (Object_Read_Request.Has_Response_Content_Type,
                        Object_Read_Request.Response_Content_Type)
                     and then Valid_Response_Field
                       (Object_Read_Request.Has_Response_Expires,
                        Object_Read_Request.Response_Expires));

                  procedure Set_Common_Headers is
                  begin
                     Apps.Set_Header (X, "Accept-Ranges", "bytes");
                     Apps.Set_Header
                       (X, "ETag",
                        '"' & US.To_String (Info.Entity_Tag) & '"');
                     Apps.Set_Header
                       (X, "Last-Modified",
                        HTTP_Last_Modified (Info.Modified));
                     Apps.Set_Header
                       (X, "x-amz-version-id",
                        (if US.Length (Info.Version) > 0
                         then US.To_String (Info.Version) else "null"));
                     --  A multipart Range without partNumber cannot be
                     --  mapped to retained part boundaries through one
                     --  atomic backend snapshot. Do not mislabel the whole
                     --  object checksum as a selected-part checksum.
                     if Checksum_Count = 1
                       and then not
                         (Has_Range and then Snapshot.Is_Multipart
                          and then not
                            Object_Read_Request.Has_Part_Number)
                     then
                        Set_Checksum_Headers (X, Info.Checksum);
                     end if;
                  end Set_Common_Headers;

                  procedure Set_Response_Overrides is
                     procedure Set_One
                       (Name : String;
                        Present : Boolean;
                        Value : US.Unbounded_String) is
                     begin
                        if Present then
                           Apps.Set_Header (X, Name, US.To_String (Value));
                        end if;
                     end Set_One;
                  begin
                     Set_One
                       ("Cache-Control",
                        Object_Read_Request.Has_Response_Cache_Control,
                        Object_Read_Request.Response_Cache_Control);
                     Set_One
                       ("Content-Disposition",
                        Object_Read_Request.Has_Response_Content_Disposition,
                        Object_Read_Request.Response_Content_Disposition);
                     Set_One
                       ("Content-Encoding",
                        Object_Read_Request.Has_Response_Content_Encoding,
                        Object_Read_Request.Response_Content_Encoding);
                     Set_One
                       ("Content-Language",
                        Object_Read_Request.Has_Response_Content_Language,
                        Object_Read_Request.Response_Content_Language);
                     Set_One
                       ("Expires", Object_Read_Request.Has_Response_Expires,
                        Object_Read_Request.Response_Expires);
                  end Set_Response_Overrides;
               begin
                  if If_Match_Count > 1
                    or else If_Modified_Count > 1
                    or else If_None_Match_Count > 1
                    or else If_Unmodified_Count > 1
                    or else Range_Count > 1
                    or else SSE_Algorithm_Count > 1
                    or else SSE_Key_Count > 1
                    or else SSE_MD5_Count > 1
                    or else Server_Encryption_Count > 1
                    or else Payer_Count > 1
                    or else Checksum_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A HeadObject request header is duplicated",
                        Target_Text);
                     return;
                  elsif (If_Match_Count = 1
                         and then Apps.Request_Header
                           (X, "if-match")'Length = 0)
                    or else (If_Modified_Count = 1
                             and then Apps.Request_Header
                               (X, "if-modified-since")'Length = 0)
                    or else (If_None_Match_Count = 1
                             and then Apps.Request_Header
                               (X, "if-none-match")'Length = 0)
                    or else (If_Unmodified_Count = 1
                             and then Apps.Request_Header
                               (X, "if-unmodified-since")'Length = 0)
                    or else (Range_Count = 1
                             and then Apps.Request_Header
                               (X, "range")'Length = 0)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A HeadObject request header is empty", Target_Text);
                     return;
                  elsif (If_Match_Count = 1
                         and then not
                           Backends.Valid_Read_Entity_Tag_Condition
                             (Apps.Request_Header (X, "if-match")))
                    or else (If_None_Match_Count = 1
                             and then not
                               Backends.Valid_Read_Entity_Tag_Condition
                                 (Apps.Request_Header (X, "if-none-match")))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A HeadObject entity-tag condition is malformed",
                        Target_Text);
                     return;
                  elsif (If_Modified_Count = 1
                         and then not Modified_Date.Valid)
                    or else (If_Unmodified_Count = 1
                             and then not Unmodified_Date.Valid)
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A HeadObject date condition is malformed",
                        Target_Text);
                     return;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif not Valid_Response_Overrides then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A HeadObject response override contains an " &
                        "invalid field value", Target_Text);
                     return;
                  elsif Server_Encryption_Count = 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "HeadObject cannot specify the server-side " &
                        "encryption method", Target_Text);
                     return;
                  elsif SSE_Algorithm_Count > 0 or else SSE_Key_Count > 0
                    or else SSE_MD5_Count > 0
                  then
                     if SSE_Algorithm_Count /= 1
                       or else SSE_Key_Count /= 1
                       or else SSE_MD5_Count /= 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The SSE-C header group is incomplete",
                           Target_Text);
                        return;
                     elsif Apps.Request_Header
                       (X, "x-amz-server-side-encryption-customer-" &
                          "algorithm") /= "AES256"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The SSE-C algorithm is invalid", Target_Text);
                        return;
                     elsif Apps.Request_Scheme (X) /=
                       Flyology.HTTP.Secure_HTTPS
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "SSE-C requests require HTTPS", Target_Text);
                        return;
                     elsif not Checksums.Valid_SSE_C_Key_MD5
                       (Apps.Request_Header
                          (X,
                           "x-amz-server-side-encryption-customer-key"),
                        Apps.Request_Header
                          (X, "x-amz-server-side-encryption-customer-" &
                           "key-md5"))
                     then
                        Send_Error
                          (X, 400, "InvalidDigest",
                           "The SSE-C key or digest is invalid", Target_Text);
                        return;
                     end if;
                     Valid_SSE_C := True;
                  elsif Has_Encryption_Header then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "HeadObject contains an unsupported encryption " &
                        "request header", Target_Text);
                     return;
                  end if;

                  if Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The request payer header is invalid", Target_Text);
                     return;
                  elsif Checksum_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-checksum-mode") /= "ENABLED"
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The checksum mode header is invalid", Target_Text);
                     return;
                  end if;

                  if If_Match_Count = 1 then
                     Conditions.If_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-match"));
                  end if;
                  if If_None_Match_Count = 1 then
                     Conditions.If_None_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-none-match"));
                  end if;
                  if Modified_Date.Valid then
                     Conditions.If_Modified_Since :=
                       (Is_Set => True,
                        Value => Modified_Date.Seconds_Since_Epoch);
                  end if;
                  if Unmodified_Date.Valid then
                     Conditions.If_Unmodified_Since :=
                       (Is_Set => True,
                        Value => Unmodified_Date.Seconds_Since_Epoch);
                  end if;

                  if Range_Count = 1 then
                     declare
                        Parsed_Range : constant S3.Core.Range_Parse_Result :=
                          S3.Core.Parse_Range_Header
                            (Apps.Request_Header (X, "range"));
                     begin
                        if Parsed_Range.Status /= S3.Core.Range_Parsed then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "The Range header is malformed", Target_Text);
                           return;
                        end if;
                        Requested := Parsed_Range.Request;
                        Has_Range := True;
                     end;
                  end if;

                  declare
                     Effective_Part : constant
                       Backends.Multipart_Part_Marker :=
                         (if Valid_SSE_C then 0 else Selected_Part);
                     Options : constant Backends.Object_Attribute_Options :=
                       (After =>
                          (if Effective_Part = 0
                           then 0 else Effective_Part - 1),
                        Maximum =>
                          (if Effective_Part = 0 then 0 else 1));
                  begin
                     Store.Get_Object_Attributes
                       (Bucket, Key, Options, Apps.Cancellation (X),
                        Apps.Deadline (X), Snapshot, Result,
                        Conditions =>
                          (if Valid_SSE_C
                           then Backends.Default_Read_Conditions
                           else Conditions),
                        Selector => Read_Version_Selector);
                     Info := Snapshot.Info;
                     if Result = Success and then Effective_Part /= 0 then
                        if not Snapshot.Is_Multipart then
                           if Effective_Part /= 1 then
                              Result := Invalid_Part;
                           end if;
                        elsif Natural (Snapshot.Parts.Length) = 1
                          and then Snapshot.Parts.First_Element.Number =
                            Effective_Part
                        then
                           Info.Size := Snapshot.Parts.First_Element.Size;
                           Info.Checksum :=
                             Snapshot.Parts.First_Element.Checksum;
                        else
                           Result := Invalid_Part;
                        end if;
                     end if;
                  end;
                  if Result = Success and then Valid_SSE_C then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The object is not encrypted with SSE-C", Target_Text);
                  elsif Result in Success | Not_Modified |
                    Precondition_Failed
                  then
                     Set_Common_Headers;
                     if Result = Not_Modified then
                        Apps.Respond (X, 304, "", "");
                     elsif Result = Precondition_Failed then
                        Send_Backend_Error (X, Result, False, Target_Text);
                     else
                        if Object_Read_Request.Has_Part_Number
                          and then Snapshot.Is_Multipart
                        then
                           Apps.Set_Header
                             (X, "x-amz-mp-parts-count",
                              Ada.Strings.Fixed.Trim
                                (Natural'Image (Snapshot.Total_Parts),
                                 Ada.Strings.Both));
                        end if;
                        if Has_Range then
                           declare
                              Resolved : constant Range_Resolution :=
                                Resolve_Range (Info.Size, Requested);
                           begin
                              if Resolved.Kind /= Satisfied_Range then
                                 Apps.Set_Header
                                   (X, "Content-Range",
                                    "bytes */" & Decimal (Info.Size));
                                 Send_Backend_Error
                                   (X, Invalid_Range, False, Target_Text);
                                 return;
                              end if;
                              Set_Object_Metadata_Headers (Info);
                              Set_Response_Overrides;
                              Apps.Begin_Stream
                                (X, 200,
                                 (if Object_Read_Request
                                       .Has_Response_Content_Type
                                  then US.To_String
                                    (Object_Read_Request
                                       .Response_Content_Type)
                                  else US.To_String (Info.Content_Type)),
                                 Flyology.HTTP.Body_Size (Resolved.Length));
                           end;
                        else
                           Set_Object_Metadata_Headers (Info);
                           Set_Response_Overrides;
                           Apps.Begin_Stream
                             (X, 200,
                              (if Object_Read_Request
                                    .Has_Response_Content_Type
                               then US.To_String
                                 (Object_Read_Request.Response_Content_Type)
                               else US.To_String (Info.Content_Type)),
                              Flyology.HTTP.Body_Size (Info.Size));
                        end if;
                        Apps.End_Stream (X);
                     end if;
                  elsif Result = Invalid_Part then
                     Apps.Set_Header
                       (X, "Content-Range", "bytes */" & Decimal (Info.Size));
                     Send_Backend_Error
                       (X, Invalid_Range, False, Target_Text);
                  else
                     Send_Backend_Error (X, Result, False, Target_Text);
                  end if;
               end;

            when Get_Object =>
               declare
                  If_Match_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-match");
                  If_Modified_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-modified-since");
                  If_None_Match_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-none-match");
                  If_Unmodified_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-unmodified-since");
                  Range_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "range");
                  SSE_Algorithm_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-" &
                       "algorithm");
                  SSE_Key_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key");
                  SSE_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption-customer-key-md5");
                  Server_Encryption_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-server-side-encryption");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Checksum_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-mode");
                  Modified_Date : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if If_Modified_Count = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Apps.Request_Header (X, "if-modified-since"),
                          Clock)
                       else (Valid => False));
                  Unmodified_Date : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if If_Unmodified_Count = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Apps.Request_Header (X, "if-unmodified-since"),
                          Clock)
                       else (Valid => False));
                  Requested : Byte_Range := Whole_Object;
                  Conditions : Backends.Read_Conditions :=
                    Backends.Default_Read_Conditions;
                  Sink      : Response_IO.Response_Sink;
                  Owner_OK  : Boolean := False;
               begin
                  if If_Match_Count > 1
                    or else If_Modified_Count > 1
                    or else If_None_Match_Count > 1
                    or else If_Unmodified_Count > 1
                    or else Range_Count > 1
                    or else SSE_Algorithm_Count > 1
                    or else SSE_Key_Count > 1
                    or else SSE_MD5_Count > 1
                    or else Server_Encryption_Count > 1
                    or else Payer_Count > 1
                    or else Checksum_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A GetObject request header is duplicated",
                        Target_Text);
                     return;
                  elsif (If_Match_Count = 1
                          and then Apps.Request_Header
                            (X, "if-match")'Length = 0)
                    or else (If_Modified_Count = 1
                             and then Apps.Request_Header
                               (X, "if-modified-since")'Length = 0)
                    or else (If_None_Match_Count = 1
                             and then Apps.Request_Header
                               (X, "if-none-match")'Length = 0)
                    or else (If_Unmodified_Count = 1
                             and then Apps.Request_Header
                               (X, "if-unmodified-since")'Length = 0)
                    or else (Range_Count = 1
                             and then Apps.Request_Header
                               (X, "range")'Length = 0)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A GetObject request header is empty", Target_Text);
                     return;
                  elsif (If_Match_Count = 1
                         and then not
                           Backends.Valid_Read_Entity_Tag_Condition
                             (Apps.Request_Header (X, "if-match")))
                    or else (If_None_Match_Count = 1
                             and then not
                               Backends.Valid_Read_Entity_Tag_Condition
                                 (Apps.Request_Header (X, "if-none-match")))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A GetObject entity-tag condition is malformed",
                        Target_Text);
                     return;
                  elsif (If_Modified_Count = 1
                         and then not Modified_Date.Valid)
                    or else (If_Unmodified_Count = 1
                             and then not Unmodified_Date.Valid)
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A GetObject date condition is malformed",
                        Target_Text);
                     return;
                  end if;

                  Check_Expected_Bucket_Owner
                    (US.To_String (Auth.Principal), Owner_OK);
                  if not Owner_OK then
                     return;
                  elsif Object_Read_Request.Has_Part_Number then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Part-number GetObject is not implemented",
                        Target_Text);
                     return;
                  elsif Server_Encryption_Count = 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "GetObject cannot specify the server-side " &
                        "encryption method", Target_Text);
                     return;
                  elsif SSE_Algorithm_Count = 1
                    or else SSE_Key_Count = 1
                    or else SSE_MD5_Count = 1
                  then
                     if SSE_Algorithm_Count /= 1
                       or else SSE_Key_Count /= 1
                       or else SSE_MD5_Count /= 1
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The SSE-C header group is incomplete",
                           Target_Text);
                     elsif Apps.Request_Header
                       (X, "x-amz-server-side-encryption-customer-" &
                          "algorithm") /= "AES256"
                     then
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The SSE-C algorithm is invalid", Target_Text);
                     elsif Apps.Request_Scheme (X) /=
                       Flyology.HTTP.Secure_HTTPS
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "SSE-C requests require HTTPS", Target_Text);
                     elsif not Checksums.Valid_SSE_C_Key_MD5
                       (Apps.Request_Header
                          (X,
                           "x-amz-server-side-encryption-customer-key"),
                        Apps.Request_Header
                          (X, "x-amz-server-side-encryption-customer-" &
                           "key-md5"))
                     then
                        Send_Error
                          (X, 400, "InvalidDigest",
                           "The SSE-C key or digest is invalid", Target_Text);
                     else
                        Send_Error
                          (X, 501, "NotImplemented",
                           "SSE-C GetObject requests are not implemented",
                           Target_Text);
                     end if;
                     return;
                  elsif Has_Encryption_Header then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "The GetObject encryption header is not implemented",
                        Target_Text);
                     return;
                  elsif Payer_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-request-payer") /= "requester"
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The request payer header is invalid", Target_Text);
                     return;
                  elsif Checksum_Count = 1
                    and then Apps.Request_Header
                      (X, "x-amz-checksum-mode") /= "ENABLED"
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The checksum mode header is invalid", Target_Text);
                     return;
                  end if;

                  if If_Match_Count = 1 then
                     Conditions.If_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-match"));
                  end if;
                  if If_None_Match_Count = 1 then
                     Conditions.If_None_Match := US.To_Unbounded_String
                       (Apps.Request_Header (X, "if-none-match"));
                  end if;
                  if Modified_Date.Valid then
                     Conditions.If_Modified_Since :=
                       (Is_Set => True,
                        Value => Modified_Date.Seconds_Since_Epoch);
                  end if;
                  if Unmodified_Date.Valid then
                     Conditions.If_Unmodified_Since :=
                       (Is_Set => True,
                        Value => Unmodified_Date.Seconds_Since_Epoch);
                  end if;

                  if Range_Count = 1 then
                     declare
                        Parsed_Range : constant S3.Core.Range_Parse_Result :=
                          S3.Core.Parse_Range_Header
                            (Apps.Request_Header (X, "range"));
                     begin
                        if Parsed_Range.Status /= S3.Core.Range_Parsed then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "The Range header is malformed", Target_Text);
                           return;
                        end if;
                        Requested := Parsed_Range.Request;
                     end;
                  end if;
                  Sink.Include_Checksum := Checksum_Count = 1;
                  Sink.Suppress_Composite_Checksum := Range_Count = 1;
                  Store.Get_Object
                    (Bucket, Key, Requested, Sink, Apps.Cancellation (X),
                     Apps.Deadline (X), Info, Result, Conditions,
                     Selector => Read_Version_Selector);
                  if Result = Success then
                     if not Sink.Started
                       or else Sink.Observed /= Sink.Expected
                     then
                        raise Program_Error with
                          "backend succeeded with incomplete response framing";
                     end if;
                     Apps.End_Stream (X);
                  elsif Result = Not_Modified
                    and then not Apps.Wire_Response_Started (X)
                  then
                     Apps.Set_Header
                       (X, "ETag", '"' & US.To_String (Info.Entity_Tag) & '"');
                     Apps.Set_Header
                       (X, "Last-Modified",
                        HTTP_Last_Modified (Info.Modified));
                     Apps.Respond (X, 304, "", "");
                  elsif not Apps.Wire_Response_Started (X) then
                     if Result = Invalid_Range and then Info.Size >= 0 then
                        Apps.Set_Header
                          (X, "Content-Range",
                           "bytes */" & Decimal (Info.Size));
                     end if;
                     Send_Backend_Error (X, Result, False, Target_Text);
                  else
                     Apps.Mark_Failed (X);
                  end if;
               end;

            when Delete_Object =>
               declare
                  MFA_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-mfa");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Bypass_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-bypass-governance-retention");
                  Owner_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-expected-bucket-owner");
                  Match_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "if-match");
                  Modified_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-if-match-last-modified-time");
                  Size_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-if-match-size");
                  Payer : constant String :=
                    (if Payer_Count = 1
                     then Apps.Request_Header (X, "x-amz-request-payer")
                     else "");
                  Match : constant String :=
                    (if Match_Count = 1
                     then Apps.Request_Header (X, "if-match") else "");
                  Modified : constant String :=
                    (if Modified_Count = 1
                     then Apps.Request_Header
                       (X, "x-amz-if-match-last-modified-time") else "");
                  Bypass : constant S3.Wire_Core.Boolean_Result :=
                    (if Bypass_Count = 1
                     then S3.Wire_Core.Parse_Boolean
                       (Apps.Request_Header
                          (X, "x-amz-bypass-governance-retention"))
                     else (Valid => False));
                  Match_Size : constant S3.Wire_Core.Byte_Count_Result :=
                    (if Size_Count = 1
                     then S3.Wire_Core.Parse_Byte_Count
                       (Apps.Request_Header (X, "x-amz-if-match-size"))
                     else (Valid => False));
                  Match_Modified : constant
                    Object_Reads.Conditional_Date_Result :=
                      (if Modified_Count = 1
                       then Object_Reads.Parse_Conditional_Date
                         (Modified, Clock)
                       else (Valid => False));
                  Owner_Accepted : Boolean;
               begin
                  if MFA_Count > 1 or else Payer_Count > 1
                    or else Bypass_Count > 1 or else Owner_Count > 1
                    or else Match_Count > 1 or else Modified_Count > 1
                    or else Size_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A DeleteObject header is duplicated", Target_Text);
                  elsif Payer_Count = 1 and then Payer /= "requester" then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer value is invalid", Target_Text);
                  elsif (MFA_Count = 1
                         and then Apps.Request_Header
                           (X, "x-amz-mfa")'Length = 0)
                    or else (Match_Count = 1 and then Match'Length = 0)
                    or else
                      (Modified_Count = 1 and then Modified'Length = 0)
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A DeleteObject conditional value is empty",
                        Target_Text);
                  elsif Bypass_Count = 1 and then not Bypass.Valid then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The governance bypass value is invalid",
                        Target_Text);
                  elsif Size_Count = 1 and then not Match_Size.Valid then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The conditional object size is invalid",
                        Target_Text);
                  elsif Modified_Count = 1
                    and then not Match_Modified.Valid
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The conditional modification time is invalid",
                        Target_Text);
                  elsif Match_Count = 1
                    and then not Valid_Object_Delete_ETag_Condition (Match)
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ETag condition is invalid", Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                     if Owner_Accepted then
                        declare
                           MFA_Result : constant MFA.Authorization_Status :=
                             (if MFA_Count = 1
                              then Verify_MFA_Credential
                                (US.To_String (Auth.Principal),
                                 Apps.Request_Header (X, "x-amz-mfa"))
                              else MFA.Authorized);
                        begin
                           if MFA_Count = 1
                             and then MFA_Result /= MFA.Authorized
                           then
                              Send_MFA_Error (MFA_Result);
                           elsif Payer_Count > 0 then
                              Send_Error
                                (X, 501, "NotImplemented",
                                 "Requester Pays is not implemented",
                                 Target_Text);
                           elsif Bypass_Count > 0 and then Bypass.Value then
                              Send_Error
                                (X, 501, "NotImplemented",
                                 "Governance retention enforcement is not " &
                                 "implemented", Target_Text);
                           elsif Modified_Count > 0 or else Size_Count > 0 then
                              Send_Error
                                (X, 400, "InvalidArgument",
                                 "LastModifiedTime and Size require a " &
                                 "directory bucket", Target_Text);
                           else
                              declare
                                 Configuration :
                                   Bucket_Versioning_Configuration;
                                 Delete_Outcome :
                                   Backends.Version_Delete_Outcome;
                                 Conditions : constant
                                   Backends.Delete_Object_Conditions :=
                                     (Has_ETag => Match_Count = 1,
                                      ETag => US.To_Unbounded_String (Match),
                                      others => <>);
                              begin
                                 Store.Get_Bucket_Versioning
                                   (Bucket, Apps.Cancellation (X),
                                    Apps.Deadline (X), Configuration, Result);
                                 if Result = Not_Found then
                                    Result := Bucket_Not_Found;
                                 elsif Result = Success
                                   and then
                                     (Delete_Request.Has_Version_ID
                                      or else Configuration.Status /=
                                        Versioning_Unconfigured)
                                 then
                                    Store.Delete_Selected_Object
                                      (Bucket, Key, Delete_Version_Selector,
                                       Conditions,
                                       MFA_Validated =>
                                         MFA_Count = 1
                                         and then MFA_Result = MFA.Authorized,
                                       Token => Apps.Cancellation (X),
                                       Deadline => Apps.Deadline (X),
                                       Outcome => Delete_Outcome,
                                       Result => Result);
                                    if Result = Success
                                      and then Delete_Outcome.Has_Version_ID
                                    then
                                       Apps.Set_Header
                                         (X, "x-amz-version-id",
                                          (if Delete_Outcome.Is_Null_Version
                                           then "null"
                                           else US.To_String
                                             (Delete_Outcome.Version_ID)));
                                    end if;
                                    if Result = Success
                                      and then Delete_Outcome.Kind in
                                        Backends.Delete_Marker_Created |
                                        Backends.Delete_Marker_Removed
                                    then
                                       Apps.Set_Header
                                         (X, "x-amz-delete-marker", "true");
                                    end if;
                                 elsif Result = Success then
                                    --  The legacy primitive performs its own
                                    --  atomic unversioned-state admission, so
                                    --  a concurrent versioning transition can
                                    --  only fail closed before deletion.
                                    Store.Delete_Object
                                      (Bucket, Key, Apps.Cancellation (X),
                                       Apps.Deadline (X), Result,
                                       Conditions => Conditions,
                                       Requirements =>
                                         (Require_Unversioned => True,
                                          others => <>));
                                 end if;
                              end;
                              if Result = Success then
                                 Apps.Respond (X, 204, "", "");
                              elsif Result = Not_Implemented then
                                 Send_Error
                                   (X, 501, "NotImplemented",
                                    "The configured backend does not " &
                                    "support " &
                                    "the selected object generation",
                                    Target_Text);
                              else
                                 Send_Backend_Error
                                   (X, Result, False, Target_Text);
                              end if;
                           end if;
                        end;
                     end if;
                  end if;
               end;

            when Delete_Objects =>
               declare
                  Source : Request_IO.Request_Source :=
                    (Checksum_Kind => S3.Core.CRC64NVME,
                     Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Maximum_Delete_Objects_Body,
                     Completed => False,
                     others    => <>);
                  Document : constant String := Read_Document (Source);
                  MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
                  MFA_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-mfa");
                  Payer_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-request-payer");
                  Bypass_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-bypass-governance-retention");
                  SDK_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-sdk-checksum-algorithm");
                  CRC32_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-crc32");
                  CRC32C_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-crc32c");
                  CRC64_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-crc64nvme");
                  SHA1_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-sha1");
                  SHA256_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-sha256");
                  SHA512_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-sha512");
                  Checksum_MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-md5");
                  XXHASH64_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-xxhash64");
                  XXHASH3_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "x-amz-checksum-xxhash3");
                  XXHASH128_Count : constant Natural :=
                    Apps.Request_Header_Count
                      (X, "x-amz-checksum-xxhash128");
                  Checksum_Count : constant Natural :=
                    CRC32_Count + CRC32C_Count + CRC64_Count + SHA1_Count +
                    SHA256_Count + SHA512_Count + Checksum_MD5_Count +
                    XXHASH64_Count + XXHASH3_Count + XXHASH128_Count;
                  Payer : constant String :=
                    (if Payer_Count = 1
                     then Apps.Request_Header (X, "x-amz-request-payer")
                     else "");
                  MFA_Header : constant String :=
                    (if MFA_Count = 1
                     then Apps.Request_Header (X, "x-amz-mfa") else "");
                  Bypass : constant S3.Wire_Core.Boolean_Result :=
                    (if Bypass_Count = 1
                     then S3.Wire_Core.Parse_Boolean
                       (Apps.Request_Header
                          (X, "x-amz-bypass-governance-retention"))
                     else (Valid => False));
                  Owner_Accepted : Boolean := False;

                  type Checksum_Verification is
                    (Checksum_OK, Invalid_Checksum_Group,
                     Invalid_Checksum_Value, Checksum_Mismatch);

                  function Header_Name
                    (Algorithm : Checksum_Policy.Algorithm) return String is
                    (case Algorithm is
                        when S3.Core.CRC32 => "x-amz-checksum-crc32",
                        when S3.Core.CRC32C => "x-amz-checksum-crc32c",
                        when S3.Core.CRC64NVME =>
                          "x-amz-checksum-crc64nvme",
                        when S3.Core.SHA1 => "x-amz-checksum-sha1",
                        when S3.Core.SHA256 => "x-amz-checksum-sha256",
                        when S3.Core.SHA512 => "x-amz-checksum-sha512",
                        when S3.Core.MD5 => "x-amz-checksum-md5",
                        when S3.Core.XXHASH64 => "x-amz-checksum-xxhash64",
                        when S3.Core.XXHASH3 => "x-amz-checksum-xxhash3",
                        when S3.Core.XXHASH128 =>
                          "x-amz-checksum-xxhash128");

                  function Count_For
                    (Algorithm : Checksum_Policy.Algorithm) return Natural is
                    (case Algorithm is
                        when S3.Core.CRC32 => CRC32_Count,
                        when S3.Core.CRC32C => CRC32C_Count,
                        when S3.Core.CRC64NVME => CRC64_Count,
                        when S3.Core.SHA1 => SHA1_Count,
                        when S3.Core.SHA256 => SHA256_Count,
                        when S3.Core.SHA512 => SHA512_Count,
                        when S3.Core.MD5 => Checksum_MD5_Count,
                        when S3.Core.XXHASH64 => XXHASH64_Count,
                        when S3.Core.XXHASH3 => XXHASH3_Count,
                        when S3.Core.XXHASH128 => XXHASH128_Count);

                  function Selected_Algorithm return
                    Checksum_Policy.Algorithm_Parse_Result
                  is
                  begin
                     if SDK_Count = 1 then
                        return Checksum_Policy.Parse_Algorithm
                          (Apps.Request_Header
                             (X, "x-amz-sdk-checksum-algorithm"));
                     elsif CRC32_Count = 1 then
                        return (Valid => True, Value => S3.Core.CRC32);
                     elsif CRC32C_Count = 1 then
                        return (Valid => True, Value => S3.Core.CRC32C);
                     elsif CRC64_Count = 1 then
                        return (Valid => True, Value => S3.Core.CRC64NVME);
                     elsif SHA1_Count = 1 then
                        return (Valid => True, Value => S3.Core.SHA1);
                     elsif SHA256_Count = 1 then
                        return (Valid => True, Value => S3.Core.SHA256);
                     elsif SHA512_Count = 1 then
                        return (Valid => True, Value => S3.Core.SHA512);
                     elsif Checksum_MD5_Count = 1 then
                        return (Valid => True, Value => S3.Core.MD5);
                     elsif XXHASH64_Count = 1 then
                        return (Valid => True, Value => S3.Core.XXHASH64);
                     elsif XXHASH3_Count = 1 then
                        return (Valid => True, Value => S3.Core.XXHASH3);
                     elsif XXHASH128_Count = 1 then
                        return (Valid => True, Value => S3.Core.XXHASH128);
                     else
                        return (Valid => False);
                     end if;
                  end Selected_Algorithm;

                  function Verify_Checksum return Checksum_Verification is
                     Selected : constant
                       Checksum_Policy.Algorithm_Parse_Result :=
                         Selected_Algorithm;
                  begin
                     if SDK_Count > 1 or else Checksum_Count > 1
                       or else CRC32_Count > 1 or else CRC32C_Count > 1
                       or else CRC64_Count > 1 or else SHA1_Count > 1
                       or else SHA256_Count > 1 or else SHA512_Count > 1
                       or else Checksum_MD5_Count > 1
                       or else XXHASH64_Count > 1
                       or else XXHASH3_Count > 1
                       or else XXHASH128_Count > 1
                       or else
                         (SDK_Count = 1
                          and then
                            (not Selected.Valid
                             or else Checksum_Count /= 1
                             or else Count_For (Selected.Value) /= 1))
                     then
                        return Invalid_Checksum_Group;
                     elsif Checksum_Count = 0 then
                        return Checksum_OK;
                     elsif not Selected.Valid then
                        return Invalid_Checksum_Group;
                     end if;
                     declare
                        Supplied : constant Checksums.Decode_Result :=
                          Checksums.Decode_Base64
                            (Apps.Request_Header
                               (X, Header_Name (Selected.Value)),
                             Selected.Value);
                     begin
                        if not Supplied.Valid then
                           return Invalid_Checksum_Value;
                        end if;
                        declare
                           Computed : constant Checksums.Digest_Value :=
                             Checksums.Compute
                               (Selected.Value,
                                Flyology.Bytes.To_Array
                                  (Flyology.Bytes.From_Byte_String
                                     (Document)));
                        begin
                           if Checksums.Equivalent
                             (Supplied.Value, Computed)
                           then
                              return Checksum_OK;
                           else
                              return Checksum_Mismatch;
                           end if;
                        end;
                     end;
                  end Verify_Checksum;

                  Checksum_Status : constant Checksum_Verification :=
                    Verify_Checksum;
               begin
                  if MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      ((if MD5_Count = 1
                        then Apps.Request_Header (X, "content-md5") else ""),
                       16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "DeleteObjects requires one valid Content-MD5 header",
                        Target_Text);
                  elsif Content_MD5 (Document) /=
                    Apps.Request_Header (X, "content-md5")
                  then
                     Send_Error
                       (X, 400, "BadDigest",
                        "The Content-MD5 does not match the request body",
                        Target_Text);
                  elsif MFA_Count > 1 or else Payer_Count > 1
                    or else Bypass_Count > 1
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "A DeleteObjects control header is duplicated",
                        Target_Text);
                  elsif Payer_Count = 1 and then Payer /= "requester" then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The request payer value is invalid", Target_Text);
                  elsif MFA_Count = 1 and then MFA_Header'Length = 0 then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The MFA value is empty", Target_Text);
                  elsif Bypass_Count = 1 and then not Bypass.Valid then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The governance bypass value is invalid",
                        Target_Text);
                  elsif Checksum_Status in
                    Invalid_Checksum_Group | Invalid_Checksum_Value
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The DeleteObjects checksum group is invalid",
                        Target_Text);
                  elsif Checksum_Status = Checksum_Mismatch then
                     Send_Error
                       (X, 400, "BadDigest",
                        "The optional checksum does not match the " &
                        "request body",
                        Target_Text);
                  else
                     Check_Expected_Bucket_Owner
                       (US.To_String (Auth.Principal), Owner_Accepted);
                  end if;
                  if Owner_Accepted then
                     declare
                        Request : constant
                          Deletions.Delete_Objects_Request :=
                            Deletions.Parse_Request
                              (Document,
                               (Maximum_Document_Bytes =>
                                  Natural (Maximum_Delete_Objects_Body),
                                Maximum_Depth      => 8,
                                Maximum_Elements   =>
                                  Deletions.Maximum_Request_Elements,
                                Maximum_Text_Bytes =>
                                  Natural (Maximum_Delete_Objects_Body)));
                        Response : Deletions.Delete_Objects_Result;
                        Entries  : Backends.Delete_Object_Entries;
                        Outcomes : Backends.Delete_Object_Outcomes;
                        Has_Versioned_Entry : Boolean := False;
                        MFA_Result : MFA.Authorization_Status :=
                          MFA.Authorized;
                     begin
                        for Object_Request of Request.Objects loop
                           declare
                              ETag_Valid : constant Boolean :=
                                not Object_Request.Has_ETag
                                or else Valid_Object_Delete_ETag_Condition
                                  (US.To_String (Object_Request.ETag));
                           begin
                              if ETag_Valid
                                and then
                                  not Object_Request.Has_Last_Modified_Time
                                and then not Object_Request.Has_Size
                              then
                                 Has_Versioned_Entry :=
                                   Has_Versioned_Entry
                                   or else
                                     US.Length
                                       (Object_Request.Version_ID) > 0;
                                 Entries.Append
                                   (Backends.Delete_Object_Entry'
                                      (Key => Object_Request.Key,
                                       Selector =>
                                         To_Version_Selector
                                           (US.Length
                                              (Object_Request.Version_ID) > 0,
                                            Object_Request.Version_ID),
                                       Conditions =>
                                         (Has_ETag =>
                                            Object_Request.Has_ETag,
                                          ETag => Object_Request.ETag,
                                          others => <>)));
                              end if;
                           end;
                        end loop;
                        if Has_Versioned_Entry and then MFA_Count = 1 then
                           MFA_Result := Verify_MFA_Credential
                             (US.To_String (Auth.Principal), MFA_Header);
                           if MFA_Result /= MFA.Authorized then
                              Send_MFA_Error (MFA_Result);
                              return;
                           end if;
                        end if;
                        if Entries.Is_Empty then
                           --  No storage mutation can follow, so a separate
                           --  existence lookup preserves S3's NoSuchBucket
                           --  classification without reintroducing the
                           --  versioning/delete race on actionable entries.
                           Store.Head_Bucket
                             (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                              Result);
                           if Result /= Success then
                              Send_Backend_Error
                                (X, Result, True, Target_Text);
                              return;
                           end if;
                        else
                           Store.Delete_Objects
                             (Bucket, Entries,
                              (Require_Unversioned => False,
                               MFA_Validated =>
                                 Has_Versioned_Entry
                                 and then MFA_Count = 1
                                 and then MFA_Result = MFA.Authorized),
                              Apps.Cancellation (X), Apps.Deadline (X),
                              Outcomes, Result);
                           if Result /= Success then
                              Send_Backend_Error
                                (X, Result, True, Target_Text);
                              return;
                           end if;
                        end if;
                        declare
                           Outcome_Index : Positive := 1;
                        begin
                           for Object_Request of Request.Objects loop
                              declare
                                 Date_Value : constant
                                   Object_Reads.Conditional_Date_Result :=
                                     (if
                                        Object_Request.Has_Last_Modified_Time
                                      then
                                        Object_Reads.Parse_Conditional_Date
                                          (US.To_String
                                             (Object_Request
                                                .Last_Modified_Time),
                                           Clock)
                                      else (Valid => False));
                                 ETag_Valid : constant Boolean :=
                                   not Object_Request.Has_ETag
                                   or else Valid_Object_Delete_ETag_Condition
                                     (US.To_String (Object_Request.ETag));
                                 Entry_Result : Status := Invalid_Request;
                                 Publication :
                                   Backends.Version_Delete_Outcome;
                                 Marker_Result : Boolean := False;
                                 Marker_Version_ID : US.Unbounded_String;
                                 Error_Code : US.Unbounded_String;
                                 Error_Message : US.Unbounded_String;
                              begin
                                 if not ETag_Valid then
                                    Error_Code := US.To_Unbounded_String
                                      ("InvalidArgument");
                                    Error_Message := US.To_Unbounded_String
                                      ("The ETag condition is invalid");
                                 elsif Object_Request.Has_Last_Modified_Time
                                   and then not Date_Value.Valid
                                 then
                                    Error_Code := US.To_Unbounded_String
                                      ("InvalidArgument");
                                    Error_Message := US.To_Unbounded_String
                                      ("The LastModifiedTime condition is " &
                                       "invalid");
                                 elsif Object_Request.Has_Last_Modified_Time
                                   or else Object_Request.Has_Size
                                 then
                                    Error_Code := US.To_Unbounded_String
                                      ("InvalidArgument");
                                    Error_Message := US.To_Unbounded_String
                                      ("LastModifiedTime and Size require " &
                                       "a directory bucket");
                                 else
                                    Entry_Result :=
                                      Outcomes (Outcome_Index).Result;
                                    Publication :=
                                      Outcomes (Outcome_Index).Publication;
                                    Marker_Result := Publication.Kind in
                                      Backends.Delete_Marker_Created |
                                        Backends.Delete_Marker_Removed;
                                    Marker_Version_ID :=
                                      (if not Marker_Result
                                         or else not Publication.Has_Version_ID
                                       then US.Null_Unbounded_String
                                       elsif Publication.Is_Null_Version
                                       then US.To_Unbounded_String ("null")
                                       else Publication.Version_ID);
                                    Outcome_Index := Outcome_Index + 1;
                                    if Entry_Result = Success then
                                       if not Request.Quiet then
                                          Response.Deleted.Append
                                            (Deletions.Deleted_Object'
                                               (Key => Object_Request.Key,
                                                Version_ID =>
                                                  Object_Request.Version_ID,
                                                Delete_Marker =>
                                                  (Is_Set =>
                                                     Marker_Result,
                                                   Value => Marker_Result),
                                                Delete_Marker_Version_ID =>
                                                  Marker_Version_ID));
                                       end if;
                                    elsif Entry_Result = Not_Found then
                                       Error_Code := US.To_Unbounded_String
                                         ("NoSuchKey");
                                       Error_Message := US.To_Unbounded_String
                                         ("The conditioned key does not " &
                                          "exist");
                                    elsif Entry_Result = Precondition_Failed
                                    then
                                       Error_Code := US.To_Unbounded_String
                                         ("PreconditionFailed");
                                       Error_Message := US.To_Unbounded_String
                                         ("A delete condition did not match");
                                    elsif Entry_Result in
                                      Capacity_Exceeded | Backend_Unavailable
                                    then
                                       Error_Code := US.To_Unbounded_String
                                         ("SlowDown");
                                       Error_Message := US.To_Unbounded_String
                                         ("The object could not be deleted");
                                    elsif Entry_Result = Conflict then
                                       Error_Code := US.To_Unbounded_String
                                         ("OperationAborted");
                                       Error_Message := US.To_Unbounded_String
                                         ("The object could not be deleted");
                                    elsif Entry_Result = Access_Denied then
                                       Error_Code := US.To_Unbounded_String
                                         ("AccessDenied");
                                       Error_Message := US.To_Unbounded_String
                                         ("MFA Delete authorization is " &
                                          "required");
                                    elsif Entry_Result = Not_Implemented then
                                       Error_Code := US.To_Unbounded_String
                                         ("NotImplemented");
                                       Error_Message := US.To_Unbounded_String
                                         ("The selected object generation " &
                                          "is not supported");
                                    else
                                       Error_Code := US.To_Unbounded_String
                                         ("InvalidRequest");
                                       Error_Message := US.To_Unbounded_String
                                         ("The object could not be deleted");
                                    end if;
                                 end if;
                                 if US.Length (Error_Code) > 0 then
                                    Response.Errors.Append
                                      (Deletions.Delete_Error'
                                         (Key => Object_Request.Key,
                                          Version_ID =>
                                            Object_Request.Version_ID,
                                          Code => Error_Code,
                                          Message => Error_Message));
                                 end if;
                              end;
                           end loop;
                        end;
                        Apps.Respond
                          (X, 200, "application/xml",
                           Deletions.Serialize_Result (Response));
                     end;
                  end if;
               exception
                  when Deletions.Malformed_Delete =>
                     Send_Error
                       (X, 400, "MalformedXML",
                        "The XML provided was not well-formed or did not " &
                        "validate against the published schema", Target_Text);
               end;

            when Unsupported =>
               raise Program_Error with "unreachable S3 operation";
         end case;
      end;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         Apps.Mark_Failed (X);
         raise;
      when Buckets.Malformed_Bucket_Configuration =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "MalformedXML",
               "The XML provided was not well-formed or did not validate " &
               "against the published schema", Target_Text);
         end if;
      when Body_Entity_Too_Large =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "EntityTooLarge",
               "Your proposed upload exceeds the maximum allowed size",
               Target_Text);
         end if;
      when Payload_Hash_Mismatch =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "XAmzContentSHA256Mismatch",
               "The provided payload hash does not match the request body",
               Target_Text);
         end if;
      when Content_MD5_Mismatch =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "BadDigest",
               "The Content-MD5 does not match the request body",
               Target_Text);
         end if;
      when Body_Checksum_Mismatch =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "BadDigest",
               "The checksum does not match the request body",
               Target_Text);
         end if;
      when Body_Checksum_Invalid =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "InvalidRequest",
               "The checksum value or trailer is invalid",
               Target_Text);
         end if;
      when Malformed_Body_Framing =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "InvalidRequest", "Invalid request body framing",
               Target_Text);
         end if;
      when Multipart.Malformed_Multipart =>
         if Apps.Wire_Response_Started (X) then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 400, "MalformedXML",
               "The XML provided was not well-formed or did not validate " &
               "against the published schema", Target_Text);
         end if;
      when others =>
         if Apps.Response (X) /= Apps.Not_Started
           or else Apps.Wire_Response_Started (X)
         then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 500, "InternalError",
               "We encountered an internal error", Target_Text);
         end if;
   end Handle;

end Flyology.Object_Storage.Server.S3_Applications;
