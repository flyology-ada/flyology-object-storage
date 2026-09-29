--  BACKEND-FILES-3: the files backend's singleton bucket-configuration
--  readers (policy, CORS, encryption, ownership controls, lifecycle,
--  logging, notification) rebuild the whole persisted document in a
--  stack-allocated local through Read_String
--  (src/flyology-object_storage-backends-files.adb:1579-1608,
--  :1780-1796), while the writers stream it in 64 KiB chunks and the
--  admission bound is 16 MiB (backends.ads:2792).  A document larger than
--  the reading task's stack therefore cannot be read back after it has been
--  acknowledged.
--
--  A GNAT task with no Storage_Size aspect gets 2 MiB (Default_Stack_Size,
--  toolchain s-parame.adb, GNAT 16.1.0), and the Flyology HTTP worker task
--  declares no Storage_Size (flyology 0.1.1
--  src/flyology-io-structured_servers.adb:386-391), so every server worker
--  reads with a 2 MiB stack.  This program uses a 3 MiB document: it fits
--  the environment task's 8 MiB process stack (the control read below
--  succeeds) but not a default task stack.
--
--  Correct behaviour asserted: GetBucketPolicy returns the acknowledged
--  document from a default-Storage_Size task.  Controls: the same read from
--  the environment task, the same round trip on the memory backend, and the
--  identical child-process read of a 1 MiB policy that fits the task stack.
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with GNAT.OS_Lib;
with Repro_Backend_Files_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Files_3 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Memory renames Flyology.Object_Storage.Backends.Memory;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Files_Support;
   use type Storage.Status;

   Small_Bucket : constant String := "small-policy-bucket";
   Large_Bucket : constant String := "large-policy-bucket";
   Forever      : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;
   Small_Size   : constant Positive := 1 * 1024 * 1024;
   Large_Size   : constant Positive := 3 * 1024 * 1024;

   --  Child mode: open the store on Root and read Bucket's policy from a
   --  task with the GNAT default Storage_Size.  Exit 0 only when the
   --  acknowledged document comes back whole.
   procedure Run_Worker_Child
     (Root : String; Bucket : String; Expected : Natural)
   is
      Subject       : Files.Store := Files.Open (Root);
      Worker_Result : Storage.Status := Storage.Success;
      Worker_Length : Natural := 0;
      Worker_Note   : US.Unbounded_String;
   begin
      declare
         task Worker;

         task body Worker is
            Policy     : US.Unbounded_String;
            Configured : Boolean;
         begin
            Subject.Get_Bucket_Policy
              (Bucket, null, Forever, Policy, Configured, Worker_Result);
            Worker_Length := US.Length (Policy);
         exception
            when Error : others =>
               Worker_Note := US.To_Unbounded_String
                 (Ada.Exceptions.Exception_Name (Error));
         end Worker;
      begin
         null;
      end;
      Ada.Text_IO.Put_Line
        ("  -- [child] " & Bucket & " GetBucketPolicy from a "
         & "default-Storage_Size task -> " & Worker_Result'Image & " length"
         & Natural'Image (Worker_Length)
         & (if US.Length (Worker_Note) > 0
            then " exception " & US.To_String (Worker_Note) else ""));
      if Worker_Result = Storage.Success and then Worker_Length = Expected
      then
         Ada.Command_Line.Set_Exit_Status (0);
      else
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
   end Run_Worker_Child;

   function Child_Status (Root, Bucket : String; Expected : Positive)
     return Integer
   is
      Self : constant String := GNAT.OS_Lib.Normalize_Pathname
        (Ada.Command_Line.Command_Name);
      Command : constant String :=
        "'" & Self & "' worker '" & Root & "' " & Bucket & " "
        & Image (Expected) & "; s=$?; "
        & "echo ""  -- [sh] child for " & Bucket
        & " terminated with status $s (128+n means signal n)""; exit $s";
      Arguments : constant GNAT.OS_Lib.Argument_List :=
        [new String'("-c"), new String'(Command)];
   begin
      return GNAT.OS_Lib.Spawn ("/bin/sh", Arguments);
   end Child_Status;

   type Document_Access is access String;

   function New_Document (Size : Positive) return Document_Access is
      Result : constant Document_Access := new String (1 .. Size);
   begin
      Result.all := [others => 'p'];
      return Result;
   end New_Document;

   Root   : constant String := Support.Make_Root ("bf3");
   Result : Storage.Status;
begin
   if Ada.Command_Line.Argument_Count = 4
     and then Ada.Command_Line.Argument (1) = "worker"
   then
      Run_Worker_Child
        (Ada.Command_Line.Argument (2), Ada.Command_Line.Argument (3),
         Natural'Value (Ada.Command_Line.Argument (4)));
      return;
   end if;

   Note ("files root " & Root);
   Note ("documents:" & Natural'Image (Small_Size) & " bytes and"
         & Natural'Image (Large_Size) & " bytes; documented admission bound "
         & "is 16 MiB (backends.ads:2792); GNAT default task stack is 2 MiB");

   declare
      Document : constant Document_Access := New_Document (Large_Size);
      Control : Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 64 * 1024 * 1024);
      Policy     : US.Unbounded_String;
      Configured : Boolean;
   begin
      Control.Create_Bucket (Large_Bucket, null, Forever, Result);
      Check (Result = Storage.Success, "memory (control) CreateBucket");
      Control.Put_Bucket_Policy
        (Large_Bucket, Document.all, null, Forever, Result);
      Check (Result = Storage.Success,
             "memory (control) PutBucketPolicy accepts 3 MiB");
      Control.Get_Bucket_Policy
        (Large_Bucket, null, Forever, Policy, Configured, Result);
      Note ("memory (control) GetBucketPolicy -> " & Result'Image
            & " length" & Natural'Image (US.Length (Policy)));
      Check (Result = Storage.Success
             and then US.Length (Policy) = Large_Size,
             "memory (control) round-trips the 3 MiB policy");
   end;

   declare
      Subject : Files.Store := Files.Open (Root);

      procedure Store_Policy (Bucket : String; Size : Positive) is
         Document   : constant Document_Access := New_Document (Size);
         Policy     : US.Unbounded_String;
         Configured : Boolean;
      begin
         Subject.Create_Bucket (Bucket, null, Forever, Result);
         Check (Result = Storage.Success,
                "files  (subject) CreateBucket " & Bucket);
         Subject.Put_Bucket_Policy
           (Bucket, Document.all, null, Forever, Result);
         Note ("files  (subject) PutBucketPolicy(" & Bucket & ","
               & Natural'Image (Size) & " bytes) -> " & Result'Image);
         Check (Result = Storage.Success,
                "files  (subject) PutBucketPolicy acknowledges " & Bucket);
         Subject.Get_Bucket_Policy
           (Bucket, null, Forever, Policy, Configured, Result);
         Note ("files  (subject) GetBucketPolicy(" & Bucket
               & ") from the environment task -> " & Result'Image
               & " length" & Natural'Image (US.Length (Policy)));
         Check (Result = Storage.Success and then US.Length (Policy) = Size,
                "files  (subject) the environment task reads " & Bucket
                & " back (the bytes are on disk and intact)");
      end Store_Policy;
   begin
      Store_Policy (Small_Bucket, Small_Size);
      Store_Policy (Large_Bucket, Large_Size);
   end;

   --  The same read from a task with the GNAT default stack (2 MiB), which
   --  is what a Flyology HTTP worker gets.  It runs in a child process
   --  because the outcome is not always a recoverable Ada exception.
   declare
      Small : constant Integer :=
        Child_Status (Root, Small_Bucket, Small_Size);
      Large : constant Integer :=
        Child_Status (Root, Large_Bucket, Large_Size);
   begin
      Note ("files  (subject) child status for the 1 MiB policy"
            & Integer'Image (Small));
      Check (Small = 0,
             "files  (subject) a default-stack task reads a 1 MiB policy "
             & "back (child-process control)");
      Note ("files  (subject) child status for the 3 MiB policy"
            & Integer'Image (Large));
      Check (Large = 0,
             "files  (subject) a default-stack task reads the acknowledged "
             & "3 MiB policy back");
   end;

   if Failures = 0 then
      Support.Drop_Root (Root);
   else
      Note ("files root retained for inspection: " & Root);
   end if;
   Finish;
end Repro_Backend_Files_3;
