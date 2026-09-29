--  S3-DOMAIN-B-6: the object XML tagging path collapses every tag-validity
--  failure into Malformed_Tagging, so PutObjectTagging answers
--  400 MalformedXML ("did not validate against the object tagging schema")
--  for a well-formed document whose tags break the AWS repertoire, repeat a
--  key, or exceed ten entries.  The same failures reported through
--  x-amz-tagging on PutObject and through PutBucketTagging answer
--  400 InvalidTag.  Every document below is namespaced, so S3-DOMAIN-B-1/-2
--  are not involved.  This program asserts the code the crate itself uses on
--  the other two paths.
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_B_6 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   Bucket : constant String := "/domain-b6";
   Target : constant String := Bucket & "/k";

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   function Tag_Element (Key, Value : String) return String is
     ("<Tag><Key>" & Key & "</Key><Value>" & Value & "</Value></Tag>");

   function Document (Tags : String) return String is
     ("<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<TagSet>" & Tags & "</TagSet></Tagging>");

   function Eleven_Tags return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for Index in 1 .. 11 loop
         Ada.Strings.Unbounded.Append
           (Result, Tag_Element ("k" & Image (Index), "v"));
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Eleven_Tags;

   function Tagging_Put (Target_Path, Doc : String) return String is
     (Signed_Request
        ("PUT", Target_Path, Doc,
         "Content-MD5: " & MD5_Base64 (Doc) & CRLF &
         "Content-Type: application/xml" & CRLF,
         [SigV4.Pair ("tagging", "")]));

   function Error_Code (Response : String) return String is
      Text  : constant String := Body_Of (Response);
      Open  : constant String := "<Code>";
      Close : constant String := "</Code>";
      From  : Natural := 0;
   begin
      if Text'Length < Open'Length then
         return "";
      end if;
      for Index in Text'First .. Text'Last - Open'Length + 1 loop
         if Text (Index .. Index + Open'Length - 1) = Open then
            From := Index + Open'Length;
            exit;
         end if;
      end loop;
      if From = 0 then
         return "";
      end if;
      for Index in From .. Text'Last - Close'Length + 1 loop
         if Text (Index .. Index + Close'Length - 1) = Close then
            return Text (From .. Index - 1);
         end if;
      end loop;
      return "";
   end Error_Code;

   procedure Object_Case (Label, Doc : String) is
      Response : constant String := Run (Tagging_Put (Target, Doc));
      Code     : constant String := Error_Code (Response);
   begin
      Note ("PutObjectTagging  " & Label);
      Note ("    status=" & Image (Status_Code (Response)) &
            " code=" & Code);
      Check (Code = "InvalidTag",
             "PutObjectTagging reports InvalidTag for " & Label);
   end Object_Case;

   procedure Control (Label, Response : String) is
      Code : constant String := Error_Code (Response);
   begin
      Note ("control " & Label);
      Note ("    status=" & Image (Status_Code (Response)) &
            " code=" & Code);
      Check (Code = "InvalidTag",
             "control: " & Label & " already reports InvalidTag");
   end Control;

begin
   Note ("=== fixtures ===");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket))) = 200,
          "CreateBucket " & Bucket & " is 200");
   Check (Status_Code (Run (Signed_Request ("PUT", Target, "x"))) = 200,
          "PutObject k is 200");

   Note ("");
   Note ("=== the same tag failures on the object XML path ===");
   Object_Case ("outside the AWS repertoire (key a#b)",
                Document (Tag_Element ("a#b", "v")));
   Object_Case ("duplicate key                       ",
                Document (Tag_Element ("dup", "1") &
                          Tag_Element ("dup", "2")));
   Object_Case ("eleven tags                         ",
                Document (Eleven_Tags));

   Note ("");
   Note ("=== controls: the other two paths on the same server ===");
   Control ("PutObject x-amz-tagging with key a#b",
            Run (Signed_Request
                   ("PUT", Bucket & "/hdr", "x",
                    "x-amz-tagging: a%23b=v" & CRLF)));
   Control ("PutBucketTagging with key a#b       ",
            Run (Tagging_Put (Bucket, Document (Tag_Element ("a#b", "v")))));

   Finish;
end Repro_S3_Domain_B_6;
