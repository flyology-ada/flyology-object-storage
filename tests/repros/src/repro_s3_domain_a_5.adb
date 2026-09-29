--  S3-DOMAIN-A-5: S3.Versioning.Parse -- the codec the server calls for the
--  PutBucketVersioning body (server-s3_applications.adb:10425) -- is the
--  only request-body codec in the crate that requires the S3 namespace on
--  the root element (versioning.adb:47-54 with
--  Allow_Empty_Namespace => False, versioning.adb:171-176).  Every sibling
--  request parser accepts an unqualified root:
--    Lifecycle.Parse            lifecycle.adb:70-73      (Unqualified)
--    Notifications.Parse        notifications.adb:167-170 (Unqualified)
--    Buckets.Parse_Create_Configuration  buckets.adb:531-545 (no namespace
--                                        check at all)
--  and the crate's own Versioning.Parse_Response accepts it
--  (versioning.adb:178-186), documented in versioning.ads:29-32 as "a few
--  otherwise compatible implementations omit it".
--
--  Correct behaviour asserted here: the server accepts a signed
--  PUT /b?versioning whose body omits xmlns, exactly as it accepts a
--  namespace-free CreateBucketConfiguration on the same connection, and a
--  following GET ?versioning reports Enabled.
--
--  repro_s3_domain_a_5_live.adb holds the same application on a loopback
--  port so boto3, aws-cli v2 and mc can be pointed at it; what those three
--  actually put on the wire is recorded in the report.

with Ada.Exceptions;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.Notifications;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_A_5 is

   package Buckets renames Flyology.Object_Storage.S3.Buckets;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Lifecycle renames Flyology.Object_Storage.S3.Lifecycle;
   package Notifications renames Flyology.Object_Storage.S3.Notifications;
   package Versioning renames Flyology.Object_Storage.S3.Versioning;
   package XML renames Flyology.Object_Storage.S3.XML;

   NS : constant String := "http://s3.amazonaws.com/doc/2006-03-01/";

   function MD5_Header (Value : String) return String is
     ("Content-MD5: " &
      Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))) & CRLF);

   Qualified_Body : constant String :=
     "<VersioningConfiguration xmlns=""" & NS & """>" &
     "<Status>Enabled</Status></VersioningConfiguration>";

   Unqualified_Body : constant String :=
     "<VersioningConfiguration><Status>Enabled</Status>" &
     "</VersioningConfiguration>";

   Unqualified_Lifecycle : constant String :=
     "<LifecycleConfiguration><Rule><ID>r</ID>" &
     "<Status>Enabled</Status><Expiration><Days>1</Days></Expiration>" &
     "</Rule></LifecycleConfiguration>";

   Unqualified_Notification : constant String :=
     "<NotificationConfiguration/>";

   Unqualified_Create : constant String :=
     "<CreateBucketConfiguration>" &
     "<LocationConstraint>eu-west-1</LocationConstraint>" &
     "</CreateBucketConfiguration>";

   Versioning_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("versioning", ""));

   Bucket : constant String := "/domain-a-5";
   Other_Bucket : constant String := "/domain-a-5-other";

   procedure Report_Codec (Label : String; Accepted : Boolean) is
   begin
      Note ("  codec " & Label & ": " &
            (if Accepted then "accepted" else "REJECTED"));
   end Report_Codec;

begin
   ----------------------------------------------------------------------
   --  Part 1: the pure codecs, side by side.
   ----------------------------------------------------------------------
   Note ("--- unqualified request bodies through their own parsers ---");

   begin
      declare
         Ignored : constant Lifecycle.Lifecycle_Configuration :=
           Lifecycle.Parse (Unqualified_Lifecycle, XML.Default_Limits);
         pragma Unreferenced (Ignored);
      begin
         Report_Codec ("Lifecycle.Parse", True);
      end;
   exception
      when Lifecycle.Malformed_Lifecycle =>
         Report_Codec ("Lifecycle.Parse", False);
   end;

   begin
      declare
         Ignored : constant Notifications.Notification_Configuration :=
           Notifications.Parse (Unqualified_Notification, XML.Default_Limits);
         pragma Unreferenced (Ignored);
      begin
         Report_Codec ("Notifications.Parse", True);
      end;
   exception
      when Notifications.Malformed_Notification =>
         Report_Codec ("Notifications.Parse", False);
   end;

   begin
      declare
         Ignored : constant Buckets.Create_Bucket_Configuration :=
           Buckets.Parse_Create_Configuration
             (Unqualified_Create, XML.Default_Limits);
         pragma Unreferenced (Ignored);
      begin
         Report_Codec ("Buckets.Parse_Create_Configuration", True);
      end;
   exception
      when Buckets.Malformed_Bucket_Configuration =>
         Report_Codec ("Buckets.Parse_Create_Configuration", False);
   end;

   begin
      declare
         Ignored : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse_Response (Unqualified_Body);
         pragma Unreferenced (Ignored);
      begin
         Report_Codec ("Versioning.Parse_Response", True);
      end;
   exception
      when Versioning.Malformed_Configuration =>
         Report_Codec ("Versioning.Parse_Response", False);
   end;

   begin
      declare
         Ignored : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse (Unqualified_Body);
         pragma Unreferenced (Ignored);
      begin
         Report_Codec ("Versioning.Parse", True);
      end;
      Check (True, "Versioning.Parse accepts an unqualified root");
   exception
      when E : Versioning.Malformed_Configuration =>
         Report_Codec ("Versioning.Parse", False);
         Note ("    " & Ada.Exceptions.Exception_Message (E));
         Check (False, "Versioning.Parse accepts an unqualified root");
   end;

   ----------------------------------------------------------------------
   --  Part 2: the same bodies over the in-process S3 application.
   ----------------------------------------------------------------------
   Note ("--- signed requests through the S3 application ---");
   Note ("CreateBucket " & Bucket & " status " &
         Image (Status_Code (Run (Signed_Request ("PUT", Bucket)))));

   --  Control A: the namespaced versioning body is accepted today.
   declare
      Response : constant String := Run
        (Signed_Request
           ("PUT", Bucket, Qualified_Body,
            MD5_Header (Qualified_Body), Versioning_Query));
   begin
      Note ("PUT " & Bucket & "?versioning  (xmlns present) -> " &
            Image (Status_Code (Response)));
      Check (Status_Code (Response) = 200,
             "namespaced PutBucketVersioning is accepted");
   end;

   --  A second bucket whose versioning is still unconfigured, so the
   --  assertion below cannot be satisfied by the qualified PUT above.
   declare
      Response : constant String :=
        Run (Signed_Request ("PUT", Other_Bucket));
   begin
      Note ("CreateBucket " & Other_Bucket & " status " &
            Image (Status_Code (Response)));
      Check (Status_Code (Response) = 200,
             "the second bucket is created");
   end;

   --  The finding, on a bucket whose versioning is still unconfigured.
   declare
      Response : constant String := Run
        (Signed_Request
           ("PUT", Other_Bucket, Unqualified_Body,
            MD5_Header (Unqualified_Body), Versioning_Query));
   begin
      Note ("PUT " & Other_Bucket & "?versioning (no xmlns) -> " &
            Image (Status_Code (Response)));
      Note ("  body: " & Escape (Body_Of (Response)));
      Check (Status_Code (Response) = 200,
             "namespace-free PutBucketVersioning is accepted");
   end;

   declare
      Response : constant String := Run
        (Signed_Request ("GET", Other_Bucket, "", "", Versioning_Query));
   begin
      Note ("GET " & Other_Bucket & "?versioning -> " &
            Image (Status_Code (Response)) & " body " &
            Escape (Body_Of (Response)));
      Check (Contains (Body_Of (Response), "<Status>Enabled</Status>"),
             "the bucket ends up with versioning enabled");
   end;

   Finish;
end Repro_S3_Domain_A_5;
