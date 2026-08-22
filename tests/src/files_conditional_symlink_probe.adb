with Ada.Command_Line;
with Ada.Directories;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Interfaces.C;
with Interfaces.C.Strings;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;

procedure Files_Conditional_Symlink_Probe is
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type C.int;
   use type Storage.Status;

   function Symlink
     (Target, Link_Path : CS.chars_ptr) return C.int
     with Import, Convention => C, External_Name => "symlink";

   type Buffer_Source is new Backends.Byte_Source with record
      Data     : Flyology.Bytes.Unbounded_Bytes;
      Position : Natural := 0;
   end record;

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Buffer_Source) return Backends.Source_Length is
     (Kind => Backends.Known,
      Bytes => Storage.Byte_Count (Flyology.Bytes.Length (Item.Data)));

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Remaining : constant Natural :=
        Flyology.Bytes.Length (Item.Data) - Item.Position;
      Count : constant Natural := Natural'Min (Remaining, Data'Length);
   begin
      if Count > 0 then
         for Offset in 0 .. Count - 1 loop
            Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
              Flyology.Bytes.Element (Item.Data, Item.Position + Offset + 1);
         end loop;
      end if;
      Item.Position := Item.Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Finished := Item.Position = Flyology.Bytes.Length (Item.Data);
   end Read;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   Root : constant String := Ada.Command_Line.Argument (1);
   Mode : constant String := Ada.Command_Line.Argument (2);
   Outside : constant String := Ada.Directories.Compose (Root, "outside");
   Sentinel : constant String := Ada.Directories.Compose (Outside, "sentinel");
   Missing : constant String := Ada.Directories.Compose (Outside, "missing");
   Link_Path : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Compose (Root, "buckets"), "symlink-bucket"),
           "objects"),
        "6C696E6B.fos");
   Link_Target : constant String :=
     (if Mode = "live" then Sentinel else Missing);
   Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
   Result : Storage.Status;
   Info   : Storage.Object_Information;
   Source : Buffer_Source :=
     (Data => Flyology.Bytes.From_Byte_String ("replacement"), Position => 0);
   Conditions : Storage.Write_Conditions := Storage.Default_Write_Conditions;
begin
   Require (Mode in "live" | "dangling", "invalid probe mode");
   Store.Create_Bucket
     ("symlink-bucket", null, Ada.Real_Time.Time_Last, Result);
   Require (Result = Storage.Success, "could not create probe bucket");
   Ada.Directories.Create_Path (Outside);
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Sentinel);
         Ada.Text_IO.Put_Line (File, "outside-sentinel");
         Ada.Text_IO.Close (File);
      end;
   end if;
   declare
      Target_C : CS.chars_ptr := CS.New_String (Link_Target);
      Link_C   : CS.chars_ptr := CS.New_String (Link_Path);
      Code     : C.int;
   begin
      Code := Symlink (Target_C, Link_C);
      CS.Free (Target_C);
      CS.Free (Link_C);
      Require (Code = 0, "could not create object-path symlink");
   end;
   Conditions.If_None_Match := US.To_Unbounded_String ("*");
   Store.Put_Object
     ("symlink-bucket", "link", Source, Storage.Default_Put_Options,
      null, Ada.Real_Time.Time_Last, Info, Result, Conditions);
   Require
     (Result = Storage.Backend_Unavailable,
      "conditional Put_Object accepted an object-path symlink");
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Link_Path),
      "failed conditional Put_Object replaced the symlink");
   Store.Delete_Object
     ("symlink-bucket", "link", null, Ada.Real_Time.Time_Last, Result,
      (Has_ETag => True,
       ETag => US.To_Unbounded_String ("*"),
       others => <>),
      (Require_Unversioned => True));
   Require
     (Result =
        (if Mode = "live"
         then Storage.Backend_Unavailable else Storage.Not_Found),
      "conditional Delete_Object followed an object-path symlink: " &
      Storage.Status'Image (Result));
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Link_Path),
      "failed conditional Delete_Object removed the symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-sentinel",
            "conditional Put_Object modified the external sentinel");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing),
         "conditional Put_Object created the dangling-link target");
   end if;
end Files_Conditional_Symlink_Probe;
