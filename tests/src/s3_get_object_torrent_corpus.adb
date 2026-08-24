with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Object_Torrent_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Get_Object_Torrent_Outcome_Kind;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>NoSuchKey</Code><Message>missing</Message>" &
     "<Resource>/example-bucket/object</Resource></Error>";
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  The model's representative client/server error classes gate typed
   --  rejection without treating any one provider's status set as exhaustive.
   Rejection_Statuses : constant Status_Array :=
     (400, 403, 404, 429, 500);
   --  The test value is the production signer's established per-header
   --  admission boundary; it is not a new GetObjectTorrent policy.
   Header_Boundary : constant Positive := 8_192;
   --  This is the production object-key validator's established boundary;
   --  exact and one-past cases prove that the client does not narrow it.
   Key_Boundary : constant Positive := 1_024;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket";
      Key    : String := "object";
      Payer  : String := "";
      Owner  : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Torrent
                (Origin, Low_Level.Path_Style, Bucket, Key,
                 (Request_Payer         => US.To_Unbounded_String (Payer),
                  Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Prepared);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require (Raised, "GetObjectTorrent admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
              Low_Level.Decode_Get_Object_Torrent_Response_Head
                (Status, Payload, Request_Charged, Request_ID, Host_ID,
                 Limits);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "GetObjectTorrent admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Parameters : constant Low_Level.Get_Object_Torrent_Parameters :=
        (Request_Payer         => US.To_Unbounded_String ("requester"),
         Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012"));
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Torrent
          (Origin, Low_Level.Path_Style, "example-bucket", "path/to object",
           Parameters, Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Torrent
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", "path/to object",
           Parameters, Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/path/to%20object?torrent"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetObjectTorrent path-style projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/path/to%20object?torrent"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetObjectTorrent virtual-hosted projection mismatch");
   end;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Torrent
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Prepared) = "/example-bucket/object?torrent"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared), "x-amz-request-payer") = 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared),
            "x-amz-expected-bucket-owner") = 0,
         "GetObjectTorrent optional omission mismatch");
   end;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Key => "");
   Expect_Invalid_Request
     (Key => String'(1 .. Key_Boundary + 1 => 'k'));
   Expect_Invalid_Request (Payer => "Requester");
   Expect_Invalid_Request (Payer => "requester,other");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Key : constant String := String'(1 .. Key_Boundary => 'k');
      Exact_Owner : constant String :=
        String'(1 .. Header_Boundary => 'o');
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Torrent
          (Origin, Low_Level.Path_Style, "example-bucket", Exact_Key,
           (Request_Payer         => US.Null_Unbounded_String,
            Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Prepared);
   begin
      null;
   end;

   for Index in 1 .. 2 loop
      declare
         Charged : constant String :=
           (if Index = 1 then "" else "requester");
         Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
           Low_Level.Decode_Get_Object_Torrent_Response_Head
             (200, "", Charged);
      begin
         Require
           (Outcome.Kind = Low_Level.Torrent_Opened
            and then Outcome.Status = 200
            and then US.To_String (Outcome.Result.Request_Charged) = Charged,
            "GetObjectTorrent typed success mismatch");
      end;
   end loop;

   Expect_Invalid_Response (200, "torrent bytes");
   Expect_Invalid_Response (200, "", Request_Charged => "RequestEr");
   Expect_Invalid_Response
     (200, "", Request_Charged =>
        String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "", Request_ID => "request" & Character'Val (13));
   Expect_Invalid_Response
     (200, "", Request_ID =>
        String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "", Host_ID => "host" & Character'Val (10));
   Expect_Invalid_Response
     (200, "", Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));

   declare
      Exact_Request_ID : constant String :=
        String'(1 .. Header_Boundary => 'r');
      Exact_Host_ID : constant String :=
        String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
        Low_Level.Decode_Get_Object_Torrent_Response_Head
          (403, Error_XML, Request_ID => Exact_Request_ID,
           Host_ID => Exact_Host_ID);
   begin
      Require
        (Outcome.Kind = Low_Level.Get_Object_Torrent_Rejected
         and then US.To_String (Outcome.Error.Request_ID) = Exact_Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Exact_Host_ID,
         "GetObjectTorrent exact header boundary mismatch");
   end;

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
           Low_Level.Decode_Get_Object_Torrent_Response_Head
             (Status, Error_XML, Request_ID => "request-id",
              Host_ID => "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Object_Torrent_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "NoSuchKey"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "GetObjectTorrent typed rejection mismatch");
      end;
   end loop;

   Expect_Invalid_Response (403, "");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");
   Expect_Invalid_Response
     (403, "<!DOCTYPE Error [<!ENTITY x 'bad'>]>" &
        "<Error><Code>&x;</Code></Error>");
   declare
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
         Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
         Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes);
      Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
        Low_Level.Decode_Get_Object_Torrent_Response_Head
          (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (403, Error_XML,
         Limits =>
           (Maximum_Document_Bytes => Error_XML'Length - 1,
            Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
            Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
            Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes));
   end;

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object_Torrent (HTTP, Wrong);
            pragma Unreferenced (Response);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require
        (Raised,
         "GetObjectTorrent executor admitted another operation before HTTP");
   end;

   Ada.Text_IO.Put_Line ("S3 GetObjectTorrent deterministic corpus: OK");
end S3_Get_Object_Torrent_Corpus;
