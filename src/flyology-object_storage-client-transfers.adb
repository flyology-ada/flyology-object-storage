with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Streams;
with Flyology.IO;
with Flyology.IO.Files;
with Flyology.HTTP.Client.Request_Bodies.Files;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Requests;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Task_Scopes;
with GNAT.OS_Lib;
with GNAT.SHA256;

package body Flyology.Object_Storage.Client.Transfers is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Files renames Flyology.IO.Files;
   package File_Bodies renames Flyology.HTTP.Client.Request_Bodies.Files;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package Requests renames Flyology.Object_Storage.S3.Requests;
   package Encoding renames
     Flyology.Object_Storage.S3.SigV4_Encoding;

   package Digest_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => GNAT.SHA256.Message_Digest);
   subtype Digests is Digest_Vectors.Vector;

   use type Ada.Real_Time.Time;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Files.File_Descriptor;
   use type Files.File_Offset;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Head_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type Requests.Target_Kind;
   use type Requests.Target_Status;

   Hash_Buffer_Size : constant := 64 * 1_024;
   Transfer_Buffer_Size : constant := 64 * 1_024;

   type Client_Access is access all HTTP_Client.Client;
   type Credentials_Access is access constant Low_Level.Credentials;

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
      Digest   : out GNAT.SHA256.Message_Digest;
      Part_Digests : out Digests;
      Size     : out Byte_Count)
   is
      Context : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Part_Context : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. Hash_Buffer_Size);
      Last    : Ada.Streams.Stream_Element_Offset;
      Offset  : Files.File_Offset := 0;
      Count   : Byte_Count;
      Part_Used : Byte_Count := 0;
   begin
      Size := 0;
      Part_Digests.Clear;
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
                  Part_Used := Part_Used + Taken;
                  First := First + Taken_Offset;
                  if Part_Used = Part_Size then
                     if Part_Digests.Length < 10_000 then
                        Part_Digests.Append
                          (GNAT.SHA256.Digest (Part_Context));
                     end if;
                     Part_Context := GNAT.SHA256.Initial_Context;
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
      end if;
      Digest := GNAT.SHA256.Digest (Context);
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
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Style, Bucket, Key, Identity, Region,
              Current_Timestamp, Content_Type);
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
               Parameters : constant Low_Level.Upload_Part_Parameters :=
                 (Part_Number => Core.Part_Number (Index),
                  Upload_ID => Upload_ID,
                  Payload_SHA256 =>
                    US.To_Unbounded_String (String (Part_Digest)),
                  others => <>);
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Origin, Style, Bucket, Key, Parameters, Identity, Region,
                    Current_Timestamp);
               Source : File_Bodies.Range_Source
                 (File, Files.File_Offset (Offset),
                  Flyology.HTTP.Body_Size (Count));
               Outcome : constant Low_Level.Upload_Part_Outcome :=
                 Low_Level.Execute_Upload_Part
                   (Client, Prepared, Source, Remaining (Deadline), Token);
            begin
               if Outcome.Kind = Low_Level.Upload_Rejected then
                  Abort_Best_Effort;
                  Initiated := False;
                  return
                    (Kind   => Upload_Rejected,
                     Status => Outcome.Status,
                     Error  => Outcome.Error);
               end if;
               Completion.Parts.Append
                 (Multipart.Completed_Part'
                    (Number     => Core.Part_Number (Index),
                     Entity_Tag => Outcome.Result.Entity_Tag,
                     others     => <>));
               Offset := Offset + Count;
            end;
         end loop;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Complete_Multipart_Upload
                (Origin, Style, Bucket, Key, US.To_String (Upload_ID),
                 Completion, Identity, Region, Current_Timestamp);
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
            Initiated := False;
            return
              (Kind       => File_Uploaded,
               Status     => Outcome.Status,
               Bytes      => Size,
               Entity_Tag => Outcome.Result.Entity_Tag);
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
      Multipart_Part_Size : Byte_Count := Default_Multipart_Part_Size)
      return Upload_Outcome
   is
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
      File     : aliased Files.File_Descriptor := Files.Invalid_File;
      Digest   : GNAT.SHA256.Message_Digest;
      Part_Digests : Digests;
      Size     : Byte_Count;
   begin
      Check_Cancelled (Token);
      if Local_Path'Length = 0 then
         raise Constraint_Error with "local upload path is empty";
      elsif not Core.Valid_Multipart_Part_Size (Multipart_Part_Size)
      then
         raise Constraint_Error with "invalid multipart part size";
      end if;
      File := Files.Open (Local_Path, Files.Read_Only);
      Hash_File
        (File, Deadline, Token, Multipart_Part_Size, Digest, Part_Digests,
         Size);
      if Size > 0 and then Size >= Multipart_Threshold then
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
                 Multipart_Part_Size, Part_Digests, Identity, Region, Style,
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
               Files.Close (File);
               return
                 (Kind       => File_Uploaded,
                  Status     => Outcome.Status,
                  Bytes      => Size,
                  Entity_Tag => Outcome.Result.Entity_Tag);
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
            Parameters : Low_Level.Copy_Object_Parameters;
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
            Parameters.Copy_Source_If_Match :=
              US.To_Unbounded_String (Source_If_Match);
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
      Token         : access Flyology.Cancellation.Token := null)
      return Head_Outcome
   is
      Deadline : constant Ada.Real_Time.Time := Deadline_For (Timeout);
      Parameters : Low_Level.Head_Object_Parameters;
   begin
      Check_Cancelled (Token);
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
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

end Flyology.Object_Storage.Client.Transfers;
