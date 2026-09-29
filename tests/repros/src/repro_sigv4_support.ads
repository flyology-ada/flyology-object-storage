with Flyology.Object_Storage.Backends.Memory;

--  Helper for the SIGV4 verification programs: two further in-process S3
--  applications over their own memory backends, identical to
--  Repro_S3_Server's except for the principal reported by the static
--  credential provider.  Both use Repro_S3_Server.Access_Key and
--  Repro_S3_Server.Secret_Key, so Repro_S3_Server.Signed_Request produces
--  requests that verify against them.
package Repro_SigV4_Support is

   Short_Principal : constant String (1 .. 200) := (others => 'p');
   --  Inside Authentication.Valid_Principal's 256-byte bound.

   Long_Principal : constant String (1 .. 300) := (others => 'p');
   --  Outside that bound but inside Static_Credentials'
   --  Maximum_Principal_Bytes (1_024).

   Short_Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 8,
      Object_Capacity => 64,
      Byte_Capacity   => 1_024 * 1_024);

   Long_Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 8,
      Object_Capacity => 64,
      Byte_Capacity   => 1_024 * 1_024);

   function Run_Short (Raw_Request : String) return String;
   --  One in-process exchange against the application whose provider
   --  reports a 200-byte principal.

   function Run_Long (Raw_Request : String) return String;
   --  One in-process exchange against the application whose provider
   --  reports a 300-byte principal.

end Repro_SigV4_Support;
