with Ada.Environment_Variables;
with Flyology.Object_Storage.Backends.SQLite;
with S3_Server_Harness;

procedure S3_SQLite_Server is
   function Root return String is
   begin
      if not Ada.Environment_Variables.Exists ("FLYOLOGY_STORAGE_ROOT") then
         raise Program_Error with
           "missing required environment: FLYOLOGY_STORAGE_ROOT";
      end if;
      return Ada.Environment_Variables.Value ("FLYOLOGY_STORAGE_ROOT");
   end Root;

   Store : Flyology.Object_Storage.Backends.SQLite.Store :=
     Flyology.Object_Storage.Backends.SQLite.Open (Root);

   procedure Serve is new S3_Server_Harness
     (Backend_Type => Flyology.Object_Storage.Backends.SQLite.Store,
      Store        => Store);
begin
   Serve;
end S3_SQLite_Server;
