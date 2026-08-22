with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Typed CreateBucket REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Buckets is

   Invalid_Bucket_Configuration : exception;
   Malformed_Bucket_Configuration : exception;
   Malformed_Bucket_Location : exception;

   subtype Max_Buckets_Value is Positive range 1 .. 10_000;
   Maximum_Bucket_Region_Length : constant := 63;

   type List_Buckets_Request is record
      Max_Buckets            : Max_Buckets_Value := Max_Buckets_Value'Last;
      Has_Max_Buckets        : Boolean := False;
      Continuation_Token     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix                 : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Malformed_List_Buckets_Request : exception;

   --  Parse raw query bytes after '?'. Empty is valid; percent escapes are
   --  strict, '+' stays literal, duplicates/unknowns fail, and x-id is
   --  accepted only as ListBuckets.
   function Parse_List_Buckets_Query
     (Query : String) return List_Buckets_Request;

   type Continuation_Result is record
      Valid : Boolean := False;
      After : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Encode_Continuation
     (Prefix, Bucket_Region, After : String) return String;

   function Decode_Continuation
     (Token, Prefix, Bucket_Region : String) return Continuation_Result;

   type Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Tag);

   subtype Tag_List is Tag_Vectors.Vector;

   --  Every member of the pinned CreateBucketConfiguration shape. Empty
   --  paired fields mean that their containing XML structure is absent.
   type Create_Bucket_Configuration is record
      Location_Constraint : Ada.Strings.Unbounded.Unbounded_String;
      Location_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Location_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Data_Redundancy     : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Type         : Ada.Strings.Unbounded.Unbounded_String;
      Tags                : Tag_List;
   end record;

   function Is_Empty (Value : Create_Bucket_Configuration) return Boolean;

   --  Returns an empty string when the configuration is absent; otherwise
   --  emits the namespaced CreateBucketConfiguration document.
   function Serialize_Create_Configuration
     (Value : Create_Bucket_Configuration) return String;

   --  Parse the exact CreateBucketConfiguration shape. Empty input means the
   --  configuration member is absent. Unknown, duplicate, misplaced, or
   --  incomplete elements fail, as do documents outside the supplied limits.
   function Parse_Create_Configuration
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Create_Bucket_Configuration;

   --  Legacy GetBucketLocation represents us-east-1 as an empty root value;
   --  EU remains the legacy spelling for eu-west-1. Other values follow the
   --  pinned AWS BucketLocationConstraint enumeration.
   function Valid_Location_Constraint (Value : String) return Boolean;

   --  The parser additionally accepts literal us-east-1 from compatible
   --  servers and the exact single-field CreateBucketConfiguration wrapper
   --  emitted by SeaweedFS 4.43. Serialization retains AWS's null scalar.
   function Parse_Location_Constraint
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits) return String;

   function Serialize_Location_Constraint (Region : String) return String;

   --  Every member of the pinned ListBuckets Bucket structure. Empty values
   --  preserve optional-member absence exactly as received.
   type Bucket_Entry is record
      Name          : Ada.Strings.Unbounded.Unbounded_String;
      Creation_Date : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_ARN    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Bucket_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Bucket_Entry);

   subtype Bucket_List is Bucket_Entry_Vectors.Vector;

   type Bucket_Owner is record
      Display_Name : Ada.Strings.Unbounded.Unbounded_String;
      ID           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Every member of the pinned ListBuckets output shape. Has_Owner
   --  distinguishes an absent Owner structure from an empty present one.
   type List_Buckets_Result is record
      Buckets            : Bucket_List;
      Has_Owner          : Boolean := False;
      Owner              : Bucket_Owner;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Malformed_Bucket_Listing : exception;

   function Parse_List_Buckets
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Buckets_Result;

   function Serialize_List_Buckets
     (Value : List_Buckets_Result) return String;

end Flyology.Object_Storage.S3.Buckets;
