with Ada.Environment_Variables;
with Flyology.Object_Storage.Backends.Files;
with S3_Server_Harness;

procedure S3_Files_Server is
   function Root return String is
   begin
      if not Ada.Environment_Variables.Exists ("FLYOLOGY_STORAGE_ROOT") then
         raise Program_Error with
           "missing required environment: FLYOLOGY_STORAGE_ROOT";
      end if;
      return Ada.Environment_Variables.Value ("FLYOLOGY_STORAGE_ROOT");
   end Root;

   --  Benchmark policy: the comparable files series measures the production
   --  Power_Loss_Durable mode. Keep this explicit so a future Open default
   --  cannot silently change the recorded series' durability semantics.
   Store : Flyology.Object_Storage.Backends.Files.Store :=
     Flyology.Object_Storage.Backends.Files.Open
       (Root,
        Commit =>
          Flyology.Object_Storage.Backends.Files.Power_Loss_Durable);

   procedure Serve is new S3_Server_Harness
     (Backend_Type => Flyology.Object_Storage.Backends.Files.Store,
      Store        => Store);
begin
   Serve;
end S3_Files_Server;
