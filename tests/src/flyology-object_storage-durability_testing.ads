package Flyology.Object_Storage.Durability_Testing is

   function Missing_File_Is_Rejected (Path : String) return Boolean;

   procedure Fail_Next_Barrier_After (Successful_Barriers : Natural);
   procedure Crash_At_Barrier
     (Barrier : Natural; After_Sync : Boolean);
   procedure Clear_Failure;

end Flyology.Object_Storage.Durability_Testing;
