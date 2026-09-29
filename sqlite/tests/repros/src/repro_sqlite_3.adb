--  BACKEND-SQLITE-3: Find_Selected_Object's exception handler runs the
--  annotation-lease release BEFORE Item.Gate.Release.  When the release
--  raises (it always does for a lease at refs=1, see BACKEND-SQLITE-2) the
--  gate is never released, so every later catalog operation on the store
--  blocks forever in the protected entry Gate.Acquire.
--
--  Trigger used here (deterministic): the Check callback Copy_Object passes
--  to Find_Selected_Object raises Data_Error because the source body file is
--  gone.  The same handler runs when that callback raises
--  Operation_Cancelled or Timeout_Error, which are the caller-reachable
--  triggers (Copy_Object of an annotated source that is cancelled or whose
--  deadline expires while it waits for the gate).
--
--  Asserts the CORRECT behaviour: after a failed Copy_Object the store still
--  answers.  A second task performs the probe with a bounded 5 s wait, and
--  the program exits 1 on the timeout instead of hanging the harness.
with Ada.Directories;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with GNAT.OS_Lib;
with Repro_Support; use Repro_Support;
with Repro_SQLite_Support; use Repro_SQLite_Support;

procedure Repro_SQLite_3 is
   use type Flyology.Object_Storage.Status;
   package OSS renames Flyology.Object_Storage;
   package OSB renames Flyology.Object_Storage.Backends;
   package SQL_Backend renames Flyology.Object_Storage.Backends.SQLite;

   Root   : constant String := Fresh_Root ("gate-leak");
   Bucket : constant String := "gate-bucket";
   Never  : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;
   Body_Text : constant String := "source body";

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

   function Sole_Blob return String is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Found  : Ada.Strings.Unbounded.Unbounded_String;
      Count  : Natural := 0;
   begin
      Ada.Directories.Start_Search
        (Search, Root & "/objects", "*.blob",
         [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Count := Count + 1;
         Found := Ada.Strings.Unbounded.To_Unbounded_String
           (Ada.Directories.Full_Name (Item));
      end loop;
      Ada.Directories.End_Search (Search);
      Check (Count = 1, "exactly one payload file before annotating");
      return Ada.Strings.Unbounded.To_String (Found);
   end Sole_Blob;

begin
   Note ("root " & Root);
   Store.Create_Bucket (Bucket, null, Never, Result);
   Check (Result = OSS.Success, "Create_Bucket succeeds");

   declare
      Source   : Buffer_Source := Source_Of (Body_Text);
      Info     : OSS.Object_Information;
      Identity : OSB.Version_Identity;
   begin
      Store.Put_Object
        (Bucket, "src", Source, OSS.Default_Put_Options, null, Never,
         Info, Identity, Result);
      Check (Result = OSS.Success, "Put_Object src succeeds");
   end;

   declare
      Body_Payload : constant String := Sole_Blob;
      Source   : Buffer_Source := Source_Of ("annotation");
      Info     : OSS.Object_Annotation_Information;
      Identity : OSB.Version_Identity;
      Options  : constant OSB.Put_Object_Annotation_Options :=
        (Expected_Checksum => <>,
         Conditions =>
           (Has_Object_ETag => False,
            Object_ETag     => Ada.Strings.Unbounded.Null_Unbounded_String));
   begin
      Store.Put_Object_Annotation
        (Bucket, "src", "note", Source, Options, null, Never,
         Info, Identity, Result);
      Check (Result = OSS.Success, "Put_Object_Annotation succeeds");

      --  Control: the store answers before the trigger.
      Store.Head_Bucket (Bucket, null, Never, Result);
      Note ("control Head_Bucket " & Image (Result));
      Check (Result = OSS.Success, "control Head_Bucket succeeds");

      --  Trigger: make Copy_Object's Check callback raise under the gate.
      Ada.Directories.Delete_File (Body_Payload);
      Note ("removed the source body payload " & Body_Payload);
   end;

   declare
      Info : OSS.Object_Information;
      Source_Identity      : OSB.Version_Identity;
      Destination_Identity : OSB.Version_Identity;
   begin
      Store.Copy_Object
        (Bucket, "src", Bucket, "dst", OSB.Default_Copy_Options, null, Never,
         Info, Source_Identity, Destination_Identity, Result);
      Note ("Copy_Object with a missing source body returned " &
            Image (Result));
   exception
      when E : others =>
         Note ("Copy_Object raised " & Ada.Exceptions.Exception_Name (E) &
               " -- " & Ada.Exceptions.Exception_Message (E));
   end;

   Note ("probing the store from a second task (bounded 5 s wait)");
   Prober.Start;
   declare
      Probe : OSS.Status;
   begin
      select
         Completion.Wait (Probe);
         Note ("probe Head_Bucket returned " & Image (Probe));
         Check (Probe = OSS.Success,
                "the store still serves Head_Bucket after a failed " &
                "Copy_Object");
         Finish;
      or
         delay 5.0;
         Note ("probe Head_Bucket did not return within 5 s: the catalog " &
               "operation gate was never released");
         Check (False,
                "the store still serves Head_Bucket after a failed " &
                "Copy_Object");
         Finish;
         Ada.Text_IO.Flush;
         GNAT.OS_Lib.OS_Exit (1);
      end select;
   end;
end Repro_SQLite_3;
