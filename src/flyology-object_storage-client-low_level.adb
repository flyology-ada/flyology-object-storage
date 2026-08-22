with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Bytes;
with Flyology.HTTP.Headers;
with Flyology.Object_Storage.Secrets;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Object_Reads;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.Wire_Core;
with GNAT.MD5;

package body Flyology.Object_Storage.Client.Low_Level is

   package US renames Ada.Strings.Unbounded;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Model renames Flyology.Object_Storage.S3.Model;
   package Encoding renames Flyology.Object_Storage.S3.SigV4_Encoding;
   package Object_Reads renames Flyology.Object_Storage.S3.Object_Reads;
   package Checksum_Policy renames
     Flyology.Object_Storage.S3.Checksum_Policy;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Flyology.HTTP.Origin_Scheme;
   use type Flyology.HTTP.Port_Number;
   use type Model.Member_Location;
   use type Model.Operation_Id;
   use type Model.Shape_Kind;
   use type S3.Core.Range_Parse_Status;

   function Authority (Origin : Flyology.HTTP.Origin) return String;
   function Wire_Query (Canonical : String) return String;
   function Valid_Optional_Checksum
     (Value : US.Unbounded_String; Bytes : Positive) return Boolean;
   function Valid_Optional_Object_Checksum
     (Value : US.Unbounded_String; Bytes : Positive; Kind : String)
      return Boolean;
   function Valid_Read_Checksum_Headers
     (CRC32, CRC32C, CRC64NVME, SHA1, SHA256, SHA512, MD5,
      XXHASH64, XXHASH3, XXHASH128 : US.Unbounded_String;
      Kind : String) return Boolean;
   function Valid_Checksum_Algorithm (Value : String) return Boolean;
   function Content_MD5 (Value : String) return String;
   function Whitespace_Only (Value : String) return Boolean;
   function Error_Response
     (Payload, Request_ID, Host_ID : String;
      Limits : S3.XML.Parse_Limits) return S3.Errors.Error_Response;
   function Prepare_Object_Request
     (Operation : Operation_Kind;
      Method    : String;
      Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Query     : SigV4.Name_Value_Array;
      Additional_Headers : SigV4.Name_Value_Array;
      Payload   : String;
      Payload_Hash_Value : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String;
      Object_Resource : Boolean := True) return Prepared_Request;
   function Prepare_Put_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Value      : Tags.Tag_Set;
      Parameters : Put_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Document : constant String := S3.Tagging.Serialize_Bucket (Value);
      Supplied_MD5 : constant String :=
        US.To_String (Parameters.Content_MD5);
      MD5 : constant String :=
        (if Supplied_MD5'Length = 0
         then Content_MD5 (Document) else Supplied_MD5);
      Checksum : constant String :=
        US.To_String (Parameters.Checksum_Algorithm);
      Algorithm : constant Checksum_Policy.Algorithm_Parse_Result :=
        Checksum_Policy.Parse_Algorithm (Checksum);
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Payer : constant String := US.To_String (Parameters.Request_Payer);
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("tagging", ""));
      Headers : SigV4.Name_Value_Array
        (1 .. 1 + Boolean'Pos (Owner'Length > 0) +
           2 * Boolean'Pos (Checksum'Length > 0));
      Last : Positive := 1;
   begin
      if not Wire_Core.Valid_Base64 (MD5, 16)
        or else Payer'Length > 0
        or else (Checksum'Length > 0 and then not Algorithm.Valid)
      then
         raise Invalid_Request with "invalid PutBucketTagging parameters";
      end if;
      Headers (1) := SigV4.Pair ("content-md5", MD5);
      if Owner'Length > 0 then
         Last := Last + 1;
         Headers (Last) :=
           SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      if Checksum'Length > 0 then
         declare
            Digest : constant Checksums.Digest_Value :=
              Checksums.Compute
                (Algorithm.Value,
                 Flyology.Bytes.To_Array
                   (Flyology.Bytes.From_Byte_String (Document)));
            Header_Name : constant String :=
              (case Algorithm.Value is
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
         begin
            Last := Last + 1;
            Headers (Last) :=
              SigV4.Pair ("x-amz-sdk-checksum-algorithm", Checksum);
            Last := Last + 1;
            Headers (Last) :=
              SigV4.Pair (Header_Name, Checksums.Encode_Base64 (Digest));
         end;
      end if;
      return Prepare_Object_Request
        (Put_Bucket_Tagging_Operation, "PUT", Origin, Style, Bucket, "",
         Query, Headers, Document, "", Identity, Region, Timestamp,
         Object_Resource => False);
   exception
      when S3.Tagging.Invalid_Tag =>
         raise Invalid_Request with "invalid PutBucketTagging tag set";
   end Prepare_Put_Bucket_Tagging;

   function Decode_Put_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Bucket_Tagging_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Tagging_Outcome
   is
      Charged : constant String := US.To_String (Headers.Request_Charged);
   begin
      if Status in 200 | 204 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "PutBucketTagging success contains a response body";
         elsif Charged'Length > 0 then
            raise Invalid_Response with
              "PutBucketTagging returned invalid request charging metadata";
         end if;
         return
           (Kind => Bucket_Tags_Replaced, Status => Status,
            Result => Headers);
      else
         return
           (Kind   => Put_Bucket_Tagging_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed PutBucketTagging response";
   end Decode_Put_Bucket_Tagging_Response;

   function Execute_Put_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Tagging_Outcome
   is
   begin
      if Prepared.Operation /= Put_Bucket_Tagging_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Put_Bucket_Tagging_Result :=
           (Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Put_Bucket_Tagging_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "PutBucketTagging response exceeds XML limit";
   end Execute_Put_Bucket_Tagging;

   function Prepare_Get_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Payer : constant String := US.To_String (Parameters.Request_Payer);
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("tagging", ""));
      Headers : SigV4.Name_Value_Array
        (1 .. Boolean'Pos (Owner'Length > 0));
      Last : Natural := 0;
   begin
      if Payer'Length > 0 then
         raise Invalid_Request with "invalid GetBucketTagging parameters";
      end if;
      if Owner'Length > 0 then
         Last := Last + 1;
         Headers (Last) :=
           SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      return Prepare_Object_Request
        (Get_Bucket_Tagging_Operation, "GET", Origin, Style, Bucket, "",
         Query, Headers, "", "", Identity, Region, Timestamp,
         Object_Resource => False);
   end Prepare_Get_Bucket_Tagging;

   function Decode_Get_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Get_Bucket_Tagging_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Tagging_Outcome
   is
      Charged : constant String := US.To_String (Headers.Request_Charged);
      Result : Get_Bucket_Tagging_Result := Headers;
   begin
      if Status = 200 then
         if Charged'Length > 0 then
            raise Invalid_Response with
              "GetBucketTagging returned invalid request charging metadata";
         end if;
         Result.Value := S3.Tagging.Parse_Bucket_Response (Payload, Limits);
         return
           (Kind => Bucket_Tags_Found, Status => Status, Result => Result);
      else
         return
           (Kind   => Get_Bucket_Tagging_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Tagging.Malformed_Tagging | S3.Tagging.Invalid_Tag |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed GetBucketTagging response";
   end Decode_Get_Bucket_Tagging_Response;

   function Execute_Get_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Tagging_Outcome
   is
   begin
      if Prepared.Operation /= Get_Bucket_Tagging_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Get_Bucket_Tagging_Result :=
           (Value => Tags.Tag_Vectors.Empty_Vector,
            Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response,
              Natural'Min
                (Limits.Maximum_Document_Bytes,
                 S3.Tagging.Maximum_Document_Bytes),
              Token);
      begin
         return Decode_Get_Bucket_Tagging_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "GetBucketTagging response exceeds XML limit";
   end Execute_Get_Bucket_Tagging;

   function Prepare_Delete_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("tagging", ""));
      Headers : SigV4.Name_Value_Array
        (1 .. Boolean'Pos (Owner'Length > 0));
   begin
      if Owner'Length > 0 then
         Headers (1) :=
           SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      return Prepare_Object_Request
        (Delete_Bucket_Tagging_Operation, "DELETE", Origin, Style, Bucket,
         "", Query, Headers, "", "", Identity, Region, Timestamp,
         Object_Resource => False);
   end Prepare_Delete_Bucket_Tagging;

   function Decode_Delete_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Tagging_Outcome
   is
   begin
      if Status = 204 then
         if Payload'Length /= 0 then
            raise Invalid_Response with
              "DeleteBucketTagging success contains a response body";
         end if;
         return (Kind => Bucket_Tags_Deleted, Status => Status);
      end if;
      return
        (Kind   => Delete_Bucket_Tagging_Rejected,
         Status => Status,
         Error  => Error_Response (Payload, Request_ID, Host_ID, Limits));
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed DeleteBucketTagging response";
   end Decode_Delete_Bucket_Tagging_Response;

   function Execute_Delete_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Tagging_Outcome
   is
   begin
      if Prepared.Operation /= Delete_Bucket_Tagging_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Delete_Bucket_Tagging_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "DeleteBucketTagging response exceeds XML limit";
   end Execute_Delete_Bucket_Tagging;

   function Valid_SSE_C_Group
     (Algorithm, Key, Key_MD5 : String) return Boolean;
   function Optional_Boolean_Header
     (Value : String) return Optional_Boolean;
   function Valid_Content_Range
     (Value : String; Length : Optional_Byte_Count) return Boolean;

   No_Headers : constant SigV4.Name_Value_Array (1 .. 0) :=
     (others => <>);
   No_Query : constant SigV4.Name_Value_Array (1 .. 0) :=
     (others => <>);

   function Access_Key (Item : Credentials) return String is
     (Item.Access_Key_Data (1 .. Item.Access_Key_Length));

   function Secret_Key (Item : Credentials) return String is
     (Item.Secret_Key_Data (1 .. Item.Secret_Key_Length));

   function Session_Token (Item : Credentials) return String is
     (Item.Session_Token_Data (1 .. Item.Session_Token_Length));

   overriding procedure Finalize (Item : in out Credentials) is
   begin
      Flyology.Object_Storage.Secrets.Wipe (Item.Access_Key_Data);
      Flyology.Object_Storage.Secrets.Wipe (Item.Secret_Key_Data);
      Flyology.Object_Storage.Secrets.Wipe (Item.Session_Token_Data);
      Item.Access_Key_Length := 0;
      Item.Secret_Key_Length := 0;
      Item.Session_Token_Length := 0;
   end Finalize;

   function Make_Credentials
     (Access_Key, Secret_Key : String;
      Session_Token         : String := "") return Credentials
   is
   begin
      if not Encoding.Valid_Access_Key (Access_Key)
        or else Access_Key'Length > Maximum_Credential_Bytes
        or else Secret_Key'Length = 0
        or else Secret_Key'Length > Maximum_Credential_Bytes
        or else Session_Token'Length > Maximum_Session_Token_Bytes
      then
         raise Invalid_Request with "invalid S3 credentials";
      end if;
      return Result : Credentials do
         Result.Access_Key_Length := Access_Key'Length;
         Result.Secret_Key_Length := Secret_Key'Length;
         Result.Session_Token_Length := Session_Token'Length;
         Result.Access_Key_Data (1 .. Access_Key'Length) := Access_Key;
         Result.Secret_Key_Data (1 .. Secret_Key'Length) := Secret_Key;
         if Session_Token'Length > 0 then
            Result.Session_Token_Data (1 .. Session_Token'Length) :=
              Session_Token;
         end if;
      end return;
   end Make_Credentials;

   function Target (Item : Prepared_Request) return String is
     (US.To_String (Item.Target_Value));

   function Authority (Item : Prepared_Request) return String is
     (US.To_String (Item.Authority_Value));

   function Canonical_Request (Item : Prepared_Request) return String is
     (US.To_String (Item.Signing.Canonical_Request));

   function Signed_Headers (Item : Prepared_Request) return String is
     (US.To_String (Item.Signing.Signed_Headers));

   function Starts_With (Value, Prefix : String) return Boolean is
     (Value'Length >= Prefix'Length
      and then Value
        (Value'First .. Value'First + Prefix'Length - 1) = Prefix);

   type Natural_Array is array (Positive range <>) of Natural;
   type Boolean_Array is array (Positive range <>) of Boolean;

   function Model_Method (Value : Model.HTTP_Method) return String is
     (case Value is
         when Model.Delete_Method => "DELETE",
         when Model.Get_Method    => "GET",
         when Model.Head_Method   => "HEAD",
         when Model.Post_Method   => "POST",
         when Model.Put_Method    => "PUT");

   function Find_Model_Member
     (Shape : Model.Shape_Index; Name : String) return Natural
   is
   begin
      if Model.Member_Count (Shape) > 0 then
         for Member in 1 .. Model.Member_Count (Shape) loop
            if Model.Member_Name (Shape, Member) = Name then
               return Member;
            end if;
         end loop;
      end if;
      return 0;
   end Find_Model_Member;

   function Fixed_Query_Count (URI : String) return Natural is
      Question : constant Natural := Ada.Strings.Fixed.Index (URI, "?");
      Result   : Natural := 0;
   begin
      if Question = 0 or else Question = URI'Last then
         return 0;
      end if;
      Result := 1;
      for Index in Question + 1 .. URI'Last loop
         if URI (Index) = '&' then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Fixed_Query_Count;

   procedure Append_Fixed_Query
     (URI   : String;
      Query : in out SigV4.Name_Value_Array;
      Last  : in out Natural)
   is
      Question : constant Natural := Ada.Strings.Fixed.Index (URI, "?");
      First    : Natural := Question + 1;

      procedure Append_Segment (Segment_First, Segment_Last : Natural) is
         Equals : Natural := 0;
      begin
         if Segment_First > Segment_Last then
            raise Invalid_Request with "empty fixed model query member";
         end if;
         for Index in Segment_First .. Segment_Last loop
            if URI (Index) = '=' and then Equals = 0 then
               Equals := Index;
            end if;
         end loop;
         Last := Last + 1;
         if Equals = 0 then
            Query (Last) := SigV4.Pair
              (URI (Segment_First .. Segment_Last), "");
         else
            Query (Last) := SigV4.Pair
              (URI (Segment_First .. Equals - 1),
               URI (Equals + 1 .. Segment_Last));
         end if;
      end Append_Segment;
   begin
      if Question = 0 or else Question = URI'Last then
         return;
      end if;
      for Index in Question + 1 .. URI'Last loop
         if URI (Index) = '&' then
            Append_Segment (First, Index - 1);
            First := Index + 1;
         end if;
      end loop;
      Append_Segment (First, URI'Last);
   end Append_Fixed_Query;

   function Model_Path_Template
     (URI : String; Style : Addressing_Style) return String
   is
      Question : constant Natural := Ada.Strings.Fixed.Index (URI, "?");
      Last : constant Natural :=
        (if Question = 0 then URI'Last else Question - 1);
      Path : constant String := URI (URI'First .. Last);
      Bucket_Label : constant String := "/{Bucket}";
   begin
      if Style = Virtual_Hosted_Style
        and then Starts_With (Path, Bucket_Label)
      then
         if Path'Length = Bucket_Label'Length then
            return "/";
         else
            return Path
              (Path'First + Bucket_Label'Length .. Path'Last);
         end if;
      end if;
      return Path;
   end Model_Path_Template;

   function Expand_Model_Path
     (Template      : String;
      Input_Shape   : Model.Shape_Index;
      Values        : Model_Value_Array;
      Value_Members : Natural_Array;
      Encode_Values : Boolean) return String
   is
      Result : US.Unbounded_String;
      Index  : Natural := Template'First;
   begin
      while Index <= Template'Last loop
         if Template (Index) /= '{' then
            US.Append (Result, Template (Index));
            Index := Index + 1;
         else
            declare
               Relative_Close : constant Natural := Ada.Strings.Fixed.Index
                 (Template (Index .. Template'Last), "}");
               Close : constant Natural := Relative_Close;
            begin
               if Close = 0 or else Close = Index + 1 then
                  raise Invalid_Request with "invalid modeled URI template";
               end if;
               declare
                  Raw_Label : constant String :=
                    Template (Index + 1 .. Close - 1);
                  Greedy : constant Boolean :=
                    Raw_Label (Raw_Label'Last) = '+';
                  Label : constant String :=
                    (if Greedy
                     then Raw_Label (Raw_Label'First .. Raw_Label'Last - 1)
                     else Raw_Label);
                  Found : Boolean := False;
               begin
                  for Value_Index in Values'Range loop
                     if Value_Members (Value_Index) > 0
                       and then Model.Location
                         (Input_Shape, Value_Members (Value_Index)) =
                           Model.URI_Location
                       and then Model.Member_Location_Name
                         (Input_Shape, Value_Members (Value_Index)) = Label
                     then
                        if Found then
                           raise Invalid_Request with
                             "duplicate modeled URI member";
                        end if;
                        if Encode_Values then
                           US.Append
                             (Result,
                              Encoding.URI_Encode
                                (US.To_String (Values (Value_Index).Value),
                                 Encode_Slash => not Greedy));
                        else
                           US.Append
                             (Result,
                              US.To_String (Values (Value_Index).Value));
                        end if;
                        Found := True;
                     end if;
                  end loop;
                  if not Found then
                     raise Invalid_Request with
                       "missing modeled URI member " & Label;
                  end if;
                  Index := Close + 1;
               end;
            end;
         end if;
      end loop;
      return US.To_String (Result);
   end Expand_Model_Path;

   function Valid_Model_Scalar
     (Shape : Model.Shape_Index; Value : String) return Boolean
   is
      function Within_Length_Bounds return Boolean is
         Minimum : constant String := Model.Minimum (Shape);
         Maximum : constant String := Model.Maximum (Shape);
      begin
         return
           (Minimum'Length = 0
            or else Value'Length >= Natural'Value (Minimum))
           and then
           (Maximum'Length = 0
            or else Value'Length <= Natural'Value (Maximum));
      end Within_Length_Bounds;

      function Matches_Pattern return Boolean is
         Pattern : constant String := Model.Pattern (Shape);
      begin
         if Pattern'Length = 0 then
            return True;
         elsif Pattern = "\/?.+\/.+" and then Value'Length >= 3 then
            declare
               Start : constant Positive :=
                 Value'First + Boolean'Pos (Value (Value'First) = '/');
               Slash : constant Natural := Ada.Strings.Fixed.Index
                 (Value (Start .. Value'Last), "/");
            begin
               return Slash > Start and then Slash < Value'Last;
            end;
         else
            --  The pinned S3 model has only the source-path pattern on a
            --  serialized non-body scalar. Fail closed if that changes.
            return False;
         end if;
      end Matches_Pattern;
   begin
      if Model.Enumeration_Count (Shape) > 0 then
         declare
            Found : Boolean := False;
         begin
            for Index in 1 .. Model.Enumeration_Count (Shape) loop
               Found := Found or else
                 Model.Enumeration_Value (Shape, Index) = Value;
            end loop;
            if not Found then
               return False;
            end if;
         end;
      end if;
      case Model.Kind (Shape) is
         when Model.Boolean_Shape =>
            return Value = "true" or else Value = "false";
         when Model.Integer_Shape | Model.Long_Shape =>
            declare
               Number : Long_Long_Integer;
               Minimum : constant String := Model.Minimum (Shape);
               Maximum : constant String := Model.Maximum (Shape);
            begin
               Number := Long_Long_Integer'Value (Value);
               return
                 (Minimum'Length = 0
                  or else Number >= Long_Long_Integer'Value (Minimum))
                 and then
                 (Maximum'Length = 0
                  or else Number <= Long_Long_Integer'Value (Maximum));
            exception
               when Constraint_Error =>
                  return False;
            end;
         when Model.List_Shape =>
            declare
               Reference : constant Model.Shape_Reference :=
                 Model.List_Member_Shape (Shape);
               First : Positive := Value'First;
            begin
               if Reference = Model.No_Shape or else Value'Length = 0 then
                  return False;
               end if;
               for Index in Value'Range loop
                  if Value (Index) = ',' then
                     if Index = First
                       or else not Valid_Model_Scalar
                         (Model.Shape_Index (Reference),
                          Value (First .. Index - 1))
                     then
                        return False;
                     end if;
                     First := Index + 1;
                  end if;
               end loop;
               return First <= Value'Last
                 and then Valid_Model_Scalar
                   (Model.Shape_Index (Reference),
                    Value (First .. Value'Last));
            end;
         when Model.String_Shape =>
            return Within_Length_Bounds and then Matches_Pattern;
         when others =>
            return True;
      end case;
   end Valid_Model_Scalar;

   function Prepare_Model_Request
     (Operation      : Model.Operation_Id;
      Origin         : Flyology.HTTP.Origin;
      Style          : Addressing_Style;
      Values         : Model_Value_Array;
      Payload        : String;
      Payload_Is_Set : Boolean;
      Payload_SHA256 : String;
      Identity       : Credentials;
      Region         : String;
      Timestamp      : String) return Prepared_Request
   is
      Input_Reference : constant Model.Shape_Reference :=
        Model.Input_Shape (Operation);
      Input_Shape : constant Model.Shape_Index :=
        (if Input_Reference = Model.No_Shape
         then Model.Shape_Index'First
         else Model.Shape_Index (Input_Reference));
      Member_Count : constant Natural :=
        (if Input_Reference = Model.No_Shape
         then 0 else Model.Member_Count (Input_Shape));
      Value_Members : Natural_Array (Values'Range) := (others => 0);
      Seen : Boolean_Array (1 .. Member_Count) := (others => False);
      Query_Count : Natural := Fixed_Query_Count
        (Model.Request_URI (Operation));
      Header_Count : Natural := 0;
      Has_Body_Member : Boolean := False;
      Bucket_Value : US.Unbounded_String;
   begin
      if Payload'Length > 0 and then not Payload_Is_Set then
         raise Invalid_Request with "modeled payload value is not present";
      end if;
      if Input_Reference = Model.No_Shape and then Values'Length > 0 then
         raise Invalid_Request with "modeled operation has no input shape";
      end if;

      for Value_Index in Values'Range loop
         declare
            Name : constant String :=
              US.To_String (Values (Value_Index).Member_Name);
            Map_Key : constant String :=
              US.To_String (Values (Value_Index).Map_Key);
            Member : constant Natural :=
              (if Input_Reference = Model.No_Shape
               then 0 else Find_Model_Member (Input_Shape, Name));
         begin
            if Name'Length = 0 or else Name'Length > 128
              or else Map_Key'Length > 1_024
              or else US.Length (Values (Value_Index).Value) > 1_048_576
              or else Member = 0
            then
               raise Invalid_Request with "invalid modeled request member";
            end if;
            Value_Members (Value_Index) := Member;
            declare
               Location : constant Model.Member_Location :=
                 Model.Location (Input_Shape, Member);
               Shape : constant Model.Shape_Index :=
                 Model.Member_Shape (Input_Shape, Member);
               Location_Name : constant String :=
                 Model.Member_Location_Name (Input_Shape, Member);
            begin
               if Location = Model.Body_Location then
                  raise Invalid_Request with
                    "modeled body members require the raw payload";
               elsif Location = Model.Headers_Location then
                  if Map_Key'Length = 0
                    or else Model.Kind (Shape) /= Model.Map_Shape
                    or else Model.Map_Key_Shape (Shape) = Model.No_Shape
                    or else Model.Map_Value_Shape (Shape) = Model.No_Shape
                    or else not Valid_Model_Scalar
                      (Model.Shape_Index (Model.Map_Key_Shape (Shape)),
                       Map_Key)
                    or else not Valid_Model_Scalar
                      (Model.Shape_Index (Model.Map_Value_Shape (Shape)),
                       US.To_String (Values (Value_Index).Value))
                  then
                     raise Invalid_Request with
                       "invalid modeled header-map member";
                  end if;
                  for Previous in Values'Range loop
                     exit when Previous = Value_Index;
                     if Value_Members (Previous) = Member
                       and then Ada.Characters.Handling.To_Lower
                         (US.To_String (Values (Previous).Map_Key)) =
                           Ada.Characters.Handling.To_Lower (Map_Key)
                     then
                        raise Invalid_Request with
                          "duplicate modeled header-map key";
                     end if;
                  end loop;
                  Seen (Member) := True;
                  Header_Count := Header_Count + 1;
               else
                  if not Valid_Model_Scalar
                    (Shape, US.To_String (Values (Value_Index).Value))
                  then
                     raise Invalid_Request with
                       "invalid modeled request scalar";
                  elsif Map_Key'Length > 0 or else Seen (Member) then
                     raise Invalid_Request with
                       "duplicate or keyed modeled scalar member";
                  end if;
                  Seen (Member) := True;
                  case Location is
                     when Model.Query_Location =>
                        Query_Count := Query_Count + 1;
                     when Model.Header_Location =>
                        if Location_Name = "Content-Length" then
                           if not Payload_Is_Set
                             or else Long_Long_Integer'Value
                               (US.To_String (Values (Value_Index).Value)) /=
                                 Payload'Length
                           then
                              raise Invalid_Request with
                                "modeled content length does not match body";
                           end if;
                        else
                           Header_Count := Header_Count + 1;
                        end if;
                     when Model.URI_Location =>
                        if Model.Member_Location_Name
                          (Input_Shape, Member) = "Bucket"
                        then
                           Bucket_Value := Values (Value_Index).Value;
                        end if;
                     when others =>
                        null;
                  end case;
               end if;
            end;
         end;
      end loop;

      if Input_Reference /= Model.No_Shape and then Member_Count > 0 then
         for Member in 1 .. Member_Count loop
            if Model.Location (Input_Shape, Member) = Model.Body_Location then
               Has_Body_Member := True;
            end if;
            if Model.Member_Required (Input_Shape, Member)
              and then
                (if Model.Location (Input_Shape, Member) = Model.Body_Location
                 then not Payload_Is_Set
                 else not Seen (Member))
            then
               raise Invalid_Request with "missing required modeled member";
            end if;
         end loop;
      end if;
      if Payload_Is_Set and then not Has_Body_Member then
         raise Invalid_Request with "modeled operation has no request body";
      end if;

      declare
         URI : constant String := Model.Request_URI (Operation);
         Raw_Path : constant String := Expand_Model_Path
           (Model_Path_Template (URI, Style), Input_Shape, Values,
            Value_Members, Encode_Values => True);
         Signing_Path : constant String := Expand_Model_Path
           (Model_Path_Template (URI, Style), Input_Shape, Values,
            Value_Members, Encode_Values => False);
         Host : constant String := Authority (Origin);
         Origin_Host : constant String := Flyology.HTTP.Host (Origin);
         Bucket : constant String := US.To_String (Bucket_Value);
         Query : SigV4.Name_Value_Array (1 .. Query_Count);
         Query_Last : Natural := 0;
         Token_Value : constant String := Session_Token (Identity);
         Headers : SigV4.Name_Value_Array
           (1 .. 3 + Boolean'Pos (Token_Value'Length > 0) + Header_Count);
         Header_Last : Natural := 3;
         Hash : constant String :=
           (if Payload_SHA256'Length > 0 then Payload_SHA256
            elsif Model.Unsigned_Payload (Operation)
            then SigV4.Unsigned_Payload
            elsif Payload_Is_Set then SigV4.SHA256_Hex (Payload)
            else SigV4.Empty_Payload_Hash);
         Method : constant String := Model_Method (Model.Method (Operation));
         Signing : SigV4.Signing_Result;
         Message : Flyology.HTTP.Client.Request;
      begin
         if (Payload_SHA256'Length > 0
             and then Payload_SHA256 /= SigV4.Unsigned_Payload
             and then not Encoding.Valid_SHA256_Hex (Payload_SHA256))
           or else (Hash = SigV4.Unsigned_Payload
                    and then Flyology.HTTP.Scheme (Origin) /=
                      Flyology.HTTP.Secure_HTTPS)
           or else (Style = Virtual_Hosted_Style
                    and then Bucket'Length > 0
                    and then not Starts_With (Origin_Host, Bucket & "."))
         then
            raise Invalid_Request with "invalid modeled signing parameters";
         end if;
         Append_Fixed_Query (URI, Query, Query_Last);
         for Value_Index in Values'Range loop
            declare
               Member : constant Positive := Value_Members (Value_Index);
               Location : constant Model.Member_Location :=
                 Model.Location (Input_Shape, Member);
            begin
               if Location = Model.Query_Location then
                  Query_Last := Query_Last + 1;
                  Query (Query_Last) := SigV4.Pair
                    (Model.Member_Location_Name (Input_Shape, Member),
                     US.To_String (Values (Value_Index).Value));
               end if;
            end;
         end loop;
         Headers (1) := SigV4.Pair ("host", Host);
         Headers (2) := SigV4.Pair ("x-amz-content-sha256", Hash);
         Headers (3) := SigV4.Pair ("x-amz-date", Timestamp);
         if Token_Value'Length > 0 then
            Header_Last := Header_Last + 1;
            Headers (Header_Last) :=
              SigV4.Pair ("x-amz-security-token", Token_Value);
         end if;
         for Value_Index in Values'Range loop
            declare
               Member : constant Positive := Value_Members (Value_Index);
               Location : constant Model.Member_Location :=
                 Model.Location (Input_Shape, Member);
               Name : constant String :=
                 (if Location = Model.Headers_Location
                  then Model.Member_Location_Name (Input_Shape, Member) &
                    US.To_String (Values (Value_Index).Map_Key)
                  else Model.Member_Location_Name (Input_Shape, Member));
            begin
               if Location = Model.Header_Location
                 and then Name /= "Content-Length"
               then
                  Header_Last := Header_Last + 1;
                  Headers (Header_Last) := SigV4.Pair
                    (Name, US.To_String (Values (Value_Index).Value));
               elsif Location = Model.Headers_Location
               then
                  Header_Last := Header_Last + 1;
                  Headers (Header_Last) := SigV4.Pair
                    (Name, US.To_String (Values (Value_Index).Value));
               end if;
            end;
         end loop;
         declare
            Canonical_Query : constant String := SigV4.Canonical_Query (Query);
            Target_Query : constant String := Wire_Query (Canonical_Query);
            Target : constant String := Raw_Path &
              (if Target_Query'Length = 0 then "" else "?" & Target_Query);
         begin
            if Raw_Path'Length = 0 or else Target'Length > 8_192 then
               raise Invalid_Request with "invalid modeled request target";
            end if;
            Signing := SigV4.Sign
              (Method, Signing_Path, Query, Headers, Hash,
               Access_Key (Identity), Secret_Key (Identity), Region,
               Timestamp);
            Flyology.HTTP.Client.Set_Method
              (Message, Flyology.HTTP.To_Method (Method));
            Flyology.HTTP.Client.Set_Target (Message, Target);
            Flyology.HTTP.Client.Add_Header
              (Message, "x-amz-content-sha256", Hash);
            Flyology.HTTP.Client.Add_Header
              (Message, "x-amz-date", Timestamp);
            if Token_Value'Length > 0 then
               Flyology.HTTP.Client.Add_Header
                 (Message, "x-amz-security-token", Token_Value);
            end if;
            for Index in 4 + Boolean'Pos (Token_Value'Length > 0) ..
              Headers'Last
            loop
               Flyology.HTTP.Client.Add_Header
                 (Message, US.To_String (Headers (Index).Name),
                  US.To_String (Headers (Index).Value));
            end loop;
            Flyology.HTTP.Client.Add_Header
              (Message, "authorization",
               US.To_String (Signing.Authorization));
            if Payload_Is_Set then
               Flyology.HTTP.Client.Set_Body (Message, Payload);
            end if;
            return
              (Operation         => Model_Driven_Operation,
               Modeled_Operation => Operation,
               Message           => Message,
               Target_Value      => US.To_Unbounded_String (Target),
               Authority_Value   => US.To_Unbounded_String (Host),
               Signing           => Signing);
         end;
      end;
   exception
      when SigV4.Invalid_Signing_Input |
           Flyology.HTTP.Headers.Headers_Too_Large |
           Constraint_Error =>
         raise Invalid_Request with "invalid modeled S3 request";
   end Prepare_Model_Request;

   function Prepare_Model_Streaming_Request
     (Operation      : Model.Operation_Id;
      Origin         : Flyology.HTTP.Origin;
      Style          : Addressing_Style;
      Values         : Model_Value_Array;
      Payload_SHA256 : String;
      Identity       : Credentials;
      Region         : String;
      Timestamp      : String) return Prepared_Request is
   begin
      if Payload_SHA256'Length = 0 then
         raise Invalid_Request with
           "streaming modeled request requires a payload hash";
      end if;
      for Value of Values loop
         if US.To_String (Value.Member_Name) = "ContentLength" then
            raise Invalid_Request with
              "streaming source owns the modeled content length";
         end if;
      end loop;
      return Prepare_Model_Request
        (Operation, Origin, Style, Values, "", True, Payload_SHA256,
         Identity, Region, Timestamp);
   end Prepare_Model_Streaming_Request;

   function Execute_Model_Request
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response is
   begin
      if Prepared.Operation /= Model_Driven_Operation then
         raise Invalid_Request with "prepared request is not model-driven";
      end if;
      return Flyology.HTTP.Client.Execute
        (Client, Prepared.Message, Timeout, Token);
   end Execute_Model_Request;

   function Execute_Model_Request
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response is
   begin
      if Prepared.Operation /= Model_Driven_Operation then
         raise Invalid_Request with "prepared request is not model-driven";
      end if;
      return Flyology.HTTP.Client.Execute
        (Client, Prepared.Message, Source, Timeout, Token);
   end Execute_Model_Request;

   function Authority (Origin : Flyology.HTTP.Origin) return String is
      Host : constant String := Flyology.HTTP.Host (Origin);
      Port : constant Flyology.HTTP.Port_Number := Flyology.HTTP.Port (Origin);
      Default_Port : constant Flyology.HTTP.Port_Number :=
        (if Flyology.HTTP.Scheme (Origin) = Flyology.HTTP.Plain_HTTP
         then 80 else 443);
      Host_Text : constant String :=
        (if Ada.Strings.Fixed.Index (Host, ":") = 0
         then Host else "[" & Host & "]");
   begin
      if Port = Default_Port then
         return Host_Text;
      else
         return Host_Text & ":" &
           Ada.Strings.Fixed.Trim
             (Flyology.HTTP.Port_Number'Image (Port), Ada.Strings.Both);
      end if;
   end Authority;

   function Wire_Query (Canonical : String) return String is
      Result : String (1 .. Canonical'Length);
      Last   : Natural := 0;
   begin
      for Index in Canonical'Range loop
         if Canonical (Index) /= '='
           or else (Index < Canonical'Last
                    and then Canonical (Index + 1) /= '&')
         then
            Last := Last + 1;
            Result (Last) := Canonical (Index);
         end if;
      end loop;
      return Result (1 .. Last);
   end Wire_Query;

   function Prepare_Object_Request
     (Operation : Operation_Kind;
      Method    : String;
      Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Query     : SigV4.Name_Value_Array;
      Additional_Headers : SigV4.Name_Value_Array;
      Payload   : String;
      Payload_Hash_Value : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String;
      Object_Resource : Boolean := True) return Prepared_Request
   is
      Host : constant String := Authority (Origin);
      Origin_Host : constant String := Flyology.HTTP.Host (Origin);
      Virtual_Prefix : constant String := Bucket & ".";
      Raw_Path : constant String :=
        (if Object_Resource and then Style = Path_Style
         then "/" & Bucket & "/" & Key
         elsif Object_Resource
         then "/" & Key
         elsif Style = Path_Style
         then "/" & Bucket
         else "/");
      Wire_Path : constant String :=
        Encoding.URI_Encode (Raw_Path, Encode_Slash => False);
      Canonical_Query : constant String := SigV4.Canonical_Query (Query);
      Target_Query : constant String := Wire_Query (Canonical_Query);
      Target : constant String :=
        Wire_Path &
        (if Target_Query'Length = 0 then "" else "?" & Target_Query);
      Payload_Hash : constant String :=
        (if Payload_Hash_Value'Length > 0 then Payload_Hash_Value
         elsif Payload'Length = 0 then SigV4.Empty_Payload_Hash
         else SigV4.SHA256_Hex (Payload));
      Token : constant String := Session_Token (Identity);
      Headers : SigV4.Name_Value_Array
        (1 .. (if Token'Length = 0 then 3 else 4) +
           Additional_Headers'Length);
      Last : Positive := 3;
      Signing : SigV4.Signing_Result;
      Message : Flyology.HTTP.Client.Request;
   begin
      if not Valid_Bucket_Name (Bucket)
        or else (Object_Resource and then not Valid_Object_Key (Key))
        or else (Style = Virtual_Hosted_Style
                 and then not Starts_With (Origin_Host, Virtual_Prefix))
        or else Target'Length > 8_192
      then
         raise Invalid_Request with "invalid S3 resource request target";
      end if;
      Headers (1) := SigV4.Pair ("host", Host);
      Headers (2) := SigV4.Pair ("x-amz-content-sha256", Payload_Hash);
      Headers (3) := SigV4.Pair ("x-amz-date", Timestamp);
      if Token'Length > 0 then
         Headers (4) := SigV4.Pair ("x-amz-security-token", Token);
         Last := 4;
      end if;
      for Header of Additional_Headers loop
         Last := Last + 1;
         Headers (Last) := Header;
      end loop;
      Signing := SigV4.Sign
        (Method, Raw_Path, Query, Headers, Payload_Hash,
         Access_Key (Identity), Secret_Key (Identity), Region, Timestamp);
      Flyology.HTTP.Client.Set_Method
        (Message, Flyology.HTTP.To_Method (Method));
      Flyology.HTTP.Client.Set_Target (Message, Target);
      Flyology.HTTP.Client.Add_Header
        (Message, "x-amz-content-sha256", Payload_Hash);
      Flyology.HTTP.Client.Add_Header (Message, "x-amz-date", Timestamp);
      if Token'Length > 0 then
         Flyology.HTTP.Client.Add_Header
           (Message, "x-amz-security-token", Token);
      end if;
      for Header of Additional_Headers loop
         Flyology.HTTP.Client.Add_Header
           (Message, US.To_String (Header.Name),
            US.To_String (Header.Value));
      end loop;
      Flyology.HTTP.Client.Add_Header
        (Message, "authorization", US.To_String (Signing.Authorization));
      if Payload'Length > 0 then
         Flyology.HTTP.Client.Set_Body (Message, Payload);
      end if;
      return
        (Operation       => Operation,
         Modeled_Operation => Model.Operation_Id'First,
         Message         => Message,
         Target_Value    => US.To_Unbounded_String (Target),
         Authority_Value => US.To_Unbounded_String (Host),
         Signing         => Signing);
   exception
      when SigV4.Invalid_Signing_Input |
           Flyology.HTTP.Headers.Headers_Too_Large |
           Constraint_Error =>
         raise Invalid_Request with "invalid signed S3 object request";
   end Prepare_Object_Request;

   function Prepare_List_Objects
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request
   is
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Has_Prefix : constant Boolean :=
        Parameters.Has_Prefix or else US.Length (Parameters.Prefix) > 0;
      Has_Delimiter : constant Boolean :=
        Parameters.Has_Delimiter or else US.Length (Parameters.Delimiter) > 0;
      Has_Marker : constant Boolean :=
        Parameters.Has_Marker or else US.Length (Parameters.Marker) > 0;
      Optional_Count : constant Natural :=
        Boolean'Pos (Has_Prefix) +
        Boolean'Pos (Has_Delimiter) +
        Boolean'Pos (Has_Marker) +
        Boolean'Pos (Parameters.Has_Max_Keys) +
        Boolean'Pos (Parameters.URL_Encoding) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (Parameters.Include_Restore_Status);
      Values : Model_Value_Array (1 .. 1 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if not Valid_Bucket_Name (Bucket)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
      then
         raise Invalid_Request with "invalid ListObjects parameters";
      end if;
      Add ("Bucket", Bucket);
      if Parameters.Has_Max_Keys then
         Add
           ("MaxKeys",
            Ada.Strings.Fixed.Trim
              (S3.Core.Page_Size'Image (Parameters.Max_Keys),
               Ada.Strings.Both));
      end if;
      if Has_Prefix then
         Add ("Prefix", US.To_String (Parameters.Prefix));
      end if;
      if Has_Delimiter then
         Add ("Delimiter", US.To_String (Parameters.Delimiter));
      end if;
      if Has_Marker then
         Add ("Marker", US.To_String (Parameters.Marker));
      end if;
      if Parameters.URL_Encoding then
         Add ("EncodingType", "url");
      end if;
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      if Parameters.Include_Restore_Status then
         Add ("OptionalObjectAttributes", "RestoreStatus");
      end if;
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.List_Objects_Operation, Origin, Style, Values, "", False,
         SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := List_Objects_Operation;
      end return;
   exception
      when Constraint_Error =>
         raise Invalid_Request with "invalid ListObjects parameters";
   end Prepare_List_Objects;

   function Decode_List_Objects_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_Outcome
   is
   begin
      if Status = 200 then
         if Request_Charged'Length > 0
           and then Request_Charged /= "requester"
         then
            raise Invalid_Response with
              "invalid ListObjects response headers";
         end if;
         return
           (Kind   => Listed,
            Status => Status,
            Result =>
              (Listing => S3.Listings.Parse_List_Objects (Payload, Limits),
               Request_Charged =>
                 US.To_Unbounded_String (Request_Charged)));
      else
         declare
            Value : S3.Errors.Error_Response :=
              S3.Errors.Parse (Payload, Limits);
         begin
            if US.Length (Value.Request_ID) = 0 then
               Value.Request_ID := US.To_Unbounded_String (Request_ID);
            end if;
            if US.Length (Value.Host_ID) = 0 then
               Value.Host_ID := US.To_Unbounded_String (Host_ID);
            end if;
            return (Kind => Rejected, Status => Status, Error => Value);
         end;
      end if;
   exception
      when S3.Listings.Malformed_Listing | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjects response";
   end Decode_List_Objects_Response;

   function Execute_List_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_Outcome
   is
   begin
      if Prepared.Operation /= List_Objects_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_Charged : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-charged");
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_List_Objects_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_Charged,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "ListObjects response exceeds XML limit";
   end Execute_List_Objects;

   function Prepare_List_Objects_V2
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_V2_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request
   is
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Has_Continuation : constant Boolean :=
        Parameters.Has_Continuation_Token
        or else US.Length (Parameters.Continuation_Token) > 0;
      Has_Fetch_Owner : constant Boolean :=
        Parameters.Has_Fetch_Owner or else Parameters.Fetch_Owner;
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Prefix) > 0) +
        Boolean'Pos (US.Length (Parameters.Delimiter) > 0) +
        Boolean'Pos (Has_Continuation) +
        Boolean'Pos (US.Length (Parameters.Start_After) > 0) +
        Boolean'Pos (Has_Fetch_Owner) +
        Boolean'Pos (Parameters.URL_Encoding) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (Parameters.Include_Restore_Status);
      Values : Model_Value_Array (1 .. 2 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if not Valid_Bucket_Name (Bucket)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
      then
         raise Invalid_Request with "invalid ListObjectsV2 parameters";
      end if;
      Add ("Bucket", Bucket);
      Add
        ("MaxKeys",
         Ada.Strings.Fixed.Trim
           (S3.Core.Page_Size'Image (Parameters.Max_Keys), Ada.Strings.Both));
      Add_Optional ("Prefix", Parameters.Prefix);
      Add_Optional ("Delimiter", Parameters.Delimiter);
      if Has_Continuation then
         Add ("ContinuationToken", US.To_String
           (Parameters.Continuation_Token));
      end if;
      Add_Optional ("StartAfter", Parameters.Start_After);
      if Has_Fetch_Owner then
         Add
           ("FetchOwner",
            (if Parameters.Fetch_Owner then "true" else "false"));
      end if;
      if Parameters.URL_Encoding then
         Add ("EncodingType", "url");
      end if;
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      if Parameters.Include_Restore_Status then
         Add ("OptionalObjectAttributes", "RestoreStatus");
      end if;
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.List_Objects_V2_Operation, Origin, Style, Values, "", False,
         SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := List_Objects_V2_Operation;
      end return;
   exception
      when Constraint_Error =>
         raise Invalid_Request with "invalid ListObjectsV2 parameters";
   end Prepare_List_Objects_V2;

   function Decode_List_Objects_V2_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Request_Charged : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome
   is
   begin
      if Status = 200 then
         if Request_Charged'Length > 0
           and then Request_Charged /= "requester"
         then
            raise Invalid_Response with
              "invalid ListObjectsV2 response headers";
         end if;
         return
           (Kind    => Listed,
            Status  => Status,
            Listing => S3.Listings.Parse_List_Objects_V2 (Payload, Limits),
            Request_Charged => US.To_Unbounded_String (Request_Charged));
      else
         declare
            Value : S3.Errors.Error_Response :=
              S3.Errors.Parse (Payload, Limits);
         begin
            if US.Length (Value.Request_ID) = 0 then
               Value.Request_ID := US.To_Unbounded_String (Request_ID);
            end if;
            if US.Length (Value.Host_ID) = 0 then
               Value.Host_ID := US.To_Unbounded_String (Host_ID);
            end if;
            return (Kind => Rejected, Status => Status, Error => Value);
         end;
      end if;
   exception
      when S3.Listings.Malformed_Listing | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjectsV2 response";
   end Decode_List_Objects_V2_Response;

   function Execute_List_Objects_V2
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome
   is
   begin
      if Prepared.Operation /= List_Objects_V2_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Request_Charged : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-charged");
      begin
         declare
            Payload : constant Flyology.Bytes.Unbounded_Bytes :=
              Flyology.HTTP.Client.Read_All
                (Response, Limits.Maximum_Document_Bytes, Token);
         begin
            return Decode_List_Objects_V2_Response
              (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
               Host_ID, Request_Charged, Limits);
         end;
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "ListObjectsV2 response exceeds XML limit";
   end Execute_List_Objects_V2;

   function Error_Response
     (Payload, Request_ID, Host_ID : String;
      Limits : S3.XML.Parse_Limits) return S3.Errors.Error_Response
   is
      Value : S3.Errors.Error_Response := S3.Errors.Parse (Payload, Limits);
   begin
      if US.Length (Value.Request_ID) = 0 then
         Value.Request_ID := US.To_Unbounded_String (Request_ID);
      end if;
      if US.Length (Value.Host_ID) = 0 then
         Value.Host_ID := US.To_Unbounded_String (Host_ID);
      end if;
      return Value;
   end Error_Response;

   function Prepare_Create_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String;
      Content_Type : String := "") return Prepared_Request
   is
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("uploads", ""));
      Headers : constant SigV4.Name_Value_Array :=
        (if Content_Type'Length = 0
         then No_Headers
         else (1 => SigV4.Pair ("content-type", Content_Type)));
   begin
      return Prepare_Object_Request
        (Create_Multipart_Operation, "POST", Origin, Style, Bucket, Key,
         Query, Headers, "", "", Identity, Region, Timestamp);
   end Prepare_Create_Multipart_Upload;

   function Decode_Create_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Multipart_Outcome
   is
   begin
      if Status = 200 then
         return
           (Kind   => Created,
            Status => Status,
            Result => S3.Multipart.Parse_Create_Result (Payload, Limits));
      else
         return
           (Kind   => Create_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Multipart.Malformed_Multipart | S3.Errors.Malformed_Error =>
         raise Invalid_Response with
           "malformed CreateMultipartUpload response";
   end Decode_Create_Multipart_Response;

   function Execute_Create_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Multipart_Outcome
   is
   begin
      if Prepared.Operation /= Create_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Create_Multipart_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "CreateMultipartUpload response exceeds XML limit";
   end Execute_Create_Multipart_Upload;

   function Prepare_Complete_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String) return Prepared_Request
   is
      Parameters : constant Complete_Multipart_Parameters := (others => <>);
   begin
      return Prepare_Complete_Multipart_Upload
        (Origin, Style, Bucket, Key, Upload_ID, Completion, Parameters,
         Identity, Region, Timestamp);
   end Prepare_Complete_Multipart_Upload;

   function Prepare_Complete_Multipart_Upload
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Upload_ID  : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Complete_Multipart_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      SSE_Algorithm : constant String :=
        US.To_String (Parameters.SSE_Customer_Algorithm);
      SSE_Key : constant String := US.To_String (Parameters.SSE_Customer_Key);
      SSE_Key_MD5 : constant String :=
        US.To_String (Parameters.SSE_Customer_Key_MD5);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Checksum_CRC32) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_CRC32C) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_CRC64NVME) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_SHA1) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_SHA256) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_SHA512) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_MD5) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_XXHASH64) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_XXHASH3) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_XXHASH128) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_Type) > 0) +
        Boolean'Pos (Parameters.Mpu_Object_Size.Is_Set) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (US.Length (Parameters.If_Match) > 0) +
        Boolean'Pos (US.Length (Parameters.If_None_Match) > 0) +
        Boolean'Pos (SSE_Algorithm'Length > 0) +
        Boolean'Pos (SSE_Key'Length > 0) +
        Boolean'Pos (SSE_Key_MD5'Length > 0);
      Values : Model_Value_Array (1 .. 3 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if Upload_ID'Length not in 1 .. 8_192
        or else not Valid_Optional_Checksum (Parameters.Checksum_CRC32, 4)
        or else not Valid_Optional_Checksum (Parameters.Checksum_CRC32C, 4)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_CRC64NVME, 8)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA1, 20)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA256, 32)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA512, 64)
        or else not Valid_Optional_Checksum (Parameters.Checksum_MD5, 16)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH64, 8)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH3, 8)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH128, 16)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
        or else not Valid_SSE_C_Group
          (SSE_Algorithm, SSE_Key, SSE_Key_MD5)
        or else (SSE_Key'Length > 0
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
      then
         raise Invalid_Request with
           "invalid CompleteMultipartUpload parameters";
      end if;

      Add ("Bucket", Bucket);
      Add ("Key", Key);
      Add ("UploadId", Upload_ID);
      Add_Optional ("ChecksumCRC32", Parameters.Checksum_CRC32);
      Add_Optional ("ChecksumCRC32C", Parameters.Checksum_CRC32C);
      Add_Optional ("ChecksumCRC64NVME", Parameters.Checksum_CRC64NVME);
      Add_Optional ("ChecksumSHA1", Parameters.Checksum_SHA1);
      Add_Optional ("ChecksumSHA256", Parameters.Checksum_SHA256);
      Add_Optional ("ChecksumSHA512", Parameters.Checksum_SHA512);
      Add_Optional ("ChecksumMD5", Parameters.Checksum_MD5);
      Add_Optional ("ChecksumXXHASH64", Parameters.Checksum_XXHASH64);
      Add_Optional ("ChecksumXXHASH3", Parameters.Checksum_XXHASH3);
      Add_Optional ("ChecksumXXHASH128", Parameters.Checksum_XXHASH128);
      Add_Optional ("ChecksumType", Parameters.Checksum_Type);
      if Parameters.Mpu_Object_Size.Is_Set then
         Add
           ("MpuObjectSize",
            Ada.Strings.Fixed.Trim
              (Byte_Count'Image (Parameters.Mpu_Object_Size.Value),
               Ada.Strings.Both));
      end if;
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add_Optional ("IfMatch", Parameters.If_Match);
      Add_Optional ("IfNoneMatch", Parameters.If_None_Match);
      Add_Optional
        ("SSECustomerAlgorithm", Parameters.SSE_Customer_Algorithm);
      Add_Optional ("SSECustomerKey", Parameters.SSE_Customer_Key);
      Add_Optional ("SSECustomerKeyMD5", Parameters.SSE_Customer_Key_MD5);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.Complete_Multipart_Upload_Operation, Origin, Style, Values,
         S3.Multipart.Serialize_Complete_Request (Completion), True, "",
         Identity, Region, Timestamp)
      do
         Result.Operation := Complete_Multipart_Operation;
      end return;
   exception
      when S3.Multipart.Malformed_Multipart =>
         raise Invalid_Request with "invalid multipart completion body";
   end Prepare_Complete_Multipart_Upload;

   procedure Validate_Complete_Multipart_Result
     (Value : Complete_Multipart_Result) is
      Encryption : constant String :=
        US.To_String (Value.Server_Side_Encryption);
      Checksum_Type : constant String := US.To_String (Value.Checksum_Type);
      Charged : constant String := US.To_String (Value.Request_Charged);
   begin
      if US.Length (Value.Entity_Tag) = 0
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_CRC32, 4, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_CRC32C, 4, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_CRC64NVME, 8, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_SHA1, 20, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_SHA256, 32, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_SHA512, 64, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_MD5, 16, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_XXHASH64, 8, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_XXHASH3, 8, Checksum_Type)
        or else not Valid_Optional_Object_Checksum
          (Value.Checksum_XXHASH128, 16, Checksum_Type)
        or else (Checksum_Type'Length > 0
                 and then Checksum_Type not in "COMPOSITE" | "FULL_OBJECT")
        or else (Encryption'Length > 0
                 and then Encryption not in
                   "AES256" | "aws:fsx" | "aws:kms" | "aws:kms:dsse")
        or else (Charged'Length > 0 and then Charged /= "requester")
      then
         raise Invalid_Response with
           "invalid CompleteMultipartUpload response";
      end if;
   end Validate_Complete_Multipart_Result;

   function Decode_Complete_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome
   is
      Headers : constant Complete_Multipart_Response_Headers :=
        (others => <>);
   begin
      return Decode_Complete_Multipart_Response
        (Status, Payload, Headers, Request_ID, Host_ID, Limits);
   end Decode_Complete_Multipart_Response;

   function Decode_Complete_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Complete_Multipart_Response_Headers;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome
   is
   begin
      if Status = 200 then
         begin
            return
              (Kind   => Complete_Rejected,
               Status => Status,
               Error  => Error_Response
                 (Payload, Request_ID, Host_ID, Limits));
         exception
            when S3.Errors.Malformed_Error =>
               declare
                  Parsed : constant
                    S3.Multipart.Complete_Multipart_Upload_Result :=
                    S3.Multipart.Parse_Complete_Result (Payload, Limits);
                  Result : constant Complete_Multipart_Result :=
                    (Location => Parsed.Location,
                     Bucket => Parsed.Bucket,
                     Key => Parsed.Key,
                     Expiration => Headers.Expiration,
                     Entity_Tag => Parsed.Entity_Tag,
                     Checksum_CRC32 => Parsed.Checksum_CRC32,
                     Checksum_CRC32C => Parsed.Checksum_CRC32C,
                     Checksum_CRC64NVME => Parsed.Checksum_CRC64NVME,
                     Checksum_SHA1 => Parsed.Checksum_SHA1,
                     Checksum_SHA256 => Parsed.Checksum_SHA256,
                     Checksum_SHA512 => Parsed.Checksum_SHA512,
                     Checksum_MD5 => Parsed.Checksum_MD5,
                     Checksum_XXHASH64 => Parsed.Checksum_XXHASH64,
                     Checksum_XXHASH3 => Parsed.Checksum_XXHASH3,
                     Checksum_XXHASH128 => Parsed.Checksum_XXHASH128,
                     Checksum_Type => Parsed.Checksum_Type,
                     Server_Side_Encryption =>
                       Headers.Server_Side_Encryption,
                     Version_ID => Headers.Version_ID,
                     SSE_KMS_Key_ID => Headers.SSE_KMS_Key_ID,
                     Bucket_Key_Enabled => Headers.Bucket_Key_Enabled,
                     Request_Charged => Headers.Request_Charged);
               begin
                  Validate_Complete_Multipart_Result (Result);
                  return
                    (Kind => Completed, Status => Status, Result => Result);
               end;
         end;
      else
         return
           (Kind   => Complete_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Multipart.Malformed_Multipart | S3.Errors.Malformed_Error =>
         raise Invalid_Response with
           "malformed CompleteMultipartUpload response";
   end Decode_Complete_Multipart_Response;

   function Execute_Complete_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome
   is
   begin
      if Prepared.Operation /= Complete_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Complete_Multipart_Response_Headers :=
           (Expiration => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-expiration")),
            Server_Side_Encryption => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption")),
            Version_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-version-id")),
            SSE_KMS_Key_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-aws-kms-key-id")),
            Bucket_Key_Enabled => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-bucket-key-enabled")),
            Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Complete_Multipart_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "CompleteMultipartUpload response exceeds XML limit";
   end Execute_Complete_Multipart_Upload;

   function Prepare_Abort_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String) return Prepared_Request
   is
      Parameters : constant Abort_Multipart_Parameters := (others => <>);
   begin
      return Prepare_Abort_Multipart_Upload
        (Origin, Style, Bucket, Key, Upload_ID, Parameters, Identity,
         Region, Timestamp);
   end Prepare_Abort_Multipart_Upload;

   function Prepare_Abort_Multipart_Upload
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Upload_ID  : String;
      Parameters : Abort_Multipart_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("uploadId", Upload_ID));
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Initiated : constant String :=
        US.To_String (Parameters.If_Match_Initiated_Time);
      Header_Count : constant Natural :=
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (Initiated'Length > 0);
      Headers : SigV4.Name_Value_Array (1 .. Header_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         if Value'Length > 0 then
            Last := Last + 1;
            Headers (Last) := SigV4.Pair (Name, Value);
         end if;
      end Add;
   begin
      if Upload_ID'Length = 0 or else Upload_ID'Length > 8_192 then
         raise Invalid_Request with "invalid multipart upload identifier";
      elsif Request_Payer'Length > 0 and then Request_Payer /= "requester"
      then
         raise Invalid_Request with "invalid AbortMultipartUpload payer";
      elsif Initiated'Length > 0
        and then not S3.Object_Reads.Parse_Conditional_Date (Initiated).Valid
      then
         raise Invalid_Request with
           "invalid AbortMultipartUpload initiation time";
      end if;
      Add ("x-amz-request-payer", Request_Payer);
      Add
        ("x-amz-expected-bucket-owner",
         US.To_String (Parameters.Expected_Bucket_Owner));
      Add ("x-amz-if-match-initiated-time", Initiated);
      return Prepare_Object_Request
        (Abort_Multipart_Operation, "DELETE", Origin, Style, Bucket, Key,
         Query, Headers, "", "", Identity, Region, Timestamp);
   end Prepare_Abort_Multipart_Upload;

   function Prepare_List_Buckets
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Parameters : List_Buckets_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Optional_Count : constant Natural :=
        Boolean'Pos (Parameters.Has_Max_Buckets) +
        Boolean'Pos
          (Parameters.Has_Continuation_Token
           or else US.Length (Parameters.Continuation_Token) > 0) +
        Boolean'Pos
          (Parameters.Has_Prefix or else US.Length (Parameters.Prefix) > 0) +
        Boolean'Pos (US.Length (Parameters.Bucket_Region) > 0);
      Values : Model_Value_Array (1 .. Optional_Count);
      Last   : Natural := 0;

      procedure Add
        (Name, Value : String; Present : Boolean := True) is
      begin
         if Present then
            Last := Last + 1;
            Values (Last) :=
              (Member_Name => US.To_Unbounded_String (Name),
               Map_Key     => US.Null_Unbounded_String,
               Value       => US.To_Unbounded_String (Value));
         end if;
      end Add;
   begin
      if US.Length (Parameters.Continuation_Token) >
        S3.Buckets.Maximum_Continuation_Token_Length
      then
         raise Invalid_Request with
           "ListBuckets continuation token exceeds 1,024 bytes";
      end if;
      if Parameters.Has_Max_Buckets then
         Add
           ("MaxBuckets",
            Ada.Strings.Fixed.Trim
              (S3.Buckets.Max_Buckets_Value'Image
                 (Parameters.Max_Buckets),
               Ada.Strings.Both));
      end if;
      Add
        ("ContinuationToken",
         US.To_String (Parameters.Continuation_Token),
         Parameters.Has_Continuation_Token
           or else US.Length (Parameters.Continuation_Token) > 0);
      Add
        ("Prefix", US.To_String (Parameters.Prefix),
         Parameters.Has_Prefix or else US.Length (Parameters.Prefix) > 0);
      Add
        ("BucketRegion", US.To_String (Parameters.Bucket_Region),
         US.Length (Parameters.Bucket_Region) > 0);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.List_Buckets_Operation, Origin, Style, Values, "", False, "",
         Identity, Region, Timestamp)
      do
         Result.Operation := List_Buckets_Operation;
      end return;
   end Prepare_List_Buckets;

   function Decode_List_Buckets_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome
   is
   begin
      if Status = 200 then
         return
           (Kind   => Buckets_Listed,
            Status => Status,
            Result => S3.Buckets.Parse_List_Buckets (Payload, Limits));
      else
         return
           (Kind   => List_Buckets_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Buckets.Malformed_Bucket_Listing |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListBuckets response";
   end Decode_List_Buckets_Response;

   function Execute_List_Buckets
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome
   is
   begin
      if Prepared.Operation /= List_Buckets_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_List_Buckets_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "ListBuckets response exceeds XML limit";
   end Execute_List_Buckets;

   function Whitespace_Only (Value : String) return Boolean is
   begin
      for Item of Value loop
         if Item /= ' '
           and then Item /= Character'Val (9)
           and then Item /= Character'Val (10)
           and then Item /= Character'Val (13)
         then
            return False;
         end if;
      end loop;
      return True;
   end Whitespace_Only;

   function Valid_Create_ACL (Value : String) return Boolean is
     (Value'Length = 0
      or else Value = "private"
      or else Value = "public-read"
      or else Value = "public-read-write"
      or else Value = "authenticated-read");

   function Valid_Object_Ownership (Value : String) return Boolean is
     (Value'Length = 0
      or else Value = "BucketOwnerPreferred"
      or else Value = "ObjectWriter"
      or else Value = "BucketOwnerEnforced");

   function Valid_Bucket_Namespace (Value : String) return Boolean is
     (Value'Length = 0
      or else Value = "account-regional"
      or else Value = "global");

   function Prepare_Create_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Create_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      ACL : constant String := US.To_String (Parameters.ACL);
      Ownership : constant String :=
        US.To_String (Parameters.Object_Ownership);
      Namespace : constant String :=
        US.To_String (Parameters.Bucket_Namespace);
      Optional_Header_Count : constant Natural :=
        Boolean'Pos (ACL'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Full_Control) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Read) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Read_ACP) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Write) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Write_ACP) > 0) +
        Boolean'Pos (Parameters.Object_Lock_Enabled.Is_Set) +
        Boolean'Pos (Ownership'Length > 0) +
        Boolean'Pos (Namespace'Length > 0);
      Headers : SigV4.Name_Value_Array (1 .. Optional_Header_Count);
      Last : Natural := 0;

      procedure Add_Header (Name, Value : String) is
      begin
         if Value'Length > 0 then
            Last := Last + 1;
            Headers (Last) := SigV4.Pair (Name, Value);
         end if;
      end Add_Header;
   begin
      if not Valid_Create_ACL (ACL)
        or else not Valid_Object_Ownership (Ownership)
        or else not Valid_Bucket_Namespace (Namespace)
      then
         raise Invalid_Request with "invalid CreateBucket parameters";
      end if;
      Add_Header ("x-amz-acl", ACL);
      Add_Header
        ("x-amz-grant-full-control",
         US.To_String (Parameters.Grant_Full_Control));
      Add_Header ("x-amz-grant-read", US.To_String (Parameters.Grant_Read));
      Add_Header
        ("x-amz-grant-read-acp", US.To_String (Parameters.Grant_Read_ACP));
      Add_Header
        ("x-amz-grant-write", US.To_String (Parameters.Grant_Write));
      Add_Header
        ("x-amz-grant-write-acp",
         US.To_String (Parameters.Grant_Write_ACP));
      if Parameters.Object_Lock_Enabled.Is_Set then
         Add_Header
           ("x-amz-bucket-object-lock-enabled",
            (if Parameters.Object_Lock_Enabled.Value
             then "true" else "false"));
      end if;
      Add_Header ("x-amz-object-ownership", Ownership);
      Add_Header ("x-amz-bucket-namespace", Namespace);
      return Prepare_Object_Request
        (Create_Bucket_Operation, "PUT", Origin, Style, Bucket, "",
         No_Query, Headers,
         S3.Buckets.Serialize_Create_Configuration (Parameters.Configuration),
         "", Identity, Region, Timestamp, Object_Resource => False);
   exception
      when S3.Buckets.Invalid_Bucket_Configuration =>
         raise Invalid_Request with "invalid CreateBucket configuration";
   end Prepare_Create_Bucket;

   function Decode_Create_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Create_Bucket_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Bucket_Outcome
   is
      ARN : constant String := US.To_String (Headers.Bucket_ARN);
      S3_Service : constant Natural :=
        Ada.Strings.Fixed.Index (ARN, ":s3:");
      Express_Service : constant Natural :=
        Ada.Strings.Fixed.Index (ARN, ":s3express:");
      Service : constant Natural :=
        (if S3_Service > 0 then S3_Service else Express_Service);
   begin
      if Status = 200 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "CreateBucket success contains a response body";
         elsif ARN'Length > 128
           or else
             (ARN'Length > 0
              and then Ada.Strings.Fixed.Index (ARN, "arn:") /= ARN'First)
           or else
             (ARN'Length > 0 and then Service <= ARN'First + 4)
           or else
             (Service > ARN'First + 4
              and then Ada.Strings.Fixed.Index
                (ARN (ARN'First + 4 .. Service - 1), ":") > 0)
         then
            raise Invalid_Response with
              "CreateBucket returned an invalid bucket ARN";
         end if;
         return
           (Kind => Bucket_Created, Status => Status, Result => Headers);
      else
         return
           (Kind   => Create_Bucket_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed CreateBucket response";
   end Decode_Create_Bucket_Response;

   function Execute_Create_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Bucket_Outcome
   is
   begin
      if Prepared.Operation /= Create_Bucket_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Create_Bucket_Result :=
           (Location => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "location")),
            Bucket_ARN => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-bucket-arn")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Create_Bucket_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "CreateBucket response exceeds XML limit";
   end Execute_Create_Bucket;

   function Prepare_Get_Bucket_Location
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Location_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("location", ""));
      Headers : SigV4.Name_Value_Array
        (1 .. Boolean'Pos (Owner'Length > 0));
   begin
      if Owner'Length > 0 then
         Headers (1) := SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      return Prepare_Object_Request
        (Get_Bucket_Location_Operation, "GET", Origin, Style, Bucket, "",
         Query, Headers, "", "", Identity, Region, Timestamp,
         Object_Resource => False);
   end Prepare_Get_Bucket_Location;

   function Decode_Get_Bucket_Location_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Location_Outcome
   is
   begin
      if Status = 200 then
         return
           (Kind   => Bucket_Location_Found,
            Status => Status,
            Result =>
              (Location_Constraint => US.To_Unbounded_String
                 (S3.Buckets.Parse_Location_Constraint (Payload, Limits))));
      else
         return
           (Kind   => Get_Bucket_Location_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Buckets.Malformed_Bucket_Location |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed GetBucketLocation response";
   end Decode_Get_Bucket_Location_Response;

   function Execute_Get_Bucket_Location
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Location_Outcome
   is
   begin
      if Prepared.Operation /= Get_Bucket_Location_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Get_Bucket_Location_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "GetBucketLocation response exceeds XML limit";
   end Execute_Get_Bucket_Location;

   function Prepare_Put_Bucket_Versioning
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Put_Bucket_Versioning_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Payload : constant String :=
        S3.Versioning.Serialize (Parameters.Configuration);
      Supplied_MD5 : constant String :=
        US.To_String (Parameters.Content_MD5);
      MD5 : constant String :=
        (if Supplied_MD5'Length = 0
         then Content_MD5 (Payload) else Supplied_MD5);
      Checksum : constant String :=
        US.To_String (Parameters.Checksum_Algorithm);
      MFA : constant String := US.To_String (Parameters.MFA);
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Count : constant Positive :=
        2 + Boolean'Pos (Checksum'Length > 0)
          + Boolean'Pos (MFA'Length > 0)
          + Boolean'Pos (Owner'Length > 0);
      Values : Model_Value_Array (1 .. Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String; Present : Boolean := True) is
      begin
         if Present then
            Last := Last + 1;
            Values (Last) :=
              (Member_Name => US.To_Unbounded_String (Name),
               Map_Key     => US.Null_Unbounded_String,
               Value       => US.To_Unbounded_String (Value));
         end if;
      end Add;

      function Valid_Bounded_Header (Value : String) return Boolean is
      begin
         if Value'Length > 2 * 1_024 then
            return False;
         end if;
         for Character_Value of Value loop
            if Character_Value in ASCII.NUL | ASCII.CR | ASCII.LF then
               return False;
            end if;
         end loop;
         return True;
      end Valid_Bounded_Header;
   begin
      if not Wire_Core.Valid_Base64 (MD5, 16)
        or else not Valid_Bounded_Header (MFA)
        or else not Valid_Bounded_Header (Owner)
      then
         raise Invalid_Request with
           "invalid PutBucketVersioning header";
      end if;
      Add ("Bucket", Bucket);
      Add ("ContentMD5", MD5);
      Add ("ChecksumAlgorithm", Checksum, Checksum'Length > 0);
      Add ("MFA", MFA, MFA'Length > 0);
      Add ("ExpectedBucketOwner", Owner, Owner'Length > 0);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.Put_Bucket_Versioning_Operation, Origin, Style, Values,
         Payload, True, "", Identity, Region, Timestamp)
      do
         Result.Operation := Put_Bucket_Versioning_Operation;
      end return;
   end Prepare_Put_Bucket_Versioning;

   function Decode_Put_Bucket_Versioning_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Put_Bucket_Versioning_Outcome
   is
   begin
      if Status = 200 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "PutBucketVersioning success contains a response body";
         end if;
         return (Kind => Bucket_Versioning_Updated, Status => Status);
      else
         return
           (Kind   => Put_Bucket_Versioning_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with
           "malformed PutBucketVersioning response";
   end Decode_Put_Bucket_Versioning_Response;

   function Execute_Put_Bucket_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Put_Bucket_Versioning_Outcome
   is
   begin
      if Prepared.Operation /= Put_Bucket_Versioning_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Put_Bucket_Versioning_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "PutBucketVersioning response exceeds XML limit";
   end Execute_Put_Bucket_Versioning;

   function Prepare_Get_Bucket_Versioning
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Versioning_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Count : constant Positive := 1 + Boolean'Pos (Owner'Length > 0);
      Values : Model_Value_Array (1 .. Count) :=
        (1 =>
           (Member_Name => US.To_Unbounded_String ("Bucket"),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Bucket)),
         others => <>);
   begin
      if Owner'Length > 2 * 1_024
        or else Ada.Strings.Fixed.Index (Owner, String'(1 => ASCII.NUL)) > 0
        or else Ada.Strings.Fixed.Index (Owner, String'(1 => ASCII.CR)) > 0
        or else Ada.Strings.Fixed.Index (Owner, String'(1 => ASCII.LF)) > 0
      then
         raise Invalid_Request with
           "invalid GetBucketVersioning owner header";
      end if;
      if Owner'Length > 0 then
         Values (2) :=
           (Member_Name =>
              US.To_Unbounded_String ("ExpectedBucketOwner"),
            Map_Key => US.Null_Unbounded_String,
            Value   => US.To_Unbounded_String (Owner));
      end if;
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.Get_Bucket_Versioning_Operation, Origin, Style, Values,
         "", False, "", Identity, Region, Timestamp)
      do
         Result.Operation := Get_Bucket_Versioning_Operation;
      end return;
   end Prepare_Get_Bucket_Versioning;

   function Decode_Get_Bucket_Versioning_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Get_Bucket_Versioning_Outcome
   is
   begin
      if Status = 200 then
         return
           (Kind          => Bucket_Versioning_Found,
            Status        => Status,
            Configuration => S3.Versioning.Parse_Response (Payload, Limits));
      else
         return
           (Kind   => Get_Bucket_Versioning_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Versioning.Malformed_Configuration |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with
           "malformed GetBucketVersioning response";
   end Decode_Get_Bucket_Versioning_Response;

   function Execute_Get_Bucket_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Get_Bucket_Versioning_Outcome
   is
   begin
      if Prepared.Operation /= Get_Bucket_Versioning_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Get_Bucket_Versioning_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "GetBucketVersioning response exceeds XML limit";
   end Execute_Get_Bucket_Versioning;

   function Prepare_Head_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Head_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Headers : SigV4.Name_Value_Array
        (1 .. Boolean'Pos (Owner'Length > 0));
   begin
      if Owner'Length > 0 then
         Headers (1) := SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      return Prepare_Object_Request
        (Head_Bucket_Operation, "HEAD", Origin, Style, Bucket, "",
         No_Query, Headers, "", "", Identity, Region, Timestamp,
         Object_Resource => False);
   end Prepare_Head_Bucket;

   function Head_Error
     (Operation : String;
      Status : Flyology.HTTP.Status_Code; Request_ID, Host_ID : String)
      return S3.Errors.Error_Response
   is
      Status_Text : constant String :=
        Ada.Strings.Fixed.Trim
          (Flyology.HTTP.Status_Code'Image (Status), Ada.Strings.Both);
   begin
      return
         (Code       => US.To_Unbounded_String ("HTTP" & Status_Text),
         Message    => US.To_Unbounded_String
           (Operation & " returned HTTP status " & Status_Text),
         Resource   => US.Null_Unbounded_String,
         Request_ID => US.To_Unbounded_String (Request_ID),
         Host_ID    => US.To_Unbounded_String (Host_ID));
   end Head_Error;

   function Decode_Head_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Head_Bucket_Result;
      Request_ID : String := "";
      Host_ID    : String := "") return Head_Bucket_Outcome
   is
      Location_Type : constant String :=
        US.To_String (Headers.Bucket_Location_Type);
      Location_Name : constant String :=
        US.To_String (Headers.Bucket_Location_Name);
      Region : constant String := US.To_String (Headers.Bucket_Region);
   begin
      if not Whitespace_Only (Payload) then
         raise Invalid_Response with "HeadBucket contains a response body";
      elsif Status = 200 then
         if (Location_Type'Length > 0
             and then Location_Type /= "AvailabilityZone"
             and then Location_Type /= "LocalZone")
           or else US.Length (Headers.Bucket_ARN) > 128
           or else
             (Location_Name'Length > 0
              and then
                (Location_Name'Length > 63
                 or else not Encoding.Valid_Scope_Segment (Location_Name)))
           or else Region'Length > 63
           or else
             (Region'Length > 0
              and then not Encoding.Valid_Scope_Segment (Region))
         then
            raise Invalid_Response with "invalid HeadBucket response headers";
         end if;
         return (Kind => Bucket_Found, Status => Status, Result => Headers);
      else
         return
           (Kind   => Head_Bucket_Rejected,
            Status => Status,
            Error  => Head_Error
              ("HeadBucket", Status, Request_ID, Host_ID));
      end if;
   end Decode_Head_Bucket_Response;

   function Execute_Head_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Outcome
   is
   begin
      if Prepared.Operation /= Head_Bucket_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Head_Bucket_Result :=
           (Bucket_ARN => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-bucket-arn")),
            Bucket_Location_Type => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-bucket-location-type")),
            Bucket_Location_Name => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-bucket-location-name")),
            Bucket_Region => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-bucket-region")),
            Access_Point_Alias => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-access-point-alias")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All (Response, 1, Token);
      begin
         return Decode_Head_Bucket_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "HeadBucket response contains a body";
   end Execute_Head_Bucket;

   function Valid_SSE_C_Group
     (Algorithm, Key, Key_MD5 : String) return Boolean is
     ((Algorithm'Length = 0 and then Key'Length = 0
       and then Key_MD5'Length = 0)
      or else
        (Algorithm = "AES256"
         and then Wire_Core.Valid_Base64 (Key, 32)
         and then Wire_Core.Valid_Base64 (Key_MD5, 16)));

   function Prepare_Object_Read
     (Modeled_Operation : Model.Operation_Id;
      Typed_Operation   : Operation_Kind;
      Operation_Name    : String;
      Origin            : Flyology.HTTP.Origin;
      Style             : Addressing_Style;
      Bucket            : String;
      Key               : String;
      Parameters        : Head_Object_Parameters;
      Identity          : Credentials;
      Region            : String;
      Timestamp         : String) return Prepared_Request
   is
      SSE_Algorithm : constant String :=
        US.To_String (Parameters.SSE_Customer_Algorithm);
      SSE_Key : constant String := US.To_String (Parameters.SSE_Customer_Key);
      SSE_Key_MD5 : constant String :=
        US.To_String (Parameters.SSE_Customer_Key_MD5);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.If_Match) > 0) +
        Boolean'Pos (US.Length (Parameters.If_Modified_Since) > 0) +
        Boolean'Pos (US.Length (Parameters.If_None_Match) > 0) +
        Boolean'Pos (US.Length (Parameters.If_Unmodified_Since) > 0) +
        Boolean'Pos (US.Length (Parameters.Byte_Range_Header) > 0) +
        Boolean'Pos (US.Length (Parameters.Response_Cache_Control) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Response_Content_Disposition) > 0) +
        Boolean'Pos (US.Length (Parameters.Response_Content_Encoding) > 0) +
        Boolean'Pos (US.Length (Parameters.Response_Content_Language) > 0) +
        Boolean'Pos (US.Length (Parameters.Response_Content_Type) > 0) +
        Boolean'Pos (US.Length (Parameters.Response_Expires) > 0) +
        Boolean'Pos (US.Length (Parameters.Version_ID) > 0) +
        Boolean'Pos (SSE_Algorithm'Length > 0) +
        Boolean'Pos (SSE_Key'Length > 0) +
        Boolean'Pos (SSE_Key_MD5'Length > 0) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (Parameters.Part_Number.Is_Set) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (Parameters.Checksum_Mode);
      Values : Model_Value_Array (1 .. 2 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if US.Length (Parameters.Version_ID) > 8_192
        or else (US.Length (Parameters.Byte_Range_Header) > 0
                 and then S3.Core.Parse_Range_Header
                   (US.To_String (Parameters.Byte_Range_Header)).Status /=
                     S3.Core.Range_Parsed)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
        or else not Valid_SSE_C_Group
          (SSE_Algorithm, SSE_Key, SSE_Key_MD5)
        or else (SSE_Key'Length > 0
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
      then
         raise Invalid_Request with
           "invalid " & Operation_Name & " parameters";
      end if;
      Add ("Bucket", Bucket);
      Add ("Key", Key);
      Add_Optional ("IfMatch", Parameters.If_Match);
      Add_Optional ("IfModifiedSince", Parameters.If_Modified_Since);
      Add_Optional ("IfNoneMatch", Parameters.If_None_Match);
      Add_Optional ("IfUnmodifiedSince", Parameters.If_Unmodified_Since);
      Add_Optional ("Range", Parameters.Byte_Range_Header);
      Add_Optional
        ("ResponseCacheControl", Parameters.Response_Cache_Control);
      Add_Optional
        ("ResponseContentDisposition",
         Parameters.Response_Content_Disposition);
      Add_Optional
        ("ResponseContentEncoding", Parameters.Response_Content_Encoding);
      Add_Optional
        ("ResponseContentLanguage", Parameters.Response_Content_Language);
      Add_Optional
        ("ResponseContentType", Parameters.Response_Content_Type);
      Add_Optional ("ResponseExpires", Parameters.Response_Expires);
      Add_Optional ("VersionId", Parameters.Version_ID);
      Add_Optional ("SSECustomerAlgorithm",
                    Parameters.SSE_Customer_Algorithm);
      Add_Optional ("SSECustomerKey", Parameters.SSE_Customer_Key);
      Add_Optional ("SSECustomerKeyMD5", Parameters.SSE_Customer_Key_MD5);
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      if Parameters.Part_Number.Is_Set then
         Add
           ("PartNumber",
            Ada.Strings.Fixed.Trim
              (S3.Core.Part_Number'Image (Parameters.Part_Number.Value),
               Ada.Strings.Both));
      end if;
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      if Parameters.Checksum_Mode then
         Add ("ChecksumMode", "ENABLED");
      end if;
      return Result : Prepared_Request := Prepare_Model_Request
        (Modeled_Operation, Origin, Style, Values, "", False,
         SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := Typed_Operation;
      end return;
   end Prepare_Object_Read;

   function Prepare_Head_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Head_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request is
     (Prepare_Object_Read
        (Model.Head_Object_Operation, Head_Object_Operation, "HeadObject",
         Origin, Style, Bucket, Key, Parameters, Identity, Region,
         Timestamp));

   function Prepare_Get_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request is
     (Prepare_Object_Read
        (Model.Get_Object_Operation, Get_Object_Operation, "GetObject",
         Origin, Style, Bucket, Key, Parameters, Identity, Region,
         Timestamp));

   function Prepare_Get_Object_Attributes
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Attributes_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      SSE_Algorithm : constant String :=
        US.To_String (Parameters.SSE_Customer_Algorithm);
      SSE_Key : constant String := US.To_String (Parameters.SSE_Customer_Key);
      SSE_Key_MD5 : constant String :=
        US.To_String (Parameters.SSE_Customer_Key_MD5);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Version_ID) > 0) +
        Boolean'Pos (Parameters.Has_Max_Parts) +
        Boolean'Pos (Parameters.Has_Part_Number_Marker) +
        Boolean'Pos (SSE_Algorithm'Length > 0) +
        Boolean'Pos (SSE_Key'Length > 0) +
        Boolean'Pos (SSE_Key_MD5'Length > 0) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0);
      Values : Model_Value_Array (1 .. 3 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else US.Length (Parameters.Version_ID) > 8_192
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
        or else not Valid_SSE_C_Group
          (SSE_Algorithm, SSE_Key, SSE_Key_MD5)
        or else (SSE_Key'Length > 0
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
      then
         raise Invalid_Request with "invalid GetObjectAttributes parameters";
      end if;
      Add ("Bucket", Bucket);
      Add ("Key", Key);
      Add_Optional ("VersionId", Parameters.Version_ID);
      if Parameters.Has_Max_Parts then
         Add
           ("MaxParts",
            Ada.Strings.Fixed.Trim
              (S3.Core.Page_Size'Image (Parameters.Max_Parts),
               Ada.Strings.Both));
      end if;
      if Parameters.Has_Part_Number_Marker then
         Add
           ("PartNumberMarker",
            Ada.Strings.Fixed.Trim
              (S3.Attributes.Part_Marker_Value'Image
                 (Parameters.Part_Number_Marker),
               Ada.Strings.Both));
      end if;
      Add_Optional
        ("SSECustomerAlgorithm", Parameters.SSE_Customer_Algorithm);
      Add_Optional ("SSECustomerKey", Parameters.SSE_Customer_Key);
      Add_Optional ("SSECustomerKeyMD5", Parameters.SSE_Customer_Key_MD5);
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add ("ObjectAttributes", S3.Attributes.Image (Parameters.Attributes));
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.Get_Object_Attributes_Operation, Origin, Style, Values, "",
         False, SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := Get_Object_Attributes_Operation;
      end return;
   exception
      when S3.Attributes.Malformed_Attributes | Constraint_Error =>
         raise Invalid_Request with "invalid GetObjectAttributes parameters";
   end Prepare_Get_Object_Attributes;

   function Decode_Get_Object_Attributes_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Delete_Marker   : String := "";
      Last_Modified   : String := "";
      Version_ID      : String := "";
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Attributes_Outcome
   is
   begin
      if Status = 200 then
         if Request_Charged'Length > 0
           and then Request_Charged /= "requester"
         then
            raise Invalid_Response with
              "invalid GetObjectAttributes response headers";
         end if;
         return
           (Kind   => Object_Attributes_Found,
            Status => Status,
            Result =>
              (Delete_Marker => Optional_Boolean_Header (Delete_Marker),
               Last_Modified => US.To_Unbounded_String (Last_Modified),
               Version_ID => US.To_Unbounded_String (Version_ID),
               Request_Charged => US.To_Unbounded_String (Request_Charged),
               Attributes => S3.Attributes.Parse_Result (Payload, Limits)));
      end if;
      return
        (Kind   => Get_Object_Attributes_Rejected,
         Status => Status,
         Error  => Error_Response (Payload, Request_ID, Host_ID, Limits));
   exception
      when S3.Attributes.Malformed_Attributes | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed GetObjectAttributes response";
   end Decode_Get_Object_Attributes_Response;

   function Execute_Get_Object_Attributes
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Attributes_Outcome
   is
   begin
      if Prepared.Operation /= Get_Object_Attributes_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Get_Object_Attributes_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload),
            Flyology.HTTP.Client.Header (Response, "x-amz-delete-marker"),
            Flyology.HTTP.Client.Header (Response, "last-modified"),
            Flyology.HTTP.Client.Header (Response, "x-amz-version-id"),
            Flyology.HTTP.Client.Header (Response, "x-amz-request-charged"),
            Flyology.HTTP.Client.Header (Response, "x-amz-request-id"),
            Flyology.HTTP.Client.Header (Response, "x-amz-id-2"), Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "GetObjectAttributes response exceeds XML limit";
   end Execute_Get_Object_Attributes;

   function Optional_Natural_Header
     (Value : String) return Optional_Natural is
   begin
      if Value'Length = 0 then
         return (Is_Set => False, Value => 0);
      end if;
      declare
         Parsed : constant Wire_Core.Natural_Result :=
           Wire_Core.Parse_Natural (Value);
      begin
         if not Parsed.Valid then
            raise Invalid_Response with "invalid S3 natural response header";
         end if;
         return (Is_Set => True, Value => Parsed.Value);
      end;
   end Optional_Natural_Header;

   function Head_Content_Length
     (Value : String; Required : Boolean) return Byte_Count is
      Parsed : constant Wire_Core.Byte_Count_Result :=
        Wire_Core.Parse_Byte_Count (Value);
   begin
      if Value'Length = 0 and then not Required then
         return 0;
      elsif not Parsed.Valid then
         raise Invalid_Response with
           "HeadObject lacks a valid Content-Length";
      end if;
      return Parsed.Value;
   end Head_Content_Length;

   function Valid_Head_Object_Enum
     (Value : US.Unbounded_String; Member : Positive) return Boolean
   is
      Text : constant String := US.To_String (Value);
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.Head_Object_Operation));
      Shape : constant Model.Shape_Index :=
        Model.Member_Shape (Output, Member);
   begin
      if Text'Length = 0 then
         return True;
      end if;
      for Index in 1 .. Model.Enumeration_Count (Shape) loop
         if Text = Model.Enumeration_Value (Shape, Index) then
            return True;
         end if;
      end loop;
      return False;
   end Valid_Head_Object_Enum;

   function Valid_Response_Entity_Tag (Value : String) return Boolean is
   begin
      if Value'Length < 2
        or else Value (Value'First) /= '"'
        or else Value (Value'Last) /= '"'
      then
         return False;
      end if;
      for Index in Value'First + 1 .. Value'Last - 1 loop
         if Character'Pos (Value (Index)) < 16#21#
           or else Value (Index) = '"'
           or else Character'Pos (Value (Index)) = 16#7F#
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Response_Entity_Tag;

   procedure Validate_Head_Object_Headers
     (Value : Head_Object_Result; Status : Flyology.HTTP.Status_Code)
   is
      Length : constant Optional_Byte_Count :=
        (Is_Set => True, Value => Value.Content_Length);
   begin
      if (Status = 206
          and then not Valid_Content_Range
            (US.To_String (Value.Content_Range), Length))
        or else (Status = 200 and then US.Length (Value.Content_Range) > 0)
        or else US.To_String (Value.Accept_Ranges) not in "" | "bytes"
        or else not Valid_Response_Entity_Tag
          (US.To_String (Value.Entity_Tag))
        or else not Object_Reads.Parse_Conditional_Date
          (US.To_String (Value.Last_Modified)).Valid
        or else not Valid_Read_Checksum_Headers
          (Value.Checksum_CRC32, Value.Checksum_CRC32C,
           Value.Checksum_CRC64NVME, Value.Checksum_SHA1,
           Value.Checksum_SHA256, Value.Checksum_SHA512,
           Value.Checksum_MD5, Value.Checksum_XXHASH64,
           Value.Checksum_XXHASH3, Value.Checksum_XXHASH128,
           US.To_String (Value.Checksum_Type))
        or else not Valid_Head_Object_Enum (Value.Archive_Status, 5)
        or else not Valid_Head_Object_Enum (Value.Checksum_Type, 18)
        or else (US.Length (Value.SSE_Customer_Key_MD5) > 0
                 and then not Wire_Core.Valid_Base64
                   (US.To_String (Value.SSE_Customer_Key_MD5), 16))
        or else not Valid_Head_Object_Enum
          (Value.Server_Side_Encryption, 30)
        or else (US.Length (Value.SSE_Customer_Algorithm) > 0
                 and then US.To_String (Value.SSE_Customer_Algorithm) /=
                   "AES256")
        or else not Valid_Head_Object_Enum (Value.Storage_Class, 36)
        or else not Valid_Head_Object_Enum (Value.Request_Charged, 37)
        or else not Valid_Head_Object_Enum (Value.Replication_Status, 38)
        or else not Valid_Head_Object_Enum (Value.Object_Lock_Mode, 41)
        or else not Valid_Head_Object_Enum
          (Value.Object_Lock_Legal_Hold_Status, 43)
        or else (Value.Parts_Count.Is_Set
                 and then Value.Parts_Count.Value not in 1 .. 10_000)
        or else (Value.Tag_Count.Is_Set and then Value.Tag_Count.Value > 10)
      then
         raise Invalid_Response with "invalid HeadObject response headers";
      end if;
   end Validate_Head_Object_Headers;

   function Decode_Head_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Head_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "") return Head_Object_Outcome
   is
   begin
      if Payload'Length > 0 then
         raise Invalid_Response with "HeadObject contains a response body";
      elsif Status in 200 | 206 then
         Validate_Head_Object_Headers (Headers, Status);
         return (Kind => Object_Found, Status => Status, Result => Headers);
      else
         return
           (Kind   => Head_Object_Rejected,
            Status => Status,
            Error  => Head_Error
              ("HeadObject", Status, Request_ID, Host_ID));
      end if;
   end Decode_Head_Object_Response;

   function Execute_Head_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Object_Outcome
   is
      function Is_Head_Singleton_Header (Name : String) return Boolean is
        (Name = "accept-ranges"
         or else Name = "cache-control"
         or else Name = "content-disposition"
         or else Name = "content-encoding"
         or else Name = "content-language"
         or else Name = "content-length"
         or else Name = "content-range"
         or else Name = "content-type"
         or else Name = "etag"
         or else Name = "expires"
         or else Name = "last-modified"
         or else Name = "x-amz-archive-status"
         or else Name = "x-amz-checksum-crc32"
         or else Name = "x-amz-checksum-crc32c"
         or else Name = "x-amz-checksum-crc64nvme"
         or else Name = "x-amz-checksum-md5"
         or else Name = "x-amz-checksum-sha1"
         or else Name = "x-amz-checksum-sha256"
         or else Name = "x-amz-checksum-sha512"
         or else Name = "x-amz-checksum-type"
         or else Name = "x-amz-checksum-xxhash128"
         or else Name = "x-amz-checksum-xxhash3"
         or else Name = "x-amz-checksum-xxhash64"
         or else Name = "x-amz-delete-marker"
         or else Name = "x-amz-expiration"
         or else Name = "x-amz-id-2"
         or else Name = "x-amz-missing-meta"
         or else Name = "x-amz-mp-parts-count"
         or else Name = "x-amz-object-lock-legal-hold"
         or else Name = "x-amz-object-lock-mode"
         or else Name = "x-amz-object-lock-retain-until-date"
         or else Name = "x-amz-replication-status"
         or else Name = "x-amz-request-charged"
         or else Name = "x-amz-request-id"
         or else Name = "x-amz-restore"
         or else Name = "x-amz-server-side-encryption"
         or else Name =
           "x-amz-server-side-encryption-aws-kms-key-id"
         or else Name =
           "x-amz-server-side-encryption-bucket-key-enabled"
         or else Name =
           "x-amz-server-side-encryption-customer-algorithm"
         or else Name =
           "x-amz-server-side-encryption-customer-key-md5"
         or else Name = "x-amz-storage-class"
         or else Name = "x-amz-tagging-count"
         or else Name = "x-amz-version-id"
         or else Name = "x-amz-website-redirect-location");
   begin
      if Prepared.Operation /= Head_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");

         function H (Name : String) return US.Unbounded_String is
           (US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, Name)));

         Metadata : Metadata_Entry_Vectors.Vector;
      begin
         for Index in 1 .. Flyology.HTTP.Client.Header_Count (Response) loop
            declare
               Name : constant String := Ada.Characters.Handling.To_Lower
                 (Flyology.HTTP.Client.Header_Name (Response, Index));
               Prefix : constant String := "x-amz-meta-";
            begin
               if Name = "transfer-encoding" then
                  raise Invalid_Response with
                    "HeadObject response uses transfer coding";
               elsif Is_Head_Singleton_Header (Name) then
                  for Previous in 1 .. Index - 1 loop
                     if Ada.Characters.Handling.To_Lower
                       (Flyology.HTTP.Client.Header_Name
                          (Response, Previous)) = Name
                     then
                        raise Invalid_Response with
                          "HeadObject response duplicates a singleton header";
                     end if;
                  end loop;
               end if;
               if Name'Length > Prefix'Length
                 and then Name (Name'First .. Name'First + Prefix'Length - 1)
                   = Prefix
               then
                  Metadata.Append
                    (Metadata_Entry'
                       (Name => US.To_Unbounded_String
                        (Name (Name'First + Prefix'Length .. Name'Last)),
                      Value => US.To_Unbounded_String
                        (Flyology.HTTP.Client.Header_Value
                           (Response, Index))));
               end if;
            end;
         end loop;
         declare
            Headers : constant Head_Object_Result :=
              (Delete_Marker => Optional_Boolean_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-delete-marker")),
               Accept_Ranges => H ("accept-ranges"),
               Expiration => H ("x-amz-expiration"),
               Restore => H ("x-amz-restore"),
               Archive_Status => H ("x-amz-archive-status"),
               Last_Modified => H ("last-modified"),
               Content_Length => Head_Content_Length
                 (Flyology.HTTP.Client.Header (Response, "content-length"),
                  Status in 200 | 206),
               Checksum_CRC32 => H ("x-amz-checksum-crc32"),
               Checksum_CRC32C => H ("x-amz-checksum-crc32c"),
               Checksum_CRC64NVME => H ("x-amz-checksum-crc64nvme"),
               Checksum_SHA1 => H ("x-amz-checksum-sha1"),
               Checksum_SHA256 => H ("x-amz-checksum-sha256"),
               Checksum_SHA512 => H ("x-amz-checksum-sha512"),
               Checksum_MD5 => H ("x-amz-checksum-md5"),
               Checksum_XXHASH64 => H ("x-amz-checksum-xxhash64"),
               Checksum_XXHASH3 => H ("x-amz-checksum-xxhash3"),
               Checksum_XXHASH128 => H ("x-amz-checksum-xxhash128"),
               Checksum_Type => H ("x-amz-checksum-type"),
               Entity_Tag => H ("etag"),
               Missing_Meta => Optional_Natural_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-missing-meta")),
               Version_ID => H ("x-amz-version-id"),
               Cache_Control => H ("cache-control"),
               Content_Disposition => H ("content-disposition"),
               Content_Encoding => H ("content-encoding"),
               Content_Language => H ("content-language"),
               Content_Type => H ("content-type"),
               Content_Range => H ("content-range"),
               Expires => H ("expires"),
               Website_Redirect_Location =>
                 H ("x-amz-website-redirect-location"),
               Server_Side_Encryption =>
                 H ("x-amz-server-side-encryption"),
               Metadata => Metadata,
               SSE_Customer_Algorithm => H
                 ("x-amz-server-side-encryption-customer-algorithm"),
               SSE_Customer_Key_MD5 => H
                 ("x-amz-server-side-encryption-customer-key-md5"),
               SSE_KMS_Key_ID => H
                 ("x-amz-server-side-encryption-aws-kms-key-id"),
               Bucket_Key_Enabled => Optional_Boolean_Header
                 (Flyology.HTTP.Client.Header
                    (Response,
                     "x-amz-server-side-encryption-bucket-key-enabled")),
               Storage_Class => H ("x-amz-storage-class"),
               Request_Charged => H ("x-amz-request-charged"),
               Replication_Status => H ("x-amz-replication-status"),
               Parts_Count => Optional_Natural_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-mp-parts-count")),
               Tag_Count => Optional_Natural_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-tagging-count")),
               Object_Lock_Mode => H ("x-amz-object-lock-mode"),
               Object_Lock_Retain_Until_Date =>
                 H ("x-amz-object-lock-retain-until-date"),
               Object_Lock_Legal_Hold_Status =>
                 H ("x-amz-object-lock-legal-hold"));
            Payload : constant Flyology.Bytes.Unbounded_Bytes :=
              Flyology.HTTP.Client.Read_All (Response, 1, Token);
         begin
            return Decode_Head_Object_Response
              (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
               Request_ID, Host_ID);
         end;
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "HeadObject response contains a body";
   end Execute_Head_Object;

   function Optional_Byte_Count_Header
     (Value : String) return Optional_Byte_Count is
   begin
      if Value'Length = 0 then
         return (Is_Set => False, Value => 0);
      end if;
      declare
         Parsed : constant Wire_Core.Byte_Count_Result :=
           Wire_Core.Parse_Byte_Count (Value);
      begin
         if not Parsed.Valid then
            raise Invalid_Response with
              "invalid S3 byte-count response header";
         end if;
         return (Is_Set => True, Value => Parsed.Value);
      end;
   end Optional_Byte_Count_Header;

   function Valid_Get_Object_Enum
     (Value : US.Unbounded_String; Member : Positive) return Boolean
   is
      Text : constant String := US.To_String (Value);
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.Get_Object_Operation));
      Shape : constant Model.Shape_Index :=
        Model.Member_Shape (Output, Member);
   begin
      if Text'Length = 0 then
         return True;
      end if;
      for Index in 1 .. Model.Enumeration_Count (Shape) loop
         if Text = Model.Enumeration_Value (Shape, Index) then
            return True;
         end if;
      end loop;
      return False;
   end Valid_Get_Object_Enum;

   function Valid_Content_Range
     (Value : String; Length : Optional_Byte_Count) return Boolean
   is
      Prefix : constant String := "bytes ";
   begin
      if Value'Length <= Prefix'Length
        or else Value (Value'First .. Value'First + Prefix'Length - 1) /=
          Prefix
      then
         return False;
      end if;
      declare
         Interval_First : constant Positive :=
           Value'First + Prefix'Length;
         Hyphen : constant Natural := Ada.Strings.Fixed.Index
           (Value, "-", From => Interval_First);
         Slash : constant Natural := Ada.Strings.Fixed.Index
           (Value, "/", From => Interval_First);
      begin
         if Hyphen <= Interval_First
           or else Slash <= Hyphen + 1
           or else Slash = Value'Last
           or else Ada.Strings.Fixed.Index
             (Value, "-", From => Hyphen + 1) /= 0
           or else Ada.Strings.Fixed.Index
             (Value, "/", From => Slash + 1) /= 0
         then
            return False;
         end if;
         declare
            First_Value : constant Wire_Core.Byte_Count_Result :=
              Wire_Core.Parse_Byte_Count
                (Value (Interval_First .. Hyphen - 1));
            Last_Value : constant Wire_Core.Byte_Count_Result :=
              Wire_Core.Parse_Byte_Count (Value (Hyphen + 1 .. Slash - 1));
            Total_Value : constant Wire_Core.Byte_Count_Result :=
              Wire_Core.Parse_Byte_Count (Value (Slash + 1 .. Value'Last));
         begin
            return First_Value.Valid and then Last_Value.Valid
              and then Total_Value.Valid and then Length.Is_Set
              and then First_Value.Value <= Last_Value.Value
              and then Last_Value.Value < Total_Value.Value
              and then Last_Value.Value - First_Value.Value + 1 =
                Length.Value;
         end;
      end;
   end Valid_Content_Range;

   procedure Validate_Get_Object_Headers
     (Value : Get_Object_Result; Status : Flyology.HTTP.Status_Code) is
   begin
      if (Status = 206
          and then not Valid_Content_Range
            (US.To_String (Value.Content_Range), Value.Content_Length))
        or else (Status = 200 and then US.Length (Value.Content_Range) > 0)
        or else not Valid_Read_Checksum_Headers
          (Value.Checksum_CRC32, Value.Checksum_CRC32C,
           Value.Checksum_CRC64NVME, Value.Checksum_SHA1,
           Value.Checksum_SHA256, Value.Checksum_SHA512,
           Value.Checksum_MD5, Value.Checksum_XXHASH64,
           Value.Checksum_XXHASH3, Value.Checksum_XXHASH128,
           US.To_String (Value.Checksum_Type))
        or else not Valid_Get_Object_Enum (Value.Checksum_Type, 19)
        or else (US.Length (Value.SSE_Customer_Key_MD5) > 0
                 and then not Wire_Core.Valid_Base64
                   (US.To_String (Value.SSE_Customer_Key_MD5), 16))
        or else not Valid_Get_Object_Enum
          (Value.Server_Side_Encryption, 30)
        or else (US.Length (Value.SSE_Customer_Algorithm) > 0
                 and then US.To_String (Value.SSE_Customer_Algorithm) /=
                   "AES256")
        or else not Valid_Get_Object_Enum (Value.Storage_Class, 36)
        or else not Valid_Get_Object_Enum (Value.Request_Charged, 37)
        or else not Valid_Get_Object_Enum (Value.Replication_Status, 38)
        or else not Valid_Get_Object_Enum (Value.Object_Lock_Mode, 41)
        or else not Valid_Get_Object_Enum
          (Value.Object_Lock_Legal_Hold_Status, 43)
        or else (Value.Parts_Count.Is_Set
                 and then Value.Parts_Count.Value not in 1 .. 10_000)
        or else (Value.Tag_Count.Is_Set and then Value.Tag_Count.Value > 10)
      then
         raise Invalid_Response with "invalid GetObject response headers";
      end if;
   end Validate_Get_Object_Headers;

   function Execute_Get_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response
   is
   begin
      if Prepared.Operation /= Get_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      return Flyology.HTTP.Client.Execute
        (Client, Prepared.Message, Timeout, Token);
   end Execute_Get_Object;

   function Decode_Get_Object_Response_Head
     (Response : in out Flyology.HTTP.Client.Response;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Head_Outcome
   is
      Status : constant Flyology.HTTP.Status_Code :=
        Flyology.HTTP.Client.Status (Response);
      Request_ID : constant String :=
        Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
      Host_ID : constant String :=
        Flyology.HTTP.Client.Header (Response, "x-amz-id-2");

      function H (Name : String) return US.Unbounded_String is
        (US.To_Unbounded_String
           (Flyology.HTTP.Client.Header (Response, Name)));
   begin
      if Status not in 200 | 206 then
         declare
            Payload : constant Flyology.Bytes.Unbounded_Bytes :=
              Flyology.HTTP.Client.Read_All
                (Response, Limits.Maximum_Document_Bytes, Token);
            Text : constant String :=
              Flyology.Bytes.To_Byte_String (Payload);
         begin
            if Whitespace_Only (Text) then
               return
                 (Kind   => Get_Object_Rejected,
                  Status => Status,
                  Error  => Head_Error
                    ("GetObject", Status, Request_ID, Host_ID));
            end if;
            begin
               return
                 (Kind   => Get_Object_Rejected,
                  Status => Status,
                  Error  => Error_Response
                    (Text, Request_ID, Host_ID, Limits));
            exception
               when S3.Errors.Malformed_Error =>
                  --  S3 peers and intermediaries may return bodyless or
                  --  non-XML HTTP errors.  Preserve the typed rejection and
                  --  wire status instead of turning a valid rejection into
                  --  a client protocol failure.
                  return
                    (Kind   => Get_Object_Rejected,
                     Status => Status,
                     Error  => Head_Error
                       ("GetObject", Status, Request_ID, Host_ID));
            end;
         end;
      end if;

      declare
         Metadata : Metadata_Entry_Vectors.Vector;
      begin
         for Index in 1 .. Flyology.HTTP.Client.Header_Count (Response) loop
            declare
               Name : constant String := Ada.Characters.Handling.To_Lower
                 (Flyology.HTTP.Client.Header_Name (Response, Index));
               Prefix : constant String := "x-amz-meta-";
            begin
               if Name'Length > Prefix'Length
                 and then Name (Name'First .. Name'First + Prefix'Length - 1)
                   = Prefix
               then
                  Metadata.Append
                    (Metadata_Entry'
                       (Name => US.To_Unbounded_String
                          (Name
                             (Name'First + Prefix'Length .. Name'Last)),
                        Value => US.To_Unbounded_String
                          (Flyology.HTTP.Client.Header_Value
                             (Response, Index))));
               end if;
            end;
         end loop;

         declare
            Result : constant Get_Object_Result :=
              (Delete_Marker => Optional_Boolean_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-delete-marker")),
               Accept_Ranges => H ("accept-ranges"),
               Expiration => H ("x-amz-expiration"),
               Restore => H ("x-amz-restore"),
               Last_Modified => H ("last-modified"),
               Content_Length => Optional_Byte_Count_Header
                 (Flyology.HTTP.Client.Header (Response, "content-length")),
               Entity_Tag => H ("etag"),
               Checksum_CRC32 => H ("x-amz-checksum-crc32"),
               Checksum_CRC32C => H ("x-amz-checksum-crc32c"),
               Checksum_CRC64NVME => H ("x-amz-checksum-crc64nvme"),
               Checksum_SHA1 => H ("x-amz-checksum-sha1"),
               Checksum_SHA256 => H ("x-amz-checksum-sha256"),
               Checksum_SHA512 => H ("x-amz-checksum-sha512"),
               Checksum_MD5 => H ("x-amz-checksum-md5"),
               Checksum_XXHASH64 => H ("x-amz-checksum-xxhash64"),
               Checksum_XXHASH3 => H ("x-amz-checksum-xxhash3"),
               Checksum_XXHASH128 => H ("x-amz-checksum-xxhash128"),
               Checksum_Type => H ("x-amz-checksum-type"),
               Missing_Meta => Optional_Natural_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-missing-meta")),
               Version_ID => H ("x-amz-version-id"),
               Cache_Control => H ("cache-control"),
               Content_Disposition => H ("content-disposition"),
               Content_Encoding => H ("content-encoding"),
               Content_Language => H ("content-language"),
               Content_Range => H ("content-range"),
               Content_Type => H ("content-type"),
               Expires => H ("expires"),
               Website_Redirect_Location =>
                 H ("x-amz-website-redirect-location"),
               Server_Side_Encryption =>
                 H ("x-amz-server-side-encryption"),
               Metadata => Metadata,
               SSE_Customer_Algorithm => H
                 ("x-amz-server-side-encryption-customer-algorithm"),
               SSE_Customer_Key_MD5 => H
                 ("x-amz-server-side-encryption-customer-key-md5"),
               SSE_KMS_Key_ID => H
                 ("x-amz-server-side-encryption-aws-kms-key-id"),
               Bucket_Key_Enabled => Optional_Boolean_Header
                 (Flyology.HTTP.Client.Header
                    (Response,
                     "x-amz-server-side-encryption-bucket-key-enabled")),
               Storage_Class => H ("x-amz-storage-class"),
               Request_Charged => H ("x-amz-request-charged"),
               Replication_Status => H ("x-amz-replication-status"),
               Parts_Count => Optional_Natural_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-mp-parts-count")),
               Tag_Count => Optional_Natural_Header
                 (Flyology.HTTP.Client.Header
                    (Response, "x-amz-tagging-count")),
               Object_Lock_Mode => H ("x-amz-object-lock-mode"),
               Object_Lock_Retain_Until_Date =>
                 H ("x-amz-object-lock-retain-until-date"),
               Object_Lock_Legal_Hold_Status =>
                 H ("x-amz-object-lock-legal-hold"));
         begin
            Validate_Get_Object_Headers (Result, Status);
            return (Kind => Object_Opened, Status => Status, Result => Result);
         end;
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "GetObject error exceeds XML limit";
   end Decode_Get_Object_Response_Head;

   function Prepare_Put_Object
     (Origin         : Flyology.HTTP.Origin;
      Style          : Addressing_Style;
      Bucket         : String;
      Key            : String;
      Parameters     : Put_Object_Parameters;
      Payload_SHA256 : String;
      Identity       : Credentials;
      Region         : String;
      Timestamp      : String) return Prepared_Request
   is
      Algorithm : constant String :=
        US.To_String (Parameters.Checksum_Algorithm);
      SSE_Algorithm : constant String :=
        US.To_String (Parameters.SSE_Customer_Algorithm);
      SSE_Key : constant String := US.To_String (Parameters.SSE_Customer_Key);
      SSE_Key_MD5 : constant String :=
        US.To_String (Parameters.SSE_Customer_Key_MD5);
      Server_Encryption : constant String :=
        US.To_String (Parameters.Server_Side_Encryption);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Grant_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Grant_Full_Control) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Read) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Read_ACP) > 0) +
        Boolean'Pos (US.Length (Parameters.Grant_Write_ACP) > 0);
      Has_KMS_Configuration : constant Boolean :=
        US.Length (Parameters.SSE_KMS_Key_ID) > 0
        or else US.Length (Parameters.SSE_KMS_Encryption_Context) > 0;
      Has_Object_Lock : constant Boolean :=
        US.Length (Parameters.Object_Lock_Mode) > 0
        or else US.Length (Parameters.Object_Lock_Retain_Until_Date) > 0
        or else US.Length (Parameters.Object_Lock_Legal_Hold_Status) > 0;

      function Present (Value : US.Unbounded_String) return Natural is
        (Boolean'Pos (US.Length (Value) > 0));

      function Matching_Checksum_Present return Boolean is
      begin
         if Algorithm'Length = 0 then
            return True;
         elsif Algorithm = "CRC32" then
            return US.Length (Parameters.Checksum_CRC32) > 0;
         elsif Algorithm = "CRC32C" then
            return US.Length (Parameters.Checksum_CRC32C) > 0;
         elsif Algorithm = "CRC64NVME" then
            return US.Length (Parameters.Checksum_CRC64NVME) > 0;
         elsif Algorithm = "SHA1" then
            return US.Length (Parameters.Checksum_SHA1) > 0;
         elsif Algorithm = "SHA256" then
            return US.Length (Parameters.Checksum_SHA256) > 0;
         elsif Algorithm = "SHA512" then
            return US.Length (Parameters.Checksum_SHA512) > 0;
         elsif Algorithm = "MD5" then
            return US.Length (Parameters.Checksum_MD5) > 0;
         elsif Algorithm = "XXHASH64" then
            return US.Length (Parameters.Checksum_XXHASH64) > 0;
         elsif Algorithm = "XXHASH3" then
            return US.Length (Parameters.Checksum_XXHASH3) > 0;
         elsif Algorithm = "XXHASH128" then
            return US.Length (Parameters.Checksum_XXHASH128) > 0;
         else
            return False;
         end if;
      end Matching_Checksum_Present;

      Optional_Count : constant Natural :=
        Present (Parameters.ACL) + Present (Parameters.Cache_Control) +
        Present (Parameters.Content_Disposition) +
        Present (Parameters.Content_Encoding) +
        Present (Parameters.Content_Language) +
        Present (Parameters.Content_MD5) + Present (Parameters.Content_Type) +
        Present (Parameters.Checksum_Algorithm) +
        Present (Parameters.Checksum_CRC32) +
        Present (Parameters.Checksum_CRC32C) +
        Present (Parameters.Checksum_CRC64NVME) +
        Present (Parameters.Checksum_SHA1) +
        Present (Parameters.Checksum_SHA256) +
        Present (Parameters.Checksum_SHA512) +
        Present (Parameters.Checksum_MD5) +
        Present (Parameters.Checksum_XXHASH64) +
        Present (Parameters.Checksum_XXHASH3) +
        Present (Parameters.Checksum_XXHASH128) +
        Present (Parameters.Expires) +
        Present (Parameters.If_Match) + Present (Parameters.If_None_Match) +
        Present (Parameters.Grant_Full_Control) +
        Present (Parameters.Grant_Read) + Present (Parameters.Grant_Read_ACP) +
        Present (Parameters.Grant_Write_ACP) +
        Boolean'Pos (Parameters.Write_Offset_Bytes.Is_Set) +
        Natural (Parameters.Metadata.Length) +
        Present (Parameters.Server_Side_Encryption) +
        Present (Parameters.Storage_Class) +
        Present (Parameters.Website_Redirect_Location) +
        Present (Parameters.SSE_Customer_Algorithm) +
        Present (Parameters.SSE_Customer_Key) +
        Present (Parameters.SSE_Customer_Key_MD5) +
        Present (Parameters.SSE_KMS_Key_ID) +
        Present (Parameters.SSE_KMS_Encryption_Context) +
        Boolean'Pos (Parameters.Bucket_Key_Enabled.Is_Set) +
        Present (Parameters.Request_Payer) + Present (Parameters.Tagging) +
        Present (Parameters.Object_Lock_Mode) +
        Present (Parameters.Object_Lock_Retain_Until_Date) +
        Present (Parameters.Object_Lock_Legal_Hold_Status) +
        Present (Parameters.Expected_Bucket_Owner);
      Values : Model_Value_Array (1 .. 2 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String; Map_Key : String := "") is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.To_Unbounded_String (Map_Key),
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if (Algorithm'Length > 0
          and then not Valid_Checksum_Algorithm (Algorithm))
        or else not Matching_Checksum_Present
        or else not Valid_Optional_Checksum (Parameters.Content_MD5, 16)
        or else not Valid_Optional_Checksum (Parameters.Checksum_CRC32, 4)
        or else not Valid_Optional_Checksum (Parameters.Checksum_CRC32C, 4)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_CRC64NVME, 8)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA1, 20)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA256, 32)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA512, 64)
        or else not Valid_Optional_Checksum (Parameters.Checksum_MD5, 16)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH64, 8)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH3, 8)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH128, 16)
        or else not Valid_SSE_C_Group
          (SSE_Algorithm, SSE_Key, SSE_Key_MD5)
        or else (SSE_Key'Length > 0
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
        or else (SSE_Key'Length > 0
                 and then
                   (Server_Encryption'Length > 0
                    or else US.Length (Parameters.SSE_KMS_Key_ID) > 0
                    or else
                      US.Length (Parameters.SSE_KMS_Encryption_Context) > 0
                    or else Parameters.Bucket_Key_Enabled.Is_Set))
        or else (US.Length (Parameters.ACL) > 0 and then Grant_Count > 0)
        or else (Has_KMS_Configuration
                 and then Server_Encryption not in
                   "aws:kms" | "aws:kms:dsse")
        or else (Parameters.Bucket_Key_Enabled.Is_Set
                 and then Server_Encryption /= "aws:kms")
        or else (Has_Object_Lock
                 and then US.Length (Parameters.Content_MD5) = 0
                 and then Algorithm'Length = 0)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
      then
         raise Invalid_Request with "invalid PutObject parameters";
      end if;

      Add ("Bucket", Bucket);
      Add ("Key", Key);
      Add_Optional ("ACL", Parameters.ACL);
      Add_Optional ("CacheControl", Parameters.Cache_Control);
      Add_Optional ("ContentDisposition", Parameters.Content_Disposition);
      Add_Optional ("ContentEncoding", Parameters.Content_Encoding);
      Add_Optional ("ContentLanguage", Parameters.Content_Language);
      Add_Optional ("ContentMD5", Parameters.Content_MD5);
      Add_Optional ("ContentType", Parameters.Content_Type);
      Add_Optional ("ChecksumAlgorithm", Parameters.Checksum_Algorithm);
      Add_Optional ("ChecksumCRC32", Parameters.Checksum_CRC32);
      Add_Optional ("ChecksumCRC32C", Parameters.Checksum_CRC32C);
      Add_Optional ("ChecksumCRC64NVME", Parameters.Checksum_CRC64NVME);
      Add_Optional ("ChecksumSHA1", Parameters.Checksum_SHA1);
      Add_Optional ("ChecksumSHA256", Parameters.Checksum_SHA256);
      Add_Optional ("ChecksumSHA512", Parameters.Checksum_SHA512);
      Add_Optional ("ChecksumMD5", Parameters.Checksum_MD5);
      Add_Optional ("ChecksumXXHASH64", Parameters.Checksum_XXHASH64);
      Add_Optional ("ChecksumXXHASH3", Parameters.Checksum_XXHASH3);
      Add_Optional ("ChecksumXXHASH128", Parameters.Checksum_XXHASH128);
      Add_Optional ("Expires", Parameters.Expires);
      Add_Optional ("IfMatch", Parameters.If_Match);
      Add_Optional ("IfNoneMatch", Parameters.If_None_Match);
      Add_Optional ("GrantFullControl", Parameters.Grant_Full_Control);
      Add_Optional ("GrantRead", Parameters.Grant_Read);
      Add_Optional ("GrantReadACP", Parameters.Grant_Read_ACP);
      Add_Optional ("GrantWriteACP", Parameters.Grant_Write_ACP);
      if Parameters.Write_Offset_Bytes.Is_Set then
         Add
           ("WriteOffsetBytes",
            Ada.Strings.Fixed.Trim
              (Byte_Count'Image (Parameters.Write_Offset_Bytes.Value),
               Ada.Strings.Both));
      end if;
      for Item of Parameters.Metadata loop
         Add ("Metadata", US.To_String (Item.Value), US.To_String (Item.Name));
      end loop;
      Add_Optional
        ("ServerSideEncryption", Parameters.Server_Side_Encryption);
      Add_Optional ("StorageClass", Parameters.Storage_Class);
      Add_Optional
        ("WebsiteRedirectLocation", Parameters.Website_Redirect_Location);
      Add_Optional
        ("SSECustomerAlgorithm", Parameters.SSE_Customer_Algorithm);
      Add_Optional ("SSECustomerKey", Parameters.SSE_Customer_Key);
      Add_Optional ("SSECustomerKeyMD5", Parameters.SSE_Customer_Key_MD5);
      Add_Optional ("SSEKMSKeyId", Parameters.SSE_KMS_Key_ID);
      Add_Optional
        ("SSEKMSEncryptionContext", Parameters.SSE_KMS_Encryption_Context);
      if Parameters.Bucket_Key_Enabled.Is_Set then
         Add
           ("BucketKeyEnabled",
            (if Parameters.Bucket_Key_Enabled.Value
             then "true" else "false"));
      end if;
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional ("Tagging", Parameters.Tagging);
      Add_Optional ("ObjectLockMode", Parameters.Object_Lock_Mode);
      Add_Optional
        ("ObjectLockRetainUntilDate",
         Parameters.Object_Lock_Retain_Until_Date);
      Add_Optional
        ("ObjectLockLegalHoldStatus",
         Parameters.Object_Lock_Legal_Hold_Status);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);

      return Result : Prepared_Request := Prepare_Model_Streaming_Request
        (Model.Put_Object_Operation, Origin, Style, Values, Payload_SHA256,
         Identity, Region, Timestamp)
      do
         Result.Operation := Put_Object_Operation;
      end return;
   exception
      when Constraint_Error =>
         raise Invalid_Request with "invalid PutObject parameters";
   end Prepare_Put_Object;

   function Valid_Put_Object_Enum
     (Value : US.Unbounded_String; Member : Positive) return Boolean
   is
      Text : constant String := US.To_String (Value);
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.Put_Object_Operation));
      Shape : constant Model.Shape_Index :=
        Model.Member_Shape (Output, Member);
   begin
      if Text'Length = 0 then
         return True;
      end if;
      for Index in 1 .. Model.Enumeration_Count (Shape) loop
         if Text = Model.Enumeration_Value (Shape, Index) then
            return True;
         end if;
      end loop;
      return False;
   end Valid_Put_Object_Enum;

   procedure Validate_Put_Object_Headers (Value : Put_Object_Result) is
   begin
      if US.Length (Value.Entity_Tag) = 0
        or else not Valid_Optional_Checksum (Value.Checksum_CRC32, 4)
        or else not Valid_Optional_Checksum (Value.Checksum_CRC32C, 4)
        or else not Valid_Optional_Checksum (Value.Checksum_CRC64NVME, 8)
        or else not Valid_Optional_Checksum (Value.Checksum_SHA1, 20)
        or else not Valid_Optional_Checksum (Value.Checksum_SHA256, 32)
        or else not Valid_Optional_Checksum (Value.Checksum_SHA512, 64)
        or else not Valid_Optional_Checksum (Value.Checksum_MD5, 16)
        or else not Valid_Optional_Checksum (Value.Checksum_XXHASH64, 8)
        or else not Valid_Optional_Checksum (Value.Checksum_XXHASH3, 8)
        or else not Valid_Optional_Checksum (Value.Checksum_XXHASH128, 16)
        or else not Valid_Put_Object_Enum (Value.Checksum_Type, 13)
        or else not Valid_Put_Object_Enum
          (Value.Server_Side_Encryption, 14)
        or else (US.Length (Value.SSE_Customer_Algorithm) > 0
                 and then US.To_String (Value.SSE_Customer_Algorithm) /=
                   "AES256")
        or else (US.Length (Value.SSE_Customer_Key_MD5) > 0
                 and then not Wire_Core.Valid_Base64
                   (US.To_String (Value.SSE_Customer_Key_MD5), 16))
        or else not Valid_Put_Object_Enum (Value.Request_Charged, 22)
      then
         raise Invalid_Response with "invalid PutObject response headers";
      end if;
   end Validate_Put_Object_Headers;

   function Decode_Put_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome
   is
   begin
      if Status = 200 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "PutObject success contains a response body";
         end if;
         Validate_Put_Object_Headers (Headers);
         return (Kind => Object_Put, Status => Status, Result => Headers);
      else
         return
           (Kind   => Put_Object_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed PutObject error response";
   end Decode_Put_Object_Response;

   function Execute_Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome
   is
   begin
      if Prepared.Operation /= Put_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Source, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");

         function H (Name : String) return US.Unbounded_String is
           (US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, Name)));

         Headers : constant Put_Object_Result :=
           (Expiration => H ("x-amz-expiration"),
            Entity_Tag => H ("etag"),
            Checksum_CRC32 => H ("x-amz-checksum-crc32"),
            Checksum_CRC32C => H ("x-amz-checksum-crc32c"),
            Checksum_CRC64NVME => H ("x-amz-checksum-crc64nvme"),
            Checksum_SHA1 => H ("x-amz-checksum-sha1"),
            Checksum_SHA256 => H ("x-amz-checksum-sha256"),
            Checksum_SHA512 => H ("x-amz-checksum-sha512"),
            Checksum_MD5 => H ("x-amz-checksum-md5"),
            Checksum_XXHASH64 => H ("x-amz-checksum-xxhash64"),
            Checksum_XXHASH3 => H ("x-amz-checksum-xxhash3"),
            Checksum_XXHASH128 => H ("x-amz-checksum-xxhash128"),
            Checksum_Type => H ("x-amz-checksum-type"),
            Server_Side_Encryption =>
              H ("x-amz-server-side-encryption"),
            Version_ID => H ("x-amz-version-id"),
            SSE_Customer_Algorithm =>
              H ("x-amz-server-side-encryption-customer-algorithm"),
            SSE_Customer_Key_MD5 =>
              H ("x-amz-server-side-encryption-customer-key-md5"),
            SSE_KMS_Key_ID =>
              H ("x-amz-server-side-encryption-aws-kms-key-id"),
            SSE_KMS_Encryption_Context =>
              H ("x-amz-server-side-encryption-context"),
            Bucket_Key_Enabled => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-bucket-key-enabled")),
            Size => Optional_Byte_Count_Header
              (Flyology.HTTP.Client.Header (Response, "x-amz-object-size")),
            Request_Charged => H ("x-amz-request-charged"));
         Maximum : constant Natural :=
           (if Status = 200 then 1 else Limits.Maximum_Document_Bytes);
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All (Response, Maximum, Token);
      begin
         return Decode_Put_Object_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "PutObject response body exceeds limit";
   end Execute_Put_Object;

   function Prepare_Delete_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Owner : constant String :=
        US.To_String (Parameters.Expected_Bucket_Owner);
      Headers : SigV4.Name_Value_Array
        (1 .. Boolean'Pos (Owner'Length > 0));
   begin
      if Owner'Length > 0 then
         Headers (1) := SigV4.Pair ("x-amz-expected-bucket-owner", Owner);
      end if;
      return Prepare_Object_Request
        (Delete_Bucket_Operation, "DELETE", Origin, Style, Bucket, "",
         No_Query, Headers, "", "", Identity, Region, Timestamp,
         Object_Resource => False);
   end Prepare_Delete_Bucket;

   function Decode_Delete_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Outcome
   is
   begin
      if Status = 204 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "DeleteBucket success contains a response body";
         end if;
         return (Kind => Bucket_Deleted, Status => Status);
      else
         return
           (Kind   => Delete_Bucket_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed DeleteBucket response";
   end Decode_Delete_Bucket_Response;

   function Execute_Delete_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Outcome
   is
   begin
      if Prepared.Operation /= Delete_Bucket_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Delete_Bucket_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Request_ID,
            Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "DeleteBucket response exceeds XML limit";
   end Execute_Delete_Bucket;

   function Prepare_Delete_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Delete_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Version_ID : constant String := US.To_String (Parameters.Version_ID);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Optional_Header_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.MFA) > 0) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (Parameters.Bypass_Governance_Retention.Is_Set) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (US.Length (Parameters.If_Match) > 0) +
        Boolean'Pos
          (US.Length (Parameters.If_Match_Last_Modified_Time) > 0) +
        Boolean'Pos (Parameters.If_Match_Size.Is_Set);
      Query : SigV4.Name_Value_Array
        (1 .. Boolean'Pos (Version_ID'Length > 0));
      Headers : SigV4.Name_Value_Array (1 .. Optional_Header_Count);
      Last : Natural := 0;

      procedure Add_Header (Name, Value : String) is
      begin
         if Value'Length > 0 then
            Last := Last + 1;
            Headers (Last) := SigV4.Pair (Name, Value);
         end if;
      end Add_Header;
   begin
      if not S3.Deletions.Valid_Version_ID (Version_ID)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
      then
         raise Invalid_Request with "invalid DeleteObject parameters";
      end if;
      if Version_ID'Length > 0 then
         Query (1) := SigV4.Pair ("versionId", Version_ID);
      end if;
      Add_Header ("x-amz-mfa", US.To_String (Parameters.MFA));
      Add_Header ("x-amz-request-payer", Request_Payer);
      if Parameters.Bypass_Governance_Retention.Is_Set then
         Add_Header
           ("x-amz-bypass-governance-retention",
            (if Parameters.Bypass_Governance_Retention.Value
             then "true" else "false"));
      end if;
      Add_Header
        ("x-amz-expected-bucket-owner",
         US.To_String (Parameters.Expected_Bucket_Owner));
      Add_Header ("if-match", US.To_String (Parameters.If_Match));
      Add_Header
        ("x-amz-if-match-last-modified-time",
         US.To_String (Parameters.If_Match_Last_Modified_Time));
      if Parameters.If_Match_Size.Is_Set then
         Add_Header
           ("x-amz-if-match-size",
            Ada.Strings.Fixed.Trim
              (Byte_Count'Image (Parameters.If_Match_Size.Value),
               Ada.Strings.Both));
      end if;
      return Prepare_Object_Request
        (Delete_Object_Operation, "DELETE", Origin, Style, Bucket, Key,
         Query, Headers, "", "", Identity, Region, Timestamp);
   end Prepare_Delete_Object;

   function Decode_Delete_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Delete_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Outcome
   is
      Charged : constant String := US.To_String (Headers.Request_Charged);
   begin
      if Status = 204 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "DeleteObject success contains a response body";
         elsif Charged'Length > 0 and then Charged /= "requester" then
            raise Invalid_Response with
              "invalid DeleteObject request-charged header";
         elsif not S3.Deletions.Valid_Version_ID
           (US.To_String (Headers.Version_ID))
         then
            raise Invalid_Response with
              "invalid DeleteObject version header";
         end if;
         return
           (Kind => Object_Deleted, Status => Status, Result => Headers);
      else
         return
           (Kind   => Delete_Object_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed DeleteObject response";
   end Decode_Delete_Object_Response;

   function Optional_Boolean_Header (Value : String) return Optional_Boolean is
   begin
      if Value'Length = 0 then
         return (Is_Set => False, Value => False);
      end if;
      declare
         Parsed : constant Wire_Core.Boolean_Result :=
           Wire_Core.Parse_Boolean (Value);
      begin
         if not Parsed.Valid then
            raise Invalid_Response with "invalid S3 boolean response header";
         end if;
         return (Is_Set => True, Value => Parsed.Value);
      end;
   end Optional_Boolean_Header;

   function Execute_Delete_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Outcome
   is
   begin
      if Prepared.Operation /= Delete_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Delete_Object_Result :=
           (Delete_Marker => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-delete-marker")),
            Version_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-version-id")),
            Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Delete_Object_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "DeleteObject response exceeds XML limit";
   end Execute_Delete_Object;

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

   function Model_Value_Of (Name, Value : String) return Model_Value is
     (Member_Name => US.To_Unbounded_String (Name),
      Map_Key     => US.Null_Unbounded_String,
      Value       => US.To_Unbounded_String (Value));

   function Prepare_Put_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Tags : Object_Tag_Set;
      Parameters : Put_Object_Tagging_Parameters; Identity : Credentials;
      Region, Timestamp : String) return Prepared_Request
   is
      Payload : constant String := S3.Tagging.Serialize (Tags);
      Count : constant Positive :=
        3 + Boolean'Pos (US.Length (Parameters.Version_ID) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_Algorithm) > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (US.Length (Parameters.Request_Payer) > 0);
      Values : Model_Value_Array (1 .. Count);
      Last : Natural := 3;

      procedure Add (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Last := Last + 1;
            Values (Last) := Model_Value_Of (Name, US.To_String (Value));
         end if;
      end Add;
   begin
      Values (1) := Model_Value_Of ("Bucket", Bucket);
      Values (2) := Model_Value_Of ("Key", Key);
      Values (3) := Model_Value_Of ("ContentMD5", Content_MD5 (Payload));
      Add ("VersionId", Parameters.Version_ID);
      Add ("ChecksumAlgorithm", Parameters.Checksum_Algorithm);
      Add ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add ("RequestPayer", Parameters.Request_Payer);
      return Prepare_Model_Request
        (Model.Put_Object_Tagging_Operation, Origin, Style, Values, Payload,
         True, "", Identity, Region, Timestamp);
   end Prepare_Put_Object_Tagging;

   function Prepare_Get_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : Get_Object_Tagging_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request
   is
      Count : constant Positive :=
        2 + Boolean'Pos (US.Length (Parameters.Version_ID) > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (US.Length (Parameters.Request_Payer) > 0);
      Values : Model_Value_Array (1 .. Count);
      Last : Natural := 2;

      procedure Add (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Last := Last + 1;
            Values (Last) := Model_Value_Of (Name, US.To_String (Value));
         end if;
      end Add;
   begin
      Values (1) := Model_Value_Of ("Bucket", Bucket);
      Values (2) := Model_Value_Of ("Key", Key);
      Add ("VersionId", Parameters.Version_ID);
      Add ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add ("RequestPayer", Parameters.Request_Payer);
      return Prepare_Model_Request
        (Model.Get_Object_Tagging_Operation, Origin, Style, Values, "", False,
         "", Identity, Region, Timestamp);
   end Prepare_Get_Object_Tagging;

   function Prepare_Delete_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : Delete_Object_Tagging_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request
   is
      Count : constant Positive :=
        2 + Boolean'Pos (US.Length (Parameters.Version_ID) > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0);
      Values : Model_Value_Array (1 .. Count);
      Last : Natural := 2;

      procedure Add (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Last := Last + 1;
            Values (Last) := Model_Value_Of (Name, US.To_String (Value));
         end if;
      end Add;
   begin
      Values (1) := Model_Value_Of ("Bucket", Bucket);
      Values (2) := Model_Value_Of ("Key", Key);
      Add ("VersionId", Parameters.Version_ID);
      Add ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      return Prepare_Model_Request
        (Model.Delete_Object_Tagging_Operation, Origin, Style, Values, "",
         False, "", Identity, Region, Timestamp);
   end Prepare_Delete_Object_Tagging;

   function Execute_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Expected : Model.Operation_Id;
      Timeout : Duration; Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits) return Object_Tagging_Outcome
   is
   begin
      if Prepared.Operation /= Model_Driven_Operation
        or else Prepared.Modeled_Operation /= Expected
      then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Execute_Model_Request (Client, Prepared, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Version_ID : constant US.Unbounded_String := US.To_Unbounded_String
           (Flyology.HTTP.Client.Header (Response, "x-amz-version-id"));
         Maximum : constant Positive :=
           (if Status = Model.Response_Code (Expected)
            then Positive'Min
              (Positive (S3.Tagging.Maximum_Document_Bytes),
               Limits.Maximum_Document_Bytes)
            else Limits.Maximum_Document_Bytes);
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Maximum, Token);
         Document : constant String := Flyology.Bytes.To_Byte_String (Payload);
      begin
         if US.Length (Version_ID) > 0
           and then not S3.Deletions.Valid_Version_ID
             (US.To_String (Version_ID))
         then
            raise Invalid_Response with
              "object tagging response contains an invalid version id";
         elsif Status /= Model.Response_Code (Expected) then
            return
              (Kind   => Object_Tagging_Rejected,
               Status => Status,
               Error  => Error_Response
                 (Document, Request_ID, Host_ID, Limits));
         elsif Expected = Model.Get_Object_Tagging_Operation then
            return
              (Kind   => Tags_Gotten,
               Status => Status,
               Result =>
                 (Tags       => S3.Tagging.Parse (Document, Limits),
                  Version_ID => Version_ID));
         elsif not Whitespace_Only (Document) then
            raise Invalid_Response with
              "object tagging mutation response contains a body";
         elsif Expected = Model.Put_Object_Tagging_Operation then
            return
              (Kind   => Tags_Put,
               Status => Status,
               Result =>
                 (Tags => Empty_Object_Tags, Version_ID => Version_ID));
         else
            return
              (Kind   => Tags_Deleted,
               Status => Status,
               Result =>
                 (Tags => Empty_Object_Tags, Version_ID => Version_ID));
         end if;
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "object tagging response exceeds limit";
      when S3.Tagging.Malformed_Tagging | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed object tagging response";
   end Execute_Object_Tagging;

   function Execute_Put_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome is
     (Execute_Object_Tagging
        (Client, Prepared, Model.Put_Object_Tagging_Operation, Timeout, Token,
         Limits));

   function Execute_Get_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome is
     (Execute_Object_Tagging
        (Client, Prepared, Model.Get_Object_Tagging_Operation, Timeout, Token,
         Limits));

   function Execute_Delete_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome is
     (Execute_Object_Tagging
        (Client, Prepared, Model.Delete_Object_Tagging_Operation, Timeout,
         Token, Limits));

   function Prepare_Delete_Objects
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Request    : S3.Deletions.Delete_Objects_Request;
      Parameters : Delete_Objects_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Algorithm_Text : constant String :=
        US.To_String (Parameters.Checksum_Algorithm);
      Algorithm : constant Checksum_Policy.Algorithm_Parse_Result :=
        Checksum_Policy.Parse_Algorithm (Algorithm_Text);
      Header_Count : constant Natural :=
        1 + Boolean'Pos (US.Length (Parameters.MFA) > 0) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (Parameters.Bypass_Governance_Retention.Is_Set) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        2 * Boolean'Pos (Algorithm_Text'Length > 0);
      Headers : SigV4.Name_Value_Array (1 .. Header_Count);
      Query : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("delete", ""));
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         if Value'Length > 0 then
            Last := Last + 1;
            Headers (Last) := SigV4.Pair (Name, Value);
         end if;
      end Add;
   begin
      if Request_Payer'Length > 0 and then Request_Payer /= "requester" then
         raise Invalid_Request with "invalid DeleteObjects request payer";
      elsif Algorithm_Text'Length > 0 and then not Algorithm.Valid then
         raise Invalid_Request with "invalid DeleteObjects checksum algorithm";
      end if;
      declare
         Payload : constant String :=
           S3.Deletions.Serialize_Request (Request);
      begin
         Add ("content-md5", Content_MD5 (Payload));
         Add ("x-amz-mfa", US.To_String (Parameters.MFA));
         Add ("x-amz-request-payer", Request_Payer);
         if Parameters.Bypass_Governance_Retention.Is_Set then
            Add
              ("x-amz-bypass-governance-retention",
               (if Parameters.Bypass_Governance_Retention.Value
                then "true" else "false"));
         end if;
         Add
           ("x-amz-expected-bucket-owner",
            US.To_String (Parameters.Expected_Bucket_Owner));
         if Algorithm_Text'Length > 0 then
            declare
               Digest : constant Checksums.Digest_Value :=
                 Checksums.Compute
                   (Algorithm.Value,
                    Flyology.Bytes.To_Array
                      (Flyology.Bytes.From_Byte_String (Payload)));
               Header_Name : constant String :=
                 (case Algorithm.Value is
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
            begin
               Add ("x-amz-sdk-checksum-algorithm", Algorithm_Text);
               Add (Header_Name, Checksums.Encode_Base64 (Digest));
            end;
         end if;
         return Result : Prepared_Request := Prepare_Object_Request
           (Delete_Objects_Operation, "POST", Origin, Style, Bucket, "",
            Query, Headers, Payload, "", Identity, Region, Timestamp,
            Object_Resource => False)
         do
            Result.Operation := Delete_Objects_Operation;
         end return;
      end;
   exception
      when S3.Deletions.Malformed_Delete =>
         raise Invalid_Request with "invalid DeleteObjects request body";
   end Prepare_Delete_Objects;

   function Decode_Delete_Objects_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Objects_Outcome
   is
   begin
      if Status = 200 then
         if Request_Charged'Length > 0
           and then Request_Charged /= "requester"
         then
            raise Invalid_Response with
              "invalid DeleteObjects request-charged header";
         end if;
         return
           (Kind   => Objects_Deleted,
            Status => Status,
            Result =>
              (Result => S3.Deletions.Parse_Result (Payload, Limits),
               Request_Charged =>
                 US.To_Unbounded_String (Request_Charged)));
      end if;
      return
        (Kind   => Delete_Objects_Rejected,
         Status => Status,
         Error  => Error_Response
           (Payload, Request_ID, Host_ID, Limits));
   exception
      when S3.Deletions.Malformed_Delete | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed DeleteObjects response";
   end Decode_Delete_Objects_Response;

   function Execute_Delete_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Objects_Outcome
   is
   begin
      if Prepared.Operation /= Delete_Objects_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Request_Charged : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-charged");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Delete_Objects_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload),
            Request_Charged, Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "DeleteObjects response exceeds XML limit";
   end Execute_Delete_Objects;

   function Decode_Abort_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome
   is
      Headers : constant Abort_Multipart_Result := (others => <>);
   begin
      return Decode_Abort_Multipart_Response
        (Status, Payload, Headers, Request_ID, Host_ID, Limits);
   end Decode_Abort_Multipart_Response;

   function Decode_Abort_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Abort_Multipart_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome
   is
      Charged : constant String := US.To_String (Headers.Request_Charged);
   begin
      if Status = 204 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "AbortMultipartUpload success contains a response body";
         elsif Charged'Length > 0 and then Charged /= "requester" then
            raise Invalid_Response with
              "invalid AbortMultipartUpload request-charged header";
         end if;
         return (Kind => Aborted, Status => Status, Result => Headers);
      else
         return
           (Kind   => Abort_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed AbortMultipartUpload response";
   end Decode_Abort_Multipart_Response;

   function Execute_Abort_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome
   is
   begin
      if Prepared.Operation /= Abort_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
         Headers : constant Abort_Multipart_Result :=
           (Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
      begin
         return Decode_Abort_Multipart_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "AbortMultipartUpload response exceeds XML limit";
   end Execute_Abort_Multipart_Upload;

   function Prepare_List_Parts
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : List_Parts_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Upload_ID : constant String := US.To_String (Parameters.Upload_ID);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      SSE_Algorithm : constant String :=
        US.To_String (Parameters.SSE_Customer_Algorithm);
      SSE_Key : constant String := US.To_String (Parameters.SSE_Customer_Key);
      SSE_Key_MD5 : constant String :=
        US.To_String (Parameters.SSE_Customer_Key_MD5);
      Optional_Count : constant Natural :=
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (SSE_Algorithm'Length > 0) +
        Boolean'Pos (SSE_Key'Length > 0) +
        Boolean'Pos (SSE_Key_MD5'Length > 0);
      Values : Model_Value_Array (1 .. 5 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length = 0
        or else Upload_ID'Length > 8_192
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
        or else not Valid_SSE_C_Group
          (SSE_Algorithm, SSE_Key, SSE_Key_MD5)
        or else (SSE_Key'Length > 0
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
      then
         raise Invalid_Request with "invalid ListParts parameters";
      end if;
      Add ("Bucket", Bucket);
      Add ("Key", Key);
      Add
        ("MaxParts",
         Ada.Strings.Fixed.Trim
           (S3.Core.Page_Size'Image (Parameters.Max_Parts),
            Ada.Strings.Both));
      Add
        ("PartNumberMarker",
         Ada.Strings.Fixed.Trim
           (S3.Multipart.Part_Marker_Value'Image
              (Parameters.Part_Number_Marker),
            Ada.Strings.Both));
      Add ("UploadId", Upload_ID);
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add_Optional
        ("SSECustomerAlgorithm", Parameters.SSE_Customer_Algorithm);
      Add_Optional ("SSECustomerKey", Parameters.SSE_Customer_Key);
      Add_Optional ("SSECustomerKeyMD5", Parameters.SSE_Customer_Key_MD5);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.List_Parts_Operation, Origin, Style, Values, "", False,
         SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := List_Parts_Operation;
      end return;
   exception
      when Constraint_Error =>
         raise Invalid_Request with "invalid ListParts parameters";
   end Prepare_List_Parts;

   function Decode_List_Parts_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Abort_Date      : String := "";
      Abort_Rule_ID   : String := "";
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Parts_Outcome
   is
   begin
      if Status = 200 then
         if Request_Charged'Length > 0
           and then Request_Charged /= "requester"
         then
            raise Invalid_Response with "invalid ListParts response headers";
         end if;
         return
           (Kind   => Parts_Listed,
            Status => Status,
            Result =>
              (Listing => S3.Multipart.Parse_List_Parts_Result
                 (Payload, Limits),
               Abort_Date => US.To_Unbounded_String (Abort_Date),
               Abort_Rule_ID => US.To_Unbounded_String (Abort_Rule_ID),
               Request_Charged =>
                 US.To_Unbounded_String (Request_Charged)));
      else
         return
           (Kind   => List_Parts_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Multipart.Malformed_Multipart | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListParts response";
   end Decode_List_Parts_Response;

   function Execute_List_Parts
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Parts_Outcome
   is
   begin
      if Prepared.Operation /= List_Parts_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Abort_Date : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-abort-date");
         Abort_Rule_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-abort-rule-id");
         Request_Charged : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-charged");
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_List_Parts_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Abort_Date,
            Abort_Rule_ID, Request_Charged, Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "ListParts response exceeds XML limit";
   end Execute_List_Parts;

   function Prepare_List_Multipart_Uploads
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : List_Multipart_Uploads_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Delimiter) > 0) +
        Boolean'Pos (Parameters.URL_Encoding) +
        Boolean'Pos (US.Length (Parameters.Key_Marker) > 0) +
        Boolean'Pos (US.Length (Parameters.Prefix) > 0) +
        Boolean'Pos (US.Length (Parameters.Upload_ID_Marker) > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos (Request_Payer'Length > 0);
      Values : Model_Value_Array (1 .. 2 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if not Valid_Bucket_Name (Bucket)
        or else Parameters.Max_Uploads = 0
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
      then
         raise Invalid_Request with
           "invalid ListMultipartUploads parameters";
      end if;
      Add ("Bucket", Bucket);
      Add
        ("MaxUploads",
         Ada.Strings.Fixed.Trim
           (S3.Core.Page_Size'Image (Parameters.Max_Uploads),
            Ada.Strings.Both));
      Add_Optional ("Delimiter", Parameters.Delimiter);
      if Parameters.URL_Encoding then
         Add ("EncodingType", "url");
      end if;
      Add_Optional ("KeyMarker", Parameters.Key_Marker);
      Add_Optional ("Prefix", Parameters.Prefix);
      Add_Optional ("UploadIdMarker", Parameters.Upload_ID_Marker);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.List_Multipart_Uploads_Operation, Origin, Style, Values, "",
         False, SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := List_Multipart_Uploads_Operation;
      end return;
   exception
      when Constraint_Error =>
         raise Invalid_Request with
           "invalid ListMultipartUploads parameters";
   end Prepare_List_Multipart_Uploads;

   function Decode_List_Multipart_Uploads_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Multipart_Uploads_Outcome
   is
   begin
      if Status = 200 then
         if Request_Charged'Length > 0
           and then Request_Charged /= "requester"
         then
            raise Invalid_Response with
              "invalid ListMultipartUploads response headers";
         end if;
         return
           (Kind   => Multipart_Uploads_Listed,
            Status => Status,
            Result =>
              (Listing =>
                 S3.Multipart_Uploads.Parse_List_Multipart_Uploads
                   (Payload, Limits),
               Request_Charged =>
                 US.To_Unbounded_String (Request_Charged)));
      else
         return
           (Kind   => List_Multipart_Uploads_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when Occurrence : S3.Multipart_Uploads.Malformed_Upload_Listing =>
         raise Invalid_Response with
           "malformed ListMultipartUploads response: " &
           Ada.Exceptions.Exception_Message (Occurrence);
      when Occurrence : S3.Errors.Malformed_Error =>
         raise Invalid_Response with
           "malformed ListMultipartUploads error response: " &
           Ada.Exceptions.Exception_Message (Occurrence);
   end Decode_List_Multipart_Uploads_Response;

   function Execute_List_Multipart_Uploads
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Multipart_Uploads_Outcome
   is
   begin
      if Prepared.Operation /= List_Multipart_Uploads_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_Charged : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-charged");
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_List_Multipart_Uploads_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload),
            Request_Charged, Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "ListMultipartUploads response exceeds XML limit";
   end Execute_List_Multipart_Uploads;

   function Valid_Checksum_Algorithm (Value : String) return Boolean is
     (Value = "CRC32"
      or else Value = "CRC32C"
      or else Value = "SHA1"
      or else Value = "SHA256"
      or else Value = "CRC64NVME"
      or else Value = "SHA512"
      or else Value = "MD5"
      or else Value = "XXHASH64"
      or else Value = "XXHASH3"
      or else Value = "XXHASH128");

   function Valid_Optional_Checksum
     (Value : US.Unbounded_String; Bytes : Positive) return Boolean is
     (US.Length (Value) = 0
      or else Wire_Core.Valid_Base64 (US.To_String (Value), Bytes));

   function Valid_Optional_Object_Checksum
     (Value : US.Unbounded_String; Bytes : Positive; Kind : String)
      return Boolean
   is
      Text : constant String := US.To_String (Value);
      Dash : constant Natural :=
        (if Kind = "COMPOSITE" or else Kind'Length = 0
         then Ada.Strings.Fixed.Index
           (Text, "-", Going => Ada.Strings.Backward)
         else 0);
   begin
      if Text'Length = 0 then
         return True;
      elsif Kind /= "COMPOSITE" and then Kind'Length > 0 then
         return Wire_Core.Valid_Base64 (Text, Bytes);
      elsif Kind'Length = 0 and then Wire_Core.Valid_Base64 (Text, Bytes) then
         return True;
      elsif Dash = 0 or else Dash = Text'First or else Dash = Text'Last then
         return False;
      end if;
      declare
         Count : constant Wire_Core.Natural_Result :=
           Wire_Core.Parse_Natural (Text (Dash + 1 .. Text'Last));
      begin
         return Count.Valid
           and then Count.Value in S3.Core.Part_Number'Range
           and then Text (Dash + 1) /= '0'
           and then Wire_Core.Valid_Base64
             (Text (Text'First .. Dash - 1), Bytes);
      end;
   end Valid_Optional_Object_Checksum;

   function Valid_Read_Checksum_Headers
     (CRC32, CRC32C, CRC64NVME, SHA1, SHA256, SHA512, MD5,
      XXHASH64, XXHASH3, XXHASH128 : US.Unbounded_String;
      Kind : String) return Boolean
   is
      Count : constant Natural :=
        Boolean'Pos (US.Length (CRC32) > 0) +
        Boolean'Pos (US.Length (CRC32C) > 0) +
        Boolean'Pos (US.Length (CRC64NVME) > 0) +
        Boolean'Pos (US.Length (SHA1) > 0) +
        Boolean'Pos (US.Length (SHA256) > 0) +
        Boolean'Pos (US.Length (SHA512) > 0) +
        Boolean'Pos (US.Length (MD5) > 0) +
        Boolean'Pos (US.Length (XXHASH64) > 0) +
        Boolean'Pos (US.Length (XXHASH3) > 0) +
        Boolean'Pos (US.Length (XXHASH128) > 0);

      function Encoding_Is_Valid
        (Value : US.Unbounded_String; Bytes : Positive) return Boolean is
        (Valid_Optional_Checksum (Value, Bytes)
         or else Valid_Optional_Object_Checksum (Value, Bytes, Kind));

      function Pair_Is_Supported return Boolean is
         Algorithm : constant Checksum_Policy.Algorithm :=
           (if US.Length (CRC32) > 0 then S3.Core.CRC32
            elsif US.Length (CRC32C) > 0 then S3.Core.CRC32C
            elsif US.Length (CRC64NVME) > 0 then S3.Core.CRC64NVME
            elsif US.Length (SHA1) > 0 then S3.Core.SHA1
            elsif US.Length (SHA256) > 0 then S3.Core.SHA256
            elsif US.Length (SHA512) > 0 then S3.Core.SHA512
            elsif US.Length (MD5) > 0 then S3.Core.MD5
            elsif US.Length (XXHASH64) > 0 then S3.Core.XXHASH64
            elsif US.Length (XXHASH3) > 0 then S3.Core.XXHASH3
            else S3.Core.XXHASH128);
         Method : constant Checksum_Policy.Checksum_Type :=
           (if Kind = "COMPOSITE"
            then Checksum_Policy.Composite
            else Checksum_Policy.Full_Object);
      begin
         return Checksum_Policy.Supported (Algorithm, Method);
      end Pair_Is_Supported;
   begin
      if Count > 1
        or else Kind not in "" | "COMPOSITE" | "FULL_OBJECT"
      then
         return False;
      elsif Count = 0 then
         return Kind'Length = 0;
      elsif Kind'Length > 0 and then not Pair_Is_Supported then
         return False;
      elsif US.Length (CRC32) > 0 then
         return Encoding_Is_Valid (CRC32, 4);
      elsif US.Length (CRC32C) > 0 then
         return Encoding_Is_Valid (CRC32C, 4);
      elsif US.Length (CRC64NVME) > 0 then
         return Encoding_Is_Valid (CRC64NVME, 8);
      elsif US.Length (SHA1) > 0 then
         return Encoding_Is_Valid (SHA1, 20);
      elsif US.Length (SHA256) > 0 then
         return Encoding_Is_Valid (SHA256, 32);
      elsif US.Length (SHA512) > 0 then
         return Encoding_Is_Valid (SHA512, 64);
      elsif US.Length (MD5) > 0 then
         return Encoding_Is_Valid (MD5, 16);
      elsif US.Length (XXHASH64) > 0 then
         return Encoding_Is_Valid (XXHASH64, 8);
      elsif US.Length (XXHASH3) > 0 then
         return Encoding_Is_Valid (XXHASH3, 8);
      else
         return Encoding_Is_Valid (XXHASH128, 16);
      end if;
   end Valid_Read_Checksum_Headers;

   function Prepare_Upload_Part
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Upload_Part_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Upload_ID : constant String := US.To_String (Parameters.Upload_ID);
      Payload_Hash : constant String :=
        US.To_String (Parameters.Payload_SHA256);
      Algorithm : constant String :=
        US.To_String (Parameters.Checksum_Algorithm);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      SSE_Algorithm : constant String :=
        US.To_String (Parameters.SSE_Customer_Algorithm);
      SSE_Key : constant String := US.To_String (Parameters.SSE_Customer_Key);
      SSE_Key_MD5 : constant String :=
        US.To_String (Parameters.SSE_Customer_Key_MD5);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Content_MD5) > 0) +
        Boolean'Pos (Algorithm'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_CRC32) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_CRC32C) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_CRC64NVME) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_SHA1) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_SHA256) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_SHA512) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_MD5) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_XXHASH64) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_XXHASH3) > 0) +
        Boolean'Pos (US.Length (Parameters.Checksum_XXHASH128) > 0) +
        Boolean'Pos (SSE_Algorithm'Length > 0) +
        Boolean'Pos (SSE_Key'Length > 0) +
        Boolean'Pos (SSE_Key_MD5'Length > 0) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0);
      Query : SigV4.Name_Value_Array (1 .. 2);
      Headers : SigV4.Name_Value_Array (1 .. Optional_Count);
      Last : Natural := 0;

      procedure Add_Header (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Last := Last + 1;
            Headers (Last) := SigV4.Pair (Name, US.To_String (Value));
         end if;
      end Add_Header;
   begin
      if Upload_ID'Length = 0
        or else Upload_ID'Length > 8_192
        or else (Payload_Hash /= SigV4.Unsigned_Payload
                 and then not Encoding.Valid_SHA256_Hex (Payload_Hash))
        or else (Payload_Hash = SigV4.Unsigned_Payload
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
        or else (Algorithm'Length > 0
                 and then not Valid_Checksum_Algorithm (Algorithm))
        or else not Valid_Optional_Checksum (Parameters.Content_MD5, 16)
        or else not Valid_Optional_Checksum (Parameters.Checksum_CRC32, 4)
        or else not Valid_Optional_Checksum (Parameters.Checksum_CRC32C, 4)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_CRC64NVME, 8)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA1, 20)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA256, 32)
        or else not Valid_Optional_Checksum (Parameters.Checksum_SHA512, 64)
        or else not Valid_Optional_Checksum (Parameters.Checksum_MD5, 16)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH64, 8)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH3, 8)
        or else not Valid_Optional_Checksum
          (Parameters.Checksum_XXHASH128, 16)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
        or else not Valid_SSE_C_Group
          (SSE_Algorithm, SSE_Key, SSE_Key_MD5)
        or else (SSE_Key'Length > 0
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
      then
         raise Invalid_Request with "invalid UploadPart parameters";
      end if;
      Query (1) := SigV4.Pair
        ("partNumber",
         Ada.Strings.Fixed.Trim
           (S3.Core.Part_Number'Image (Parameters.Part_Number),
            Ada.Strings.Both));
      Query (2) := SigV4.Pair ("uploadId", Upload_ID);
      Add_Header ("content-md5", Parameters.Content_MD5);
      Add_Header ("x-amz-sdk-checksum-algorithm",
                  Parameters.Checksum_Algorithm);
      Add_Header ("x-amz-checksum-crc32", Parameters.Checksum_CRC32);
      Add_Header ("x-amz-checksum-crc32c", Parameters.Checksum_CRC32C);
      Add_Header
        ("x-amz-checksum-crc64nvme", Parameters.Checksum_CRC64NVME);
      Add_Header ("x-amz-checksum-sha1", Parameters.Checksum_SHA1);
      Add_Header ("x-amz-checksum-sha256", Parameters.Checksum_SHA256);
      Add_Header ("x-amz-checksum-sha512", Parameters.Checksum_SHA512);
      Add_Header ("x-amz-checksum-md5", Parameters.Checksum_MD5);
      Add_Header ("x-amz-checksum-xxhash64", Parameters.Checksum_XXHASH64);
      Add_Header ("x-amz-checksum-xxhash3", Parameters.Checksum_XXHASH3);
      Add_Header
        ("x-amz-checksum-xxhash128", Parameters.Checksum_XXHASH128);
      Add_Header
        ("x-amz-server-side-encryption-customer-algorithm",
         Parameters.SSE_Customer_Algorithm);
      Add_Header
        ("x-amz-server-side-encryption-customer-key",
         Parameters.SSE_Customer_Key);
      Add_Header
        ("x-amz-server-side-encryption-customer-key-md5",
         Parameters.SSE_Customer_Key_MD5);
      Add_Header ("x-amz-request-payer", Parameters.Request_Payer);
      Add_Header
        ("x-amz-expected-bucket-owner",
         Parameters.Expected_Bucket_Owner);
      return Prepare_Object_Request
        (Upload_Part_Operation, "PUT", Origin, Style, Bucket, Key, Query,
         Headers, "", Payload_Hash, Identity, Region, Timestamp);
   end Prepare_Upload_Part;

   procedure Validate_Upload_Result (Value : Upload_Part_Result) is
      Bucket_Key : constant String := US.To_String (Value.Bucket_Key_Enabled);
      Charged : constant String := US.To_String (Value.Request_Charged);
   begin
      if US.Length (Value.Entity_Tag) = 0
        or else not Valid_Optional_Checksum (Value.Checksum_CRC32, 4)
        or else not Valid_Optional_Checksum (Value.Checksum_CRC32C, 4)
        or else not Valid_Optional_Checksum (Value.Checksum_CRC64NVME, 8)
        or else not Valid_Optional_Checksum (Value.Checksum_SHA1, 20)
        or else not Valid_Optional_Checksum (Value.Checksum_SHA256, 32)
        or else not Valid_Optional_Checksum (Value.Checksum_SHA512, 64)
        or else not Valid_Optional_Checksum (Value.Checksum_MD5, 16)
        or else not Valid_Optional_Checksum (Value.Checksum_XXHASH64, 8)
        or else not Valid_Optional_Checksum (Value.Checksum_XXHASH3, 8)
        or else not Valid_Optional_Checksum (Value.Checksum_XXHASH128, 16)
        or else (Bucket_Key'Length > 0
                 and then not Wire_Core.Parse_Boolean (Bucket_Key).Valid)
        or else (Charged'Length > 0 and then Charged /= "requester")
      then
         raise Invalid_Response with "invalid UploadPart response headers";
      end if;
   end Validate_Upload_Result;

   function Decode_Upload_Part_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Upload_Part_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Outcome
   is
   begin
      if Status = 200 then
         if not Whitespace_Only (Payload) then
            raise Invalid_Response with
              "UploadPart success contains a response body";
         end if;
         Validate_Upload_Result (Headers);
         return (Kind => Part_Uploaded, Status => Status, Result => Headers);
      else
         return
           (Kind   => Upload_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed UploadPart response";
   end Decode_Upload_Part_Response;

   function Execute_Upload_Part
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Outcome
   is
   begin
      if Prepared.Operation /= Upload_Part_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Source, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Upload_Part_Result :=
           (Entity_Tag => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "etag")),
            Checksum_CRC32 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-checksum-crc32")),
            Checksum_CRC32C => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-crc32c")),
            Checksum_CRC64NVME => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-crc64nvme")),
            Checksum_SHA1 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-checksum-sha1")),
            Checksum_SHA256 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-sha256")),
            Checksum_SHA512 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-sha512")),
            Checksum_MD5 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-checksum-md5")),
            Checksum_XXHASH64 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-xxhash64")),
            Checksum_XXHASH3 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-xxhash3")),
            Checksum_XXHASH128 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-checksum-xxhash128")),
            Server_Side_Encryption => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption")),
            SSE_Customer_Algorithm => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-customer-algorithm")),
            SSE_Customer_Key_MD5 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-customer-key-md5")),
            SSE_KMS_Key_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-aws-kms-key-id")),
            Bucket_Key_Enabled => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-bucket-key-enabled")),
            Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Upload_Part_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "UploadPart response exceeds XML limit";
   end Execute_Upload_Part;

   function Prepare_Upload_Part_Copy
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Upload_Part_Copy_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Upload_ID : constant String := US.To_String (Parameters.Upload_ID);
      Copy_Source : constant String := US.To_String (Parameters.Copy_Source);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Destination_SSE_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.SSE_Customer_Algorithm) > 0) +
        Boolean'Pos (US.Length (Parameters.SSE_Customer_Key) > 0) +
        Boolean'Pos (US.Length (Parameters.SSE_Customer_Key_MD5) > 0);
      Source_SSE_Count : constant Natural :=
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_SSE_Customer_Algorithm) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_SSE_Customer_Key) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_SSE_Customer_Key_MD5) > 0);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Copy_Source_If_Match) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_If_Modified_Since) > 0) +
        Boolean'Pos (US.Length (Parameters.Copy_Source_If_None_Match) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_If_Unmodified_Since) > 0) +
        Boolean'Pos (Parameters.Source_Range.Is_Set) +
        Destination_SSE_Count + Source_SSE_Count +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Expected_Source_Bucket_Owner) > 0);
      Values : Model_Value_Array (1 .. 5 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if Upload_ID'Length not in 1 .. 8_192
        or else Copy_Source'Length not in 1 .. 8_192
        or else Destination_SSE_Count not in 0 | 3
        or else Source_SSE_Count not in 0 | 3
        or else not Valid_SSE_C_Group
          (US.To_String (Parameters.SSE_Customer_Algorithm),
           US.To_String (Parameters.SSE_Customer_Key),
           US.To_String (Parameters.SSE_Customer_Key_MD5))
        or else not Valid_SSE_C_Group
          (US.To_String
             (Parameters.Copy_Source_SSE_Customer_Algorithm),
           US.To_String (Parameters.Copy_Source_SSE_Customer_Key),
           US.To_String (Parameters.Copy_Source_SSE_Customer_Key_MD5))
        or else ((Destination_SSE_Count > 0 or else Source_SSE_Count > 0)
                 and then Flyology.HTTP.Scheme (Origin) /=
                   Flyology.HTTP.Secure_HTTPS)
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
        or else (Parameters.Source_Range.Is_Set
                 and then
                   (Parameters.Source_Range.First >
                      Parameters.Source_Range.Last
                    or else Parameters.Source_Range.Last -
                      Parameters.Source_Range.First >=
                        S3.Core.Maximum_Part_Size))
      then
         raise Invalid_Request with "invalid UploadPartCopy parameters";
      end if;

      Add ("Bucket", Bucket);
      Add ("CopySource", Copy_Source);
      Add ("Key", Key);
      Add
        ("PartNumber",
         Ada.Strings.Fixed.Trim
           (S3.Core.Part_Number'Image (Parameters.Part_Number),
            Ada.Strings.Both));
      Add ("UploadId", Upload_ID);
      Add_Optional ("CopySourceIfMatch", Parameters.Copy_Source_If_Match);
      Add_Optional
        ("CopySourceIfModifiedSince",
         Parameters.Copy_Source_If_Modified_Since);
      Add_Optional
        ("CopySourceIfNoneMatch", Parameters.Copy_Source_If_None_Match);
      Add_Optional
        ("CopySourceIfUnmodifiedSince",
         Parameters.Copy_Source_If_Unmodified_Since);
      if Parameters.Source_Range.Is_Set then
         Add
           ("CopySourceRange",
            "bytes=" &
            Ada.Strings.Fixed.Trim
              (Byte_Count'Image (Parameters.Source_Range.First),
               Ada.Strings.Both) & "-" &
            Ada.Strings.Fixed.Trim
              (Byte_Count'Image (Parameters.Source_Range.Last),
               Ada.Strings.Both));
      end if;
      Add_Optional
        ("SSECustomerAlgorithm", Parameters.SSE_Customer_Algorithm);
      Add_Optional ("SSECustomerKey", Parameters.SSE_Customer_Key);
      Add_Optional ("SSECustomerKeyMD5", Parameters.SSE_Customer_Key_MD5);
      Add_Optional
        ("CopySourceSSECustomerAlgorithm",
         Parameters.Copy_Source_SSE_Customer_Algorithm);
      Add_Optional
        ("CopySourceSSECustomerKey",
         Parameters.Copy_Source_SSE_Customer_Key);
      Add_Optional
        ("CopySourceSSECustomerKeyMD5",
         Parameters.Copy_Source_SSE_Customer_Key_MD5);
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add_Optional
        ("ExpectedSourceBucketOwner",
         Parameters.Expected_Source_Bucket_Owner);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.Upload_Part_Copy_Operation, Origin, Style, Values, "", False,
         SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := Upload_Part_Copy_Operation;
      end return;
   end Prepare_Upload_Part_Copy;

   procedure Validate_Upload_Part_Copy_Headers
     (Value : Upload_Part_Copy_Result) is
      Bucket_Key : constant String := US.To_String (Value.Bucket_Key_Enabled);
      Charged : constant String := US.To_String (Value.Request_Charged);
      Encryption : constant String :=
        US.To_String (Value.Server_Side_Encryption);
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.Upload_Part_Copy_Operation));
      Encryption_Shape : constant Model.Shape_Index :=
        Model.Member_Shape (Output, 3);

      function Valid_Encryption return Boolean is
      begin
         if Encryption'Length = 0 then
            return True;
         end if;
         for Index in 1 .. Model.Enumeration_Count (Encryption_Shape) loop
            if Encryption =
              Model.Enumeration_Value (Encryption_Shape, Index)
            then
               return True;
            end if;
         end loop;
         return False;
      end Valid_Encryption;
   begin
      if not Valid_Encryption
        or else (US.Length (Value.SSE_Customer_Algorithm) > 0
                 and then US.To_String (Value.SSE_Customer_Algorithm) /=
                   "AES256")
        or else (US.Length (Value.SSE_Customer_Key_MD5) > 0
                 and then not Wire_Core.Valid_Base64
                   (US.To_String (Value.SSE_Customer_Key_MD5), 16))
        or else (Bucket_Key'Length > 0
          and then not Wire_Core.Parse_Boolean (Bucket_Key).Valid)
        or else (Charged'Length > 0 and then Charged /= "requester")
      then
         raise Invalid_Response with
           "invalid UploadPartCopy response headers";
      end if;
   end Validate_Upload_Part_Copy_Headers;

   function Decode_Upload_Part_Copy_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Upload_Part_Copy_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome
   is
   begin
      if Status = 200 then
         begin
            return
              (Kind   => Copy_Part_Rejected,
               Status => Status,
               Error  => Error_Response
                 (Payload, Request_ID, Host_ID, Limits));
         exception
            when S3.Errors.Malformed_Error =>
               declare
                  Result : Upload_Part_Copy_Result := Headers;
               begin
                  Validate_Upload_Part_Copy_Headers (Result);
                  Result.Copy_Part :=
                    S3.Multipart.Parse_Copy_Part_Result (Payload, Limits);
                  return
                    (Kind => Part_Copied, Status => Status, Result => Result);
               end;
         end;
      else
         return
           (Kind   => Copy_Part_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Multipart.Malformed_Multipart | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed UploadPartCopy response";
   end Decode_Upload_Part_Copy_Response;

   function Execute_Upload_Part_Copy
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome
   is
   begin
      if Prepared.Operation /= Upload_Part_Copy_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Upload_Part_Copy_Result :=
           (Copy_Source_Version_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-copy-source-version-id")),
            Copy_Part => (others => <>),
            Server_Side_Encryption => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption")),
            SSE_Customer_Algorithm => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-customer-algorithm")),
            SSE_Customer_Key_MD5 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-customer-key-md5")),
            SSE_KMS_Key_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-aws-kms-key-id")),
            Bucket_Key_Enabled => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-bucket-key-enabled")),
            Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Upload_Part_Copy_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "UploadPartCopy response exceeds XML limit";
   end Execute_Upload_Part_Copy;

   function Prepare_Copy_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Copy_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request
   is
      Copy_Source : constant String := US.To_String (Parameters.Copy_Source);
      Directive : constant String :=
        US.To_String (Parameters.Metadata_Directive);
      Request_Payer : constant String :=
        US.To_String (Parameters.Request_Payer);
      Optional_Count : constant Natural :=
        Boolean'Pos (US.Length (Parameters.Content_Type) > 0) +
        Boolean'Pos (US.Length (Parameters.Copy_Source_If_Match) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_If_Modified_Since) > 0) +
        Boolean'Pos (US.Length (Parameters.Copy_Source_If_None_Match) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Copy_Source_If_Unmodified_Since) > 0) +
        Boolean'Pos (Directive'Length > 0) +
        Boolean'Pos (Request_Payer'Length > 0) +
        Boolean'Pos (US.Length (Parameters.Expected_Bucket_Owner) > 0) +
        Boolean'Pos
          (US.Length (Parameters.Expected_Source_Bucket_Owner) > 0);
      Values : Model_Value_Array (1 .. 3 + Optional_Count);
      Last : Natural := 0;

      procedure Add (Name, Value : String) is
      begin
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String (Name),
            Map_Key     => US.Null_Unbounded_String,
            Value       => US.To_Unbounded_String (Value));
      end Add;

      procedure Add_Optional
        (Name : String; Value : US.Unbounded_String) is
      begin
         if US.Length (Value) > 0 then
            Add (Name, US.To_String (Value));
         end if;
      end Add_Optional;
   begin
      if Copy_Source'Length not in 1 .. 8_192
        or else (Directive'Length > 0
                 and then Directive not in "COPY" | "REPLACE")
        or else (Request_Payer'Length > 0
                 and then Request_Payer /= "requester")
      then
         raise Invalid_Request with "invalid CopyObject parameters";
      end if;
      Add ("Bucket", Bucket);
      Add ("CopySource", Copy_Source);
      Add ("Key", Key);
      Add_Optional ("ContentType", Parameters.Content_Type);
      Add_Optional ("CopySourceIfMatch", Parameters.Copy_Source_If_Match);
      Add_Optional
        ("CopySourceIfModifiedSince",
         Parameters.Copy_Source_If_Modified_Since);
      Add_Optional
        ("CopySourceIfNoneMatch", Parameters.Copy_Source_If_None_Match);
      Add_Optional
        ("CopySourceIfUnmodifiedSince",
         Parameters.Copy_Source_If_Unmodified_Since);
      Add_Optional ("MetadataDirective", Parameters.Metadata_Directive);
      Add_Optional ("RequestPayer", Parameters.Request_Payer);
      Add_Optional
        ("ExpectedBucketOwner", Parameters.Expected_Bucket_Owner);
      Add_Optional
        ("ExpectedSourceBucketOwner",
         Parameters.Expected_Source_Bucket_Owner);
      return Result : Prepared_Request := Prepare_Model_Request
        (Model.Copy_Object_Operation, Origin, Style, Values, "", False,
         SigV4.Empty_Payload_Hash, Identity, Region, Timestamp)
      do
         Result.Operation := Copy_Object_Operation;
      end return;
   end Prepare_Copy_Object;

   procedure Validate_Copy_Object_Headers (Value : Copy_Object_Result) is
      Bucket_Key : constant String := US.To_String (Value.Bucket_Key_Enabled);
      Charged : constant String := US.To_String (Value.Request_Charged);
   begin
      if (Bucket_Key'Length > 0
          and then not Wire_Core.Parse_Boolean (Bucket_Key).Valid)
        or else (Charged'Length > 0 and then Charged /= "requester")
      then
         raise Invalid_Response with "invalid CopyObject response headers";
      end if;
   end Validate_Copy_Object_Headers;

   function Decode_Copy_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Copy_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Copy_Object_Outcome
   is
   begin
      if Status = 200 then
         begin
            return
              (Kind   => Copy_Object_Rejected,
               Status => Status,
               Error  => Error_Response
                 (Payload, Request_ID, Host_ID, Limits));
         exception
            when S3.Errors.Malformed_Error =>
               declare
                  Result : Copy_Object_Result := Headers;
               begin
                  Validate_Copy_Object_Headers (Result);
                  Result.Copy_Result :=
                    S3.Copies.Parse_Copy_Object_Result (Payload, Limits);
                  return
                    (Kind => Object_Copied,
                     Status => Status,
                     Result => Result);
               end;
         end;
      else
         return
           (Kind   => Copy_Object_Rejected,
            Status => Status,
            Error  => Error_Response
              (Payload, Request_ID, Host_ID, Limits));
      end if;
   exception
      when S3.Copies.Malformed_Copy | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed CopyObject response";
   end Decode_Copy_Object_Response;

   function Execute_Copy_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Copy_Object_Outcome
   is
   begin
      if Prepared.Operation /= Copy_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
         Response : Flyology.HTTP.Client.Response :=
           Flyology.HTTP.Client.Execute
             (Client, Prepared.Message, Timeout, Token);
         Status : constant Flyology.HTTP.Status_Code :=
           Flyology.HTTP.Client.Status (Response);
         Request_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-request-id");
         Host_ID : constant String :=
           Flyology.HTTP.Client.Header (Response, "x-amz-id-2");
         Headers : constant Copy_Object_Result :=
           (Copy_Result => (others => <>),
            Expiration => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-expiration")),
            Copy_Source_Version_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-copy-source-version-id")),
            Version_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header (Response, "x-amz-version-id")),
            Server_Side_Encryption => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption")),
            SSE_Customer_Algorithm => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-customer-algorithm")),
            SSE_Customer_Key_MD5 => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-customer-key-md5")),
            SSE_KMS_Key_ID => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-aws-kms-key-id")),
            SSE_KMS_Encryption_Context => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-server-side-encryption-context")),
            Bucket_Key_Enabled => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response,
                  "x-amz-server-side-encryption-bucket-key-enabled")),
            Request_Charged => US.To_Unbounded_String
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-request-charged")));
         Payload : constant Flyology.Bytes.Unbounded_Bytes :=
           Flyology.HTTP.Client.Read_All
             (Response, Limits.Maximum_Document_Bytes, Token);
      begin
         return Decode_Copy_Object_Response
           (Status, Flyology.Bytes.To_Byte_String (Payload), Headers,
            Request_ID, Host_ID, Limits);
      end;
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with "CopyObject response exceeds XML limit";
   end Execute_Copy_Object;

end Flyology.Object_Storage.Client.Low_Level;
