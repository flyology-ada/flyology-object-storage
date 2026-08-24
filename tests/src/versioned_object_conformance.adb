with Ada.Containers;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.Object_Storage;

package body Versioned_Object_Conformance is

   use Flyology.Object_Storage;
   use Flyology.Object_Storage.Backends;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
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
      Data  : Flyology.Bytes.Unbounded_Bytes;
      Began : Boolean := False;
   end record;

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
        (Info, First, Content_Length, Partial, Token, Deadline);
   begin
      Item.Began := True;
      Flyology.Bytes.Clear (Item.Data);
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

   procedure Exercise
     (Store  : in out Backend'Class;
      Bucket : String)
   is
      Result : Status;
      Info   : Object_Information;
      Legacy : Object_Information;
      V1     : Object_Information;
      V2     : Object_Information;
      V3     : Object_Information;
      Nested : Object_Information;
      Page   : List_Versions_Page;
      Delete_Outcome : Version_Delete_Outcome;

      procedure Put
        (Key, Payload : String;
         Stored       : out Object_Information;
         Conditions   : Write_Conditions := Default_Write_Conditions)
      is
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0);
      begin
         Store.Put_Object
           (Bucket, Key, Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Stored, Result, Conditions);
      end Put;

      procedure Require_Body
        (Key, Payload : String; Selector : Version_Selector)
      is
         Sink : Buffer_Sink;
      begin
         Store.Get_Object
           (Bucket, Key, Whole_Object, Sink, null,
            Ada.Real_Time.Time_Last, Info, Result,
            Selector => Selector);
         Require
           (Result = Success and then Sink.Began
            and then Flyology.Bytes.To_Byte_String (Sink.Data) = Payload,
            "version-addressed body mismatch: " & Payload);
      end Require_Body;

      function Exact (Value : Object_Information) return Version_Selector is
        ((Kind => Exact_Version, ID => Value.Version));

      function Version_At (Index : Positive) return String is
        (US.To_String (Page.Entries (Index).Version_ID));
   begin
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "versioning bucket setup");

      Put ("alpha", "legacy", Legacy);
      Require
        (Result = Success and then US.Length (Legacy.Version) = 0,
         "unconfigured PutObject version identity");
      Store.List_Object_Versions
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page,
         Result);
      Require
        (Result = Success and then Page.Entries.Length = 1
         and then Version_At (1) = "null"
         and then Page.Entries (1).Is_Latest,
         "unconfigured null version listing");

      Store.Delete_Selected_Object
        (Bucket, "alpha", Current_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Object_Version_Removed
         and then not Delete_Outcome.Has_Version_ID,
         "unconfigured selected delete");
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Not_Found,
         "unconfigured selected delete retained data");
      Put ("alpha", "legacy", Legacy);
      Require (Result = Success, "restore unconfigured null generation");

      Store.Put_Bucket_Versioning
        (Bucket, (Status => Versioning_Enabled, others => <>), null,
         Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "enable versioning");

      Put ("alpha", "v1", V1);
      Require (Result = Success, "first enabled PutObject");
      Put ("alpha", "v2", V2);
      Require (Result = Success, "second enabled PutObject");
      Put ("alpha", "v2", V3);
      Require (Result = Success, "identical enabled PutObject");
      Require
        (US.Length (V1.Version) > 0
         and then US.Length (V1.Version) <= Maximum_Version_ID_Length
         and then V1.Version /= V2.Version
         and then V2.Version /= V3.Version
         and then V1.Version /= V3.Version,
         "enabled version IDs are not bounded and unique");

      Require_Body ("alpha", "legacy", Null_Version_Selector);
      Require_Body ("alpha", "v1", Exact (V1));
      Require_Body ("alpha", "v2", Exact (V2));
      Require_Body ("alpha", "v2", Exact (V3));
      Require_Body ("alpha", "v2", Current_Version_Selector);

      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector => Exact (V1));
      Require
        (Result = Success and then Info.Version = V1.Version,
         "exact HeadObject generation");

      declare
         Tags : Object_Tag_Set;
         V1_Tags : Object_Tag_Set := Empty_Object_Tags;
      begin
         V1_Tags.Length := 1;
         V1_Tags.Items (1) :=
           (Key => US.To_Unbounded_String ("generation"),
            Value => US.To_Unbounded_String ("v1"));
         Store.Put_Object_Tags
           (Bucket, "alpha", V1_Tags, null, Ada.Real_Time.Time_Last,
            Result, Exact (V1));
         Require (Result = Success, "exact-version PutObjectTagging");
         Store.Get_Object_Tags
           (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Tags, Result,
            Exact (V1));
         Require
           (Result = Success and then Tags = V1_Tags,
            "exact-version GetObjectTagging");
         Store.Get_Object_Tags
           (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Tags, Result,
            Exact (V2));
         Require
           (Result = Success and then Tags = Empty_Object_Tags,
            "version tag isolation");
      end;

      Store.List_Object_Versions
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page,
         Result);
      Require
        (Result = Success and then Page.Entries.Length = 4
         and then Version_At (1) = US.To_String (V3.Version)
         and then Version_At (2) = US.To_String (V2.Version)
         and then Version_At (3) = US.To_String (V1.Version)
         and then Version_At (4) = "null"
         and then Page.Entries (1).Is_Latest
         and then not Page.Entries (2).Is_Latest
         and then not Page.Entries (3).Is_Latest
         and then not Page.Entries (4).Is_Latest,
         "newest-first complete version listing");

      declare
         Options : List_Versions_Options := (others => <>);
         Seen    : Natural := 0;
      begin
         Options.Maximum := 1;
         loop
            Store.List_Object_Versions
              (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
            Require
              (Result = Success and then Page.Entries.Length = 1,
               "single-entry version page");
            Seen := Seen + 1;
            Require
              ((case Seen is
                  when 1 => Version_At (1) = US.To_String (V3.Version),
                  when 2 => Version_At (1) = US.To_String (V2.Version),
                  when 3 => Version_At (1) = US.To_String (V1.Version),
                  when 4 => Version_At (1) = "null",
                  when others => False),
               "version cursor repeated or reordered a generation");
            exit when not Page.Is_Truncated;
            Options.Has_Key_Marker := True;
            Options.Key_Marker := Page.Next_Key_Marker;
            Options.Has_Version_ID_Marker := True;
            Options.Version_ID_Marker := Page.Next_Version_ID_Marker;
         end loop;
         Require (Seen = 4, "paired cursor did not visit every generation");
      end;

      declare
         Options : List_Versions_Options := (others => <>);
      begin
         Options.Maximum := 0;
         Store.List_Object_Versions
           (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Require
           (Result = Success and then Page.Entries.Is_Empty
            and then not Page.Is_Truncated,
            "zero-size version page");

         Options := (others => <>);
         Options.Has_Version_ID_Marker := True;
         Options.Version_ID_Marker := V1.Version;
         Store.List_Object_Versions
           (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Require (Result = Invalid_Request, "unpaired version cursor");

         Options.Has_Key_Marker := True;
         Options.Key_Marker := US.To_Unbounded_String ("alpha");
         Options.Version_ID_Marker := US.To_Unbounded_String ("unknown");
         Store.List_Object_Versions
           (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Require (Result = Invalid_Request, "unknown exact version cursor");
      end;

      Store.Put_Bucket_Versioning
        (Bucket, (Status => Versioning_Suspended, others => <>), null,
         Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "suspend versioning");
      Put ("alpha", "null-one", Info);
      Require
        (Result = Success and then US.Length (Info.Version) = 0,
         "first suspended null PutObject");
      Put ("alpha", "null-two", Info);
      Require
        (Result = Success and then US.Length (Info.Version) = 0,
         "replacement suspended null PutObject");
      Require_Body ("alpha", "null-two", Null_Version_Selector);
      Require_Body ("alpha", "null-two", Current_Version_Selector);
      Require_Body ("alpha", "v1", Exact (V1));

      Store.List_Object_Versions
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page,
         Result);
      Require
        (Result = Success and then Page.Entries.Length = 4
         and then Version_At (1) = "null"
         and then Page.Entries (1).Is_Latest
         and then Version_At (2) = US.To_String (V3.Version),
         "suspended null replacement and retained history");

      Store.Delete_Selected_Object
        (Bucket, "alpha", Current_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Delete_Marker_Created
         and then Delete_Outcome.Has_Version_ID
         and then Delete_Outcome.Is_Null_Version
         and then US.Length (Delete_Outcome.Version_ID) = 0,
         "suspended current delete marker publication");
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Not_Found, "suspended marker did not hide current");
      Require_Body ("alpha", "v1", Exact (V1));
      Store.List_Object_Versions
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page,
         Result);
      Require
        (Result = Success and then Page.Entries.Length = 4
         and then Page.Entries (1).Is_Delete_Marker
         and then Page.Entries (1).Is_Latest
         and then Version_At (1) = "null",
         "suspended null marker listing");

      Store.Delete_Selected_Object
        (Bucket, "alpha", Current_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Delete_Marker_Created
         and then Delete_Outcome.Is_Null_Version,
         "repeated suspended current delete marker replacement");
      Store.List_Object_Versions
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page,
         Result);
      Require
        (Result = Success and then Page.Entries.Length = 4
         and then Page.Entries (1).Is_Delete_Marker
         and then Page.Entries (1).Is_Latest
         and then Version_At (1) = "null",
         "repeated suspended delete accumulated null markers");

      Store.Delete_Selected_Object
        (Bucket, "alpha", Null_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Delete_Marker_Removed
         and then Delete_Outcome.Has_Version_ID
         and then Delete_Outcome.Is_Null_Version,
         "exact null delete marker removal");
      Require_Body ("alpha", "v2", Current_Version_Selector);

      Store.Put_Bucket_Versioning
        (Bucket, (Status => Versioning_Enabled, others => <>), null,
         Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "re-enable versioning for marker history");
      Store.Delete_Selected_Object
        (Bucket, "alpha", Current_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Delete_Marker_Created
         and then Delete_Outcome.Has_Version_ID
         and then not Delete_Outcome.Is_Null_Version,
         "enabled current delete marker publication");
      declare
         First_Marker : constant Version_Selector :=
           (Kind => Exact_Version, ID => Delete_Outcome.Version_ID);
         First_ID : constant US.Unbounded_String :=
           Delete_Outcome.Version_ID;
      begin
         Store.Delete_Selected_Object
           (Bucket, "alpha", Current_Version_Selector,
            No_Delete_Object_Conditions, False, null,
            Ada.Real_Time.Time_Last, Delete_Outcome, Result);
         Require
           (Result = Success
            and then Delete_Outcome.Kind = Delete_Marker_Created
            and then Delete_Outcome.Version_ID /= First_ID,
            "repeated enabled delete marker identity");
         declare
            Second_Marker : constant Version_Selector :=
              (Kind => Exact_Version, ID => Delete_Outcome.Version_ID);
         begin
            Store.Delete_Selected_Object
              (Bucket, "alpha", First_Marker,
               No_Delete_Object_Conditions, False, null,
               Ada.Real_Time.Time_Last, Delete_Outcome, Result);
            Require
              (Result = Success
               and then Delete_Outcome.Kind = Delete_Marker_Removed,
               "noncurrent exact marker removal");
            Store.Head_Object
              (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info,
               Result);
            Require
              (Result = Not_Found,
               "removing noncurrent marker exposed object");
            Store.Delete_Selected_Object
              (Bucket, "alpha", Second_Marker,
               No_Delete_Object_Conditions, False, null,
               Ada.Real_Time.Time_Last, Delete_Outcome, Result);
            Require
              (Result = Success
               and then Delete_Outcome.Kind = Delete_Marker_Removed,
               "current exact marker removal");
         end;
      end;
      Require_Body ("alpha", "v2", Current_Version_Selector);

      Store.Delete_Selected_Object
        (Bucket, "alpha", Exact (V2),
         (Has_ETag => True,
          ETag => US.To_Unbounded_String ("""mismatch"""),
          others => <>),
         False, null, Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Precondition_Failed,
         "exact generation conditional delete mismatch");
      Require_Body ("alpha", "v2", Exact (V2));
      Store.Delete_Selected_Object
        (Bucket, "alpha", Exact (V2), No_Delete_Object_Conditions,
         False, null, Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Object_Version_Removed
         and then Delete_Outcome.Version_ID = V2.Version,
         "exact object generation removal");
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector => Exact (V2));
      Require (Result = Not_Found, "removed exact generation remains visible");

      Store.Delete_Selected_Object
        (Bucket, "alpha",
         (Kind => Exact_Version,
          ID => US.To_Unbounded_String ("missing-generation")),
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = No_Version_Removed
         and then Delete_Outcome.Has_Version_ID,
         "missing exact deletion is not idempotent");

      Store.Put_Bucket_Versioning
        (Bucket,
         (Status => Versioning_Unconfigured,
          MFA_Delete => MFA_Delete_Enabled),
         null, Ada.Real_Time.Time_Last, Result, MFA_Validated => True);
      Require (Result = Success, "enable MFA Delete for exact generation");
      Store.Delete_Selected_Object
        (Bucket, "alpha", Exact (V1), No_Delete_Object_Conditions,
         False, null, Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require (Result = Access_Denied, "MFA Delete admitted without MFA");
      Require_Body ("alpha", "v1", Exact (V1));
      Store.Delete_Selected_Object
        (Bucket, "alpha", Exact (V1), No_Delete_Object_Conditions,
         True, null, Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Success
         and then Delete_Outcome.Kind = Object_Version_Removed,
         "MFA-attested exact delete");

      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector =>
           (Kind => Current_Version,
            ID   => US.To_Unbounded_String ("forbidden")));
      Require (Result = Invalid_Request, "malformed current selector");
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector =>
           (Kind => Exact_Version, ID => US.Null_Unbounded_String));
      Require (Result = Invalid_Request, "empty exact selector");
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector =>
           (Kind => Exact_Version, ID => US.To_Unbounded_String ("null")));
      Require (Result = Invalid_Request, "wire null used as exact selector");

      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector =>
           (Kind => Exact_Version,
            ID   => US.To_Unbounded_String
              ((1 .. Maximum_Version_ID_Length => 'x'))));
      Require (Result = Not_Found, "maximum-size exact selector rejected");
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result,
         Selector =>
           (Kind => Exact_Version,
            ID   => US.To_Unbounded_String
              ((1 .. Maximum_Version_ID_Length + 1 => 'x'))));
      Require (Result = Invalid_Request, "overlong exact selector accepted");

      Store.Delete_Selected_Object
        (Bucket, "alpha",
         (Kind => Current_Version,
          ID   => US.To_Unbounded_String ("forbidden")),
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Invalid_Request,
         "selected delete admitted malformed current selector");
      Store.Delete_Selected_Object
        (Bucket, "alpha",
         (Kind => Exact_Version,
          ID   => US.To_Unbounded_String
            ((1 .. Maximum_Version_ID_Length + 1 => 'x'))),
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Invalid_Request,
         "selected delete admitted overlong exact selector");
      Store.Delete_Selected_Object
        (Bucket, "alpha", Current_Version_Selector,
         (Has_ETag => True,
          ETag => US.To_Unbounded_String ("""unterminated"),
          others => <>),
         False, null, Ada.Real_Time.Time_Last, Delete_Outcome, Result);
      Require
        (Result = Invalid_Request,
         "selected delete admitted malformed ETag condition");

      declare
         Ordered_Bucket : constant String := Bucket & "-ordering";
         Ignore         : Object_Information;
         Options        : List_Versions_Options := (others => <>);
      begin
         Store.Create_Bucket
           (Ordered_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require (Result = Success, "ordered version bucket setup");
         Store.Put_Bucket_Versioning
           (Ordered_Bucket,
            (Status => Versioning_Enabled, others => <>), null,
            Ada.Real_Time.Time_Last, Result);
         Require (Result = Success, "ordered version bucket enable");
         declare
            procedure Put_Ordered (Key, Payload : String) is
               Source : Buffer_Source :=
                 (Data => Flyology.Bytes.From_Byte_String (Payload),
                  Position => 0);
            begin
               Store.Put_Object
                 (Ordered_Bucket, Key, Source, Default_Put_Options, null,
                  Ada.Real_Time.Time_Last, Ignore, Result);
               Require (Result = Success, "ordered version publication");
            end Put_Ordered;
         begin
            Put_Ordered ("zeta", "z");
            Put_Ordered ("beta", "b1");
            Put_Ordered ("beta", "b2");
            Put_Ordered ("alpha", "a");
         end;

         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Entries.Length = 4
            and then US.To_String (Page.Entries (1).Key) = "alpha"
            and then US.To_String (Page.Entries (2).Key) = "beta"
            and then US.To_String (Page.Entries (3).Key) = "beta"
            and then US.To_String (Page.Entries (4).Key) = "zeta",
            "version listing key and generation order");

         Options.Prefix := US.To_Unbounded_String ("bet");
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Entries.Length = 2
            and then US.To_String (Page.Entries (1).Key) = "beta"
            and then US.To_String (Page.Entries (2).Key) = "beta",
            "version listing prefix filter");

         Options := (others => <>);
         Options.Has_Key_Marker := True;
         Options.Key_Marker := US.To_Unbounded_String ("beta");
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Entries.Length = 1
            and then US.To_String (Page.Entries (1).Key) = "zeta",
            "key-only version cursor");

         declare
            Discarded : Object_Information;

            procedure Put_Delimited
              (Key, Payload : String; Stored : out Object_Information)
            is
               Source : Buffer_Source :=
                 (Data => Flyology.Bytes.From_Byte_String (Payload),
                  Position => 0);
            begin
               Store.Put_Object
                 (Ordered_Bucket, Key, Source, Default_Put_Options, null,
                  Ada.Real_Time.Time_Last, Stored, Result);
               Require (Result = Success, "delimited version publication");
            end Put_Delimited;
         begin
            Put_Delimited ("logs/a", "l1", Discarded);
            Put_Delimited ("logs/a", "l2", Discarded);
            Put_Delimited ("logs/nested/b", "n", Nested);
         end;

         Options := (others => <>);
         Options.Delimiter := US.To_Unbounded_String ("/");
         Options.Maximum := 4;
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Is_Truncated
            and then Page.Entries.Length = 3
            and then Page.Common_Prefixes.Length = 1
            and then US.To_String (Page.Entries (1).Key) = "alpha"
            and then US.To_String (Page.Entries (2).Key) = "beta"
            and then US.To_String (Page.Entries (3).Key) = "beta"
            and then US.To_String (Page.Common_Prefixes (1)) = "logs/"
            and then US.Length (Page.Next_Key_Marker) > 0
            and then US.Length (Page.Next_Version_ID_Marker) > 0,
            "delimited version page projection");

         Options.Has_Key_Marker := True;
         Options.Key_Marker := Page.Next_Key_Marker;
         Options.Has_Version_ID_Marker := True;
         Options.Version_ID_Marker := Page.Next_Version_ID_Marker;
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then not Page.Is_Truncated
            and then Page.Entries.Length = 1
            and then Page.Common_Prefixes.Is_Empty
            and then US.To_String (Page.Entries (1).Key) = "zeta",
            "delimited version paired continuation");

         Options := (others => <>);
         Options.Delimiter := US.To_Unbounded_String ("/");
         Options.Has_Key_Marker := True;
         Options.Key_Marker := US.To_Unbounded_String ("logs/");
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Entries.Length = 1
            and then Page.Common_Prefixes.Is_Empty
            and then US.To_String (Page.Entries (1).Key) = "zeta",
            "key-only common-prefix cursor repeated its prefix");

         Options := (others => <>);
         Options.Prefix := US.To_Unbounded_String ("logs/");
         Options.Delimiter := US.To_Unbounded_String ("/");
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Entries.Length = 2
            and then Page.Common_Prefixes.Length = 1
            and then US.To_String (Page.Entries (1).Key) = "logs/a"
            and then US.To_String (Page.Entries (2).Key) = "logs/a"
            and then US.To_String (Page.Common_Prefixes (1)) =
              "logs/nested/",
            "delimited version prefix scope");

         Options.Has_Key_Marker := True;
         Options.Key_Marker := US.To_Unbounded_String ("logs/nested/b");
         Options.Has_Version_ID_Marker := True;
         Options.Version_ID_Marker := Nested.Version;
         Store.List_Object_Versions
           (Ordered_Bucket, Options, null, Ada.Real_Time.Time_Last, Page,
            Result);
         Require
           (Result = Success and then Page.Entries.Is_Empty
            and then Page.Common_Prefixes.Is_Empty,
            "paired cursor repeated its enclosing common prefix");
      end;
   end Exercise;

   procedure Exercise_Capacity
     (Store  : in out Backend'Class;
      Bucket : String)
   is
      Result  : Status;
      First   : Object_Information;
      Info    : Object_Information;
      Outcome : Version_Delete_Outcome;
      Page    : List_Versions_Page;

      procedure Put (Payload : String) is
         Source : Buffer_Source :=
           (Data => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0);
      begin
         Store.Put_Object
           (Bucket, "only-key", Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
      end Put;
   begin
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "capacity bucket setup");
      Store.Put_Bucket_Versioning
        (Bucket, (Status => Versioning_Enabled, others => <>), null,
         Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, "capacity bucket versioning enable");

      Put ("first");
      Require (Result = Success, "capacity first generation");
      First := Info;
      Put ("second");
      Require (Result = Capacity_Exceeded, "retained history exceeded slot");
      Store.Head_Object
        (Bucket, "only-key", null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Success and then Info.Version = First.Version,
         "failed retained publication changed current generation");

      Store.Delete_Selected_Object
        (Bucket, "only-key", Current_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Outcome, Result);
      Require
        (Result = Capacity_Exceeded,
         "delete marker exceeded retained slot capacity");
      Store.Head_Object
        (Bucket, "only-key", null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Success and then Info.Version = First.Version,
         "failed marker publication hid current generation");

      Store.Delete_Selected_Object
        (Bucket, "only-key",
         (Kind => Exact_Version, ID => First.Version),
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Outcome, Result);
      Require
        (Result = Success and then Outcome.Kind = Object_Version_Removed,
         "exact removal did not release retained slot");
      Store.Delete_Selected_Object
        (Bucket, "only-key", Current_Version_Selector,
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Outcome, Result);
      Require
        (Result = Success and then Outcome.Kind = Delete_Marker_Created,
         "released slot did not admit marker");
      Store.List_Object_Versions
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page,
         Result);
      Require
        (Result = Success and then Page.Entries.Length = 1
         and then Page.Entries (1).Is_Delete_Marker,
         "one-slot marker listing");
      Put ("blocked-by-marker");
      Require
        (Result = Capacity_Exceeded,
         "marker did not consume retained object slot");
      Store.Delete_Selected_Object
        (Bucket, "only-key",
         (Kind => Exact_Version, ID => Outcome.Version_ID),
         No_Delete_Object_Conditions, False, null,
         Ada.Real_Time.Time_Last, Outcome, Result);
      Require
        (Result = Success and then Outcome.Kind = Delete_Marker_Removed,
         "exact marker removal did not release slot");
      Put ("after-marker");
      Require (Result = Success, "released marker slot rejected generation");
   end Exercise_Capacity;

end Versioned_Object_Conformance;
