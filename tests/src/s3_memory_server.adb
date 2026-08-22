with Flyology.Object_Storage.Backends.Memory;
with S3_Server_Harness;

procedure S3_Memory_Server is
   type Store_Access is access all
     Flyology.Object_Storage.Backends.Memory.Store;
   Store : constant Store_Access := new
     Flyology.Object_Storage.Backends.Memory.Store
       (Bucket_Capacity => 256,
        Object_Capacity => 100_000,
        Byte_Capacity   => 16 * 1_024 * 1_024 * 1_024);

   procedure Serve is new S3_Server_Harness
     (Backend_Type => Flyology.Object_Storage.Backends.Memory.Store,
      Store        => Store.all);
begin
   Serve;
end S3_Memory_Server;
