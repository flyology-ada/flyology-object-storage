with Ada.Finalization;
with System;

--  Controlled, exception-safe Ada ownership around the vendored SQLite API.
package Flyology.Object_Storage.SQLite.Databases is

   SQLite_Error : exception;

   type Database is limited private;

   procedure Open
     (Item                : in out Database;
      Path                : String;
      Busy_Timeout_Millis : Natural := 5_000);

   procedure Close (Item : in out Database);
   function Is_Open (Item : Database) return Boolean;
   function Changes (Item : Database) return Long_Long_Integer;
   procedure Execute (Item : in out Database; SQL : String);

   type Transaction_Mode is (Deferred, Immediate, Exclusive);
   procedure Begin_Transaction
     (Item : in out Database; Mode : Transaction_Mode := Immediate);
   procedure Commit (Item : in out Database);
   procedure Rollback (Item : in out Database);

   type Statement is limited private;

   procedure Prepare
     (Item : in out Statement;
      On_Database : Database;
      SQL : String);
   procedure Bind_Null
     (Item : in out Statement; Index : Positive);
   procedure Bind
     (Item : in out Statement; Index : Positive; Value : Long_Long_Integer);
   procedure Bind
     (Item : in out Statement; Index : Positive; Value : String);
   procedure Bind_Bytes
     (Item : in out Statement; Index : Positive; Value : String);

   type Step_Result is (Row, Done);
   function Step (Item : in out Statement) return Step_Result;
   procedure Reset (Item : in out Statement);
   function Column_Is_Null
     (Item : Statement; Index : Natural) return Boolean;
   function Column
     (Item : Statement; Index : Natural) return Long_Long_Integer;
   function Column
     (Item : Statement; Index : Natural) return String;
   function Column_Bytes
     (Item : Statement; Index : Natural) return String;

private
   type Statement_State is (Unprepared, Prepared, On_Row, Exhausted);

   type Database_Resource is
     limited new Ada.Finalization.Limited_Controlled with record
      Handle : System.Address := System.Null_Address;
   end record;

   overriding procedure Finalize (Item : in out Database_Resource);

   type Database is limited record
      Resource : Database_Resource;
   end record;

   type Statement_Resource is
     limited new Ada.Finalization.Limited_Controlled with record
      Handle   : System.Address := System.Null_Address;
      Database : System.Address := System.Null_Address;
      State    : Statement_State := Unprepared;
   end record;

   overriding procedure Finalize (Item : in out Statement_Resource);

   type Statement is limited record
      Resource : Statement_Resource;
   end record;

end Flyology.Object_Storage.SQLite.Databases;
