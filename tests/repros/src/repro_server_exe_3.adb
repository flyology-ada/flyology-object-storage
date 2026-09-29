--  SERVER-EXE-3: the server executable hands any FLYOLOGY_OBJECT_STORAGE_ROOT
--  straight to Files.Open (flyology_object_storage_server.adb:64-68), and
--  Files.Open recursively deletes a pre-existing <root>/tmp tree
--  (flyology-object_storage-backends-files.adb:3548-3564) after checking only
--  that it is a non-symlink directory whose contents contain no symlink or
--  special file.  No layout marker distinguishes a real store root from an
--  arbitrary directory, so a mistyped or shared root loses unrelated data.
--
--  Correct behaviour asserted here:
--    A. Open on a directory that is plainly not a store either refuses it
--       (Configuration_Error) or leaves its existing content alone; the
--       sentinel file <root>/tmp/keep.txt must still exist afterwards.
--    B. the same for a nested file below <root>/tmp/.
--  Controls (must pass on the current sources): a dedicated empty root opens
--  and accepts a bucket, and a sibling directory the store does not use
--  (<root>/notes/) is left untouched -- so the deletion above is a targeted
--  sweep of tmp/, not a wholesale wipe, and this harness observes the
--  filesystem correctly.
with Ada.Calendar;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends.Files;
with Repro_Support; use Repro_Support;

procedure Repro_Server_Exe_3 is
   package Storage renames Flyology.Object_Storage;
   package Files renames Flyology.Object_Storage.Backends.Files;
   use type Storage.Status;

   Scratch : constant String := "/private/tmp/claude-501";
   Forever : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   function Under (Base, First, Second : String) return String is
     (Ada.Directories.Compose (Ada.Directories.Compose (Base, First), Second));

   function Make_Root (Label : String) return String is
      Stamp : String := Ada.Strings.Fixed.Trim
        (Duration'Image (Ada.Calendar.Seconds (Ada.Calendar.Clock)),
         Ada.Strings.Both);
   begin
      for Index in Stamp'Range loop
         if Stamp (Index) not in '0' .. '9' then
            Stamp (Index) := '-';
         end if;
      end loop;
      return Path : constant String :=
        Ada.Directories.Compose (Scratch, "repro-" & Label & "-" & Stamp)
      do
         Ada.Directories.Create_Path (Path);
      end return;
   end Make_Root;

   procedure Drop_Root (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Tree (Path);
      end if;
   exception
      when others =>
         null;
   end Drop_Root;

   procedure Write_File (Path, Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Directories.Create_Path
        (Ada.Directories.Containing_Directory (Path));
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Text);
      Ada.Text_IO.Close (File);
   end Write_File;

   --  A directory an operator might name by mistake: it is not a store, but
   --  it happens to contain a tmp/ child, like /var, a home directory, or a
   --  checkout with a scratch area.
   Foreign   : constant String := Make_Root ("server-exe-3-foreign");
   Keep      : constant String := Under (Foreign, "tmp", "keep.txt");
   Deep      : constant String :=
     Under (Ada.Directories.Compose (Foreign, "tmp"), "nested", "deep.txt");
   Untouched : constant String := Under (Foreign, "notes", "readme.txt");
   Refused   : Boolean := False;
begin
   Write_File (Keep, "keep-me: unrelated operator data");
   Write_File (Deep, "keep-me: unrelated operator data, one level down");
   Write_File (Untouched, "unrelated notes outside the store layout");
   Note ("foreign root = " & Foreign);
   Note ("  before: tmp/keep.txt exists        = " &
         Boolean'Image (Ada.Directories.Exists (Keep)));
   Note ("  before: tmp/nested/deep.txt exists = " &
         Boolean'Image (Ada.Directories.Exists (Deep)));
   Note ("  before: notes/readme.txt exists    = " &
         Boolean'Image (Ada.Directories.Exists (Untouched)));

   --  Control first: a dedicated, empty root is what the documented
   --  configuration expects, and it must work.
   declare
      Dedicated : constant String := Make_Root ("server-exe-3-dedicated");
   begin
      declare
         Store  : Files.Store := Files.Open (Dedicated);
         Result : Storage.Status;
      begin
         Store.Create_Bucket ("control-bucket", null, Forever, Result);
         Note ("control: dedicated empty root " & Dedicated);
         Note ("  Create_Bucket status = " & Storage.Status'Image (Result));
         Check (Result = Storage.Success,
                "control: a dedicated empty root opens and accepts a bucket");
      end;
      Drop_Root (Dedicated);
   exception
      when Error : others =>
         Note ("control raised " & Ada.Exceptions.Exception_Name (Error));
         Check (False,
                "control: a dedicated empty root opens and accepts a bucket");
   end;

   --  The finding: Open the foreign directory the way the executable does.
   begin
      declare
         Store : Files.Store := Files.Open (Foreign);
         pragma Unreferenced (Store);
      begin
         Note ("Files.Open (foreign root) returned normally");
      end;
   exception
      when Error : Files.Configuration_Error =>
         Refused := True;
         Note ("Files.Open (foreign root) raised " &
               Ada.Exceptions.Exception_Name (Error) &
               " -- the root was refused");
      when Error : others =>
         Note ("Files.Open (foreign root) raised " &
               Ada.Exceptions.Exception_Name (Error) &
               " -- not a refusal of the layout");
   end;

   Note ("  after:  tmp/keep.txt exists        = " &
         Boolean'Image (Ada.Directories.Exists (Keep)));
   Note ("  after:  tmp/nested/deep.txt exists = " &
         Boolean'Image (Ada.Directories.Exists (Deep)));
   Note ("  after:  notes/readme.txt exists    = " &
         Boolean'Image (Ada.Directories.Exists (Untouched)));
   Note ("  Open refused the root (Configuration_Error) = " &
         Boolean'Image (Refused));

   Check (Refused or else Ada.Directories.Exists (Keep),
          "Files.Open either refuses a root that is not a store or leaves " &
          "<root>/tmp/keep.txt in place");
   Check (Refused or else Ada.Directories.Exists (Deep),
          "Files.Open either refuses a root that is not a store or leaves " &
          "<root>/tmp/nested/deep.txt in place");
   Check (Ada.Directories.Exists (Untouched),
          "control: a sibling directory the store does not use survives");

   Drop_Root (Foreign);
   Finish;
end Repro_Server_Exe_3;
