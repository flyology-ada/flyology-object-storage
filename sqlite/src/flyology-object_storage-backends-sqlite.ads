with Ada.Finalization;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage.Tags;
with Flyology.Object_Storage.SQLite.Catalogs;
with System;

--  SQLite catalog with immutable object bodies stored as external files.
--  Namespace changes are transactional; startup removes incomplete and
--  superseded payload files left by process interruption.
package Flyology.Object_Storage.Backends.SQLite is

   Configuration_Error : exception;

   type Store is limited new Backend with private;

   function Open
     (Root                : String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last) return Store;

   overriding procedure Create_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure List_Buckets
     (Item     : in out Store;
      Options  : List_Buckets_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out Bucket_Page;
      Result   : out Status);

   overriding procedure Delete_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Head_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Value    : Tags.Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Tags.Tag_Set;
      Result   : out Status);

   overriding procedure Delete_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_CORS
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_CORS
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   overriding procedure Delete_Bucket_CORS
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Transactionally retain one bounded encryption override.
   --  @param Item SQLite backend
   --  @param Bucket Existing bucket name
   --  @param Document Canonical encryption bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Encryption
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one transactional encryption-override snapshot.
   --  @param Item SQLite backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether an override is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Encryption
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove the retained encryption override.
   --  @param Item SQLite backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Encryption
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Transactionally retain one ownership-controls document.
   --  @param Item SQLite backend
   --  @param Bucket Existing bucket name
   --  @param Document Canonical ownership-controls bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Ownership_Controls
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one transactional ownership-controls snapshot.
   --  @param Item SQLite backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether ownership controls are retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Ownership_Controls
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove retained ownership controls.
   --  @param Item SQLite backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Ownership_Controls
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Public_Access_Block
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Public_Access_Block_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status);

   overriding procedure Get_Bucket_Public_Access_Block
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Public_Access_Block_Configuration;
      Configured    : out Boolean;
      Result        : out Status);

   overriding procedure Delete_Bucket_Public_Access_Block
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Policy
     (Item     : in out Store;
      Bucket   : String;
      Policy   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_Policy
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Policy     : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   overriding procedure Delete_Bucket_Policy
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Versioning_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status;
      MFA_Validated : Boolean := False);

   overriding procedure Get_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status);

   --  Replace the ABAC state in one SQLite catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving ABAC state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_ABAC
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_ABAC_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one ABAC snapshot from a SQLite catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete presence-preserving ABAC snapshot
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_ABAC
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_ABAC_Status;
      Result   : out Status);

   --  Replace acceleration state in one SQLite catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving acceleration state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Acceleration
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_Acceleration_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one acceleration snapshot from a SQLite catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete presence-preserving acceleration snapshot
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Acceleration
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Acceleration_Status;
      Result   : out Status);

   --  Replace request-payment state in one SQLite catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Existing bucket name
   --  @param Value Complete request-payment state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Request_Payment
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_Request_Payment_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one request-payment snapshot from a SQLite catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete request-payment snapshot
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Request_Payment
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Request_Payment_Status;
      Result   : out Status);

   --  Publish one payload/catalog generation and return the version identity
   --  committed by the same catalog transaction.
   --  @param Item SQLite-backed store
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Source One-shot body source consumed synchronously
   --  @param Options Complete object publication options
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata published on success
   --  @param Identity Omitted, opaque, or null identity on success only
   --  @param Result Publication result
   --  @param Conditions Atomic destination ETag predicates
   overriding procedure Put_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Identity : out Version_Identity;
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions);

   --  Copy one selected SQLite generation and return source/publication
   --  identities from their protected catalog boundaries.
   --  @param Item SQLite backend instance
   --  @param Source_Bucket Source bucket name
   --  @param Source_Key Source key
   --  @param Destination_Bucket Destination bucket name
   --  @param Destination_Key Destination key
   --  @param Options Source selection and copy policy
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Published destination metadata on success
   --  @param Source_Identity Selected source generation on success
   --  @param Destination_Identity Published destination generation on success
   --  @param Result Storage-domain outcome
   overriding procedure Copy_Object
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Copy_Options;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Source_Identity    : out Version_Identity;
      Destination_Identity : out Version_Identity;
      Result             : out Status);

   --  Read one selected SQLite metadata generation.
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Head_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector);

   --  Stream one selected SQLite object generation.
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Get_Object
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Requested : Byte_Range;
      Sink      : in out Byte_Sink'Class;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector);

   --  Read attributes from one selected SQLite generation.
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Get_Object_Attributes
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Options  : Object_Attribute_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Snapshot : out Object_Attribute_Snapshot;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector);

   overriding procedure Delete_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status;
      Conditions : Delete_Object_Conditions :=
        No_Delete_Object_Conditions;
      Requirements : Delete_Objects_Requirements := (others => <>));

   --  Delete one selected SQLite generation when qualified.
   --  @param Item SQLite backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Selector Current, null, or exact deletion target
   --  @param Conditions Optional selected-generation predicates
   --  @param MFA_Validated Caller authorization attestation for MFA Delete
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Outcome Exact publication effect and generation identity
   --  @param Result Storage-domain outcome
   overriding procedure Delete_Selected_Object
     (Item          : in out Store;
      Bucket        : String;
      Key           : String;
      Selector      : Version_Selector;
      Conditions    : Delete_Object_Conditions;
      MFA_Validated : Boolean;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Outcome       : out Version_Delete_Outcome;
      Result        : out Status);

   overriding procedure Delete_Objects
     (Item     : in out Store;
      Bucket   : String;
      Entries  : Delete_Object_Entries;
      Requirements : Delete_Objects_Requirements;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Outcomes : out Delete_Object_Outcomes;
      Result   : out Status);

   --  Replace tags on one selected SQLite generation.
   --  @param Identity Selected generation from the mutation transaction
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Read tags from one selected SQLite generation.
   --  @param Identity Selected generation from the catalog snapshot
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Clear tags on one selected SQLite generation.
   --  @param Identity Selected generation from the mutation transaction
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   overriding procedure List_Objects
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Page;
      Result   : out Status);

   --  Return one bounded SQLite generation page when qualified.
   --  @param Item SQLite backend instance
   --  @param Bucket Bucket name
   --  @param Options Prefix, delimiter, paired cursor, and page bound
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Page Atomic bounded result page
   --  @param Result Storage-domain outcome
   overriding procedure List_Object_Versions
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Versions_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Versions_Page;
      Result   : out Status);

   overriding procedure Create_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Options   : Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
      Result    : out Status);

   overriding procedure Put_Multipart_Part
     (Item        : in out Store;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Options     : Multipart_Part_Options;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status);

   overriding procedure List_Multipart_Parts
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : List_Multipart_Parts_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Part_Page;
      Result    : out Status);

   overriding procedure List_Multipart_Uploads
     (Item      : in out Store;
      Bucket    : String;
      Options   : List_Multipart_Uploads_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Upload_Page;
      Result    : out Status);

   overriding procedure Copy_Multipart_Part
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Upload_ID          : String;
      Part_Number        : Multipart_Part_Number;
      Requested          : Byte_Range;
      Conditions         : Copy_Conditions;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status);

   overriding procedure Complete_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Options   : Complete_Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status);

   overriding procedure Abort_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Conditions : Abort_Multipart_Conditions;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Result    : out Status);

   function Root_Directory (Item : Store) return String;

private
   type Root_Lock is
     limited new Ada.Finalization.Limited_Controlled with record
      Handle : System.Address := System.Null_Address;
   end record;

   overriding procedure Finalize (Item : in out Root_Lock);

   protected type Sequence is
      procedure Next (Value : out Long_Long_Integer);
   private
      Value : Long_Long_Integer := 0;
   end Sequence;

   type Store is limited new Backend with record
      Root_Path           : Ada.Strings.Unbounded.Unbounded_String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last;
      Temp_Sequence       : Sequence;
      Lock                : Root_Lock;
      Catalog             : Flyology.Object_Storage.SQLite.Catalogs.Catalog;
   end record;

end Flyology.Object_Storage.Backends.SQLite;
