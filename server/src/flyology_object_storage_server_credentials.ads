package Flyology_Object_Storage_Server_Credentials is

   Username : constant String := "admin";
   Generated_Password_Length : constant := 48;

   type Credential is private;

   --  Load a strict owner-only credential file, or atomically create it with
   --  a CSPRNG password and PBKDF2-HMAC-SHA256 verifier. Password is returned
   --  only for a successful first bootstrap and must be wiped by the caller.
   procedure Load_Or_Bootstrap
     (Path      : String;
      Value     : out Credential;
      Generated : out Boolean;
      Password  : out String)
   with Pre => Password'Length = Generated_Password_Length;

   function Verify
     (Value : Credential; User, Password : String) return Boolean;

   --  Check the PBKDF2-HMAC-SHA256 implementation against the published
   --  iteration-one vector before accepting administrator credentials.
   function Cryptographic_Self_Test return Boolean;

   procedure Wipe (Value : in out String);

private
   Salt_Length : constant := 32;
   Hash_Length : constant := 32;

   type Credential is record
      Salt       : String (1 .. Salt_Length) := (others => Character'Val (0));
      Hash       : String (1 .. Hash_Length) := (others => Character'Val (0));
      Iterations : Positive := 600_000;
   end record;
end Flyology_Object_Storage_Server_Credentials;
