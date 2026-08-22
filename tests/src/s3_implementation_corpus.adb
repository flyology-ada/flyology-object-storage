with Ada.Command_Line;
with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.SigV4;

procedure S3_Implementation_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Stream_IO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Ada.Containers.Count_Type;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Upload_Part_Copy_Outcome_Kind;
   use type Transfers.Download_Outcome_Kind;
   use type Transfers.Upload_Outcome_Kind;

   Access_Key : constant String := "FLYOLOGYS3ORACLE";
   Secret_Key : constant String := "flyology-s3-oracle-secret-key-tests";
   Payload    : aliased constant String :=
     String'(1 .. 6 * 1_024 * 1_024 => 'm');

   type Upload_Source
     (Value : not null access constant String) is
     new HTTP_Client.Request_Body_Source with record
      Position : Natural := 0;
      Chunk    : Positive := 997;
   end record;

   overriding function Declared_Length
     (Item : Upload_Source) return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Item.Value'Length)));

   overriding procedure Read
     (Item     : in out Upload_Source;
      Data     : out Stream_Element_Array;
      Last     : out Stream_Element_Offset;
      Finished : out Boolean;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
      Remaining : constant Natural := Item.Value'Length - Item.Position;
      Count : constant Natural := Natural'Min
        (Remaining, Natural'Min (Natural (Data'Length), Item.Chunk));
   begin
      Data := (others => 0);
      if Count = 0 then
         Last := Data'First - 1;
      else
         for Offset in 0 .. Count - 1 loop
            Data (Data'First + Stream_Element_Offset (Offset)) :=
              Stream_Element
                (Character'Pos
                   (Item.Value
                      (Item.Value'First + Item.Position + Offset)));
         end loop;
         Last := Data'First + Stream_Element_Offset (Count - 1);
         Item.Position := Item.Position + Count;
      end if;
      Finished := Item.Position = Item.Value'Length;
   end Read;

   procedure Run
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Key       : String;
      Timestamp : String)
   is
      HTTP     : aliased HTTP_Client.Client (Capacity => 1);
      Identity : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);

      procedure Upload_High_Level_File is
         Local_Path : constant String :=
           "/tmp/flyology-object-storage-" & Key & ".bin";
         Download_Path : constant String := Local_Path & ".download";
         File : Stream_IO.File_Type;
         Buffer : constant Stream_Element_Array (1 .. 64 * 1_024) :=
           (others => Stream_Element (Character'Pos ('m')));
         Remaining : Natural := Payload'Length;

         procedure Require_Downloaded_Payload is
            Input : Stream_IO.File_Type;
            Data  : Stream_Element_Array (1 .. 64 * 1_024);
            Last  : Stream_Element_Offset;
            Total : Flyology.Object_Storage.Byte_Count := 0;
         begin
            Stream_IO.Open (Input, Stream_IO.In_File, Download_Path);
            loop
               Stream_IO.Read (Input, Data, Last);
               exit when Last < Data'First;
               for Index in Data'First .. Last loop
                  if Data (Index) /= Stream_Element (Character'Pos ('m')) then
                     raise Program_Error with
                       "high-level download changed object bytes";
                  end if;
               end loop;
               Total := Total
                 + Flyology.Object_Storage.Byte_Count
                     (Last - Data'First + 1);
            end loop;
            Stream_IO.Close (Input);
            if Total /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
            then
               raise Program_Error with
                 "high-level download returned the wrong byte count";
            end if;
         exception
            when others =>
               if Stream_IO.Is_Open (Input) then
                  Stream_IO.Close (Input);
               end if;
               raise;
         end Require_Downloaded_Payload;
      begin
         Stream_IO.Create (File, Stream_IO.Out_File, Local_Path);
         while Remaining > 0 loop
            declare
               Count : constant Natural :=
                 Natural'Min (Remaining, Natural (Buffer'Length));
            begin
               Stream_IO.Write
                 (File,
                  Buffer
                    (Buffer'First ..
                       Buffer'First + Stream_Element_Offset (Count - 1)));
               Remaining := Remaining - Count;
            end;
         end loop;
         Stream_IO.Close (File);
         declare
            Result : constant Transfers.Upload_Outcome :=
              Transfers.Upload_File
                (HTTP, Origin, Bucket, Key & "-high level+%25", Local_Path,
                 Identity, Content_Type => "application/octet-stream",
                 Timeout => 60.0,
                 Multipart_Threshold => 5 * 1_024 * 1_024,
                 Multipart_Part_Size => 5 * 1_024 * 1_024);
         begin
            if Result.Kind = Transfers.Upload_Rejected then
               raise Program_Error with
                 "S3 implementation rejected high-level file upload: "
                 & Result.Status'Image & " "
                 & US.To_String (Result.Error.Code) & " "
                 & US.To_String (Result.Error.Message);
            elsif Result.Bytes /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Result.Entity_Tag) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid high-level upload "
                 & "metadata: bytes="
                 & Flyology.Object_Storage.Byte_Count'Image (Result.Bytes)
                 & " etag=" & US.To_String (Result.Entity_Tag);
            end if;
         end;
         declare
            Result : constant Transfers.Download_Outcome :=
              Transfers.Download_File
                (HTTP, Origin, Bucket, Key & "-high level+%25",
                 Download_Path, Identity, Timeout => 60.0);
         begin
            if Result.Kind = Transfers.Download_Rejected then
               raise Program_Error with
                 "S3 implementation rejected high-level file download: "
                 & Result.Status'Image & " "
                 & US.To_String (Result.Error.Code) & " "
                 & US.To_String (Result.Error.Message);
            elsif Result.Bytes /=
              Flyology.Object_Storage.Byte_Count (Payload'Length)
              or else US.Length (Result.Entity_Tag) = 0
            then
               raise Program_Error with
                 "S3 implementation returned invalid high-level download "
                 & "metadata: bytes="
                 & Flyology.Object_Storage.Byte_Count'Image (Result.Bytes)
                 & " etag=" & US.To_String (Result.Entity_Tag);
            end if;
         end;
         Require_Downloaded_Payload;
         Ada.Directories.Delete_File (Local_Path);
         Ada.Directories.Delete_File (Download_Path);
      exception
         when others =>
            if Stream_IO.Is_Open (File) then
               Stream_IO.Close (File);
            end if;
            if Ada.Directories.Exists (Local_Path) then
               Ada.Directories.Delete_File (Local_Path);
            end if;
            if Ada.Directories.Exists (Download_Path) then
               Ada.Directories.Delete_File (Download_Path);
            end if;
            raise;
      end Upload_High_Level_File;

      procedure Require_Listed_Object is
         Parameters : Low_Level.List_Objects_V2_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Key);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Objects_V2
                (Origin, Low_Level.Path_Style, Bucket, Parameters,
                 Identity, "us-east-1", Timestamp);
            Outcome : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Listed
              or else Outcome.Listing.Contents.Length /= 1
              or else US.To_String
                (Outcome.Listing.Contents.First_Element.Key) /= Key
              or else Outcome.Listing.Contents.First_Element.Size /=
                Flyology.Object_Storage.Byte_Count (Payload'Length)
            then
               raise Program_Error with
                 "S3 implementation did not expose the completed object";
            end if;
         end;
      end Require_Listed_Object;

      procedure Copy_With_Multipart is
         Copy_Key : constant String := Key & "-copy-part";
         Prepared_Create : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Low_Level.Path_Style, Bucket, Copy_Key, Identity,
              "us-east-1", Timestamp);
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Create, Timeout => 30.0);
      begin
         if Created.Kind /= Low_Level.Created then
            raise Program_Error with
              "S3 implementation rejected copy-part initiation";
         end if;
         declare
            Upload_ID : constant String :=
              US.To_String (Created.Result.Upload_ID);
            Parameters : Low_Level.Upload_Part_Copy_Parameters;
         begin
            Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
            Parameters.Copy_Source :=
              US.To_Unbounded_String (Bucket & "/" & Key);
            declare
               Prepared_Copy : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part_Copy
                   (Origin, Low_Level.Path_Style, Bucket, Copy_Key,
                    Parameters, Identity, "us-east-1", Timestamp);
               Copied : constant Low_Level.Upload_Part_Copy_Outcome :=
                 Low_Level.Execute_Upload_Part_Copy
                   (HTTP, Prepared_Copy, Timeout => 60.0);
            begin
               if Copied.Kind /= Low_Level.Part_Copied then
                  raise Program_Error with
                    "S3 implementation rejected UploadPartCopy";
               end if;
               declare
                  Completion : Multipart.Complete_Multipart_Upload_Request;
               begin
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 1,
                        Entity_Tag => Copied.Result.Copy_Part.Entity_Tag,
                        others     => <>));
                  declare
                     Prepared_Complete : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Complete_Multipart_Upload
                         (Origin, Low_Level.Path_Style, Bucket, Copy_Key,
                          Upload_ID, Completion, Identity, "us-east-1",
                          Timestamp);
                     Completed : constant
                       Low_Level.Complete_Multipart_Outcome :=
                         Low_Level.Execute_Complete_Multipart_Upload
                           (HTTP, Prepared_Complete, Timeout => 30.0);
                  begin
                     if Completed.Kind /= Low_Level.Completed
                       or else US.To_String (Completed.Result.Key) /= Copy_Key
                     then
                        raise Program_Error with
                          "S3 implementation rejected copied-part completion";
                     end if;
                  end;
               end;
            end;
         end;
      end Copy_With_Multipart;

      procedure Copy_Whole_Object is
         Copy_Key : constant String := Key & "-copy-object";
         Parameters : Low_Level.Copy_Object_Parameters;
      begin
         Parameters.Copy_Source :=
           US.To_Unbounded_String (Bucket & "/" & Key);
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Copy_Object
                (Origin, Low_Level.Path_Style, Bucket, Copy_Key, Parameters,
                 Identity, "us-east-1", Timestamp);
            Copied : constant Low_Level.Copy_Object_Outcome :=
              Low_Level.Execute_Copy_Object
                (HTTP, Prepared, Timeout => 60.0);
         begin
            if Copied.Kind /= Low_Level.Object_Copied
              or else US.Length (Copied.Result.Copy_Result.Entity_Tag) = 0
              or else US.Length
                (Copied.Result.Copy_Result.Last_Modified) = 0
            then
               raise Program_Error with
                 "S3 implementation rejected typed CopyObject";
            end if;
         end;
      end Copy_Whole_Object;
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Parameters : Low_Level.List_Objects_V2_Parameters;
         Prepared : Low_Level.Prepared_Request;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Key);
         Prepared := Low_Level.Prepare_List_Objects_V2
           (Origin, Low_Level.Path_Style, Bucket, Parameters,
            Identity, "us-east-1", Timestamp);
         declare
            Outcome : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Listed
              or else not Outcome.Listing.Contents.Is_Empty
            then
               raise Program_Error with
                 "S3 implementation preflight list result mismatch";
            end if;
         end;
      end;
      declare
         Prepared_Create : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Low_Level.Path_Style, Bucket, Key, Identity,
              "us-east-1", Timestamp);
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Create, Timeout => 30.0);
      begin
         if Created.Kind /= Low_Level.Created then
            raise Program_Error with
              "S3 implementation rejected CreateMultipartUpload";
         end if;
         declare
            Upload_ID : constant String :=
              US.To_String (Created.Result.Upload_ID);
            Parameters : Low_Level.Upload_Part_Parameters;
            Source : Upload_Source (Payload'Access);
         begin
            Parameters.Upload_ID := US.To_Unbounded_String (Upload_ID);
            Parameters.Payload_SHA256 := US.To_Unbounded_String
              (SigV4.SHA256_Hex (Payload));
            declare
               Prepared_Upload : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Upload_Part
                   (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                    Identity, "us-east-1", Timestamp);
               Uploaded : constant Low_Level.Upload_Part_Outcome :=
                 Low_Level.Execute_Upload_Part
                   (HTTP, Prepared_Upload, Source, Timeout => 60.0);
            begin
               if Uploaded.Kind /= Low_Level.Part_Uploaded then
                  raise Program_Error with
                    "S3 implementation rejected UploadPart";
               end if;
               declare
                  Completion : Multipart.Complete_Multipart_Upload_Request;
               begin
                  Completion.Parts.Append
                    (Multipart.Completed_Part'
                       (Number     => 1,
                        Entity_Tag => Uploaded.Result.Entity_Tag,
                        others     => <>));
                  declare
                     Prepared_Complete : constant Low_Level.Prepared_Request :=
                       Low_Level.Prepare_Complete_Multipart_Upload
                         (Origin, Low_Level.Path_Style, Bucket, Key,
                          Upload_ID, Completion, Identity, "us-east-1",
                          Timestamp);
                     Completed : constant
                       Low_Level.Complete_Multipart_Outcome :=
                         Low_Level.Execute_Complete_Multipart_Upload
                           (HTTP, Prepared_Complete, Timeout => 30.0);
                  begin
                     if Completed.Kind /= Low_Level.Completed
                       or else US.To_String (Completed.Result.Key) /= Key
                     then
                        raise Program_Error with
                          "S3 implementation rejected CompleteMultipartUpload";
                     end if;
                  end;
               end;
            end;
         end;
      end;
      Require_Listed_Object;
      Copy_With_Multipart;
      Copy_Whole_Object;
      Upload_High_Level_File;
      declare
         Abort_Key : constant String := Key & "-aborted";
         Prepared_Create : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Multipart_Upload
             (Origin, Low_Level.Path_Style, Bucket, Abort_Key, Identity,
              "us-east-1", Timestamp);
         Created : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Create, Timeout => 30.0);
      begin
         if Created.Kind /= Low_Level.Created then
            raise Program_Error with
              "S3 implementation rejected abort-corpus initiation";
         end if;
         declare
            Prepared_Abort : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Abort_Multipart_Upload
                (Origin, Low_Level.Path_Style, Bucket, Abort_Key,
                 US.To_String (Created.Result.Upload_ID), Identity,
                 "us-east-1", Timestamp);
            Aborted : constant Low_Level.Abort_Multipart_Outcome :=
              Low_Level.Execute_Abort_Multipart_Upload
                (HTTP, Prepared_Abort, Timeout => 30.0);
         begin
            if Aborted.Kind /= Low_Level.Aborted then
               raise Program_Error with
                 "S3 implementation rejected AbortMultipartUpload";
            end if;
         end;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Run;

   procedure Require_Head_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Parameters : Low_Level.Head_Bucket_Parameters;
      Prepared   : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Head_Bucket
          (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
           "us-east-1", Timestamp);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Low_Level.Head_Bucket_Outcome :=
           Low_Level.Execute_Head_Bucket
             (HTTP, Prepared, Timeout => 30.0);
      begin
         if Outcome.Kind /= Low_Level.Bucket_Found then
            raise Program_Error with "S3 implementation rejected HeadBucket";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Require_Head_Bucket;

   procedure Create_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Parameters : Low_Level.Create_Bucket_Parameters;
      Prepared   : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Bucket
          (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
           "us-east-1", Timestamp);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Low_Level.Create_Bucket_Outcome :=
           Low_Level.Execute_Create_Bucket
             (HTTP, Prepared, Timeout => 30.0);
      begin
         if Outcome.Kind /= Low_Level.Bucket_Created then
            raise Program_Error with
              "S3 implementation rejected CreateBucket";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Create_Bucket;

   procedure Delete_One
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Key       : String;
      Timestamp : String)
   is
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Parameters : Low_Level.Delete_Object_Parameters;
      Prepared   : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Object
          (Origin, Low_Level.Path_Style, Bucket, Key, Parameters, Identity,
           "us-east-1", Timestamp);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Low_Level.Delete_Object_Outcome :=
           Low_Level.Execute_Delete_Object
             (HTTP, Prepared, Timeout => 30.0);
      begin
         if Outcome.Kind /= Low_Level.Object_Deleted then
            raise Program_Error with
              "S3 implementation rejected DeleteObject";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Delete_One;

   procedure Delete_Empty_Bucket
     (Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Timestamp : String)
   is
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Identity   : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials (Access_Key, Secret_Key);
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Prepared   : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket
          (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
           "us-east-1", Timestamp);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      declare
         Outcome : constant Low_Level.Delete_Bucket_Outcome :=
           Low_Level.Execute_Delete_Bucket
             (HTTP, Prepared, Timeout => 30.0);
      begin
         if Outcome.Kind /= Low_Level.Bucket_Deleted then
            raise Program_Error with
              "S3 implementation rejected DeleteBucket";
         end if;
      end;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Delete_Empty_Bucket;

   protected type Task_Result is
      procedure Report (Passed : Boolean; Detail : String := "");
      entry Wait (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Done         : Boolean := False;
      Passed_Value : Boolean := False;
      Detail_Value : US.Unbounded_String;
   end Task_Result;

   protected body Task_Result is
      procedure Report (Passed : Boolean; Detail : String := "") is
      begin
         Passed_Value := Passed;
         Detail_Value := US.To_Unbounded_String (Detail);
         Done := True;
      end Report;

      entry Wait
        (Passed : out Boolean; Detail : out US.Unbounded_String) when Done
      is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait;
   end Task_Result;

begin
   if Ada.Command_Line.Argument_Count not in 3 .. 4 then
      raise Program_Error with
        "usage: s3_implementation_corpus ENDPOINT BUCKET " &
        "YYYYMMDDTHHMMSSZ [setup|cleanup]";
   end if;
   declare
      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin (Ada.Command_Line.Argument (1));
      Bucket : constant String := Ada.Command_Line.Argument (2);
      Timestamp : constant String := Ada.Command_Line.Argument (3);
      Lightweight_Result : Task_Result;
      Passed : Boolean;
      Detail : US.Unbounded_String;
   begin
      if Ada.Command_Line.Argument_Count = 3 then
         Run (Origin, Bucket, "native-object", Timestamp);
         declare
            task Lightweight_Client is
               pragma Task_Info (Flyology.Lightweight_Task);
            end Lightweight_Client;

            task body Lightweight_Client is
            begin
               Run (Origin, Bucket, "lightweight-object", Timestamp);
               Lightweight_Result.Report (True);
            exception
               when Occurrence : others =>
                  Lightweight_Result.Report
                    (False,
                     Ada.Exceptions.Exception_Information (Occurrence));
            end Lightweight_Client;
         begin
            Lightweight_Result.Wait (Passed, Detail);
         end;
         if not Passed then
            raise Program_Error with US.To_String (Detail);
         end if;
         Ada.Text_IO.Put_Line
           ("S3 implementation corpus: native and lightweight clients OK");
      elsif Ada.Command_Line.Argument (4) = "setup" then
         Create_Bucket (Origin, Bucket, Timestamp);
         declare
            task Lightweight_Client is
               pragma Task_Info (Flyology.Lightweight_Task);
            end Lightweight_Client;

            task body Lightweight_Client is
            begin
               Require_Head_Bucket (Origin, Bucket, Timestamp);
               Lightweight_Result.Report (True);
            exception
               when Occurrence : others =>
                  Lightweight_Result.Report
                    (False,
                     Ada.Exceptions.Exception_Information (Occurrence));
            end Lightweight_Client;
         begin
            Lightweight_Result.Wait (Passed, Detail);
         end;
         if not Passed then
            raise Program_Error with US.To_String (Detail);
         end if;
         Require_Head_Bucket (Origin, Bucket, Timestamp);
         Ada.Text_IO.Put_Line
           ("S3 implementation setup: bucket created and headed");
      elsif Ada.Command_Line.Argument (4) = "cleanup" then
         Delete_One (Origin, Bucket, "native-object", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-copy-part", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-copy-object", Timestamp);
         Delete_One
           (Origin, Bucket, "native-object-high level+%25", Timestamp);
         declare
            task Lightweight_Client is
               pragma Task_Info (Flyology.Lightweight_Task);
            end Lightweight_Client;

            task body Lightweight_Client is
            begin
               Delete_One
                 (Origin, Bucket, "lightweight-object", Timestamp);
               Delete_One
                 (Origin, Bucket, "lightweight-object-copy-part", Timestamp);
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-copy-object", Timestamp);
               Delete_One
                 (Origin, Bucket,
                  "lightweight-object-high level+%25", Timestamp);
               Lightweight_Result.Report (True);
            exception
               when Occurrence : others =>
                  Lightweight_Result.Report
                    (False,
                     Ada.Exceptions.Exception_Information (Occurrence));
            end Lightweight_Client;
         begin
            Lightweight_Result.Wait (Passed, Detail);
         end;
         if not Passed then
            raise Program_Error with US.To_String (Detail);
         end if;
         Delete_Empty_Bucket (Origin, Bucket, Timestamp);
         Ada.Text_IO.Put_Line
           ("S3 implementation cleanup: objects and bucket deleted");
      else
         raise Program_Error with "unknown corpus mode";
      end if;
   end;
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("S3 implementation corpus failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_Implementation_Corpus;
