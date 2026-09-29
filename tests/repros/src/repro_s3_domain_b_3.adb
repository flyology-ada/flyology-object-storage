--  S3-DOMAIN-B-3: the ListObjectAnnotations query codec binds the camelCase
--  spellings annotationPrefix / maxAnnotationResults / continuationToken,
--  while the pinned model (review/baseline/service-2.json), the generated
--  descriptor and therefore the crate's own client emit annotation-prefix /
--  max-annotation-results / continuation-token.  Every prefixed, bounded or
--  paginated ListObjectAnnotations request built from the model is answered
--  400 InvalidArgument.  This program prints the model's location names,
--  then sends both spellings to the in-process application and asserts that
--  the model's spelling is accepted.
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Model;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_B_3 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Model renames Flyology.Object_Storage.S3.Model;

   use type Model.Member_Location;

   Bucket : constant String := "/domain-b3";
   Target : constant String := Bucket & "/obj";

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   function SHA256_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.SHA256,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   function Put_Annotation (Name, Payload : String) return String is
     (Signed_Request
        ("PUT", Target, Payload,
         "Content-MD5: " & MD5_Base64 (Payload) & CRLF &
         "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
         "x-amz-checksum-sha256: " & SHA256_Base64 (Payload) & CRLF,
         [SigV4.Pair ("annotation", ""),
          SigV4.Pair ("annotationName", Name),
          SigV4.Pair ("x-id", "PutObjectAnnotation")]));

   function List (Name, Value : String) return String is
     (Run
        (Signed_Request
           ("GET", Target, "", "",
            [SigV4.Pair ("annotation", ""), SigV4.Pair (Name, Value)])));

   procedure Probe (Label, Name, Value : String; Must_Work : Boolean) is
      Response : constant String := List (Name, Value);
   begin
      Note (Label & " GET " & Target & "?annotation&" & Name & "=" & Value);
      Note ("    status=" & Image (Status_Code (Response)) &
            " body=" & Escape (Body_Of (Response)));
      if Must_Work then
         Check (Status_Code (Response) = 200,
                "the model's spelling """ & Name & """ is accepted");
      end if;
   end Probe;

begin
   Note ("=== the pinned model's ListObjectAnnotations query names ===");
   declare
      Shape : constant Model.Shape_Reference :=
        Model.Input_Shape (Model.List_Object_Annotations_Operation);
   begin
      Check (Shape /= Model.No_Shape,
             "control: the model has a ListObjectAnnotations input shape");
      for Member in 1 .. Model.Member_Count (Shape) loop
         if Model.Location (Shape, Member) = Model.Query_Location then
            Note ("    " & Model.Member_Name (Shape, Member) & " -> """ &
                  Model.Member_Location_Name (Shape, Member) &
                  """ (what Client.Low_Level puts on the wire)");
         end if;
      end loop;
   end;

   Note ("");
   Note ("=== fixtures ===");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket))) = 200,
          "CreateBucket " & Bucket & " is 200");
   Check (Status_Code (Run (Signed_Request ("PUT", Target, "payload"))) = 200,
          "PutObject obj is 200");
   Check (Status_Code (Run (Put_Annotation ("alpha", "alpha payload"))) = 200,
          "PutObjectAnnotation alpha is 200");
   Check (Status_Code (Run (Put_Annotation ("beta", "beta payload"))) = 200,
          "PutObjectAnnotation beta is 200");

   Note ("");
   Note ("=== control: the codec's camelCase spellings (accepted today) ===");
   Probe ("control ", "maxAnnotationResults", "1", False);
   Probe ("control ", "annotationPrefix", "al", False);

   Note ("");
   Note ("=== the model's spellings, as the crate's own client sends ===");
   Probe ("model   ", "max-annotation-results", "1", True);
   Probe ("model   ", "annotation-prefix", "al", True);

   Note ("");
   Note ("=== pagination with the model's continuation-token ===");
   declare
      First : constant String := List ("maxAnnotationResults", "1");
      Start : constant Natural :=
        (if Contains (Body_Of (First), "<NextContinuationToken>")
         then 1 else 0);
      Token : String (1 .. 512);
      Last  : Natural := 0;
   begin
      Note ("first page (camelCase) status=" & Image (Status_Code (First)));
      if Start = 1 then
         declare
            Text  : constant String := Body_Of (First);
            Open  : constant String := "<NextContinuationToken>";
            Close : constant String := "</NextContinuationToken>";
            From  : Natural := 0;
            To    : Natural := 0;
         begin
            for Index in Text'First .. Text'Last - Open'Length + 1 loop
               if Text (Index .. Index + Open'Length - 1) = Open then
                  From := Index + Open'Length;
                  exit;
               end if;
            end loop;
            for Index in From .. Text'Last - Close'Length + 1 loop
               if Text (Index .. Index + Close'Length - 1) = Close then
                  To := Index - 1;
                  exit;
               end if;
            end loop;
            if From > 0 and then To >= From and then To - From < Token'Length
            then
               Last := To - From + 1;
               Token (1 .. Last) := Text (From .. To);
            end if;
         end;
      end if;
      Check (Last > 0, "control: the first page returns a continuation token");
      if Last > 0 then
         Note ("token=" & Token (1 .. Last));
         Probe ("model   ", "continuation-token", Token (1 .. Last), True);
      end if;
   end;

   Finish;
end Repro_S3_Domain_B_3;
