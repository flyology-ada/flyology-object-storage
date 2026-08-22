with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Tags;

procedure S3_Bucket_Tagging_Benchmark is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Tags renames Flyology.Object_Storage.Tags;
   package US renames Ada.Strings.Unbounded;
   package Real_IO is new Ada.Text_IO.Float_IO (Long_Float);

   use type Ada.Real_Time.Time;
   use type Buckets.Create_Outcome_Kind;
   use type Buckets.Delete_Outcome_Kind;
   use type Buckets.Put_Tags_Outcome_Kind;
   use type Buckets.Get_Tags_Outcome_Kind;
   use type Buckets.Delete_Tags_Outcome_Kind;
   use type Tags.Tag_Vectors.Vector;

   procedure Put_Rate (Value : Long_Float) is
   begin
      Real_IO.Put (Value, Fore => 1, Aft => 6, Exp => 0);
   end Put_Rate;

   function Lifecycle_Valid
     (Expected      : Tags.Tag_Set;
      Put_Result    : Buckets.Put_Tags_Outcome;
      Get_Result    : Buckets.Get_Tags_Outcome;
      Delete_Result : Buckets.Delete_Tags_Outcome;
      Absent_Result : Buckets.Get_Tags_Outcome) return Boolean is
     (Put_Result.Kind = Buckets.Tags_Replaced
      and then Put_Result.Status in 200 | 204
      and then Get_Result.Kind = Buckets.Tags_Found
      and then Get_Result.Status = 200
      and then Get_Result.Value = Expected
      and then Delete_Result.Kind = Buckets.Tags_Deleted
      and then Delete_Result.Status = 204
      and then Absent_Result.Kind = Buckets.Get_Tags_Rejected
      and then Absent_Result.Status = 404
      and then US.To_String (Absent_Result.Error.Code) = "NoSuchTagSet");

   procedure Check_Negative_Oracle is
      First : Tags.Tag_Set;
      Second : Tags.Tag_Set;
      Put_OK : constant Buckets.Put_Tags_Outcome :=
        (Kind => Buckets.Tags_Replaced, Status => 200);
      Delete_OK : constant Buckets.Delete_Tags_Outcome :=
        (Kind => Buckets.Tags_Deleted, Status => 204);
      No_Tags : constant Buckets.Get_Tags_Outcome :=
        (Kind   => Buckets.Get_Tags_Rejected,
         Status => 404,
         Error  =>
           (Code   => US.To_Unbounded_String ("NoSuchTagSet"),
            others => US.Null_Unbounded_String));
   begin
      First.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("benchmark"),
            Value => US.To_Unbounded_String ("first")));
      Second.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("benchmark"),
            Value => US.To_Unbounded_String ("second")));
      declare
         Stale_Get : constant Buckets.Get_Tags_Outcome :=
           (Kind => Buckets.Tags_Found, Status => 200, Value => First);
      begin
         if Lifecycle_Valid
           (Second, Put_OK, Stale_Get, Delete_OK, No_Tags)
         then
            raise Program_Error with
              "bucket tagging benchmark accepted a stale Put";
         end if;
      end;
      declare
         Current_Get : constant Buckets.Get_Tags_Outcome :=
           (Kind => Buckets.Tags_Found, Status => 200, Value => First);
         Still_Present : constant Buckets.Get_Tags_Outcome :=
           (Kind => Buckets.Tags_Found, Status => 200, Value => First);
      begin
         if Lifecycle_Valid
           (First, Put_OK, Current_Get, Delete_OK, Still_Present)
         then
            raise Program_Error with
              "bucket tagging benchmark accepted a no-op Delete";
         end if;
      end;
      declare
         Current_Get : constant Buckets.Get_Tags_Outcome :=
           (Kind => Buckets.Tags_Found, Status => 200, Value => First);
         Wrong_Status : constant Buckets.Get_Tags_Outcome :=
           (Kind   => Buckets.Get_Tags_Rejected,
            Status => 500,
            Error  =>
              (Code   => US.To_Unbounded_String ("NoSuchTagSet"),
               others => US.Null_Unbounded_String));
      begin
         if Lifecycle_Valid
           (First, Put_OK, Current_Get, Delete_OK, Wrong_Status)
         then
            raise Program_Error with
              "bucket tagging benchmark accepted NoSuchTagSet with HTTP 500";
         end if;
      end;
   end Check_Negative_Oracle;

begin
   Check_Negative_Oracle;
   if Ada.Command_Line.Argument_Count = 1
     and then Ada.Command_Line.Argument (1) = "--self-test"
   then
      Ada.Text_IO.Put_Line
        ("bucket tagging benchmark stale-put/no-op-delete/status oracle: OK");
      return;
   end if;
   if Ada.Command_Line.Argument_Count /= 7 then
      raise Program_Error with
        "usage: s3_bucket_tagging_benchmark ENDPOINT BUCKET ACCESS_KEY " &
        "SECRET_KEY CYCLES REPETITIONS WARMUP_CYCLES";
   end if;
   declare
      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin (Ada.Command_Line.Argument (1));
      Bucket : constant String := Ada.Command_Line.Argument (2);
      Identity : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials
          (Ada.Command_Line.Argument (3), Ada.Command_Line.Argument (4));
      Cycles : constant Positive :=
        Positive'Value (Ada.Command_Line.Argument (5));
      Repetitions : constant Positive :=
        Positive'Value (Ada.Command_Line.Argument (6));
      Warmup_Cycles : constant Natural :=
        Natural'Value (Ada.Command_Line.Argument (7));
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      First_Value : Tags.Tag_Set;
      Second_Value : Tags.Tag_Set;
      Sequence : Natural := 0;
      Configured : Boolean := False;
      Created : Boolean := False;

      procedure Exercise (Expected : Tags.Tag_Set) is
         Put_Result : constant Buckets.Put_Tags_Outcome :=
           Buckets.Put_Tags
             (HTTP, Origin, Bucket, Expected, Identity, Timeout => 30.0);
         Get_Result : constant Buckets.Get_Tags_Outcome :=
           Buckets.Get_Tags
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
         Delete_Result : constant Buckets.Delete_Tags_Outcome :=
           Buckets.Delete_Tags
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
         Absent_Result : constant Buckets.Get_Tags_Outcome :=
           Buckets.Get_Tags
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
      begin
         if not Lifecycle_Valid
           (Expected, Put_Result, Get_Result, Delete_Result, Absent_Result)
         then
            raise Program_Error with
              "bucket tagging benchmark correctness oracle failed";
         end if;
      end Exercise;

      procedure Exercise_Next is
      begin
         Sequence := Sequence + 1;
         if Sequence mod 2 = 1 then
            Exercise (First_Value);
         else
            Exercise (Second_Value);
         end if;
      end Exercise_Next;

      procedure Cleanup is
      begin
         if Configured and then Created then
            declare
               Ignored : constant Buckets.Delete_Tags_Outcome :=
                 Buckets.Delete_Tags
                   (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
               pragma Unreferenced (Ignored);
               Deleted : constant Buckets.Delete_Outcome :=
                 Buckets.Delete
                   (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
            begin
               if Deleted.Kind /= Buckets.Deletion_Completed then
                  raise Program_Error with
                    "bucket tagging benchmark cleanup rejected DeleteBucket";
               end if;
               Created := False;
            end;
         end if;
         if Configured then
            HTTP_Client.Shutdown (HTTP);
            Configured := False;
         end if;
      end Cleanup;
   begin
      First_Value.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("benchmark"),
            Value => US.To_Unbounded_String ("first")));
      Second_Value.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("benchmark"),
            Value => US.To_Unbounded_String ("second")));
      HTTP_Client.Configure (HTTP, Origin);
      Configured := True;
      declare
         Result : constant Buckets.Create_Outcome :=
           Buckets.Create
             (HTTP, Origin, Bucket, Identity, Timeout => 30.0);
      begin
         if Result.Kind /= Buckets.Creation_Completed then
            raise Program_Error with
              "bucket tagging benchmark rejected CreateBucket";
         end if;
         Created := True;
      end;
      for Iteration in 1 .. Warmup_Cycles loop
         Exercise_Next;
      end loop;
      Ada.Text_IO.Put_Line
        ("repetition" & ASCII.HT & "cycles" & ASCII.HT & "operations" &
         ASCII.HT & "seconds" & ASCII.HT & "lifecycles_per_second" &
         ASCII.HT & "operations_per_second");
      for Repetition in 1 .. Repetitions loop
         declare
            Started : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
            Finished : Ada.Real_Time.Time;
            Seconds : Long_Float;
            Lifecycle_Rate : Long_Float;
            Operation_Rate : Long_Float;
         begin
            for Iteration in 1 .. Cycles loop
               Exercise_Next;
            end loop;
            Finished := Ada.Real_Time.Clock;
            Seconds := Long_Float
              (Ada.Real_Time.To_Duration (Finished - Started));
            Lifecycle_Rate :=
              Long_Float (Cycles) / Long_Float'Max (Seconds, 0.000_001);
            Operation_Rate := 4.0 * Lifecycle_Rate;
            Ada.Text_IO.Put (Positive'Image (Repetition) & ASCII.HT);
            Ada.Text_IO.Put (Positive'Image (Cycles) & ASCII.HT);
            Ada.Text_IO.Put (Positive'Image (4 * Cycles) & ASCII.HT);
            Put_Rate (Seconds);
            Ada.Text_IO.Put (ASCII.HT);
            Put_Rate (Lifecycle_Rate);
            Ada.Text_IO.Put (ASCII.HT);
            Put_Rate (Operation_Rate);
            Ada.Text_IO.New_Line;
         end;
      end loop;
      Cleanup;
   exception
      when others =>
         Cleanup;
         raise;
   end;
end S3_Bucket_Tagging_Benchmark;
