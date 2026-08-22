with Ada.IO_Exceptions;
with Interfaces.C;
with Interfaces.C.Strings;

package body Flyology.Object_Storage.Durability is

   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   protected Faults is
      procedure Configure (After : Natural);
      procedure Clear;
      procedure Before_Barrier;
   private
      Enabled   : Boolean := False;
      Remaining : Natural := 0;
   end Faults;

   protected body Faults is
      procedure Configure (After : Natural) is
      begin
         Enabled := True;
         Remaining := After;
      end Configure;

      procedure Clear is
      begin
         Enabled := False;
         Remaining := 0;
      end Clear;

      procedure Before_Barrier is
      begin
         if Enabled and then Remaining = 0 then
            Enabled := False;
            raise Ada.IO_Exceptions.Device_Error with
              "injected durability barrier failure";
         elsif Enabled then
            Remaining := Remaining - 1;
         end if;
      end Before_Barrier;
   end Faults;

   function Sync_File_C
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   with Import, Convention => C,
        External_Name => "flyology_object_storage_core_sync_file";

   function Sync_Directory_C
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   with Import, Convention => C,
        External_Name => "flyology_object_storage_core_sync_directory";

   procedure Sync
     (Path : String; Directory : Boolean)
   is
      package CS renames Interfaces.C.Strings;
      Value : CS.chars_ptr := CS.New_String (Path);
      Code  : Interfaces.C.int;
   begin
      Faults.Before_Barrier;
      Code :=
        (if Directory then Sync_Directory_C (Value)
         else Sync_File_C (Value));
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
      Faults.Configure (After);
   end Set_Test_Failure;

   procedure Clear_Test_Failure is
   begin
      Faults.Clear;
   end Clear_Test_Failure;

end Flyology.Object_Storage.Durability;
