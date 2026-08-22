with Ada.IO_Exceptions;
with Interfaces.C;
with Interfaces.C.Strings;

package body Flyology.Object_Storage.Durability is

   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   type Fault_Mode is (Disabled, Raise_Device_Error, Crash_Process);

   protected Faults is
      procedure Configure_Failure (After : Natural);
      procedure Configure_Crash
        (After : Natural; Moment : Barrier_Moment);
      procedure Clear;
      procedure Event
        (Moment : Barrier_Moment;
         Raise_Failure : out Boolean;
         Crash : out Boolean);
   private
      Mode      : Fault_Mode := Disabled;
      At_Moment : Barrier_Moment := Before_Barrier;
      Remaining : Natural := 0;
   end Faults;

   protected body Faults is
      procedure Configure_Failure (After : Natural) is
      begin
         Mode := Raise_Device_Error;
         At_Moment := Before_Barrier;
         Remaining := After;
      end Configure_Failure;

      procedure Configure_Crash
        (After : Natural; Moment : Barrier_Moment)
      is
      begin
         Mode := Crash_Process;
         At_Moment := Moment;
         Remaining := After;
      end Configure_Crash;

      procedure Clear is
      begin
         Mode := Disabled;
         Remaining := 0;
      end Clear;

      procedure Event
        (Moment : Barrier_Moment;
         Raise_Failure : out Boolean;
         Crash : out Boolean)
      is
      begin
         Raise_Failure := False;
         Crash := False;
         if Mode /= Disabled and then Moment = At_Moment
           and then Remaining = 0
         then
            Raise_Failure := Mode = Raise_Device_Error;
            Crash := Mode = Crash_Process;
            Mode := Disabled;
         elsif Mode /= Disabled and then Moment = At_Moment then
            Remaining := Remaining - 1;
         end if;
      end Event;
   end Faults;

   function Sync_File_C
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   with Import, Convention => C,
        External_Name => "flyology_object_storage_core_sync_file";

   function Sync_Directory_C
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   with Import, Convention => C,
        External_Name => "flyology_object_storage_core_sync_directory";

   procedure Crash_Process_C
   with Import, Convention => C,
        External_Name => "flyology_object_storage_core_crash_process";

   procedure Test_Event (Moment : Barrier_Moment) is
      Raise_Failure : Boolean;
      Crash         : Boolean;
   begin
      Faults.Event (Moment, Raise_Failure, Crash);
      if Raise_Failure then
         raise Ada.IO_Exceptions.Device_Error with
           "injected durability barrier failure";
      elsif Crash then
         Crash_Process_C;
         raise Program_Error with "crash-process hook returned";
      end if;
   end Test_Event;

   procedure Sync
     (Path : String; Directory : Boolean)
   is
      package CS renames Interfaces.C.Strings;
      Value : CS.chars_ptr := CS.New_String (Path);
      Code  : Interfaces.C.int;
   begin
      Test_Event (Before_Barrier);
      Code :=
        (if Directory then Sync_Directory_C (Value)
         else Sync_File_C (Value));
      if Code = 0 then
         Test_Event (After_Barrier);
      end if;
      CS.Free (Value);
      if Code /= 0 then
         raise Ada.IO_Exceptions.Device_Error with
           "could not make storage path durable";
      end if;
   exception
      when others =>
         if Value /= CS.Null_Ptr then
            CS.Free (Value);
         end if;
         raise;
   end Sync;

   procedure Sync_File (Path : String) is
   begin
      Sync (Path, Directory => False);
   end Sync_File;

   procedure Sync_Directory (Path : String) is
   begin
      Sync (Path, Directory => True);
   end Sync_Directory;

   procedure Set_Test_Failure (After : Natural) is
   begin
      Faults.Configure_Failure (After);
   end Set_Test_Failure;

   procedure Set_Test_Crash
     (After : Natural; Moment : Barrier_Moment)
   is
   begin
      Faults.Configure_Crash (After, Moment);
   end Set_Test_Crash;

   procedure Clear_Test_Failure is
   begin
      Faults.Clear;
   end Clear_Test_Failure;

end Flyology.Object_Storage.Durability;
