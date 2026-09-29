--  S3-DOMAIN-A-3: the Lifecycle and Notifications serializers validate text
--  against the byte range 16#20# .. 16#7E#
--  (src/flyology-object_storage-s3-lifecycle.adb:789-790,
--   src/flyology-object_storage-s3-notifications.adb:503-504), so they
--  reject U+007F (DEL), while
--    * XML 1.0 includes #x7F in Char,
--    * the shared escape boundary S3.XML.Escape_Text rejects only bytes
--      below 32 other than TAB/LF/CR
--      (src/flyology-object_storage-s3-xml.adb:221-226),
--    * the Replication serializer uses 16#20# .. 16#7F#
--      (src/flyology-object_storage-s3-replication.adb:828-829), and
--    * their own parsers accept it.
--
--  The lifecycle comment at :771-773 justifies the range as keeping the
--  serializer "from emitting bytes the matching parser must reject", which
--  this program checks directly: the same documents parse.
--
--  Correct behaviour asserted here: a document that Parse accepts can be
--  handed straight back to Serialize.  Round-tripping a server-supplied
--  configuration is the reachable path -- read a rule, change one member,
--  write it back.

with Ada.Exceptions;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.Notifications;
with Flyology.Object_Storage.S3.Replication;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_A_3 is

   package Lifecycle renames Flyology.Object_Storage.S3.Lifecycle;
   package Notifications renames Flyology.Object_Storage.S3.Notifications;
   package Replication renames Flyology.Object_Storage.S3.Replication;
   package XML renames Flyology.Object_Storage.S3.XML;

   DEL : constant String := (1 => Character'Val (16#7F#));

   function Lifecycle_Document (Suffix : String) return String is
     ("<LifecycleConfiguration><Rule><ID>rule" & Suffix & "</ID>" &
      "<Status>Enabled</Status><Expiration><Days>1</Days></Expiration>" &
      "</Rule></LifecycleConfiguration>");

   function Notification_Document (Suffix : String) return String is
     ("<NotificationConfiguration><TopicConfiguration>" &
      "<Id>topic" & Suffix & "</Id>" &
      "<Topic>arn:aws:sns:us-east-1:123456789012:t</Topic>" &
      "<Event>s3:ObjectCreated:*</Event>" &
      "</TopicConfiguration></NotificationConfiguration>");

   function Replication_Document (Suffix : String) return String is
     ("<ReplicationConfiguration>" &
      "<Role>arn:aws:iam::123456789012:role/r</Role>" &
      "<Rule><ID>rule" & Suffix & "</ID><Status>Enabled</Status>" &
      "<Destination><Bucket>arn:aws:s3:::dest</Bucket></Destination>" &
      "</Rule></ReplicationConfiguration>");

   procedure Round_Trip_Lifecycle (Label, Document : String) is
      Parsed_OK : Boolean := False;
   begin
      declare
         Value : constant Lifecycle.Lifecycle_Configuration :=
           Lifecycle.Parse (Document, XML.Default_Limits);
      begin
         Parsed_OK := True;
         Note ("lifecycle " & Label & ": Parse accepted (" &
               Image (Document'Length) & " bytes)");
         declare
            Written : constant String :=
              Lifecycle.Serialize (Value, XML.Default_Limits);
         begin
            Note ("lifecycle " & Label & ": Serialize produced " &
                  Image (Written'Length) & " bytes");
            Check (Written'Length > 0,
                   "lifecycle " & Label & ": Serialize round-trips Parse");
         end;
      end;
   exception
      when E : Lifecycle.Malformed_Lifecycle =>
         Note ("lifecycle " & Label & ": " &
               (if Parsed_OK then "Serialize" else "Parse") & " REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         Check (False,
                "lifecycle " & Label & ": Serialize round-trips Parse");
   end Round_Trip_Lifecycle;

   procedure Round_Trip_Notifications (Label, Document : String) is
      Parsed_OK : Boolean := False;
   begin
      declare
         Value : constant Notifications.Notification_Configuration :=
           Notifications.Parse (Document, XML.Default_Limits);
      begin
         Parsed_OK := True;
         Note ("notifications " & Label & ": Parse accepted (" &
               Image (Document'Length) & " bytes)");
         declare
            Written : constant String :=
              Notifications.Serialize (Value, XML.Default_Limits);
         begin
            Note ("notifications " & Label & ": Serialize produced " &
                  Image (Written'Length) & " bytes");
            Check (Written'Length > 0,
                   "notifications " & Label &
                   ": Serialize round-trips Parse");
         end;
      end;
   exception
      when E : Notifications.Malformed_Notification =>
         Note ("notifications " & Label & ": " &
               (if Parsed_OK then "Serialize" else "Parse") & " REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         Check (False,
                "notifications " & Label & ": Serialize round-trips Parse");
   end Round_Trip_Notifications;

   procedure Round_Trip_Replication (Label, Document : String) is
      Parsed_OK : Boolean := False;
   begin
      declare
         Value : constant Replication.Replication_Configuration :=
           Replication.Parse (Document, XML.Default_Limits);
      begin
         Parsed_OK := True;
         Note ("replication " & Label & ": Parse accepted (" &
               Image (Document'Length) & " bytes)");
         declare
            Written : constant String :=
              Replication.Serialize (Value, XML.Default_Limits);
         begin
            Note ("replication " & Label & ": Serialize produced " &
                  Image (Written'Length) & " bytes");
            Check (Written'Length > 0,
                   "replication " & Label & ": Serialize round-trips Parse");
         end;
      end;
   exception
      when E : Replication.Malformed_Replication =>
         Note ("replication " & Label & ": " &
               (if Parsed_OK then "Serialize" else "Parse") & " REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         Check (False,
                "replication " & Label & ": Serialize round-trips Parse");
   end Round_Trip_Replication;

begin
   Note ("DEL byte value " & Image (Character'Pos (DEL (DEL'First))));

   --  Controls: the same three documents without DEL round-trip today.
   Round_Trip_Lifecycle ("plain ASCII ID", Lifecycle_Document ("-a"));
   Round_Trip_Notifications ("plain ASCII Id", Notification_Document ("-a"));
   Round_Trip_Replication ("plain ASCII ID", Replication_Document ("-a"));

   --  Control: the Replication serializer, whose byte range is 20..7F,
   --  accepts the very same DEL that the other two reject.
   Round_Trip_Replication ("ID with U+007F", Replication_Document (DEL));

   --  The finding.
   Round_Trip_Lifecycle ("ID with U+007F", Lifecycle_Document (DEL));
   Round_Trip_Notifications ("Id with U+007F", Notification_Document (DEL));

   --  U+0080 (the first C1 control, two UTF-8 bytes) is also XML 1.0 text
   --  and shows the boundary is exactly the one-byte range, not a general
   --  control-character rule.
   Round_Trip_Lifecycle
     ("ID with U+0080",
      Lifecycle_Document (Character'Val (16#C2#) & Character'Val (16#80#)));

   Finish;
end Repro_S3_Domain_A_3;
