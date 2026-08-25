with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations.Drivers;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Flyology.IO.Files;
with Flyology.HTTP.Client.Request_Bodies.Files;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Requests;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Task_Scopes;
with GNAT.OS_Lib;
with GNAT.SHA256;

package body Flyology.Object_Storage.Client.Transfers is

   package US renames Ada.Strings.Unbounded;
   package Buffer_Drivers renames Flyology.Buffers.Drivers;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Operations renames Flyology.Operations;
   package Operation_Drivers renames Flyology.Operations.Drivers;
   package Low renames Flyology.Object_Storage.Client.Low_Level;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Requests renames Flyology.Object_Storage.S3.Requests;
   package Encoding renames
     Flyology.Object_Storage.S3.SigV4_Encoding;
   package Byte_Pointers is new System.Address_To_Access_Conversions
     (Ada.Streams.Stream_Element);

   use type Ada.Streams.Stream_Element_Offset;
   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Operations.Driver_Event;
   use type Requests.Target_Kind;
   use type Requests.Target_Status;
   use type System.Storage_Elements.Storage_Offset;
   use type US.Unbounded_String;

   Response_Limit_Exceeded : exception;

   function Failed_Reason
     (Kind : HTTP_Client.Exchange_Result_Kind) return Failure_Reason is
     (case Kind is
         when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
         when HTTP_Client.Cancelled => Cancelled,
         when HTTP_Client.Timed_Out => Timed_Out,
         when HTTP_Client.Client_Unavailable => Client_Unavailable,
         when HTTP_Client.Connection_Failed => Connection_Failed,
         when HTTP_Client.Transport_Failed => Transport_Failed,
         when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
         when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
         when HTTP_Client.Response_Complete |
              HTTP_Client.Response_Invalid |
              HTTP_Client.Response_Sink_Failed =>
           Corrupt_Or_Invalid_Response);

   function Failed_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Publication_Disposition is
   begin
      if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then
         return Cancelled_Before_Publication;
      elsif Admission = HTTP_Client.Not_Admitted then
         return Definitely_Not_Published;
      else
         return Outcome_Unknown;
      end if;
   end Failed_Disposition;

   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.Upload_Part_Copy_Outcome_Kind;
   --  SigV4 external wire contract: basic-format timestamps are UTC
   --  YYYYMMDD'T'HHMMSS'Z'. The slices below project that fixed shape from
   --  Ada.Calendar.Formatting.Image; changing them invalidates signatures.
   function Timestamp return String is
      Image : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => False, Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 3) &
        Image (Image'First + 5 .. Image'First + 6) &
        Image (Image'First + 8 .. Image'First + 9) & "T" &
        Image (Image'First + 11 .. Image'First + 12) &
        Image (Image'First + 14 .. Image'First + 15) &
        Image (Image'First + 17 .. Image'First + 18) & "Z";
   end Timestamp;

   package Files renames Flyology.IO.Files;
   package File_Bodies renames Flyology.HTTP.Client.Request_Bodies.Files;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;

   package Digest_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => GNAT.SHA256.Message_Digest);
   subtype Digests is Digest_Vectors.Vector;

   package Checksum_Value_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => US.Unbounded_String,
      "=" => US."=");
   subtype Checksum_Values is Checksum_Value_Vectors.Vector;

   use type Ada.Real_Time.Time;
   use type Ada.Containers.Count_Type;
   use type Files.File_Descriptor;
   use type Files.File_Offset;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Head_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type Checksum_Policy.Checksum_Type;

   Hash_Buffer_Size : constant := 64 * 1_024;
   Transfer_Buffer_Size : constant := 64 * 1_024;

   type Client_Access is access all HTTP_Client.Client;
   type Credentials_Access is access constant Low_Level.Credentials;

   --  Multipart part replacement cannot be transparently replayed after the
   --  first request may have reached S3.  This adapter deliberately exposes
   --  an otherwise rewindable borrowed file range as a one-shot source while
   --  retaining the same bounded synchronous lifetime and streaming reads.
   type One_Shot_Range_Source
     (Value : not null access File_Bodies.Range_Source)
   is limited new HTTP_Client.Request_Body_Source with null record;

   overriding function Declared_Length
     (Item : One_Shot_Range_Source) return HTTP_Client.Body_Length is
     (File_Bodies.Declared_Length (Item.Value.all));

   overriding procedure Read
     (Item     : in out One_Shot_Range_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token) is
   begin
      File_Bodies.Read
        (Item.Value.all, Data, Last, Finished, Timeout, Token);
   end Read;

   type Work_Item is record
      Client            : Client_Access;
      Origin            : Flyology.HTTP.Origin;
      Value             : Subject;
      Identity          : Credentials_Access;
      Region            : US.Unbounded_String;
      Style             : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Cancel_On_Failure : Boolean := False;
      Multipart_Threshold : Byte_Count := Default_Multipart_Threshold;
      Multipart_Part_Size : Byte_Count := Default_Multipart_Part_Size;
   end record;

   protected Temporary_Sequence is
      procedure Next (Value : out Long_Long_Integer);
   private
      Value : Long_Long_Integer := 0;
   end Temporary_Sequence;

   protected body Temporary_Sequence is
      procedure Next (Value : out Long_Long_Integer) is
      begin
         if Temporary_Sequence.Value = Long_Long_Integer'Last then
            Temporary_Sequence.Value := 1;
         else
            Temporary_Sequence.Value := Temporary_Sequence.Value + 1;
         end if;
         Value := Temporary_Sequence.Value;
      end Next;
   end Temporary_Sequence;

   function Current_Timestamp return String is
      Image : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => False,
         Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 3)
        & Image (Image'First + 5 .. Image'First + 6)
        & Image (Image'First + 8 .. Image'First + 9)
        & "T"
        & Image (Image'First + 11 .. Image'First + 12)
        & Image (Image'First + 14 .. Image'First + 15)
        & Image (Image'First + 17 .. Image'First + 18)
        & "Z";
   end Current_Timestamp;

   function Create_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Create_Multipart_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Create_Multipart_Result
   is
      --  The multipart parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Create_Multipart_Operation :=
           Create_Multipart_Upload
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Create_Multipart_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Create_Multipart_Upload;

   function Create_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Create_Multipart_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.Create_Multipart_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Multipart_Upload
          (Origin, Style, Bucket, Key, Parameters, Identity, Region,
           Current_Timestamp);
   begin
      return Low_Level.Execute_Create_Multipart_Upload
        (Client, Prepared, Timeout, Token);
   end Create_Multipart_Upload;

   function Abort_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Request_Payer : String := "";
      Expected_Bucket_Owner : String := "";
      If_Match_Initiated_Time : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Multipart_Abort_Result
   is
      Parameters : constant Low_Level.Abort_Multipart_Parameters :=
        (Request_Payer => US.To_Unbounded_String (Request_Payer),
         Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner),
         If_Match_Initiated_Time =>
           US.To_Unbounded_String (If_Match_Initiated_Time));
      --  The abort parent, HTTP exchange, and HTTP's single active transport
      --  child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Abort_Multipart_Operation :=
           Abort_Multipart_Upload
             (Set'Access, Client'Access, Origin, Bucket, Key, Upload_ID,
              Parameters, Identity, Flyology.HTTP.Client.Deadline_After
                (Timeout),
              Region, Style, Token);
         Result : Multipart_Abort_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Abort_Multipart_Upload;

   function Abort_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Request_Payer : String := "";
      Expected_Bucket_Owner : String := "";
      If_Match_Initiated_Time : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.Abort_Multipart_Outcome
   is
      Parameters : constant Low_Level.Abort_Multipart_Parameters :=
        (Request_Payer => US.To_Unbounded_String (Request_Payer),
         Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner),
         If_Match_Initiated_Time =>
           US.To_Unbounded_String (If_Match_Initiated_Time));
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Abort_Multipart_Upload
          (Origin, Style, Bucket, Key, Upload_ID, Parameters, Identity,
           Region, Current_Timestamp);
   begin
      return Low_Level.Execute_Abort_Multipart_Upload
        (Client, Prepared, Timeout, Token);
   end Abort_Multipart_Upload;

   function List_Parts_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.List_Parts_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return List_Parts_Result
   is
      --  The ListParts parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : List_Parts_Operation :=
           List_Parts_Page
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout),
              Region, Style, Token);
         Result : List_Parts_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end List_Parts_Page;

   function List_Parts_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.List_Parts_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.List_Parts_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_List_Parts
          (Origin, Style, Bucket, Key, Parameters, Identity, Region,
           Current_Timestamp);
   begin
      return Low_Level.Execute_List_Parts
        (Client, Prepared, Timeout, Token);
   end List_Parts_Page;

   function List_Multipart_Uploads_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Parameters   : Low_Level.List_Multipart_Uploads_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return List_Multipart_Uploads_Result
   is
      --  The listing parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : List_Multipart_Uploads_Operation :=
           List_Multipart_Uploads_Page
             (Set'Access, Client'Access, Origin, Bucket, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout),
              Region, Style, Token);
         Result : List_Multipart_Uploads_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end List_Multipart_Uploads_Page;

   function List_Multipart_Uploads_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Parameters   : Low_Level.List_Multipart_Uploads_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.List_Multipart_Uploads_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_List_Multipart_Uploads
          (Origin, Style, Bucket, Parameters, Identity, Region,
           Current_Timestamp);
   begin
      return Low_Level.Execute_List_Multipart_Uploads
        (Client, Prepared, Timeout, Token);
   end List_Multipart_Uploads_Page;

   function Upload_Part
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Upload_Part_Parameters;
      Source       : in out
        Flyology.HTTP.Client.Request_Body_Source'Class;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.Upload_Part_Outcome
   is
   begin
      if Source in HTTP_Client.Rewindable_Request_Body_Source'Class then
         raise Low_Level.Invalid_Request with
           "UploadPart requires a one-shot request body source";
      end if;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Upload_Part
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Current_Timestamp);
      begin
         return Low_Level.Execute_Upload_Part
           (Client, Prepared, Source, Timeout, Token);
      end;
   end Upload_Part;

   function Upload_Part
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Upload_Part_Result
   is
      --  The UploadPart parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Upload_Part_Operation :=
           Upload_Part
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Payload_Buffer, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Upload_Part_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result, Payload_Buffer);
         return Result;
      end;
   end Upload_Part;

   function Complete_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Completion   : Multipart.Complete_Multipart_Upload_Request;
      Parameters   : Low_Level.Complete_Multipart_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Multipart_Completion_Result
   is
      --  The completion parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Complete_Multipart_Operation :=
           Complete_Multipart_Upload
             (Set'Access, Client'Access, Origin, Bucket, Key, Upload_ID,
              Completion, Parameters, Identity,
              HTTP_Client.Deadline_After (Timeout), Region, Style, Token);
         Result : Multipart_Completion_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Complete_Multipart_Upload;

   function Deadline_For (Timeout : Duration) return Ada.Real_Time.Time is
   begin
      if Timeout < 0.0 then
         return Ada.Real_Time.Time_Last;
      end if;
      return Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (Timeout);
   exception
      when Constraint_Error =>
         return Ada.Real_Time.Time_Last;
   end Deadline_For;

   function Remaining (Deadline : Ada.Real_Time.Time) return Duration is
      Now : Ada.Real_Time.Time;
   begin
      if Deadline = Ada.Real_Time.Time_Last then
         return -1.0;
      end if;
      Now := Ada.Real_Time.Clock;
      if Now >= Deadline then
         raise Flyology.IO.Timeout_Error;
      end if;
      return Ada.Real_Time.To_Duration (Deadline - Now);
   end Remaining;

   procedure Check_Cancelled
     (Token : access Flyology.Cancellation.Token) is
   begin
      if Token /= null and then Token.Requested then
         raise Flyology.Cancellation.Operation_Cancelled;
      end if;
   end Check_Cancelled;

   procedure Close_After_Failure (File : in out Files.File_Descriptor) is
   begin
      if File /= Files.Invalid_File then
         begin
            Files.Close (File);
         exception
            when others =>
               null;
         end;
      end if;
   end Close_After_Failure;

   procedure Delete_After_Failure (Path : String) is
   begin
      if Path'Length > 0 and then Ada.Directories.Exists (Path) then
         begin
            Ada.Directories.Delete_File (Path);
         exception
            when others =>
               null;
         end;
      end if;
   end Delete_After_Failure;

   function New_Temporary_Path (Local_Path : String) return String is
      Sequence : Long_Long_Integer;
   begin
      for Attempt in 1 .. 16 loop
         Temporary_Sequence.Next (Sequence);
         declare
            Candidate : constant String :=
              Local_Path & ".flyology-"
              & GNAT.SHA256.Digest
                  (Local_Path & Character'Val (0)
                   & Long_Long_Integer'Image (Sequence)
                   & Ada.Calendar.Time'Image (Ada.Calendar.Clock))
              & ".part";
         begin
            if not Ada.Directories.Exists (Candidate) then
               return Candidate;
            end if;
         end;
      end loop;
      raise Flyology.IO.Device_Error with
        "could not allocate a temporary download path";
   end New_Temporary_Path;

   procedure Request_Cancellation
     (Token : access Flyology.Cancellation.Token) is
   begin
      if Token /= null and then not Token.Requested then
         begin
            Token.Request;
         exception
            when others =>
               null;
         end;
      end if;
   end Request_Cancellation;

   procedure Execute_Transfer
     (Input    : Work_Item;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Transfer_Result)
   is
      Failed_Operation : Boolean := False;
   begin
      Result := (others => <>);
      if Input.Client = null or else Input.Identity = null then
         raise Program_Error with "invalid structured transfer context";
      end if;
      case Input.Value.Kind is
         when Upload =>
            declare
               Outcome : constant Upload_Outcome := Upload_File
                 (Input.Client.all, Input.Origin,
                  US.To_String (Input.Value.Bucket),
                  US.To_String (Input.Value.Key),
                  US.To_String (Input.Value.Local_Path), Input.Identity.all,
                  US.To_String (Input.Region), Input.Style,
                  US.To_String (Input.Value.Content_Type),
                  Remaining (Deadline), Token,
                  Input.Multipart_Threshold, Input.Multipart_Part_Size);
            begin
               case Outcome.Kind is
                  when File_Uploaded =>
                     Result :=
                       (State      => Completed,
                        Status     => Outcome.Status,
                        Bytes      => Outcome.Bytes,
                        Entity_Tag => Outcome.Entity_Tag,
                        others     => <>);
                  when Upload_Rejected =>
                     Result :=
                       (State      => Rejected,
                        Status     => Outcome.Status,
                        Error_Code => Outcome.Error.Code,
                        Message    => Outcome.Error.Message,
                        others     => <>);
                     Failed_Operation := True;
               end case;
            end;
         when Download =>
            declare
               Outcome : constant Download_Outcome := Download_File
                 (Input.Client.all, Input.Origin,
                  US.To_String (Input.Value.Bucket),
                  US.To_String (Input.Value.Key),
                  US.To_String (Input.Value.Local_Path), Input.Identity.all,
                  US.To_String (Input.Region), Input.Style,
                  Remaining (Deadline), Token);
            begin
               case Outcome.Kind is
                  when File_Downloaded =>
                     Result :=
                       (State      => Completed,
                        Status     => Outcome.Status,
                        Bytes      => Outcome.Bytes,
                        Entity_Tag => Outcome.Entity_Tag,
                        others     => <>);
                  when Download_Rejected =>
                     Result :=
                       (State      => Rejected,
                        Status     => Outcome.Status,
                        Error_Code => Outcome.Error.Code,
                        Message    => Outcome.Error.Message,
                        others     => <>);
                     Failed_Operation := True;
               end case;
            end;
      end case;
      if Failed_Operation and then Input.Cancel_On_Failure then
         Request_Cancellation (Token);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled =>
         Result :=
           (State   => Cancelled,
            Message => US.To_Unbounded_String ("transfer cancelled"),
            others  => <>);
         if Input.Cancel_On_Failure then
            Request_Cancellation (Token);
         end if;
      when Flyology.IO.Timeout_Error =>
         Result :=
           (State   => Failed,
            Message => US.To_Unbounded_String ("transfer deadline expired"),
            others  => <>);
         if Input.Cancel_On_Failure then
            Request_Cancellation (Token);
         end if;
      when Occurrence : others =>
         Result :=
           (State   => Failed,
            Message => US.To_Unbounded_String
              (Ada.Exceptions.Exception_Name (Occurrence) & ": "
               & Ada.Exceptions.Exception_Message (Occurrence)),
            others  => <>);
         if Input.Cancel_On_Failure then
            Request_Cancellation (Token);
         end if;
   end Execute_Transfer;

   package Structured_Transfers is new Flyology.Task_Scopes
     (Input_Type  => Work_Item,
      Result_Type => Transfer_Result,
      Execute     => Execute_Transfer);

   procedure Hash_File
     (File     : Files.File_Descriptor;
      Deadline : Ada.Real_Time.Time;
      Token    : access Flyology.Cancellation.Token;
      Part_Size : Byte_Count;
      Selection : Upload_Checksum_Selection;
      Digest   : out GNAT.SHA256.Message_Digest;
      Part_Digests : out Digests;
      Part_Checksums : out Checksum_Values;
      Object_Checksum : out US.Unbounded_String;
      Size     : out Byte_Count)
   is
      Context : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Part_Context : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Object_Checksum_Context : Checksums.Context (Selection.Algorithm);
      Part_Checksum_Context : Checksums.Context (Selection.Algorithm);
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. Hash_Buffer_Size);
      Last    : Ada.Streams.Stream_Element_Offset;
      Offset  : Files.File_Offset := 0;
      Count   : Byte_Count;
      Part_Used : Byte_Count := 0;
   begin
      Size := 0;
      Part_Digests.Clear;
      Part_Checksums.Clear;
      Object_Checksum := US.Null_Unbounded_String;
      loop
         Check_Cancelled (Token);
         Files.Read_At
           (File, Offset, Buffer, Last, Remaining (Deadline), Token);
         exit when Last < Buffer'First;
         Count := Byte_Count (Last - Buffer'First + 1);
         if Size > Byte_Count'Last - Count
           or else Offset > Files.File_Offset'Last - Files.File_Offset (Count)
         then
            raise Constraint_Error with "local file exceeds supported size";
         end if;
         GNAT.SHA256.Update (Context, Buffer (Buffer'First .. Last));
         if Selection.Enabled then
            Checksums.Update
              (Object_Checksum_Context, Buffer (Buffer'First .. Last));
         end if;
         declare
            First : Ada.Streams.Stream_Element_Offset := Buffer'First;
         begin
            while First <= Last loop
               declare
                  Available : constant Byte_Count :=
                    Byte_Count (Last - First + 1);
                  Taken : constant Byte_Count :=
                    Byte_Count'Min (Available, Part_Size - Part_Used);
                  Taken_Offset : constant Ada.Streams.Stream_Element_Offset :=
                    Ada.Streams.Stream_Element_Offset (Taken);
               begin
                  GNAT.SHA256.Update
                    (Part_Context,
                     Buffer (First .. First + Taken_Offset - 1));
                  if Selection.Enabled then
                     Checksums.Update
                       (Part_Checksum_Context,
                        Buffer (First .. First + Taken_Offset - 1));
                  end if;
                  Part_Used := Part_Used + Taken;
                  First := First + Taken_Offset;
                  if Part_Used = Part_Size then
                     if Part_Digests.Length < 10_000 then
                        Part_Digests.Append
                          (GNAT.SHA256.Digest (Part_Context));
                     end if;
                     Part_Context := GNAT.SHA256.Initial_Context;
                     if Selection.Enabled
                       and then Part_Checksums.Length < 10_000
                     then
                        Part_Checksums.Append
                          (US.To_Unbounded_String
                             (Checksums.Encode_Base64
                                (Checksums.Finish
                                   (Part_Checksum_Context))));
                        Checksums.Reset (Part_Checksum_Context);
                     end if;
                     Part_Used := 0;
                  end if;
               end;
            end loop;
         end;
         Size := Size + Count;
         Offset := Offset + Files.File_Offset (Count);
      end loop;
      if Part_Used > 0 and then Part_Digests.Length < 10_000 then
         Part_Digests.Append (GNAT.SHA256.Digest (Part_Context));
         if Selection.Enabled and then Part_Checksums.Length < 10_000 then
            Part_Checksums.Append
              (US.To_Unbounded_String
                 (Checksums.Encode_Base64
                    (Checksums.Finish (Part_Checksum_Context))));
         end if;
      end if;
      Digest := GNAT.SHA256.Digest (Context);
      if Selection.Enabled then
         if Selection.Kind = Checksum_Policy.Composite
           and then not Part_Checksums.Is_Empty
         then
            declare
               Parts : Checksums.Digest_Array
                 (1 .. Natural (Part_Checksums.Length));
            begin
               for Index in Parts'Range loop
                  declare
                     Decoded : constant Checksums.Decode_Result :=
                       Checksums.Decode_Base64
                         (US.To_String (Part_Checksums (Index)),
                          Selection.Algorithm);
                  begin
                     if not Decoded.Valid then
                        raise Program_Error with
                          "invalid locally computed part checksum";
                     end if;
                     Parts (Index) := Decoded.Value;
                  end;
               end loop;
               Object_Checksum := US.To_Unbounded_String
                 (Checksums.Encode_Object
                    (Checksums.Composite (Selection.Algorithm, Parts),
                     Selection.Kind, Parts'Length));
            end;
         else
            Object_Checksum := US.To_Unbounded_String
              (Checksums.Encode_Base64
                 (Checksums.Finish (Object_Checksum_Context)));
         end if;
      end if;
   end Hash_File;

   function Upload_Multipart_File
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      File         : not null access Files.File_Descriptor;
      Size         : Byte_Count;
      Part_Size    : Byte_Count;
      Part_Digests : Digests;
      Part_Checksums : Checksum_Values;
      Object_Checksum : US.Unbounded_String;
      Selection    : Upload_Checksum_Selection;
      Identity     : Low_Level.Credentials;
      Region       : String;
      Style        : Low_Level.Addressing_Style;
      Content_Type : String;
      Deadline     : Ada.Real_Time.Time;
      Token        : access Flyology.Cancellation.Token)
      return Upload_Outcome
   is
      Upload_ID : US.Unbounded_String;
      Initiated : Boolean := False;

      function Create_Parameters return Low_Level.Create_Multipart_Parameters
      is
         Result : Low_Level.Create_Multipart_Parameters;
      begin
         Result.Content_Type := US.To_Unbounded_String (Content_Type);
         if Selection.Enabled then
            Result.Checksum_Algorithm := US.To_Unbounded_String
              (Checksum_Policy.Wire_Name (Selection.Algorithm));
            Result.Checksum_Type := US.To_Unbounded_String
              (Checksum_Policy.Wire_Name (Selection.Kind));
         end if;
         return Result;
      end Create_Parameters;

      function Complete_Parameters
        return Low_Level.Complete_Multipart_Parameters
      is
         Result : Low_Level.Complete_Multipart_Parameters;
         Text : constant String := US.To_String (Object_Checksum);
         Dash : constant Natural :=
           Ada.Strings.Fixed.Index
             (Text, "-", Going => Ada.Strings.Backward);
         Completion_Checksum : constant US.Unbounded_String :=
           (if Selection.Enabled
              and then Selection.Kind = Checksum_Policy.Composite
            then
              (if Dash = 0
               then raise Program_Error with
                 "missing composite checksum part-count suffix"
               else US.To_Unbounded_String (Text (Text'First .. Dash - 1)))
            else Object_Checksum);
      begin
         if not Selection.Enabled then
            return Result;
         end if;
         Result.Mpu_Object_Size := (Is_Set => True, Value => Size);
         Result.Checksum_Type := US.To_Unbounded_String
           (Checksum_Policy.Wire_Name (Selection.Kind));
         case Selection.Algorithm is
            when Core.CRC32 =>
               Result.Checksum_CRC32 := Completion_Checksum;
            when Core.CRC32C =>
               Result.Checksum_CRC32C := Completion_Checksum;
            when Core.CRC64NVME =>
               Result.Checksum_CRC64NVME := Completion_Checksum;
            when Core.SHA1 =>
               Result.Checksum_SHA1 := Completion_Checksum;
            when Core.SHA256 =>
               Result.Checksum_SHA256 := Completion_Checksum;
            when Core.SHA512 =>
               Result.Checksum_SHA512 := Completion_Checksum;
            when Core.MD5 =>
               Result.Checksum_MD5 := Completion_Checksum;
            when Core.XXHASH64 =>
               Result.Checksum_XXHASH64 := Completion_Checksum;
            when Core.XXHASH3 =>
               Result.Checksum_XXHASH3 := Completion_Checksum;
            when Core.XXHASH128 =>
               Result.Checksum_XXHASH128 := Completion_Checksum;
         end case;
         return Result;
      end Complete_Parameters;

      procedure Set_Part_Checksum
        (Value      : US.Unbounded_String;
         Parameters : in out Low_Level.Upload_Part_Parameters;
         Completed  : in out Multipart.Completed_Part) is
      begin
         if not Selection.Enabled then
            return;
         end if;
         Parameters.Checksum_Algorithm := US.To_Unbounded_String
           (Checksum_Policy.Wire_Name (Selection.Algorithm));
         case Selection.Algorithm is
            when Core.CRC32 =>
               Parameters.Checksum_CRC32 := Value;
               Completed.Checksum_CRC32 := Value;
            when Core.CRC32C =>
               Parameters.Checksum_CRC32C := Value;
               Completed.Checksum_CRC32C := Value;
            when Core.CRC64NVME =>
               Parameters.Checksum_CRC64NVME := Value;
               Completed.Checksum_CRC64NVME := Value;
            when Core.SHA1 =>
               Parameters.Checksum_SHA1 := Value;
               Completed.Checksum_SHA1 := Value;
            when Core.SHA256 =>
               Parameters.Checksum_SHA256 := Value;
               Completed.Checksum_SHA256 := Value;
            when Core.SHA512 =>
               Parameters.Checksum_SHA512 := Value;
               Completed.Checksum_SHA512 := Value;
            when Core.MD5 =>
               Parameters.Checksum_MD5 := Value;
               Completed.Checksum_MD5 := Value;
            when Core.XXHASH64 =>
               Parameters.Checksum_XXHASH64 := Value;
               Completed.Checksum_XXHASH64 := Value;
            when Core.XXHASH3 =>
               Parameters.Checksum_XXHASH3 := Value;
               Completed.Checksum_XXHASH3 := Value;
            when Core.XXHASH128 =>
               Parameters.Checksum_XXHASH128 := Value;
               Completed.Checksum_XXHASH128 := Value;
         end case;
      end Set_Part_Checksum;

      function Result_Checksum
        (Value : Low_Level.Complete_Multipart_Result)
         return US.Unbounded_String is
      begin
         case Selection.Algorithm is
            when Core.CRC32 => return Value.Checksum_CRC32;
            when Core.CRC32C => return Value.Checksum_CRC32C;
            when Core.CRC64NVME => return Value.Checksum_CRC64NVME;
            when Core.SHA1 => return Value.Checksum_SHA1;
            when Core.SHA256 => return Value.Checksum_SHA256;
            when Core.SHA512 => return Value.Checksum_SHA512;
            when Core.MD5 => return Value.Checksum_MD5;
            when Core.XXHASH64 => return Value.Checksum_XXHASH64;
            when Core.XXHASH3 => return Value.Checksum_XXHASH3;
            when Core.XXHASH128 => return Value.Checksum_XXHASH128;
         end case;
      end Result_Checksum;

      function Result_Checksum
        (Value : Low_Level.Upload_Part_Result)
         return US.Unbounded_String is
      begin
         case Selection.Algorithm is
            when Core.CRC32 => return Value.Checksum_CRC32;
            when Core.CRC32C => return Value.Checksum_CRC32C;
            when Core.CRC64NVME => return Value.Checksum_CRC64NVME;
            when Core.SHA1 => return Value.Checksum_SHA1;
            when Core.SHA256 => return Value.Checksum_SHA256;
            when Core.SHA512 => return Value.Checksum_SHA512;
            when Core.MD5 => return Value.Checksum_MD5;
            when Core.XXHASH64 => return Value.Checksum_XXHASH64;
            when Core.XXHASH3 => return Value.Checksum_XXHASH3;
            when Core.XXHASH128 => return Value.Checksum_XXHASH128;
         end case;
      end Result_Checksum;

      procedure Abort_Best_Effort is
      begin
         if not Initiated then
            return;
         end if;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Abort_Multipart_Upload
                (Origin, Style, Bucket, Key, US.To_String (Upload_ID),
                 Identity, Region, Current_Timestamp);
            Outcome : constant Low_Level.Abort_Multipart_Outcome :=
              Low_Level.Execute_Abort_Multipart_Upload
                (Client, Prepared, Timeout => 5.0, Token => null);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when others =>
            null;
      end Abort_Best_Effort;
   begin
      if Selection.Enabled
        and then Part_Checksums.Length /= Part_Digests.Length
      then
         raise Program_Error with "multipart checksum plan mismatch";
      end if;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Style, Bucket, Key, Create_Parameters, Identity, Region,
              Current_Timestamp);
         Outcome : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (Client, Prepared, Remaining (Deadline), Token);
      begin
         if Outcome.Kind = Low_Level.Create_Rejected then
            return
              (Kind   => Upload_Rejected,
               Status => Outcome.Status,
               Error  => Outcome.Error);
         end if;
         Upload_ID := Outcome.Result.Upload_ID;
         Initiated := True;
      end;

      declare
         Completion : Multipart.Complete_Multipart_Upload_Request;
         Offset     : Byte_Count := 0;
      begin
         for Index in Part_Digests.First_Index ..
           Part_Digests.Last_Index
         loop
            declare
               Count : constant Byte_Count :=
                 Byte_Count'Min (Part_Size, Size - Offset);
               Part_Digest : constant GNAT.SHA256.Message_Digest :=
                 Part_Digests (Index);
               Parameters : Low_Level.Upload_Part_Parameters :=
                 (Part_Number => Core.Part_Number (Index),
                  Upload_ID => Upload_ID,
                  Payload_SHA256 =>
                    US.To_Unbounded_String (String (Part_Digest)),
                  others => <>);
               Completed : Multipart.Completed_Part :=
                 (Number => Core.Part_Number (Index), others => <>);
               Range_Value : aliased File_Bodies.Range_Source
                 (File, Files.File_Offset (Offset),
                  Flyology.HTTP.Body_Size (Count));
               Source : One_Shot_Range_Source (Range_Value'Access);
            begin
               if Selection.Enabled then
                  Set_Part_Checksum
                    (Part_Checksums (Index), Parameters, Completed);
               end if;
               declare
                  Outcome : constant Low_Level.Upload_Part_Outcome :=
                    Upload_Part
                      (Client, Origin, Bucket, Key, Parameters, Source,
                       Identity, Region, Style, Remaining (Deadline), Token);
               begin
                  if Outcome.Kind = Low_Level.Upload_Rejected then
                     Abort_Best_Effort;
                     Initiated := False;
                     return
                       (Kind   => Upload_Rejected,
                        Status => Outcome.Status,
                        Error  => Outcome.Error);
                  end if;
                  if Selection.Enabled
                    and then Result_Checksum (Outcome.Result) /=
                      Part_Checksums (Index)
                  then
                     raise Low_Level.Invalid_Response with
                       "UploadPart response checksum does not match file";
                  end if;
                  Completed.Entity_Tag := Outcome.Result.Entity_Tag;
                  Completion.Parts.Append (Completed);
                  Offset := Offset + Count;
               end;
            end;
         end loop;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Complete_Multipart_Upload
                (Origin, Style, Bucket, Key, US.To_String (Upload_ID),
                 Completion, Complete_Parameters, Identity, Region,
                 Current_Timestamp);
            Outcome : constant Low_Level.Complete_Multipart_Outcome :=
              Low_Level.Execute_Complete_Multipart_Upload
                (Client, Prepared, Remaining (Deadline), Token);
         begin
            if Outcome.Kind = Low_Level.Complete_Rejected then
               Abort_Best_Effort;
               Initiated := False;
               return
                 (Kind   => Upload_Rejected,
                  Status => Outcome.Status,
                  Error  => Outcome.Error);
            end if;
            if Selection.Enabled
              and then
                (Result_Checksum (Outcome.Result) /= Object_Checksum
                 or else
                   (US.Length (Outcome.Result.Checksum_Type) > 0
                    and then US.To_String (Outcome.Result.Checksum_Type) /=
                      Checksum_Policy.Wire_Name (Selection.Kind)))
            then
               raise Low_Level.Invalid_Response with
                 "CompleteMultipartUpload checksum does not match file";
            end if;
            Initiated := False;
            return
              (Kind       => File_Uploaded,
               Status     => Outcome.Status,
               Bytes      => Size,
               Entity_Tag => Outcome.Result.Entity_Tag,
               Checksum =>
                 (if Selection.Enabled
                  then Result_Checksum (Outcome.Result)
                  else US.Null_Unbounded_String),
               Checksum_Type =>
                 (if Selection.Enabled
                  then US.To_Unbounded_String
                    (Checksum_Policy.Wire_Name (Selection.Kind))
                  else US.Null_Unbounded_String));
         end;
      end;
   exception
      when others =>
         Abort_Best_Effort;
         Initiated := False;
         raise;
   end Upload_Multipart_File;

   function Upload_File
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Local_Path   : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null;
      Multipart_Threshold : Byte_Count := Default_Multipart_Threshold;
      Multipart_Part_Size : Byte_Count := Default_Multipart_Part_Size;
      Checksum : Upload_Checksum_Selection := Default_Upload_Checksum)
      return Upload_Outcome
   is
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
      File     : aliased Files.File_Descriptor := Files.Invalid_File;
      Digest   : GNAT.SHA256.Message_Digest;
      Part_Digests : Digests;
      Part_Checksums : Checksum_Values;
      Object_Checksum : US.Unbounded_String;
      Size     : Byte_Count;

      procedure Set_Put_Checksum
        (Parameters : in out Low_Level.Put_Object_Parameters) is
      begin
         if not Checksum.Enabled then
            return;
         end if;
         Parameters.Checksum_Algorithm := US.To_Unbounded_String
           (Checksum_Policy.Wire_Name (Checksum.Algorithm));
         case Checksum.Algorithm is
            when Core.CRC32 =>
               Parameters.Checksum_CRC32 := Object_Checksum;
            when Core.CRC32C =>
               Parameters.Checksum_CRC32C := Object_Checksum;
            when Core.CRC64NVME =>
               Parameters.Checksum_CRC64NVME := Object_Checksum;
            when Core.SHA1 =>
               Parameters.Checksum_SHA1 := Object_Checksum;
            when Core.SHA256 =>
               Parameters.Checksum_SHA256 := Object_Checksum;
            when Core.SHA512 =>
               Parameters.Checksum_SHA512 := Object_Checksum;
            when Core.MD5 =>
               Parameters.Checksum_MD5 := Object_Checksum;
            when Core.XXHASH64 =>
               Parameters.Checksum_XXHASH64 := Object_Checksum;
            when Core.XXHASH3 =>
               Parameters.Checksum_XXHASH3 := Object_Checksum;
            when Core.XXHASH128 =>
               Parameters.Checksum_XXHASH128 := Object_Checksum;
         end case;
      end Set_Put_Checksum;

      function Result_Checksum
        (Value : Low_Level.Put_Object_Result)
         return US.Unbounded_String is
      begin
         case Checksum.Algorithm is
            when Core.CRC32 => return Value.Checksum_CRC32;
            when Core.CRC32C => return Value.Checksum_CRC32C;
            when Core.CRC64NVME => return Value.Checksum_CRC64NVME;
            when Core.SHA1 => return Value.Checksum_SHA1;
            when Core.SHA256 => return Value.Checksum_SHA256;
            when Core.SHA512 => return Value.Checksum_SHA512;
            when Core.MD5 => return Value.Checksum_MD5;
            when Core.XXHASH64 => return Value.Checksum_XXHASH64;
            when Core.XXHASH3 => return Value.Checksum_XXHASH3;
            when Core.XXHASH128 => return Value.Checksum_XXHASH128;
         end case;
      end Result_Checksum;
   begin
      Check_Cancelled (Token);
      if Local_Path'Length = 0 then
         raise Constraint_Error with "local upload path is empty";
      elsif not Core.Valid_Multipart_Part_Size (Multipart_Part_Size)
      then
         raise Constraint_Error with "invalid multipart part size";
      elsif Checksum.Enabled
        and then Checksum.Kind = Checksum_Policy.Composite
        and then not Checksum_Policy.Supported
          (Checksum.Algorithm, Checksum.Kind)
      then
         raise Constraint_Error with
           "unsupported multipart checksum algorithm and type";
      end if;
      File := Files.Open (Local_Path, Files.Read_Only);
      Hash_File
        (File, Deadline, Token, Multipart_Part_Size, Checksum, Digest,
         Part_Digests, Part_Checksums, Object_Checksum, Size);
      if Checksum.Enabled
        and then Checksum.Kind = Checksum_Policy.Composite
        and then Size = 0
      then
         raise Constraint_Error with
           "composite checksum requires a nonempty multipart upload";
      end if;
      if Size > 0
        and then Size >= Multipart_Threshold
        and then Checksum.Enabled
        and then not Checksum_Policy.Supported
          (Checksum.Algorithm, Checksum.Kind)
      then
         raise Constraint_Error with
           "checksum policy is not supported for multipart upload";
      end if;
      if Size > 0
        and then
          (Size >= Multipart_Threshold
           or else
             (Checksum.Enabled
              and then Checksum.Kind = Checksum_Policy.Composite))
      then
         if not Core.Valid_Multipart_Plan (Size, Multipart_Part_Size)
           or else Byte_Count (Part_Digests.Length) /=
             Core.Multipart_Part_Count (Size, Multipart_Part_Size)
         then
            raise Constraint_Error with "invalid multipart upload plan";
         end if;
         declare
            Outcome : constant Upload_Outcome :=
              Upload_Multipart_File
                (Client, Origin, Bucket, Key, File'Access, Size,
                 Multipart_Part_Size, Part_Digests, Part_Checksums,
                 Object_Checksum, Checksum, Identity, Region, Style,
                 Content_Type, Deadline, Token);
         begin
            Files.Close (File);
            return Outcome;
         end;
      end if;
      declare
         Parameters : Low_Level.Put_Object_Parameters;
      begin
         Parameters.Content_Type := US.To_Unbounded_String (Content_Type);
         Set_Put_Checksum (Parameters);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object
                (Origin, Style, Bucket, Key, Parameters, String (Digest),
                 Identity, Region, Current_Timestamp);
            Source : File_Bodies.Range_Source
              (File'Access, 0, Flyology.HTTP.Body_Size (Size));
            Outcome : constant Low_Level.Put_Object_Outcome :=
              Low_Level.Execute_Put_Object
                (Client, Prepared, Source, Remaining (Deadline), Token);
         begin
            if Outcome.Kind = Low_Level.Object_Put then
               if Checksum.Enabled
                 and then
                   (Result_Checksum (Outcome.Result) /= Object_Checksum
                    or else
                      (US.Length (Outcome.Result.Checksum_Type) > 0
                       and then US.To_String (Outcome.Result.Checksum_Type) /=
                         "FULL_OBJECT"))
               then
                  raise Low_Level.Invalid_Response with
                    "PutObject checksum does not match file";
               end if;
               Files.Close (File);
               return
                 (Kind       => File_Uploaded,
                  Status     => Outcome.Status,
                  Bytes      => Size,
                  Entity_Tag => Outcome.Result.Entity_Tag,
                  Checksum =>
                    (if Checksum.Enabled
                     then Result_Checksum (Outcome.Result)
                     else US.Null_Unbounded_String),
                  Checksum_Type =>
                    (if Checksum.Enabled
                     then US.To_Unbounded_String ("FULL_OBJECT")
                     else US.Null_Unbounded_String));
            else
               Files.Close (File);
               return
                 (Kind   => Upload_Rejected,
                  Status => Outcome.Status,
                  Error  => Outcome.Error);
            end if;
         end;
      end;
   exception
      when others =>
         if File /= Files.Invalid_File then
            Files.Close (File);
         end if;
         raise;
   end Upload_File;

   function Upload_Part_Copy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Upload_Part_Copy_Result
   is
      --  The copy-part parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Upload_Part_Copy_Operation :=
           Upload_Part_Copy
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Upload_Part_Copy_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Upload_Part_Copy;

   function Copy_Object
     (Client             : aliased in out Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout            : Duration := 30.0;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Result
   is
      --  The copy parent, HTTP exchange, and HTTP's single active transport
      --  child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Copy_Operation :=
           Copy_Object
             (Set'Access, Client'Access, Origin, Source_Bucket, Source_Key,
              Destination_Bucket, Destination_Key, Options, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Copy_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Copy_Object;

   function Copy_Object
     (Client             : aliased in out Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout            : Duration := 30.0;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Outcome
   is
      Maximum_Copy_Source_Length : constant :=
        Requests.Maximum_Target_Length - 1;
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
   begin
      Check_Cancelled (Token);
      if Source_Bucket'Length = 0
        or else Source_Key'Length = 0
        or else Source_Bucket'Length >= Maximum_Copy_Source_Length
        or else Source_Key'Length >
          Maximum_Copy_Source_Length - Source_Bucket'Length - 1
      then
         raise Low_Level.Invalid_Request with "invalid CopyObject source";
      end if;
      declare
         Raw_Source : constant String := Source_Bucket & "/" & Source_Key;
         Encoded_Source : constant String :=
           Encoding.URI_Encode (Raw_Source, Encode_Slash => False);
      begin
         if Encoded_Source'Length > Maximum_Copy_Source_Length then
            raise Low_Level.Invalid_Request with
              "encoded CopyObject source exceeds header limit";
         end if;
         declare
            Source_Target : constant String := "/" & Encoded_Source;
            Parsed_Source : constant Requests.Target_Result :=
              Requests.Parse_Target (Source_Target);
            Parameters : Low_Level.Copy_Object_Parameters := Options;
         begin
            if Parsed_Source.Status /= Requests.Target_Parsed
              or else Parsed_Source.Kind /= Requests.Object_Target
              or else Requests.Bucket_Name
                (Source_Target, Parsed_Source) /= Source_Bucket
              or else Requests.Object_Key
                (Source_Target, Parsed_Source) /= Source_Key
            then
               raise Low_Level.Invalid_Request with
                 "invalid CopyObject source bucket or key";
            end if;
            Parameters.Copy_Source :=
              US.To_Unbounded_String (Encoded_Source);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Copy_Object
                   (Origin, Style, Destination_Bucket, Destination_Key,
                    Parameters, Identity, Region, Current_Timestamp);
               Outcome : constant Low_Level.Copy_Object_Outcome :=
                 Low_Level.Execute_Copy_Object
                   (Client, Prepared, Remaining (Deadline), Token);
            begin
               if Outcome.Kind = Low_Level.Copy_Object_Rejected then
                  return
                    (Kind   => Copy_Rejected,
                     Status => Outcome.Status,
                     Error  => Outcome.Error);
               end if;
               return
                 (Kind                   => Object_Copied,
                  Status                 => Outcome.Status,
                  Details                => Outcome.Result,
                  Entity_Tag             =>
                    Outcome.Result.Copy_Result.Entity_Tag,
                  Last_Modified          =>
                    Outcome.Result.Copy_Result.Last_Modified,
                  Version_ID             => Outcome.Result.Version_ID,
                  Copy_Source_Version_ID =>
                    Outcome.Result.Copy_Source_Version_ID);
            end;
         end;
      end;
   end Copy_Object;

   function Copy_Object
     (Client             : aliased in out Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Identity           : Low_Level.Credentials;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Source_If_Match    : String := "";
      Timeout            : Duration := 30.0;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Outcome
   is
      Options : Low_Level.Copy_Object_Parameters;
   begin
      Options.Copy_Source_If_Match :=
        US.To_Unbounded_String (Source_If_Match);
      return Copy_Object
        (Client, Origin, Source_Bucket, Source_Key, Destination_Bucket,
         Destination_Key, Options, Identity, Region, Style, Timeout, Token);
   end Copy_Object;

   function Head_Object
     (Client        : aliased in out Flyology.HTTP.Client.Client;
      Origin        : Flyology.HTTP.Origin;
      Bucket        : String;
      Key           : String;
      Identity      : Low_Level.Credentials;
      Region        : String := "us-east-1";
      Style         : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID    : String := "";
      If_Match      : String := "";
      Checksum_Mode : Boolean := False;
      Timeout       : Duration := 30.0;
      Token         : access Flyology.Cancellation.Token := null;
      If_Modified_Since : String := "";
      If_None_Match : String := "";
      If_Unmodified_Since : String := "";
      Byte_Range_Header : String := "";
      Response_Cache_Control : String := "";
      Response_Content_Disposition : String := "";
      Response_Content_Encoding : String := "";
      Response_Content_Language : String := "";
      Response_Content_Type : String := "";
      Response_Expires : String := "";
      SSE_Customer_Algorithm : String := "";
      SSE_Customer_Key : String := "";
      SSE_Customer_Key_MD5 : String := "";
      Request_Payer : String := "";
      Part_Number : Low_Level.Optional_Part_Number :=
        (Is_Set => False, Value => 1);
      Expected_Bucket_Owner : String := "")
      return Head_Outcome
   is
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
      Parameters : Low_Level.Head_Object_Parameters;
   begin
      Check_Cancelled (Token);
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
      Parameters.If_Modified_Since :=
        US.To_Unbounded_String (If_Modified_Since);
      Parameters.If_None_Match := US.To_Unbounded_String (If_None_Match);
      Parameters.If_Unmodified_Since :=
        US.To_Unbounded_String (If_Unmodified_Since);
      Parameters.Byte_Range_Header :=
        US.To_Unbounded_String (Byte_Range_Header);
      Parameters.Response_Cache_Control :=
        US.To_Unbounded_String (Response_Cache_Control);
      Parameters.Response_Content_Disposition :=
        US.To_Unbounded_String (Response_Content_Disposition);
      Parameters.Response_Content_Encoding :=
        US.To_Unbounded_String (Response_Content_Encoding);
      Parameters.Response_Content_Language :=
        US.To_Unbounded_String (Response_Content_Language);
      Parameters.Response_Content_Type :=
        US.To_Unbounded_String (Response_Content_Type);
      Parameters.Response_Expires := US.To_Unbounded_String (Response_Expires);
      Parameters.SSE_Customer_Algorithm :=
        US.To_Unbounded_String (SSE_Customer_Algorithm);
      Parameters.SSE_Customer_Key := US.To_Unbounded_String (SSE_Customer_Key);
      Parameters.SSE_Customer_Key_MD5 :=
        US.To_Unbounded_String (SSE_Customer_Key_MD5);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Part_Number := Part_Number;
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Checksum_Mode := Checksum_Mode;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Head_Object
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Current_Timestamp);
         Outcome : constant Low_Level.Head_Object_Outcome :=
           Low_Level.Execute_Head_Object
             (Client, Prepared, Remaining (Deadline), Token);
      begin
         if Outcome.Kind = Low_Level.Head_Object_Rejected then
            return
              (Kind   => Head_Rejected,
               Status => Outcome.Status,
               Error  => Outcome.Error);
         end if;
         return
           (Kind            => Object_Found,
            Status          => Outcome.Status,
            Details         => Outcome.Result,
            Bytes           => Outcome.Result.Content_Length,
            Entity_Tag      => Outcome.Result.Entity_Tag,
            Last_Modified   => Outcome.Result.Last_Modified,
            Content_Type    => Outcome.Result.Content_Type,
            Version_ID      => Outcome.Result.Version_ID,
            Checksum_CRC32  => Outcome.Result.Checksum_CRC32,
            Checksum_CRC32C => Outcome.Result.Checksum_CRC32C,
            Checksum_SHA1   => Outcome.Result.Checksum_SHA1,
            Checksum_SHA256 => Outcome.Result.Checksum_SHA256,
            Checksum_Type   => Outcome.Result.Checksum_Type);
      end;
   end Head_Object;

   function Download_File
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Local_Path : String;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Version_ID : String := "";
      If_Match   : String := "";
      If_Modified_Since : String := "";
      If_None_Match : String := "";
      If_Unmodified_Since : String := "";
      Byte_Range_Header : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False)
      return Download_Outcome
   is
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
      File     : Files.File_Descriptor := Files.Invalid_File;
      Temp     : US.Unbounded_String;
      Published : Boolean := False;
   begin
      Check_Cancelled (Token);
      if Local_Path'Length = 0 then
         raise Constraint_Error with "local download path is empty";
      end if;
      declare
         Parameters : Low_Level.Get_Object_Parameters;
      begin
         Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
         Parameters.If_Match := US.To_Unbounded_String (If_Match);
         Parameters.If_Modified_Since :=
           US.To_Unbounded_String (If_Modified_Since);
         Parameters.If_None_Match := US.To_Unbounded_String (If_None_Match);
         Parameters.If_Unmodified_Since :=
           US.To_Unbounded_String (If_Unmodified_Since);
         Parameters.Byte_Range_Header :=
           US.To_Unbounded_String (Byte_Range_Header);
         Parameters.Expected_Bucket_Owner :=
           US.To_Unbounded_String (Expected_Bucket_Owner);
         Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
         Parameters.Checksum_Mode := Checksum_Mode;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Style, Bucket, Key, Parameters, Identity, Region,
                 Current_Timestamp);
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (Client, Prepared, Remaining (Deadline), Token);
            Head : constant Low_Level.Get_Object_Head_Outcome :=
              Low_Level.Decode_Get_Object_Response_Head
                (Response, Token);
         begin
            if Head.Kind = Low_Level.Get_Object_Rejected then
               return
                 (Kind   => Download_Rejected,
                  Status => Head.Status,
                  Error  => Head.Error);
            elsif (Byte_Range_Header'Length = 0 and then Head.Status /= 200)
              or else
                (Byte_Range_Header'Length > 0 and then Head.Status /= 206)
            then
               raise Low_Level.Invalid_Response with
                 "GetObject returned an unsolicited representation interval";
            end if;

            Temp := US.To_Unbounded_String (New_Temporary_Path (Local_Path));
            File := Files.Open
              (US.To_String (Temp), Files.Write_Only,
               Create => True, Truncate => True);
            declare
               Buffer   : Ada.Streams.Stream_Element_Array
                 (1 .. Transfer_Buffer_Size);
               Last     : Ada.Streams.Stream_Element_Offset;
               Finished : Boolean := False;
               Offset   : Files.File_Offset := 0;
               Total    : Byte_Count := 0;
            begin
               while not Finished loop
                  HTTP_Client.Read_Body
                    (Response, Buffer, Last, Finished, Token);
                  if Last >= Buffer'First then
                     declare
                        First : Ada.Streams.Stream_Element_Offset :=
                          Buffer'First;
                     begin
                        while First <= Last loop
                           declare
                              Written_Last :
                                Ada.Streams.Stream_Element_Offset;
                              Count : Byte_Count;
                           begin
                              Files.Write_At
                                (File, Offset, Buffer (First .. Last),
                                 Written_Last, Token);
                              if Written_Last < First then
                                 raise Flyology.IO.Device_Error with
                                   "download file write made no progress";
                              end if;
                              Count := Byte_Count (Written_Last - First + 1);
                              if Total > Byte_Count'Last - Count
                                or else Offset >
                                  Files.File_Offset'Last
                                    - Files.File_Offset (Count)
                              then
                                 raise Constraint_Error with
                                   "download exceeds supported size";
                              end if;
                              Total := Total + Count;
                              Offset := Offset + Files.File_Offset (Count);
                              First := Written_Last + 1;
                              Check_Cancelled (Token);
                              declare
                                 Ignored : constant Duration :=
                                   Remaining (Deadline);
                                 pragma Unreferenced (Ignored);
                              begin
                                 null;
                              end;
                           end;
                        end loop;
                     end;
                  end if;
               end loop;
               Check_Cancelled (Token);
               if Head.Result.Content_Length.Is_Set
                 and then Total /= Head.Result.Content_Length.Value
               then
                  raise Low_Level.Invalid_Response with
                    "GetObject body length differs from its response head";
               end if;
               declare
                  Ignored : constant Duration := Remaining (Deadline);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
               Files.Close (File);
               declare
                  Renamed : Boolean;
               begin
                  GNAT.OS_Lib.Rename_File
                    (US.To_String (Temp), Local_Path, Renamed);
                  if not Renamed then
                     raise Flyology.IO.Device_Error with
                       "could not publish downloaded file";
                  end if;
               end;
               Published := True;
               return
                 (Kind       => File_Downloaded,
                  Status     => Head.Status,
                  Bytes      => Total,
                  Entity_Tag => Head.Result.Entity_Tag);
            end;
         end;
      end;
   exception
      when others =>
         Close_After_Failure (File);
         if not Published then
            Delete_After_Failure (US.To_String (Temp));
         end if;
         raise;
   end Download_File;

   procedure Transfer_Many
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Subjects : Subject_Array;
      Results  : out Transfer_Result_Array;
      Identity : aliased Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Options  : Batch_Options := (others => <>);
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
   is
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
      Total : constant Natural := Subjects'Length;
      Buffer_Slots : constant Byte_Count :=
        Options.Maximum_In_Flight_Bytes / Byte_Count (Transfer_Buffer_Size);
      Offset : Natural := 0;

      procedure Mark_Remaining
        (State : Transfer_Status; Message : String) is
      begin
         if Offset < Total then
            for Remaining_Offset in Offset .. Total - 1 loop
               Results (Subjects'First + Remaining_Offset) :=
                 (State   => State,
                  Message => US.To_Unbounded_String (Message),
                  others  => <>);
            end loop;
         end if;
      end Mark_Remaining;
   begin
      if Subjects'First /= Results'First
        or else Subjects'Last /= Results'Last
      then
         raise Constraint_Error with
           "transfer subjects and results ranges do not match";
      end if;
      Results := (others => <>);
      if Total = 0 then
         return;
      elsif Buffer_Slots = 0 then
         raise Constraint_Error with
           "transfer byte budget is smaller than one 64 KiB buffer";
      elsif Token /= null and then Token.Requested then
         Mark_Remaining (Cancelled, "batch cancelled before admission");
         return;
      end if;

      declare
         Byte_Workers : constant Positive := Positive
           (Byte_Count'Min (Buffer_Slots, Byte_Count (Positive'Last)));
         Worker_Limit : constant Positive := Positive'Min
           (Options.Maximum_Concurrent_Objects,
            Positive'Min
              (Options.Maximum_Concurrent_Requests, Byte_Workers));
      begin
         while Offset < Total loop
            declare
               Wave_Count : constant Positive := Positive'Min
                 (Worker_Limit, Positive (Total - Offset));
               Group : Structured_Transfers.Scope (Wave_Count, Token);
               Handles : array (1 .. Wave_Count) of
                 Structured_Transfers.Operation_Handle;
               Wave_Failed : Boolean := False;
            begin
               Structured_Transfers.Configure
                 (Group, Deadline,
                  Cancel_Siblings_On_Failure =>
                    Options.On_Failure = Cancel_Remaining);
               for Position in Handles'Range loop
                  declare
                     Index : constant Positive :=
                       Subjects'First + Offset + Position - 1;
                  begin
                     --  Both unchecked borrows are confined to Group. Join
                     --  completes every operation before either formal can
                     --  leave scope, and Work_Item never escapes the group.
                     Structured_Transfers.Spawn
                       (Group,
                        (Client            => Client'Unchecked_Access,
                         Origin            => Origin,
                         Value             => Subjects (Index),
                         Identity          => Identity'Unchecked_Access,
                         Region            => US.To_Unbounded_String (Region),
                         Style             => Style,
                         Cancel_On_Failure =>
                           Options.On_Failure = Cancel_Remaining,
                         Multipart_Threshold =>
                           Options.Multipart_Threshold,
                         Multipart_Part_Size =>
                           Options.Multipart_Part_Size),
                        Handles (Position));
                  end;
               end loop;
               Structured_Transfers.Join (Group);
               for Position in Handles'Range loop
                  declare
                     Index : constant Positive :=
                       Subjects'First + Offset + Position - 1;
                  begin
                     if Structured_Transfers.Succeeded
                       (Group, Handles (Position))
                     then
                        Results (Index) := Structured_Transfers.Result
                          (Group, Handles (Position));
                     else
                        begin
                           Results (Index) := Structured_Transfers.Result
                             (Group, Handles (Position));
                        exception
                           when Flyology.Cancellation.Operation_Cancelled =>
                              Results (Index) :=
                                (State   => Cancelled,
                                 Message => US.To_Unbounded_String
                                   ("transfer cancelled before execution"),
                                 others  => <>);
                           when Flyology.IO.Timeout_Error =>
                              Results (Index) :=
                                (State   => Failed,
                                 Message => US.To_Unbounded_String
                                   ("transfer deadline expired"),
                                 others  => <>);
                           when Occurrence : others =>
                              Results (Index) :=
                                (State   => Failed,
                                 Message => US.To_Unbounded_String
                                   (Ada.Exceptions.Exception_Name
                                      (Occurrence)
                                    & ": "
                                    & Ada.Exceptions.Exception_Message
                                      (Occurrence)),
                                 others  => <>);
                        end;
                     end if;
                     if Results (Index).State /= Completed then
                        Wave_Failed := True;
                     end if;
                  end;
               end loop;
               Offset := Offset + Wave_Count;
               if Token /= null and then Token.Requested then
                  Mark_Remaining (Cancelled, "batch parent was cancelled");
                  return;
               elsif Options.On_Failure = Cancel_Remaining
                 and then Wave_Failed
               then
                  Mark_Remaining
                    (Cancelled, "not admitted after an earlier failure");
                  return;
               elsif Deadline /= Ada.Real_Time.Time_Last
                 and then Ada.Real_Time.Clock >= Deadline
               then
                  Mark_Remaining (Failed, "batch deadline expired");
                  return;
               end if;
            end;
         end loop;
      end;
   end Transfer_Many;

   function Normalize_Create_Multipart_Response
     (Value     : Low_Level.Create_Multipart_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Create_Multipart_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Create_Rejected
         then US.To_String (Value.Error.Code) else "");
      --  Wire authority: only exact modeled S3 status/code pairs establish
      --  rejection; changing this set changes mutation certainty semantics.
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400 and then Code = "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else (Value.Status = 404 and then Code = "NoSuchBucket");
      Retryable_Response : constant Boolean :=
        (Value.Status = 409 and then Code = "OperationAborted")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout");
      Failure : constant Failure_Reason :=
        (if Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif Value.Status = 400 and then Code = "InvalidRequest"
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Create_Multipart_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Creation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Created
            then Multipart_Upload_Created
            elsif Conclusive_Rejection
            then Definitely_Not_Created
            else Creation_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Created
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Create_Multipart_Response;

   function Normalize_Create_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Create_Multipart_Result is
   begin
      return
        (Kind        => Create_Multipart_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Creation_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Created
            else Creation_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Create_Multipart_Failure;

   overriding function Declared_Length
     (Item : Create_Multipart_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  Wire authority: CreateMultipartUpload has no request body.  The
      --  zero-length declaration prevents content from entering initiation.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Create_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Create_Multipart_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Create_Multipart_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Create_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "CreateMultipartUpload response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Create_Multipart_Child
     (Item : in out Create_Multipart_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              (Kind        => Create_Multipart_Exchange_Failed,
               Disposition =>
                 (if Admission = HTTP_Client.Not_Admitted
                  then Definitely_Not_Created
                  else Creation_Outcome_Unknown),
               Failure     => Corrupt_Or_Invalid_Response,
               Admission   => Admission,
               HTTP_Result => HTTP_Client.Response_Sink_Failed,
               HTTP_Phase  => HTTP_Client.Receiving_Response_Body,
               Detail      => US.Null_Unbounded_String);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Create_Multipart_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Create_Multipart_Response
              (Low_Level.Decode_Create_Multipart_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 (Kind        => Create_Multipart_Exchange_Failed,
                  Disposition => Creation_Outcome_Unknown,
                  Failure     => Corrupt_Or_Invalid_Response,
                  Admission   => HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Result => HTTP_Client.Response_Invalid,
                  HTTP_Phase  => HTTP_Client.Phase (HTTP_Result),
                  Detail      => US.Null_Unbounded_String);
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Create_Multipart_Child;

   overriding procedure Drive
     (Item : in out Create_Multipart_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Create_Multipart_Upload
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Create_Multipart_Child (Item);
      else
         raise Program_Error with
           "invalid CreateMultipartUpload driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Create_Multipart_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Create_Multipart_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Create_Multipart_Upload
     (Operation : in out Create_Multipart_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "CreateMultipartUpload restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Create_Multipart_Upload
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained initiation response bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Create_Multipart_Upload;

   function Create_Multipart_Upload
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Multipart_Operation is
   begin
      return Result : Create_Multipart_Operation (Set, Client, Token) do
         Start_Create_Multipart_Upload
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Create_Multipart_Upload;

   procedure Finish
     (Operation : in out Create_Multipart_Operation;
      Result    : out Create_Multipart_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "CreateMultipartUpload has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. A complete modeled
   --  rejection still does not prove that an earlier attempt did not stage a
   --  part, so only a validated success or definite non-admission changes
   --  publication certainty.
   function Normalize_Upload_Part_Response
     (Value     : Low_Level.Upload_Part_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Upload_Part_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Upload_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Part_Uploaded then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status = 400
           and then Code in
             "BadDigest" | "InvalidPart" | "InvalidRequest" |
             "EntityTooLarge"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Upload_Part_Response_Available,
         Disposition =>
           (if Admission = HTTP_Client.Response_Observed
              and then Value.Kind = Low_Level.Part_Uploaded
            then Part_Published
            else Part_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Upload_Part_Response;

   function Normalize_Upload_Part_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Upload_Part_Result is
   begin
      return
        (Kind        => Upload_Part_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Part_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Staged
            else Part_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Upload_Part_Failure;

   overriding function Declared_Length
     (Item : Upload_Part_Operation) return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Buffer_Drivers.Length (Item.Source)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Upload_Part_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural := Buffer_Drivers.Length (Item.Source);
      Count  : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Byte_Pointers.To_Pointer
             (Buffer_Drivers.Address (Item.Source) +
                System.Storage_Elements.Storage_Offset
                  (Item.Source_Position + Offset)).all;
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Upload_Part_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Upload_Part_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Upload_Part_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "UploadPart response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Upload_Part_Child
     (Item : in out Upload_Part_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Upload_Part_Failure
               (HTTP_Client.Response_Sink_Failed, Admission,
                HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            Low.Clear_Prepared_Request (Item.Prepared);
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Upload_Part_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Upload_Part_Response
              (Low_Level.Decode_Upload_Part_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Upload_Part_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Upload_Part_Child;

   overriding procedure Drive
     (Item : in out Upload_Part_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Upload_Part
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Upload_Part_Child (Item);
      else
         raise Program_Error with "invalid UploadPart driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Upload_Part_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Upload_Part_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Buffer_Drivers.Release (Item.Source);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Upload_Part
     (Operation : in out Upload_Part_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "UploadPart restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Upload_Part
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained UploadPart response bytes use the
        --  maintained limit of the S3 XML decoder that consumes errors.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Buffer_Drivers.Move_From (Payload_Buffer, Operation.Source);
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Buffer_Drivers.Has_Buffer (Operation.Source) then
               Buffer_Drivers.Move_To (Operation.Source, Payload_Buffer);
            end if;
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Upload_Part;

   function Upload_Part
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Upload_Part_Operation is
   begin
      return Result : Upload_Part_Operation (Set, Client, Token) do
         Start_Upload_Part
           (Result, Client, Origin, Bucket, Key, Parameters, Payload_Buffer,
            Identity, Deadline, Region, Style, Token);
      end return;
   end Upload_Part;

   procedure Finish
     (Operation : in out Upload_Part_Operation;
      Result    : out Upload_Part_Result;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer) is
   begin
      if not Buffer_Drivers.Same_Pool
        (Operation.Source, Payload_Buffer)
      then
         raise Program_Error with
           "UploadPart Finish requires the original buffer pool";
      end if;
      Operations.Consume (Operation);
      Buffer_Drivers.Move_To (Operation.Source, Payload_Buffer);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "UploadPart has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. Even a complete modeled
   --  rejection may be an embedded HTTP 200 error after server-side work, so
   --  only validated success or definite non-admission is conclusive.
   function Normalize_Complete_Multipart_Response
     (Value     : Low_Level.Complete_Multipart_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Multipart_Completion_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Complete_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Completed then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status in 200 | 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status in 200 | 400 | 412
           and then Code in
             "BadDigest" | "EntityTooSmall" | "InvalidPart" |
             "InvalidPartOrder" | "InvalidRequest" | "PreconditionFailed"
         then Invalid_Request
         elsif (Value.Status in 200 | 409
                  and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status in 200 | 500
                      and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Complete_Multipart_Response_Available,
         Disposition =>
           (if Admission = HTTP_Client.Response_Observed
              and then Value.Kind = Low_Level.Completed
            then Multipart_Completed
            else Completion_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Complete_Multipart_Response;

   function Normalize_Complete_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Completion_Result is
   begin
      return
        (Kind        => Complete_Multipart_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Completion_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Completed
            else Completion_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Complete_Multipart_Failure;

   overriding function Declared_Length
     (Item : Complete_Multipart_Operation) return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Item.Prepared)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Complete_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural :=
        Low.Owned_Payload_Length (Item.Prepared);
      Count : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Item.Prepared, Item.Source_Position + Offset + 1)));
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Complete_Multipart_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Complete_Multipart_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Complete_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "CompleteMultipartUpload response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Multipart_Child
     (Item : in out Complete_Multipart_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Complete_Multipart_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Complete_Multipart_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Complete_Multipart_Response
              (Low_Level.Decode_Complete_Multipart_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Complete_Multipart_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Multipart_Child;

   overriding procedure Drive
     (Item : in out Complete_Multipart_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Complete_Multipart_Upload
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Multipart_Child (Item);
      else
         raise Program_Error with
           "invalid CompleteMultipartUpload driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Complete_Multipart_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Complete_Multipart_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Complete_Multipart_Upload
     (Operation : in out Complete_Multipart_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "CompleteMultipartUpload restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Complete_Multipart_Upload
        (Origin, Style, Bucket, Key, Upload_ID, Completion, Parameters,
         Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained completion response bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Complete_Multipart_Upload;

   function Complete_Multipart_Upload
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Complete_Multipart_Operation is
   begin
      return Result : Complete_Multipart_Operation (Set, Client, Token) do
         Start_Complete_Multipart_Upload
           (Result, Client, Origin, Bucket, Key, Upload_ID, Completion,
            Parameters, Identity, Deadline, Region, Style, Token);
      end return;
   end Complete_Multipart_Upload;

   procedure Finish
     (Operation : in out Complete_Multipart_Operation;
      Result    : out Multipart_Completion_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "CompleteMultipartUpload has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority for bounded diagnostics.
   --  Only a validated 204 proves this abort request was accepted; every
   --  complete rejection remains conservative after possible admission.
   function Normalize_Abort_Multipart_Response
     (Value     : Low_Level.Abort_Multipart_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Multipart_Abort_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Abort_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Aborted then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status in 400 | 412
           and then Code in "InvalidRequest" | "PreconditionFailed"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Abort_Multipart_Response_Available,
         Disposition =>
           (if Admission = HTTP_Client.Response_Observed
              and then Value.Kind = Low_Level.Aborted
            then Multipart_Aborted
            else Abort_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Abort_Multipart_Response;

   function Normalize_Abort_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Abort_Result is
   begin
      return
        (Kind        => Abort_Multipart_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Abort_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Aborted
            else Abort_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Abort_Multipart_Failure;

   overriding function Declared_Length
     (Item : Abort_Multipart_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  S3 wire contract: AbortMultipartUpload has no request body.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Abort_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Abort_Multipart_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Abort_Multipart_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Abort_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "AbortMultipartUpload response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Abort_Multipart_Child
     (Item : in out Abort_Multipart_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Abort_Multipart_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Abort_Multipart_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Abort_Multipart_Response
              (Low_Level.Decode_Abort_Multipart_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Abort_Multipart_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Abort_Multipart_Child;

   overriding procedure Drive
     (Item : in out Abort_Multipart_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Abort_Multipart_Upload
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Abort_Multipart_Child (Item);
      else
         raise Program_Error with
           "invalid AbortMultipartUpload driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Abort_Multipart_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Abort_Multipart_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Abort_Multipart_Upload
     (Operation : in out Abort_Multipart_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "AbortMultipartUpload restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Abort_Multipart_Upload
        (Origin, Style, Bucket, Key, Upload_ID, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained abort error bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Abort_Multipart_Upload;

   function Abort_Multipart_Upload
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Abort_Multipart_Operation is
   begin
      return Result : Abort_Multipart_Operation (Set, Client, Token) do
         Start_Abort_Multipart_Upload
           (Result, Client, Origin, Bucket, Key, Upload_ID, Parameters,
            Identity, Deadline, Region, Style, Token);
      end return;
   end Abort_Multipart_Upload;

   procedure Finish
     (Operation : in out Abort_Multipart_Operation;
      Result    : out Multipart_Abort_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "AbortMultipartUpload has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListObjectVersions attempt;
   --  it does not authorize retry or join snapshots across pages.
   function Normalize_List_Parts_Response
     (Value     : Low_Level.List_Parts_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Parts_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.List_Parts_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Parts_Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => List_Parts_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Parts_Response;

   function Normalize_List_Parts_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Parts_Result is
   begin
      return
        (Kind        => List_Parts_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Parts_Failure;

   overriding procedure Write
     (Item : in out List_Parts_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListParts response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Parts_Child
     (Item : in out List_Parts_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Parts_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Parts_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Parts_Response
              (Low_Level.Decode_List_Parts_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Parts_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Parts_Child;

   overriding procedure Drive
     (Item : in out List_Parts_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.List_Parts
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Parts_Child (Item);
      else
         raise Program_Error with "invalid ListParts driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Parts_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Parts_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Parts
     (Operation : in out List_Parts_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListParts restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Parts
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained ListParts bytes use the maintained
        --  limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Parts;

   function List_Parts_Page
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Parts_Operation is
   begin
      return Result : List_Parts_Operation (Set, Client, Token) do
         Start_List_Parts
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end List_Parts_Page;

   procedure Finish
     (Operation : in out List_Parts_Operation;
      Result    : out List_Parts_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "ListParts has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListMultipartUploads
   --  attempt; it does not authorize retry or imply a shared snapshot with a
   --  later page.
   function Normalize_List_Multipart_Uploads_Response
     (Value     : Low_Level.List_Multipart_Uploads_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Multipart_Uploads_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.List_Multipart_Uploads_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Multipart_Uploads_Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Multipart_Uploads_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Multipart_Uploads_Response;

   function Normalize_List_Multipart_Uploads_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Multipart_Uploads_Result is
   begin
      return
        (Kind        => List_Multipart_Uploads_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Multipart_Uploads_Failure;

   overriding procedure Write
     (Item : in out List_Multipart_Uploads_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListMultipartUploads response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Multipart_Uploads_Child
     (Item : in out List_Multipart_Uploads_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Multipart_Uploads_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Multipart_Uploads_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Multipart_Uploads_Response
              (Low_Level.Decode_List_Multipart_Uploads_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Multipart_Uploads_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Multipart_Uploads_Child;

   overriding procedure Drive
     (Item : in out List_Multipart_Uploads_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.List_Multipart_Uploads
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Multipart_Uploads_Child (Item);
      else
         raise Program_Error with
           "invalid ListMultipartUploads driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Multipart_Uploads_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Multipart_Uploads_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Multipart_Uploads
     (Operation : in out List_Multipart_Uploads_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListMultipartUploads restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Multipart_Uploads
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained listing bytes use the maintained
        --  limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Multipart_Uploads;

   function List_Multipart_Uploads_Page
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Multipart_Uploads_Operation is
   begin
      return Result : List_Multipart_Uploads_Operation
        (Set, Client, Token)
      do
         Start_List_Multipart_Uploads
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end List_Multipart_Uploads_Page;

   procedure Finish
     (Operation : in out List_Multipart_Uploads_Operation;
      Result    : out List_Multipart_Uploads_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "ListMultipartUploads has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. This operation is never
   --  replayed, so an exact modeled rejection observed for its one request can
   --  prove non-publication; embedded or retryable errors remain ambiguous.
   function Normalize_Upload_Part_Copy_Response
     (Value     : Low_Level.Upload_Part_Copy_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Upload_Part_Copy_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Copy_Part_Rejected
         then US.To_String (Value.Error.Code) else "");
      Precondition_Rejection : constant Boolean :=
        Value.Status = 412 and then Code = "PreconditionFailed";
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in
           "InvalidArgument" | "InvalidPart" | "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else
          (Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload")
        or else (Value.Status = 501 and then Code = "NotImplemented");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Part_Copied then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status = 400
           and then Code in
             "InvalidArgument" | "InvalidPart" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 412 and then Code = "PreconditionFailed"
         then No_Failure
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status in 200 | 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
         (Kind        => Upload_Part_Copy_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Outcome_Unknown
            elsif Value.Kind = Low_Level.Part_Copied
            then Published
            elsif Precondition_Rejection
            then Precondition_Failed
            elsif Conclusive_Rejection
            then Definitely_Not_Published
            else Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Upload_Part_Copy_Response;

   function Normalize_Upload_Part_Copy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Upload_Part_Copy_Result is
   begin
      return
         (Kind        => Upload_Part_Copy_Exchange_Failed,
         Disposition => Failed_Disposition (Kind, Admission),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Upload_Part_Copy_Failure;

   overriding function Declared_Length
     (Item : Upload_Part_Copy_Operation)
      return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  S3 UploadPartCopy wire contract: the mutation has no request body.
      --  The one-shot zero-length source prevents transport-layer replay.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Upload_Part_Copy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Upload_Part_Copy_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Upload_Part_Copy_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Upload_Part_Copy_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "UploadPartCopy response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Upload_Part_Copy_Child
     (Item : in out Upload_Part_Copy_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Upload_Part_Copy_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Upload_Part_Copy_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Upload_Part_Copy_Response
              (Low_Level.Decode_Upload_Part_Copy_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Upload_Part_Copy_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Upload_Part_Copy_Child;

   overriding procedure Drive
     (Item : in out Upload_Part_Copy_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Upload_Part_Copy
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Upload_Part_Copy_Child (Item);
      else
         raise Program_Error with "invalid UploadPartCopy driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Upload_Part_Copy_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Upload_Part_Copy_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Upload_Part_Copy
     (Operation : in out Upload_Part_Copy_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "UploadPartCopy restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Upload_Part_Copy
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained UploadPartCopy response bytes use
        --  the maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Upload_Part_Copy;

   function Upload_Part_Copy
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Upload_Part_Copy_Operation is
   begin
      return Result : Upload_Part_Copy_Operation (Set, Client, Token) do
         Start_Upload_Part_Copy
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Upload_Part_Copy;

   procedure Finish
     (Operation : in out Upload_Part_Copy_Operation;
      Result    : out Upload_Part_Copy_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "UploadPartCopy has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. An embedded HTTP-200
   --  error is never conclusive publication evidence; only validated success,
   --  an exact precondition failure, or an exact non-mutating rejection can
   --  avoid read-only reconciliation.
   function Normalize_Copy_Response
     (Value     : Low_Level.Copy_Object_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Copy_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Copy_Object_Rejected
         then US.To_String (Value.Error.Code) else "");
      Precondition_Rejection : constant Boolean :=
        Value.Status = 412 and then Code = "PreconditionFailed";
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in "InvalidArgument" | "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else
          (Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey")
        or else (Value.Status = 501 and then Code = "NotImplemented");
      Retryable_Response : constant Boolean :=
        (Value.Status = 409 and then Code = "OperationAborted")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status in 200 | 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout");
      Failure : constant Failure_Reason :=
        (if Precondition_Rejection then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey"
         then Not_Found
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Copy_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Outcome_Unknown
            elsif Value.Kind = Low_Level.Object_Copied
            then Published
            elsif Precondition_Rejection
            then Precondition_Failed
            elsif Conclusive_Rejection
            then Definitely_Not_Published
            else Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Copied
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Copy_Response;

   function Normalize_Copy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Copy_Result is
   begin
      return
        (Kind        => Copy_Exchange_Failed,
         Disposition => Failed_Disposition (Kind, Admission),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Copy_Failure;

   overriding function Declared_Length
     (Item : Copy_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  S3 CopyObject wire contract: the mutation request has no body. The
      --  one-shot zero-length source prevents transport-layer replay.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Copy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Copy_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source (Item : in out Copy_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Copy_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "CopyObject response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Copy_Child (Item : in out Copy_Operation) is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Copy_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Copy_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Copy_Response
              (Low_Level.Decode_Copy_Object_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Copy_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Copy_Child;

   overriding procedure Drive
     (Item : in out Copy_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Copy_Object
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Copy_Child (Item);
      else
         raise Program_Error with "invalid CopyObject driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation (Item : in out Copy_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Copy_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   function Prepare_Copy_From_Raw_Source
     (Origin             : Flyology.HTTP.Origin;
      Style              : Low_Level.Addressing_Style;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Region             : String) return Low_Level.Prepared_Request
   is
      --  Derived header capacity: the leading slash consumes one byte of the
      --  maintained maximum request-target representation.
      Maximum_Copy_Source_Length : constant :=
        Requests.Maximum_Target_Length - 1;
   begin
      if Source_Bucket'Length = 0
        or else Source_Key'Length = 0
        or else Source_Bucket'Length >= Maximum_Copy_Source_Length
        or else Source_Key'Length >
          Maximum_Copy_Source_Length - Source_Bucket'Length - 1
      then
         raise Low_Level.Invalid_Request with "invalid CopyObject source";
      end if;
      declare
         Raw_Source : constant String := Source_Bucket & "/" & Source_Key;
         Encoded_Source : constant String :=
           Encoding.URI_Encode (Raw_Source, Encode_Slash => False);
      begin
         if Encoded_Source'Length > Maximum_Copy_Source_Length then
            raise Low_Level.Invalid_Request with
              "encoded CopyObject source exceeds header limit";
         end if;
         declare
            Source_Target : constant String := "/" & Encoded_Source;
            Parsed_Source : constant Requests.Target_Result :=
              Requests.Parse_Target (Source_Target);
            Parameters : Low_Level.Copy_Object_Parameters := Options;
         begin
            if Parsed_Source.Status /= Requests.Target_Parsed
              or else Parsed_Source.Kind /= Requests.Object_Target
              or else Requests.Bucket_Name
                (Source_Target, Parsed_Source) /= Source_Bucket
              or else Requests.Object_Key
                (Source_Target, Parsed_Source) /= Source_Key
            then
               raise Low_Level.Invalid_Request with
                 "invalid CopyObject source bucket or key";
            end if;
            Parameters.Copy_Source :=
              US.To_Unbounded_String (Encoded_Source);
            return Low_Level.Prepare_Copy_Object
              (Origin, Style, Destination_Bucket, Destination_Key,
               Parameters, Identity, Region, Timestamp);
         end;
      end;
   end Prepare_Copy_From_Raw_Source;

   procedure Start_Copy_Object
     (Operation          : in out Copy_Operation;
      Client             : not null access HTTP_Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Deadline           : HTTP_Client.Monotonic_Deadline;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token              : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "CopyObject restart changed a retained owner";
      end if;
      Operation.Prepared := Prepare_Copy_From_Raw_Source
        (Origin, Style, Source_Bucket, Source_Key, Destination_Bucket,
         Destination_Key, Options, Identity, Region);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained CopyObject response bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Copy_Object;

   function Copy_Object
     (Set                : not null access Operations.Completion_Set'Class;
      Client             : not null access HTTP_Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Deadline           : HTTP_Client.Monotonic_Deadline;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Operation is
   begin
      return Result : Copy_Operation (Set, Client, Token) do
         Start_Copy_Object
           (Result, Client, Origin, Source_Bucket, Source_Key,
            Destination_Bucket, Destination_Key, Options, Identity, Deadline,
            Region, Style, Token);
      end return;
   end Copy_Object;

   procedure Finish
     (Operation : in out Copy_Operation;
      Result    : out Copy_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "CopyObject has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure Create_Multipart_Upload
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Create_Multipart_Operation) is
   begin
      Start_Create_Multipart_Upload
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Create_Multipart_Upload;

   procedure Upload_Part
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Upload_Part_Operation) is
   begin
      Start_Upload_Part
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Payload_Buffer,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Upload_Part;

   procedure Complete_Multipart_Upload
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Complete_Multipart_Operation) is
   begin
      Start_Complete_Multipart_Upload
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Upload_ID,
         Completion,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Complete_Multipart_Upload;

   procedure Abort_Multipart_Upload
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Abort_Multipart_Operation) is
   begin
      Start_Abort_Multipart_Upload
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Upload_ID,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Abort_Multipart_Upload;

   procedure List_Parts_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Parts_Operation) is
   begin
      Start_List_Parts
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end List_Parts_Page;

   procedure List_Multipart_Uploads_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Multipart_Uploads_Operation) is
   begin
      Start_List_Multipart_Uploads
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end List_Multipart_Uploads_Page;

   procedure Upload_Part_Copy
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Upload_Part_Copy_Operation) is
   begin
      Start_Upload_Part_Copy
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Upload_Part_Copy;

   procedure Copy_Object
     (Client             : not null access Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Deadline           : Flyology.HTTP.Client.Monotonic_Deadline;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token              : access Flyology.Cancellation.Token := null;
      Operation          : in out Copy_Operation) is
   begin
      Start_Copy_Object
        (Operation,
         Client,
         Origin,
         Source_Bucket,
         Source_Key,
         Destination_Bucket,
         Destination_Key,
         Options,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Copy_Object;

end Flyology.Object_Storage.Client.Transfers;
