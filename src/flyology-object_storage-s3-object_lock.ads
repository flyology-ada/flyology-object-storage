with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codecs for small S3 Object Lock documents.
package Flyology.Object_Storage.S3.Object_Lock is

   Malformed_Object_Lock : exception;

   --  Pinned model contract for ObjectLockLegalHoldStatus.  Absent preserves
   --  omission independently from the two external ON and OFF values.
   --  @enum Legal_Hold_Status_Absent Status member was absent
   --  @enum Legal_Hold_On Exact external ON value
   --  @enum Legal_Hold_Off Exact external OFF value
   type Legal_Hold_Status is
     (Legal_Hold_Status_Absent, Legal_Hold_On, Legal_Hold_Off);

   --  Presence-preserving ObjectLockLegalHold payload.  The defaults encode
   --  model-member absence only; they do not establish object-lock policy.
   --  @field Is_Set Whether the outer LegalHold payload member was present
   --  @field Status Optional nested Status member
   type Legal_Hold is record
      Is_Set : Boolean := False;
      Status : Legal_Hold_Status := Legal_Hold_Status_Absent;
   end record;

   --  Parse one exact GetObjectLegalHold payload.  An empty HTTP body is
   --  represented by the caller as an absent LegalHold member and is not
   --  passed to this function.
   --  @param Document Complete nonempty same-response LegalHold XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present legal-hold value with optional status
   --  @exception Malformed_Object_Lock Document violates the pinned model
   function Parse_Legal_Hold
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Legal_Hold;

   --  Serialize one exact PutObjectLegalHold body.  An absent outer member
   --  produces the model-permitted empty payload; a present outer member
   --  preserves optional Status presence.
   --  @param Value Presence-preserving legal-hold request value
   --  @param Limits Caller-selected document, depth, element, and text limits
   --  @return Exact bounded S3 LegalHold XML or the absent empty payload
   --  @exception Malformed_Object_Lock Value is inconsistent or exceeds limits
   function Serialize_Legal_Hold
     (Value  : Legal_Hold;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String;

   --  Pinned model contract for ObjectLockRetentionMode.  Absent preserves
   --  omission independently from the two external retention modes.
   --  @enum Retention_Mode_Absent Mode member was absent
   --  @enum Governance_Retention Exact external GOVERNANCE value
   --  @enum Compliance_Retention Exact external COMPLIANCE value
   type Retention_Mode is
     (Retention_Mode_Absent, Governance_Retention, Compliance_Retention);

   --  Presence-preserving ObjectLockRetention payload.  The defaults encode
   --  model-member absence only and never create a retention policy or date.
   --  @field Is_Set Whether the outer Retention payload member was present
   --  @field Mode Optional nested retention mode
   --  @field Retain_Until_Date Optional exact ISO-8601 timestamp text
   type Retention is record
      Is_Set            : Boolean := False;
      Mode              : Retention_Mode := Retention_Mode_Absent;
      Retain_Until_Date : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Parse one exact GetObjectRetention payload.  An empty HTTP body is
   --  represented by the caller as an absent Retention member and is not
   --  passed to this function.
   --  @param Document Complete nonempty same-response Retention XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present retention value with independent optional members
   --  @exception Malformed_Object_Lock Document violates the pinned model
   function Parse_Retention
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Retention;

   --  Serialize one exact PutObjectRetention body.  An absent outer member
   --  produces the model-permitted empty payload; a present outer member
   --  preserves Mode and RetainUntilDate independently.
   --  @param Value Presence-preserving retention request value
   --  @param Limits Caller-selected document, depth, element, and text limits
   --  @return Exact bounded S3 Retention XML or the absent empty payload
   --  @exception Malformed_Object_Lock Value is inconsistent or exceeds limits
   function Serialize_Retention
     (Value  : Retention;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String;

   --  Pinned model contract for ObjectLockEnabled.  Absent preserves model
   --  omission independently from the sole external Enabled value.
   --  @enum Object_Lock_Enabled_Absent ObjectLockEnabled member was absent
   --  @enum Object_Lock_Enabled Exact external Enabled value
   type Object_Lock_Enabled_Status is
     (Object_Lock_Enabled_Absent, Object_Lock_Enabled);

   --  Presence-preserving arbitrary-precision integer text.  The pinned Days
   --  and Years shapes define no numeric bounds, so a machine integer would
   --  impose an unauthorized compatibility ceiling.
   --  @field Is_Set Whether the modeled integer member was present
   --  @field Text Exact validated signed decimal wire text
   type Optional_Integer_Text is record
      Is_Set : Boolean := False;
      Text   : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Presence-preserving DefaultRetention structure.  No relationship among
   --  Mode, Days, and Years is inferred beyond the pinned generated model.
   --  @field Is_Set Whether the DefaultRetention member was present
   --  @field Mode Optional exact retention mode
   --  @field Days Optional unbounded integer text
   --  @field Years Optional unbounded integer text
   type Default_Retention is record
      Is_Set : Boolean := False;
      Mode   : Retention_Mode := Retention_Mode_Absent;
      Days   : Optional_Integer_Text;
      Years  : Optional_Integer_Text;
   end record;

   --  Presence-preserving ObjectLockRule structure.
   --  @field Is_Set Whether the Rule member was present
   --  @field Default_Value Optional DefaultRetention member
   type Object_Lock_Rule is record
      Is_Set        : Boolean := False;
      Default_Value : Default_Retention;
   end record;

   --  Presence-preserving ObjectLockConfiguration payload.  Defaults encode
   --  member absence only and never enable Object Lock or create retention.
   --  @field Is_Set Whether the outer payload member was present
   --  @field Enabled Optional ObjectLockEnabled member
   --  @field Rule Optional nested rule
   type Object_Lock_Configuration is record
      Is_Set  : Boolean := False;
      Enabled : Object_Lock_Enabled_Status := Object_Lock_Enabled_Absent;
      Rule    : Object_Lock_Rule;
   end record;

   --  Parse one exact GetObjectLockConfiguration payload.  An empty HTTP body
   --  is represented by the caller as an absent outer member.
   --  @param Document Complete nonempty same-response configuration XML
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present configuration with all nested presence preserved
   --  @exception Malformed_Object_Lock Document violates the pinned model
   function Parse_Configuration
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Object_Lock_Configuration;

end Flyology.Object_Storage.S3.Object_Lock;
