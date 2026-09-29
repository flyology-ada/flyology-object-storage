pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_client_low_5.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_client_low_5.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E006 : Short_Integer; pragma Import (Ada, E006, "ada__exceptions_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "system__soft_links_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__exception_table_E");
   E023 : Short_Integer; pragma Import (Ada, E023, "system__exceptions_E");
   E018 : Short_Integer; pragma Import (Ada, E018, "system__soft_links__initialize_E");
   E301 : Short_Integer; pragma Import (Ada, E301, "ada__assertions_E");
   E133 : Short_Integer; pragma Import (Ada, E133, "ada__containers_E");
   E099 : Short_Integer; pragma Import (Ada, E099, "ada__io_exceptions_E");
   E050 : Short_Integer; pragma Import (Ada, E050, "ada__strings_E");
   E065 : Short_Integer; pragma Import (Ada, E065, "ada__strings__utf_encoding_E");
   E159 : Short_Integer; pragma Import (Ada, E159, "gnat_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "interfaces__c_E");
   E534 : Short_Integer; pragma Import (Ada, E534, "interfaces__c__strings_E");
   E255 : Short_Integer; pragma Import (Ada, E255, "system__os_lib_E");
   E073 : Short_Integer; pragma Import (Ada, E073, "ada__tags_E");
   E063 : Short_Integer; pragma Import (Ada, E063, "ada__strings__text_buffers_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__streams_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "system__file_control_block_E");
   E101 : Short_Integer; pragma Import (Ada, E101, "system__finalization_root_E");
   E096 : Short_Integer; pragma Import (Ada, E096, "ada__finalization_E");
   E251 : Short_Integer; pragma Import (Ada, E251, "system__file_io_E");
   E137 : Short_Integer; pragma Import (Ada, E137, "system__storage_pools_E");
   E139 : Short_Integer; pragma Import (Ada, E139, "system__storage_pools__subpools_E");
   E372 : Short_Integer; pragma Import (Ada, E372, "ada__calendar_E");
   E447 : Short_Integer; pragma Import (Ada, E447, "ada__calendar__delays_E");
   E376 : Short_Integer; pragma Import (Ada, E376, "ada__calendar__time_zones_E");
   E247 : Short_Integer; pragma Import (Ada, E247, "ada__text_io_E");
   E163 : Short_Integer; pragma Import (Ada, E163, "gnat__secure_hashes_E");
   E165 : Short_Integer; pragma Import (Ada, E165, "gnat__secure_hashes__md5_E");
   E161 : Short_Integer; pragma Import (Ada, E161, "gnat__md5_E");
   E172 : Short_Integer; pragma Import (Ada, E172, "gnat__secure_hashes__sha1_E");
   E178 : Short_Integer; pragma Import (Ada, E178, "gnat__secure_hashes__sha2_common_E");
   E176 : Short_Integer; pragma Import (Ada, E176, "gnat__secure_hashes__sha2_32_E");
   E182 : Short_Integer; pragma Import (Ada, E182, "gnat__secure_hashes__sha2_64_E");
   E170 : Short_Integer; pragma Import (Ada, E170, "gnat__sha1_E");
   E174 : Short_Integer; pragma Import (Ada, E174, "gnat__sha256_E");
   E180 : Short_Integer; pragma Import (Ada, E180, "gnat__sha512_E");
   E306 : Short_Integer; pragma Import (Ada, E306, "system__flyology__scheduler_E");
   E429 : Short_Integer; pragma Import (Ada, E429, "ada__real_time_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__maps_E");
   E120 : Short_Integer; pragma Import (Ada, E120, "ada__strings__maps__constants_E");
   E084 : Short_Integer; pragma Import (Ada, E084, "ada__strings__unbounded_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "gnat__directory_operations_E");
   E624 : Short_Integer; pragma Import (Ada, E624, "system__interrupt_management__operations_E");
   E236 : Short_Integer; pragma Import (Ada, E236, "system__pool_global_E");
   E401 : Short_Integer; pragma Import (Ada, E401, "system__tasking__initialization_E");
   E391 : Short_Integer; pragma Import (Ada, E391, "system__tasking__protected_objects_E");
   E397 : Short_Integer; pragma Import (Ada, E397, "system__tasking__protected_objects__entries_E");
   E409 : Short_Integer; pragma Import (Ada, E409, "system__tasking__queuing_E");
   E630 : Short_Integer; pragma Import (Ada, E630, "system__flyology__task_results_E");
   E626 : Short_Integer; pragma Import (Ada, E626, "system__tasking__stages_E");
   E620 : Short_Integer; pragma Import (Ada, E620, "system__tasking__async_delays_E");
   E418 : Short_Integer; pragma Import (Ada, E418, "flyology__wake_sources_E");
   E415 : Short_Integer; pragma Import (Ada, E415, "flyology__cancellation_E");
   E445 : Short_Integer; pragma Import (Ada, E445, "flyology__operations_E");
   E443 : Short_Integer; pragma Import (Ada, E443, "flyology__io_E");
   E192 : Short_Integer; pragma Import (Ada, E192, "unicode_E");
   E388 : Short_Integer; pragma Import (Ada, E388, "flyology__buffers_E");
   E422 : Short_Integer; pragma Import (Ada, E422, "flyology__buffers__drivers_E");
   E132 : Short_Integer; pragma Import (Ada, E132, "flyology__bytes_E");
   E472 : Short_Integer; pragma Import (Ada, E472, "flyology__capacity_E");
   E615 : Short_Integer; pragma Import (Ada, E615, "flyology__file_open_policy_E");
   E117 : Short_Integer; pragma Import (Ada, E117, "flyology__http_E");
   E425 : Short_Integer; pragma Import (Ada, E425, "flyology__http__client_policy_E");
   E499 : Short_Integer; pragma Import (Ada, E499, "flyology__http__header_huffman_policy_E");
   E145 : Short_Integer; pragma Import (Ada, E145, "flyology__http__headers_E");
   E431 : Short_Integer; pragma Import (Ada, E431, "flyology__http__http_2_frames_E");
   E435 : Short_Integer; pragma Import (Ada, E435, "flyology__http__http_2_huffman_E");
   E433 : Short_Integer; pragma Import (Ada, E433, "flyology__http__http_2_hpack_E");
   E437 : Short_Integer; pragma Import (Ada, E437, "flyology__http__http_2_payloads_E");
   E439 : Short_Integer; pragma Import (Ada, E439, "flyology__http__http_2_policy_E");
   E478 : Short_Integer; pragma Import (Ada, E478, "flyology__http__http_2_requests_E");
   E441 : Short_Integer; pragma Import (Ada, E441, "flyology__http__http_2_settings_E");
   E486 : Short_Integer; pragma Import (Ada, E486, "flyology__http__http_3_frame_policy_E");
   E505 : Short_Integer; pragma Import (Ada, E505, "flyology__http__http_3_message_policy_E");
   E491 : Short_Integer; pragma Import (Ada, E491, "flyology__http__http_3_settings_policy_E");
   E493 : Short_Integer; pragma Import (Ada, E493, "flyology__http__http_3_stream_policy_E");
   E484 : Short_Integer; pragma Import (Ada, E484, "flyology__http__http_3_control_policy_E");
   E501 : Short_Integer; pragma Import (Ada, E501, "flyology__http__qpack_integer_policy_E");
   E503 : Short_Integer; pragma Import (Ada, E503, "flyology__http__qpack_static_table_E");
   E497 : Short_Integer; pragma Import (Ada, E497, "flyology__http__qpack_field_section_policy_E");
   E495 : Short_Integer; pragma Import (Ada, E495, "flyology__http__http_3_header_policy_E");
   E507 : Short_Integer; pragma Import (Ada, E507, "flyology__http__http_3_stream_receive_policy_E");
   E613 : Short_Integer; pragma Import (Ada, E613, "flyology__io__files_E");
   E468 : Short_Integer; pragma Import (Ada, E468, "flyology__io__sockets_E");
   E608 : Short_Integer; pragma Import (Ada, E608, "flyology__io__dns_E");
   E122 : Short_Integer; pragma Import (Ada, E122, "flyology__object_storage_E");
   E150 : Short_Integer; pragma Import (Ada, E150, "flyology__object_storage__s3__core_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "flyology__object_storage__s3__checksum_crc_E");
   E148 : Short_Integer; pragma Import (Ada, E148, "flyology__object_storage__s3__checksum_policy_E");
   E368 : Short_Integer; pragma Import (Ada, E368, "flyology__object_storage__s3__imf_dates_E");
   E654 : Short_Integer; pragma Import (Ada, E654, "flyology__object_storage__s3__model_E");
   E346 : Short_Integer; pragma Import (Ada, E346, "flyology__object_storage__s3__sigv4_encoding_E");
   E154 : Short_Integer; pragma Import (Ada, E154, "flyology__object_storage__s3__wire_core_E");
   E156 : Short_Integer; pragma Import (Ada, E156, "flyology__object_storage__secrets_E");
   E152 : Short_Integer; pragma Import (Ada, E152, "flyology__object_storage__s3__checksums_E");
   E672 : Short_Integer; pragma Import (Ada, E672, "flyology__object_storage__s3__sigv4_E");
   E385 : Short_Integer; pragma Import (Ada, E385, "flyology__object_storage__tags_E");
   E582 : Short_Integer; pragma Import (Ada, E582, "flyology__quic__crypto_flight_E");
   E532 : Short_Integer; pragma Import (Ada, E532, "flyology__quic__crypto_openssl_E");
   E527 : Short_Integer; pragma Import (Ada, E527, "flyology__quic__debug_E");
   E586 : Short_Integer; pragma Import (Ada, E586, "flyology__quic__handshake_receiver_E");
   E588 : Short_Integer; pragma Import (Ada, E588, "flyology__quic__handshake_sender_E");
   E572 : Short_Integer; pragma Import (Ada, E572, "flyology__quic__initial_receiver_E");
   E576 : Short_Integer; pragma Import (Ada, E576, "flyology__quic__initial_sender_E");
   E570 : Short_Integer; pragma Import (Ada, E570, "flyology__quic__initial_connection_E");
   E590 : Short_Integer; pragma Import (Ada, E590, "flyology__quic__initial_space_E");
   E538 : Short_Integer; pragma Import (Ada, E538, "flyology__quic__one_rtt_receiver_E");
   E544 : Short_Integer; pragma Import (Ada, E544, "flyology__quic__one_rtt_sender_E");
   E546 : Short_Integer; pragma Import (Ada, E546, "flyology__quic__tls_key_schedule_E");
   E530 : Short_Integer; pragma Import (Ada, E530, "flyology__quic__application_connection_E");
   E511 : Short_Integer; pragma Import (Ada, E511, "flyology__quic__application_space_E");
   E584 : Short_Integer; pragma Import (Ada, E584, "flyology__quic__handshake_connection_E");
   E578 : Short_Integer; pragma Import (Ada, E578, "flyology__quic__handshake_space_E");
   E592 : Short_Integer; pragma Import (Ada, E592, "flyology__quic__tls_session_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "flyology__quic__connection_driver_E");
   E509 : Short_Integer; pragma Import (Ada, E509, "flyology__quic__connections_E");
   E482 : Short_Integer; pragma Import (Ada, E482, "flyology__http__http_3_connection_E");
   E480 : Short_Integer; pragma Import (Ada, E480, "flyology__http__http_3_E");
   E602 : Short_Integer; pragma Import (Ada, E602, "flyology__http__http_3_client_connection_E");
   E465 : Short_Integer; pragma Import (Ada, E465, "flyology__io__tls_E");
   E461 : Short_Integer; pragma Import (Ada, E461, "flyology__io__tls_driver_E");
   E456 : Short_Integer; pragma Import (Ada, E456, "flyology__io__connections_E");
   E476 : Short_Integer; pragma Import (Ada, E476, "flyology__io__connections__drivers_E");
   E427 : Short_Integer; pragma Import (Ada, E427, "flyology__http__http_2_client_connection_E");
   E606 : Short_Integer; pragma Import (Ada, E606, "flyology__io__tls__alpn_E");
   E604 : Short_Integer; pragma Import (Ada, E604, "flyology__io__connections__tls_E");
   E420 : Short_Integer; pragma Import (Ada, E420, "flyology__http__client_E");
   E678 : Short_Integer; pragma Import (Ada, E678, "repro_support_E");
   E278 : Short_Integer; pragma Import (Ada, E278, "sax__htable_E");
   E280 : Short_Integer; pragma Import (Ada, E280, "sax__pointers_E");
   E203 : Short_Integer; pragma Import (Ada, E203, "unicode__ccs_E");
   E205 : Short_Integer; pragma Import (Ada, E205, "unicode__ccs__iso_8859_1_E");
   E208 : Short_Integer; pragma Import (Ada, E208, "unicode__ccs__iso_8859_15_E");
   E213 : Short_Integer; pragma Import (Ada, E213, "unicode__ccs__iso_8859_2_E");
   E216 : Short_Integer; pragma Import (Ada, E216, "unicode__ccs__iso_8859_3_E");
   E218 : Short_Integer; pragma Import (Ada, E218, "unicode__ccs__iso_8859_4_E");
   E220 : Short_Integer; pragma Import (Ada, E220, "unicode__ccs__windows_1251_E");
   E225 : Short_Integer; pragma Import (Ada, E225, "unicode__ccs__windows_1252_E");
   E199 : Short_Integer; pragma Import (Ada, E199, "unicode__ces_E");
   E273 : Short_Integer; pragma Import (Ada, E273, "sax__symbols_E");
   E284 : Short_Integer; pragma Import (Ada, E284, "sax__locators_E");
   E282 : Short_Integer; pragma Import (Ada, E282, "sax__exceptions_E");
   E230 : Short_Integer; pragma Import (Ada, E230, "unicode__ces__utf32_E");
   E228 : Short_Integer; pragma Import (Ada, E228, "unicode__ces__basic_8bit_E");
   E232 : Short_Integer; pragma Import (Ada, E232, "unicode__ces__utf16_E");
   E234 : Short_Integer; pragma Import (Ada, E234, "unicode__ces__utf8_E");
   E270 : Short_Integer; pragma Import (Ada, E270, "sax__models_E");
   E268 : Short_Integer; pragma Import (Ada, E268, "sax__attributes_E");
   E286 : Short_Integer; pragma Import (Ada, E286, "sax__utils_E");
   E201 : Short_Integer; pragma Import (Ada, E201, "unicode__encodings_E");
   E190 : Short_Integer; pragma Import (Ada, E190, "input_sources_E");
   E266 : Short_Integer; pragma Import (Ada, E266, "input_sources__file_E");
   E242 : Short_Integer; pragma Import (Ada, E242, "input_sources__strings_E");
   E245 : Short_Integer; pragma Import (Ada, E245, "sax__readers_E");
   E188 : Short_Integer; pragma Import (Ada, E188, "flyology__object_storage__s3__xml_E");
   E352 : Short_Integer; pragma Import (Ada, E352, "flyology__object_storage__s3__acl_E");
   E640 : Short_Integer; pragma Import (Ada, E640, "flyology__object_storage__s3__bucket_controls_E");
   E344 : Short_Integer; pragma Import (Ada, E344, "flyology__object_storage__s3__buckets_E");
   E642 : Short_Integer; pragma Import (Ada, E642, "flyology__object_storage__s3__copies_E");
   E381 : Short_Integer; pragma Import (Ada, E381, "flyology__object_storage__s3__deletions_E");
   E638 : Short_Integer; pragma Import (Ada, E638, "flyology__object_storage__s3__attributes_E");
   E644 : Short_Integer; pragma Import (Ada, E644, "flyology__object_storage__s3__encryption_E");
   E646 : Short_Integer; pragma Import (Ada, E646, "flyology__object_storage__s3__errors_E");
   E650 : Short_Integer; pragma Import (Ada, E650, "flyology__object_storage__s3__lifecycle_E");
   E652 : Short_Integer; pragma Import (Ada, E652, "flyology__object_storage__s3__listings_E");
   E362 : Short_Integer; pragma Import (Ada, E362, "flyology__object_storage__s3__logging_E");
   E662 : Short_Integer; pragma Import (Ada, E662, "flyology__object_storage__s3__multipart_E");
   E664 : Short_Integer; pragma Import (Ada, E664, "flyology__object_storage__s3__multipart_uploads_E");
   E666 : Short_Integer; pragma Import (Ada, E666, "flyology__object_storage__s3__notifications_E");
   E668 : Short_Integer; pragma Import (Ada, E668, "flyology__object_storage__s3__object_lock_E");
   E370 : Short_Integer; pragma Import (Ada, E370, "flyology__object_storage__s3__object_reads_E");
   E358 : Short_Integer; pragma Import (Ada, E358, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E634 : Short_Integer; pragma Import (Ada, E634, "flyology__object_storage__s3__analytics_E");
   E636 : Short_Integer; pragma Import (Ada, E636, "flyology__object_storage__s3__annotations_E");
   E648 : Short_Integer; pragma Import (Ada, E648, "flyology__object_storage__s3__intelligent_tiering_E");
   E356 : Short_Integer; pragma Import (Ada, E356, "flyology__object_storage__s3__inventory_E");
   E660 : Short_Integer; pragma Import (Ada, E660, "flyology__object_storage__s3__metrics_E");
   E670 : Short_Integer; pragma Import (Ada, E670, "flyology__object_storage__s3__replication_E");
   E186 : Short_Integer; pragma Import (Ada, E186, "flyology__object_storage__s3__strict_xml_codecs_E");
   E184 : Short_Integer; pragma Import (Ada, E184, "flyology__object_storage__s3__generated_list_directory_buckets_xml_E");
   E383 : Short_Integer; pragma Import (Ada, E383, "flyology__object_storage__s3__tagging_E");
   E674 : Short_Integer; pragma Import (Ada, E674, "flyology__object_storage__s3__versioning_E");
   E676 : Short_Integer; pragma Import (Ada, E676, "flyology__object_storage__s3__versions_E");
   E366 : Short_Integer; pragma Import (Ada, E366, "flyology__object_storage__s3__website_E");
   E350 : Short_Integer; pragma Import (Ada, E350, "flyology__object_storage__s3__xml_writers_E");
   E348 : Short_Integer; pragma Import (Ada, E348, "flyology__object_storage__s3__generated_put_bucket_acl_xml_E");
   E354 : Short_Integer; pragma Import (Ada, E354, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E360 : Short_Integer; pragma Import (Ada, E360, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E364 : Short_Integer; pragma Import (Ada, E364, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E656 : Short_Integer; pragma Import (Ada, E656, "flyology__object_storage__s3__metadata_configurations_E");
   E658 : Short_Integer; pragma Import (Ada, E658, "flyology__object_storage__s3__metadata_tables_E");
   E130 : Short_Integer; pragma Import (Ada, E130, "flyology__object_storage__client__low_level_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "flyology__object_storage__client__low_level__finalize_body");
      begin
         E130 := E130 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology__object_storage__client__low_level__finalize_spec");
      begin
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__s3__metadata_tables__finalize_body");
      begin
         E658 := E658 - 1;
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E656 := E656 - 1;
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__website__finalize_body");
      begin
         E366 := E366 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__website__finalize_spec");
      begin
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__s3__versions__finalize_body");
      begin
         E676 := E676 - 1;
         F7;
      end;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology__object_storage__s3__versions__finalize_spec");
      begin
         F8;
      end;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology__object_storage__s3__versioning__finalize_body");
      begin
         E674 := E674 - 1;
         F9;
      end;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology__object_storage__s3__tagging__finalize_body");
      begin
         E383 := E383 - 1;
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__generated_list_directory_buckets_xml__finalize_body");
      begin
         E184 := E184 - 1;
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__replication__finalize_body");
      begin
         E670 := E670 - 1;
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
         E660 := E660 - 1;
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
         E356 := E356 - 1;
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
         E648 := E648 - 1;
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
         E636 := E636 - 1;
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
         E634 := E634 - 1;
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
         E668 := E668 - 1;
         F24;
      end;
      declare
         procedure F25;
         pragma Import (Ada, F25, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E666 := E666 - 1;
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
         E664 := E664 - 1;
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
         E662 := E662 - 1;
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
         E362 := E362 - 1;
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
         E652 := E652 - 1;
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
         E650 := E650 - 1;
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
         E646 := E646 - 1;
         F37;
      end;
      declare
         procedure F38;
         pragma Import (Ada, F38, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E644 := E644 - 1;
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
         E638 := E638 - 1;
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
         E381 := E381 - 1;
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
         pragma Import (Ada, F44, "flyology__object_storage__s3__copies__finalize_body");
      begin
         E642 := E642 - 1;
         F44;
      end;
      declare
         procedure F45;
         pragma Import (Ada, F45, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E344 := E344 - 1;
         F45;
      end;
      declare
         procedure F46;
         pragma Import (Ada, F46, "flyology__object_storage__s3__buckets__finalize_spec");
      begin
         F46;
      end;
      declare
         procedure F47;
         pragma Import (Ada, F47, "flyology__object_storage__s3__bucket_controls__finalize_body");
      begin
         E640 := E640 - 1;
         F47;
      end;
      declare
         procedure F48;
         pragma Import (Ada, F48, "flyology__object_storage__s3__bucket_controls__finalize_spec");
      begin
         F48;
      end;
      declare
         procedure F49;
         pragma Import (Ada, F49, "flyology__object_storage__s3__acl__finalize_body");
      begin
         E352 := E352 - 1;
         F49;
      end;
      declare
         procedure F50;
         pragma Import (Ada, F50, "flyology__object_storage__s3__acl__finalize_spec");
      begin
         F50;
      end;
      declare
         procedure F51;
         pragma Import (Ada, F51, "flyology__object_storage__s3__xml__finalize_body");
      begin
         E188 := E188 - 1;
         F51;
      end;
      E245 := E245 - 1;
      declare
         procedure F52;
         pragma Import (Ada, F52, "sax__readers__finalize_spec");
      begin
         F52;
      end;
      E242 := E242 - 1;
      declare
         procedure F53;
         pragma Import (Ada, F53, "input_sources__strings__finalize_spec");
      begin
         F53;
      end;
      E266 := E266 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "input_sources__file__finalize_spec");
      begin
         F54;
      end;
      E190 := E190 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "input_sources__finalize_spec");
      begin
         F55;
      end;
      E286 := E286 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "sax__utils__finalize_spec");
      begin
         F56;
      end;
      E268 := E268 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "sax__attributes__finalize_spec");
      begin
         F57;
      end;
      E282 := E282 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__exceptions__finalize_spec");
      begin
         F58;
      end;
      E273 := E273 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__symbols__finalize_spec");
      begin
         F59;
      end;
      E280 := E280 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "sax__pointers__finalize_spec");
      begin
         F60;
      end;
      declare
         procedure F61;
         pragma Import (Ada, F61, "flyology__http__client__finalize_body");
      begin
         E420 := E420 - 1;
         F61;
      end;
      declare
         procedure F62;
         pragma Import (Ada, F62, "flyology__http__client__finalize_spec");
      begin
         F62;
      end;
      E604 := E604 - 1;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__io__connections__tls__finalize_spec");
      begin
         F63;
      end;
      E606 := E606 - 1;
      declare
         procedure F64;
         pragma Import (Ada, F64, "flyology__io__tls__alpn__finalize_spec");
      begin
         F64;
      end;
      declare
         procedure F65;
         pragma Import (Ada, F65, "flyology__http__http_2_client_connection__finalize_body");
      begin
         E427 := E427 - 1;
         F65;
      end;
      E476 := E476 - 1;
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
         E456 := E456 - 1;
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
         E465 := E465 - 1;
         F69;
      end;
      declare
         procedure F70;
         pragma Import (Ada, F70, "flyology__io__tls__finalize_spec");
      begin
         F70;
      end;
      E480 := E480 - 1;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__http__http_3__finalize_spec");
      begin
         F71;
      end;
      declare
         procedure F72;
         pragma Import (Ada, F72, "flyology__quic__connections__finalize_body");
      begin
         E509 := E509 - 1;
         F72;
      end;
      declare
         procedure F73;
         pragma Import (Ada, F73, "flyology__quic__connections__finalize_spec");
      begin
         F73;
      end;
      E532 := E532 - 1;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__quic__crypto_openssl__finalize_spec");
      begin
         F74;
      end;
      E385 := E385 - 1;
      declare
         procedure F75;
         pragma Import (Ada, F75, "flyology__object_storage__tags__finalize_spec");
      begin
         F75;
      end;
      E152 := E152 - 1;
      declare
         procedure F76;
         pragma Import (Ada, F76, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F76;
      end;
      E608 := E608 - 1;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__io__dns__finalize_spec");
      begin
         F77;
      end;
      E468 := E468 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__io__sockets__finalize_spec");
      begin
         F78;
      end;
      E613 := E613 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__io__files__finalize_spec");
      begin
         F79;
      end;
      E132 := E132 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__bytes__finalize_spec");
      begin
         F80;
      end;
      E422 := E422 - 1;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__buffers__drivers__finalize_spec");
      begin
         F81;
      end;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__buffers__finalize_body");
      begin
         E388 := E388 - 1;
         F82;
      end;
      declare
         procedure F83;
         pragma Import (Ada, F83, "flyology__buffers__finalize_spec");
      begin
         F83;
      end;
      E445 := E445 - 1;
      E443 := E443 - 1;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__io__finalize_spec");
      begin
         F84;
      end;
      declare
         procedure F85;
         pragma Import (Ada, F85, "flyology__operations__finalize_spec");
      begin
         F85;
      end;
      E418 := E418 - 1;
      declare
         procedure F86;
         pragma Import (Ada, F86, "flyology__wake_sources__finalize_spec");
      begin
         F86;
      end;
      E397 := E397 - 1;
      declare
         procedure F87;
         pragma Import (Ada, F87, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F87;
      end;
      E236 := E236 - 1;
      declare
         procedure F88;
         pragma Import (Ada, F88, "system__pool_global__finalize_spec");
      begin
         F88;
      end;
      E084 := E084 - 1;
      declare
         procedure F89;
         pragma Import (Ada, F89, "ada__strings__unbounded__finalize_spec");
      begin
         F89;
      end;
      E180 := E180 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "gnat__sha512__finalize_spec");
      begin
         F90;
      end;
      E174 := E174 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "gnat__sha256__finalize_spec");
      begin
         F91;
      end;
      E170 := E170 - 1;
      declare
         procedure F92;
         pragma Import (Ada, F92, "gnat__sha1__finalize_spec");
      begin
         F92;
      end;
      E161 := E161 - 1;
      declare
         procedure F93;
         pragma Import (Ada, F93, "gnat__md5__finalize_spec");
      begin
         F93;
      end;
      E247 := E247 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "ada__text_io__finalize_spec");
      begin
         F94;
      end;
      E139 := E139 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "system__storage_pools__subpools__finalize_spec");
      begin
         F95;
      end;
      declare
         procedure F96;
         pragma Import (Ada, F96, "system__file_io__finalize_body");
      begin
         E251 := E251 - 1;
         F96;
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
           False, False, False, True, False, False, True, True, 
           False, True, True, False, True, True, True, True, 
           False, True, False, False, False, True, True, False, 
           True, True, False, True, True, True, True, False, 
           True, False, True, True, False, False, True, False, 
           True, False, False, False, True, False, False, False, 
           False, True, False, True, True, True, False, False, 
           True, False, True, True, True, False, True, True, 
           False, True, True, True, True, False, False, False, 
           True, False, False, False, False, True, False, False, 
           True, True, True, False),
         Count => (0, 0, 0, 2, 0, 0, 1, 1, 12, 0),
         Unknown => (False, False, False, False, False, False, False, True, True, False));
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
      E301 := E301 + 1;
      Ada.Containers'Elab_Spec;
      E133 := E133 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E099 := E099 + 1;
      Ada.Strings'Elab_Spec;
      E050 := E050 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E065 := E065 + 1;
      Gnat'Elab_Spec;
      E159 := E159 + 1;
      Interfaces.C'Elab_Spec;
      E089 := E089 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E534 := E534 + 1;
      System.Os_Lib'Elab_Body;
      E255 := E255 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E073 := E073 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E063 := E063 + 1;
      Ada.Streams'Elab_Spec;
      E098 := E098 + 1;
      System.File_Control_Block'Elab_Spec;
      E261 := E261 + 1;
      System.Finalization_Root'Elab_Spec;
      E101 := E101 + 1;
      Ada.Finalization'Elab_Spec;
      E096 := E096 + 1;
      System.File_Io'Elab_Body;
      E251 := E251 + 1;
      System.Storage_Pools'Elab_Spec;
      E137 := E137 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E139 := E139 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E372 := E372 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E447 := E447 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E376 := E376 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E247 := E247 + 1;
      E163 := E163 + 1;
      E165 := E165 + 1;
      Gnat.Md5'Elab_Spec;
      E161 := E161 + 1;
      E172 := E172 + 1;
      E178 := E178 + 1;
      E176 := E176 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E182 := E182 + 1;
      Gnat.Sha1'Elab_Spec;
      E170 := E170 + 1;
      Gnat.Sha256'Elab_Spec;
      E174 := E174 + 1;
      Gnat.Sha512'Elab_Spec;
      E180 := E180 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E306 := E306 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E429 := E429 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E054 := E054 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E120 := E120 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E084 := E084 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E263 := E263 + 1;
      System.Interrupt_Management.Operations'Elab_Body;
      E624 := E624 + 1;
      System.Pool_Global'Elab_Spec;
      E236 := E236 + 1;
      System.Tasking.Initialization'Elab_Body;
      E401 := E401 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E391 := E391 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E397 := E397 + 1;
      System.Tasking.Queuing'Elab_Body;
      E409 := E409 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E630 := E630 + 1;
      System.Tasking.Stages'Elab_Body;
      E626 := E626 + 1;
      System.Tasking.Async_Delays'Elab_Body;
      E620 := E620 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E418 := E418 + 1;
      Flyology.Cancellation'Elab_Spec;
      E415 := E415 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E443 := E443 + 1;
      E445 := E445 + 1;
      Unicode'Elab_Body;
      E192 := E192 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E388 := E388 + 1;
      Flyology.Buffers.Drivers'Elab_Spec;
      Flyology.Buffers.Drivers'Elab_Body;
      E422 := E422 + 1;
      Flyology.Bytes'Elab_Spec;
      E132 := E132 + 1;
      E472 := E472 + 1;
      E615 := E615 + 1;
      Flyology.Http'Elab_Spec;
      E117 := E117 + 1;
      E425 := E425 + 1;
      E499 := E499 + 1;
      Flyology.Http.Headers'Elab_Spec;
      E145 := E145 + 1;
      E431 := E431 + 1;
      Flyology.Http.Http_2_Huffman'Elab_Body;
      E435 := E435 + 1;
      Flyology.Http.Http_2_Hpack'Elab_Spec;
      E433 := E433 + 1;
      E437 := E437 + 1;
      E439 := E439 + 1;
      E478 := E478 + 1;
      E441 := E441 + 1;
      E486 := E486 + 1;
      E505 := E505 + 1;
      E491 := E491 + 1;
      E493 := E493 + 1;
      E484 := E484 + 1;
      E501 := E501 + 1;
      E503 := E503 + 1;
      E497 := E497 + 1;
      E495 := E495 + 1;
      E507 := E507 + 1;
      Flyology.Io.Files'Elab_Spec;
      Flyology.Io.Files'Elab_Body;
      E613 := E613 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E468 := E468 + 1;
      Flyology.Io.Dns'Elab_Spec;
      Flyology.Io.Dns'Elab_Body;
      E608 := E608 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E122 := E122 + 1;
      E150 := E150 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E158 := E158 + 1;
      E148 := E148 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E368 := E368 + 1;
      E654 := E654 + 1;
      E346 := E346 + 1;
      E154 := E154 + 1;
      E156 := E156 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E152 := E152 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E672 := E672 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E385 := E385 + 1;
      E582 := E582 + 1;
      Flyology.Quic.Crypto_Openssl'Elab_Spec;
      Flyology.Quic.Crypto_Openssl'Elab_Body;
      E532 := E532 + 1;
      E527 := E527 + 1;
      E586 := E586 + 1;
      E588 := E588 + 1;
      E572 := E572 + 1;
      E576 := E576 + 1;
      E570 := E570 + 1;
      E590 := E590 + 1;
      E538 := E538 + 1;
      E544 := E544 + 1;
      E546 := E546 + 1;
      E530 := E530 + 1;
      E511 := E511 + 1;
      E584 := E584 + 1;
      E578 := E578 + 1;
      E592 := E592 + 1;
      E564 := E564 + 1;
      Flyology.Quic.Connections'Elab_Spec;
      Flyology.Quic.Connections'Elab_Body;
      E509 := E509 + 1;
      E482 := E482 + 1;
      Flyology.Http.Http_3'Elab_Spec;
      Flyology.Http.Http_3'Elab_Body;
      E480 := E480 + 1;
      E602 := E602 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E461 := E461 + 1;
      Flyology.Io.Tls'Elab_Body;
      E465 := E465 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E456 := E456 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E476 := E476 + 1;
      Flyology.Http.Http_2_Client_Connection'Elab_Spec;
      Flyology.Http.Http_2_Client_Connection'Elab_Body;
      E427 := E427 + 1;
      Flyology.Io.Tls.Alpn'Elab_Spec;
      E606 := E606 + 1;
      Flyology.Io.Connections.Tls'Elab_Spec;
      Flyology.Io.Connections.Tls'Elab_Body;
      E604 := E604 + 1;
      Flyology.Http.Client'Elab_Spec;
      Flyology.Http.Client'Elab_Body;
      E420 := E420 + 1;
      E678 := E678 + 1;
      E278 := E278 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E280 := E280 + 1;
      Unicode.Ccs'Elab_Spec;
      E203 := E203 + 1;
      E205 := E205 + 1;
      E208 := E208 + 1;
      E213 := E213 + 1;
      E216 := E216 + 1;
      E218 := E218 + 1;
      E220 := E220 + 1;
      E225 := E225 + 1;
      Unicode.Ces'Elab_Spec;
      E199 := E199 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E273 := E273 + 1;
      E284 := E284 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E282 := E282 + 1;
      E230 := E230 + 1;
      E228 := E228 + 1;
      E232 := E232 + 1;
      E234 := E234 + 1;
      Sax.Models'Elab_Spec;
      E270 := E270 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E268 := E268 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E286 := E286 + 1;
      E201 := E201 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E190 := E190 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E266 := E266 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E242 := E242 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E245 := E245 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E188 := E188 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E352 := E352 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E640 := E640 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E344 := E344 + 1;
      Flyology.Object_Storage.S3.Copies'Elab_Spec;
      Flyology.Object_Storage.S3.Copies'Elab_Body;
      E642 := E642 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E381 := E381 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E638 := E638 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E644 := E644 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E646 := E646 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E650 := E650 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E652 := E652 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E362 := E362 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E662 := E662 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E664 := E664 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E666 := E666 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E668 := E668 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E370 := E370 + 1;
      E358 := E358 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E634 := E634 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E636 := E636 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E648 := E648 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E356 := E356 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E660 := E660 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E670 := E670 + 1;
      E186 := E186 + 1;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Body;
      E184 := E184 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E383 := E383 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E674 := E674 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E676 := E676 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E366 := E366 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E350 := E350 + 1;
      E348 := E348 + 1;
      E354 := E354 + 1;
      E360 := E360 + 1;
      E364 := E364 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E656 := E656 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E658 := E658 + 1;
      Flyology.Object_Storage.Client.Low_Level'Elab_Spec;
      Flyology.Object_Storage.Client.Low_Level'Elab_Body;
      E130 := E130 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_client_low_5");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_client_low_5.o
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
