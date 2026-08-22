with Ada.Calendar;
with Ada.Containers;
with Ada.Calendar.Formatting;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Cancellation;
with Flyology.HTTP.Server;
with Flyology.HTTP.Server.Applications;
with Flyology.IO;
with Flyology.IO.Sockets;
with Flyology.Object_Storage.Backends.Memory;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;

procedure S3_Server_Application_Corpus is
   package HTTP_Server renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Sockets renames Flyology.IO.Sockets;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Buckets renames Flyology.Object_Storage.S3.Buckets;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Listings renames Flyology.Object_Storage.S3.Listings;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package Multipart_Uploads renames
     Flyology.Object_Storage.S3.Multipart_Uploads;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Containers.Count_Type;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Access_Key : constant String := "AKIDEXAMPLE";
   Secret_Key : constant String :=
     "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
   Timestamp  : constant String := "20130524T000000Z";
   Region     : constant String := "us-east-1";
   Host       : constant String := "localhost:9000";
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

   Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 8,
      Object_Capacity => 16,
      Byte_Capacity   => 2 * 1_024 * 1_024);
   Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Access_Key, Secret_Key, Principal => "test-principal");
   Rules : constant Authentication.Policy :=
     (Expected_Region    => US.To_Unbounded_String (Region),
      Maximum_Clock_Skew => 1.0);

   package S3_App is new Flyology.Object_Storage.Server.S3_Applications
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
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Query : constant SigV4.Name_Value_Array :=
        (if Query_Name'Length = 0 then No_Query
         else (1 => SigV4.Pair (Query_Name, Query_Value)));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Authorization : String := US.To_String (Signing.Authorization);
      Wire_Body : constant String :=
        (if not Chunked then Payload
         elsif Payload'Length = 0 then "0" & CRLF & CRLF
         else Ada.Strings.Fixed.Trim
           (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
           Payload & CRLF & "0" & CRLF & CRLF);
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
   end Signed_Request;

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
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair
              (Header_Name,
               Header_Value &
                 (if Second_Value'Length = 0
                  then "" else ", " & Second_Value))));
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
      Second_Value : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Header_Name'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp),
            SigV4.Pair
              (Header_Name,
               Header_Value &
                 (if Second_Value'Length = 0
                  then "" else ", " & Second_Value))));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("DELETE", Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
   begin
      return "DELETE " & Target &
        (if Query_Text'Length = 0 then "" else "?" & Query_Text) &
        " HTTP/1.1" & CRLF & "Host: " & Host & CRLF &
        "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        (if Header_Name'Length = 0 then ""
         else Header_Name & ": " & Header_Value & CRLF) &
        (if Second_Value'Length = 0 then ""
         else Header_Name & ": " & Second_Value & CRLF) &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
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
              ("x-amz-expected-bucket-owner",
               Expected_Owner & ", " & Second_Owner)));
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

   function Signed_Upload_Part_Copy_Request
     (Target      : String;
      Upload_ID   : String;
      Copy_Source : String;
      Copy_Range  : String;
      Encryption  : String := "") return String
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
        (SigV4.Pair ("partNumber", "1"),
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
      Extra_Header_Value : String := "") return String
   is
      Payload_Hash : constant String := SigV4.SHA256_Hex ("");
      Headers : constant SigV4.Name_Value_Array :=
        (if Extra_Header_Name'Length = 0 then
           (SigV4.Pair ("host", Host),
            SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
            SigV4.Pair ("x-amz-date", Timestamp))
         else
           (SigV4.Pair ("host", Host),
            SigV4.Pair (Extra_Header_Name, Extra_Header_Value),
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
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        (if Extra_Header_Name'Length = 0 then ""
         else Extra_Header_Name & ": " & Extra_Header_Value & CRLF) &
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
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Timestamp));
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Target, Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Timestamp);
      Query_Text : constant String := SigV4.Canonical_Query (Query);
   begin
      return Method & " " & Target & "?" & Query_Text & " HTTP/1.1" &
        CRLF & "Host: " & Host & CRLF & "x-amz-date: " & Timestamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        Extra_Headers & "Content-Length: " &
        Ada.Strings.Fixed.Trim
          (Natural'Image (Payload'Length), Ada.Strings.Both) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Query_Body_Request;

   function Run (Input : String; Receive_Max : Natural := Natural'Last)
     return String
   is
      Wire : aliased Memory_Transport;
   begin
      Wire.Input := US.To_Unbounded_String (Input);
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
               null, HTTP_Server.Request_Deadline (Client));
         begin
            S3_App.Handle (X);
         end;
      end;
      return US.To_String (Wire.Output);
   end Run;

   function Has (Value, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Value, Pattern) /= 0);

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
            and then Has (Response, "ETag: """ & Part_ETag & """"),
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
            Response : constant String := Run
              (Signed_Query_Body_Request
                 ("POST", "/test-bucket/multipart-object", Query, Document),
               Receive_Max => 2);
         begin
            Require
              (Has (Response, "200 OK")
               and then Has (Response, "<ETag>""")
               and then Has (Response, "-1""</ETag>"),
               "CompleteMultipartUpload server response mismatch: " &
               Response);
         end;
      end;
      declare
         Response : constant String := Run
           (Signed_Request
              ("GET", "/test-bucket/multipart-object", ""));
      begin
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "Content-Length: 14" & CRLF)
            and then Has (Response, "Content-Type: text/plain" & CRLF)
            and then Has (Response, Payload),
            "completed multipart object was not published exactly");
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

      declare
         Abort_Create : constant String := Run
           (Signed_Query_Body_Request
              ("POST", "/test-bucket/abort-object", Create_Query, ""));
         Abort_ID : constant String := US.To_String
           (Multipart.Parse_Create_Result
              (Response_Body (Abort_Create)).Upload_ID);
         Abort_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("uploadId", Abort_ID));
         Response : constant String := Run
           (Signed_Query_Body_Request
              ("DELETE", "/test-bucket/abort-object", Abort_Query, ""));
      begin
         Require
           (Has (Response, "204 No Content"),
            "AbortMultipartUpload server response mismatch");
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
        (Has (Response, "ETag: ""5eb63bbbe01eeed093cb22bb8f5acdc3"""),
         "PutObject ETag mismatch");
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
      Require
        (Has
           (Run
              (Signed_Copy_Request
                 ("/test-bucket/copy-missing", "test-bucket/missing")),
            "NoSuchKey"),
         "CopyObject source absence was not reported as NoSuchKey");
      Require
        (Has
           (Run
              (Signed_Copy_Request
                 ("/test-bucket/object", "test-bucket/object")),
            "InvalidRequest"),
         "metadata-preserving CopyObject accepted a self copy");
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
        (Has (Range_Response, "HTTP/1.1 206 ")
         and then Has (Range_Response, "Content-Range: bytes 1-4/11")
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
            "501 Not Implemented"),
         "HeadObject silently ignored checksum mode");
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
            "501 Not Implemented"),
         "HeadObject silently ignored requester-pays");
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
            "501 Not Implemented"),
         "HeadObject silently ignored a valid SSE-C group");
      Require
        (Has
           (Run
              (Signed_Request
                 ("HEAD", "/test-bucket/object", "",
                  Extra_Headers =>
                    "If-Modified-Since: Fri, 24 May 2013 00:00:00 GMT" &
                    CRLF)),
            "501 Not Implemented"),
         "HeadObject silently ignored a date condition");
   end;

   declare
      Version : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("versionId", "version-one"));
      Part : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("partNumber", "1"));
      Override : constant SigV4.Name_Value_Array :=
        (1 => SigV4.Pair ("response-content-type", "text/plain"));
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
         "HeadObject silently ignored versionId");
      Require
        (Has
           (Run (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Part)),
            "501 Not Implemented"),
         "HeadObject silently ignored partNumber");
      Require
        (Has
           (Run (Signed_Query_Request
              ("HEAD", "/test-bucket/object", Override)),
            "501 Not Implemented"),
         "HeadObject silently ignored a response override");
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
        (Has (Run (Signed_Request
          ("PUT", "/test-bucket/multi-a", "a")), "200 OK"),
         "DeleteObjects setup A failed");
      Require
        (Has (Run (Signed_Request
          ("PUT", "/test-bucket/multi-b", "b")), "200 OK"),
         "DeleteObjects setup B failed");
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("multi-a"),
          Version_ID => US.Null_Unbounded_String));
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("multi-b"),
          Version_ID => US.Null_Unbounded_String));
      declare
         Payload : constant String := Deletions.Serialize_Request (Request);
         Response : constant String := Run
           (Signed_Request
              ("POST", "/test-bucket", Payload,
               Query_Name => "delete"));
      begin
         Require (Has (Response, "200 OK"), "DeleteObjects failed");
         Require
           (Has (Response, "<Key>multi-a</Key>")
            and then Has (Response, "<Key>multi-b</Key>"),
            "DeleteObjects response omitted deleted keys");
      end;
      Require
        (Has (Run (Signed_Request
          ("HEAD", "/test-bucket/multi-a", "")), "404 Not Found"),
         "DeleteObjects left its first key visible");
      Require
        (Has (Run (Signed_Request
          ("HEAD", "/test-bucket/multi-b", "")), "404 Not Found"),
         "DeleteObjects left its second key visible");
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Request.Quiet := True;
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("already-absent"),
          Version_ID => US.Null_Unbounded_String));
      declare
         Response : constant String := Run
           (Signed_Request
              ("POST", "/test-bucket",
               Deletions.Serialize_Request (Request),
               Query_Name => "delete"));
      begin
         Require (Has (Response, "200 OK"), "quiet DeleteObjects failed");
         Require
           (not Has (Response, "<Deleted>"),
            "quiet DeleteObjects emitted a success entry");
      end;
   end;

   declare
      Request : Deletions.Delete_Objects_Request;
   begin
      Require
        (Has (Run (Signed_Request
          ("PUT", "/test-bucket/version-preserved", "v")), "200 OK"),
         "versioned DeleteObjects setup failed");
      Request.Objects.Append
        (Deletions.Object_Identifier'
         (Key        => US.To_Unbounded_String ("version-preserved"),
          Version_ID => US.To_Unbounded_String ("unsupported-version")));
      declare
         Response : constant String := Run
           (Signed_Request
              ("POST", "/test-bucket",
               Deletions.Serialize_Request (Request),
               Query_Name => "delete"));
      begin
         Require
           (Has (Response, "InvalidArgument"),
            "versioned DeleteObjects lacked a per-key error");
      end;
      Require
        (Has (Run (Signed_Request
          ("GET", "/test-bucket/version-preserved", "")), "v"),
         "versioned DeleteObjects removed the current object");
   end;

   declare
      Malformed : constant String :=
        "<Delete><Object><VersionId>v</VersionId></Object></Delete>";
      Response : constant String := Run
        (Signed_Request
           ("POST", "/test-bucket", Malformed,
            Query_Name => "delete"));
   begin
      Require
         (Has (Response, "400 Bad Request")
          and then Has (Response, "MalformedXML"),
         "malformed DeleteObjects XML response mismatch: " & Response);
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
   begin
      Require
        (Has (Response, "200 OK")
         and then Has (Response, "<Marker></Marker>")
         and then Has (Response, "<Key>list/a</Key>")
         and then Has (Response, "<Key>list/sub/c</Key>")
         and then not Has (Response, "<KeyCount>")
         and then not Has (Response, "ContinuationToken"),
         "ListObjects v1 default response mismatch");
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
      Require
        (Has
           (Run (Signed_Query_Request ("GET", "/test-bucket", Owner)),
            "501 Not Implemented"),
         "unsupported ListObjectsV2 owner projection was hidden");
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
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "if-match",
                  Header_Value => """etag""")),
            "501 Not Implemented"),
         "DeleteObject silently ignored If-Match");
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
            "501 Not Implemented"),
         "DeleteObject silently ignored the conditional size");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy",
                  Header_Name => "x-amz-if-match-last-modified-time",
                  Header_Value => "Wed, 21 Oct 2015 07:28:00 GMT")),
            "501 Not Implemented"),
         "DeleteObject silently ignored the modification-time condition");
      Require
        (Has
           (Run
              (Signed_Delete_Object_Request
                 ("/test-bucket/delete-policy", Header_Name => "x-amz-mfa",
                  Header_Value => "device 123456")),
            "501 Not Implemented"),
         "DeleteObject silently ignored MFA Delete");
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
