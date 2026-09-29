pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_s3_domain_a_4.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_s3_domain_a_4.adb");
pragma Suppress (Overflow_Check);
with Ada.Exceptions;

package body ada_main is

   E006 : Short_Integer; pragma Import (Ada, E006, "ada__exceptions_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "system__soft_links_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__exception_table_E");
   E023 : Short_Integer; pragma Import (Ada, E023, "system__exceptions_E");
   E018 : Short_Integer; pragma Import (Ada, E018, "system__soft_links__initialize_E");
   E256 : Short_Integer; pragma Import (Ada, E256, "ada__assertions_E");
   E298 : Short_Integer; pragma Import (Ada, E298, "ada__containers_E");
   E099 : Short_Integer; pragma Import (Ada, E099, "ada__io_exceptions_E");
   E052 : Short_Integer; pragma Import (Ada, E052, "ada__strings_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__utf_encoding_E");
   E208 : Short_Integer; pragma Import (Ada, E208, "gnat_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "interfaces__c_E");
   E201 : Short_Integer; pragma Import (Ada, E201, "system__os_lib_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__tags_E");
   E051 : Short_Integer; pragma Import (Ada, E051, "ada__strings__text_buffers_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__streams_E");
   E207 : Short_Integer; pragma Import (Ada, E207, "system__file_control_block_E");
   E101 : Short_Integer; pragma Import (Ada, E101, "system__finalization_root_E");
   E096 : Short_Integer; pragma Import (Ada, E096, "ada__finalization_E");
   E197 : Short_Integer; pragma Import (Ada, E197, "system__file_io_E");
   E186 : Short_Integer; pragma Import (Ada, E186, "system__storage_pools_E");
   E235 : Short_Integer; pragma Import (Ada, E235, "system__storage_pools__subpools_E");
   E193 : Short_Integer; pragma Import (Ada, E193, "ada__text_io_E");
   E308 : Short_Integer; pragma Import (Ada, E308, "gnat__secure_hashes_E");
   E315 : Short_Integer; pragma Import (Ada, E315, "gnat__secure_hashes__sha2_common_E");
   E310 : Short_Integer; pragma Import (Ada, E310, "gnat__secure_hashes__sha2_32_E");
   E306 : Short_Integer; pragma Import (Ada, E306, "gnat__sha256_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "system__flyology__scheduler_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "ada__strings__maps_E");
   E145 : Short_Integer; pragma Import (Ada, E145, "ada__strings__maps__constants_E");
   E084 : Short_Integer; pragma Import (Ada, E084, "ada__strings__unbounded_E");
   E210 : Short_Integer; pragma Import (Ada, E210, "gnat__directory_operations_E");
   E180 : Short_Integer; pragma Import (Ada, E180, "system__pool_global_E");
   E133 : Short_Integer; pragma Import (Ada, E133, "unicode_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "flyology__object_storage_E");
   E304 : Short_Integer; pragma Import (Ada, E304, "flyology__object_storage__s3__sigv4_encoding_E");
   E127 : Short_Integer; pragma Import (Ada, E127, "flyology__object_storage__s3__wire_core_E");
   E327 : Short_Integer; pragma Import (Ada, E327, "repro_support_E");
   E227 : Short_Integer; pragma Import (Ada, E227, "sax__htable_E");
   E229 : Short_Integer; pragma Import (Ada, E229, "sax__pointers_E");
   E147 : Short_Integer; pragma Import (Ada, E147, "unicode__ccs_E");
   E149 : Short_Integer; pragma Import (Ada, E149, "unicode__ccs__iso_8859_1_E");
   E152 : Short_Integer; pragma Import (Ada, E152, "unicode__ccs__iso_8859_15_E");
   E157 : Short_Integer; pragma Import (Ada, E157, "unicode__ccs__iso_8859_2_E");
   E160 : Short_Integer; pragma Import (Ada, E160, "unicode__ccs__iso_8859_3_E");
   E162 : Short_Integer; pragma Import (Ada, E162, "unicode__ccs__iso_8859_4_E");
   E164 : Short_Integer; pragma Import (Ada, E164, "unicode__ccs__windows_1251_E");
   E169 : Short_Integer; pragma Import (Ada, E169, "unicode__ccs__windows_1252_E");
   E140 : Short_Integer; pragma Import (Ada, E140, "unicode__ces_E");
   E222 : Short_Integer; pragma Import (Ada, E222, "sax__symbols_E");
   E233 : Short_Integer; pragma Import (Ada, E233, "sax__locators_E");
   E231 : Short_Integer; pragma Import (Ada, E231, "sax__exceptions_E");
   E174 : Short_Integer; pragma Import (Ada, E174, "unicode__ces__utf32_E");
   E172 : Short_Integer; pragma Import (Ada, E172, "unicode__ces__basic_8bit_E");
   E176 : Short_Integer; pragma Import (Ada, E176, "unicode__ces__utf16_E");
   E178 : Short_Integer; pragma Import (Ada, E178, "unicode__ces__utf8_E");
   E219 : Short_Integer; pragma Import (Ada, E219, "sax__models_E");
   E217 : Short_Integer; pragma Import (Ada, E217, "sax__attributes_E");
   E241 : Short_Integer; pragma Import (Ada, E241, "sax__utils_E");
   E142 : Short_Integer; pragma Import (Ada, E142, "unicode__encodings_E");
   E131 : Short_Integer; pragma Import (Ada, E131, "input_sources_E");
   E215 : Short_Integer; pragma Import (Ada, E215, "input_sources__file_E");
   E188 : Short_Integer; pragma Import (Ada, E188, "input_sources__strings_E");
   E191 : Short_Integer; pragma Import (Ada, E191, "sax__readers_E");
   E129 : Short_Integer; pragma Import (Ada, E129, "flyology__object_storage__s3__xml_E");
   E302 : Short_Integer; pragma Import (Ada, E302, "flyology__object_storage__s3__buckets_E");
   E125 : Short_Integer; pragma Import (Ada, E125, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E123 : Short_Integer; pragma Import (Ada, E123, "flyology__object_storage__s3__analytics_E");
   E321 : Short_Integer; pragma Import (Ada, E321, "flyology__object_storage__s3__intelligent_tiering_E");
   E323 : Short_Integer; pragma Import (Ada, E323, "flyology__object_storage__s3__inventory_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "flyology__object_storage__s3__metrics_E");
   E319 : Short_Integer; pragma Import (Ada, E319, "flyology__object_storage__s3__strict_xml_codecs_E");
   E317 : Short_Integer; pragma Import (Ada, E317, "flyology__object_storage__s3__generated_list_directory_buckets_xml_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "flyology__object_storage__s3__generated_list_directory_buckets_xml__finalize_body");
      begin
         E317 := E317 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology__object_storage__s3__metrics__finalize_body");
      begin
         E325 := E325 - 1;
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__s3__metrics__finalize_spec");
      begin
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__s3__inventory__finalize_body");
      begin
         E323 := E323 - 1;
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__inventory__finalize_spec");
      begin
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__intelligent_tiering__finalize_body");
      begin
         E321 := E321 - 1;
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__s3__intelligent_tiering__finalize_spec");
      begin
         F7;
      end;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology__object_storage__s3__analytics__finalize_body");
      begin
         E123 := E123 - 1;
         F8;
      end;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology__object_storage__s3__analytics__finalize_spec");
      begin
         F9;
      end;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E302 := E302 - 1;
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__buckets__finalize_spec");
      begin
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__xml__finalize_body");
      begin
         E129 := E129 - 1;
         F12;
      end;
      E191 := E191 - 1;
      declare
         procedure F13;
         pragma Import (Ada, F13, "sax__readers__finalize_spec");
      begin
         F13;
      end;
      E188 := E188 - 1;
      declare
         procedure F14;
         pragma Import (Ada, F14, "input_sources__strings__finalize_spec");
      begin
         F14;
      end;
      E215 := E215 - 1;
      declare
         procedure F15;
         pragma Import (Ada, F15, "input_sources__file__finalize_spec");
      begin
         F15;
      end;
      E131 := E131 - 1;
      declare
         procedure F16;
         pragma Import (Ada, F16, "input_sources__finalize_spec");
      begin
         F16;
      end;
      E241 := E241 - 1;
      declare
         procedure F17;
         pragma Import (Ada, F17, "sax__utils__finalize_spec");
      begin
         F17;
      end;
      E217 := E217 - 1;
      declare
         procedure F18;
         pragma Import (Ada, F18, "sax__attributes__finalize_spec");
      begin
         F18;
      end;
      E231 := E231 - 1;
      declare
         procedure F19;
         pragma Import (Ada, F19, "sax__exceptions__finalize_spec");
      begin
         F19;
      end;
      E222 := E222 - 1;
      declare
         procedure F20;
         pragma Import (Ada, F20, "sax__symbols__finalize_spec");
      begin
         F20;
      end;
      E229 := E229 - 1;
      declare
         procedure F21;
         pragma Import (Ada, F21, "sax__pointers__finalize_spec");
      begin
         F21;
      end;
      E180 := E180 - 1;
      declare
         procedure F22;
         pragma Import (Ada, F22, "system__pool_global__finalize_spec");
      begin
         F22;
      end;
      E084 := E084 - 1;
      declare
         procedure F23;
         pragma Import (Ada, F23, "ada__strings__unbounded__finalize_spec");
      begin
         F23;
      end;
      E306 := E306 - 1;
      declare
         procedure F24;
         pragma Import (Ada, F24, "gnat__sha256__finalize_spec");
      begin
         F24;
      end;
      E193 := E193 - 1;
      declare
         procedure F25;
         pragma Import (Ada, F25, "ada__text_io__finalize_spec");
      begin
         F25;
      end;
      E235 := E235 - 1;
      declare
         procedure F26;
         pragma Import (Ada, F26, "system__storage_pools__subpools__finalize_spec");
      begin
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "system__file_io__finalize_body");
      begin
         E197 := E197 - 1;
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
      E022 := E022 + 1;
      System.Exceptions'Elab_Spec;
      E023 := E023 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E018 := E018 + 1;
      E011 := E011 + 1;
      E006 := E006 + 1;
      Ada.Assertions'Elab_Spec;
      E256 := E256 + 1;
      Ada.Containers'Elab_Spec;
      E298 := E298 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E099 := E099 + 1;
      Ada.Strings'Elab_Spec;
      E052 := E052 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E054 := E054 + 1;
      Gnat'Elab_Spec;
      E208 := E208 + 1;
      Interfaces.C'Elab_Spec;
      E089 := E089 + 1;
      System.Os_Lib'Elab_Body;
      E201 := E201 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E062 := E062 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E051 := E051 + 1;
      Ada.Streams'Elab_Spec;
      E098 := E098 + 1;
      System.File_Control_Block'Elab_Spec;
      E207 := E207 + 1;
      System.Finalization_Root'Elab_Spec;
      E101 := E101 + 1;
      Ada.Finalization'Elab_Spec;
      E096 := E096 + 1;
      System.File_Io'Elab_Body;
      E197 := E197 + 1;
      System.Storage_Pools'Elab_Spec;
      E186 := E186 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E235 := E235 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E193 := E193 + 1;
      E308 := E308 + 1;
      E315 := E315 + 1;
      E310 := E310 + 1;
      Gnat.Sha256'Elab_Spec;
      E306 := E306 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E261 := E261 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E103 := E103 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E145 := E145 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E084 := E084 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E210 := E210 + 1;
      System.Pool_Global'Elab_Spec;
      E180 := E180 + 1;
      Unicode'Elab_Body;
      E133 := E133 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E077 := E077 + 1;
      E304 := E304 + 1;
      E127 := E127 + 1;
      E327 := E327 + 1;
      E227 := E227 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E229 := E229 + 1;
      Unicode.Ccs'Elab_Spec;
      E147 := E147 + 1;
      E149 := E149 + 1;
      E152 := E152 + 1;
      E157 := E157 + 1;
      E160 := E160 + 1;
      E162 := E162 + 1;
      E164 := E164 + 1;
      E169 := E169 + 1;
      Unicode.Ces'Elab_Spec;
      E140 := E140 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E222 := E222 + 1;
      E233 := E233 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E231 := E231 + 1;
      E174 := E174 + 1;
      E172 := E172 + 1;
      E176 := E176 + 1;
      E178 := E178 + 1;
      Sax.Models'Elab_Spec;
      E219 := E219 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E217 := E217 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E241 := E241 + 1;
      E142 := E142 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E131 := E131 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E215 := E215 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E188 := E188 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E191 := E191 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E129 := E129 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E302 := E302 + 1;
      E125 := E125 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E123 := E123 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E321 := E321 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E323 := E323 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E325 := E325 + 1;
      E319 := E319 + 1;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Body;
      E317 := E317 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_s3_domain_a_4");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_support.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_s3_domain_a_4.o
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/
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
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_0.1.1_bd95746d/3cf1f8e431e0343b4154ab650e51121b9e3441939b55a10702aab1165f04bd0a/build/alire-rts/adalib/
   --   -static
   --   -lgnarl
   --   -lgnat
--  END Object file/option list   

end ada_main;
