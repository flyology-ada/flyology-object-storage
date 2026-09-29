--  S3-DOMAIN-B-1: Deletions.Parse_Request demands the S3 XML namespace on
--  every element, so the namespace-free <Delete> document that minio-go
--  (mc rm --recursive) and s3cmd (rm --recursive) send is answered
--  400 MalformedXML.  Both bodies below were captured off the wire from the
--  real clients against tests/bin/s3_memory_server; both carry a correct
--  Content-MD5, so they are past the SERVER-1 digest gate.  This program
--  asserts the AWS/MinIO behaviour: the documents are accepted and the keys
--  are deleted.
with Ada.Containers;
with Ada.Exceptions;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_B_1 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;

   use type Ada.Containers.Count_Type;

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   Delete_Query : constant SigV4.Name_Value_Array (1 .. 1) :=
     [SigV4.Pair ("delete", "")];

   Bucket : constant String := "/domain-b1";

   --  Captured from mc RELEASE.2025-08-13T08-35-41Z (minio-go v7.0.90).
   MC_Body : constant String :=
     "<Delete><Quiet>false</Quiet><Object><Key>k1</Key></Object></Delete>";
   --  Captured from s3cmd 2.4.0.
   S3cmd_Body : constant String :=
     "<Delete><Object><Key>k2</Key></Object></Delete>";
   --  Captured from boto3 1.43.89 / aws-cli 2.36.34 (control: accepted today).
   SDK_Body : constant String :=
     "<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Object><Key>k3</Key></Object><Quiet>false</Quiet></Delete>";

   function Delete_Request (Document : String) return String is
     (Signed_Request
        ("POST", Bucket, Document,
         "Content-MD5: " & MD5_Base64 (Document) & CRLF &
         "Content-Type: application/xml" & CRLF,
         Delete_Query));

   procedure Exchange (Label, Document, Key : String; Expect_Delete : Boolean)
   is
      Response : constant String := Run (Delete_Request (Document));
   begin
      Note (Label & " body=" & Document);
      Note ("    status=" & Image (Status_Code (Response)) &
            " body=" & Escape (Body_Of (Response)));
      if Expect_Delete then
         Check (Status_Code (Response) = 200, Label & " is answered 200");
         Check (Contains (Body_Of (Response),
                          "<Deleted><Key>" & Key & "</Key></Deleted>"),
                Label & " reports " & Key & " as deleted");
      end if;
   end Exchange;

begin
   Note ("=== fixtures ===");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket))) = 200,
          "CreateBucket " & Bucket & " is 200");
   for Index in 1 .. 3 loop
      declare
         Key : constant String := "k" & Image (Index);
      begin
         Check (Status_Code
                  (Run (Signed_Request ("PUT", Bucket & "/" & Key, "x")))
                    = 200,
                "PutObject " & Key & " is 200");
      end;
   end loop;

   Note ("");
   Note ("=== unit level: Deletions.Parse_Request ===");
   declare
      Parsed : Deletions.Delete_Objects_Request;
   begin
      Parsed := Deletions.Parse_Request (MC_Body);
      Note ("Parse_Request accepted the namespace-free document, entries=" &
            Image (Integer (Parsed.Objects.Length)));
      Check (Parsed.Objects.Length = 1,
             "Parse_Request returns one entry for the mc document");
   exception
      when Error : Deletions.Malformed_Delete =>
         Note ("Parse_Request raised Malformed_Delete: " &
               Ada.Exceptions.Exception_Message (Error));
         Check (False,
                "Deletions.Parse_Request accepts a namespace-free <Delete>");
   end;

   Note ("");
   Note ("=== server: stock-client bodies (must be accepted) ===");
   Exchange ("mc (minio-go) DeleteObjects   ", MC_Body, "k1", True);
   Exchange ("s3cmd DeleteObjects           ", S3cmd_Body, "k2", True);

   Note ("");
   Note ("=== control: the same request with xmlns (passes today) ===");
   Exchange ("boto3/aws-cli DeleteObjects   ", SDK_Body, "k3", True);

   Finish;
end Repro_S3_Domain_B_1;
