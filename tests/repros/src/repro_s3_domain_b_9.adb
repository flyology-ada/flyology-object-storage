--  S3-DOMAIN-B-9 (promoted from the discovery's "empty TagSet" observation,
--  now with a real server behind it): the GetBucketTagging response decoder
--  runs the publication predicate Tags.Valid_Bucket_Tag_Set, which requires a
--  NONEMPTY tag set, over a decoded response.  The pinned model puts no
--  minimum on Tagging.TagSet, and MinIO RELEASE.2025-09-07T16-13-09Z really
--  answers 200 with <Tagging><TagSet></TagSet></Tagging> for a bucket whose
--  tag set was stored empty (captured against the image pinned in
--  tests/scripts/test-minio.sh; MinIO accepts PutBucketTagging with an empty
--  TagSet and then serves it back).  Parse_Bucket_Response raises Invalid_Tag
--  and the client reports Invalid_Response for a well-formed 200 response.
with Ada.Containers;
with Ada.Exceptions;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.Tags;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_B_9 is

   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Tagging renames Flyology.Object_Storage.S3.Tagging;
   package Tags renames Flyology.Object_Storage.Tags;

   use type Ada.Containers.Count_Type;

   --  Exactly the bytes MinIO returns (no XML declaration, no namespace).
   Empty_Body : constant String :=
     "<Tagging><TagSet></TagSet></Tagging>";
   One_Tag_Body : constant String :=
     "<Tagging><TagSet><Tag><Key>k</Key><Value>v</Value></Tag>" &
     "</TagSet></Tagging>";

   No_Headers : constant Low_Level.Get_Bucket_Tagging_Result :=
     (others => <>);

   procedure Decode (Label, Document : String; Must_Work : Boolean) is
   begin
      Note (Label & " body=" & Document);
      begin
         declare
            Decoded : constant Tags.Tag_Set :=
              Tagging.Parse_Bucket_Response (Document);
         begin
            Note ("    S3.Tagging.Parse_Bucket_Response: accepted, tags=" &
                  Image (Integer (Decoded.Length)));
         end;
      exception
         when Error : others =>
            Note ("    S3.Tagging.Parse_Bucket_Response: " &
                  Ada.Exceptions.Exception_Name (Error) & ": " &
                  Ada.Exceptions.Exception_Message (Error));
      end;
      begin
         declare
            Outcome : constant Low_Level.Get_Bucket_Tagging_Outcome :=
              Low_Level.Decode_Get_Bucket_Tagging_Response
                (Status  => 200,
                 Payload => Document,
                 Headers => No_Headers);
         begin
            Note ("    Client.Low_Level: accepted, kind=" &
                  Low_Level.Get_Bucket_Tagging_Outcome_Kind'Image
                    (Outcome.Kind));
            if Must_Work then
               Check (True, Label);
            end if;
         end;
      exception
         when Error : others =>
            Note ("    Client.Low_Level: " &
                  Ada.Exceptions.Exception_Name (Error) & ": " &
                  Ada.Exceptions.Exception_Message (Error));
            if Must_Work then
               Check (False, Label);
            end if;
      end;
   end Decode;

begin
   Note ("=== control: a one-tag GetBucketTagging response ===");
   Decode ("control: one tag                    ", One_Tag_Body, False);
   Note ("");
   Note ("=== MinIO's empty-TagSet GetBucketTagging response ===");
   Decode ("client decodes an empty bucket TagSet", Empty_Body, True);
   Finish;
end Repro_S3_Domain_B_9;
