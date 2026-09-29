--  BACKEND-MEMORY-1: ListMultipartUploads paginated with a service-produced
--  (key-marker, upload-id-marker) pair silently drops same-key uploads.
--
--  Page order inside one key is initiation time
--  (src/flyology-object_storage-backends-multipart_listing.adb:17-30) but the
--  exclusive marker is applied by lexical upload ID only (:81-92), and the
--  memory backend's upload IDs are SHA-256 digests of a counter
--  (src/flyology-object_storage-backends-memory.adb:2829-2833) whose lexical
--  order is unrelated to creation order.  Whenever the next upload in
--  initiation order has an ID that sorts at or before the marker, it is never
--  returned by any continuation of that cursor.
--
--  This program asserts the CORRECT behaviour: walking the cursor the service
--  itself produced must yield every active upload exactly once.  It checks
--  the backend interface directly and then the same walk over the in-process
--  S3 application.
with Ada.Containers;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Memory_Support;
with Repro_S3_Server; use Repro_S3_Server;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Memory_1 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Memory_Support;

   use type Storage.Status;
   use type Ada.Containers.Count_Type;
   use type US.Unbounded_String;

   Uploads_Wanted : constant := 6;
   --  Six same-key uploads one second apart.  Their IDs are the SHA-256
   --  digests of "<bucket>NUL<key>NUL <n>", so the initiation/lexical
   --  inversion is fixed by the sources rather than left to chance: for
   --  bucket "bkt" and key "k" the six digests begin dc3e, 6f9a, 42d9, ccbf,
   --  8044, c4dd, so every upload after the first sorts before it.

   Deadline : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   type ID_Array is array (1 .. Uploads_Wanted) of US.Unbounded_String;

   function Occurrences
     (Walk : ID_Array; Count : Natural; Value : US.Unbounded_String)
      return Natural
   is
      Hits : Natural := 0;
   begin
      for Index in 1 .. Count loop
         if Walk (Index) = Value then
            Hits := Hits + 1;
         end if;
      end loop;
      return Hits;
   end Occurrences;

   --  Return the text of the first <Name>...</Name> at or after From and
   --  leave From just past the closing tag; return "" and leave From
   --  unchanged when the element is absent.
   function Take_Element
     (Document : String; Name : String; From : in out Positive) return String
   is
      Open  : constant String := "<" & Name & ">";
      Close : constant String := "</" & Name & ">";
      At_Open, At_Close : Natural;
   begin
      if From > Document'Last then
         return "";
      end if;
      At_Open := Ada.Strings.Fixed.Index (Document, Open, From);
      if At_Open = 0 then
         return "";
      end if;
      At_Close := Ada.Strings.Fixed.Index
        (Document, Close, At_Open + Open'Length);
      if At_Close = 0 then
         return "";
      end if;
      From := At_Close + Close'Length;
      return Document (At_Open + Open'Length .. At_Close - 1);
   end Take_Element;

   function First_Element (Document : String; Name : String) return String is
      Cursor : Positive := (if Document'Length = 0 then 1 else Document'First);
   begin
      if Document'Length = 0 then
         return "";
      end if;
      return Take_Element (Document, Name, Cursor);
   end First_Element;

   ------------------------------------------------------------------
   --  1. Backend interface, own store with small capacities.
   ------------------------------------------------------------------

   procedure Backend_Walk is
      Store : Flyology.Object_Storage.Backends.Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1_048_576);
      Bucket  : constant String := "bkt";
      Key     : constant String := "k";
      Created : ID_Array;
      Walk    : ID_Array;
      Walked  : Natural := 0;
      Result  : Storage.Status := Storage.Success;
      Options : Backends.List_Multipart_Uploads_Options;
      Page    : Backends.Multipart_Upload_Page;
   begin
      Store.Create_Bucket (Bucket, null, Deadline, Result);
      Check (Result = Storage.Success, "backend: bucket created");

      for Index in 1 .. Uploads_Wanted loop
         if Index > 1 then
            Support.Advance_One_Second;
         end if;
         Store.Create_Multipart_Upload
           (Bucket, Key, Backends.Default_Multipart_Options, null, Deadline,
            Created (Index), Result);
         Check (Result = Storage.Success,
                "backend: upload" & Image (Index) & " initiated");
         Note ("backend: initiation order" & Image (Index) & " id "
               & US.To_String (Created (Index)));
      end loop;

      --  Control: an unbounded listing sees all of them, in page order.
      Options := (others => <>);
      Options.Maximum := 1_000;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Deadline, Page, Result);
      Check (Result = Storage.Success and then not Page.Is_Truncated,
             "control: unbounded listing succeeds and is complete");
      Check (Page.Uploads.Length =
               Ada.Containers.Count_Type (Uploads_Wanted),
             "control: unbounded listing returns every active upload");
      for Position in Page.Uploads.First_Index .. Page.Uploads.Last_Index loop
         Note ("backend: page order" & Image (Position) & " initiated "
               & Image_64 (Page.Uploads (Position).Initiated) & " id "
               & US.To_String (Page.Uploads (Position).Upload_ID));
      end loop;

      --  The walk under test: Maximum = 1, following the returned cursor.
      Options := (others => <>);
      Options.Maximum := 1;
      for Step in 1 .. 3 * Uploads_Wanted loop
         Store.List_Multipart_Uploads
           (Bucket, Options, null, Deadline, Page, Result);
         exit when Result /= Storage.Success;
         for Upload of Page.Uploads loop
            if Walked < Uploads_Wanted then
               Walked := Walked + 1;
               Walk (Walked) := Upload.Upload_ID;
            end if;
         end loop;
         Note ("backend: page" & Image (Step) & " uploads"
               & Image (Natural (Page.Uploads.Length)) & " truncated "
               & Boolean'Image (Page.Is_Truncated)
               & " next-key '" & US.To_String (Page.Next_After.Key)
               & "' next-id '" & US.To_String (Page.Next_After.Upload_ID)
               & "'");
         exit when not Page.Is_Truncated;
         Options.After := Page.Next_After;
      end loop;
      Check (Result = Storage.Success, "backend: every page succeeded");
      Note ("backend: walk returned" & Image (Walked) & " of"
            & Image (Uploads_Wanted) & " uploads");
      Check (Walked = Uploads_Wanted,
             "backend: paired-cursor walk returns every active upload");
      for Index in 1 .. Uploads_Wanted loop
         Check (Occurrences (Walk, Walked, Created (Index)) = 1,
                "backend: initiation order" & Image (Index)
                & " returned exactly once by the walk");
      end loop;
   end Backend_Walk;

   ------------------------------------------------------------------
   --  2. Same walk over the in-process S3 application.
   ------------------------------------------------------------------

   procedure Wire_Walk is
      Bucket  : constant String := "mpu-cursor";
      Key     : constant String := "k";
      Created : ID_Array;
      Walk    : ID_Array;
      Walked  : Natural := 0;
      Key_Marker : US.Unbounded_String;
      ID_Marker  : US.Unbounded_String;
      Truncated  : Boolean := True;
   begin
      declare
         Made : constant String := Run (Signed_Request ("PUT", "/" & Bucket));
      begin
         Check (Status_Code (Made) = 200, "wire: CreateBucket is 200");
      end;
      for Index in 1 .. Uploads_Wanted loop
         if Index > 1 then
            Support.Advance_One_Second;
         end if;
         declare
            Started : constant String := Run
              (Signed_Request
                 ("POST", "/" & Bucket & "/" & Key,
                  Query => [SigV4.Pair ("uploads", "")]));
            Body_Text : constant String := Body_Of (Started);
         begin
            Check (Status_Code (Started) = 200,
                   "wire: CreateMultipartUpload" & Image (Index) & " is 200");
            Created (Index) := US.To_Unbounded_String
              (First_Element (Body_Text, "UploadId"));
            Note ("wire: initiation order" & Image (Index) & " id "
                  & US.To_String (Created (Index)));
         end;
      end loop;

      --  Control: an unbounded wire listing sees all six.
      declare
         Listed : constant String := Run
           (Signed_Request
              ("GET", "/" & Bucket,
               Query => [SigV4.Pair ("uploads", "")]));
         Document : constant String := Body_Of (Listed);
         Cursor   : Positive :=
           (if Document'Length = 0 then 1 else Document'First);
         Seen     : Natural := 0;
      begin
         Check (Status_Code (Listed) = 200,
                "control: wire ListMultipartUploads is 200");
         loop
            declare
               Value : constant String :=
                 Take_Element (Document, "UploadId", Cursor);
            begin
               exit when Value = "";
               Seen := Seen + 1;
            end;
         end loop;
         Note ("control: unbounded wire listing reported" & Image (Seen)
               & " uploads, IsTruncated "
               & First_Element (Document, "IsTruncated"));
         Check (Seen = Uploads_Wanted,
                "control: unbounded wire listing returns every upload");
      end;

      --  The walk under test.
      for Step in 1 .. 3 * Uploads_Wanted loop
         exit when not Truncated;
         declare
            Response : constant String := Run
              (Signed_Request
                 ("GET", "/" & Bucket,
                  Query =>
                    [SigV4.Pair ("uploads", ""),
                     SigV4.Pair ("max-uploads", "1"),
                     SigV4.Pair ("key-marker", US.To_String (Key_Marker)),
                     SigV4.Pair
                       ("upload-id-marker", US.To_String (ID_Marker))]));
            Document : constant String := Body_Of (Response);
            Cursor   : Positive :=
              (if Document'Length = 0 then 1 else Document'First);
            Returned : Natural := 0;
         begin
            Check (Status_Code (Response) = 200,
                   "wire: page" & Image (Step) & " is 200");
            exit when Status_Code (Response) /= 200;
            loop
               declare
                  Value : constant String :=
                    Take_Element (Document, "UploadId", Cursor);
               begin
                  exit when Value = "";
                  Returned := Returned + 1;
                  if Walked < Uploads_Wanted then
                     Walked := Walked + 1;
                     Walk (Walked) := US.To_Unbounded_String (Value);
                  end if;
               end;
            end loop;
            Truncated := First_Element (Document, "IsTruncated") = "true";
            Key_Marker := US.To_Unbounded_String
              (First_Element (Document, "NextKeyMarker"));
            ID_Marker := US.To_Unbounded_String
              (First_Element (Document, "NextUploadIdMarker"));
            Note ("wire: page" & Image (Step) & " uploads" & Image (Returned)
                  & " IsTruncated " & Boolean'Image (Truncated)
                  & " NextKeyMarker '" & US.To_String (Key_Marker)
                  & "' NextUploadIdMarker '" & US.To_String (ID_Marker)
                  & "'");
         end;
      end loop;
      Note ("wire: walk returned" & Image (Walked) & " of"
            & Image (Uploads_Wanted) & " uploads");
      Check (Walked = Uploads_Wanted,
             "wire: paired-cursor walk returns every active upload");
      for Index in 1 .. Uploads_Wanted loop
         Check (Occurrences (Walk, Walked, Created (Index)) = 1,
                "wire: initiation order" & Image (Index)
                & " returned exactly once by the walk");
      end loop;
   end Wire_Walk;

begin
   Backend_Walk;
   Wire_Walk;
   Finish;
end Repro_Backend_Memory_1;
