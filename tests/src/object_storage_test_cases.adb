with Ada.Containers;
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
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Requests;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.SigV4_Verification;
with Flyology.Object_Storage.S3.XML;

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
   begin
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
         Store.Complete_Multipart_Upload
           ("multipart-bucket", "target", US.To_String (Upload_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
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
         Store.Abort_Multipart_Upload
           ("multipart-bucket", "small", US.To_String (Small_ID), null,
            Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success
            and then Store.Bytes_Used = Byte_Count (5 * MiB + 4),
            "memory multipart abort did not release staged bytes");
         Store.Abort_Multipart_Upload
           ("multipart-bucket", "small", US.To_String (Small_ID), null,
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
         Store.Create_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "files create bucket");
         Store.Head_Bucket
           ("file-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "head existing files bucket");
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
            Store.Complete_Multipart_Upload
              ("file-bucket", "multipart-target",
               US.To_String (Upload_ID), Completion, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Info.Size = 14
               and then US.To_String (Info.Content_Type) =
                 "application/x-multipart-test",
               "files multipart completion persisted across reopen");
            Store.Get_Object
              ("file-bucket", "multipart-target", Whole_Object,
               Multipart_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Success
               and then Flyology.Bytes.To_Byte_String
                 (Multipart_Sink.Data) = "multipart body",
               "files multipart completion body");
            Store.Abort_Multipart_Upload
              ("file-bucket", "aborted-target", US.To_String (Abort_ID),
               null, Ada.Real_Time.Time_Last, Result);
            Assert (Result = Success, "files persisted multipart abort");
            Store.Abort_Multipart_Upload
              ("file-bucket", "aborted-target", US.To_String (Abort_ID),
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

   procedure Check_Backend_Listings (Unused : in out Fixture) is
      pragma Unreferenced (Unused);
      package Memory renames Flyology.Object_Storage.Backends.Memory;
      package Files renames Flyology.Object_Storage.Backends.Files;
      Root : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "obj"),
           "fs-listing-conformance");

      procedure Clean is
      begin
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
      end Clean;
   begin
      declare
         Store : Memory.Store (2, 16, 128);
      begin
         Exercise_Listing (Store, "memory-list-bucket");
      end;
      Clean;
      declare
         Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
      begin
         Exercise_Listing (Store, "files-list-bucket");
      end;
      Clean;
   exception
      when others =>
         Clean;
         raise;
   end Check_Backend_Listings;

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
      begin
         Assert
           (Empty.Max_Keys = Flyology.Object_Storage.S3.Core.Page_Size'Last
            and then US.Length (Empty.Prefix) = 0,
            "empty ListObjects query defaults");
         Assert
           (US.To_String (Request.Prefix) = "logs/+"
            and then US.To_String (Request.Delimiter) = "/"
            and then US.To_String (Request.Marker) = "a+b"
            and then Request.Max_Keys = 7
            and then Request.URL_Encoding,
            "ListObjects query decoding");
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
         Value : Listings.List_Objects_Result :=
           (Name            => US.To_Unbounded_String ("bucket"),
            Prefix          => US.Null_Unbounded_String,
            Delimiter       => US.To_Unbounded_String ("/"),
            Encoding_Type   => US.Null_Unbounded_String,
            Marker          => US.To_Unbounded_String ("before"),
            Next_Marker     => US.To_Unbounded_String ("a&b/"),
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
            and then Request.URL_Encoding,
            "ListObjectsV2 query decoding");
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
   begin
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
               Version_ID => US.Null_Unbounded_String));
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
         Parameters.Source_Range :=
           (Is_Set => True, First => 5, Last => 9);
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Upload_Part_Copy
                (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                 Low_Level.Path_Style, "example-bucket", "photos/a b+%",
                 Parameters, Identity, "us-east-1", "20130524T000000Z");
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
                  "x-amz-copy-source-if-match") > 0,
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
                 (Outcome.Result.Copy_Source_Version_ID) = "v1",
               "typed UploadPartCopy success response");
         end;
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
      use type Low_Level.Head_Bucket_Outcome_Kind;
      use type Low_Level.Head_Object_Outcome_Kind;
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
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
         Headers.Server_Side_Encryption :=
           US.To_Unbounded_String ("aws:kms:dsse");
         Headers.Metadata.Append
           (Low_Level.Metadata_Entry'
              (Name  => US.To_Unbounded_String ("project"),
               Value => US.To_Unbounded_String ("flyology")));
         Headers.SSE_Customer_Key_MD5 :=
           US.To_Unbounded_String ("AAAAAAAAAAAAAAAAAAAAAA==");
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
              Low_Level.Decode_Head_Object_Response (206, "", Headers);
         begin
            Assert
              (Outcome.Kind = Low_Level.Object_Found
               and then Outcome.Result.Content_Length = 9
               and then Outcome.Result.Metadata.Length = 1
               and then Outcome.Result.Parts_Count.Is_Set
               and then Outcome.Result.Parts_Count.Value = 3,
               "typed HeadObject complete response headers");
         end;
      end;

      declare
         Headers : Low_Level.Head_Object_Result;
         Raised : Boolean := False;
      begin
         Headers.Checksum_CRC32 := US.To_Unbounded_String ("not-base64");
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
   begin
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
         Request : Deletions.Delete_Objects_Request;
         Parameters : Low_Level.Delete_Objects_Parameters;
      begin
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String ("a&b"),
               Version_ID => US.Null_Unbounded_String));
         Request.Objects.Append
           (Deletions.Object_Identifier'
              (Key        => US.To_Unbounded_String ("second"),
               Version_ID => US.To_Unbounded_String ("v1")));
         Request.Quiet := True;
         Parameters.MFA := US.To_Unbounded_String ("device 123456");
         Parameters.Request_Payer := US.To_Unbounded_String ("requester");
         Parameters.Bypass_Governance_Retention :=
           (Is_Set => True, Value => False);
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String ("123456789012");
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
                 "x-amz-content-sha256;x-amz-date;" &
                 "x-amz-expected-bucket-owner;x-amz-mfa;" &
                 "x-amz-request-payer"
               and then Ada.Strings.Fixed.Index
                 (Canonical, "content-md5:oHu1qjgIzoBt4qEk27Rx2Q==") > 0,
               "DeleteObjects Content-MD5 and modeled headers are signed");
         end;
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
           ("backends.listing-conformance",
            Check_Backend_Listings'Access));
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
           ("s3.delete-objects-result-codec",
            Check_Delete_Objects_Result_Codec'Access));
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
