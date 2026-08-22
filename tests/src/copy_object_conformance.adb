with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.IO;
with Flyology.Object_Storage;

package body Copy_Object_Conformance is

   use Flyology.Object_Storage;
   use Flyology.Object_Storage.Backends;
   use type Ada.Streams.Stream_Element_Offset;
   use type Status;
   package US renames Ada.Strings.Unbounded;

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
      Deadline       : Ada.Real_Time.Time) is
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

   type Backend_Access is access all Backend'Class;

   protected type Start_Gate is
      entry Wait;
      procedure Release;
   private
      Open : Boolean := False;
   end Start_Gate;

   protected body Start_Gate is
      entry Wait when Open is
      begin
         null;
      end Wait;

      procedure Release is
      begin
         Open := True;
      end Release;
   end Start_Gate;

   type Start_Gate_Access is access all Start_Gate;

   protected type Race_Results is
      procedure Record_Copy (Value : Status);
      procedure Record_Mutation (Value : Status);
      entry Wait_For_Both
        (Copy_Result_Value, Mutation_Result_Value : out Status);
   private
      Copy_Value     : Status := Backend_Unavailable;
      Mutation_Value : Status := Backend_Unavailable;
      Completed      : Natural range 0 .. 2 := 0;
   end Race_Results;

   protected body Race_Results is
      procedure Record_Copy (Value : Status) is
      begin
         Copy_Value := Value;
         Completed := Completed + 1;
      end Record_Copy;

      procedure Record_Mutation (Value : Status) is
      begin
         Mutation_Value := Value;
         Completed := Completed + 1;
      end Record_Mutation;

      entry Wait_For_Both
        (Copy_Result_Value, Mutation_Result_Value : out Status)
        when Completed = 2 is
      begin
         Copy_Result_Value := Copy_Value;
         Mutation_Result_Value := Mutation_Value;
      end Wait_For_Both;
   end Race_Results;

   type Race_Results_Access is access all Race_Results;
   type Mutation_Kind is (Overwrite_Source, Delete_Source);

   procedure Exercise
     (Store           : in out Backend'Class;
      Bucket          : String;
      Race_Iterations : Positive := 16)
   is
      Source_Key : constant String := "copy-source";
      Destination_Key : constant String := "copy-destination";
      Race_Source_Key : constant String := "copy-race-source";
      Race_Destination_Key : constant String := "copy-race-destination";
      Large_A : constant String (1 .. 128 * 1_024) := (others => 'A');
      Large_B : constant String (1 .. 128 * 1_024) := (others => 'B');
      Info   : Object_Information;
      Result : Status;

      procedure Put
        (Key          : String;
         Payload      : String;
         Content_Type : String;
         ETag         : String;
         Info         : out Object_Information;
         Result       : out Status)
      is
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0);
         Options : constant Put_Options :=
           (Entity_Tag   => US.To_Unbounded_String (ETag),
            Content_Type => US.To_Unbounded_String (Content_Type));
      begin
         Store.Put_Object
           (Bucket, Key, Source, Options, null, Ada.Real_Time.Time_Last,
            Info, Result);
      end Put;

      function Read_Body
        (Key      : String;
         Observed : out Status;
         Snapshot : out Object_Information) return String is
         Sink : Buffer_Sink;
      begin
         Store.Get_Object
           (Bucket, Key, Whole_Object, Sink, null,
            Ada.Real_Time.Time_Last, Snapshot, Observed);
         return Flyology.Bytes.To_Byte_String (Sink.Data);
      end Read_Body;

      procedure Require_State
        (Key, Payload, Content_Type : String; Message : String)
      is
         Observed : Status;
         Snapshot : Object_Information;
         Value : constant String := Read_Body (Key, Observed, Snapshot);
      begin
         Require
           (Observed = Success
            and then Value = Payload
            and then US.To_String (Snapshot.Content_Type) = Content_Type,
            Message);
      end Require_State;

      task type Copier
        (Gate      : Start_Gate_Access;
         Outcomes  : Race_Results_Access;
         Target    : Backend_Access;
         Same_Key  : Boolean);

      task body Copier is
         Options : Copy_Options := Default_Copy_Options;
         Local_Info : Object_Information;
         Local_Result : Status;
      begin
         if Same_Key then
            Options.Metadata_Directive := Replace_Metadata;
            Options.Content_Type := US.To_Unbounded_String ("copy/race");
         end if;
         Gate.Wait;
         Target.Copy_Object
           (Bucket, Race_Source_Key, Bucket,
            (if Same_Key then Race_Source_Key else Race_Destination_Key),
            Options, null, Ada.Real_Time.Time_Last,
            Local_Info, Local_Result);
         Outcomes.Record_Copy (Local_Result);
      exception
         when others =>
            Outcomes.Record_Copy (Backend_Unavailable);
      end Copier;

      task type Mutator
        (Gate     : Start_Gate_Access;
         Outcomes : Race_Results_Access;
         Target   : Backend_Access;
         Kind     : Mutation_Kind);

      task body Mutator is
         Local_Info : Object_Information;
         Local_Result : Status;
         Source : Buffer_Source :=
           (Data => Flyology.Bytes.From_Byte_String (Large_B), Position => 0);
         Options : constant Put_Options :=
           (Entity_Tag => US.To_Unbounded_String ("race-b"),
            Content_Type => US.To_Unbounded_String ("writer/race"));
      begin
         Gate.Wait;
         if Kind = Delete_Source then
            Target.Delete_Object
              (Bucket, Race_Source_Key, null, Ada.Real_Time.Time_Last,
               Local_Result);
         else
            Target.Put_Object
              (Bucket, Race_Source_Key, Source, Options, null,
               Ada.Real_Time.Time_Last, Local_Info, Local_Result);
         end if;
         Outcomes.Record_Mutation (Local_Result);
      exception
         when others =>
            Outcomes.Record_Mutation (Backend_Unavailable);
      end Mutator;

      Source_Info : Object_Information;
      Destination_Info : Object_Information;
      Options : Copy_Options := Default_Copy_Options;
      Copy_Race_Result : Status;
      Mutation_Race_Result : Status;
   begin
      Store.Create_Bucket (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "CopyObject bucket setup failed");
      Put
        (Source_Key, "source-body", "source/type", "source-etag",
         Source_Info, Result);
      Require (Result = Success, "CopyObject source setup failed");

      Store.Copy_Object
        (Bucket, Source_Key, Bucket, Destination_Key, Options, null,
         Ada.Real_Time.Time_Last, Destination_Info, Result);
      Require (Result = Success, "ordinary CopyObject failed");
      Require_State
        (Destination_Key, "source-body", "source/type",
         "ordinary CopyObject did not preserve one snapshot");

      Options.Conditions.If_Match := US.To_Unbounded_String
        ('"' & US.To_String (Source_Info.Entity_Tag) & '"');
      Options.Conditions.If_Unmodified_Since :=
        (Is_Set => True,
         Value => Long_Long_Integer (Source_Info.Modified) - 1);
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, Destination_Key, Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Success,
         "source If-Match did not override If-Unmodified-Since");

      Options.Conditions := Default_Copy_Conditions;
      Options.Conditions.If_None_Match := US.To_Unbounded_String
        ("W/""source-etag""");
      Options.Conditions.If_Modified_Since :=
        (Is_Set => True,
         Value => Long_Long_Integer (Source_Info.Modified) - 1);
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, Destination_Key, Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Precondition_Failed,
         "source If-None-Match did not override If-Modified-Since");
      Require_State
        (Destination_Key, "source-body", "source/type",
         "failed source condition changed the destination");

      Options.Conditions := Default_Copy_Conditions;
      Options.Conditions.If_Match := US.To_Unbounded_String ("bare");
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, Destination_Key, Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Invalid_Request, "malformed source ETag accepted");
      Store.Copy_Object
        (Bucket, "missing-copy-source", Bucket, Destination_Key, Options,
         null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Invalid_Request,
         "malformed source ETag was not rejected before source lookup");

      Options := Default_Copy_Options;
      Options.Destination_Conditions.If_Match :=
        US.To_Unbounded_String ("bare");
      Store.Copy_Object
        (Bucket, "missing-copy-source", Bucket, Destination_Key, Options,
         null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Invalid_Request,
         "malformed destination ETag was not rejected before source lookup");

      Options := Default_Copy_Options;
      Options.Destination_Conditions.If_None_Match :=
        US.To_Unbounded_String ("*");
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, "copy-create-only", Options, null,
         Ada.Real_Time.Time_Last, Destination_Info, Result);
      Require (Result = Success, "destination If-None-Match create failed");
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, "copy-create-only", Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Precondition_Failed,
         "destination If-None-Match replaced an object");

      Options := Default_Copy_Options;
      Options.Destination_Conditions.If_Match := US.To_Unbounded_String
        ('"' & US.To_String (Destination_Info.Entity_Tag) & '"');
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, "copy-create-only", Options, null,
         Ada.Real_Time.Time_Last, Destination_Info, Result);
      Require (Result = Success, "matching destination If-Match failed");
      Options.Destination_Conditions.If_Match :=
        US.To_Unbounded_String ("""stale""");
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, "copy-create-only", Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Precondition_Failed,
         "stale destination If-Match replaced an object");

      Options := Default_Copy_Options;
      Store.Copy_Object
        ("missing-copy-source-bucket", Source_Key, Bucket, Destination_Key,
         Options, null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Source_Bucket_Not_Found,
         "missing source bucket was reported as a missing key");
      Store.Copy_Object
        (Bucket, "missing-copy-source", Bucket, Destination_Key,
         Options, null, Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Source_Not_Found, "missing source key mismatch");
      Store.Copy_Object
        (Bucket, Source_Key, "missing-copy-destination", Destination_Key,
         Options, null, Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Not_Found, "missing destination bucket mismatch");

      Store.Copy_Object
        (Bucket, Source_Key, Bucket, Source_Key, Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Invalid_Request,
         "metadata-preserving same-key CopyObject was accepted");
      Options.Metadata_Directive := Replace_Metadata;
      Options.Content_Type := US.To_Unbounded_String ("replaced/type");
      Store.Copy_Object
        (Bucket, Source_Key, Bucket, Source_Key, Options, null,
         Ada.Real_Time.Time_Last, Source_Info, Result);
      Require (Result = Success, "same-key metadata replacement failed");
      Require_State
        (Source_Key, "source-body", "replaced/type",
         "same-key replacement did not preserve exact bytes");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.Copy_Object
              (Bucket, Source_Key, Bucket, Destination_Key,
               Default_Copy_Options, Cancel'Access,
               Ada.Real_Time.Time_Last, Info, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled => Raised := True;
         end;
         Require (Raised, "CopyObject ignored pre-start cancellation");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            Store.Copy_Object
              (Bucket, Source_Key, Bucket, Destination_Key,
               Default_Copy_Options, null, Ada.Real_Time.Time_First,
               Info, Result);
         exception
            when Flyology.IO.Timeout_Error => Raised := True;
         end;
         Require (Raised, "CopyObject ignored an expired deadline");
      end;
      Require_State
        (Destination_Key, "source-body", "source/type",
         "cancelled or expired CopyObject changed the destination");

      for Iteration in 1 .. Race_Iterations loop
         Put
           (Race_Source_Key, Large_A, "source/race", "race-a",
            Info, Result);
         Require (Result = Success, "CopyObject race source reset failed");
         Put
           (Race_Destination_Key, "sentinel", "sentinel/type", "sentinel",
            Info, Result);
         Require
           (Result = Success, "CopyObject race destination reset failed");
         declare
            Gate : aliased Start_Gate;
            Outcomes : aliased Race_Results;
            Copy_Task : Copier
              (Gate'Unchecked_Access, Outcomes'Unchecked_Access,
               Store'Unchecked_Access, False);
            Mutation_Task : Mutator
              (Gate'Unchecked_Access, Outcomes'Unchecked_Access,
               Store'Unchecked_Access,
               (if Iteration mod 2 = 0
                then Delete_Source else Overwrite_Source));
         begin
            Gate.Release;
            Outcomes.Wait_For_Both
              (Copy_Race_Result, Mutation_Race_Result);
         end;
         Require
           (Mutation_Race_Result = Success,
            "concurrent CopyObject source mutation failed");
         if Copy_Race_Result = Success then
            declare
               Observed : Status;
               Snapshot : Object_Information;
               Value : constant String := Read_Body
                 (Race_Destination_Key, Observed, Snapshot);
               Content_Type : constant String :=
                 US.To_String (Snapshot.Content_Type);
            begin
               Require
                 (Observed = Success
                  and then
                    ((Value = Large_A and then Content_Type = "source/race")
                     or else
                       (Value = Large_B
                        and then Content_Type = "writer/race")),
                  "CopyObject combined body and metadata snapshots");
            end;
         else
            Require
              (Copy_Race_Result = Source_Not_Found,
               "source race returned an unexpected CopyObject status");
            Require_State
              (Race_Destination_Key, "sentinel", "sentinel/type",
               "failed source race changed the destination");
         end if;

         Put
           (Race_Source_Key, Large_A, "source/race", "race-a",
            Info, Result);
         Require (Result = Success, "same-key race reset failed");
         declare
            Gate : aliased Start_Gate;
            Outcomes : aliased Race_Results;
            Copy_Task : Copier
              (Gate'Unchecked_Access, Outcomes'Unchecked_Access,
               Store'Unchecked_Access, True);
            Mutation_Task : Mutator
              (Gate'Unchecked_Access, Outcomes'Unchecked_Access,
               Store'Unchecked_Access, Overwrite_Source);
         begin
            Gate.Release;
            Outcomes.Wait_For_Both
              (Copy_Race_Result, Mutation_Race_Result);
         end;
         Require
           (Copy_Race_Result = Success
            and then Mutation_Race_Result = Success,
            "same-key CopyObject race did not publish both operations");
         declare
            Observed : Status;
            Snapshot : Object_Information;
            Value : constant String := Read_Body
              (Race_Source_Key, Observed, Snapshot);
            Content_Type : constant String :=
              US.To_String (Snapshot.Content_Type);
         begin
            Require
              (Observed = Success
               and then
                 ((Value = Large_A and then Content_Type = "copy/race")
                  or else
                    (Value = Large_B
                     and then Content_Type in "copy/race" | "writer/race")),
               "same-key CopyObject mixed publication body and metadata");
         end;
      end loop;
   end Exercise;

end Copy_Object_Conformance;
