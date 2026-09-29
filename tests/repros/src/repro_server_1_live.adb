--  SERVER-1 supporting evidence: hold the loopback listener open so a stock
--  client (aws-cli v2) can be pointed at the real Ada application.  It
--  creates the fixtures, prints "LISTENING <port>", serves for the requested
--  number of seconds (argument 1, default 45) and exits 0.  This program is
--  not an assertion; the verdict for SERVER-1 comes from repro_server_1.adb.
with Ada.Command_Line;
with Ada.Text_IO;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Server_1_Live is
   Port    : Natural;
   Seconds : Duration := 45.0;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Seconds := Duration'Value (Ada.Command_Line.Argument (1));
   end if;
   Note ("CreateBucket /live-bucket status " &
         Image (Status_Code (Run (Signed_Request ("PUT", "/live-bucket")))));
   Note ("PutObject /live-bucket/modelled status " &
         Image (Status_Code
                  (Run (Signed_Request
                          ("PUT", "/live-bucket/modelled", "payload")))));
   Start_Loopback (Port);
   Ada.Text_IO.Put_Line ("LISTENING " & Image (Port));
   Ada.Text_IO.Flush;
   delay Seconds;
   Stop_Loopback;
   Ada.Text_IO.Put_Line ("STOPPED");
end Repro_Server_1_Live;
