with Flyology.Object_Storage.Secrets;

package body Flyology.Object_Storage.Server.MFA is

   function Valid_Text (Value : String; Allow_Empty : Boolean) return Boolean
   is
   begin
      if not Allow_Empty and then Value'Length = 0 then
         return False;
      end if;
      for Element of Value loop
         if Element = Character'Val (0)
           or else Character'Pos (Element) < 32
           or else Character'Pos (Element) = 127
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Text;

   procedure Initialize
     (Item             : in out Authorization_Request;
      Principal        : String;
      Credential       : String;
      Secure_Transport : Boolean;
      Result           : out Request_Status)
   is
   begin
      Clear (Item);
      if Principal'Length = 0
        or else Principal'Length > Maximum_Principal_Bytes
        or else not Valid_Text (Principal, Allow_Empty => False)
      then
         Result := Principal_Invalid;
      elsif Credential'Length = 0 then
         Result := Credential_Missing;
      elsif Credential'Length > Maximum_Credential_Bytes
        or else not Valid_Text (Credential, Allow_Empty => False)
      then
         Result := Credential_Invalid;
      else
         Item.Principal_Size := Principal'Length;
         Item.Credential_Size := Credential'Length;
         Item.Secure := Secure_Transport;
         Item.Principal_Data (1 .. Principal'Length) := Principal;
         Item.Credential_Data (1 .. Credential'Length) := Credential;
         Result := Request_Ready;
      end if;
   end Initialize;

   procedure Authorize
     (Item    : in out Verifier'Class;
      Request : Authorization_Request;
      Result  : out Authorization_Status)
   is
   begin
      Item.Verify
        (Request.Principal_Data (1 .. Request.Principal_Size),
         Request.Credential_Data (1 .. Request.Credential_Size),
         Request.Secure, Result);
   end Authorize;

   procedure Clear (Item : in out Authorization_Request) is
   begin
      Secrets.Wipe (Item.Principal_Data);
      Secrets.Wipe (Item.Credential_Data);
      Item.Principal_Size := 0;
      Item.Credential_Size := 0;
      Item.Secure := False;
   end Clear;

end Flyology.Object_Storage.Server.MFA;
