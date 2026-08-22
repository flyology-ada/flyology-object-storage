with Ada.Containers;
with Ada.Calendar.Formatting;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;
with AUnit.Test_Fixtures;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Durability_Testing;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.Object_Reads;
with Flyology.Object_Storage.S3.Requests;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.SigV4_Verification;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;

package body Object_Storage_Test_Cases is

   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Containers.Count_Type;
   use type Flyology.Object_Storage.Status;

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   package Caller is new AUnit.Test_Caller (Fixture);

   type Buffer_Source is new
     Flyology.Object_Storage.Backends.Byte_Source with
   record
      Data     : Flyology.Bytes.Unbounded_Bytes;
      Position : Natural := 0;
      Length   : Flyology.Object_Storage.Backends.Source_Length :=
        (Kind => Flyology.Object_Storage.Backends.Unknown);
      Bad_Last : Boolean := False;
   end record;

   overriding function Declared_Length
     (Item : Buffer_Source)
      return Flyology.Object_Storage.Backends.Source_Length is (Item.Length);

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   type Buffer_Sink is new Flyology.Object_Storage.Backends.Byte_Sink with
   record
      Data               : Flyology.Bytes.Unbounded_Bytes;
      Begun              : Boolean := False;
      Begin_Count        : Natural := 0;
      First              : Flyology.Object_Storage.Byte_Count := 0;
      Content_Length     : Flyology.Object_Storage.Byte_Count := 0;
      Partial            : Boolean := False;
      Snapshot           : Flyology.Object_Storage.Object_Information;
      Write_Before_Begin : Boolean := False;
   end record;

   type Raising_Sink is new Flyology.Object_Storage.Backends.Byte_Sink
     with null record;

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : Flyology.Object_Storage.Object_Information;
      First          : Flyology.Object_Storage.Byte_Count;
      Content_Length : Flyology.Object_Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Begin_Object
     (Item           : in out Raising_Sink;
      Info           : Flyology.Object_Storage.Object_Information;
      First          : Flyology.Object_Storage.Byte_Count;
      Content_Length : Flyology.Object_Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Raising_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   procedure Exercise_Conditional_Read
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String;
      Key    : String)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      use type US.Unbounded_String;
      Snapshot   : Object_Information;
      Result     : Status;
      Conditions : Read_Conditions := Default_Read_Conditions;

      procedure Read_And_Require
        (Expected : Status; Expected_Begins : Natural; Message : String)
      is
         Sink : Buffer_Sink;
         Info : Object_Information;
         Head_Info : Object_Information;
         Head_Result : Status;
      begin
         Store.Get_Object
           (Bucket, Key, Whole_Object, Sink, null,
            Ada.Real_Time.Time_Last, Info, Result, Conditions);
         Assert
           (Result = Expected
            and then Sink.Begin_Count = Expected_Begins
            and then (if Expected /= Success
                      then Info.Size = Snapshot.Size
                        and then Info.Modified = Snapshot.Modified
                        and then Info.Entity_Tag = Snapshot.Entity_Tag),
            Message);
         Store.Head_Object
           (Bucket, Key, null, Ada.Real_Time.Time_Last, Head_Info,
            Head_Result, Conditions);
         Assert
           (Head_Result = Expected
            and then Head_Info.Size = Snapshot.Size
            and then Head_Info.Modified = Snapshot.Modified
            and then Head_Info.Entity_Tag = Snapshot.Entity_Tag,
            "atomic HeadObject: " & Message);
      end Read_And_Require;
   begin
      Store.Head_Object
        (Bucket, Key, null, Ada.Real_Time.Time_Last, Snapshot, Result);
      Assert (Result = Success, "conditional-read setup head");

      Conditions.If_Match := US.To_Unbounded_String
        ('"' & US.To_String (Snapshot.Entity_Tag) & '"');
      Read_And_Require (Success, 1, "matching If-Match rejected");

      Conditions.If_Unmodified_Since :=
        (Is_Set => True, Value => Long_Long_Integer (Snapshot.Modified) - 1);
      Read_And_Require
        (Success, 1, "If-Match did not override If-Unmodified-Since");

      Conditions := Default_Read_Conditions;
      Conditions.If_Match := US.To_Unbounded_String ("""wrong""");
      Read_And_Require
        (Precondition_Failed, 0,
         "failed If-Match reached the response sink");

      Conditions.If_Match := US.To_Unbounded_String
        ("W/""" & US.To_String (Snapshot.Entity_Tag) & """");
      Read_And_Require
        (Precondition_Failed, 0,
         "weak If-Match used a non-strong comparison");

      Conditions := Default_Read_Conditions;
      Conditions.If_None_Match := US.To_Unbounded_String
        ("W/""" & US.To_String (Snapshot.Entity_Tag) & """");
      Read_And_Require
        (Not_Modified, 0,
         "weak If-None-Match failed to suppress the body");

      Conditions.If_None_Match := US.To_Unbounded_String
        (ASCII.HT & """other""," & ASCII.HT &
         "W/""" & US.To_String (Snapshot.Entity_Tag) & """" & ASCII.HT);
      Read_And_Require
        (Not_Modified, 0,
         "entity-tag list rejected legal optional whitespace");

      Conditions.If_None_Match := US.To_Unbounded_String ("""other""");
      Conditions.If_Modified_Since :=
        (Is_Set => True, Value => Long_Long_Integer'Last);
      Read_And_Require
        (Success, 1, "If-None-Match did not override If-Modified-Since");

      Conditions := Default_Read_Conditions;
      Conditions.If_Modified_Since :=
        (Is_Set => True, Value => Long_Long_Integer (Snapshot.Modified));
      Read_And_Require
        (Not_Modified, 0,
         "equal If-Modified-Since emitted an object body");

      Conditions := Default_Read_Conditions;
      Conditions.If_Unmodified_Since :=
        (Is_Set => True, Value => Long_Long_Integer (Snapshot.Modified) - 1);
      Read_And_Require
        (Precondition_Failed, 0,
         "failed If-Unmodified-Since reached the response sink");

      Conditions := Default_Read_Conditions;
      Conditions.If_None_Match := US.To_Unbounded_String ("*, ""other""");
      Read_And_Require
        (Invalid_Request, 0,
         "mixed wildcard entity-tag list was accepted");
   end Exercise_Conditional_Read;
   procedure Exercise_Bucket_Tags
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      package Storage_Tags renames Flyology.Object_Storage.Tags;
      package US renames Ada.Strings.Unbounded;
      use type Storage_Tags.Tag_Vectors.Vector;
      Value    : Storage_Tags.Tag_Set;
      Snapshot : Storage_Tags.Tag_Set;
      Result   : Status;

      function Item (Key, Text : String) return Storage_Tags.Tag is
        ((Key   => US.To_Unbounded_String (Key),
          Value => US.To_Unbounded_String (Text)));
   begin
      Store.Get_Bucket_Tags
        ("missing-tag-bucket", null, Ada.Real_Time.Time_Last,
         Snapshot, Result);
      Assert (Result = Not_Found, "tag get did not distinguish absent bucket");

      Store.Get_Bucket_Tags
        (Bucket, null, Ada.Real_Time.Time_Last, Snapshot, Result);
      Assert
        (Result = Tag_Set_Not_Found and then Snapshot.Is_Empty,
         "untagged bucket did not report NoSuchTagSet state");

      Value.Append (Item ("Project", "Flyology Ada"));
      Value.Append
        (Item
           (Character'Val (16#CE#) & Character'Val (16#A0#),
            Character'Val (16#E4#) & Character'Val (16#B8#) &
            Character'Val (16#80#)));
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "valid bucket tag set was rejected");
      Store.Get_Bucket_Tags
        (Bucket, null, Ada.Real_Time.Time_Last, Snapshot, Result);
      Assert
        (Result = Success and then Snapshot = Value,
         "bucket tag snapshot did not round trip");

      Snapshot (Snapshot.First_Index).Value :=
        US.To_Unbounded_String ("caller mutation");
      Store.Get_Bucket_Tags
        (Bucket, null, Ada.Real_Time.Time_Last, Snapshot, Result);
      Assert
        (Result = Success
         and then US.To_String (Snapshot (Snapshot.First_Index).Value) =
           "Flyology Ada",
         "returned bucket tag set aliased backend state");

      Value.Clear;
      Value.Append (Item ("replacement", ""));
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Store.Get_Bucket_Tags
        (Bucket, null, Ada.Real_Time.Time_Last, Snapshot, Result);
      Assert
        (Result = Success and then Snapshot = Value,
         "PutBucketTagging did not atomically replace the complete set");

      Value.Append (Item ("replacement", "duplicate"));
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Invalid_Request, "duplicate tag key was accepted");
      Value.Clear;
      Value.Append (Item ("aws:reserved", "x"));
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Invalid_Request, "reserved aws tag key was accepted");
      Value.Clear;
      Value.Append (Item ("invalid?", "x"));
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Invalid_Request, "invalid tag character was accepted");

      Value.Clear;
      for Index in 1 .. Storage_Tags.Maximum_Bucket_Tags + 1 loop
         Value.Append
           (Item
              ("key" & Ada.Strings.Fixed.Trim
                 (Natural'Image (Index), Ada.Strings.Both),
               "value"));
      end loop;
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Invalid_Request, "51-tag set was accepted");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.Get_Bucket_Tags
              (Bucket, Cancel'Access, Ada.Real_Time.Time_Last,
               Snapshot, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled => Raised := True;
         end;
         Assert (Raised, "bucket tag get ignored cancellation");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            Store.Get_Bucket_Tags
              (Bucket, null, Ada.Real_Time.Time_First, Snapshot, Result);
         exception
            when Flyology.IO.Timeout_Error => Raised := True;
         end;
         Assert (Raised, "bucket tag get ignored deadline");
      end;
   end Exercise_Bucket_Tags;

   procedure Exercise_Bucket_Listing
     (Store : in out Flyology.Object_Storage.Backends.Backend'Class)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      Options : List_Buckets_Options;
      Page    : Bucket_Page;
      Result  : Status;

      function Name_At (Index : Positive) return String is
        (case Index is
           when 1 => "bucket-zeta",
           when 2 => "other-bucket",
           when 3 => "bucket-alpha",
           when 4 => "bucket-beta",
           when others => raise Program_Error);
   begin
      for Index in 1 .. 4 loop
         Store.Create_Bucket
           (Name_At (Index), null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "bucket listing setup create");
      end loop;

      Options.Prefix := US.To_Unbounded_String ("bucket-");
      Options.Maximum := 2;
      Store.List_Buckets
        (Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Buckets.Length = 2
         and then US.To_String (Page.Buckets (1).Name) = "bucket-alpha"
         and then US.To_String (Page.Buckets (2).Name) = "bucket-beta"
         and then Page.Buckets (1).Created > 0
         and then Page.Buckets (2).Created > 0
         and then Page.Is_Truncated
         and then US.To_String (Page.Next_After) = "bucket-beta",
         "bucket listing sorted first page");

      Options.After := Page.Next_After;
      Store.List_Buckets
        (Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Buckets.Length = 1
         and then US.To_String (Page.Buckets.First_Element.Name) =
           "bucket-zeta"
         and then Page.Buckets.First_Element.Created > 0
         and then not Page.Is_Truncated
         and then US.Length (Page.Next_After) = 0,
         "bucket listing exclusive continuation");

      Options := (others => <>);
      Options.Prefix := US.To_Unbounded_String ("missing-");
      Store.List_Buckets
        (Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Buckets.Is_Empty
         and then not Page.Is_Truncated,
         "bucket listing empty prefix");

      Store.Delete_Bucket
        ("bucket-beta", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "bucket listing deletion setup");
      Options := (others => <>);
      Options.Prefix := US.To_Unbounded_String ("bucket-");
      Store.List_Buckets
        (Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Buckets.Length = 2
         and then US.To_String (Page.Buckets (1).Name) = "bucket-alpha"
         and then US.To_String (Page.Buckets (2).Name) = "bucket-zeta",
         "bucket listing excludes deleted bucket");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.List_Buckets
              (Options, Cancel'Access, Ada.Real_Time.Time_Last, Page, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled =>
               Raised := True;
         end;
         Assert (Raised, "bucket listing observes pre-cancellation");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            Store.List_Buckets
              (Options, null, Ada.Real_Time.Time_First, Page, Result);
         exception
            when Flyology.IO.Timeout_Error =>
               Raised := True;
         end;
         Assert (Raised, "bucket listing observes expired deadline");
      end;

      for Index in 1 .. 4 loop
         if Name_At (Index) /= "bucket-beta" then
            Store.Delete_Bucket
              (Name_At (Index), null, Ada.Real_Time.Time_Last, Result);
            Assert (Result = Success, "bucket listing cleanup");
         end if;
      end loop;
   end Exercise_Bucket_Listing;

   procedure Exercise_Listing
     (Store : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      Info   : Object_Information;
      Result : Status;
      Page   : List_Page;
      Options : List_Options;

      function Key_At (Index : Positive) return String is
        (case Index is
           when 1 => "zeta",
           when 2 => "dir/sub/c",
           when 3 => "alpha",
           when 4 => "dir/b",
           when 5 => "omega",
           when 6 => "dir/a",
           when others => raise Program_Error);

      procedure Put_Listing_Key (Key : String) is
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("x"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 1),
            Bad_Last => False);
      begin
         Store.Put_Object
           (Bucket, Key, Source, Default_Put_Options,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success, "ListObjectsV2 backend key setup");
      end Put_Listing_Key;

      procedure Delete_Listing_Key (Key : String) is
      begin
         Store.Delete_Object
           (Bucket, Key, null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "ListObjectsV2 backend key cleanup");
      end Delete_Listing_Key;
   begin
      Store.Delete_Object
        ("missing-bucket", "key", null, Ada.Real_Time.Time_Last, Result);
      Assert
        (Result = Bucket_Not_Found,
         "object delete did not distinguish an absent bucket");
      Store.List_Objects
        ("missing-bucket", Options, null, Ada.Real_Time.Time_Last,
         Page, Result);
      Assert (Result = Not_Found, "listing absent bucket");
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "listing bucket create");
      for Index in 1 .. 6 loop
         declare
            Source : Buffer_Source :=
              (Data     => Flyology.Bytes.From_Byte_String ("x"),
               Position => 0,
               Length   => (Kind => Known, Bytes => 1),
               Bad_Last => False);
         begin
            Store.Put_Object
              (Bucket, Key_At (Index), Source, Default_Put_Options,
               null, Ada.Real_Time.Time_Last, Info, Result);
            Assert (Result = Success, "listing object setup");
         end;
      end loop;

      Options.Maximum := 2;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Length = 2
         and then Page.Common_Prefixes.Is_Empty
         and then US.To_String (Page.Objects (1).Key) = "alpha"
         and then US.To_String (Page.Objects (2).Key) = "dir/a"
         and then Page.Is_Truncated
         and then US.To_String (Page.Next_After) = "dir/a",
         "plain listing lexical first page");

      Options.After := Page.Next_After;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Length = 2
         and then US.To_String (Page.Objects (1).Key) = "dir/b"
         and then US.To_String (Page.Objects (2).Key) = "dir/sub/c"
         and then Page.Is_Truncated,
         "plain listing continuation");

      Options := (others => <>);
      Options.Delimiter := US.To_Unbounded_String ("/");
      Options.Maximum := 2;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Length = 1
         and then US.To_String (Page.Objects.First_Element.Key) = "alpha"
         and then Page.Common_Prefixes.Length = 1
         and then US.To_String (Page.Common_Prefixes.First_Element) = "dir/"
         and then Page.Is_Truncated
         and then US.To_String (Page.Next_After) = "dir/",
         "delimiter listing collapses and counts prefixes");

      Options.After := Page.Next_After;
      Options.Maximum := 10;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Length = 2
         and then US.To_String (Page.Objects (1).Key) = "omega"
         and then US.To_String (Page.Objects (2).Key) = "zeta"
         and then Page.Common_Prefixes.Is_Empty
         and then not Page.Is_Truncated,
         "delimiter listing continuation skips collapsed group");

      Options := (others => <>);
      Options.Prefix := US.To_Unbounded_String ("dir/");
      Options.Delimiter := US.To_Unbounded_String ("/");
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Length = 2
         and then Page.Common_Prefixes.Length = 1
         and then US.To_String (Page.Common_Prefixes.First_Element) =
           "dir/sub/"
         and then not Page.Is_Truncated,
         "prefix-relative delimiter grouping");

      Options := (others => <>);
      Options.After := US.To_Unbounded_String ("dir/a");
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then US.To_String (Page.Objects.First_Element.Key) = "dir/b",
         "exclusive listing cursor");

      Options := (others => <>);
      Options.Maximum := 0;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Objects.Is_Empty
         and then Page.Common_Prefixes.Is_Empty
         and then not Page.Is_Truncated
         and then US.Length (Page.Next_After) = 0,
         "zero-sized listing is empty and final");

      --  ListObjectsV2 backend conformance: every nonzero bound is honored
      --  exactly, and truncation/token state agrees with the remaining
      --  namespace snapshot.
      for Maximum in 1 .. 6 loop
         Options := (others => <>);
         Options.Maximum := Maximum;
         Store.List_Objects
           (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success
            and then Natural (Page.Objects.Length) = Maximum
            and then Page.Common_Prefixes.Is_Empty
            and then Page.Is_Truncated = (Maximum < 6)
            and then
              (US.Length (Page.Next_After) > 0) = Page.Is_Truncated,
            "ListObjectsV2 backend bounded-page property");
      end loop;

      --  A continuation is an exclusive projected-key cursor over a fresh,
      --  atomic call snapshot.  A later insertion before the cursor cannot
      --  repeat, while a later insertion after it is eligible for the next
      --  page.
      Options := (others => <>);
      Options.Maximum := 2;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      declare
         Cursor : constant US.Unbounded_String := Page.Next_After;
      begin
         Put_Listing_Key ("aardvark");
         Put_Listing_Key ("dir/aa");
         Options.After := Cursor;
         Store.List_Objects
           (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success
            and then Page.Objects.Length = 2
            and then US.To_String (Page.Objects (1).Key) = "dir/aa"
            and then US.To_String (Page.Objects (2).Key) = "dir/b",
            "ListObjectsV2 mutation-safe exclusive continuation");
         Delete_Listing_Key ("aardvark");
         Delete_Listing_Key ("dir/aa");
      end;

      --  Delimiters are strings, not characters.  A collapsed common prefix
      --  consumes one result and its projected name is the exclusive cursor.
      Put_Listing_Key ("multi/a--x");
      Put_Listing_Key ("multi/a--y");
      Put_Listing_Key ("multi/b");
      Options := (others => <>);
      Options.Prefix := US.To_Unbounded_String ("multi/");
      Options.Delimiter := US.To_Unbounded_String ("--");
      Options.Maximum := 1;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Is_Empty
         and then Page.Common_Prefixes.Length = 1
         and then US.To_String (Page.Common_Prefixes.First_Element) =
           "multi/a--"
         and then Page.Is_Truncated
         and then US.To_String (Page.Next_After) = "multi/a--",
         "ListObjectsV2 multi-character delimiter projection");
      Options.After := Page.Next_After;
      Store.List_Objects
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success
         and then Page.Objects.Length = 1
         and then US.To_String (Page.Objects.First_Element.Key) = "multi/b"
         and then Page.Common_Prefixes.Is_Empty
         and then not Page.Is_Truncated,
         "ListObjectsV2 projected-prefix continuation");
      Delete_Listing_Key ("multi/a--x");
      Delete_Listing_Key ("multi/a--y");
      Delete_Listing_Key ("multi/b");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.List_Objects
              (Bucket, Options, Cancel'Access, Ada.Real_Time.Time_Last,
               Page, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled =>
               Raised := True;
         end;
         Assert (Raised, "listing observes pre-cancellation");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            Store.List_Objects
              (Bucket, Options, null, Ada.Real_Time.Time_First,
               Page, Result);
         exception
            when Flyology.IO.Timeout_Error =>
               Raised := True;
         end;
         Assert (Raised, "listing observes an expired deadline");
      end;

      for Index in 1 .. 6 loop
         Store.Delete_Object
           (Bucket, Key_At (Index), null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "listing cleanup object");
      end loop;
      Store.Delete_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "listing cleanup bucket");
   end Exercise_Listing;

   procedure Exercise_Delete_Objects
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      Entries      : Delete_Object_Entries;
      Outcomes     : Delete_Object_Outcomes;
      Match_Info   : Object_Information;
      Size_Info    : Object_Information;
      Time_Info    : Object_Information;
      Result       : Status;

      procedure Put
        (Key, Payload : String;
         Info         : out Object_Information;
         Target_Bucket : String := Bucket)
      is
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0,
            Length   =>
              (Kind => Known, Bytes => Byte_Count (Payload'Length)),
            Bad_Last => False);
      begin
         Store.Put_Object
           (Target_Bucket, Key, Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success, "DeleteObjects conformance put " & Key);
      end Put;

      function Item
        (Key        : String;
         Conditions : Delete_Object_Conditions :=
           No_Delete_Object_Conditions) return Delete_Object_Entry is
        ((Key => US.To_Unbounded_String (Key), Conditions => Conditions));
   begin
      Entries.Append (Item ("probe"));
      Store.Delete_Objects
        ("missing-delete-objects-bucket", Entries, (others => <>), null,
         Ada.Real_Time.Time_Last, Outcomes, Result);
      Assert
        (Result = Bucket_Not_Found and then Outcomes.Is_Empty,
         "DeleteObjects missing bucket classification");

      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "DeleteObjects conformance bucket create");

      declare
         Race_Bucket : constant String := "delete-objects-version-race";
         Configuration : Bucket_Versioning_Configuration;
      begin
         Store.Create_Bucket
           (Race_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "DeleteObjects race bucket create");
         Put ("race-object", "keep", Match_Info, Race_Bucket);
         Store.Get_Bucket_Versioning
           (Race_Bucket, null, Ada.Real_Time.Time_Last,
            Configuration, Result);
         Assert
           (Result = Success
            and then Configuration.Status = Versioning_Unconfigured,
            "DeleteObjects race did not begin unversioned");
         Store.Put_Bucket_Versioning
           (Race_Bucket,
            (Status => Versioning_Enabled,
             MFA_Delete => MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success,
            "DeleteObjects race could not publish versioning");
         Entries.Clear;
         Entries.Append (Item ("race-object"));
         Store.Delete_Objects
           (Race_Bucket, Entries, (Require_Unversioned => True), null,
            Ada.Real_Time.Time_Last, Outcomes, Result);
         Assert
           (Result = Not_Implemented and then Outcomes.Is_Empty,
            "DeleteObjects raced past an atomic versioning precondition");
         Store.Head_Object
           (Race_Bucket, "race-object", null, Ada.Real_Time.Time_Last,
            Match_Info, Result);
         Assert
           (Result = Success,
            "DeleteObjects versioning race removed current data");
         Store.Delete_Object
           (Race_Bucket, "race-object", null, Ada.Real_Time.Time_Last,
            Result);
         Store.Delete_Bucket
           (Race_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "DeleteObjects race bucket cleanup");
      end;

      Put ("match", "hello", Match_Info);
      Put ("mismatch", "keep", Size_Info);
      Put ("size", "1234567", Size_Info);
      Put ("timestamp", "clock", Time_Info);

      Entries.Clear;
      Entries.Append
        (Item
           ("match",
            (Has_ETag => True,
             ETag => US.To_Unbounded_String
               ('"' & US.To_String (Match_Info.Entity_Tag) & '"'),
             Has_Last_Modified_Time => True,
             Last_Modified_Time => Long_Long_Integer (Match_Info.Modified),
             Has_Size => True,
             Size => Match_Info.Size)));
      Entries.Append (Item ("already-missing"));
      Entries.Append
        (Item
           ("mismatch",
            (Has_ETag => True,
             ETag => US.To_Unbounded_String ("not-the-etag"),
             others => <>)));
      Entries.Append
        (Item
           ("conditioned-missing",
            (Has_ETag => True,
             ETag => US.To_Unbounded_String ("*"),
             others => <>)));
      Entries.Append
        (Item
           ("size",
            (Has_Size => True, Size => Size_Info.Size, others => <>)));
      Entries.Append (Item ("size"));
      Entries.Append
        (Item
           ("timestamp",
            (Has_Last_Modified_Time => True,
             Last_Modified_Time =>
               (if Time_Info.Modified = 0
                then 1 else Long_Long_Integer (Time_Info.Modified) - 1),
             others => <>)));
      Store.Delete_Objects
        (Bucket, Entries, (others => <>), null,
         Ada.Real_Time.Time_Last, Outcomes, Result);
      Assert
        (Result = Success and then Outcomes.Length = Entries.Length,
         "DeleteObjects ordered outcome cardinality");
      Assert
        (Outcomes (1).Result = Success
         and then Outcomes (2).Result = Success
         and then Outcomes (3).Result = Precondition_Failed
         and then Outcomes (4).Result = Not_Found
         and then Outcomes (5).Result = Success
         and then Outcomes (6).Result = Success
         and then Outcomes (7).Result = Precondition_Failed,
         "DeleteObjects ordered conditional outcomes");
      Store.Head_Object
        (Bucket, "match", null, Ada.Real_Time.Time_Last, Match_Info, Result);
      Assert (Result = Not_Found, "DeleteObjects matching key remained");
      Store.Head_Object
        (Bucket, "mismatch", null, Ada.Real_Time.Time_Last,
         Match_Info, Result);
      Assert (Result = Success, "DeleteObjects ETag mismatch mutated key");
      Store.Head_Object
        (Bucket, "size", null, Ada.Real_Time.Time_Last, Match_Info, Result);
      Assert (Result = Not_Found, "DeleteObjects size match remained");
      Store.Head_Object
        (Bucket, "timestamp", null, Ada.Real_Time.Time_Last,
         Match_Info, Result);
      Assert
        (Result = Success, "DeleteObjects timestamp mismatch mutated key");

      Entries.Clear;
      Entries.Append (Item ("mismatch"));
      Entries.Append
        (Item
           ("timestamp",
            (Has_ETag => True,
             ETag => US.To_Unbounded_String ("bad,etag"),
             others => <>)));
      Store.Delete_Objects
        (Bucket, Entries, (others => <>), null,
         Ada.Real_Time.Time_Last, Outcomes, Result);
      Assert
        (Result = Invalid_Request and then Outcomes.Is_Empty,
         "DeleteObjects invalid request was not rejected before publication");
      Store.Head_Object
        (Bucket, "mismatch", null, Ada.Real_Time.Time_Last,
         Match_Info, Result);
      Assert
        (Result = Success, "DeleteObjects invalid suffix partially mutated");

      Entries.Clear;
      Entries.Append (Item ("mismatch"));
      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.Delete_Objects
              (Bucket, Entries, (others => <>), Cancel'Access,
               Ada.Real_Time.Time_Last,
               Outcomes, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled => Raised := True;
         end;
         Assert (Raised, "DeleteObjects ignored pre-cancellation");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            Store.Delete_Objects
              (Bucket, Entries, (others => <>), null,
               Ada.Real_Time.Time_First,
               Outcomes, Result);
         exception
            when Flyology.IO.Timeout_Error => Raised := True;
         end;
         Assert (Raised, "DeleteObjects ignored expired deadline");
      end;

      Entries.Clear;
      Entries.Append (Item ("mismatch"));
      Entries.Append (Item ("timestamp"));
      Store.Delete_Objects
        (Bucket, Entries, (others => <>), null,
         Ada.Real_Time.Time_Last, Outcomes, Result);
      Assert
        (Result = Success
         and then Outcomes.Length = 2
         and then Outcomes (1).Result = Success
         and then Outcomes (2).Result = Success,
         "DeleteObjects conformance cleanup batch");
      Store.Delete_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "DeleteObjects conformance bucket cleanup");
   end Exercise_Delete_Objects;

   procedure Exercise_Multipart_Upload_Listing
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      Upload_IDs : array (Positive range 1 .. 5) of US.Unbounded_String;
      Page       : Multipart_Upload_Page;
      Options    : List_Multipart_Uploads_Options;
      Result     : Status;

      function Key_At (Index : Positive) return String is
        (case Index is
           when 1 => "zeta",
           when 2 => "same",
           when 3 => "dir/b",
           when 4 => "same",
           when 5 => "dir/a",
           when others => raise Program_Error);

      function Content_Type_At (Index : Positive) return String is
        ("application/x-upload-" & Positive'Image (Index));

      function Expected_Content_Type (Upload_ID : String) return String is
      begin
         for Index in Upload_IDs'Range loop
            if US.To_String (Upload_IDs (Index)) = Upload_ID then
               return Content_Type_At (Index);
            end if;
         end loop;
         raise Program_Error with "unknown multipart upload ID";
      end Expected_Content_Type;

      function Smaller_ID return US.Unbounded_String is
        (if US.To_String (Upload_IDs (2)) < US.To_String (Upload_IDs (4))
         then Upload_IDs (2) else Upload_IDs (4));

      function Larger_ID return US.Unbounded_String is
        (if US.To_String (Upload_IDs (2)) < US.To_String (Upload_IDs (4))
         then Upload_IDs (4) else Upload_IDs (2));
   begin
      Store.List_Multipart_Uploads
        ("missing-multipart-list-bucket", Options, null,
         Ada.Real_Time.Time_Last, Page, Result);
      Assert (Result = Not_Found, "multipart listing absent bucket");
      Store.List_Multipart_Uploads
        ("Invalid_Bucket", Options, null, Ada.Real_Time.Time_Last,
         Page, Result);
      Assert (Result = Invalid_Request, "multipart listing invalid bucket");

      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "multipart listing bucket create");
      for Index in Upload_IDs'Range loop
         Store.Create_Multipart_Upload
           (Bucket, Key_At (Index),
            (Content_Type =>
               US.To_Unbounded_String (Content_Type_At (Index))),
            null, Ada.Real_Time.Time_Last, Upload_IDs (Index), Result);
         Assert
           (Result = Success and then US.Length (Upload_IDs (Index)) = 64,
            "multipart listing upload setup");
      end loop;

      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 5
         and then Page.Common_Prefixes.Is_Empty
         and then US.To_String (Page.Uploads (1).Key) = "dir/a"
         and then US.To_String (Page.Uploads (2).Key) = "dir/b"
         and then US.To_String (Page.Uploads (3).Key) = "same"
         and then US.To_String (Page.Uploads (4).Key) = "same"
         and then US.To_String (Page.Uploads (5).Key) = "zeta"
         and then not Page.Is_Truncated,
         "multipart listing key order and complete page");
      Assert
        (Page.Uploads (3).Initiated < Page.Uploads (4).Initiated
         or else
           (Page.Uploads (3).Initiated = Page.Uploads (4).Initiated
            and then US.To_String (Page.Uploads (3).Upload_ID) <
              US.To_String (Page.Uploads (4).Upload_ID)),
         "same-key uploads are not initiation-time ordered");
      for Upload of Page.Uploads loop
         Assert
           (US.To_String (Upload.Options.Content_Type) =
              Expected_Content_Type (US.To_String (Upload.Upload_ID)),
            "multipart listing lost initiation options");
      end loop;

      Options.Maximum := 2;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 2
         and then US.To_String (Page.Uploads (1).Key) = "dir/a"
         and then US.To_String (Page.Uploads (2).Key) = "dir/b"
         and then Page.Is_Truncated
         and then US.To_String (Page.Next_After.Key) = "dir/b"
         and then US.Length (Page.Next_After.Upload_ID) = 64,
         "multipart listing bounded first page");
      Options.After := Page.Next_After;
      Options.Maximum := 10;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 3
         and then US.To_String (Page.Uploads (1).Key) = "same"
         and then US.To_String (Page.Uploads (2).Key) = "same"
         and then US.To_String (Page.Uploads (3).Key) = "zeta"
         and then not Page.Is_Truncated,
         "multipart listing continuation");

      Options := (others => <>);
      Options.After.Key := US.To_Unbounded_String ("same");
      Options.After.Upload_ID := Smaller_ID;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 2
         and then US.To_String (Page.Uploads (1).Upload_ID) =
           US.To_String (Larger_ID)
         and then US.To_String (Page.Uploads (2).Key) = "zeta",
         "multipart upload-ID marker filtering");
      Options.After.Upload_ID := US.Null_Unbounded_String;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 1
         and then US.To_String (Page.Uploads.First_Element.Key) = "zeta",
         "key-only multipart marker did not skip equal keys");

      Options := (others => <>);
      Options.Delimiter := US.To_Unbounded_String ("/");
      Options.Maximum := 1;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Is_Empty
         and then Page.Common_Prefixes.Length = 1
         and then US.To_String (Page.Common_Prefixes.First_Element) = "dir/"
         and then Page.Is_Truncated
         and then US.To_String (Page.Next_After.Key) = "dir/"
         and then US.Length (Page.Next_After.Upload_ID) = 0,
         "multipart delimiter prefix and page budget");
      Options.After := Page.Next_After;
      Options.Maximum := 10;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 3
         and then Page.Common_Prefixes.Is_Empty
         and then not Page.Is_Truncated,
         "multipart delimiter continuation");

      Options := (others => <>);
      Options.Prefix := US.To_Unbounded_String ("same");
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 2,
         "multipart listing prefix filter");

      Store.Abort_Multipart_Upload
        (Bucket, "same", US.To_String (Upload_IDs (2)),
         Flyology.Object_Storage.Backends.No_Abort_Multipart_Conditions, null,
         Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "multipart listing abort setup");
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 1
         and then US.To_String (Page.Uploads.First_Element.Upload_ID) =
           US.To_String (Upload_IDs (4)),
         "aborted multipart upload remained visible");

      Options := (others => <>);
      Options.Maximum := 0;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Is_Empty
         and then Page.Common_Prefixes.Is_Empty and then not Page.Is_Truncated,
         "zero-sized multipart listing is empty and final");

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.List_Multipart_Uploads
              (Bucket, Options, Cancel'Access, Ada.Real_Time.Time_Last,
               Page, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled => Raised := True;
         end;
         Assert (Raised, "multipart listing ignored cancellation");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            Store.List_Multipart_Uploads
              (Bucket, Options, null, Ada.Real_Time.Time_First, Page, Result);
         exception
            when Flyology.IO.Timeout_Error => Raised := True;
         end;
         Assert (Raised, "multipart listing ignored expired deadline");
      end;

      for Index in Upload_IDs'Range loop
         if Index /= 2 then
            Store.Abort_Multipart_Upload
              (Bucket, Key_At (Index), US.To_String (Upload_IDs (Index)),
               Flyology.Object_Storage.Backends.No_Abort_Multipart_Conditions,
               null, Ada.Real_Time.Time_Last, Result);
            Assert (Result = Success, "multipart listing cleanup upload");
         end if;
      end loop;
      Store.Delete_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "multipart listing cleanup bucket");
   end Exercise_Multipart_Upload_Listing;

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
      if Item.Bad_Last then
         Last := Data'Last + 1;
         Finished := True;
         return;
      end if;
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

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : Flyology.Object_Storage.Object_Information;
      First          : Flyology.Object_Storage.Byte_Count;
      Content_Length : Flyology.Object_Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Item.Begun := True;
      Item.Begin_Count := Item.Begin_Count + 1;
      Item.First := First;
      Item.Content_Length := Content_Length;
      Item.Partial := Partial;
      Item.Snapshot := Info;
   end Begin_Object;

   overriding procedure Begin_Object
     (Item           : in out Raising_Sink;
      Info           : Flyology.Object_Storage.Object_Information;
      First          : Flyology.Object_Storage.Byte_Count;
      Content_Length : Flyology.Object_Storage.Byte_Count;
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
      if not Item.Begun then
         Item.Write_Before_Begin := True;
      end if;
      Flyology.Bytes.Append (Item.Data, Data);
   end Write;

   overriding procedure Write
     (Item     : in out Raising_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Item, Data, Token, Deadline);
   begin
      raise Program_Error with "sink sentinel";
   end Write;

   type XML_Recorder is new
     Flyology.Object_Storage.S3.XML.Event_Handler with
   record
      Trace : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   overriding procedure Start_Element
     (Item : in out XML_Recorder; Local_Name : String);
   overriding procedure Text
     (Item : in out XML_Recorder; Value : String);
   overriding procedure End_Element
     (Item : in out XML_Recorder; Local_Name : String);

   overriding procedure Start_Element
     (Item : in out XML_Recorder; Local_Name : String) is
   begin
      Ada.Strings.Unbounded.Append (Item.Trace, "<" & Local_Name & ">");
   end Start_Element;

   overriding procedure Text
     (Item : in out XML_Recorder; Value : String) is
   begin
      Ada.Strings.Unbounded.Append (Item.Trace, Value);
   end Text;

   overriding procedure End_Element
     (Item : in out XML_Recorder; Local_Name : String) is
   begin
      Ada.Strings.Unbounded.Append (Item.Trace, "</" & Local_Name & ">");
   end End_Element;

   procedure Check_Validators (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      Nul_Key : constant String := "a" & Character'Val (0) & "b";

      function Read_Result
        (If_Match                 : String := "";
         If_None_Match            : String := "";
         Has_If_Modified_Since    : Boolean := False;
         If_Modified_Since        : Long_Long_Integer := 0;
         Has_If_Unmodified_Since  : Boolean := False;
         If_Unmodified_Since      : Long_Long_Integer := 0)
         return Status is
        (Evaluate_Object_Read_Conditions
           (If_Match, If_None_Match,
            Has_If_Modified_Since, If_Modified_Since,
            Has_If_Unmodified_Since, If_Unmodified_Since,
            "etag", 100));
   begin
      Assert (Valid_Bucket_Name ("abc"), "minimum bucket name");
      Assert (Valid_Bucket_Name ("logs.example-1"), "ordinary bucket name");
      Assert (not Valid_Bucket_Name ("ab"), "too short");
      Assert (not Valid_Bucket_Name ("Aaa"), "uppercase");
      Assert (not Valid_Bucket_Name ("-abc"), "leading hyphen");
      Assert (not Valid_Bucket_Name ("abc-"), "trailing hyphen");
      Assert (not Valid_Bucket_Name (".abc"), "leading dot");
      Assert (not Valid_Bucket_Name ("abc."), "trailing dot");
      Assert (not Valid_Bucket_Name ("a..b"), "adjacent dots");
      Assert (not Valid_Bucket_Name ("a.-b"), "dot hyphen adjacency");
      Assert (not Valid_Bucket_Name ("a-.b"), "hyphen dot adjacency");
      Assert (not Valid_Bucket_Name ("192.168.1.1"), "IPv4-shaped name");
      Assert (Valid_Bucket_Name ("256.1.1.1"), "non-IP numeric labels");
      Assert (not Valid_Bucket_Name ("xn--bucket"), "reserved xn prefix");
      Assert
        (not Valid_Bucket_Name ("sthree-bucket"), "reserved sthree prefix");
      Assert
        (not Valid_Bucket_Name ("amzn-s3-demo-bucket"),
         "reserved AWS demo prefix");
      Assert
        (not Valid_Bucket_Name ("bucket-s3alias"), "access point suffix");
      Assert
        (not Valid_Bucket_Name ("bucket--ol-s3"), "object lambda suffix");
      Assert (not Valid_Bucket_Name ("bucket.mrap"), "MRAP suffix");
      Assert (not Valid_Bucket_Name ("bucket--x-s3"), "directory suffix");
      Assert (not Valid_Bucket_Name ("bucket--table-s3"), "table suffix");
      Assert (not Valid_Bucket_Name ("bucket-an"), "account namespace suffix");
      Assert (Valid_Object_Key ("../opaque/key"), "keys are opaque");
      Assert (Valid_Object_Key ("/leading/slash"), "leading slash is opaque");
      Assert (not Valid_Object_Key (""), "empty key");
      Assert (not Valid_Object_Key (Nul_Key), "NUL key");
      Assert
        (not Valid_Object_Key ((1 .. 1_025 => 'x')), "key over 1,024 bytes");
      Assert
        (Evaluate_Object_Write_Conditions
           ("""etag""", "", True, "etag") = Success,
         "strong If-Match did not match");
      Assert
        (Evaluate_Object_Write_Conditions
           ("W/""etag""", "", True, "etag") = Precondition_Failed,
         "weak If-Match incorrectly matched");
      Assert
        (Evaluate_Object_Write_Conditions
           ("*", "", False, "") = Precondition_Failed,
         "If-Match accepted an absent object");
      Assert
        (Evaluate_Object_Write_Conditions
           ("", "*", False, "") = Success,
         "If-None-Match rejected an absent object");
      Assert
        (Evaluate_Object_Write_Conditions
           ("", "W/""etag""", True, "etag") = Precondition_Failed,
         "weak If-None-Match did not match");
      Assert
        (Evaluate_Object_Write_Conditions
           (" ""other"", ""etag"" ", "", True, "etag") = Success,
         "entity-tag lists or optional whitespace were mishandled");
      Assert
        (Evaluate_Object_Write_Conditions
           ("""unterminated", "", True, "etag") = Invalid_Request,
         "malformed If-Match was accepted");
      Assert
        (Evaluate_Object_Write_Conditions
           ("", "*, ""etag""", True, "etag") = Invalid_Request,
         "mixed wildcard If-None-Match was accepted");
      Assert
        (Evaluate_Object_Write_Conditions
           ((1 .. 16_385 => 'x'), "", True, "etag") = Invalid_Request,
         "oversized condition field was accepted");
      Assert
        (Valid_Object_Read_Entity_Tag_Condition
           (ASCII.HT & """other""," & ASCII.HT & "W/""etag"""),
         "valid read entity-tag list was rejected");
      Assert
        (not Valid_Object_Read_Entity_Tag_Condition (""),
         "empty read entity-tag condition was accepted");
      Assert
        (not Valid_Object_Read_Entity_Tag_Condition ("*, ""etag"""),
         "mixed-wildcard read entity-tag list was accepted");
      Assert
        (not Valid_Object_Read_Entity_Tag_Condition ((1 .. 16_385 => 'x')),
         "oversized read entity-tag condition was accepted");
      Assert
        (Read_Result (If_Match => """etag""") = Success,
         "strong read If-Match did not match");
      Assert
        (Read_Result (If_Match => "W/""etag""") = Precondition_Failed,
         "weak read If-Match incorrectly matched");
      Assert
        (Read_Result
           (If_Match => """etag""",
            Has_If_Unmodified_Since => True,
            If_Unmodified_Since => 99) = Success,
         "read If-Match did not override If-Unmodified-Since");
      Assert
        (Read_Result
           (Has_If_Unmodified_Since => True,
            If_Unmodified_Since => 99) = Precondition_Failed,
         "failed read If-Unmodified-Since was accepted");
      Assert
        (Read_Result (If_None_Match => "W/""etag""") = Not_Modified,
         "weak read If-None-Match did not match");
      Assert
        (Read_Result
           (If_None_Match => """other""",
            Has_If_Modified_Since => True,
            If_Modified_Since => Long_Long_Integer'Last) = Success,
         "read If-None-Match did not override If-Modified-Since");
      Assert
        (Read_Result
           (Has_If_Modified_Since => True,
            If_Modified_Since => 100) = Not_Modified,
         "equal read If-Modified-Since was accepted");
      Assert
        (Read_Result (If_None_Match => "*, ""etag""") = Invalid_Request,
         "malformed read If-None-Match was accepted");
      Assert
        (Valid_Object_Delete_ETag_Condition ("etag")
         and then Valid_Object_Delete_ETag_Condition ("""etag""")
         and then Valid_Object_Delete_ETag_Condition ("*"),
         "valid DeleteObjects ETag condition was rejected");
      Assert
        (not Valid_Object_Delete_ETag_Condition ("")
         and then not Valid_Object_Delete_ETag_Condition ("W/""etag""")
         and then not Valid_Object_Delete_ETag_Condition ("etag,other")
         and then not Valid_Object_Delete_ETag_Condition (" etag"),
         "malformed DeleteObjects ETag condition was accepted");
      Assert
        (Evaluate_Object_Delete_Conditions
           (True, """etag""", True, 100, True, 5,
            True, "etag", 100, 5) = Success,
         "matching DeleteObjects conditions failed");
      Assert
        (Evaluate_Object_Delete_Conditions
           (False, "", False, 0, False, 0,
            False, "", 0, 0) = Success,
         "unconditioned missing DeleteObjects key was not idempotent");
      Assert
        (Evaluate_Object_Delete_Conditions
           (True, "*", False, 0, False, 0,
            False, "", 0, 0) = Not_Found,
         "conditioned missing DeleteObjects key did not report Not_Found");
      Assert
        (Evaluate_Object_Delete_Conditions
           (False, "", True, 99, False, 0,
            True, "etag", 100, 5) = Precondition_Failed
         and then Evaluate_Object_Delete_Conditions
           (False, "", False, 0, True, 4,
            True, "etag", 100, 5) = Precondition_Failed,
         "DeleteObjects metadata mismatch was accepted");
   end Check_Validators;

   procedure Check_Memory_Lifecycle (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      type Store_Access is access all Memory.Store;
      type Reservation_Sink is new Byte_Sink with record
         Store            : Store_Access;
         Observed         : Boolean := False;
         Written          : Natural := 0;
         Competing_Result : Status := Success;
      end record;
      overriding procedure Begin_Object
        (Item           : in out Reservation_Sink;
         Info           : Object_Information;
         First          : Byte_Count;
         Content_Length : Byte_Count;
         Partial        : Boolean;
         Token          : access Flyology.Cancellation.Token;
         Deadline       : Ada.Real_Time.Time);
      overriding procedure Write
        (Item     : in out Reservation_Sink;
         Data     : Ada.Streams.Stream_Element_Array;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time);

      Store  : aliased Memory.Store (2, 4, 64);
      Source : Buffer_Source :=
        (Data     => Flyology.Bytes.From_Byte_String ("hello world"),
         Position => 0,
         Length   => (Kind => Known, Bytes => 11),
         Bad_Last => False);
      Sink   : Buffer_Sink;
      Info   : Object_Information;
      Result : Status;

      overriding procedure Begin_Object
        (Item           : in out Reservation_Sink;
         Info           : Object_Information;
         First          : Byte_Count;
         Content_Length : Byte_Count;
         Partial        : Boolean;
         Token          : access Flyology.Cancellation.Token;
         Deadline       : Ada.Real_Time.Time)
      is
         pragma Unreferenced
           (Info, First, Content_Length, Partial, Token, Deadline);
         Competitor : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String
              (String'(1 .. 43 => 'x')),
            Position => 0,
            Length   => (Kind => Known, Bytes => 43),
            Bad_Last => False);
         Ignored : Object_Information;
      begin
         Item.Observed := Item.Store.Bytes_Used = 22;
         Item.Store.Put_Object
           ("test-bucket", "competitor", Competitor,
            Default_Put_Options, null, Ada.Real_Time.Time_Last,
            Ignored, Item.Competing_Result);
      end Begin_Object;

      overriding procedure Write
        (Item     : in out Reservation_Sink;
         Data     : Ada.Streams.Stream_Element_Array;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time)
      is
         pragma Unreferenced (Token, Deadline);
      begin
         Item.Written := Item.Written + Data'Length;
      end Write;
   begin
      Store.Create_Bucket
        ("test-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "create bucket");
      Store.Head_Bucket
        ("test-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "head existing memory bucket");
      Exercise_Bucket_Tags (Store, "test-bucket");
      Store.Put_Object
        ("test-bucket", "../opaque/key", Source, Default_Put_Options,
         null, Ada.Real_Time.Time_Last, Info, Result);
      Assert (Result = Success, "put object");
      Assert (Info.Size = 11, "put size");
      Assert
        (Ada.Strings.Unbounded.To_String (Info.Entity_Tag) =
           "5eb63bbbe01eeed093cb22bb8f5acdc3",
         "memory generates single-part MD5 entity tag");
      Assert (Store.Bytes_Used = 11, "account committed bytes");
      Store.Head_Object
        ("test-bucket", "../opaque/key", null,
         Ada.Real_Time.Time_Last, Info, Result);
      Assert (Result = Success and then Info.Size = 11, "head object");
      Exercise_Conditional_Read (Store, "test-bucket", "../opaque/key");
      Store.Get_Object
        ("test-bucket", "../opaque/key", Whole_Object, Sink,
         null, Ada.Real_Time.Time_Last, Info, Result);
      Assert (Result = Success, "get object");
      Assert
        (Flyology.Bytes.To_Byte_String (Sink.Data) = "hello world",
         "round trip body");
      Assert
        (Sink.Begun
         and then Sink.Begin_Count = 1
         and then not Sink.Write_Before_Begin
         and then Sink.First = 0
         and then Sink.Content_Length = 11
         and then not Sink.Partial
         and then Sink.Snapshot.Size = Info.Size,
         "memory announces coherent snapshot before body");
      declare
         Probe : Reservation_Sink :=
           (Store => Store'Unchecked_Access, others => <>);
      begin
         Store.Get_Object
           ("test-bucket", "../opaque/key", Whole_Object, Probe,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Probe.Observed
            and then Probe.Competing_Result = Capacity_Exceeded
            and then Probe.Written = 11 and then Store.Bytes_Used = 11,
            "outbound snapshot escaped or leaked byte accounting");
      end;
      declare
         Failed : Raising_Sink;
         Propagated : Boolean := False;
      begin
         begin
            Store.Get_Object
              ("test-bucket", "../opaque/key", Whole_Object, Failed,
               null, Ada.Real_Time.Time_Last, Info, Result);
         exception
            when Program_Error =>
               Propagated := True;
         end;
         Assert
           (Propagated and then Store.Bytes_Used = 11,
            "exceptional outbound sink leaked its snapshot reservation");
      end;
      declare
         Copy_Options_Value : Copy_Options := Default_Copy_Options;
         Copied : Buffer_Sink;
      begin
         Copy_Options_Value.Conditions.If_Match :=
           Ada.Strings.Unbounded.To_Unbounded_String
             ('"' & Ada.Strings.Unbounded.To_String (Info.Entity_Tag) & '"');
         Store.Copy_Object
           ("test-bucket", "../opaque/key", "test-bucket", "copy",
            Copy_Options_Value, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Info.Size = 11
            and then Ada.Strings.Unbounded.To_String (Info.Content_Type) =
              "application/octet-stream"
            and then Store.Bytes_Used = 22,
            "memory copy did not preserve source metadata and accounting");
         Store.Get_Object
           ("test-bucket", "copy", Whole_Object, Copied,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Copied.Data) =
              "hello world" and then Store.Bytes_Used = 22,
            "memory copy body mismatch or snapshot leak");
         Copy_Options_Value.Conditions.If_Match :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Copy_Options_Value.Conditions.If_None_Match :=
           Ada.Strings.Unbounded.To_Unbounded_String
             ('"' & Ada.Strings.Unbounded.To_String (Info.Entity_Tag) & '"');
         Store.Copy_Object
           ("test-bucket", "../opaque/key", "test-bucket", "copy",
            Copy_Options_Value, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Precondition_Failed and then Store.Bytes_Used = 22,
            "memory copy precondition failed to preserve destination");
         Store.Copy_Object
           ("test-bucket", "missing", "test-bucket", "copy",
            Default_Copy_Options, null, Ada.Real_Time.Time_Last,
            Info, Result);
         Assert
           (Result = Source_Not_Found and then Store.Bytes_Used = 22,
            "memory copy source absence was ambiguous or leaked");
         Store.Copy_Object
           ("test-bucket", "../opaque/key", "test-bucket",
            "../opaque/key", Default_Copy_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Invalid_Request and then Store.Bytes_Used = 22,
            "memory accepted a metadata-preserving self copy");
         Store.Delete_Object
           ("test-bucket", "copy", null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success and then Store.Bytes_Used = 11,
                 "memory copy cleanup failed");
      end;
      Store.Delete_Bucket
        ("test-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Bucket_Not_Empty, "reject nonempty bucket delete");
      Store.Delete_Object
        ("test-bucket", "../opaque/key", null,
         Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success and then Store.Bytes_Used = 0, "delete object");
      Store.Delete_Bucket
        ("test-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "delete empty bucket");
      Store.Head_Bucket
        ("test-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Not_Found, "head deleted memory bucket");
   end Check_Memory_Lifecycle;

   procedure Check_Memory_Multipart (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      MiB : constant Natural := 1_024 * 1_024;
      Store : Flyology.Object_Storage.Backends.Memory.Store
        (1, 8, 12 * Byte_Count (MiB));
      Upload_ID : US.Unbounded_String;
      Target_ETag : US.Unbounded_String;
      Info : Object_Information;
      Result : Status;

      function Repeated
        (Count : Natural;
         Value : Ada.Streams.Stream_Element)
         return Flyology.Bytes.Unbounded_Bytes
      is
         Chunk : constant Ada.Streams.Stream_Element_Array
           (1 .. 16 * 1_024) :=
           (others => Value);
         Data : Flyology.Bytes.Unbounded_Bytes;
         Remaining : Natural := Count;
      begin
         Flyology.Bytes.Reserve_Capacity (Data, Count);
         while Remaining > 0 loop
            declare
               Size : constant Natural := Natural'Min
                 (Remaining, Natural (Chunk'Length));
            begin
               Flyology.Bytes.Append
                 (Data,
                  Chunk
                    (Chunk'First ..
                     Chunk'First + Ada.Streams.Stream_Element_Offset (Size) -
                       1));
               Remaining := Remaining - Size;
            end;
         end loop;
         return Data;
      end Repeated;

      procedure Upload
        (ID : String;
         Key : String;
         Number : Multipart_Part_Number;
         Data : Flyology.Bytes.Unbounded_Bytes;
         ETag : out US.Unbounded_String)
      is
         Source : Buffer_Source :=
           (Data     => Data,
            Position => 0,
            Length   => (Kind => Known,
                         Bytes => Byte_Count (Flyology.Bytes.Length (Data))),
            Bad_Last => False);
      begin
         Store.Put_Multipart_Part
           ("multipart-bucket", Key, ID, Number, Source, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success, "memory multipart part upload failed");
         ETag := Info.Entity_Tag;
      end Upload;
   begin
      Exercise_Multipart_Upload_Listing (Store, "multipart-listing");
      Store.Create_Bucket
        ("multipart-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "memory multipart bucket create failed");
      Store.Create_Multipart_Upload
        ("multipart-bucket", "target", Default_Multipart_Options, null,
         Ada.Real_Time.Time_Last, Upload_ID, Result);
      Assert
        (Result = Success and then US.Length (Upload_ID) = 64,
         "memory multipart create failed");
      Store.Delete_Bucket
        ("multipart-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert
        (Result = Bucket_Not_Empty,
         "active multipart upload did not protect its bucket");

      declare
         First_ETag, Last_ETag : US.Unbounded_String;
         Completion : Multipart_Part_References;
      begin
         Upload
           (US.To_String (Upload_ID), "target", 1,
            Repeated
              (5 * MiB,
               Ada.Streams.Stream_Element (Character'Pos ('a'))),
            First_ETag);
         Upload
           (US.To_String (Upload_ID), "target", 2,
            Flyology.Bytes.From_Byte_String ("tail"), Last_ETag);
         declare
            Page : Multipart_Part_Page;
            Options : List_Multipart_Parts_Options :=
              (After => 0, Maximum => 1);
         begin
            Store.List_Multipart_Parts
              ("multipart-bucket", "target", US.To_String (Upload_ID),
               Options, null, Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Success and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Number = 1
               and then Page.Parts.First_Element.Info.Size =
                 Byte_Count (5 * MiB)
               and then Page.Is_Truncated and then Page.Next_After = 1,
               "memory ListParts first page failed");
            Options.After := Page.Next_After;
            Store.List_Multipart_Parts
              ("multipart-bucket", "target", US.To_String (Upload_ID),
               Options, null, Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Success and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Number = 2
               and then Page.Parts.First_Element.Info.Size = 4
               and then not Page.Is_Truncated and then Page.Next_After = 0,
               "memory ListParts continuation failed");
            Store.List_Multipart_Parts
              ("multipart-bucket", "target", "missing-upload", Options,
               null, Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Not_Found and then Page.Parts.Is_Empty,
               "memory ListParts missing upload was ambiguous");
         end;
         Assert
           (Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "staged multipart bytes were not accounted");
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 2, Entity_Tag => Last_ETag));
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1, Entity_Tag => First_ETag));
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "target", US.To_String (Upload_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Invalid_Part_Order,
            "out-of-order multipart completion was accepted");
         Completion.Clear;
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1,
               Entity_Tag => US.To_Unbounded_String ("wrong")));
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 2, Entity_Tag => Last_ETag));
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "target", US.To_String (Upload_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Invalid_Part, "wrong multipart ETag was accepted");
         Completion.Replace_Element
           (1, Multipart_Part_Reference'
             (Number => 1, Entity_Tag => First_ETag));
         declare
            Options : Complete_Multipart_Options :=
              Default_Complete_Multipart_Options;
         begin
            Options.Expected_Size :=
              (Kind => Known, Bytes => Byte_Count (5 * MiB + 5));
            Store.Complete_Multipart_Upload
              ("multipart-bucket", "target", US.To_String (Upload_ID),
               Completion, Options, null, Ada.Real_Time.Time_Last, Info,
               Result);
            Assert
              (Result = Invalid_Request,
               "wrong memory multipart object size consumed the upload");
            Options.Expected_Size.Bytes := Byte_Count (5 * MiB + 4);
            Options.Conditions.If_Match := US.To_Unbounded_String ("*");
            Store.Complete_Multipart_Upload
              ("multipart-bucket", "target", US.To_String (Upload_ID),
               Completion, Options, null, Ada.Real_Time.Time_Last, Info,
               Result);
            Assert
              (Result = Precondition_Failed,
               "memory completion If-Match accepted a missing target");
            Options.Conditions.If_Match := US.Null_Unbounded_String;
            Options.Conditions.If_None_Match :=
              US.To_Unbounded_String ("*");
            Store.Complete_Multipart_Upload
              ("multipart-bucket", "target", US.To_String (Upload_ID),
               Completion, Options, null, Ada.Real_Time.Time_Last, Info,
               Result);
         end;
         Assert
           (Result = Success
            and then Info.Size = Byte_Count (5 * MiB + 4)
            and then US.Length (Info.Entity_Tag) = 34
            and then US.To_String (Info.Entity_Tag)
              (33 .. 34) = "-2"
            and then Store.Bytes_Used = Info.Size,
            "valid memory multipart completion failed");
         Target_ETag := Info.Entity_Tag;
      end;

      declare
         Oversized_ID : US.Unbounded_String;
         Oversized : Buffer_Source :=
           (Data     => Flyology.Bytes.Empty,
            Position => 0,
            Length   =>
              (Kind  => Known,
               Bytes => Maximum_Multipart_Part_Size + 1),
            Bad_Last => False);
      begin
         Store.Create_Multipart_Upload
           ("multipart-bucket", "oversized", Default_Multipart_Options,
            null, Ada.Real_Time.Time_Last, Oversized_ID, Result);
         Assert (Result = Success, "oversized multipart create failed");
         Store.Put_Multipart_Part
           ("multipart-bucket", "oversized", US.To_String (Oversized_ID),
            1, Oversized, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Entity_Too_Large
            and then Oversized.Position = 0
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "logical 5 GiB+1 multipart part was read or retained");
         Store.Abort_Multipart_Upload
           ("multipart-bucket", "oversized", US.To_String (Oversized_ID),
            Flyology.Object_Storage.Backends.No_Abort_Multipart_Conditions,
            null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "oversized multipart cleanup failed");
      end;

      declare
         Copy_ID : US.Unbounded_String;
         Copy_ETag : US.Unbounded_String;
         Completion : Multipart_Part_References;
         Conditions : Copy_Conditions := (others => <>);
         Copied : Buffer_Sink;
      begin
         Store.Create_Multipart_Upload
           ("multipart-bucket", "copied-part", Default_Multipart_Options,
            null, Ada.Real_Time.Time_Last, Copy_ID, Result);
         Assert (Result = Success, "memory copy-part create failed");
         Conditions.If_Match := US.To_Unbounded_String
           ('"' & US.To_String (Target_ETag) & '"');
         Store.Copy_Multipart_Part
           ("multipart-bucket", "target", "multipart-bucket",
            "copied-part", US.To_String (Copy_ID), 1,
            (Kind  => Bounded_Range,
             First => Byte_Count (5 * MiB),
             Last  => Byte_Count (5 * MiB + 3),
             Count => 0),
            Conditions, null, Ada.Real_Time.Time_Last, Info, Result);
         Copy_ETag := Info.Entity_Tag;
         Assert
           (Result = Success and then Info.Size = 4
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 8),
            "memory ranged copy-part failed or leaked its snapshot");
         Conditions.If_Match := US.To_Unbounded_String ("wrong");
         Store.Copy_Multipart_Part
           ("multipart-bucket", "target", "multipart-bucket",
            "copied-part", US.To_String (Copy_ID), 1, Whole_Object,
            Conditions, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Precondition_Failed
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 8),
            "failed memory copy-part condition replaced or leaked a part");
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1, Entity_Tag => Copy_ETag));
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "copied-part", US.To_String (Copy_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success and then Info.Size = 4,
                 "memory copied-part completion failed");
         Store.Get_Object
           ("multipart-bucket", "copied-part", Whole_Object, Copied,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Copied.Data) = "tail",
            "memory copied-part body mismatch");
         Store.Delete_Object
           ("multipart-bucket", "copied-part", null,
            Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "memory copied-part cleanup leaked capacity");
      end;

      declare
         Small_ID : US.Unbounded_String;
         First_ETag, Last_ETag : US.Unbounded_String;
         Completion : Multipart_Part_References;
      begin
         Store.Create_Multipart_Upload
           ("multipart-bucket", "small", Default_Multipart_Options, null,
            Ada.Real_Time.Time_Last, Small_ID, Result);
         Assert (Result = Success, "small multipart create failed");
         Upload
           (US.To_String (Small_ID), "small", 1,
            Flyology.Bytes.From_Byte_String ("small"), First_ETag);
         Upload
           (US.To_String (Small_ID), "small", 1,
            Flyology.Bytes.From_Byte_String ("x"), First_ETag);
         Upload
           (US.To_String (Small_ID), "small", 2,
            Flyology.Bytes.From_Byte_String ("last"), Last_ETag);
         Assert
           (Store.Bytes_Used = Byte_Count (5 * MiB + 9),
            "replaced multipart part retained its old bytes");
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1, Entity_Tag => First_ETag));
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 2, Entity_Tag => Last_ETag));
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "small", US.To_String (Small_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Entity_Too_Small,
            "undersized nonfinal multipart part was accepted");
         declare
            Page : Multipart_Upload_Page;
            Options : constant List_Multipart_Uploads_Options :=
              (Prefix => US.To_Unbounded_String ("small"), others => <>);
            Conditions : Abort_Multipart_Conditions;
         begin
            Store.List_Multipart_Uploads
              ("multipart-bucket", Options, null,
               Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Success and then Page.Uploads.Length = 1
               and then US.To_String (Page.Uploads.First_Element.Upload_ID) =
                 US.To_String (Small_ID),
               "memory abort initiation lookup failed");
            Conditions :=
              (Has_Initiated_Time => True,
               Initiated_Time => Page.Uploads.First_Element.Initiated + 1);
            Store.Abort_Multipart_Upload
              ("multipart-bucket", "small", US.To_String (Small_ID),
               Conditions, null, Ada.Real_Time.Time_Last, Result);
            Assert
              (Result = Precondition_Failed
               and then Store.Bytes_Used = Byte_Count (5 * MiB + 9),
               "memory failed abort condition retired staged parts");
            Conditions.Initiated_Time :=
              Page.Uploads.First_Element.Initiated;
            Store.Abort_Multipart_Upload
              ("multipart-bucket", "small", US.To_String (Small_ID),
               Conditions, null, Ada.Real_Time.Time_Last, Result);
         end;
         Assert
           (Result = Success
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "memory multipart abort did not release staged bytes");
         Store.Abort_Multipart_Upload
           ("multipart-bucket", "small", US.To_String (Small_ID),
            Flyology.Object_Storage.Backends.No_Abort_Multipart_Conditions,
            null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Not_Found, "missing memory upload was not reported");
      end;

      declare
         Retry_ID : US.Unbounded_String;
         First_ETag, Last_ETag : US.Unbounded_String;
         Completion : Multipart_Part_References;
      begin
         Store.Create_Multipart_Upload
           ("multipart-bucket", "retry", Default_Multipart_Options, null,
            Ada.Real_Time.Time_Last, Retry_ID, Result);
         Assert (Result = Success, "retry multipart create failed");
         Upload
           (US.To_String (Retry_ID), "retry", 1,
            Repeated
              (5 * MiB,
               Ada.Streams.Stream_Element (Character'Pos ('r'))),
            First_ETag);
         Upload
           (US.To_String (Retry_ID), "retry", 2,
            Flyology.Bytes.From_Byte_String ("tail"), Last_ETag);
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1, Entity_Tag => First_ETag));
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 2, Entity_Tag => Last_ETag));
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "retry", US.To_String (Retry_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Capacity_Exceeded
            and then Store.Bytes_Used = Byte_Count (10 * MiB + 8),
            "capacity failure consumed multipart state or leaked assembly");
         Store.Delete_Object
           ("multipart-bucket", "target", null,
            Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "freeing completion headroom did not preserve staged upload");
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "retry", US.To_String (Retry_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "multipart completion was not retryable after capacity failure");
         declare
            Retained_Tags : Object_Tag_Set := Empty_Object_Tags;
         begin
            Retained_Tags.Length := 1;
            Retained_Tags.Items (1) :=
              (Key   => US.To_Unbounded_String ("generation"),
               Value => US.To_Unbounded_String ("multipart"));
            Store.Put_Object_Tags
              ("multipart-bucket", "retry", Retained_Tags, null,
               Ada.Real_Time.Time_Last, Result);
            Assert
              (Result = Success,
               "memory multipart object tag update failed");
         end;
         declare
            Options : Object_Attribute_Options :=
              (After => 0, Maximum => 1);
            Snapshot : Object_Attribute_Snapshot;
         begin
            Store.Get_Object_Attributes
              ("multipart-bucket", "retry", Options, null,
               Ada.Real_Time.Time_Last, Snapshot, Result);
            Assert
              (Result = Success and then Snapshot.Is_Multipart
               and then US.To_String (Snapshot.Info.Entity_Tag) =
                 US.To_String (Info.Entity_Tag)
               and then Snapshot.Total_Parts = 2
               and then Snapshot.Parts.Length = 1
               and then Snapshot.Parts.First_Element.Number = 1
               and then Snapshot.Parts.First_Element.Size =
                 Byte_Count (5 * MiB)
               and then Snapshot.Is_Truncated
               and then Snapshot.Next_After = 1,
               "memory completed attributes first page mismatch");
            Options.After := Snapshot.Next_After;
            Store.Get_Object_Attributes
              ("multipart-bucket", "retry", Options, null,
               Ada.Real_Time.Time_Last, Snapshot, Result);
            Assert
              (Result = Success and then Snapshot.Total_Parts = 2
               and then Snapshot.Parts.Length = 1
               and then Snapshot.Parts.First_Element.Number = 2
               and then Snapshot.Parts.First_Element.Size = 4
               and then not Snapshot.Is_Truncated,
               "memory completed attributes continuation mismatch");
         end;
      end;

      declare
         Cancel : aliased Flyology.Cancellation.Token;
         Ignored : US.Unbounded_String;
         Raised : Boolean := False;
      begin
         Cancel.Request;
         begin
            Store.Create_Multipart_Upload
              ("multipart-bucket", "cancelled", Default_Multipart_Options,
               Cancel'Access, Ada.Real_Time.Time_Last, Ignored, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled =>
               Raised := True;
         end;
         Assert (Raised, "memory multipart create ignored cancellation");
      end;
      declare
         Ignored : US.Unbounded_String;
         Raised : Boolean := False;
      begin
         begin
            Store.Create_Multipart_Upload
              ("multipart-bucket", "expired", Default_Multipart_Options,
               null, Ada.Real_Time.Time_First, Ignored, Result);
         exception
            when Flyology.IO.Timeout_Error =>
               Raised := True;
         end;
         Assert (Raised, "memory multipart create ignored deadline");
      end;

      Store.Delete_Object
        ("multipart-bucket", "retry", null,
         Ada.Real_Time.Time_Last, Result);
      Store.Delete_Bucket
        ("multipart-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert
        (Result = Success and then Store.Bytes_Used = 0,
         "memory multipart cleanup failed");
   end Check_Memory_Multipart;

   procedure Check_Ranges_And_Bounds (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      type Store_Access is access all Memory.Store;
      type Probing_Source is new Byte_Source with record
         Store            : Store_Access;
         Observed         : Boolean := False;
         Sent             : Boolean := False;
         Competing_Result : Status := Success;
      end record;
      overriding function Declared_Length
        (Item : Probing_Source) return Source_Length;
      overriding procedure Read
        (Item     : in out Probing_Source;
         Data     : out Ada.Streams.Stream_Element_Array;
         Last     : out Ada.Streams.Stream_Element_Offset;
         Finished : out Boolean;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time);

      overriding function Declared_Length
        (Item : Probing_Source) return Source_Length is
        (Kind => Known, Bytes => 4);

      overriding procedure Read
        (Item     : in out Probing_Source;
         Data     : out Ada.Streams.Stream_Element_Array;
         Last     : out Ada.Streams.Stream_Element_Offset;
         Finished : out Boolean;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time)
      is
         pragma Unreferenced (Token, Deadline);
         Competitor : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("1234567890123"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 13),
            Bad_Last => False);
         Ignored_Info : Object_Information;
      begin
         Item.Observed := Item.Store.Bytes_Used = 4;
         Item.Store.Put_Object
           ("abc", "competitor", Competitor, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Ignored_Info, Item.Competing_Result);
         Data := (others => 0);
         if Item.Sent then
            Last := Data'First - 1;
         else
            Data (Data'First .. Data'First + 3) := (others => 7);
            Last := Data'First + 3;
            Item.Sent := True;
         end if;
         Finished := True;
      end Read;

      Store  : aliased Memory.Store (1, 1, 16);
      Source : Buffer_Source :=
        (Data     => Flyology.Bytes.From_Byte_String ("abcdefgh"),
         Position => 0,
         Length   => (Kind => Unknown),
         Bad_Last => False);
      Sink   : Buffer_Sink;
      Info   : Object_Information;
      Result : Status;
   begin
      Store.Create_Bucket ("abc", null, Ada.Real_Time.Time_Last, Result);
      declare
         Probe : Probing_Source :=
           (Store => Store'Unchecked_Access, others => <>);
      begin
         Store.Put_Object
           ("abc", "probe", Probe, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Probe.Observed
            and then Probe.Competing_Result = Capacity_Exceeded
            and then Store.Bytes_Used = 4,
            "overlapping known-length reservations exceeded the byte cap");
         Store.Delete_Object
           ("abc", "probe", null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success and then Store.Bytes_Used = 0,
            "committed reservation was not released on delete");
      end;
      Store.Put_Object
        ("abc", "key", Source, Default_Put_Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Assert (Result = Success, "bounded put");
      declare
         Replacement : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("123456789"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 9),
            Bad_Last => False);
         Existing : Buffer_Sink;
      begin
         Store.Put_Object
           ("abc", "key", Replacement, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Capacity_Exceeded and then Store.Bytes_Used = 8,
            "overwrite bypassed payload-coexistence capacity");
         Store.Get_Object
           ("abc", "key", Whole_Object, Existing, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Existing.Data) =
              "abcdefgh",
            "failed overwrite changed the existing object");
      end;
      Store.Get_Object
        ("abc", "key",
         (Kind  => Bounded_Range,
          First => 2,
          Last  => 4,
          Count => 0),
         Sink, null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Success
         and then Flyology.Bytes.To_Byte_String (Sink.Data) = "cde",
         "bounded range");
      Assert
        (Sink.Begin_Count = 1
         and then not Sink.Write_Before_Begin
         and then Sink.First = 2
         and then Sink.Content_Length = 3
         and then Sink.Partial
         and then Sink.Snapshot.Size = 8,
         "memory announces resolved range before body");
      declare
         Suffix_Sink : Buffer_Sink;
      begin
         Store.Get_Object
           ("abc", "key",
            (Kind  => Suffix_Range,
             First => 0,
             Last  => 0,
             Count => 3),
            Suffix_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Suffix_Sink.Data) = "fgh"
            and then Suffix_Sink.Begin_Count = 1
            and then Suffix_Sink.First = 5
            and then Suffix_Sink.Content_Length = 3
            and then Suffix_Sink.Partial,
            "memory resolves a suffix against the streamed snapshot");
      end;
      Store.Get_Object
        ("abc", "key",
         (Kind  => Open_Ended_Range,
          First => 8,
          Last  => 0,
          Count => 0),
         Sink, null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Invalid_Range and then Sink.Begin_Count = 1,
         "invalid range must not announce an object");
      declare
         Too_Large : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("123456789"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 9),
            Bad_Last => False);
      begin
         Store.Put_Object
           ("abc", "other", Too_Large, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Capacity_Exceeded, "declared length bound");
      end;
      declare
         Malformed : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("x"),
            Position => 0,
            Length   => (Kind => Unknown),
            Bad_Last => True);
      begin
         Store.Put_Object
           ("abc", "other", Malformed, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Invalid_Request, "source cannot overrun buffer");
      end;
      Store.Delete_Object
        ("abc", "key", null, Ada.Real_Time.Time_Last, Result);
      declare
         Malformed : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("x"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 1),
            Bad_Last => True);
      begin
         Store.Put_Object
           ("abc", "failed", Malformed, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Invalid_Request and then Store.Bytes_Used = 0,
            "failed buffered put leaked transient reservation");
      end;
      declare
         Empty_Source : Buffer_Source :=
           (Data     => Flyology.Bytes.Empty,
            Position => 0,
            Length   => (Kind => Known, Bytes => 0),
            Bad_Last => False);
      begin
         Store.Put_Object
           ("abc", "empty", Empty_Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success and then Info.Size = 0, "empty object");
         declare
            Empty_Sink : Buffer_Sink;
         begin
            Store.Get_Object
              ("abc", "empty", Whole_Object, Empty_Sink, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Empty_Sink.Begin_Count = 1
               and then Empty_Sink.Content_Length = 0
               and then not Empty_Sink.Partial
               and then not Empty_Sink.Write_Before_Begin
               and then Ada.Strings.Unbounded.To_String
                 (Empty_Sink.Snapshot.Entity_Tag) =
                   "d41d8cd98f00b204e9800998ecf8427e"
               and then Flyology.Bytes.Length (Empty_Sink.Data) = 0,
               "memory announces an empty object without writes");
         end;
      end;

      declare
         Slack_Store : Memory.Store (1, 2, 40_000);
         Payload : constant String (1 .. 17_000) := (others => 'x');
         Unknown_Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0,
            Length   => (Kind => Unknown),
            Bad_Last => False);
         Competitor : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String
              (String'(1 .. 8_000 => 'y')),
            Position => 0,
            Length   => (Kind => Known, Bytes => 8_000),
            Bad_Last => False);
      begin
         Slack_Store.Create_Bucket
           ("slack", null, Ada.Real_Time.Time_Last, Result);
         Slack_Store.Put_Object
           ("slack", "unknown", Unknown_Source, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Info.Size = 17_000
            and then Slack_Store.Bytes_Used = 32_768,
            "unknown-length allocator slack was not retained in accounting");
         Slack_Store.Put_Object
           ("slack", "competitor", Competitor, Default_Put_Options, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Capacity_Exceeded
            and then Slack_Store.Bytes_Used = 32_768,
            "committed allocator slack allowed the physical cap to overflow");
         Slack_Store.Delete_Object
           ("slack", "unknown", null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success and then Slack_Store.Bytes_Used = 0,
            "deleting an unknown-length object leaked retained capacity");
      end;
   end Check_Ranges_And_Bounds;

   procedure Check_Filesystem_Conformance (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package Files renames Flyology.Object_Storage.Backends.Files;
      package US renames Ada.Strings.Unbounded;
      Root : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "obj"),
           "fs-conformance");
      Key : constant String := "../../opaque/%2F/key";
      Upload_ID : US.Unbounded_String;
      Part_ETag : US.Unbounded_String;
      Abort_ID  : US.Unbounded_String;

      procedure Clean is
      begin
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
      end Clean;
   begin
      Clean;
      Assert
        (Flyology.Object_Storage.Durability_Testing.Missing_File_Is_Rejected
           (Ada.Directories.Compose (Root, "missing-sync-target")),
         "durability adapter accepted a missing file");
      declare
         Atomic_Root : constant String :=
           Ada.Directories.Compose
             (Ada.Directories.Compose (Root, "nested"), "atomic");
         Store : Files.Store :=
           Files.Open
             (Atomic_Root, Maximum_Object_Size => 64,
              Commit => Files.Process_Crash_Atomic);
         Result : Status;
      begin
         Assert
           (Ada.Directories.Exists
              (Ada.Directories.Compose (Atomic_Root, "buckets"))
            and then Ada.Directories.Exists
              (Ada.Directories.Compose (Atomic_Root, "tmp")),
            "atomic commit policy did not initialize a nested root");
         Store.Create_Bucket
           ("atomic-policy-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "atomic commit policy create bucket");
         Store.Delete_Bucket
           ("atomic-policy-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "atomic commit policy delete bucket");
      end;
      Clean;
      declare
         Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("first body"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 10),
            Bad_Last => False);
         Info   : Object_Information;
         Result : Status;
      begin
         Exercise_Multipart_Upload_Listing (Store, "file-multipart-list");
         Store.Create_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files create bucket");
         Store.Head_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "head existing files bucket");
         Exercise_Bucket_Tags (Store, "file-bucket");
         Store.Put_Object
           ("file-bucket", Key, Source,
            (Entity_Tag   => US.To_Unbounded_String ("etag-1"),
             Content_Type => US.To_Unbounded_String ("text/plain")),
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Info.Size = 10,
            "files put: " & Status'Image (Result));
         declare
            Replacement : Buffer_Source :=
              (Data     => Flyology.Bytes.From_Byte_String ("second body"),
               Position => 0,
               Length   => (Kind => Known, Bytes => 11),
               Bad_Last => False);
         begin
            Store.Put_Object
              ("file-bucket", Key, Replacement,
               (Entity_Tag   => US.To_Unbounded_String ("etag-2"),
                Content_Type => US.To_Unbounded_String ("text/plain")),
               null, Ada.Real_Time.Time_Last, Info, Result);
            Assert (Result = Success, "files atomic overwrite");
         end;
         declare
            Empty_Source : Buffer_Source :=
              (Data     => Flyology.Bytes.Empty,
               Position => 0,
               Length   => (Kind => Known, Bytes => 0),
               Bad_Last => False);
         begin
            Store.Put_Object
              ("file-bucket", "empty", Empty_Source, Default_Put_Options,
               null, Ada.Real_Time.Time_Last, Info, Result);
            Assert (Result = Success, "files empty put");
         end;
         Store.Create_Multipart_Upload
           ("file-bucket", "multipart-target",
            (Content_Type =>
               US.To_Unbounded_String ("application/x-multipart-test")),
            null, Ada.Real_Time.Time_Last, Upload_ID, Result);
         Assert (Result = Success, "files multipart create");
         declare
            Part_Source : Buffer_Source :=
              (Data     => Flyology.Bytes.From_Byte_String
                 ("multipart body"),
               Position => 0,
               Length   => (Kind => Known, Bytes => 14),
               Bad_Last => False);
         begin
            Store.Put_Multipart_Part
              ("file-bucket", "multipart-target",
               US.To_String (Upload_ID), 1, Part_Source, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Part_ETag := Info.Entity_Tag;
            Assert
              (Result = Success and then Info.Size = 14,
               "files multipart part upload");
         end;
         declare
            Part_Source : Buffer_Source :=
              (Data     => Flyology.Bytes.From_Byte_String ("later"),
               Position => 0,
               Length   => (Kind => Known, Bytes => 5),
               Bad_Last => False);
         begin
            Store.Put_Multipart_Part
              ("file-bucket", "multipart-target",
               US.To_String (Upload_ID), 3, Part_Source, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success and then Info.Size = 5,
               "files sparse multipart part upload");
         end;
         Store.Create_Multipart_Upload
           ("file-bucket", "aborted-target", Default_Multipart_Options,
            null, Ada.Real_Time.Time_Last, Abort_ID, Result);
         Assert (Result = Success, "files second multipart create");
      end;
      declare
         Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
         Info  : Object_Information;
         Result : Status;
         Sink   : Buffer_Sink;
      begin
         Store.Head_Object
           ("file-bucket", Key, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Info.Size = 11
            and then US.To_String (Info.Entity_Tag) = "etag-2",
            "files metadata persists across reopen");
         declare
            Snapshot : Object_Attribute_Snapshot;
         begin
            Store.Get_Object_Attributes
              ("file-bucket", Key, (others => <>), null,
               Ada.Real_Time.Time_Last, Snapshot, Result);
            Assert
              (Result = Success and then not Snapshot.Is_Multipart
               and then Snapshot.Total_Parts = 0
               and then Snapshot.Parts.Is_Empty
               and then Snapshot.Info.Size = 11,
               "ordinary files object exposed multipart attributes");
         end;
         Exercise_Conditional_Read (Store, "file-bucket", Key);
         declare
            Page : Multipart_Part_Page;
            Options : List_Multipart_Parts_Options :=
              (After => 0, Maximum => 1);
         begin
            Store.List_Multipart_Parts
              ("file-bucket", "multipart-target", US.To_String (Upload_ID),
               Options, null, Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Success and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Number = 1
               and then Page.Parts.First_Element.Info.Size = 14
               and then Page.Is_Truncated and then Page.Next_After = 1,
               "files persisted ListParts first page failed");
            Options.After := Page.Next_After;
            Store.List_Multipart_Parts
              ("file-bucket", "multipart-target", US.To_String (Upload_ID),
               Options, null, Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Success and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Number = 3
               and then Page.Parts.First_Element.Info.Size = 5
               and then not Page.Is_Truncated,
               "files persisted ListParts continuation failed");
         end;
         declare
            Options : Copy_Options := Default_Copy_Options;
            Copy_Sink : Buffer_Sink;
         begin
            Options.Conditions.If_Match :=
              US.To_Unbounded_String
                ('"' & US.To_String (Info.Entity_Tag) & '"');
            Store.Copy_Object
              ("file-bucket", Key, "file-bucket", "copied", Options,
               null, Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success and then Info.Size = 11
               and then US.To_String (Info.Content_Type) = "text/plain",
               "files copy did not preserve content metadata");
            Store.Get_Object
              ("file-bucket", "copied", Whole_Object, Copy_Sink, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Flyology.Bytes.To_Byte_String (Copy_Sink.Data) =
                 "second body",
               "files copy body mismatch");
            Options.Conditions.If_Match := US.To_Unbounded_String ("wrong");
            Store.Copy_Object
              ("file-bucket", Key, "file-bucket", "copied", Options,
               null, Ada.Real_Time.Time_Last, Info, Result);
            Assert (Result = Precondition_Failed,
                    "files copy accepted a failed source condition");
            Store.Copy_Object
              ("file-bucket", "missing", "file-bucket", "copied",
               Default_Copy_Options, null, Ada.Real_Time.Time_Last,
               Info, Result);
            Assert (Result = Source_Not_Found,
                    "files copy source absence was ambiguous");
         end;
         declare
            Copy_ID : US.Unbounded_String;
            Copy_ETag : US.Unbounded_String;
            Completion : Multipart_Part_References;
            Copy_Sink : Buffer_Sink;
         begin
            Store.Create_Multipart_Upload
              ("file-bucket", "copy-part-target",
               Default_Multipart_Options, null,
               Ada.Real_Time.Time_Last, Copy_ID, Result);
            Assert (Result = Success, "files copy-part create failed");
            Store.Copy_Multipart_Part
              ("file-bucket", Key, "file-bucket", "copy-part-target",
               US.To_String (Copy_ID), 1,
               (Kind => Bounded_Range, First => 7, Last => 10, Count => 0),
               (others => <>), null, Ada.Real_Time.Time_Last, Info, Result);
            Copy_ETag := Info.Entity_Tag;
            Assert
              (Result = Success and then Info.Size = 4,
               "files ranged copy-part failed");
            Store.Copy_Multipart_Part
              ("file-bucket", Key, "file-bucket", "copy-part-target",
               US.To_String (Copy_ID), 2,
               (Kind => Bounded_Range, First => 99, Last => 100, Count => 0),
               (others => <>), null, Ada.Real_Time.Time_Last, Info, Result);
            Assert (Result = Invalid_Range,
                    "files copy-part accepted an invalid source range");
            Completion.Append
              (Multipart_Part_Reference'
                 (Number => 1, Entity_Tag => Copy_ETag));
            Store.Complete_Multipart_Upload
              ("file-bucket", "copy-part-target", US.To_String (Copy_ID),
               Completion, null, Ada.Real_Time.Time_Last, Info, Result);
            Store.Get_Object
              ("file-bucket", "copy-part-target", Whole_Object, Copy_Sink,
               null, Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Flyology.Bytes.To_Byte_String (Copy_Sink.Data) =
                 "body",
               "files copied-part completion body mismatch");
            Store.Delete_Object
              ("file-bucket", "copy-part-target", null,
               Ada.Real_Time.Time_Last, Result);
            Assert (Result = Success, "files copied-part cleanup failed");
         end;
         declare
            Completion : Multipart_Part_References;
            Multipart_Sink : Buffer_Sink;
         begin
            Completion.Append
              (Multipart_Part_Reference'
                 (Number => 1, Entity_Tag => Part_ETag));
            declare
               Options : Complete_Multipart_Options :=
                 Default_Complete_Multipart_Options;
            begin
               Options.Expected_Size := (Kind => Known, Bytes => 15);
               Store.Complete_Multipart_Upload
                 ("file-bucket", "multipart-target",
                  US.To_String (Upload_ID), Completion, Options, null,
                  Ada.Real_Time.Time_Last, Info, Result);
               Assert
                 (Result = Invalid_Request,
                  "files wrong multipart object size consumed upload");
               Options.Expected_Size.Bytes := 14;
               Options.Conditions.If_None_Match :=
                 US.To_Unbounded_String ("*");
               Store.Complete_Multipart_Upload
                 ("file-bucket", "multipart-target",
                  US.To_String (Upload_ID), Completion, Options, null,
                  Ada.Real_Time.Time_Last, Info, Result);
            end;
            Assert
              (Result = Success
               and then Info.Size = 14
               and then US.To_String (Info.Content_Type) =
                 "application/x-multipart-test",
               "files multipart completion persisted across reopen");
            declare
               Retained_Tags : Object_Tag_Set := Empty_Object_Tags;
            begin
               Retained_Tags.Length := 1;
               Retained_Tags.Items (1) :=
                 (Key   => US.To_Unbounded_String ("generation"),
                  Value => US.To_Unbounded_String ("multipart"));
               Store.Put_Object_Tags
                 ("file-bucket", "multipart-target", Retained_Tags, null,
                  Ada.Real_Time.Time_Last, Result);
               Assert
                 (Result = Success,
                  "files multipart object tag update failed");
            end;
            declare
               Snapshot : Object_Attribute_Snapshot;
            begin
               Store.Get_Object_Attributes
                 ("file-bucket", "multipart-target", (others => <>), null,
                  Ada.Real_Time.Time_Last, Snapshot, Result);
               Assert
                 (Result = Success and then Snapshot.Is_Multipart
                  and then Snapshot.Total_Parts = 1
                  and then Snapshot.Parts.Length = 1
                  and then Snapshot.Parts.First_Element.Number = 1
                  and then Snapshot.Parts.First_Element.Size = 14
                  and then US.To_String (Snapshot.Info.Entity_Tag) =
                    US.To_String (Info.Entity_Tag),
                  "files completed object attributes mismatch");
            end;
            Store.Get_Object
              ("file-bucket", "multipart-target", Whole_Object,
               Multipart_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Flyology.Bytes.To_Byte_String
                 (Multipart_Sink.Data) = "multipart body",
               "files multipart completion body");
            declare
               Page : Multipart_Upload_Page;
               Options : constant List_Multipart_Uploads_Options :=
                 (Prefix => US.To_Unbounded_String ("aborted-target"),
                  others => <>);
               Conditions : Abort_Multipart_Conditions;
            begin
               Store.List_Multipart_Uploads
                 ("file-bucket", Options, null,
                  Ada.Real_Time.Time_Last, Page, Result);
               Assert
                 (Result = Success and then Page.Uploads.Length = 1
                  and then US.To_String
                    (Page.Uploads.First_Element.Upload_ID) =
                      US.To_String (Abort_ID),
                  "files abort initiation lookup failed");
               Conditions :=
                 (Has_Initiated_Time => True,
                  Initiated_Time => Page.Uploads.First_Element.Initiated + 1);
               Store.Abort_Multipart_Upload
                 ("file-bucket", "aborted-target", US.To_String (Abort_ID),
                  Conditions, null, Ada.Real_Time.Time_Last, Result);
               Assert
                 (Result = Precondition_Failed,
                  "files failed abort condition retired upload");
               Conditions.Initiated_Time :=
                 Page.Uploads.First_Element.Initiated;
               Store.Abort_Multipart_Upload
                 ("file-bucket", "aborted-target", US.To_String (Abort_ID),
                  Conditions, null, Ada.Real_Time.Time_Last, Result);
            end;
            Assert (Result = Success, "files persisted multipart abort");
            Store.Abort_Multipart_Upload
              ("file-bucket", "aborted-target", US.To_String (Abort_ID),
               Flyology.Object_Storage.Backends.No_Abort_Multipart_Conditions,
               null, Ada.Real_Time.Time_Last, Result);
            Assert (Result = Not_Found, "files missing multipart upload");
         end;
         Store.Get_Object
           ("file-bucket", Key,
            (Kind  => Bounded_Range,
             First => 7,
             Last  => 10,
             Count => 0),
            Sink, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Sink.Data) = "body",
            "files range read");
         Assert
           (Sink.Begin_Count = 1
            and then not Sink.Write_Before_Begin
            and then Sink.First = 7
            and then Sink.Content_Length = 4
            and then Sink.Partial
            and then Sink.Snapshot.Size = 11,
            "files announce resolved range before body");
         declare
            Suffix_Sink : Buffer_Sink;
         begin
            Store.Get_Object
              ("file-bucket", Key,
               (Kind  => Suffix_Range,
                First => 0,
                Last  => 0,
                Count => 4),
               Suffix_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Flyology.Bytes.To_Byte_String (Suffix_Sink.Data) =
                 "body"
               and then Suffix_Sink.Begin_Count = 1
               and then Suffix_Sink.First = 7
               and then Suffix_Sink.Content_Length = 4
               and then Suffix_Sink.Partial,
               "files resolve a suffix against the streamed snapshot");
         end;
         declare
            Empty_Sink : Buffer_Sink;
         begin
            Store.Get_Object
              ("file-bucket", "empty", Whole_Object, Empty_Sink, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Empty_Sink.Begin_Count = 1
               and then Empty_Sink.Content_Length = 0
               and then not Empty_Sink.Partial
               and then US.To_String (Empty_Sink.Snapshot.Entity_Tag) =
                 "d41d8cd98f00b204e9800998ecf8427e"
               and then Flyology.Bytes.Length (Empty_Sink.Data) = 0,
               "files announce an empty object without writes");
         end;
         declare
            Bad_Sink : Raising_Sink;
            Propagated : Boolean := False;
         begin
            begin
               Store.Get_Object
                 ("file-bucket", Key, Whole_Object, Bad_Sink, null,
                  Ada.Real_Time.Time_Last, Info, Result);
            exception
               when Program_Error =>
                  Propagated := True;
            end;
            Assert (Propagated, "sink exception propagates");
         end;
         Store.Delete_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Bucket_Not_Empty, "files nonempty bucket");
         Store.Delete_Object
           ("file-bucket", Key, null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files delete object");
         Store.Delete_Object
           ("file-bucket", "empty", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files delete empty object");
         Store.Delete_Object
           ("file-bucket", "multipart-target", null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files delete multipart object");
         Store.Delete_Object
           ("file-bucket", "copied", null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files delete copied object");
         Store.Delete_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files delete bucket");
         Store.Head_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Not_Found, "head deleted files bucket");
      end;
      Clean;
   exception
      when others =>
         Clean;
         raise;
   end Check_Filesystem_Conformance;

   procedure Check_Filesystem_Durability_Faults
     (Unused : in out Fixture)
   is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package Files renames Flyology.Object_Storage.Backends.Files;
      package Faults renames Flyology.Object_Storage.Durability_Testing;
      package US renames Ada.Strings.Unbounded;
      Base : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "obj"),
           "fs-durability-faults");

      function Path (Name : String; Point : Natural) return String is
        (Ada.Directories.Compose
           (Base, Name & "-" & Ada.Strings.Fixed.Trim
              (Natural'Image (Point), Ada.Strings.Both)));

      procedure Clean (Root : String) is
      begin
         Faults.Clear_Failure;
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
      end Clean;

      procedure Create_Bucket
        (Store : in out Files.Store; Result : out Status)
      is
      begin
         Store.Create_Bucket
           ("durability-bucket", null, Ada.Real_Time.Time_Last, Result);
      end Create_Bucket;

      procedure Put
        (Store  : in out Files.Store;
         Key    : String;
         Payload : String;
         Result : out Status)
      is
         Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String (Payload),
            Position => 0,
            Length   => (Kind => Known, Bytes => Payload'Length),
            Bad_Last => False);
         Info : Object_Information;
      begin
         Store.Put_Object
           ("durability-bucket", Key, Source, Default_Put_Options,
            null, Ada.Real_Time.Time_Last, Info, Result);
      end Put;

      procedure Count_Uploads
        (Store  : in out Files.Store;
         Count  : out Natural;
         Result : out Status)
      is
         Page : Multipart_Upload_Page;
      begin
         Store.List_Multipart_Uploads
           ("durability-bucket", (others => <>), null,
            Ada.Real_Time.Time_Last, Page, Result);
         Count := Natural (Page.Uploads.Length);
      end Count_Uploads;
   begin
      if Ada.Directories.Exists (Base) then
         Ada.Directories.Delete_Tree (Base);
      end if;

      for Point in 0 .. 11 loop
         declare
            Root : constant String := Path ("bucket", Point);
            Result : Status;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
            begin
               Faults.Fail_Next_Barrier_After (Point);
               Create_Bucket (Store, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 10 then Backend_Unavailable else Success),
               "bucket creation durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Observed : Status;
            begin
               Store.Head_Bucket
                 ("durability-bucket", null, Ada.Real_Time.Time_Last,
                  Observed);
               Assert
                 (Observed in Success | Not_Found,
                  "bucket sync fault exposed malformed namespace");
               if Result = Success then
                  Assert (Observed = Success,
                          "successful durable bucket was not observable");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 4 loop
         declare
            Root : constant String := Path ("tags", Point);
            Result : Status;
            Old_Value : Flyology.Object_Storage.Tags.Tag_Set;
            New_Value : Flyology.Object_Storage.Tags.Tag_Set;
         begin
            Old_Value.Append
              (Flyology.Object_Storage.Tags.Tag'
                 (Key   => US.To_Unbounded_String ("state"),
                  Value => US.To_Unbounded_String ("old")));
            New_Value.Append
              (Flyology.Object_Storage.Tags.Tag'
                 (Key   => US.To_Unbounded_String ("state"),
                  Value => US.To_Unbounded_String ("replacement")));
            declare
               Store : Files.Store := Files.Open (Root);
            begin
               Create_Bucket (Store, Result);
               Assert (Result = Success, "tag fault setup bucket");
               Store.Put_Bucket_Tags
                 ("durability-bucket", Old_Value, null,
                  Ada.Real_Time.Time_Last, Result);
               Assert (Result = Success, "tag fault setup value");
               Faults.Fail_Next_Barrier_After (Point);
               Store.Put_Bucket_Tags
                 ("durability-bucket", New_Value, null,
                  Ada.Real_Time.Time_Last, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 3 then Backend_Unavailable else Success),
               "tag publication durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Observed : Flyology.Object_Storage.Tags.Tag_Set;
               Read_Result : Status;
               Text : US.Unbounded_String;
            begin
               Store.Get_Bucket_Tags
                 ("durability-bucket", null, Ada.Real_Time.Time_Last,
                  Observed, Read_Result);
               if Read_Result = Success and then Observed.Length = 1 then
                  Text := Observed.First_Element.Value;
               end if;
               Assert
                 (Read_Result = Success and then Observed.Length = 1
                  and then US.To_String (Text) in "old" | "replacement",
                  "tag sync fault exposed a partial tag set");
               if Result = Success then
                  Assert
                    (US.To_String (Text) = "replacement",
                     "successful durable tag put retained old set");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 4 loop
         declare
            Root : constant String := Path ("put", Point);
            Result : Status;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
            begin
               Create_Bucket (Store, Result);
               Assert (Result = Success, "put fault setup bucket");
               Put (Store, "object", "old", Result);
               Assert (Result = Success, "put fault setup object");
               Faults.Fail_Next_Barrier_After (Point);
               Put (Store, "object", "replacement", Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 3 then Backend_Unavailable else Success),
               "object publication durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Sink : Buffer_Sink;
               Info : Object_Information;
               Observed : Status;
            begin
               Store.Get_Object
                 ("durability-bucket", "object", Whole_Object, Sink, null,
                  Ada.Real_Time.Time_Last, Info, Observed);
               declare
                  Payload : constant String :=
                    Flyology.Bytes.To_Byte_String (Sink.Data);
               begin
                  Assert
                    (Observed = Success
                     and then
                       (Payload = "old" or else Payload = "replacement"),
                     "put sync fault exposed partial object");
                  if Result = Success then
                     Assert (Payload = "replacement",
                             "successful durable put retained old body");
                  end if;
               end;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 4 loop
         declare
            Root : constant String := Path ("tags", Point);
            Result : Status;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
               Old_Tags : Object_Tag_Set := Empty_Object_Tags;
               New_Tags : Object_Tag_Set := Empty_Object_Tags;
            begin
               Create_Bucket (Store, Result);
               Put (Store, "object", "body", Result);
               Assert (Result = Success, "tag fault setup object");
               Old_Tags.Length := 1;
               Old_Tags.Items (1) :=
                 (Key => US.To_Unbounded_String ("state"),
                  Value => US.To_Unbounded_String ("old"));
               Store.Put_Object_Tags
                 ("durability-bucket", "object", Old_Tags, null,
                  Ada.Real_Time.Time_Last, Result);
               Assert (Result = Success, "tag fault setup old set");
               New_Tags.Length := 1;
               New_Tags.Items (1) :=
                 (Key => US.To_Unbounded_String ("state"),
                  Value => US.To_Unbounded_String ("new"));
               Faults.Fail_Next_Barrier_After (Point);
               Store.Put_Object_Tags
                 ("durability-bucket", "object", New_Tags, null,
                  Ada.Real_Time.Time_Last, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 3 then Backend_Unavailable else Success),
               "object-tag publication durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Tags : Object_Tag_Set;
               Observed : Status;
            begin
               Store.Get_Object_Tags
                 ("durability-bucket", "object", null,
                  Ada.Real_Time.Time_Last, Tags, Observed);
               Assert
                  (Observed = Success and then Tags.Length = 1
                  and then US.To_String (Tags.Items (1).Key) = "state"
                  and then US.To_String (Tags.Items (1).Value)
                    in "old" | "new",
                  "tag sync fault exposed a partial tag set");
               if Result = Success then
                  Assert
                    (US.To_String (Tags.Items (1).Value) = "new",
                     "successful durable tag replacement retained old set");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 2 loop
         declare
            Root : constant String := Path ("delete", Point);
            Result : Status;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
            begin
               Create_Bucket (Store, Result);
               Put (Store, "object", "body", Result);
               Assert (Result = Success, "delete fault setup object");
               Faults.Fail_Next_Barrier_After (Point);
               Store.Delete_Object
                 ("durability-bucket", "object", null,
                  Ada.Real_Time.Time_Last, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 1 then Backend_Unavailable else Success),
               "object deletion durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Info : Object_Information;
               Observed : Status;
            begin
               Store.Head_Object
                 ("durability-bucket", "object", null,
                  Ada.Real_Time.Time_Last, Info, Observed);
               Assert
                 (Observed in Success | Not_Found,
                  "delete sync fault exposed malformed object");
               if Result = Success then
                  Assert (Observed = Not_Found,
                          "successful durable delete remained visible");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 7 loop
         declare
            Root : constant String := Path ("initiate", Point);
            Result : Status;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
               Upload_ID : US.Unbounded_String;
            begin
               Create_Bucket (Store, Result);
               Faults.Fail_Next_Barrier_After (Point);
               Store.Create_Multipart_Upload
                 ("durability-bucket", "object", Default_Multipart_Options,
                  null, Ada.Real_Time.Time_Last, Upload_ID, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 6 then Backend_Unavailable else Success),
               "multipart initiation durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Count : Natural;
               Observed : Status;
            begin
               Count_Uploads (Store, Count, Observed);
               Assert
                 (Observed = Success and then Count in 0 .. 1,
                  "initiation sync fault exposed malformed upload");
               if Result = Success then
                  Assert (Count = 1,
                          "successful durable initiation disappeared");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 4 loop
         declare
            Root : constant String := Path ("part", Point);
            Result : Status;
            Upload_ID : US.Unbounded_String;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
               Old_Source : Buffer_Source :=
                 (Data     => Flyology.Bytes.From_Byte_String ("old"),
                  Position => 0,
                  Length   => (Kind => Known, Bytes => 3),
                  Bad_Last => False);
               New_Source : Buffer_Source :=
                 (Data     => Flyology.Bytes.From_Byte_String ("new-part"),
                  Position => 0,
                  Length   => (Kind => Known, Bytes => 8),
                  Bad_Last => False);
               Info : Object_Information;
            begin
               Create_Bucket (Store, Result);
               Store.Create_Multipart_Upload
                 ("durability-bucket", "object", Default_Multipart_Options,
                  null, Ada.Real_Time.Time_Last, Upload_ID, Result);
               Store.Put_Multipart_Part
                 ("durability-bucket", "object", US.To_String (Upload_ID),
                  1, Old_Source, null, Ada.Real_Time.Time_Last, Info, Result);
               Assert (Result = Success, "part fault setup old part");
               Faults.Fail_Next_Barrier_After (Point);
               Store.Put_Multipart_Part
                 ("durability-bucket", "object", US.To_String (Upload_ID),
                  1, New_Source, null, Ada.Real_Time.Time_Last, Info, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 3 then Backend_Unavailable else Success),
               "multipart part durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Page : Multipart_Part_Page;
               Observed : Status;
            begin
               Store.List_Multipart_Parts
                 ("durability-bucket", "object", US.To_String (Upload_ID),
                  (After => 0, Maximum => 2), null,
                  Ada.Real_Time.Time_Last, Page, Observed);
               Assert
                 (Observed = Success
                  and then Page.Parts.Length = 1
                  and then Page.Parts.First_Element.Info.Size in 3 | 8,
                  "part sync fault exposed partial replacement");
               if Result = Success then
                  Assert
                    (Page.Parts.First_Element.Info.Size = 8,
                     "successful durable part replacement retained old part");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 2 loop
         declare
            Root : constant String := Path ("abort", Point);
            Result : Status;
            Upload_ID : US.Unbounded_String;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
            begin
               Create_Bucket (Store, Result);
               Store.Create_Multipart_Upload
                 ("durability-bucket", "object", Default_Multipart_Options,
                  null, Ada.Real_Time.Time_Last, Upload_ID, Result);
               Faults.Fail_Next_Barrier_After (Point);
               Store.Abort_Multipart_Upload
                 ("durability-bucket", "object", US.To_String (Upload_ID),
                  (others => <>),
                  null, Ada.Real_Time.Time_Last, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 1 then Backend_Unavailable else Success),
               "multipart abort durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Count : Natural;
               Observed : Status;
            begin
               Count_Uploads (Store, Count, Observed);
               Assert
                 (Observed = Success and then Count in 0 .. 1,
                  "abort sync fault exposed malformed upload namespace");
               if Result = Success then
                  Assert (Count = 0,
                          "successful durable abort remained visible");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 2 loop
         declare
            Root : constant String := Path ("delete-bucket", Point);
            Result : Status;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
            begin
               Create_Bucket (Store, Result);
               Faults.Fail_Next_Barrier_After (Point);
               Store.Delete_Bucket
                 ("durability-bucket", null, Ada.Real_Time.Time_Last,
                  Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 1 then Backend_Unavailable else Success),
               "bucket deletion durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Observed : Status;
            begin
               Store.Head_Bucket
                 ("durability-bucket", null, Ada.Real_Time.Time_Last,
                  Observed);
               Assert
                 (Observed in Success | Not_Found,
                  "bucket delete sync fault exposed malformed namespace");
               if Result = Success then
                  Assert (Observed = Not_Found,
                          "successful durable bucket delete remained visible");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      for Point in 0 .. 5 loop
         declare
            Root : constant String := Path ("complete", Point);
            Result : Status;
            Upload_ID : US.Unbounded_String;
            Part_ETag : US.Unbounded_String;
         begin
            declare
               Store : Files.Store := Files.Open (Root);
               Source : Buffer_Source :=
                 (Data     => Flyology.Bytes.From_Byte_String ("part-body"),
                  Position => 0,
                  Length   => (Kind => Known, Bytes => 9),
                  Bad_Last => False);
               Info : Object_Information;
               Parts : Multipart_Part_References;
            begin
               Create_Bucket (Store, Result);
               Store.Create_Multipart_Upload
                 ("durability-bucket", "object", Default_Multipart_Options,
                  null, Ada.Real_Time.Time_Last, Upload_ID, Result);
               Store.Put_Multipart_Part
                 ("durability-bucket", "object", US.To_String (Upload_ID),
                  1, Source, null, Ada.Real_Time.Time_Last, Info, Result);
               Assert (Result = Success, "completion fault setup part");
               Part_ETag := Info.Entity_Tag;
               Parts.Append
                 (Multipart_Part_Reference'
                    (Number => 1, Entity_Tag => Part_ETag));
               Faults.Fail_Next_Barrier_After (Point);
               Store.Complete_Multipart_Upload
                 ("durability-bucket", "object", US.To_String (Upload_ID),
                  Parts, null, Ada.Real_Time.Time_Last, Info, Result);
               Faults.Clear_Failure;
            end;
            Assert
              (Result =
                 (if Point < 4 then Backend_Unavailable else Success),
               "multipart completion durability barrier count changed");
            declare
               Store : Files.Store := Files.Open (Root);
               Info : Object_Information;
               Object_Status : Status;
               Upload_Status : Status;
               Upload_Count : Natural;
            begin
               Store.Head_Object
                 ("durability-bucket", "object", null,
                  Ada.Real_Time.Time_Last, Info, Object_Status);
               Count_Uploads (Store, Upload_Count, Upload_Status);
               Assert
                 (Upload_Status = Success
                  and then Object_Status in Success | Not_Found
                  and then Upload_Count in 0 .. 1
                  and then not
                    (Object_Status = Not_Found
                     and then Upload_Count = 0),
                  "completion sync fault lost both object and upload");
               if Result = Success then
                  Assert
                    (Object_Status = Success and then Upload_Count = 0,
                     "successful durable completion was not final");
               end if;
            end;
            Clean (Root);
         exception
            when others =>
               Clean (Root);
               raise;
         end;
      end loop;

      if Ada.Directories.Exists (Base) then
         Ada.Directories.Delete_Tree (Base);
      end if;
   exception
      when others =>
         Faults.Clear_Failure;
         if Ada.Directories.Exists (Base) then
            Ada.Directories.Delete_Tree (Base);
         end if;
         raise;
   end Check_Filesystem_Durability_Faults;

   procedure Check_Backend_Listings (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      package Files renames Flyology.Object_Storage.Backends.Files;
      Root : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "obj"),
           "fs-listing-conformance");
      Persisted_Created : Flyology.Object_Storage.Unix_Time := 0;

      procedure Clean is
      begin
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
      end Clean;
   begin
      declare
         Store : Memory.Store (8, 16, 128);
      begin
         Exercise_Bucket_Listing (Store);
         Exercise_Listing (Store, "memory-list-bucket");
      end;
      Clean;
      declare
         Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
         Options : Flyology.Object_Storage.Backends.List_Buckets_Options;
         Page : Flyology.Object_Storage.Backends.Bucket_Page;
         Status : Flyology.Object_Storage.Status;
      begin
         Exercise_Bucket_Listing (Store);
         Exercise_Listing (Store, "files-list-bucket");
         Store.Create_Bucket
           ("files-persisted-bucket", null, Ada.Real_Time.Time_Last, Status);
         AUnit.Assertions.Assert
           (Status = Flyology.Object_Storage.Success,
            "files persistent listing bucket create");
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Page, Status);
         AUnit.Assertions.Assert
           (Status = Flyology.Object_Storage.Success
            and then Page.Buckets.Length = 1,
            "files persistent listing first snapshot");
         Persisted_Created := Page.Buckets.First_Element.Created;
      end;
      declare
         Stale : constant String :=
           Ada.Directories.Compose
             (Ada.Directories.Compose (Root, "tmp"), "stale-bucket-stage");
      begin
         Ada.Directories.Create_Path
           (Ada.Directories.Compose (Stale, "objects"));
      end;
      declare
         Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
         Options : Flyology.Object_Storage.Backends.List_Buckets_Options;
         Page : Flyology.Object_Storage.Backends.Bucket_Page;
         Status : Flyology.Object_Storage.Status;
      begin
         AUnit.Assertions.Assert
           (not Ada.Directories.Exists
              (Ada.Directories.Compose
                 (Ada.Directories.Compose (Root, "tmp"),
                  "stale-bucket-stage")),
            "files open retained an interrupted staging directory");
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Page, Status);
         AUnit.Assertions.Assert
           (Status = Flyology.Object_Storage.Success
            and then Page.Buckets.Length = 1
            and then Page.Buckets.First_Element.Created = Persisted_Created,
            "files bucket creation time survives reopen");
         Store.Delete_Bucket
           ("files-persisted-bucket", null, Ada.Real_Time.Time_Last, Status);
         AUnit.Assertions.Assert
           (Status = Flyology.Object_Storage.Success,
            "files persistent listing cleanup");
         declare
            Partial : constant String :=
              Ada.Directories.Compose
                (Ada.Directories.Compose
                   (Ada.Directories.Compose (Root, "buckets"),
                    "partial-bucket"),
                 "objects");
         begin
            Ada.Directories.Create_Path (Partial);
            Store.List_Buckets
              (Options, null, Ada.Real_Time.Time_Last, Page, Status);
            AUnit.Assertions.Assert
              (Status = Flyology.Object_Storage.Backend_Unavailable
               and then Page.Buckets.Is_Empty,
               "files listing accepted a partial bucket artifact");
         end;
      end;
      Clean;
   exception
      when others =>
         Clean;
         raise;
   end Check_Backend_Listings;

   procedure Check_Backend_Delete_Objects (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      package Files renames Flyology.Object_Storage.Backends.Files;
      Root : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "obj"),
           "fs-delete-objects-conformance");

      procedure Clean is
      begin
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
      end Clean;
   begin
      declare
         Store : Memory.Store (4, 16, 256);
      begin
         Exercise_Delete_Objects (Store, "memory-delete-objects-bucket");
      end;
      Clean;
      declare
         Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
      begin
         Exercise_Delete_Objects (Store, "files-delete-objects-bucket");
      end;
      Clean;
   exception
      when others =>
         Clean;
         raise;
   end Check_Backend_Delete_Objects;

   procedure Check_S3_Core_Rules (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Core renames Flyology.Object_Storage.S3.Core;
      use type Core.Multipart_State;
      use type Core.Range_Parse_Status;
      use type Core.Range_Request_Kind;
      use type Core.Range_Resolution_Kind;

      procedure Check_Range
        (Size     : Flyology.Object_Storage.Byte_Count;
         Request  : Core.Range_Request;
         Kind     : Core.Range_Resolution_Kind;
         First    : Flyology.Object_Storage.Byte_Count := 0;
         Last     : Flyology.Object_Storage.Byte_Count := 0;
         Length   : Flyology.Object_Storage.Byte_Count := 0;
         Message  : String)
      is
         Result : constant Core.Range_Resolution :=
           Core.Resolve_Range (Size, Request);
      begin
         Assert (Result.Kind = Kind, Message & " kind");
         if Kind = Core.Satisfied then
            Assert
              (Result.First = First
               and then Result.Last = Last
               and then Result.Length = Length,
               Message & " values");
         end if;
      end Check_Range;
   begin
      Assert
        (not Core.Valid_Part_Size (Core.Minimum_Part_Size - 1, False),
         "nonfinal part below minimum");
      Assert
        (Core.Valid_Part_Size (Core.Minimum_Part_Size, False),
         "part at minimum");
      Assert
        (Core.Valid_Part_Size (Core.Maximum_Part_Size, False),
         "part at maximum");
      Assert
        (not Core.Valid_Part_Size (Core.Maximum_Part_Size + 1, True),
         "final part above maximum");
      Assert (Core.Valid_Part_Size (0, True), "empty final part");
      Assert
        (not Core.Valid_Multipart_Part_Size (Core.Minimum_Part_Size - 1),
         "multipart part below minimum");
      Assert
        (Core.Valid_Multipart_Part_Size (Core.Minimum_Part_Size),
         "multipart part at minimum");
      Assert
        (Core.Multipart_Part_Count (0, Core.Minimum_Part_Size) = 0,
         "empty multipart part count");
      Assert
        (Core.Multipart_Part_Count (1, Core.Minimum_Part_Size) = 1,
         "single-byte multipart part count");
      Assert
        (Core.Multipart_Part_Count
           (Core.Minimum_Part_Size + 1, Core.Minimum_Part_Size) = 2,
         "multipart ceiling division");
      Assert
        (Core.Valid_Multipart_Plan
           (10_000 * Core.Minimum_Part_Size, Core.Minimum_Part_Size),
         "maximum part-count plan");
      Assert
        (not Core.Valid_Multipart_Plan
           (10_000 * Core.Minimum_Part_Size + 1, Core.Minimum_Part_Size),
         "plan exceeding maximum part count");
      Assert
        (Core.Multipart_Part_Count
           (Flyology.Object_Storage.Byte_Count'Last,
            Flyology.Object_Storage.Byte_Count'Last) = 1,
         "overflow-safe maximum part count");

      Assert
        (Flyology.Object_Storage.Listing_Matches_Prefix
           ("logs/archive/object", "logs/")
         and then not Flyology.Object_Storage.Listing_Matches_Prefix
           ("log", "logs/")
         and then Flyology.Object_Storage.Listing_Matches_Prefix ("x", ""),
         "ListObjectsV2 byte-prefix predicate");
      Assert
        (Flyology.Object_Storage.Listing_Follows_Cursor ("b", "a")
         and then not
           Flyology.Object_Storage.Listing_Follows_Cursor ("a", "a")
         and then not
           Flyology.Object_Storage.Listing_Follows_Cursor ("a", "b"),
         "ListObjectsV2 exclusive cursor predicate");
      declare
         Valid : constant String :=
           "fos1." & String'(1 .. 64 => 'a') & "." & "00ff";
         Empty : constant String :=
           "fos1." & String'(1 .. 64 => '0') & ".";
         Odd : constant String :=
           "fos1." & String'(1 .. 64 => '0') & ".0";
         Bad_Digest : constant String :=
           "fos1." & String'(1 .. 63 => '0') & "g.";
         Bad_Cursor : constant String :=
           "fos1." & String'(1 .. 64 => '0') & ".0g";
      begin
         Assert
           (Core.Valid_Listing_Continuation_Syntax (Valid)
            and then Core.Valid_Listing_Continuation_Syntax (Empty)
            and then not Core.Valid_Listing_Continuation_Syntax (Odd)
            and then not
              Core.Valid_Listing_Continuation_Syntax (Bad_Digest)
            and then not
              Core.Valid_Listing_Continuation_Syntax (Bad_Cursor)
            and then not Core.Valid_Listing_Continuation_Syntax
              ("fos2." & String'(1 .. 64 => '0') & ".")
            and then not Core.Valid_Listing_Continuation_Syntax
              ("fos1." & String'(1 .. 64 => '0') & "." &
               String'(1 .. 2 * Core.Maximum_Listing_Cursor_Bytes + 2 =>
                 '0')),
            "ListObjectsV2 continuation syntax bounds");
      end;

      Assert
        (Core.Can_Transition (Core.Initiated, Core.Active),
         "multipart activation");
      Assert
        (Core.Can_Transition (Core.Active, Core.Completing),
         "multipart completion start");
      Assert
        (Core.Can_Transition (Core.Completing, Core.Completed),
         "multipart completion commit");
      Assert
        (not Core.Can_Transition (Core.Completed, Core.Active),
         "completed upload is terminal");
      Assert
        (not Core.Can_Transition (Core.Aborted, Core.Active),
         "aborted upload is terminal");

      Assert
        (Core.Valid_Completion_Order ((1, 5, 14)),
         "sparse ascending completion order");
      Assert
        (not Core.Valid_Completion_Order ((1, 1)),
         "duplicate completion part");
      Assert
        (not Core.Valid_Completion_Order ((2, 1)),
         "descending completion part");
      Assert
        (not Core.Valid_Completion_Order
           (Core.Part_Number_Array'(1 .. 0 => 1)),
         "empty completion");
      Assert
        (Core.Valid_Consecutive_Completion_Order ((1, 2, 3)),
         "consecutive completion order");
      Assert
        (not Core.Valid_Consecutive_Completion_Order ((1, 3)),
         "gapped completion order");
      Assert
        (not Core.Valid_Consecutive_Completion_Order ((2, 3)),
         "consecutive completion must start at one");

      Check_Range
        (0, (Kind => Core.Whole, others => 0), Core.Empty_Object,
         Message => "empty whole");
      Check_Range
        (0, (Kind => Core.Bounded, First => 0, Last => 0, Count => 0),
         Core.Unsatisfiable, Message => "empty bounded");
      Check_Range
        (10, (Kind => Core.Whole, others => 0), Core.Satisfied,
         0, 9, 10, "whole");
      Check_Range
        (10, (Kind => Core.Bounded, First => 2, Last => 4, Count => 0),
         Core.Satisfied, 2, 4, 3, "bounded");
      Check_Range
        (10, (Kind => Core.Bounded, First => 8, Last => 99, Count => 0),
         Core.Satisfied, 8, 9, 2, "bounded capped at end");
      Check_Range
        (10, (Kind => Core.Bounded, First => 8, Last => 7, Count => 0),
         Core.Unsatisfiable, Message => "reversed");
      Check_Range
        (10, (Kind => Core.Open_Ended, First => 5, others => 0),
         Core.Satisfied, 5, 9, 5, "open ended");
      Check_Range
        (10, (Kind => Core.Open_Ended, First => 10, others => 0),
         Core.Unsatisfiable, Message => "open at end");
      Check_Range
        (10, (Kind => Core.Suffix, Count => 3, others => 0),
         Core.Satisfied, 7, 9, 3, "suffix");
      Check_Range
        (10, (Kind => Core.Suffix, Count => 99, others => 0),
         Core.Satisfied, 0, 9, 10, "large suffix");
      Check_Range
        (10, (Kind => Core.Suffix, Count => 0, others => 0),
         Core.Unsatisfiable, Message => "zero suffix");

      declare
         Bounded : constant Core.Range_Parse_Result :=
           Core.Parse_Range_Header ("BYTES= " & Character'Val (9) & "2-4 ");
         Open_Ended : constant Core.Range_Parse_Result :=
           Core.Parse_Range_Header ("bytes=5-");
         Suffix : constant Core.Range_Parse_Result :=
           Core.Parse_Range_Header ("bytes=-3");
         Rebasing : constant String (10 .. 18) := "bytes=1-2";
         Rebased : constant Core.Range_Parse_Result :=
           Core.Parse_Range_Header (Rebasing);
      begin
         Assert
           (Bounded.Status = Core.Range_Parsed
            and then Bounded.Request.Kind = Core.Bounded
            and then Bounded.Request.First = 2
            and then Bounded.Request.Last = 4,
            "case-insensitive bounded range parser");
         Assert
           (Open_Ended.Status = Core.Range_Parsed
            and then Open_Ended.Request.Kind = Core.Open_Ended
            and then Open_Ended.Request.First = 5,
            "open-ended range parser");
         Assert
           (Suffix.Status = Core.Range_Parsed
            and then Suffix.Request.Kind = Core.Suffix
            and then Suffix.Request.Count = 3,
            "suffix range parser");
         Assert
           (Rebased.Status = Core.Range_Parsed
            and then Rebased.Request.First = 1
            and then Rebased.Request.Last = 2,
            "range parser supports non-one string bounds");
      end;
      Assert
        (Core.Parse_Range_Header ("bytes=0-0,2-2").Status =
           Core.Malformed_Range,
         "multi-range rejected until multipart responses exist");
      Assert
        (Core.Parse_Range_Header ("items=0-1").Status =
           Core.Malformed_Range,
         "unknown range unit");
      Assert
        (Core.Parse_Range_Header ("bytes=1 -2").Status =
           Core.Malformed_Range,
         "internal range whitespace");
      Assert
        (Core.Parse_Range_Header ("bytes=--1").Status =
           Core.Malformed_Range,
         "duplicate range hyphen");
      Assert
        (Core.Parse_Range_Header ("bytes=-").Status =
           Core.Malformed_Range,
         "range without digits");
      Assert
        (Core.Parse_Range_Header ("bytes=9223372036854775808-").Status =
           Core.Malformed_Range,
         "range integer overflow");
   end Check_S3_Core_Rules;

   procedure Check_Request_Target_Parsing (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Requests renames Flyology.Object_Storage.S3.Requests;
      use type Requests.Target_Kind;
      use type Requests.Target_Status;

      procedure Rejects (Value, Message : String) is
      begin
         Assert
           (Requests.Parse_Target (Value).Status = Requests.Malformed_Target,
            Message);
      end Rejects;
   begin
      declare
         Service : constant Requests.Target_Result :=
           Requests.Parse_Target ("/");
         Bucket : constant Requests.Target_Result :=
           Requests.Parse_Target ("/example%2Dbucket/");
         Object : constant Requests.Target_Result :=
           Requests.Parse_Target
             ("/example-bucket/a%20b+%2Fz?versionId=x%2By");
         Empty_Query : constant Requests.Target_Result :=
           Requests.Parse_Target ("/example-bucket?");
      begin
         Assert
           (Service.Status = Requests.Target_Parsed
            and then Service.Kind = Requests.Service_Target,
            "service target");
         Assert
           (Bucket.Status = Requests.Target_Parsed
            and then Bucket.Kind = Requests.Bucket_Target
            and then Requests.Bucket_Name
              ("/example%2Dbucket/", Bucket) = "example-bucket",
            "decoded bucket target");
         Assert
           (Object.Status = Requests.Target_Parsed
            and then Object.Kind = Requests.Object_Target
            and then Requests.Bucket_Name
              ("/example-bucket/a%20b+%2Fz?versionId=x%2By", Object) =
              "example-bucket"
            and then Requests.Object_Key
              ("/example-bucket/a%20b+%2Fz?versionId=x%2By", Object) =
              "a b+/z"
            and then Requests.Query_String
              ("/example-bucket/a%20b+%2Fz?versionId=x%2By", Object) =
              "versionId=x%2By",
            "strict object target decoding keeps plus literal");
         Assert
           (Empty_Query.Status = Requests.Target_Parsed
            and then Empty_Query.Has_Query
            and then Requests.Query_String
              ("/example-bucket?", Empty_Query) = "",
            "empty query remains present");
      end;
      declare
         Rebased_Value : constant String (10 .. 28) :=
           "/example-bucket/key";
         Rebased : constant Requests.Target_Result :=
           Requests.Parse_Target (Rebased_Value);
      begin
         Assert
           (Rebased.Status = Requests.Target_Parsed
            and then Requests.Object_Key (Rebased_Value, Rebased) = "key",
            "target parser supports non-one string bounds");
      end;
      declare
         Exact_Key : constant String := (1 .. 1_024 => 'x');
         Parsed : constant Requests.Target_Result :=
           Requests.Parse_Target ("/example-bucket/" & Exact_Key);
      begin
         Assert
           (Parsed.Status = Requests.Target_Parsed
            and then Requests.Object_Key
              ("/example-bucket/" & Exact_Key, Parsed)'Length = 1_024,
            "maximum decoded key length");
      end;
      Rejects ("https://example.test/bucket", "absolute target accepted");
      Rejects ("//key", "empty bucket accepted");
      Rejects ("/bad_bucket/key", "invalid bucket accepted");
      Rejects ("/example%2Fbucket/key", "escaped bucket slash accepted");
      Rejects ("/example-bucket/%00", "NUL object key accepted");
      Rejects ("/example-bucket/key#fragment", "fragment accepted");
      Rejects ("/example-bucket/%", "truncated percent escape accepted");
      Rejects ("/example-bucket/%GG", "nonhex percent escape accepted");
      Rejects
        ("/example-bucket/key?x=%GG", "malformed query escape accepted");
      Rejects
        ("/example-bucket/" & String'(1 .. 1_025 => 'x'),
         "oversized decoded key accepted");
   end Check_Request_Target_Parsing;

   procedure Check_SigV4_Official_Vectors (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package SigV4 renames Flyology.Object_Storage.S3.SigV4;
      package Encoding renames
        Flyology.Object_Storage.S3.SigV4_Encoding;
      package US renames Ada.Strings.Unbounded;
      LF : constant Character := Character'Val (10);
      Access_Key : constant String := "AKIAIOSFODNN7EXAMPLE";
      Secret_Key : constant String :=
        "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
      Empty_Query : constant SigV4.Name_Value_Array (1 .. 0) :=
        (others => SigV4.Pair ("", ""));
   begin
      declare
         Result : constant SigV4.Signing_Result := SigV4.Sign
           (Method       => "GET",
            Path         => "/test.txt",
            Query        => Empty_Query,
            Headers      =>
              (SigV4.Pair ("Host", "examplebucket.s3.amazonaws.com"),
               SigV4.Pair ("Range", "bytes=0-9"),
               SigV4.Pair ("x-amz-content-sha256",
                            SigV4.Empty_Payload_Hash),
               SigV4.Pair ("x-amz-date", "20130524T000000Z")),
            Payload_Hash => SigV4.Empty_Payload_Hash,
            Access_Key   => Access_Key,
            Secret_Key   => Secret_Key,
            Region       => "us-east-1",
            Timestamp    => "20130524T000000Z");
      begin
         Assert
           (SigV4.SHA256_Hex (US.To_String (Result.Canonical_Request)) =
              "7344ae5b7ee6c3e7e6b0fe0640412a37" &
              "625d1fbfff95c48bbb2dc43964946972",
            "AWS GET canonical request vector");
         Assert
           (US.To_String (Result.Signature) =
              "f0e8bdb87c964420e857bd35b5d6ed31" &
              "0bd44f0170aba48dd91039c6036bdb41",
            "AWS GET signature vector");
         Assert
           (US.To_String (Result.Authorization) =
              "AWS4-HMAC-SHA256 Credential=" & Access_Key &
              "/20130524/us-east-1/s3/aws4_request," &
              "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date," &
              "Signature=" &
              "f0e8bdb87c964420e857bd35b5d6ed31" &
              "0bd44f0170aba48dd91039c6036bdb41",
            "AWS GET authorization vector");
      end;

      declare
         Payload_Hash : constant String :=
           "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072";
         Result : constant SigV4.Signing_Result := SigV4.Sign
           (Method       => "PUT",
            Path         => "/test$file.text",
            Query        => Empty_Query,
            Headers      =>
              (SigV4.Pair ("Date", "Fri, 24 May 2013 00:00:00 GMT"),
               SigV4.Pair ("Host", "examplebucket.s3.amazonaws.com"),
               SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
               SigV4.Pair ("x-amz-date", "20130524T000000Z"),
               SigV4.Pair ("x-amz-storage-class", "REDUCED_REDUNDANCY")),
            Payload_Hash => Payload_Hash,
            Access_Key   => Access_Key,
            Secret_Key   => Secret_Key,
            Region       => "us-east-1",
            Timestamp    => "20130524T000000Z");
      begin
         Assert
           (SigV4.SHA256_Hex (US.To_String (Result.Canonical_Request)) =
              "9e0e90d9c76de8fa5b200d8c849cd5b" &
              "8dc7a3be3951ddb7f6a76b4158342019d",
            "AWS PUT canonical request vector");
         Assert
           (US.To_String (Result.Signature) =
              "98ad721746da40c64f1a55b78f14c238" &
              "d841ea1380cd77a1b5971af0ece108bd",
            "AWS PUT signature vector");
      end;

      declare
         Result : constant SigV4.Signing_Result := SigV4.Sign
           (Method       => "GET",
            Path         => "/",
            Query        => (1 => SigV4.Pair ("lifecycle", "")),
            Headers      =>
              (SigV4.Pair ("Host", "examplebucket.s3.amazonaws.com"),
               SigV4.Pair ("x-amz-content-sha256",
                            SigV4.Empty_Payload_Hash),
               SigV4.Pair ("x-amz-date", "20130524T000000Z")),
            Payload_Hash => SigV4.Empty_Payload_Hash,
            Access_Key   => Access_Key,
            Secret_Key   => Secret_Key,
            Region       => "us-east-1",
            Timestamp    => "20130524T000000Z");
      begin
         Assert
           (US.To_String (Result.Signature) =
              "fea454ca298b7da1c68078a5d1bdbfbb" &
              "e0d65c699e0f91ac7a200a0136783543",
            "AWS lifecycle signature vector");
      end;

      declare
         Result : constant SigV4.Signing_Result := SigV4.Sign
           (Method       => "GET",
            Path         => "/",
            Query        =>
              (SigV4.Pair ("prefix", "J"), SigV4.Pair ("max-keys", "2")),
            Headers      =>
              (SigV4.Pair ("Host", "examplebucket.s3.amazonaws.com"),
               SigV4.Pair ("x-amz-content-sha256",
                            SigV4.Empty_Payload_Hash),
               SigV4.Pair ("x-amz-date", "20130524T000000Z")),
            Payload_Hash => SigV4.Empty_Payload_Hash,
            Access_Key   => Access_Key,
            Secret_Key   => Secret_Key,
            Region       => "us-east-1",
            Timestamp    => "20130524T000000Z");
      begin
         Assert
           (US.To_String (Result.Signature) =
              "34b48302e7b5fa45bde8084f4b7868a8" &
              "6f0a534bc59db6670ed5711ef69dc6f7",
            "AWS list signature and query-sort vector");
      end;

      Assert
        (Encoding.URI_Encode (" /" & Character'Val (255), True) =
           "%20%2F%FF",
         "SigV4 byte URI encoding");
      Assert
        (Encoding.Normalize_Header_Value
           (Character'Val (9) & "  a" & Character'Val (9) & " b  ") =
           "a b",
         "SigV4 header whitespace normalization");
      declare
         Result : constant SigV4.Signing_Result := SigV4.Sign
           ("GET", "/", Empty_Query,
            (SigV4.Pair ("x-test", "second"),
             SigV4.Pair ("Host", "example.test"),
             SigV4.Pair ("x-test", "first")),
            SigV4.Empty_Payload_Hash, Access_Key, Secret_Key,
            "us-east-1", "20130524T000000Z");
      begin
         Assert
           (US.To_String (Result.Canonical_Request) =
              "GET" & LF & "/" & LF & LF &
              "host:example.test" & LF & "x-test:second,first" & LF & LF &
              "host;x-test" & LF & SigV4.Empty_Payload_Hash,
            "duplicate header wire order");
      end;
      Assert (SigV4.Constant_Time_Equal ("signature", "signature"),
              "equal signatures");
      Assert (not SigV4.Constant_Time_Equal ("signature", "signaturf"),
              "different signatures");
      Assert (not SigV4.Constant_Time_Equal ("", "x"),
              "different-length signatures");
      Assert
        (Encoding.Valid_Timestamp ("20240229T235959Z")
         and then not Encoding.Valid_Timestamp ("20230229T235959Z")
         and then not Encoding.Valid_Timestamp ("20241301T000000Z")
         and then not Encoding.Valid_Timestamp ("20240132T000000Z")
         and then not Encoding.Valid_Timestamp ("20240101T240000Z")
         and then not Encoding.Valid_Timestamp ("00000101T000000Z"),
         "SigV4 timestamp calendar or time bounds");

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant SigV4.Signing_Result := SigV4.Sign
                 ("GET", "/", Empty_Query,
                  (1 => SigV4.Pair ("x-test", "unsafe" & LF & "value")),
                  SigV4.Empty_Payload_Hash, Access_Key, Secret_Key,
                  "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when SigV4.Invalid_Signing_Input =>
               Raised := True;
         end;
         Assert (Raised, "unsafe or hostless SigV4 headers were accepted");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant SigV4.Signing_Result := SigV4.Sign
                 ("GET", "/", Empty_Query,
                  (1 => SigV4.Pair ("host", "example.test")),
                  SigV4.Empty_Payload_Hash, Access_Key, Secret_Key,
                  "us-east-1", "20130524X000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when SigV4.Invalid_Signing_Input =>
               Raised := True;
         end;
         Assert (Raised, "malformed SigV4 timestamp was accepted");
      end;
   end Check_SigV4_Official_Vectors;

   procedure Check_XML_Security_And_Limits (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package XML renames Flyology.Object_Storage.S3.XML;
      package Errors renames Flyology.Object_Storage.S3.Errors;
      package US renames Ada.Strings.Unbounded;

      procedure Must_Reject
        (Document : String;
         Limits   : XML.Parse_Limits := XML.Default_Limits;
         Message  : String)
      is
         Recorder : aliased XML_Recorder;
         Raised   : Boolean := False;
      begin
         begin
            XML.Parse (Document, Recorder, Limits);
         exception
            when XML.XML_Error =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject;

   begin
      declare
         Recorder : aliased XML_Recorder;
      begin
         XML.Parse
           ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
            "<s3:ListBucketResult xmlns:s3=""http://s3.amazonaws.com/doc/" &
            "2006-03-01/""><s3:Key>a&amp;&lt;</s3:Key>" &
            "</s3:ListBucketResult>",
            Recorder);
         Assert
           (US.To_String (Recorder.Trace) =
              "<ListBucketResult><Key>a&<</Key></ListBucketResult>",
            "bounded SAX events or namespace handling");
      end;

      Assert
        (XML.Escape_Text ("a&<>""'") = "a&amp;&lt;&gt;""'",
         "XML text escaping");
      Assert
        (XML.Escape_Attribute ("a&<>""'") =
           "a&amp;&lt;&gt;&quot;&apos;",
         "XML attribute escaping");

      Must_Reject
        ("<!DOCTYPE x [<!ENTITY e SYSTEM ""file:///etc/passwd"">]>" &
         "<x>&e;</x>",
         Message => "external entity document was accepted");
      Must_Reject
        ("<!DOCTYPE x [<!ENTITY e ""expanded"">]><x>&e;</x>",
         Message => "internal entity document was accepted");
      Must_Reject
        ("<x><?unexpected value?></x>",
         Message => "processing instruction was accepted");
      Must_Reject
        ("<x><y></x>", Message => "malformed nesting was accepted");
      Must_Reject
        ("<a><b><c/></b></a>",
         (Maximum_Document_Bytes => 100,
          Maximum_Depth          => 2,
          Maximum_Elements       => 10,
          Maximum_Text_Bytes     => 100),
         "XML depth limit was ignored");
      Must_Reject
        ("<a><b/><c/></a>",
         (Maximum_Document_Bytes => 100,
          Maximum_Depth          => 10,
          Maximum_Elements       => 2,
          Maximum_Text_Bytes     => 100),
         "XML element limit was ignored");
      Must_Reject
        ("<a>12345</a>",
         (Maximum_Document_Bytes => 100,
          Maximum_Depth          => 10,
          Maximum_Elements       => 10,
          Maximum_Text_Bytes     => 4),
         "XML text limit was ignored");
      Must_Reject
        ("<a/>",
         (Maximum_Document_Bytes => 3,
          Maximum_Depth          => 10,
          Maximum_Elements       => 10,
          Maximum_Text_Bytes     => 10),
         "XML document limit was ignored");
      Must_Reject
        ("<a>" & Character'Val (16#C0#) & "</a>",
         Message => "invalid UTF-8 was accepted");

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String :=
                 XML.Escape_Text ("bad" & Character'Val (0));
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when XML.XML_Error =>
               Raised := True;
         end;
         Assert (Raised, "invalid XML character was escaped");
      end;

      declare
         Parsed : constant Errors.Error_Response := Errors.Parse
           ("<Error xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
            "<Code>NoSuchKey</Code><Message>The key &lt;x&gt;</Message>" &
            "<Resource>/bucket/key</Resource>" &
            "<RequestId>request-1</RequestId>" &
            "<HostId>host-1</HostId><Future><Nested>ignored</Nested>" &
            "</Future></Error>");
         Round_Trip : constant Errors.Error_Response :=
           Errors.Parse (Errors.Serialize (Parsed));
      begin
         Assert
           (US.To_String (Parsed.Code) = "NoSuchKey" and then
            US.To_String (Parsed.Message) = "The key <x>" and then
            US.To_String (Parsed.Request_ID) = "request-1" and then
            US.To_String (Parsed.Host_ID) = "host-1",
            "typed S3 error parsing");
         Assert
           (US.To_String (Round_Trip.Code) = US.To_String (Parsed.Code)
            and then US.To_String (Round_Trip.Message) =
              US.To_String (Parsed.Message),
            "typed S3 error serialization round trip");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Errors.Error_Response := Errors.Parse
                 ("<Error><Code>A</Code><Code>B</Code>" &
                  "<Message>bad</Message></Error>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Errors.Malformed_Error =>
               Raised := True;
         end;
         Assert (Raised, "duplicate S3 error field was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Errors.Error_Response :=
                 Errors.Parse ("<Error><Code>OnlyCode</Code></Error>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Errors.Malformed_Error =>
               Raised := True;
         end;
         Assert (Raised, "incomplete S3 error was accepted");
      end;
   end Check_XML_Security_And_Limits;

   procedure Check_List_Objects_V1_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Listings renames Flyology.Object_Storage.S3.Listings;
      package US renames Ada.Strings.Unbounded;

      procedure Must_Reject_Query (Query, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Listings.List_Objects_Request :=
                 Listings.Parse_List_Objects_Query (Query);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Listings.Malformed_List_Request =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Query;

      procedure Must_Reject_Result
        (Value : Listings.List_Objects_Result; Message : String)
      is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String :=
                 Listings.Serialize_List_Objects (Value);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Listings.Malformed_Listing =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Result;

      procedure Must_Reject_Document (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Listings.List_Objects_Result :=
                 Listings.Parse_List_Objects (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Listings.Malformed_Listing =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Document;

      function Empty_Listing (Extra : String := "") return String is
        ("<ListBucketResult><Name>bucket</Name><Prefix></Prefix>" &
         "<Marker></Marker><MaxKeys>3</MaxKeys>" &
         "<IsTruncated>false</IsTruncated>" & Extra &
         "</ListBucketResult>");
   begin
      declare
         Empty : constant Listings.List_Objects_Request :=
           Listings.Parse_List_Objects_Query ("");
         Request : constant Listings.List_Objects_Request :=
           Listings.Parse_List_Objects_Query
             ("delimiter=%2F&encoding-type=url&marker=a+b&max-keys=7&" &
              "prefix=logs%2F%2B&x-id=ListObjects");
         Explicit_Empty : constant Listings.List_Objects_Request :=
           Listings.Parse_List_Objects_Query
             ("prefix=&delimiter=&marker=&max-keys=0");
      begin
         Assert
           (Empty.Max_Keys = Flyology.Object_Storage.S3.Core.Page_Size'Last
            and then not Empty.Has_Max_Keys
            and then not Empty.Has_Prefix
            and then not Empty.Has_Delimiter
            and then not Empty.Has_Marker,
            "empty ListObjects query defaults");
         Assert
           (US.To_String (Request.Prefix) = "logs/+"
            and then US.To_String (Request.Delimiter) = "/"
            and then US.To_String (Request.Marker) = "a+b"
            and then Request.Max_Keys = 7
            and then Request.Has_Max_Keys
            and then Request.Has_Prefix
            and then Request.Has_Delimiter
            and then Request.Has_Marker
            and then Request.URL_Encoding,
            "ListObjects query decoding");
         Assert
           (Explicit_Empty.Has_Prefix
            and then Explicit_Empty.Has_Delimiter
            and then Explicit_Empty.Has_Marker
            and then Explicit_Empty.Has_Max_Keys
            and then Explicit_Empty.Max_Keys = 0,
            "ListObjects explicit-empty query presence");
      end;

      Must_Reject_Query
        ("prefix=%GG", "invalid v1 listing escape was accepted");
      Must_Reject_Query
        ("prefix=a&prefix=b", "duplicate v1 listing prefix was accepted");
      Must_Reject_Query
        ("max-keys=1001", "oversized v1 listing page was accepted");
      Must_Reject_Query
        ("list-type=2", "v2 selector was accepted as ListObjects v1");
      Must_Reject_Query
        ("x-id=ListObjectsV2", "mismatched v1 operation ID was accepted");

      declare
         Present_Empty : constant Listings.List_Objects_Result :=
           Listings.Parse_List_Objects (Empty_Listing);
         Round_Trip : constant String :=
           Listings.Serialize_List_Objects (Present_Empty);
      begin
         Assert
           (Present_Empty.Has_Prefix
            and then Present_Empty.Has_Marker
            and then not Present_Empty.Has_Delimiter
            and then not Present_Empty.Has_Next_Marker
            and then Ada.Strings.Fixed.Index
              (Round_Trip, "<Prefix></Prefix>") /= 0
            and then Ada.Strings.Fixed.Index
              (Round_Trip, "<Marker></Marker>") /= 0,
            "ListObjects response empty-field presence round trip");
      end;

      declare
         Value : Listings.List_Objects_Result :=
           (Name            => US.To_Unbounded_String ("bucket"),
            Prefix          => US.Null_Unbounded_String,
            Has_Prefix      => True,
            Delimiter       => US.To_Unbounded_String ("/"),
            Has_Delimiter   => True,
            Encoding_Type   => US.Null_Unbounded_String,
            Has_Encoding_Type => False,
            Marker          => US.To_Unbounded_String ("before"),
            Has_Marker      => True,
            Next_Marker     => US.To_Unbounded_String ("a&b/"),
            Has_Next_Marker => True,
            Max_Keys        => 2,
            Is_Truncated    => True,
            Contents        => <>,
            Common_Prefixes => <>);
      begin
         Value.Contents.Append
           (Listings.Object_Entry'
              (Key            => US.To_Unbounded_String ("a&b"),
               Last_Modified  => US.To_Unbounded_String
                 ("2026-08-21T00:00:00.000Z"),
               Entity_Tag     => US.To_Unbounded_String ("&quot;etag&quot;"),
               Size           => 9,
               Storage_Class  => US.To_Unbounded_String ("STANDARD"),
               others         => <>));
         Value.Common_Prefixes.Append
           (US.To_Unbounded_String ("a&b/"));
         declare
            Document : constant String :=
              Listings.Serialize_List_Objects (Value);
            Parsed : constant Listings.List_Objects_Result :=
              Listings.Parse_List_Objects (Document);
         begin
            Assert
              (Ada.Strings.Fixed.Index
                 (Document, "<Marker>before</Marker>") /= 0
               and then Ada.Strings.Fixed.Index
                 (Document, "<NextMarker>a&amp;b/</NextMarker>") /= 0
               and then Ada.Strings.Fixed.Index
                 (Document, "<Key>a&amp;b</Key>") /= 0
               and then Ada.Strings.Fixed.Index
                 (Document, "<CommonPrefixes><Prefix>a&amp;b/</Prefix>") /= 0,
               "ListObjects XML fields and escaping");
            Assert
              (US.To_String (Parsed.Name) = "bucket"
               and then US.To_String (Parsed.Marker) = "before"
               and then US.To_String (Parsed.Next_Marker) = "a&b/"
               and then Parsed.Has_Prefix
               and then Parsed.Has_Delimiter
               and then Parsed.Has_Marker
               and then Parsed.Has_Next_Marker
               and then Parsed.Max_Keys = 2
               and then Parsed.Is_Truncated
               and then Parsed.Contents.Length = 1
               and then Parsed.Common_Prefixes.Length = 1
               and then US.To_String (Parsed.Contents.First_Element.Key) =
                 "a&b"
               and then Parsed.Contents.First_Element.Size = 9,
               "ListObjects serialization round trip");
         end;

         Value.Delimiter := US.Null_Unbounded_String;
         Must_Reject_Result
           (Value, "v1 next marker without delimiter was serialized");
         Value.Next_Marker := US.Null_Unbounded_String;
         Value.Has_Next_Marker := False;
         Value.Max_Keys := 0;
         Must_Reject_Result
           (Value, "truncated zero-sized v1 page was serialized");
      end;

      declare
         Parsed : constant Listings.List_Objects_Result :=
           Listings.Parse_List_Objects
             ("<ListBucketResult><Name>bucket</Name><Prefix>logs/</Prefix>" &
              "<Marker>before</Marker><MaxKeys>2</MaxKeys>" &
              "<IsTruncated>false</IsTruncated>" &
              "<Contents><Key>logs/a</Key>" &
              "<ChecksumAlgorithm>CRC32</ChecksumAlgorithm>" &
              "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>" &
              "<Size>9223372036854775807</Size>" &
              "<StorageClass>STANDARD</StorageClass>" &
              "<Owner><DisplayName>owner</DisplayName><ID>owner-id</ID>" &
              "</Owner><RestoreStatus><IsRestoreInProgress>false" &
              "</IsRestoreInProgress><RestoreExpiryDate>" &
              "Fri, 21 Aug 2026 17:00:00 GMT</RestoreExpiryDate>" &
              "</RestoreStatus></Contents>" &
              "<Future><Nested>ignored</Nested></Future>" &
              "</ListBucketResult>");
         Round_Trip : constant Listings.List_Objects_Result :=
           Listings.Parse_List_Objects
             (Listings.Serialize_List_Objects (Parsed));
      begin
         Assert
           (not Parsed.Is_Truncated
            and then US.Length (Parsed.Next_Marker) = 0
            and then Parsed.Contents.Length = 1
            and then Parsed.Contents.First_Element.Size =
              Flyology.Object_Storage.Byte_Count'Last
            and then Parsed.Contents.First_Element.
              Checksum_Algorithms.Length = 2
            and then US.To_String
              (Parsed.Contents.First_Element.Checksum_Type) = "FULL_OBJECT"
            and then Parsed.Contents.First_Element.Has_Owner
            and then US.To_String
              (Parsed.Contents.First_Element.Owner.ID) = "owner-id"
            and then Parsed.Contents.First_Element.Has_Restore_Status
            and then Parsed.Contents.First_Element.Restore_Status.
              Has_Is_Restore_In_Progress
            and then not Parsed.Contents.First_Element.Restore_Status.
              Is_Restore_In_Progress,
            "ListObjects complete nested object parsing");
         Assert
           (Round_Trip.Contents.First_Element.Checksum_Algorithms.Length = 2
            and then Round_Trip.Contents.First_Element.Has_Owner
            and then Round_Trip.Contents.First_Element.Has_Restore_Status
            and then US.To_String
              (Round_Trip.Contents.First_Element.Restore_Status.
                 Restore_Expiry_Date) =
              "Fri, 21 Aug 2026 17:00:00 GMT",
            "ListObjects complete nested object round trip");
      end;

      Must_Reject_Document
        ("<Wrong><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated></Wrong>",
         "ListObjects wrong root was accepted");
      Must_Reject_Document
        (Empty_Listing ("<Name>again</Name>"),
         "ListObjects duplicate singleton was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>True</IsTruncated></ListBucketResult>",
         "ListObjects invalid boolean was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name>" &
         "<MaxKeys>999999999999999999999999</MaxKeys>" &
         "<IsTruncated>false</IsTruncated></ListBucketResult>",
         "ListObjects overflowing count was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key><Size>9223372036854775808</Size>" &
         "</Contents></ListBucketResult>",
         "ListObjects overflowing object size was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>0</MaxKeys>" &
         "<IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key><Size>1</Size></Contents>" &
         "</ListBucketResult>",
         "ListObjects result exceeding max keys was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><Delimiter>/</Delimiter>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjects truncated delimiter page without marker was accepted");
      Must_Reject_Document
        (Empty_Listing ("<NextMarker>unexpected</NextMarker>"),
         "ListObjects marker on final page was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key></Contents></ListBucketResult>",
         "ListObjects object without size was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key><Size>1</Size><Size>2</Size>" &
         "</Contents></ListBucketResult>",
         "ListObjects duplicate object field was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated><Contents><Key>x</Key>" &
         "<ChecksumAlgorithm>INVALID</ChecksumAlgorithm><Size>1</Size>" &
         "</Contents></ListBucketResult>",
         "ListObjects invalid checksum algorithm was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated><Contents><Key>x</Key>" &
         "<Size>1</Size><StorageClass>INVALID</StorageClass>" &
         "</Contents></ListBucketResult>",
         "ListObjects invalid storage class was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated><Contents><Key>x" &
         "<Nested/></Key><Size>1</Size></Contents></ListBucketResult>",
         "ListObjects nested object scalar was accepted");
      Must_Reject_Document
        ("<ListBucketResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated><Contents><Key>x</Key>" &
         "<Size>1</Size><Owner><ID>one</ID></Owner>" &
         "<Owner><ID>two</ID></Owner></Contents></ListBucketResult>",
         "ListObjects duplicate owner was accepted");
      Must_Reject_Document
        (Empty_Listing ("<Name><Nested/></Name>"),
         "ListObjects nested scalar was accepted");
      Must_Reject_Document
        ("<ListBucketResult>non-whitespace<Name>bucket</Name>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjects root text was accepted");
   end Check_List_Objects_V1_Codec;

   procedure Check_List_Objects_V2_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Listings renames Flyology.Object_Storage.S3.Listings;
      package US renames Ada.Strings.Unbounded;

      procedure Must_Reject (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Listings.List_Objects_V2_Result :=
                 Listings.Parse_List_Objects_V2 (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Listings.Malformed_Listing =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject;

      procedure Must_Reject_Query (Query, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Listings.List_Objects_V2_Request :=
                 Listings.Parse_List_Objects_V2_Query (Query);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Listings.Malformed_List_Request =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Query;

      function Empty_Listing (Extra : String := "") return String is
        ("<ListBucketResult><Name>bucket</Name><Prefix></Prefix>" &
         "<KeyCount>0</KeyCount><MaxKeys>3</MaxKeys>" &
         "<IsTruncated>false</IsTruncated>" & Extra &
         "</ListBucketResult>");
   begin
      declare
         Parsed : constant Listings.List_Objects_V2_Result :=
           Listings.Parse_List_Objects_V2
             ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
              "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
              "2006-03-01/""><Name>example-bucket</Name>" &
              "<Prefix>logs/</Prefix><KeyCount>3</KeyCount>" &
              "<MaxKeys>3</MaxKeys><Delimiter>/</Delimiter>" &
              "<EncodingType>url</EncodingType>" &
              "<ContinuationToken>input-token</ContinuationToken>" &
              "<NextContinuationToken>next-token</NextContinuationToken>" &
              "<StartAfter>before</StartAfter>" &
              "<IsTruncated>true</IsTruncated>" &
              "<Contents><Key>a&amp;b</Key>" &
              "<LastModified>2026-08-21T00:00:00.000Z</LastModified>" &
              "<ETag>&quot;etag-1&quot;</ETag><Size>0</Size>" &
              "<StorageClass>STANDARD</StorageClass></Contents>" &
              "<Contents><Key>logs/object</Key><Size>9223372036854775807" &
              "</Size></Contents><CommonPrefixes><Prefix>logs/archive/" &
              "</Prefix></CommonPrefixes><Future><Nested>ignored</Nested>" &
              "</Future></ListBucketResult>");
         Round_Trip : constant Listings.List_Objects_V2_Result :=
           Listings.Parse_List_Objects_V2
             (Listings.Serialize_List_Objects_V2 (Parsed));
      begin
         Assert
           (US.To_String (Parsed.Name) = "example-bucket"
            and then Parsed.Key_Count = 3
            and then Parsed.Max_Keys = 3
            and then Parsed.Is_Truncated
            and then Parsed.Has_Delimiter
            and then Parsed.Has_Continuation_Token
            and then Parsed.Has_Next_Continuation_Token
            and then Parsed.Has_Start_After
            and then US.To_String (Parsed.Next_Continuation_Token) =
              "next-token"
            and then Parsed.Contents.Length = 2
            and then Parsed.Common_Prefixes.Length = 1,
            "ListObjectsV2 root fields");
         Assert
           (US.To_String (Parsed.Contents.First_Element.Key) = "a&b"
            and then Parsed.Contents.First_Element.Size = 0
            and then Parsed.Contents.Last_Element.Size =
              Flyology.Object_Storage.Byte_Count'Last,
            "ListObjectsV2 object fields and 64-bit size");
         Assert
           (Round_Trip.Key_Count = Parsed.Key_Count
            and then Round_Trip.Contents.Length = Parsed.Contents.Length
            and then US.To_String (Round_Trip.Contents.First_Element.Key) =
              "a&b",
            "ListObjectsV2 serialization round trip");
      end;

      Must_Reject
        ("<Wrong><Name>bucket</Name><KeyCount>0</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated></Wrong>",
         "ListObjectsV2 wrong root was accepted");
      Must_Reject
        (Empty_Listing ("<Name>again</Name>"),
         "ListObjectsV2 duplicate singleton was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>0</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>True</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjectsV2 invalid boolean was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>0</KeyCount>" &
         "<MaxKeys>1001</MaxKeys><IsTruncated>false</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjectsV2 oversized response page was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name>" &
         "<KeyCount>999999999999999999999999</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjectsV2 overflowing count was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>1</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key><Size>9223372036854775808</Size>" &
         "</Contents></ListBucketResult>",
         "ListObjectsV2 overflowing object size was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>1</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjectsV2 inconsistent key count was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>0</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
         "</ListBucketResult>",
         "ListObjectsV2 truncated page without token was accepted");
      Must_Reject
        (Empty_Listing
           ("<NextContinuationToken>unexpected</NextContinuationToken>"),
         "ListObjectsV2 token on final page was accepted");
      Must_Reject
        (Empty_Listing
           ("<NextContinuationToken></NextContinuationToken>"),
         "ListObjectsV2 empty token on final page was accepted");
      Must_Reject
        (Empty_Listing ("<EncodingType></EncodingType>"),
         "ListObjectsV2 empty encoding type was accepted");
      Must_Reject
        (Empty_Listing ("<EncodingType>xml</EncodingType>"),
         "ListObjectsV2 invalid encoding type was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>1</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key></Contents></ListBucketResult>",
         "ListObjectsV2 object without size was accepted");
      Must_Reject
        ("<ListBucketResult><Name>bucket</Name><KeyCount>1</KeyCount>" &
         "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
         "<Contents><Key>x</Key><Size>1</Size><Size>2</Size>" &
         "</Contents></ListBucketResult>",
         "ListObjectsV2 duplicate object field was accepted");
      Must_Reject
        (Empty_Listing ("<Name><Nested/></Name>"),
         "ListObjectsV2 nested scalar was accepted");
      Must_Reject
        ("<ListBucketResult>non-whitespace<Name>bucket</Name>" &
         "<KeyCount>0</KeyCount><MaxKeys>1</MaxKeys>" &
         "<IsTruncated>false</IsTruncated></ListBucketResult>",
         "ListObjectsV2 root text was accepted");

      declare
         Request : constant Listings.List_Objects_V2_Request :=
           Listings.Parse_List_Objects_V2_Query
             ("delimiter=%2F&encoding-type=url&fetch-owner=false&" &
              "list-type=2&max-keys=7&prefix=logs%2F%2B&" &
              "start-after=a+b&x-id=ListObjectsV2");
      begin
         Assert
           (US.To_String (Request.Prefix) = "logs/+"
            and then US.To_String (Request.Delimiter) = "/"
            and then US.To_String (Request.Start_After) = "a+b"
            and then Request.Max_Keys = 7
            and then not Request.Fetch_Owner
            and then Request.Has_Delimiter
            and then Request.Has_Start_After
            and then Request.Has_Fetch_Owner
            and then Request.URL_Encoding,
            "ListObjectsV2 query decoding");
      end;

      declare
         Request : constant Listings.List_Objects_V2_Request :=
           Listings.Parse_List_Objects_V2_Query
             ("delimiter=&fetch-owner=false&list-type=2&start-after=");
         Value : Listings.List_Objects_V2_Result;
         Round_Trip : Listings.List_Objects_V2_Result;
      begin
         Assert
           (Request.Has_Delimiter
            and then US.Length (Request.Delimiter) = 0
            and then Request.Has_Fetch_Owner
            and then not Request.Fetch_Owner
            and then Request.Has_Start_After
            and then US.Length (Request.Start_After) = 0,
            "present empty ListObjectsV2 query members were collapsed");
         Value.Name := US.To_Unbounded_String ("bucket");
         Value.Has_Delimiter := True;
         Value.Has_Start_After := True;
         Round_Trip := Listings.Parse_List_Objects_V2
           (Listings.Serialize_List_Objects_V2 (Value));
         Assert
           (Round_Trip.Has_Delimiter
            and then US.Length (Round_Trip.Delimiter) = 0
            and then Round_Trip.Has_Start_After
            and then US.Length (Round_Trip.Start_After) = 0,
            "present empty ListObjectsV2 response members were collapsed");
      end;

      Must_Reject_Query
        ("list-type=2&prefix=%GG", "invalid listing escape was accepted");
      Must_Reject_Query
        ("list-type=2&prefix=a&prefix=b",
         "duplicate listing prefix was accepted");
      Must_Reject_Query
        ("list-type=2&max-keys=1001",
         "oversized listing page was accepted");
      Must_Reject_Query
        ("list-type=2&fetch-owner=yes",
         "invalid listing boolean was accepted");
      Must_Reject_Query
        ("max-keys=1", "listing without V2 selector was accepted");
      Must_Reject_Query
        ("list-type=2&unknown=value",
         "unknown listing parameter was accepted");
      declare
         Empty_Token : constant Listings.List_Objects_V2_Request :=
           Listings.Parse_List_Objects_V2_Query
             ("list-type=2&continuation-token=");
      begin
         Assert
           (Empty_Token.Has_Continuation_Token
            and then US.Length (Empty_Token.Continuation_Token) = 0,
            "present empty continuation token was not preserved");
      end;

      declare
         Token : constant String := Listings.Encode_Continuation
           ("bucket", "logs/", "/", "logs/archive/");
         Decoded : constant Listings.Continuation_Result :=
           Listings.Decode_Continuation
             (Token, "bucket", "logs/", "/");
         Wrong_Bucket : constant Listings.Continuation_Result :=
           Listings.Decode_Continuation
             (Token, "other", "logs/", "/");
         Wrong_Prefix : constant Listings.Continuation_Result :=
           Listings.Decode_Continuation
             (Token, "bucket", "other/", "/");
         Tampered : String := Token;
      begin
         Tampered (Tampered'Last) :=
           (if Tampered (Tampered'Last) = '0' then '1' else '0');
         Assert
           (Decoded.Valid
            and then US.To_String (Decoded.After) = "logs/archive/"
            and then not Wrong_Bucket.Valid
            and then not Wrong_Prefix.Valid
            and then not Listings.Decode_Continuation
              (Tampered, "bucket", "logs/", "/").Valid,
            "listing continuation binding and tamper detection");
      end;

      declare
         Empty : constant Listings.Continuation_Result :=
           Listings.Decode_Continuation
             (Listings.Encode_Continuation ("bucket", "", "", ""),
              "bucket", "", "");
      begin
         Assert
           (Empty.Valid and then US.Length (Empty.After) = 0,
            "empty listing cursor token");
      end;
   end Check_List_Objects_V2_Codec;

   procedure Check_Multipart_Completion_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Multipart renames Flyology.Object_Storage.S3.Multipart;
      package US renames Ada.Strings.Unbounded;
      use type Multipart.Multipart_Query_Kind;

      procedure Must_Reject (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant
                 Multipart.Complete_Multipart_Upload_Request :=
                   Multipart.Parse_Complete_Request (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject;

      procedure Must_Reject_Query (Query, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.Multipart_Query :=
                 Multipart.Parse_Query (Query);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Query;
   begin
      declare
         Create : constant Multipart.Multipart_Query :=
           Multipart.Parse_Query
             ("x-id=CreateMultipartUpload&uploads=");
         Part : constant Multipart.Multipart_Query :=
           Multipart.Parse_Query
             ("uploadId=upload%2B%2F%3D&partNumber=10000");
         Existing : constant Multipart.Multipart_Query :=
           Multipart.Parse_Query ("uploadId=a+b");
         Listed : constant Multipart.Multipart_Query :=
           Multipart.Parse_Query
             ("part-number-marker=7&uploadId=a+b&max-parts=11&" &
              "x-id=ListParts");
      begin
         Assert
           (Create.Kind = Multipart.Create_Upload_Query
            and then Part.Kind = Multipart.Upload_Part_Query
            and then Part.Part_Number = 10_000
            and then US.To_String (Part.Upload_ID) = "upload+/="
            and then Existing.Kind = Multipart.Existing_Upload_Query
            and then US.To_String (Existing.Existing_Upload_ID) = "a+b"
            and then Listed.Kind = Multipart.List_Parts_Query
            and then US.To_String (Listed.Listed_Upload_ID) = "a+b"
            and then Listed.Part_Number_Marker = 7
            and then Listed.Max_Parts = 11,
            "multipart query decoding and classification");
      end;
      Must_Reject_Query
        ("uploads&uploads=", "duplicate multipart uploads marker accepted");
      Must_Reject_Query
        ("uploadId=", "empty multipart upload identifier accepted");
      Must_Reject_Query
        ("uploadId=x&partNumber=0", "zero multipart part number accepted");
      Must_Reject_Query
        ("uploadId=x&partNumber=10001",
         "oversized multipart part number accepted");
      Must_Reject_Query
        ("uploadId=%GG&partNumber=1",
         "bad multipart percent escape accepted");
      Must_Reject_Query
        ("uploads=&uploadId=x", "mixed multipart query shapes accepted");
      Must_Reject_Query
        ("uploadId=x&unknown=y", "unknown multipart query field accepted");
      Must_Reject_Query
        ("uploadId=x&partNumber=1&x-id=AbortMultipartUpload",
         "wrong multipart operation identifier accepted");
      Must_Reject_Query
        ("uploadId=x&part-number-marker=10001",
         "oversized ListParts marker accepted");
      Must_Reject_Query
        ("uploadId=x&max-parts=1001", "oversized ListParts page accepted");
      Must_Reject_Query
        ("uploadId=x&max-parts=1&x-id=CompleteMultipartUpload",
         "mixed ListParts/completion query accepted");

      declare
         Parsed : constant Multipart.Complete_Multipart_Upload_Request :=
           Multipart.Parse_Complete_Request
             ("<CompleteMultipartUpload xmlns=""http://s3.amazonaws.com/" &
              "doc/2006-03-01/""><Part><ETag>&quot;etag-1&quot;</ETag>" &
              "<PartNumber>1</PartNumber><ChecksumCRC32>AAAAAA==" &
              "</ChecksumCRC32><ChecksumMD5>" &
              "AAAAAAAAAAAAAAAAAAAAAA==</ChecksumMD5>" &
              "<ChecksumXXHASH64>AAAAAAAAAAA=</ChecksumXXHASH64>" &
              "<Future><Nested>ignored</Nested></Future>" &
              "</Part><Part><PartNumber>2</PartNumber>" &
              "<ETag>&quot;etag&amp;2&quot;</ETag>" &
              "<ChecksumCRC32>AAAAAA==</ChecksumCRC32></Part>" &
              "</CompleteMultipartUpload>");
         Round_Trip : constant Multipart.Complete_Multipart_Upload_Request :=
           Multipart.Parse_Complete_Request
             (Multipart.Serialize_Complete_Request (Parsed));
      begin
         Assert
           (Parsed.Parts.Length = 2
            and then Parsed.Parts.First_Element.Number = 1
            and then Parsed.Parts.Last_Element.Number = 2
            and then US.To_String (Parsed.Parts.Last_Element.Entity_Tag) =
              """etag&2""",
            "multipart completion fields and namespace handling");
         Assert
           (Round_Trip.Parts.Length = 2
            and then Round_Trip.Parts.Last_Element.Number = 2
            and then US.To_String
              (Round_Trip.Parts.First_Element.Checksum_CRC32) = "AAAAAA=="
            and then US.To_String
              (Round_Trip.Parts.First_Element.Checksum_MD5) =
                "AAAAAAAAAAAAAAAAAAAAAA=="
            and then US.To_String
              (Round_Trip.Parts.First_Element.Checksum_XXHASH64) =
                "AAAAAAAAAAA=",
            "multipart completion serialization round trip");
      end;

      Must_Reject
        ("<Wrong><Part><ETag>x</ETag><PartNumber>1</PartNumber>" &
         "</Part></Wrong>",
         "multipart completion wrong root was accepted");
      Must_Reject
        ("<CompleteMultipartUpload/>",
         "empty multipart completion was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag>x</ETag>" &
         "<PartNumber>0</PartNumber></Part></CompleteMultipartUpload>",
         "multipart part zero was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag>x</ETag>" &
         "<PartNumber>2</PartNumber></Part><Part><ETag>y</ETag>" &
         "<PartNumber>1</PartNumber></Part></CompleteMultipartUpload>",
         "unordered multipart completion was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag>x</ETag>" &
         "<PartNumber>1</PartNumber><PartNumber>2</PartNumber>" &
         "</Part></CompleteMultipartUpload>",
         "duplicate multipart field was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><PartNumber>1</PartNumber>" &
         "</Part></CompleteMultipartUpload>",
         "multipart completion without ETag was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag>x</ETag>" &
         "<PartNumber>9999999999999999999999</PartNumber>" &
         "</Part></CompleteMultipartUpload>",
         "overflowing multipart part number was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag>x</ETag>" &
         "<PartNumber>1</PartNumber><ChecksumCRC32>abc</ChecksumCRC32>" &
         "</Part></CompleteMultipartUpload>",
         "malformed multipart checksum was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag>x</ETag>" &
         "<PartNumber>1</PartNumber><ChecksumCRC32>AAAAAA==" &
         "</ChecksumCRC32></Part><Part><ETag>y</ETag>" &
         "<PartNumber>3</PartNumber></Part></CompleteMultipartUpload>",
         "gapped checksummed multipart completion was accepted");
      Must_Reject
        ("<CompleteMultipartUpload><Part><ETag><Nested/></ETag>" &
         "<PartNumber>1</PartNumber></Part></CompleteMultipartUpload>",
         "nested multipart scalar was accepted");

      declare
         Parsed : constant Multipart.Create_Multipart_Upload_Result :=
           Multipart.Parse_Create_Result
             ("<InitiateMultipartUploadResult>" &
              "<Bucket>example-bucket</Bucket><Key>a&amp;b</Key>" &
              "<UploadId>upload-1</UploadId>" &
              "<Future><Nested>ignored</Nested></Future>" &
              "</InitiateMultipartUploadResult>");
         Round_Trip : constant Multipart.Create_Multipart_Upload_Result :=
           Multipart.Parse_Create_Result
             (Multipart.Serialize_Create_Result (Parsed));
      begin
         Assert
           (US.To_String (Round_Trip.Bucket) = "example-bucket"
            and then US.To_String (Round_Trip.Key) = "a&b"
            and then US.To_String (Round_Trip.Upload_ID) = "upload-1",
            "CreateMultipartUpload result round trip");
      end;

      declare
         Parsed : constant Multipart.Complete_Multipart_Upload_Result :=
           Multipart.Parse_Complete_Result
             ("<CompleteMultipartUploadResult>" &
              "<Location>https://example.invalid/a</Location>" &
              "<Bucket>example-bucket</Bucket><Key>a</Key>" &
              "<ETag>&quot;etag&quot;</ETag>" &
              "<ChecksumMD5>AAAAAAAAAAAAAAAAAAAAAA==</ChecksumMD5>" &
              "<ChecksumXXHASH128>" &
              "AAAAAAAAAAAAAAAAAAAAAA==</ChecksumXXHASH128>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>" &
              "</CompleteMultipartUploadResult>");
         Round_Trip : constant Multipart.Complete_Multipart_Upload_Result :=
           Multipart.Parse_Complete_Result
             (Multipart.Serialize_Complete_Result (Parsed));
      begin
         Assert
           (US.To_String (Round_Trip.Entity_Tag) = """etag"""
            and then US.To_String (Round_Trip.Checksum_MD5) =
              "AAAAAAAAAAAAAAAAAAAAAA=="
            and then US.To_String (Round_Trip.Checksum_XXHASH128) =
              "AAAAAAAAAAAAAAAAAAAAAA=="
            and then US.To_String (Round_Trip.Checksum_Type) =
              "FULL_OBJECT",
            "CompleteMultipartUpload result round trip");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.Create_Multipart_Upload_Result :=
                 Multipart.Parse_Create_Result
                   ("<InitiateMultipartUploadResult>" &
                    "<UploadId>one</UploadId><UploadId>two</UploadId>" &
                    "</InitiateMultipartUploadResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, "duplicate create multipart result was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.Complete_Multipart_Upload_Result :=
                 Multipart.Parse_Complete_Result
                   ("<CompleteMultipartUploadResult>" &
                    "<ChecksumSHA512>abc</ChecksumSHA512>" &
                    "</CompleteMultipartUploadResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, "invalid complete multipart checksum was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.Complete_Multipart_Upload_Result :=
                 Multipart.Parse_Complete_Result
                   ("<CompleteMultipartUploadResult>" &
                    "<ChecksumType>UNKNOWN</ChecksumType>" &
                    "</CompleteMultipartUploadResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, "invalid multipart checksum type was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.Create_Multipart_Upload_Result :=
                 Multipart.Parse_Create_Result
                   ("<InitiateMultipartUploadResult>" &
                    "<Bucket>example-bucket</Bucket><Key>key</Key>" &
                    "</InitiateMultipartUploadResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, "create result without upload ID was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.Complete_Multipart_Upload_Result :=
                 Multipart.Parse_Complete_Result
                   ("<CompleteMultipartUploadResult>" &
                    "<Bucket>example-bucket</Bucket><Key>key</Key>" &
                    "</CompleteMultipartUploadResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, "complete result without ETag was accepted");
      end;
   end Check_Multipart_Completion_Codec;

   procedure Check_List_Parts_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Multipart renames Flyology.Object_Storage.S3.Multipart;
      package US renames Ada.Strings.Unbounded;

      function Root (Content : String) return String is
        ("<ListPartsResult><Bucket>bucket</Bucket><Key>key</Key>" &
         "<UploadId>upload</UploadId><PartNumberMarker>0" &
         "</PartNumberMarker><MaxParts>2</MaxParts>" &
         "<IsTruncated>false</IsTruncated>" & Content &
         "</ListPartsResult>");

      procedure Must_Reject (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Multipart.List_Parts_Result :=
                 Multipart.Parse_List_Parts_Result (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Multipart.Malformed_Multipart =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject;
   begin
      declare
         Parsed : constant Multipart.List_Parts_Result :=
           Multipart.Parse_List_Parts_Result
             ("<ListPartsResult xmlns=""http://s3.amazonaws.com/doc/" &
              "2006-03-01/""><Bucket>bucket</Bucket><Key>a&amp;b</Key>" &
              "<UploadId>upload</UploadId><PartNumberMarker>1" &
              "</PartNumberMarker><NextPartNumberMarker>2" &
              "</NextPartNumberMarker><MaxParts>1</MaxParts>" &
              "<IsTruncated>true</IsTruncated><Part>" &
              "<PartNumber>2</PartNumber>" &
              "<LastModified>2026-08-21T12:00:00.000Z</LastModified>" &
              "<ETag>&quot;etag&quot;</ETag>" &
              "<Size>9223372036854775807</Size>" &
              "<ChecksumCRC32>AAAAAA==</ChecksumCRC32>" &
              "<ChecksumCRC32C>AAAAAA==</ChecksumCRC32C>" &
              "<ChecksumCRC64NVME>AAAAAAAAAAA=</ChecksumCRC64NVME>" &
              "<ChecksumSHA1>AAAAAAAAAAAAAAAAAAAAAAAAAAA=</ChecksumSHA1>" &
              "<ChecksumSHA256>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" &
              "</ChecksumSHA256><ChecksumSHA512>" &
              String'(1 .. 86 => 'A') & "==</ChecksumSHA512>" &
              "<ChecksumMD5>AAAAAAAAAAAAAAAAAAAAAA==</ChecksumMD5>" &
              "<ChecksumXXHASH64>AAAAAAAAAAA=</ChecksumXXHASH64>" &
              "<ChecksumXXHASH3>AAAAAAAAAAA=</ChecksumXXHASH3>" &
              "<ChecksumXXHASH128>AAAAAAAAAAAAAAAAAAAAAA==" &
              "</ChecksumXXHASH128></Part>" &
              "<Initiator><ID>initiator-id</ID>" &
              "<DisplayName>initiator</DisplayName></Initiator>" &
              "<Owner><ID>owner-id</ID><DisplayName>owner</DisplayName>" &
              "</Owner><StorageClass>STANDARD</StorageClass>" &
              "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>" &
              "<Future><Nested>ignored</Nested></Future>" &
              "</ListPartsResult>");
         Round_Trip : constant Multipart.List_Parts_Result :=
           Multipart.Parse_List_Parts_Result
             (Multipart.Serialize_List_Parts_Result (Parsed));
      begin
         Assert
           (Parsed.Parts.Length = 1
            and then Parsed.Parts.First_Element.Number = 2
            and then Parsed.Parts.First_Element.Size =
              Flyology.Object_Storage.Byte_Count'Last
            and then US.To_String (Parsed.Key) = "a&b"
            and then Parsed.Has_Initiator
            and then Parsed.Has_Owner
            and then US.To_String (Parsed.Owner.ID) = "owner-id"
            and then US.To_String (Parsed.Storage_Class) = "STANDARD"
            and then US.To_String (Parsed.Checksum_Algorithm) = "SHA256"
            and then US.To_String (Parsed.Checksum_Type) = "FULL_OBJECT",
            "ListParts complete response fields");
         Assert
           (Round_Trip.Parts.Length = 1
            and then Round_Trip.Next_Part_Number_Marker = 2
            and then Round_Trip.Parts.First_Element.Size =
              Flyology.Object_Storage.Byte_Count'Last
            and then US.To_String
              (Round_Trip.Parts.First_Element.Checksum_SHA512) =
                String'(1 .. 86 => 'A') & "=="
            and then US.To_String
              (Round_Trip.Parts.First_Element.Checksum_XXHASH128) =
                "AAAAAAAAAAAAAAAAAAAAAA==",
            "ListParts serialization round trip");
      end;

      declare
         Empty : constant Multipart.List_Parts_Result :=
           Multipart.Parse_List_Parts_Result (Root (""));
      begin
         Assert
           (Empty.Parts.Is_Empty and then not Empty.Is_Truncated,
            "ListParts empty final page");
      end;

      Must_Reject ("<Wrong/>", "ListParts wrong root was accepted");
      Must_Reject
        ("<ListPartsResult><Bucket>bucket</Bucket></ListPartsResult>",
         "ListParts missing required fields was accepted");
      Must_Reject
        (Root ("<Bucket>again</Bucket>"),
         "ListParts duplicate scalar was accepted");
      Must_Reject
        ("<ListPartsResult><Bucket>bucket</Bucket><Key>key</Key>" &
         "<UploadId>upload</UploadId><PartNumberMarker>10001" &
         "</PartNumberMarker><MaxParts>1</MaxParts>" &
         "<IsTruncated>false</IsTruncated></ListPartsResult>",
         "ListParts oversized marker was accepted");
      Must_Reject
        ("<ListPartsResult><Bucket>bucket</Bucket><Key>key</Key>" &
         "<UploadId>upload</UploadId><PartNumberMarker>0" &
         "</PartNumberMarker><MaxParts>1001</MaxParts>" &
         "<IsTruncated>false</IsTruncated></ListPartsResult>",
         "ListParts oversized page size was accepted");
      Must_Reject
        ("<ListPartsResult><Bucket>bucket</Bucket><Key>key</Key>" &
         "<UploadId>upload</UploadId><PartNumberMarker>0" &
         "</PartNumberMarker><MaxParts>1</MaxParts>" &
         "<IsTruncated>True</IsTruncated></ListPartsResult>",
         "ListParts noncanonical boolean was accepted");
      Must_Reject
        (Root ("<Part><PartNumber>1</PartNumber>" &
               "<LastModified>x</LastModified><ETag>e</ETag>" &
               "<Size>9223372036854775808</Size></Part>"),
         "ListParts overflowing part size was accepted");
      Must_Reject
        (Root ("<Part><PartNumber>1</PartNumber>" &
               "<LastModified>x</LastModified><ETag>e</ETag><Size>1</Size>" &
               "<ChecksumCRC32>abc</ChecksumCRC32></Part>"),
         "ListParts malformed checksum was accepted");
      Must_Reject
        (Root ("<Part><PartNumber>2</PartNumber><LastModified>x" &
               "</LastModified><ETag>e</ETag><Size>1</Size></Part>" &
               "<Part><PartNumber>1</PartNumber><LastModified>x" &
               "</LastModified><ETag>e</ETag><Size>1</Size></Part>"),
         "ListParts unordered parts were accepted");
      Must_Reject
        ("<ListPartsResult><Bucket>bucket</Bucket><Key>key</Key>" &
         "<UploadId>upload</UploadId><PartNumberMarker>0" &
         "</PartNumberMarker><NextPartNumberMarker>2" &
         "</NextPartNumberMarker><MaxParts>1</MaxParts>" &
         "<IsTruncated>true</IsTruncated><Part>" &
         "<PartNumber>1</PartNumber><LastModified>x</LastModified>" &
         "<ETag>e</ETag><Size>1</Size></Part></ListPartsResult>",
         "ListParts mismatched next marker was accepted");
      Must_Reject
        (Root ("<StorageClass>UNKNOWN</StorageClass>"),
         "ListParts invalid storage class was accepted");
      Must_Reject
        (Root ("<ChecksumAlgorithm>UNKNOWN</ChecksumAlgorithm>"),
         "ListParts invalid checksum algorithm was accepted");
      Must_Reject
        (Root ("<ChecksumType>FULL_OBJECT</ChecksumType>"),
         "ListParts checksum type without algorithm was accepted");
      Must_Reject
        (Root ("<Part><PartNumber><Nested/></PartNumber>" &
               "<LastModified>x</LastModified><ETag>e</ETag>" &
               "<Size>1</Size></Part>"),
         "ListParts nested scalar was accepted");
   end Check_List_Parts_Codec;

   procedure Check_Object_Attributes_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Attributes renames
        Flyology.Object_Storage.S3.Attributes;
      package US renames Ada.Strings.Unbounded;

      procedure Selection_Must_Reject (Value, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Attributes.Attribute_Selection :=
                 Attributes.Parse_Selection (Value);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Attributes.Malformed_Attributes =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Selection_Must_Reject;

      procedure Query_Must_Reject (Value, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Attributes.Attributes_Query :=
                 Attributes.Parse_Query (Value);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Attributes.Malformed_Attributes =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Query_Must_Reject;

      procedure Result_Must_Reject (Value, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant
                 Attributes.Get_Object_Attributes_Result :=
                   Attributes.Parse_Result (Value);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Attributes.Malformed_Attributes =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Result_Must_Reject;

      function Root (Content : String) return String is
        ("<GetObjectAttributesResponse>" & Content &
         "</GetObjectAttributesResponse>");
   begin
      declare
         Selection : constant Attributes.Attribute_Selection :=
           Attributes.Parse_Selection
             (" ETag," & ASCII.HT & "Checksum,ObjectParts," &
              "StorageClass,ObjectSize ");
      begin
         Assert
           (Selection.Entity_Tag and then Selection.Checksum
            and then Selection.Object_Parts
            and then Selection.Storage_Class
            and then Selection.Object_Size
            and then Attributes.Image (Selection) =
              "ETag,Checksum,ObjectParts,StorageClass,ObjectSize",
            "object-attributes selection parsing");
      end;
      Selection_Must_Reject
        ("", "empty object-attributes selection accepted");
      Selection_Must_Reject
        ("ETag,ETag", "duplicate object attribute accepted");
      Selection_Must_Reject
        ("ETag,Future", "unknown object attribute accepted");
      Selection_Must_Reject
        ("ETag,,ObjectSize", "empty object attribute accepted");
      Selection_Must_Reject
        ("ETag" & ASCII.LF, "control byte in object attributes accepted");

      declare
         Query : constant Attributes.Attributes_Query :=
           Attributes.Parse_Query
             ("attributes&versionId=null&x-id=GetObjectAttributes");
      begin
         Assert
           (Query.Has_Version_ID
            and then US.To_String (Query.Version_ID) = "null",
            "attributes query parsing");
      end;
      Query_Must_Reject
        ("versionId=null", "attributes query without marker accepted");
      Query_Must_Reject
        ("attributes&attributes", "duplicate attributes marker accepted");
      Query_Must_Reject
        ("attributes=1", "valued attributes marker accepted");
      Query_Must_Reject
        ("attributes&versionId=%GG", "bad attributes escape accepted");
      Query_Must_Reject
        ("attributes&x-id=GetObject", "wrong attributes x-id accepted");

      declare
         Document : constant String :=
           "<GetObjectAttributesResponse xmlns=""http://s3.amazonaws.com/" &
           "doc/2006-03-01/""><ETag>etag&amp;opaque</ETag>" &
           "<Checksum><ChecksumCRC32>AAAAAA==</ChecksumCRC32>" &
           "<ChecksumCRC32C>AAAAAA==</ChecksumCRC32C>" &
           "<ChecksumCRC64NVME>AAAAAAAAAAA=</ChecksumCRC64NVME>" &
           "<ChecksumSHA1>AAAAAAAAAAAAAAAAAAAAAAAAAAA=</ChecksumSHA1>" &
           "<ChecksumSHA256>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" &
           "</ChecksumSHA256><ChecksumSHA512>" &
           String'(1 .. 86 => 'A') & "==</ChecksumSHA512>" &
           "<ChecksumMD5>AAAAAAAAAAAAAAAAAAAAAA==</ChecksumMD5>" &
           "<ChecksumXXHASH64>AAAAAAAAAAA=</ChecksumXXHASH64>" &
           "<ChecksumXXHASH3>AAAAAAAAAAA=</ChecksumXXHASH3>" &
           "<ChecksumXXHASH128>AAAAAAAAAAAAAAAAAAAAAA==" &
           "</ChecksumXXHASH128><ChecksumType>COMPOSITE</ChecksumType>" &
           "</Checksum><ObjectParts><PartsCount>2</PartsCount>" &
           "<PartNumberMarker>1</PartNumberMarker>" &
           "<NextPartNumberMarker>2</NextPartNumberMarker>" &
           "<MaxParts>1</MaxParts><IsTruncated>true</IsTruncated>" &
           "<Part><ChecksumCRC32>AAAAAA==</ChecksumCRC32>" &
           "<PartNumber>2</PartNumber><Size>9223372036854775807</Size>" &
           "</Part></ObjectParts><StorageClass>STANDARD_IA</StorageClass>" &
           "<ObjectSize>9223372036854775807</ObjectSize>" &
           "<Future><Nested>ignored</Nested></Future>" &
           "</GetObjectAttributesResponse>";
         Parsed : constant Attributes.Get_Object_Attributes_Result :=
           Attributes.Parse_Result (Document);
         Round_Trip : constant Attributes.Get_Object_Attributes_Result :=
           Attributes.Parse_Result (Attributes.Serialize_Result (Parsed));
      begin
         Assert
           (Parsed.Has_Entity_Tag
            and then US.To_String (Parsed.Entity_Tag) = "etag&opaque"
            and then Parsed.Has_Checksum
            and then US.To_String (Parsed.Checksum.Kind) = "COMPOSITE"
            and then Parsed.Has_Object_Parts
            and then Parsed.Object_Parts.Parts.Length = 1
            and then Parsed.Object_Parts.Parts.First_Element.Number.Value = 2
            and then Parsed.Object_Parts.Parts.First_Element.Size.Value =
              Flyology.Object_Storage.Byte_Count'Last
            and then Parsed.Has_Storage_Class
            and then Parsed.Object_Size.Value =
              Flyology.Object_Storage.Byte_Count'Last,
            "complete GetObjectAttributes response fields");
         Assert
           (Round_Trip.Object_Parts.Has_Is_Truncated
            and then Round_Trip.Object_Parts.Is_Truncated
            and then Round_Trip.Object_Parts.Next_Part_Number_Marker.Value = 2
            and then US.To_String (Round_Trip.Checksum.SHA512) =
              String'(1 .. 86 => 'A') & "==",
            "GetObjectAttributes serialization round trip");
      end;

      Result_Must_Reject
        ("<Wrong/>", "wrong attributes result root accepted");
      declare
         Empty : constant Attributes.Get_Object_Attributes_Result :=
           Attributes.Parse_Result (Root (""));
      begin
         Assert
           (not Empty.Has_Entity_Tag
            and then not Empty.Has_Checksum
            and then not Empty.Has_Object_Parts
            and then not Empty.Has_Storage_Class
            and then not Empty.Object_Size.Is_Set,
            "empty selected-attribute response rejected");
      end;
      Result_Must_Reject
        (Root ("<ETag>a</ETag><ETag>b</ETag>"),
         "duplicate attributes result field accepted");
      Result_Must_Reject
        (Root ("<StorageClass>UNKNOWN</StorageClass>"),
         "unknown attributes storage class accepted");
      Result_Must_Reject
        (Root ("<ObjectSize>9223372036854775808</ObjectSize>"),
         "overflowing attributes object size accepted");
      Result_Must_Reject
        (Root ("<Checksum><ChecksumCRC32>abc</ChecksumCRC32>" &
               "</Checksum>"),
         "malformed attributes checksum accepted");
      Result_Must_Reject
        (Root ("<ObjectParts><MaxParts>1001</MaxParts>" &
               "</ObjectParts>"),
         "oversized attributes page accepted");
      Result_Must_Reject
        (Root ("<ObjectParts><IsTruncated>True</IsTruncated>" &
               "</ObjectParts>"),
         "noncanonical attributes boolean accepted");
      Result_Must_Reject
        (Root ("<ObjectParts><Part><PartNumber>1</PartNumber>" &
               "</Part></ObjectParts>"),
         "attributes part without size accepted");
      Result_Must_Reject
        (Root ("<ObjectParts><Part><PartNumber>2</PartNumber>" &
               "<Size>1</Size></Part><Part><PartNumber>1</PartNumber>" &
               "<Size>1</Size></Part></ObjectParts>"),
         "unordered attributes parts accepted");
      Result_Must_Reject
        (Root ("<ETag><Nested/></ETag>"),
         "nested attributes scalar accepted");
   end Check_Object_Attributes_Codec;

   procedure Check_List_Multipart_Uploads_Codec
     (Unused : in out Fixture)
   is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Uploads renames
        Flyology.Object_Storage.S3.Multipart_Uploads;
      package US renames Ada.Strings.Unbounded;

      function Root (Content : String; Max_Uploads : Natural := 3)
         return String
      is
        ("<ListMultipartUploadsResult><Bucket>bucket</Bucket>" &
         "<MaxUploads>" & Ada.Strings.Fixed.Trim
           (Natural'Image (Max_Uploads), Ada.Strings.Both) &
         "</MaxUploads><IsTruncated>false</IsTruncated>" & Content &
         "</ListMultipartUploadsResult>");

      procedure Must_Reject (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Uploads.List_Multipart_Uploads_Result :=
                 Uploads.Parse_List_Multipart_Uploads (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Uploads.Malformed_Upload_Listing =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject;

      procedure Must_Reject_Query (Query, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Uploads.List_Multipart_Uploads_Request :=
                 Uploads.Parse_List_Multipart_Uploads_Query (Query);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Uploads.Malformed_List_Request => Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Query;

      function Upload_XML
        (Key, Upload_ID, Initiated : String;
         Extra : String := "") return String
      is
        ("<Upload><UploadId>" & Upload_ID & "</UploadId><Key>" & Key &
         "</Key><Initiated>" & Initiated &
         "</Initiated><StorageClass>STANDARD</StorageClass>" & Extra &
         "</Upload>");
   begin
      declare
         Request : constant Uploads.List_Multipart_Uploads_Request :=
           Uploads.Parse_List_Multipart_Uploads_Query
             ("delimiter=%2F&encoding-type=url&key-marker=before%2Bkey&" &
              "max-uploads=17&prefix=logs%2F&" &
              "upload-id-marker=ignored-without-policy&uploads&" &
              "x-id=ListMultipartUploads");
      begin
         Assert
           (US.To_String (Request.Delimiter) = "/"
            and then Request.URL_Encoding
            and then US.To_String (Request.Key_Marker) = "before+key"
            and then Request.Max_Uploads = 17
            and then US.To_String (Request.Prefix) = "logs/"
            and then US.To_String (Request.Upload_ID_Marker) =
              "ignored-without-policy",
            "ListMultipartUploads complete query parsing");
      end;
      Must_Reject_Query
        ("max-uploads=1", "ListMultipartUploads marker omission accepted");
      Must_Reject_Query
        ("uploads=x", "nonempty ListMultipartUploads marker accepted");
      Must_Reject_Query
        ("max-uploads=0&uploads", "zero max-uploads accepted");
      Must_Reject_Query
        ("max-uploads=1001&uploads", "oversized max-uploads accepted");
      Must_Reject_Query
        ("uploads&prefix=a&prefix=b", "duplicate upload prefix accepted");
      Must_Reject_Query
        ("uploads&encoding-type=xml", "invalid upload encoding accepted");
      Must_Reject_Query
        ("uploads&prefix=%GG", "invalid upload query escape accepted");
      Must_Reject_Query
        ("uploads&unknown=x", "unknown upload query field accepted");
      Must_Reject_Query
        ("uploads&x-id=ListParts", "wrong upload operation ID accepted");

      declare
         Parsed : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads
             ("<ListMultipartUploadsResult " &
              "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
              "<Bucket>bucket</Bucket><KeyMarker>before</KeyMarker>" &
              "<UploadIdMarker>upload-before</UploadIdMarker>" &
              "<NextKeyMarker>logs/b</NextKeyMarker>" &
              "<NextUploadIdMarker>upload-b</NextUploadIdMarker>" &
              "<Prefix>logs/</Prefix><Delimiter>/</Delimiter>" &
              "<MaxUploads>3</MaxUploads><IsTruncated>true" &
              "</IsTruncated>" &
              Upload_XML
                ("logs/a", "upload-a", "2026-08-21T01:00:00.000Z",
                 "<Owner><ID>owner-id</ID><DisplayName>owner" &
                 "</DisplayName></Owner><Initiator><ID>init-id</ID>" &
                 "<DisplayName>initiator</DisplayName></Initiator>" &
                 "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
                 "<ChecksumType>COMPOSITE</ChecksumType>") &
              Upload_XML
                ("logs/b", "upload-b", "2026-08-21T02:00:00.000Z") &
              "<CommonPrefixes><Prefix>logs/archive/</Prefix>" &
              "</CommonPrefixes><EncodingType>url</EncodingType>" &
              "<Future><Nested>ignored</Nested></Future>" &
              "</ListMultipartUploadsResult>");
         Round_Trip : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads
             (Uploads.Serialize_List_Multipart_Uploads (Parsed));
      begin
         Assert
           (Parsed.Uploads.Length = 2
            and then Parsed.Common_Prefixes.Length = 1
            and then Parsed.Is_Truncated
            and then US.To_String (Parsed.Next_Key_Marker) = "logs/b"
            and then US.To_String
              (Parsed.Uploads.First_Element.Owner.ID) = "owner-id"
            and then Parsed.Uploads.First_Element.Has_Owner
            and then Parsed.Uploads.First_Element.Has_Initiator
            and then US.To_String
              (Parsed.Uploads.First_Element.Checksum_Algorithm) = "SHA256"
            and then US.To_String
              (Parsed.Uploads.First_Element.Checksum_Type) = "COMPOSITE",
            "complete ListMultipartUploads response fields");
         Assert
           (Round_Trip.Uploads.Length = 2
            and then Round_Trip.Common_Prefixes.Length = 1
            and then US.To_String
              (Round_Trip.Common_Prefixes.First_Element) = "logs/archive/"
            and then US.To_String (Round_Trip.Encoding_Type) = "url",
            "ListMultipartUploads serialization round trip");
      end;

      declare
         Empty : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads (Root (""));
      begin
         Assert
           (Empty.Uploads.Is_Empty
            and then Empty.Common_Prefixes.Is_Empty
            and then not Empty.Is_Truncated,
            "empty ListMultipartUploads final page");
      end;

      Must_Reject ("<Wrong/>", "wrong multipart-upload list root accepted");
      Must_Reject
        ("<ListMultipartUploadsResult><Bucket>bucket</Bucket>" &
         "</ListMultipartUploadsResult>",
         "multipart-upload list missing required fields accepted");
      Must_Reject
        (Root ("<Bucket>again</Bucket>"),
         "duplicate multipart-upload list scalar accepted");
      Must_Reject
        (Root ("", 1_001), "oversized max-uploads accepted");
      Must_Reject
        ("<ListMultipartUploadsResult><Bucket>bucket</Bucket>" &
         "<MaxUploads>1</MaxUploads><IsTruncated>True</IsTruncated>" &
         "</ListMultipartUploadsResult>",
         "noncanonical multipart-upload list boolean accepted");
      Must_Reject
        (Root ("<Upload><UploadId>id</UploadId></Upload>"),
         "incomplete multipart upload accepted");
      declare
         Without_Storage : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads
             (Root
                ("<Upload><UploadId>id</UploadId><Key>key</Key>" &
                 "<Initiated>2026-08-21T01:00:00.000Z</Initiated>" &
                 "</Upload>"));
      begin
         Assert
           (Without_Storage.Uploads.Length = 1
            and then US.Length
              (Without_Storage.Uploads.First_Element.Storage_Class) = 0,
            "model-optional multipart storage class was rejected");
      end;
      Must_Reject
        (Root
           ("<Upload><UploadId><Nested/></UploadId><Key>key</Key>" &
            "<Initiated>x</Initiated><StorageClass>STANDARD" &
            "</StorageClass></Upload>"),
         "nested multipart upload scalar accepted");
      Must_Reject
        (Root
           ("<Upload><UploadId>id</UploadId><Key>key</Key>" &
            "<Initiated>x</Initiated><StorageClass>UNKNOWN" &
            "</StorageClass></Upload>"),
         "invalid multipart upload storage class accepted");
      Must_Reject
        (Root ("<EncodingType>xml</EncodingType>"),
         "invalid multipart-upload encoding type accepted");
      Must_Reject
        (Root
           (Upload_XML
              ("key", "id", "x",
               "<ChecksumAlgorithm>UNKNOWN</ChecksumAlgorithm>")),
         "invalid multipart upload checksum algorithm accepted");
      Must_Reject
        (Root
           (Upload_XML
              ("key", "id", "x",
               "<ChecksumType>UNKNOWN</ChecksumType>")),
         "invalid multipart upload checksum type accepted");
      declare
         Type_Only : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads
             (Root
                (Upload_XML
                   ("key", "id", "x",
                    "<ChecksumType>COMPOSITE</ChecksumType>")));
      begin
         Assert
           (US.To_String
              (Type_Only.Uploads.First_Element.Checksum_Type) = "COMPOSITE",
            "independent multipart upload checksum type was rejected");
      end;
      declare
         Directory_Order : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads
             (Root
                (Upload_XML ("b", "id-b", "x") &
                 Upload_XML ("a", "id-a", "x")));
      begin
         Assert
           (Directory_Order.Uploads.Length = 2,
            "directory-bucket multipart upload order was rejected");
      end;
      declare
         Marker_Variance : constant Uploads.List_Multipart_Uploads_Result :=
           Uploads.Parse_List_Multipart_Uploads
             ("<ListMultipartUploadsResult><Bucket>bucket</Bucket>" &
              "<UploadIdMarker>ignored-without-key</UploadIdMarker>" &
              "<NextKeyMarker>sample.jpg</NextKeyMarker>" &
              "<NextUploadIdMarker>next-id</NextUploadIdMarker>" &
              "<MaxUploads>1</MaxUploads><IsTruncated>false" &
              "</IsTruncated></ListMultipartUploadsResult>");
      begin
         Assert
           (US.To_String (Marker_Variance.Upload_ID_Marker) =
              "ignored-without-key"
            and then US.To_String (Marker_Variance.Next_Key_Marker) =
              "sample.jpg",
            "valid AWS multipart-upload marker variance was rejected");
      end;
      Must_Reject
        ("<ListMultipartUploadsResult><Bucket>bucket</Bucket>" &
         "<MaxUploads>1</MaxUploads><IsTruncated>true</IsTruncated>" &
         "</ListMultipartUploadsResult>",
         "truncated multipart-upload page without next key accepted");
      Must_Reject
        (Root
           (Upload_XML ("a", "id-a", "x") &
            Upload_XML ("b", "id-b", "x"), 1),
         "multipart-upload page exceeding max-uploads accepted");
      declare
         Prefixes_Do_Not_Consume_Upload_Limit : constant
           Uploads.List_Multipart_Uploads_Result :=
             Uploads.Parse_List_Multipart_Uploads
               (Root
                  (Upload_XML ("a", "id-a", "x") &
                   "<CommonPrefixes><Prefix>b/</Prefix></CommonPrefixes>",
                   1));
      begin
         Assert
           (Prefixes_Do_Not_Consume_Upload_Limit.Uploads.Length = 1
            and then
              Prefixes_Do_Not_Consume_Upload_Limit.Common_Prefixes.Length = 1,
            "common prefixes incorrectly consumed max-uploads");
      end;
      Must_Reject
        (Root ("<CommonPrefixes></CommonPrefixes>"),
         "empty multipart common-prefix structure accepted");
      Must_Reject
        (Root
           ("<CommonPrefixes><Prefix>a/</Prefix><Prefix>b/</Prefix>" &
            "</CommonPrefixes>"),
         "duplicate multipart common prefix accepted");
   end Check_List_Multipart_Uploads_Codec;

   procedure Check_Bucket_Tagging_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Tagging renames Flyology.Object_Storage.S3.Tagging;
      package Tags renames Flyology.Object_Storage.Tags;
      package US renames Ada.Strings.Unbounded;
      use type Tags.Tag_Vectors.Vector;

      procedure Must_Reject_Malformed (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Tags.Tag_Set :=
                 Tagging.Parse_Bucket (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Tagging.Malformed_Tagging =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Malformed;

      procedure Must_Reject_Tag (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Tags.Tag_Set :=
                 Tagging.Parse_Bucket (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Tagging.Invalid_Tag =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Tag;

      function Root (Content : String) return String is
        ("<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<TagSet>" & Content & "</TagSet></Tagging>");

      function Tag_XML (Key, Value : String) return String is
        ("<Tag><Key>" & Key & "</Key><Value>" & Value &
         "</Value></Tag>");
   begin
      declare
         Parsed : constant Tags.Tag_Set :=
           Tagging.Parse_Bucket
             (Root
                (Tag_XML ("Project", "Flyology Ada") &
                 Tag_XML ("empty", "")));
         Round_Trip : constant Tags.Tag_Set :=
           Tagging.Parse_Bucket (Tagging.Serialize_Bucket (Parsed));
      begin
         Assert
           (Parsed.Length = 2
            and then US.To_String (Parsed.First_Element.Key) = "Project"
            and then US.To_String (Parsed.First_Element.Value) =
              "Flyology Ada"
            and then US.Length (Parsed.Last_Element.Value) = 0
            and then Round_Trip = Parsed,
            "bucket tagging XML did not preserve typed values");
      end;

      declare
         Namespace_Free : constant String :=
           "<Tagging><TagSet>" & Tag_XML ("project", "flyology") &
           "</TagSet></Tagging>";
         Parsed : constant Tags.Tag_Set :=
           Tagging.Parse_Bucket_Response (Namespace_Free);
         Rejected_Foreign : Boolean := False;
      begin
         Assert
           (Parsed.Length = 1
            and then US.To_String (Parsed.First_Element.Key) = "project",
            "namespace-free compatible response was rejected");
         begin
            declare
               Ignored : constant Tags.Tag_Set :=
                 Tagging.Parse_Bucket_Response
                   ("<x:Tagging xmlns:x=""urn:foreign""><x:TagSet/>" &
                    "</x:Tagging>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Tagging.Malformed_Tagging =>
               Rejected_Foreign := True;
         end;
         Assert
           (Rejected_Foreign,
            "foreign namespace in compatible response was accepted");
      end;

      Must_Reject_Malformed
        ("<Wrong/>", "bucket tagging wrong root was accepted");
      Must_Reject_Malformed
        ("<Tagging/>", "bucket tagging document without TagSet was accepted");
      Must_Reject_Malformed
        ("<Tagging><TagSet>" & Tag_XML ("a", "b") &
         "</TagSet></Tagging>",
         "bucket tagging document without the S3 namespace was accepted");
      Must_Reject_Malformed
        (Root ("<Tag extra=""x""><Key>a</Key><Value>b</Value></Tag>"),
         "bucket tagging attribute was accepted");
      Must_Reject_Malformed
        ("<evil:Tagging xmlns:evil=""urn:evil""><evil:TagSet>" &
         "<evil:Tag><evil:Key>a</evil:Key><evil:Value>b</evil:Value>" &
         "</evil:Tag></evil:TagSet></evil:Tagging>",
         "foreign-namespace bucket tagging document was accepted");
      Must_Reject_Malformed
        ("<Tagging><TagSet>" & Tag_XML ("a", "b") & "</TagSet>" &
         "<TagSet>" & Tag_XML ("c", "d") & "</TagSet></Tagging>",
         "duplicate bucket TagSet was accepted");
      Must_Reject_Malformed
        (Root ("<Unknown/>"), "unknown bucket tag entry was accepted");
      Must_Reject_Malformed
        (Root ("<Tag><Key>a</Key><Key>b</Key><Value>c</Value></Tag>"),
         "duplicate bucket tag key was accepted");
      Must_Reject_Malformed
        (Root ("<Tag><Key>a</Key></Tag>"),
         "bucket tag without Value was accepted");
      Must_Reject_Malformed
        (Root ("<Tag><Key><Nested/></Key><Value>x</Value></Tag>"),
         "nested bucket tag scalar was accepted");
      Must_Reject_Malformed
        ("<!DOCTYPE Tagging [<!ENTITY x 'value'>]>" &
         Root (Tag_XML ("key", "&x;")),
         "bucket tagging DTD was accepted");

      Must_Reject_Tag
        (Root (Tag_XML ("", "value")),
         "empty bucket tag key was accepted");
      Must_Reject_Tag
        (Root (Tag_XML ("AWS:reserved", "value")),
         "reserved bucket tag prefix was accepted");
      Must_Reject_Tag
        (Root (Tag_XML ("duplicate", "one") &
               Tag_XML ("duplicate", "two")),
         "duplicate bucket tag key was accepted");
      Must_Reject_Tag
        (Root (Tag_XML ("not!allowed", "value")),
         "forbidden bucket tag character was accepted");
      Must_Reject_Tag
        (Root (Tag_XML (String'(1 .. 129 => 'a'), "value")),
         "oversized bucket tag key was accepted");
      Must_Reject_Tag
        (Root (Tag_XML ("key", String'(1 .. 257 => 'a'))),
         "oversized bucket tag value was accepted");
      Must_Reject_Malformed
        (Root (Tag_XML (Character'Val (16#C0#) & Character'Val (16#80#),
                       "value")),
         "noncanonical UTF-8 bucket tag key was accepted");
      declare
         Document : US.Unbounded_String :=
           US.To_Unbounded_String ("<Tagging><TagSet>");
      begin
         for Index in 1 .. Tags.Maximum_Bucket_Tags + 1 loop
            US.Append
              (Document, Tag_XML ("key" & Index'Image, "value"));
         end loop;
         US.Append (Document, "</TagSet></Tagging>");
         Must_Reject_Malformed
           (US.To_String (Document),
            "bucket tagging document exceeded the 50-tag bound");
      end;
   end Check_Bucket_Tagging_Codec;

   procedure Check_Delete_Objects_Result_Codec
     (Unused : in out Fixture)
   is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Deletions renames Flyology.Object_Storage.S3.Deletions;
      package US renames Ada.Strings.Unbounded;

      procedure Must_Reject (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Deletions.Delete_Objects_Result :=
                 Deletions.Parse_Result (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Deletions.Malformed_Delete =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject;

      procedure Must_Reject_Request (Document, Message : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Deletions.Delete_Objects_Request :=
                 Deletions.Parse_Request (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Deletions.Malformed_Delete =>
               Raised := True;
         end;
         Assert (Raised, Message);
      end Must_Reject_Request;
   begin
      declare
         Document : constant String :=
           "<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<Object><ETag>*</ETag><Key>a&amp;b</Key>" &
           "<LastModifiedTime>Tue, 15 Oct 2024 15:04:05 GMT" &
           "</LastModifiedTime><Size>50</Size><VersionId>v1</VersionId>" &
           "</Object><Quiet>true</Quiet></Delete>";
         Parsed : constant Deletions.Delete_Objects_Request :=
           Deletions.Parse_Request (Document);
         Round_Trip : constant Deletions.Delete_Objects_Request :=
           Deletions.Parse_Request
             (Deletions.Serialize_Request (Parsed));
         Item : constant Deletions.Object_Identifier :=
           Parsed.Objects.First_Element;
      begin
         Assert
           (Parsed.Objects.Length = 1
            and then Parsed.Quiet
            and then US.To_String (Item.Key) = "a&b"
            and then US.To_String (Item.Version_ID) = "v1"
            and then Item.Has_ETag
            and then US.To_String (Item.ETag) = "*"
            and then Item.Has_Last_Modified_Time
            and then US.To_String (Item.Last_Modified_Time) =
              "Tue, 15 Oct 2024 15:04:05 GMT"
            and then Item.Has_Size
            and then Item.Size = 50
            and then Round_Trip.Objects.First_Element.Has_ETag
            and then Round_Trip.Objects.First_Element.Has_Size,
            "DeleteObjects request omitted modeled object conditions");
      end;

      declare
         Request : Deletions.Delete_Objects_Request;
      begin
         for Index in 1 .. Deletions.Maximum_Objects loop
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key                    => US.To_Unbounded_String
                    ("all-members-" & Index'Image),
                  Version_ID             => US.To_Unbounded_String ("v"),
                  Has_ETag               => True,
                  ETag                   => US.To_Unbounded_String ("*"),
                  Has_Last_Modified_Time => True,
                  Last_Modified_Time     => US.To_Unbounded_String
                    ("Wed, 21 Oct 2015 07:28:00 GMT"),
                  Has_Size               => True,
                  Size                   => 1));
         end loop;
         declare
            Document : constant String :=
              Deletions.Serialize_Request (Request);
            Parsed : constant Deletions.Delete_Objects_Request :=
              Deletions.Parse_Request
                (Document,
                 (Maximum_Document_Bytes =>
                    Deletions.Maximum_Document_Bytes,
                  Maximum_Depth          => 8,
                  Maximum_Elements       =>
                    Deletions.Maximum_Request_Elements,
                  Maximum_Text_Bytes     =>
                    Deletions.Maximum_Document_Bytes));
         begin
            Assert
              (Natural (Parsed.Objects.Length) = Deletions.Maximum_Objects,
               "DeleteObjects all-member maximum exceeded element budget");
         end;
      end;

      Must_Reject_Request
        ("<Delete><Object><Key>k</Key></Object></Delete>",
         "namespace-free DeleteObjects request was accepted");
      Must_Reject_Request
        ("<x:Delete xmlns:x=""urn:foreign""><x:Object><x:Key>k" &
         "</x:Key></x:Object></x:Delete>",
         "foreign DeleteObjects request namespace was accepted");
      Must_Reject_Request
        ("<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"" " &
         "extra=""x""><Object><Key>k</Key></Object></Delete>",
         "DeleteObjects request attribute was accepted");
      Must_Reject_Request
        ("<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<Object><Key>k</Key><Unknown>x</Unknown></Object></Delete>",
         "unknown DeleteObjects object field was accepted");
      Must_Reject_Request
        ("<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<Object><Key>k</Key><ETag/></Object></Delete>",
         "empty DeleteObjects ETag was accepted");
      Must_Reject_Request
        ("<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<Object><Key>k</Key><Size>-1</Size></Object></Delete>",
         "negative DeleteObjects size was accepted");
      declare
         Parsed : constant Deletions.Delete_Objects_Request :=
           Deletions.Parse_Request
             ("<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
              "<Object><Key>k</Key></Object><Quiet>false</Quiet></Delete>");
      begin
         Assert (not Parsed.Quiet, "false DeleteObjects Quiet was changed");
      end;

      declare
         Parsed : constant Deletions.Delete_Objects_Result :=
           Deletions.Parse_Result
             ("<DeleteResult xmlns=""http://s3.amazonaws.com/doc/" &
              "2006-03-01/"">" &
              "<Deleted><Key>a&amp;b</Key><VersionId>v1</VersionId>" &
              "<DeleteMarker>false</DeleteMarker>" &
              "<DeleteMarkerVersionId>dm1</DeleteMarkerVersionId>" &
              "<Future>ignored</Future></Deleted>" &
              "<Error><Key>bad&lt;key</Key><VersionId>v2</VersionId>" &
              "<Code>AccessDenied</Code><Message>denied &amp; logged" &
              "</Message></Error><Extension><Nested/></Extension>" &
              "</DeleteResult>");
         Round_Trip : constant Deletions.Delete_Objects_Result :=
           Deletions.Parse_Result (Deletions.Serialize_Result (Parsed));
      begin
         Assert
           (Parsed.Deleted.Length = 1
            and then Parsed.Errors.Length = 1
            and then US.To_String (Parsed.Deleted.First_Element.Key) =
              "a&b"
            and then Parsed.Deleted.First_Element.Delete_Marker.Is_Set
            and then not Parsed.Deleted.First_Element.Delete_Marker.Value
            and then US.To_String
              (Parsed.Deleted.First_Element.Delete_Marker_Version_ID) =
                "dm1"
            and then US.To_String (Parsed.Errors.First_Element.Key) =
              "bad<key"
            and then US.To_String (Parsed.Errors.First_Element.Code) =
              "AccessDenied"
            and then Round_Trip.Deleted.Length = 1
            and then Round_Trip.Errors.Length = 1,
            "DeleteObjects result fields and round trip");
      end;

      declare
         Empty : constant Deletions.Delete_Objects_Result :=
           Deletions.Parse_Result ("<DeleteResult/>");
      begin
         Assert
           (Empty.Deleted.Is_Empty and then Empty.Errors.Is_Empty,
            "quiet empty DeleteObjects result");
      end;

      Must_Reject
        ("<Wrong/>", "DeleteObjects result wrong root was accepted");
      Must_Reject
        ("<DeleteResult><Deleted><VersionId>v</VersionId>" &
         "</Deleted></DeleteResult>",
         "DeleteObjects deleted entry without key was accepted");
      Must_Reject
        ("<DeleteResult><Error><Key>k</Key><Message>m</Message>" &
         "</Error></DeleteResult>",
         "DeleteObjects error entry without code was accepted");
      Must_Reject
        ("<DeleteResult><Deleted><Key>one</Key><Key>two</Key>" &
         "</Deleted></DeleteResult>",
         "duplicate DeleteObjects result field was accepted");
      Must_Reject
        ("<DeleteResult><Deleted><Key>k</Key>" &
         "<DeleteMarker>maybe</DeleteMarker></Deleted></DeleteResult>",
         "invalid DeleteObjects marker boolean was accepted");
      Must_Reject
        ("<DeleteResult><Error><Key><Nested/></Key>" &
         "<Code>Bad</Code></Error></DeleteResult>",
         "nested DeleteObjects result scalar was accepted");
      Must_Reject
        ("<DeleteResult><Deleted><Key>" & String'(1 .. 1_025 => 'k') &
         "</Key></Deleted></DeleteResult>",
         "oversized DeleteObjects result key was accepted");
      declare
         Request : Deletions.Delete_Objects_Request;
         Raised  : Boolean := False;
      begin
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String
                 (String'(1 .. 1_025 => 'k')),
               Version_ID => US.Null_Unbounded_String,
               others     => <>));
         begin
            declare
               Ignored : constant String :=
                 Deletions.Serialize_Request (Request);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Deletions.Malformed_Delete =>
               Raised := True;
         end;
         Assert (Raised, "oversized DeleteObjects request key was accepted");
      end;
      declare
         Document : US.Unbounded_String :=
           US.To_Unbounded_String ("<DeleteResult>");
      begin
         for Index in 1 .. Deletions.Maximum_Objects + 1 loop
            US.Append
              (Document, "<Deleted><Key>k" & Index'Image &
               "</Key></Deleted>");
         end loop;
         US.Append (Document, "</DeleteResult>");
         Must_Reject
           (US.To_String (Document),
            "DeleteObjects result exceeded the 1,000-entry bound");
      end;
   end Check_Delete_Objects_Result_Codec;

   procedure Check_Low_Level_List_Request (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package US renames Ada.Strings.Unbounded;
      use type Low_Level.List_Outcome_Kind;
      LF : constant Character := Character'Val (10);
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
         "temporary-token");
   begin
      declare
         procedure Must_Reject_Credentials
           (Access_Key, Secret_Key, Token, Message : String)
         is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Credentials :=
                    Low_Level.Make_Credentials
                      (Access_Key, Secret_Key, Token);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Must_Reject_Credentials;
      begin
         Must_Reject_Credentials
           ("bad/access", "secret", "", "invalid access key was accepted");
         Must_Reject_Credentials
           ("ACCESS", "", "", "empty secret key was accepted");
         Must_Reject_Credentials
           ("ACCESS", "secret", String'(1 .. 8_193 => 'x'),
            "oversized session token was accepted");
         declare
            Boundary : constant Low_Level.Credentials :=
              Low_Level.Make_Credentials
                ("ACCESS", String'(1 .. 1_024 => 's'),
                 String'(1 .. 8_192 => 't'));
            pragma Unreferenced (Boundary);
         begin
            null;
         end;
      end;

      declare
         Parameters : Low_Level.List_Objects_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String ("photos/Jan &");
         Parameters.Delimiter := US.To_Unbounded_String ("/");
         Parameters.Marker := US.To_Unbounded_String ("a+b");
         Parameters.Max_Keys := 2;
         Parameters.URL_Encoding := True;
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Include_Restore_Status := True;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Objects
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
            Expected_Query : constant String :=
              "delimiter=%2F&encoding-type=url&marker=a%2Bb&max-keys=2&" &
              "prefix=photos%2FJan%20%26";
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket?" & Expected_Query
               and then Low_Level.Authority (Prepared) = "localhost:9000",
               "path-style ListObjects target and authority");
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "GET" & LF & "/example-bucket" & LF &
                  Expected_Query & LF) = 1
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;" &
                 "x-amz-optional-object-attributes;x-amz-request-payer;" &
                 "x-amz-security-token",
               "complete ListObjects request signing");
         end;
      end;

      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Objects
             (Flyology.HTTP.Parse_Origin
                ("https://example-bucket.s3.us-west-2.amazonaws.com"),
              Low_Level.Virtual_Hosted_Style, "example-bucket",
              (others => <>), Identity, "us-west-2", "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) = "/?max-keys=1000",
            "virtual-hosted ListObjects target");
      end;

      declare
         Parameters : Low_Level.List_Objects_Parameters;
      begin
         Parameters.Has_Prefix := True;
         Parameters.Has_Delimiter := True;
         Parameters.Has_Marker := True;
         Parameters.Has_Max_Keys := False;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Objects
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket?delimiter&marker&prefix",
               "ListObjects explicit-empty and omitted max-keys target: " &
               Low_Level.Target (Prepared));
         end;
      end;

      declare
         Raised : Boolean := False;
         Parameters : Low_Level.List_Objects_Parameters;
      begin
         Parameters.Request_Payer := US.To_Unbounded_String ("owner");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", Parameters,
                    Identity, "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "invalid ListObjects requester payer was accepted");
      end;

      declare
         Outcome : constant Low_Level.List_Objects_Outcome :=
           Low_Level.Decode_List_Objects_Response
             (200,
              "<ListBucketResult><Name>example-bucket</Name>" &
              "<Marker></Marker><MaxKeys>1000</MaxKeys>" &
              "<IsTruncated>false</IsTruncated></ListBucketResult>",
              Request_Charged => "requester");
      begin
         Assert
           (Outcome.Kind = Low_Level.Listed
            and then Outcome.Result.Listing.Max_Keys = 1_000
            and then US.To_String (Outcome.Result.Request_Charged) =
              "requester",
            "successful complete ListObjects response decoding");
      end;

      declare
         Outcome : constant Low_Level.List_Objects_Outcome :=
           Low_Level.Decode_List_Objects_Response
             (403, "<Error><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error>", Request_ID => "v1-request",
              Host_ID => "v1-host");
      begin
         Assert
           (Outcome.Kind = Low_Level.Rejected
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "v1-request"
            and then US.To_String (Outcome.Error.Host_ID) = "v1-host",
            "typed ListObjects S3 error decoding and header fallback");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.List_Objects_Outcome :=
                 Low_Level.Decode_List_Objects_Response
                   (200,
                    "<ListBucketResult><Name>example-bucket</Name>" &
                    "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
                    "</ListBucketResult>", Request_Charged => "invalid");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "invalid ListObjects response header was accepted");
      end;

      declare
         Parameters : Low_Level.List_Objects_V2_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String ("photos/Jan &");
         Parameters.Delimiter := US.To_Unbounded_String ("/");
         Parameters.Max_Keys := 2;
         Parameters.Fetch_Owner := True;
         Parameters.URL_Encoding := True;
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Include_Restore_Status := True;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Objects_V2
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
            Expected_Query : constant String :=
              "delimiter=%2F&encoding-type=url&" &
              "fetch-owner=true&list-type=2&max-keys=2&" &
              "prefix=photos%2FJan%20%26";
            Expected_Target : constant String :=
              "/example-bucket?" & Expected_Query;
         begin
            Assert
              (Low_Level.Target (Prepared) = Expected_Target
               and then Low_Level.Authority (Prepared) = "localhost:9000",
               "path-style ListObjectsV2 target and authority");
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "GET" & LF & "/example-bucket" & LF &
                  Expected_Query & LF) = 1
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;" &
                 "x-amz-optional-object-attributes;x-amz-request-payer;" &
                 "x-amz-security-token",
               "ListObjectsV2 request signing matches exact wire target");
         end;
      end;

      declare
         Parameters : Low_Level.List_Objects_V2_Parameters;
      begin
         Parameters.Has_Continuation_Token := True;
         Parameters.Has_Fetch_Owner := True;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Objects_V2
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket?continuation-token&fetch-owner=false&" &
                 "list-type=2&max-keys=1000",
               "present empty ListObjectsV2 inputs were not preserved");
         end;
      end;

      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Objects_V2
             (Flyology.HTTP.Parse_Origin
                ("https://example-bucket.s3.us-west-2.amazonaws.com"),
              Low_Level.Virtual_Hosted_Style, "example-bucket",
              (others => <>), Identity, "us-west-2", "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/?list-type=2&max-keys=1000",
            "virtual-hosted ListObjectsV2 target");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects_V2
                   (Flyology.HTTP.Parse_Origin ("https://s3.amazonaws.com"),
                    Low_Level.Virtual_Hosted_Style, "example-bucket",
                    (others => <>), Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "mismatched virtual-hosted S3 origin was accepted");
      end;

      declare
         Raised     : Boolean := False;
         Parameters : Low_Level.List_Objects_V2_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String
           (String'(1 .. 8_193 => 'x'));
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects_V2
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", Parameters,
                    Identity, "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "oversized ListObjectsV2 target was accepted");
      end;

      declare
         Raised : Boolean := False;
         Parameters : Low_Level.List_Objects_V2_Parameters;
      begin
         Parameters.Request_Payer := US.To_Unbounded_String ("owner");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects_V2
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", Parameters,
                    Identity, "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised, "invalid ListObjectsV2 requester payer was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects_V2
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "Invalid_Bucket", (others => <>),
                    Identity, "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "invalid ListObjectsV2 bucket was accepted");
      end;

      declare
         Outcome : constant Low_Level.List_Objects_V2_Outcome :=
           Low_Level.Decode_List_Objects_V2_Response
             (200,
              "<ListBucketResult><Name>example-bucket</Name>" &
              "<KeyCount>0</KeyCount><MaxKeys>1000</MaxKeys>" &
              "<IsTruncated>false</IsTruncated></ListBucketResult>",
              Request_Charged => "requester");
      begin
         Assert
           (Outcome.Kind = Low_Level.Listed
            and then Outcome.Listing.Key_Count = 0
            and then US.To_String (Outcome.Request_Charged) = "requester",
            "successful ListObjectsV2 response decoding");
      end;

      declare
         Outcome : constant Low_Level.List_Objects_V2_Outcome :=
           Low_Level.Decode_List_Objects_V2_Response
             (403, "<Error><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error>", "request-header",
              "host-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Rejected
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header"
            and then US.To_String (Outcome.Error.Host_ID) = "host-header",
            "typed ListObjectsV2 S3 error decoding and header fallback");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.List_Objects_V2_Outcome :=
                 Low_Level.Decode_List_Objects_V2_Response
                   (200,
                    "<ListBucketResult><Name>example-bucket</Name>" &
                    "<KeyCount>0</KeyCount><MaxKeys>1</MaxKeys>" &
                    "<IsTruncated>false</IsTruncated>" &
                    "</ListBucketResult>",
                    Request_Charged => "invalid");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert
           (Raised, "invalid ListObjectsV2 response header was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.List_Objects_V2_Outcome :=
                 Low_Level.Decode_List_Objects_V2_Response
                   (200, "<ListBucketResult/>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "malformed successful S3 response was accepted");
      end;
   end Check_Low_Level_List_Request;

   procedure Check_Low_Level_Multipart_Request (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package Multipart renames Flyology.Object_Storage.S3.Multipart;
      package SigV4 renames Flyology.Object_Storage.S3.SigV4;
      package US renames Ada.Strings.Unbounded;
      use type Low_Level.Create_Multipart_Outcome_Kind;
      use type Low_Level.Complete_Multipart_Outcome_Kind;
      use type Low_Level.Abort_Multipart_Outcome_Kind;
      use type Low_Level.List_Parts_Outcome_Kind;
      use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
      use type Low_Level.Upload_Part_Outcome_Kind;
      use type Low_Level.Upload_Part_Copy_Outcome_Kind;
      use type Low_Level.Put_Object_Outcome_Kind;
      LF : constant Character := Character'Val (10);
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
      Completion : Multipart.Complete_Multipart_Upload_Request;
   begin
      Completion.Parts.Append
        (Multipart.Completed_Part'
           (Number => 1,
            Entity_Tag => US.To_Unbounded_String ("""part-etag"""),
            others => <>));
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", "photos/a b+%",
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/example-bucket/photos/a%20b%2B%25?uploads",
            "CreateMultipartUpload exact wire target");
         Assert
           (Ada.Strings.Fixed.Index
              (Low_Level.Canonical_Request (Prepared),
               "POST" & LF &
               "/example-bucket/photos/a%20b%2B%25" & LF &
               "uploads=" & LF) = 1,
            "CreateMultipartUpload canonical query retains empty value");
      end;

      declare
         Serialized : constant String :=
           Multipart.Serialize_Complete_Request (Completion);
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Complete_Multipart_Upload
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", "photos/a b+%",
              "upload+/=", Completion, Identity, "us-east-1",
              "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/example-bucket/photos/a%20b%2B%25?" &
              "uploadId=upload%2B%2F%3D",
            "CompleteMultipartUpload exact wire target");
         Assert
           (Ada.Strings.Fixed.Index
              (Low_Level.Canonical_Request (Prepared),
               "POST" & LF &
               "/example-bucket/photos/a%20b%2B%25" & LF &
               "uploadId=upload%2B%2F%3D" & LF) = 1
            and then Ada.Strings.Fixed.Index
              (Low_Level.Canonical_Request (Prepared),
               SigV4.SHA256_Hex (Serialized)) > 0,
            "CompleteMultipartUpload signs exact body and query");
      end;

      declare
         Parameters : Low_Level.Complete_Multipart_Parameters;
      begin
         Parameters.Checksum_CRC32 := US.To_Unbounded_String ("AAAAAA==");
         Parameters.Checksum_CRC32C := US.To_Unbounded_String ("AAAAAA==");
         Parameters.Checksum_CRC64NVME :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Parameters.Checksum_SHA1 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.Checksum_SHA256 := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.Checksum_SHA512 := US.To_Unbounded_String
           (String'(1 .. 86 => 'A') & "==");
         Parameters.Checksum_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Checksum_XXHASH64 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Parameters.Checksum_XXHASH3 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Parameters.Checksum_XXHASH128 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Checksum_Type := US.To_Unbounded_String ("COMPOSITE");
         Parameters.Mpu_Object_Size := (Is_Set => True, Value => 5);
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.If_Match := US.To_Unbounded_String ("""old""");
         Parameters.If_None_Match := US.To_Unbounded_String ("""other""");
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Complete_Multipart_Upload
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "key", "upload",
                 Completion, Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Signed : constant String :=
              ";" & Low_Level.Signed_Headers (Prepared) & ";";

            function Has (Name : String) return Boolean is
              (Ada.Strings.Fixed.Index (Signed, ";" & Name & ";") > 0);
         begin
            Assert
              (Has ("x-amz-checksum-crc32")
               and then Has ("x-amz-checksum-crc32c")
               and then Has ("x-amz-checksum-crc64nvme")
               and then Has ("x-amz-checksum-sha1")
               and then Has ("x-amz-checksum-sha256")
               and then Has ("x-amz-checksum-sha512")
               and then Has ("x-amz-checksum-md5")
               and then Has ("x-amz-checksum-xxhash64")
               and then Has ("x-amz-checksum-xxhash3")
               and then Has ("x-amz-checksum-xxhash128")
               and then Has ("x-amz-checksum-type")
               and then Has ("x-amz-mp-object-size")
               and then Has ("x-amz-request-payer")
               and then Has ("x-amz-expected-bucket-owner")
               and then Has ("if-match")
               and then Has ("if-none-match")
               and then Has
                 ("x-amz-server-side-encryption-customer-algorithm")
               and then Has
                 ("x-amz-server-side-encryption-customer-key")
               and then Has
                 ("x-amz-server-side-encryption-customer-key-md5"),
               "CompleteMultipartUpload signs every modeled request header");
         end;
      end;

      declare
         Parameters : Low_Level.Complete_Multipart_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Checksum_CRC32 := US.To_Unbounded_String ("invalid");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Complete_Multipart_Upload
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key", "upload",
                    Completion, Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised, "invalid CompleteMultipartUpload checksum was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Complete_Multipart_Upload
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key", "",
                    Completion, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "empty multipart upload identifier was accepted");
      end;

      declare
         Outcome : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Decode_Create_Multipart_Response
             (200, "<InitiateMultipartUploadResult>" &
              "<Bucket>example-bucket</Bucket><Key>key</Key>" &
              "<UploadId>upload-1</UploadId>" &
              "</InitiateMultipartUploadResult>");
      begin
         Assert
           (Outcome.Kind = Low_Level.Created
            and then US.To_String (Outcome.Result.Upload_ID) = "upload-1",
            "typed CreateMultipartUpload success response");
      end;

      declare
         Outcome : constant Low_Level.Complete_Multipart_Outcome :=
           Low_Level.Decode_Complete_Multipart_Response
             (200, "<CompleteMultipartUploadResult>" &
              "<Bucket>example-bucket</Bucket><Key>key</Key>" &
              "<ETag>&quot;whole&quot;</ETag>" &
              "</CompleteMultipartUploadResult>");
      begin
         Assert
           (Outcome.Kind = Low_Level.Completed
            and then US.To_String (Outcome.Result.Entity_Tag) =
              """whole""",
            "typed CompleteMultipartUpload success response");
      end;

      declare
         Headers : constant Low_Level.Complete_Multipart_Response_Headers :=
           (Expiration => US.To_Unbounded_String ("expiry=soon"),
            Server_Side_Encryption => US.To_Unbounded_String ("aws:kms"),
            Version_ID => US.To_Unbounded_String ("version-1"),
            SSE_KMS_Key_ID => US.To_Unbounded_String ("kms-key"),
            Bucket_Key_Enabled => (Is_Set => True, Value => True),
            Request_Charged => US.To_Unbounded_String ("requester"));
         Outcome : constant Low_Level.Complete_Multipart_Outcome :=
           Low_Level.Decode_Complete_Multipart_Response
             (200, "<CompleteMultipartUploadResult>" &
              "<Bucket>example-bucket</Bucket><Key>key</Key>" &
              "<ETag>&quot;whole&quot;</ETag>" &
              "<ChecksumCRC32>AAAAAA==</ChecksumCRC32>" &
              "<ChecksumType>COMPOSITE</ChecksumType>" &
              "</CompleteMultipartUploadResult>", Headers);
      begin
         Assert
           (Outcome.Kind = Low_Level.Completed
            and then US.To_String (Outcome.Result.Checksum_CRC32) =
              "AAAAAA=="
            and then US.To_String
              (Outcome.Result.Server_Side_Encryption) = "aws:kms"
            and then US.To_String (Outcome.Result.Version_ID) = "version-1"
            and then Outcome.Result.Bucket_Key_Enabled.Is_Set
            and then Outcome.Result.Bucket_Key_Enabled.Value
            and then US.To_String (Outcome.Result.Request_Charged) =
              "requester",
            "typed CompleteMultipartUpload complete output shape");
      end;

      declare
         Headers : Low_Level.Complete_Multipart_Response_Headers;
         Raised : Boolean := False;
      begin
         Headers.Server_Side_Encryption :=
           US.To_Unbounded_String ("unknown");
         begin
            declare
               Ignored : constant Low_Level.Complete_Multipart_Outcome :=
                 Low_Level.Decode_Complete_Multipart_Response
                   (200, "<CompleteMultipartUploadResult>" &
                    "<ETag>&quot;whole&quot;</ETag>" &
                    "</CompleteMultipartUploadResult>", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert
           (Raised,
            "invalid CompleteMultipartUpload response enum was accepted");
      end;

      declare
         Outcome : constant Low_Level.Complete_Multipart_Outcome :=
           Low_Level.Decode_Complete_Multipart_Response
             (200, "<Error><Code>InternalError</Code>" &
              "<Message>late failure</Message></Error>",
              "request-header", "host-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Complete_Rejected
            and then Outcome.Status = 200
            and then US.To_String (Outcome.Error.Code) = "InternalError"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header",
            "embedded HTTP-200 multipart error response");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Complete_Multipart_Outcome :=
                 Low_Level.Decode_Complete_Multipart_Response
                   (200, "<Error><Code>InternalError</Code></Error>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "malformed embedded multipart error was accepted");
      end;

      declare
         Parameters : Low_Level.Abort_Multipart_Parameters;
      begin
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.If_Match_Initiated_Time :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Abort_Multipart_Upload
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 "upload+/=", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Headers : constant Low_Level.Abort_Multipart_Result :=
              (Request_Charged => US.To_Unbounded_String ("requester"));
            Outcome : constant Low_Level.Abort_Multipart_Outcome :=
              Low_Level.Decode_Abort_Multipart_Response (204, "", Headers);
            Canonical : constant String :=
              Low_Level.Canonical_Request (Prepared);
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?" &
                 "uploadId=upload%2B%2F%3D"
               and then Outcome.Kind = Low_Level.Aborted
               and then US.To_String (Outcome.Result.Request_Charged) =
                 "requester"
               and then Ada.Strings.Fixed.Index
                 (Canonical,
                  "x-amz-expected-bucket-owner:123456789012" & LF) > 0
               and then Ada.Strings.Fixed.Index
                 (Canonical,
                  "x-amz-if-match-initiated-time:" &
                  "Fri, 24 May 2013 00:00:00 GMT" & LF) > 0
               and then Ada.Strings.Fixed.Index
                 (Canonical, "x-amz-request-payer:requester" & LF) > 0,
               "AbortMultipartUpload complete modeled request/result");
         end;
      end;

      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Abort_Multipart_Upload
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", "photos/a b+%",
              "upload+/=", Identity, "us-east-1", "20130524T000000Z");
         Outcome : constant Low_Level.Abort_Multipart_Outcome :=
           Low_Level.Decode_Abort_Multipart_Response (204, "");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/example-bucket/photos/a%20b%2B%25?" &
              "uploadId=upload%2B%2F%3D"
            and then Outcome.Kind = Low_Level.Aborted,
            "AbortMultipartUpload exact target and empty success");
      end;

      declare
         Outcome : constant Low_Level.Abort_Multipart_Outcome :=
           Low_Level.Decode_Abort_Multipart_Response
             (404, "<Error><Code>NoSuchUpload</Code>" &
              "<Message>gone</Message></Error>", "request-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Abort_Rejected
            and then US.To_String (Outcome.Error.Code) = "NoSuchUpload"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header",
            "typed AbortMultipartUpload error response");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Abort_Multipart_Outcome :=
                 Low_Level.Decode_Abort_Multipart_Response
                   (204, "unexpected");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "AbortMultipartUpload accepted a 204 body");
      end;

      for Invalid_Kind in 1 .. 3 loop
         declare
            Parameters : Low_Level.Abort_Multipart_Parameters;
            Raised : Boolean := False;
         begin
            if Invalid_Kind = 1 then
               Parameters.Request_Payer := US.To_Unbounded_String ("owner");
            elsif Invalid_Kind = 2 then
               Parameters.If_Match_Initiated_Time :=
                 US.To_Unbounded_String ("not-a-date");
            else
               null;
            end if;
            begin
               if Invalid_Kind < 3 then
                  declare
                     Ignored : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Abort_Multipart_Upload
                         (Flyology.HTTP.Parse_Origin
                            ("http://localhost:9000"),
                          Low_Level.Path_Style, "example-bucket", "key",
                          "upload", Parameters, Identity, "us-east-1",
                          "20130524T000000Z");
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               else
                  declare
                     Headers : constant Low_Level.Abort_Multipart_Result :=
                       (Request_Charged => US.To_Unbounded_String ("owner"));
                     Ignored : constant Low_Level.Abort_Multipart_Outcome :=
                       Low_Level.Decode_Abort_Multipart_Response
                         (204, "", Headers);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               end if;
            exception
               when Low_Level.Invalid_Request |
                    Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            Assert
              (Raised,
               "AbortMultipartUpload accepted invalid modeled member" &
               Integer'Image (Invalid_Kind));
         end;
      end loop;

      declare
         Parameters : Low_Level.List_Parts_Parameters;
      begin
         Parameters.Max_Parts := 7;
         Parameters.Part_Number_Marker := 3;
         Parameters.Upload_ID := US.To_Unbounded_String ("upload+/=");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Parts
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
            Signed : constant String :=
              ";" & Low_Level.Signed_Headers (Prepared) & ";";

            function Has (Name : String) return Boolean is
              (Ada.Strings.Fixed.Index (Signed, ";" & Name & ";") > 0);
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?max-parts=7&" &
                 "part-number-marker=3&uploadId=upload%2B%2F%3D",
               "ListParts exact modeled wire target");
            Assert
              (Has ("x-amz-expected-bucket-owner")
               and then Has ("x-amz-request-payer")
               and then Has
                 ("x-amz-server-side-encryption-customer-algorithm")
               and then Has ("x-amz-server-side-encryption-customer-key")
               and then Has
                 ("x-amz-server-side-encryption-customer-key-md5"),
               "ListParts modeled headers are signed");
         end;
      end;

      declare
         Outcome : constant Low_Level.List_Parts_Outcome :=
           Low_Level.Decode_List_Parts_Response
             (200,
              "<ListPartsResult><Bucket>example-bucket</Bucket>" &
              "<Key>key</Key><UploadId>upload</UploadId>" &
              "<PartNumberMarker>0</PartNumberMarker>" &
              "<MaxParts>1</MaxParts><IsTruncated>false</IsTruncated>" &
              "<Part><PartNumber>1</PartNumber>" &
              "<LastModified>2026-08-21T00:00:00Z</LastModified>" &
              "<ETag>&quot;part&quot;</ETag><Size>42</Size></Part>" &
              "</ListPartsResult>",
              Abort_Date => "Fri, 21 Aug 2026 00:00:00 GMT",
              Abort_Rule_ID => "cleanup",
              Request_Charged => "requester");
      begin
         Assert
           (Outcome.Kind = Low_Level.Parts_Listed
            and then Outcome.Result.Listing.Parts.Length = 1
            and then Outcome.Result.Listing.Parts.First_Element.Size = 42
            and then US.To_String (Outcome.Result.Abort_Rule_ID) = "cleanup"
            and then US.To_String (Outcome.Result.Request_Charged) =
              "requester",
            "typed ListParts complete success response");
      end;

      declare
         Outcome : constant Low_Level.List_Parts_Outcome :=
           Low_Level.Decode_List_Parts_Response
             (404, "<Error><Code>NoSuchUpload</Code>" &
              "<Message>gone</Message></Error>",
              Request_ID => "list-parts-request",
              Host_ID => "list-parts-host");
      begin
         Assert
           (Outcome.Kind = Low_Level.List_Parts_Rejected
            and then US.To_String (Outcome.Error.Code) = "NoSuchUpload"
            and then US.To_String (Outcome.Error.Request_ID) =
              "list-parts-request"
            and then US.To_String (Outcome.Error.Host_ID) =
              "list-parts-host",
            "typed ListParts S3 error response");
      end;

      declare
         Parameters : Low_Level.List_Parts_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Upload_ID := US.To_Unbounded_String ("upload");
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Parts
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "ListParts allowed an SSE-C key over plaintext HTTP");
      end;

      declare
         Parameters : Low_Level.List_Parts_Parameters;

         procedure Require_Rejected (Message : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_List_Parts
                      (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                       Low_Level.Path_Style, "example-bucket", "key",
                       Parameters, Identity, "us-east-1",
                       "20130524T000000Z");
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Require_Rejected;
      begin
         Require_Rejected ("ListParts accepted an empty upload identifier");

         Parameters.Upload_ID := US.To_Unbounded_String ("upload");
         Parameters.Request_Payer := US.To_Unbounded_String ("owner");
         Require_Rejected ("ListParts accepted an invalid requester payer");

         Parameters.Request_Payer := US.Null_Unbounded_String;
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Require_Rejected ("ListParts accepted an incomplete SSE-C group");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.List_Parts_Outcome :=
                 Low_Level.Decode_List_Parts_Response
                   (200,
                    "<ListPartsResult><Bucket>example-bucket</Bucket>" &
                    "<Key>key</Key><UploadId>upload</UploadId>" &
                    "<PartNumberMarker>0</PartNumberMarker>" &
                    "<MaxParts>0</MaxParts>" &
                    "<IsTruncated>false</IsTruncated>" &
                    "</ListPartsResult>",
                    Request_Charged => "owner");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "ListParts invalid request-charged was accepted");
      end;

      declare
         Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      begin
         Parameters.Delimiter := US.To_Unbounded_String ("/");
         Parameters.URL_Encoding := True;
         Parameters.Key_Marker := US.To_Unbounded_String ("a+b");
         Parameters.Max_Uploads := 7;
         Parameters.Prefix := US.To_Unbounded_String ("photos/Jan &");
         Parameters.Upload_ID_Marker :=
           US.To_Unbounded_String ("upload+/=");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Multipart_Uploads
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
            Expected_Query : constant String :=
              "delimiter=%2F&encoding-type=url&key-marker=a%2Bb&" &
              "max-uploads=7&prefix=photos%2FJan%20%26&" &
              "upload-id-marker=upload%2B%2F%3D&uploads";
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket?" & Expected_Query,
               "ListMultipartUploads exact modeled wire target");
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "GET" & LF & "/example-bucket" & LF &
                  Expected_Query & "=" & LF) = 1
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;x-amz-request-payer",
               "complete ListMultipartUploads request signing");
         end;
      end;

      declare
         Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      begin
         Parameters.Upload_ID_Marker := US.To_Unbounded_String ("ignored");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Multipart_Uploads
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket?max-uploads=1000&" &
                 "upload-id-marker=ignored&uploads",
               "ignored upload-id marker was not preserved on the wire");
         end;
      end;

      declare
         Outcome : constant Low_Level.List_Multipart_Uploads_Outcome :=
           Low_Level.Decode_List_Multipart_Uploads_Response
             (200,
              "<ListMultipartUploadsResult><Bucket>example-bucket" &
              "</Bucket><MaxUploads>1</MaxUploads><IsTruncated>false" &
              "</IsTruncated><Upload><UploadId>upload</UploadId>" &
              "<Key>key</Key><Initiated>2026-08-21T00:00:00Z" &
              "</Initiated><StorageClass>STANDARD</StorageClass>" &
              "</Upload></ListMultipartUploadsResult>",
              Request_Charged => "requester");
      begin
         Assert
           (Outcome.Kind = Low_Level.Multipart_Uploads_Listed
            and then Outcome.Result.Listing.Uploads.Length = 1
            and then US.To_String
              (Outcome.Result.Listing.Uploads.First_Element.Upload_ID) =
                "upload"
            and then US.To_String (Outcome.Result.Request_Charged) =
              "requester",
            "typed ListMultipartUploads complete success response");
      end;

      declare
         Outcome : constant Low_Level.List_Multipart_Uploads_Outcome :=
           Low_Level.Decode_List_Multipart_Uploads_Response
             (403, "<Error><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error>",
              Request_ID => "list-uploads-request",
              Host_ID => "list-uploads-host");
      begin
         Assert
           (Outcome.Kind = Low_Level.List_Multipart_Uploads_Rejected
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) =
              "list-uploads-request"
            and then US.To_String (Outcome.Error.Host_ID) =
              "list-uploads-host",
            "typed ListMultipartUploads S3 error response");
      end;

      declare
         Parameters : Low_Level.List_Multipart_Uploads_Parameters;

         procedure Require_Rejected (Message : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_List_Multipart_Uploads
                      (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                       Low_Level.Path_Style, "example-bucket", Parameters,
                       Identity, "us-east-1", "20130524T000000Z");
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Require_Rejected;
      begin
         Parameters.Max_Uploads := 0;
         Require_Rejected
           ("ListMultipartUploads accepted zero max-uploads");
         Parameters.Max_Uploads := 1;
         Parameters.Request_Payer := US.To_Unbounded_String ("owner");
         Require_Rejected
           ("ListMultipartUploads accepted invalid requester payer");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.List_Multipart_Uploads_Outcome :=
                 Low_Level.Decode_List_Multipart_Uploads_Response
                   (200,
                    "<ListMultipartUploadsResult><Bucket>example-bucket" &
                    "</Bucket><MaxUploads>1</MaxUploads>" &
                    "<IsTruncated>false</IsTruncated>" &
                    "</ListMultipartUploadsResult>",
                    Request_Charged => "owner");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert
           (Raised,
            "ListMultipartUploads invalid request-charged was accepted");
      end;

      declare
         Parameters : Low_Level.Put_Object_Parameters;
      begin
         Parameters.Cache_Control := US.To_Unbounded_String ("no-cache");
         Parameters.Content_Disposition :=
           US.To_Unbounded_String ("attachment");
         Parameters.Content_Encoding := US.To_Unbounded_String ("gzip");
         Parameters.Content_Language := US.To_Unbounded_String ("en-CA");
         Parameters.Content_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Content_Type :=
           US.To_Unbounded_String ("application/test");
         Parameters.Checksum_Algorithm := US.To_Unbounded_String ("SHA256");
         Parameters.Checksum_CRC32 := US.To_Unbounded_String ("AAAAAA==");
         Parameters.Checksum_CRC32C := US.To_Unbounded_String ("AAAAAA==");
         Parameters.Checksum_CRC64NVME :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Parameters.Checksum_SHA1 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.Checksum_SHA256 := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.Checksum_SHA512 := US.To_Unbounded_String
           (String'(1 .. 86 => 'A') & "==");
         Parameters.Checksum_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Checksum_XXHASH64 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Parameters.Checksum_XXHASH3 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Parameters.Checksum_XXHASH128 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Expires :=
           US.To_Unbounded_String ("Fri, 24 May 2013 01:00:00 GMT");
         Parameters.If_Match := US.To_Unbounded_String ("""etag""");
         Parameters.If_None_Match := US.To_Unbounded_String ("*");
         Parameters.Grant_Full_Control := US.To_Unbounded_String ("id=owner");
         Parameters.Grant_Read := US.To_Unbounded_String ("id=reader");
         Parameters.Grant_Read_ACP := US.To_Unbounded_String ("id=reader");
         Parameters.Grant_Write_ACP := US.To_Unbounded_String ("id=writer");
         Parameters.Write_Offset_Bytes := (Is_Set => True, Value => 7);
         Parameters.Metadata.Append
           (Low_Level.Metadata_Entry'
              (Name  => US.To_Unbounded_String ("project"),
               Value => US.To_Unbounded_String ("flyology")));
         Parameters.Metadata.Append
           (Low_Level.Metadata_Entry'
              (Name  => US.To_Unbounded_String ("stage"),
               Value => US.To_Unbounded_String ("typed")));
         Parameters.Server_Side_Encryption :=
           US.To_Unbounded_String ("aws:kms");
         Parameters.Storage_Class := US.To_Unbounded_String ("STANDARD");
         Parameters.Website_Redirect_Location :=
           US.To_Unbounded_String ("/next");
         Parameters.SSE_KMS_Key_ID := US.To_Unbounded_String ("kms-key");
         Parameters.SSE_KMS_Encryption_Context :=
           US.To_Unbounded_String ("e30=");
         Parameters.Bucket_Key_Enabled := (Is_Set => True, Value => True);
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Tagging := US.To_Unbounded_String ("a=b");
         Parameters.Object_Lock_Mode :=
           US.To_Unbounded_String ("GOVERNANCE");
         Parameters.Object_Lock_Retain_Until_Date :=
           US.To_Unbounded_String ("2027-08-21T00:00:00Z");
         Parameters.Object_Lock_Legal_Hold_Status :=
           US.To_Unbounded_String ("ON");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         declare
            Digest : constant String := SigV4.SHA256_Hex ("streamed payload");
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Digest, Identity, "us-east-1",
                 "20130524T000000Z");
            Signed : constant String :=
              ";" & Low_Level.Signed_Headers (Prepared) & ";";

            function Has (Name : String) return Boolean is
              (Ada.Strings.Fixed.Index (Signed, ";" & Name & ";") > 0);
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25"
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared), Digest) > 0,
               "PutObject exact target and streaming payload hash");
            Assert
              (Has ("content-md5") and then Has ("content-type")
               and then Has ("if-match") and then Has ("if-none-match")
               and then Has ("x-amz-checksum-sha256")
               and then Has ("x-amz-grant-full-control")
               and then Has ("x-amz-meta-project")
               and then Has ("x-amz-meta-stage")
               and then Has ("x-amz-object-lock-mode")
               and then Has ("x-amz-server-side-encryption")
               and then Has ("x-amz-server-side-encryption-aws-kms-key-id")
               and then Has ("x-amz-storage-class")
               and then Has ("x-amz-tagging")
               and then Has ("x-amz-write-offset-bytes"),
               "PutObject modeled header families are signed");
         end;
      end;

      declare
         Parameters : Low_Level.Put_Object_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.ACL := US.To_Unbounded_String ("private");
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "key", Parameters,
                 SigV4.SHA256_Hex ("payload"), Identity, "us-east-1",
                 "20130524T000000Z");
         begin
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared),
                  "x-amz-server-side-encryption-customer-key") > 0
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared), "x-amz-acl") > 0,
               "PutObject SSE-C group is signed over HTTPS");
         end;
         Parameters.Checksum_Algorithm := US.To_Unbounded_String ("CRC32");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Object
                   (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, SigV4.SHA256_Hex ("payload"), Identity,
                    "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised,
            "PutObject accepted a checksum algorithm without its value");
      end;

      declare
         Parameters : Low_Level.Put_Object_Parameters;

         procedure Require_Rejected (Message : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Put_Object
                      (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                       Low_Level.Path_Style, "example-bucket", "key",
                       Parameters, SigV4.SHA256_Hex ("payload"), Identity,
                       "us-east-1", "20130524T000000Z");
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Require_Rejected;
      begin
         Parameters.ACL := US.To_Unbounded_String ("private");
         Parameters.Grant_Read := US.To_Unbounded_String ("id=reader");
         Require_Rejected ("PutObject combined canned and explicit ACLs");

         Parameters := (others => <>);
         Parameters.SSE_KMS_Key_ID := US.To_Unbounded_String ("kms-key");
         Require_Rejected ("PutObject accepted a KMS key without SSE-KMS");

         Parameters := (others => <>);
         Parameters.Object_Lock_Mode :=
           US.To_Unbounded_String ("GOVERNANCE");
         Require_Rejected
           ("PutObject accepted Object Lock without an integrity header");
      end;

      declare
         Headers : Low_Level.Put_Object_Result;
      begin
         Headers.Expiration := US.To_Unbounded_String ("expiry=soon");
         Headers.Entity_Tag := US.To_Unbounded_String ("""put-etag""");
         Headers.Checksum_CRC32 := US.To_Unbounded_String ("AAAAAA==");
         Headers.Checksum_CRC32C := US.To_Unbounded_String ("AAAAAA==");
         Headers.Checksum_CRC64NVME :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Headers.Checksum_SHA1 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Headers.Checksum_SHA256 := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Headers.Checksum_SHA512 := US.To_Unbounded_String
           (String'(1 .. 86 => 'A') & "==");
         Headers.Checksum_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.Checksum_XXHASH64 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Headers.Checksum_XXHASH3 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Headers.Checksum_XXHASH128 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.Checksum_Type := US.To_Unbounded_String ("FULL_OBJECT");
         Headers.Server_Side_Encryption :=
           US.To_Unbounded_String ("aws:backup");
         Headers.Version_ID := US.To_Unbounded_String ("version");
         Headers.SSE_Customer_Algorithm := US.To_Unbounded_String ("AES256");
         Headers.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.SSE_KMS_Key_ID := US.To_Unbounded_String ("kms-key");
         Headers.SSE_KMS_Encryption_Context :=
           US.To_Unbounded_String ("context");
         Headers.Bucket_Key_Enabled := (Is_Set => True, Value => True);
         Headers.Size := (Is_Set => True, Value => 42);
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         declare
            Outcome : constant Low_Level.Put_Object_Outcome :=
              Low_Level.Decode_Put_Object_Response (200, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Object_Put
               and then Outcome.Result.Size.Is_Set
               and then Outcome.Result.Size.Value = 42
               and then US.To_String (Outcome.Result.Entity_Tag) =
                 """put-etag"""
               and then US.To_String
                 (Outcome.Result.Server_Side_Encryption) = "aws:backup",
               "typed PutObject complete response headers");
         end;
      end;

      declare
         Headers : Low_Level.Put_Object_Result;
         Raised : Boolean := False;
      begin
         Headers.Entity_Tag := US.To_Unbounded_String ("""etag""");
         Headers.Checksum_SHA256 := US.To_Unbounded_String ("not-base64");
         begin
            declare
               Ignored : constant Low_Level.Put_Object_Outcome :=
                 Low_Level.Decode_Put_Object_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "PutObject accepted an invalid response checksum");
      end;

      declare
         Headers : Low_Level.Put_Object_Result;
         Outcome : constant Low_Level.Put_Object_Outcome :=
           Low_Level.Decode_Put_Object_Response
             (403, "<Error><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error>", Headers,
              "put-request", "put-host");
      begin
         Assert
           (Outcome.Kind = Low_Level.Put_Object_Rejected
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "put-request",
            "typed PutObject error response");
      end;

      declare
         Parameters : Low_Level.Upload_Part_Parameters;
      begin
         Parameters.Part_Number := 7;
         Parameters.Upload_ID := US.To_Unbounded_String ("upload+/=");
         Parameters.Payload_SHA256 := US.To_Unbounded_String
           (SigV4.SHA256_Hex ("streamed payload"));
         Parameters.Checksum_Algorithm := US.To_Unbounded_String ("CRC32");
         Parameters.Checksum_CRC32 := US.To_Unbounded_String ("AAAAAA==");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Upload_Part
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?partNumber=7&" &
                 "uploadId=upload%2B%2F%3D"
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  SigV4.SHA256_Hex ("streamed payload")) > 0,
               "UploadPart exact target and streaming payload hash");
            Assert
              (Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-checksum-crc32;x-amz-content-sha256;" &
                 "x-amz-date;x-amz-sdk-checksum-algorithm",
               "UploadPart modeled checksum headers are signed");
         end;
      end;

      declare
         Parameters : Low_Level.Upload_Part_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Upload_ID := US.To_Unbounded_String ("upload");
         Parameters.Payload_SHA256 :=
           US.To_Unbounded_String (SigV4.Unsigned_Payload);
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "UNSIGNED-PAYLOAD was accepted over cleartext HTTP");
      end;

      declare
         Parameters : Low_Level.Upload_Part_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Upload_ID := US.To_Unbounded_String ("upload");
         Parameters.Payload_SHA256 :=
           US.To_Unbounded_String (SigV4.SHA256_Hex ("payload"));
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key :=
           US.To_Unbounded_String
             ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised, "UploadPart allowed an SSE-C key over plaintext HTTP");
         Raised := False;
         Parameters.SSE_Customer_Key := US.To_Unbounded_String ("AAAA");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "UploadPart accepted a non-256-bit SSE-C key");
      end;

      declare
         Headers : Low_Level.Upload_Part_Result;
      begin
         Headers.Entity_Tag := US.To_Unbounded_String ("""part""");
         Headers.Checksum_CRC32 := US.To_Unbounded_String ("AAAAAA==");
         Headers.Bucket_Key_Enabled := US.To_Unbounded_String ("true");
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         declare
            Outcome : constant Low_Level.Upload_Part_Outcome :=
              Low_Level.Decode_Upload_Part_Response (200, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Part_Uploaded
               and then US.To_String (Outcome.Result.Entity_Tag) =
                 """part""",
               "typed UploadPart response headers");
         end;
      end;

      declare
         Headers : Low_Level.Upload_Part_Result;
         Raised  : Boolean := False;
      begin
         Headers.Entity_Tag := US.To_Unbounded_String ("""part""");
         Headers.Bucket_Key_Enabled := US.To_Unbounded_String ("maybe");
         begin
            declare
               Ignored : constant Low_Level.Upload_Part_Outcome :=
                 Low_Level.Decode_Upload_Part_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "invalid UploadPart boolean header was accepted");
      end;

      declare
         Parameters : Low_Level.Upload_Part_Copy_Parameters;
      begin
         Parameters.Part_Number := 9;
         Parameters.Upload_ID := US.To_Unbounded_String ("upload+/=");
         Parameters.Copy_Source :=
           US.To_Unbounded_String ("source-bucket/source-key");
         Parameters.Copy_Source_If_Match :=
           US.To_Unbounded_String ("""source-etag""");
         Parameters.Copy_Source_If_Modified_Since :=
           US.To_Unbounded_String ("Fri, 21 Aug 2026 17:00:00 GMT");
         Parameters.Copy_Source_If_None_Match :=
           US.To_Unbounded_String ("""other-etag""");
         Parameters.Copy_Source_If_Unmodified_Since :=
           US.To_Unbounded_String ("Fri, 21 Aug 2026 18:00:00 GMT");
         Parameters.Source_Range :=
           (Is_Set => True, First => 5, Last => 9);
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Copy_Source_SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.Copy_Source_SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.Copy_Source_SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Expected_Source_Bucket_Owner :=
           US.To_Unbounded_String ("210987654321");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Upload_Part_Copy
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
            Signed : constant String :=
              ";" & Low_Level.Signed_Headers (Prepared) & ";";

            function Has (Name : String) return Boolean is
              (Ada.Strings.Fixed.Index (Signed, ";" & Name & ";") > 0);
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?partNumber=9&" &
                 "uploadId=upload%2B%2F%3D",
               "UploadPartCopy exact wire target");
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "x-amz-copy-source:source-bucket/source-key") > 0
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "x-amz-copy-source-range:bytes=5-9") > 0
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared),
                  "x-amz-copy-source-if-match") > 0
               and then Has ("x-amz-copy-source-if-modified-since")
               and then Has ("x-amz-copy-source-if-none-match")
               and then Has ("x-amz-copy-source-if-unmodified-since")
               and then Has
                 ("x-amz-copy-source-server-side-encryption-customer-key")
               and then Has
                 ("x-amz-server-side-encryption-customer-key")
               and then Has ("x-amz-request-payer")
               and then Has ("x-amz-expected-bucket-owner")
               and then Has ("x-amz-source-expected-bucket-owner"),
               "UploadPartCopy modeled headers are signed");
         end;
      end;

      declare
         Parameters : Low_Level.Upload_Part_Copy_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Upload_ID := US.To_Unbounded_String ("upload");
         Parameters.Copy_Source :=
           US.To_Unbounded_String ("source-bucket/source-key");
         Parameters.Source_Range :=
           (Is_Set => True,
            First  => 0,
            Last   =>
              Flyology.Object_Storage.S3.Core.Maximum_Part_Size);
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part_Copy
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "UploadPartCopy accepted a 5 GiB+1 range");
      end;

      declare
         Parameters : Low_Level.Upload_Part_Copy_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Upload_ID := US.To_Unbounded_String ("upload");
         Parameters.Copy_Source :=
           US.To_Unbounded_String ("source-bucket/source-key");
         Parameters.Copy_Source_SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.Copy_Source_SSE_Customer_Key :=
           US.To_Unbounded_String
             ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.Copy_Source_SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part_Copy
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised,
            "UploadPartCopy allowed an SSE-C key over plaintext HTTP");
         Raised := False;
         Parameters.Copy_Source_SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES512");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part_Copy
                   (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised, "UploadPartCopy accepted a non-AES256 SSE-C algorithm");
      end;

      declare
         Headers : Low_Level.Upload_Part_Copy_Result;
      begin
         Headers.Copy_Source_Version_ID := US.To_Unbounded_String ("v1");
         Headers.Server_Side_Encryption :=
           US.To_Unbounded_String ("aws:kms");
         Headers.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Headers.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.SSE_KMS_Key_ID := US.To_Unbounded_String ("kms-key");
         Headers.Bucket_Key_Enabled := US.To_Unbounded_String ("true");
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         declare
            Outcome : constant Low_Level.Upload_Part_Copy_Outcome :=
              Low_Level.Decode_Upload_Part_Copy_Response
                (200,
                 "<CopyPartResult>" &
                 "<LastModified>2026-08-21T17:00:00.000Z</LastModified>" &
                 "<ETag>&quot;copied&quot;</ETag>" &
                 "<ChecksumCRC32>AAAAAA==</ChecksumCRC32>" &
                 "</CopyPartResult>", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Part_Copied
               and then US.To_String
                 (Outcome.Result.Copy_Part.Entity_Tag) = """copied"""
               and then US.To_String
                 (Outcome.Result.Copy_Source_Version_ID) = "v1"
               and then US.To_String
                 (Outcome.Result.Server_Side_Encryption) = "aws:kms"
               and then US.To_String
                 (Outcome.Result.SSE_Customer_Algorithm) = "AES256"
               and then US.To_String
                 (Outcome.Result.SSE_KMS_Key_ID) = "kms-key"
               and then US.To_String
                 (Outcome.Result.Request_Charged) = "requester",
               "typed UploadPartCopy success response");
         end;
      end;

      declare
         Headers : Low_Level.Upload_Part_Copy_Result;

         procedure Require_Invalid (Message : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Upload_Part_Copy_Outcome :=
                    Low_Level.Decode_Upload_Part_Copy_Response
                      (200,
                       "<CopyPartResult>" &
                       "<LastModified>2026-08-21T17:00:00Z</LastModified>" &
                       "<ETag>&quot;copied&quot;</ETag>" &
                       "</CopyPartResult>", Headers);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Require_Invalid;
      begin
         Headers.Server_Side_Encryption :=
           US.To_Unbounded_String ("not-an-encryption-mode");
         Require_Invalid
           ("UploadPartCopy accepted an invalid encryption result");
         Headers := (others => <>);
         Headers.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES512");
         Require_Invalid
           ("UploadPartCopy accepted an invalid SSE-C result algorithm");
         Headers := (others => <>);
         Headers.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("not-base64");
         Require_Invalid
           ("UploadPartCopy accepted an invalid SSE-C result digest");
         Headers := (others => <>);
         Headers.Bucket_Key_Enabled := US.To_Unbounded_String ("maybe");
         Require_Invalid
           ("UploadPartCopy accepted an invalid bucket-key result");
         Headers := (others => <>);
         Headers.Request_Charged := US.To_Unbounded_String ("owner");
         Require_Invalid
           ("UploadPartCopy accepted an invalid requester-pays result");
      end;

      declare
         Headers : Low_Level.Upload_Part_Copy_Result;
         Outcome : constant Low_Level.Upload_Part_Copy_Outcome :=
           Low_Level.Decode_Upload_Part_Copy_Response
             (200, "<Error><Code>InternalError</Code>" &
              "<Message>late copy failure</Message></Error>", Headers,
              "request-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Copy_Part_Rejected
            and then Outcome.Status = 200
            and then US.To_String (Outcome.Error.Code) = "InternalError"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header",
            "embedded HTTP-200 UploadPartCopy error response");
      end;

      declare
         Headers : Low_Level.Upload_Part_Copy_Result;
         Raised  : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Upload_Part_Copy_Outcome :=
                 Low_Level.Decode_Upload_Part_Copy_Response
                   (200, "<CopyPartResult><ETag>missing-date</ETag>" &
                    "</CopyPartResult>", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert
           (Raised, "incomplete UploadPartCopy success was accepted");
      end;

      declare
         HTTP : aliased Flyology.HTTP.Client.Client (Capacity => 1);
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", "key", Identity,
              "us-east-1", "20130524T000000Z");
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Complete_Multipart_Outcome :=
                 Low_Level.Execute_Complete_Multipart_Upload
                   (HTTP, Prepared);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "prepared operation mismatch reached HTTP client");
      end;
   end Check_Low_Level_Multipart_Request;

   procedure Check_Low_Level_Copy_Object (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package US renames Ada.Strings.Unbounded;
      use type Low_Level.Copy_Object_Outcome_Kind;
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");

   begin
      declare
         Parameters : Low_Level.Copy_Object_Parameters;
      begin
         Parameters.Copy_Source :=
           US.To_Unbounded_String ("source-bucket/source-key");
         Parameters.Content_Type := US.To_Unbounded_String ("text/plain");
         Parameters.Copy_Source_If_Match :=
           US.To_Unbounded_String ("""source-etag""");
         Parameters.Metadata_Directive := US.To_Unbounded_String ("COPY");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Copy_Object
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25",
               "CopyObject exact wire target");
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "x-amz-copy-source:source-bucket/source-key") > 0
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "x-amz-metadata-directive:COPY") > 0
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared),
                  "x-amz-copy-source-if-match") > 0,
               "CopyObject core headers are signed");
         end;
      end;

      declare
         Parameters : Low_Level.Copy_Object_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Copy_Source :=
           US.To_Unbounded_String ("source-bucket/source-key");
         Parameters.Metadata_Directive :=
           US.To_Unbounded_String ("MERGE");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Copy_Object
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "invalid CopyObject metadata directive accepted");
      end;

      declare
         Headers : Low_Level.Copy_Object_Result;
      begin
         Headers.Copy_Source_Version_ID := US.To_Unbounded_String ("v1");
         Headers.Bucket_Key_Enabled := US.To_Unbounded_String ("true");
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         declare
            Outcome : constant Low_Level.Copy_Object_Outcome :=
              Low_Level.Decode_Copy_Object_Response
                (200,
                 "<CopyObjectResult>" &
                 "<LastModified>2026-08-21T17:00:00.000Z</LastModified>" &
                 "<ETag>&quot;copied-object&quot;</ETag>" &
                 "<ChecksumType>FULL_OBJECT</ChecksumType>" &
                 "<ChecksumCRC32>AAAAAA==</ChecksumCRC32>" &
                 "</CopyObjectResult>", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Object_Copied
               and then US.To_String
                 (Outcome.Result.Copy_Result.Entity_Tag) =
                   """copied-object"""
               and then US.To_String
                 (Outcome.Result.Copy_Source_Version_ID) = "v1",
               "typed CopyObject success response");
         end;
      end;

      declare
         Headers : Low_Level.Copy_Object_Result;
         Outcome : constant Low_Level.Copy_Object_Outcome :=
           Low_Level.Decode_Copy_Object_Response
             (200, "<Error><Code>InternalError</Code>" &
              "<Message>late copy failure</Message></Error>", Headers,
              "request-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Copy_Object_Rejected
            and then Outcome.Status = 200
            and then US.To_String (Outcome.Error.Code) = "InternalError"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header",
            "embedded HTTP-200 CopyObject error response");
      end;

      declare
         Headers : Low_Level.Copy_Object_Result;
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Copy_Object_Outcome :=
                 Low_Level.Decode_Copy_Object_Response
                   (200, "<CopyObjectResult>" &
                    "<LastModified>2026-08-21T17:00:00Z</LastModified>" &
                    "<ETag>etag</ETag>" &
                    "<ChecksumType>UNKNOWN</ChecksumType>" &
                    "</CopyObjectResult>", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "invalid CopyObject checksum type accepted");
      end;
   end Check_Low_Level_Copy_Object;

   procedure Check_Low_Level_Bucket_Lifecycle (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Buckets renames Flyology.Object_Storage.S3.Buckets;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package SigV4 renames Flyology.Object_Storage.S3.SigV4;
      package US renames Ada.Strings.Unbounded;
      use type Low_Level.Create_Bucket_Outcome_Kind;
      use type Low_Level.Get_Bucket_Location_Outcome_Kind;
      use type Low_Level.Put_Bucket_Tagging_Outcome_Kind;
      use type Low_Level.Get_Bucket_Tagging_Outcome_Kind;
      use type Low_Level.Head_Bucket_Outcome_Kind;
      use type Low_Level.Head_Object_Outcome_Kind;
      use type Low_Level.Get_Object_Attributes_Outcome_Kind;
      use type Low_Level.Head_Object_Result;
      use type Low_Level.List_Buckets_Outcome_Kind;
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
      declare
         Value : Buckets.List_Buckets_Result;
      begin
         Value.Has_Owner := True;
         Value.Owner.Display_Name := US.To_Unbounded_String ("owner&name");
         Value.Owner.ID := US.To_Unbounded_String ("owner-id");
         Value.Buckets.Append
           (Buckets.Bucket_Entry'
              (Name          => US.To_Unbounded_String ("alpha-bucket"),
               Creation_Date => US.To_Unbounded_String
                 ("2026-08-22T01:02:03.000Z"),
               Bucket_Region => US.To_Unbounded_String ("us-west-2"),
               Bucket_ARN    => US.To_Unbounded_String
                 ("arn:aws:s3:::alpha-bucket")));
         Value.Continuation_Token := US.To_Unbounded_String ("next<&>");
         Value.Has_Continuation_Token := True;
         Value.Prefix := US.To_Unbounded_String ("alpha-");
         Value.Has_Prefix := True;
         declare
            Document : constant String :=
              Buckets.Serialize_List_Buckets (Value);
            Parsed : constant Buckets.List_Buckets_Result :=
              Buckets.Parse_List_Buckets (Document);
         begin
            Assert
              (Parsed.Has_Owner
               and then Parsed.Has_Continuation_Token
               and then Parsed.Has_Prefix
               and then US.To_String (Parsed.Owner.Display_Name) =
                 "owner&name"
               and then Parsed.Buckets.Length = 1
               and then US.To_String
                 (Parsed.Buckets.First_Element.Name) = "alpha-bucket"
               and then US.To_String
                 (Parsed.Buckets.First_Element.Creation_Date) =
                   "2026-08-22T01:02:03.000Z"
               and then US.To_String
                 (Parsed.Buckets.First_Element.Bucket_Region) = "us-west-2"
               and then US.To_String (Parsed.Continuation_Token) = "next<&>"
               and then Ada.Strings.Fixed.Index
                 (Document, "<ContinuationToken>next&lt;&amp;&gt;" &
                  "</ContinuationToken>") > 0,
               "ListBuckets complete XML round trip");
         end;
      end;

      declare
         Parameters : constant Low_Level.List_Buckets_Parameters :=
           (Max_Buckets            => 2,
            Has_Max_Buckets        => True,
            Continuation_Token     => US.To_Unbounded_String ("token +/="),
            Has_Continuation_Token => True,
            Prefix                 => US.To_Unbounded_String ("team/ "),
            Has_Prefix             => True,
            Bucket_Region          => US.To_Unbounded_String ("us-west-2"));
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Buckets
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, Parameters, Identity, "us-east-1",
              "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/?bucket-region=us-west-2&continuation-token=" &
              "token%20%2B%2F%3D&max-buckets=2&prefix=team%2F%20",
            "ListBuckets exact generated-model query projection");
      end;

      declare
         Request : constant Buckets.List_Buckets_Request :=
           Buckets.Parse_List_Buckets_Query
             ("max-buckets=2&prefix=team%2Dbucket&" &
              "bucket-region=us-east-1&x-id=ListBuckets");
      begin
         Assert
           (Request.Has_Max_Buckets
            and then Request.Max_Buckets = 2
            and then not Request.Has_Continuation_Token
            and then US.To_String (Request.Prefix) = "team-bucket"
            and then US.To_String (Request.Bucket_Region) = "us-east-1",
            "strict ListBuckets server query projection");
      end;

      declare
         Request : constant Buckets.List_Buckets_Request :=
           Buckets.Parse_List_Buckets_Query
             ("continuation-token=&prefix=");
      begin
         Assert
           (Request.Has_Continuation_Token
            and then US.Length (Request.Continuation_Token) = 0
            and then Request.Has_Prefix
            and then US.Length (Request.Prefix) = 0,
            "ListBuckets lost present empty query members");
      end;

      declare
         Token : constant String := Buckets.Encode_Continuation
           ("team-", "us-east-1", "team-alpha-bucket");
         Decoded : constant Buckets.Continuation_Result :=
           Buckets.Decode_Continuation
             (Token, "team-", "us-east-1");
      begin
         Assert
           (Decoded.Valid
            and then US.To_String (Decoded.After) = "team-alpha-bucket",
            "ListBuckets continuation token round trip");
         Assert
           (not Buckets.Decode_Continuation
              (Token, "other-", "us-east-1").Valid,
            "ListBuckets continuation token was not prefix-bound");
         Assert
           (not Buckets.Decode_Continuation
              (Token, "team-", "us-west-2").Valid,
            "ListBuckets continuation token was not region-bound");
         Assert
           (not Buckets.Decode_Continuation
              (Token & "00", "team-", "us-east-1").Valid,
            "malformed ListBuckets continuation token was accepted");
      end;

      declare
         procedure Expect_Bad_Query (Query : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Buckets.List_Buckets_Request :=
                    Buckets.Parse_List_Buckets_Query (Query);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Buckets.Malformed_List_Buckets_Request =>
                  Raised := True;
            end;
            Assert
              (Raised,
               "invalid ListBuckets query was accepted: " & Query);
         end Expect_Bad_Query;
      begin
         Expect_Bad_Query ("max-buckets=0");
         Expect_Bad_Query ("max-buckets=10001");
         Expect_Bad_Query ("max-buckets=1&max-buckets=2");
         Expect_Bad_Query ("prefix=bad%2");
         Expect_Bad_Query
           ("continuation-token=" & String'(1 .. 1_025 => 't'));
         Expect_Bad_Query ("bucket-region=US-EAST-1");
         Expect_Bad_Query
           ("bucket-region=" &
            String'(1 .. Buckets.Maximum_Bucket_Region_Length + 1 => 'a'));
         Expect_Bad_Query ("unknown=value");
         Expect_Bad_Query ("x-id=ListObjectsV2");
      end;

      declare
         Parameters : Low_Level.List_Buckets_Parameters;
         Prepared : Low_Level.Prepared_Request;
      begin
         Parameters.Has_Max_Buckets := True;
         Parameters.Max_Buckets := 1;
         Parameters.Has_Continuation_Token := True;
         Parameters.Has_Prefix := True;
         Prepared := Low_Level.Prepare_List_Buckets
           (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
            Low_Level.Path_Style, Parameters, Identity, "us-east-1",
            "20130524T000000Z");
         Assert
           (Low_Level.Target (Prepared) =
              "/?continuation-token&max-buckets=1&prefix",
            "ListBuckets low-level request collapsed empty members: " &
              Low_Level.Target (Prepared));
      end;

      declare
         Parameters : Low_Level.List_Buckets_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Has_Continuation_Token := True;
         Parameters.Continuation_Token :=
           US.To_Unbounded_String (String'(1 .. 1_025 => 't'));
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Buckets
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request => Raised := True;
         end;
         Assert (Raised, "oversized ListBuckets token was prepared");
      end;

      declare
         Outcome : constant Low_Level.List_Buckets_Outcome :=
           Low_Level.Decode_List_Buckets_Response
             (200,
              "<ListAllMyBucketsResult>" &
              "<Owner><ID>owner-id</ID></Owner>" &
              "<Buckets><Bucket><Name>one</Name>" &
              "<CreationDate>2026-08-22T01:02:03Z</CreationDate>" &
              "</Bucket></Buckets><Prefix>o</Prefix>" &
              "</ListAllMyBucketsResult>");
      begin
         Assert
           (Outcome.Kind = Low_Level.Buckets_Listed
            and then Outcome.Result.Has_Owner
            and then Outcome.Result.Has_Prefix
            and then Outcome.Result.Buckets.Length = 1
            and then US.To_String (Outcome.Result.Prefix) = "o",
            "typed ListBuckets success response");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Buckets.List_Buckets_Result :=
                 Buckets.Parse_List_Buckets
                   ("<ListAllMyBucketsResult><Buckets/><Buckets/>" &
                    "</ListAllMyBucketsResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Buckets.Malformed_Bucket_Listing =>
               Raised := True;
         end;
         Assert (Raised, "duplicate ListBuckets container was accepted");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Buckets.List_Buckets_Result :=
                 Buckets.Parse_List_Buckets
                   ("<ListAllMyBucketsResult><Buckets/>" &
                    "<ContinuationToken>" & String'(1 .. 1_025 => 't') &
                    "</ContinuationToken></ListAllMyBucketsResult>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Buckets.Malformed_Bucket_Listing => Raised := True;
         end;
         Assert (Raised, "oversized ListBuckets response token was accepted");
      end;

      declare
         Document : US.Unbounded_String := US.To_Unbounded_String
           ("<ListAllMyBucketsResult><Buckets>");
         Raised : Boolean := False;
      begin
         for Index in 1 .. 10_001 loop
            pragma Unreferenced (Index);
            US.Append (Document, "<Bucket/>");
         end loop;
         US.Append (Document, "</Buckets></ListAllMyBucketsResult>");
         begin
            declare
               Ignored : constant Buckets.List_Buckets_Result :=
                 Buckets.Parse_List_Buckets (US.To_String (Document));
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Buckets.Malformed_Bucket_Listing =>
               Raised := True;
         end;
         Assert (Raised, "ListBuckets accepted more than 10,000 buckets");
      end;

      declare
         Value  : Buckets.List_Buckets_Result;
         Raised : Boolean := False;
      begin
         Value.Owner.ID := US.To_Unbounded_String ("owner-without-presence");
         begin
            declare
               Ignored : constant String :=
                 Buckets.Serialize_List_Buckets (Value);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Buckets.Malformed_Bucket_Listing =>
               Raised := True;
         end;
         Assert (Raised, "ListBuckets serialized owner without presence");
      end;

      declare
         Outcome : constant Low_Level.List_Buckets_Outcome :=
           Low_Level.Decode_List_Buckets_Response
             (403,
              "<Error><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error>",
              "request-id", "host-id");
      begin
         Assert
           (Outcome.Kind = Low_Level.List_Buckets_Rejected
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id",
            "typed ListBuckets error response");
      end;

      declare
         HTTP : aliased Flyology.HTTP.Client.Client (Capacity => 1);
         Parameters : Low_Level.Create_Bucket_Parameters;
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Bucket
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", Parameters, Identity,
              "us-east-1", "20130524T000000Z");
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.List_Buckets_Outcome :=
                 Low_Level.Execute_List_Buckets (HTTP, Prepared);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "ListBuckets operation mismatch reached HTTP");
      end;

      declare
         Configuration : Buckets.Create_Bucket_Configuration;
      begin
         Configuration.Location_Type :=
           US.To_Unbounded_String ("AvailabilityZone");
         Configuration.Location_Name := US.To_Unbounded_String ("usw2-az1");
         Configuration.Data_Redundancy :=
           US.To_Unbounded_String ("SingleAvailabilityZone");
         Configuration.Bucket_Type := US.To_Unbounded_String ("Directory");
         Configuration.Tags.Append
           (Buckets.Tag'
              (Key   => US.To_Unbounded_String ("team&owner"),
               Value => US.To_Unbounded_String ("storage<core>")));
         Assert
           (Buckets.Serialize_Create_Configuration (Configuration) =
              "<?xml version=""1.0"" encoding=""UTF-8""?>" &
              "<CreateBucketConfiguration xmlns=""http://s3.amazonaws.com/" &
              "doc/2006-03-01/"">" &
              "<Location><Type>AvailabilityZone</Type>" &
              "<Name>usw2-az1</Name></Location>" &
              "<Bucket><DataRedundancy>SingleAvailabilityZone" &
              "</DataRedundancy><Type>Directory</Type></Bucket>" &
              "<Tags><Tag><Key>team&amp;owner</Key>" &
              "<Value>storage&lt;core&gt;</Value></Tag></Tags>" &
              "</CreateBucketConfiguration>",
            "CreateBucket complete nested configuration serialization");
         declare
            Parsed : constant Buckets.Create_Bucket_Configuration :=
              Buckets.Parse_Create_Configuration
                (Buckets.Serialize_Create_Configuration (Configuration));
         begin
            Assert
              (US.To_String (Parsed.Location_Type) = "AvailabilityZone"
               and then US.To_String (Parsed.Location_Name) = "usw2-az1"
               and then US.To_String (Parsed.Data_Redundancy) =
                 "SingleAvailabilityZone"
               and then US.To_String (Parsed.Bucket_Type) = "Directory"
               and then Parsed.Tags.Length = 1
               and then US.To_String (Parsed.Tags.First_Element.Key) =
                 "team&owner"
               and then US.To_String (Parsed.Tags.First_Element.Value) =
                 "storage<core>",
               "CreateBucket configuration round trip");
         end;
      end;

      declare
         procedure Rejects (Document : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Buckets.Create_Bucket_Configuration :=
                    Buckets.Parse_Create_Configuration (Document);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Buckets.Malformed_Bucket_Configuration => Raised := True;
            end;
            Assert (Raised, "malformed CreateBucket XML was accepted");
         end Rejects;
      begin
         Assert
           (Buckets.Is_Empty (Buckets.Parse_Create_Configuration ("")),
            "empty CreateBucket configuration was not accepted");
         Rejects ("<WrongRoot/>");
         Rejects
           ("<CreateBucketConfiguration><LocationConstraint>us-west-2" &
            "</LocationConstraint><LocationConstraint>us-west-2" &
            "</LocationConstraint></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><LocationConstraint/>" &
            "</CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Location><Type>" &
            "AvailabilityZone</Type></Location>" &
            "</CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Location><Type/>" &
            "<Name/></Location></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Bucket><Type>Directory</Type>" &
            "</Bucket></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Bucket><DataRedundancy/>" &
            "<Type/></Bucket></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Tags/></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Tags><Tag><Key>one</Key>" &
            "</Tag></Tags></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Tags>" &
            "<Tag><Key>same</Key><Value>one</Value></Tag>" &
            "<Tag><Key>same</Key><Value>two</Value></Tag>" &
            "</Tags></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Tags><Tag><Key>" &
            String'(1 .. 129 => 'k') &
            "</Key><Value>value</Value></Tag></Tags>" &
            "</CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><Tags><Tag><Key>key</Key>" &
            "<Value>" & String'(1 .. 257 => 'v') &
            "</Value></Tag></Tags></CreateBucketConfiguration>");
         Rejects
           ("<CreateBucketConfiguration><LocationConstraint>us-east-1" &
            "</LocationConstraint></CreateBucketConfiguration>");
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant
                    Buckets.Create_Bucket_Configuration :=
                      Buckets.Parse_Create_Configuration
                        ("<CreateBucketConfiguration/>",
                         Limits =>
                           (Maximum_Document_Bytes => 8,
                            Maximum_Depth          => 1,
                            Maximum_Elements       => 1,
                            Maximum_Text_Bytes     => 1));
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Buckets.Malformed_Bucket_Configuration => Raised := True;
            end;
            Assert (Raised, "CreateBucket XML byte limit was ignored");
         end;
         declare
            Configuration : Buckets.Create_Bucket_Configuration;
            Raised        : Boolean := False;
         begin
            for Index in 1 .. 51 loop
               Configuration.Tags.Append
                 (Buckets.Tag'
                    (Key   => US.To_Unbounded_String
                       ("key-" & Ada.Strings.Fixed.Trim
                          (Positive'Image (Index), Ada.Strings.Both)),
                     Value => US.Null_Unbounded_String));
            end loop;
            begin
               declare
                  Ignored : constant String :=
                    Buckets.Serialize_Create_Configuration (Configuration);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Buckets.Invalid_Bucket_Configuration => Raised := True;
            end;
            Assert (Raised, "CreateBucket serialized more than 50 tags");
         end;
      end;

      declare
         Parameters : Low_Level.Create_Bucket_Parameters;
      begin
         Parameters.ACL := US.To_Unbounded_String ("private");
         Parameters.Configuration.Location_Constraint :=
           US.To_Unbounded_String ("us-west-2");
         Parameters.Grant_Full_Control :=
           US.To_Unbounded_String ("id=owner");
         Parameters.Grant_Read := US.To_Unbounded_String ("id=reader");
         Parameters.Grant_Read_ACP := US.To_Unbounded_String ("id=acl-read");
         Parameters.Grant_Write := US.To_Unbounded_String ("id=writer");
         Parameters.Grant_Write_ACP :=
           US.To_Unbounded_String ("id=acl-write");
         Parameters.Object_Lock_Enabled := (Is_Set => True, Value => True);
         Parameters.Object_Ownership :=
           US.To_Unbounded_String ("BucketOwnerEnforced");
         Parameters.Bucket_Namespace := US.To_Unbounded_String ("global");
         declare
            Payload : constant String :=
              Buckets.Serialize_Create_Configuration
                (Parameters.Configuration);
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Create_Bucket
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-west-2", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket"
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  SigV4.SHA256_Hex (Payload)) > 0,
               "CreateBucket exact bucket target and signed XML body");
            Assert
              (Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-acl;x-amz-bucket-namespace;" &
                 "x-amz-bucket-object-lock-enabled;x-amz-content-sha256;" &
                 "x-amz-date;x-amz-grant-full-control;x-amz-grant-read;" &
                 "x-amz-grant-read-acp;x-amz-grant-write;" &
                 "x-amz-grant-write-acp;x-amz-object-ownership",
               "CreateBucket every modeled request header is signed");
         end;
      end;

      declare
         East_Document : constant String :=
           Buckets.Serialize_Location_Constraint ("us-east-1");
         West_Document : constant String :=
           Buckets.Serialize_Location_Constraint ("us-west-2");
      begin
         Assert
           (Buckets.Parse_Location_Constraint (East_Document) = ""
            and then Ada.Strings.Fixed.Index
              (East_Document, ">us-east-1<") = 0,
            "GetBucketLocation us-east-1 was not encoded as null");
         Assert
           (Buckets.Parse_Location_Constraint (West_Document) = "us-west-2"
            and then Buckets.Parse_Location_Constraint
              ("<LocationConstraint>EU</LocationConstraint>") = "EU",
            "GetBucketLocation legacy constraint round trip");
      end;

      declare
         procedure Rejects (Document : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant String :=
                    Buckets.Parse_Location_Constraint (Document);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Buckets.Malformed_Bucket_Location => Raised := True;
            end;
            Assert (Raised, "malformed GetBucketLocation XML was accepted");
         end Rejects;
      begin
         Rejects ("<WrongRoot>us-west-2</WrongRoot>");
         Rejects
           ("<LocationConstraint><Region>us-west-2</Region>" &
            "</LocationConstraint>");
         Rejects
           ("<LocationConstraint>not-a-region</LocationConstraint>");
         Rejects
           ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
            "<LocationConstraint xmlns=""http://s3.amazonaws.com/doc/" &
            "2006-03-01/"">");
      end;

      Assert
        (Buckets.Parse_Location_Constraint
           ("<LocationConstraint>us-east-1</LocationConstraint>") =
           "us-east-1",
         "compatible literal us-east-1 location was rejected");
      Assert
        (Buckets.Parse_Location_Constraint
           ("<CreateBucketConfiguration>" &
            "<LocationConstraint></LocationConstraint>" &
            "</CreateBucketConfiguration>") = "",
         "compatible wrapped location constraint was rejected");

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String :=
                 Buckets.Parse_Location_Constraint
                   ("<CreateBucketConfiguration>" &
                    "<LocationConstraint/>" &
                    "<LocationConstraint/>" &
                    "</CreateBucketConfiguration>");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Buckets.Malformed_Bucket_Location => Raised := True;
         end;
         Assert (Raised, "duplicate wrapped location was accepted");
      end;

      declare
         Parameters : Low_Level.Get_Bucket_Location_Parameters;
      begin
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Location
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket?location"
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner"
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  ASCII.LF & "location=" & ASCII.LF) > 0,
               "GetBucketLocation exact signed request projection");
         end;
      end;

      declare
         Outcome : constant Low_Level.Get_Bucket_Location_Outcome :=
           Low_Level.Decode_Get_Bucket_Location_Response
             (200,
              "<LocationConstraint xmlns=""http://s3.amazonaws.com/doc/" &
              "2006-03-01/"">us-west-2</LocationConstraint>");
      begin
         Assert
           (Outcome.Kind = Low_Level.Bucket_Location_Found
            and then US.To_String
              (Outcome.Result.Location_Constraint) = "us-west-2",
            "typed GetBucketLocation success response");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Get_Bucket_Location_Outcome :=
                 Low_Level.Decode_Get_Bucket_Location_Response
                   (200,
                    "<LocationConstraint>us-west-2" &
                    "</LocationConstraint>",
                    Limits =>
                      (Maximum_Document_Bytes => 32,
                       Maximum_Depth          => 2,
                       Maximum_Elements       => 2,
                       Maximum_Text_Bytes     => 16));
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "GetBucketLocation XML limit was ignored");
      end;

      declare
         Outcome : constant Low_Level.Get_Bucket_Location_Outcome :=
           Low_Level.Decode_Get_Bucket_Location_Response
             (404,
              "<Error><Code>NoSuchBucket</Code>" &
              "<Message>missing</Message></Error>", "request-id");
      begin
         Assert
           (Outcome.Kind = Low_Level.Get_Bucket_Location_Rejected
            and then US.To_String (Outcome.Error.Code) = "NoSuchBucket"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id",
            "typed GetBucketLocation error response");
      end;

      declare
         Value : Flyology.Object_Storage.Tags.Tag_Set;
         Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      begin
         Value.Append
           (Flyology.Object_Storage.Tags.Tag'
              (Key   => US.To_Unbounded_String ("project"),
               Value => US.To_Unbounded_String ("flyology")));
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         declare
            Document : constant String :=
              Flyology.Object_Storage.S3.Tagging.Serialize_Bucket (Value);
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Tagging
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Value, Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket?tagging"
               and then Low_Level.Signed_Headers (Prepared) =
                 "content-md5;host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;x-amz-request-payer"
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  SigV4.SHA256_Hex (Document)) > 0,
               "PutBucketTagging exact signed request projection");
         end;

         Parameters.Checksum_Algorithm := US.To_Unbounded_String ("SHA256");
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Put_Bucket_Tagging
                      (Flyology.HTTP.Parse_Origin
                         ("http://localhost:9000"),
                       Low_Level.Path_Style, "example-bucket", Value,
                       Parameters, Identity, "us-east-1",
                       "20130524T000000Z");
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request => Raised := True;
            end;
            Assert
              (Raised,
               "PutBucketTagging silently emitted an incomplete checksum");
         end;
      end;

      declare
         Headers : Low_Level.Put_Bucket_Tagging_Result;
      begin
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         declare
            Outcome : constant Low_Level.Put_Bucket_Tagging_Outcome :=
              Low_Level.Decode_Put_Bucket_Tagging_Response
                (200, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Bucket_Tags_Replaced
               and then US.To_String (Outcome.Result.Request_Charged) =
                 "requester",
               "typed PutBucketTagging success response");
         end;
      end;

      declare
         Headers : Low_Level.Put_Bucket_Tagging_Result;
         Raised  : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Put_Bucket_Tagging_Outcome :=
                 Low_Level.Decode_Put_Bucket_Tagging_Response
                   (200, "unexpected", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "PutBucketTagging accepted a success body");
      end;

      declare
         Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      begin
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Tagging
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket?tagging"
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner",
               "GetBucketTagging exact signed request projection");
         end;
      end;

      declare
         Headers : Low_Level.Get_Bucket_Tagging_Result;
         Document : constant String :=
           "<Tagging>" &
           "<TagSet><Tag><Key>project</Key><Value>flyology</Value>" &
           "</Tag></TagSet></Tagging>";
         Outcome : constant Low_Level.Get_Bucket_Tagging_Outcome :=
           Low_Level.Decode_Get_Bucket_Tagging_Response
             (200, Document, Headers);
      begin
         Assert
           (Outcome.Kind = Low_Level.Bucket_Tags_Found
            and then Outcome.Result.Value.Length = 1
            and then US.To_String
              (Outcome.Result.Value.First_Element.Value) = "flyology",
            "typed namespace-free GetBucketTagging success response");
      end;

      declare
         Headers : Low_Level.Get_Bucket_Tagging_Result;
         Outcome : constant Low_Level.Get_Bucket_Tagging_Outcome :=
           Low_Level.Decode_Get_Bucket_Tagging_Response
             (404,
              "<Error><Code>NoSuchTagSet</Code>" &
              "<Message>missing</Message></Error>", Headers, "request-id");
      begin
         Assert
           (Outcome.Kind = Low_Level.Get_Bucket_Tagging_Rejected
            and then US.To_String (Outcome.Error.Code) = "NoSuchTagSet"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id",
            "typed GetBucketTagging error response");
      end;

      declare
         Parameters : Low_Level.Head_Bucket_Parameters;
      begin
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Bucket
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket"
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner",
               "HeadBucket exact target and signed owner precondition");
         end;
      end;

      declare
         Headers : Low_Level.Create_Bucket_Result;
      begin
         Headers.Location := US.To_Unbounded_String ("/example-bucket");
         Headers.Bucket_ARN :=
           US.To_Unbounded_String ("arn:aws:s3:::example-bucket");
         declare
            Outcome : constant Low_Level.Create_Bucket_Outcome :=
              Low_Level.Decode_Create_Bucket_Response (200, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Bucket_Created
               and then US.To_String (Outcome.Result.Location) =
                 "/example-bucket",
               "typed CreateBucket success headers");
         end;
      end;

      declare
         Headers : Low_Level.Create_Bucket_Result;
         Raised  : Boolean := False;
      begin
         Headers.Bucket_ARN := US.To_Unbounded_String ("arn::s3:::bucket");
         begin
            declare
               Ignored : constant Low_Level.Create_Bucket_Outcome :=
                 Low_Level.Decode_Create_Bucket_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "CreateBucket accepted an invalid bucket ARN");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
      begin
         Headers.Bucket_Region := US.To_Unbounded_String ("us-west-2");
         Headers.Access_Point_Alias := (Is_Set => True, Value => False);
         declare
            Outcome : constant Low_Level.Head_Bucket_Outcome :=
              Low_Level.Decode_Head_Bucket_Response (200, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Bucket_Found
               and then Outcome.Result.Access_Point_Alias.Is_Set
               and then not Outcome.Result.Access_Point_Alias.Value,
               "typed HeadBucket success headers");
         end;
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Outcome : constant Low_Level.Head_Bucket_Outcome :=
           Low_Level.Decode_Head_Bucket_Response (200, "", Headers);
      begin
         Assert
           (Outcome.Kind = Low_Level.Bucket_Found
            and then US.Length (Outcome.Result.Bucket_Region) = 0,
            "HeadBucket optional region-header compatibility");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Raised  : Boolean := False;
      begin
         Headers.Bucket_Region := US.To_Unbounded_String ("US-WEST-2");
         begin
            declare
               Ignored : constant Low_Level.Head_Bucket_Outcome :=
                 Low_Level.Decode_Head_Bucket_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "HeadBucket accepted an invalid bucket region");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Raised  : Boolean := False;
      begin
         Headers.Bucket_Region := US.To_Unbounded_String ("us-west-2");
         Headers.Bucket_ARN :=
           US.To_Unbounded_String (String'(1 .. 129 => 'a'));
         begin
            declare
               Ignored : constant Low_Level.Head_Bucket_Outcome :=
                 Low_Level.Decode_Head_Bucket_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "HeadBucket accepted an oversized bucket ARN");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Raised  : Boolean := False;
      begin
         Headers.Bucket_Region := US.To_Unbounded_String ("us-west-2");
         Headers.Bucket_Location_Type :=
           US.To_Unbounded_String ("Region");
         begin
            declare
               Ignored : constant Low_Level.Head_Bucket_Outcome :=
                 Low_Level.Decode_Head_Bucket_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "HeadBucket accepted an invalid location type");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Raised  : Boolean := False;
      begin
         Headers.Bucket_Region := US.To_Unbounded_String ("us-west-2");
         Headers.Bucket_Location_Name :=
           US.To_Unbounded_String ("USW2-AZ1");
         begin
            declare
               Ignored : constant Low_Level.Head_Bucket_Outcome :=
                 Low_Level.Decode_Head_Bucket_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "HeadBucket accepted an invalid location name");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Raised  : Boolean := False;
      begin
         Headers.Bucket_Region := US.To_Unbounded_String ("us-west-2");
         begin
            declare
               Ignored : constant Low_Level.Head_Bucket_Outcome :=
                 Low_Level.Decode_Head_Bucket_Response
                   (200, "unexpected", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "HeadBucket accepted a response body");
      end;

      declare
         package Object_Reads renames
           Flyology.Object_Storage.S3.Object_Reads;
         Request : constant Object_Reads.Object_Read_Request :=
           Object_Reads.Parse_Query
             ("partNumber=7&response-content-type=text%2Fplain&" &
              "versionId=v%2B1&x-id=HeadObject",
              Object_Reads.Head_Object);

         procedure Rejects (Query : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Object_Reads.Object_Read_Request :=
                    Object_Reads.Parse_Query
                      (Query, Object_Reads.Head_Object);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Object_Reads.Malformed_Object_Read_Request =>
                  Raised := True;
            end;
            Assert (Raised, "malformed HeadObject query was accepted");
         end Rejects;
      begin
         Assert
           (Request.Has_Part_Number and then Request.Part_Number = 7
            and then Request.Has_Version_ID
            and then US.To_String (Request.Version_ID) = "v+1"
            and then Request.Has_Response_Overrides
            and then US.To_String (Request.Response_Content_Type) =
              "text/plain",
            "strict HeadObject query projection");
         Rejects ("partNumber=0");
         Rejects ("partNumber=10001");
         Rejects ("versionId=");
         Rejects ("versionId=a&versionId=b");
         Rejects ("response-content-type=%0DInjected");
         Rejects ("x-id=GetObject");
         Rejects ("unknown=value");

         declare
            Get_Request : constant Object_Reads.Object_Read_Request :=
              Object_Reads.Parse_Query
                ("response-cache-control=no-cache&x-id=GetObject",
                 Object_Reads.Get_Object);
         begin
            Assert
              (Get_Request.Has_Response_Overrides
               and then US.To_String
                 (Get_Request.Response_Cache_Control) = "no-cache",
               "strict GetObject query projection");
         end;
         declare
            Empty_Override : constant Object_Reads.Object_Read_Request :=
              Object_Reads.Parse_Query
                ("response-content-type=&x-id=GetObject",
                 Object_Reads.Get_Object);
         begin
            Assert
              (Empty_Override.Has_Response_Content_Type
               and then US.Length
                 (Empty_Override.Response_Content_Type) = 0,
               "present-empty GetObject override lost presence");
         end;

         declare
            Now : constant Ada.Calendar.Time :=
              Ada.Calendar.Formatting.Time_Of
                (2013, 5, 24, 0, 0, 0, Time_Zone => 0);
            IMF : constant Object_Reads.Conditional_Date_Result :=
              Object_Reads.Parse_Conditional_Date
                ("Sun, 06 Nov 1994 08:49:37 GMT", Now);
            RFC_850 : constant Object_Reads.Conditional_Date_Result :=
              Object_Reads.Parse_Conditional_Date
                ("Sunday, 06-Nov-94 08:49:37 GMT", Now);
            Asctime : constant Object_Reads.Conditional_Date_Result :=
              Object_Reads.Parse_Conditional_Date
                ("Sun Nov  6 08:49:37 1994", Now);
            Before_Epoch : constant Object_Reads.Conditional_Date_Result :=
              Object_Reads.Parse_Conditional_Date
                ("Wed, 31 Dec 1969 23:59:59 GMT", Now);
         begin
            Assert
              (IMF.Valid and then RFC_850.Valid and then Asctime.Valid
               and then IMF.Seconds_Since_Epoch =
                 RFC_850.Seconds_Since_Epoch
               and then IMF.Seconds_Since_Epoch =
                 Asctime.Seconds_Since_Epoch,
               "HTTP-date formats did not normalize identically");
            Assert
              (Before_Epoch.Valid
               and then Before_Epoch.Seconds_Since_Epoch = -1,
               "pre-epoch HTTP date was clamped or rejected");
            Assert
              (not Object_Reads.Parse_Conditional_Date
                 ("Sun, 31 Feb 1994 08:49:37 GMT", Now).Valid
               and then not Object_Reads.Parse_Conditional_Date
                 ("Sun, 06 Nov 1994 08:49:37 UTC", Now).Valid
               and then not Object_Reads.Parse_Conditional_Date
                 ("Sunday, 06-Nov-94 08:49:37 GMT ", Now).Valid,
               "malformed HTTP conditional date was accepted");
         end;
      end;

      declare
         Parameters : Low_Level.Head_Object_Parameters;
      begin
         Parameters.If_Match := US.To_Unbounded_String ("""etag""");
         Parameters.If_Modified_Since :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         Parameters.If_None_Match := US.To_Unbounded_String ("""other""");
         Parameters.If_Unmodified_Since :=
           US.To_Unbounded_String ("Sat, 25 May 2013 00:00:00 GMT");
         Parameters.Byte_Range_Header :=
           US.To_Unbounded_String ("bytes=1-9");
         Parameters.Response_Cache_Control :=
           US.To_Unbounded_String ("no-cache");
         Parameters.Response_Content_Disposition :=
           US.To_Unbounded_String ("attachment; filename=a b.txt");
         Parameters.Response_Content_Encoding :=
           US.To_Unbounded_String ("gzip");
         Parameters.Response_Content_Language :=
           US.To_Unbounded_String ("en-CA");
         Parameters.Response_Content_Type :=
           US.To_Unbounded_String ("application/test");
         Parameters.Response_Expires :=
           US.To_Unbounded_String ("Fri, 24 May 2013 01:00:00 GMT");
         Parameters.Version_ID := US.To_Unbounded_String ("version +/=");
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key :=
           US.To_Unbounded_String
             ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Part_Number := (Is_Set => True, Value => 7);
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Checksum_Mode := True;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Object
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?partNumber=7&" &
                 "response-cache-control=no-cache&" &
                 "response-content-disposition=attachment%3B%20" &
                 "filename%3Da%20b.txt&response-content-encoding=gzip&" &
                 "response-content-language=en-CA&response-content-type=" &
                 "application%2Ftest&response-expires=Fri%2C%2024%20May%20" &
                 "2013%2001%3A00%3A00%20GMT&versionId=version%20%2B%2F%3D",
               "HeadObject exact encoded query projection");
            Assert
              (Low_Level.Signed_Headers (Prepared) =
                 "host;if-match;if-modified-since;if-none-match;" &
                 "if-unmodified-since;range;x-amz-checksum-mode;" &
                 "x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;x-amz-request-payer;" &
                 "x-amz-server-side-encryption-customer-algorithm;" &
                 "x-amz-server-side-encryption-customer-key;" &
               "x-amz-server-side-encryption-customer-key-md5",
               "HeadObject every modeled request header is signed");
            declare
               Get_Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
            begin
               Assert
                 (Low_Level.Target (Get_Prepared) =
                    Low_Level.Target (Prepared)
                  and then Low_Level.Signed_Headers (Get_Prepared) =
                    Low_Level.Signed_Headers (Prepared),
                  "GetObject projects all 21 modeled request members");
            end;
         end;
      end;

      declare
         Parameters : Low_Level.Head_Object_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key :=
           US.To_Unbounded_String
             ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert
           (Raised, "HeadObject allowed an SSE-C key over plaintext HTTP");
         Raised := False;
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES512");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "GetObject accepted a non-AES256 SSE-C algorithm");
      end;

      declare
         Parameters : Low_Level.Get_Object_Attributes_Parameters;
      begin
         Parameters.Version_ID := US.To_Unbounded_String ("version +/=");
         Parameters.Has_Max_Parts := True;
         Parameters.Max_Parts := 17;
         Parameters.Has_Part_Number_Marker := True;
         Parameters.Part_Number_Marker := 9;
         Parameters.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Parameters.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Parameters.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Attributes :=
           (Entity_Tag => True, Checksum => False, Object_Parts => True,
            Storage_Class => False, Object_Size => True);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Attributes
                (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?attributes&" &
                 "versionId=version%20%2B%2F%3D",
               "GetObjectAttributes exact target projection");
            Assert
              (Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;x-amz-max-parts;" &
                 "x-amz-object-attributes;x-amz-part-number-marker;" &
                 "x-amz-request-payer;" &
                 "x-amz-server-side-encryption-customer-algorithm;" &
                 "x-amz-server-side-encryption-customer-key;" &
                 "x-amz-server-side-encryption-customer-key-md5",
               "GetObjectAttributes all modeled headers are signed");
            Assert
              (Ada.Strings.Fixed.Index
                 (Low_Level.Canonical_Request (Prepared),
                  "x-amz-object-attributes:ETag,ObjectParts,ObjectSize") > 0,
               "GetObjectAttributes selection canonicalization");
         end;
      end;

      declare
         procedure Must_Reject
           (Parameters : Low_Level.Get_Object_Attributes_Parameters;
            Origin     : String;
            Message    : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Get_Object_Attributes
                      (Flyology.HTTP.Parse_Origin (Origin),
                       Low_Level.Path_Style, "example-bucket", "key",
                       Parameters, Identity, "us-east-1",
                       "20130524T000000Z");
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Must_Reject;
         Empty : Low_Level.Get_Object_Attributes_Parameters;
         Plaintext : Low_Level.Get_Object_Attributes_Parameters;
         Bad_Payer : Low_Level.Get_Object_Attributes_Parameters;
      begin
         Empty.Attributes := (others => False);
         Must_Reject
           (Empty, "https://localhost:9000",
            "GetObjectAttributes accepted an empty selection");
         Plaintext.Attributes.Entity_Tag := True;
         Plaintext.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Plaintext.SSE_Customer_Key := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Plaintext.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Must_Reject
           (Plaintext, "http://localhost:9000",
            "GetObjectAttributes allowed an SSE-C key over plaintext");
         Bad_Payer.Attributes.Object_Size := True;
         Bad_Payer.Request_Payer := US.To_Unbounded_String ("owner");
         Must_Reject
           (Bad_Payer, "https://localhost:9000",
            "GetObjectAttributes accepted an invalid requester payer");
      end;

      declare
         Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
           Low_Level.Decode_Get_Object_Attributes_Response
             (200,
              "<GetObjectAttributesResponse>" &
              "<ETag>&quot;etag&quot;</ETag><ObjectSize>42</ObjectSize>" &
              "</GetObjectAttributesResponse>",
              Delete_Marker => "true",
              Last_Modified => "Fri, 24 May 2013 00:00:00 GMT",
              Version_ID => "version-1", Request_Charged => "requester");
      begin
         Assert
           (Outcome.Kind = Low_Level.Object_Attributes_Found
            and then Outcome.Result.Delete_Marker.Is_Set
            and then Outcome.Result.Delete_Marker.Value
            and then US.To_String (Outcome.Result.Last_Modified) =
              "Fri, 24 May 2013 00:00:00 GMT"
            and then US.To_String (Outcome.Result.Version_ID) = "version-1"
            and then US.To_String (Outcome.Result.Request_Charged) =
              "requester"
            and then Outcome.Result.Attributes.Has_Entity_Tag
            and then US.To_String
              (Outcome.Result.Attributes.Entity_Tag) = """etag"""
            and then Outcome.Result.Attributes.Object_Size.Value = 42,
            "GetObjectAttributes complete successful response decoding");
      end;

      declare
         Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
           Low_Level.Decode_Get_Object_Attributes_Response
             (404, "<Error><Code>NoSuchKey</Code>" &
              "<Message>missing</Message></Error>",
              Request_ID => "attributes-request",
              Host_ID => "attributes-host");
      begin
         Assert
           (Outcome.Kind = Low_Level.Get_Object_Attributes_Rejected
            and then US.To_String (Outcome.Error.Code) = "NoSuchKey"
            and then US.To_String (Outcome.Error.Request_ID) =
              "attributes-request"
            and then US.To_String (Outcome.Error.Host_ID) = "attributes-host",
            "GetObjectAttributes typed rejection and ID fallback");
      end;

      declare
         procedure Response_Must_Reject
           (Payload, Delete_Marker, Request_Charged, Message : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant
                    Low_Level.Get_Object_Attributes_Outcome :=
                      Low_Level.Decode_Get_Object_Attributes_Response
                        (200, Payload, Delete_Marker => Delete_Marker,
                         Request_Charged => Request_Charged);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Response_Must_Reject;
         Empty_Root : constant String :=
           "<GetObjectAttributesResponse/>";
      begin
         Response_Must_Reject
           (Empty_Root, "yes", "",
            "GetObjectAttributes accepted a malformed delete marker");
         Response_Must_Reject
           (Empty_Root, "", "owner",
            "GetObjectAttributes accepted an invalid request charge");
         Response_Must_Reject
           ("<GetObjectAttributesResponse><ObjectSize>-1</ObjectSize>" &
            "</GetObjectAttributesResponse>", "", "",
            "GetObjectAttributes accepted a malformed XML member");
      end;

      declare
         Parameters : Low_Level.Head_Object_Parameters;
         Raised : Boolean := False;
      begin
         Parameters.Byte_Range_Header :=
           US.To_Unbounded_String ("bytes=0-1,2-3");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "HeadObject accepted an invalid byte range");
      end;

      declare
         Headers : Low_Level.Head_Object_Result;
      begin
         Headers.Delete_Marker := (Is_Set => True, Value => False);
         Headers.Accept_Ranges := US.To_Unbounded_String ("bytes");
         Headers.Expiration :=
           US.To_Unbounded_String ("expiry-date=""future"", rule-id=rule");
         Headers.Restore :=
           US.To_Unbounded_String ("ongoing-request=""false""");
         Headers.Archive_Status := US.To_Unbounded_String ("ARCHIVE_ACCESS");
         Headers.Last_Modified :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         Headers.Content_Length := 9;
         Headers.Checksum_CRC32 := US.To_Unbounded_String ("AAAAAA==");
         Headers.Checksum_CRC32C := US.To_Unbounded_String ("AAAAAA==");
         Headers.Checksum_CRC64NVME :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Headers.Checksum_SHA1 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Headers.Checksum_SHA256 := US.To_Unbounded_String
           ("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
         Headers.Checksum_SHA512 := US.To_Unbounded_String
           (String'(1 .. 86 => 'A') & "==");
         Headers.Checksum_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.Checksum_XXHASH64 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Headers.Checksum_XXHASH3 :=
           US.To_Unbounded_String ("AAAAAAAAAAA=");
         Headers.Checksum_XXHASH128 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.Checksum_Type := US.To_Unbounded_String ("FULL_OBJECT");
         Headers.Entity_Tag := US.To_Unbounded_String ("""etag""");
         Headers.Missing_Meta := (Is_Set => True, Value => 2);
         Headers.Version_ID := US.To_Unbounded_String ("version");
         Headers.Cache_Control := US.To_Unbounded_String ("no-cache");
         Headers.Content_Disposition :=
           US.To_Unbounded_String ("attachment");
         Headers.Content_Encoding := US.To_Unbounded_String ("gzip");
         Headers.Content_Language := US.To_Unbounded_String ("en-CA");
         Headers.Content_Type := US.To_Unbounded_String ("application/test");
         Headers.Expires :=
           US.To_Unbounded_String ("Fri, 24 May 2013 01:00:00 GMT");
         Headers.Website_Redirect_Location :=
           US.To_Unbounded_String ("/replacement");
         Headers.Server_Side_Encryption :=
           US.To_Unbounded_String ("aws:kms:dsse");
         Headers.Metadata.Append
           (Low_Level.Metadata_Entry'
              (Name  => US.To_Unbounded_String ("project"),
               Value => US.To_Unbounded_String ("flyology")));
         Headers.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
         Headers.SSE_Customer_Algorithm :=
           US.To_Unbounded_String ("AES256");
         Headers.SSE_KMS_Key_ID := US.To_Unbounded_String ("kms-key");
         Headers.Bucket_Key_Enabled := (Is_Set => True, Value => True);
         Headers.Storage_Class :=
           US.To_Unbounded_String ("INTELLIGENT_TIERING");
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         Headers.Replication_Status := US.To_Unbounded_String ("COMPLETE");
         Headers.Parts_Count := (Is_Set => True, Value => 3);
         Headers.Tag_Count := (Is_Set => True, Value => 4);
         Headers.Object_Lock_Mode := US.To_Unbounded_String ("GOVERNANCE");
         Headers.Object_Lock_Retain_Until_Date :=
           US.To_Unbounded_String ("2027-08-21T00:00:00Z");
         Headers.Object_Lock_Legal_Hold_Status :=
           US.To_Unbounded_String ("ON");
         declare
            Outcome : constant Low_Level.Head_Object_Outcome :=
              Low_Level.Decode_Head_Object_Response (200, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Object_Found
               and then Outcome.Result = Headers,
               "typed HeadObject complete response headers");
         end;
         Headers.Content_Range := US.To_Unbounded_String ("bytes 0-8/9");
         declare
            Outcome : constant Low_Level.Head_Object_Outcome :=
              Low_Level.Decode_Head_Object_Response (206, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Object_Found
               and then Outcome.Result = Headers,
               "typed HeadObject reference 206 compatibility");
         end;
      end;

      declare
         Headers : Low_Level.Head_Object_Result;
         Raised : Boolean := False;
      begin
         Headers.Content_Length := 1;
         Headers.Entity_Tag := US.To_Unbounded_String ("""etag""");
         Headers.Last_Modified :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         begin
            declare
               Ignored : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Decode_Head_Object_Response (200, " ", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "HeadObject accepted a whitespace response body");
      end;

      declare
         Headers : Low_Level.Head_Object_Result;
         Raised : Boolean := False;
      begin
         Headers.Checksum_CRC32 := US.To_Unbounded_String ("not-base64");
         Headers.Entity_Tag := US.To_Unbounded_String ("""etag""");
         Headers.Last_Modified :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         begin
            declare
               Ignored : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Decode_Head_Object_Response (200, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "HeadObject accepted an invalid checksum header");
      end;

      declare
         Headers : Low_Level.Head_Object_Result;

         procedure Expect_Invalid
           (Status  : Flyology.HTTP.Status_Code;
            Value   : Low_Level.Head_Object_Result;
            Message : String)
         is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Head_Object_Outcome :=
                    Low_Level.Decode_Head_Object_Response
                      (Status, "", Value);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            Assert (Raised, Message);
         end Expect_Invalid;
      begin
         Headers.Content_Length := 1;
         Headers.Entity_Tag := US.To_Unbounded_String ("""etag""");
         Headers.Last_Modified :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         Expect_Invalid
           (206, Headers, "HeadObject accepted 206 without Content-Range");
         Headers.Content_Range := US.To_Unbounded_String ("bytes 0-0/1");
         Expect_Invalid
           (200, Headers, "HeadObject accepted unsolicited Content-Range");
         Headers.Content_Range := US.Null_Unbounded_String;
         Headers.Accept_Ranges := US.To_Unbounded_String ("items");
         Expect_Invalid
           (200, Headers, "HeadObject accepted invalid Accept-Ranges");
         Headers.Accept_Ranges := US.Null_Unbounded_String;
         Headers.Last_Modified := US.To_Unbounded_String ("not-a-date");
         Expect_Invalid
           (200, Headers, "HeadObject accepted invalid Last-Modified");
         Headers.Last_Modified :=
           US.To_Unbounded_String ("Fri, 24 May 2013 00:00:00 GMT");
         Headers.Entity_Tag := US.To_Unbounded_String ("bare-etag");
         Expect_Invalid
           (200, Headers, "HeadObject accepted an unquoted ETag");
      end;

      declare
         Headers : Low_Level.Head_Object_Result;
         Outcome : constant Low_Level.Head_Object_Outcome :=
           Low_Level.Decode_Head_Object_Response
             (404, "", Headers, "head-request", "head-host");
      begin
         Assert
           (Outcome.Kind = Low_Level.Head_Object_Rejected
            and then US.To_String (Outcome.Error.Code) = "HTTP404"
            and then US.To_String (Outcome.Error.Request_ID) =
              "head-request",
            "typed HeadObject bodyless error preserves request identifiers");
      end;

      declare
         Headers : Low_Level.Head_Bucket_Result;
         Outcome : constant Low_Level.Head_Bucket_Outcome :=
           Low_Level.Decode_Head_Bucket_Response
             (404, "", Headers, "request-header", "host-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Head_Bucket_Rejected
            and then US.To_String (Outcome.Error.Code) = "HTTP404"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header",
            "HeadBucket preserves status and request identifiers without XML");
      end;

      declare
         Parameters : Low_Level.Create_Bucket_Parameters;
         Raised     : Boolean := False;
      begin
         Parameters.Configuration.Location_Type :=
           US.To_Unbounded_String ("AvailabilityZone");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Create_Bucket
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", Parameters,
                    Identity, "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "incomplete CreateBucket location was accepted");
      end;

      declare
         HTTP : aliased Flyology.HTTP.Client.Client (Capacity => 1);
         Parameters : Low_Level.Head_Bucket_Parameters;
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Head_Bucket
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", Parameters, Identity,
              "us-east-1", "20130524T000000Z");
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Create_Bucket_Outcome :=
                 Low_Level.Execute_Create_Bucket (HTTP, Prepared);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "CreateBucket operation mismatch reached HTTP");
      end;
   end Check_Low_Level_Bucket_Lifecycle;

   procedure Check_Low_Level_Delete_Requests (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package Deletions renames Flyology.Object_Storage.S3.Deletions;
      package US renames Ada.Strings.Unbounded;
      use type Low_Level.Delete_Bucket_Outcome_Kind;
      use type Low_Level.Delete_Object_Outcome_Kind;
      use type Low_Level.Delete_Objects_Outcome_Kind;
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");

      procedure Check_Delete_Checksum
        (Algorithm   : String;
         Header_Name : String)
      is
         Request    : Deletions.Delete_Objects_Request;
         Parameters : Low_Level.Delete_Objects_Parameters;
      begin
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String ("checksum-key"),
               Version_ID => US.Null_Unbounded_String,
               others     => <>));
         Parameters.Checksum_Algorithm :=
           US.To_Unbounded_String (Algorithm);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Objects
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Request,
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
            Canonical : constant String :=
              Low_Level.Canonical_Request (Prepared);
            Signed : constant String :=
              ";" & Low_Level.Signed_Headers (Prepared) & ";";
         begin
            Assert
              (Ada.Strings.Fixed.Index
                 (Signed, ";" & Header_Name & ";") > 0
               and then Ada.Strings.Fixed.Index
                 (Signed, ";x-amz-sdk-checksum-algorithm;") > 0
               and then Ada.Strings.Fixed.Index
                 (Canonical, Header_Name & ":") > 0
               and then Ada.Strings.Fixed.Index
                 (Canonical,
                  "x-amz-sdk-checksum-algorithm:" & Algorithm) > 0,
               "DeleteObjects checksum mapping " & Algorithm);
         end;
      end Check_Delete_Checksum;
   begin
      Check_Delete_Checksum ("CRC32", "x-amz-checksum-crc32");
      Check_Delete_Checksum ("CRC32C", "x-amz-checksum-crc32c");
      Check_Delete_Checksum ("CRC64NVME", "x-amz-checksum-crc64nvme");
      Check_Delete_Checksum ("SHA1", "x-amz-checksum-sha1");
      Check_Delete_Checksum ("SHA256", "x-amz-checksum-sha256");
      Check_Delete_Checksum ("SHA512", "x-amz-checksum-sha512");
      Check_Delete_Checksum ("MD5", "x-amz-checksum-md5");
      Check_Delete_Checksum ("XXHASH64", "x-amz-checksum-xxhash64");
      Check_Delete_Checksum ("XXHASH3", "x-amz-checksum-xxhash3");
      Check_Delete_Checksum ("XXHASH128", "x-amz-checksum-xxhash128");

      declare
         Parameters : Low_Level.Delete_Bucket_Parameters;
      begin
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket"
               and then Low_Level.Signed_Headers (Prepared) =
                 "host;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner",
               "DeleteBucket exact target and modeled signed header");
         end;
      end;

      declare
         procedure Rejects (Query : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Deletions.Delete_Object_Request :=
                    Deletions.Parse_Delete_Object_Query (Query);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Deletions.Malformed_Delete_Object_Request =>
                  Raised := True;
            end;
            Assert (Raised, "malformed DeleteObject query was accepted");
         end Rejects;
         Empty : constant Deletions.Delete_Object_Request :=
           Deletions.Parse_Delete_Object_Query ("");
         Versioned : constant Deletions.Delete_Object_Request :=
           Deletions.Parse_Delete_Object_Query
             ("versionId=v%20%2B%2F%3D&x-id=DeleteObject");
         Literal_Plus : constant Deletions.Delete_Object_Request :=
           Deletions.Parse_Delete_Object_Query ("versionId=a+b");
      begin
         Assert
           (not Empty.Has_Version_ID
            and then Versioned.Has_Version_ID
            and then US.To_String (Versioned.Version_ID) = "v +/=",
            "DeleteObject strict query decoding");
         Assert
           (US.To_String (Literal_Plus.Version_ID) = "a+b",
            "DeleteObject query changed a literal plus into a space");
         Rejects ("versionId=");
         Rejects ("versionId=one&versionId=two");
         Rejects ("versionId=%GG");
         Rejects ("versionId=" & String'(1 .. 1_025 => 'v'));
         Rejects ("versionId=v" & Character'Val (0));
         Rejects ("x-id=WrongOperation");
         Rejects ("unknown=value");
         Rejects ("versionId=one&&x-id=DeleteObject");
      end;

      declare
         Parameters : Low_Level.Delete_Object_Parameters;
      begin
         Parameters.MFA := US.To_Unbounded_String
           ("arn:aws:iam::123456789012:mfa/root 123456");
         Parameters.Version_ID := US.To_Unbounded_String ("v +/=");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Bypass_Governance_Retention :=
           (Is_Set => True, Value => False);
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.If_Match := US.To_Unbounded_String ("""etag""");
         Parameters.If_Match_Last_Modified_Time :=
           US.To_Unbounded_String ("Wed, 21 Oct 2015 07:28:00 GMT");
         Parameters.If_Match_Size := (Is_Set => True, Value => 42);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Object
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/photos/a%20b%2B%25?" &
                 "versionId=v%20%2B%2F%3D",
               "DeleteObject exact encoded target");
            Assert
              (Low_Level.Signed_Headers (Prepared) =
                 "host;if-match;x-amz-bypass-governance-retention;" &
                 "x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;" &
                 "x-amz-if-match-last-modified-time;x-amz-if-match-size;" &
                 "x-amz-mfa;x-amz-request-payer",
               "DeleteObject every modeled request header is signed");
         end;
      end;

      declare
         Headers : Low_Level.Delete_Object_Result;
      begin
         Headers.Delete_Marker := (Is_Set => True, Value => True);
         Headers.Version_ID := US.To_Unbounded_String ("deleted-version");
         Headers.Request_Charged := US.To_Unbounded_String ("requester");
         declare
            Outcome : constant Low_Level.Delete_Object_Outcome :=
              Low_Level.Decode_Delete_Object_Response
                (204, " " & Character'Val (10), Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Object_Deleted
               and then Outcome.Result.Delete_Marker.Is_Set
               and then Outcome.Result.Delete_Marker.Value
               and then US.To_String (Outcome.Result.Version_ID) =
                 "deleted-version",
               "typed DeleteObject success headers");
         end;
      end;

      declare
         Outcome : constant Low_Level.Delete_Bucket_Outcome :=
           Low_Level.Decode_Delete_Bucket_Response
             (409, "<Error><Code>BucketNotEmpty</Code>" &
              "<Message>not empty</Message></Error>", "request-header");
      begin
         Assert
           (Outcome.Kind = Low_Level.Delete_Bucket_Rejected
            and then US.To_String (Outcome.Error.Code) = "BucketNotEmpty"
            and then US.To_String (Outcome.Error.Request_ID) =
              "request-header",
            "typed DeleteBucket error response");
      end;

      declare
         Outcome : constant Low_Level.Delete_Bucket_Outcome :=
           Low_Level.Decode_Delete_Bucket_Response
             (204, " " & Character'Val (10));
      begin
         Assert
           (Outcome.Kind = Low_Level.Bucket_Deleted,
            "typed DeleteBucket success response");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Delete_Bucket_Outcome :=
                 Low_Level.Decode_Delete_Bucket_Response
                   (204, "unexpected");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "DeleteBucket accepted a success response body");
      end;

      declare
         Headers : Low_Level.Delete_Object_Result;
         Raised  : Boolean := False;
      begin
         Headers.Request_Charged := US.To_Unbounded_String ("owner");
         begin
            declare
               Ignored : constant Low_Level.Delete_Object_Outcome :=
                 Low_Level.Decode_Delete_Object_Response (204, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert (Raised, "invalid DeleteObject response header was accepted");
      end;

      declare
         Headers : Low_Level.Delete_Object_Result;
         Raised  : Boolean := False;
      begin
         Headers.Version_ID :=
           US.To_Unbounded_String (String'(1 .. 1_025 => 'v'));
         begin
            declare
               Ignored : constant Low_Level.Delete_Object_Outcome :=
                 Low_Level.Decode_Delete_Object_Response (204, "", Headers);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response => Raised := True;
         end;
         Assert (Raised, "oversized DeleteObject version was accepted");
      end;

      declare
         Parameters : Low_Level.Delete_Object_Parameters;
         Raised     : Boolean := False;
      begin
         Parameters.Request_Payer := US.To_Unbounded_String ("owner");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Object
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "invalid DeleteObject request payer was accepted");
      end;

      declare
         Parameters : Low_Level.Delete_Object_Parameters;
         Raised     : Boolean := False;
      begin
         Parameters.Version_ID :=
           US.To_Unbounded_String (String'(1 .. 1_025 => 'v'));
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Object
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", "key",
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request => Raised := True;
         end;
         Assert (Raised, "oversized DeleteObject version was prepared");
      end;

      declare
         Request : Deletions.Delete_Objects_Request;
         Parameters : Low_Level.Delete_Objects_Parameters;
      begin
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String ("a&b"),
               Version_ID => US.Null_Unbounded_String,
               others     => <>));
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String ("second"),
               Version_ID => US.To_Unbounded_String ("v1"),
               others     => <>));
         Request.Quiet := True;
         Parameters.MFA := US.To_Unbounded_String ("device 123456");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Bypass_Governance_Retention :=
           (Is_Set => True, Value => False);
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         Parameters.Checksum_Algorithm := US.To_Unbounded_String ("SHA256");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Objects
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Request,
                 Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Canonical : constant String :=
              Low_Level.Canonical_Request (Prepared);
         begin
            Assert
              (Low_Level.Target (Prepared) = "/example-bucket?delete",
               "DeleteObjects exact subresource target");
            Assert
              (Low_Level.Signed_Headers (Prepared) =
                 "content-md5;host;x-amz-bypass-governance-retention;" &
                 "x-amz-checksum-sha256;x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;x-amz-mfa;" &
                 "x-amz-request-payer;x-amz-sdk-checksum-algorithm"
               and then Ada.Strings.Fixed.Index
                 (Canonical, "content-md5:oHu1qjgIzoBt4qEk27Rx2Q==") > 0
               and then Ada.Strings.Fixed.Index
                 (Canonical, "x-amz-checksum-sha256:") > 0
               and then Ada.Strings.Fixed.Index
                 (Canonical, "x-amz-sdk-checksum-algorithm:SHA256") > 0,
               "DeleteObjects Content-MD5 and modeled headers are signed");
         end;
      end;

      declare
         Request : Deletions.Delete_Objects_Request;
         Parameters : Low_Level.Delete_Objects_Parameters;
         Raised : Boolean := False;
      begin
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String ("key"),
               Version_ID => US.Null_Unbounded_String,
               others     => <>));
         Parameters.Checksum_Algorithm := US.To_Unbounded_String ("sha256");
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Objects
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", Request,
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "invalid DeleteObjects checksum algorithm prepared");
      end;

      declare
         Outcome : constant Low_Level.Delete_Objects_Outcome :=
           Low_Level.Decode_Delete_Objects_Response
             (200,
              "<DeleteResult><Deleted><Key>a&amp;b</Key></Deleted>" &
              "<Error><Key>locked</Key><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error></DeleteResult>",
              "requester");
      begin
         Assert
           (Outcome.Kind = Low_Level.Objects_Deleted
            and then Outcome.Result.Result.Deleted.Length = 1
            and then Outcome.Result.Result.Errors.Length = 1
            and then US.To_String
              (Outcome.Result.Result.Deleted.First_Element.Key) = "a&b"
            and then US.To_String (Outcome.Result.Request_Charged) =
              "requester",
            "typed DeleteObjects success response");
      end;

      declare
         Outcome : constant Low_Level.Delete_Objects_Outcome :=
           Low_Level.Decode_Delete_Objects_Response
             (403, "<Error><Code>AccessDenied</Code>" &
              "<Message>denied</Message></Error>", Request_ID => "request");
      begin
         Assert
           (Outcome.Kind = Low_Level.Delete_Objects_Rejected
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request",
            "typed DeleteObjects error response");
      end;

      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Delete_Objects_Outcome :=
                 Low_Level.Decode_Delete_Objects_Response
                   (200, "<DeleteResult/>", "owner");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Raised := True;
         end;
         Assert
           (Raised, "invalid DeleteObjects response header was accepted");
      end;

      declare
         HTTP : aliased Flyology.HTTP.Client.Client (Capacity => 1);
         Parameters : Low_Level.Delete_Object_Parameters;
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Delete_Object
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", "key", Parameters,
              Identity, "us-east-1", "20130524T000000Z");
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Delete_Objects_Outcome :=
                 Low_Level.Execute_Delete_Objects (HTTP, Prepared);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "DeleteObjects operation mismatch reached HTTP");
      end;

      declare
         HTTP : aliased Flyology.HTTP.Client.Client (Capacity => 1);
         Parameters : Low_Level.Delete_Bucket_Parameters;
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Delete_Bucket
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", Parameters, Identity,
              "us-east-1", "20130524T000000Z");
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Delete_Object_Outcome :=
                 Low_Level.Execute_Delete_Object (HTTP, Prepared);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, "DeleteObject operation mismatch reached HTTP");
      end;
   end Check_Low_Level_Delete_Requests;

   procedure Check_Generated_S3_Model (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Model renames Flyology.Object_Storage.S3.Model;
      use type Model.Shape_Kind;
      Seen_Operations : Natural := 0;
      Seen_Shapes     : Natural := 0;
   begin
      for Operation in Model.Operation_Id loop
         Seen_Operations := Seen_Operations + 1;
         declare
            Input  : constant Model.Shape_Reference :=
              Model.Input_Shape (Operation);
            Output : constant Model.Shape_Reference :=
              Model.Output_Shape (Operation);
         begin
            Assert
              (Model.Operation_Name (Operation)'Length > 0,
               "empty generated operation name");
            Assert
              (Model.Request_URI (Operation)'Length > 0
               and then Model.Request_URI (Operation)
                 (Model.Request_URI (Operation)'First) = '/',
               "invalid generated operation URI");
            Assert
              (Model.Response_Code (Operation) in 100 .. 599,
               "invalid generated response code");
            if Input /= Model.No_Shape then
               Assert
                 (Model.Shape_Name (Model.Shape_Index (Input))'Length > 0,
                  "invalid generated input shape reference");
            end if;
            if Output /= Model.No_Shape then
               Assert
                 (Model.Shape_Name (Model.Shape_Index (Output))'Length > 0,
                  "invalid generated output shape reference");
            end if;
            if Model.Error_Count (Operation) > 0 then
               for Index in 1 .. Model.Error_Count (Operation) loop
                  Assert
                    (Model.Error_Shape (Operation, Index) /= Model.No_Shape,
                     "invalid generated error shape reference");
               end loop;
            end if;
         end;
      end loop;

      for Shape in Model.Shape_Index loop
         Seen_Shapes := Seen_Shapes + 1;
         Assert
           (Model.Shape_Name (Shape)'Length > 0,
            "empty generated shape name");
         case Model.Kind (Shape) is
            when Model.List_Shape =>
               Assert
                 (Model.List_Member_Shape (Shape) /= Model.No_Shape,
                  "list shape lacks member shape");
            when Model.Map_Shape =>
               Assert
                 (Model.Map_Key_Shape (Shape) /= Model.No_Shape
                  and then Model.Map_Value_Shape (Shape) /= Model.No_Shape,
                  "map shape lacks key or value shape");
            when others =>
               Assert
                 (Model.List_Member_Shape (Shape) = Model.No_Shape
                  and then Model.Map_Key_Shape (Shape) = Model.No_Shape
                  and then Model.Map_Value_Shape (Shape) = Model.No_Shape,
                  "non-container shape has container references");
         end case;

         if Model.Enumeration_Count (Shape) > 0 then
            for Left in 1 .. Model.Enumeration_Count (Shape) loop
               Assert
                 (Model.Enumeration_Value (Shape, Left)'Length > 0,
                  "empty generated enumeration value");
               for Right in Left + 1 .. Model.Enumeration_Count (Shape) loop
                  Assert
                    (Model.Enumeration_Value (Shape, Left) /=
                       Model.Enumeration_Value (Shape, Right),
                     "duplicate generated enumeration value");
               end loop;
            end loop;
         end if;

         if Model.Member_Count (Shape) > 0 then
            for Member in 1 .. Model.Member_Count (Shape) loop
               Assert
                 (Model.Member_Name (Shape, Member)'Length > 0
                  and then Model.Member_Location_Name
                    (Shape, Member)'Length > 0,
                  "invalid generated member name");
               Assert
                 (Model.Shape_Name
                    (Model.Member_Shape (Shape, Member))'Length > 0,
                  "invalid generated member shape reference");
               for Other in Member + 1 .. Model.Member_Count (Shape) loop
                  Assert
                    (Model.Member_Name (Shape, Member) /=
                       Model.Member_Name (Shape, Other),
                     "duplicate generated member name");
               end loop;
            end loop;
         end if;
      end loop;

      Assert
        (Seen_Operations = Model.Operation_Count,
         "generated S3 operation traversal count");
      Assert
        (Seen_Shapes = Model.Shape_Count,
         "generated S3 shape traversal count");

      Assert
        (Model.Operation_Name (Model.Write_Get_Object_Response_Operation) =
           "WriteGetObjectResponse"
         and then Model.Unsigned_Payload
           (Model.Write_Get_Object_Response_Operation)
         and then Model.Authentication_Type
           (Model.Write_Get_Object_Response_Operation) = "v4-unsigned-body",
         "special unsigned S3 operation traits changed");
   end Check_Generated_S3_Model;

   procedure Check_Model_Request_Projection (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package Model renames Flyology.Object_Storage.S3.Model;
      package SigV4 renames Flyology.Object_Storage.S3.SigV4;
      package US renames Ada.Strings.Unbounded;
      use type Model.Member_Location;
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
      Seen : Natural := 0;

      function Sample
        (Member_Name : String; Shape : Model.Shape_Index) return String
      is
      begin
         if Member_Name = "Bucket" then
            return "example-bucket";
         elsif Member_Name = "Key" then
            return "key/path";
         elsif Member_Name = "ContentLength" then
            return "9";
         elsif Member_Name = "CopySource"
           or else Member_Name = "RenameSource"
         then
            return "/source-bucket/source-key";
         elsif Model.Enumeration_Count (Shape) > 0 then
            return Model.Enumeration_Value (Shape, 1);
         end if;
         case Model.Kind (Shape) is
            when Model.Boolean_Shape =>
               return "true";
            when Model.Integer_Shape | Model.Long_Shape =>
               return "1";
            when Model.Timestamp_Shape =>
               return "Wed, 21 Oct 2015 07:28:00 GMT";
            when Model.List_Shape =>
               return Model.Enumeration_Value
                 (Model.Shape_Index (Model.List_Member_Shape (Shape)), 1);
            when others =>
               return "sample";
         end case;
      end Sample;

      function Item
        (Name, Value : String; Map_Key : String := "")
         return Low_Level.Model_Value is
        ((Member_Name => US.To_Unbounded_String (Name),
          Map_Key     => US.To_Unbounded_String (Map_Key),
          Value       => US.To_Unbounded_String (Value)));

      procedure Expect_Invalid
        (Operation      : Model.Operation_Id;
         Values         : Low_Level.Model_Value_Array;
         Label          : String;
         Payload        : String := "";
         Payload_Is_Set : Boolean := False)
      is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Model_Request
                   (Operation, Flyology.HTTP.Parse_Origin
                      ("https://localhost:9000"),
                    Low_Level.Path_Style, Values, Payload,
                    Payload_Is_Set, "", Identity, "us-east-1",
                    "20130524T000000Z");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Assert (Raised, Label);
      end Expect_Invalid;
   begin
      for Operation in Model.Operation_Id loop
         declare
            Input_Reference : constant Model.Shape_Reference :=
              Model.Input_Shape (Operation);
            Input_Shape : constant Model.Shape_Index :=
              (if Input_Reference = Model.No_Shape
               then Model.Shape_Index'First
               else Model.Shape_Index (Input_Reference));
            Count : Natural := 0;
            Has_Body : Boolean := False;
         begin
            if Input_Reference /= Model.No_Shape
              and then Model.Member_Count (Input_Shape) > 0
            then
               for Member in 1 .. Model.Member_Count (Input_Shape) loop
                  if Model.Location (Input_Shape, Member) =
                    Model.Body_Location
                  then
                     Has_Body := True;
                  else
                     Count := Count + 1;
                  end if;
               end loop;
            end if;
            declare
               Values : Low_Level.Model_Value_Array (1 .. Count);
               Last : Natural := 0;
            begin
               if Input_Reference /= Model.No_Shape
                 and then Model.Member_Count (Input_Shape) > 0
               then
                  for Member in 1 .. Model.Member_Count (Input_Shape) loop
                     if Model.Location (Input_Shape, Member) /=
                       Model.Body_Location
                     then
                        Last := Last + 1;
                        Values (Last).Member_Name := US.To_Unbounded_String
                          (Model.Member_Name (Input_Shape, Member));
                        if Model.Location (Input_Shape, Member) =
                          Model.Headers_Location
                        then
                           Values (Last).Map_Key :=
                             US.To_Unbounded_String ("sample");
                        end if;
                        Values (Last).Value := US.To_Unbounded_String
                          (Sample
                             (Model.Member_Name (Input_Shape, Member),
                              Model.Member_Shape (Input_Shape, Member)));
                     end if;
                  end loop;
               end if;
               begin
                  declare
                     Prepared : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Model_Request
                         (Operation      => Operation,
                          Origin         => Flyology.HTTP.Parse_Origin
                            ("https://localhost:9000"),
                          Style          => Low_Level.Path_Style,
                          Values         => Values,
                          Payload        =>
                            (if Has_Body then "<sample/>" else ""),
                          Payload_Is_Set => Has_Body,
                          Payload_SHA256 => "",
                          Identity       => Identity,
                          Region         => "us-east-1",
                          Timestamp      => "20130524T000000Z");
                  begin
                     Assert
                       (Low_Level.Target (Prepared)'Length > 0
                        and then Low_Level.Target (Prepared)
                          (Low_Level.Target (Prepared)'First) = '/'
                        and then Low_Level.Canonical_Request
                          (Prepared)'Length > 0,
                        "empty model projection for " &
                          Model.Operation_Name (Operation));
                  end;
               exception
                  when Occurrence : others =>
                     Assert
                       (False,
                        "model projection failed for " &
                          Model.Operation_Name (Operation) & ": " &
                          Ada.Exceptions.Exception_Message (Occurrence));
               end;
            end;
            Seen := Seen + 1;
         end;
      end loop;
      Assert (Seen = Model.Operation_Count, "model request traversal count");

      declare
         Values : Low_Level.Model_Value_Array (1 .. 1);
      begin
         Values (1).Member_Name := US.To_Unbounded_String ("Bucket");
         Values (1).Value := US.To_Unbounded_String ("example-bucket");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Request
                (Operation      => Model.Create_Bucket_Operation,
                 Origin         => Flyology.HTTP.Parse_Origin
                   ("https://example-bucket.localhost:9000"),
                 Style          => Low_Level.Virtual_Hosted_Style,
                 Values         => Values,
                 Payload        => "",
                 Payload_Is_Set => False,
                 Payload_SHA256 => "",
                 Identity       => Identity,
                 Region         => "us-east-1",
                 Timestamp      => "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) = "/",
               "virtual-hosted generated bucket projection");
         end;
      end;

      declare
         Values : Low_Level.Model_Value_Array (1 .. 2);
      begin
         Values (1).Member_Name := US.To_Unbounded_String ("Bucket");
         Values (1).Value := US.To_Unbounded_String ("example-bucket");
         Values (2).Member_Name := US.To_Unbounded_String ("Key");
         Values (2).Value :=
           US.To_Unbounded_String ("high level+file%25");
         declare
            Expected_Path : constant String :=
              "/example-bucket/high%20level%2Bfile%2525";
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Streaming_Request
                (Operation      => Model.Put_Object_Operation,
                 Origin         => Flyology.HTTP.Parse_Origin
                   ("https://localhost:9000"),
                 Style          => Low_Level.Path_Style,
                 Values         => Values,
                 Payload_SHA256 => SigV4.SHA256_Hex ("x"),
                 Identity       => Identity,
                 Region         => "us-east-1",
                 Timestamp      => "20130524T000000Z");
            Canonical : constant String :=
              Low_Level.Canonical_Request (Prepared);
         begin
            Assert
              (Low_Level.Target (Prepared) = Expected_Path,
               "generic streaming URI member was not encoded exactly once");
            Assert
              (Ada.Strings.Fixed.Index
                 (Canonical,
                  "PUT" & Character'Val (10) & Expected_Path
                  & Character'Val (10)) = Canonical'First,
               "generic streaming canonical path was double encoded");
         end;
      end;

      declare
         Values : Low_Level.Model_Value_Array (1 .. 2);
      begin
         Values (1).Member_Name := US.To_Unbounded_String ("Bucket");
         Values (1).Value := US.To_Unbounded_String ("example-bucket");
         Values (2).Member_Name := US.To_Unbounded_String ("Key");
         Values (2).Value := US.To_Unbounded_String ("key/path");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Request
                (Operation      => Model.Select_Object_Content_Operation,
                 Origin         => Flyology.HTTP.Parse_Origin
                   ("https://localhost:9000"),
                 Style          => Low_Level.Path_Style,
                 Values         => Values,
                 Payload        => "<SelectObjectContentRequest/>",
                 Payload_Is_Set => True,
                 Payload_SHA256 => "",
                 Identity       => Identity,
                 Region         => "us-east-1",
                 Timestamp      => "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket/key/path?select&select-type=2",
               "generated fixed multi-query projection");
         end;
      end;

      declare
         Values : Low_Level.Model_Value_Array (1 .. 1);
      begin
         Values (1) := Item ("Unknown", "value");
         Expect_Invalid
           (Model.List_Buckets_Operation, Values,
            "unknown generated model member was accepted");
      end;

      Expect_Invalid
        (Model.Head_Bucket_Operation, Low_Level.No_Model_Values,
         "missing required URI member was accepted");

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (Item ("Bucket", "example-bucket"),
            Item ("Bucket", "example-bucket"));
      begin
         Expect_Invalid
           (Model.Head_Bucket_Operation, Values,
            "duplicate generated scalar member was accepted");
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (1 => Item ("Bucket", "example-bucket"));
      begin
         Expect_Invalid
           (Model.Head_Bucket_Operation, Values,
            "raw body on a bodyless operation was accepted", "x", True);
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (1 => Item ("MaxBuckets", "0"));
      begin
         Expect_Invalid
           (Model.List_Directory_Buckets_Operation, Values,
            "modeled integer minimum was not enforced");
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (Item ("Bucket", "example-bucket"),
            Item ("Key", "key"),
            Item ("CopySource", "missing-slash"));
      begin
         Expect_Invalid
           (Model.Copy_Object_Operation, Values,
            "modeled source path pattern was not enforced");
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (Item ("Bucket", "example-bucket"),
            Item ("Key", "key"),
            Item ("StorageClass", "NOT_A_STORAGE_CLASS"));
      begin
         Expect_Invalid
           (Model.Put_Object_Operation, Values,
            "modeled enumeration was not enforced", "x", True);
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (Item ("Bucket", "example-bucket"),
            Item ("Key", "key"),
            Item ("ContentLength", "2"));
      begin
         Expect_Invalid
           (Model.Put_Object_Operation, Values,
            "mismatched modeled content length was accepted", "x", True);
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (Item ("Bucket", "example-bucket"),
            Item ("Key", "key"),
            Item ("Metadata", "first", "duplicate"),
            Item ("Metadata", "second", "DUPLICATE"));
      begin
         Expect_Invalid
           (Model.Put_Object_Operation, Values,
            "case-insensitive duplicate metadata key was accepted",
            "x", True);
      end;

      declare
         Values : constant Low_Level.Model_Value_Array :=
           (Item ("Bucket", "example-bucket"),
            Item ("Key", "key"),
            Item ("ObjectAttributes", "ETag,INVALID"));
      begin
         Expect_Invalid
           (Model.Get_Object_Attributes_Operation, Values,
            "invalid generated header-list element was accepted");
      end;
   end Check_Model_Request_Projection;

   procedure Check_SigV4_Verification (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package SigV4 renames Flyology.Object_Storage.S3.SigV4;
      package Verification renames
        Flyology.Object_Storage.S3.SigV4_Verification;
      package US renames Ada.Strings.Unbounded;
      use type Verification.Parse_Status;
      Query : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("a b", "+"), SigV4.Pair ("empty", ""));
      Headers : constant SigV4.Name_Value_Array :=
        (SigV4.Pair ("host", "localhost:9000"),
         SigV4.Pair ("x-amz-content-sha256", SigV4.Empty_Payload_Hash),
         SigV4.Pair ("x-amz-date", "20130524T000000Z"));
      Request_Target : constant String :=
        "/example-bucket/key%20name%2Bpercent%2525?a%20b=%2B&empty";
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        ("GET", "/example-bucket/key name+percent%25", Query, Headers,
         SigV4.Empty_Payload_Hash, "AKIDEXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "us-east-1",
         "20130524T000000Z");
      Parsed : constant Verification.Parse_Result := Verification.Parse
        (US.To_String (Signing.Authorization));

      procedure Rejects (Authorization, Label : String) is
      begin
         Assert
           (Verification.Parse (Authorization).Status /= Verification.Parsed,
            Label);
      end Rejects;
   begin
      Assert
        (Parsed.Status = Verification.Parsed,
         "valid SigV4 did not parse");
      Assert
        (Verification.Access_Key (Parsed.Data) = "AKIDEXAMPLE"
         and then Verification.Scope_Date (Parsed.Data) = "20130524"
         and then Verification.Region (Parsed.Data) = "us-east-1"
         and then Verification.Service (Parsed.Data) = "s3"
         and then Verification.Signed_Header_Count (Parsed.Data) = 3
         and then Verification.Header_Is_Signed (Parsed.Data, "HOST"),
         "parsed SigV4 fields mismatch");
      Assert
        (Verification.Verify
           (Parsed.Data, "GET", Request_Target, Headers,
            SigV4.Empty_Payload_Hash,
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
         "valid SigV4 request did not verify");
      Assert
        (not Verification.Verify
           (Parsed.Data, "PUT", Request_Target, Headers,
            SigV4.Empty_Payload_Hash,
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")
         and then not Verification.Verify
           (Parsed.Data, "GET",
            "/example-bucket/other?a%20b=%2B&empty", Headers,
            SigV4.Empty_Payload_Hash,
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")
         and then not Verification.Verify
           (Parsed.Data, "GET", Request_Target, Headers,
            SigV4.Empty_Payload_Hash,
            "wrong-secret"),
         "tampered SigV4 request verified");
      Assert
        (not Verification.Verify
           (Parsed.Data, "GET", Request_Target, Headers,
            String'(1 .. 64 => '0'),
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
         "payload hash parameter diverged from its signed header");
      Assert
        (not Verification.Verify
           (Parsed.Data, "GET", "/example-bucket/key?bad=%GG", Headers,
            SigV4.Empty_Payload_Hash,
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
         "malformed query escape verified");
      Assert
        (not Verification.Verify
           (Parsed.Data, "GET", "/example-bucket/%GG", Headers,
            SigV4.Empty_Payload_Hash,
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
         "malformed path escape verified");

      declare
         Plus_Query : constant SigV4.Name_Value_Array :=
           (1 => SigV4.Pair ("a+b", "+"));
         Plus_Signing : constant SigV4.Signing_Result := SigV4.Sign
           ("GET", "/bucket", Plus_Query, Headers,
            SigV4.Empty_Payload_Hash, "AKIDEXAMPLE",
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "us-east-1",
            "20130524T000000Z");
         Plus_Parsed : constant Verification.Parse_Result :=
           Verification.Parse (US.To_String (Plus_Signing.Authorization));
      begin
         Assert
           (Plus_Parsed.Status = Verification.Parsed
            and then Verification.Verify
              (Plus_Parsed.Data, "GET", "/bucket?a+b=%2B", Headers,
               SigV4.Empty_Payload_Hash,
               "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
            "SigV4 query plus was treated as form-space");
      end;

      Rejects ("", "missing Authorization accepted");
      Rejects
        ("AWS3 Credential=AKID/20130524/us-east-1/s3/aws4_request," &
         "SignedHeaders=host;x-amz-content-sha256;x-amz-date," &
         "Signature=" & String'(1 .. 64 => '0'),
         "unsupported SigV4 algorithm accepted");
      Rejects
        ("AWS4-HMAC-SHA256 Credential=AKID/20130524/us-east-1/s3/" &
         "aws4_request,SignedHeaders=x-amz-date;host;" &
         "x-amz-content-sha256,Signature=" & String'(1 .. 64 => '0'),
         "unsorted signed headers accepted");
      Rejects
        ("AWS4-HMAC-SHA256 Credential=AKID/20130524/us-east-1/s3/" &
         "aws4_request,SignedHeaders=host;x-amz-date,Signature=" &
         String'(1 .. 64 => '0'),
         "missing required content hash signature accepted");
      Rejects
        ("AWS4-HMAC-SHA256 Credential=AKID/20130524/us-east-1/s3/" &
         "bad,SignedHeaders=host;x-amz-content-sha256;x-amz-date," &
         "Signature=" & String'(1 .. 64 => '0'),
         "invalid credential terminator accepted");
      Rejects
        ("AWS4-HMAC-SHA256 Credential=AKID/20130524/us-east-1/s3/" &
         "aws4_request,SignedHeaders=host;x-amz-content-sha256;" &
         "x-amz-date,Signature=" & String'(1 .. 64 => 'A'),
         "uppercase signature accepted");
      Rejects
        (US.To_String (Signing.Authorization) & ",Unknown=value",
         "unknown Authorization attribute accepted");
   end Check_SigV4_Verification;

   procedure Exercise_Object_Tagging
     (Store : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String)
   is
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String ("tagged body"),
         Position => 0, Length => (Kind => Known, Bytes => 11),
         Bad_Last => False);
      Replacement : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String ("replacement"),
         Position => 0, Length => (Kind => Known, Bytes => 11),
         Bad_Last => False);
      Info : Object_Information;
      Result : Status;
      Tags : Object_Tag_Set;
      Wanted : Object_Tag_Set;
   begin
      Store.Get_Object_Tags
        ("missing-tag-bucket", "key", null, Ada.Real_Time.Time_Last,
         Tags, Result);
      Assert (Result = Bucket_Not_Found, "tagging missing bucket status");
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "tagging create bucket");
      Store.Put_Object
        (Bucket, "tagged/key", Source, Default_Put_Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Assert (Result = Success, "tagging put object");
      Store.Get_Object_Tags
        (Bucket, "tagged/key", null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags.Length = 0,
         "new object did not start with an empty tag set");

      Wanted.Length := 2;
      Wanted.Items (1) :=
        (Key => US.To_Unbounded_String ("environment"),
         Value => US.To_Unbounded_String ("production"));
      Wanted.Items (2) :=
        (Key => US.To_Unbounded_String ("team"),
         Value => US.To_Unbounded_String ("storage/core"));
      Store.Put_Object_Tags
        (Bucket, "tagged/key", Wanted, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "tagging atomic replace");
      Store.Get_Object_Tags
        (Bucket, "tagged/key", null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags = Wanted,
         "tagging atomic read did not preserve order and values");

      Store.Put_Object
        (Bucket, "tagged/key", Replacement, Default_Put_Options, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Store.Get_Object_Tags
        (Bucket, "tagged/key", null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags.Length = 0,
         "object overwrite retained stale tags");
      Store.Put_Object_Tags
        (Bucket, "tagged/key", Wanted, null, Ada.Real_Time.Time_Last, Result);
      Store.Delete_Object_Tags
        (Bucket, "tagged/key", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "tagging delete");
      Store.Get_Object_Tags
        (Bucket, "tagged/key", null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags.Length = 0,
         "tagging delete did not clear complete set");

      Wanted.Items (2).Key := Wanted.Items (1).Key;
      Store.Put_Object_Tags
        (Bucket, "tagged/key", Wanted, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Invalid_Request, "duplicate direct backend tag keys");
      Store.Get_Object_Tags
        (Bucket, "missing", null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert (Result = Not_Found, "tagging missing object status");
      Store.Delete_Object
        (Bucket, "tagged/key", null, Ada.Real_Time.Time_Last, Result);
      Store.Delete_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "tagging cleanup");
   end Exercise_Object_Tagging;

   procedure Check_Backend_Object_Tagging (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      package Files renames Flyology.Object_Storage.Backends.Files;
      Root : constant String := Ada.Directories.Compose
        (Ada.Directories.Compose (Ada.Directories.Current_Directory, "obj"),
         "files-object-tagging");
   begin
      declare
         Store : Memory.Store (2, 4, 128);
      begin
         Exercise_Object_Tagging (Store, "memory-tag-bucket");
      end;
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      declare
         Store : Files.Store := Files.Open
           (Root, Commit => Files.Process_Crash_Atomic);
      begin
         Exercise_Object_Tagging (Store, "files-tag-bucket");
      end;
      Ada.Directories.Delete_Tree (Root);
   end Check_Backend_Object_Tagging;

   procedure Check_Object_Tagging_Codec (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Tagging renames Flyology.Object_Storage.S3.Tagging;
      package US renames Ada.Strings.Unbounded;
      use type Tagging.Tagging_Operation;
      use type Flyology.Object_Storage.Object_Tag_Set;
      Tags : constant Flyology.Object_Storage.Object_Tag_Set :=
        Tagging.Parse
          ("<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
           "<TagSet><Tag><Key>a_b</Key><Value>x+y</Value></Tag>" &
           "<Tag><Key>team</Key><Value>storage/core</Value></Tag>" &
           "</TagSet></Tagging>");

      procedure Rejects (Document : String; Label : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Flyology.Object_Storage.Object_Tag_Set :=
                 Tagging.Parse (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Tagging.Malformed_Tagging =>
               Raised := True;
         end;
         Assert (Raised, Label);
      end Rejects;

      procedure Rejects_Query (Query : String; Label : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Tagging.Tagging_Query :=
                 Tagging.Parse_Query (Query, Tagging.Get_Object_Tagging);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Tagging.Malformed_Tagging_Query =>
               Raised := True;
         end;
         Assert (Raised, Label);
      end Rejects_Query;
   begin
      Assert
        (Tags.Length = 2
         and then US.To_String (Tags.Items (1).Value) = "x+y"
         and then Tagging.Parse (Tagging.Serialize (Tags)) = Tags,
         "object tagging XML round trip");
      declare
         Query : constant Tagging.Tagging_Query := Tagging.Parse_Query
           ("versionId=v%20%2B%2F%3D&tagging=&x-id=GetObjectTagging",
            Tagging.Get_Object_Tagging);
      begin
         Assert
           (Query.Has_Version_ID
            and then US.To_String (Query.Version_ID) = "v +/=",
            "object tagging query decode");
      end;
      declare
         Query : constant Tagging.Tagging_Query := Tagging.Parse_Query
           ("%74agging", Tagging.Get_Object_Tagging);
      begin
         Assert
           (not Query.Has_Version_ID,
            "percent-encoded tagging subresource was not recognized");
      end;
      Rejects ("<Tagging><TagSet><Tag><Key>a</Key></Tag></TagSet></Tagging>",
               "tag missing Value accepted");
      Rejects
        ("<Tagging><TagSet><Tag><Value>x</Value><Key>a</Key></Tag>" &
         "</TagSet></Tagging>", "reversed tag fields accepted");
      Rejects
        ("<Tagging><TagSet><Tag><Key>a</Key><Value>!</Value></Tag>" &
         "</TagSet></Tagging>", "invalid tag character accepted");
      Rejects
        ("<Tagging><TagSet><Tag><Key></Key><Value>x</Value></Tag>" &
         "</TagSet></Tagging>", "empty tag key accepted");
      Rejects
        ("<Tagging><TagSet><Tag><Key>" & String'(1 .. 129 => 'a') &
         "</Key><Value>x</Value></Tag></TagSet></Tagging>",
         "overlong Unicode tag key accepted");
      Rejects
        ("<Tagging><TagSet><Tag><Key>a" & Character'Val (255) &
         "</Key><Value>x</Value></Tag></TagSet></Tagging>",
         "invalid UTF-8 tag key accepted");
      Rejects
        ("<Tagging><TagSet><Tag><Key>a</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a</Key><Value>y</Value></Tag></TagSet></Tagging>",
         "duplicate tag keys accepted");
      Rejects
        ("<Tagging><TagSet>" &
         "<Tag><Key>a1</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a2</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a3</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a4</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a5</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a6</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a7</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a8</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a9</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a10</Key><Value>x</Value></Tag>" &
         "<Tag><Key>a11</Key><Value>x</Value></Tag>" &
         "</TagSet></Tagging>", "eleven object tags accepted");
      Rejects
        ("<Tagging><TagSet>" & String'(1 .. 16 * 1_024 => ' ') &
         "</TagSet></Tagging>", "oversized tagging document accepted");
      Rejects
        ("<!DOCTYPE x><Tagging><TagSet/></Tagging>",
         "object tagging DTD accepted");
      Rejects
        ("<Tagging><TagSet><Other/></TagSet></Tagging>",
         "unknown tagging element accepted");
      Rejects_Query ("versionId=x", "missing tagging subresource accepted");
      Rejects_Query ("tagging&tagging=", "duplicate tagging accepted");
      Rejects_Query ("tagging&unknown=x", "unknown tagging query accepted");
      Rejects_Query ("tagging&versionId=%GG", "bad tagging escape accepted");
      Rejects_Query
        ("tagging&versionId=a&versionId=b",
         "duplicate tagging version ID accepted");
      Rejects_Query
        ("tagging&x-id=GetObjectTagging&x-id=GetObjectTagging",
         "duplicate tagging operation ID accepted");
      Rejects_Query
        ("tagging=" & String'(1 .. 8 * 1_024 => 'x'),
         "oversized tagging query accepted");
   end Check_Object_Tagging_Codec;

   procedure Check_Low_Level_Object_Tagging (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package US renames Ada.Strings.Unbounded;
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Tags : Flyology.Object_Storage.Object_Tag_Set;
   begin
      Tags.Length := 1;
      Tags.Items (1) :=
        (Key => US.To_Unbounded_String ("team"),
         Value => US.To_Unbounded_String ("storage"));
      Parameters.Expected_Bucket_Owner := US.To_Unbounded_String ("owner");
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object_Tagging
             (Flyology.HTTP.Parse_Origin ("https://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", "key with space", Tags,
              Parameters, Identity, "us-east-1", "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/example-bucket/key%20with%20space?tagging"
            and then Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared), "content-md5") /= 0
            and then Ada.Strings.Fixed.Index
              (Low_Level.Canonical_Request (Prepared),
               "x-amz-expected-bucket-owner:owner") /= 0,
            "typed PutObjectTagging projection and signing");
      end;
   end Check_Low_Level_Object_Tagging;

   procedure Check_Bucket_Versioning (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      use AUnit.Assertions;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package Files renames Flyology.Object_Storage.Backends.Files;
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
      package Versioning renames
        Flyology.Object_Storage.S3.Versioning;
      package US renames Ada.Strings.Unbounded;
      use type Low_Level.Get_Bucket_Versioning_Outcome_Kind;
      use type Low_Level.Put_Bucket_Versioning_Outcome_Kind;

      procedure Exercise
        (Store : in out Flyology.Object_Storage.Backends.Backend'Class)
      is
         Result : Status;
         Value  : Bucket_Versioning_Configuration;
      begin
         Store.Create_Bucket
           ("versioning-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "versioning test bucket create failed");
         Store.Get_Bucket_Versioning
           ("versioning-bucket", null, Ada.Real_Time.Time_Last,
            Value, Result);
         Assert
           (Result = Success
            and then Value.Status = Versioning_Unconfigured
            and then Value.MFA_Delete = MFA_Delete_Unconfigured,
            "new bucket did not report unconfigured versioning");
         Store.Put_Bucket_Versioning
           ("versioning-bucket",
            (Status => Versioning_Enabled,
             MFA_Delete => MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "enabling versioning failed");
         Store.Put_Bucket_Versioning
           ("versioning-bucket",
            (Status => Versioning_Unconfigured,
             MFA_Delete => MFA_Delete_Disabled),
            null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "MFA-delete update failed");
         Store.Get_Bucket_Versioning
           ("versioning-bucket", null, Ada.Real_Time.Time_Last,
            Value, Result);
         Assert
           (Result = Success
            and then Value.Status = Versioning_Enabled
            and then Value.MFA_Delete = MFA_Delete_Disabled,
            "atomic independent versioning fields did not merge");
         Store.Put_Bucket_Versioning
           ("versioning-bucket",
            (Status => Versioning_Suspended,
             MFA_Delete => MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Result);
         Store.Get_Bucket_Versioning
           ("versioning-bucket", null, Ada.Real_Time.Time_Last,
            Value, Result);
         Assert
           (Result = Success
            and then Value.Status = Versioning_Suspended
            and then Value.MFA_Delete = MFA_Delete_Disabled,
            "suspension discarded independent MFA-delete state");
         Store.Get_Bucket_Versioning
           ("missing-bucket", null, Ada.Real_Time.Time_Last,
            Value, Result);
         Assert
           (Result = Not_Found
            and then Value.Status = Versioning_Unconfigured,
            "missing bucket versioning classification");
      end Exercise;

      procedure Expect_Malformed (Document, Label : String) is
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Bucket_Versioning_Configuration :=
                 Versioning.Parse (Document);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Versioning.Malformed_Configuration =>
               Raised := True;
         end;
         Assert (Raised, Label);
      end Expect_Malformed;

      Identity : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials
          ("AKIAIOSFODNN7EXAMPLE",
           "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
      Root : constant String := "obj/versioning-files";
      Versioning_Start : constant String :=
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">";
      Versioning_End : constant String := "</VersioningConfiguration>";
   begin
      for Current_Status in Bucket_Versioning_Status loop
         for Current_MFA in MFA_Delete_Status loop
            for Update_Status in Bucket_Versioning_Status loop
               for Update_MFA in MFA_Delete_Status loop
                  declare
                     Current : constant
                       Bucket_Versioning_Configuration :=
                         (Status => Current_Status,
                          MFA_Delete => Current_MFA);
                     Update : constant
                       Bucket_Versioning_Configuration :=
                         (Status => Update_Status,
                          MFA_Delete => Update_MFA);
                     Merged : constant
                       Bucket_Versioning_Configuration :=
                         Merge_Bucket_Versioning (Current, Update);
                  begin
                     Assert
                       (Merged.Status =
                          (if Update_Status = Versioning_Unconfigured
                           then Current_Status else Update_Status)
                        and then Merged.MFA_Delete =
                          (if Update_MFA = MFA_Delete_Unconfigured
                           then Current_MFA else Update_MFA),
                        "exhaustive versioning merge mismatch");
                  end;
               end loop;
            end loop;
         end loop;
      end loop;
      declare
         Value : constant Bucket_Versioning_Configuration :=
           (Status => Versioning_Enabled,
            MFA_Delete => MFA_Delete_Disabled);
         Document : constant String := Versioning.Serialize (Value);
         Parsed : constant Bucket_Versioning_Configuration :=
           Versioning.Parse (Document);
      begin
         Assert
           (Parsed = Value
            and then Ada.Strings.Fixed.Index
              (Document, "<MfaDelete>Disabled</MfaDelete>") > 0
            and then Ada.Strings.Fixed.Index
              (Document, "<Status>Enabled</Status>") > 0,
            "bucket versioning XML round trip");
         declare
            Response : constant String :=
              Versioning.Serialize_Response (Value);
         begin
            Assert
              (Ada.Strings.Fixed.Index (Response, "<Status>") <
                 Ada.Strings.Fixed.Index (Response, "<MfaDelete>")
               and then Versioning.Parse_Response (Response) = Value,
               "bucket versioning response model order");
         end;
      end;
      declare
         Parsed : constant Bucket_Versioning_Configuration :=
           Versioning.Parse
             ("<VersioningConfiguration xmlns=""" &
              "http://s3.amazonaws.com/doc/2006-03-01/""/>");
      begin
         Assert
           (Parsed.Status = Versioning_Unconfigured
            and then Parsed.MFA_Delete = MFA_Delete_Unconfigured,
            "empty versioning configuration lost member absence");
      end;
      Expect_Malformed ("", "empty versioning document accepted");
      Expect_Malformed
        ("<Other/>", "wrong versioning root accepted");
      Expect_Malformed
        (Versioning_Start & "<Status>Enabled</Status>" &
         "<Status>Suspended</Status>" & Versioning_End,
         "duplicate versioning status accepted");
      Expect_Malformed
        (Versioning_Start & "<MFADelete>Enabled</MFADelete>" &
         Versioning_End,
         "incorrectly cased MFA-delete element accepted");
      Expect_Malformed
        (Versioning_Start & "<Unknown>Enabled</Unknown>" & Versioning_End,
         "unknown versioning field accepted");
      Expect_Malformed
        (Versioning_Start & "<Status><Value>Enabled</Value></Status>" &
         Versioning_End,
         "nested versioning status accepted");
      Expect_Malformed
        (Versioning_Start & "<Status>Disabled</Status>" & Versioning_End,
         "invalid versioning status accepted");
      Expect_Malformed
        (Versioning_Start & "<Status> Enabled </Status>" & Versioning_End,
         "padded versioning status accepted");
      Expect_Malformed
        ("<!DOCTYPE x [<!ENTITY y ""Enabled"">]>" &
         Versioning_Start & "<Status>&y;</Status>" & Versioning_End,
         "versioning XML entity accepted");
      Expect_Malformed
        ("<VersioningConfiguration><Status>Enabled</Status>" &
         "</VersioningConfiguration>",
         "namespace-free versioning request accepted");
      Expect_Malformed
        ("<VersioningConfiguration xmlns=""urn:foreign"">" &
         "<Status>Enabled</Status></VersioningConfiguration>",
         "foreign versioning namespace accepted");
      Expect_Malformed
        ("<VersioningConfiguration xmlns=""" &
         "http://s3.amazonaws.com/doc/2006-03-01/"" extra=""x"">" &
         "<Status>Enabled</Status></VersioningConfiguration>",
         "versioning element attribute accepted");
      declare
         Parsed : constant Bucket_Versioning_Configuration :=
           Versioning.Parse_Response
             ("<VersioningConfiguration><Status>Enabled</Status>" &
              "</VersioningConfiguration>");
      begin
         Assert
           (Parsed.Status = Versioning_Enabled,
            "namespace-free compatible versioning response rejected");
      end;
      Expect_Malformed
        (String'(1 .. Versioning.Maximum_Document_Bytes + 1 => 'x'),
         "oversized versioning document accepted");

      declare
         Store : Memory.Store
           (Bucket_Capacity => 4,
            Object_Capacity => 4,
            Byte_Capacity   => 1_024);
      begin
         Exercise (Store);
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      declare
         Store : Files.Store :=
           Files.Open (Root, Commit => Files.Process_Crash_Atomic);
         Before, After : Bucket_Page;
         Options : List_Buckets_Options;
         Result : Status;
      begin
         Exercise (Store);
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Before, Result);
         Store.Put_Bucket_Versioning
           ("versioning-bucket",
            (Status => Versioning_Enabled,
             MFA_Delete => MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Result);
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, After, Result);
         Assert
           (Before.Buckets.Length = 1
            and then After.Buckets.Length = 1
            and then Before.Buckets.First_Element.Created =
              After.Buckets.First_Element.Created,
            "files versioning update changed bucket creation time");
      end;
      declare
         Store : Files.Store :=
           Files.Open (Root, Commit => Files.Process_Crash_Atomic);
         Value : Bucket_Versioning_Configuration;
         Result : Status;
      begin
         Store.Get_Bucket_Versioning
           ("versioning-bucket", null, Ada.Real_Time.Time_Last,
            Value, Result);
         Assert
           (Result = Success
            and then Value.Status = Versioning_Enabled
            and then Value.MFA_Delete = MFA_Delete_Disabled,
            "files versioning configuration did not persist");
         Store.Delete_Bucket
           ("versioning-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success
            and then not Ada.Directories.Exists
              (Root & "/buckets/versioning-bucket/configuration/" &
               "versioning.fos"),
            "files bucket deletion retained versioning configuration");
      end;
      Ada.Directories.Delete_Tree (Root);

      declare
         Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      begin
         Parameters.Configuration.Status := Versioning_Enabled;
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Versioning
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", Parameters,
                 Identity, "us-east-1", "20130524T000000Z");
         begin
            Assert
              (Low_Level.Target (Prepared) =
                 "/example-bucket?versioning"
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared), "content-md5") > 0
               and then Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared),
                  "x-amz-expected-bucket-owner") > 0,
               "typed PutBucketVersioning request projection");
         end;
      end;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Get_Bucket_Versioning
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket",
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012")),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Assert
           (Low_Level.Target (Prepared) =
              "/example-bucket?versioning"
            and then Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               "x-amz-expected-bucket-owner") > 0,
            "typed GetBucketVersioning request projection");
      end;
      declare
         Outcome : constant Low_Level.Get_Bucket_Versioning_Outcome :=
           Low_Level.Decode_Get_Bucket_Versioning_Response
             (200,
              "<VersioningConfiguration><Status>Suspended</Status>" &
              "</VersioningConfiguration>");
      begin
         Assert
           (Outcome.Kind = Low_Level.Bucket_Versioning_Found
            and then Outcome.Configuration.Status =
              Versioning_Suspended
            and then Outcome.Configuration.MFA_Delete =
              MFA_Delete_Unconfigured,
            "typed GetBucketVersioning success decode");
      end;
      declare
         Outcome : constant Low_Level.Put_Bucket_Versioning_Outcome :=
           Low_Level.Decode_Put_Bucket_Versioning_Response (200, "");
      begin
         Assert
           (Outcome.Kind = Low_Level.Bucket_Versioning_Updated,
            "typed PutBucketVersioning success decode");
      end;
      declare
         Outcome : constant Low_Level.Get_Bucket_Versioning_Outcome :=
           Low_Level.Decode_Get_Bucket_Versioning_Response
             (404,
              "<Error><Code>NoSuchBucket</Code>" &
              "<Message>missing</Message></Error>",
              "request-id", "host-id");
      begin
         Assert
           (Outcome.Kind = Low_Level.Get_Bucket_Versioning_Rejected
            and then US.To_String (Outcome.Error.Code) = "NoSuchBucket"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id",
            "typed GetBucketVersioning error decode");
      end;
   end Check_Bucket_Versioning;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test
        (Caller.Create ("domain.validator-corpus", Check_Validators'Access));
      Result.Add_Test
        (Caller.Create ("memory.lifecycle", Check_Memory_Lifecycle'Access));
      Result.Add_Test
        (Caller.Create ("memory.multipart", Check_Memory_Multipart'Access));
      Result.Add_Test
        (Caller.Create
           ("memory.ranges-and-bounds", Check_Ranges_And_Bounds'Access));
      Result.Add_Test
        (Caller.Create
           ("files.persistence-and-safety",
            Check_Filesystem_Conformance'Access));
      Result.Add_Test
        (Caller.Create
           ("files.durability-fault-barriers",
            Check_Filesystem_Durability_Faults'Access));
      Result.Add_Test
        (Caller.Create
           ("backends.listing-conformance",
            Check_Backend_Listings'Access));
      Result.Add_Test
        (Caller.Create
           ("backends.delete-objects-conformance",
            Check_Backend_Delete_Objects'Access));
      Result.Add_Test
        (Caller.Create
           ("backends.object-tagging-conformance",
            Check_Backend_Object_Tagging'Access));
      Result.Add_Test
        (Caller.Create ("s3.core-rules", Check_S3_Core_Rules'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.request-target-adversarial",
            Check_Request_Target_Parsing'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.sigv4-official-vectors",
            Check_SigV4_Official_Vectors'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.xml-security-and-limits",
            Check_XML_Security_And_Limits'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.list-objects-v1-codec",
            Check_List_Objects_V1_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.list-objects-v2-codec",
            Check_List_Objects_V2_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.multipart-completion-codec",
            Check_Multipart_Completion_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.list-parts-codec",
            Check_List_Parts_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.get-object-attributes-codec",
            Check_Object_Attributes_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.list-multipart-uploads-codec",
            Check_List_Multipart_Uploads_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.bucket-tagging-codec",
            Check_Bucket_Tagging_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.delete-objects-result-codec",
            Check_Delete_Objects_Result_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.object-tagging-codec-adversarial",
            Check_Object_Tagging_Codec'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.low-level-list-request",
            Check_Low_Level_List_Request'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.low-level-multipart-request",
            Check_Low_Level_Multipart_Request'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.low-level-copy-object",
            Check_Low_Level_Copy_Object'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.low-level-bucket-lifecycle",
            Check_Low_Level_Bucket_Lifecycle'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.low-level-delete-requests",
            Check_Low_Level_Delete_Requests'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.low-level-object-tagging",
            Check_Low_Level_Object_Tagging'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.bucket-versioning-core",
            Check_Bucket_Versioning'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.generated-model-exhaustive",
            Check_Generated_S3_Model'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.model-request-projection-all-operations",
            Check_Model_Request_Projection'Access));
      Result.Add_Test
        (Caller.Create
           ("s3.sigv4-verification-adversarial",
            Check_SigV4_Verification'Access));
      return Result;
   end Suite;

end Object_Storage_Test_Cases;
