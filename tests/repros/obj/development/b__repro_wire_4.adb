pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_wire_4.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_wire_4.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E006 : Short_Integer; pragma Import (Ada, E006, "ada__exceptions_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "system__soft_links_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__exception_table_E");
   E023 : Short_Integer; pragma Import (Ada, E023, "system__exceptions_E");
   E018 : Short_Integer; pragma Import (Ada, E018, "system__soft_links__initialize_E");
   E250 : Short_Integer; pragma Import (Ada, E250, "ada__assertions_E");
   E303 : Short_Integer; pragma Import (Ada, E303, "ada__containers_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "ada__io_exceptions_E");
   E050 : Short_Integer; pragma Import (Ada, E050, "ada__strings_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__utf_encoding_E");
   E202 : Short_Integer; pragma Import (Ada, E202, "gnat_E");
   E079 : Short_Integer; pragma Import (Ada, E079, "interfaces__c_E");
   E386 : Short_Integer; pragma Import (Ada, E386, "interfaces__c__strings_E");
   E195 : Short_Integer; pragma Import (Ada, E195, "system__os_lib_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__tags_E");
   E052 : Short_Integer; pragma Import (Ada, E052, "ada__strings__text_buffers_E");
   E088 : Short_Integer; pragma Import (Ada, E088, "ada__streams_E");
   E201 : Short_Integer; pragma Import (Ada, E201, "system__file_control_block_E");
   E091 : Short_Integer; pragma Import (Ada, E091, "system__finalization_root_E");
   E086 : Short_Integer; pragma Import (Ada, E086, "ada__finalization_E");
   E191 : Short_Integer; pragma Import (Ada, E191, "system__file_io_E");
   E180 : Short_Integer; pragma Import (Ada, E180, "system__storage_pools_E");
   E229 : Short_Integer; pragma Import (Ada, E229, "system__storage_pools__subpools_E");
   E295 : Short_Integer; pragma Import (Ada, E295, "ada__calendar_E");
   E368 : Short_Integer; pragma Import (Ada, E368, "ada__calendar__delays_E");
   E299 : Short_Integer; pragma Import (Ada, E299, "ada__calendar__time_zones_E");
   E187 : Short_Integer; pragma Import (Ada, E187, "ada__text_io_E");
   E457 : Short_Integer; pragma Import (Ada, E457, "gnat__secure_hashes_E");
   E459 : Short_Integer; pragma Import (Ada, E459, "gnat__secure_hashes__md5_E");
   E455 : Short_Integer; pragma Import (Ada, E455, "gnat__md5_E");
   E466 : Short_Integer; pragma Import (Ada, E466, "gnat__secure_hashes__sha1_E");
   E472 : Short_Integer; pragma Import (Ada, E472, "gnat__secure_hashes__sha2_common_E");
   E470 : Short_Integer; pragma Import (Ada, E470, "gnat__secure_hashes__sha2_32_E");
   E476 : Short_Integer; pragma Import (Ada, E476, "gnat__secure_hashes__sha2_64_E");
   E464 : Short_Integer; pragma Import (Ada, E464, "gnat__sha1_E");
   E468 : Short_Integer; pragma Import (Ada, E468, "gnat__sha256_E");
   E474 : Short_Integer; pragma Import (Ada, E474, "gnat__sha512_E");
   E255 : Short_Integer; pragma Import (Ada, E255, "system__flyology__scheduler_E");
   E310 : Short_Integer; pragma Import (Ada, E310, "ada__real_time_E");
   E093 : Short_Integer; pragma Import (Ada, E093, "ada__strings__maps_E");
   E139 : Short_Integer; pragma Import (Ada, E139, "ada__strings__maps__constants_E");
   E074 : Short_Integer; pragma Import (Ada, E074, "ada__strings__unbounded_E");
   E204 : Short_Integer; pragma Import (Ada, E204, "gnat__directory_operations_E");
   E174 : Short_Integer; pragma Import (Ada, E174, "system__pool_global_E");
   E377 : Short_Integer; pragma Import (Ada, E377, "gnat__sockets_E");
   E380 : Short_Integer; pragma Import (Ada, E380, "gnat__sockets__poll_E");
   E384 : Short_Integer; pragma Import (Ada, E384, "gnat__sockets__thin_common_E");
   E382 : Short_Integer; pragma Import (Ada, E382, "gnat__sockets__thin_E");
   E329 : Short_Integer; pragma Import (Ada, E329, "system__tasking__initialization_E");
   E319 : Short_Integer; pragma Import (Ada, E319, "system__tasking__protected_objects_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "system__tasking__protected_objects__entries_E");
   E337 : Short_Integer; pragma Import (Ada, E337, "system__tasking__queuing_E");
   E588 : Short_Integer; pragma Import (Ada, E588, "system__flyology__task_results_E");
   E584 : Short_Integer; pragma Import (Ada, E584, "system__tasking__stages_E");
   E343 : Short_Integer; pragma Import (Ada, E343, "flyology__wake_sources_E");
   E316 : Short_Integer; pragma Import (Ada, E316, "flyology__cancellation_E");
   E366 : Short_Integer; pragma Import (Ada, E366, "flyology__operations_E");
   E364 : Short_Integer; pragma Import (Ada, E364, "flyology__io_E");
   E127 : Short_Integer; pragma Import (Ada, E127, "unicode_E");
   E408 : Short_Integer; pragma Import (Ada, E408, "flyology__buffers_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "flyology__bytes_E");
   E345 : Short_Integer; pragma Import (Ada, E345, "flyology__capacity_E");
   E350 : Short_Integer; pragma Import (Ada, E350, "flyology__counter_policy_E");
   E352 : Short_Integer; pragma Import (Ada, E352, "flyology__http_E");
   E356 : Short_Integer; pragma Import (Ada, E356, "flyology__http__expect_policy_E");
   E391 : Short_Integer; pragma Import (Ada, E391, "flyology__http__fixed_response_policy_E");
   E362 : Short_Integer; pragma Import (Ada, E362, "flyology__http_chunk_encoding_E");
   E404 : Short_Integer; pragma Import (Ada, E404, "flyology__io__sockets_E");
   E115 : Short_Integer; pragma Import (Ada, E115, "flyology__object_storage_E");
   E445 : Short_Integer; pragma Import (Ada, E445, "flyology__object_storage__s3__core_E");
   E453 : Short_Integer; pragma Import (Ada, E453, "flyology__object_storage__s3__checksum_crc_E");
   E443 : Short_Integer; pragma Import (Ada, E443, "flyology__object_storage__s3__checksum_policy_E");
   E517 : Short_Integer; pragma Import (Ada, E517, "flyology__object_storage__s3__imf_dates_E");
   E525 : Short_Integer; pragma Import (Ada, E525, "flyology__object_storage__s3__model_E");
   E545 : Short_Integer; pragma Import (Ada, E545, "flyology__object_storage__s3__requests_E");
   E489 : Short_Integer; pragma Import (Ada, E489, "flyology__object_storage__s3__sigv4_encoding_E");
   E449 : Short_Integer; pragma Import (Ada, E449, "flyology__object_storage__s3__wire_core_E");
   E451 : Short_Integer; pragma Import (Ada, E451, "flyology__object_storage__secrets_E");
   E447 : Short_Integer; pragma Import (Ada, E447, "flyology__object_storage__s3__checksums_E");
   E441 : Short_Integer; pragma Import (Ada, E441, "flyology__object_storage__checksum_engine_E");
   E547 : Short_Integer; pragma Import (Ada, E547, "flyology__object_storage__s3__sigv4_E");
   E558 : Short_Integer; pragma Import (Ada, E558, "flyology__object_storage__s3__sigv4_verification_E");
   E561 : Short_Integer; pragma Import (Ada, E561, "flyology__object_storage__server__mfa_E");
   E562 : Short_Integer; pragma Import (Ada, E562, "flyology__object_storage__server__object_lambda_responses_E");
   E431 : Short_Integer; pragma Import (Ada, E431, "flyology__object_storage__tags_E");
   E429 : Short_Integer; pragma Import (Ada, E429, "flyology__object_storage__backends_E");
   E435 : Short_Integer; pragma Import (Ada, E435, "flyology__object_storage__backends__bucket_listing_E");
   E437 : Short_Integer; pragma Import (Ada, E437, "flyology__object_storage__backends__listing_E");
   E439 : Short_Integer; pragma Import (Ada, E439, "flyology__object_storage__backends__multipart_listing_E");
   E433 : Short_Integer; pragma Import (Ada, E433, "flyology__object_storage__backends__memory_E");
   E401 : Short_Integer; pragma Import (Ada, E401, "flyology__io__tls_E");
   E397 : Short_Integer; pragma Import (Ada, E397, "flyology__io__tls_driver_E");
   E393 : Short_Integer; pragma Import (Ada, E393, "flyology__io__connections_E");
   E411 : Short_Integer; pragma Import (Ada, E411, "flyology__io__connections__drivers_E");
   E424 : Short_Integer; pragma Import (Ada, E424, "flyology__io__structured_servers_E");
   E360 : Short_Integer; pragma Import (Ada, E360, "flyology__websocket_deflate_policy_E");
   E354 : Short_Integer; pragma Import (Ada, E354, "flyology__http__server_E");
   E358 : Short_Integer; pragma Import (Ada, E358, "flyology__http__server__websocket_deflate_E");
   E420 : Short_Integer; pragma Import (Ada, E420, "flyology__http__server__connection_handlers_E");
   E422 : Short_Integer; pragma Import (Ada, E422, "flyology__http__server__connections_E");
   E418 : Short_Integer; pragma Import (Ada, E418, "flyology__http__server__exchange_backends_E");
   E415 : Short_Integer; pragma Import (Ada, E415, "flyology__http__server__applications_E");
   E556 : Short_Integer; pragma Import (Ada, E556, "flyology__object_storage__server__authentication_E");
   E566 : Short_Integer; pragma Import (Ada, E566, "flyology__object_storage__server__static_credentials_E");
   E568 : Short_Integer; pragma Import (Ada, E568, "repro_support_E");
   E221 : Short_Integer; pragma Import (Ada, E221, "sax__htable_E");
   E223 : Short_Integer; pragma Import (Ada, E223, "sax__pointers_E");
   E141 : Short_Integer; pragma Import (Ada, E141, "unicode__ccs_E");
   E143 : Short_Integer; pragma Import (Ada, E143, "unicode__ccs__iso_8859_1_E");
   E146 : Short_Integer; pragma Import (Ada, E146, "unicode__ccs__iso_8859_15_E");
   E151 : Short_Integer; pragma Import (Ada, E151, "unicode__ccs__iso_8859_2_E");
   E154 : Short_Integer; pragma Import (Ada, E154, "unicode__ccs__iso_8859_3_E");
   E156 : Short_Integer; pragma Import (Ada, E156, "unicode__ccs__iso_8859_4_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "unicode__ccs__windows_1251_E");
   E163 : Short_Integer; pragma Import (Ada, E163, "unicode__ccs__windows_1252_E");
   E134 : Short_Integer; pragma Import (Ada, E134, "unicode__ces_E");
   E216 : Short_Integer; pragma Import (Ada, E216, "sax__symbols_E");
   E227 : Short_Integer; pragma Import (Ada, E227, "sax__locators_E");
   E225 : Short_Integer; pragma Import (Ada, E225, "sax__exceptions_E");
   E168 : Short_Integer; pragma Import (Ada, E168, "unicode__ces__utf32_E");
   E166 : Short_Integer; pragma Import (Ada, E166, "unicode__ces__basic_8bit_E");
   E170 : Short_Integer; pragma Import (Ada, E170, "unicode__ces__utf16_E");
   E172 : Short_Integer; pragma Import (Ada, E172, "unicode__ces__utf8_E");
   E213 : Short_Integer; pragma Import (Ada, E213, "sax__models_E");
   E211 : Short_Integer; pragma Import (Ada, E211, "sax__attributes_E");
   E235 : Short_Integer; pragma Import (Ada, E235, "sax__utils_E");
   E136 : Short_Integer; pragma Import (Ada, E136, "unicode__encodings_E");
   E125 : Short_Integer; pragma Import (Ada, E125, "input_sources_E");
   E209 : Short_Integer; pragma Import (Ada, E209, "input_sources__file_E");
   E182 : Short_Integer; pragma Import (Ada, E182, "input_sources__strings_E");
   E185 : Short_Integer; pragma Import (Ada, E185, "sax__readers_E");
   E123 : Short_Integer; pragma Import (Ada, E123, "flyology__object_storage__s3__xml_E");
   E509 : Short_Integer; pragma Import (Ada, E509, "flyology__object_storage__s3__acl_E");
   E493 : Short_Integer; pragma Import (Ada, E493, "flyology__object_storage__s3__bucket_controls_E");
   E495 : Short_Integer; pragma Import (Ada, E495, "flyology__object_storage__s3__buckets_E");
   E487 : Short_Integer; pragma Import (Ada, E487, "flyology__object_storage__s3__deletions_E");
   E491 : Short_Integer; pragma Import (Ada, E491, "flyology__object_storage__s3__attributes_E");
   E497 : Short_Integer; pragma Import (Ada, E497, "flyology__object_storage__s3__encryption_E");
   E499 : Short_Integer; pragma Import (Ada, E499, "flyology__object_storage__s3__errors_E");
   E521 : Short_Integer; pragma Import (Ada, E521, "flyology__object_storage__s3__lifecycle_E");
   E523 : Short_Integer; pragma Import (Ada, E523, "flyology__object_storage__s3__listings_E");
   E511 : Short_Integer; pragma Import (Ada, E511, "flyology__object_storage__s3__logging_E");
   E533 : Short_Integer; pragma Import (Ada, E533, "flyology__object_storage__s3__multipart_E");
   E535 : Short_Integer; pragma Import (Ada, E535, "flyology__object_storage__s3__multipart_uploads_E");
   E537 : Short_Integer; pragma Import (Ada, E537, "flyology__object_storage__s3__notifications_E");
   E539 : Short_Integer; pragma Import (Ada, E539, "flyology__object_storage__s3__object_lock_E");
   E541 : Short_Integer; pragma Import (Ada, E541, "flyology__object_storage__s3__object_reads_E");
   E483 : Short_Integer; pragma Import (Ada, E483, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E481 : Short_Integer; pragma Import (Ada, E481, "flyology__object_storage__s3__analytics_E");
   E485 : Short_Integer; pragma Import (Ada, E485, "flyology__object_storage__s3__annotations_E");
   E519 : Short_Integer; pragma Import (Ada, E519, "flyology__object_storage__s3__intelligent_tiering_E");
   E505 : Short_Integer; pragma Import (Ada, E505, "flyology__object_storage__s3__inventory_E");
   E531 : Short_Integer; pragma Import (Ada, E531, "flyology__object_storage__s3__metrics_E");
   E543 : Short_Integer; pragma Import (Ada, E543, "flyology__object_storage__s3__replication_E");
   E549 : Short_Integer; pragma Import (Ada, E549, "flyology__object_storage__s3__tagging_E");
   E551 : Short_Integer; pragma Import (Ada, E551, "flyology__object_storage__s3__versioning_E");
   E553 : Short_Integer; pragma Import (Ada, E553, "flyology__object_storage__s3__versions_E");
   E515 : Short_Integer; pragma Import (Ada, E515, "flyology__object_storage__s3__website_E");
   E503 : Short_Integer; pragma Import (Ada, E503, "flyology__object_storage__s3__xml_writers_E");
   E501 : Short_Integer; pragma Import (Ada, E501, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E507 : Short_Integer; pragma Import (Ada, E507, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E513 : Short_Integer; pragma Import (Ada, E513, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E527 : Short_Integer; pragma Import (Ada, E527, "flyology__object_storage__s3__metadata_configurations_E");
   E529 : Short_Integer; pragma Import (Ada, E529, "flyology__object_storage__s3__metadata_tables_E");
   E559 : Short_Integer; pragma Import (Ada, E559, "flyology__object_storage__server__metadata_results_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "flyology__object_storage__server__s3_applications_E");
   E293 : Short_Integer; pragma Import (Ada, E293, "repro_s3_server_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "repro_s3_server__finalize_body");
      begin
         E293 := E293 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "repro_s3_server__finalize_spec");
      begin
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__server__metadata_results__finalize_spec");
      begin
         E559 := E559 - 1;
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__s3__metadata_tables__finalize_body");
      begin
         E529 := E529 - 1;
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E527 := E527 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__website__finalize_body");
      begin
         E515 := E515 - 1;
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__s3__website__finalize_spec");
      begin
         F7;
      end;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology__object_storage__s3__versions__finalize_body");
      begin
         E553 := E553 - 1;
         F8;
      end;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology__object_storage__s3__versions__finalize_spec");
      begin
         F9;
      end;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology__object_storage__s3__versioning__finalize_body");
      begin
         E551 := E551 - 1;
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__tagging__finalize_body");
      begin
         E549 := E549 - 1;
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__replication__finalize_body");
      begin
         E543 := E543 - 1;
         F12;
      end;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology__object_storage__s3__replication__finalize_spec");
      begin
         F13;
      end;
      declare
         procedure F14;
         pragma Import (Ada, F14, "flyology__object_storage__s3__metrics__finalize_body");
      begin
         E531 := E531 - 1;
         F14;
      end;
      declare
         procedure F15;
         pragma Import (Ada, F15, "flyology__object_storage__s3__metrics__finalize_spec");
      begin
         F15;
      end;
      declare
         procedure F16;
         pragma Import (Ada, F16, "flyology__object_storage__s3__inventory__finalize_body");
      begin
         E505 := E505 - 1;
         F16;
      end;
      declare
         procedure F17;
         pragma Import (Ada, F17, "flyology__object_storage__s3__inventory__finalize_spec");
      begin
         F17;
      end;
      declare
         procedure F18;
         pragma Import (Ada, F18, "flyology__object_storage__s3__intelligent_tiering__finalize_body");
      begin
         E519 := E519 - 1;
         F18;
      end;
      declare
         procedure F19;
         pragma Import (Ada, F19, "flyology__object_storage__s3__intelligent_tiering__finalize_spec");
      begin
         F19;
      end;
      declare
         procedure F20;
         pragma Import (Ada, F20, "flyology__object_storage__s3__annotations__finalize_body");
      begin
         E485 := E485 - 1;
         F20;
      end;
      declare
         procedure F21;
         pragma Import (Ada, F21, "flyology__object_storage__s3__annotations__finalize_spec");
      begin
         F21;
      end;
      declare
         procedure F22;
         pragma Import (Ada, F22, "flyology__object_storage__s3__analytics__finalize_body");
      begin
         E481 := E481 - 1;
         F22;
      end;
      declare
         procedure F23;
         pragma Import (Ada, F23, "flyology__object_storage__s3__analytics__finalize_spec");
      begin
         F23;
      end;
      declare
         procedure F24;
         pragma Import (Ada, F24, "flyology__object_storage__s3__object_lock__finalize_body");
      begin
         E539 := E539 - 1;
         F24;
      end;
      declare
         procedure F25;
         pragma Import (Ada, F25, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E537 := E537 - 1;
         F25;
      end;
      declare
         procedure F26;
         pragma Import (Ada, F26, "flyology__object_storage__s3__notifications__finalize_spec");
      begin
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "flyology__object_storage__s3__multipart_uploads__finalize_body");
      begin
         E535 := E535 - 1;
         F27;
      end;
      declare
         procedure F28;
         pragma Import (Ada, F28, "flyology__object_storage__s3__multipart_uploads__finalize_spec");
      begin
         F28;
      end;
      declare
         procedure F29;
         pragma Import (Ada, F29, "flyology__object_storage__s3__multipart__finalize_body");
      begin
         E533 := E533 - 1;
         F29;
      end;
      declare
         procedure F30;
         pragma Import (Ada, F30, "flyology__object_storage__s3__multipart__finalize_spec");
      begin
         F30;
      end;
      declare
         procedure F31;
         pragma Import (Ada, F31, "flyology__object_storage__s3__logging__finalize_body");
      begin
         E511 := E511 - 1;
         F31;
      end;
      declare
         procedure F32;
         pragma Import (Ada, F32, "flyology__object_storage__s3__logging__finalize_spec");
      begin
         F32;
      end;
      declare
         procedure F33;
         pragma Import (Ada, F33, "flyology__object_storage__s3__listings__finalize_body");
      begin
         E523 := E523 - 1;
         F33;
      end;
      declare
         procedure F34;
         pragma Import (Ada, F34, "flyology__object_storage__s3__listings__finalize_spec");
      begin
         F34;
      end;
      declare
         procedure F35;
         pragma Import (Ada, F35, "flyology__object_storage__s3__lifecycle__finalize_body");
      begin
         E521 := E521 - 1;
         F35;
      end;
      declare
         procedure F36;
         pragma Import (Ada, F36, "flyology__object_storage__s3__lifecycle__finalize_spec");
      begin
         F36;
      end;
      declare
         procedure F37;
         pragma Import (Ada, F37, "flyology__object_storage__s3__errors__finalize_body");
      begin
         E499 := E499 - 1;
         F37;
      end;
      declare
         procedure F38;
         pragma Import (Ada, F38, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E497 := E497 - 1;
         F38;
      end;
      declare
         procedure F39;
         pragma Import (Ada, F39, "flyology__object_storage__s3__encryption__finalize_spec");
      begin
         F39;
      end;
      declare
         procedure F40;
         pragma Import (Ada, F40, "flyology__object_storage__s3__attributes__finalize_body");
      begin
         E491 := E491 - 1;
         F40;
      end;
      declare
         procedure F41;
         pragma Import (Ada, F41, "flyology__object_storage__s3__attributes__finalize_spec");
      begin
         F41;
      end;
      declare
         procedure F42;
         pragma Import (Ada, F42, "flyology__object_storage__s3__deletions__finalize_body");
      begin
         E487 := E487 - 1;
         F42;
      end;
      declare
         procedure F43;
         pragma Import (Ada, F43, "flyology__object_storage__s3__deletions__finalize_spec");
      begin
         F43;
      end;
      declare
         procedure F44;
         pragma Import (Ada, F44, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E495 := E495 - 1;
         F44;
      end;
      declare
         procedure F45;
         pragma Import (Ada, F45, "flyology__object_storage__s3__buckets__finalize_spec");
      begin
         F45;
      end;
      declare
         procedure F46;
         pragma Import (Ada, F46, "flyology__object_storage__s3__bucket_controls__finalize_body");
      begin
         E493 := E493 - 1;
         F46;
      end;
      declare
         procedure F47;
         pragma Import (Ada, F47, "flyology__object_storage__s3__bucket_controls__finalize_spec");
      begin
         F47;
      end;
      declare
         procedure F48;
         pragma Import (Ada, F48, "flyology__object_storage__s3__acl__finalize_body");
      begin
         E509 := E509 - 1;
         F48;
      end;
      declare
         procedure F49;
         pragma Import (Ada, F49, "flyology__object_storage__s3__acl__finalize_spec");
      begin
         F49;
      end;
      declare
         procedure F50;
         pragma Import (Ada, F50, "flyology__object_storage__s3__xml__finalize_body");
      begin
         E123 := E123 - 1;
         F50;
      end;
      E185 := E185 - 1;
      declare
         procedure F51;
         pragma Import (Ada, F51, "sax__readers__finalize_spec");
      begin
         F51;
      end;
      E182 := E182 - 1;
      declare
         procedure F52;
         pragma Import (Ada, F52, "input_sources__strings__finalize_spec");
      begin
         F52;
      end;
      E209 := E209 - 1;
      declare
         procedure F53;
         pragma Import (Ada, F53, "input_sources__file__finalize_spec");
      begin
         F53;
      end;
      E125 := E125 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "input_sources__finalize_spec");
      begin
         F54;
      end;
      E235 := E235 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "sax__utils__finalize_spec");
      begin
         F55;
      end;
      E211 := E211 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "sax__attributes__finalize_spec");
      begin
         F56;
      end;
      E225 := E225 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "sax__exceptions__finalize_spec");
      begin
         F57;
      end;
      E216 := E216 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__symbols__finalize_spec");
      begin
         F58;
      end;
      E223 := E223 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__pointers__finalize_spec");
      begin
         F59;
      end;
      E566 := E566 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "flyology__object_storage__server__static_credentials__finalize_spec");
      begin
         F60;
      end;
      E415 := E415 - 1;
      declare
         procedure F61;
         pragma Import (Ada, F61, "flyology__http__server__applications__finalize_spec");
      begin
         F61;
      end;
      E422 := E422 - 1;
      declare
         procedure F62;
         pragma Import (Ada, F62, "flyology__http__server__connections__finalize_spec");
      begin
         F62;
      end;
      E354 := E354 - 1;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__server__finalize_spec");
      begin
         F63;
      end;
      E411 := E411 - 1;
      declare
         procedure F64;
         pragma Import (Ada, F64, "flyology__io__connections__drivers__finalize_spec");
      begin
         F64;
      end;
      declare
         procedure F65;
         pragma Import (Ada, F65, "flyology__io__connections__finalize_body");
      begin
         E393 := E393 - 1;
         F65;
      end;
      declare
         procedure F66;
         pragma Import (Ada, F66, "flyology__io__connections__finalize_spec");
      begin
         F66;
      end;
      declare
         procedure F67;
         pragma Import (Ada, F67, "flyology__io__tls__finalize_body");
      begin
         E401 := E401 - 1;
         F67;
      end;
      declare
         procedure F68;
         pragma Import (Ada, F68, "flyology__io__tls__finalize_spec");
      begin
         F68;
      end;
      E433 := E433 - 1;
      declare
         procedure F69;
         pragma Import (Ada, F69, "flyology__object_storage__backends__memory__finalize_spec");
      begin
         F69;
      end;
      E439 := E439 - 1;
      declare
         procedure F70;
         pragma Import (Ada, F70, "flyology__object_storage__backends__multipart_listing__finalize_spec");
      begin
         F70;
      end;
      E437 := E437 - 1;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__object_storage__backends__listing__finalize_spec");
      begin
         F71;
      end;
      E435 := E435 - 1;
      declare
         procedure F72;
         pragma Import (Ada, F72, "flyology__object_storage__backends__bucket_listing__finalize_spec");
      begin
         F72;
      end;
      E429 := E429 - 1;
      declare
         procedure F73;
         pragma Import (Ada, F73, "flyology__object_storage__backends__finalize_spec");
      begin
         F73;
      end;
      E431 := E431 - 1;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__object_storage__tags__finalize_spec");
      begin
         F74;
      end;
      declare
         procedure F75;
         pragma Import (Ada, F75, "flyology__object_storage__server__object_lambda_responses__finalize_spec");
      begin
         E562 := E562 - 1;
         F75;
      end;
      E561 := E561 - 1;
      declare
         procedure F76;
         pragma Import (Ada, F76, "flyology__object_storage__server__mfa__finalize_spec");
      begin
         F76;
      end;
      E441 := E441 - 1;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__object_storage__checksum_engine__finalize_spec");
      begin
         F77;
      end;
      E447 := E447 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F78;
      end;
      E404 := E404 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__io__sockets__finalize_spec");
      begin
         F79;
      end;
      E314 := E314 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__bytes__finalize_spec");
      begin
         F80;
      end;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__buffers__finalize_body");
      begin
         E408 := E408 - 1;
         F81;
      end;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__buffers__finalize_spec");
      begin
         F82;
      end;
      E366 := E366 - 1;
      E364 := E364 - 1;
      declare
         procedure F83;
         pragma Import (Ada, F83, "flyology__io__finalize_spec");
      begin
         F83;
      end;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__operations__finalize_spec");
      begin
         F84;
      end;
      E343 := E343 - 1;
      declare
         procedure F85;
         pragma Import (Ada, F85, "flyology__wake_sources__finalize_spec");
      begin
         F85;
      end;
      E325 := E325 - 1;
      declare
         procedure F86;
         pragma Import (Ada, F86, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F86;
      end;
      declare
         procedure F87;
         pragma Import (Ada, F87, "gnat__sockets__finalize_body");
      begin
         E377 := E377 - 1;
         F87;
      end;
      declare
         procedure F88;
         pragma Import (Ada, F88, "gnat__sockets__finalize_spec");
      begin
         F88;
      end;
      E174 := E174 - 1;
      declare
         procedure F89;
         pragma Import (Ada, F89, "system__pool_global__finalize_spec");
      begin
         F89;
      end;
      E074 := E074 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "ada__strings__unbounded__finalize_spec");
      begin
         F90;
      end;
      E474 := E474 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "gnat__sha512__finalize_spec");
      begin
         F91;
      end;
      E468 := E468 - 1;
      declare
         procedure F92;
         pragma Import (Ada, F92, "gnat__sha256__finalize_spec");
      begin
         F92;
      end;
      E464 := E464 - 1;
      declare
         procedure F93;
         pragma Import (Ada, F93, "gnat__sha1__finalize_spec");
      begin
         F93;
      end;
      E455 := E455 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "gnat__md5__finalize_spec");
      begin
         F94;
      end;
      E187 := E187 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "ada__text_io__finalize_spec");
      begin
         F95;
      end;
      E229 := E229 - 1;
      declare
         procedure F96;
         pragma Import (Ada, F96, "system__storage_pools__subpools__finalize_spec");
      begin
         F96;
      end;
      declare
         procedure F97;
         pragma Import (Ada, F97, "system__file_io__finalize_body");
      begin
         E191 := E191 - 1;
         F97;
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
          (True, True, False, False, True, True, False, False, 
           True, False, False, True, True, True, True, False, 
           False, True, False, True, True, False, True, True, 
           False, True, True, False, True, True, True, True, 
           False, True, False, False, False, True, True, False, 
           True, True, False, True, False, True, True, False, 
           True, False, True, True, False, False, True, False, 
           True, False, False, False, False, True, False, False, 
           True, True, True, True, True, True, True, False, 
           True, False, True, True, True, False, True, True, 
           False, True, True, True, True, False, False, False, 
           True, False, False, False, False, True, True, True, 
           True, False, True, False),
         Count => (0, 0, 0, 2, 2, 1, 1, 0, 12, 0),
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
      E022 := E022 + 1;
      System.Exceptions'Elab_Spec;
      E023 := E023 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E018 := E018 + 1;
      E011 := E011 + 1;
      E006 := E006 + 1;
      Ada.Assertions'Elab_Spec;
      E250 := E250 + 1;
      Ada.Containers'Elab_Spec;
      E303 := E303 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E089 := E089 + 1;
      Ada.Strings'Elab_Spec;
      E050 := E050 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E054 := E054 + 1;
      Gnat'Elab_Spec;
      E202 := E202 + 1;
      Interfaces.C'Elab_Spec;
      E079 := E079 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E386 := E386 + 1;
      System.Os_Lib'Elab_Body;
      E195 := E195 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E062 := E062 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E052 := E052 + 1;
      Ada.Streams'Elab_Spec;
      E088 := E088 + 1;
      System.File_Control_Block'Elab_Spec;
      E201 := E201 + 1;
      System.Finalization_Root'Elab_Spec;
      E091 := E091 + 1;
      Ada.Finalization'Elab_Spec;
      E086 := E086 + 1;
      System.File_Io'Elab_Body;
      E191 := E191 + 1;
      System.Storage_Pools'Elab_Spec;
      E180 := E180 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E229 := E229 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E295 := E295 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E368 := E368 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E299 := E299 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E187 := E187 + 1;
      E457 := E457 + 1;
      E459 := E459 + 1;
      Gnat.Md5'Elab_Spec;
      E455 := E455 + 1;
      E466 := E466 + 1;
      E472 := E472 + 1;
      E470 := E470 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E476 := E476 + 1;
      Gnat.Sha1'Elab_Spec;
      E464 := E464 + 1;
      Gnat.Sha256'Elab_Spec;
      E468 := E468 + 1;
      Gnat.Sha512'Elab_Spec;
      E474 := E474 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E255 := E255 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E310 := E310 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E093 := E093 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E139 := E139 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E074 := E074 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E204 := E204 + 1;
      System.Pool_Global'Elab_Spec;
      E174 := E174 + 1;
      Gnat.Sockets'Elab_Spec;
      Gnat.Sockets.Thin_Common'Elab_Spec;
      E384 := E384 + 1;
      E382 := E382 + 1;
      Gnat.Sockets'Elab_Body;
      E377 := E377 + 1;
      E380 := E380 + 1;
      System.Tasking.Initialization'Elab_Body;
      E329 := E329 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E319 := E319 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E325 := E325 + 1;
      System.Tasking.Queuing'Elab_Body;
      E337 := E337 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E588 := E588 + 1;
      System.Tasking.Stages'Elab_Body;
      E584 := E584 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E343 := E343 + 1;
      Flyology.Cancellation'Elab_Spec;
      E316 := E316 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E364 := E364 + 1;
      E366 := E366 + 1;
      Unicode'Elab_Body;
      E127 := E127 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E408 := E408 + 1;
      Flyology.Bytes'Elab_Spec;
      E314 := E314 + 1;
      E345 := E345 + 1;
      E350 := E350 + 1;
      Flyology.Http'Elab_Spec;
      E352 := E352 + 1;
      E356 := E356 + 1;
      E391 := E391 + 1;
      E362 := E362 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E404 := E404 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E115 := E115 + 1;
      E445 := E445 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E453 := E453 + 1;
      E443 := E443 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E517 := E517 + 1;
      E525 := E525 + 1;
      E545 := E545 + 1;
      E489 := E489 + 1;
      E449 := E449 + 1;
      E451 := E451 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E447 := E447 + 1;
      Flyology.Object_Storage.Checksum_Engine'Elab_Spec;
      Flyology.Object_Storage.Checksum_Engine'Elab_Body;
      E441 := E441 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E547 := E547 + 1;
      E558 := E558 + 1;
      Flyology.Object_Storage.Server.Mfa'Elab_Spec;
      E561 := E561 + 1;
      Flyology.Object_Storage.Server.Object_Lambda_Responses'Elab_Spec;
      E562 := E562 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E431 := E431 + 1;
      Flyology.Object_Storage.Backends'Elab_Spec;
      E429 := E429 + 1;
      Flyology.Object_Storage.Backends.Bucket_Listing'Elab_Spec;
      E435 := E435 + 1;
      Flyology.Object_Storage.Backends.Listing'Elab_Spec;
      E437 := E437 + 1;
      Flyology.Object_Storage.Backends.Multipart_Listing'Elab_Spec;
      E439 := E439 + 1;
      Flyology.Object_Storage.Backends.Memory'Elab_Spec;
      Flyology.Object_Storage.Backends.Memory'Elab_Body;
      E433 := E433 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E397 := E397 + 1;
      Flyology.Io.Tls'Elab_Body;
      E401 := E401 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E393 := E393 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E411 := E411 + 1;
      E424 := E424 + 1;
      E360 := E360 + 1;
      Flyology.Http.Server'Elab_Spec;
      Flyology.Http.Server.Websocket_Deflate'Elab_Spec;
      E358 := E358 + 1;
      Flyology.Http.Server'Elab_Body;
      E354 := E354 + 1;
      E420 := E420 + 1;
      Flyology.Http.Server.Connections'Elab_Spec;
      Flyology.Http.Server.Connections'Elab_Body;
      E422 := E422 + 1;
      Flyology.Http.Server.Exchange_Backends'Elab_Spec;
      E418 := E418 + 1;
      Flyology.Http.Server.Applications'Elab_Spec;
      Flyology.Http.Server.Applications'Elab_Body;
      E415 := E415 + 1;
      Flyology.Object_Storage.Server.Authentication'Elab_Spec;
      E556 := E556 + 1;
      Flyology.Object_Storage.Server.Static_Credentials'Elab_Spec;
      Flyology.Object_Storage.Server.Static_Credentials'Elab_Body;
      E566 := E566 + 1;
      E568 := E568 + 1;
      E221 := E221 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E223 := E223 + 1;
      Unicode.Ccs'Elab_Spec;
      E141 := E141 + 1;
      E143 := E143 + 1;
      E146 := E146 + 1;
      E151 := E151 + 1;
      E154 := E154 + 1;
      E156 := E156 + 1;
      E158 := E158 + 1;
      E163 := E163 + 1;
      Unicode.Ces'Elab_Spec;
      E134 := E134 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E216 := E216 + 1;
      E227 := E227 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E225 := E225 + 1;
      E168 := E168 + 1;
      E166 := E166 + 1;
      E170 := E170 + 1;
      E172 := E172 + 1;
      Sax.Models'Elab_Spec;
      E213 := E213 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E211 := E211 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E235 := E235 + 1;
      E136 := E136 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E125 := E125 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E209 := E209 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E182 := E182 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E185 := E185 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E123 := E123 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E509 := E509 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E493 := E493 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E495 := E495 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E487 := E487 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E491 := E491 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E497 := E497 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E499 := E499 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E521 := E521 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E523 := E523 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E511 := E511 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E533 := E533 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E535 := E535 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E537 := E537 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E539 := E539 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E541 := E541 + 1;
      E483 := E483 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E481 := E481 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E485 := E485 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E519 := E519 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E505 := E505 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E531 := E531 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E543 := E543 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E549 := E549 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E551 := E551 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E553 := E553 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E515 := E515 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E503 := E503 + 1;
      E501 := E501 + 1;
      E507 := E507 + 1;
      E513 := E513 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E527 := E527 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E529 := E529 + 1;
      Flyology.Object_Storage.Server.Metadata_Results'Elab_Spec;
      E559 := E559 + 1;
      E564 := E564 + 1;
      Repro_S3_Server'Elab_Spec;
      Repro_S3_Server'Elab_Body;
      E293 := E293 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_wire_4");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_s3_server.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_wire_4.o
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
