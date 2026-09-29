--  SERVER-4: CompleteMultipartUpload returns a path, not a URI, in
--  <Location>.  The pinned model documents
--  shapes.CompleteMultipartUploadOutput.members.Location as "The URI that
--  identifies the newly created object"; RFC 3986 requires a scheme in a URI,
--  and the server emits "/bucket/key".
--
--  This program runs a one-part multipart upload and asserts that Location is
--  an absolute URI naming the object.  Controls: the upload itself succeeds
--  and Bucket, Key and a composite ETag are present and correct.
with Ada.Strings.Fixed;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Server_4 is

   function Index_Of (Haystack, Needle : String) return Natural is
     (Ada.Strings.Fixed.Index (Haystack, Needle));

   function Element_Text (Document, Name : String) return String is
      Open  : constant Natural := Index_Of (Document, "<" & Name & ">");
   begin
      if Open = 0 then
         return "";
      end if;
      declare
         First : constant Natural := Open + Name'Length + 2;
         Stop  : constant Natural :=
           Index_Of (Document (First .. Document'Last), "</" & Name & ">");
      begin
         return (if Stop = 0 then "" else Document (First .. Stop - 1));
      end;
   end Element_Text;

   Upload_Buffer : String (1 .. 512);
   Upload_Last   : Natural := 0;

begin
   Check (Status_Code (Run (Signed_Request ("PUT", "/mpu-bucket"))) = 200,
          "fixture: CreateBucket /mpu-bucket");

   declare
      Created : constant String :=
        Run (Signed_Request
               ("POST", "/mpu-bucket/dir/object.bin",
                Query => (1 => SigV4.Pair ("uploads", ""))));
      Upload  : constant String := Element_Text (Body_Of (Created), "UploadId");
   begin
      Check (Status_Code (Created) = 200 and then Upload /= "",
             "fixture: CreateMultipartUpload returns an UploadId");
      Upload_Last := Upload'Length;
      if Upload_Last > 0 then
         Upload_Buffer (1 .. Upload_Last) := Upload;
      end if;
   end;

   if Upload_Last = 0 then
      Finish;
      return;
   end if;

   declare
      Part : constant String :=
        Run (Signed_Request
               ("PUT", "/mpu-bucket/dir/object.bin", Repeat ('x', 32),
                Query =>
                  (SigV4.Pair ("partNumber", "1"),
                   SigV4.Pair ("uploadId", Upload_Buffer (1 .. Upload_Last)))));
      ETag : constant String := Header_Value (Part, "ETag");
      Manifest : constant String :=
        "<CompleteMultipartUpload " &
        "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Part><PartNumber>1</PartNumber><ETag>" & ETag &
        "</ETag></Part></CompleteMultipartUpload>";
      Done : constant String :=
        Run (Signed_Request
               ("POST", "/mpu-bucket/dir/object.bin", Manifest,
                Query =>
                  (1 => SigV4.Pair
                     ("uploadId", Upload_Buffer (1 .. Upload_Last)))));
      Doc  : constant String := Body_Of (Done);
      Where : constant String := Element_Text (Doc, "Location");
   begin
      Check (Status_Code (Part) = 200, "fixture: UploadPart is 200");
      Note ("CompleteMultipartUpload status " & Image (Status_Code (Done)));
      Note ("   body " & Escape (Doc));
      Note ("   <Location> = [" & Where & "]");
      Check (Status_Code (Done) = 200,
             "CONTROL: CompleteMultipartUpload is 200");
      Check (Element_Text (Doc, "Bucket") = "mpu-bucket",
             "CONTROL: the result names the bucket");
      Check (Element_Text (Doc, "Key") = "dir/object.bin",
             "CONTROL: the result names the key");
      Check (Contains (Element_Text (Doc, "ETag"), "-1"),
             "CONTROL: the result carries a composite ETag");
      Check (Contains (Where, "://"),
             "CompleteMultipartUpload <Location> is an absolute URI " &
             "(the model documents 'The URI that identifies the newly " &
             "created object')");
      Check (Contains (Where, "dir/object.bin"),
             "CONTROL: <Location> at least names the object");
   end;

   Finish;
end Repro_Server_4;
