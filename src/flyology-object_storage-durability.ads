private package Flyology.Object_Storage.Durability is

   --  Make prior writes to one ordinary file stable according to the host
   --  filesystem. Device_Error is raised when the host cannot guarantee it.
   procedure Sync_File (Path : String);

   --  Make prior directory-entry changes stable according to the host
   --  filesystem. Device_Error is raised when the host cannot guarantee it.
   procedure Sync_Directory (Path : String);

   --  Internal deterministic fault injection used by descendant test units.
   --  After successful barriers have passed, the next barrier raises
   --  Device_Error. Clear_Test_Failure disables injection.
   procedure Set_Test_Failure (After : Natural);
   procedure Clear_Test_Failure;

end Flyology.Object_Storage.Durability;
