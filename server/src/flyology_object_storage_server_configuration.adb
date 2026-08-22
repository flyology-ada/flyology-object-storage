with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Flyology_Object_Storage_Server_Configuration is

   function Environment
     (Name : String; Default : String := "") return String
   is
     (if Ada.Environment_Variables.Exists (Name)
      then Ada.Environment_Variables.Value (Name)
      else Default);

   function Image (Value : Backend_Kind) return String is
     (case Value is
         when Memory => "memory",
         when Files  => "files",
         when SQLite => "sqlite");

   function Load return Settings is
      Backend_Name : constant String :=
        Ada.Characters.Handling.To_Lower
          (Environment ("FLYOLOGY_OBJECT_STORAGE_BACKEND", "files"));
      Root : constant String :=
        Environment ("FLYOLOGY_OBJECT_STORAGE_ROOT");
      Address : constant String :=
        Environment ("FLYOLOGY_S3_BIND", "127.0.0.1");
      Result : Settings;
   begin
      if Backend_Name = "memory" then
         Result.Backend := Memory;
      elsif Backend_Name = "files" then
         Result.Backend := Files;
      elsif Backend_Name = "sqlite" then
         Result.Backend := SQLite;
      else
         raise Constraint_Error with
           "FLYOLOGY_OBJECT_STORAGE_BACKEND must be memory, files, or sqlite";
      end if;

      if Result.Backend /= Memory and then Root'Length = 0 then
         raise Constraint_Error with
           "FLYOLOGY_OBJECT_STORAGE_ROOT is required for " & Backend_Name;
      end if;
      Result.Storage_Root := To_Unbounded_String (Root);

      if not Flyology.IO.Sockets.Is_IP_Address
        (Address, Flyology.IO.Sockets.IPv4)
      then
         raise Constraint_Error with
           "FLYOLOGY_S3_BIND must be a numeric IPv4 address";
      end if;
      Result.S3_Address := Flyology.IO.Sockets.Parse_IP_Address (Address);
      Result.S3_Port := Flyology.IO.Sockets.Port'Value
        (Environment ("FLYOLOGY_S3_PORT", "9000"));
      Result.Capacity := Server_Capacity'Value
        (Environment ("FLYOLOGY_S3_CAPACITY", "128"));
      return Result;
   exception
      when Constraint_Error =>
         raise;
      when others =>
         raise Constraint_Error with "invalid object-storage server settings";
   end Load;

end Flyology_Object_Storage_Server_Configuration;
