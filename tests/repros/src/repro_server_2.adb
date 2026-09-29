--  SERVER-2: reading a delete marker.  The pinned model documents, on
--  GetObjectOutput.DeleteMarker (x-amz-delete-marker):
--
--    "If the current version of the object is a delete marker, Amazon S3
--     behaves as if the object was deleted and includes
--     x-amz-delete-marker: true in the response."
--    "If the specified version in the request is a delete marker, the
--     response returns a 405 Method Not Allowed error and the
--     Last-Modified: timestamp response header."
--
--  This program enables versioning, writes a key, deletes it to publish a
--  marker, and then asserts both documented behaviours on GET and HEAD.  It
--  also checks the controls that must pass today: DELETE reports the marker,
--  a live key still reads 200, and a key that never existed reads 404 with no
--  marker header.
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Server_2 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   Versioning_Document : constant String :=
     "<VersioningConfiguration " &
     "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Status>Enabled</Status></VersioningConfiguration>";

   Versioning_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("versioning", ""));

   procedure Report (Label : String; Response : String) is
   begin
      Note (Label & ": status " & Image (Status_Code (Response)) &
            "  x-amz-delete-marker=[" &
            Header_Value (Response, "x-amz-delete-marker") &
            "]  x-amz-version-id=[" &
            Header_Value (Response, "x-amz-version-id") &
            "]  Last-Modified=[" &
            Header_Value (Response, "Last-Modified") & "]");
      if Status_Code (Response) /= 200 then
         Note ("   body " & Escape (Body_Of (Response)));
      end if;
   end Report;

   Marker_Version : String (1 .. 256);
   Marker_Last    : Natural := 0;

begin
   Check (Status_Code (Run (Signed_Request ("PUT", "/marker-bucket"))) = 200,
          "fixture: CreateBucket /marker-bucket");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/marker-bucket", Versioning_Document,
                     Extra_Headers =>
                       "Content-MD5: " & MD5_Base64 (Versioning_Document) &
                       CRLF,
                     Query => Versioning_Query))) = 200,
          "fixture: PutBucketVersioning Enabled");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/marker-bucket/k", "payload"))) = 200,
          "fixture: PutObject /marker-bucket/k");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/marker-bucket/live", "still here"))) = 200,
          "fixture: PutObject /marker-bucket/live");

   --  Publish the delete marker and remember its version id.
   declare
      Response : constant String :=
        Run (Signed_Request ("DELETE", "/marker-bucket/k"));
      Version  : constant String :=
        Header_Value (Response, "x-amz-version-id");
   begin
      Report ("CONTROL DELETE /marker-bucket/k", Response);
      Check (Status_Code (Response) = 204,
             "CONTROL: DELETE of a versioned key is 204");
      Check (Header_Value (Response, "x-amz-delete-marker") = "true",
             "CONTROL: DELETE reports x-amz-delete-marker: true");
      Check (Version /= "" and then Version /= "null",
             "CONTROL: DELETE reports the marker version id");
      Marker_Last := Version'Length;
      Marker_Version (1 .. Marker_Last) := Version;
   end;

   --  (a) The current version is a delete marker: GET must still be 404, but
   --      must carry x-amz-delete-marker: true.
   declare
      Response : constant String :=
        Run (Signed_Request ("GET", "/marker-bucket/k"));
   begin
      Report ("GET a key whose current version is a delete marker", Response);
      Check (Status_Code (Response) = 404,
             "GET of a current delete marker is 404");
      Check (Header_Value (Response, "x-amz-delete-marker") = "true",
             "GET of a current delete marker carries " &
             "x-amz-delete-marker: true");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request ("HEAD", "/marker-bucket/k"));
   begin
      Report ("HEAD a key whose current version is a delete marker",
              Response);
      Check (Status_Code (Response) = 404,
             "HEAD of a current delete marker is 404");
      Check (Header_Value (Response, "x-amz-delete-marker") = "true",
             "HEAD of a current delete marker carries " &
             "x-amz-delete-marker: true");
   end;

   --  (b) The requested version IS the delete marker: 405 with Last-Modified.
   declare
      Response : constant String :=
        Run (Signed_Request
               ("GET", "/marker-bucket/k",
                Query =>
                  (1 => SigV4.Pair
                     ("versionId", Marker_Version (1 .. Marker_Last)))));
   begin
      Report ("GET ?versionId=<the marker itself>", Response);
      Check (Status_Code (Response) = 405,
             "GET of an exact delete-marker version is 405 " &
             "MethodNotAllowed");
      Check (Header_Value (Response, "x-amz-delete-marker") = "true",
             "GET of an exact delete-marker version carries " &
             "x-amz-delete-marker: true");
      Check (Header_Value (Response, "Last-Modified") /= "",
             "GET of an exact delete-marker version carries Last-Modified");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request
               ("HEAD", "/marker-bucket/k",
                Query =>
                  (1 => SigV4.Pair
                     ("versionId", Marker_Version (1 .. Marker_Last)))));
   begin
      Report ("HEAD ?versionId=<the marker itself>", Response);
      Check (Status_Code (Response) = 405,
             "HEAD of an exact delete-marker version is 405 " &
             "MethodNotAllowed");
      Check (Header_Value (Response, "x-amz-delete-marker") = "true",
             "HEAD of an exact delete-marker version carries " &
             "x-amz-delete-marker: true");
   end;

   --  Controls that must pass today.
   declare
      Response : constant String :=
        Run (Signed_Request ("GET", "/marker-bucket/live"));
   begin
      Report ("CONTROL GET of a live key", Response);
      Check (Status_Code (Response) = 200 and then Body_Of (Response) =
               "still here",
             "CONTROL: GET of a live key still reads 200");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request ("GET", "/marker-bucket/never-existed"));
   begin
      Report ("CONTROL GET of a key that never existed", Response);
      Check (Status_Code (Response) = 404,
             "CONTROL: GET of an absent key is 404");
      Check (Header_Value (Response, "x-amz-delete-marker") = "",
             "CONTROL: GET of an absent key carries no delete-marker header");
   end;

   Finish;
end Repro_Server_2;
