with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 bucket-encryption configurations.
package Flyology.Object_Storage.S3.Encryption is

   --  Raised when a response violates the pinned GetBucketEncryption model.
   Malformed_Encryption : exception;

   --  Exact pinned ServerSideEncryption wire domain.
   --  @enum AES256_Encryption Exact AES256 wire value
   --  @enum FSx_Encryption Exact aws:fsx wire value
   --  @enum Backup_Encryption Exact aws:backup wire value
   --  @enum KMS_Encryption Exact aws:kms wire value
   --  @enum KMS_DSSE_Encryption Exact aws:kms:dsse wire value
   type Encryption_Algorithm is
     (AES256_Encryption, FSx_Encryption, Backup_Encryption,
      KMS_Encryption, KMS_DSSE_Encryption);

   --  Exact pinned blocked-encryption wire domain.
   --  @enum No_Blocked_Encryption Exact NONE wire value
   --  @enum SSE_C_Blocked Exact SSE-C wire value
   type Blocked_Encryption_Type is
     (No_Blocked_Encryption, SSE_C_Blocked);

   --  Presence-preserving optional Boolean.
   --  @field Is_Set Whether the modeled Boolean was present
   --  @field Value Exact decoded value, meaningful only when present
   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Presence-preserving optional string.  Empty text remains distinct from
   --  member absence because the pinned string shape has no minimum.
   --  @field Is_Set Whether the modeled string was present
   --  @field Value Exact decoded string
   type Optional_String is record
      Is_Set : Boolean := False;
      Value  : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Optional ApplyServerSideEncryptionByDefault structure.  SSEAlgorithm
   --  is required whenever the structure is present.  The AES256 initializer
   --  is deterministic parser scratch only: it is never returned for an
   --  absent or incomplete structure and does not select provider policy.
   --  @field Is_Set Whether the outer structure was present
   --  @field Algorithm Required exact algorithm when present
   --  @field KMS_Master_Key_ID Optional exact KMS key identifier
   type Encryption_By_Default is record
      Is_Set            : Boolean := False;
      Algorithm         : Encryption_Algorithm := AES256_Encryption;
      KMS_Master_Key_ID : Optional_String;
   end record;

   --  Dynamically sized blocked-type storage bounded by caller XML limits.
   package Blocked_Encryption_Type_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Blocked_Encryption_Type);

   --  Optional BlockedEncryptionTypes structure and flattened list presence.
   --  @field Is_Set Whether the outer structure was present
   --  @field Types_Is_Set Whether at least one EncryptionType was present
   --  @field Types Exact values in wire order
   type Blocked_Encryption_Types is record
      Is_Set       : Boolean := False;
      Types_Is_Set : Boolean := False;
      Types        : Blocked_Encryption_Type_Vectors.Vector;
   end record;

   --  One exact ServerSideEncryptionRule.
   --  @field Default_Encryption Optional default-encryption structure
   --  @field Bucket_Key_Enabled Optional exact Boolean
   --  @field Blocked_Types Optional blocked-encryption structure
   type Encryption_Rule is record
      Default_Encryption : Encryption_By_Default;
      Bucket_Key_Enabled : Optional_Boolean;
      Blocked_Types      : Blocked_Encryption_Types;
   end record;

   --  Dynamically sized flattened Rule storage bounded by caller XML limits.
   package Encryption_Rule_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Encryption_Rule);

   --  Presence-preserving GetBucketEncryption response payload.
   --  @field Is_Set Whether the outer payload was present
   --  @field Rules Required nonempty flattened Rule list when present
   type Encryption_Configuration is record
      Is_Set : Boolean := False;
      Rules  : Encryption_Rule_Vectors.Vector;
   end record;

   --  Parse one exact nonempty GetBucketEncryption response payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present configuration with every modeled member preserved
   --  @exception Malformed_Encryption Document violates the pinned model
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Encryption_Configuration;

   --  Serialize one exact required PutBucketEncryption payload within the
   --  caller-selected shared XML resource limits. The required flattened Rule
   --  list must contain at least one element because an empty flattened list
   --  has no distinct REST/XML representation.
   --  @param Value Present configuration with one or more exact rules
   --  @param Limits Caller-selected document, depth, element, and text limits
   --  @return Exact S3 ServerSideEncryptionConfiguration XML document
   --  @exception Malformed_Encryption Value or encoded document violates the
   --   pinned schema or caller-selected limits
   function Serialize
     (Value  : Encryption_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String;

end Flyology.Object_Storage.S3.Encryption;
