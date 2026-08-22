with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Text_IO;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;

procedure S3_Checksum_Benchmark is
   package Policy renames Flyology.Object_Storage.S3.Checksum_Policy;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Real_IO is new Ada.Text_IO.Float_IO (Long_Float);
   use type Ada.Real_Time.Time;

   subtype SEO is Ada.Streams.Stream_Element_Offset;
   subtype Bytes is Ada.Streams.Stream_Element_Array;
   type Bytes_Access is access all Bytes;

   Block_Size : constant Positive := 1_024 * 1_024;
   MiB_Count  : constant Positive :=
     (if Ada.Command_Line.Argument_Count = 0
      then 256
      else Positive'Value (Ada.Command_Line.Argument (1)));
   Data : constant Bytes_Access := new Bytes (1 .. SEO (Block_Size));

   procedure Run (Kind : Policy.Algorithm) is
      Item     : Checksums.Context (Kind);
      Started  : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Finished : Ada.Real_Time.Time;
      Seconds  : Long_Float;
      Rate     : Long_Float;
      Value    : Checksums.Digest_Value;
   begin
      for Iteration in 1 .. MiB_Count loop
         Checksums.Update (Item, Data.all);
      end loop;
      Value := Checksums.Finish (Item);
      Finished := Ada.Real_Time.Clock;
      Seconds := Long_Float
        (Ada.Real_Time.To_Duration (Finished - Started));
      Rate := Long_Float (MiB_Count) / Long_Float'Max (Seconds, 0.000_001);
      Ada.Text_IO.Put (Policy.Wire_Name (Kind) & ASCII.HT);
      Ada.Text_IO.Put (Positive'Image (MiB_Count * Block_Size) & ASCII.HT);
      Real_IO.Put (Seconds, Fore => 1, Aft => 6, Exp => 0);
      Ada.Text_IO.Put (ASCII.HT);
      Real_IO.Put (Rate, Fore => 1, Aft => 2, Exp => 0);
      Ada.Text_IO.Put (ASCII.HT & Checksums.Encode_Base64 (Value));
      Ada.Text_IO.New_Line;
   end Run;

begin
   for Index in 0 .. Block_Size - 1 loop
      Data (SEO (Index + 1)) := Ada.Streams.Stream_Element
        ((Index * 131 + Index / 7 + 17) mod 256);
   end loop;
   Ada.Text_IO.Put_Line
     ("algorithm" & ASCII.HT & "bytes" & ASCII.HT & "seconds" &
      ASCII.HT & "MiB/s" & ASCII.HT & "digest");
   for Kind in Policy.Algorithm loop
      Run (Kind);
   end loop;
end S3_Checksum_Benchmark;
