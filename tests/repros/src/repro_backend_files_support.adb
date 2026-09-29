with Ada.Calendar;
with Ada.Directories;
with Ada.Strings.Fixed;

package body Repro_Backend_Files_Support is

   Scratch : constant String := "/private/tmp/claude-501";

   function Make_Root (Label : String) return String is
      Stamp : constant String := Ada.Strings.Fixed.Trim
        (Duration'Image
           (Ada.Calendar.Seconds (Ada.Calendar.Clock)), Ada.Strings.Both);
      Clean : String := Stamp;
      Path  : US.Unbounded_String;
   begin
      for Index in Clean'Range loop
         if Clean (Index) not in '0' .. '9' then
            Clean (Index) := '-';
         end if;
      end loop;
      Path := US.To_Unbounded_String
        (Ada.Directories.Compose
           (Scratch, "repro-" & Label & "-" & Clean));
      Ada.Directories.Create_Path (US.To_String (Path));
      return US.To_String (Path);
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

   overriding function Declared_Length
     (Item : String_Source) return Backends.Source_Length is
     (Kind  => Backends.Known,
      Bytes => Storage.Byte_Count (Item.Length));

   overriding procedure Read
     (Item     : in out String_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      use type Ada.Streams.Stream_Element_Offset;
      Remaining : constant Natural := Item.Length - Item.Sent;
      Count     : constant Natural :=
        Natural'Min (Remaining, Natural (Data'Length));
   begin
      Data := [others => 0];
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Item.Payload (Item.Sent + 1 + Offset)));
      end loop;
      Item.Sent := Item.Sent + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Finished := Item.Sent >= Item.Length;
   end Read;

   function Source_Of (Payload : String) return String_Source is
   begin
      return Result : String_Source (Payload'Length) do
         Result.Payload := Payload;
         Result.Sent := 0;
      end return;
   end Source_Of;

   overriding procedure Begin_Object
     (Item           : in out Collecting_Sink;
      Info           : Storage.Object_Information;
      First          : Storage.Byte_Count;
      Content_Length : Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced (First, Content_Length, Partial, Token, Deadline);
   begin
      Item.Started := True;
      Item.Info := Info;
      Item.Data := US.Null_Unbounded_String;
   end Begin_Object;

   overriding procedure Write
     (Item     : in out Collecting_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Text : String (1 .. Natural (Data'Length));
      Cursor : Natural := 0;
   begin
      for Element of Data loop
         Cursor := Cursor + 1;
         Text (Cursor) := Character'Val (Natural (Element));
      end loop;
      US.Append (Item.Data, Text);
   end Write;

   overriding procedure Begin_Annotation
     (Item     : in out Collecting_Annotation_Sink;
      Info     : Storage.Object_Annotation_Information;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Info, Token, Deadline);
   begin
      Item.Started := True;
      Item.Data := US.Null_Unbounded_String;
   end Begin_Annotation;

   overriding procedure Write
     (Item     : in out Collecting_Annotation_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Text : String (1 .. Natural (Data'Length));
      Cursor : Natural := 0;
   begin
      for Element of Data loop
         Cursor := Cursor + 1;
         Text (Cursor) := Character'Val (Natural (Element));
      end loop;
      US.Append (Item.Data, Text);
   end Write;

   function Directory_Exists (Path : String) return Boolean is
      use type Ada.Directories.File_Kind;
   begin
      return Ada.Directories.Exists (Path)
        and then Ada.Directories.Kind (Path) = Ada.Directories.Directory;
   exception
      when others =>
         return False;
   end Directory_Exists;

   function Count_Generation_Directories (Path : String) return Natural is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Total  : Natural := 0;
      Nested : US.Unbounded_String;
   begin
      if not Directory_Exists (Path) then
         return 0;
      end if;
      Ada.Directories.Start_Search
        (Search, Path, "*",
         [Ada.Directories.Directory => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name /= "." and then Name /= ".." then
               if Name'Length > 11
                 and then Name (Name'First .. Name'First + 10) = "generation-"
               then
                  Total := Total + 1;
               else
                  US.Append
                    (Nested, Ada.Directories.Full_Name (Item) & ASCII.LF);
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      declare
         Text  : constant String := US.To_String (Nested);
         First : Positive := Text'First;
      begin
         for Index in Text'Range loop
            if Text (Index) = ASCII.LF then
               Total := Total +
                 Count_Generation_Directories (Text (First .. Index - 1));
               First := Index + 1;
            end if;
         end loop;
      end;
      return Total;
   end Count_Generation_Directories;

end Repro_Backend_Files_Support;
