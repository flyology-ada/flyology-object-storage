with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;

procedure Files_Copy_Benchmark is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package US renames Ada.Strings.Unbounded;
   package Real_IO is new Ada.Text_IO.Float_IO (Long_Float);

   use type Ada.Real_Time.Time;
   use type Ada.Streams.Stream_Element_Offset;
   use type Storage.Status;

   type Generated_Source is limited new Backends.Byte_Source with record
      Total     : Storage.Byte_Count;
      Remaining : Storage.Byte_Count;
   end record;

   overriding function Declared_Length
     (Source : Generated_Source) return Backends.Source_Length is
     (Kind => Backends.Known, Bytes => Source.Total);

   overriding procedure Read
     (Source   : in out Generated_Source;
      Buffer   : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Count : constant Ada.Streams.Stream_Element_Offset :=
        Ada.Streams.Stream_Element_Offset
          (Storage.Byte_Count'Min
             (Source.Remaining, Storage.Byte_Count (Buffer'Length)));
   begin
      if Count = 0 then
         Last := Buffer'First - 1;
      else
         for Index in Buffer'First .. Buffer'First + Count - 1 loop
            Buffer (Index) := Ada.Streams.Stream_Element
              ((Long_Long_Integer (Source.Total - Source.Remaining)
                + Long_Long_Integer (Index - Buffer'First)) mod 251);
         end loop;
         Last := Buffer'First + Count - 1;
         Source.Remaining := Source.Remaining - Storage.Byte_Count (Count);
      end if;
      Finished := Source.Remaining = 0;
   end Read;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Required_Argument (Index : Positive) return String is
   begin
      if Ada.Command_Line.Argument_Count /= 3 then
         raise Program_Error with
           "usage: files_copy_benchmark ROOT MIB COPIES";
      end if;
      return Ada.Command_Line.Argument (Index);
   end Required_Argument;

   Root : constant String := Required_Argument (1);
   MiB : constant Positive := Positive'Value (Required_Argument (2));
   Copies : constant Positive :=
     Positive'Value (Required_Argument (3));
   Bytes : constant Storage.Byte_Count :=
     Storage.Byte_Count (MiB) * 1_024 * 1_024;
   Store : Files.Store := Files.Open
     (Root, Maximum_Object_Size => Bytes,
      Commit => Files.Process_Crash_Atomic);
   Source : Generated_Source := (Total => Bytes, Remaining => Bytes);
   Options : constant Storage.Put_Options :=
     (Entity_Tag => US.To_Unbounded_String ("benchmark-source"),
      Content_Type => US.To_Unbounded_String ("application/octet-stream"));
   Copy_Options : constant Backends.Copy_Options :=
     Backends.Default_Copy_Options;
   Info : Storage.Object_Information;
   Result : Storage.Status;
   Started, Finished : Ada.Real_Time.Time;
   Seconds, Rate : Long_Float;
begin
   Store.Create_Bucket
     ("benchmark", null, Ada.Real_Time.Time_Last, Result);
   Require (Result = Storage.Success, "create bucket failed");
   Store.Put_Object
     ("benchmark", "source", Source, Options, null,
      Ada.Real_Time.Time_Last, Info, Result);
   Require (Result = Storage.Success, "put source failed");

   Started := Ada.Real_Time.Clock;
   for Index in 1 .. Copies loop
      Store.Copy_Object
        ("benchmark", "source", "benchmark",
         "copy-" & Positive'Image (Index), Copy_Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Storage.Success, "copy failed");
   end loop;
   Finished := Ada.Real_Time.Clock;
   Seconds := Long_Float (Ada.Real_Time.To_Duration (Finished - Started));
   Rate := Long_Float (MiB * Copies) / Long_Float'Max (Seconds, 0.000_001);

   Ada.Text_IO.Put_Line
     ("backend" & ASCII.HT & "object_bytes" & ASCII.HT & "copies" &
      ASCII.HT & "seconds" & ASCII.HT & "logical_MiB/s");
   Ada.Text_IO.Put
     ("files-process-crash-atomic" & ASCII.HT &
      Storage.Byte_Count'Image (Bytes) & ASCII.HT &
      Positive'Image (Copies) & ASCII.HT);
   Real_IO.Put (Seconds, Fore => 1, Aft => 6, Exp => 0);
   Ada.Text_IO.Put (ASCII.HT);
   Real_IO.Put (Rate, Fore => 1, Aft => 2, Exp => 0);
   Ada.Text_IO.New_Line;
end Files_Copy_Benchmark;
