pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_wire_probe.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_wire_probe.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E016 : Short_Integer; pragma Import (Ada, E016, "ada__exceptions_E");
   E012 : Short_Integer; pragma Import (Ada, E012, "system__soft_links_E");
   E010 : Short_Integer; pragma Import (Ada, E010, "system__exception_table_E");
   E019 : Short_Integer; pragma Import (Ada, E019, "system__exceptions_E");
   E050 : Short_Integer; pragma Import (Ada, E050, "system__soft_links__initialize_E");
   E179 : Short_Integer; pragma Import (Ada, E179, "ada__assertions_E");
   E161 : Short_Integer; pragma Import (Ada, E161, "ada__containers_E");
   E099 : Short_Integer; pragma Import (Ada, E099, "ada__io_exceptions_E");
   E007 : Short_Integer; pragma Import (Ada, E007, "ada__strings_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__utf_encoding_E");
   E267 : Short_Integer; pragma Import (Ada, E267, "gnat_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "interfaces__c_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "interfaces__c__strings_E");
   E135 : Short_Integer; pragma Import (Ada, E135, "system__os_lib_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__tags_E");
   E005 : Short_Integer; pragma Import (Ada, E005, "ada__strings__text_buffers_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__streams_E");
   E229 : Short_Integer; pragma Import (Ada, E229, "system__file_control_block_E");
   E101 : Short_Integer; pragma Import (Ada, E101, "system__finalization_root_E");
   E096 : Short_Integer; pragma Import (Ada, E096, "ada__finalization_E");
   E228 : Short_Integer; pragma Import (Ada, E228, "system__file_io_E");
   E233 : Short_Integer; pragma Import (Ada, E233, "system__storage_pools_E");
   E235 : Short_Integer; pragma Import (Ada, E235, "system__storage_pools__subpools_E");
   E133 : Short_Integer; pragma Import (Ada, E133, "ada__calendar_E");
   E293 : Short_Integer; pragma Import (Ada, E293, "ada__calendar__delays_E");
   E152 : Short_Integer; pragma Import (Ada, E152, "ada__calendar__time_zones_E");
   E224 : Short_Integer; pragma Import (Ada, E224, "ada__text_io_E");
   E388 : Short_Integer; pragma Import (Ada, E388, "gnat__secure_hashes_E");
   E390 : Short_Integer; pragma Import (Ada, E390, "gnat__secure_hashes__md5_E");
   E386 : Short_Integer; pragma Import (Ada, E386, "gnat__md5_E");
   E397 : Short_Integer; pragma Import (Ada, E397, "gnat__secure_hashes__sha1_E");
   E403 : Short_Integer; pragma Import (Ada, E403, "gnat__secure_hashes__sha2_common_E");
   E401 : Short_Integer; pragma Import (Ada, E401, "gnat__secure_hashes__sha2_32_E");
   E407 : Short_Integer; pragma Import (Ada, E407, "gnat__secure_hashes__sha2_64_E");
   E395 : Short_Integer; pragma Import (Ada, E395, "gnat__sha1_E");
   E399 : Short_Integer; pragma Import (Ada, E399, "gnat__sha256_E");
   E405 : Short_Integer; pragma Import (Ada, E405, "gnat__sha512_E");
   E184 : Short_Integer; pragma Import (Ada, E184, "system__flyology__scheduler_E");
   E168 : Short_Integer; pragma Import (Ada, E168, "ada__real_time_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "ada__strings__maps_E");
   E160 : Short_Integer; pragma Import (Ada, E160, "ada__strings__maps__constants_E");
   E084 : Short_Integer; pragma Import (Ada, E084, "ada__strings__unbounded_E");
   E468 : Short_Integer; pragma Import (Ada, E468, "gnat__directory_operations_E");
   E318 : Short_Integer; pragma Import (Ada, E318, "system__pool_global_E");
   E302 : Short_Integer; pragma Import (Ada, E302, "gnat__sockets_E");
   E305 : Short_Integer; pragma Import (Ada, E305, "gnat__sockets__poll_E");
   E312 : Short_Integer; pragma Import (Ada, E312, "gnat__sockets__thin_common_E");
   E307 : Short_Integer; pragma Import (Ada, E307, "gnat__sockets__thin_E");
   E252 : Short_Integer; pragma Import (Ada, E252, "system__tasking__initialization_E");
   E242 : Short_Integer; pragma Import (Ada, E242, "system__tasking__protected_objects_E");
   E248 : Short_Integer; pragma Import (Ada, E248, "system__tasking__protected_objects__entries_E");
   E260 : Short_Integer; pragma Import (Ada, E260, "system__tasking__queuing_E");
   E588 : Short_Integer; pragma Import (Ada, E588, "system__flyology__task_results_E");
   E584 : Short_Integer; pragma Import (Ada, E584, "system__tasking__stages_E");
   E266 : Short_Integer; pragma Import (Ada, E266, "flyology__wake_sources_E");
   E239 : Short_Integer; pragma Import (Ada, E239, "flyology__cancellation_E");
   E291 : Short_Integer; pragma Import (Ada, E291, "flyology__operations_E");
   E289 : Short_Integer; pragma Import (Ada, E289, "flyology__io_E");
   E420 : Short_Integer; pragma Import (Ada, E420, "unicode_E");
   E341 : Short_Integer; pragma Import (Ada, E341, "flyology__buffers_E");
   E231 : Short_Integer; pragma Import (Ada, E231, "flyology__bytes_E");
   E270 : Short_Integer; pragma Import (Ada, E270, "flyology__capacity_E");
   E275 : Short_Integer; pragma Import (Ada, E275, "flyology__counter_policy_E");
   E277 : Short_Integer; pragma Import (Ada, E277, "flyology__http_E");
   E281 : Short_Integer; pragma Import (Ada, E281, "flyology__http__expect_policy_E");
   E323 : Short_Integer; pragma Import (Ada, E323, "flyology__http__fixed_response_policy_E");
   E287 : Short_Integer; pragma Import (Ada, E287, "flyology__http_chunk_encoding_E");
   E336 : Short_Integer; pragma Import (Ada, E336, "flyology__io__sockets_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "flyology__object_storage_E");
   E123 : Short_Integer; pragma Import (Ada, E123, "flyology__object_storage__s3__core_E");
   E384 : Short_Integer; pragma Import (Ada, E384, "flyology__object_storage__s3__checksum_crc_E");
   E378 : Short_Integer; pragma Import (Ada, E378, "flyology__object_storage__s3__checksum_policy_E");
   E125 : Short_Integer; pragma Import (Ada, E125, "flyology__object_storage__s3__imf_dates_E");
   E527 : Short_Integer; pragma Import (Ada, E527, "flyology__object_storage__s3__model_E");
   E127 : Short_Integer; pragma Import (Ada, E127, "flyology__object_storage__s3__requests_E");
   E493 : Short_Integer; pragma Import (Ada, E493, "flyology__object_storage__s3__sigv4_encoding_E");
   E129 : Short_Integer; pragma Import (Ada, E129, "flyology__object_storage__s3__wire_core_E");
   E382 : Short_Integer; pragma Import (Ada, E382, "flyology__object_storage__secrets_E");
   E380 : Short_Integer; pragma Import (Ada, E380, "flyology__object_storage__s3__checksums_E");
   E376 : Short_Integer; pragma Import (Ada, E376, "flyology__object_storage__checksum_engine_E");
   E547 : Short_Integer; pragma Import (Ada, E547, "flyology__object_storage__s3__sigv4_E");
   E558 : Short_Integer; pragma Import (Ada, E558, "flyology__object_storage__s3__sigv4_verification_E");
   E561 : Short_Integer; pragma Import (Ada, E561, "flyology__object_storage__server__mfa_E");
   E562 : Short_Integer; pragma Import (Ada, E562, "flyology__object_storage__server__object_lambda_responses_E");
   E364 : Short_Integer; pragma Import (Ada, E364, "flyology__object_storage__tags_E");
   E362 : Short_Integer; pragma Import (Ada, E362, "flyology__object_storage__backends_E");
   E370 : Short_Integer; pragma Import (Ada, E370, "flyology__object_storage__backends__bucket_listing_E");
   E372 : Short_Integer; pragma Import (Ada, E372, "flyology__object_storage__backends__listing_E");
   E374 : Short_Integer; pragma Import (Ada, E374, "flyology__object_storage__backends__multipart_listing_E");
   E368 : Short_Integer; pragma Import (Ada, E368, "flyology__object_storage__backends__memory_E");
   E333 : Short_Integer; pragma Import (Ada, E333, "flyology__io__tls_E");
   E329 : Short_Integer; pragma Import (Ada, E329, "flyology__io__tls_driver_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "flyology__io__connections_E");
   E344 : Short_Integer; pragma Import (Ada, E344, "flyology__io__connections__drivers_E");
   E357 : Short_Integer; pragma Import (Ada, E357, "flyology__io__structured_servers_E");
   E285 : Short_Integer; pragma Import (Ada, E285, "flyology__websocket_deflate_policy_E");
   E279 : Short_Integer; pragma Import (Ada, E279, "flyology__http__server_E");
   E283 : Short_Integer; pragma Import (Ada, E283, "flyology__http__server__websocket_deflate_E");
   E353 : Short_Integer; pragma Import (Ada, E353, "flyology__http__server__connection_handlers_E");
   E355 : Short_Integer; pragma Import (Ada, E355, "flyology__http__server__connections_E");
   E351 : Short_Integer; pragma Import (Ada, E351, "flyology__http__server__exchange_backends_E");
   E348 : Short_Integer; pragma Import (Ada, E348, "flyology__http__server__applications_E");
   E556 : Short_Integer; pragma Import (Ada, E556, "flyology__object_storage__server__authentication_E");
   E566 : Short_Integer; pragma Import (Ada, E566, "flyology__object_storage__server__static_credentials_E");
   E568 : Short_Integer; pragma Import (Ada, E568, "repro_support_E");
   E479 : Short_Integer; pragma Import (Ada, E479, "sax__htable_E");
   E481 : Short_Integer; pragma Import (Ada, E481, "sax__pointers_E");
   E431 : Short_Integer; pragma Import (Ada, E431, "unicode__ccs_E");
   E433 : Short_Integer; pragma Import (Ada, E433, "unicode__ccs__iso_8859_1_E");
   E435 : Short_Integer; pragma Import (Ada, E435, "unicode__ccs__iso_8859_15_E");
   E440 : Short_Integer; pragma Import (Ada, E440, "unicode__ccs__iso_8859_2_E");
   E443 : Short_Integer; pragma Import (Ada, E443, "unicode__ccs__iso_8859_3_E");
   E445 : Short_Integer; pragma Import (Ada, E445, "unicode__ccs__iso_8859_4_E");
   E447 : Short_Integer; pragma Import (Ada, E447, "unicode__ccs__windows_1251_E");
   E452 : Short_Integer; pragma Import (Ada, E452, "unicode__ccs__windows_1252_E");
   E427 : Short_Integer; pragma Import (Ada, E427, "unicode__ces_E");
   E477 : Short_Integer; pragma Import (Ada, E477, "sax__symbols_E");
   E485 : Short_Integer; pragma Import (Ada, E485, "sax__locators_E");
   E483 : Short_Integer; pragma Import (Ada, E483, "sax__exceptions_E");
   E457 : Short_Integer; pragma Import (Ada, E457, "unicode__ces__utf32_E");
   E455 : Short_Integer; pragma Import (Ada, E455, "unicode__ces__basic_8bit_E");
   E459 : Short_Integer; pragma Import (Ada, E459, "unicode__ces__utf16_E");
   E461 : Short_Integer; pragma Import (Ada, E461, "unicode__ces__utf8_E");
   E474 : Short_Integer; pragma Import (Ada, E474, "sax__models_E");
   E472 : Short_Integer; pragma Import (Ada, E472, "sax__attributes_E");
   E487 : Short_Integer; pragma Import (Ada, E487, "sax__utils_E");
   E429 : Short_Integer; pragma Import (Ada, E429, "unicode__encodings_E");
   E418 : Short_Integer; pragma Import (Ada, E418, "input_sources_E");
   E470 : Short_Integer; pragma Import (Ada, E470, "input_sources__file_E");
   E463 : Short_Integer; pragma Import (Ada, E463, "input_sources__strings_E");
   E466 : Short_Integer; pragma Import (Ada, E466, "sax__readers_E");
   E416 : Short_Integer; pragma Import (Ada, E416, "flyology__object_storage__s3__xml_E");
   E513 : Short_Integer; pragma Import (Ada, E513, "flyology__object_storage__s3__acl_E");
   E497 : Short_Integer; pragma Import (Ada, E497, "flyology__object_storage__s3__bucket_controls_E");
   E499 : Short_Integer; pragma Import (Ada, E499, "flyology__object_storage__s3__buckets_E");
   E491 : Short_Integer; pragma Import (Ada, E491, "flyology__object_storage__s3__deletions_E");
   E495 : Short_Integer; pragma Import (Ada, E495, "flyology__object_storage__s3__attributes_E");
   E501 : Short_Integer; pragma Import (Ada, E501, "flyology__object_storage__s3__encryption_E");
   E503 : Short_Integer; pragma Import (Ada, E503, "flyology__object_storage__s3__errors_E");
   E523 : Short_Integer; pragma Import (Ada, E523, "flyology__object_storage__s3__lifecycle_E");
   E525 : Short_Integer; pragma Import (Ada, E525, "flyology__object_storage__s3__listings_E");
   E515 : Short_Integer; pragma Import (Ada, E515, "flyology__object_storage__s3__logging_E");
   E535 : Short_Integer; pragma Import (Ada, E535, "flyology__object_storage__s3__multipart_E");
   E537 : Short_Integer; pragma Import (Ada, E537, "flyology__object_storage__s3__multipart_uploads_E");
   E539 : Short_Integer; pragma Import (Ada, E539, "flyology__object_storage__s3__notifications_E");
   E541 : Short_Integer; pragma Import (Ada, E541, "flyology__object_storage__s3__object_lock_E");
   E543 : Short_Integer; pragma Import (Ada, E543, "flyology__object_storage__s3__object_reads_E");
   E414 : Short_Integer; pragma Import (Ada, E414, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E412 : Short_Integer; pragma Import (Ada, E412, "flyology__object_storage__s3__analytics_E");
   E489 : Short_Integer; pragma Import (Ada, E489, "flyology__object_storage__s3__annotations_E");
   E521 : Short_Integer; pragma Import (Ada, E521, "flyology__object_storage__s3__intelligent_tiering_E");
   E509 : Short_Integer; pragma Import (Ada, E509, "flyology__object_storage__s3__inventory_E");
   E533 : Short_Integer; pragma Import (Ada, E533, "flyology__object_storage__s3__metrics_E");
   E545 : Short_Integer; pragma Import (Ada, E545, "flyology__object_storage__s3__replication_E");
   E549 : Short_Integer; pragma Import (Ada, E549, "flyology__object_storage__s3__tagging_E");
   E551 : Short_Integer; pragma Import (Ada, E551, "flyology__object_storage__s3__versioning_E");
   E553 : Short_Integer; pragma Import (Ada, E553, "flyology__object_storage__s3__versions_E");
   E519 : Short_Integer; pragma Import (Ada, E519, "flyology__object_storage__s3__website_E");
   E507 : Short_Integer; pragma Import (Ada, E507, "flyology__object_storage__s3__xml_writers_E");
   E505 : Short_Integer; pragma Import (Ada, E505, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E511 : Short_Integer; pragma Import (Ada, E511, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E517 : Short_Integer; pragma Import (Ada, E517, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E529 : Short_Integer; pragma Import (Ada, E529, "flyology__object_storage__s3__metadata_configurations_E");
   E531 : Short_Integer; pragma Import (Ada, E531, "flyology__object_storage__s3__metadata_tables_E");
   E559 : Short_Integer; pragma Import (Ada, E559, "flyology__object_storage__server__metadata_results_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "flyology__object_storage__server__s3_applications_E");
   E131 : Short_Integer; pragma Import (Ada, E131, "repro_s3_server_E");

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
         E131 := E131 - 1;
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
         E531 := E531 - 1;
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E529 := E529 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__website__finalize_body");
      begin
         E519 := E519 - 1;
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
         E545 := E545 - 1;
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
         E533 := E533 - 1;
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
         E509 := E509 - 1;
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
         E521 := E521 - 1;
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
         E489 := E489 - 1;
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
         E412 := E412 - 1;
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
         E541 := E541 - 1;
         F24;
      end;
      declare
         procedure F25;
         pragma Import (Ada, F25, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E539 := E539 - 1;
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
         E537 := E537 - 1;
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
         E535 := E535 - 1;
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
         E515 := E515 - 1;
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
         E525 := E525 - 1;
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
         E523 := E523 - 1;
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
         E503 := E503 - 1;
         F37;
      end;
      declare
         procedure F38;
         pragma Import (Ada, F38, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E501 := E501 - 1;
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
         E495 := E495 - 1;
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
         E491 := E491 - 1;
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
         E499 := E499 - 1;
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
         E497 := E497 - 1;
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
         E513 := E513 - 1;
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
         E416 := E416 - 1;
         F50;
      end;
      E466 := E466 - 1;
      declare
         procedure F51;
         pragma Import (Ada, F51, "sax__readers__finalize_spec");
      begin
         F51;
      end;
      E463 := E463 - 1;
      declare
         procedure F52;
         pragma Import (Ada, F52, "input_sources__strings__finalize_spec");
      begin
         F52;
      end;
      E470 := E470 - 1;
      declare
         procedure F53;
         pragma Import (Ada, F53, "input_sources__file__finalize_spec");
      begin
         F53;
      end;
      E418 := E418 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "input_sources__finalize_spec");
      begin
         F54;
      end;
      E487 := E487 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "sax__utils__finalize_spec");
      begin
         F55;
      end;
      E472 := E472 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "sax__attributes__finalize_spec");
      begin
         F56;
      end;
      E483 := E483 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "sax__exceptions__finalize_spec");
      begin
         F57;
      end;
      E477 := E477 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__symbols__finalize_spec");
      begin
         F58;
      end;
      E481 := E481 - 1;
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
      E348 := E348 - 1;
      declare
         procedure F61;
         pragma Import (Ada, F61, "flyology__http__server__applications__finalize_spec");
      begin
         F61;
      end;
      E355 := E355 - 1;
      declare
         procedure F62;
         pragma Import (Ada, F62, "flyology__http__server__connections__finalize_spec");
      begin
         F62;
      end;
      E279 := E279 - 1;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__server__finalize_spec");
      begin
         F63;
      end;
      E344 := E344 - 1;
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
         E325 := E325 - 1;
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
         E333 := E333 - 1;
         F67;
      end;
      declare
         procedure F68;
         pragma Import (Ada, F68, "flyology__io__tls__finalize_spec");
      begin
         F68;
      end;
      E368 := E368 - 1;
      declare
         procedure F69;
         pragma Import (Ada, F69, "flyology__object_storage__backends__memory__finalize_spec");
      begin
         F69;
      end;
      E374 := E374 - 1;
      declare
         procedure F70;
         pragma Import (Ada, F70, "flyology__object_storage__backends__multipart_listing__finalize_spec");
      begin
         F70;
      end;
      E372 := E372 - 1;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__object_storage__backends__listing__finalize_spec");
      begin
         F71;
      end;
      E370 := E370 - 1;
      declare
         procedure F72;
         pragma Import (Ada, F72, "flyology__object_storage__backends__bucket_listing__finalize_spec");
      begin
         F72;
      end;
      E362 := E362 - 1;
      declare
         procedure F73;
         pragma Import (Ada, F73, "flyology__object_storage__backends__finalize_spec");
      begin
         F73;
      end;
      E364 := E364 - 1;
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
      E376 := E376 - 1;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__object_storage__checksum_engine__finalize_spec");
      begin
         F77;
      end;
      E380 := E380 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F78;
      end;
      E336 := E336 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__io__sockets__finalize_spec");
      begin
         F79;
      end;
      E231 := E231 - 1;
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
         E341 := E341 - 1;
         F81;
      end;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__buffers__finalize_spec");
      begin
         F82;
      end;
      E291 := E291 - 1;
      E289 := E289 - 1;
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
      E266 := E266 - 1;
      declare
         procedure F85;
         pragma Import (Ada, F85, "flyology__wake_sources__finalize_spec");
      begin
         F85;
      end;
      E248 := E248 - 1;
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
         E302 := E302 - 1;
         F87;
      end;
      declare
         procedure F88;
         pragma Import (Ada, F88, "gnat__sockets__finalize_spec");
      begin
         F88;
      end;
      E318 := E318 - 1;
      declare
         procedure F89;
         pragma Import (Ada, F89, "system__pool_global__finalize_spec");
      begin
         F89;
      end;
      E084 := E084 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "ada__strings__unbounded__finalize_spec");
      begin
         F90;
      end;
      E405 := E405 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "gnat__sha512__finalize_spec");
      begin
         F91;
      end;
      E399 := E399 - 1;
      declare
         procedure F92;
         pragma Import (Ada, F92, "gnat__sha256__finalize_spec");
      begin
         F92;
      end;
      E395 := E395 - 1;
      declare
         procedure F93;
         pragma Import (Ada, F93, "gnat__sha1__finalize_spec");
      begin
         F93;
      end;
      E386 := E386 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "gnat__md5__finalize_spec");
      begin
         F94;
      end;
      E224 := E224 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "ada__text_io__finalize_spec");
      begin
         F95;
      end;
      E235 := E235 - 1;
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
         E228 := E228 - 1;
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
      E010 := E010 + 1;
      System.Exceptions'Elab_Spec;
      E019 := E019 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E050 := E050 + 1;
      E012 := E012 + 1;
      E016 := E016 + 1;
      Ada.Assertions'Elab_Spec;
      E179 := E179 + 1;
      Ada.Containers'Elab_Spec;
      E161 := E161 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E099 := E099 + 1;
      Ada.Strings'Elab_Spec;
      E007 := E007 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E054 := E054 + 1;
      Gnat'Elab_Spec;
      E267 := E267 + 1;
      Interfaces.C'Elab_Spec;
      E089 := E089 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E314 := E314 + 1;
      System.Os_Lib'Elab_Body;
      E135 := E135 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E062 := E062 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E005 := E005 + 1;
      Ada.Streams'Elab_Spec;
      E098 := E098 + 1;
      System.File_Control_Block'Elab_Spec;
      E229 := E229 + 1;
      System.Finalization_Root'Elab_Spec;
      E101 := E101 + 1;
      Ada.Finalization'Elab_Spec;
      E096 := E096 + 1;
      System.File_Io'Elab_Body;
      E228 := E228 + 1;
      System.Storage_Pools'Elab_Spec;
      E233 := E233 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E235 := E235 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E133 := E133 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E293 := E293 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E152 := E152 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E224 := E224 + 1;
      E388 := E388 + 1;
      E390 := E390 + 1;
      Gnat.Md5'Elab_Spec;
      E386 := E386 + 1;
      E397 := E397 + 1;
      E403 := E403 + 1;
      E401 := E401 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E407 := E407 + 1;
      Gnat.Sha1'Elab_Spec;
      E395 := E395 + 1;
      Gnat.Sha256'Elab_Spec;
      E399 := E399 + 1;
      Gnat.Sha512'Elab_Spec;
      E405 := E405 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E184 := E184 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E168 := E168 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E103 := E103 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E160 := E160 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E084 := E084 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E468 := E468 + 1;
      System.Pool_Global'Elab_Spec;
      E318 := E318 + 1;
      Gnat.Sockets'Elab_Spec;
      Gnat.Sockets.Thin_Common'Elab_Spec;
      E312 := E312 + 1;
      E307 := E307 + 1;
      Gnat.Sockets'Elab_Body;
      E302 := E302 + 1;
      E305 := E305 + 1;
      System.Tasking.Initialization'Elab_Body;
      E252 := E252 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E242 := E242 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E248 := E248 + 1;
      System.Tasking.Queuing'Elab_Body;
      E260 := E260 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E588 := E588 + 1;
      System.Tasking.Stages'Elab_Body;
      E584 := E584 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E266 := E266 + 1;
      Flyology.Cancellation'Elab_Spec;
      E239 := E239 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E289 := E289 + 1;
      E291 := E291 + 1;
      Unicode'Elab_Body;
      E420 := E420 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E341 := E341 + 1;
      Flyology.Bytes'Elab_Spec;
      E231 := E231 + 1;
      E270 := E270 + 1;
      E275 := E275 + 1;
      Flyology.Http'Elab_Spec;
      E277 := E277 + 1;
      E281 := E281 + 1;
      E323 := E323 + 1;
      E287 := E287 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E336 := E336 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E077 := E077 + 1;
      E123 := E123 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E384 := E384 + 1;
      E378 := E378 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E125 := E125 + 1;
      E527 := E527 + 1;
      E127 := E127 + 1;
      E493 := E493 + 1;
      E129 := E129 + 1;
      E382 := E382 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E380 := E380 + 1;
      Flyology.Object_Storage.Checksum_Engine'Elab_Spec;
      Flyology.Object_Storage.Checksum_Engine'Elab_Body;
      E376 := E376 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E547 := E547 + 1;
      E558 := E558 + 1;
      Flyology.Object_Storage.Server.Mfa'Elab_Spec;
      E561 := E561 + 1;
      Flyology.Object_Storage.Server.Object_Lambda_Responses'Elab_Spec;
      E562 := E562 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E364 := E364 + 1;
      Flyology.Object_Storage.Backends'Elab_Spec;
      E362 := E362 + 1;
      Flyology.Object_Storage.Backends.Bucket_Listing'Elab_Spec;
      E370 := E370 + 1;
      Flyology.Object_Storage.Backends.Listing'Elab_Spec;
      E372 := E372 + 1;
      Flyology.Object_Storage.Backends.Multipart_Listing'Elab_Spec;
      E374 := E374 + 1;
      Flyology.Object_Storage.Backends.Memory'Elab_Spec;
      Flyology.Object_Storage.Backends.Memory'Elab_Body;
      E368 := E368 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E329 := E329 + 1;
      Flyology.Io.Tls'Elab_Body;
      E333 := E333 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E325 := E325 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E344 := E344 + 1;
      E357 := E357 + 1;
      E285 := E285 + 1;
      Flyology.Http.Server'Elab_Spec;
      Flyology.Http.Server.Websocket_Deflate'Elab_Spec;
      E283 := E283 + 1;
      Flyology.Http.Server'Elab_Body;
      E279 := E279 + 1;
      E353 := E353 + 1;
      Flyology.Http.Server.Connections'Elab_Spec;
      Flyology.Http.Server.Connections'Elab_Body;
      E355 := E355 + 1;
      Flyology.Http.Server.Exchange_Backends'Elab_Spec;
      E351 := E351 + 1;
      Flyology.Http.Server.Applications'Elab_Spec;
      Flyology.Http.Server.Applications'Elab_Body;
      E348 := E348 + 1;
      Flyology.Object_Storage.Server.Authentication'Elab_Spec;
      E556 := E556 + 1;
      Flyology.Object_Storage.Server.Static_Credentials'Elab_Spec;
      Flyology.Object_Storage.Server.Static_Credentials'Elab_Body;
      E566 := E566 + 1;
      E568 := E568 + 1;
      E479 := E479 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E481 := E481 + 1;
      Unicode.Ccs'Elab_Spec;
      E431 := E431 + 1;
      E433 := E433 + 1;
      E435 := E435 + 1;
      E440 := E440 + 1;
      E443 := E443 + 1;
      E445 := E445 + 1;
      E447 := E447 + 1;
      E452 := E452 + 1;
      Unicode.Ces'Elab_Spec;
      E427 := E427 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E477 := E477 + 1;
      E485 := E485 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E483 := E483 + 1;
      E457 := E457 + 1;
      E455 := E455 + 1;
      E459 := E459 + 1;
      E461 := E461 + 1;
      Sax.Models'Elab_Spec;
      E474 := E474 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E472 := E472 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E487 := E487 + 1;
      E429 := E429 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E418 := E418 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E470 := E470 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E463 := E463 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E466 := E466 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E416 := E416 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E513 := E513 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E497 := E497 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E499 := E499 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E491 := E491 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E495 := E495 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E501 := E501 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E503 := E503 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E523 := E523 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E525 := E525 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E515 := E515 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E535 := E535 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E537 := E537 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E539 := E539 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E541 := E541 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E543 := E543 + 1;
      E414 := E414 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E412 := E412 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E489 := E489 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E521 := E521 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E509 := E509 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E533 := E533 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E545 := E545 + 1;
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
      E519 := E519 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E507 := E507 + 1;
      E505 := E505 + 1;
      E511 := E511 + 1;
      E517 := E517 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E529 := E529 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E531 := E531 + 1;
      Flyology.Object_Storage.Server.Metadata_Results'Elab_Spec;
      E559 := E559 + 1;
      E564 := E564 + 1;
      Repro_S3_Server'Elab_Spec;
      Repro_S3_Server'Elab_Body;
      E131 := E131 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_wire_probe");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_wire_probe.o
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
