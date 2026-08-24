with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 bucket access-control policy reads.
package Flyology.Object_Storage.S3.ACL is

   --  Raised when a response violates the pinned GetBucketAcl model.
   Malformed_ACL : exception;

   --  Exact pinned grantee xsi:type wire domain.
   --  @enum Canonical_User Exact CanonicalUser wire value
   --  @enum Amazon_Customer_By_Email Exact AmazonCustomerByEmail wire value
   --  @enum Group_Grantee Exact Group wire value
   type Grantee_Type is
     (Canonical_User, Amazon_Customer_By_Email, Group_Grantee);

   --  Exact pinned permission wire domain.
   --  @enum Full_Control Exact FULL_CONTROL wire value
   --  @enum Write Exact WRITE wire value
   --  @enum Write_ACP Exact WRITE_ACP wire value
   --  @enum Read Exact READ wire value
   --  @enum Read_ACP Exact READ_ACP wire value
   type Permission is (Full_Control, Write, Write_ACP, Read, Read_ACP);

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the modeled string was present
   --  @field Value Exact decoded string
   type Optional_String is record
      Is_Set : Boolean := False;
      Value  : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Optional access-control policy owner and its optional strings.
   --  @field Is_Set Whether the Owner structure was present
   --  @field Display_Name Optional exact display name
   --  @field ID Optional exact canonical identifier
   type Owner is record
      Is_Set       : Boolean := False;
      Display_Name : Optional_String;
      ID           : Optional_String;
   end record;

   --  Optional grantee.  A present grantee requires one exact xsi:type
   --  attribute.  The Canonical_User initializer is parser scratch only and
   --  is never returned for an absent or incomplete grantee.
   --  @field Is_Set Whether the Grantee structure was present
   --  @field Kind Required exact xsi:type value when present
   --  @field Display_Name Optional exact display name
   --  @field Email_Address Optional exact email address
   --  @field ID Optional exact canonical identifier
   --  @field URI Optional exact group URI
   type Grantee is record
      Is_Set        : Boolean := False;
      Kind          : Grantee_Type := Canonical_User;
      Display_Name  : Optional_String;
      Email_Address : Optional_String;
      ID            : Optional_String;
      URI           : Optional_String;
   end record;

   --  Presence-preserving optional permission.  The Full_Control initializer
   --  is parser scratch only and does not grant permission when absent.
   --  @field Is_Set Whether Permission was present
   --  @field Value Exact permission when present
   type Optional_Permission is record
      Is_Set : Boolean := False;
      Value  : Permission := Full_Control;
   end record;

   --  One exact Grant list member.
   --  @field Principal Optional typed grantee
   --  @field Allowed Optional exact permission
   type Grant is record
      Principal : Grantee;
      Allowed   : Optional_Permission;
   end record;

   --  Dynamically sized Grant storage bounded by caller XML limits.
   package Grant_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Grant);

   --  Optional AccessControlList wrapper and ordered Grant values.
   --  @field Is_Set Whether AccessControlList was present
   --  @field Grants Exact grants in wire order
   type Access_Control_List is record
      Is_Set : Boolean := False;
      Grants : Grant_Vectors.Vector;
   end record;

   --  Presence-preserving GetBucketAcl response payload.
   --  @field Is_Set Whether the outer payload was present
   --  @field Policy_Owner Optional exact Owner structure
   --  @field ACL Optional AccessControlList and ordered grants
   type Access_Control_Policy is record
      Is_Set       : Boolean := False;
      Policy_Owner : Owner;
      ACL          : Access_Control_List;
   end record;

   --  Parse one exact nonempty GetBucketAcl response payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present access-control policy with modeled presence preserved
   --  @exception Malformed_ACL Document violates the pinned model
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Access_Control_Policy;

end Flyology.Object_Storage.S3.ACL;
