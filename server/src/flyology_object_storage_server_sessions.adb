with Flyology_Object_Storage_Server_Credentials;
with Interfaces;

package body Flyology_Object_Storage_Server_Sessions is
   use type Ada.Real_Time.Time;
   use type Interfaces.Unsigned_8;

   function Equal (Left, Right : String) return Boolean is
      Difference : Interfaces.Unsigned_8 := 0;
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;
      for Offset in 0 .. Left'Length - 1 loop
         Difference := Difference or
           (Interfaces.Unsigned_8
              (Character'Pos (Left (Left'First + Offset))) xor
            Interfaces.Unsigned_8
              (Character'Pos (Right (Right'First + Offset))));
      end loop;
      return Difference = 0;
   end Equal;

   protected body Store is
      procedure Create (Token : String; Now : Ada.Real_Time.Time) is
         Slot : Positive := Entries'First;
      begin
         if Token'Length /= Token_Length then
            raise Constraint_Error with "invalid administrator session token";
         end if;
         for Index in Entries'Range loop
            if not Entries (Index).Occupied
              or else Entries (Index).Expires <= Now
            then
               Slot := Index;
               exit;
            elsif Entries (Index).Expires < Entries (Slot).Expires then
               Slot := Index;
            end if;
         end loop;
         Flyology_Object_Storage_Server_Credentials.Wipe
           (Entries (Slot).Token);
         Entries (Slot) :=
           (Occupied => True,
            Token    => Token,
            Expires  => Now + Ada.Real_Time.Seconds (43_200));
      end Create;

      function Valid
        (Token : String; Now : Ada.Real_Time.Time) return Boolean
      is
      begin
         if Token'Length /= Token_Length then
            return False;
         end if;
         for Value of Entries loop
            if Value.Occupied and then Value.Expires > Now
              and then Equal (Value.Token, Token)
            then
               return True;
            end if;
         end loop;
         return False;
      end Valid;

      procedure Revoke (Token : String) is
      begin
         if Token'Length /= Token_Length then
            return;
         end if;
         for Value of Entries loop
            if Value.Occupied and then Equal (Value.Token, Token) then
               Flyology_Object_Storage_Server_Credentials.Wipe (Value.Token);
               Value.Occupied := False;
            end if;
         end loop;
      end Revoke;
   end Store;
end Flyology_Object_Storage_Server_Sessions;
