with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.SHA256;
with Flyology.Cancellation;
with Flyology.IO;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Requests;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.Server.S3_Applications is

   package Apps renames Flyology.HTTP.Server.Applications;
   package US renames Ada.Strings.Unbounded;
   package Requests renames S3.Requests;
   package Encoding renames S3.SigV4_Encoding;
   package Deletions renames S3.Deletions;
   package Listings renames S3.Listings;
   package Multipart renames S3.Multipart;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Calendar.Time;
   use type Apps.Response_State;
   use type Authentication.Outcome_Status;
   use type Backends.Length_Kind;
   use type Multipart.Multipart_Query_Kind;
   use type Requests.Target_Kind;
   use type Requests.Target_Status;
   use type S3.Core.Range_Parse_Status;

   Payload_Hash_Mismatch : exception;
   Malformed_Body_Framing : exception;
   Body_Entity_Too_Large : exception;

   Maximum_Create_Bucket_Body : constant Byte_Count := 64 * 1_024;
   Maximum_Delete_Objects_Body : constant Byte_Count := 2 * 1_024 * 1_024;
   Maximum_Complete_Multipart_Body : constant Byte_Count :=
     2 * 1_024 * 1_024;

   function Decimal (Value : Byte_Count) return String is
     (Ada.Strings.Fixed.Trim
        (Byte_Count'Image (Value), Ada.Strings.Both));

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
         when Source_Not_Found =>
            Send_Error
              (X, 404, "NoSuchKey",
               "The specified copy source does not exist", Resource);
         when Precondition_Failed =>
            Send_Error
              (X, 412, "PreconditionFailed",
               "At least one copy source precondition failed", Resource);
         when Conflict =>
            Send_Error
              (X, 409, "OperationAborted",
               "A conflicting operation is currently in progress", Resource);
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
         Create_Bucket, Head_Bucket, Delete_Bucket,
         Put_Object, Copy_Object, Get_Object, Head_Object, Delete_Object,
         Delete_Objects,
         List_Objects, List_Objects_V2,
         Create_Multipart, Put_Multipart_Part, Copy_Multipart_Part,
         Complete_Multipart, Abort_Multipart);

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
      Padded_Query : constant String := '&' & Query_Text & '&';
      Is_List_Objects_V2_Query : constant Boolean :=
        Ada.Strings.Fixed.Index (Padded_Query, "&list-type=2&") /= 0
        or else
          Ada.Strings.Fixed.Index
            (Padded_Query, "&x-id=ListObjectsV2&") /= 0;
      Operation   : Operation_Kind := Unsupported;
      Multipart_Query_Invalid : Boolean := False;
      Has_Copy_Source : constant Boolean :=
        Apps.Request_Header_Count (X, "x-amz-copy-source") > 0;

      function Has_User_Metadata return Boolean is
      begin
         for Index in 1 .. Apps.Request_Header_Count (X) loop
            declare
               Name : constant String := Ada.Characters.Handling.To_Lower
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

      function Copy_Result_XML
        (Root : String; Value : Object_Information) return String is
        ("<" & Root &
         " xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<LastModified>" & Last_Modified (Value.Modified) &
         "</LastModified><ETag>&quot;" &
         US.To_String (Value.Entity_Tag) & "&quot;</ETag></" & Root & ">");

      package Request_IO is
         type Request_Source is limited new Backends.Byte_Source with record
            Length_Value : Backends.Source_Length :=
              (Kind => Backends.Unknown);
            Expected_Hash : US.Unbounded_String;
            Check_Hash    : Boolean := False;
            Hash          : GNAT.SHA256.Context :=
              GNAT.SHA256.Initial_Context;
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
            Apps.Read_Body (X, Data, Last, Finished);
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
            end if;
            if Finished then
               Item.Completed := True;
               if Item.Length_Value.Kind = Backends.Known
                 and then Item.Observed /= Item.Length_Value.Bytes
               then
                  raise Malformed_Body_Framing;
               elsif Item.Check_Hash
                 and then GNAT.SHA256.Digest (Item.Hash) /=
                   Encoding.Lowercase (US.To_String (Item.Expected_Hash))
               then
                  raise Payload_Hash_Mismatch;
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
            end if;
            if Partial then
               Apps.Set_Header
                 (X, "Content-Range",
                  "bytes " & Decimal (First) & "-" &
                  Decimal (First + Content_Length - 1) & "/" &
                  Decimal (Info.Size));
            end if;
            Apps.Begin_Stream
              (X, (if Partial then 206 else 200),
               US.To_String (Info.Content_Type),
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

      procedure Drain (Source : in out Request_IO.Request_Source) is
         Buffer   : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
         Last     : Ada.Streams.Stream_Element_Offset;
         Finished : Boolean := False;
      begin
         while not Finished loop
            Source.Read
              (Buffer, Last, Finished, Apps.Cancellation (X),
               Apps.Deadline (X));
         end loop;
      end Drain;

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

      Auth       : Authentication.Outcome;
      Accepted   : Boolean;
      Length_OK  : Boolean;
      Length     : Backends.Source_Length;
      Info       : Object_Information;
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
          (Parsed.Kind = Requests.Bucket_Target
           and then Method = "POST"
           and then Is_Delete_Objects_Query)
        and then not
          (Parsed.Kind = Requests.Object_Target
           and then Method = "DELETE"
           and then Requests.Query_String (Target_Text, Parsed) =
             "x-id=DeleteObject")
        and then not
          (Parsed.Kind = Requests.Object_Target
           and then Method in "POST" | "PUT" | "DELETE")
        and then not
          (Parsed.Kind = Requests.Bucket_Target and then Method = "GET")
      then
         Send_Error
           (X, 501, "NotImplemented",
            "The requested S3 operation is not implemented", Target_Text);
         return;
      end if;

      if Parsed.Kind = Requests.Bucket_Target then
         Operation :=
           (if Method = "PUT"
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
            elsif Method = "GET" and then Is_List_Objects_V2_Query
            then List_Objects_V2
            elsif Method = "GET" then List_Objects
            else Unsupported);
      elsif Parsed.Kind = Requests.Object_Target then
         if not Parsed.Has_Query or else Is_Ordinary_Operation_Query then
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
         elsif Method = "DELETE" and then Query_Text = "x-id=DeleteObject"
         then
            Operation := Delete_Object;
         elsif Method in "POST" | "PUT" | "DELETE" then
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
                     else Unsupported);
               end;
            exception
               when Multipart.Malformed_Multipart =>
                  Multipart_Query_Invalid := True;
                  Operation :=
                    (if Method = "PUT" then Put_Multipart_Part
                     elsif Method = "POST" then Complete_Multipart
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
         (if Operation in Create_Bucket | Put_Object | Delete_Objects |
         Put_Multipart_Part | Complete_Multipart
          then Apps.Stream_Body else Apps.Reject_Body),
         Apps.Required_Authentication, 0, 0, 0, Apps.No_Upgrade);
      Apps.Seal_Route (X);

      Auth := Authentication.Verify_Request (X, Credentials, Rules, Clock);
      if Auth.Status /= Authentication.Authenticated then
         Send_Authentication_Error (X, Auth, Target_Text);
         return;
      end if;
      Apps.Set_Principal (X, US.To_String (Auth.Principal));

      if Has_Encryption_Header then
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
      end if;

      if Operation not in Create_Bucket | Put_Object | Delete_Objects |
        Put_Multipart_Part | Complete_Multipart
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
            when Create_Bucket =>
               declare
                  Source : Request_IO.Request_Source :=
                    (Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Maximum_Create_Bucket_Body,
                     Completed => False);
               begin
                  Drain (Source);
               end;
               Store.Create_Bucket
                 (Bucket, Apps.Cancellation (X), Apps.Deadline (X), Result);
               if Result = Success then
                  Apps.Set_Header (X, "Location", "/" & Bucket);
                  Apps.Respond (X, 200, "", "");
               else
                  Send_Backend_Error (X, Result, True, Target_Text);
               end if;

            when Head_Bucket =>
               Store.Head_Bucket
                 (Bucket, Apps.Cancellation (X), Apps.Deadline (X), Result);
               if Result = Success then
                  Apps.Respond (X, 200, "", "");
               else
                  Send_Backend_Error (X, Result, True, Target_Text);
               end if;

            when Delete_Bucket =>
               Store.Delete_Bucket
                 (Bucket, Apps.Cancellation (X), Apps.Deadline (X), Result);
               if Result = Success then
                  Apps.Respond (X, 204, "", "");
               else
                  Send_Backend_Error (X, Result, True, Target_Text);
               end if;

            when List_Objects =>
               begin
                  declare
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
                           Delimiter       => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Delimiter))),
                           Encoding_Type   =>
                             (if Request.URL_Encoding
                              then US.To_Unbounded_String ("url")
                              else US.Null_Unbounded_String),
                           Marker          => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Marker))),
                           Next_Marker     => US.Null_Unbounded_String,
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
                     if Request.Fetch_Owner then
                        Send_Error
                          (X, 501, "NotImplemented",
                           "Object owner fields are not implemented",
                           Target_Text);
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
                           Encoding_Type      =>
                             (if Request.URL_Encoding
                              then US.To_Unbounded_String ("url")
                              else US.Null_Unbounded_String),
                           Continuation_Token => Request.Continuation_Token,
                           Has_Continuation_Token =>
                             Request.Has_Continuation_Token,
                           Next_Continuation_Token =>
                             US.Null_Unbounded_String,
                           Start_After        => US.To_Unbounded_String
                             (Encoded (US.To_String (Request.Start_After))),
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

            when Create_Multipart =>
               if Apps.Request_Header_Count (X, "content-type") > 1 then
                  Send_Error
                    (X, 400, "InvalidRequest",
                     "The Content-Type header is duplicated", Target_Text);
                  return;
               end if;
               declare
                  Options : Backends.Multipart_Options :=
                    Backends.Default_Multipart_Options;
                  Upload_ID : US.Unbounded_String;
               begin
                  if Apps.Request_Header_Count (X, "content-type") = 1 then
                     Options.Content_Type := US.To_Unbounded_String
                       (Apps.Request_Header (X, "content-type"));
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

            when Put_Multipart_Part =>
               declare
                  Query : constant Multipart.Multipart_Query :=
                    Multipart.Parse_Query (Query_Text);
                  Source : Request_IO.Request_Source :=
                    (Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Backends.Maximum_Multipart_Part_Size,
                     Completed => False);
               begin
                  Store.Put_Multipart_Part
                    (Bucket, Key, US.To_String (Query.Upload_ID),
                     Backends.Multipart_Part_Number (Query.Part_Number),
                     Source, Apps.Cancellation (X), Apps.Deadline (X),
                     Info, Result);
                  if Result = Success and then not Source.Completed then
                     raise Program_Error with
                       "backend committed before validating the whole part";
                  elsif Result = Success then
                     Apps.Set_Header
                       (X, "ETag", '"' & US.To_String (Info.Entity_Tag) & '"');
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
                  elsif Result = Source_Not_Found then
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
                    (Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Maximum_Complete_Multipart_Body,
                     Completed => False);
                  Request : constant
                    Multipart.Complete_Multipart_Upload_Request :=
                      Multipart.Parse_Complete_Request
                        (Read_Document (Source));
                  Completion : Backends.Multipart_Part_References;

                  function Bare_ETag (Value : String) return String is
                    (if Value'Length >= 2
                       and then Value (Value'First) = '"'
                       and then Value (Value'Last) = '"'
                     then Value (Value'First + 1 .. Value'Last - 1)
                     else Value);

                  function Has_Checksum
                    (Part : Multipart.Completed_Part) return Boolean is
                    (US.Length (Part.Checksum_CRC32) > 0
                     or else US.Length (Part.Checksum_CRC32C) > 0
                     or else US.Length (Part.Checksum_CRC64NVME) > 0
                     or else US.Length (Part.Checksum_SHA1) > 0
                     or else US.Length (Part.Checksum_SHA256) > 0
                     or else US.Length (Part.Checksum_SHA512) > 0
                     or else US.Length (Part.Checksum_MD5) > 0
                     or else US.Length (Part.Checksum_XXHASH64) > 0
                     or else US.Length (Part.Checksum_XXHASH3) > 0
                     or else US.Length (Part.Checksum_XXHASH128) > 0);
               begin
                  for Part of Request.Parts loop
                     if Has_Checksum (Part) then
                        Send_Error
                          (X, 501, "NotImplemented",
                           "Multipart completion checksums are not " &
                           "implemented", Target_Text);
                        return;
                     end if;
                     Completion.Append
                       (Backends.Multipart_Part_Reference'
                          (Number => Backends.Multipart_Part_Number
                             (Part.Number),
                           Entity_Tag => US.To_Unbounded_String
                             (Bare_ETag (US.To_String (Part.Entity_Tag)))));
                  end loop;
                  Store.Complete_Multipart_Upload
                    (Bucket, Key,
                     US.To_String (Query.Existing_Upload_ID), Completion,
                     Apps.Cancellation (X), Apps.Deadline (X), Info, Result);
                  if Result = Success then
                     Apps.Respond
                       (X, 200, "application/xml",
                        Multipart.Serialize_Complete_Result
                          ((Location => US.To_Unbounded_String
                              ("/" & Bucket & "/" &
                               Encoding.URI_Encode
                                 (Key, Encode_Slash => False)),
                            Bucket     => US.To_Unbounded_String (Bucket),
                            Key        => US.To_Unbounded_String (Key),
                            Entity_Tag => US.To_Unbounded_String
                              ('"' & US.To_String (Info.Entity_Tag) & '"'),
                            others     => <>)));
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
               begin
                  Store.Abort_Multipart_Upload
                    (Bucket, Key,
                     US.To_String (Query.Existing_Upload_ID),
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
               if Apps.Request_Header_Count (X, "x-amz-copy-source") /= 1
                 or else Apps.Request_Header_Count
                   (X, "x-amz-metadata-directive") > 1
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-match") > 1
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-none-match") > 1
                 or else Apps.Request_Header_Count (X, "content-type") > 1
               then
                  Send_Error
                    (X, 400, "InvalidRequest",
                     "A CopyObject header is missing or duplicated",
                     Target_Text);
                  return;
               elsif Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-modified-since") > 0
                 or else Apps.Request_Header_Count
                   (X, "x-amz-copy-source-if-unmodified-since") > 0
                 or else Apps.Request_Header_Count (X, "x-amz-acl") > 0
                 or else Has_User_Metadata
               then
                  Send_Error
                    (X, 501, "NotImplemented",
                     "This CopyObject metadata or condition is not " &
                     "implemented", Target_Text);
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
                  Raw_Source : constant String :=
                    Apps.Request_Header (X, "x-amz-copy-source");
                  Source_Target : constant String :=
                    (if Raw_Source'Length > 0
                       and then Raw_Source (Raw_Source'First) = '/'
                     then Raw_Source else '/' & Raw_Source);
                  Source_Parsed : constant Requests.Target_Result :=
                    Requests.Parse_Target (Source_Target);
                  Directive : Backends.Copy_Metadata_Directive :=
                    Backends.Copy_Metadata;
                  Copy_Options_Value : Backends.Copy_Options :=
                    Backends.Default_Copy_Options;
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
                    (X, "x-amz-metadata-directive") = 1
                  then
                     declare
                        Value : constant String :=
                          Apps.Request_Header
                            (X, "x-amz-metadata-directive");
                     begin
                        if Value = "COPY" then
                           Directive := Backends.Copy_Metadata;
                        elsif Value = "REPLACE" then
                           Directive := Backends.Replace_Metadata;
                        else
                           Send_Error
                             (X, 400, "InvalidArgument",
                              "The metadata directive is invalid",
                              Target_Text);
                           return;
                        end if;
                     end;
                  end if;
                  Copy_Options_Value.Metadata_Directive := Directive;
                  Copy_Options_Value.Content_Type :=
                    (if Apps.Request_Header_Count (X, "content-type") = 1
                     then US.To_Unbounded_String
                       (Apps.Request_Header (X, "content-type"))
                     else US.To_Unbounded_String
                       ("application/octet-stream"));
                  if Apps.Request_Header_Count
                    (X, "x-amz-copy-source-if-match") = 1
                  then
                     Copy_Options_Value.Conditions.If_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-if-match"));
                  end if;
                  if Apps.Request_Header_Count
                    (X, "x-amz-copy-source-if-none-match") = 1
                  then
                     Copy_Options_Value.Conditions.If_None_Match :=
                       US.To_Unbounded_String
                         (Apps.Request_Header
                            (X, "x-amz-copy-source-if-none-match"));
                  end if;
                  Store.Copy_Object
                    (Requests.Bucket_Name (Source_Target, Source_Parsed),
                     Requests.Object_Key (Source_Target, Source_Parsed),
                     Bucket, Key, Copy_Options_Value,
                     Apps.Cancellation (X), Apps.Deadline (X), Info, Result);
                  if Result = Success then
                     Apps.Respond
                       (X, 200, "application/xml",
                        Copy_Result_XML ("CopyObjectResult", Info));
                  elsif Result = Source_Not_Found then
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
                  Source : Request_IO.Request_Source :=
                    (Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Byte_Count'Last,
                     Completed => False);
                  Options : Put_Options := Default_Put_Options;
               begin
                  if Apps.Request_Header_Count (X, "content-type") = 1 then
                     Options.Content_Type := US.To_Unbounded_String
                       (Apps.Request_Header (X, "content-type"));
                  end if;
                  Store.Put_Object
                    (Bucket, Key, Source, Options, Apps.Cancellation (X),
                     Apps.Deadline (X), Info, Result);
                  if Result = Success and then not Source.Completed then
                     raise Program_Error with
                       "backend committed before validating the whole body";
                  end if;
               end;
               if Result = Success then
                  Apps.Set_Header
                    (X, "ETag", '"' & US.To_String (Info.Entity_Tag) & '"');
                  Apps.Respond (X, 200, "", "");
               else
                  --  Put_Object can report Not_Found only for its bucket;
                  --  the destination key need not exist before a PUT.
                  Send_Backend_Error (X, Result, True, Target_Text);
               end if;

            when Head_Object =>
               Store.Head_Object
                 (Bucket, Key, Apps.Cancellation (X), Apps.Deadline (X),
                  Info, Result);
               if Result = Success then
                  Apps.Set_Header
                    (X, "ETag", '"' & US.To_String (Info.Entity_Tag) & '"');
                  Apps.Set_Header (X, "Accept-Ranges", "bytes");
                  Apps.Set_Header
                    (X, "Last-Modified", HTTP_Last_Modified (Info.Modified));
                  if US.Length (Info.Version) > 0 then
                     Apps.Set_Header
                       (X, "x-amz-version-id", US.To_String (Info.Version));
                  end if;
                  Apps.Begin_Stream
                    (X, 200, US.To_String (Info.Content_Type),
                     Flyology.HTTP.Body_Size (Info.Size));
                  Apps.End_Stream (X);
               else
                  Send_Backend_Error (X, Result, False, Target_Text);
               end if;

            when Get_Object =>
               declare
                  Requested : Byte_Range := Whole_Object;
                  Sink      : Response_IO.Response_Sink;
               begin
                  if Apps.Request_Header_Count (X, "range") > 1 then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The Range header is duplicated", Target_Text);
                     return;
                  elsif Apps.Request_Header_Count (X, "range") = 1 then
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
                  Store.Get_Object
                    (Bucket, Key, Requested, Sink, Apps.Cancellation (X),
                     Apps.Deadline (X), Info, Result);
                  if Result = Success then
                     if not Sink.Started
                       or else Sink.Observed /= Sink.Expected
                     then
                        raise Program_Error with
                          "backend succeeded with incomplete response framing";
                     end if;
                     Apps.End_Stream (X);
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
               Store.Delete_Object
                 (Bucket, Key, Apps.Cancellation (X), Apps.Deadline (X),
                  Result);
               if Result in Success | Not_Found then
                  Apps.Respond (X, 204, "", "");
               else
                  Send_Backend_Error (X, Result, False, Target_Text);
               end if;

            when Delete_Objects =>
               declare
                  Source : Request_IO.Request_Source :=
                    (Length_Value  => Length,
                     Expected_Hash => Auth.Payload_Hash,
                     Check_Hash    =>
                       US.To_String (Auth.Payload_Hash) /=
                         S3.SigV4.Unsigned_Payload,
                     Hash      => GNAT.SHA256.Initial_Context,
                     Observed  => 0,
                     Maximum   => Maximum_Delete_Objects_Body,
                     Completed => False);
               begin
                  declare
                     Request : constant Deletions.Delete_Objects_Request :=
                       Deletions.Parse_Request
                         (Read_Document (Source),
                          (Maximum_Document_Bytes =>
                             Natural (Maximum_Delete_Objects_Body),
                           Maximum_Depth      => 8,
                           Maximum_Elements   => 3_005,
                           Maximum_Text_Bytes =>
                             Natural (Maximum_Delete_Objects_Body)));
                     Response : Deletions.Delete_Objects_Result;
                  begin
                     --  Parse and hash the admitted body before consulting
                     --  the backend, so every response leaves the HTTP
                     --  connection at the next request boundary.
                     Store.Head_Bucket
                       (Bucket, Apps.Cancellation (X), Apps.Deadline (X),
                        Result);
                     if Result /= Success then
                        Send_Backend_Error
                          (X, Result, True, Target_Text);
                        return;
                     end if;
                     for Item of Request.Objects loop
                        if US.Length (Item.Version_ID) > 0 then
                           Response.Errors.Append
                             (Deletions.Delete_Error'
                              (Key        => Item.Key,
                               Version_ID => Item.Version_ID,
                               Code       => US.To_Unbounded_String
                                 ("InvalidArgument"),
                               Message    => US.To_Unbounded_String
                                 ("Object versioning is not supported")));
                        else
                           Store.Delete_Object
                             (Bucket, US.To_String (Item.Key),
                              Apps.Cancellation (X), Apps.Deadline (X),
                              Result);
                           if Result in Success | Not_Found then
                              if not Request.Quiet then
                                 Response.Deleted.Append
                                   (Deletions.Deleted_Object'
                                      (Key        => Item.Key,
                                       Version_ID => Item.Version_ID,
                                       others     => <>));
                              end if;
                           else
                              Response.Errors.Append
                                (Deletions.Delete_Error'
                                 (Key        => Item.Key,
                                  Version_ID => Item.Version_ID,
                                  Code       => US.To_Unbounded_String
                                    (if Result in
                                         Capacity_Exceeded |
                                         Backend_Unavailable
                                     then "SlowDown"
                                     elsif Result = Conflict
                                     then "OperationAborted"
                                     else "InvalidRequest"),
                                  Message    => US.To_Unbounded_String
                                    ("The object could not be deleted")));
                           end if;
                        end if;
                     end loop;
                     Apps.Respond
                       (X, 200, "application/xml",
                        Deletions.Serialize_Result (Response));
                  end;
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
