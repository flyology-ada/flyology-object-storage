with Ada.Calendar.Formatting;

package body Repro_Backend_Memory_Support is

   use type Storage.Unix_Time;

   --  Mirrors src/flyology-object_storage-backends-memory.adb:93-95, 207-208.
   Epoch : constant Ada.Calendar.Time :=
     Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0, 0, 0, Time_Zone => 0);

   function Backend_Unix_Time return Storage.Unix_Time is
      use type Ada.Calendar.Time;
   begin
      return Storage.Unix_Time
        (Long_Long_Integer (Ada.Calendar.Clock - Epoch));
   end Backend_Unix_Time;

   procedure Advance_One_Second is
      Start : constant Storage.Unix_Time := Backend_Unix_Time;
   begin
      loop
         delay 0.05;
         exit when Backend_Unix_Time /= Start;
      end loop;
   end Advance_One_Second;

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
   begin
      for Element of Data loop
         US.Append (Item.Data, Character'Val (Natural (Element)));
      end loop;
   end Write;

end Repro_Backend_Memory_Support;
