pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_sigv4_2.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_sigv4_2.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E005 : Short_Integer; pragma Import (Ada, E005, "ada__exceptions_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "system__soft_links_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__exception_table_E");
   E023 : Short_Integer; pragma Import (Ada, E023, "system__exceptions_E");
   E018 : Short_Integer; pragma Import (Ada, E018, "system__soft_links__initialize_E");
   E226 : Short_Integer; pragma Import (Ada, E226, "ada__assertions_E");
   E198 : Short_Integer; pragma Import (Ada, E198, "ada__containers_E");
   E099 : Short_Integer; pragma Import (Ada, E099, "ada__io_exceptions_E");
   E052 : Short_Integer; pragma Import (Ada, E052, "ada__strings_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__utf_encoding_E");
   E139 : Short_Integer; pragma Import (Ada, E139, "gnat_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "interfaces__c_E");
   E307 : Short_Integer; pragma Import (Ada, E307, "interfaces__c__strings_E");
   E160 : Short_Integer; pragma Import (Ada, E160, "system__os_lib_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__tags_E");
   E051 : Short_Integer; pragma Import (Ada, E051, "ada__strings__text_buffers_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__streams_E");
   E365 : Short_Integer; pragma Import (Ada, E365, "system__file_control_block_E");
   E101 : Short_Integer; pragma Import (Ada, E101, "system__finalization_root_E");
   E096 : Short_Integer; pragma Import (Ada, E096, "ada__finalization_E");
   E364 : Short_Integer; pragma Import (Ada, E364, "system__file_io_E");
   E130 : Short_Integer; pragma Import (Ada, E130, "system__storage_pools_E");
   E132 : Short_Integer; pragma Import (Ada, E132, "system__storage_pools__subpools_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "ada__calendar_E");
   E208 : Short_Integer; pragma Import (Ada, E208, "ada__calendar__delays_E");
   E177 : Short_Integer; pragma Import (Ada, E177, "ada__calendar__time_zones_E");
   E360 : Short_Integer; pragma Import (Ada, E360, "ada__text_io_E");
   E143 : Short_Integer; pragma Import (Ada, E143, "gnat__secure_hashes_E");
   E406 : Short_Integer; pragma Import (Ada, E406, "gnat__secure_hashes__md5_E");
   E404 : Short_Integer; pragma Import (Ada, E404, "gnat__md5_E");
   E410 : Short_Integer; pragma Import (Ada, E410, "gnat__secure_hashes__sha1_E");
   E150 : Short_Integer; pragma Import (Ada, E150, "gnat__secure_hashes__sha2_common_E");
   E145 : Short_Integer; pragma Import (Ada, E145, "gnat__secure_hashes__sha2_32_E");
   E414 : Short_Integer; pragma Import (Ada, E414, "gnat__secure_hashes__sha2_64_E");
   E408 : Short_Integer; pragma Import (Ada, E408, "gnat__sha1_E");
   E141 : Short_Integer; pragma Import (Ada, E141, "gnat__sha256_E");
   E412 : Short_Integer; pragma Import (Ada, E412, "gnat__sha512_E");
   E231 : Short_Integer; pragma Import (Ada, E231, "system__flyology__scheduler_E");
   E316 : Short_Integer; pragma Import (Ada, E316, "ada__real_time_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "ada__strings__maps_E");
   E187 : Short_Integer; pragma Import (Ada, E187, "ada__strings__maps__constants_E");
   E084 : Short_Integer; pragma Import (Ada, E084, "ada__strings__unbounded_E");
   E475 : Short_Integer; pragma Import (Ada, E475, "gnat__directory_operations_E");
   E311 : Short_Integer; pragma Import (Ada, E311, "system__pool_global_E");
   E295 : Short_Integer; pragma Import (Ada, E295, "gnat__sockets_E");
   E298 : Short_Integer; pragma Import (Ada, E298, "gnat__sockets__poll_E");
   E305 : Short_Integer; pragma Import (Ada, E305, "gnat__sockets__thin_common_E");
   E300 : Short_Integer; pragma Import (Ada, E300, "gnat__sockets__thin_E");
   E271 : Short_Integer; pragma Import (Ada, E271, "system__tasking__initialization_E");
   E213 : Short_Integer; pragma Import (Ada, E213, "system__tasking__protected_objects_E");
   E267 : Short_Integer; pragma Import (Ada, E267, "system__tasking__protected_objects__entries_E");
   E279 : Short_Integer; pragma Import (Ada, E279, "system__tasking__queuing_E");
   E588 : Short_Integer; pragma Import (Ada, E588, "system__flyology__task_results_E");
   E584 : Short_Integer; pragma Import (Ada, E584, "system__tasking__stages_E");
   E285 : Short_Integer; pragma Import (Ada, E285, "flyology__wake_sources_E");
   E210 : Short_Integer; pragma Import (Ada, E210, "flyology__cancellation_E");
   E206 : Short_Integer; pragma Import (Ada, E206, "flyology__operations_E");
   E204 : Short_Integer; pragma Import (Ada, E204, "flyology__io_E");
   E427 : Short_Integer; pragma Import (Ada, E427, "unicode_E");
   E337 : Short_Integer; pragma Import (Ada, E337, "flyology__buffers_E");
   E197 : Short_Integer; pragma Import (Ada, E197, "flyology__bytes_E");
   E340 : Short_Integer; pragma Import (Ada, E340, "flyology__capacity_E");
   E367 : Short_Integer; pragma Import (Ada, E367, "flyology__counter_policy_E");
   E184 : Short_Integer; pragma Import (Ada, E184, "flyology__http_E");
   E191 : Short_Integer; pragma Import (Ada, E191, "flyology__http__expect_policy_E");
   E318 : Short_Integer; pragma Import (Ada, E318, "flyology__http__fixed_response_policy_E");
   E202 : Short_Integer; pragma Import (Ada, E202, "flyology__http_chunk_encoding_E");
   E332 : Short_Integer; pragma Import (Ada, E332, "flyology__io__sockets_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "flyology__object_storage_E");
   E396 : Short_Integer; pragma Import (Ada, E396, "flyology__object_storage__s3__core_E");
   E402 : Short_Integer; pragma Import (Ada, E402, "flyology__object_storage__s3__checksum_crc_E");
   E394 : Short_Integer; pragma Import (Ada, E394, "flyology__object_storage__s3__checksum_policy_E");
   E526 : Short_Integer; pragma Import (Ada, E526, "flyology__object_storage__s3__imf_dates_E");
   E534 : Short_Integer; pragma Import (Ada, E534, "flyology__object_storage__s3__model_E");
   E554 : Short_Integer; pragma Import (Ada, E554, "flyology__object_storage__s3__requests_E");
   E126 : Short_Integer; pragma Import (Ada, E126, "flyology__object_storage__s3__sigv4_encoding_E");
   E400 : Short_Integer; pragma Import (Ada, E400, "flyology__object_storage__s3__wire_core_E");
   E128 : Short_Integer; pragma Import (Ada, E128, "flyology__object_storage__secrets_E");
   E398 : Short_Integer; pragma Import (Ada, E398, "flyology__object_storage__s3__checksums_E");
   E392 : Short_Integer; pragma Import (Ada, E392, "flyology__object_storage__checksum_engine_E");
   E138 : Short_Integer; pragma Import (Ada, E138, "flyology__object_storage__s3__sigv4_E");
   E152 : Short_Integer; pragma Import (Ada, E152, "flyology__object_storage__s3__sigv4_verification_E");
   E563 : Short_Integer; pragma Import (Ada, E563, "flyology__object_storage__server__mfa_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "flyology__object_storage__server__object_lambda_responses_E");
   E380 : Short_Integer; pragma Import (Ada, E380, "flyology__object_storage__tags_E");
   E378 : Short_Integer; pragma Import (Ada, E378, "flyology__object_storage__backends_E");
   E386 : Short_Integer; pragma Import (Ada, E386, "flyology__object_storage__backends__bucket_listing_E");
   E388 : Short_Integer; pragma Import (Ada, E388, "flyology__object_storage__backends__listing_E");
   E390 : Short_Integer; pragma Import (Ada, E390, "flyology__object_storage__backends__multipart_listing_E");
   E384 : Short_Integer; pragma Import (Ada, E384, "flyology__object_storage__backends__memory_E");
   E329 : Short_Integer; pragma Import (Ada, E329, "flyology__io__tls_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "flyology__io__tls_driver_E");
   E320 : Short_Integer; pragma Import (Ada, E320, "flyology__io__connections_E");
   E344 : Short_Integer; pragma Import (Ada, E344, "flyology__io__connections__drivers_E");
   E373 : Short_Integer; pragma Import (Ada, E373, "flyology__io__structured_servers_E");
   E195 : Short_Integer; pragma Import (Ada, E195, "flyology__websocket_deflate_policy_E");
   E189 : Short_Integer; pragma Import (Ada, E189, "flyology__http__server_E");
   E193 : Short_Integer; pragma Import (Ada, E193, "flyology__http__server__websocket_deflate_E");
   E369 : Short_Integer; pragma Import (Ada, E369, "flyology__http__server__connection_handlers_E");
   E371 : Short_Integer; pragma Import (Ada, E371, "flyology__http__server__connections_E");
   E351 : Short_Integer; pragma Import (Ada, E351, "flyology__http__server__exchange_backends_E");
   E348 : Short_Integer; pragma Import (Ada, E348, "flyology__http__server__applications_E");
   E156 : Short_Integer; pragma Import (Ada, E156, "flyology__object_storage__server__authentication_E");
   E123 : Short_Integer; pragma Import (Ada, E123, "flyology__object_storage__server__static_credentials_E");
   E568 : Short_Integer; pragma Import (Ada, E568, "repro_support_E");
   E486 : Short_Integer; pragma Import (Ada, E486, "sax__htable_E");
   E488 : Short_Integer; pragma Import (Ada, E488, "sax__pointers_E");
   E438 : Short_Integer; pragma Import (Ada, E438, "unicode__ccs_E");
   E440 : Short_Integer; pragma Import (Ada, E440, "unicode__ccs__iso_8859_1_E");
   E442 : Short_Integer; pragma Import (Ada, E442, "unicode__ccs__iso_8859_15_E");
   E447 : Short_Integer; pragma Import (Ada, E447, "unicode__ccs__iso_8859_2_E");
   E450 : Short_Integer; pragma Import (Ada, E450, "unicode__ccs__iso_8859_3_E");
   E452 : Short_Integer; pragma Import (Ada, E452, "unicode__ccs__iso_8859_4_E");
   E454 : Short_Integer; pragma Import (Ada, E454, "unicode__ccs__windows_1251_E");
   E459 : Short_Integer; pragma Import (Ada, E459, "unicode__ccs__windows_1252_E");
   E434 : Short_Integer; pragma Import (Ada, E434, "unicode__ces_E");
   E484 : Short_Integer; pragma Import (Ada, E484, "sax__symbols_E");
   E492 : Short_Integer; pragma Import (Ada, E492, "sax__locators_E");
   E490 : Short_Integer; pragma Import (Ada, E490, "sax__exceptions_E");
   E464 : Short_Integer; pragma Import (Ada, E464, "unicode__ces__utf32_E");
   E462 : Short_Integer; pragma Import (Ada, E462, "unicode__ces__basic_8bit_E");
   E466 : Short_Integer; pragma Import (Ada, E466, "unicode__ces__utf16_E");
   E468 : Short_Integer; pragma Import (Ada, E468, "unicode__ces__utf8_E");
   E481 : Short_Integer; pragma Import (Ada, E481, "sax__models_E");
   E479 : Short_Integer; pragma Import (Ada, E479, "sax__attributes_E");
   E494 : Short_Integer; pragma Import (Ada, E494, "sax__utils_E");
   E436 : Short_Integer; pragma Import (Ada, E436, "unicode__encodings_E");
   E425 : Short_Integer; pragma Import (Ada, E425, "input_sources_E");
   E477 : Short_Integer; pragma Import (Ada, E477, "input_sources__file_E");
   E470 : Short_Integer; pragma Import (Ada, E470, "input_sources__strings_E");
   E473 : Short_Integer; pragma Import (Ada, E473, "sax__readers_E");
   E423 : Short_Integer; pragma Import (Ada, E423, "flyology__object_storage__s3__xml_E");
   E518 : Short_Integer; pragma Import (Ada, E518, "flyology__object_storage__s3__acl_E");
   E502 : Short_Integer; pragma Import (Ada, E502, "flyology__object_storage__s3__bucket_controls_E");
   E504 : Short_Integer; pragma Import (Ada, E504, "flyology__object_storage__s3__buckets_E");
   E498 : Short_Integer; pragma Import (Ada, E498, "flyology__object_storage__s3__deletions_E");
   E500 : Short_Integer; pragma Import (Ada, E500, "flyology__object_storage__s3__attributes_E");
   E506 : Short_Integer; pragma Import (Ada, E506, "flyology__object_storage__s3__encryption_E");
   E508 : Short_Integer; pragma Import (Ada, E508, "flyology__object_storage__s3__errors_E");
   E530 : Short_Integer; pragma Import (Ada, E530, "flyology__object_storage__s3__lifecycle_E");
   E532 : Short_Integer; pragma Import (Ada, E532, "flyology__object_storage__s3__listings_E");
   E520 : Short_Integer; pragma Import (Ada, E520, "flyology__object_storage__s3__logging_E");
   E542 : Short_Integer; pragma Import (Ada, E542, "flyology__object_storage__s3__multipart_E");
   E544 : Short_Integer; pragma Import (Ada, E544, "flyology__object_storage__s3__multipart_uploads_E");
   E546 : Short_Integer; pragma Import (Ada, E546, "flyology__object_storage__s3__notifications_E");
   E548 : Short_Integer; pragma Import (Ada, E548, "flyology__object_storage__s3__object_lock_E");
   E550 : Short_Integer; pragma Import (Ada, E550, "flyology__object_storage__s3__object_reads_E");
   E421 : Short_Integer; pragma Import (Ada, E421, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E419 : Short_Integer; pragma Import (Ada, E419, "flyology__object_storage__s3__analytics_E");
   E496 : Short_Integer; pragma Import (Ada, E496, "flyology__object_storage__s3__annotations_E");
   E528 : Short_Integer; pragma Import (Ada, E528, "flyology__object_storage__s3__intelligent_tiering_E");
   E514 : Short_Integer; pragma Import (Ada, E514, "flyology__object_storage__s3__inventory_E");
   E540 : Short_Integer; pragma Import (Ada, E540, "flyology__object_storage__s3__metrics_E");
   E552 : Short_Integer; pragma Import (Ada, E552, "flyology__object_storage__s3__replication_E");
   E556 : Short_Integer; pragma Import (Ada, E556, "flyology__object_storage__s3__tagging_E");
   E558 : Short_Integer; pragma Import (Ada, E558, "flyology__object_storage__s3__versioning_E");
   E560 : Short_Integer; pragma Import (Ada, E560, "flyology__object_storage__s3__versions_E");
   E524 : Short_Integer; pragma Import (Ada, E524, "flyology__object_storage__s3__website_E");
   E512 : Short_Integer; pragma Import (Ada, E512, "flyology__object_storage__s3__xml_writers_E");
   E510 : Short_Integer; pragma Import (Ada, E510, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E516 : Short_Integer; pragma Import (Ada, E516, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E522 : Short_Integer; pragma Import (Ada, E522, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E536 : Short_Integer; pragma Import (Ada, E536, "flyology__object_storage__s3__metadata_configurations_E");
   E538 : Short_Integer; pragma Import (Ada, E538, "flyology__object_storage__s3__metadata_tables_E");
   E561 : Short_Integer; pragma Import (Ada, E561, "flyology__object_storage__server__metadata_results_E");
   E566 : Short_Integer; pragma Import (Ada, E566, "flyology__object_storage__server__s3_applications_E");
   E353 : Short_Integer; pragma Import (Ada, E353, "repro_s3_server_E");
   E592 : Short_Integer; pragma Import (Ada, E592, "repro_sigv4_support_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "repro_sigv4_support__finalize_body");
      begin
         E592 := E592 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "repro_sigv4_support__finalize_spec");
      begin
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "repro_s3_server__finalize_body");
      begin
         E353 := E353 - 1;
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "repro_s3_server__finalize_spec");
      begin
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__server__metadata_results__finalize_spec");
      begin
         E561 := E561 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__metadata_tables__finalize_body");
      begin
         E538 := E538 - 1;
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E536 := E536 - 1;
         F7;
      end;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology__object_storage__s3__website__finalize_body");
      begin
         E524 := E524 - 1;
         F8;
      end;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology__object_storage__s3__website__finalize_spec");
      begin
         F9;
      end;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology__object_storage__s3__versions__finalize_body");
      begin
         E560 := E560 - 1;
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__versions__finalize_spec");
      begin
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__versioning__finalize_body");
      begin
         E558 := E558 - 1;
         F12;
      end;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology__object_storage__s3__tagging__finalize_body");
      begin
         E556 := E556 - 1;
         F13;
      end;
      declare
         procedure F14;
         pragma Import (Ada, F14, "flyology__object_storage__s3__replication__finalize_body");
      begin
         E552 := E552 - 1;
         F14;
      end;
      declare
         procedure F15;
         pragma Import (Ada, F15, "flyology__object_storage__s3__replication__finalize_spec");
      begin
         F15;
      end;
      declare
         procedure F16;
         pragma Import (Ada, F16, "flyology__object_storage__s3__metrics__finalize_body");
      begin
         E540 := E540 - 1;
         F16;
      end;
      declare
         procedure F17;
         pragma Import (Ada, F17, "flyology__object_storage__s3__metrics__finalize_spec");
      begin
         F17;
      end;
      declare
         procedure F18;
         pragma Import (Ada, F18, "flyology__object_storage__s3__inventory__finalize_body");
      begin
         E514 := E514 - 1;
         F18;
      end;
      declare
         procedure F19;
         pragma Import (Ada, F19, "flyology__object_storage__s3__inventory__finalize_spec");
      begin
         F19;
      end;
      declare
         procedure F20;
         pragma Import (Ada, F20, "flyology__object_storage__s3__intelligent_tiering__finalize_body");
      begin
         E528 := E528 - 1;
         F20;
      end;
      declare
         procedure F21;
         pragma Import (Ada, F21, "flyology__object_storage__s3__intelligent_tiering__finalize_spec");
      begin
         F21;
      end;
      declare
         procedure F22;
         pragma Import (Ada, F22, "flyology__object_storage__s3__annotations__finalize_body");
      begin
         E496 := E496 - 1;
         F22;
      end;
      declare
         procedure F23;
         pragma Import (Ada, F23, "flyology__object_storage__s3__annotations__finalize_spec");
      begin
         F23;
      end;
      declare
         procedure F24;
         pragma Import (Ada, F24, "flyology__object_storage__s3__analytics__finalize_body");
      begin
         E419 := E419 - 1;
         F24;
      end;
      declare
         procedure F25;
         pragma Import (Ada, F25, "flyology__object_storage__s3__analytics__finalize_spec");
      begin
         F25;
      end;
      declare
         procedure F26;
         pragma Import (Ada, F26, "flyology__object_storage__s3__object_lock__finalize_body");
      begin
         E548 := E548 - 1;
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E546 := E546 - 1;
         F27;
      end;
      declare
         procedure F28;
         pragma Import (Ada, F28, "flyology__object_storage__s3__notifications__finalize_spec");
      begin
         F28;
      end;
      declare
         procedure F29;
         pragma Import (Ada, F29, "flyology__object_storage__s3__multipart_uploads__finalize_body");
      begin
         E544 := E544 - 1;
         F29;
      end;
      declare
         procedure F30;
         pragma Import (Ada, F30, "flyology__object_storage__s3__multipart_uploads__finalize_spec");
      begin
         F30;
      end;
      declare
         procedure F31;
         pragma Import (Ada, F31, "flyology__object_storage__s3__multipart__finalize_body");
      begin
         E542 := E542 - 1;
         F31;
      end;
      declare
         procedure F32;
         pragma Import (Ada, F32, "flyology__object_storage__s3__multipart__finalize_spec");
      begin
         F32;
      end;
      declare
         procedure F33;
         pragma Import (Ada, F33, "flyology__object_storage__s3__logging__finalize_body");
      begin
         E520 := E520 - 1;
         F33;
      end;
      declare
         procedure F34;
         pragma Import (Ada, F34, "flyology__object_storage__s3__logging__finalize_spec");
      begin
         F34;
      end;
      declare
         procedure F35;
         pragma Import (Ada, F35, "flyology__object_storage__s3__listings__finalize_body");
      begin
         E532 := E532 - 1;
         F35;
      end;
      declare
         procedure F36;
         pragma Import (Ada, F36, "flyology__object_storage__s3__listings__finalize_spec");
      begin
         F36;
      end;
      declare
         procedure F37;
         pragma Import (Ada, F37, "flyology__object_storage__s3__lifecycle__finalize_body");
      begin
         E530 := E530 - 1;
         F37;
      end;
      declare
         procedure F38;
         pragma Import (Ada, F38, "flyology__object_storage__s3__lifecycle__finalize_spec");
      begin
         F38;
      end;
      declare
         procedure F39;
         pragma Import (Ada, F39, "flyology__object_storage__s3__errors__finalize_body");
      begin
         E508 := E508 - 1;
         F39;
      end;
      declare
         procedure F40;
         pragma Import (Ada, F40, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E506 := E506 - 1;
         F40;
      end;
      declare
         procedure F41;
         pragma Import (Ada, F41, "flyology__object_storage__s3__encryption__finalize_spec");
      begin
         F41;
      end;
      declare
         procedure F42;
         pragma Import (Ada, F42, "flyology__object_storage__s3__attributes__finalize_body");
      begin
         E500 := E500 - 1;
         F42;
      end;
      declare
         procedure F43;
         pragma Import (Ada, F43, "flyology__object_storage__s3__attributes__finalize_spec");
      begin
         F43;
      end;
      declare
         procedure F44;
         pragma Import (Ada, F44, "flyology__object_storage__s3__deletions__finalize_body");
      begin
         E498 := E498 - 1;
         F44;
      end;
      declare
         procedure F45;
         pragma Import (Ada, F45, "flyology__object_storage__s3__deletions__finalize_spec");
      begin
         F45;
      end;
      declare
         procedure F46;
         pragma Import (Ada, F46, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E504 := E504 - 1;
         F46;
      end;
      declare
         procedure F47;
         pragma Import (Ada, F47, "flyology__object_storage__s3__buckets__finalize_spec");
      begin
         F47;
      end;
      declare
         procedure F48;
         pragma Import (Ada, F48, "flyology__object_storage__s3__bucket_controls__finalize_body");
      begin
         E502 := E502 - 1;
         F48;
      end;
      declare
         procedure F49;
         pragma Import (Ada, F49, "flyology__object_storage__s3__bucket_controls__finalize_spec");
      begin
         F49;
      end;
      declare
         procedure F50;
         pragma Import (Ada, F50, "flyology__object_storage__s3__acl__finalize_body");
      begin
         E518 := E518 - 1;
         F50;
      end;
      declare
         procedure F51;
         pragma Import (Ada, F51, "flyology__object_storage__s3__acl__finalize_spec");
      begin
         F51;
      end;
      declare
         procedure F52;
         pragma Import (Ada, F52, "flyology__object_storage__s3__xml__finalize_body");
      begin
         E423 := E423 - 1;
         F52;
      end;
      E473 := E473 - 1;
      declare
         procedure F53;
         pragma Import (Ada, F53, "sax__readers__finalize_spec");
      begin
         F53;
      end;
      E470 := E470 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "input_sources__strings__finalize_spec");
      begin
         F54;
      end;
      E477 := E477 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "input_sources__file__finalize_spec");
      begin
         F55;
      end;
      E425 := E425 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "input_sources__finalize_spec");
      begin
         F56;
      end;
      E494 := E494 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "sax__utils__finalize_spec");
      begin
         F57;
      end;
      E479 := E479 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__attributes__finalize_spec");
      begin
         F58;
      end;
      E490 := E490 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__exceptions__finalize_spec");
      begin
         F59;
      end;
      E484 := E484 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "sax__symbols__finalize_spec");
      begin
         F60;
      end;
      E488 := E488 - 1;
      declare
         procedure F61;
         pragma Import (Ada, F61, "sax__pointers__finalize_spec");
      begin
         F61;
      end;
      E123 := E123 - 1;
      declare
         procedure F62;
         pragma Import (Ada, F62, "flyology__object_storage__server__static_credentials__finalize_spec");
      begin
         F62;
      end;
      E348 := E348 - 1;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__server__applications__finalize_spec");
      begin
         F63;
      end;
      E371 := E371 - 1;
      declare
         procedure F64;
         pragma Import (Ada, F64, "flyology__http__server__connections__finalize_spec");
      begin
         F64;
      end;
      E189 := E189 - 1;
      declare
         procedure F65;
         pragma Import (Ada, F65, "flyology__http__server__finalize_spec");
      begin
         F65;
      end;
      E344 := E344 - 1;
      declare
         procedure F66;
         pragma Import (Ada, F66, "flyology__io__connections__drivers__finalize_spec");
      begin
         F66;
      end;
      declare
         procedure F67;
         pragma Import (Ada, F67, "flyology__io__connections__finalize_body");
      begin
         E320 := E320 - 1;
         F67;
      end;
      declare
         procedure F68;
         pragma Import (Ada, F68, "flyology__io__connections__finalize_spec");
      begin
         F68;
      end;
      declare
         procedure F69;
         pragma Import (Ada, F69, "flyology__io__tls__finalize_body");
      begin
         E329 := E329 - 1;
         F69;
      end;
      declare
         procedure F70;
         pragma Import (Ada, F70, "flyology__io__tls__finalize_spec");
      begin
         F70;
      end;
      E384 := E384 - 1;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__object_storage__backends__memory__finalize_spec");
      begin
         F71;
      end;
      E390 := E390 - 1;
      declare
         procedure F72;
         pragma Import (Ada, F72, "flyology__object_storage__backends__multipart_listing__finalize_spec");
      begin
         F72;
      end;
      E388 := E388 - 1;
      declare
         procedure F73;
         pragma Import (Ada, F73, "flyology__object_storage__backends__listing__finalize_spec");
      begin
         F73;
      end;
      E386 := E386 - 1;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__object_storage__backends__bucket_listing__finalize_spec");
      begin
         F74;
      end;
      E378 := E378 - 1;
      declare
         procedure F75;
         pragma Import (Ada, F75, "flyology__object_storage__backends__finalize_spec");
      begin
         F75;
      end;
      E380 := E380 - 1;
      declare
         procedure F76;
         pragma Import (Ada, F76, "flyology__object_storage__tags__finalize_spec");
      begin
         F76;
      end;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__object_storage__server__object_lambda_responses__finalize_spec");
      begin
         E564 := E564 - 1;
         F77;
      end;
      E563 := E563 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__object_storage__server__mfa__finalize_spec");
      begin
         F78;
      end;
      E392 := E392 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__object_storage__checksum_engine__finalize_spec");
      begin
         F79;
      end;
      E398 := E398 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F80;
      end;
      E332 := E332 - 1;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__io__sockets__finalize_spec");
      begin
         F81;
      end;
      E197 := E197 - 1;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__bytes__finalize_spec");
      begin
         F82;
      end;
      declare
         procedure F83;
         pragma Import (Ada, F83, "flyology__buffers__finalize_body");
      begin
         E337 := E337 - 1;
         F83;
      end;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__buffers__finalize_spec");
      begin
         F84;
      end;
      E206 := E206 - 1;
      E204 := E204 - 1;
      declare
         procedure F85;
         pragma Import (Ada, F85, "flyology__io__finalize_spec");
      begin
         F85;
      end;
      declare
         procedure F86;
         pragma Import (Ada, F86, "flyology__operations__finalize_spec");
      begin
         F86;
      end;
      E285 := E285 - 1;
      declare
         procedure F87;
         pragma Import (Ada, F87, "flyology__wake_sources__finalize_spec");
      begin
         F87;
      end;
      E267 := E267 - 1;
      declare
         procedure F88;
         pragma Import (Ada, F88, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F88;
      end;
      declare
         procedure F89;
         pragma Import (Ada, F89, "gnat__sockets__finalize_body");
      begin
         E295 := E295 - 1;
         F89;
      end;
      declare
         procedure F90;
         pragma Import (Ada, F90, "gnat__sockets__finalize_spec");
      begin
         F90;
      end;
      E311 := E311 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "system__pool_global__finalize_spec");
      begin
         F91;
      end;
      E084 := E084 - 1;
      declare
         procedure F92;
         pragma Import (Ada, F92, "ada__strings__unbounded__finalize_spec");
      begin
         F92;
      end;
      E412 := E412 - 1;
      declare
         procedure F93;
         pragma Import (Ada, F93, "gnat__sha512__finalize_spec");
      begin
         F93;
      end;
      E141 := E141 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "gnat__sha256__finalize_spec");
      begin
         F94;
      end;
      E408 := E408 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "gnat__sha1__finalize_spec");
      begin
         F95;
      end;
      E404 := E404 - 1;
      declare
         procedure F96;
         pragma Import (Ada, F96, "gnat__md5__finalize_spec");
      begin
         F96;
      end;
      E360 := E360 - 1;
      declare
         procedure F97;
         pragma Import (Ada, F97, "ada__text_io__finalize_spec");
      begin
         F97;
      end;
      E132 := E132 - 1;
      declare
         procedure F98;
         pragma Import (Ada, F98, "system__storage_pools__subpools__finalize_spec");
      begin
         F98;
      end;
      declare
         procedure F99;
         pragma Import (Ada, F99, "system__file_io__finalize_body");
      begin
         E364 := E364 - 1;
         F99;
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
         Count => (0, 0, 0, 2, 2, 1, 1, 0, 13, 0),
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
      E005 := E005 + 1;
      Ada.Assertions'Elab_Spec;
      E226 := E226 + 1;
      Ada.Containers'Elab_Spec;
      E198 := E198 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E099 := E099 + 1;
      Ada.Strings'Elab_Spec;
      E052 := E052 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E054 := E054 + 1;
      Gnat'Elab_Spec;
      E139 := E139 + 1;
      Interfaces.C'Elab_Spec;
      E089 := E089 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E307 := E307 + 1;
      System.Os_Lib'Elab_Body;
      E160 := E160 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E062 := E062 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E051 := E051 + 1;
      Ada.Streams'Elab_Spec;
      E098 := E098 + 1;
      System.File_Control_Block'Elab_Spec;
      E365 := E365 + 1;
      System.Finalization_Root'Elab_Spec;
      E101 := E101 + 1;
      Ada.Finalization'Elab_Spec;
      E096 := E096 + 1;
      System.File_Io'Elab_Body;
      E364 := E364 + 1;
      System.Storage_Pools'Elab_Spec;
      E130 := E130 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E132 := E132 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E158 := E158 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E208 := E208 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E177 := E177 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E360 := E360 + 1;
      E143 := E143 + 1;
      E406 := E406 + 1;
      Gnat.Md5'Elab_Spec;
      E404 := E404 + 1;
      E410 := E410 + 1;
      E150 := E150 + 1;
      E145 := E145 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E414 := E414 + 1;
      Gnat.Sha1'Elab_Spec;
      E408 := E408 + 1;
      Gnat.Sha256'Elab_Spec;
      E141 := E141 + 1;
      Gnat.Sha512'Elab_Spec;
      E412 := E412 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E231 := E231 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E316 := E316 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E103 := E103 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E187 := E187 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E084 := E084 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E475 := E475 + 1;
      System.Pool_Global'Elab_Spec;
      E311 := E311 + 1;
      Gnat.Sockets'Elab_Spec;
      Gnat.Sockets.Thin_Common'Elab_Spec;
      E305 := E305 + 1;
      E300 := E300 + 1;
      Gnat.Sockets'Elab_Body;
      E295 := E295 + 1;
      E298 := E298 + 1;
      System.Tasking.Initialization'Elab_Body;
      E271 := E271 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E213 := E213 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E267 := E267 + 1;
      System.Tasking.Queuing'Elab_Body;
      E279 := E279 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E588 := E588 + 1;
      System.Tasking.Stages'Elab_Body;
      E584 := E584 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E285 := E285 + 1;
      Flyology.Cancellation'Elab_Spec;
      E210 := E210 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E204 := E204 + 1;
      E206 := E206 + 1;
      Unicode'Elab_Body;
      E427 := E427 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E337 := E337 + 1;
      Flyology.Bytes'Elab_Spec;
      E197 := E197 + 1;
      E340 := E340 + 1;
      E367 := E367 + 1;
      Flyology.Http'Elab_Spec;
      E184 := E184 + 1;
      E191 := E191 + 1;
      E318 := E318 + 1;
      E202 := E202 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E332 := E332 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E077 := E077 + 1;
      E396 := E396 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E402 := E402 + 1;
      E394 := E394 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E526 := E526 + 1;
      E534 := E534 + 1;
      E554 := E554 + 1;
      E126 := E126 + 1;
      E400 := E400 + 1;
      E128 := E128 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E398 := E398 + 1;
      Flyology.Object_Storage.Checksum_Engine'Elab_Spec;
      Flyology.Object_Storage.Checksum_Engine'Elab_Body;
      E392 := E392 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E138 := E138 + 1;
      E152 := E152 + 1;
      Flyology.Object_Storage.Server.Mfa'Elab_Spec;
      E563 := E563 + 1;
      Flyology.Object_Storage.Server.Object_Lambda_Responses'Elab_Spec;
      E564 := E564 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E380 := E380 + 1;
      Flyology.Object_Storage.Backends'Elab_Spec;
      E378 := E378 + 1;
      Flyology.Object_Storage.Backends.Bucket_Listing'Elab_Spec;
      E386 := E386 + 1;
      Flyology.Object_Storage.Backends.Listing'Elab_Spec;
      E388 := E388 + 1;
      Flyology.Object_Storage.Backends.Multipart_Listing'Elab_Spec;
      E390 := E390 + 1;
      Flyology.Object_Storage.Backends.Memory'Elab_Spec;
      Flyology.Object_Storage.Backends.Memory'Elab_Body;
      E384 := E384 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E325 := E325 + 1;
      Flyology.Io.Tls'Elab_Body;
      E329 := E329 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E320 := E320 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E344 := E344 + 1;
      E373 := E373 + 1;
      E195 := E195 + 1;
      Flyology.Http.Server'Elab_Spec;
      Flyology.Http.Server.Websocket_Deflate'Elab_Spec;
      E193 := E193 + 1;
      Flyology.Http.Server'Elab_Body;
      E189 := E189 + 1;
      E369 := E369 + 1;
      Flyology.Http.Server.Connections'Elab_Spec;
      Flyology.Http.Server.Connections'Elab_Body;
      E371 := E371 + 1;
      Flyology.Http.Server.Exchange_Backends'Elab_Spec;
      E351 := E351 + 1;
      Flyology.Http.Server.Applications'Elab_Spec;
      Flyology.Http.Server.Applications'Elab_Body;
      E348 := E348 + 1;
      Flyology.Object_Storage.Server.Authentication'Elab_Spec;
      E156 := E156 + 1;
      Flyology.Object_Storage.Server.Static_Credentials'Elab_Spec;
      Flyology.Object_Storage.Server.Static_Credentials'Elab_Body;
      E123 := E123 + 1;
      E568 := E568 + 1;
      E486 := E486 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E488 := E488 + 1;
      Unicode.Ccs'Elab_Spec;
      E438 := E438 + 1;
      E440 := E440 + 1;
      E442 := E442 + 1;
      E447 := E447 + 1;
      E450 := E450 + 1;
      E452 := E452 + 1;
      E454 := E454 + 1;
      E459 := E459 + 1;
      Unicode.Ces'Elab_Spec;
      E434 := E434 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E484 := E484 + 1;
      E492 := E492 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E490 := E490 + 1;
      E464 := E464 + 1;
      E462 := E462 + 1;
      E466 := E466 + 1;
      E468 := E468 + 1;
      Sax.Models'Elab_Spec;
      E481 := E481 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E479 := E479 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E494 := E494 + 1;
      E436 := E436 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E425 := E425 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E477 := E477 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E470 := E470 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E473 := E473 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E423 := E423 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E518 := E518 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E502 := E502 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E504 := E504 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E498 := E498 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E500 := E500 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E506 := E506 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E508 := E508 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E530 := E530 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E532 := E532 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E520 := E520 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E542 := E542 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E544 := E544 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E546 := E546 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E548 := E548 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E550 := E550 + 1;
      E421 := E421 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E419 := E419 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E496 := E496 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E528 := E528 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E514 := E514 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E540 := E540 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E552 := E552 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E556 := E556 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E558 := E558 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E560 := E560 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E524 := E524 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E512 := E512 + 1;
      E510 := E510 + 1;
      E516 := E516 + 1;
      E522 := E522 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E536 := E536 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E538 := E538 + 1;
      Flyology.Object_Storage.Server.Metadata_Results'Elab_Spec;
      E561 := E561 + 1;
      E566 := E566 + 1;
      Repro_S3_Server'Elab_Spec;
      Repro_S3_Server'Elab_Body;
      E353 := E353 + 1;
      Repro_Sigv4_Support'Elab_Spec;
      Repro_Sigv4_Support'Elab_Body;
      E592 := E592 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_sigv4_2");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_sigv4_support.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_sigv4_2.o
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
