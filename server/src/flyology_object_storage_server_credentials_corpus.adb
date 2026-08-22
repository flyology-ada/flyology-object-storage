with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;
with Flyology_Object_Storage_Server_Credentials;

procedure Flyology_Object_Storage_Server_Credentials_Corpus is
   package Credentials renames Flyology_Object_Storage_Server_Credentials;

   First  : Credentials.Credential;
   Second : Credentials.Credential;
   First_Generated  : Boolean;
   Second_Generated : Boolean;
   Password : String (1 .. Credentials.Generated_Password_Length);
   Reload_Buffer : String (1 .. Credentials.Generated_Password_Length);
   Wrong_Password : String (1 .. Credentials.Generated_Password_Length);
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      raise Program_Error with
        "usage: flyology_object_storage_server_credentials_corpus PATH";
   end if;
   declare
      Path : constant String := Ada.Command_Line.Argument (1);
   begin
      if not Credentials.Cryptographic_Self_Test then
         raise Program_Error with "PBKDF2-HMAC-SHA256 vector failed";
      end if;
      Credentials.Load_Or_Bootstrap
        (Path, First, First_Generated, Password);
      Wrong_Password := Password;
      Wrong_Password (Wrong_Password'Last) :=
        (if Wrong_Password (Wrong_Password'Last) = '0' then '1' else '0');
      if not First_Generated
        or else not Ada.Directories.Exists (Path)
        or else not Credentials.Verify
          (First, Credentials.Username, Password)
        or else Credentials.Verify
          (First, Credentials.Username, Wrong_Password)
        or else Credentials.Verify (First, "other", Password)
      then
         raise Program_Error with
           "administrator credential bootstrap verification failed";
      end if;

      Credentials.Load_Or_Bootstrap
        (Path, Second, Second_Generated, Reload_Buffer);
      if Second_Generated
        or else Reload_Buffer /= String'(Reload_Buffer'Range => ' ')
        or else not Credentials.Verify
          (Second, Credentials.Username, Password)
      then
         raise Program_Error with
           "administrator credential reload verification failed";
      end if;
      Credentials.Wipe (Password);
      Credentials.Wipe (Reload_Buffer);
      Credentials.Wipe (Wrong_Password);
   end;
   Ada.Text_IO.Put_Line ("administrator credential bootstrap corpus: OK");
exception
   when others =>
      Credentials.Wipe (Password);
      Credentials.Wipe (Reload_Buffer);
      Credentials.Wipe (Wrong_Password);
      raise;
end Flyology_Object_Storage_Server_Credentials_Corpus;
