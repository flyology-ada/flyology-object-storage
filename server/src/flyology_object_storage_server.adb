with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with Flyology.Object_Storage.Backends.SQLite;
with Flyology_Object_Storage_Server_Configuration;
with Flyology_Object_Storage_Server_Runtime;

procedure Flyology_Object_Storage_Server is
   package Configuration renames
     Flyology_Object_Storage_Server_Configuration;
   package US renames Ada.Strings.Unbounded;

   Settings : constant Configuration.Settings := Configuration.Load;
begin
   case Settings.Backend is
      when Configuration.Memory =>
         declare
            type Store_Access is access all
              Flyology.Object_Storage.Backends.Memory.Store;
            Store : constant Store_Access := new
              Flyology.Object_Storage.Backends.Memory.Store
                (Bucket_Capacity => 256,
                 Object_Capacity => 100_000,
                 Byte_Capacity   => 16 * 1_024 * 1_024 * 1_024);
            procedure Run is new Flyology_Object_Storage_Server_Runtime
              (Backend_Type => Flyology.Object_Storage.Backends.Memory.Store,
               Store        => Store.all,
               Configuration => Settings);
         begin
            Run;
         end;

      when Configuration.Files =>
         declare
            Store : Flyology.Object_Storage.Backends.Files.Store :=
              Flyology.Object_Storage.Backends.Files.Open
                (US.To_String (Settings.Storage_Root));
            procedure Run is new Flyology_Object_Storage_Server_Runtime
              (Backend_Type => Flyology.Object_Storage.Backends.Files.Store,
               Store        => Store,
               Configuration => Settings);
         begin
            Run;
         end;

      when Configuration.SQLite =>
         declare
            Store : Flyology.Object_Storage.Backends.SQLite.Store :=
              Flyology.Object_Storage.Backends.SQLite.Open
                (US.To_String (Settings.Storage_Root));
            procedure Run is new Flyology_Object_Storage_Server_Runtime
              (Backend_Type => Flyology.Object_Storage.Backends.SQLite.Store,
               Store        => Store,
               Configuration => Settings);
         begin
            Run;
         end;
   end case;
exception
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "object-storage server startup failed: " &
         Ada.Exceptions.Exception_Information (Error));
      raise;
end Flyology_Object_Storage_Server;
