--  S3-DOMAIN-A-4: four response decoders pin the botocore OUTPUT SHAPE name
--  as the XML root element, but the AWS S3 API Reference "Response Syntax"
--  for those operations shows a different root:
--
--    operation                            crate root (shape name)
--                                         AWS documented wire root
--    ListBucketInventoryConfigurations    ListBucketInventoryConfigurationsOutput
--                                         <ListInventoryConfigurationsResult>
--    ListBucketMetricsConfigurations      ListBucketMetricsConfigurationsOutput
--                                         <ListMetricsConfigurationsResult>
--    ListBucketAnalyticsConfigurations    ListBucketAnalyticsConfigurationsOutput
--                                         <ListBucketAnalyticsConfigurationResult>
--    ListDirectoryBuckets                 ListDirectoryBucketsOutput
--                                         <ListAllMyDirectoryBucketsResult>
--
--  (the four AWS names were read from the Response Syntax and the
--  "Root level tag" Response Elements entry of
--  docs.aws.amazon.com/AmazonS3/latest/API/API_<operation>.html on
--  2026-09-06; the pinned model carries neither locationName nor
--  resultWrapper for any of these output shapes, so the reference is the
--  only authority.)
--
--  Enforcement:
--    src/flyology-object_storage-s3-paginated_rest_xml_reads.adb:133-136
--      (Local_Name /= Root_Name  =>  Malformed_Page) for the three
--      configuration listings, and :283-286 on close;
--    src/flyology-object_storage-s3-strict_xml_codecs.adb:313-315
--      (Local_Name /= Element_Name (Root_Element)  =>  Malformed_Document)
--      for the generated ListDirectoryBuckets decoder, whose root comes
--      from tools/s3_codegen.py:815-816
--      (root_name = shapes[root_shape].get("locationName", root_shape)).
--
--  The same crate already uses the wire root, not the shape name, wherever
--  the two differ for the older operations: ListAllMyBucketsResult
--  (buckets.adb:914), ListBucketResult (listings.adb:690),
--  ListVersionsResult (versions.adb:528), and the two metadata reads.
--  ListBucketIntelligentTieringConfigurations is NOT affected: AWS really
--  does document ListBucketIntelligentTieringConfigurationsOutput as the
--  root there, and this program checks that too, as a control.
--
--  Correct behaviour asserted here: each decoder accepts the document AWS
--  documents itself as sending.

with Ada.Exceptions;
with Flyology.Object_Storage.S3.Analytics;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_XML;
with Flyology.Object_Storage.S3.Intelligent_Tiering;
with Flyology.Object_Storage.S3.Inventory;
with Flyology.Object_Storage.S3.Metrics;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_A_4 is

   package Analytics renames Flyology.Object_Storage.S3.Analytics;
   package Buckets renames Flyology.Object_Storage.S3.Buckets;
   package Directory_Buckets renames
     Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_XML;
   package Intelligent_Tiering renames
     Flyology.Object_Storage.S3.Intelligent_Tiering;
   package Inventory renames Flyology.Object_Storage.S3.Inventory;
   package Metrics renames Flyology.Object_Storage.S3.Metrics;
   package XML renames Flyology.Object_Storage.S3.XML;

   NS : constant String := "http://s3.amazonaws.com/doc/2006-03-01/";

   function Empty_List (Root : String) return String is
     ("<" & Root & " xmlns=""" & NS & """>" &
      "<IsTruncated>false</IsTruncated>" &
      "</" & Root & ">");

   procedure Try_Inventory (Root : String; Assert_Accepted : Boolean) is
   begin
      declare
         Page : constant Inventory.Inventory_Configuration_Page :=
           Inventory.Parse_List (Empty_List (Root), XML.Default_Limits);
      begin
         Note ("Inventory.Parse_List <" & Root & ">: accepted, " &
               "has_is_truncated=" & Boolean'Image (Page.Has_Is_Truncated));
         if Assert_Accepted then
            Check (Page.Has_Is_Truncated,
                   "Inventory.Parse_List accepts <" & Root & ">");
         end if;
      end;
   exception
      when E : Inventory.Malformed_Inventory =>
         Note ("Inventory.Parse_List <" & Root & ">: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False, "Inventory.Parse_List accepts <" & Root & ">");
         end if;
   end Try_Inventory;

   procedure Try_Metrics (Root : String; Assert_Accepted : Boolean) is
   begin
      declare
         Page : constant Metrics.Metrics_Configuration_Page :=
           Metrics.Parse_List (Empty_List (Root), XML.Default_Limits);
      begin
         Note ("Metrics.Parse_List <" & Root & ">: accepted, " &
               "has_is_truncated=" & Boolean'Image (Page.Has_Is_Truncated));
         if Assert_Accepted then
            Check (Page.Has_Is_Truncated,
                   "Metrics.Parse_List accepts <" & Root & ">");
         end if;
      end;
   exception
      when E : Metrics.Malformed_Metrics =>
         Note ("Metrics.Parse_List <" & Root & ">: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False, "Metrics.Parse_List accepts <" & Root & ">");
         end if;
   end Try_Metrics;

   procedure Try_Analytics (Root : String; Assert_Accepted : Boolean) is
   begin
      declare
         Page : constant Analytics.Analytics_Configuration_Page :=
           Analytics.Parse_List (Empty_List (Root), XML.Default_Limits);
      begin
         Note ("Analytics.Parse_List <" & Root & ">: accepted, " &
               "has_is_truncated=" & Boolean'Image (Page.Has_Is_Truncated));
         if Assert_Accepted then
            Check (Page.Has_Is_Truncated,
                   "Analytics.Parse_List accepts <" & Root & ">");
         end if;
      end;
   exception
      when E : Analytics.Malformed_Analytics =>
         Note ("Analytics.Parse_List <" & Root & ">: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False, "Analytics.Parse_List accepts <" & Root & ">");
         end if;
   end Try_Analytics;

   procedure Try_Tiering (Root : String; Assert_Accepted : Boolean) is
   begin
      declare
         Page : constant
           Intelligent_Tiering.Intelligent_Tiering_Configuration_Page :=
             Intelligent_Tiering.Parse_List
               (Empty_List (Root), XML.Default_Limits);
      begin
         Note ("Intelligent_Tiering.Parse_List <" & Root & ">: accepted, " &
               "has_is_truncated=" & Boolean'Image (Page.Has_Is_Truncated));
         if Assert_Accepted then
            Check (Page.Has_Is_Truncated,
                   "Intelligent_Tiering.Parse_List accepts <" & Root & ">");
         end if;
      end;
   exception
      when E : Intelligent_Tiering.Malformed_Intelligent_Tiering =>
         Note ("Intelligent_Tiering.Parse_List <" & Root & ">: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False,
                   "Intelligent_Tiering.Parse_List accepts <" & Root & ">");
         end if;
   end Try_Tiering;

   procedure Try_Directory_Buckets
     (Root : String; Assert_Accepted : Boolean)
   is
      Document : constant String :=
        "<" & Root & " xmlns=""" & NS & """><Buckets><Bucket>" &
        "<Name>b--usw2-az1--x-s3</Name>" &
        "<CreationDate>2026-01-01T00:00:00.000Z</CreationDate>" &
        "<BucketRegion>us-west-2</BucketRegion>" &
        "<BucketArn>arn:aws:s3express:us-west-2:1:bucket/b</BucketArn>" &
        "</Bucket></Buckets></" & Root & ">";
   begin
      declare
         Value : constant Buckets.List_Buckets_Result :=
           Directory_Buckets.Parse (Document, XML.Default_Limits, 1_000);
      begin
         Note ("ListDirectoryBuckets <" & Root & ">: accepted, buckets=" &
               Image (Natural (Value.Buckets.Length)));
         if Assert_Accepted then
            Check (Natural (Value.Buckets.Length) = 1,
                   "ListDirectoryBuckets decoder accepts <" & Root & ">");
         end if;
      end;
   exception
      when E : Directory_Buckets.Malformed_Document =>
         Note ("ListDirectoryBuckets <" & Root & ">: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False,
                   "ListDirectoryBuckets decoder accepts <" & Root & ">");
         end if;
   end Try_Directory_Buckets;

begin
   Note ("--- controls: the shape-name roots the crate pins today ---");
   Try_Inventory ("ListBucketInventoryConfigurationsOutput", False);
   Try_Metrics ("ListBucketMetricsConfigurationsOutput", False);
   Try_Analytics ("ListBucketAnalyticsConfigurationsOutput", False);
   Try_Directory_Buckets ("ListDirectoryBucketsOutput", False);

   Note ("--- control: Intelligent-Tiering, where AWS really does " &
         "document the shape name as the root ---");
   Try_Tiering ("ListBucketIntelligentTieringConfigurationsOutput", True);

   Note ("--- the finding: the roots the AWS API Reference documents ---");
   Try_Inventory ("ListInventoryConfigurationsResult", True);
   Try_Metrics ("ListMetricsConfigurationsResult", True);
   Try_Analytics ("ListBucketAnalyticsConfigurationResult", True);
   Try_Directory_Buckets ("ListAllMyDirectoryBucketsResult", True);

   Finish;
end Repro_S3_Domain_A_4;
