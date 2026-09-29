--  A minimal scripted loopback HTTP/1.1 origin for the CLIENT-OBJECTS
--  reproduction programs.
--
--  The in-process S3 application cannot show these findings: it always emits
--  "x-amz-version-id: null" on HeadObject when the request carried a version
--  selector (src/flyology-object_storage-server-s3_applications.adb:4188)
--  and on GetObject and every tagging route.  A never-versioned bucket on a
--  real server (MinIO, RustFS, SeaweedFS, AWS) omits that header entirely.
--  This package answers with exactly the canned bytes the program scripts,
--  so the client sees the real-server response shape.
--
--  Usage: Script one raw HTTP/1.1 response per expected exchange, in order,
--  then Start, drive the client, then Stop.  Each response should carry
--  "Connection: close" so one exchange uses one connection.
package Repro_Client_Objects_Fake is

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

end Repro_Client_Objects_Fake;
