with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with GNAT.OS_Lib;
with Object_Storage_Test_Cases;

procedure Flyology_Object_Storage_Tests is
   use type AUnit.Status;

   function Run is new AUnit.Run.Test_Runner_With_Status
     (Object_Storage_Test_Cases.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   Reporter.Set_Use_ANSI_Colors (True);
   if Run
       (Reporter,
        (Global_Timer     => True,
         Test_Case_Timer  => True,
         Report_Successes => True,
         others           => <>)) /= AUnit.Success
   then
      GNAT.OS_Lib.OS_Exit (1);
   end if;
end Flyology_Object_Storage_Tests;
