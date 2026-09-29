--  BACKEND-MEMORY probe (not a bug reproduction).  Two of the discovery
--  report's uncounted observations, measured rather than reasoned about.
--  It asserts the behaviour I claim in the verification report, so it PASSES
--  (exit 0) on the current sources; a failure here would mean the report's
--  disposition of those observations is wrong.
--
--  A. Reservation accounting.  memory.adb:1379-1385 (Release_Transient)
--     protects underflow only with a Program_Error, and Release_Buffer
--     (:3456-3464) zeroes the buffer before releasing, so the question is
--     whether any reachable path releases twice or leaks.  This probe drives
--     every reachable success and failure path that reserves transient bytes
--     and checks that Bytes_Used (Bytes + Reserved_Bytes, memory.adb:3424)
--     returns exactly to its retained level, including when the caller's sink
--     raises in Begin_Object and in Write.
--
--  B. Unknown paired version cursor.  memory.adb:2675-2690 rejects a paired
--     ListObjectVersions cursor whose generation is not in the candidate set.
--     This probe records what a *stale* cursor does after the marked
--     generation is permanently removed between pages, and what a cursor
--     excluded by a prefix does.
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Memory_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Memory_Probe is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Memory_Support;

   use type Storage.Status;
   use type Storage.Byte_Count;

   Deadline : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Enabled : constant Storage.Bucket_Versioning_Configuration :=
     (Status     => Storage.Versioning_Enabled,
      MFA_Delete => Storage.MFA_Delete_Unconfigured);

   Sink_Failure : exception;

   --  A sink that raises at a chosen point, to exercise the backend's
   --  exception paths through a caller-supplied callback.
   type Failure_Point is (Fail_On_Begin, Fail_On_Write);

   type Raising_Sink (Point : Failure_Point) is limited
     new Backends.Byte_Sink with null record;

   overriding procedure Begin_Object
     (Item           : in out Raising_Sink;
      Info           : Storage.Object_Information;
      First          : Storage.Byte_Count;
      Content_Length : Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Raising_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Begin_Object
     (Item           : in out Raising_Sink;
      Info           : Storage.Object_Information;
      First          : Storage.Byte_Count;
      Content_Length : Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Info, First, Content_Length, Partial);
      pragma Unreferenced (Token, Deadline);
   begin
      if Item.Point = Fail_On_Begin then
         raise Sink_Failure;
      end if;
   end Begin_Object;

   overriding procedure Write
     (Item     : in out Raising_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Data, Token, Deadline);
   begin
      if Item.Point = Fail_On_Write then
         raise Sink_Failure;
      end if;
   end Write;

   ------------------------------------------------------------------
   --  A. Reservation accounting across every reachable path.
   ------------------------------------------------------------------

   procedure Accounting_Probe is
      Store : Flyology.Object_Storage.Backends.Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1_048_576);
      Bucket : constant String := "bkt";
      Payload : constant String (1 .. 4_096) := [others => 'x'];
      Result   : Storage.Status;
      Info     : Storage.Object_Information;
      Identity : Backends.Version_Identity;
      Retained : Storage.Byte_Count;

      procedure Same (Label : String; Expected : Storage.Byte_Count) is
         Actual : constant Storage.Byte_Count := Store.Bytes_Used;
      begin
         Note ("accounting: " & Label & " Bytes_Used "
               & Image_64 (Long_Long_Integer (Actual))
               & " expected " & Image_64 (Long_Long_Integer (Expected)));
         Check (Actual = Expected,
                "accounting: " & Label & " leaves Bytes_Used unchanged");
      end Same;
   begin
      Check (Store.Bytes_Used = 0, "accounting: empty store uses no bytes");
      Store.Create_Bucket (Bucket, null, Deadline, Result);
      Check (Result = Storage.Success, "accounting: bucket created");
      declare
         Source : Support.String_Source := Support.Source_Of (Payload);
      begin
         Store.Put_Object
           (Bucket, "k", Source, Storage.Default_Put_Options, null, Deadline,
            Info, Identity, Result);
      end;
      Check (Result = Storage.Success, "accounting: object published");
      Retained := Store.Bytes_Used;
      Note ("accounting: retained baseline "
            & Image_64 (Long_Long_Integer (Retained)));

      --  Repeated successful reads each reserve and release a full snapshot.
      for Pass in 1 .. 3 loop
         declare
            Sink : Support.Collecting_Sink;
         begin
            Store.Get_Object
              (Bucket, "k", Storage.Whole_Object, Sink, null, Deadline,
               Info, Result);
            Check (Result = Storage.Success and then
                     US.Length (Sink.Data) = Payload'Length,
                   "accounting: read" & Image (Pass) & " succeeded");
         end;
      end loop;
      Same ("three successful GETs", Retained);

      --  A sink that raises in Begin_Object.
      begin
         declare
            Sink : Raising_Sink (Fail_On_Begin);
         begin
            Store.Get_Object
              (Bucket, "k", Storage.Whole_Object, Sink, null, Deadline,
               Info, Result);
         end;
         Check (False, "accounting: Begin_Object failure propagates");
      exception
         when Sink_Failure =>
            Check (True, "accounting: Begin_Object failure propagates");
      end;
      Same ("GET whose sink raised in Begin_Object", Retained);

      --  A sink that raises in Write.
      begin
         declare
            Sink : Raising_Sink (Fail_On_Write);
         begin
            Store.Get_Object
              (Bucket, "k", Storage.Whole_Object, Sink, null, Deadline,
               Info, Result);
         end;
         Check (False, "accounting: Write failure propagates");
      exception
         when Sink_Failure =>
            Check (True, "accounting: Write failure propagates");
      end;
      Same ("GET whose sink raised in Write", Retained);

      --  A conditional read that fails after the snapshot is reserved.
      declare
         Sink : Support.Collecting_Sink;
         Conditions : Backends.Read_Conditions;
      begin
         Conditions.If_None_Match := US.To_Unbounded_String ("*");
         Store.Get_Object
           (Bucket, "k", Storage.Whole_Object, Sink, null, Deadline,
            Info, Result, Conditions => Conditions);
         Note ("accounting: conditional GET -> "
               & Storage.Status'Image (Result));
      end;
      Same ("conditional GET rejected after reservation", Retained);

      --  An unsatisfiable range, rejected after the snapshot is reserved.
      declare
         Sink : Support.Collecting_Sink;
         Requested : constant Storage.Byte_Range :=
           (Kind => Storage.Bounded_Range, First => 999_999, Last => 999_999,
            Count => 0);
      begin
         Store.Get_Object
           (Bucket, "k", Requested, Sink, null, Deadline, Info, Result);
         Note ("accounting: unsatisfiable range GET -> "
               & Storage.Status'Image (Result));
      end;
      Same ("unsatisfiable range GET", Retained);

      --  A copy that is published and then removed again.
      declare
         Options : constant Backends.Copy_Options :=
           Backends.Default_Copy_Options;
         Source_Identity, Destination_Identity : Backends.Version_Identity;
      begin
         Store.Copy_Object
           (Bucket, "k", Bucket, "copy", Options, null, Deadline,
            Info, Source_Identity, Destination_Identity, Result);
         Check (Result = Storage.Success, "accounting: copy published");
         Store.Delete_Object (Bucket, "copy", null, Deadline, Result);
         Check (Result = Storage.Success, "accounting: copy removed");
      end;
      Same ("CopyObject then DeleteObject", Retained);

      --  A conditional PUT rejected inside the publication boundary.
      declare
         Source : Support.String_Source := Support.Source_Of (Payload);
         Conditions : Storage.Write_Conditions;
      begin
         Conditions.If_None_Match := US.To_Unbounded_String ("*");
         Store.Put_Object
           (Bucket, "k", Source, Storage.Default_Put_Options, null, Deadline,
            Info, Identity, Result, Conditions => Conditions);
         Note ("accounting: conditional PUT -> "
               & Storage.Status'Image (Result));
      end;
      Same ("conditional PUT rejected at publication", Retained);

      --  A PUT that exceeds the byte capacity.
      declare
         Big : constant String (1 .. 2_000_000) := [others => 'y'];
         Source : Support.String_Source := Support.Source_Of (Big);
      begin
         Store.Put_Object
           (Bucket, "big", Source, Storage.Default_Put_Options, null,
            Deadline, Info, Identity, Result);
         Note ("accounting: oversize PUT -> " & Storage.Status'Image (Result));
         Check (Result = Storage.Capacity_Exceeded,
                "accounting: oversize PUT is Capacity_Exceeded");
      end;
      Same ("PUT rejected for capacity", Retained);

      --  Multipart staging then abort.
      declare
         Upload : US.Unbounded_String;
         Source : Support.String_Source := Support.Source_Of (Payload);
      begin
         Store.Create_Multipart_Upload
           (Bucket, "mp", Backends.Default_Multipart_Options, null, Deadline,
            Upload, Result);
         Check (Result = Storage.Success, "accounting: upload initiated");
         Store.Put_Multipart_Part
           (Bucket, "mp", US.To_String (Upload), 1, Source,
            Backends.Default_Multipart_Part_Options, null, Deadline,
            Info, Result);
         Check (Result = Storage.Success, "accounting: part staged");
         Store.Abort_Multipart_Upload
           (Bucket, "mp", US.To_String (Upload),
            Backends.No_Abort_Multipart_Conditions, null, Deadline, Result);
         Check (Result = Storage.Success, "accounting: upload aborted");
      end;
      Same ("multipart stage then abort", Retained);

      Store.Delete_Object (Bucket, "k", null, Deadline, Result);
      Check (Result = Storage.Success, "accounting: object removed");
      Store.Delete_Bucket (Bucket, null, Deadline, Result);
      Check (Result = Storage.Success, "accounting: bucket removed");
      Same ("empty store after teardown", 0);
   end Accounting_Probe;

   ------------------------------------------------------------------
   --  B. Stale and excluded paired ListObjectVersions cursors.
   ------------------------------------------------------------------

   procedure Cursor_Probe is
      Store : Flyology.Object_Storage.Backends.Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1_048_576);
      Bucket : constant String := "ver";
      Key    : constant String := "alpha";
      Result   : Storage.Status;
      Info     : Storage.Object_Information;
      Identity : Backends.Version_Identity;
      Outcome  : Backends.Version_Delete_Outcome;
      Options  : Backends.List_Versions_Options;
      Page     : Backends.List_Versions_Page;
      Marker_Key, Marker_Version : US.Unbounded_String;
      Oldest : US.Unbounded_String;
   begin
      Store.Create_Bucket (Bucket, null, Deadline, Result);
      Check (Result = Storage.Success, "cursor: bucket created");
      Store.Put_Bucket_Versioning (Bucket, Enabled, null, Deadline, Result);
      Check (Result = Storage.Success, "cursor: versioning enabled");
      for Pass in 1 .. 3 loop
         declare
            Source : Support.String_Source :=
              Support.Source_Of ("gen" & Image (Pass));
         begin
            Store.Put_Object
              (Bucket, Key, Source, Storage.Default_Put_Options, null,
               Deadline, Info, Identity, Result);
            Check (Result = Storage.Success,
                   "cursor: generation" & Image (Pass) & " published");
            if Pass = 1 then
               Oldest := Identity.Version_ID;
            end if;
         end;
      end loop;

      Options.Maximum := 1;
      Store.List_Object_Versions
        (Bucket, Options, null, Deadline, Page, Result);
      Check (Result = Storage.Success and then Page.Is_Truncated,
             "cursor: first page is truncated");
      Marker_Key := Page.Next_Key_Marker;
      Marker_Version := Page.Next_Version_ID_Marker;
      Note ("cursor: page 1 marker key '" & US.To_String (Marker_Key)
            & "' version '" & US.To_String (Marker_Version) & "'");

      --  Control: the fresh cursor resumes.
      Options.Has_Key_Marker := True;
      Options.Key_Marker := Marker_Key;
      Options.Has_Version_ID_Marker := True;
      Options.Version_ID_Marker := Marker_Version;
      Store.List_Object_Versions
        (Bucket, Options, null, Deadline, Page, Result);
      Note ("cursor: fresh cursor -> " & Storage.Status'Image (Result)
            & " entries" & Image (Natural (Page.Entries.Length)));
      Check (Result = Storage.Success,
             "cursor: a fresh service cursor resumes");

      --  Removing an unrelated generation does not disturb the cursor.
      Store.Delete_Selected_Object
        (Bucket, Key,
         (Kind => Backends.Exact_Version, ID => Oldest),
         Backends.No_Delete_Object_Conditions, False, null, Deadline,
         Outcome, Result);
      Check (Result = Storage.Success,
             "cursor: unrelated generation removed");
      Store.List_Object_Versions
        (Bucket, Options, null, Deadline, Page, Result);
      Note ("cursor: after removing an unrelated generation -> "
            & Storage.Status'Image (Result) & " entries"
            & Image (Natural (Page.Entries.Length)));
      Check (Result = Storage.Success,
             "cursor: cursor still resumes after an unrelated removal");

      --  Now remove the generation the cursor names.
      Store.Delete_Selected_Object
        (Bucket, Key,
         (Kind => Backends.Exact_Version, ID => Marker_Version),
         Backends.No_Delete_Object_Conditions, False, null, Deadline,
         Outcome, Result);
      Check (Result = Storage.Success,
             "cursor: the marked generation was removed");
      Store.List_Object_Versions
        (Bucket, Options, null, Deadline, Page, Result);
      Note ("cursor: stale cursor (marked generation deleted) -> "
            & Storage.Status'Image (Result) & " entries"
            & Image (Natural (Page.Entries.Length))
            & " truncated " & Boolean'Image (Page.Is_Truncated));
      Check (Result = Storage.Invalid_Request,
             "cursor: a stale cursor is REJECTED, not skipped or restarted");

      --  A prefix that excludes the marked key has the same effect.
      declare
         Fresh_Options : Backends.List_Versions_Options;
         Fresh_Page    : Backends.List_Versions_Page;
      begin
         Fresh_Options.Maximum := 1;
         Store.List_Object_Versions
           (Bucket, Fresh_Options, null, Deadline, Fresh_Page, Result);
         Check (Result = Storage.Success, "cursor: refreshed page");
         Fresh_Options.Has_Key_Marker := True;
         Fresh_Options.Key_Marker := Fresh_Page.Next_Key_Marker;
         Fresh_Options.Has_Version_ID_Marker := True;
         Fresh_Options.Version_ID_Marker := Fresh_Page.Next_Version_ID_Marker;
         Fresh_Options.Prefix := US.To_Unbounded_String ("zzz");
         Store.List_Object_Versions
           (Bucket, Fresh_Options, null, Deadline, Fresh_Page, Result);
         Note ("cursor: prefix-excluded cursor -> "
               & Storage.Status'Image (Result));
         Check (Result = Storage.Invalid_Request,
                "cursor: a prefix-excluded cursor is also rejected");
      end;
   end Cursor_Probe;

begin
   Accounting_Probe;
   Cursor_Probe;
   Finish;
end Repro_Backend_Memory_Probe;
