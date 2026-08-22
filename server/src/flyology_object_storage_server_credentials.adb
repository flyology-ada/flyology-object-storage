with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.SHA256;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Flyology_Object_Storage_Server_Credentials is
   use type Interfaces.C.int;
   use type Interfaces.Unsigned_8;
   use type Ada.Streams.Stream_Element_Offset;

   Work_Factor : constant Positive := 600_000;
   File_Prefix : constant String := "flyology-admin-v1:admin:600000:";

   function Random_Bytes
     (Address : System.Address; Length : Interfaces.C.size_t)
      return Interfaces.C.int
   with Import, Convention => C,
        External_Name => "flyology_object_storage_server_random";

   function Publish
     (Path : Interfaces.C.Strings.chars_ptr;
      Data : System.Address;
      Length : Interfaces.C.size_t) return Interfaces.C.int
   with Import, Convention => C,
        External_Name =>
          "flyology_object_storage_server_publish_credentials";

   function Secure_File
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   with Import, Convention => C,
        External_Name =>
          "flyology_object_storage_server_credentials_secure";

   procedure Secure_Erase
     (Address : System.Address; Bytes : Interfaces.C.size_t)
   with Import, Convention => C,
        External_Name => "flyology_object_storage_secure_erase";

   procedure Wipe (Value : in out String) is
   begin
      if Value'Length > 0 then
         Secure_Erase (Value'Address, Interfaces.C.size_t (Value'Length));
      end if;
   end Wipe;

   function Hex (Value : String) return String is
      Alphabet : constant String := "0123456789abcdef";
      Result : String (1 .. Value'Length * 2);
   begin
      for Offset in 0 .. Value'Length - 1 loop
         declare
            Byte : constant Natural :=
              Character'Pos (Value (Value'First + Offset));
         begin
            Result (Result'First + Offset * 2) :=
              Alphabet (Alphabet'First + Byte / 16);
            Result (Result'First + Offset * 2 + 1) :=
              Alphabet (Alphabet'First + Byte mod 16);
         end;
      end loop;
      return Result;
   end Hex;

   function Nibble (Value : Character) return Natural is
     (case Value is
         when '0' .. '9' => Character'Pos (Value) - Character'Pos ('0'),
         when 'a' .. 'f' => Character'Pos (Value) - Character'Pos ('a') + 10,
         when others => raise Constraint_Error with
           "invalid administrator credential hex");

   function Decode_Hex (Value : String) return String is
      Result : String (1 .. Value'Length / 2);
   begin
      if Value'Length mod 2 /= 0 then
         raise Constraint_Error with "invalid administrator credential hex";
      end if;
      for Offset in 0 .. Result'Length - 1 loop
         Result (Result'First + Offset) := Character'Val
           (16 * Nibble (Value (Value'First + Offset * 2)) +
            Nibble (Value (Value'First + Offset * 2 + 1)));
      end loop;
      return Result;
   end Decode_Hex;

   function Binary_String
     (Value : GNAT.SHA256.Binary_Message_Digest) return String
   is
      Result : String (1 .. Natural (Value'Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Character'Val
           (Value
              (Value'First +
               Ada.Streams.Stream_Element_Offset (Index - Result'First)));
      end loop;
      return Result;
   end Binary_String;

   function HMAC (Key, Data : String) return String is
      Context : GNAT.SHA256.Context := GNAT.SHA256.HMAC_Initial_Context (Key);
      Result : String (1 .. Hash_Length);
   begin
      GNAT.SHA256.Update (Context, Data);
      Result := Binary_String (GNAT.SHA256.Digest (Context));
      Secure_Erase
        (Context'Address,
         Interfaces.C.size_t
           ((Context'Size + System.Storage_Unit - 1) / System.Storage_Unit));
      return Result;
   exception
      when others =>
         Secure_Erase
           (Context'Address,
            Interfaces.C.size_t
              ((Context'Size + System.Storage_Unit - 1) /
               System.Storage_Unit));
         raise;
   end HMAC;

   function Derive
     (Password, Salt : String; Iterations : Positive) return String
   is
      Block : constant String :=
        Salt & Character'Val (0) & Character'Val (0) & Character'Val (0) &
        Character'Val (1);
      U : String (1 .. Hash_Length) := HMAC (Password, Block);
      Result : String (1 .. Hash_Length) := U;
   begin
      for Iteration in 2 .. Iterations loop
         declare
            Next : String (1 .. Hash_Length) := HMAC (Password, U);
         begin
            for Index in Result'Range loop
               Result (Index) := Character'Val
                 (Interfaces.Unsigned_8 (Character'Pos (Result (Index))) xor
                  Interfaces.Unsigned_8 (Character'Pos (Next (Index))));
            end loop;
            Wipe (U);
            U := Next;
            Wipe (Next);
         end;
      end loop;
      Wipe (U);
      return Result;
   exception
      when others =>
         Wipe (U);
         Wipe (Result);
         raise;
   end Derive;

   function Constant_Time_Equal (Left, Right : String) return Boolean is
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
   end Constant_Time_Equal;

   function Cryptographic_Self_Test return Boolean is
      Expected : constant String :=
        "120fb6cffcf8b32c43e7225256c4f837a" &
        "86548c92ccc35480805987cb70be17b";
      Result : String (1 .. Hash_Length) := Derive ("password", "salt", 1);
      Passed : constant Boolean :=
        Constant_Time_Equal (Hex (Result), Expected);
   begin
      Wipe (Result);
      return Passed;
   end Cryptographic_Self_Test;

   function Random_Token return String is
      Bytes : String (1 .. 32) := (others => Character'Val (0));
   begin
      if Random_Bytes (Bytes'Address, Bytes'Length) /= 0 then
         raise Program_Error with "operating-system random source failed";
      end if;
      declare
         Result : constant String := Hex (Bytes);
      begin
         Wipe (Bytes);
         return Result;
      end;
   exception
      when others =>
         Wipe (Bytes);
         raise;
   end Random_Token;

   function Load (Path : String) return Credential is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      File : Ada.Text_IO.File_Type;
   begin
      if Secure_File (C_Path) /= 1 then
         raise Constraint_Error with
           "administrator credential file must be owner-owned mode 0600";
      end if;
      Interfaces.C.Strings.Free (C_Path);
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      declare
         Line : constant String := Ada.Text_IO.Get_Line (File);
         Separator : constant Natural :=
           Ada.Strings.Fixed.Index (Line, ":", From => File_Prefix'Length + 1);
      begin
         if Ada.Text_IO.End_Of_File (File) = False
           or else Line'Length /= File_Prefix'Length + 64 + 1 + 64
           or else Line (Line'First .. Line'First + File_Prefix'Length - 1) /=
             File_Prefix
           or else Separator /= Line'First + File_Prefix'Length + 64
         then
            raise Constraint_Error with
              "invalid administrator credential file";
         end if;
         declare
            Salt_Hex : constant String :=
              Line
                (Line'First + File_Prefix'Length .. Separator - 1);
            Hash_Hex : constant String := Line (Separator + 1 .. Line'Last);
            Result : constant Credential :=
              (Salt       => Decode_Hex (Salt_Hex),
               Hash       => Decode_Hex (Hash_Hex),
               Iterations => Work_Factor);
         begin
            Ada.Text_IO.Close (File);
            return Result;
         end;
      end;
   exception
      when others =>
         Interfaces.C.Strings.Free (C_Path);
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Load;

   procedure Load_Or_Bootstrap
     (Path      : String;
      Value     : out Credential;
      Generated : out Boolean;
      Password  : out String)
   is
      Salt : String (1 .. Salt_Length) := (others => Character'Val (0));
      Password_Bytes : String (1 .. Generated_Password_Length / 2) :=
        (others => Character'Val (0));
      Derived : String (1 .. Hash_Length) := (others => Character'Val (0));
   begin
      Generated := False;
      Password := (others => ' ');
      if Ada.Directories.Exists (Path) then
         Value := Load (Path);
         Generated := False;
         return;
      end if;

      declare
         Parent : constant String :=
           Ada.Directories.Containing_Directory (Path);
      begin
         if not Ada.Directories.Exists (Parent) then
            Ada.Directories.Create_Path (Parent);
         end if;
      end;
      if Random_Bytes (Salt'Address, Salt'Length) /= 0
        or else Random_Bytes
          (Password_Bytes'Address, Password_Bytes'Length) /= 0
      then
         raise Program_Error with "operating-system random source failed";
      end if;
      Password := Hex (Password_Bytes);
      Derived := Derive (Password, Salt, Work_Factor);
      declare
         Document : aliased constant String :=
           File_Prefix & Hex (Salt) & ":" & Hex (Derived) & ASCII.LF;
         C_Path : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String (Path);
         Outcome : Interfaces.C.int;
      begin
         Outcome := Publish
           (C_Path, Document'Address, Interfaces.C.size_t (Document'Length));
         Interfaces.C.Strings.Free (C_Path);
         if Outcome in 1 .. 2 then
            Value :=
              (Salt => Salt, Hash => Derived, Iterations => Work_Factor);
            Generated := True;
         elsif Outcome = 0 then
            Wipe (Password);
            Value := Load (Path);
            Generated := False;
         else
            raise Program_Error with
              "could not publish administrator credential file";
         end if;
      exception
         when others =>
            Interfaces.C.Strings.Free (C_Path);
            raise;
      end;
      Wipe (Salt);
      Wipe (Password_Bytes);
      Wipe (Derived);
   exception
      when others =>
         Wipe (Salt);
         Wipe (Password_Bytes);
         Wipe (Derived);
         Wipe (Password);
         raise;
   end Load_Or_Bootstrap;

   function Verify
     (Value : Credential; User, Password : String) return Boolean
   is
   begin
      if User'Length /= Username'Length
        or else not Constant_Time_Equal (User, Username)
        or else Password'Length not in 1 .. 64
      then
         return False;
      end if;
      declare
         Candidate : String (1 .. Hash_Length) :=
           Derive (Password, Value.Salt, Value.Iterations);
         Matches : constant Boolean :=
           Constant_Time_Equal (Candidate, Value.Hash);
      begin
         Wipe (Candidate);
         return Matches;
      end;
   end Verify;
end Flyology_Object_Storage_Server_Credentials;
