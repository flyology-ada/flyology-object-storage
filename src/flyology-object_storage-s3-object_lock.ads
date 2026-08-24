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

end Flyology.Object_Storage.S3.Object_Lock;
