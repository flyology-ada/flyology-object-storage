with Interfaces.C;
with Interfaces.C.Strings;
with System;

private package Flyology.Object_Storage.SQLite.C is

   subtype Handle is System.Address;

   function Libversion return Interfaces.C.Strings.chars_ptr
     with Import, Convention => C, External_Name => "sqlite3_libversion";

   function Source_ID return Interfaces.C.Strings.chars_ptr
     with Import, Convention => C, External_Name => "sqlite3_sourceid";

   function Threadsafe return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_threadsafe";

   function Open_V2
     (Filename : Interfaces.C.Strings.chars_ptr;
      Database : access Handle;
      Flags    : Interfaces.C.int;
      VFS      : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_open_v2";

   function Close_V2 (Database : Handle) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_close_v2";

   function Errmsg
     (Database : Handle) return Interfaces.C.Strings.chars_ptr
     with Import, Convention => C, External_Name => "sqlite3_errmsg";

   function Extended_Result_Codes
     (Database : Handle; Enabled : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "sqlite3_extended_result_codes";

   function Busy_Timeout
     (Database : Handle; Milliseconds : Interfaces.C.int)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_busy_timeout";

   function Exec
     (Database : Handle;
      SQL      : Interfaces.C.Strings.chars_ptr;
      Callback : System.Address;
      Context  : System.Address;
      Error    : access Interfaces.C.Strings.chars_ptr)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_exec";

   procedure Free (Value : Interfaces.C.Strings.chars_ptr)
     with Import, Convention => C, External_Name => "sqlite3_free";

   function Malloc64
     (Bytes : Interfaces.C.unsigned_long_long) return System.Address
     with Import, Convention => C, External_Name => "sqlite3_malloc64";

   procedure Free (Value : System.Address)
     with Import, Convention => C, External_Name => "sqlite3_free";

   function Prepare_V3
     (Database : Handle;
      SQL      : Interfaces.C.Strings.chars_ptr;
      Bytes    : Interfaces.C.int;
      Flags    : Interfaces.C.unsigned;
      Statement : access Handle;
      Tail      : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_prepare_v3";

   function Finalize (Statement : Handle) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_finalize";

   function Step (Statement : Handle) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_step";

   function Reset (Statement : Handle) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_reset";

   function Clear_Bindings (Statement : Handle) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_clear_bindings";

   function Bind_Parameter_Count (Statement : Handle) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "sqlite3_bind_parameter_count";

   function Bind_Null
     (Statement : Handle; Index : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_bind_null";

   function Bind_Int64
     (Statement : Handle;
      Index     : Interfaces.C.int;
      Value     : Interfaces.C.long_long) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_bind_int64";

   function Bind_Text64
     (Statement  : Handle;
      Index      : Interfaces.C.int;
      Value      : System.Address;
      Bytes      : Interfaces.C.unsigned_long_long;
      Destructor : System.Address;
      Encoding   : Interfaces.C.unsigned_char) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_bind_text64";

   function Bind_Blob64
     (Statement  : Handle;
      Index      : Interfaces.C.int;
      Value      : System.Address;
      Bytes      : Interfaces.C.unsigned_long_long;
      Destructor : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_bind_blob64";

   function Column_Type
     (Statement : Handle; Index : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_column_type";

   function Column_Count (Statement : Handle) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_column_count";

   function Column_Int64
     (Statement : Handle; Index : Interfaces.C.int)
      return Interfaces.C.long_long
     with Import, Convention => C, External_Name => "sqlite3_column_int64";

   function Column_Text
     (Statement : Handle; Index : Interfaces.C.int)
      return System.Address
     with Import, Convention => C, External_Name => "sqlite3_column_text";

   function Column_Blob
     (Statement : Handle; Index : Interfaces.C.int)
      return System.Address
     with Import, Convention => C, External_Name => "sqlite3_column_blob";

   function Column_Bytes
     (Statement : Handle; Index : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "sqlite3_column_bytes";

   function Changes64 (Database : Handle) return Interfaces.C.long_long
     with Import, Convention => C, External_Name => "sqlite3_changes64";

end Flyology.Object_Storage.SQLite.C;
