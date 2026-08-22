with Ada.Finalization;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.SigV4_Verification;
with Flyology.Object_Storage.Server.Authentication;

--  Supplies one securely owned static SigV4 identity. This provider is useful
--  for small deployments and qualification servers; dynamic registries and
--  HSM integrations should implement Authentication.Credential_Provider
--  directly so secret material never leaves their trust boundary.
package Flyology.Object_Storage.Server.Static_Credentials is

   Invalid_Credentials : exception;

   type Provider is limited new Ada.Finalization.Limited_Controlled and
     Authentication.Credential_Provider with private;

   --  Copy one credential identity into bounded provider-owned storage.
   --  All retained fields are wiped during finalization. An empty Principal
   --  uses Access_Key as the authenticated principal name.
   --  @param Access_Key AWS access-key identifier
   --  @param Secret_Key AWS secret signing key
   --  @param Session_Token Optional required session token
   --  @param Principal Application principal reported after authentication
   --  @return Limited credential provider owning independent copies
   --  @exception Invalid_Credentials A field is empty, malformed, or too long
   function Create
     (Access_Key    : String;
      Secret_Key    : String;
      Session_Token : String := "";
      Principal     : String := "") return Provider;

private
   Maximum_Credential_Bytes : constant := 1_024;
   Maximum_Session_Token_Bytes : constant := 8_192;
   Maximum_Principal_Bytes : constant := 1_024;

   type Provider is limited new Ada.Finalization.Limited_Controlled and
     Authentication.Credential_Provider with record
      Access_Key_Length : Natural range 0 .. Maximum_Credential_Bytes := 0;
      Secret_Key_Length : Natural range 0 .. Maximum_Credential_Bytes := 0;
      Session_Token_Length :
        Natural range 0 .. Maximum_Session_Token_Bytes := 0;
      Principal_Length : Natural range 0 .. Maximum_Principal_Bytes := 0;
      Access_Key_Data : String (1 .. Maximum_Credential_Bytes) :=
        (others => Character'Val (0));
      Secret_Key_Data : String (1 .. Maximum_Credential_Bytes) :=
        (others => Character'Val (0));
      Session_Token_Data : String (1 .. Maximum_Session_Token_Bytes) :=
        (others => Character'Val (0));
      Principal_Data : String (1 .. Maximum_Principal_Bytes) :=
        (others => Character'Val (0));
   end record;

   overriding procedure Authenticate
     (Item          : in out Provider;
      Authorization : S3.SigV4_Verification.Authorization_Data;
      Method        : String;
      Target        : String;
      Headers       : S3.SigV4.Name_Value_Array;
      Payload_Hash  : String;
      Session_Token : String;
      Allowed       : out Boolean;
      Principal     : out Ada.Strings.Unbounded.Unbounded_String);

   overriding procedure Finalize (Item : in out Provider);

end Flyology.Object_Storage.Server.Static_Credentials;
