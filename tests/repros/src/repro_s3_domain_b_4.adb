--  S3-DOMAIN-B-4: Multipart_Uploads.Validate compares the ListMultipartUploads
--  key markers bytewise, but the server fills them with percent-encoded text
--  when encoding-type=url was requested.  Percent encoding is not order
--  preserving ('%' is 16#25#, below every unreserved byte), so a perfectly
--  valid truncated page whose next key diverges at an encoded byte fails the
--  "next cursor does not advance" check.  Serialize_List_Multipart_Uploads
--  then raises Malformed_Upload_Listing, which the ListMultipartUploads
--  handler does not catch, and the request ends as 500 InternalError; the
--  client maps the same exception to Invalid_Response.
--
--  Keys a9 / a: / az: raw "a9" < "a:", but encoded "a%3A" < "a9".
with Ada.Exceptions;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_B_4 is

   package Multipart_Uploads renames
     Flyology.Object_Storage.S3.Multipart_Uploads;

   Bucket : constant String := "/domain-b4";

   function Element_Text (Document, Name : String) return String is
      Open  : constant String := "<" & Name & ">";
      Close : constant String := "</" & Name & ">";
      From  : Natural := 0;
   begin
      if Document'Length < Open'Length then
         return "";
      end if;
      for Index in Document'First .. Document'Last - Open'Length + 1 loop
         if Document (Index .. Index + Open'Length - 1) = Open then
            From := Index + Open'Length;
            exit;
         end if;
      end loop;
      if From = 0 then
         return "";
      end if;
      for Index in From .. Document'Last - Close'Length + 1 loop
         if Document (Index .. Index + Close'Length - 1) = Close then
            return Document (From .. Index - 1);
         end if;
      end loop;
      return "";
   end Element_Text;

   procedure Create_Upload (Key : String) is
      Response : constant String :=
        Run (Signed_Request
               ("POST", Bucket & "/" & Key, "", "",
                [SigV4.Pair ("uploads", "")]));
   begin
      Note ("CreateMultipartUpload key=[" & Key & "] status=" &
            Image (Status_Code (Response)) & " uploadId=" &
            Element_Text (Body_Of (Response), "UploadId"));
      Check (Status_Code (Response) = 200,
             "CreateMultipartUpload for key [" & Key & "] is 200");
   end Create_Upload;

   --  Hand-built page that a conforming server (AWS with EncodingType=url)
   --  produces for the same fixtures; the client decoder must accept it.
   Encoded_Page : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListMultipartUploadsResult " &
     "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Bucket>domain-b4</Bucket>" &
     "<KeyMarker>a9</KeyMarker>" &
     "<UploadIdMarker>u1</UploadIdMarker>" &
     "<NextKeyMarker>a%3A</NextKeyMarker>" &
     "<NextUploadIdMarker>u2</NextUploadIdMarker>" &
     "<MaxUploads>1</MaxUploads>" &
     "<IsTruncated>true</IsTruncated>" &
     "<EncodingType>url</EncodingType>" &
     "<Upload><Key>a%3A</Key><UploadId>u2</UploadId>" &
     "<Initiated>2026-01-01T00:00:00.000Z</Initiated></Upload>" &
     "</ListMultipartUploadsResult>";

begin
   Note ("=== fixtures ===");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket))) = 200,
          "CreateBucket " & Bucket & " is 200");
   Create_Upload ("a9");
   Create_Upload ("a:");
   Create_Upload ("az");

   Note ("");
   Note ("=== client decoder: a conforming truncated url-encoded page ===");
   declare
      Decoded : Multipart_Uploads.List_Multipart_Uploads_Result;
   begin
      Decoded := Multipart_Uploads.Parse_List_Multipart_Uploads
        (Encoded_Page);
      Note ("Parse_List_Multipart_Uploads accepted the page, uploads=" &
            Image (Integer (Decoded.Uploads.Length)));
      Check (True, "client decodes an encoded truncated page");
   exception
      when Error : Multipart_Uploads.Malformed_Upload_Listing =>
         Note ("Parse_List_Multipart_Uploads raised " &
               "Malformed_Upload_Listing: " &
               Ada.Exceptions.Exception_Message (Error));
         Check (False, "client decodes an encoded truncated page");
   end;

   Note ("");
   Note ("=== server: paging with encoding-type=url&max-uploads=1 ===");
   declare
      Page_1 : constant String :=
        Run (Signed_Request
               ("GET", Bucket, "", "",
                [SigV4.Pair ("uploads", ""),
                 SigV4.Pair ("encoding-type", "url"),
                 SigV4.Pair ("max-uploads", "1")]));
      Body_1 : constant String := Body_Of (Page_1);
      Next_Key : constant String := Element_Text (Body_1, "NextKeyMarker");
      Next_ID  : constant String :=
        Element_Text (Body_1, "NextUploadIdMarker");
   begin
      Note ("page 1 status=" & Image (Status_Code (Page_1)));
      Note ("    body=" & Escape (Body_1));
      Check (Status_Code (Page_1) = 200, "page 1 is 200");
      Check (Next_Key = "a9", "page 1 NextKeyMarker is a9");
      declare
         Page_2 : constant String :=
           Run (Signed_Request
                  ("GET", Bucket, "", "",
                   [SigV4.Pair ("uploads", ""),
                    SigV4.Pair ("encoding-type", "url"),
                    SigV4.Pair ("max-uploads", "1"),
                    SigV4.Pair ("key-marker", Next_Key),
                    SigV4.Pair ("upload-id-marker", Next_ID)]));
         Body_2 : constant String := Body_Of (Page_2);
      begin
         Note ("page 2 (key-marker=" & Next_Key & ") status=" &
               Image (Status_Code (Page_2)));
         Note ("    body=" & Escape (Body_2));
         Check (Status_Code (Page_2) = 200,
                "page 2 of a url-encoded listing is 200");
         Check (Element_Text (Body_2, "NextKeyMarker") = "a%3A",
                "page 2 reports the encoded next key marker a%3A");
      end;
   end;

   Note ("");
   Note ("=== control: the same paging without encoding-type ===");
   declare
      Plain : constant String :=
        Run (Signed_Request
               ("GET", Bucket, "", "",
                [SigV4.Pair ("uploads", ""),
                 SigV4.Pair ("max-uploads", "1"),
                 SigV4.Pair ("key-marker", "a9")]));
   begin
      Note ("plain page 2 status=" & Image (Status_Code (Plain)));
      Note ("    body=" & Escape (Body_Of (Plain)));
      Check (Status_Code (Plain) = 200,
             "control: page 2 without encoding-type is 200");
   end;

   Finish;
end Repro_S3_Domain_B_4;
