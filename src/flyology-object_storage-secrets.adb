with Interfaces.C;

package body Flyology.Object_Storage.Secrets is

   procedure Secure_Erase
     (Address : System.Address;
      Bytes   : Interfaces.C.size_t)
   with Import,
        Convention    => C,
        External_Name => "flyology_object_storage_secure_erase";

   procedure Wipe (Value : in out String) is
   begin
      if Value'Length > 0 then
         Secure_Erase (Value'Address, Interfaces.C.size_t (Value'Length));
      end if;
   end Wipe;

   procedure Wipe (Address : System.Address; Bytes : Natural) is
   begin
      if Bytes > 0 then
         Secure_Erase (Address, Interfaces.C.size_t (Bytes));
      end if;
   end Wipe;

end Flyology.Object_Storage.Secrets;
