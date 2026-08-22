with Ada.Real_Time;

package Flyology_Object_Storage_Server_Sessions is
   Token_Length : constant := 64;
   Capacity : constant := 64;

   type Session_Entry is record
      Occupied : Boolean := False;
      Token : String (1 .. Token_Length) := (others => ' ');
      Expires : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
   end record;
   type Entry_Array is
     array (Positive range 1 .. Capacity) of Session_Entry;

   protected type Store is
      procedure Create (Token : String; Now : Ada.Real_Time.Time);
      function Valid (Token : String; Now : Ada.Real_Time.Time) return Boolean;
      procedure Revoke (Token : String);
   private
      Entries : Entry_Array;
   end Store;
end Flyology_Object_Storage_Server_Sessions;
