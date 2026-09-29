--  A minimal scripted loopback HTTP/1.1 origin for the CLIENT-BUCKETS
--  reproduction programs.  Same pattern as Repro_Client_Objects_Fake, kept
--  as a separate unit so the two areas cannot disturb each other.
--
--  The in-process S3 application cannot serve these fixtures: it answers a
--  rejected credential with 403 SignatureDoesNotMatch
--  (src/flyology-object_storage-server-s3_applications.adb:1906-1909) and
--  never with the AWS/MinIO 403 InvalidAccessKeyId, and it never emits a 301
--  with x-amz-bucket-region.  This package answers with exactly the canned
--  bytes the program scripts, so the client sees the wire shape recorded
--  from the pinned MinIO release.
--
--  Usage: Script one raw HTTP/1.1 response per expected exchange, in order,
--  then Start, drive the client, then Stop.  Each response should carry
--  "Connection: close" so one exchange uses one connection.
package Repro_Client_Buckets_Fake is

   procedure Script (Response : String);
   --  Append one canned raw HTTP/1.1 response; responses are served in the
   --  order they were scripted.

   procedure Start (Port : out Natural);
   --  Bind a loopback listener on an ephemeral port and serve in a task.

   procedure Stop;
   --  Ask the listener task to stop after the current accept.

   function Served return Natural;
   --  Number of complete request heads received so far.

   function Request_Head (Index : Positive) return String;
   --  The recorded request head (request line and headers) of exchange Index.

   function Request_Line (Index : Positive) return String;
   --  The recorded request line only, without CRLF.

   function Server_Error return String;
   --  A diagnostic from the listener task, or "" when it never failed.

end Repro_Client_Buckets_Fake;
