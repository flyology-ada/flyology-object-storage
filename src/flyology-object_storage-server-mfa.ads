--  Bounded, request-scoped MFA authorization boundary for S3 operations.
--  Implementations validate device credentials and root-owner authority
--  without exporting verifier secrets into the HTTP or storage layers.
package Flyology.Object_Storage.Server.MFA is

   Maximum_Principal_Bytes : constant := 1_024;
   Maximum_Credential_Bytes : constant := 2_048;

   type Request_Status is
     (Request_Ready,
      Principal_Invalid,
      Credential_Missing,
      Credential_Invalid);

   type Authorization_Status is
     (Authorized,
      Missing_Credential,
      Insecure_Transport,
      Invalid_Credential,
      Not_Root_Owner,
      Verifier_Unavailable);

   type Authorization_Request is limited private;

   --  Copy borrowed input views into bounded request-scoped storage. This is
   --  the sole mutable application-owned credential copy. Controls, overlong
   --  values, and an empty principal are rejected. The caller must wipe the
   --  request with Clear on every exit path.
   procedure Initialize
     (Item             : in out Authorization_Request;
      Principal        : String;
      Credential       : String;
      Secure_Transport : Boolean;
      Result           : out Request_Status);

   procedure Clear (Item : in out Authorization_Request);

   type Verifier is limited interface;

   --  Decide both device validity and whether Principal is the root bucket
   --  owner authorized for S3 MFA Delete. Implementations must not retain the
   --  request or either borrowed view beyond this call and must not log the
   --  credential. Expected authentication failures are returned, not raised.
   procedure Verify
     (Item    : in out Verifier;
      Principal : String;
      Credential : String;
      Secure_Transport : Boolean;
      Result  : out Authorization_Status) is abstract;

   --  Dispatch one authorization using borrowed views of the request's sole
   --  mutable credential copy. The verifier must not retain either view.
   procedure Authorize
     (Item    : in out Verifier'Class;
      Request : Authorization_Request;
      Result  : out Authorization_Status);

   type Verifier_Access is access all Verifier'Class;

private
   subtype Principal_Length is Natural range 0 .. Maximum_Principal_Bytes;
   subtype Credential_Length is Natural range 0 .. Maximum_Credential_Bytes;

   type Authorization_Request is limited record
      Principal_Size : Principal_Length := 0;
      Credential_Size : Credential_Length := 0;
      Secure : Boolean := False;
      Principal_Data : String (1 .. Maximum_Principal_Bytes) :=
        (others => Character'Val (0));
      Credential_Data : String (1 .. Maximum_Credential_Bytes) :=
        (others => Character'Val (0));
   end record;

end Flyology.Object_Storage.Server.MFA;
