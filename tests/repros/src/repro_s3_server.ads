with Flyology.Object_Storage.Backends.Memory;
with Flyology.Object_Storage.S3.SigV4;

--  An in-process S3 application over the memory backend, for reproduction
--  programs.  Three ways to drive it:
--
--  1. Run (Raw_Request): one HTTP/1.1 exchange through the application with
--     no socket (mirrors tests/src/s3_server_application_corpus.adb).  The
--     request must be a complete raw HTTP/1.1 message; use Signed_Request to
--     build a SigV4-signed one.
--  2. Start_Loopback / Exchange_Over_Socket / Stop_Loopback: the same
--     application behind a real loopback listener, for programs that need
--     real sockets, keep-alive, pipelining, or a stock client driven from a
--     shell.
--  3. Store: the memory backend itself, for programs that mix backend calls
--     with server exchanges.
package Repro_S3_Server is

   package SigV4 renames Flyology.Object_Storage.S3.SigV4;

   Access_Key : constant String := "AKIDEXAMPLE";
   Secret_Key : constant String := "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
   Region     : constant String := "us-east-1";
   Host       : constant String := "127.0.0.1";
   Principal  : constant String := "repro-principal";

   Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 64,
      Object_Capacity => 20_000,
      Byte_Capacity   => 512 * 1_024 * 1_024);

   No_Query : constant SigV4.Name_Value_Array (1 .. 0) := [];

   function Timestamp return String;
   --  Current UTC time as a SigV4 basic timestamp (YYYYMMDDTHHMMSSZ).

   function Signed_Request
     (Method          : String;
      Path            : String;
      Payload         : String := "";
      Extra_Headers   : String := "";
      Query           : SigV4.Name_Value_Array := No_Query;
      Hash_Override   : String := "";
      Chunked         : Boolean := False;
      Host_Value      : String := Host;
      Timestamp_Value : String := "";
      Keep_Alive      : Boolean := False;
      Signing_Path    : String := "") return String;
   --  Build one complete SigV4-signed HTTP/1.1 request.  Path is the raw
   --  request path (already percent-encoded as it should appear on the
   --  wire).  When Path contains percent escapes, pass the decoded form in
   --  Signing_Path: the server decodes the wire path and re-encodes it for
   --  the canonical request, so the signature must be computed over the
   --  decoded path (SigV4.Sign encodes what it is given).  Query pairs are appended verbatim as name=value in the given
   --  order and signed through SigV4.Sign, so pass values that need no
   --  encoding, or pre-encode them and expect the signature to reflect the
   --  library's canonicalization of the raw text.  Extra_Headers is zero or
   --  more "Name: value" lines each terminated by CRLF; every one is signed.
   --  Hash_Override replaces the computed payload hash (for
   --  UNSIGNED-PAYLOAD or a deliberately wrong hash).  Chunked sends the
   --  payload as one HTTP chunk.  Keep_Alive omits "Connection: close".

   function Run (Raw_Request : String) return String;
   --  One in-process exchange; returns the raw HTTP/1.1 response bytes.

   procedure Start_Loopback (Port : out Natural);
   --  Start the loopback listener in a background task; may be called once.

   procedure Stop_Loopback;

   function Exchange_Over_Socket
     (Port        : Natural;
      Raw_Request : String;
      Timeout     : Duration := 10.0) return String;
   --  Connect, send the raw request, read until the peer closes or the
   --  timeout elapses, and return everything received.

end Repro_S3_Server;
