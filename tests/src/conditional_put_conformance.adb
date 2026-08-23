with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Checksum_Engine;

package body Conditional_Put_Conformance is

   use Flyology.Object_Storage;
   use Flyology.Object_Storage.Backends;
   use type Ada.Containers.Count_Type;
   use type Ada.Calendar.Time;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Real_Time.Time;
   use type Status;
   package US renames Ada.Strings.Unbounded;
   use type US.Unbounded_String;
   package Checksum_Engine renames
     Flyology.Object_Storage.Checksum_Engine;

   Tuple_Key : constant String := "put-object-complete-tuple";

   Epoch : constant Ada.Calendar.Time :=
     Ada.Calendar.Formatting.Time_Of
       (1970, 1, 1, 0, 0, 0, Time_Zone => 0);

   function Current_Unix_Time return Unix_Time is
     (Unix_Time (Long_Long_Integer (Ada.Calendar.Clock - Epoch)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Tuple_Payload (Algorithm : Checksum_Algorithm) return String is
     ("tuple:" & Checksum_Algorithm'Image (Algorithm));

   function Expected_Checksum
     (Algorithm : Checksum_Algorithm;
      Payload   : String) return Checksum_Information
   is
      State : Checksum_Engine.Context
        (Checksum_Engine.Algorithm_Value (Algorithm));
      Data : constant Ada.Streams.Stream_Element_Array :=
        Flyology.Bytes.To_Array
          (Flyology.Bytes.From_Byte_String (Payload));
   begin
      Checksum_Engine.Update (State, Data);
      return
        (Algorithm => Algorithm,
         Method    => Full_Object_Checksum,
         Value     => US.To_Unbounded_String
           (Checksum_Engine.Finish (State)));
   end Expected_Checksum;

   function Tuple_Options
     (Algorithm : Checksum_Algorithm) return Put_Options
   is
      Result : Put_Options := Default_Put_Options;
   begin
      Result.Entity_Tag := US.To_Unbounded_String
        ("tuple-" & Checksum_Algorithm'Image (Algorithm));
      Result.Content_Type := US.To_Unbounded_String ("application/tuple");
      Result.Metadata.Cache_Control :=
        (Is_Set => True, Value => US.To_Unbounded_String ("no-cache"));
      Result.Metadata.Content_Disposition :=
        (Is_Set => True,
         Value => US.To_Unbounded_String ("attachment; filename=tuple"));
      Result.Metadata.Content_Encoding :=
        (Is_Set => True, Value => US.To_Unbounded_String ("identity"));
      Result.Metadata.Content_Language :=
        (Is_Set => True, Value => US.To_Unbounded_String ("en-CA"));
      Result.Metadata.Expires := (Is_Set => True, Value => 0);
      Result.Metadata.Website_Redirect_Location :=
        (Is_Set => True, Value => US.To_Unbounded_String ("/next"));
      Result.Metadata.User.Length := 2;
      Result.Metadata.User.Items (1) :=
        (Key   => US.To_Unbounded_String ("trace"),
         Value => US.To_Unbounded_String ("alpha"));
      Result.Metadata.User.Items (2) :=
        (Key   => US.To_Unbounded_String ("workflow"),
         Value => US.To_Unbounded_String ("put-object"));
      Result.Tags.Length := 2;
      Result.Tags.Items (1) :=
        (Key   => US.To_Unbounded_String ("stage"),
         Value => US.To_Unbounded_String ("qualified"));
      Result.Tags.Items (2) :=
        (Key   => US.To_Unbounded_String ("algorithm"),
         Value => US.To_Unbounded_String
           (Checksum_Algorithm'Image (Algorithm)));
      Result.Checksum :=
        (Algorithm => Algorithm,
         Method    => Full_Object_Checksum,
         Value     => US.Null_Unbounded_String);
      return Result;
   end Tuple_Options;

   procedure Require_Known_Info
     (Observed  : Object_Information;
      Options   : Put_Options;
      Payload   : String;
      Not_Before : Unix_Time;
      Not_After  : Unix_Time;
      Message   : String)
   is
      Expected_Digest : constant Checksum_Information :=
        Expected_Checksum (Options.Checksum.Algorithm, Payload);
   begin
      Require
        (Observed.Size = Byte_Count (Payload'Length)
         and then Observed.Modified >= Not_Before
         and then Observed.Modified <= Not_After
         and then Observed.Entity_Tag = Options.Entity_Tag
         and then Observed.Content_Type = Options.Content_Type
         and then Observed.Version = US.Null_Unbounded_String
         and then Observed.Checksum = Expected_Digest
         and then Observed.Metadata = Options.Metadata,
         Message);
   end Require_Known_Info;

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

   procedure Verify_Tuple
     (Store  : in out Backend'Class;
      Bucket : String)
   is
      Algorithm : constant Checksum_Algorithm := Checksum_XXHASH128;
      Expected  : constant Put_Options := Tuple_Options (Algorithm);
      Payload   : constant String := Tuple_Payload (Algorithm);
      Checksum  : constant Checksum_Information :=
        Expected_Checksum (Algorithm, Payload);
      Head_Info : Object_Information;
      Read_Info : Object_Information;
      Tags      : Object_Tag_Set;
      Sink      : Buffer_Sink;
      Result    : Status;
   begin
      Store.Head_Object
        (Bucket, Tuple_Key, null, Ada.Real_Time.Time_Last,
         Head_Info, Result);
      Require
        (Result = Success
         and then Head_Info.Size = Byte_Count (Payload'Length)
         and then Head_Info.Entity_Tag = Expected.Entity_Tag
         and then Head_Info.Content_Type = Expected.Content_Type
         and then Head_Info.Version = US.Null_Unbounded_String
         and then Head_Info.Metadata = Expected.Metadata
         and then Head_Info.Checksum = Checksum,
         "complete PutObject tuple head");
      Store.Get_Object
        (Bucket, Tuple_Key, Whole_Object, Sink, null,
         Ada.Real_Time.Time_Last, Read_Info, Result);
      Require
        (Result = Success
         and then Flyology.Bytes.To_Byte_String (Sink.Data) = Payload
         and then Read_Info = Head_Info,
         "complete PutObject tuple body/info snapshot");
      Store.Get_Object_Tags
        (Bucket, Tuple_Key, null, Ada.Real_Time.Time_Last, Tags, Result);
      Require
        (Result = Success and then Tags = Expected.Tags,
         "complete PutObject tuple tags");
   end Verify_Tuple;

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

   type Cancelling_Source is new Byte_Source with record
      Calls : Natural := 0;
   end record;

   overriding procedure Read
     (Item     : in out Cancelling_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Cancelling_Source) return Source_Length is
     (Kind => Known, Bytes => 8);

   overriding procedure Read
     (Item     : in out Cancelling_Source;
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
      if Token = null then
         raise Program_Error with "missing cancellation token";
      end if;
      Token.Request;
   end Read;

   protected type Deadline_Gate is
      procedure Publish_Deadline (Value : Ada.Real_Time.Time);
      procedure Arrive_At_Final_Read;
      entry Wait_For_Final_Read (Value : out Ada.Real_Time.Time);
      entry Wait_For_Release;
      procedure Release;
   private
      Deadline  : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
      Published : Boolean := False;
      Arrived   : Boolean := False;
      Released  : Boolean := False;
   end Deadline_Gate;

   protected body Deadline_Gate is
      procedure Publish_Deadline (Value : Ada.Real_Time.Time) is
      begin
         Deadline := Value;
         Published := True;
      end Publish_Deadline;

      procedure Arrive_At_Final_Read is
      begin
         Arrived := True;
      end Arrive_At_Final_Read;

      entry Wait_For_Final_Read (Value : out Ada.Real_Time.Time)
        when Published and Arrived
      is
      begin
         Value := Deadline;
      end Wait_For_Final_Read;

      entry Wait_For_Release when Released is
      begin
         null;
      end Wait_For_Release;

      procedure Release is
      begin
         Released := True;
      end Release;
   end Deadline_Gate;

   type Deadline_Gate_Access is access all Deadline_Gate;

   type Deadline_Source is new Byte_Source with record
      Gate     : Deadline_Gate_Access;
      Calls    : Natural := 0;
      Returned : Boolean := False;
   end record;

   overriding procedure Read
     (Item     : in out Deadline_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Deadline_Source) return Source_Length is
     (Kind => Known, Bytes => 8);

   overriding procedure Read
     (Item     : in out Deadline_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token);
   begin
      if Item.Calls = 0 then
         Item.Calls := 1;
         Data (Data'First .. Data'First + 3) :=
           (Character'Pos ('p'), Character'Pos ('a'),
            Character'Pos ('r'), Character'Pos ('t'));
         Last := Data'First + 3;
         Finished := False;
      elsif Item.Calls = 1 then
         Item.Calls := 2;
         Item.Gate.Arrive_At_Final_Read;
         Item.Gate.Wait_For_Release;
         if Ada.Real_Time.Clock < Deadline then
            raise Program_Error with "deadline gate released too early";
         end if;
         Data (Data'First .. Data'First + 3) :=
           (Character'Pos ('t'), Character'Pos ('a'),
            Character'Pos ('i'), Character'Pos ('l'));
         Last := Data'First + 3;
         Finished := True;
         Item.Returned := True;
      else
         raise Program_Error with
           "deadline was not observed after the final source callback";
      end if;
   end Read;

   protected type Length_Observations is
      procedure Observe;
      function Count return Natural;
   private
      Total : Natural := 0;
   end Length_Observations;

   protected body Length_Observations is
      procedure Observe is
      begin
         Total := Total + 1;
      end Observe;

      function Count return Natural is (Total);
   end Length_Observations;

   type Length_Observations_Access is access all Length_Observations;

   type Raising_Length_Source is new Byte_Source with record
      Observations : Length_Observations_Access;
   end record;

   overriding function Declared_Length
     (Item : Raising_Length_Source) return Source_Length;

   overriding procedure Read
     (Item     : in out Raising_Length_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Raising_Length_Source) return Source_Length
   is
   begin
      Item.Observations.Observe;
      return
        (raise Program_Error with
           "malformed request consumed declared length");
   end Declared_Length;

   overriding procedure Read
     (Item     : in out Raising_Length_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced
        (Item, Data, Last, Finished, Token, Deadline);
   begin
      raise Program_Error with "malformed request consumed source bytes";
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
            Content_Type => US.To_Unbounded_String ("application/test"),
            others => <>);
      begin
         Store.Put_Object
           (Bucket, Object_Key, Source, Options, null,
            Ada.Real_Time.Time_Last, Info, Result, Conditions);
      end Put;

      procedure Require_State
        (Object_Key : String;
         Payload    : String;
         Expected   : Object_Information;
         Message    : String;
         Expected_Tags : Object_Tag_Set := Empty_Object_Tags)
      is
         Sink      : Buffer_Sink;
         Bound_Sink : Buffer_Sink;
         Head_Info : Object_Information;
         Read_Info : Object_Information;
         Bound_Info : Object_Information;
         Tags      : Object_Tag_Set;
         Observed  : Status;
         Read_Conditions_Value : Read_Conditions;
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
            and then Head_Info.Version = Expected.Version
            and then Head_Info.Checksum = Expected.Checksum
            and then Head_Info.Metadata = Expected.Metadata,
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
            and then Read_Info.Version = Head_Info.Version
            and then Read_Info.Checksum = Head_Info.Checksum
            and then Read_Info.Metadata = Head_Info.Metadata,
            Message & " body/info");
         Read_Conditions_Value.If_Match := US.To_Unbounded_String
           ("""" & US.To_String (Read_Info.Entity_Tag) & """");
         Store.Get_Object
           (Bucket, Object_Key, Whole_Object, Bound_Sink, null,
            Ada.Real_Time.Time_Last, Bound_Info, Observed,
            Read_Conditions_Value);
         Require
           (Observed = Success
            and then Flyology.Bytes.To_Byte_String (Bound_Sink.Data) =
              Payload
            and then Bound_Info.Size = Read_Info.Size
            and then Bound_Info.Modified = Read_Info.Modified
            and then Bound_Info.Entity_Tag = Read_Info.Entity_Tag
            and then Bound_Info.Content_Type = Read_Info.Content_Type
            and then Bound_Info.Version = Read_Info.Version
            and then Bound_Info.Checksum = Read_Info.Checksum
            and then Bound_Info.Metadata = Read_Info.Metadata,
            Message & " generation-bound body/info");
         Store.Get_Object_Tags
           (Bucket, Object_Key, null, Ada.Real_Time.Time_Last,
            Tags, Observed);
         Require
           (Observed = Success and then Tags = Expected_Tags,
            Message & " tags");
      end Require_State;

      function Race_Options (Index : Positive) return Put_Options is
         Options : Put_Options := Default_Put_Options;
      begin
         Options.Entity_Tag := US.To_Unbounded_String
           ("race-" &
            Ada.Strings.Fixed.Trim
              (Positive'Image (Index), Ada.Strings.Both));
         Options.Content_Type := US.To_Unbounded_String ("application/race");
         Options.Metadata.Cache_Control :=
           (Is_Set => True,
            Value => US.To_Unbounded_String
              ("race-" &
               Ada.Strings.Fixed.Trim
                 (Positive'Image (Index), Ada.Strings.Both)));
         Options.Tags.Length := 1;
         Options.Tags.Items (1) :=
           (Key   => US.To_Unbounded_String ("winner"),
            Value => US.To_Unbounded_String
              (Positive'Image (Index)));
         Options.Checksum :=
           (Algorithm =>
              (if Index = 1 then Checksum_CRC32 else Checksum_SHA256),
            Method => Full_Object_Checksum,
            Value  => US.Null_Unbounded_String);
         return Options;
      end Race_Options;

      procedure Require_Stale_Read
        (Object_Key, Entity_Tag, Message : String)
      is
         Sink : Buffer_Sink;
         Read_Info : Object_Information;
         Observed : Status;
         Conditions : Read_Conditions;
      begin
         Conditions.If_Match := US.To_Unbounded_String (Entity_Tag);
         Store.Get_Object
           (Bucket, Object_Key, Whole_Object, Sink, null,
            Ada.Real_Time.Time_Last, Read_Info, Observed, Conditions);
         Require
           (Observed = Precondition_Failed
            and then Flyology.Bytes.Length (Sink.Data) = 0,
            Message);
      end Require_Stale_Read;

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
            Options : constant Put_Options := Race_Options (Index);
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

      procedure Expect_Post_Callback_Deadline
        (Upload_ID : String := "")
      is
         Gate       : aliased Deadline_Gate;
         Raised     : Boolean := False;
         Calls      : Natural := 0;
         Returned   : Boolean := False;
         Unexpected : Boolean := False;
      begin
         declare
            task Writer;

            task body Writer is
               Deadline : constant Ada.Real_Time.Time :=
                 Ada.Real_Time."+"
                   (Ada.Real_Time.Clock, Ada.Real_Time.Seconds (1));
               Source : Deadline_Source :=
                 (Gate => Gate'Unchecked_Access,
                  Calls => 0,
                  Returned => False);
               Local_Info   : Object_Information;
               Local_Result : Status;
            begin
               Gate.Publish_Deadline (Deadline);
               begin
                  if Upload_ID'Length = 0 then
                     Store.Put_Object
                       (Bucket, Key, Source, Default_Put_Options, null,
                        Deadline, Local_Info, Local_Result, Conditions);
                  else
                     Store.Put_Multipart_Part
                       (Bucket, "conditional-multipart", Upload_ID, 1,
                        Source, Default_Multipart_Part_Options, null,
                        Deadline, Local_Info, Local_Result);
                  end if;
               exception
                  when Flyology.IO.Timeout_Error => Raised := True;
                  when others => Unexpected := True;
               end;
               Calls := Source.Calls;
               Returned := Source.Returned;
            end Writer;
            Observed_Deadline : Ada.Real_Time.Time;
         begin
            select
               Gate.Wait_For_Final_Read (Observed_Deadline);
            or
               delay 3.0;
               Gate.Release;
               raise Program_Error with
                 "conditional write did not reach final source callback";
            end select;
            delay until Observed_Deadline;
            Gate.Release;
         end;
         Require
           (Raised and then not Unexpected
            and then Calls = 2 and then Returned,
            "post-callback deadline did not stop conditional write");
      end Expect_Post_Callback_Deadline;
   begin
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "conditional put bucket setup");

      declare
         Observations : aliased Length_Observations;
         Source : Raising_Length_Source :=
           (Observations => Observations'Unchecked_Access);
      begin
         Store.Put_Object
           (Bucket, "", Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Require
           (Result = Invalid_Request and then Observations.Count = 0,
            "malformed put invoked Declared_Length");
         Store.Put_Multipart_Part
           (Bucket, "", "missing-upload", 1, Source,
            Default_Multipart_Part_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Require
           (Result = Invalid_Request and then Observations.Count = 0,
            "malformed multipart put invoked Declared_Length");
      end;

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
      Require_Stale_Read
        (Key, """generation-1""",
         "stale generation-bound whole Get succeeded");

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
         Source : Cancelling_Source;
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

      Expect_Post_Callback_Deadline;
      Require_State (Key, "third", Current, "mid-stream deadline rollback");

      declare
         Upload_ID  : US.Unbounded_String;
         Prior      : Object_Information;
         Page       : Multipart_Part_Page;
         Source     : Buffer_Source :=
           (Data => Flyology.Bytes.From_Byte_String ("prior"),
            Position => 0);
      begin
         Store.Create_Multipart_Upload
           (Bucket, "conditional-multipart", Default_Multipart_Options,
            null, Ada.Real_Time.Time_Last, Upload_ID, Result);
         Require (Result = Success, "deadline multipart setup");
         Store.Put_Multipart_Part
           (Bucket, "conditional-multipart", US.To_String (Upload_ID), 1,
            Source, Default_Multipart_Part_Options, null,
            Ada.Real_Time.Time_Last, Prior, Result);
         Require (Result = Success, "deadline multipart prior part");
         Expect_Post_Callback_Deadline (US.To_String (Upload_ID));
         Store.List_Multipart_Parts
           (Bucket, "conditional-multipart", US.To_String (Upload_ID),
            (others => <>), null, Ada.Real_Time.Time_Last, Page, Result);
         Require
           (Result = Success and then Page.Parts.Length = 1
            and then Page.Parts.First_Element.Number = 1
            and then Page.Parts.First_Element.Info.Size = Prior.Size
            and then Page.Parts.First_Element.Info.Entity_Tag =
              Prior.Entity_Tag,
            "deadline multipart failure replaced the prior part");
         Store.Abort_Multipart_Upload
           (Bucket, "conditional-multipart", US.To_String (Upload_ID),
            No_Abort_Multipart_Conditions, null,
            Ada.Real_Time.Time_Last, Result);
         Require (Result = Success, "deadline multipart cleanup");
      end;

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

      for Algorithm in Checksum_CRC32 .. Checksum_XXHASH128 loop
         declare
            Payload : constant String := Tuple_Payload (Algorithm);
            Options : constant Put_Options := Tuple_Options (Algorithm);
            Source  : Buffer_Source :=
              (Data     => Flyology.Bytes.From_Byte_String (Payload),
               Position => 0);
            Tuple_Info : Object_Information;
            Not_Before : constant Unix_Time := Current_Unix_Time;
            Not_After  : Unix_Time;
         begin
            Store.Put_Object
              (Bucket, Tuple_Key, Source, Options, null,
               Ada.Real_Time.Time_Last, Tuple_Info, Result);
            Not_After := Current_Unix_Time;
            Require
              (Result = Success,
               "complete PutObject direct checksum " &
                 Checksum_Algorithm'Image (Algorithm));
            Require_Known_Info
              (Tuple_Info, Options, Payload, Not_Before, Not_After,
               "complete PutObject exact returned tuple " &
                 Checksum_Algorithm'Image (Algorithm));
            Require_State
              (Tuple_Key, Payload, Tuple_Info,
               "complete PutObject tuple " &
                 Checksum_Algorithm'Image (Algorithm),
               Options.Tags);
         end;
      end loop;
      Verify_Tuple (Store, Bucket);

      declare
         Source     : Adversarial_Source (Raise_After_Chunk);
         Raised     : Boolean := False;
         Prior_Info : Object_Information;
         After_Info : Object_Information;
      begin
         Store.Head_Object
           (Bucket, Tuple_Key, null, Ada.Real_Time.Time_Last,
            Prior_Info, Result);
         Require
           (Result = Success,
            "complete PutObject tuple pre-failure snapshot");
         begin
            Store.Put_Object
              (Bucket, Tuple_Key, Source,
               Tuple_Options (Checksum_CRC32), null,
               Ada.Real_Time.Time_Last, Info, Result);
         exception
            when Program_Error => Raised := True;
         end;
         Require
           (Raised, "complete PutObject tuple source failure was swallowed");
         Store.Head_Object
           (Bucket, Tuple_Key, null, Ada.Real_Time.Time_Last,
            After_Info, Result);
         Require
           (Result = Success and then After_Info = Prior_Info,
            "complete PutObject source failure changed object information");
         Verify_Tuple (Store, Bucket);
      end;

      for Iteration in 1 .. Race_Iterations loop
         Race.Reset;
         declare
            Not_Before : constant Unix_Time := Current_Unix_Time;
         begin
            declare
               Gate : aliased Publication_Race_Gate;
               One : Writer
                 (1, Iteration, Gate'Unchecked_Access,
                  Store'Unchecked_Access);
               Two : Writer
                 (2, Iteration, Gate'Unchecked_Access,
                  Store'Unchecked_Access);
            begin
               null;
            end;
            declare
               Not_After : constant Unix_Time := Current_Unix_Time;
            begin
               Require
                 ((Race.Status_At (1) = Success
                   and then Race.Status_At (2) = Precondition_Failed)
                  or else
                    (Race.Status_At (2) = Success
                     and then Race.Status_At (1) = Precondition_Failed),
                  "concurrent create-if-absent did not have exactly " &
                    "one winner");
               declare
                  Winner : constant Positive :=
                    (if Race.Status_At (1) = Success then 1 else 2);
                  Payload : constant String :=
                    (if Winner = 1 then "A" else "B");
                  Options : constant Put_Options := Race_Options (Winner);
               begin
                  Require_Known_Info
                    (Race.Info_At (Winner), Options, Payload,
                     Not_Before, Not_After,
                     "concurrent create-if-absent returned tuple");
                  Require_State
                    (Race_Key (Iteration), Payload, Race.Info_At (Winner),
                     "concurrent create-if-absent winner",
                     Options.Tags);
               end;
            end;
         end;
      end loop;
   end Exercise;

end Conditional_Put_Conformance;
