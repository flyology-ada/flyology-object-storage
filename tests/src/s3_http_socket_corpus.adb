with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.IO.Sockets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Objects;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.Tags;

procedure S3_HTTP_Socket_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Objects renames Flyology.Object_Storage.Client.Objects;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Client_Buckets renames
     Flyology.Object_Storage.Client.Buckets;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Model renames Flyology.Object_Storage.S3.Model;
   package Multipart renames Flyology.Object_Storage.S3.Multipart;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Tags renames Flyology.Object_Storage.Tags;
   package Sockets renames Flyology.IO.Sockets;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Objects.List_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type Low_Level.Delete_Objects_Outcome_Kind;
   use type Low_Level.Put_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Get_Bucket_Versioning_Outcome_Kind;
   use type Client_Buckets.Set_Versioning_Outcome_Kind;
   use type Client_Buckets.Get_Versioning_Outcome_Kind;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;
   use type Low_Level.Head_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Object_Tagging_Outcome_Kind;
   use type Objects.Tagging_Outcome_Kind;
   use type Flyology.Object_Storage.Object_Tag_Set;
   use type Low_Level.Get_Object_Attributes_Outcome_Kind;
   use type Buckets.Put_Tags_Outcome_Kind;
   use type Buckets.Get_Tags_Outcome_Kind;
   use type Buckets.Delete_Tags_Outcome_Kind;
   use type Tags.Tag_Vectors.Vector;
   use type Transfers.Download_Outcome_Kind;
   use type Transfers.Upload_Outcome_Kind;
   use type Transfers.Copy_Outcome_Kind;
   use type Transfers.Head_Outcome_Kind;
   use type Sockets.Selector_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Upload_Payload : aliased constant String :=
     String'(1 .. 120 * 1_024 => 'u');
   Download_Payload : constant String :=
     String'(1 .. 120 * 1_024 => 'd');
   Conditional_First : aliased constant String := "conditional-first";
   Conditional_Collision : aliased constant String :=
     "conditional-collision";
   Conditional_Second : aliased constant String := "conditional-second";
   Conditional_Stale : aliased constant String := "conditional-stale";

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

   function Bytes (Value : String) return Stream_Element_Array is
      Result : Stream_Element_Array
        (1 .. Stream_Element_Offset (Value'Length));
   begin
      for Offset in 0 .. Value'Length - 1 loop
         Result (Result'First + Stream_Element_Offset (Offset)) :=
           Stream_Element (Character'Pos (Value (Value'First + Offset)));
      end loop;
      return Result;
   end Bytes;

   procedure Write_File (Path, Value : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Value'Length > 0 then
         SIO.Write (File, Bytes (Value));
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_File;

   procedure Delete_If_Present (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Present;

   function Read_File (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
      begin
         if Size = 0 then
            SIO.Close (File);
            return "";
         elsif Size > SIO.Count (Natural'Last) then
            raise Program_Error with "test file is too large";
         end if;
         declare
            Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
            Last : Stream_Element_Offset;
            Result : String (1 .. Natural (Size));
         begin
            SIO.Read (File, Data, Last);
            if Last /= Data'Last then
               raise Program_Error with "short test file read";
            end if;
            for Index in Result'Range loop
               Result (Index) := Character'Val
                 (Data
                    (Data'First
                     + Stream_Element_Offset (Index - Result'First)));
            end loop;
            SIO.Close (File);
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_File;

   procedure Require_No_Download_Temporary (Path : String) is
      Search : Ada.Directories.Search_Type;
      Active : Boolean := False;
      Found  : Boolean;
      Directory : constant String := Ada.Directories.Containing_Directory
        (Path);
      Pattern : constant String := Ada.Directories.Simple_Name (Path)
        & ".flyology-*.part";
   begin
      Ada.Directories.Start_Search (Search, Directory, Pattern);
      Active := True;
      Found := Ada.Directories.More_Entries (Search);
      Ada.Directories.End_Search (Search);
      Active := False;
      if Found then
         raise Program_Error with "download temporary file was not removed";
      end if;
   exception
      when others =>
         if Active then
            Ada.Directories.End_Search (Search);
         end if;
         raise;
   end Require_No_Download_Temporary;

   function Decimal (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal;

   function HTTP_Response
     (Status, Payload      : String;
      Extra_Headers        : String := "";
      Omit_Content_Length  : Boolean := False) return String is
     ("HTTP/1.1 " & Status & CRLF &
      (if Omit_Content_Length then ""
       else "Content-Length: " & Decimal (Payload'Length) & CRLF) &
      Extra_Headers & "Connection: close" & CRLF & CRLF & Payload);

   protected type Coordination is
      procedure Publish (Value : Sockets.Port);
      entry Wait_Ready (Value : out Sockets.Port);
      procedure Complete (Passed : Boolean; Detail : String := "");
      entry Wait_Done (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Port_Value   : Sockets.Port := Sockets.Any_Port;
      Ready        : Boolean := False;
      Done         : Boolean := False;
      Passed_Value : Boolean := False;
      Detail_Value : US.Unbounded_String;
   end Coordination;

   protected body Coordination is
      procedure Publish (Value : Sockets.Port) is
      begin
         Port_Value := Value;
         Ready := True;
      end Publish;

      entry Wait_Ready (Value : out Sockets.Port) when Ready is
      begin
         Value := Port_Value;
      end Wait_Ready;

      procedure Complete (Passed : Boolean; Detail : String := "") is
      begin
         Passed_Value := Passed;
         Detail_Value := US.To_Unbounded_String (Detail);
         Done := True;
      end Complete;

      entry Wait_Done
        (Passed : out Boolean; Detail : out US.Unbounded_String) when Done is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait_Done;
   end Coordination;

   State : Coordination;

   protected type Client_Results is
      procedure Report (Passed : Boolean; Detail : String := "");
      entry Wait_All
        (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Count        : Natural := 0;
      Passed_Value : Boolean := True;
      Detail_Value : US.Unbounded_String;
   end Client_Results;

   protected body Client_Results is
      procedure Report (Passed : Boolean; Detail : String := "") is
      begin
         Count := Count + 1;
         Passed_Value := Passed_Value and Passed;
         if not Passed and then US.Length (Detail_Value) = 0 then
            Detail_Value := US.To_Unbounded_String (Detail);
         end if;
      end Report;

      entry Wait_All
        (Passed : out Boolean; Detail : out US.Unbounded_String)
        when Count = 2
      is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait_All;
   end Client_Results;

   Clients : Client_Results;

   task Raw_S3_Server is
      pragma Task_Info (Flyology.Native_Task);
   end Raw_S3_Server;

   task body Raw_S3_Server is
      Listener : Sockets.Socket_Type;
      Peer     : Sockets.Socket_Type;
      Address  : Sockets.Endpoint;
      Status   : Sockets.Selector_Status;
      Port     : Sockets.Port;

      function Header_Value (Header, Name : String) return String is
         Marker : constant String := CRLF & Name & ":";
         Position : constant Natural :=
           Ada.Strings.Fixed.Index (Header, Marker);
         First : Natural := Position + Marker'Length;
         Last  : Natural;
      begin
         if Position = 0 then
            return "";
         end if;
         while First <= Header'Last and then Header (First) = ' ' loop
            First := First + 1;
         end loop;
         Last := Ada.Strings.Fixed.Index
           (Header, CRLF, From => First) - 1;
         if Last < First then
            return "";
         end if;
         return Header (First .. Last);
      end Header_Value;

      procedure Serve
        (Response           : String;
         Expected_Method    : String;
         Expected_Target    : String;
         Expected_Body_Root : String := "";
         Expected_Content_Type : String := "";
         Expected_Content_MD5 : String := "";
         Expected_Copy_Source : String := "";
         Expected_Copy_If_Match : String := "";
         Expected_If_Match : String := "";
         Expected_If_Modified_Since : String := "";
         Expected_If_None_Match : String := "";
         Expected_If_Unmodified_Since : String := "";
         Expected_Range : String := "";
         Expected_Checksum_Mode : String := "";
         Expected_Request_Payer : String := "";
         Expected_Bucket_Owner : String := "";
         Expected_MFA : String := "";
         Expected_Governance_Bypass : String := "";
         Expected_SDK_Checksum : String := "";
         Expected_Checksum_CRC32 : String := "";
         Expected_Object_Attributes : String := "";
         Expected_Get_Object_Attributes : String := "";
         Expected_Max_Parts : String := "";
         Expected_Part_Marker : String := "";
         Fragmented         : Boolean := False)
      is
         Buffer : Stream_Element_Array (1 .. 4_096);
         Last   : Stream_Element_Offset;
         Head   : US.Unbounded_String;
      begin
         Sockets.Accept_Socket
           (Listener, Peer, Address, Timeout => 5.0, Status => Status);
         if Status /= Sockets.Completed then
            raise Program_Error with "socket accept timed out";
         end if;
         loop
            Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);
            if Last < Buffer'First then
               raise Program_Error with "client closed before request head";
            end if;
            for Index in Buffer'First .. Last loop
               US.Append (Head, Character'Val (Buffer (Index)));
            end loop;
            exit when Ada.Strings.Fixed.Index
              (US.To_String (Head), CRLF & CRLF) /= 0;
         end loop;
         declare
            Request : constant String := US.To_String (Head);
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index (Request, CRLF & CRLF);
            Header : constant String :=
              Request (Request'First .. Separator + 3);
            Lower   : constant String :=
              Ada.Characters.Handling.To_Lower (Header);
            Target : constant String :=
              Ada.Characters.Handling.To_Lower
                (Expected_Method & " " & Expected_Target & " http/1.1") &
              CRLF;
            Length_Text : constant String :=
              Header_Value (Lower, "content-length");
            Expected_Length : constant Natural :=
              (if Length_Text'Length = 0
               then 0 else Natural'Value (Length_Text));
            Request_Body : US.Unbounded_String;
         begin
            if Ada.Strings.Fixed.Index (Lower, Target) /= 1
              or else Ada.Strings.Fixed.Index
                (Lower, "host: 127.0.0.1:" & Decimal (Natural (Port))) = 0
              or else Ada.Strings.Fixed.Index
                (Lower, "authorization: aws4-hmac-sha256 credential=") = 0
              or else
                (if Expected_Get_Object_Attributes'Length > 0 then
                    Header_Value (Lower, "x-amz-object-attributes") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Get_Object_Attributes)
                    or else Header_Value (Lower, "x-amz-max-parts") /=
                      Ada.Characters.Handling.To_Lower (Expected_Max_Parts)
                    or else Header_Value
                      (Lower, "x-amz-part-number-marker") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Part_Marker)
                    or else Header_Value
                      (Lower, "x-amz-request-payer") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Request_Payer)
                    or else Header_Value
                      (Lower, "x-amz-expected-bucket-owner") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Bucket_Owner)
                    or else Ada.Strings.Fixed.Index
                      (Lower, ";x-amz-object-attributes") = 0
                 elsif Expected_Copy_Source'Length > 0 then
                    Header_Value (Lower, "x-amz-copy-source") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Copy_Source)
                    or else Header_Value
                      (Lower, "x-amz-copy-source-if-match") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Copy_If_Match)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=host;x-amz-content-sha256;" &
                       "x-amz-copy-source" &
                       (if Expected_Copy_If_Match'Length = 0 then ";"
                        else ";x-amz-copy-source-if-match;") &
                       "x-amz-date") = 0
                 elsif Expected_Content_MD5'Length > 0 then
                    Header_Value (Lower, "content-md5")'Length = 0
                    or else
                      (Expected_Content_MD5 /= "*"
                       and then Header_Value (Lower, "content-md5") /=
                         Ada.Characters.Handling.To_Lower
                           (Expected_Content_MD5))
                    or else
                      (Expected_Bucket_Owner'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-expected-bucket-owner") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Bucket_Owner))
                    or else
                      (Expected_Request_Payer'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-request-payer") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Request_Payer))
                    or else
                      (Expected_MFA'Length > 0
                       and then Header_Value (Lower, "x-amz-mfa") /=
                         Ada.Characters.Handling.To_Lower (Expected_MFA))
                    or else
                      (Expected_Governance_Bypass'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-bypass-governance-retention") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_Governance_Bypass))
                    or else
                      (Expected_SDK_Checksum'Length > 0
                       and then Header_Value
                         (Lower, "x-amz-sdk-checksum-algorithm") /=
                           Ada.Characters.Handling.To_Lower
                             (Expected_SDK_Checksum))
                    or else
                      (Expected_Checksum_CRC32'Length > 0
                       and then
                         (Header_Value
                            (Lower, "x-amz-checksum-crc32")'Length = 0
                          or else
                            (Expected_Checksum_CRC32 /= "*"
                             and then Header_Value
                               (Lower, "x-amz-checksum-crc32") /=
                                 Ada.Characters.Handling.To_Lower
                                   (Expected_Checksum_CRC32))))
                    or else Ada.Strings.Fixed.Index
                      (Lower, "signedheaders=content-md5;host;") = 0
                    or else Ada.Strings.Fixed.Index
                      (Lower, ";x-amz-content-sha256;x-amz-date") = 0
                    or else
                      (Expected_Bucket_Owner'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-expected-bucket-owner") = 0)
                    or else
                      (Expected_Request_Payer'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-request-payer") = 0)
                    or else
                      (Expected_MFA'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-mfa") = 0)
                    or else
                      (Expected_Governance_Bypass'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-bypass-governance-retention;") = 0)
                    or else
                      (Expected_SDK_Checksum'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-sdk-checksum-algorithm") = 0)
                    or else
                      (Expected_Checksum_CRC32'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-checksum-crc32;") = 0)
                 elsif Expected_Request_Payer'Length > 0
                   or else Expected_Bucket_Owner'Length > 0
                   or else Expected_Object_Attributes'Length > 0
                 then
                    Header_Value (Lower, "x-amz-request-payer") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Request_Payer)
                    or else Header_Value
                      (Lower, "x-amz-expected-bucket-owner") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Bucket_Owner)
                    or else Header_Value
                      (Lower, "x-amz-optional-object-attributes") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Object_Attributes)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=host;x-amz-content-sha256;" &
                       "x-amz-date" &
                       (if Expected_Bucket_Owner'Length > 0 then
                           ";x-amz-expected-bucket-owner"
                        else "") &
                       (if Expected_Object_Attributes'Length > 0 then
                           ";x-amz-optional-object-attributes"
                        else "") &
                       (if Expected_Request_Payer'Length > 0 then
                           ";x-amz-request-payer"
                        else "")) = 0
                 elsif Expected_If_Match'Length > 0
                   or else Expected_If_Modified_Since'Length > 0
                   or else Expected_If_None_Match'Length > 0
                   or else Expected_If_Unmodified_Since'Length > 0
                   or else Expected_Range'Length > 0
                   or else Expected_Checksum_Mode'Length > 0
                 then
                    Header_Value (Lower, "if-match") /=
                      Ada.Characters.Handling.To_Lower (Expected_If_Match)
                    or else Header_Value (Lower, "if-modified-since") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_If_Modified_Since)
                    or else Header_Value (Lower, "if-none-match") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_If_None_Match)
                    or else Header_Value (Lower, "if-unmodified-since") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_If_Unmodified_Since)
                    or else Header_Value (Lower, "range") /=
                      Ada.Characters.Handling.To_Lower (Expected_Range)
                    or else Header_Value
                      (Lower, "x-amz-checksum-mode") /=
                        Ada.Characters.Handling.To_Lower
                          (Expected_Checksum_Mode)
                    or else Ada.Strings.Fixed.Index
                      (Lower, "signedheaders=host;") = 0
                    or else
                      (Expected_If_Match'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-match;") = 0)
                    or else
                      (Expected_If_Modified_Since'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-modified-since;") = 0)
                    or else
                      (Expected_If_None_Match'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-none-match;") = 0)
                    or else
                      (Expected_If_Unmodified_Since'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";if-unmodified-since;") = 0)
                    or else
                      (Expected_Range'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";range;") = 0)
                    or else
                      (Expected_Checksum_Mode'Length > 0
                       and then Ada.Strings.Fixed.Index
                         (Lower, ";x-amz-checksum-mode;") = 0)
                    or else Ada.Strings.Fixed.Index
                      (Lower, ";x-amz-content-sha256;x-amz-date") = 0
                 elsif Expected_Content_MD5'Length > 0 then
                    Header_Value (Lower, "content-md5") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Content_MD5)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=content-md5;host;" &
                       "x-amz-content-sha256;x-amz-date") = 0
                 elsif Expected_Content_Type'Length = 0 then
                    Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=host;x-amz-content-sha256;" &
                       "x-amz-date") = 0
                 else
                    Header_Value (Lower, "content-type") /=
                      Ada.Characters.Handling.To_Lower
                        (Expected_Content_Type)
                    or else Ada.Strings.Fixed.Index
                      (Lower,
                       "signedheaders=content-type;host;" &
                       "x-amz-content-sha256;x-amz-date") = 0)
            then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "expected signed request: " & Expected_Method & " " &
                  Expected_Target);
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, "observed head: " & Header);
               raise Program_Error with "unexpected signed S3 request head";
            end if;
            if Separator + 4 <= Request'Last then
               US.Append
                 (Request_Body, Request (Separator + 4 .. Request'Last));
            end if;
            while US.Length (Request_Body) < Expected_Length loop
               Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);
               if Last < Buffer'First then
                  raise Program_Error with
                    "client closed before complete request body";
               end if;
               for Index in Buffer'First .. Last loop
                  US.Append
                    (Request_Body, Character'Val (Buffer (Index)));
               end loop;
            end loop;
            if US.Length (Request_Body) /= Expected_Length then
               raise Program_Error with "request body length mismatch";
            elsif Expected_Body_Root'Length > 0 then
               declare
                  Body_Text : constant String := US.To_String (Request_Body);
                  Expected_Hash : constant String :=
                    SigV4.SHA256_Hex (Body_Text);
               begin
                  if Ada.Strings.Fixed.Index
                    (Body_Text, Expected_Body_Root) = 0
                    or else Header_Value
                      (Lower, "x-amz-content-sha256") /= Expected_Hash
                  then
                     raise Program_Error with
                       "signed S3 request body mismatch";
                  end if;
               end;
            end if;
         end;
         if Fragmented then
            for Character_Value of Response loop
               Sockets.Send_All
                 (Peer, Bytes (String'(1 => Character_Value)), Timeout => 5.0);
            end loop;
         else
            Sockets.Send_All (Peer, Bytes (Response), Timeout => 5.0);
         end if;
         Sockets.Close_Socket (Peer);
      end Serve;

      Success_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/"">" &
        "<Name>example-bucket</Name><KeyCount>0</KeyCount>" &
        "<MaxKeys>2</MaxKeys><IsTruncated>false</IsTruncated>" &
        "</ListBucketResult>";
      First_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-page/</Prefix><KeyCount>1</KeyCount>" &
        "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
        "<NextContinuationToken>opaque-next</NextContinuationToken>" &
        "<Contents><Key>socket-page/a</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      Second_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-page/</Prefix>" &
        "<ContinuationToken>opaque-next</ContinuationToken>" &
        "<KeyCount>1</KeyCount><MaxKeys>1</MaxKeys>" &
        "<IsTruncated>false</IsTruncated>" &
        "<Contents><Key>socket-page/b</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      List_Buckets_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Owner><ID>socket-owner</ID></Owner>" &
        "<Buckets><Bucket><Name>socket-bucket</Name>" &
        "<CreationDate>2026-08-22T01:02:03.000Z</CreationDate>" &
        "<BucketRegion>us-east-1</BucketRegion>" &
        "<BucketArn>arn:aws:s3:::socket-bucket</BucketArn>" &
        "</Bucket></Buckets><ContinuationToken>socket-next" &
        "</ContinuationToken><Prefix>socket-</Prefix>" &
        "</ListAllMyBucketsResult>";
      V1_Success_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket/</Prefix><Marker>before</Marker>" &
        "<Delimiter>/</Delimiter><MaxKeys>2</MaxKeys>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>false</IsTruncated></ListBucketResult>";
      V1_First_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix><Marker></Marker>" &
        "<EncodingType>url</EncodingType>" &
        "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
        "<Contents><Key>socket-v1/a%20/%25%C3%A9</Key>" &
        "<Size>1</Size></Contents>" &
        "</ListBucketResult>";
      V1_Second_Page_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix>" &
        "<Marker>socket-v1/a%20/%25%C3%A9</Marker>" &
        "<EncodingType>url</EncodingType>" &
        "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
        "<Contents><Key>socket-v1/b</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      V1_Delimiter_First_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix><Marker></Marker>" &
        "<NextMarker>socket-v1/group%20%25/%C3%A9</NextMarker>" &
        "<MaxKeys>1</MaxKeys><Delimiter>/</Delimiter>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>true</IsTruncated>" &
        "<CommonPrefixes><Prefix>socket-v1/group%20%25/%C3%A9/" &
        "</Prefix></CommonPrefixes></ListBucketResult>";
      V1_Delimiter_Second_XML : constant String :=
        "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix>" &
        "<Marker>socket-v1/group%20%25/%C3%A9</Marker>" &
        "<MaxKeys>1</MaxKeys><Delimiter>/</Delimiter>" &
        "<EncodingType>url</EncodingType>" &
        "<IsTruncated>false</IsTruncated></ListBucketResult>";
      V1_Malformed_Encoding_XML : constant String :=
        "<ListBucketResult><Name>example-bucket</Name>" &
        "<Prefix>socket-v1/</Prefix><Marker></Marker>" &
        "<EncodingType>url</EncodingType><MaxKeys>1</MaxKeys>" &
        "<IsTruncated>true</IsTruncated>" &
        "<Contents><Key>socket-v1/%GG</Key><Size>1</Size></Contents>" &
        "</ListBucketResult>";
      Error_XML : constant String :=
        "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
      Precondition_XML : constant String :=
        "<Error><Code>PreconditionFailed</Code>" &
        "<Message>condition failed</Message></Error>";
      Create_XML : constant String :=
        "<InitiateMultipartUploadResult>" &
        "<Bucket>example-bucket</Bucket><Key>object key</Key>" &
        "<UploadId>socket-upload</UploadId>" &
        "</InitiateMultipartUploadResult>";
      Complete_XML : constant String :=
        "<CompleteMultipartUploadResult>" &
        "<Bucket>example-bucket</Bucket><Key>object key</Key>" &
        "<ETag>&quot;whole&quot;</ETag>" &
        "</CompleteMultipartUploadResult>";
      Embedded_Error_XML : constant String :=
        "<Error><Code>InternalError</Code>" &
        "<Message>late failure</Message></Error>";
      List_Uploads_XML : constant String :=
        "<ListMultipartUploadsResult>" &
        "<Bucket>example-bucket</Bucket><KeyMarker>before</KeyMarker>" &
        "<UploadIdMarker>upload-before</UploadIdMarker>" &
        "<MaxUploads>2</MaxUploads><IsTruncated>false</IsTruncated>" &
        "<Upload><UploadId>socket-upload</UploadId><Key>socket/key</Key>" &
        "<Initiated>2026-08-21T00:00:00Z</Initiated>" &
        "<StorageClass>STANDARD</StorageClass></Upload>" &
        "</ListMultipartUploadsResult>";
      Copy_XML : constant String :=
        "<CopyObjectResult>" &
        "<LastModified>2026-08-21T17:00:00.000Z</LastModified>" &
        "<ETag>&quot;high-level-copy&quot;</ETag>" &
        "</CopyObjectResult>";
      Attributes_XML : constant String :=
        "<GetObjectAttributesResponse>" &
        "<ETag>&quot;socket-attributes&quot;</ETag>" &
        "<ObjectParts><PartsCount>2</PartsCount>" &
        "<PartNumberMarker>1</PartNumberMarker>" &
        "<MaxParts>1</MaxParts><IsTruncated>true</IsTruncated>" &
        "<NextPartNumberMarker>2</NextPartNumberMarker>" &
        "<Part><PartNumber>2</PartNumber><Size>7</Size></Part>" &
        "</ObjectParts><ObjectSize>14</ObjectSize>" &
        "</GetObjectAttributesResponse>";
      Tagging_XML : constant String :=
        "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<TagSet><Tag><Key>project</Key><Value>flyology</Value></Tag>" &
        "</TagSet></Tagging>";
      Delete_Objects_XML : constant String :=
        "<DeleteResult xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Deleted><Key>socket-delete-a</Key><VersionId>version-a</VersionId>" &
        "<DeleteMarker>false</DeleteMarker>" &
        "<DeleteMarkerVersionId>marker-a</DeleteMarkerVersionId>" &
        "</Deleted><Error><Key>socket-delete-b</Key>" &
        "<VersionId>version-b</VersionId><Code>AccessDenied</Code>" &
        "<Message>denied</Message></Error></DeleteResult>";
   begin
      Sockets.Create_Socket (Listener);
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Any_Port));
      Sockets.Listen_Socket (Listener);
      Port := Sockets.Get_Socket_Name (Listener).Port;
      State.Publish (Port);
      for Round in 1 .. 2 loop
         Serve
           (HTTP_Response ("200 OK", List_Buckets_XML),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: list-buckets-request" & CRLF &
               "x-amz-id-2: list-buckets-host" & CRLF),
            "GET", "/?bucket-region=us-east-1&max-buckets=1&" &
              "prefix=socket-");
         Serve
           (HTTP_Response
              ("200 OK", V1_Success_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: v1-socket-request" & CRLF &
               "x-amz-id-2: v1-socket-host" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=before&max-keys=2&prefix=socket%2F",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", V1_First_Page_XML), "GET",
            "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=socket-v1%2F",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", V1_Second_Page_XML), "GET",
            "/example-bucket?encoding-type=url&" &
              "marker=socket-v1%2Fa%20%2F%25%C3%A9&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Delimiter_First_XML), "GET",
            "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "max-keys=1&prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Delimiter_Second_XML), "GET",
            "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "marker=socket-v1%2Fgroup%20%25%2F%C3%A9&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response ("200 OK", V1_Malformed_Encoding_XML), "GET",
            "/example-bucket?encoding-type=url&max-keys=1&" &
              "prefix=socket-v1%2F");
         Serve
           (HTTP_Response
              ("200 OK", Success_XML,
               "x-amz-request-charged: requester" & CRLF), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: socket-request" & CRLF &
               "x-amz-id-2: socket-host" & CRLF),
            "GET", "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", String'(1 .. 256 => 'x')), "GET",
            "/example-bucket?list-type=2&max-keys=2",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Object_Attributes => "RestoreStatus");
         Serve
           (HTTP_Response ("200 OK", First_Page_XML), "GET",
            "/example-bucket?list-type=2&max-keys=1&" &
              "prefix=socket-page%2F");
         Serve
           (HTTP_Response ("200 OK", Second_Page_XML), "GET",
            "/example-bucket?continuation-token=opaque-next&" &
              "list-type=2&max-keys=1&prefix=socket-page%2F");
         Serve
           (HTTP_Response
              ("200 OK", List_Uploads_XML,
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&key-marker=before&" &
              "max-uploads=2&prefix=socket%2F&" &
              "upload-id-marker=upload-before&uploads",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("403 Forbidden", Error_XML,
               "x-amz-request-id: list-uploads-request" & CRLF &
               "x-amz-id-2: list-uploads-host" & CRLF),
            "GET", "/example-bucket?delimiter=%2F&key-marker=before&" &
              "max-uploads=2&prefix=socket%2F&" &
              "upload-id-marker=upload-before&uploads",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?versioning",
            Expected_Body_Root => "<VersioningConfiguration",
            Expected_Bucket_Owner => "123456789012",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK",
               "<VersioningConfiguration>" &
               "<Status>Enabled</Status>" &
               "</VersioningConfiguration>"),
            "GET", "/example-bucket?versioning",
            Expected_Bucket_Owner => "123456789012",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?versioning",
            Expected_Body_Root => "<Status>Suspended</Status>",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK",
               "<VersioningConfiguration>" &
               "<Status>Suspended</Status>" &
               "</VersioningConfiguration>"),
            "GET", "/example-bucket?versioning", Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK", "", Omit_Content_Length => True),
            "HEAD", "/example-bucket");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""model-stream""" & CRLF),
            "PUT", "/example-bucket/model-stream", "u");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "ETag: ""typed-put""" & CRLF &
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF &
               "x-amz-server-side-encryption: aws:backup" & CRLF &
               "x-amz-version-id: put-version" & CRLF &
               "x-amz-server-side-encryption-bucket-key-enabled: true" &
               CRLF & "x-amz-object-size: 1" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "PUT", "/example-bucket/typed-put", "u");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""conditional-first""" & CRLF),
            "PUT", "/example-bucket/conditional-put", "conditional-first",
            Expected_If_None_Match => "*");
         Serve
           (HTTP_Response ("412 Precondition Failed", Precondition_XML),
            "PUT", "/example-bucket/conditional-put",
            "conditional-collision", Expected_If_None_Match => "*");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 17" & CRLF &
               "ETag: ""conditional-first""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/conditional-put");
         Serve
           (HTTP_Response
              ("200 OK", "conditional-first",
               "ETag: ""conditional-first""" & CRLF),
            "GET", "/example-bucket/conditional-put");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""conditional-second""" & CRLF),
            "PUT", "/example-bucket/conditional-put", "conditional-second",
            Expected_If_Match => """conditional-first""");
         Serve
           (HTTP_Response ("412 Precondition Failed", Precondition_XML),
            "PUT", "/example-bucket/conditional-put", "conditional-stale",
            Expected_If_Match => """conditional-first""");
         Serve
           (HTTP_Response
              ("200 OK", "conditional-second",
               "ETag: ""conditional-second""" & CRLF),
            "GET", "/example-bucket/conditional-put");
         Serve
           (HTTP_Response
              ("200 OK", "", "x-amz-version-id: tag-put-version" & CRLF),
            "PUT", "/example-bucket/typed-tagged?tagging", "<Tagging",
            Expected_Content_MD5 => "FHvgEqWnwx8BYbDb/UMn6Q==");
         Serve
           (HTTP_Response
              ("200 OK",
               "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
               "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag>" &
               "</TagSet></Tagging>",
               "x-amz-version-id: tag-get-version" & CRLF),
            "GET", "/example-bucket/typed-tagged?tagging",
            Fragmented => True);
         Serve
           (HTTP_Response
              ("204 No Content", "",
               "x-amz-version-id: tag-delete-version" & CRLF,
               Omit_Content_Length => True),
            "DELETE", "/example-bucket/typed-tagged?tagging");
         Serve
           (HTTP_Response ("200 OK", ""),
            "PUT", "/example-bucket/convenient-tagged?tagging", "<Tagging",
            Expected_Content_MD5 => "FHvgEqWnwx8BYbDb/UMn6Q==");
         Serve
           (HTTP_Response
              ("200 OK",
               "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
               "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag>" &
               "</TagSet></Tagging>"),
            "GET", "/example-bucket/convenient-tagged?tagging");
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket/convenient-tagged?tagging");
         Serve
           (HTTP_Response
              ("200 OK", Delete_Objects_XML,
               "x-amz-request-charged: requester" & CRLF),
            "POST", "/example-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_MFA => "device 123456",
            Expected_Governance_Bypass => "true",
            Expected_SDK_Checksum => "CRC32",
            Expected_Checksum_CRC32 => "*", Fragmented => True);
         Serve
           (HTTP_Response
              ("404 Not Found",
               "<Error><Code>NoSuchBucket</Code>" &
               "<Message>missing bucket</Message></Error>",
               "x-amz-request-id: delete-missing-request" & CRLF),
            "POST", "/missing-bucket?delete", "<Delete",
            Expected_Content_MD5 => "*");
         Serve
           (HTTP_Response
              ("200 OK", Attributes_XML,
               "x-amz-delete-marker: false" & CRLF &
               "Last-Modified: Fri, 24 May 2013 00:00:00 GMT" & CRLF &
               "x-amz-version-id: socket-version" & CRLF &
               "x-amz-request-charged: requester" & CRLF),
            "GET", "/example-bucket/object%20key?attributes&" &
              "versionId=socket%20version",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012",
            Expected_Get_Object_Attributes =>
              "ETag,ObjectParts,ObjectSize",
            Expected_Max_Parts => "1", Expected_Part_Marker => "1",
            Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Attributes_XML),
            "GET", "/example-bucket/convenience-attributes?attributes",
            Expected_Get_Object_Attributes =>
              "ETag,Checksum,ObjectParts,StorageClass,ObjectSize");
         Serve
           (HTTP_Response
              ("404 Not Found", Error_XML,
               "x-amz-request-id: attributes-request" & CRLF &
               "x-amz-id-2: attributes-host" & CRLF),
            "GET", "/example-bucket/missing-attributes?attributes",
            Expected_Get_Object_Attributes => "ObjectSize");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""high-level""" & CRLF),
            "PUT", "/example-bucket/high%20level%2Bfile%2525",
            "high-level file payload", "application/test");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""empty""" & CRLF),
            "PUT", "/example-bucket/high-level-empty");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "PUT", "/example-bucket/high-level-rejected",
            "high-level file payload");
         Serve
           (HTTP_Response
              ("200 OK", Download_Payload,
               "ETag: ""download-large""" & CRLF),
            "GET", "/example-bucket/download%20large%2B%2525");
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""download-empty""" & CRLF),
            "GET", "/example-bucket/download-empty");
         Serve
           (HTTP_Response ("403 Forbidden", Error_XML),
            "GET", "/example-bucket/download-rejected");
         Serve
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Length: 64" & CRLF
            & "ETag: ""download-truncated""" & CRLF
            & "Connection: close" & CRLF & CRLF & "short",
            "GET", "/example-bucket/download-truncated");
         Serve
           (HTTP_Response
              ("206 Partial Content", "partial",
               "Content-Range: bytes 0-6/42" & CRLF &
               "ETag: ""download-partial""" & CRLF),
            "GET", "/example-bucket/download-unexpected-range");
         Serve
           (HTTP_Response
              ("206 Partial Content", "partial",
               "Content-Range: bytes 7-13/42" & CRLF &
               "ETag: ""download-range""" & CRLF),
            "GET", "/example-bucket/download-range",
            Expected_Range => "bytes=7-13");
         Serve
           (HTTP_Response
              ("304 Not Modified", "", Omit_Content_Length => True),
            "GET", "/example-bucket/download-not-modified",
            Expected_If_None_Match => """download-range""");
         Serve
           (HTTP_Response ("412 Precondition Failed", "precondition failed"),
            "GET", "/example-bucket/download-precondition",
            Expected_If_Match => """different""");
         Serve
           (HTTP_Response ("206 Partial Content", "x"),
            "GET", "/example-bucket/download-missing-content-range",
            Expected_Range => "bytes=0-0");
         Serve
           (HTTP_Response
              ("206 Partial Content", "xx",
               "Content-Range: bytes 0-0/2" & CRLF),
            "GET", "/example-bucket/download-length-mismatch",
            Expected_Range => "bytes=0-0");
         Serve
           (HTTP_Response
              ("206 Partial Content", "x",
               "Content-Range: bytes 2-1/3" & CRLF),
            "GET", "/example-bucket/download-invalid-content-range",
            Expected_Range => "bytes=0-0");
         Serve
           (HTTP_Response
              ("200 OK", "x", "Content-Range: bytes 0-0/1" & CRLF),
            "GET", "/example-bucket/download-unsolicited-content-range");
         Serve
           (HTTP_Response
              ("200 OK", Copy_XML,
               "x-amz-version-id: destination-version" & CRLF &
               "x-amz-copy-source-version-id: source-version" & CRLF),
            "PUT", "/example-bucket/copied%20object%2B%2525",
            Expected_Copy_Source =>
              "source-bucket/source%20key%2B%2525",
            Expected_Copy_If_Match => """source-etag""");
         Serve
           (HTTP_Response ("412 Precondition Failed", Error_XML),
            "PUT", "/example-bucket/copy-rejected",
            Expected_Copy_Source => "source-bucket/source-key");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 4" & CRLF &
               "ETag: ""head-etag""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "Content-Type: application/test" & CRLF &
               "x-amz-version-id: head-version" & CRLF &
               "x-amz-checksum-sha256: " &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF &
               "x-amz-mp-parts-count: 3" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head%20object%2B%2525?" &
              "partNumber=3&response-cache-control=no-cache&" &
              "response-content-disposition=attachment&" &
              "response-content-encoding=gzip&" &
              "response-content-language=en-CA&response-content-type=" &
              "application%2Ftest&response-expires=Fri%2C%2021%20Aug%20" &
              "2026%2018%3A00%3A00%20GMT&versionId=version%20one",
            Expected_If_Match => """expected-etag""",
            Expected_If_Modified_Since =>
              "Fri, 21 Aug 2026 16:00:00 GMT",
            Expected_If_None_Match => """other-etag""",
            Expected_If_Unmodified_Since =>
              "Fri, 21 Aug 2026 18:00:00 GMT",
            Expected_Range => "bytes=1-4",
            Expected_Checksum_Mode => "ENABLED");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 42" & CRLF &
               "ETag: ""head-policy""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-policy",
            Expected_Request_Payer => "requester",
            Expected_Bucket_Owner => "123456789012");
         Serve
           (HTTP_Response
              ("404 Not Found", "",
               "x-amz-request-id: head-request" & CRLF &
               "x-amz-id-2: head-host" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-missing");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 1" & CRLF &
               "ETag: ""checksum-etag""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-sha256: not-base64" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-invalid-checksum");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 1" & CRLF &
               "ETag: ""first""" & CRLF &
               "ETag: ""second""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/head-duplicate-header");
         Serve
           ("HTTP/1.1 200 OK" & CRLF &
            "Transfer-Encoding: chunked" & CRLF &
            "ETag: ""framed""" & CRLF &
            "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
            "Connection: close" & CRLF & CRLF,
            "HEAD", "/example-bucket/head-transfer-encoding");
         Serve
           (HTTP_Response
              ("200 OK", "",
               "Content-Length: 7" & CRLF &
               "x-amz-delete-marker: false" & CRLF &
               "x-amz-archive-status: ARCHIVE_ACCESS" & CRLF &
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF &
               "ETag: ""typed-head""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-missing-meta: 2" & CRLF &
               "x-amz-meta-project: flyology" & CRLF &
               "x-amz-meta-stage: typed" & CRLF &
               "x-amz-server-side-encryption: aws:backup" & CRLF &
               "x-amz-server-side-encryption-customer-algorithm: " &
               "AES256" & CRLF &
               "x-amz-storage-class: AWS_BACKUP_WARM" & CRLF &
               "x-amz-request-charged: requester" & CRLF &
               "x-amz-replication-status: COMPLETED" & CRLF &
               "x-amz-mp-parts-count: 3" & CRLF &
               "x-amz-tagging-count: 2" & CRLF &
               "x-amz-object-lock-mode: COMPLIANCE" & CRLF &
               "x-amz-object-lock-legal-hold: OFF" & CRLF,
               Omit_Content_Length => True),
            "HEAD", "/example-bucket/typed-head");
         Serve
           (HTTP_Response
              ("206 Partial Content", "getdata",
               "Accept-Ranges: bytes" & CRLF &
               "Content-Range: bytes 1-7/9" & CRLF &
               "ETag: ""typed-get""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-sha256: " &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=-3" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF &
               "x-amz-meta-project: flyology" & CRLF &
               "x-amz-meta-stage: get" & CRLF &
               "x-amz-server-side-encryption: aws:backup" & CRLF &
               "x-amz-storage-class: AWS_BACKUP_WARM" & CRLF &
               "x-amz-replication-status: COMPLETED" & CRLF &
               "x-amz-mp-parts-count: 3" & CRLF &
               "x-amz-tagging-count: 2" & CRLF &
               "x-amz-object-lock-mode: COMPLIANCE" & CRLF &
               "x-amz-object-lock-legal-hold: OFF" & CRLF),
            "GET", "/example-bucket/typed-get?versionId=version%20one",
            Expected_If_Match => """expected-etag""",
            Expected_Checksum_Mode => "ENABLED");
         Serve
           (HTTP_Response
              ("200 OK", "full",
               "ETag: ""typed-get-full""" & CRLF &
               "Last-Modified: Fri, 21 Aug 2026 17:00:00 GMT" & CRLF &
               "x-amz-checksum-crc64nvme: AAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: FULL_OBJECT" & CRLF),
            "GET", "/example-bucket/typed-get-full",
            Expected_Checksum_Mode => "ENABLED");
         Serve
           (HTTP_Response
              ("304 Not Modified", "",
               "x-amz-request-id: get-request" & CRLF &
               "x-amz-id-2: get-host" & CRLF,
               Omit_Content_Length => True),
            "GET", "/example-bucket/typed-get-missing");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-sha256: not-base64" & CRLF),
            "GET", "/example-bucket/typed-get-invalid");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-crc32: AAAAAA==" & CRLF &
               "x-amz-checksum-sha256: " &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF),
            "GET", "/example-bucket/typed-get-multiple");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-crc64nvme: AAAAAAAAAAA=" & CRLF &
               "x-amz-checksum-type: COMPOSITE" & CRLF),
            "GET", "/example-bucket/typed-get-illegal-pair");
         Serve
           (HTTP_Response
              ("200 OK", "x",
               "x-amz-checksum-type: COMPOSITE" & CRLF),
            "GET", "/example-bucket/typed-get-type-only");
         Serve
           (HTTP_Response ("200 OK", ""), "PUT",
            "/example-bucket?tagging", "<Tagging",
            Expected_Content_MD5 => "2VvoA0oifGYAP5yZrGu55w==");
         Serve
           (HTTP_Response ("200 OK", Tagging_XML), "GET",
            "/example-bucket?tagging", Fragmented => True);
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket?tagging");
         Serve
           (HTTP_Response
              ("404 Not Found",
               "<Error><Code>NoSuchTagSet</Code>" &
               "<Message>The TagSet does not exist</Message></Error>"),
            "GET", "/example-bucket?tagging", Fragmented => True);
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True),
            "DELETE", "/example-bucket?tagging");
         Serve
           (HTTP_Response ("200 OK", Create_XML), "POST",
            "/example-bucket/object%20key?uploads", Fragmented => True);
         Serve
           (HTTP_Response
              ("200 OK", "", "ETag: ""socket-part""" & CRLF),
            "PUT",
            "/example-bucket/object%20key?partNumber=1&" &
            "uploadId=socket-upload", "u");
         Serve
           (HTTP_Response ("200 OK", Complete_XML), "POST",
            "/example-bucket/object%20key?uploadId=socket-upload",
            "<CompleteMultipartUpload", Fragmented => True);
         Serve
           (HTTP_Response ("200 OK", Embedded_Error_XML), "POST",
            "/example-bucket/object%20key?uploadId=socket-upload",
            "<CompleteMultipartUpload");
         Serve
           (HTTP_Response
              ("204 No Content", "", Omit_Content_Length => True), "DELETE",
            "/example-bucket/object%20key?uploadId=socket-upload");
      end loop;
      Sockets.Close_Socket (Listener);
      State.Complete (True);
   exception
      when Occurrence : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "raw S3 socket server failure: " &
            Ada.Exceptions.Exception_Information (Occurrence));
         if Sockets.Is_Open (Peer) then
            Sockets.Close_Socket (Peer);
         end if;
         if Sockets.Is_Open (Listener) then
            Sockets.Close_Socket (Listener);
         end if;
         State.Complete
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Raw_S3_Server;

   procedure Run_Client is
      Port       : Sockets.Port;
      HTTP       : aliased HTTP_Client.Client (Capacity => 1);
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity   : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
      State.Wait_Ready (Port);
      Parameters.Max_Keys := 2;
      Parameters.Request_Payer := US.To_Unbounded_String ("requester");
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String ("123456789012");
      Parameters.Include_Restore_Status := True;
      declare
         Origin : constant Flyology.HTTP.Origin := Flyology.HTTP.Parse_Origin
           ("http://127.0.0.1:" & Decimal (Natural (Port)));
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Objects_V2
             (Origin, Low_Level.Path_Style, "example-bucket", Parameters,
              Identity, "us-east-1", "20130524T000000Z");

         function Conditional_Put
           (Value         : not null access constant String;
            If_Match      : String := "";
            If_None_Match : String := "")
            return Low_Level.Put_Object_Outcome
         is
            Parameters : Low_Level.Put_Object_Parameters;
            Source     : Upload_Source (Value);
         begin
            Parameters.If_Match := US.To_Unbounded_String (If_Match);
            Parameters.If_None_Match :=
              US.To_Unbounded_String (If_None_Match);
            declare
               Request : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "conditional-put", Parameters,
                    SigV4.SHA256_Hex (Value.all), Identity,
                    "us-east-1", "20130524T000000Z");
            begin
               return Low_Level.Execute_Put_Object
                 (HTTP, Request, Source, Timeout => 5.0);
            end;
         end Conditional_Put;

         procedure Require_Conditional_Get
           (Expected_Body, Expected_ETag : String)
         is
            Parameters : Low_Level.Get_Object_Parameters;
            Request : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "conditional-put", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object (HTTP, Request, Timeout => 5.0);
            Result : constant Low_Level.Get_Object_Head_Outcome :=
              Low_Level.Decode_Get_Object_Response_Head (Response);
            Received : US.Unbounded_String;
            Buffer : Stream_Element_Array (1 .. 8);
            Last : Stream_Element_Offset;
            Finished : Boolean := False;
         begin
            if Result.Kind /= Low_Level.Object_Opened
              or else Result.Status /= 200
              or else not Result.Result.Content_Length.Is_Set
              or else Result.Result.Content_Length.Value /=
                Expected_Body'Length
              or else US.To_String (Result.Result.Entity_Tag) /=
                Expected_ETag
            then
               raise Program_Error with
                 "conditional PutObject GetObject head mismatch";
            end if;
            while not Finished loop
               HTTP_Client.Read_Body (Response, Buffer, Last, Finished);
               for Index in Buffer'First .. Last loop
                  US.Append (Received, Character'Val (Buffer (Index)));
               end loop;
            end loop;
            if US.To_String (Received) /= Expected_Body then
               raise Program_Error with
                 "conditional PutObject GetObject body mismatch";
            end if;
         end Require_Conditional_Get;

         procedure Run_Conditional_Put_Lifecycle is
            Created : constant Low_Level.Put_Object_Outcome :=
              Conditional_Put
                (Conditional_First'Access, If_None_Match => "*");
            Collision : constant Low_Level.Put_Object_Outcome :=
              Conditional_Put
                (Conditional_Collision'Access, If_None_Match => "*");
         begin
            if Created.Kind /= Low_Level.Object_Put
              or else Created.Status /= 200
              or else US.To_String (Created.Result.Entity_Tag) /=
                """conditional-first"""
              or else Collision.Kind /= Low_Level.Put_Object_Rejected
              or else Collision.Status /= 412
              or else US.To_String (Collision.Error.Code) /=
                "PreconditionFailed"
            then
               raise Program_Error with
                 "conditional create/collision socket mismatch";
            end if;
            declare
               Parameters : Low_Level.Head_Object_Parameters;
               Request : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "conditional-put", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Request, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Found
                 or else Result.Status /= 200
                 or else Result.Result.Content_Length /=
                   Conditional_First'Length
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """conditional-first"""
               then
                  raise Program_Error with
                    "conditional collision changed HeadObject state";
               end if;
            end;
            Require_Conditional_Get
              (Conditional_First, """conditional-first""");
            declare
               Replaced : constant Low_Level.Put_Object_Outcome :=
                 Conditional_Put
                   (Conditional_Second'Access,
                    If_Match => """conditional-first""");
               Stale : constant Low_Level.Put_Object_Outcome :=
                 Conditional_Put
                   (Conditional_Stale'Access,
                    If_Match => """conditional-first""");
            begin
               if Replaced.Kind /= Low_Level.Object_Put
                 or else Replaced.Status /= 200
                 or else US.To_String (Replaced.Result.Entity_Tag) /=
                   """conditional-second"""
                 or else Stale.Kind /= Low_Level.Put_Object_Rejected
                 or else Stale.Status /= 412
                 or else US.To_String (Stale.Error.Code) /=
                   "PreconditionFailed"
               then
                  raise Program_Error with
                    "conditional replace/stale socket mismatch";
               end if;
            end;
            Require_Conditional_Get
              (Conditional_Second, """conditional-second""");
         end Run_Conditional_Put_Lifecycle;
      begin
         HTTP_Client.Configure (HTTP, Origin);
         declare
            Bucket_Parameters : constant Low_Level.List_Buckets_Parameters :=
              (Max_Buckets            => 1,
               Has_Max_Buckets        => True,
               Continuation_Token     => US.Null_Unbounded_String,
               Has_Continuation_Token => False,
               Prefix                 => US.To_Unbounded_String ("socket-"),
               Has_Prefix             => True,
               Bucket_Region          =>
                 US.To_Unbounded_String ("us-east-1"));
            Bucket_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Buckets
                (Origin, Low_Level.Path_Style, Bucket_Parameters, Identity,
                 "us-east-1", "20130524T000000Z");
         begin
            declare
               Result : constant Low_Level.List_Buckets_Outcome :=
                 Low_Level.Execute_List_Buckets
                   (HTTP, Bucket_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Buckets_Listed
                 or else not Result.Result.Has_Owner
                 or else US.To_String (Result.Result.Owner.ID) /=
                   "socket-owner"
                 or else Natural (Result.Result.Buckets.Length) /= 1
                 or else US.To_String
                   (Result.Result.Buckets.First_Element.Name) /=
                     "socket-bucket"
                 or else US.To_String
                   (Result.Result.Buckets.First_Element.Creation_Date) /=
                     "2026-08-22T01:02:03.000Z"
                 or else US.To_String
                   (Result.Result.Buckets.First_Element.Bucket_Region) /=
                     "us-east-1"
                 or else US.To_String
                   (Result.Result.Continuation_Token) /= "socket-next"
                 or else US.To_String (Result.Result.Prefix) /= "socket-"
               then
                  raise Program_Error with
                    "typed ListBuckets socket success mismatch";
               end if;
            end;
            declare
               Result : constant Low_Level.List_Buckets_Outcome :=
                 Low_Level.Execute_List_Buckets
                   (HTTP, Bucket_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.List_Buckets_Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "list-buckets-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "list-buckets-host"
               then
                  raise Program_Error with
                    "typed ListBuckets socket error mismatch";
               end if;
            end;
         end;
         declare
            V1_Parameters : Low_Level.List_Objects_Parameters;
         begin
            V1_Parameters.Prefix := US.To_Unbounded_String ("socket/");
            V1_Parameters.Delimiter := US.To_Unbounded_String ("/");
            V1_Parameters.Marker := US.To_Unbounded_String ("before");
            V1_Parameters.Max_Keys := 2;
            V1_Parameters.URL_Encoding := True;
            V1_Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            V1_Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            V1_Parameters.Include_Restore_Status := True;
            declare
               V1_Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    V1_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Objects_Outcome :=
                 Low_Level.Execute_List_Objects
                   (HTTP, V1_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Listed
                 or else US.To_String (Result.Result.Listing.Prefix) /=
                   "socket/"
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "typed ListObjects socket success mismatch";
               end if;
            end;
            declare
               V1_Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Objects
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    V1_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Objects_Outcome :=
                 Low_Level.Execute_List_Objects
                   (HTTP, V1_Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Rejected
                 or else US.To_String (Result.Error.Request_ID) /=
                   "v1-socket-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "v1-socket-host"
               then
                  raise Program_Error with
                    "typed ListObjects socket error mismatch";
               end if;
            end;
         end;
         declare
            Stop      : aliased Flyology.Cancellation.Token;
            Cancelled : Boolean := False;
            Timed_Out : Boolean := False;
         begin
            Stop.Request;
            begin
               declare
                  Ignored : constant Objects.List_V1_Outcome :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-v1/", Maximum => 1,
                       Timeout => 5.0, Token => Stop'Access);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Cancelled := True;
            end;
            begin
               declare
                  Ignored : constant Objects.List_V1_Outcome :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-v1/", Maximum => 1,
                       Timeout => 0.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.IO.Timeout_Error =>
                  Timed_Out := True;
            end;
            if not Cancelled or else not Timed_Out then
               raise Program_Error with
                 "high-level ListObjects v1 ignored cancellation/deadline";
            end if;
         end;
         declare
            Special_Key : constant String :=
              "socket-v1/a /%" & Character'Val (16#C3#) &
              Character'Val (16#A9#);
            First : constant Objects.List_V1_Outcome :=
              Objects.List_V1_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "socket-v1/", Maximum => 1,
                 URL_Encoding => True, Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else Natural (First.Page.Contents.Length) /= 1
              or else not First.Page.Is_Truncated
              or else First.Page.Has_Next_Marker
              or else not First.Has_Next_Marker
              or else US.To_String (First.Next_Marker) /= Special_Key
            then
               raise Program_Error with
                 "high-level ListObjects v1 lost derived marker";
            end if;
            declare
               Next : constant Objects.List_V1_Outcome :=
                 Objects.List_V1_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "socket-v1/", Maximum => 1,
                    Marker => US.To_String (First.Next_Marker),
                    URL_Encoding => True,
                    Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Natural (Next.Page.Contents.Length) /= 1
                 or else US.To_String
                   (Next.Page.Contents.First_Element.Key) /= "socket-v1/b"
                 or else Next.Page.Is_Truncated
                 or else Next.Has_Next_Marker
               then
                  raise Program_Error with
                    "high-level ListObjects v1 continuation mismatch";
               end if;
            end;
         end;
         declare
            Delimiter_Marker : constant String :=
              "socket-v1/group %/" & Character'Val (16#C3#) &
              Character'Val (16#A9#);
            First : constant Objects.List_V1_Outcome :=
              Objects.List_V1_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "socket-v1/", Delimiter => "/", Maximum => 1,
                 URL_Encoding => True, Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else Natural (First.Page.Common_Prefixes.Length) /= 1
              or else not First.Page.Has_Next_Marker
              or else not First.Has_Next_Marker
              or else US.To_String (First.Next_Marker) /= Delimiter_Marker
            then
               raise Program_Error with
                 "high-level ListObjects v1 lost decoded NextMarker";
            end if;
            declare
               Next : constant Objects.List_V1_Outcome :=
                 Objects.List_V1_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "socket-v1/", Delimiter => "/", Maximum => 1,
                    Marker => US.To_String (First.Next_Marker),
                    URL_Encoding => True, Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Next.Page.Is_Truncated
                 or else Next.Has_Next_Marker
               then
                  raise Program_Error with
                    "high-level ListObjects v1 delimiter " &
                    "continuation mismatch";
               end if;
            end;
         end;
         declare
            Rejected : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Objects.List_V1_Outcome :=
                    Objects.List_V1_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-v1/", Maximum => 1,
                       URL_Encoding => True, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Rejected := True;
            end;
            if not Rejected then
               raise Program_Error with
                 "high-level ListObjects v1 accepted malformed URL marker";
            end if;
         end;
         declare
            Result : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Listed
              or else Result.Listing.Key_Count /= 0
              or else US.To_String (Result.Request_Charged) /= "requester"
            then
               raise Program_Error with "socket success result mismatch";
            end if;
         end;
         declare
            Result : constant Low_Level.List_Objects_V2_Outcome :=
              Low_Level.Execute_List_Objects_V2
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Rejected
              or else US.To_String (Result.Error.Request_ID) /=
                "socket-request"
              or else US.To_String (Result.Error.Host_ID) /= "socket-host"
            then
               raise Program_Error with "socket error result mismatch";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.List_Objects_V2_Outcome :=
                    Low_Level.Execute_List_Objects_V2
                      (HTTP, Prepared, Timeout => 5.0,
                       Limits =>
                         (Maximum_Document_Bytes => 64,
                          Maximum_Depth          => 8,
                          Maximum_Elements       => 32,
                          Maximum_Text_Bytes     => 64));
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with "oversized socket response accepted";
            end if;
         end;
         declare
            Stop      : aliased Flyology.Cancellation.Token;
            Cancelled : Boolean := False;
            Timed_Out : Boolean := False;
         begin
            Stop.Request;
            begin
               declare
                  Ignored : constant Objects.List_Outcome :=
                    Objects.List_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-page/", Maximum => 1,
                       Timeout => 5.0, Token => Stop'Access);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Cancelled := True;
            end;
            begin
               declare
                  Ignored : constant Objects.List_Outcome :=
                    Objects.List_Page
                      (HTTP, Origin, "example-bucket", Identity,
                       Prefix => "socket-page/", Maximum => 1,
                       Timeout => 0.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Flyology.IO.Timeout_Error =>
                  Timed_Out := True;
            end;
            if not Cancelled or else not Timed_Out then
               raise Program_Error with
                 "high-level ListObjectsV2 ignored cancellation/deadline";
            end if;
         end;
         declare
            First : constant Objects.List_Outcome :=
              Objects.List_Page
                (HTTP, Origin, "example-bucket", Identity,
                 Prefix => "socket-page/", Maximum => 1, Timeout => 5.0);
         begin
            if First.Kind /= Objects.Page_Available
              or else Natural (First.Page.Contents.Length) /= 1
              or else not First.Page.Is_Truncated
              or else not First.Page.Has_Next_Continuation_Token
              or else US.To_String (First.Page.Next_Continuation_Token) /=
                "opaque-next"
            then
               raise Program_Error with
                 "high-level ListObjectsV2 lost truncated-page token";
            end if;
            declare
               Next : constant Objects.List_Outcome :=
                 Objects.List_Page
                   (HTTP, Origin, "example-bucket", Identity,
                    Prefix => "socket-page/", Maximum => 1,
                    Continuation_Token => US.To_String
                      (First.Page.Next_Continuation_Token),
                    Timeout => 5.0);
            begin
               if Next.Kind /= Objects.Page_Available
                 or else Natural (Next.Page.Contents.Length) /= 1
                 or else US.To_String
                   (Next.Page.Contents.First_Element.Key) /= "socket-page/b"
                 or else Next.Page.Is_Truncated
                 or else Next.Page.Has_Next_Continuation_Token
               then
                  raise Program_Error with
                    "high-level ListObjectsV2 continuation mismatch";
               end if;
            end;
         end;
         declare
            List_Parameters : Low_Level.List_Multipart_Uploads_Parameters;
         begin
            List_Parameters.Delimiter := US.To_Unbounded_String ("/");
            List_Parameters.Key_Marker :=
              US.To_Unbounded_String ("before");
            List_Parameters.Max_Uploads := 2;
            List_Parameters.Prefix := US.To_Unbounded_String ("socket/");
            List_Parameters.Upload_ID_Marker :=
              US.To_Unbounded_String ("upload-before");
            List_Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            List_Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            declare
               Prepared_Uploads : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Multipart_Uploads
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    List_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Multipart_Uploads_Outcome :=
                 Low_Level.Execute_List_Multipart_Uploads
                   (HTTP, Prepared_Uploads, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Multipart_Uploads_Listed
                 or else Natural
                   (Result.Result.Listing.Uploads.Length) /= 1
                 or else US.To_String
                   (Result.Result.Listing.Uploads.First_Element.Upload_ID) /=
                     "socket-upload"
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
               then
                  raise Program_Error with
                    "typed ListMultipartUploads socket success mismatch";
               end if;
            end;
            declare
               Prepared_Uploads : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Multipart_Uploads
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    List_Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.List_Multipart_Uploads_Outcome :=
                 Low_Level.Execute_List_Multipart_Uploads
                   (HTTP, Prepared_Uploads, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.List_Multipart_Uploads_Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "list-uploads-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "list-uploads-host"
               then
                  raise Program_Error with
                    "typed ListMultipartUploads socket error mismatch";
               end if;
            end;
         end;
         declare
            Put_Parameters : constant
              Low_Level.Put_Bucket_Versioning_Parameters :=
              (Content_MD5 => US.Null_Unbounded_String,
               Checksum_Algorithm => US.Null_Unbounded_String,
               MFA => US.Null_Unbounded_String,
               Configuration =>
                 (Status     =>
                    Flyology.Object_Storage.Versioning_Enabled,
                  MFA_Delete =>
                    Flyology.Object_Storage.MFA_Delete_Unconfigured),
               Expected_Bucket_Owner =>
                 US.To_Unbounded_String ("123456789012"));
            Put_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Versioning
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Put_Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Put_Result : constant
              Low_Level.Put_Bucket_Versioning_Outcome :=
                Low_Level.Execute_Put_Bucket_Versioning
                  (HTTP, Put_Prepared, Timeout => 5.0);
            Get_Parameters : constant
              Low_Level.Get_Bucket_Versioning_Parameters :=
                (Expected_Bucket_Owner =>
                   US.To_Unbounded_String ("123456789012"));
            Get_Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Versioning
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Get_Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Get_Result : constant
              Low_Level.Get_Bucket_Versioning_Outcome :=
                Low_Level.Execute_Get_Bucket_Versioning
                  (HTTP, Get_Prepared, Timeout => 5.0);
         begin
            if Put_Result.Kind /= Low_Level.Bucket_Versioning_Updated then
               raise Program_Error with
                 "typed PutBucketVersioning socket result mismatch";
            elsif Get_Result.Kind /= Low_Level.Bucket_Versioning_Found
              or else
                Get_Result.Configuration.Status /=
                  Flyology.Object_Storage.Versioning_Enabled
            then
               raise Program_Error with
                 "typed GetBucketVersioning socket result mismatch";
            end if;
         end;
         declare
            Set_Result : constant Client_Buckets.Set_Versioning_Outcome :=
              Client_Buckets.Set_Versioning
                (HTTP, Origin, "example-bucket",
                 Flyology.Object_Storage.Versioning_Suspended,
                 Identity, Timeout => 5.0);
            Get_Result : constant Client_Buckets.Get_Versioning_Outcome :=
              Client_Buckets.Get_Versioning
                (HTTP, Origin, "example-bucket", Identity,
                 Timeout => 5.0);
         begin
            if Set_Result.Kind /= Client_Buckets.Versioning_Updated
              or else Get_Result.Kind /= Client_Buckets.Versioning_Found
              or else
                Get_Result.Configuration.Status /=
                  Flyology.Object_Storage.Versioning_Suspended
            then
               raise Program_Error with
                 "convenience bucket versioning socket result mismatch";
            end if;
         end;
         declare
            Values : constant Low_Level.Model_Value_Array :=
              (1 =>
                 (Member_Name =>
                    US.To_Unbounded_String ("Bucket"),
                  Map_Key => US.Null_Unbounded_String,
                  Value => US.To_Unbounded_String ("example-bucket")));
            Prepared_Head : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Request
                (Model.Head_Bucket_Operation, Origin,
                 Low_Level.Path_Style, Values, "", False, "", Identity,
                 "us-east-1", "20130524T000000Z");
            Response : constant HTTP_Client.Response :=
              Low_Level.Execute_Model_Request
                (HTTP, Prepared_Head, Timeout => 5.0);
         begin
            if HTTP_Client.Status (Response) /= 200
              or else not HTTP_Client.Body_Complete (Response)
            then
               raise Program_Error with
                 "generic model execution result mismatch";
            end if;
         end;
         declare
            Values : constant Low_Level.Model_Value_Array :=
              ((Member_Name => US.To_Unbounded_String ("Bucket"),
                Map_Key => US.Null_Unbounded_String,
                Value => US.To_Unbounded_String ("example-bucket")),
               (Member_Name => US.To_Unbounded_String ("Key"),
                Map_Key => US.Null_Unbounded_String,
                Value => US.To_Unbounded_String ("model-stream")));
            Prepared_Put : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Model_Streaming_Request
                (Model.Put_Object_Operation, Origin,
                 Low_Level.Path_Style, Values,
                 SigV4.SHA256_Hex (Upload_Payload), Identity,
                 "us-east-1", "20130524T000000Z");
            Source : Upload_Source (Upload_Payload'Access);
            Response : constant HTTP_Client.Response :=
              Low_Level.Execute_Model_Request
                (HTTP, Prepared_Put, Source, Timeout => 5.0);
         begin
            if HTTP_Client.Status (Response) /= 200
              or else HTTP_Client.Header (Response, "etag") /=
                """model-stream"""
            then
               raise Program_Error with
                 "generic streaming model execution result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Put_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object
                (Origin, Low_Level.Path_Style, "example-bucket", "typed-put",
                 Parameters, SigV4.SHA256_Hex (Upload_Payload), Identity,
                 "us-east-1", "20130524T000000Z");
            Source : Upload_Source (Upload_Payload'Access);
            Result : constant Low_Level.Put_Object_Outcome :=
              Low_Level.Execute_Put_Object
                (HTTP, Prepared, Source, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Put
              or else US.To_String (Result.Result.Entity_Tag) /=
                """typed-put"""
              or else US.To_String (Result.Result.Checksum_Type) /=
                "FULL_OBJECT"
              or else US.To_String
                (Result.Result.Server_Side_Encryption) /= "aws:backup"
              or else not Result.Result.Bucket_Key_Enabled.Is_Set
              or else not Result.Result.Bucket_Key_Enabled.Value
              or else not Result.Result.Size.Is_Set
              or else Result.Result.Size.Value /= 1
            then
               raise Program_Error with "typed PutObject result mismatch";
            end if;
         end;
         Run_Conditional_Put_Lifecycle;
         declare
            Tags : Flyology.Object_Storage.Object_Tag_Set;
            Put_Parameters : Low_Level.Put_Object_Tagging_Parameters;
            Get_Parameters : Low_Level.Get_Object_Tagging_Parameters;
            Delete_Parameters : Low_Level.Delete_Object_Tagging_Parameters;
         begin
            Tags.Length := 1;
            Tags.Items (1) :=
              (Key => US.To_Unbounded_String ("team"),
               Value => US.To_Unbounded_String ("storage"));
            declare
               Prepared_Put : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Put_Object_Tagging
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-tagged", Tags, Put_Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Object_Tagging_Outcome :=
                 Low_Level.Execute_Put_Object_Tagging
                   (HTTP, Prepared_Put, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Tags_Put
                 or else US.To_String (Result.Result.Version_ID) /=
                   "tag-put-version"
               then
                  raise Program_Error with
                    "typed PutObjectTagging socket result mismatch";
               end if;
            end;
            declare
               Prepared_Get : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Tagging
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-tagged", Get_Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Object_Tagging_Outcome :=
                 Low_Level.Execute_Get_Object_Tagging
                   (HTTP, Prepared_Get, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Tags_Gotten
                 or else Result.Result.Tags /= Tags
                 or else US.To_String (Result.Result.Version_ID) /=
                   "tag-get-version"
               then
                  raise Program_Error with
                    "typed GetObjectTagging socket result mismatch";
               end if;
            end;
            declare
               Prepared_Delete : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Object_Tagging
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-tagged", Delete_Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Object_Tagging_Outcome :=
                 Low_Level.Execute_Delete_Object_Tagging
                   (HTTP, Prepared_Delete, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Tags_Deleted
                 or else US.To_String (Result.Result.Version_ID) /=
                   "tag-delete-version"
               then
                  raise Program_Error with
                    "typed DeleteObjectTagging socket result mismatch";
               end if;
            end;
            declare
               Put_Result : constant Objects.Tagging_Outcome :=
                 Objects.Put_Tags
                   (HTTP, Origin, "example-bucket", "convenient-tagged",
                    Tags, Identity, Timeout => 5.0);
               Get_Result : constant Objects.Tagging_Outcome :=
                 Objects.Get_Tags
                   (HTTP, Origin, "example-bucket", "convenient-tagged",
                    Identity, Timeout => 5.0);
               Delete_Result : constant Objects.Tagging_Outcome :=
                 Objects.Delete_Tags
                   (HTTP, Origin, "example-bucket", "convenient-tagged",
                    Identity, Timeout => 5.0);
            begin
               if Put_Result.Kind /= Objects.Tags_Replaced
                 or else Get_Result.Kind /= Objects.Tags_Read
                 or else Get_Result.Result.Tags /= Tags
                 or else Delete_Result.Kind /= Objects.Tags_Cleared
               then
                  raise Program_Error with
                    "convenient object tagging socket flow mismatch";
               end if;
            end;
         end;
         declare
            Request : Deletions.Delete_Objects_Request;
            Parameters : Low_Level.Delete_Objects_Parameters;
         begin
            Request.Quiet := True;
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key                    =>
                    US.To_Unbounded_String ("socket-delete-a"),
                  Version_ID             =>
                    US.To_Unbounded_String ("version-a"),
                  Has_ETag               => True,
                  ETag                   => US.To_Unbounded_String ("*"),
                  Has_Last_Modified_Time => True,
                  Last_Modified_Time     => US.To_Unbounded_String
                    ("Wed, 21 Oct 2015 07:28:00 GMT"),
                  Has_Size               => True,
                  Size                   => 7));
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String ("socket-delete-b"),
                  Version_ID => US.To_Unbounded_String ("version-b"),
                  others     => <>));
            Parameters.MFA := US.To_Unbounded_String ("device 123456");
            Parameters.Request_Payer :=
              US.To_Unbounded_String ("requester");
            Parameters.Bypass_Governance_Retention :=
              (Is_Set => True, Value => True);
            Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Parameters.Checksum_Algorithm :=
              US.To_Unbounded_String ("CRC32");
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Objects
                   (Origin, Low_Level.Path_Style, "example-bucket", Request,
                    Parameters, Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Delete_Objects_Outcome :=
                 Low_Level.Execute_Delete_Objects
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Objects_Deleted
                 or else Natural (Result.Result.Result.Deleted.Length) /= 1
                 or else Natural (Result.Result.Result.Errors.Length) /= 1
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
                 or else US.To_String
                   (Result.Result.Result.Deleted.First_Element.Key) /=
                     "socket-delete-a"
                 or else US.To_String
                   (Result.Result.Result.Deleted.First_Element.Version_ID) /=
                     "version-a"
                 or else not Result.Result.Result.Deleted.First_Element
                   .Delete_Marker.Is_Set
                 or else Result.Result.Result.Deleted.First_Element
                   .Delete_Marker.Value
                 or else US.To_String
                   (Result.Result.Result.Deleted.First_Element
                      .Delete_Marker_Version_ID) /= "marker-a"
                 or else US.To_String
                   (Result.Result.Result.Errors.First_Element.Key) /=
                     "socket-delete-b"
                 or else US.To_String
                   (Result.Result.Result.Errors.First_Element.Version_ID) /=
                     "version-b"
                 or else US.To_String
                   (Result.Result.Result.Errors.First_Element.Code) /=
                     "AccessDenied"
                 or else US.To_String
                   (Result.Result.Result.Errors.First_Element.Message) /=
                     "denied"
               then
                  raise Program_Error with
                    "typed DeleteObjects socket result mismatch";
               end if;
            end;
            Request.Objects.Clear;
            Request.Quiet := False;
            Request.Objects.Append
              (Deletions.Object_Identifier'
                 (Key        => US.To_Unbounded_String ("unsupported"),
                  Version_ID => US.To_Unbounded_String ("version-id"),
                  others     => <>));
            Parameters := (others => <>);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Delete_Objects
                   (Origin, Low_Level.Path_Style, "missing-bucket", Request,
                    Parameters, Identity, "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Delete_Objects_Outcome :=
                 Low_Level.Execute_Delete_Objects
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Delete_Objects_Rejected
                 or else US.To_String (Result.Error.Code) /= "NoSuchBucket"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "delete-missing-request"
               then
                  raise Program_Error with
                    "all-unsupported DeleteObjects socket classification " &
                    "mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
         begin
            Parameters.Version_ID :=
              US.To_Unbounded_String ("socket version");
            Parameters.Has_Max_Parts := True;
            Parameters.Max_Parts := 1;
            Parameters.Has_Part_Number_Marker := True;
            Parameters.Part_Number_Marker := 1;
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Expected_Bucket_Owner :=
              US.To_Unbounded_String ("123456789012");
            Parameters.Attributes :=
              (Entity_Tag => True, Checksum => False,
               Object_Parts => True, Storage_Class => False,
               Object_Size => True);
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Attributes
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "object key", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Result : constant Low_Level.Get_Object_Attributes_Outcome :=
                 Low_Level.Execute_Get_Object_Attributes
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Object_Attributes_Found
                 or else not Result.Result.Delete_Marker.Is_Set
                 or else Result.Result.Delete_Marker.Value
                 or else US.To_String (Result.Result.Version_ID) /=
                   "socket-version"
                 or else US.To_String (Result.Result.Request_Charged) /=
                   "requester"
                 or else not Result.Result.Attributes.Has_Object_Parts
                 or else Natural
                   (Result.Result.Attributes.Object_Parts.Parts.Length) /= 1
                 or else Result.Result.Attributes.Object_Size.Value /= 14
               then
                  raise Program_Error with
                    "typed GetObjectAttributes result mismatch";
               end if;
            end;
         end;
         declare
            Result : constant Objects.Get_Attributes_Outcome :=
              Objects.Get_Attributes
                (HTTP, Origin, "example-bucket", "convenience-attributes",
                 Identity, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Attributes_Found
              or else US.To_String (Result.Result.Attributes.Entity_Tag) /=
                """socket-attributes"""
              or else Result.Result.Attributes.Object_Size.Value /= 14
            then
               raise Program_Error with
                 "convenience GetObjectAttributes result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Get_Object_Attributes_Parameters;
         begin
            Parameters.Attributes.Object_Size := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object_Attributes
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "missing-attributes", Parameters, Identity,
                    "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Get_Object_Attributes_Outcome :=
                 Low_Level.Execute_Get_Object_Attributes
                   (HTTP, Prepared, Timeout => 5.0);
            begin
               if Result.Kind /=
                 Low_Level.Get_Object_Attributes_Rejected
                 or else US.To_String (Result.Error.Code) /= "AccessDenied"
                 or else US.To_String (Result.Error.Request_ID) /=
                   "attributes-request"
                 or else US.To_String (Result.Error.Host_ID) /=
                   "attributes-host"
               then
                  raise Program_Error with
                    "GetObjectAttributes socket rejection mismatch";
               end if;
            end;
         end;
         declare
            Upload_Path : constant String :=
              "/tmp/flyology-object-storage-upload-"
              & Decimal (Natural (Port)) & ".bin";
            Empty_Path : constant String := Upload_Path & ".empty";

            procedure Check_High_Level_Uploads is
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
               Stop : aliased Flyology.Cancellation.Token;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket", "cancelled",
                          Upload_Path, Identity, Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               if not Cancelled then
                  raise Program_Error with
                    "high-level upload ignored pre-cancellation";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Upload_Outcome :=
                       Transfers.Upload_File
                         (HTTP, Origin, "example-bucket", "timed-out",
                          Upload_Path, Identity, Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Timed_Out then
                  raise Program_Error with
                    "high-level upload ignored zero timeout";
               end if;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high level+file%25", Upload_Path, Identity,
                       Content_Type => "application/test", Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 23
                    or else US.To_String (Result.Entity_Tag) /=
                      """high-level"""
                  then
                     raise Program_Error with
                       "high-level file upload result mismatch";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket", "high-level-empty",
                       Empty_Path, Identity, Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Uploaded
                    or else Result.Bytes /= 0
                    or else US.To_String (Result.Entity_Tag) /= """empty"""
                  then
                     raise Program_Error with
                       "high-level empty upload result mismatch";
                  end if;
               end;
               declare
                  Result : constant Transfers.Upload_Outcome :=
                    Transfers.Upload_File
                      (HTTP, Origin, "example-bucket",
                       "high-level-rejected", Upload_Path, Identity,
                       Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.Upload_Rejected
                    or else Result.Status /= 403
                    or else US.To_String (Result.Error.Code) /=
                      "AccessDenied"
                  then
                     raise Program_Error with
                       "high-level upload rejection mismatch";
                  end if;
               end;
            end Check_High_Level_Uploads;
         begin
            Write_File (Upload_Path, "high-level file payload");
            Write_File (Empty_Path, "");
            begin
               Check_High_Level_Uploads;
            exception
               when others =>
                  Delete_If_Present (Upload_Path);
                  Delete_If_Present (Empty_Path);
                  raise;
            end;
            Delete_If_Present (Upload_Path);
            Delete_If_Present (Empty_Path);
         end;
         declare
            Download_Path : constant String :=
              "/tmp/flyology-object-storage-download-"
              & Decimal (Natural (Port)) & ".bin";
            Empty_Path : constant String := Download_Path & ".empty";
            Rejected_Path : constant String := Download_Path & ".rejected";
            Truncated_Path : constant String := Download_Path & ".truncated";
            Partial_Path : constant String := Download_Path & ".partial";
            Range_Path : constant String := Download_Path & ".range";
            Not_Modified_Path : constant String :=
              Download_Path & ".not-modified";
            Precondition_Path : constant String :=
              Download_Path & ".precondition";
            Invalid_Path : constant String := Download_Path & ".invalid";

            procedure Cleanup is
            begin
               Delete_If_Present (Download_Path);
               Delete_If_Present (Empty_Path);
               Delete_If_Present (Rejected_Path);
               Delete_If_Present (Truncated_Path);
               Delete_If_Present (Partial_Path);
               Delete_If_Present (Range_Path);
               Delete_If_Present (Not_Modified_Path);
               Delete_If_Present (Precondition_Path);
               Delete_If_Present (Invalid_Path);
            end Cleanup;

            procedure Check_High_Level_Downloads is
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
               Truncated : Boolean := False;
               Partial   : Boolean := False;
               Stop : aliased Flyology.Cancellation.Token;

               procedure Require_Invalid_Interval
                 (Key : String; Range_Header : String := "")
               is
                  Raised : Boolean := False;
               begin
                  Write_File (Invalid_Path, "preserve-invalid-interval");
                  begin
                     declare
                        Ignored : constant Transfers.Download_Outcome :=
                          Transfers.Download_File
                            (HTTP, Origin, "example-bucket", Key,
                             Invalid_Path, Identity, Timeout => 5.0,
                             Byte_Range_Header => Range_Header);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Low_Level.Invalid_Response =>
                        Raised := True;
                  end;
                  if not Raised
                    or else Read_File (Invalid_Path) /=
                      "preserve-invalid-interval"
                  then
                     raise Program_Error with
                       "invalid GetObject interval was accepted";
                  end if;
                  Require_No_Download_Temporary (Invalid_Path);
               end Require_Invalid_Interval;
            begin
               Write_File (Download_Path, "preserved-before-start");
               Stop.Request;
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket", "cancelled",
                          Download_Path, Identity, Timeout => 5.0,
                          Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               if not Cancelled
                 or else Read_File (Download_Path) /= "preserved-before-start"
               then
                  raise Program_Error with
                    "high-level download pre-cancellation was not atomic";
               end if;
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket", "timed-out",
                          Download_Path, Identity, Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Timed_Out
                 or else Read_File (Download_Path) /= "preserved-before-start"
               then
                  raise Program_Error with
                    "high-level download zero-timeout was not atomic";
               end if;
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket",
                       "download large+%25", Download_Path, Identity,
                       Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Downloaded
                    or else Result.Bytes /= Download_Payload'Length
                    or else US.To_String (Result.Entity_Tag) /=
                      """download-large"""
                    or else Read_File (Download_Path) /= Download_Payload
                  then
                     raise Program_Error with
                       "high-level large download result mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Download_Path);

               Write_File (Empty_Path, "replace-me");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-empty",
                       Empty_Path, Identity, Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.File_Downloaded
                    or else Result.Bytes /= 0
                    or else US.To_String (Result.Entity_Tag) /=
                      """download-empty"""
                    or else Read_File (Empty_Path)'Length /= 0
                  then
                     raise Program_Error with
                       "high-level empty download result mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Empty_Path);

               Write_File (Rejected_Path, "preserve-rejected");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-rejected",
                       Rejected_Path, Identity, Timeout => 5.0);
               begin
                  if Result.Kind /= Transfers.Download_Rejected
                    or else Result.Status /= 403
                    or else US.To_String (Result.Error.Code) /= "AccessDenied"
                    or else Read_File (Rejected_Path) /= "preserve-rejected"
                  then
                     raise Program_Error with
                       "high-level download rejection mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Rejected_Path);

               Write_File (Truncated_Path, "preserve-truncated");
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket",
                          "download-truncated", Truncated_Path, Identity,
                          Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.HTTP.Protocol_Error =>
                     Truncated := True;
               end;
               if not Truncated
                 or else Read_File (Truncated_Path) /= "preserve-truncated"
               then
                  raise Program_Error with
                    "truncated download replaced the destination";
               end if;
               Require_No_Download_Temporary (Truncated_Path);

               Write_File (Partial_Path, "preserve-partial");
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket",
                          "download-unexpected-range", Partial_Path,
                          Identity, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Partial := True;
               end;
               if not Partial
                 or else Read_File (Partial_Path) /= "preserve-partial"
               then
                  raise Program_Error with
                    "partial download replaced the whole-file destination";
               end if;
               Require_No_Download_Temporary (Partial_Path);

               Write_File (Range_Path, "replace-range");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-range",
                       Range_Path, Identity, Timeout => 5.0,
                       Byte_Range_Header => "bytes=7-13");
               begin
                  if Result.Kind /= Transfers.File_Downloaded
                    or else Result.Status /= 206
                    or else Result.Bytes /= 7
                    or else US.To_String (Result.Entity_Tag) /=
                      """download-range"""
                    or else Read_File (Range_Path) /= "partial"
                  then
                     raise Program_Error with
                       "high-level ranged download result mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Range_Path);

               Write_File (Not_Modified_Path, "preserve-not-modified");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket",
                       "download-not-modified", Not_Modified_Path, Identity,
                       Timeout => 5.0,
                       If_None_Match => """download-range""");
               begin
                  if Result.Kind /= Transfers.Download_Rejected
                    or else Result.Status /= 304
                    or else US.To_String (Result.Error.Code) /= "HTTP304"
                    or else Read_File (Not_Modified_Path) /=
                      "preserve-not-modified"
                  then
                     raise Program_Error with
                       "high-level conditional 304 download mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Not_Modified_Path);

               Write_File (Precondition_Path, "preserve-precondition");
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket",
                       "download-precondition", Precondition_Path, Identity,
                       Timeout => 5.0, If_Match => """different""");
               begin
                  if Result.Kind /= Transfers.Download_Rejected
                    or else Result.Status /= 412
                    or else US.To_String (Result.Error.Code) /= "HTTP412"
                    or else Read_File (Precondition_Path) /=
                      "preserve-precondition"
                  then
                     raise Program_Error with
                       "high-level conditional 412 download mismatch";
                  end if;
               end;
               Require_No_Download_Temporary (Precondition_Path);

               Require_Invalid_Interval
                 ("download-missing-content-range", "bytes=0-0");
               Require_Invalid_Interval
                 ("download-length-mismatch", "bytes=0-0");
               Require_Invalid_Interval
                 ("download-invalid-content-range", "bytes=0-0");
               Require_Invalid_Interval
                 ("download-unsolicited-content-range");
            end Check_High_Level_Downloads;
         begin
            begin
               Check_High_Level_Downloads;
            exception
               when others =>
                  Cleanup;
                  raise;
            end;
            Cleanup;
         end;
         declare
            Result : constant Transfers.Copy_Outcome :=
              Transfers.Copy_Object
                (HTTP, Origin, "source-bucket", "source key+%25",
                 "example-bucket", "copied object+%25", Identity,
                 Source_If_Match => """source-etag""",
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Object_Copied
              or else Result.Status /= 200
              or else US.To_String (Result.Entity_Tag) /=
                """high-level-copy"""
              or else US.To_String (Result.Last_Modified) /=
                "2026-08-21T17:00:00.000Z"
              or else US.To_String (Result.Version_ID) /=
                "destination-version"
              or else US.To_String (Result.Copy_Source_Version_ID) /=
                "source-version"
            then
               raise Program_Error with
                 "high-level CopyObject result mismatch";
            end if;
         end;
         declare
            Result : constant Transfers.Copy_Outcome :=
              Transfers.Copy_Object
                (HTTP, Origin, "source-bucket", "source-key",
                 "example-bucket", "copy-rejected", Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Copy_Rejected
              or else Result.Status /= 412
              or else US.To_String (Result.Error.Code) /= "AccessDenied"
            then
               raise Program_Error with
                 "high-level CopyObject rejection mismatch";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Transfers.Copy_Outcome :=
                    Transfers.Copy_Object
                      (HTTP, Origin, "source-bucket",
                       String'(1 .. 8_192 => 'x'), "example-bucket",
                       "copy-too-large", Identity, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "oversized high-level CopyObject source was accepted";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Transfers.Copy_Outcome :=
                    Transfers.Copy_Object
                      (HTTP, Origin, "source/bucket", "source-key",
                       "example-bucket", "copy-invalid-source", Identity,
                       Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Request =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "ambiguous high-level CopyObject source was accepted";
            end if;
         end;
         declare
            Result : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "head object+%25",
                 Identity, Version_ID => "version one",
                 If_Match => """expected-etag""", Checksum_Mode => True,
                 Timeout => 5.0,
                 If_Modified_Since =>
                   "Fri, 21 Aug 2026 16:00:00 GMT",
                 If_None_Match => """other-etag""",
                 If_Unmodified_Since =>
                   "Fri, 21 Aug 2026 18:00:00 GMT",
                 Byte_Range_Header => "bytes=1-4",
                 Response_Cache_Control => "no-cache",
                 Response_Content_Disposition => "attachment",
                 Response_Content_Encoding => "gzip",
                 Response_Content_Language => "en-CA",
                 Response_Content_Type => "application/test",
                 Response_Expires => "Fri, 21 Aug 2026 18:00:00 GMT",
                 Part_Number => (Is_Set => True, Value => 3));
         begin
            if Result.Kind /= Transfers.Object_Found
              or else Result.Status /= 200
              or else Result.Bytes /= 4
              or else US.To_String (Result.Entity_Tag) /= """head-etag"""
              or else US.To_String (Result.Last_Modified) /=
                "Fri, 21 Aug 2026 17:00:00 GMT"
              or else US.To_String (Result.Content_Type) /=
                "application/test"
              or else US.To_String (Result.Version_ID) /= "head-version"
              or else US.To_String (Result.Checksum_SHA256) /=
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
              or else US.To_String (Result.Checksum_Type) /= "COMPOSITE"
              or else not Result.Details.Parts_Count.Is_Set
              or else Result.Details.Parts_Count.Value /= 3
              or else US.Length (Result.Details.Content_Range) /= 0
            then
               raise Program_Error with "high-level HeadObject mismatch";
            end if;
         end;
         declare
            Result : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "head-policy", Identity,
                 Request_Payer => "requester",
                 Expected_Bucket_Owner => "123456789012",
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Object_Found
              or else Result.Status /= 200
              or else Result.Bytes /= 42
            then
               raise Program_Error with
                 "high-level HeadObject owner/payer mismatch";
            end if;
         end;
         declare
            Result : constant Transfers.Head_Outcome :=
              Transfers.Head_Object
                (HTTP, Origin, "example-bucket", "head-missing", Identity,
                 Timeout => 5.0);
         begin
            if Result.Kind /= Transfers.Head_Rejected
              or else Result.Status /= 404
              or else US.To_String (Result.Error.Code) /= "HTTP404"
              or else US.To_String (Result.Error.Request_ID) /=
                "head-request"
              or else US.To_String (Result.Error.Host_ID) /= "head-host"
            then
               raise Program_Error with
                 "bodyless high-level HeadObject rejection mismatch";
            end if;
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Transfers.Head_Outcome :=
                    Transfers.Head_Object
                      (HTTP, Origin, "example-bucket",
                       "head-invalid-checksum", Identity, Timeout => 5.0);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "invalid HeadObject checksum was accepted";
            end if;
         end;
         for Index in 1 .. 2 loop
            declare
               Key : constant String :=
                 (if Index = 1 then "head-duplicate-header"
                  else "head-transfer-encoding");
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant Transfers.Head_Outcome :=
                       Transfers.Head_Object
                         (HTTP, Origin, "example-bucket", Key,
                          Identity, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with
                    "invalid HeadObject singleton/framing was accepted";
               end if;
            end;
         end loop;
         declare
            Parameters : Low_Level.Head_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Head_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "typed-head", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Head_Object_Outcome :=
              Low_Level.Execute_Head_Object
                (HTTP, Prepared, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Object_Found
              or else Result.Status /= 200
              or else Result.Result.Content_Length /= 7
              or else US.To_String (Result.Result.Entity_Tag) /=
                """typed-head"""
              or else Natural (Result.Result.Metadata.Length) /= 2
              or else US.To_String
                (Result.Result.Metadata.First_Element.Name) /= "project"
              or else not Result.Result.Parts_Count.Is_Set
              or else Result.Result.Parts_Count.Value /= 3
              or else US.To_String (Result.Result.Server_Side_Encryption) /=
                "aws:backup"
              or else US.To_String (Result.Result.Storage_Class) /=
                "AWS_BACKUP_WARM"
            then
               raise Program_Error with "typed HeadObject result mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
         begin
            Parameters.If_Match :=
              US.To_Unbounded_String ("""expected-etag""");
            Parameters.Version_ID :=
              US.To_Unbounded_String ("version one");
            Parameters.Checksum_Mode := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-get", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Response : HTTP_Client.Response :=
                 Low_Level.Execute_Get_Object
                   (HTTP, Prepared, Timeout => 5.0);
               Result : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Response_Head (Response);
               Received : US.Unbounded_String;
               Buffer : Stream_Element_Array (1 .. 3);
               Last : Stream_Element_Offset;
               Finished : Boolean := False;
            begin
               if Result.Kind /= Low_Level.Object_Opened
                 or else Result.Status /= 206
                 or else not Result.Result.Content_Length.Is_Set
                 or else Result.Result.Content_Length.Value /= 7
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """typed-get"""
                 or else US.To_String (Result.Result.Content_Range) /=
                   "bytes 1-7/9"
                 or else Natural (Result.Result.Metadata.Length) /= 2
                 or else US.To_String
                   (Result.Result.Metadata.First_Element.Name) /= "project"
                 or else US.To_String (Result.Result.Checksum_Type) /=
                   "COMPOSITE"
                 or else US.To_String (Result.Result.Checksum_SHA256) /=
                   "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=-3"
                 or else US.To_String
                   (Result.Result.Server_Side_Encryption) /= "aws:backup"
                 or else US.To_String (Result.Result.Storage_Class) /=
                   "AWS_BACKUP_WARM"
               then
                  raise Program_Error with "typed GetObject head mismatch";
               end if;
               while not Finished loop
                  HTTP_Client.Read_Body
                    (Response, Buffer, Last, Finished);
                  for Index in Buffer'First .. Last loop
                     US.Append (Received, Character'Val (Buffer (Index)));
                  end loop;
               end loop;
               if US.To_String (Received) /= "getdata" then
                  raise Program_Error with "typed GetObject body mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
         begin
            Parameters.Checksum_Mode := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "typed-get-full", Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Response : HTTP_Client.Response :=
                 Low_Level.Execute_Get_Object
                   (HTTP, Prepared, Timeout => 5.0);
               Result : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Response_Head (Response);
               Received : US.Unbounded_String;
               Buffer : Stream_Element_Array (1 .. 3);
               Last : Stream_Element_Offset;
               Finished : Boolean := False;
            begin
               if Result.Kind /= Low_Level.Object_Opened
                 or else Result.Status /= 200
                 or else US.To_String (Result.Result.Checksum_Type) /=
                   "FULL_OBJECT"
                 or else US.To_String
                   (Result.Result.Checksum_CRC64NVME) /= "AAAAAAAAAAA="
               then
                  raise Program_Error with
                    "full-object GetObject checksum mismatch";
               end if;
               while not Finished loop
                  HTTP_Client.Read_Body
                    (Response, Buffer, Last, Finished);
                  for Index in Buffer'First .. Last loop
                     US.Append (Received, Character'Val (Buffer (Index)));
                  end loop;
               end loop;
               if US.To_String (Received) /= "full" then
                  raise Program_Error with
                    "full-object GetObject body mismatch";
               end if;
            end;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "typed-get-missing", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (HTTP, Prepared, Timeout => 5.0);
            Result : constant Low_Level.Get_Object_Head_Outcome :=
              Low_Level.Decode_Get_Object_Response_Head (Response);
         begin
            if Result.Kind /= Low_Level.Get_Object_Rejected
              or else Result.Status /= 304
              or else US.To_String (Result.Error.Code) /= "HTTP304"
              or else US.To_String (Result.Error.Request_ID) /=
                "get-request"
              or else US.To_String (Result.Error.Host_ID) /= "get-host"
              or else not HTTP_Client.Body_Complete (Response)
            then
               raise Program_Error with
                 "typed GetObject bodyless rejection mismatch";
            end if;
         end;
         declare
            Parameters : Low_Level.Get_Object_Parameters;
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "typed-get-invalid", Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object
                (HTTP, Prepared, Timeout => 5.0);
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Get_Object_Head_Outcome :=
                    Low_Level.Decode_Get_Object_Response_Head (Response);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "typed GetObject accepted an invalid checksum";
            end if;
         end;
         declare
            procedure Reject_Invalid_Get
              (Key : String; Message : String) is
               Parameters : Low_Level.Get_Object_Parameters;
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Get_Object
                   (Origin, Low_Level.Path_Style, "example-bucket", Key,
                    Parameters, Identity, "us-east-1",
                    "20130524T000000Z");
               Response : HTTP_Client.Response :=
                 Low_Level.Execute_Get_Object
                   (HTTP, Prepared, Timeout => 5.0);
               Raised : Boolean := False;
            begin
               begin
                  declare
                     Ignored : constant
                       Low_Level.Get_Object_Head_Outcome :=
                         Low_Level.Decode_Get_Object_Response_Head (Response);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with Message;
               end if;
            end Reject_Invalid_Get;
         begin
            Reject_Invalid_Get
              ("typed-get-multiple",
               "GetObject accepted multiple checksum algorithm headers");
            Reject_Invalid_Get
              ("typed-get-illegal-pair",
               "GetObject accepted composite CRC64NVME metadata");
            Reject_Invalid_Get
              ("typed-get-type-only",
               "GetObject accepted checksum type without an algorithm");
         end;
         declare
            Value : Tags.Tag_Set;
         begin
            declare
               Stop : aliased Flyology.Cancellation.Token;
               Cancelled : Boolean := False;
               Timed_Out : Boolean := False;
            begin
               Stop.Request;
               begin
                  declare
                     Ignored : constant Buckets.Delete_Tags_Outcome :=
                       Buckets.Delete_Tags
                         (HTTP, Origin, "example-bucket", Identity,
                          Timeout => 5.0, Token => Stop'Access);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.Cancellation.Operation_Cancelled =>
                     Cancelled := True;
               end;
               begin
                  declare
                     Ignored : constant Buckets.Delete_Tags_Outcome :=
                       Buckets.Delete_Tags
                         (HTTP, Origin, "example-bucket", Identity,
                          Timeout => 0.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Flyology.IO.Timeout_Error =>
                     Timed_Out := True;
               end;
               if not Cancelled or else not Timed_Out then
                  raise Program_Error with
                    "DeleteBucketTagging ignored cancellation/deadline";
               end if;
            end;
            Value.Append
              (Tags.Tag'
                 (Key   => US.To_Unbounded_String ("project"),
                  Value => US.To_Unbounded_String ("flyology")));
            declare
               Put_Result : constant Buckets.Put_Tags_Outcome :=
                 Buckets.Put_Tags
                   (HTTP, Origin, "example-bucket", Value, Identity,
                    Timeout => 5.0);
               Get_Result : constant Buckets.Get_Tags_Outcome :=
                 Buckets.Get_Tags
                   (HTTP, Origin, "example-bucket", Identity,
                    Timeout => 5.0);
            begin
               if Put_Result.Kind /= Buckets.Tags_Replaced
                 or else Get_Result.Kind /= Buckets.Tags_Found
                 or else Get_Result.Value /= Value
               then
                  raise Program_Error with
                    "high-level bucket tagging socket mismatch";
               end if;
            end;
            declare
               Delete_Result : constant Buckets.Delete_Tags_Outcome :=
                 Buckets.Delete_Tags
                   (HTTP, Origin, "example-bucket", Identity,
                    Timeout => 5.0);
               Get_Result : constant Buckets.Get_Tags_Outcome :=
                 Buckets.Get_Tags
                   (HTTP, Origin, "example-bucket", Identity,
                    Timeout => 5.0);
            begin
               if Delete_Result.Kind /= Buckets.Tags_Deleted
                 or else Get_Result.Kind /= Buckets.Get_Tags_Rejected
                 or else US.To_String (Get_Result.Error.Code) /=
                   "NoSuchTagSet"
               then
                  raise Program_Error with
                    "high-level bucket tag deletion socket mismatch";
               end if;
            end;
            declare
               Delete_Result : constant Buckets.Delete_Tags_Outcome :=
                 Buckets.Delete_Tags
                   (HTTP, Origin, "example-bucket", Identity,
                    Timeout => 5.0);
            begin
               if Delete_Result.Kind /= Buckets.Tags_Deleted then
                  raise Program_Error with
                    "high-level bucket tag deletion was not idempotent";
               end if;
            end;
         end;
         declare
            Prepared_Create : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Create_Multipart_Upload
                (Origin, Low_Level.Path_Style, "example-bucket",
                 "object key", Identity, "us-east-1",
                 "20130524T000000Z");
            Result : constant Low_Level.Create_Multipart_Outcome :=
              Low_Level.Execute_Create_Multipart_Upload
                (HTTP, Prepared_Create, Timeout => 5.0);
         begin
            if Result.Kind /= Low_Level.Created
              or else US.To_String (Result.Result.Upload_ID) /=
                "socket-upload"
            then
               raise Program_Error with
                 "socket CreateMultipartUpload result mismatch";
            end if;
         end;
         declare
            Completion : Multipart.Complete_Multipart_Upload_Request;
         begin
            declare
               Parameters : Low_Level.Upload_Part_Parameters;
               Source : Upload_Source (Upload_Payload'Access);
            begin
               Parameters.Upload_ID :=
                 US.To_Unbounded_String ("socket-upload");
               Parameters.Payload_SHA256 := US.To_Unbounded_String
                 (SigV4.SHA256_Hex (Upload_Payload));
               declare
                  Prepared_Upload : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Upload_Part
                      (Origin, Low_Level.Path_Style, "example-bucket",
                       "object key", Parameters, Identity, "us-east-1",
                       "20130524T000000Z");
                  Uploaded : constant Low_Level.Upload_Part_Outcome :=
                    Low_Level.Execute_Upload_Part
                      (HTTP, Prepared_Upload, Source, Timeout => 5.0);
               begin
                  if Uploaded.Kind /= Low_Level.Part_Uploaded
                    or else US.To_String (Uploaded.Result.Entity_Tag) /=
                      """socket-part"""
                  then
                     raise Program_Error with
                       "socket UploadPart result mismatch";
                  end if;
               end;
            end;
            Completion.Parts.Append
              (Multipart.Completed_Part'
                 (Number => 1,
                  Entity_Tag => US.To_Unbounded_String ("""part"""),
                  others => <>));
            declare
               Prepared_Complete : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Complete_Multipart_Upload
                   (Origin, Low_Level.Path_Style, "example-bucket",
                    "object key", "socket-upload", Completion, Identity,
                    "us-east-1", "20130524T000000Z");
               Result : constant Low_Level.Complete_Multipart_Outcome :=
                 Low_Level.Execute_Complete_Multipart_Upload
                   (HTTP, Prepared_Complete, Timeout => 5.0);
            begin
               if Result.Kind /= Low_Level.Completed
                 or else US.To_String (Result.Result.Entity_Tag) /=
                   """whole"""
               then
                  raise Program_Error with
                    "socket CompleteMultipartUpload result mismatch";
               end if;
               declare
                  Embedded : constant Low_Level.Complete_Multipart_Outcome :=
                    Low_Level.Execute_Complete_Multipart_Upload
                      (HTTP, Prepared_Complete, Timeout => 5.0);
               begin
                  if Embedded.Kind /= Low_Level.Complete_Rejected
                    or else US.To_String (Embedded.Error.Code) /=
                      "InternalError"
                  then
                     raise Program_Error with
                       "socket embedded multipart error mismatch";
                  end if;
               end;
               declare
                  Prepared_Abort : constant Low_Level.Prepared_Request :=
                    Low_Level.Prepare_Abort_Multipart_Upload
                      (Origin, Low_Level.Path_Style, "example-bucket",
                       "object key", "socket-upload", Identity,
                       "us-east-1", "20130524T000000Z");
                  Aborted_Result : constant
                    Low_Level.Abort_Multipart_Outcome :=
                      Low_Level.Execute_Abort_Multipart_Upload
                        (HTTP, Prepared_Abort, Timeout => 5.0);
               begin
                  if Aborted_Result.Kind /= Low_Level.Aborted then
                     raise Program_Error with
                       "socket AbortMultipartUpload result mismatch";
                  end if;
               end;
            end;
         end;
         HTTP_Client.Shutdown (HTTP);
      end;
   end Run_Client;

   procedure Run_And_Report is
   begin
      Run_Client;
      Clients.Report (True);
   exception
      when Occurrence : others =>
         Clients.Report
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Run_And_Report;

   Server_Passed : Boolean;
   Client_Passed : Boolean;
   Server_Detail : US.Unbounded_String;
   Client_Detail : US.Unbounded_String;
begin
   Run_And_Report;
   declare
      task Lightweight_Client is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Lightweight_Client;

      task body Lightweight_Client is
      begin
         Run_And_Report;
      end Lightweight_Client;
   begin
      null;
   end;
   Clients.Wait_All (Client_Passed, Client_Detail);
   State.Wait_Done (Server_Passed, Server_Detail);
   if not Client_Passed then
      raise Program_Error with US.To_String (Client_Detail);
   elsif not Server_Passed then
      raise Program_Error with US.To_String (Server_Detail);
   end if;
   Ada.Text_IO.Put_Line ("S3 HTTP socket corpus: OK");
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("S3 HTTP socket corpus failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_HTTP_Socket_Corpus;
