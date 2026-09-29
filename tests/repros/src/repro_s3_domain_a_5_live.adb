--  S3-DOMAIN-A-5 supporting evidence: hold the in-process S3 application on
--  a real loopback port so stock clients (boto3, aws-cli v2, MinIO mc) can
--  send their own PutBucketVersioning body to it.  It creates the fixture
--  bucket, prints "LISTENING <port>", serves for the requested number of
--  seconds (argument 1 or FLYOLOGY_REPRO_SECONDS, default 60) and exits 0.  This program is not an
--  assertion; the verdict for S3-DOMAIN-A-5 comes from
--  repro_s3_domain_a_5.adb.
--
--    cd tests/repros && FLYOLOGY_REPRO_SECONDS=240 \
--      ./run.sh repro_s3_domain_a_5_live 300
--
--  Credentials are Repro_S3_Server.Access_Key / Secret_Key in us-east-1.
with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Text_IO;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_A_5_Live is
   Port    : Natural;
   Seconds : Duration := 60.0;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Seconds := Duration'Value (Ada.Command_Line.Argument (1));
   elsif Ada.Environment_Variables.Exists ("FLYOLOGY_REPRO_SECONDS") then
      Seconds := Duration'Value
        (Ada.Environment_Variables.Value ("FLYOLOGY_REPRO_SECONDS"));
   end if;
   Note ("CreateBucket /stock-versioning status " &
         Image (Status_Code
                  (Run (Signed_Request ("PUT", "/stock-versioning")))));
   Note ("CreateBucket /stock-versioning-2 status " &
         Image (Status_Code
                  (Run (Signed_Request ("PUT", "/stock-versioning-2")))));
   Note ("CreateBucket /stock-versioning-3 status " &
         Image (Status_Code
                  (Run (Signed_Request ("PUT", "/stock-versioning-3")))));
   Start_Loopback (Port);
   Ada.Text_IO.Put_Line ("LISTENING " & Image (Port));
   Ada.Text_IO.Flush;
   delay Seconds;
   Stop_Loopback;
   Ada.Text_IO.Put_Line ("STOPPED");
end Repro_S3_Domain_A_5_Live;
