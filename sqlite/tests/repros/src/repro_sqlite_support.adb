with Ada.Calendar;
with Ada.Directories;

package body Repro_SQLite_Support is

   use type Ada.Streams.Stream_Element_Offset;

   Scratch : constant String := "/private/tmp/claude-501";

   Counter : Natural := 0;

   function Fresh_Root (Label : String) return String is
      Stamp : constant Long_Long_Integer :=
        Long_Long_Integer
          (Duration (Ada.Calendar.Seconds (Ada.Calendar.Clock)) * 1_000);
      Digits_Image : constant String :=
        Long_Long_Integer'Image (Stamp);
      Serial : constant String := Natural'Image (Counter);
      Root : constant String :=
        Scratch & "/repro-sqlite/" & Label & "-" &
        Digits_Image (Digits_Image'First + 1 .. Digits_Image'Last) & "-" &
        Serial (Serial'First + 1 .. Serial'Last);
   begin
      Counter := Counter + 1;
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
      return Root;
   end Fresh_Root;

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Total     : constant Natural := US.Length (Item.Data);
      Remaining : constant Natural := Total - Item.Position;
      Count     : constant Natural :=
        Natural'Min (Remaining, Natural (Data'Length));
   begin
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos (US.Element (Item.Data, Item.Position + Offset + 1)));
      end loop;
      Item.Position := Item.Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Finished := Item.Position = Total;
   end Read;

   function Source_Of (Value : String) return Buffer_Source is
   begin
      return Result : Buffer_Source do
         Result.Data := US.To_Unbounded_String (Value);
         Result.Position := 0;
         Result.Length :=
           (Kind => BE.Known, Bytes => OS.Byte_Count (Value'Length));
      end return;
   end Source_Of;

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : OS.Object_Information;
      First          : OS.Byte_Count;
      Content_Length : OS.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Item.Begin_Count := Item.Begin_Count + 1;
      Item.First := First;
      Item.Content_Length := Content_Length;
      Item.Partial := Partial;
      Item.Snapshot := Info;
   end Begin_Object;

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      for Element of Data loop
         US.Append (Item.Data, Character'Val (Natural (Element)));
      end loop;
   end Write;

   overriding procedure Begin_Annotation
     (Item     : in out Annotation_Sink;
      Info     : OS.Object_Annotation_Information;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Item.Begin_Count := Item.Begin_Count + 1;
      Item.Info := Info;
   end Begin_Annotation;

   overriding procedure Write
     (Item     : in out Annotation_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      for Element of Data loop
         US.Append (Item.Data, Character'Val (Natural (Element)));
      end loop;
   end Write;

   function Image (Value : OS.Status) return String is
   begin
      return OS.Status'Image (Value);
   end Image;

end Repro_SQLite_Support;
