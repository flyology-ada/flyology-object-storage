with Ada.Command_Line;
with Ada.Containers;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;

--  Correctness-checking driver for the multipart-upload listing benchmark.
--  Setup, measurement, and cleanup use the same client for every endpoint.
procedure S3_Multipart_Listing_Benchmark is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;

   Access_Key_Name : constant String := "AWS_ACCESS_KEY_ID";
   Secret_Key_Name : constant String := "AWS_SECRET_ACCESS_KEY";
   subtype Upload_Count is Positive range 1 .. 1_000;

   function Decimal (Value : Positive) return String is
      Image : constant String := Value'Image;
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal;

   function Key_For (Prefix : String; Index : Positive) return String is
      Numerals : constant String := Decimal (Index);
      Padding  : constant Natural := 8 - Numerals'Length;
   begin
      return Prefix & "-" & String'(1 .. Padding => '0') & Numerals;
   end Key_For;

begin
   if Ada.Command_Line.Argument_Count /= 6 then
      raise Program_Error with
        "usage: s3_multipart_listing_benchmark ENDPOINT BUCKET " &
        "YYYYMMDDTHHMMSSZ setup|list|cleanup PREFIX COUNT";
   elsif not Ada.Environment_Variables.Exists (Access_Key_Name)
     or else not Ada.Environment_Variables.Exists (Secret_Key_Name)
   then
      raise Program_Error with
        "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required";
   end if;

   declare
      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin (Ada.Command_Line.Argument (1));
      Bucket : constant String := Ada.Command_Line.Argument (2);
      Timestamp : constant String := Ada.Command_Line.Argument (3);
      Mode : constant String := Ada.Command_Line.Argument (4);
      Prefix : constant String := Ada.Command_Line.Argument (5);
      Count : constant Upload_Count :=
        Upload_Count'Value (Ada.Command_Line.Argument (6));
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Identity : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials
          (Ada.Environment_Variables.Value (Access_Key_Name),
           Ada.Environment_Variables.Value (Secret_Key_Name));

      function Listing return Low_Level.List_Multipart_Uploads_Result is
         Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      begin
         Parameters.Prefix := US.To_Unbounded_String (Prefix & "-");
         Parameters.Max_Uploads := Count;
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_List_Multipart_Uploads
                (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
                 "us-east-1", Timestamp);
            Outcome : constant Low_Level.List_Multipart_Uploads_Outcome :=
              Low_Level.Execute_List_Multipart_Uploads
                (HTTP, Prepared, Timeout => 30.0);
         begin
            if Outcome.Kind /= Low_Level.Multipart_Uploads_Listed then
               raise Program_Error with
                 "ListMultipartUploads rejected:" & Outcome.Status'Image &
                 " " & US.To_String (Outcome.Error.Code) & " " &
                 US.To_String (Outcome.Error.Message);
            end if;
            return Outcome.Result;
         end;
      end Listing;

      procedure Verify (Value : Low_Level.List_Multipart_Uploads_Result) is
      begin
         if Value.Listing.Uploads.Length /= Ada.Containers.Count_Type (Count)
           or else Value.Listing.Is_Truncated
         then
            raise Program_Error with
              "ListMultipartUploads page mismatch: count=" &
              Value.Listing.Uploads.Length'Image & " truncated=" &
              Value.Listing.Is_Truncated'Image;
         end if;
         for Index in 1 .. Count loop
            if US.To_String (Value.Listing.Uploads.Element (Index).Key) /=
              Key_For (Prefix, Index)
            then
               raise Program_Error with
                 "ListMultipartUploads key ordering mismatch at" &
                 Index'Image;
            end if;
         end loop;
      end Verify;

      procedure Setup is
      begin
         for Index in 1 .. Count loop
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Create_Multipart_Upload
                   (Origin, Low_Level.Path_Style, Bucket,
                    Key_For (Prefix, Index), Identity, "us-east-1",
                    Timestamp);
               Outcome : constant Low_Level.Create_Multipart_Outcome :=
                 Low_Level.Execute_Create_Multipart_Upload
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Created then
                  raise Program_Error with
                    "CreateMultipartUpload rejected:" &
                    Outcome.Status'Image & " " &
                    US.To_String (Outcome.Error.Code) & " " &
                    US.To_String (Outcome.Error.Message);
               end if;
            end;
         end loop;
         Verify (Listing);
      end Setup;

      procedure Cleanup is
         Value : constant Low_Level.List_Multipart_Uploads_Result := Listing;
      begin
         Verify (Value);
         for Upload of Value.Listing.Uploads loop
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Abort_Multipart_Upload
                   (Origin, Low_Level.Path_Style, Bucket,
                    US.To_String (Upload.Key),
                    US.To_String (Upload.Upload_ID), Identity, "us-east-1",
                    Timestamp);
               Outcome : constant Low_Level.Abort_Multipart_Outcome :=
                 Low_Level.Execute_Abort_Multipart_Upload
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Aborted then
                  raise Program_Error with
                    "AbortMultipartUpload rejected:" &
                    Outcome.Status'Image & " " &
                    US.To_String (Outcome.Error.Code) & " " &
                    US.To_String (Outcome.Error.Message);
               end if;
            end;
         end loop;
         if not Listing.Listing.Uploads.Is_Empty then
            raise Program_Error with
              "multipart-upload cleanup left active uploads";
         end if;
      end Cleanup;
   begin
      HTTP_Client.Configure (HTTP, Origin);
      if Mode = "setup" then
         Setup;
      elsif Mode = "list" then
         declare
            Value : constant Low_Level.List_Multipart_Uploads_Result :=
              Listing;
         begin
            Verify (Value);
            Ada.Text_IO.Put_Line
              ("{""operation"":""ListMultipartUploads""," &
               """entries"":" & Count'Image &
               ",""truncated"":false}");
         end;
      elsif Mode = "cleanup" then
         Cleanup;
      else
         raise Program_Error with "mode must be setup, list, or cleanup";
      end if;
      HTTP_Client.Shutdown (HTTP);
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end;
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("multipart listing benchmark failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_Multipart_Listing_Benchmark;
