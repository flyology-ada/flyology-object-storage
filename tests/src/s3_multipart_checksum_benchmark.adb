with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Memory;

--  Measures the memory backend's explicit no-checksum multipart baseline
--  against retained CRC64NVME metadata over the same generated body.
procedure S3_Multipart_Checksum_Benchmark is
   package OS renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Memory renames Flyology.Object_Storage.Backends.Memory;
   package US renames Ada.Strings.Unbounded;
   package Real_IO is new Ada.Text_IO.Float_IO (Long_Float);
   use type Ada.Real_Time.Time;
   use type Ada.Streams.Stream_Element_Offset;
   use type OS.Checksum_Algorithm;
   use type OS.Status;

   MiB : constant OS.Byte_Count := 1_024 * 1_024;
   MiB_Count : constant Positive :=
     (if Ada.Command_Line.Argument_Count = 0 then 64
      else Positive'Value (Ada.Command_Line.Argument (1)));
   Body_Size : constant OS.Byte_Count := OS.Byte_Count (MiB_Count) * MiB;

   type Generated_Source is new Backends.Byte_Source with record
      Position : OS.Byte_Count := 0;
   end record;

   overriding function Declared_Length
     (Item : Generated_Source) return Backends.Source_Length is
     (Kind => Backends.Known, Bytes => Body_Size);

   overriding procedure Read
     (Item     : in out Generated_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Remaining : constant OS.Byte_Count := Body_Size - Item.Position;
      Count : constant Natural := Natural
        (OS.Byte_Count'Min (Remaining, OS.Byte_Count (Data'Length)));
   begin
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             ((Item.Position + OS.Byte_Count (Offset)) mod 251);
      end loop;
      Item.Position := Item.Position + OS.Byte_Count (Count);
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Finished := Item.Position = Body_Size;
   end Read;

   Store : Memory.Store
     (Bucket_Capacity => 1,
      Object_Capacity => 2,
      Byte_Capacity   => 2 * Body_Size);
   Result : OS.Status;

   procedure Run
     (Label : String; Checksum : OS.Checksum_Information)
   is
      Upload_Options : Backends.Multipart_Options :=
        Backends.Default_Multipart_Options;
      Upload_ID : US.Unbounded_String;
      Source : Generated_Source;
      Info : OS.Object_Information;
      Started : Ada.Real_Time.Time;
      Finished : Ada.Real_Time.Time;
      Seconds : Long_Float;
      Rate : Long_Float;
   begin
      Upload_Options.Checksum := Checksum;
      Store.Create_Multipart_Upload
        ("benchmark-bucket", Label, Upload_Options, null,
         Ada.Real_Time.Time_Last, Upload_ID, Result);
      if Result /= OS.Success then
         raise Program_Error with "multipart benchmark create failed";
      end if;
      Started := Ada.Real_Time.Clock;
      Store.Put_Multipart_Part
        ("benchmark-bucket", Label, US.To_String (Upload_ID), 1, Source,
         Backends.Default_Multipart_Part_Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Finished := Ada.Real_Time.Clock;
      if Result /= OS.Success
        or else Info.Checksum.Algorithm /= Checksum.Algorithm
      then
         raise Program_Error with "multipart benchmark put failed";
      end if;
      Seconds := Long_Float
        (Ada.Real_Time.To_Duration (Finished - Started));
      Rate := Long_Float (MiB_Count) / Long_Float'Max (Seconds, 0.000_001);
      Ada.Text_IO.Put (Label & ASCII.HT);
      Ada.Text_IO.Put (OS.Byte_Count'Image (Body_Size) & ASCII.HT);
      Real_IO.Put (Seconds, Fore => 1, Aft => 6, Exp => 0);
      Ada.Text_IO.Put (ASCII.HT);
      Real_IO.Put (Rate, Fore => 1, Aft => 2, Exp => 0);
      Ada.Text_IO.New_Line;
      Store.Abort_Multipart_Upload
        ("benchmark-bucket", Label, US.To_String (Upload_ID),
         Backends.No_Abort_Multipart_Conditions, null,
         Ada.Real_Time.Time_Last, Result);
      if Result /= OS.Success then
         raise Program_Error with "multipart benchmark cleanup failed";
      end if;
   end Run;

begin
   Store.Create_Bucket
     ("benchmark-bucket", null, Ada.Real_Time.Time_Last, Result);
   if Result /= OS.Success then
      raise Program_Error with "multipart benchmark bucket failed";
   end if;
   Ada.Text_IO.Put_Line
     ("selection" & ASCII.HT & "bytes" & ASCII.HT & "seconds" &
      ASCII.HT & "MiB/s");
   Run ("NONE", OS.No_Checksum_Information);
   Run
     ("CRC64NVME",
      (Algorithm => OS.Checksum_CRC64NVME,
       Method    => OS.Full_Object_Checksum,
       Value     => US.Null_Unbounded_String));
end S3_Multipart_Checksum_Benchmark;
