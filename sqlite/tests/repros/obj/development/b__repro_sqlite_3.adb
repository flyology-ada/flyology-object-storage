pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_sqlite_3.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_sqlite_3.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E010 : Short_Integer; pragma Import (Ada, E010, "ada__exceptions_E");
   E015 : Short_Integer; pragma Import (Ada, E015, "system__soft_links_E");
   E026 : Short_Integer; pragma Import (Ada, E026, "system__exception_table_E");
   E027 : Short_Integer; pragma Import (Ada, E027, "system__exceptions_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__soft_links__initialize_E");
   E173 : Short_Integer; pragma Import (Ada, E173, "ada__assertions_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__containers_E");
   E104 : Short_Integer; pragma Import (Ada, E104, "ada__io_exceptions_E");
   E092 : Short_Integer; pragma Import (Ada, E092, "ada__strings_E");
   E108 : Short_Integer; pragma Import (Ada, E108, "ada__strings__utf_encoding_E");
   E256 : Short_Integer; pragma Import (Ada, E256, "gnat_E");
   E055 : Short_Integer; pragma Import (Ada, E055, "interfaces__c_E");
   E328 : Short_Integer; pragma Import (Ada, E328, "interfaces__c__strings_E");
   E057 : Short_Integer; pragma Import (Ada, E057, "system__os_lib_E");
   E116 : Short_Integer; pragma Import (Ada, E116, "ada__tags_E");
   E106 : Short_Integer; pragma Import (Ada, E106, "ada__strings__text_buffers_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "ada__streams_E");
   E156 : Short_Integer; pragma Import (Ada, E156, "system__file_control_block_E");
   E127 : Short_Integer; pragma Import (Ada, E127, "system__finalization_root_E");
   E101 : Short_Integer; pragma Import (Ada, E101, "ada__finalization_E");
   E153 : Short_Integer; pragma Import (Ada, E153, "system__file_io_E");
   E273 : Short_Integer; pragma Import (Ada, E273, "ada__streams__stream_io_E");
   E160 : Short_Integer; pragma Import (Ada, E160, "system__storage_pools_E");
   E265 : Short_Integer; pragma Import (Ada, E265, "system__storage_pools__subpools_E");
   E008 : Short_Integer; pragma Import (Ada, E008, "ada__calendar_E");
   E281 : Short_Integer; pragma Import (Ada, E281, "ada__calendar__delays_E");
   E079 : Short_Integer; pragma Import (Ada, E079, "ada__calendar__time_zones_E");
   E216 : Short_Integer; pragma Import (Ada, E216, "ada__text_io_E");
   E307 : Short_Integer; pragma Import (Ada, E307, "gnat__secure_hashes_E");
   E309 : Short_Integer; pragma Import (Ada, E309, "gnat__secure_hashes__md5_E");
   E305 : Short_Integer; pragma Import (Ada, E305, "gnat__md5_E");
   E316 : Short_Integer; pragma Import (Ada, E316, "gnat__secure_hashes__sha1_E");
   E322 : Short_Integer; pragma Import (Ada, E322, "gnat__secure_hashes__sha2_common_E");
   E320 : Short_Integer; pragma Import (Ada, E320, "gnat__secure_hashes__sha2_32_E");
   E326 : Short_Integer; pragma Import (Ada, E326, "gnat__secure_hashes__sha2_64_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "gnat__sha1_E");
   E318 : Short_Integer; pragma Import (Ada, E318, "gnat__sha256_E");
   E324 : Short_Integer; pragma Import (Ada, E324, "gnat__sha512_E");
   E180 : Short_Integer; pragma Import (Ada, E180, "system__flyology__scheduler_E");
   E162 : Short_Integer; pragma Import (Ada, E162, "ada__real_time_E");
   E094 : Short_Integer; pragma Import (Ada, E094, "ada__strings__maps_E");
   E097 : Short_Integer; pragma Import (Ada, E097, "ada__strings__maps__constants_E");
   E139 : Short_Integer; pragma Import (Ada, E139, "ada__strings__unbounded_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "system__pool_global_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "system__regexp_E");
   E006 : Short_Integer; pragma Import (Ada, E006, "ada__directories_E");
   E241 : Short_Integer; pragma Import (Ada, E241, "system__tasking__initialization_E");
   E231 : Short_Integer; pragma Import (Ada, E231, "system__tasking__protected_objects_E");
   E237 : Short_Integer; pragma Import (Ada, E237, "system__tasking__protected_objects__entries_E");
   E249 : Short_Integer; pragma Import (Ada, E249, "system__tasking__queuing_E");
   E360 : Short_Integer; pragma Import (Ada, E360, "system__flyology__task_results_E");
   E356 : Short_Integer; pragma Import (Ada, E356, "system__tasking__stages_E");
   E255 : Short_Integer; pragma Import (Ada, E255, "flyology__wake_sources_E");
   E228 : Short_Integer; pragma Import (Ada, E228, "flyology__cancellation_E");
   E279 : Short_Integer; pragma Import (Ada, E279, "flyology__operations_E");
   E277 : Short_Integer; pragma Import (Ada, E277, "flyology__io_E");
   E219 : Short_Integer; pragma Import (Ada, E219, "flyology__object_storage_E");
   E295 : Short_Integer; pragma Import (Ada, E295, "flyology__object_storage__s3__core_E");
   E303 : Short_Integer; pragma Import (Ada, E303, "flyology__object_storage__s3__checksum_crc_E");
   E293 : Short_Integer; pragma Import (Ada, E293, "flyology__object_storage__s3__checksum_policy_E");
   E299 : Short_Integer; pragma Import (Ada, E299, "flyology__object_storage__s3__wire_core_E");
   E301 : Short_Integer; pragma Import (Ada, E301, "flyology__object_storage__secrets_E");
   E297 : Short_Integer; pragma Import (Ada, E297, "flyology__object_storage__s3__checksums_E");
   E290 : Short_Integer; pragma Import (Ada, E290, "flyology__object_storage__checksum_engine_E");
   E335 : Short_Integer; pragma Import (Ada, E335, "flyology__object_storage__sqlite_E");
   E344 : Short_Integer; pragma Import (Ada, E344, "flyology__object_storage__sqlite__databases_E");
   E259 : Short_Integer; pragma Import (Ada, E259, "flyology__object_storage__tags_E");
   E226 : Short_Integer; pragma Import (Ada, E226, "flyology__object_storage__backends_E");
   E340 : Short_Integer; pragma Import (Ada, E340, "flyology__object_storage__backends__listing_E");
   E342 : Short_Integer; pragma Import (Ada, E342, "flyology__object_storage__backends__multipart_listing_E");
   E338 : Short_Integer; pragma Import (Ada, E338, "flyology__object_storage__sqlite__catalogs_E");
   E271 : Short_Integer; pragma Import (Ada, E271, "flyology__object_storage__backends__sqlite_E");
   E346 : Short_Integer; pragma Import (Ada, E346, "repro_sqlite_support_E");
   E350 : Short_Integer; pragma Import (Ada, E350, "repro_support_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      E346 := E346 - 1;
      declare
         procedure F1;
         pragma Import (Ada, F1, "repro_sqlite_support__finalize_spec");
      begin
         F1;
      end;
      E271 := E271 - 1;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology__object_storage__backends__sqlite__finalize_spec");
      begin
         F2;
      end;
      E338 := E338 - 1;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__sqlite__catalogs__finalize_spec");
      begin
         F3;
      end;
      E342 := E342 - 1;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__backends__multipart_listing__finalize_spec");
      begin
         F4;
      end;
      E340 := E340 - 1;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__backends__listing__finalize_spec");
      begin
         F5;
      end;
      E226 := E226 - 1;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__backends__finalize_spec");
      begin
         F6;
      end;
      E259 := E259 - 1;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__tags__finalize_spec");
      begin
         F7;
      end;
      E344 := E344 - 1;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology__object_storage__sqlite__databases__finalize_spec");
      begin
         F8;
      end;
      E290 := E290 - 1;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology__object_storage__checksum_engine__finalize_spec");
      begin
         F9;
      end;
      E297 := E297 - 1;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F10;
      end;
      E279 := E279 - 1;
      E277 := E277 - 1;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__io__finalize_spec");
      begin
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__operations__finalize_spec");
      begin
         F12;
      end;
      E255 := E255 - 1;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology__wake_sources__finalize_spec");
      begin
         F13;
      end;
      E237 := E237 - 1;
      declare
         procedure F14;
         pragma Import (Ada, F14, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F14;
      end;
      declare
         procedure F15;
         pragma Import (Ada, F15, "ada__directories__finalize_body");
      begin
         E006 := E006 - 1;
         F15;
      end;
      declare
         procedure F16;
         pragma Import (Ada, F16, "ada__directories__finalize_spec");
      begin
         F16;
      end;
      E158 := E158 - 1;
      declare
         procedure F17;
         pragma Import (Ada, F17, "system__regexp__finalize_spec");
      begin
         F17;
      end;
      E261 := E261 - 1;
      declare
         procedure F18;
         pragma Import (Ada, F18, "system__pool_global__finalize_spec");
      begin
         F18;
      end;
      E139 := E139 - 1;
      declare
         procedure F19;
         pragma Import (Ada, F19, "ada__strings__unbounded__finalize_spec");
      begin
         F19;
      end;
      E324 := E324 - 1;
      declare
         procedure F20;
         pragma Import (Ada, F20, "gnat__sha512__finalize_spec");
      begin
         F20;
      end;
      E318 := E318 - 1;
      declare
         procedure F21;
         pragma Import (Ada, F21, "gnat__sha256__finalize_spec");
      begin
         F21;
      end;
      E314 := E314 - 1;
      declare
         procedure F22;
         pragma Import (Ada, F22, "gnat__sha1__finalize_spec");
      begin
         F22;
      end;
      E305 := E305 - 1;
      declare
         procedure F23;
         pragma Import (Ada, F23, "gnat__md5__finalize_spec");
      begin
         F23;
      end;
      E216 := E216 - 1;
      declare
         procedure F24;
         pragma Import (Ada, F24, "ada__text_io__finalize_spec");
      begin
         F24;
      end;
      E265 := E265 - 1;
      declare
         procedure F25;
         pragma Import (Ada, F25, "system__storage_pools__subpools__finalize_spec");
      begin
         F25;
      end;
      E273 := E273 - 1;
      declare
         procedure F26;
         pragma Import (Ada, F26, "ada__streams__stream_io__finalize_spec");
      begin
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "system__file_io__finalize_body");
      begin
         E153 := E153 - 1;
         F27;
      end;
      declare
         procedure Reraise_Library_Exception_If_Any;
            pragma Import (Ada, Reraise_Library_Exception_If_Any, "__gnat_reraise_library_exception_if_any");
      begin
         Reraise_Library_Exception_If_Any;
      end;
   end finalize_library;

   procedure adafinal is
      procedure s_stalib_adafinal;
      pragma Import (Ada, s_stalib_adafinal, "system__standard_library__adafinal");

      procedure Runtime_Finalize;
      pragma Import (C, Runtime_Finalize, "__gnat_runtime_finalize");

   begin
      if not Is_Elaborated then
         return;
      end if;
      Is_Elaborated := False;
      Runtime_Finalize;
      s_stalib_adafinal;
   end adafinal;

   type No_Param_Proc is access procedure;
   pragma Favor_Top_Level (No_Param_Proc);

   procedure adainit is
      Main_Priority : Integer;
      pragma Import (C, Main_Priority, "__gl_main_priority");
      Time_Slice_Value : Integer;
      pragma Import (C, Time_Slice_Value, "__gl_time_slice_val");
      WC_Encoding : Character;
      pragma Import (C, WC_Encoding, "__gl_wc_encoding");
      Locking_Policy : Character;
      pragma Import (C, Locking_Policy, "__gl_locking_policy");
      Queuing_Policy : Character;
      pragma Import (C, Queuing_Policy, "__gl_queuing_policy");
      Task_Dispatching_Policy : Character;
      pragma Import (C, Task_Dispatching_Policy, "__gl_task_dispatching_policy");
      Priority_Specific_Dispatching : System.Address;
      pragma Import (C, Priority_Specific_Dispatching, "__gl_priority_specific_dispatching");
      Num_Specific_Dispatching : Integer;
      pragma Import (C, Num_Specific_Dispatching, "__gl_num_specific_dispatching");
      Main_CPU : Integer;
      pragma Import (C, Main_CPU, "__gl_main_cpu");
      Interrupt_States : System.Address;
      pragma Import (C, Interrupt_States, "__gl_interrupt_states");
      Num_Interrupt_States : Integer;
      pragma Import (C, Num_Interrupt_States, "__gl_num_interrupt_states");
      Unreserve_All_Interrupts : Integer;
      pragma Import (C, Unreserve_All_Interrupts, "__gl_unreserve_all_interrupts");
      Exception_Tracebacks : Integer;
      pragma Import (C, Exception_Tracebacks, "__gl_exception_tracebacks");
      Exception_Tracebacks_Symbolic : Integer;
      pragma Import (C, Exception_Tracebacks_Symbolic, "__gl_exception_tracebacks_symbolic");
      Detect_Blocking : Integer;
      pragma Import (C, Detect_Blocking, "__gl_detect_blocking");
      Default_Stack_Size : Integer;
      pragma Import (C, Default_Stack_Size, "__gl_default_stack_size");
      Default_Secondary_Stack_Size : System.Parameters.Size_Type;
      pragma Import (C, Default_Secondary_Stack_Size, "__gnat_default_ss_size");
      Bind_Env_Addr : System.Address;
      pragma Import (C, Bind_Env_Addr, "__gl_bind_env_addr");
      Interrupts_Default_To_System : Integer;
      pragma Import (C, Interrupts_Default_To_System, "__gl_interrupts_default_to_system");

      procedure Runtime_Initialize (Install_Handler : Integer);
      pragma Import (C, Runtime_Initialize, "__gnat_runtime_initialize");

      procedure Tasking_Runtime_Initialize;
      pragma Import (C, Tasking_Runtime_Initialize, "__gnat_tasking_runtime_initialize");

      Finalize_Library_Objects : No_Param_Proc;
      pragma Import (C, Finalize_Library_Objects, "__gnat_finalize_library_objects");
      Binder_Sec_Stacks_Count : Natural;
      pragma Import (Ada, Binder_Sec_Stacks_Count, "__gnat_binder_ss_count");
      Default_Sized_SS_Pool : System.Address;
      pragma Import (Ada, Default_Sized_SS_Pool, "__gnat_default_ss_pool");

   begin
      if Is_Elaborated then
         return;
      end if;
      Is_Elaborated := True;
      Main_Priority := -1;
      Time_Slice_Value := -1;
      WC_Encoding := 'b';
      Locking_Policy := ' ';
      Queuing_Policy := ' ';
      Task_Dispatching_Policy := ' ';
      System.Restrictions.Run_Time_Restrictions :=
        (Set =>
          (False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, True, False, False, False, False, 
           False, False, False, False, False, False, False, False, 
           False, False, False, False),
         Value => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
         Violated =>
          (True, False, False, False, True, True, False, False, 
           True, False, False, True, True, True, True, False, 
           False, False, False, True, False, False, True, True, 
           False, True, True, False, True, True, True, True, 
           False, True, False, False, False, True, True, False, 
           True, True, False, True, True, True, True, False, 
           True, False, True, True, False, False, True, False, 
           True, False, False, False, False, True, False, False, 
           False, True, False, True, True, True, False, False, 
           True, False, True, True, True, False, True, True, 
           False, True, True, True, True, False, False, False, 
           True, False, False, False, False, True, False, True, 
           True, False, True, False),
         Count => (0, 0, 0, 1, 0, 1, 1, 0, 4, 0),
         Unknown => (False, False, False, False, False, False, True, False, True, False));
      Priority_Specific_Dispatching :=
        Local_Priority_Specific_Dispatching'Address;
      Num_Specific_Dispatching := 0;
      Main_CPU := -1;
      Interrupt_States := Local_Interrupt_States'Address;
      Num_Interrupt_States := 0;
      Unreserve_All_Interrupts := 0;
      Exception_Tracebacks := 1;
      Exception_Tracebacks_Symbolic := 1;
      Detect_Blocking := 0;
      Default_Stack_Size := -1;

      ada_main'Elab_Body;
      Default_Secondary_Stack_Size := System.Parameters.Runtime_Default_Sec_Stack_Size;
      Binder_Sec_Stacks_Count := 1;
      Default_Sized_SS_Pool := Sec_Default_Sized_Stacks'Address;

      Runtime_Initialize (1);
      Tasking_Runtime_Initialize;

      Finalize_Library_Objects := finalize_library'access;

      Ada.Exceptions'Elab_Spec;
      System.Soft_Links'Elab_Spec;
      System.Exception_Table'Elab_Body;
      E026 := E026 + 1;
      System.Exceptions'Elab_Spec;
      E027 := E027 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E022 := E022 + 1;
      E015 := E015 + 1;
      E010 := E010 + 1;
      Ada.Assertions'Elab_Spec;
      E173 := E173 + 1;
      Ada.Containers'Elab_Spec;
      E098 := E098 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E104 := E104 + 1;
      Ada.Strings'Elab_Spec;
      E092 := E092 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E108 := E108 + 1;
      Gnat'Elab_Spec;
      E256 := E256 + 1;
      Interfaces.C'Elab_Spec;
      E055 := E055 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E328 := E328 + 1;
      System.Os_Lib'Elab_Body;
      E057 := E057 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E116 := E116 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E106 := E106 + 1;
      Ada.Streams'Elab_Spec;
      E103 := E103 + 1;
      System.File_Control_Block'Elab_Spec;
      E156 := E156 + 1;
      System.Finalization_Root'Elab_Spec;
      E127 := E127 + 1;
      Ada.Finalization'Elab_Spec;
      E101 := E101 + 1;
      System.File_Io'Elab_Body;
      E153 := E153 + 1;
      Ada.Streams.Stream_Io'Elab_Spec;
      E273 := E273 + 1;
      System.Storage_Pools'Elab_Spec;
      E160 := E160 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E265 := E265 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E008 := E008 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E281 := E281 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E079 := E079 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E216 := E216 + 1;
      E307 := E307 + 1;
      E309 := E309 + 1;
      Gnat.Md5'Elab_Spec;
      E305 := E305 + 1;
      E316 := E316 + 1;
      E322 := E322 + 1;
      E320 := E320 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E326 := E326 + 1;
      Gnat.Sha1'Elab_Spec;
      E314 := E314 + 1;
      Gnat.Sha256'Elab_Spec;
      E318 := E318 + 1;
      Gnat.Sha512'Elab_Spec;
      E324 := E324 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E180 := E180 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E162 := E162 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E094 := E094 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E097 := E097 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E139 := E139 + 1;
      System.Pool_Global'Elab_Spec;
      E261 := E261 + 1;
      System.Regexp'Elab_Spec;
      E158 := E158 + 1;
      Ada.Directories'Elab_Spec;
      Ada.Directories'Elab_Body;
      E006 := E006 + 1;
      System.Tasking.Initialization'Elab_Body;
      E241 := E241 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E231 := E231 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E237 := E237 + 1;
      System.Tasking.Queuing'Elab_Body;
      E249 := E249 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E360 := E360 + 1;
      System.Tasking.Stages'Elab_Body;
      E356 := E356 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E255 := E255 + 1;
      Flyology.Cancellation'Elab_Spec;
      E228 := E228 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E277 := E277 + 1;
      E279 := E279 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E219 := E219 + 1;
      E295 := E295 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E303 := E303 + 1;
      E293 := E293 + 1;
      E299 := E299 + 1;
      E301 := E301 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E297 := E297 + 1;
      Flyology.Object_Storage.Checksum_Engine'Elab_Spec;
      Flyology.Object_Storage.Checksum_Engine'Elab_Body;
      E290 := E290 + 1;
      E335 := E335 + 1;
      Flyology.Object_Storage.Sqlite.Databases'Elab_Spec;
      E344 := E344 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E259 := E259 + 1;
      Flyology.Object_Storage.Backends'Elab_Spec;
      E226 := E226 + 1;
      Flyology.Object_Storage.Backends.Listing'Elab_Spec;
      E340 := E340 + 1;
      Flyology.Object_Storage.Backends.Multipart_Listing'Elab_Spec;
      E342 := E342 + 1;
      Flyology.Object_Storage.Sqlite.Catalogs'Elab_Spec;
      Flyology.Object_Storage.Sqlite.Catalogs'Elab_Body;
      E338 := E338 + 1;
      Flyology.Object_Storage.Backends.Sqlite'Elab_Spec;
      Flyology.Object_Storage.Backends.Sqlite'Elab_Body;
      E271 := E271 + 1;
      REPRO_SQLITE_SUPPORT'ELAB_SPEC;
      Repro_Sqlite_Support'Elab_Body;
      E346 := E346 + 1;
      E350 := E350 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_sqlite_3");

   function main
     (argc : Integer;
      argv : System.Address;
      envp : System.Address)
      return Integer
   is
      procedure Initialize (Addr : System.Address);
      pragma Import (C, Initialize, "__gnat_initialize");

      procedure Finalize;
      pragma Import (C, Finalize, "__gnat_finalize");
      SEH : aliased array (1 .. 2) of Integer;

      Ensure_Reference : aliased System.Address := Ada_Main_Program_Name'Address;
      pragma Volatile (Ensure_Reference);

   begin
      if gnat_argc = 0 then
         gnat_argc := argc;
         gnat_argv := argv;
      end if;
      gnat_envp := envp;

      Initialize (SEH'Address);
      adainit;
      Ada_Main_Program;
      adafinal;
      Finalize;
      return (gnat_exit_status);
   end;

--  BEGIN Object file/option list
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/sqlite/tests/repros/obj/development/repro_sqlite_support.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/sqlite/tests/repros/obj/development/repro_support.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/sqlite/tests/repros/obj/development/repro_sqlite_3.o
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/sqlite/tests/repros/obj/development/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/sqlite/tests/repros/obj/development/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_http_0.1.3_eb09a80a/2f83c58c79352aa9f7aaef1fe9a0e7c4e52d7a004e2f2764ac40177b16ad26e0/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_0.1.1_bd95746d/3cf1f8e431e0343b4154ab650e51121b9e3441939b55a10702aab1165f04bd0a/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_6f91b1af/ce5a6cb5c23b9204ed30aafa3511ec1573b30b3a1b47dd8721b7721c266f17ae/flyology_allocators/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_8e046108/5bdda21efbfd816d0f8f932767afd5a893ef9566a97c274902fcb27e88cc9956/flyology_cachelines/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_http_eb09a80a/6e5388c72c69e5c647114cc8d4babdfe646f5a3add69c618e82a20d8bdd53e4a/flyology_quic/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/xmlada_26.0.0_b140ed4a/203717355baa29ae6df321c0e5fe208e221ec4ffd0b5c962070039c4a9ab04c4/input_sources/lib/static/
   --   -L/Users/yrashk/.local/share/alire/builds/xmlada_26.0.0_b140ed4a/203717355baa29ae6df321c0e5fe208e221ec4ffd0b5c962070039c4a9ab04c4/unicode/lib/static/
   --   -L/Users/yrashk/.local/share/alire/builds/xmlada_26.0.0_b140ed4a/203717355baa29ae6df321c0e5fe208e221ec4ffd0b5c962070039c4a9ab04c4/sax/lib/static/
   --   -L/Users/yrashk/.local/share/alire/builds/xmlada_26.0.0_b140ed4a/203717355baa29ae6df321c0e5fe208e221ec4ffd0b5c962070039c4a9ab04c4/dom/lib/static/
   --   -L/Users/yrashk/.local/share/alire/builds/xmlada_26.0.0_b140ed4a/203717355baa29ae6df321c0e5fe208e221ec4ffd0b5c962070039c4a9ab04c4/schema/lib/static/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/sqlite/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_0.1.1_bd95746d/3cf1f8e431e0343b4154ab650e51121b9e3441939b55a10702aab1165f04bd0a/build/alire-rts/adalib/
   --   -static
   --   -lgnarl
   --   -lgnat
--  END Object file/option list   

end ada_main;
