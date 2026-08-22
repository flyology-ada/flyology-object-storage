with Ada.Real_Time;

package body Object_Tagging_Race_Conformance is

   procedure Exercise
     (Store         : aliased in out
        Flyology.Object_Storage.Backends.Backend'Class;
      Bucket        : String;
      Key           : String;
      Expected_Tags : Flyology.Object_Storage.Object_Tag_Set;
      Iterations    : Positive := 32)
   is
      use type Flyology.Object_Storage.Status;
      use type Flyology.Object_Storage.Object_Tag_Set;

      protected Control is
         procedure Arrive;
         entry Start;
         procedure Record_Failure;
         function Failures return Natural;
      private
         Ready : Natural range 0 .. 3 := 0;
         Failed : Natural := 0;
      end Control;

      protected body Control is
         procedure Arrive is
         begin
            Ready := Ready + 1;
         end Arrive;

         entry Start when Ready = 3 is
         begin
            null;
         end Start;

         procedure Record_Failure is
         begin
            Failed := Failed + 1;
         end Record_Failure;

         function Failures return Natural is (Failed);
      end Control;

      task type Put_Worker;
      task type Delete_Worker;
      task type Read_Worker;

      task body Put_Worker is
         Result : Flyology.Object_Storage.Status;
      begin
         Control.Arrive;
         Control.Start;
         for Iteration in 1 .. Iterations loop
            pragma Unreferenced (Iteration);
            Store.Put_Object_Tags
              (Bucket, Key, Expected_Tags, null, Ada.Real_Time.Time_Last,
               Result);
            if Result /= Flyology.Object_Storage.Success then
               Control.Record_Failure;
               exit;
            end if;
         end loop;
      exception
         when others =>
            Control.Record_Failure;
      end Put_Worker;

      task body Delete_Worker is
         Result : Flyology.Object_Storage.Status;
      begin
         Control.Arrive;
         Control.Start;
         for Iteration in 1 .. Iterations loop
            pragma Unreferenced (Iteration);
            Store.Delete_Object_Tags
              (Bucket, Key, null, Ada.Real_Time.Time_Last, Result);
            if Result /= Flyology.Object_Storage.Success then
               Control.Record_Failure;
               exit;
            end if;
         end loop;
      exception
         when others =>
            Control.Record_Failure;
      end Delete_Worker;

      task body Read_Worker is
         Observed : Flyology.Object_Storage.Object_Tag_Set;
         Result   : Flyology.Object_Storage.Status;
      begin
         Control.Arrive;
         Control.Start;
         for Pass in 1 .. 2 loop
            pragma Unreferenced (Pass);
            for Iteration in 1 .. Iterations loop
               pragma Unreferenced (Iteration);
               Store.Get_Object_Tags
                 (Bucket, Key, null, Ada.Real_Time.Time_Last,
                  Observed, Result);
               if Result /= Flyology.Object_Storage.Success
                 or else
                   (Observed.Length /= 0 and then Observed /= Expected_Tags)
               then
                  Control.Record_Failure;
                  exit;
               end if;
            end loop;
         end loop;
      exception
         when others =>
            Control.Record_Failure;
      end Read_Worker;

      Result   : Flyology.Object_Storage.Status;
      Observed : Flyology.Object_Storage.Object_Tag_Set;
   begin
      declare
         Put_Task    : Put_Worker;
         Delete_Task : Delete_Worker;
         Read_Task   : Read_Worker;
         pragma Unreferenced (Put_Task, Delete_Task, Read_Task);
      begin
         null;
      end;
      Store.Get_Object_Tags
        (Bucket, Key, null, Ada.Real_Time.Time_Last, Observed, Result);
      if Control.Failures /= 0
        or else Result /= Flyology.Object_Storage.Success
        or else (Observed.Length /= 0 and then Observed /= Expected_Tags)
      then
         raise Program_Error with
           "concurrent object-tag put/delete/read exposed a torn snapshot";
      end if;
   end Exercise;

end Object_Tagging_Race_Conformance;
