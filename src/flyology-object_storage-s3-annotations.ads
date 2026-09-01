with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 object annotation listings.
package Flyology.Object_Storage.S3.Annotations is

   --  Raised when a response violates the pinned annotation-list model.
   Malformed_Annotations : exception;

   --  Raised when an object-annotation query violates its exact operation
   --  shape or contains malformed percent encoding.
   Malformed_Annotation_Request : exception;

   --  The pinned Botocore MaxAnnotationResults shape fixes the public wire
   --  domain at 1 through 1,000. This is provider protocol, not a local page
   --  size default or resource budget.
   subtype Annotation_Result_Limit is Positive range 1 .. 1_000;

   --  Exact object-annotation operation selected by the request method.
   --  @enum Put_Annotation Replace one named annotation
   --  @enum Get_Annotation Read one named annotation
   --  @enum List_Annotations List annotations on one object generation
   --  @enum Delete_Annotation Delete one named annotation
   type Annotation_Operation is
     (Put_Annotation, Get_Annotation, List_Annotations, Delete_Annotation);

   --  Strict decoded object-annotation request query. Presence flags retain
   --  the distinction between omitted and explicitly empty list members.
   --  @field Annotation_Name Required exact name for non-list operations
   --  @field Has_Annotation_Name Whether Annotation_Name was supplied
   --  @field Version_ID Optional exact selected object version
   --  @field Has_Version_ID Whether Version_ID was supplied
   --  @field Annotation_Prefix Optional exact list prefix
   --  @field Has_Annotation_Prefix Whether Annotation_Prefix was supplied
   --  @field Maximum Caller-selected list result limit
   --  @field Has_Maximum Whether Maximum was supplied
   --  @field Continuation_Token Optional opaque next-page cursor
   --  @field Has_Continuation_Token Whether Continuation_Token was supplied
   type Annotation_Request is record
      Annotation_Name        : Ada.Strings.Unbounded.Unbounded_String;
      Has_Annotation_Name    : Boolean;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID         : Boolean;
      Annotation_Prefix      : Ada.Strings.Unbounded.Unbounded_String;
      Has_Annotation_Prefix  : Boolean;
      Maximum                : Annotation_Result_Limit;
      Has_Maximum            : Boolean;
      Continuation_Token     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean;
   end record;

   --  Parse one exact operation-specific annotation query. The annotation
   --  subresource is required, percent escapes are strict, plus remains data,
   --  duplicate and cross-operation members are rejected, and an optional
   --  x-id must identify Operation.
   --  @param Query Raw query bytes after the question mark
   --  @param Operation Operation selected from the HTTP method and name mode
   --  @return Complete strict decoded annotation request
   --  @exception Malformed_Annotation_Request Query violates the operation
   function Parse_Query
     (Query : String; Operation : Annotation_Operation)
      return Annotation_Request;

   --  Result of validating one opaque annotation continuation token.
   --  @field Valid Whether the token matches its complete request scope
   --  @field After Exclusive decoded annotation-name cursor when valid
   type Continuation_Result is record
      Valid : Boolean;
      After : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Encode a continuation token bound to one exact listing scope.
   --  @param Bucket Exact bucket name
   --  @param Key Exact object key
   --  @param Version_ID Empty for current selection or exact selected version
   --  @param Prefix Exact annotation-name prefix
   --  @param After Exclusive final emitted annotation name
   --  @return Opaque scope-bound continuation token
   function Encode_Continuation
     (Bucket, Key, Version_ID, Prefix, After : String) return String;

   --  Validate and decode one continuation token against its listing scope.
   --  @param Token Candidate opaque continuation token
   --  @param Bucket Expected bucket name
   --  @param Key Expected object key
   --  @param Version_ID Expected empty or exact version selection
   --  @param Prefix Expected annotation-name prefix
   --  @return Validation result and decoded exclusive cursor
   function Decode_Continuation
     (Token, Bucket, Key, Version_ID, Prefix : String)
      return Continuation_Result;

   --  Presence-preserving optional string. Empty text remains distinct from
   --  absence because the pinned string shapes have no minimum length.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence-preserving arbitrary-precision signed decimal text. The
   --  pinned integer shape establishes no machine-sized bound.
   --  @field Is_Set Whether the modeled member was present
   --  @field Text Exact validated signed decimal wire text
   type Optional_Integer_Text is record
      Is_Set : Boolean;
      Text   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence-preserving bounded MaxAnnotationResults value.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded provider wire value
   type Optional_Annotation_Result_Limit is record
      Is_Set : Boolean;
      Value  : Annotation_Result_Limit;
   end record;

   --  Exact checksum domain fixed by the pinned AnnotationEntry model.
   subtype Checksum_Algorithm is Core.Checksum_Algorithm range
     Core.CRC32 .. Core.XXHASH128;

   --  Dynamically sized flattened checksum storage bounded by the caller's
   --  shared XML element and document limits.
   package Checksum_Algorithm_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Checksum_Algorithm,
      "=" => Core."=");

   --  Exact pinned annotation replication-status wire domain.
   --  @enum Replication_Complete Exact COMPLETE wire value
   --  @enum Replication_Pending Exact PENDING wire value
   --  @enum Replication_Failed Exact FAILED wire value
   --  @enum Replication_Replica Exact REPLICA wire value
   --  @enum Replication_Completed Exact COMPLETED wire value
   type Replication_Status is
     (Replication_Complete, Replication_Pending, Replication_Failed,
      Replication_Replica, Replication_Completed);

   --  Presence-preserving optional replication status.
   --  @field Is_Set Whether ReplicationStatus was present
   --  @field Value Exact decoded wire value when present
   type Optional_Replication_Status is record
      Is_Set : Boolean;
      Value  : Replication_Status;
   end record;

   --  One complete required AnnotationEntry.
   --  @field Name Required exact annotation name
   --  @field Last_Modified Required validated ISO-8601 timestamp text
   --  @field Entity_Tag Optional exact ETag text
   --  @field Checksums Flattened exact checksum algorithms in wire order
   --  @field Size Required nonnegative 64-bit byte count
   --  @field Replication Optional exact replication status
   type Annotation_Entry is record
      Name          : Ada.Strings.Unbounded.Unbounded_String;
      Last_Modified : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag    : Optional_String;
      Checksums     : Checksum_Algorithm_Vectors.Vector;
      Size          : Byte_Count;
      Replication   : Optional_Replication_Status;
   end record;

   --  Dynamically sized annotation storage bounded by caller-selected shared
   --  XML document, element, depth, and text limits.
   package Annotation_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Annotation_Entry);

   --  Complete presence-preserving ListObjectAnnotations XML payload.
   --  @field Has_Annotations Whether the optional Annotations wrapper exists
   --  @field Annotations Complete entries in wire order
   --  @field Bucket Optional exact bucket echo
   --  @field Key Optional exact object-key echo
   --  @field Annotation_Prefix Optional exact prefix echo
   --  @field Max_Annotation_Results Optional bounded page-size echo
   --  @field Annotation_Count Optional arbitrary-precision signed count
   --  @field Continuation_Token Optional exact request-token echo
   --  @field Next_Continuation_Token Optional exact next-page token
   type Annotation_Page is record
      Has_Annotations        : Boolean;
      Annotations            : Annotation_Entry_Vectors.Vector;
      Bucket                 : Optional_String;
      Key                    : Optional_String;
      Annotation_Prefix      : Optional_String;
      Max_Annotation_Results : Optional_Annotation_Result_Limit;
      Annotation_Count       : Optional_Integer_Text;
      Continuation_Token     : Optional_String;
      Next_Continuation_Token : Optional_String;
   end record;

   --  Parse one complete bounded ListObjectAnnotations response body.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving annotation page
   --  @exception Malformed_Annotations Document violates the pinned model
   function Parse_List
     (Document : String; Limits : XML.Parse_Limits) return Annotation_Page;

   --  Serialize one complete strict ListObjectAnnotations response document.
   --  @param Value Complete server-produced annotation page
   --  @return Exact REST/XML response document
   --  @exception Malformed_Annotations Value is internally inconsistent
   function Serialize_List (Value : Annotation_Page) return String;

end Flyology.Object_Storage.S3.Annotations;
