with Ada.IO_Exceptions;

package body Flyology.Object_Storage.Backends.Files.Testing is

   function Rejects_Temp_Target
     (Item : Store; Path : String) return Boolean is
   begin
      Validate_New_Temp_Target (Item, Path);
      return False;
   exception
      when Ada.IO_Exceptions.Data_Error =>
         return True;
   end Rejects_Temp_Target;

end Flyology.Object_Storage.Backends.Files.Testing;
