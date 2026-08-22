with Ada.Command_Line;
with Ada.Containers;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Durability_Testing;
with Flyology.Object_Storage.Tags;

procedure Files_Crash_Probe is
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Flyology.Object_Storage.Status;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;
   package US renames Ada.Strings.Unbounded;
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Faults renames Flyology.Object_Storage.Durability_Testing;
   package Tags renames Flyology.Object_Storage.Tags;

   Bucket : constant String := "durability-bucket";
   Key    : constant String := "object";

   type Buffer_Source is new Backends.Byte_Source with record
      Data     : Flyology.Bytes.Unbounded_Bytes;
      Position : Natural := 0;
   end record;

   overriding function Declared_Length
     (Item : Buffer_Source) return Backends.Source_Length is
     ((Kind => Backends.Known,
       Bytes => Storage.Byte_Count (Flyology.Bytes.Length (Item.Data))));

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

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Create_Bucket
     (Store : in out Files.Store)
   is
      Result : Storage.Status;
   begin
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Storage.Success, "could not create test bucket");
   end Create_Bucket;

   procedure Put_At
     (Store : in out Files.Store; Object_Key, Payload : String)
   is
      Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String (Payload), Position => 0);
      Info   : Storage.Object_Information;
      Result : Storage.Status;
   begin
      Store.Put_Object
        (Bucket, Object_Key, Source, Storage.Default_Put_Options,
         null, Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Storage.Success, "could not put test object");
   end Put_At;

   procedure Put (Store : in out Files.Store; Payload : String) is
   begin
      Put_At (Store, Key, Payload);
   end Put;

   procedure Set_Object_Tag (Store : in out Files.Store; Value : String) is
      Tags : Storage.Object_Tag_Set := Storage.Empty_Object_Tags;
      Result : Storage.Status;
   begin
      Tags.Length := 1;
      Tags.Items (1) :=
        (Key => US.To_Unbounded_String ("state"),
         Value => US.To_Unbounded_String (Value));
      Store.Put_Object_Tags
        (Bucket, Key, Tags, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Storage.Success, "could not set test object tag");
   end Set_Object_Tag;

   procedure Put_Bucket_Tags (Store : in out Files.Store; Text : String) is
      Value  : Tags.Tag_Set;
      Result : Storage.Status;
   begin
      Value.Append
        (Tags.Tag'
           (Key   => US.To_Unbounded_String ("state"),
            Value => US.To_Unbounded_String (Text)));
      Store.Put_Bucket_Tags
        (Bucket, Value, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Storage.Success, "could not put test bucket tags");
   end Put_Bucket_Tags;

   procedure Create_Upload
     (Store : in out Files.Store; Upload_ID : out US.Unbounded_String)
   is
      Result : Storage.Status;
   begin
      Store.Create_Multipart_Upload
        (Bucket, Key, Backends.Default_Multipart_Options,
         null, Ada.Real_Time.Time_Last, Upload_ID, Result);
      Require (Result = Storage.Success, "could not create test upload");
   end Create_Upload;

   function Only_Upload (Store : in out Files.Store) return String is
      Page   : Backends.Multipart_Upload_Page;
      Result : Storage.Status;
   begin
      Store.List_Multipart_Uploads
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page, Result);
      Require
        (Result = Storage.Success and then Page.Uploads.Length = 1,
         "expected exactly one test upload");
      return US.To_String (Page.Uploads.First_Element.Upload_ID);
   end Only_Upload;

   function Upload_Count (Store : in out Files.Store) return Natural is
      Page   : Backends.Multipart_Upload_Page;
      Result : Storage.Status;
   begin
      Store.List_Multipart_Uploads
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last, Page, Result);
      Require (Result = Storage.Success, "could not list test uploads");
      return Natural (Page.Uploads.Length);
   end Upload_Count;

   procedure Put_Part
     (Store : in out Files.Store; Upload_ID, Payload : String)
   is
      Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String (Payload), Position => 0);
      Info   : Storage.Object_Information;
      Result : Storage.Status;
   begin
      Store.Put_Multipart_Part
        (Bucket, Key, Upload_ID, 1, Source, null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Storage.Success, "could not put test part");
   end Put_Part;

   procedure Prepare (Scenario, Root : String) is
      Store     : Files.Store := Files.Open (Root);
      Upload_ID : US.Unbounded_String;
      Result    : Storage.Status;
   begin
      if Scenario = "bucket" then
         null;
      else
         Create_Bucket (Store);
         if Scenario in "put" | "delete" | "delete-objects" |
           "object-tags"
         then
            Put (Store, "old");
            if Scenario = "delete-objects" then
               Put_At (Store, "second-object", "also-old");
            end if;
            if Scenario = "object-tags" then
               Set_Object_Tag (Store, "old");
            end if;
         elsif Scenario = "bucket-tags" then
            Put_Bucket_Tags (Store, "old");
         elsif Scenario in "part" | "abort" | "complete" then
            Create_Upload (Store, Upload_ID);
            if Scenario in "part" | "complete" then
               Put_Part (Store, US.To_String (Upload_ID), "old");
            end if;
         elsif Scenario = "versioning" then
            Store.Put_Bucket_Versioning
              (Bucket,
               (Status     => Storage.Versioning_Enabled,
                MFA_Delete => Storage.MFA_Delete_Unconfigured),
               null, Ada.Real_Time.Time_Last, Result);
            Require (Result = Storage.Success,
                     "could not prepare versioning configuration");
         elsif Scenario not in "initiate" | "delete-bucket" then
            raise Program_Error with "unknown crash scenario";
         end if;
      end if;
   end Prepare;

   procedure Mutate
     (Scenario, Root : String; Barrier : Natural; After_Sync : Boolean)
   is
      Store     : Files.Store := Files.Open (Root);
      Result    : Storage.Status;
      Upload_ID : US.Unbounded_String;
      Info      : Storage.Object_Information;
   begin
      Faults.Crash_At_Barrier (Barrier, After_Sync);
      if Scenario = "bucket" then
         Store.Create_Bucket
           (Bucket, null, Ada.Real_Time.Time_Last, Result);
      elsif Scenario = "put" then
         Put (Store, "replacement");
         Result := Storage.Success;
      elsif Scenario = "bucket-tags" then
         Put_Bucket_Tags (Store, "replacement");
         Result := Storage.Success;
      elsif Scenario = "delete" then
         Store.Delete_Object
           (Bucket, Key, null, Ada.Real_Time.Time_Last, Result);
      elsif Scenario = "delete-objects" then
         declare
            Entries  : Backends.Delete_Object_Entries;
            Outcomes : Backends.Delete_Object_Outcomes;
         begin
            Entries.Append
              (Backends.Delete_Object_Entry'
                 (Key        => US.To_Unbounded_String (Key),
                  Conditions => Backends.No_Delete_Object_Conditions));
            Entries.Append
              (Backends.Delete_Object_Entry'
                 (Key        => US.To_Unbounded_String ("second-object"),
                  Conditions => Backends.No_Delete_Object_Conditions));
            Store.Delete_Objects
              (Bucket, Entries, (others => <>), null,
               Ada.Real_Time.Time_Last,
               Outcomes, Result);
         end;
      elsif Scenario = "object-tags" then
         Set_Object_Tag (Store, "new");
         Result := Storage.Success;
      elsif Scenario = "initiate" then
         Store.Create_Multipart_Upload
           (Bucket, Key, Backends.Default_Multipart_Options,
            null, Ada.Real_Time.Time_Last, Upload_ID, Result);
      elsif Scenario = "part" then
         Put_Part (Store, Only_Upload (Store), "new-part");
         Result := Storage.Success;
      elsif Scenario = "abort" then
         Store.Abort_Multipart_Upload
           (Bucket, Key, Only_Upload (Store),
            Backends.No_Abort_Multipart_Conditions, null,
            Ada.Real_Time.Time_Last, Result);
      elsif Scenario = "delete-bucket" then
         Store.Delete_Bucket
           (Bucket, null, Ada.Real_Time.Time_Last, Result);
      elsif Scenario = "versioning" then
         Store.Put_Bucket_Versioning
           (Bucket,
            (Status     => Storage.Versioning_Suspended,
             MFA_Delete => Storage.MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Result);
      elsif Scenario = "complete" then
         Upload_ID := US.To_Unbounded_String (Only_Upload (Store));
         declare
            Page  : Backends.Multipart_Part_Page;
            Parts : Backends.Multipart_Part_References;
         begin
            Store.List_Multipart_Parts
              (Bucket, Key, US.To_String (Upload_ID),
               (After => 0, Maximum => 2), null,
               Ada.Real_Time.Time_Last, Page, Result);
            Require
              (Result = Storage.Success and then Page.Parts.Length = 1,
               "could not list completion part");
            Parts.Append
              (Backends.Multipart_Part_Reference'
                 (Number => 1,
                  Entity_Tag => Page.Parts.First_Element.Info.Entity_Tag));
            Store.Complete_Multipart_Upload
              (Bucket, Key, US.To_String (Upload_ID), Parts, null,
               Ada.Real_Time.Time_Last, Info, Result);
         end;
      else
         raise Program_Error with "unknown crash scenario";
      end if;
      Faults.Clear_Failure;
      Require (Result = Storage.Success, "mutation failed before crash hook");
      raise Program_Error with "configured crash barrier was not reached";
   end Mutate;

   procedure Verify (Scenario, Root : String) is
      Store  : Files.Store := Files.Open (Root);
      Info   : Storage.Object_Information;
      Result : Storage.Status;
   begin
      if Scenario in "bucket" | "delete-bucket" then
         Store.Head_Bucket
           (Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result in Storage.Success | Storage.Not_Found,
            "crash exposed malformed bucket namespace");
      elsif Scenario in "put" | "delete" then
         Store.Head_Object
           (Bucket, Key, null, Ada.Real_Time.Time_Last, Info, Result);
         if Scenario = "put" then
            Require
              (Result = Storage.Success and then Info.Size in 3 | 11,
               "crash exposed a partial object replacement");
         else
            Require
              (Result in Storage.Success | Storage.Not_Found,
               "crash exposed malformed object deletion");
         end if;
      elsif Scenario = "delete-objects" then
         Store.Head_Object
           (Bucket, Key, null, Ada.Real_Time.Time_Last, Info, Result);
         Require
           (Result in Storage.Success | Storage.Not_Found,
            "crash exposed malformed first batch deletion");
         Store.Head_Object
           (Bucket, "second-object", null, Ada.Real_Time.Time_Last,
            Info, Result);
         Require
           (Result in Storage.Success | Storage.Not_Found,
            "crash exposed malformed second batch deletion");
      elsif Scenario = "object-tags" then
         declare
            Tags : Storage.Object_Tag_Set;
         begin
            Store.Get_Object_Tags
              (Bucket, Key, null, Ada.Real_Time.Time_Last, Tags, Result);
            Require
              (Result = Storage.Success and then Tags.Length = 1
               and then US.To_String (Tags.Items (1).Key) = "state"
               and then US.To_String (Tags.Items (1).Value) in "old" | "new",
               "crash exposed a partial object-tag replacement");
         end;
      elsif Scenario = "bucket-tags" then
         declare
            Value : Tags.Tag_Set;
         begin
            Store.Get_Bucket_Tags
              (Bucket, null, Ada.Real_Time.Time_Last, Value, Result);
            Require
              (Result = Storage.Success and then Value.Length = 1
               and then US.To_String (Value.First_Element.Value) in
                 "old" | "replacement",
               "crash exposed a partial bucket tag replacement");
         end;
      elsif Scenario in "initiate" | "abort" then
         Require
           (Upload_Count (Store) in 0 .. 1,
            "crash exposed malformed upload namespace");
      elsif Scenario = "part" then
         declare
            Page : Backends.Multipart_Part_Page;
         begin
            Store.List_Multipart_Parts
              (Bucket, Key, Only_Upload (Store),
               (After => 0, Maximum => 2), null,
               Ada.Real_Time.Time_Last, Page, Result);
            Require
              (Result = Storage.Success
               and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Info.Size in 3 | 8,
               "crash exposed a partial part replacement");
         end;
      elsif Scenario = "complete" then
         declare
            Count : constant Natural := Upload_Count (Store);
         begin
            Store.Head_Object
              (Bucket, Key, null, Ada.Real_Time.Time_Last, Info, Result);
            Require
              (Count in 0 .. 1
               and then Result in Storage.Success | Storage.Not_Found
               and then (Result = Storage.Success or else Count = 1),
               "crash lost both completed object and active upload");
            if Result = Storage.Success then
               Require (Info.Size = 3, "completed object has wrong size");
            end if;
         end;
      elsif Scenario = "versioning" then
         declare
            Configuration : Storage.Bucket_Versioning_Configuration;
         begin
            Store.Get_Bucket_Versioning
              (Bucket, null, Ada.Real_Time.Time_Last,
               Configuration, Result);
            Require
              (Result = Storage.Success
               and then
                 Configuration.Status in
                   Storage.Versioning_Enabled |
                   Storage.Versioning_Suspended,
               "crash exposed a partial versioning configuration");
         end;
      else
         raise Program_Error with "unknown crash scenario";
      end if;
   end Verify;

begin
   Require (Ada.Command_Line.Argument_Count >= 3, "missing arguments");
   declare
      Action   : constant String := Ada.Command_Line.Argument (1);
      Scenario : constant String := Ada.Command_Line.Argument (2);
      Root     : constant String := Ada.Command_Line.Argument (3);
   begin
      if Action = "prepare" then
         Prepare (Scenario, Root);
      elsif Action = "verify" then
         Verify (Scenario, Root);
      elsif Action = "crash" then
         Require (Ada.Command_Line.Argument_Count = 5, "missing crash args");
         Mutate
           (Scenario, Root,
            Natural'Value (Ada.Command_Line.Argument (4)),
            Ada.Command_Line.Argument (5) = "after");
      else
         raise Program_Error with "unknown action";
      end if;
   end;
end Files_Crash_Probe;
