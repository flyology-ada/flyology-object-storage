pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_s3_domain_a_1.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_s3_domain_a_1.adb");
pragma Suppress (Overflow_Check);
with Ada.Exceptions;

package body ada_main is

   E006 : Short_Integer; pragma Import (Ada, E006, "ada__exceptions_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "system__soft_links_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__exception_table_E");
   E023 : Short_Integer; pragma Import (Ada, E023, "system__exceptions_E");
   E018 : Short_Integer; pragma Import (Ada, E018, "system__soft_links__initialize_E");
   E162 : Short_Integer; pragma Import (Ada, E162, "ada__assertions_E");
   E124 : Short_Integer; pragma Import (Ada, E124, "ada__containers_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "ada__io_exceptions_E");
   E050 : Short_Integer; pragma Import (Ada, E050, "ada__strings_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__utf_encoding_E");
   E131 : Short_Integer; pragma Import (Ada, E131, "gnat_E");
   E079 : Short_Integer; pragma Import (Ada, E079, "interfaces__c_E");
   E280 : Short_Integer; pragma Import (Ada, E280, "system__os_lib_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__tags_E");
   E052 : Short_Integer; pragma Import (Ada, E052, "ada__strings__text_buffers_E");
   E088 : Short_Integer; pragma Import (Ada, E088, "ada__streams_E");
   E284 : Short_Integer; pragma Import (Ada, E284, "system__file_control_block_E");
   E091 : Short_Integer; pragma Import (Ada, E091, "system__finalization_root_E");
   E086 : Short_Integer; pragma Import (Ada, E086, "ada__finalization_E");
   E276 : Short_Integer; pragma Import (Ada, E276, "system__file_io_E");
   E145 : Short_Integer; pragma Import (Ada, E145, "system__storage_pools_E");
   E309 : Short_Integer; pragma Import (Ada, E309, "system__storage_pools__subpools_E");
   E272 : Short_Integer; pragma Import (Ada, E272, "ada__text_io_E");
   E135 : Short_Integer; pragma Import (Ada, E135, "gnat__secure_hashes_E");
   E142 : Short_Integer; pragma Import (Ada, E142, "gnat__secure_hashes__sha2_common_E");
   E137 : Short_Integer; pragma Import (Ada, E137, "gnat__secure_hashes__sha2_32_E");
   E133 : Short_Integer; pragma Import (Ada, E133, "gnat__sha256_E");
   E167 : Short_Integer; pragma Import (Ada, E167, "system__flyology__scheduler_E");
   E093 : Short_Integer; pragma Import (Ada, E093, "ada__strings__maps_E");
   E228 : Short_Integer; pragma Import (Ada, E228, "ada__strings__maps__constants_E");
   E074 : Short_Integer; pragma Import (Ada, E074, "ada__strings__unbounded_E");
   E286 : Short_Integer; pragma Import (Ada, E286, "gnat__directory_operations_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "system__pool_global_E");
   E216 : Short_Integer; pragma Import (Ada, E216, "unicode_E");
   E115 : Short_Integer; pragma Import (Ada, E115, "flyology__object_storage_E");
   E210 : Short_Integer; pragma Import (Ada, E210, "flyology__object_storage__s3__core_E");
   E128 : Short_Integer; pragma Import (Ada, E128, "flyology__object_storage__s3__model_E");
   E130 : Short_Integer; pragma Import (Ada, E130, "flyology__object_storage__s3__wire_core_E");
   E317 : Short_Integer; pragma Import (Ada, E317, "repro_support_E");
   E301 : Short_Integer; pragma Import (Ada, E301, "sax__htable_E");
   E303 : Short_Integer; pragma Import (Ada, E303, "sax__pointers_E");
   E230 : Short_Integer; pragma Import (Ada, E230, "unicode__ccs_E");
   E232 : Short_Integer; pragma Import (Ada, E232, "unicode__ccs__iso_8859_1_E");
   E235 : Short_Integer; pragma Import (Ada, E235, "unicode__ccs__iso_8859_15_E");
   E240 : Short_Integer; pragma Import (Ada, E240, "unicode__ccs__iso_8859_2_E");
   E243 : Short_Integer; pragma Import (Ada, E243, "unicode__ccs__iso_8859_3_E");
   E245 : Short_Integer; pragma Import (Ada, E245, "unicode__ccs__iso_8859_4_E");
   E247 : Short_Integer; pragma Import (Ada, E247, "unicode__ccs__windows_1251_E");
   E252 : Short_Integer; pragma Import (Ada, E252, "unicode__ccs__windows_1252_E");
   E223 : Short_Integer; pragma Import (Ada, E223, "unicode__ces_E");
   E296 : Short_Integer; pragma Import (Ada, E296, "sax__symbols_E");
   E307 : Short_Integer; pragma Import (Ada, E307, "sax__locators_E");
   E305 : Short_Integer; pragma Import (Ada, E305, "sax__exceptions_E");
   E257 : Short_Integer; pragma Import (Ada, E257, "unicode__ces__utf32_E");
   E255 : Short_Integer; pragma Import (Ada, E255, "unicode__ces__basic_8bit_E");
   E259 : Short_Integer; pragma Import (Ada, E259, "unicode__ces__utf16_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "unicode__ces__utf8_E");
   E293 : Short_Integer; pragma Import (Ada, E293, "sax__models_E");
   E291 : Short_Integer; pragma Import (Ada, E291, "sax__attributes_E");
   E313 : Short_Integer; pragma Import (Ada, E313, "sax__utils_E");
   E225 : Short_Integer; pragma Import (Ada, E225, "unicode__encodings_E");
   E214 : Short_Integer; pragma Import (Ada, E214, "input_sources_E");
   E289 : Short_Integer; pragma Import (Ada, E289, "input_sources__file_E");
   E267 : Short_Integer; pragma Import (Ada, E267, "input_sources__strings_E");
   E270 : Short_Integer; pragma Import (Ada, E270, "sax__readers_E");
   E212 : Short_Integer; pragma Import (Ada, E212, "flyology__object_storage__s3__xml_E");
   E123 : Short_Integer; pragma Import (Ada, E123, "flyology__object_storage__s3__listings_E");
   E315 : Short_Integer; pragma Import (Ada, E315, "flyology__object_storage__s3__versions_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "flyology__object_storage__s3__versions__finalize_body");
      begin
         E315 := E315 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology__object_storage__s3__versions__finalize_spec");
      begin
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__s3__listings__finalize_body");
      begin
         E123 := E123 - 1;
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__s3__listings__finalize_spec");
      begin
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__xml__finalize_body");
      begin
         E212 := E212 - 1;
         F5;
      end;
      E270 := E270 - 1;
      declare
         procedure F6;
         pragma Import (Ada, F6, "sax__readers__finalize_spec");
      begin
         F6;
      end;
      E267 := E267 - 1;
      declare
         procedure F7;
         pragma Import (Ada, F7, "input_sources__strings__finalize_spec");
      begin
         F7;
      end;
      E289 := E289 - 1;
      declare
         procedure F8;
         pragma Import (Ada, F8, "input_sources__file__finalize_spec");
      begin
         F8;
      end;
      E214 := E214 - 1;
      declare
         procedure F9;
         pragma Import (Ada, F9, "input_sources__finalize_spec");
      begin
         F9;
      end;
      E313 := E313 - 1;
      declare
         procedure F10;
         pragma Import (Ada, F10, "sax__utils__finalize_spec");
      begin
         F10;
      end;
      E291 := E291 - 1;
      declare
         procedure F11;
         pragma Import (Ada, F11, "sax__attributes__finalize_spec");
      begin
         F11;
      end;
      E305 := E305 - 1;
      declare
         procedure F12;
         pragma Import (Ada, F12, "sax__exceptions__finalize_spec");
      begin
         F12;
      end;
      E296 := E296 - 1;
      declare
         procedure F13;
         pragma Import (Ada, F13, "sax__symbols__finalize_spec");
      begin
         F13;
      end;
      E303 := E303 - 1;
      declare
         procedure F14;
         pragma Import (Ada, F14, "sax__pointers__finalize_spec");
      begin
         F14;
      end;
      E263 := E263 - 1;
      declare
         procedure F15;
         pragma Import (Ada, F15, "system__pool_global__finalize_spec");
      begin
         F15;
      end;
      E074 := E074 - 1;
      declare
         procedure F16;
         pragma Import (Ada, F16, "ada__strings__unbounded__finalize_spec");
      begin
         F16;
      end;
      E133 := E133 - 1;
      declare
         procedure F17;
         pragma Import (Ada, F17, "gnat__sha256__finalize_spec");
      begin
         F17;
      end;
      E272 := E272 - 1;
      declare
         procedure F18;
         pragma Import (Ada, F18, "ada__text_io__finalize_spec");
      begin
         F18;
      end;
      E309 := E309 - 1;
      declare
         procedure F19;
         pragma Import (Ada, F19, "system__storage_pools__subpools__finalize_spec");
      begin
         F19;
      end;
      declare
         procedure F20;
         pragma Import (Ada, F20, "system__file_io__finalize_body");
      begin
         E276 := E276 - 1;
         F20;
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
      E162 := E162 + 1;
      Ada.Containers'Elab_Spec;
      E124 := E124 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E089 := E089 + 1;
      Ada.Strings'Elab_Spec;
      E050 := E050 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E054 := E054 + 1;
      Gnat'Elab_Spec;
      E131 := E131 + 1;
      Interfaces.C'Elab_Spec;
      E079 := E079 + 1;
      System.Os_Lib'Elab_Body;
      E280 := E280 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E062 := E062 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E052 := E052 + 1;
      Ada.Streams'Elab_Spec;
      E088 := E088 + 1;
      System.File_Control_Block'Elab_Spec;
      E284 := E284 + 1;
      System.Finalization_Root'Elab_Spec;
      E091 := E091 + 1;
      Ada.Finalization'Elab_Spec;
      E086 := E086 + 1;
      System.File_Io'Elab_Body;
      E276 := E276 + 1;
      System.Storage_Pools'Elab_Spec;
      E145 := E145 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E309 := E309 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E272 := E272 + 1;
      E135 := E135 + 1;
      E142 := E142 + 1;
      E137 := E137 + 1;
      Gnat.Sha256'Elab_Spec;
      E133 := E133 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E167 := E167 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E093 := E093 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E228 := E228 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E074 := E074 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E286 := E286 + 1;
      System.Pool_Global'Elab_Spec;
      E263 := E263 + 1;
      Unicode'Elab_Body;
      E216 := E216 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E115 := E115 + 1;
      E210 := E210 + 1;
      E128 := E128 + 1;
      E130 := E130 + 1;
      E317 := E317 + 1;
      E301 := E301 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E303 := E303 + 1;
      Unicode.Ccs'Elab_Spec;
      E230 := E230 + 1;
      E232 := E232 + 1;
      E235 := E235 + 1;
      E240 := E240 + 1;
      E243 := E243 + 1;
      E245 := E245 + 1;
      E247 := E247 + 1;
      E252 := E252 + 1;
      Unicode.Ces'Elab_Spec;
      E223 := E223 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E296 := E296 + 1;
      E307 := E307 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E305 := E305 + 1;
      E257 := E257 + 1;
      E255 := E255 + 1;
      E259 := E259 + 1;
      E261 := E261 + 1;
      Sax.Models'Elab_Spec;
      E293 := E293 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E291 := E291 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E313 := E313 + 1;
      E225 := E225 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E214 := E214 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E289 := E289 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E267 := E267 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E270 := E270 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E212 := E212 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E123 := E123 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E315 := E315 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_s3_domain_a_1");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_s3_domain_a_1.o
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
