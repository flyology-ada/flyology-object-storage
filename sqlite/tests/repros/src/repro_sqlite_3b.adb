--  BACKEND-SQLITE-3, caller-reachable variant: the gate leak needs no
--  filesystem tampering.  A CopyObject whose deadline expires after
--  Copy_Object's entry check but before Find_Selected_Object calls the
--  Check callback takes the same handler path: the lease release raises
--  under CHECK(refs>0) and Item.Gate.Release is skipped.
--
--  The source carries many annotations so that the lease loop takes longer
--  than the supplied deadline; the deadline is a plain caller argument, so
--  everything here is reachable through the public Backend interface.
--
--  Three outcomes per attempt distinguish the paths:
--    * Timeout_Error propagates      -> the entry Check_Context fired, no
--                                       leases were taken, harmless, retry
--                                       with a longer deadline
--    * Copy_Object returns a Status  -> the Check callback raised under the
--                                       gate: this is the defect
--    * SQLITE_ERROR propagates       -> the copy ran to completion and
--                                       BACKEND-SQLITE-2 fired instead
--
--  Asserts the CORRECT behaviour: after a CopyObject whose deadline expires,
--  the store still answers.  Bounded 5 s probe from a second task.
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with GNAT.OS_Lib;
with Repro_Support; use Repro_Support;
with Repro_SQLite_Support; use Repro_SQLite_Support;

procedure Repro_SQLite_3b is
   use type Flyology.Object_Storage.Status;
   use type Ada.Real_Time.Time;
   package OSS renames Flyology.Object_Storage;
   package OSB renames Flyology.Object_Storage.Backends;
   package SQL_Backend renames Flyology.Object_Storage.Backends.SQLite;

   Root   : constant String := Fresh_Root ("gate-leak-deadline");
   Bucket : constant String := "gate-bucket";
   Never  : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;
   Annotations : constant := 200;

   Store  : SQL_Backend.Store := SQL_Backend.Open (Root);
   Result : OSS.Status;

   protected Completion is
      procedure Signal (Value : OSS.Status);
      entry Wait (Value : out OSS.Status);
   private
      Done  : Boolean := False;
      Saved : OSS.Status := OSS.Backend_Unavailable;
   end Completion;

   protected body Completion is
      procedure Signal (Value : OSS.Status) is
      begin
         Saved := Value;
         Done := True;
      end Signal;
      entry Wait (Value : out OSS.Status) when Done is
      begin
         Value := Saved;
      end Wait;
   end Completion;

   task Prober is
      entry Start;
   end Prober;

   task body Prober is
      Probe : OSS.Status := OSS.Backend_Unavailable;
   begin
      accept Start;
      Store.Head_Bucket (Bucket, null, Never, Probe);
      Completion.Signal (Probe);
   exception
      when others =>
         Completion.Signal (OSS.Backend_Unavailable);
   end Prober;

   Engaged : Boolean := False;
   Aborted : Boolean := False;
   Entry_Timeouts : Natural := 0;
begin
   Note ("root " & Root);
   Store.Create_Bucket (Bucket, null, Never, Result);
   Check (Result = OSS.Success, "Create_Bucket succeeds");

   declare
      Source   : Buffer_Source := Source_Of ("source body");
      Info     : OSS.Object_Information;
      Identity : OSB.Version_Identity;
   begin
      Store.Put_Object
        (Bucket, "src", Source, OSS.Default_Put_Options, null, Never,
         Info, Identity, Result);
      Check (Result = OSS.Success, "Put_Object src succeeds");
   end;

   for Index in 1 .. Annotations loop
      declare
         Source   : Buffer_Source := Source_Of ("payload" & Index'Image);
         Info     : OSS.Object_Annotation_Information;
         Identity : OSB.Version_Identity;
         Options  : constant OSB.Put_Object_Annotation_Options :=
           (Expected_Checksum => <>,
            Conditions =>
              (Has_Object_ETag => False,
               Object_ETag =>
                 Ada.Strings.Unbounded.Null_Unbounded_String));
         Name : constant String :=
           "note" & Trim (Integer'Image (1_000 + Index));
      begin
         Store.Put_Object_Annotation
           (Bucket, "src", Name, Source, Options, null, Never,
            Info, Identity, Result);
         if Result /= OSS.Success then
            Check (False, "Put_Object_Annotation " & Name & " succeeds");
         end if;
      end;
   end loop;
   Note ("attached" & Annotations'Image & " annotations to src");

   Store.Head_Bucket (Bucket, null, Never, Result);
   Note ("control Head_Bucket " & Image (Result));
   Check (Result = OSS.Success, "control Head_Bucket succeeds");

   --  Scan the caller's deadline upward in microseconds.  Attempts that are
   --  too short raise Timeout_Error at Copy_Object's entry check and take no
   --  leases, so they are harmless and the scan continues.
   Entry_Timeouts := 0;
   for Step in 1 .. 400 loop
      declare
         Budget : constant Integer := Step * 3;
         Info : OSS.Object_Information;
         Source_Identity      : OSB.Version_Identity;
         Destination_Identity : OSB.Version_Identity;
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Microseconds (Budget);
      begin
         Store.Copy_Object
           (Bucket, "src", Bucket, "dst", OSB.Default_Copy_Options, null,
            Deadline, Info, Source_Identity, Destination_Identity, Result);
         Note ("CopyObject with a" & Budget'Image &
               " us deadline returned " & Image (Result) &
               " (the deadline expired inside the gate-held window)");
         Engaged := True;
      exception
         when Flyology.IO.Timeout_Error =>
            Entry_Timeouts := Entry_Timeouts + 1;
         when E : others =>
            Note ("CopyObject with a" & Budget'Image &
                  " us deadline raised " &
                  Ada.Exceptions.Exception_Name (E) & " -- " &
                  Ada.Exceptions.Exception_Message (E) &
                  " (the copy ran to completion; deadline too generous)");
            Aborted := True;
      end;
      exit when Engaged or else Aborted;
   end loop;
   Note ("attempts rejected at the entry check:" & Entry_Timeouts'Image);

   if not Engaged then
      Note ("the deadline never expired inside the gate-held window; " &
            "this route did not engage in this run");
   end if;

   Note ("probing the store from a second task (bounded 5 s wait)");
   Prober.Start;
   declare
      Probe : OSS.Status;
   begin
      select
         Completion.Wait (Probe);
         Note ("probe Head_Bucket returned " & Image (Probe));
         Check (Probe = OSS.Success,
                "the store still serves Head_Bucket after a CopyObject " &
                "whose deadline expired");
         Finish;
      or
         delay 5.0;
         Note ("probe Head_Bucket did not return within 5 s: the catalog " &
               "operation gate was never released");
         Check (False,
                "the store still serves Head_Bucket after a CopyObject " &
                "whose deadline expired");
         Finish;
         Ada.Text_IO.Flush;
         GNAT.OS_Lib.OS_Exit (1);
      end select;
   end;
end Repro_SQLite_3b;
