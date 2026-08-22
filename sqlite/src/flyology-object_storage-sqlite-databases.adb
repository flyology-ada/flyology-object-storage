with Interfaces.C;
with Interfaces.C.Strings;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Flyology.Object_Storage.SQLite.C;

package body Flyology.Object_Storage.SQLite.Databases is

   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;
   use type Interfaces.C.unsigned_long_long;
   use type System.Address;

   package C renames Flyology.Object_Storage.SQLite.C;
   package CS renames Interfaces.C.Strings;
   package Byte_Pointers is new System.Address_To_Access_Conversions
     (Interfaces.C.unsigned_char);

   SQLite_OK   : constant Interfaces.C.int := 0;
   SQLite_Row  : constant Interfaces.C.int := 100;
   SQLite_Done : constant Interfaces.C.int := 101;
   SQLite_Null : constant Interfaces.C.int := 5;

   Open_Read_Write : constant Interfaces.C.int := 2;
   Open_Create     : constant Interfaces.C.int := 4;
   Open_URI        : constant Interfaces.C.int := 64;
   Open_Full_Mutex : constant Interfaces.C.int := 65_536;

   SQLite_UTF8 : constant Interfaces.C.unsigned_char := 1;
   Transient_Destructor : constant System.Address :=
     System.Storage_Elements.To_Address
       (System.Storage_Elements.Integer_Address'Last);

   function Error_Message
     (Database : System.Address; Code : Interfaces.C.int) return String
   is
   begin
      if Database = System.Null_Address then
         return "SQLite error" & Interfaces.C.int'Image (Code);
      else
         return CS.Value (C.Errmsg (Database));
      end if;
   end Error_Message;

   procedure Check
     (Code : Interfaces.C.int; Database : System.Address)
   is
   begin
      if Code /= SQLite_OK then
         raise SQLite_Error with Error_Message (Database, Code);
      end if;
   end Check;

   procedure Check_Prepared (Item : Statement) is
   begin
      if Item.Resource.State = Unprepared
        or else Item.Resource.Handle = System.Null_Address
      then
         raise SQLite_Error with "statement is not prepared";
      end if;
   end Check_Prepared;

   procedure Check_Bindable (Item : Statement) is
   begin
      Check_Prepared (Item);
      if Item.Resource.State /= Prepared then
         raise SQLite_Error with "statement must be reset before binding";
      end if;
   end Check_Bindable;

   procedure Check_Bind_Index (Item : Statement; Index : Positive) is
   begin
      Check_Bindable (Item);
      if Interfaces.C.int (Index) >
        C.Bind_Parameter_Count (Item.Resource.Handle)
      then
         raise SQLite_Error with "bind parameter index is out of range";
      end if;
   end Check_Bind_Index;

   procedure Check_On_Row (Item : Statement) is
   begin
      Check_Prepared (Item);
      if Item.Resource.State /= On_Row then
         raise SQLite_Error with "statement is not positioned on a row";
      end if;
   end Check_On_Row;

   procedure Check_Column_Index (Item : Statement; Index : Natural) is
   begin
      Check_On_Row (Item);
      if Interfaces.C.int (Index) >= C.Column_Count (Item.Resource.Handle) then
         raise SQLite_Error with "result column index is out of range";
      end if;
   end Check_Column_Index;

   function Exact_Value
     (Address : System.Address; Length : Natural) return String
   is
      Result : String (1 .. Length);
   begin
      for Index in Result'Range loop
         Result (Index) := Character'Val
           (Byte_Pointers.To_Pointer
              (System.Storage_Elements."+"
                 (Address,
                  System.Storage_Elements.Storage_Offset (Index - 1))).all);
      end loop;
      return Result;
   end Exact_Value;

   function Exact_Copy (Value : String) return System.Address is
      Result : constant System.Address := C.Malloc64
        (Interfaces.C.unsigned_long_long (Value'Length) + 1);
   begin
      if Result = System.Null_Address then
         raise Storage_Error with "SQLite could not allocate bound text";
      end if;
      for Index in Value'Range loop
         Byte_Pointers.To_Pointer
           (System.Storage_Elements."+"
              (Result,
               System.Storage_Elements.Storage_Offset
                 (Index - Value'First))).all :=
           Interfaces.C.unsigned_char (Character'Pos (Value (Index)));
      end loop;
      Byte_Pointers.To_Pointer
        (System.Storage_Elements."+"
           (Result,
            System.Storage_Elements.Storage_Offset (Value'Length))).all := 0;
      return Result;
   end Exact_Copy;

   procedure Open
     (Item                : in out Database;
      Path                : String;
      Busy_Timeout_Millis : Natural := 5_000)
   is
      Filename : CS.chars_ptr := CS.New_String (Path);
      Handle   : aliased System.Address := System.Null_Address;
      Code     : Interfaces.C.int;
   begin
      if Is_Open (Item) then
         CS.Free (Filename);
         raise SQLite_Error with "database is already open";
      end if;
      Code := C.Open_V2
        (Filename,
         Handle'Access,
         Open_Read_Write + Open_Create + Open_URI + Open_Full_Mutex,
         CS.Null_Ptr);
      CS.Free (Filename);
      if Code /= SQLite_OK then
         declare
            Message : constant String := Error_Message (Handle, Code);
            Ignored : Interfaces.C.int;
         begin
            if Handle /= System.Null_Address then
               Ignored := C.Close_V2 (Handle);
               pragma Unreferenced (Ignored);
            end if;
            raise SQLite_Error with Message;
         end;
      end if;
      Item.Resource.Handle := Handle;
      Check
        (C.Extended_Result_Codes (Item.Resource.Handle, 1),
         Item.Resource.Handle);
      Check
        (C.Busy_Timeout
           (Item.Resource.Handle, Interfaces.C.int (Busy_Timeout_Millis)),
         Item.Resource.Handle);
   exception
      when others =>
         if Filename /= CS.Null_Ptr then
            CS.Free (Filename);
         end if;
         raise;
   end Open;

   procedure Close (Item : in out Database) is
      Code : Interfaces.C.int;
   begin
      if Item.Resource.Handle /= System.Null_Address then
         Code := C.Close_V2 (Item.Resource.Handle);
         if Code /= SQLite_OK then
            raise SQLite_Error with Error_Message (Item.Resource.Handle, Code);
         end if;
         Item.Resource.Handle := System.Null_Address;
      end if;
   end Close;

   overriding procedure Finalize (Item : in out Database_Resource) is
      Ignored : Interfaces.C.int;
   begin
      if Item.Handle /= System.Null_Address then
         Ignored := C.Close_V2 (Item.Handle);
         pragma Unreferenced (Ignored);
         Item.Handle := System.Null_Address;
      end if;
   end Finalize;

   function Is_Open (Item : Database) return Boolean is
     (Item.Resource.Handle /= System.Null_Address);

   function Changes (Item : Database) return Long_Long_Integer is
   begin
      if not Is_Open (Item) then
         raise SQLite_Error with "database is closed";
      end if;
      return Long_Long_Integer (C.Changes64 (Item.Resource.Handle));
   end Changes;

   procedure Execute (Item : in out Database; SQL : String) is
      Text  : CS.chars_ptr := CS.New_String (SQL);
      Error : aliased CS.chars_ptr := CS.Null_Ptr;
      Code  : Interfaces.C.int;
   begin
      if not Is_Open (Item) then
         CS.Free (Text);
         raise SQLite_Error with "database is closed";
      end if;
      Code := C.Exec
        (Item.Resource.Handle, Text, System.Null_Address, System.Null_Address,
         Error'Access);
      CS.Free (Text);
      if Code /= SQLite_OK then
         declare
            Message : constant String :=
              (if Error = CS.Null_Ptr
               then Error_Message (Item.Resource.Handle, Code)
               else CS.Value (Error));
         begin
            if Error /= CS.Null_Ptr then
               C.Free (Error);
               Error := CS.Null_Ptr;
            end if;
            raise SQLite_Error with Message;
         end;
      end if;
   exception
      when others =>
         if Text /= CS.Null_Ptr then
            CS.Free (Text);
         end if;
         if Error /= CS.Null_Ptr then
            C.Free (Error);
         end if;
         raise;
   end Execute;

   procedure Begin_Transaction
     (Item : in out Database; Mode : Transaction_Mode := Immediate)
   is
   begin
      Execute
        (Item,
         (case Mode is
            when Deferred  => "BEGIN DEFERRED",
            when Immediate => "BEGIN IMMEDIATE",
            when Exclusive => "BEGIN EXCLUSIVE"));
   end Begin_Transaction;

   procedure Commit (Item : in out Database) is
   begin
      Execute (Item, "COMMIT");
   end Commit;

   procedure Rollback (Item : in out Database) is
   begin
      Execute (Item, "ROLLBACK");
   end Rollback;

   procedure Prepare
     (Item : in out Statement;
      On_Database : Database;
      SQL : String)
   is
      Text   : CS.chars_ptr := CS.New_String (SQL);
      Handle : aliased System.Address := System.Null_Address;
      Code   : Interfaces.C.int;
   begin
      if Item.Resource.Handle /= System.Null_Address then
         CS.Free (Text);
         raise SQLite_Error with "statement is already prepared";
      elsif not Is_Open (On_Database) then
         CS.Free (Text);
         raise SQLite_Error with "database is closed";
      end if;
      Code := C.Prepare_V3
        (On_Database.Resource.Handle,
         Text,
         Interfaces.C.int (SQL'Length),
         0,
         Handle'Access,
         System.Null_Address);
      CS.Free (Text);
      Check (Code, On_Database.Resource.Handle);
      if Handle = System.Null_Address then
         raise SQLite_Error with "SQL did not contain a statement";
      end if;
      Item.Resource.Handle := Handle;
      Item.Resource.Database := On_Database.Resource.Handle;
      Item.Resource.State := Prepared;
   exception
      when others =>
         if Text /= CS.Null_Ptr then
            CS.Free (Text);
         end if;
         raise;
   end Prepare;

   procedure Bind_Null
     (Item : in out Statement; Index : Positive)
   is
   begin
      Check_Bind_Index (Item, Index);
      Check
        (C.Bind_Null (Item.Resource.Handle, Interfaces.C.int (Index)),
         Item.Resource.Database);
   end Bind_Null;

   procedure Bind
     (Item : in out Statement; Index : Positive; Value : Long_Long_Integer)
   is
   begin
      Check_Bind_Index (Item, Index);
      Check
        (C.Bind_Int64
           (Item.Resource.Handle, Interfaces.C.int (Index),
            Interfaces.C.long_long (Value)),
         Item.Resource.Database);
   end Bind;

   procedure Bind
     (Item : in out Statement; Index : Positive; Value : String)
   is
      Text : System.Address := Exact_Copy (Value);
      Code : Interfaces.C.int;
   begin
      Check_Bind_Index (Item, Index);
      Code := C.Bind_Text64
        (Item.Resource.Handle,
         Interfaces.C.int (Index),
         Text,
         Interfaces.C.unsigned_long_long (Value'Length),
         Transient_Destructor,
         SQLite_UTF8);
      C.Free (Text);
      Text := System.Null_Address;
      Check (Code, Item.Resource.Database);
   exception
      when others =>
         if Text /= System.Null_Address then
            C.Free (Text);
         end if;
         raise;
   end Bind;

   procedure Bind_Bytes
     (Item : in out Statement; Index : Positive; Value : String)
   is
      Data : System.Address := Exact_Copy (Value);
      Code : Interfaces.C.int;
   begin
      Check_Bind_Index (Item, Index);
      Code := C.Bind_Blob64
        (Item.Resource.Handle,
         Interfaces.C.int (Index),
         Data,
         Interfaces.C.unsigned_long_long (Value'Length),
         Transient_Destructor);
      C.Free (Data);
      Data := System.Null_Address;
      Check (Code, Item.Resource.Database);
   exception
      when others =>
         if Data /= System.Null_Address then
            C.Free (Data);
         end if;
         raise;
   end Bind_Bytes;

   function Step (Item : in out Statement) return Step_Result is
      Code : Interfaces.C.int;
   begin
      Check_Prepared (Item);
      if Item.Resource.State = Exhausted then
         raise SQLite_Error with "statement must be reset after completion";
      end if;
      Code := C.Step (Item.Resource.Handle);
      if Code = SQLite_Row then
         Item.Resource.State := On_Row;
         return Row;
      elsif Code = SQLite_Done then
         Item.Resource.State := Exhausted;
         return Done;
      else
         raise SQLite_Error with Error_Message (Item.Resource.Database, Code);
      end if;
   end Step;

   procedure Reset (Item : in out Statement) is
   begin
      Check_Prepared (Item);
      Check (C.Reset (Item.Resource.Handle), Item.Resource.Database);
      Check (C.Clear_Bindings (Item.Resource.Handle), Item.Resource.Database);
      Item.Resource.State := Prepared;
   end Reset;

   function Column_Is_Null
     (Item : Statement; Index : Natural) return Boolean
   is
   begin
      Check_Column_Index (Item, Index);
      return C.Column_Type (Item.Resource.Handle, Interfaces.C.int (Index)) =
        SQLite_Null;
   end Column_Is_Null;

   function Column
     (Item : Statement; Index : Natural) return Long_Long_Integer
   is
   begin
      Check_Column_Index (Item, Index);
      return Long_Long_Integer
        (C.Column_Int64 (Item.Resource.Handle, Interfaces.C.int (Index)));
   end Column;

   function Column
     (Item : Statement; Index : Natural) return String
   is
      Text  : System.Address;
      Bytes : Interfaces.C.int;
   begin
      Check_Column_Index (Item, Index);
      Text := C.Column_Text (Item.Resource.Handle, Interfaces.C.int (Index));
      Bytes := C.Column_Bytes (Item.Resource.Handle, Interfaces.C.int (Index));
      if Text = System.Null_Address or else Bytes = 0 then
         return "";
      elsif Bytes < 0 then
         raise SQLite_Error with "SQLite returned a negative text length";
      end if;
      return Exact_Value (Text, Natural (Bytes));
   end Column;

   function Column_Bytes
     (Item : Statement; Index : Natural) return String
   is
      Data  : System.Address;
      Bytes : Interfaces.C.int;
   begin
      Check_Column_Index (Item, Index);
      Data := C.Column_Blob (Item.Resource.Handle, Interfaces.C.int (Index));
      Bytes := C.Column_Bytes (Item.Resource.Handle, Interfaces.C.int (Index));
      if Data = System.Null_Address or else Bytes = 0 then
         return "";
      elsif Bytes < 0 then
         raise SQLite_Error with "SQLite returned a negative blob length";
      end if;
      return Exact_Value (Data, Natural (Bytes));
   end Column_Bytes;

   overriding procedure Finalize (Item : in out Statement_Resource) is
      Ignored : Interfaces.C.int;
   begin
      if Item.Handle /= System.Null_Address then
         Ignored := C.Finalize (Item.Handle);
         pragma Unreferenced (Ignored);
         Item.Handle := System.Null_Address;
         Item.Database := System.Null_Address;
         Item.State := Unprepared;
      end if;
   end Finalize;

end Flyology.Object_Storage.SQLite.Databases;
