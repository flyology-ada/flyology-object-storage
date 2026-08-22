with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.Secrets;

package body Flyology.Object_Storage.Server.Static_Credentials is

   package US renames Ada.Strings.Unbounded;
   package Encoding renames S3.SigV4_Encoding;
   package Verification renames S3.SigV4_Verification;

   function Access_Key (Item : Provider) return String is
     (Item.Access_Key_Data (1 .. Item.Access_Key_Length));

   function Secret_Key (Item : Provider) return String is
     (Item.Secret_Key_Data (1 .. Item.Secret_Key_Length));

   function Required_Token (Item : Provider) return String is
     (Item.Session_Token_Data (1 .. Item.Session_Token_Length));

   function Principal_Name (Item : Provider) return String is
     (Item.Principal_Data (1 .. Item.Principal_Length));

   function Create
     (Access_Key    : String;
      Secret_Key    : String;
      Session_Token : String := "";
      Principal     : String := "") return Provider
   is
      Effective_Principal : constant String :=
        (if Principal'Length = 0 then Access_Key else Principal);
   begin
      if not Encoding.Valid_Access_Key (Access_Key)
        or else Access_Key'Length > Maximum_Credential_Bytes
        or else Secret_Key'Length = 0
        or else Secret_Key'Length > Maximum_Credential_Bytes
        or else Session_Token'Length > Maximum_Session_Token_Bytes
        or else Effective_Principal'Length = 0
        or else Effective_Principal'Length > Maximum_Principal_Bytes
      then
         raise Invalid_Credentials with "invalid static S3 credentials";
      end if;
      for Value of Effective_Principal loop
         if Value = Character'Val (0)
           or else Character'Pos (Value) < 32
           or else Character'Pos (Value) = 127
         then
            raise Invalid_Credentials with "invalid static S3 principal";
         end if;
      end loop;
      return Result : Provider do
         Result.Access_Key_Length := Access_Key'Length;
         Result.Secret_Key_Length := Secret_Key'Length;
         Result.Session_Token_Length := Session_Token'Length;
         Result.Principal_Length := Effective_Principal'Length;
         Result.Access_Key_Data (1 .. Access_Key'Length) := Access_Key;
         Result.Secret_Key_Data (1 .. Secret_Key'Length) := Secret_Key;
         if Session_Token'Length > 0 then
            Result.Session_Token_Data (1 .. Session_Token'Length) :=
              Session_Token;
         end if;
         Result.Principal_Data (1 .. Effective_Principal'Length) :=
           Effective_Principal;
      end return;
   end Create;

   overriding procedure Authenticate
     (Item          : in out Provider;
      Authorization : Verification.Authorization_Data;
      Method        : String;
      Target        : String;
      Headers       : S3.SigV4.Name_Value_Array;
      Payload_Hash  : String;
      Session_Token : String;
      Allowed       : out Boolean;
      Principal     : out US.Unbounded_String)
   is
      Token_Matches : constant Boolean :=
        S3.SigV4.Constant_Time_Equal
          (Session_Token, Required_Token (Item));
   begin
      Allowed :=
        Verification.Access_Key (Authorization) = Access_Key (Item)
        and then Token_Matches
        and then Verification.Verify
          (Authorization, Method, Target, Headers, Payload_Hash,
           Secret_Key (Item));
      Principal :=
        (if Allowed then US.To_Unbounded_String (Principal_Name (Item))
         else US.Null_Unbounded_String);
   end Authenticate;

   overriding procedure Finalize (Item : in out Provider) is
   begin
      Secrets.Wipe (Item.Access_Key_Data);
      Secrets.Wipe (Item.Secret_Key_Data);
      Secrets.Wipe (Item.Session_Token_Data);
      Secrets.Wipe (Item.Principal_Data);
      Item.Access_Key_Length := 0;
      Item.Secret_Key_Length := 0;
      Item.Session_Token_Length := 0;
      Item.Principal_Length := 0;
   end Finalize;

end Flyology.Object_Storage.Server.Static_Credentials;
