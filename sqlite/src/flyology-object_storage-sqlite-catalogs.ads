with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.SQLite.Databases;
with Flyology.Object_Storage.Tags;

--  Transactional namespace and object metadata for the SQLite backend.
--  Payloads are immutable external files named by the backend.
package Flyology.Object_Storage.SQLite.Catalogs is

   Catalog_Error : exception;

   type Catalog is limited private;

   procedure Open (Item : in out Catalog; Path : String);
   procedure Close (Item : in out Catalog);

   procedure Create_Bucket
     (Item    : in out Catalog;
      Name    : String;
      Created : Unix_Time;
      Result  : out Status);

   procedure List_Buckets
     (Item    : in out Catalog;
      Options : Backends.List_Buckets_Options;
      Check   : not null access procedure;
      Page    : out Backends.Bucket_Page;
      Result  : out Status);

   procedure Head_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Put_Bucket_Versioning
     (Item          : in out Catalog;
      Name          : String;
      Configuration : Bucket_Versioning_Configuration;
      Result        : out Status;
      MFA_Validated : Boolean := False);

   procedure Get_Bucket_Versioning
     (Item          : in out Catalog;
      Name          : String;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status);

   procedure Delete_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Put_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Tags.Tag_Set;
      Result : out Status);

   procedure Get_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Tags.Tag_Set;
      Result : out Status);

   procedure Delete_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   procedure Put_Object
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Payload          : String;
      Info             : in out Object_Information;
      Tags             : Object_Tag_Set;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result           : out Status;
      Conditions       : Write_Conditions := Default_Write_Conditions);

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Info    : out Object_Information;
      Result  : out Status;
      Check   : access procedure
        (Payload : String; Info : Object_Information) := null);
   --  When present, Check runs after a successful lookup while the catalog
   --  operation gate is still held. It may validate the immutable external
   --  payload before a concurrent publication retires the previous file.

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Info    : out Object_Information;
      Tags    : out Object_Tag_Set;
      Result  : out Status;
      Check   : access procedure
        (Payload : String;
         Info    : Object_Information;
         Tags    : Object_Tag_Set) := null);
   --  Return tags from the same protected catalog snapshot as Info. When
   --  present, Check runs while that snapshot and external payload lifetime
   --  remain protected by the catalog operation gate.

   --  Select one retained data generation from an atomic catalog snapshot.
   --  Delete markers are reported as absent object data.
   --  @param Item Open catalog
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Selector Current, null, or exact retained generation
   --  @param Payload Immutable external payload name
   --  @param Info Metadata bound to the selected payload
   --  @param Result Operation status
   --  @param Check Optional payload validation while the gate is held
   procedure Find_Selected_Object
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Selector : Backends.Version_Selector;
      Payload  : out Ada.Strings.Unbounded.Unbounded_String;
      Info     : out Object_Information;
      Result   : out Status;
      Check    : access procedure
        (Payload : String; Info : Object_Information) := null);

   procedure Get_Object_Attributes
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Selector : Backends.Version_Selector;
      Options  : Backends.Object_Attribute_Options;
      Conditions : Backends.Read_Conditions;
      Check    : not null access procedure;
      Snapshot : out Backends.Object_Attribute_Snapshot;
      Result   : out Status);

   package Payload_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");
   subtype Payloads is Payload_Vectors.Vector;

   --  Delete one ordered batch in a single SQLite transaction. Retired
   --  payload names become unreferenced only after the transaction commits.
   procedure Delete_Objects
     (Item     : in out Catalog;
      Bucket   : String;
      Entries  : Backends.Delete_Object_Entries;
      Requirements : Backends.Delete_Objects_Requirements;
      Retired  : out Payloads;
      Outcomes : out Backends.Delete_Object_Outcomes;
      Result   : out Status);

   --  Remove one selected generation or publish the versioning-mode marker.
   --  @param Item Open catalog
   --  @param Bucket Bucket containing the key
   --  @param Key Exact object key
   --  @param Selector Current, null, or exact generation selection
   --  @param Conditions Atomic object deletion predicates
   --  @param MFA_Validated Caller authorization attestation for MFA Delete
   --  @param Modified Commit timestamp for a newly published marker
   --  @param Retired_Payload Payload made unreachable by this transaction
   --  @param Outcome Exact generation-aware deletion effect
   --  @param Result Operation status
   procedure Delete_Selected_Object
     (Item            : in out Catalog;
      Bucket          : String;
      Key             : String;
      Selector        : Backends.Version_Selector;
      Conditions      : Backends.Delete_Object_Conditions;
      MFA_Validated   : Boolean;
      Modified        : Unix_Time;
      Retired_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Outcome         : out Backends.Version_Delete_Outcome;
      Result          : out Status);

   --  Replace tags and return the selected generation from one transaction.
   procedure Put_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : Object_Tag_Set; Identity : out Backends.Version_Identity;
      Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Compatibility form when the selected identity is not needed.
   procedure Put_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : Object_Tag_Set; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Read tags and identity from one serialized catalog snapshot.
   procedure Get_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : out Object_Tag_Set; Identity : out Backends.Version_Identity;
      Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Compatibility form when the selected identity is not needed.
   procedure Get_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : out Object_Tag_Set; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Clear tags and return the selected generation from one transaction.
   procedure Delete_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Identity : out Backends.Version_Identity; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Compatibility form when the selected identity is not needed.
   procedure Delete_Object_Tags
     (Item : in out Catalog; Bucket, Key : String; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   procedure List_Objects
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Options;
      Check   : not null access procedure;
      Page    : out Backends.List_Page;
      Result  : out Status);

   --  Return one bounded retained-generation page from the catalog snapshot.
   --  @param Item Open catalog
   --  @param Bucket Bucket whose generations are listed
   --  @param Options Prefix, delimiter, paired cursor, and page bound
   --  @param Check Cancellation/deadline check run while the gate is held
   --  @param Page Ordered versions, delete markers, and common prefixes
   --  @param Result Operation status
   procedure List_Object_Versions
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Versions_Options;
      Check   : not null access procedure;
      Page    : out Backends.List_Versions_Page;
      Result  : out Status);

   function Payload_Referenced
     (Item : in out Catalog; Payload : String) return Boolean;

   type Multipart_Part_Record is record
      Number  : Backends.Multipart_Part_Number :=
        Backends.Multipart_Part_Number'First;
      Payload : Ada.Strings.Unbounded.Unbounded_String;
      Info    : Object_Information;
   end record;

   package Multipart_Part_Record_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Multipart_Part_Record);
   subtype Multipart_Part_Records is Multipart_Part_Record_Vectors.Vector;

   procedure Create_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Options      : Backends.Multipart_Options;
      Created      : Unix_Time;
      Result       : out Status);

   procedure Find_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Options      : out Backends.Multipart_Options;
      Result       : out Status);

   procedure Put_Multipart_Part
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Part_Number      : Backends.Multipart_Part_Number;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result           : out Status);

   procedure List_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : Backends.List_Multipart_Parts_Options;
      Page      : out Backends.Multipart_Part_Page;
      Result    : out Status);

   procedure List_Multipart_Uploads
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Multipart_Uploads_Options;
      Check   : not null access procedure;
      Page    : out Backends.Multipart_Upload_Page;
      Result  : out Status);

   procedure Read_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Backends.Multipart_Part_References;
      Records   : out Multipart_Part_Records;
      Result    : out Status);

   procedure Complete_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Selected         : Multipart_Part_Records;
      Payload          : String;
      Info             : in out Object_Information;
      Conditions       : Write_Conditions;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Retired_Payloads : out Payloads;
      Result           : out Status);

   procedure Abort_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Conditions       : Backends.Abort_Multipart_Conditions;
      Retired_Payloads : out Payloads;
      Result           : out Status);

private
   protected type Operation_Gate is
      entry Acquire;
      procedure Release;
   private
      Held : Boolean := False;
   end Operation_Gate;

   type Catalog is limited record
      Database : Flyology.Object_Storage.SQLite.Databases.Database;
      Gate     : Operation_Gate;
   end record;

end Flyology.Object_Storage.SQLite.Catalogs;
