with Flyology.Object_Storage.Backends;

--  Run one backend through a bounded loopback HTTP/1.1 S3 listener. This is a
--  qualification adapter, not deployment configuration: credentials come
--  from AWS_* environment variables and the process is externally supervised.
generic
   type Backend_Type (<>) is limited new
     Flyology.Object_Storage.Backends.Backend with private;
   Store : in out Backend_Type;
procedure S3_Server_Harness;
