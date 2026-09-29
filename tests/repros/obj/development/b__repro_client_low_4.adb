pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_client_low_4.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_client_low_4.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E008 : Short_Integer; pragma Import (Ada, E008, "ada__exceptions_E");
   E013 : Short_Integer; pragma Import (Ada, E013, "system__soft_links_E");
   E024 : Short_Integer; pragma Import (Ada, E024, "system__exception_table_E");
   E025 : Short_Integer; pragma Import (Ada, E025, "system__exceptions_E");
   E020 : Short_Integer; pragma Import (Ada, E020, "system__soft_links__initialize_E");
   E162 : Short_Integer; pragma Import (Ada, E162, "ada__assertions_E");
   E249 : Short_Integer; pragma Import (Ada, E249, "ada__containers_E");
   E117 : Short_Integer; pragma Import (Ada, E117, "ada__io_exceptions_E");
   E086 : Short_Integer; pragma Import (Ada, E086, "ada__strings_E");
   E090 : Short_Integer; pragma Import (Ada, E090, "ada__strings__utf_encoding_E");
   E266 : Short_Integer; pragma Import (Ada, E266, "gnat_E");
   E053 : Short_Integer; pragma Import (Ada, E053, "interfaces__c_E");
   E364 : Short_Integer; pragma Import (Ada, E364, "interfaces__c__strings_E");
   E055 : Short_Integer; pragma Import (Ada, E055, "system__os_lib_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__tags_E");
   E088 : Short_Integer; pragma Import (Ada, E088, "ada__strings__text_buffers_E");
   E116 : Short_Integer; pragma Import (Ada, E116, "ada__streams_E");
   E574 : Short_Integer; pragma Import (Ada, E574, "system__file_control_block_E");
   E119 : Short_Integer; pragma Import (Ada, E119, "system__finalization_root_E");
   E114 : Short_Integer; pragma Import (Ada, E114, "ada__finalization_E");
   E573 : Short_Integer; pragma Import (Ada, E573, "system__file_io_E");
   E233 : Short_Integer; pragma Import (Ada, E233, "system__storage_pools_E");
   E253 : Short_Integer; pragma Import (Ada, E253, "system__storage_pools__subpools_E");
   E006 : Short_Integer; pragma Import (Ada, E006, "ada__calendar_E");
   E273 : Short_Integer; pragma Import (Ada, E273, "ada__calendar__delays_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "ada__calendar__time_zones_E");
   E569 : Short_Integer; pragma Import (Ada, E569, "ada__text_io_E");
   E492 : Short_Integer; pragma Import (Ada, E492, "gnat__secure_hashes_E");
   E494 : Short_Integer; pragma Import (Ada, E494, "gnat__secure_hashes__md5_E");
   E490 : Short_Integer; pragma Import (Ada, E490, "gnat__md5_E");
   E501 : Short_Integer; pragma Import (Ada, E501, "gnat__secure_hashes__sha1_E");
   E507 : Short_Integer; pragma Import (Ada, E507, "gnat__secure_hashes__sha2_common_E");
   E505 : Short_Integer; pragma Import (Ada, E505, "gnat__secure_hashes__sha2_32_E");
   E511 : Short_Integer; pragma Import (Ada, E511, "gnat__secure_hashes__sha2_64_E");
   E499 : Short_Integer; pragma Import (Ada, E499, "gnat__sha1_E");
   E503 : Short_Integer; pragma Import (Ada, E503, "gnat__sha256_E");
   E509 : Short_Integer; pragma Import (Ada, E509, "gnat__sha512_E");
   E167 : Short_Integer; pragma Import (Ada, E167, "system__flyology__scheduler_E");
   E240 : Short_Integer; pragma Import (Ada, E240, "ada__real_time_E");
   E121 : Short_Integer; pragma Import (Ada, E121, "ada__strings__maps_E");
   E144 : Short_Integer; pragma Import (Ada, E144, "ada__strings__maps__constants_E");
   E105 : Short_Integer; pragma Import (Ada, E105, "ada__strings__unbounded_E");
   E576 : Short_Integer; pragma Import (Ada, E576, "gnat__directory_operations_E");
   E456 : Short_Integer; pragma Import (Ada, E456, "system__interrupt_management__operations_E");
   E229 : Short_Integer; pragma Import (Ada, E229, "system__pool_global_E");
   E213 : Short_Integer; pragma Import (Ada, E213, "system__tasking__initialization_E");
   E203 : Short_Integer; pragma Import (Ada, E203, "system__tasking__protected_objects_E");
   E209 : Short_Integer; pragma Import (Ada, E209, "system__tasking__protected_objects__entries_E");
   E221 : Short_Integer; pragma Import (Ada, E221, "system__tasking__queuing_E");
   E462 : Short_Integer; pragma Import (Ada, E462, "system__flyology__task_results_E");
   E458 : Short_Integer; pragma Import (Ada, E458, "system__tasking__stages_E");
   E452 : Short_Integer; pragma Import (Ada, E452, "system__tasking__async_delays_E");
   E265 : Short_Integer; pragma Import (Ada, E265, "flyology__wake_sources_E");
   E275 : Short_Integer; pragma Import (Ada, E275, "flyology__cancellation_E");
   E271 : Short_Integer; pragma Import (Ada, E271, "flyology__operations_E");
   E269 : Short_Integer; pragma Import (Ada, E269, "flyology__io_E");
   E521 : Short_Integer; pragma Import (Ada, E521, "unicode_E");
   E150 : Short_Integer; pragma Import (Ada, E150, "flyology__buffers_E");
   E227 : Short_Integer; pragma Import (Ada, E227, "flyology__buffers__drivers_E");
   E248 : Short_Integer; pragma Import (Ada, E248, "flyology__bytes_E");
   E302 : Short_Integer; pragma Import (Ada, E302, "flyology__capacity_E");
   E447 : Short_Integer; pragma Import (Ada, E447, "flyology__file_open_policy_E");
   E141 : Short_Integer; pragma Import (Ada, E141, "flyology__http_E");
   E236 : Short_Integer; pragma Import (Ada, E236, "flyology__http__client_policy_E");
   E329 : Short_Integer; pragma Import (Ada, E329, "flyology__http__header_huffman_policy_E");
   E257 : Short_Integer; pragma Import (Ada, E257, "flyology__http__headers_E");
   E242 : Short_Integer; pragma Import (Ada, E242, "flyology__http__http_2_frames_E");
   E246 : Short_Integer; pragma Import (Ada, E246, "flyology__http__http_2_huffman_E");
   E244 : Short_Integer; pragma Import (Ada, E244, "flyology__http__http_2_hpack_E");
   E259 : Short_Integer; pragma Import (Ada, E259, "flyology__http__http_2_payloads_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "flyology__http__http_2_policy_E");
   E308 : Short_Integer; pragma Import (Ada, E308, "flyology__http__http_2_requests_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "flyology__http__http_2_settings_E");
   E316 : Short_Integer; pragma Import (Ada, E316, "flyology__http__http_3_frame_policy_E");
   E335 : Short_Integer; pragma Import (Ada, E335, "flyology__http__http_3_message_policy_E");
   E321 : Short_Integer; pragma Import (Ada, E321, "flyology__http__http_3_settings_policy_E");
   E323 : Short_Integer; pragma Import (Ada, E323, "flyology__http__http_3_stream_policy_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "flyology__http__http_3_control_policy_E");
   E331 : Short_Integer; pragma Import (Ada, E331, "flyology__http__qpack_integer_policy_E");
   E333 : Short_Integer; pragma Import (Ada, E333, "flyology__http__qpack_static_table_E");
   E327 : Short_Integer; pragma Import (Ada, E327, "flyology__http__qpack_field_section_policy_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "flyology__http__http_3_header_policy_E");
   E337 : Short_Integer; pragma Import (Ada, E337, "flyology__http__http_3_stream_receive_policy_E");
   E445 : Short_Integer; pragma Import (Ada, E445, "flyology__io__files_E");
   E297 : Short_Integer; pragma Import (Ada, E297, "flyology__io__sockets_E");
   E440 : Short_Integer; pragma Import (Ada, E440, "flyology__io__dns_E");
   E467 : Short_Integer; pragma Import (Ada, E467, "flyology__object_storage_E");
   E480 : Short_Integer; pragma Import (Ada, E480, "flyology__object_storage__s3__core_E");
   E488 : Short_Integer; pragma Import (Ada, E488, "flyology__object_storage__s3__checksum_crc_E");
   E478 : Short_Integer; pragma Import (Ada, E478, "flyology__object_storage__s3__checksum_policy_E");
   E624 : Short_Integer; pragma Import (Ada, E624, "flyology__object_storage__s3__imf_dates_E");
   E654 : Short_Integer; pragma Import (Ada, E654, "flyology__object_storage__s3__model_E");
   E602 : Short_Integer; pragma Import (Ada, E602, "flyology__object_storage__s3__sigv4_encoding_E");
   E484 : Short_Integer; pragma Import (Ada, E484, "flyology__object_storage__s3__wire_core_E");
   E486 : Short_Integer; pragma Import (Ada, E486, "flyology__object_storage__secrets_E");
   E482 : Short_Integer; pragma Import (Ada, E482, "flyology__object_storage__s3__checksums_E");
   E672 : Short_Integer; pragma Import (Ada, E672, "flyology__object_storage__s3__sigv4_E");
   E632 : Short_Integer; pragma Import (Ada, E632, "flyology__object_storage__tags_E");
   E412 : Short_Integer; pragma Import (Ada, E412, "flyology__quic__crypto_flight_E");
   E362 : Short_Integer; pragma Import (Ada, E362, "flyology__quic__crypto_openssl_E");
   E357 : Short_Integer; pragma Import (Ada, E357, "flyology__quic__debug_E");
   E416 : Short_Integer; pragma Import (Ada, E416, "flyology__quic__handshake_receiver_E");
   E418 : Short_Integer; pragma Import (Ada, E418, "flyology__quic__handshake_sender_E");
   E402 : Short_Integer; pragma Import (Ada, E402, "flyology__quic__initial_receiver_E");
   E406 : Short_Integer; pragma Import (Ada, E406, "flyology__quic__initial_sender_E");
   E400 : Short_Integer; pragma Import (Ada, E400, "flyology__quic__initial_connection_E");
   E420 : Short_Integer; pragma Import (Ada, E420, "flyology__quic__initial_space_E");
   E368 : Short_Integer; pragma Import (Ada, E368, "flyology__quic__one_rtt_receiver_E");
   E374 : Short_Integer; pragma Import (Ada, E374, "flyology__quic__one_rtt_sender_E");
   E376 : Short_Integer; pragma Import (Ada, E376, "flyology__quic__tls_key_schedule_E");
   E360 : Short_Integer; pragma Import (Ada, E360, "flyology__quic__application_connection_E");
   E341 : Short_Integer; pragma Import (Ada, E341, "flyology__quic__application_space_E");
   E414 : Short_Integer; pragma Import (Ada, E414, "flyology__quic__handshake_connection_E");
   E408 : Short_Integer; pragma Import (Ada, E408, "flyology__quic__handshake_space_E");
   E422 : Short_Integer; pragma Import (Ada, E422, "flyology__quic__tls_session_E");
   E394 : Short_Integer; pragma Import (Ada, E394, "flyology__quic__connection_driver_E");
   E339 : Short_Integer; pragma Import (Ada, E339, "flyology__quic__connections_E");
   E312 : Short_Integer; pragma Import (Ada, E312, "flyology__http__http_3_connection_E");
   E310 : Short_Integer; pragma Import (Ada, E310, "flyology__http__http_3_E");
   E432 : Short_Integer; pragma Import (Ada, E432, "flyology__http__http_3_client_connection_E");
   E294 : Short_Integer; pragma Import (Ada, E294, "flyology__io__tls_E");
   E290 : Short_Integer; pragma Import (Ada, E290, "flyology__io__tls_driver_E");
   E285 : Short_Integer; pragma Import (Ada, E285, "flyology__io__connections_E");
   E306 : Short_Integer; pragma Import (Ada, E306, "flyology__io__connections__drivers_E");
   E238 : Short_Integer; pragma Import (Ada, E238, "flyology__http__http_2_client_connection_E");
   E436 : Short_Integer; pragma Import (Ada, E436, "flyology__io__tls__alpn_E");
   E434 : Short_Integer; pragma Import (Ada, E434, "flyology__io__connections__tls_E");
   E148 : Short_Integer; pragma Import (Ada, E148, "flyology__http__client_E");
   E678 : Short_Integer; pragma Import (Ada, E678, "repro_client_objects_fake_E");
   E680 : Short_Integer; pragma Import (Ada, E680, "repro_support_E");
   E590 : Short_Integer; pragma Import (Ada, E590, "sax__htable_E");
   E592 : Short_Integer; pragma Import (Ada, E592, "sax__pointers_E");
   E532 : Short_Integer; pragma Import (Ada, E532, "unicode__ccs_E");
   E534 : Short_Integer; pragma Import (Ada, E534, "unicode__ccs__iso_8859_1_E");
   E536 : Short_Integer; pragma Import (Ada, E536, "unicode__ccs__iso_8859_15_E");
   E541 : Short_Integer; pragma Import (Ada, E541, "unicode__ccs__iso_8859_2_E");
   E544 : Short_Integer; pragma Import (Ada, E544, "unicode__ccs__iso_8859_3_E");
   E546 : Short_Integer; pragma Import (Ada, E546, "unicode__ccs__iso_8859_4_E");
   E548 : Short_Integer; pragma Import (Ada, E548, "unicode__ccs__windows_1251_E");
   E553 : Short_Integer; pragma Import (Ada, E553, "unicode__ccs__windows_1252_E");
   E528 : Short_Integer; pragma Import (Ada, E528, "unicode__ces_E");
   E585 : Short_Integer; pragma Import (Ada, E585, "sax__symbols_E");
   E596 : Short_Integer; pragma Import (Ada, E596, "sax__locators_E");
   E594 : Short_Integer; pragma Import (Ada, E594, "sax__exceptions_E");
   E558 : Short_Integer; pragma Import (Ada, E558, "unicode__ces__utf32_E");
   E556 : Short_Integer; pragma Import (Ada, E556, "unicode__ces__basic_8bit_E");
   E560 : Short_Integer; pragma Import (Ada, E560, "unicode__ces__utf16_E");
   E562 : Short_Integer; pragma Import (Ada, E562, "unicode__ces__utf8_E");
   E582 : Short_Integer; pragma Import (Ada, E582, "sax__models_E");
   E580 : Short_Integer; pragma Import (Ada, E580, "sax__attributes_E");
   E598 : Short_Integer; pragma Import (Ada, E598, "sax__utils_E");
   E530 : Short_Integer; pragma Import (Ada, E530, "unicode__encodings_E");
   E519 : Short_Integer; pragma Import (Ada, E519, "input_sources_E");
   E578 : Short_Integer; pragma Import (Ada, E578, "input_sources__file_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "input_sources__strings_E");
   E567 : Short_Integer; pragma Import (Ada, E567, "sax__readers_E");
   E517 : Short_Integer; pragma Import (Ada, E517, "flyology__object_storage__s3__xml_E");
   E608 : Short_Integer; pragma Import (Ada, E608, "flyology__object_storage__s3__acl_E");
   E640 : Short_Integer; pragma Import (Ada, E640, "flyology__object_storage__s3__bucket_controls_E");
   E600 : Short_Integer; pragma Import (Ada, E600, "flyology__object_storage__s3__buckets_E");
   E642 : Short_Integer; pragma Import (Ada, E642, "flyology__object_storage__s3__copies_E");
   E628 : Short_Integer; pragma Import (Ada, E628, "flyology__object_storage__s3__deletions_E");
   E638 : Short_Integer; pragma Import (Ada, E638, "flyology__object_storage__s3__attributes_E");
   E644 : Short_Integer; pragma Import (Ada, E644, "flyology__object_storage__s3__encryption_E");
   E646 : Short_Integer; pragma Import (Ada, E646, "flyology__object_storage__s3__errors_E");
   E650 : Short_Integer; pragma Import (Ada, E650, "flyology__object_storage__s3__lifecycle_E");
   E652 : Short_Integer; pragma Import (Ada, E652, "flyology__object_storage__s3__listings_E");
   E618 : Short_Integer; pragma Import (Ada, E618, "flyology__object_storage__s3__logging_E");
   E662 : Short_Integer; pragma Import (Ada, E662, "flyology__object_storage__s3__multipart_E");
   E664 : Short_Integer; pragma Import (Ada, E664, "flyology__object_storage__s3__multipart_uploads_E");
   E666 : Short_Integer; pragma Import (Ada, E666, "flyology__object_storage__s3__notifications_E");
   E668 : Short_Integer; pragma Import (Ada, E668, "flyology__object_storage__s3__object_lock_E");
   E626 : Short_Integer; pragma Import (Ada, E626, "flyology__object_storage__s3__object_reads_E");
   E614 : Short_Integer; pragma Import (Ada, E614, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E634 : Short_Integer; pragma Import (Ada, E634, "flyology__object_storage__s3__analytics_E");
   E636 : Short_Integer; pragma Import (Ada, E636, "flyology__object_storage__s3__annotations_E");
   E648 : Short_Integer; pragma Import (Ada, E648, "flyology__object_storage__s3__intelligent_tiering_E");
   E612 : Short_Integer; pragma Import (Ada, E612, "flyology__object_storage__s3__inventory_E");
   E660 : Short_Integer; pragma Import (Ada, E660, "flyology__object_storage__s3__metrics_E");
   E670 : Short_Integer; pragma Import (Ada, E670, "flyology__object_storage__s3__replication_E");
   E515 : Short_Integer; pragma Import (Ada, E515, "flyology__object_storage__s3__strict_xml_codecs_E");
   E513 : Short_Integer; pragma Import (Ada, E513, "flyology__object_storage__s3__generated_list_directory_buckets_xml_E");
   E630 : Short_Integer; pragma Import (Ada, E630, "flyology__object_storage__s3__tagging_E");
   E674 : Short_Integer; pragma Import (Ada, E674, "flyology__object_storage__s3__versioning_E");
   E676 : Short_Integer; pragma Import (Ada, E676, "flyology__object_storage__s3__versions_E");
   E622 : Short_Integer; pragma Import (Ada, E622, "flyology__object_storage__s3__website_E");
   E606 : Short_Integer; pragma Import (Ada, E606, "flyology__object_storage__s3__xml_writers_E");
   E604 : Short_Integer; pragma Import (Ada, E604, "flyology__object_storage__s3__generated_put_bucket_acl_xml_E");
   E610 : Short_Integer; pragma Import (Ada, E610, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E616 : Short_Integer; pragma Import (Ada, E616, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E620 : Short_Integer; pragma Import (Ada, E620, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E656 : Short_Integer; pragma Import (Ada, E656, "flyology__object_storage__s3__metadata_configurations_E");
   E658 : Short_Integer; pragma Import (Ada, E658, "flyology__object_storage__s3__metadata_tables_E");
   E475 : Short_Integer; pragma Import (Ada, E475, "flyology__object_storage__client__low_level_E");

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
         E475 := E475 - 1;
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
         E622 := E622 - 1;
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
         E630 := E630 - 1;
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__generated_list_directory_buckets_xml__finalize_body");
      begin
         E513 := E513 - 1;
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
         E612 := E612 - 1;
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
         E618 := E618 - 1;
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
         E628 := E628 - 1;
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
         E600 := E600 - 1;
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
         E608 := E608 - 1;
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
         E517 := E517 - 1;
         F51;
      end;
      E567 := E567 - 1;
      declare
         procedure F52;
         pragma Import (Ada, F52, "sax__readers__finalize_spec");
      begin
         F52;
      end;
      E564 := E564 - 1;
      declare
         procedure F53;
         pragma Import (Ada, F53, "input_sources__strings__finalize_spec");
      begin
         F53;
      end;
      E578 := E578 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "input_sources__file__finalize_spec");
      begin
         F54;
      end;
      E519 := E519 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "input_sources__finalize_spec");
      begin
         F55;
      end;
      E598 := E598 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "sax__utils__finalize_spec");
      begin
         F56;
      end;
      E580 := E580 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "sax__attributes__finalize_spec");
      begin
         F57;
      end;
      E594 := E594 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__exceptions__finalize_spec");
      begin
         F58;
      end;
      E585 := E585 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__symbols__finalize_spec");
      begin
         F59;
      end;
      E592 := E592 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "sax__pointers__finalize_spec");
      begin
         F60;
      end;
      declare
         procedure F61;
         pragma Import (Ada, F61, "repro_client_objects_fake__finalize_body");
      begin
         E678 := E678 - 1;
         F61;
      end;
      declare
         procedure F62;
         pragma Import (Ada, F62, "flyology__http__client__finalize_body");
      begin
         E148 := E148 - 1;
         F62;
      end;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__client__finalize_spec");
      begin
         F63;
      end;
      E434 := E434 - 1;
      declare
         procedure F64;
         pragma Import (Ada, F64, "flyology__io__connections__tls__finalize_spec");
      begin
         F64;
      end;
      E436 := E436 - 1;
      declare
         procedure F65;
         pragma Import (Ada, F65, "flyology__io__tls__alpn__finalize_spec");
      begin
         F65;
      end;
      declare
         procedure F66;
         pragma Import (Ada, F66, "flyology__http__http_2_client_connection__finalize_body");
      begin
         E238 := E238 - 1;
         F66;
      end;
      E306 := E306 - 1;
      declare
         procedure F67;
         pragma Import (Ada, F67, "flyology__io__connections__drivers__finalize_spec");
      begin
         F67;
      end;
      declare
         procedure F68;
         pragma Import (Ada, F68, "flyology__io__connections__finalize_body");
      begin
         E285 := E285 - 1;
         F68;
      end;
      declare
         procedure F69;
         pragma Import (Ada, F69, "flyology__io__connections__finalize_spec");
      begin
         F69;
      end;
      declare
         procedure F70;
         pragma Import (Ada, F70, "flyology__io__tls__finalize_body");
      begin
         E294 := E294 - 1;
         F70;
      end;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__io__tls__finalize_spec");
      begin
         F71;
      end;
      E310 := E310 - 1;
      declare
         procedure F72;
         pragma Import (Ada, F72, "flyology__http__http_3__finalize_spec");
      begin
         F72;
      end;
      declare
         procedure F73;
         pragma Import (Ada, F73, "flyology__quic__connections__finalize_body");
      begin
         E339 := E339 - 1;
         F73;
      end;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__quic__connections__finalize_spec");
      begin
         F74;
      end;
      E362 := E362 - 1;
      declare
         procedure F75;
         pragma Import (Ada, F75, "flyology__quic__crypto_openssl__finalize_spec");
      begin
         F75;
      end;
      E632 := E632 - 1;
      declare
         procedure F76;
         pragma Import (Ada, F76, "flyology__object_storage__tags__finalize_spec");
      begin
         F76;
      end;
      E482 := E482 - 1;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F77;
      end;
      E440 := E440 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__io__dns__finalize_spec");
      begin
         F78;
      end;
      E297 := E297 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__io__sockets__finalize_spec");
      begin
         F79;
      end;
      E445 := E445 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__io__files__finalize_spec");
      begin
         F80;
      end;
      E248 := E248 - 1;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__bytes__finalize_spec");
      begin
         F81;
      end;
      E227 := E227 - 1;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__buffers__drivers__finalize_spec");
      begin
         F82;
      end;
      declare
         procedure F83;
         pragma Import (Ada, F83, "flyology__buffers__finalize_body");
      begin
         E150 := E150 - 1;
         F83;
      end;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__buffers__finalize_spec");
      begin
         F84;
      end;
      E271 := E271 - 1;
      E269 := E269 - 1;
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
      E265 := E265 - 1;
      declare
         procedure F87;
         pragma Import (Ada, F87, "flyology__wake_sources__finalize_spec");
      begin
         F87;
      end;
      E209 := E209 - 1;
      declare
         procedure F88;
         pragma Import (Ada, F88, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F88;
      end;
      E229 := E229 - 1;
      declare
         procedure F89;
         pragma Import (Ada, F89, "system__pool_global__finalize_spec");
      begin
         F89;
      end;
      E105 := E105 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "ada__strings__unbounded__finalize_spec");
      begin
         F90;
      end;
      E509 := E509 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "gnat__sha512__finalize_spec");
      begin
         F91;
      end;
      E503 := E503 - 1;
      declare
         procedure F92;
         pragma Import (Ada, F92, "gnat__sha256__finalize_spec");
      begin
         F92;
      end;
      E499 := E499 - 1;
      declare
         procedure F93;
         pragma Import (Ada, F93, "gnat__sha1__finalize_spec");
      begin
         F93;
      end;
      E490 := E490 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "gnat__md5__finalize_spec");
      begin
         F94;
      end;
      E569 := E569 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "ada__text_io__finalize_spec");
      begin
         F95;
      end;
      E253 := E253 - 1;
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
         E573 := E573 - 1;
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
           False, False, False, True, False, False, True, True, 
           False, True, True, False, True, True, True, True, 
           False, True, False, False, False, True, True, False, 
           True, True, False, True, True, True, True, False, 
           True, False, True, True, False, False, True, False, 
           True, False, False, False, True, False, False, False, 
           False, True, True, True, True, True, False, False, 
           True, False, True, True, True, False, True, True, 
           False, True, True, True, True, False, False, False, 
           True, False, False, False, False, True, True, True, 
           True, True, True, False),
         Count => (0, 0, 0, 2, 2, 1, 2, 1, 13, 0),
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
      E024 := E024 + 1;
      System.Exceptions'Elab_Spec;
      E025 := E025 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E020 := E020 + 1;
      E013 := E013 + 1;
      E008 := E008 + 1;
      Ada.Assertions'Elab_Spec;
      E162 := E162 + 1;
      Ada.Containers'Elab_Spec;
      E249 := E249 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E117 := E117 + 1;
      Ada.Strings'Elab_Spec;
      E086 := E086 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E090 := E090 + 1;
      Gnat'Elab_Spec;
      E266 := E266 + 1;
      Interfaces.C'Elab_Spec;
      E053 := E053 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E364 := E364 + 1;
      System.Os_Lib'Elab_Body;
      E055 := E055 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E098 := E098 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E088 := E088 + 1;
      Ada.Streams'Elab_Spec;
      E116 := E116 + 1;
      System.File_Control_Block'Elab_Spec;
      E574 := E574 + 1;
      System.Finalization_Root'Elab_Spec;
      E119 := E119 + 1;
      Ada.Finalization'Elab_Spec;
      E114 := E114 + 1;
      System.File_Io'Elab_Body;
      E573 := E573 + 1;
      System.Storage_Pools'Elab_Spec;
      E233 := E233 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E253 := E253 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E006 := E006 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E273 := E273 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E077 := E077 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E569 := E569 + 1;
      E492 := E492 + 1;
      E494 := E494 + 1;
      Gnat.Md5'Elab_Spec;
      E490 := E490 + 1;
      E501 := E501 + 1;
      E507 := E507 + 1;
      E505 := E505 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E511 := E511 + 1;
      Gnat.Sha1'Elab_Spec;
      E499 := E499 + 1;
      Gnat.Sha256'Elab_Spec;
      E503 := E503 + 1;
      Gnat.Sha512'Elab_Spec;
      E509 := E509 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E167 := E167 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E240 := E240 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E121 := E121 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E144 := E144 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E105 := E105 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E576 := E576 + 1;
      System.Interrupt_Management.Operations'Elab_Body;
      E456 := E456 + 1;
      System.Pool_Global'Elab_Spec;
      E229 := E229 + 1;
      System.Tasking.Initialization'Elab_Body;
      E213 := E213 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E203 := E203 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E209 := E209 + 1;
      System.Tasking.Queuing'Elab_Body;
      E221 := E221 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E462 := E462 + 1;
      System.Tasking.Stages'Elab_Body;
      E458 := E458 + 1;
      System.Tasking.Async_Delays'Elab_Body;
      E452 := E452 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E265 := E265 + 1;
      Flyology.Cancellation'Elab_Spec;
      E275 := E275 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E269 := E269 + 1;
      E271 := E271 + 1;
      Unicode'Elab_Body;
      E521 := E521 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E150 := E150 + 1;
      Flyology.Buffers.Drivers'Elab_Spec;
      Flyology.Buffers.Drivers'Elab_Body;
      E227 := E227 + 1;
      Flyology.Bytes'Elab_Spec;
      E248 := E248 + 1;
      E302 := E302 + 1;
      E447 := E447 + 1;
      Flyology.Http'Elab_Spec;
      E141 := E141 + 1;
      E236 := E236 + 1;
      E329 := E329 + 1;
      Flyology.Http.Headers'Elab_Spec;
      E257 := E257 + 1;
      E242 := E242 + 1;
      Flyology.Http.Http_2_Huffman'Elab_Body;
      E246 := E246 + 1;
      Flyology.Http.Http_2_Hpack'Elab_Spec;
      E244 := E244 + 1;
      E259 := E259 + 1;
      E261 := E261 + 1;
      E308 := E308 + 1;
      E263 := E263 + 1;
      E316 := E316 + 1;
      E335 := E335 + 1;
      E321 := E321 + 1;
      E323 := E323 + 1;
      E314 := E314 + 1;
      E331 := E331 + 1;
      E333 := E333 + 1;
      E327 := E327 + 1;
      E325 := E325 + 1;
      E337 := E337 + 1;
      Flyology.Io.Files'Elab_Spec;
      Flyology.Io.Files'Elab_Body;
      E445 := E445 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E297 := E297 + 1;
      Flyology.Io.Dns'Elab_Spec;
      Flyology.Io.Dns'Elab_Body;
      E440 := E440 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E467 := E467 + 1;
      E480 := E480 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E488 := E488 + 1;
      E478 := E478 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E624 := E624 + 1;
      E654 := E654 + 1;
      E602 := E602 + 1;
      E484 := E484 + 1;
      E486 := E486 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E482 := E482 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E672 := E672 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E632 := E632 + 1;
      E412 := E412 + 1;
      Flyology.Quic.Crypto_Openssl'Elab_Spec;
      Flyology.Quic.Crypto_Openssl'Elab_Body;
      E362 := E362 + 1;
      E357 := E357 + 1;
      E416 := E416 + 1;
      E418 := E418 + 1;
      E402 := E402 + 1;
      E406 := E406 + 1;
      E400 := E400 + 1;
      E420 := E420 + 1;
      E368 := E368 + 1;
      E374 := E374 + 1;
      E376 := E376 + 1;
      E360 := E360 + 1;
      E341 := E341 + 1;
      E414 := E414 + 1;
      E408 := E408 + 1;
      E422 := E422 + 1;
      E394 := E394 + 1;
      Flyology.Quic.Connections'Elab_Spec;
      Flyology.Quic.Connections'Elab_Body;
      E339 := E339 + 1;
      E312 := E312 + 1;
      Flyology.Http.Http_3'Elab_Spec;
      Flyology.Http.Http_3'Elab_Body;
      E310 := E310 + 1;
      E432 := E432 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E290 := E290 + 1;
      Flyology.Io.Tls'Elab_Body;
      E294 := E294 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E285 := E285 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E306 := E306 + 1;
      Flyology.Http.Http_2_Client_Connection'Elab_Spec;
      Flyology.Http.Http_2_Client_Connection'Elab_Body;
      E238 := E238 + 1;
      Flyology.Io.Tls.Alpn'Elab_Spec;
      E436 := E436 + 1;
      Flyology.Io.Connections.Tls'Elab_Spec;
      Flyology.Io.Connections.Tls'Elab_Body;
      E434 := E434 + 1;
      Flyology.Http.Client'Elab_Spec;
      Flyology.Http.Client'Elab_Body;
      E148 := E148 + 1;
      Repro_Client_Objects_Fake'Elab_Body;
      E678 := E678 + 1;
      E680 := E680 + 1;
      E590 := E590 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E592 := E592 + 1;
      Unicode.Ccs'Elab_Spec;
      E532 := E532 + 1;
      E534 := E534 + 1;
      E536 := E536 + 1;
      E541 := E541 + 1;
      E544 := E544 + 1;
      E546 := E546 + 1;
      E548 := E548 + 1;
      E553 := E553 + 1;
      Unicode.Ces'Elab_Spec;
      E528 := E528 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E585 := E585 + 1;
      E596 := E596 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E594 := E594 + 1;
      E558 := E558 + 1;
      E556 := E556 + 1;
      E560 := E560 + 1;
      E562 := E562 + 1;
      Sax.Models'Elab_Spec;
      E582 := E582 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E580 := E580 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E598 := E598 + 1;
      E530 := E530 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E519 := E519 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E578 := E578 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E564 := E564 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E567 := E567 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E517 := E517 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E608 := E608 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E640 := E640 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E600 := E600 + 1;
      Flyology.Object_Storage.S3.Copies'Elab_Spec;
      Flyology.Object_Storage.S3.Copies'Elab_Body;
      E642 := E642 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E628 := E628 + 1;
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
      E618 := E618 + 1;
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
      E626 := E626 + 1;
      E614 := E614 + 1;
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
      E612 := E612 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E660 := E660 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E670 := E670 + 1;
      E515 := E515 + 1;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Body;
      E513 := E513 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E630 := E630 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E674 := E674 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E676 := E676 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E622 := E622 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E606 := E606 + 1;
      E604 := E604 + 1;
      E610 := E610 + 1;
      E616 := E616 + 1;
      E620 := E620 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E656 := E656 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E658 := E658 + 1;
      Flyology.Object_Storage.Client.Low_Level'Elab_Spec;
      Flyology.Object_Storage.Client.Low_Level'Elab_Body;
      E475 := E475 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_client_low_4");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_client_objects_fake.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_support.o
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_client_low_4.o
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
