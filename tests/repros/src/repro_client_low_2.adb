--  CLIENT-LOW-2: Decode_Get_Object_Attributes_Complete_Response
--  (src/flyology-object_storage-client-low_level.adb:5383-5397) raises
--  Invalid_Response when a 200 OK omits x-amz-version-id and the prepared
--  request carried an explicit versionId selector.  Version_ID comes from
--  Singleton_Header ("x-amz-version-id") (:5371-5372), which returns "" when
--  the header is absent (:5349-5350), so "" /= "null" trips the check.
--
--  Unlike GetObject/HeadObject, the in-repo server has no "null" fallback for
--  this route: src/flyology-object_storage-server-s3_applications.adb:16348
--  emits the header only when the stored version is non-empty.  So the
--  repository's own memory-backed S3 application reproduces this without any
--  third-party server, and this program drives that application over the
--  loopback listener.
--
--  The pinned botocore model marks GetObjectAttributesOutput.VersionId
--  optional (review/baseline/service-2.json: required = []).
--
--  Asserts the CORRECT behaviour: a 200 with the attributes document and no
--  x-amz-version-id is a modeled success.  The control leg issues the same
--  request without a version selector against the same object and must pass.
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Repro_S3_Server;
with Repro_Support; use Repro_Support;

procedure Repro_Client_Low_2 is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Server renames Repro_S3_Server;

   use type Low_Level.Get_Object_Attributes_Outcome_Kind;

   Bucket : constant String := "never-versioned";
   Key    : constant String := "native-object";
   Body_Text : constant String := "hello attributes";

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     (Server.Access_Key, Server.Secret_Key);

   HTTP : aliased HTTP_Client.Client (Capacity => 2);
   Port : Natural;

   procedure Run_Attributes (Label : String; Selector : String) is
      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin ("http://127.0.0.1:" & Image (Port));
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Selector);
      Parameters.Attributes.Entity_Tag := True;
      Parameters.Attributes.Object_Size := True;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Get_Object_Attributes
             (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
              Identity, Server.Region, Server.Timestamp);
         Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
           Low_Level.Execute_Get_Object_Attributes
             (HTTP, Prepared, Timeout => 10.0);
      begin
         Note (Label & ": Execute_Get_Object_Attributes Kind = " &
                 Low_Level.Get_Object_Attributes_Outcome_Kind'Image
                   (Outcome.Kind) &
                 ", status " & Image (Integer (Outcome.Status)));
         if Outcome.Kind = Low_Level.Object_Attributes_Found then
            Note (Label & ": ETag = " &
                    US.To_String (Outcome.Result.Attributes.Entity_Tag) &
                    ", ObjectSize set = " &
                    Boolean'Image (Outcome.Result.Attributes.Object_Size.Is_Set)
                    & ", Version_ID = """ &
                    US.To_String (Outcome.Result.Version_ID) & """");
         end if;
         Check (Outcome.Kind = Low_Level.Object_Attributes_Found,
                Label & ": a 200 GetObjectAttributes without " &
                  "x-amz-version-id is a modeled success");
         if Outcome.Kind = Low_Level.Object_Attributes_Found then
            Check (Outcome.Result.Attributes.Has_Entity_Tag,
                   Label & ": the requested ETag attribute reaches the " &
                     "caller");
            Check (Outcome.Result.Attributes.Object_Size.Is_Set
                     and then Outcome.Result.Attributes.Object_Size.Value =
                       Body_Text'Length,
                   Label & ": ObjectSize is" & Body_Text'Length'Image);
         end if;
      end;
   exception
      when Occurrence : Low_Level.Invalid_Response =>
         Note (Label & ": raised " &
                 Ada.Exceptions.Exception_Name (Occurrence) & " : " &
                 Ada.Exceptions.Exception_Message (Occurrence));
         Check (False,
                Label & ": a 200 GetObjectAttributes without " &
                  "x-amz-version-id is a modeled success");
   end Run_Attributes;

begin
   --  Publish one object into a bucket that never had versioning enabled.
   declare
      Created : constant String :=
        Server.Run (Server.Signed_Request ("PUT", "/" & Bucket));
   begin
      Note ("in-process CreateBucket status " & Image (Status_Code (Created)));
      Check (Status_Code (Created) = 200, "setup: CreateBucket is 200");
   end;
   declare
      Put : constant String := Server.Run
        (Server.Signed_Request ("PUT", "/" & Bucket & "/" & Key, Body_Text));
   begin
      Note ("in-process PutObject status " & Image (Status_Code (Put)) &
              ", x-amz-version-id = """ &
              Header_Value (Put, "x-amz-version-id") & """");
      Check (Status_Code (Put) = 200, "setup: PutObject is 200");
      Check (Header_Value (Put, "x-amz-version-id") = "",
             "setup: the never-versioned publication returns no version id");
   end;

   --  Show the raw shape the client will be handed: the server answers the
   --  versioned attributes request with 200 and no x-amz-version-id.
   declare
      Raw : constant String := Server.Run
        (Server.Signed_Request
           ("GET", "/" & Bucket & "/" & Key,
            Extra_Headers => "x-amz-object-attributes: ETag,ObjectSize" & CRLF,
            Query => [Server.SigV4.Pair ("attributes", ""),
                      Server.SigV4.Pair ("versionId", "null")]));
   begin
      Note ("raw GET ?attributes&versionId=null -> status " &
              Image (Status_Code (Raw)) &
              ", x-amz-version-id count " &
              Image (Header_Count (Raw, "x-amz-version-id")));
      Check (Status_Code (Raw) = 200,
             "setup: the in-repo server answers the versioned attributes " &
               "request with 200");
      Check (Header_Count (Raw, "x-amz-version-id") = 0,
             "setup: that 200 carries no x-amz-version-id");
   end;

   Server.Start_Loopback (Port);
   Note ("loopback S3 application on 127.0.0.1:" & Image (Port));
   Note ("model: GetObjectAttributesOutput required = [], VersionId is an " &
           "optional x-amz-version-id header (review/baseline/service-2.json)");
   declare
      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin ("http://127.0.0.1:" & Image (Port));
   begin
      HTTP_Client.Configure (HTTP, Origin);
   end;

   Note ("--- explicit versionId=null against a never-versioned bucket ---");
   Run_Attributes ("versioned", "null");
   Note ("--- control: no version selector, same object ---");
   Run_Attributes ("control", "");

   Server.Stop_Loopback;
   Finish;
end Repro_Client_Low_2;
