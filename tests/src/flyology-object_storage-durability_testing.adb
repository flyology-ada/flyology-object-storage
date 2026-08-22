with Ada.IO_Exceptions;
with Flyology.Object_Storage.Durability;

package body Flyology.Object_Storage.Durability_Testing is

   function Missing_File_Is_Rejected (Path : String) return Boolean is
   begin
      Flyology.Object_Storage.Durability.Sync_File (Path);
      return False;
   exception
      when Ada.IO_Exceptions.Device_Error =>
         return True;
   end Missing_File_Is_Rejected;

   procedure Fail_Next_Barrier_After (Successful_Barriers : Natural) is
   begin
      Flyology.Object_Storage.Durability.Set_Test_Failure
        (Successful_Barriers);
   end Fail_Next_Barrier_After;

   procedure Crash_At_Barrier
     (Barrier : Natural; After_Sync : Boolean)
   is
      use Flyology.Object_Storage.Durability;
   begin
      Set_Test_Crash
        (Barrier,
         (if After_Sync then After_Barrier else Before_Barrier));
   end Crash_At_Barrier;

   procedure Clear_Failure is
   begin
      Flyology.Object_Storage.Durability.Clear_Test_Failure;
   end Clear_Failure;

end Flyology.Object_Storage.Durability_Testing;
