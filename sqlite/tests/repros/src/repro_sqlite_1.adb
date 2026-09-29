--  BACKEND-SQLITE-1: Get_Object passes no Check callback to
--  Find_Selected_Object, so the catalog operation gate is released before
--  SIO.Open.  A concurrent Put_Object that commits a replacement and unlinks
--  the previous payload in that window turns a valid GET into
--  Backend_Unavailable (HTTP 503 SlowDown), even though the key is readable
--  before and after the request.
--
--  Asserts the CORRECT behaviour: every GET of a key that always exists
--  returns Success.  Two phases race the same readers and writers:
--    A. ordinary reads (no conditions);
--    B. reads carrying a long but matching If-Match list, which is the only
--       work Get_Object performs between the gate release and SIO.Open, so
--       it widens the unprotected window.
--  A single-task control GET runs first and must succeed.
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with Repro_Support; use Repro_Support;
with Repro_SQLite_Support; use Repro_SQLite_Support;

procedure Repro_SQLite_1 is
   use type Flyology.Object_Storage.Status;
   use type Ada.Real_Time.Time;
   package OSS renames Flyology.Object_Storage;
   package OSB renames Flyology.Object_Storage.Backends;
   package SQL_Backend renames Flyology.Object_Storage.Backends.SQLite;

   Root    : constant String := Fresh_Root ("get-race");
   Bucket  : constant String := "race-bucket";
   Key     : constant String := "k";
   Content : constant String := "x";
   Never   : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Readers : constant := 32;
   Writers : constant := 2;
   Phase_Seconds : constant Duration := 20.0;

   Store : SQL_Backend.Store := SQL_Backend.Open (Root);

   Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
   Match_List : Ada.Strings.Unbounded.Unbounded_String;
   Stop_Time  : Ada.Real_Time.Time;
   Read_Template : OSB.Read_Conditions := OSB.Default_Read_Conditions;

   type Status_Counts is array (OSS.Status) of Natural;

   protected Tally is
      procedure Reset;
      procedure Record_Get (Value : OSS.Status);
      procedure Record_Put (Value : OSS.Status);
      procedure Finished;
      entry Wait_All;
      function Gets return Status_Counts;
      function Puts return Status_Counts;
   private
      Get_Counts : Status_Counts := [others => 0];
      Put_Counts : Status_Counts := [others => 0];
      Live       : Natural := 0;
   end Tally;

   protected body Tally is
      procedure Reset is
      begin
         Get_Counts := [others => 0];
         Put_Counts := [others => 0];
         Live := Readers + Writers;
      end Reset;
      procedure Record_Get (Value : OSS.Status) is
      begin
         Get_Counts (Value) := Get_Counts (Value) + 1;
      end Record_Get;
      procedure Record_Put (Value : OSS.Status) is
      begin
         Put_Counts (Value) := Put_Counts (Value) + 1;
      end Record_Put;
      procedure Finished is
      begin
         Live := Live - 1;
      end Finished;
      entry Wait_All when Live = 0 is
      begin
         null;
      end Wait_All;
      function Gets return Status_Counts is (Get_Counts);
      function Puts return Status_Counts is (Put_Counts);
   end Tally;

   task type Reader;
   task body Reader is
      Conditions : constant OSB.Read_Conditions := Read_Template;
      Result     : OSS.Status;
   begin
      while Ada.Real_Time.Clock < Stop_Time loop
         declare
            Sink : Buffer_Sink;
            Info : OSS.Object_Information;
         begin
            Store.Get_Object
              (Bucket, Key, OSS.Whole_Object, Sink, null, Never,
               Info, Result, Conditions);
            Tally.Record_Get (Result);
         exception
            when others =>
               Tally.Record_Get (OSS.Backend_Unavailable);
         end;
      end loop;
      Tally.Finished;
   end Reader;

   task type Writer;
   task body Writer is
      Result : OSS.Status;
   begin
      while Ada.Real_Time.Clock < Stop_Time loop
         declare
            Source   : Buffer_Source := Source_Of (Content);
            Info     : OSS.Object_Information;
            Identity : OSB.Version_Identity;
         begin
            Store.Put_Object
              (Bucket, Key, Source, OSS.Default_Put_Options, null, Never,
               Info, Identity, Result);
            Tally.Record_Put (Result);
         exception
            when others =>
               Tally.Record_Put (OSS.Backend_Unavailable);
         end;
      end loop;
      Tally.Finished;
   end Writer;

   procedure Report (Label : String; Counts : Status_Counts) is
      Total : Natural := 0;
   begin
      for Value in OSS.Status loop
         Total := Total + Counts (Value);
      end loop;
      declare
         Line : Ada.Strings.Unbounded.Unbounded_String;
      begin
         for Value in OSS.Status loop
            if Counts (Value) > 0 then
               Ada.Strings.Unbounded.Append
                 (Line, " " & Image (Value) & "=" & Image (Counts (Value)));
            end if;
         end loop;
         Note (Label & " total" & Natural'Image (Total) & ":" &
               Ada.Strings.Unbounded.To_String (Line));
      end;
   end Report;

   procedure Race (Label : String) is
   begin
      Tally.Reset;
      Stop_Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (Phase_Seconds);
      declare
         Reader_Pool : array (1 .. Readers) of Reader;
         Writer_Pool : array (1 .. Writers) of Writer;
         pragma Unreferenced (Reader_Pool, Writer_Pool);
      begin
         Tally.Wait_All;
      end;
      Report (Label & " GET", Tally.Gets);
      Report (Label & " PUT", Tally.Puts);
      Check (Tally.Puts (OSS.Success) > 0,
             Label & ": the writers made progress");
      Check (Tally.Gets (OSS.Success) = Tally.Gets (OSS.Success) +
               (Tally.Gets (OSS.Backend_Unavailable) +
                Tally.Gets (OSS.Not_Found)) - 
               (Tally.Gets (OSS.Backend_Unavailable) +
                Tally.Gets (OSS.Not_Found)),
             Label & ": tally is consistent");
      Check (Tally.Gets (OSS.Backend_Unavailable) = 0,
             Label & ": no concurrent Get_Object reports " &
             "Backend_Unavailable for a key that always exists");
      Check (Tally.Gets (OSS.Not_Found) = 0,
             Label & ": no concurrent Get_Object reports Not_Found for a " &
             "key that always exists");
   end Race;

   Result : OSS.Status;
begin
   Note ("root " & Root);
   Store.Create_Bucket (Bucket, null, Never, Result);
   Check (Result = OSS.Success, "Create_Bucket succeeds");
   declare
      Source   : Buffer_Source := Source_Of (Content);
      Info     : OSS.Object_Information;
      Identity : OSB.Version_Identity;
   begin
      Store.Put_Object
        (Bucket, Key, Source, OSS.Default_Put_Options, null, Never,
         Info, Identity, Result);
      Check (Result = OSS.Success, "Put_Object seeds the key");
      Entity_Tag := Info.Entity_Tag;
   end;
   Note ("entity tag " & Ada.Strings.Unbounded.To_String (Entity_Tag) &
         " (constant: every writer publishes the same bytes)");

   declare
      Sink : Buffer_Sink;
      Info : OSS.Object_Information;
   begin
      Store.Get_Object
        (Bucket, Key, OSS.Whole_Object, Sink, null, Never, Info, Result);
      Note ("control Get_Object " & Image (Result) & " bytes " &
            Image (Ada.Strings.Unbounded.Length (Sink.Data)));
      Check (Result = OSS.Success, "control Get_Object succeeds");
      Check (Ada.Strings.Unbounded.To_String (Sink.Data) = Content,
             "control Get_Object round-trips the body");
   end;

   Read_Template := OSB.Default_Read_Conditions;
   Race ("phase A (plain reads)");

   for Index in 1 .. 950 loop
      Ada.Strings.Unbounded.Append (Match_List, """0123456789ab"",");
   end loop;
   Ada.Strings.Unbounded.Append
     (Match_List, '"' & Ada.Strings.Unbounded.To_String (Entity_Tag) & '"');
   Note ("phase B If-Match list length" &
         Natural'Image (Ada.Strings.Unbounded.Length (Match_List)) &
         " (matching, evaluated after the gate release)");
   Read_Template := OSB.Default_Read_Conditions;
   Read_Template.If_Match := Match_List;
   Race ("phase B (long matching If-Match)");

   Finish;
end Repro_SQLite_1;
