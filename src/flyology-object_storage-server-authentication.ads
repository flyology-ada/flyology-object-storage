with Ada.Calendar;
with Ada.Strings.Unbounded;
with Flyology.HTTP.Server.Applications;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.SigV4_Verification;

--  Request-scoped S3 SigV4 authentication for Flyology HTTP exchanges.
package Flyology.Object_Storage.Server.Authentication is

   type Credential_Provider is limited interface;

   --  Verify one canonicalized request while keeping credential material
   --  inside the provider. Simple providers can call
   --  S3.SigV4_Verification.Verify with their borrowed secret; HSM-backed
   --  providers can implement the same decision without exporting a key.
   --  Session_Token is empty when the request does not carry one. Principal
   --  identifies the tenant/account owner, not the individual access key.
   --  A provider used by one S3_Applications instance must return the same
   --  nonempty Principal for every credential it accepts for that Store over
   --  the lifetime of that provider/application instance.
   procedure Authenticate
     (Item          : in out Credential_Provider;
      Authorization : S3.SigV4_Verification.Authorization_Data;
      Method        : String;
      Target        : String;
      Headers       : S3.SigV4.Name_Value_Array;
      Payload_Hash  : String;
      Session_Token : String;
      Allowed       : out Boolean;
      Principal     : out Ada.Strings.Unbounded.Unbounded_String) is abstract;

   subtype Clock_Skew is Duration range 0.0 .. 86_400.0;

   type Policy is record
      Expected_Region    : Ada.Strings.Unbounded.Unbounded_String;
      Maximum_Clock_Skew : Clock_Skew := 900.0;
   end record;

   Default_Policy : constant Policy;

   type Outcome_Status is
     (Authenticated,
      Missing_Credentials,
      Malformed_Credentials,
      Request_Time_Too_Skewed,
      Wrong_Region,
      Insecure_Unsigned_Payload,
      Credential_Rejected);

   type Outcome is record
      Status       : Outcome_Status := Missing_Credentials;
      Principal    : Ada.Strings.Unbounded.Unbounded_String;
      Payload_Hash : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Authenticate an exchange before accepting or consuming its body.
   --  Exactly one Authorization, date, content hash, and each declared signed
   --  field must be present. The scope date, semantic UTC timestamp, clock
   --  skew, optional region, and HTTPS requirement for UNSIGNED-PAYLOAD are
   --  checked before the credential provider is invoked.
   --  @param X Active Flyology HTTP application exchange
   --  @param Credentials Application credential verifier
   --  @param Rules Authentication and clock-skew policy
   --  @param Now Trusted current UTC wall-clock time
   --  @return Authentication decision and authenticated principal
   function Verify_Request
     (X           : Flyology.HTTP.Server.Applications.Exchange;
      Credentials : in out Credential_Provider'Class;
      Rules       : Policy := Default_Policy;
      Now         : Ada.Calendar.Time := Ada.Calendar.Clock) return Outcome;

private
   Default_Policy : constant Policy :=
     (Expected_Region    => Ada.Strings.Unbounded.Null_Unbounded_String,
      Maximum_Clock_Skew => 900.0);
end Flyology.Object_Storage.Server.Authentication;
