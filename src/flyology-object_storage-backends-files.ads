with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage.Tags;

--  Durable single-node backend using only ordinary filesystem primitives.
--  Object keys are encoded, never interpreted as paths supplied by callers.
package Flyology.Object_Storage.Backends.Files is

   Configuration_Error : exception;

   type Commit_Policy is (Power_Loss_Durable, Process_Crash_Atomic);

   type Store is limited new Backend with private;

   --  Open or create a backend rooted at Root. Power_Loss_Durable is the
   --  production default and synchronizes every file and directory mutation;
   --  Process_Crash_Atomic preserves rename atomicity without persistence
   --  barriers and must be labeled separately in benchmarks.
   --  @param Root Exclusively owned filesystem root
   --  @param Maximum_Object_Size Per-request bound for declared and unknown
   --  length sources
   --  @param Commit Persistence policy for every namespace mutation
   --  @return Opened files backend
   --  @exception Configuration_Error Root setup or a required initial
   --  durability barrier failed
   function Open
     (Root                : String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last;
      Commit              : Commit_Policy := Power_Loss_Durable) return Store;

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

   --  Publish an unversioned current object, a suspended null generation, or
   --  an enabled opaque retained generation. The returned identity and object
   --  bytes cross the same atomic rename boundary. A failure after rename and
   --  before the directory durability barrier is an ambiguous publication.
   --  @param Item Filesystem store
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Source One-shot body source consumed synchronously
   --  @param Options Complete object publication options
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata published on success
   --  @param Identity Omitted, null, or opaque identity on success only
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

   --  Copy one current, null, or opaque exact filesystem generation from a
   --  stable source snapshot into the destination versioning state.
   --  @param Item Files backend instance
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

   --  Read the current, null, or opaque exact filesystem metadata generation.
   --  Delete markers are not readable as objects.
   --  @param Selector Current, null, or opaque exact generation selection
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

   --  Stream the current, null, or opaque exact filesystem object generation.
   --  The selected immutable file provides one metadata-and-body snapshot.
   --  @param Selector Current, null, or opaque exact generation selection
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

   --  Read attributes from the current, null, or opaque exact filesystem
   --  generation. The returned snapshot is bound to that selected file.
   --  @param Selector Current, null, or opaque exact generation selection
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

   --  Delete one selected filesystem generation when qualified.
   --  @param Item Filesystem backend instance
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

   --  Replace tags on the current, null, or opaque exact filesystem
   --  generation without changing its version identity.
   --  @param Identity Selected generation on success
   --  @param Selector Current, null, or opaque exact generation selection
   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Read tags from the current, null, or opaque exact filesystem generation.
   --  @param Identity Selected generation on success
   --  @param Selector Current, null, or opaque exact generation selection
   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Clear tags on the current, null, or opaque exact filesystem generation
   --  without changing its version identity.
   --  @param Identity Selected generation on success
   --  @param Selector Current, null, or opaque exact generation selection
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

   --  Return one bounded filesystem generation page when qualified.
   --  @param Item Filesystem backend instance
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
   procedure Validate_New_Temp_Target (Item : Store; Path : String);

   protected type Sequence is
      procedure Next (Value : out Long_Long_Integer);
   private
      Value : Long_Long_Integer := 0;
   end Sequence;

   protected type Publication_Gate is
      entry Acquire;
      procedure Release;
   private
      Held : Boolean := False;
   end Publication_Gate;

   type Store is limited new Backend with record
      Root_Path           : Ada.Strings.Unbounded.Unbounded_String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last;
      Commit              : Commit_Policy := Power_Loss_Durable;
      Temp_Sequence       : Sequence;
      Publication         : Publication_Gate;
   end record;

end Flyology.Object_Storage.Backends.Files;
