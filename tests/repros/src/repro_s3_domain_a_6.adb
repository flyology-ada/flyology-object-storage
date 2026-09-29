--  S3-DOMAIN-A-6 (new; the discovery listed this as an uncounted
--  observation): the three listing query parsers reject max-keys above
--  S3.Core.Page_Size'Last = 1000 instead of clamping, so the Flyology
--  server answers 400 InvalidArgument to a request AWS documents as valid
--  and MinIO answers 200 to.
--
--    src/flyology-object_storage-s3-listings.adb:111-118   (ListObjects v1)
--    src/flyology-object_storage-s3-listings.adb:223-230   (ListObjectsV2)
--    src/flyology-object_storage-s3-versions.adb:134-141   (ListObjectVersions)
--        if ... Number.Value > Core.Page_Size'Last then
--           raise Malformed_List_Request with "invalid ... max-keys";
--    src/flyology-object_storage-s3-core.ads:28
--        subtype Page_Size is Natural range 0 .. 1_000;
--    server mapping: src/flyology-object_storage-server-s3_applications.adb
--        :10763-10767 and the two neighbouring handlers -> 400 InvalidArgument
--
--  AWS's own contract for max-keys (ListObjectsV2, ListObjects and
--  ListObjectVersions API Reference, "URI Request Parameters") is
--  "Sets the maximum number of keys returned in the response. By default,
--  the action returns up to 1,000 key names. The response might contain
--  fewer keys but will never contain more." -- a ceiling on the response,
--  not a request-validity rule; the operations' Errors sections list no
--  error for an oversized max-keys.  The pinned MinIO image used by
--  tests/scripts/test-minio.sh answers GET ?max-keys=2000 and
--  ?list-type=2&max-keys=2000 with 200 and echoes <MaxKeys>2000</MaxKeys>.
--  Observed with aws-cli/2.36.34 against the loopback listener of this same
--  application:
--    aws s3api list-objects-v2 --bucket b --max-keys 2000
--      -> An error occurred (InvalidArgument) when calling the ListObjectsV2
--         operation: The ListObjectsV2 request is invalid
--
--  Correct behaviour asserted here: the server answers 200 to max-keys
--  above 1000 on all three listing operations, capping the page instead.
--
--  A fix needs a maintainer decision, because S3.Core.Page_Size is a
--  visible subtype: either the query parsers clamp an oversized max-keys to
--  Page_Size'Last (leaving the subtype alone), or the request-side bound
--  becomes wider than the response-side page bound.

with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_A_6 is

   Bucket : constant String := "/domain-a-6";

   procedure Probe
     (Label           : String;
      Query           : SigV4.Name_Value_Array;
      Assert_Accepted : Boolean)
   is
      Response : constant String :=
        Run (Signed_Request ("GET", Bucket, "", "", Query));
      Status   : constant Natural := Status_Code (Response);
   begin
      Note (Label & " -> " & Image (Status));
      if Status /= 200 then
         Note ("  body: " & Escape (Body_Of (Response)));
      end if;
      if Assert_Accepted then
         Check (Status = 200, Label & " is accepted");
      end if;
   end Probe;

begin
   Note ("CreateBucket " & Bucket & " status " &
         Image (Status_Code (Run (Signed_Request ("PUT", Bucket)))));
   Note ("PutObject " & Bucket & "/k1 status " &
         Image (Status_Code
                  (Run (Signed_Request ("PUT", Bucket & "/k1", "x")))));

   --  Controls: max-keys at the boundary is accepted today on all three.
   Probe ("GET ?max-keys=1000                 ",
          [SigV4.Pair ("max-keys", "1000")], True);
   Probe ("GET ?list-type=2&max-keys=1000     ",
          [SigV4.Pair ("list-type", "2"), SigV4.Pair ("max-keys", "1000")],
          True);
   Probe ("GET ?versions&max-keys=1000        ",
          [SigV4.Pair ("max-keys", "1000"), SigV4.Pair ("versions", "")],
          True);

   --  The finding.
   Probe ("GET ?max-keys=2000                 ",
          [SigV4.Pair ("max-keys", "2000")], True);
   Probe ("GET ?list-type=2&max-keys=2000     ",
          [SigV4.Pair ("list-type", "2"), SigV4.Pair ("max-keys", "2000")],
          True);
   Probe ("GET ?versions&max-keys=2000        ",
          [SigV4.Pair ("max-keys", "2000"), SigV4.Pair ("versions", "")],
          True);

   Finish;
end Repro_S3_Domain_A_6;
