with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.IO;
with Flyology.Object_Storage;

package body Conditional_Put_Conformance is

   use Flyology.Object_Storage;
   use Flyology.Object_Storage.Backends;
   use type Ada.Streams.Stream_Element_Offset;
   use type Status;
   package US renames Ada.Strings.Unbounded;
   use type US.Unbounded_String;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   type Buffer_Source is new Byte_Source with record
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
     (Item : Buffer_Source) return Source_Length is
     (Kind => Known, Bytes => Byte_Count (Flyology.Bytes.Length (Item.Data)));

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

   type Buffer_Sink is new Byte_Sink with record
      Data : Flyology.Bytes.Unbounded_Bytes;
   end record;

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : Object_Information;
      First          : Byte_Count;
      Content_Length : Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : Object_Information;
      First          : Byte_Count;
      Content_Length : Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced
        (Item, Info, First, Content_Length, Partial, Token, Deadline);
   begin
      null;
   end Begin_Object;

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Flyology.Bytes.Append (Item.Data, Data);
   end Write;

   type Adversarial_Mode is (Raise_After_Chunk, Zero_Progress);
   type Adversarial_Source (Mode : Adversarial_Mode) is new Byte_Source
     with record
        Calls : Natural := 0;
     end record;

   overriding procedure Read
     (Item     : in out Adversarial_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Adversarial_Source) return Source_Length is
     (Kind => Known, Bytes => 8);

   overriding procedure Read
     (Item     : in out Adversarial_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      if Item.Mode = Zero_Progress then
         Item.Calls := Item.Calls + 1;
         Last := Data'First - 1;
         Finished := False;
      elsif Item.Calls = 0 then
         Item.Calls := 1;
         Data (Data'First .. Data'First + 3) :=
           (Character'Pos ('p'), Character'Pos ('a'),
            Character'Pos ('r'), Character'Pos ('t'));
         Last := Data'First + 3;
         Finished := False;
      else
         raise Program_Error with "conditional source sentinel";
      end if;
   end Read;

   type Interrupt_Mode is (Cancel_After_Chunk, Expire_After_Chunk);
   type Interrupting_Source (Mode : Interrupt_Mode) is new Byte_Source
     with record
        Calls : Natural := 0;
     end record;

   overriding procedure Read
     (Item     : in out Interrupting_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Interrupting_Source) return Source_Length is
     (Kind => Known, Bytes => 8);

   overriding procedure Read
     (Item     : in out Interrupting_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Deadline);
   begin
      if Item.Calls /= 0 then
         raise Program_Error with
           "interrupt was not observed between reads";
      end if;
      Item.Calls := 1;
      Data (Data'First .. Data'First + 3) :=
        (Character'Pos ('p'), Character'Pos ('a'),
         Character'Pos ('r'), Character'Pos ('t'));
      Last := Data'First + 3;
      Finished := False;
      if Item.Mode = Cancel_After_Chunk then
         if Token = null then
            raise Program_Error with "missing cancellation token";
         end if;
         Token.Request;
      else
         delay 0.020;
      end if;
   end Read;

   protected type Publication_Race_Gate is
      procedure Arrive;
      entry Wait_For_Both;
   private
      Arrivals : Natural range 0 .. 2 := 0;
   end Publication_Race_Gate;

   protected body Publication_Race_Gate is
      procedure Arrive is
      begin
         Arrivals := Arrivals + 1;
      end Arrive;

      entry Wait_For_Both when Arrivals = 2 is
      begin
         null;
      end Wait_For_Both;
   end Publication_Race_Gate;

   type Race_Gate_Access is access all Publication_Race_Gate;

   type Racing_Source is new Byte_Source with record
      Value : Ada.Streams.Stream_Element;
      Gate  : Race_Gate_Access;
   end record;

   overriding procedure Read
     (Item     : in out Racing_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Racing_Source) return Source_Length is
     (Kind => Known, Bytes => 1);

   overriding procedure Read
     (Item     : in out Racing_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Item.Gate.Arrive;
      Item.Gate.Wait_For_Both;
      Data (Data'First) := Item.Value;
      Last := Data'First;
      Finished := True;
   end Read;

   type Status_Array is array (Positive range 1 .. 2) of Status;
   type Info_Array is array (Positive range 1 .. 2) of Object_Information;

   protected type Race_Outcomes is
      procedure Reset;
      procedure Record_Result
        (Index : Positive; Value : Status; Value_Info : Object_Information);
      function Status_At (Index : Positive) return Status;
      function Info_At (Index : Positive) return Object_Information;
   private
      Results : Status_Array := (others => Backend_Unavailable);
      Infos   : Info_Array := (others => (others => <>));
   end Race_Outcomes;

   protected body Race_Outcomes is
      procedure Reset is
      begin
         Results := (others => Backend_Unavailable);
         Infos := (others => (others => <>));
      end Reset;

      procedure Record_Result
        (Index : Positive; Value : Status; Value_Info : Object_Information)
      is
      begin
         Results (Index) := Value;
         Infos (Index) := Value_Info;
      end Record_Result;

      function Status_At (Index : Positive) return Status is
        (Results (Index));

      function Info_At (Index : Positive) return Object_Information is
        (Infos (Index));
   end Race_Outcomes;

   type Backend_Access is access all Backend'Class;

   procedure Exercise
     (Store           : in out Backend'Class;
      Bucket          : String;
      Race_Iterations : Positive := 32)
   is
      Key    : constant String := "conditional-object";
      Info   : Object_Information;
      Result : Status;
      Race   : Race_Outcomes;

      function Race_Key (Iteration : Positive) return String is
        ("conditional-race-" &
         Ada.Strings.Fixed.Trim
           (Positive'Image (Iteration), Ada.Strings.Both));

      procedure Put
        (Object_Key : String;
         Payload    : String;
         ETag       : String;
         Conditions : Write_Conditions;
         Info       : out Object_Information;
         Result     : out Status)
      is
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0);
         Options : constant Put_Options :=
           (Entity_Tag   => US.To_Unbounded_String (ETag),
            Content_Type => US.To_Unbounded_String ("application/test"));
      begin
         Store.Put_Object
           (Bucket, Object_Key, Source, Options, null,
            Ada.Real_Time.Time_Last, Info, Result, Conditions);
      end Put;

      procedure Require_State
        (Object_Key : String;
         Payload    : String;
         Expected   : Object_Information;
         Message    : String)
      is
         Sink      : Buffer_Sink;
         Head_Info : Object_Information;
         Read_Info : Object_Information;
         Observed  : Status;
      begin
         Store.Head_Object
           (Bucket, Object_Key, null, Ada.Real_Time.Time_Last,
            Head_Info, Observed);
         Require
           (Observed = Success
            and then Head_Info.Size = Expected.Size
            and then Head_Info.Modified = Expected.Modified
            and then Head_Info.Entity_Tag = Expected.Entity_Tag
            and then Head_Info.Content_Type = Expected.Content_Type
            and then Head_Info.Version = Expected.Version,
            Message & " metadata");
         Store.Get_Object
           (Bucket, Object_Key, Whole_Object, Sink, null,
            Ada.Real_Time.Time_Last, Read_Info, Observed);
         Require
           (Observed = Success
            and then Flyology.Bytes.To_Byte_String (Sink.Data) = Payload
            and then Read_Info.Size = Head_Info.Size
            and then Read_Info.Modified = Head_Info.Modified
            and then Read_Info.Entity_Tag = Head_Info.Entity_Tag
            and then Read_Info.Content_Type = Head_Info.Content_Type
            and then Read_Info.Version = Head_Info.Version,
            Message & " body/info");
      end Require_State;

      task type Writer
        (Index     : Positive;
         Iteration : Positive;
         Gate      : Race_Gate_Access;
         Target    : Backend_Access);

      task body Writer is
         Local_Info   : Object_Information;
         Local_Result : Status;
         Conditions   : Write_Conditions := Default_Write_Conditions;
         Payload      : constant String := (if Index = 1 then "A" else "B");
      begin
         Conditions.If_None_Match := US.To_Unbounded_String ("*");
         declare
            Source : Racing_Source :=
              (Value => Ada.Streams.Stream_Element
                 (Character'Pos (Payload (Payload'First))),
               Gate  => Gate);
            Options : constant Put_Options :=
              (Entity_Tag   => US.To_Unbounded_String
                 ("race-" & Positive'Image (Index)),
               Content_Type => US.To_Unbounded_String ("application/race"));
         begin
            Target.Put_Object
              (Bucket, Race_Key (Iteration), Source, Options, null,
               Ada.Real_Time.Time_Last, Local_Info, Local_Result,
               Conditions);
         end;
         Race.Record_Result (Index, Local_Result, Local_Info);
      exception
         when others =>
            Race.Record_Result
              (Index, Backend_Unavailable, (others => <>));
      end Writer;

      First      : Object_Information;
      Current    : Object_Information;
      Conditions : Write_Conditions := Default_Write_Conditions;
   begin
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "conditional put bucket setup");

      Conditions.If_None_Match := US.To_Unbounded_String ("*");
      Put (Key, "first", "generation-1", Conditions, First, Result);
      Require (Result = Success, "create-if-absent rejected new object");
      Require_State (Key, "first", First, "create-if-absent result");

      Put (Key, "collision", "collision", Conditions, Info, Result);
      Require (Result = Precondition_Failed,
               "create-if-absent replaced an existing object");
      Require_State (Key, "first", First, "If-None-Match collision");

      Conditions := Default_Write_Conditions;
      Conditions.If_Match := US.To_Unbounded_String ("""generation-1""");
      Put (Key, "second", "generation-2", Conditions, Current, Result);
      Require (Result = Success, "matching generation replacement failed");
      Require_State (Key, "second", Current, "matching If-Match result");

      Conditions.If_Match := US.To_Unbounded_String ("""generation-1""");
      Put (Key, "stale", "stale", Conditions, Info, Result);
      Require (Result = Precondition_Failed,
               "stale generation replacement succeeded");
      Require_State (Key, "second", Current, "stale If-Match");

      Put ("missing", "missing", "missing", Conditions, Info, Result);
      Require (Result = Precondition_Failed,
               "If-Match accepted a missing destination");

      Conditions.If_Match := US.To_Unbounded_String ("""generation-2""");
      Conditions.If_None_Match := US.To_Unbounded_String ("""other""");
      Put (Key, "third", "generation-3", Conditions, Current, Result);
      Require (Result = Success,
               "combined matching write conditions were rejected");
      Require_State (Key, "third", Current, "combined conditions result");

      Conditions := Default_Write_Conditions;
      Conditions.If_Match := US.To_Unbounded_String ("""unterminated");
      declare
         Source : Adversarial_Source (Raise_After_Chunk);
      begin
         Store.Put_Object
           (Bucket, Key, Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result, Conditions);
         Require
           (Result = Invalid_Request and then Source.Calls = 0,
            "malformed condition consumed the source");
      end;
      Require_State (Key, "third", Current, "malformed condition");

      Conditions := Default_Write_Conditions;
      Conditions.If_Match := US.To_Unbounded_String ("""generation-3""");
      declare
         Source : Adversarial_Source (Raise_After_Chunk);
         Raised : Boolean := False;
      begin
         begin
            Store.Put_Object
              (Bucket, Key, Source, Default_Put_Options, null,
               Ada.Real_Time.Time_Last, Info, Result, Conditions);
         exception
            when Program_Error => Raised := True;
         end;
         Require (Raised, "source exception was swallowed");
      end;
      Require_State (Key, "third", Current, "source exception rollback");

      declare
         Source : Adversarial_Source (Zero_Progress);
      begin
         Store.Put_Object
           (Bucket, Key, Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result, Conditions);
         Require (Result = Invalid_Request,
                  "zero-progress source was accepted");
      end;
      Require_State (Key, "third", Current, "zero-progress rollback");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Source : Interrupting_Source (Cancel_After_Chunk);
         Raised : Boolean := False;
      begin
         begin
            Store.Put_Object
              (Bucket, Key, Source, Default_Put_Options, Cancel'Access,
               Ada.Real_Time.Time_Last, Info, Result, Conditions);
         exception
            when Flyology.Cancellation.Operation_Cancelled => Raised := True;
         end;
         Require
           (Raised and then Source.Calls = 1,
            "mid-stream cancellation did not stop conditional put");
      end;
      Require_State
        (Key, "third", Current, "mid-stream cancellation rollback");

      declare
         Source : Interrupting_Source (Expire_After_Chunk);
         Raised : Boolean := False;
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time."+"
             (Ada.Real_Time.Clock, Ada.Real_Time.Milliseconds (5));
      begin
         begin
            Store.Put_Object
              (Bucket, Key, Source, Default_Put_Options, null,
               Deadline, Info, Result, Conditions);
         exception
            when Flyology.IO.Timeout_Error => Raised := True;
         end;
         Require
           (Raised and then Source.Calls = 1,
            "mid-stream deadline did not stop conditional put");
      end;
      Require_State (Key, "third", Current, "mid-stream deadline rollback");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Source : Buffer_Source :=
           (Data => Flyology.Bytes.From_Byte_String ("cancelled"),
            Position => 0);
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.Put_Object
              (Bucket, Key, Source, Default_Put_Options, Cancel'Access,
               Ada.Real_Time.Time_Last, Info, Result, Conditions);
         exception
            when Flyology.Cancellation.Operation_Cancelled => Raised := True;
         end;
         Require (Raised, "conditional put ignored cancellation");
      end;
      Require_State (Key, "third", Current, "cancellation rollback");

      declare
         Source : Buffer_Source :=
           (Data => Flyology.Bytes.From_Byte_String ("expired"),
            Position => 0);
         Raised : Boolean := False;
      begin
         begin
            Store.Put_Object
              (Bucket, Key, Source, Default_Put_Options, null,
               Ada.Real_Time.Time_First, Info, Result, Conditions);
         exception
            when Flyology.IO.Timeout_Error => Raised := True;
         end;
         Require (Raised, "conditional put ignored expired deadline");
      end;
      Require_State (Key, "third", Current, "deadline rollback");

      for Iteration in 1 .. Race_Iterations loop
         Race.Reset;
         declare
            Gate : aliased Publication_Race_Gate;
            One : Writer
              (1, Iteration, Gate'Unchecked_Access, Store'Unchecked_Access);
            Two : Writer
              (2, Iteration, Gate'Unchecked_Access, Store'Unchecked_Access);
         begin
            null;
         end;
         Require
           ((Race.Status_At (1) = Success
             and then Race.Status_At (2) = Precondition_Failed)
            or else
              (Race.Status_At (2) = Success
               and then Race.Status_At (1) = Precondition_Failed),
            "concurrent create-if-absent did not have exactly one winner");
         declare
            Winner : constant Positive :=
              (if Race.Status_At (1) = Success then 1 else 2);
            Payload : constant String := (if Winner = 1 then "A" else "B");
         begin
            Require_State
              (Race_Key (Iteration), Payload, Race.Info_At (Winner),
               "concurrent create-if-absent winner");
         end;
      end loop;
   end Exercise;

end Conditional_Put_Conformance;
