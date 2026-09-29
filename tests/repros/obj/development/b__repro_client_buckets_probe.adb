pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_client_buckets_probe.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_client_buckets_probe.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E008 : Short_Integer; pragma Import (Ada, E008, "ada__exceptions_E");
   E013 : Short_Integer; pragma Import (Ada, E013, "system__soft_links_E");
   E024 : Short_Integer; pragma Import (Ada, E024, "system__exception_table_E");
   E025 : Short_Integer; pragma Import (Ada, E025, "system__exceptions_E");
   E020 : Short_Integer; pragma Import (Ada, E020, "system__soft_links__initialize_E");
   E166 : Short_Integer; pragma Import (Ada, E166, "ada__assertions_E");
   E253 : Short_Integer; pragma Import (Ada, E253, "ada__containers_E");
   E092 : Short_Integer; pragma Import (Ada, E092, "ada__io_exceptions_E");
   E095 : Short_Integer; pragma Import (Ada, E095, "ada__strings_E");
   E097 : Short_Integer; pragma Import (Ada, E097, "ada__strings__utf_encoding_E");
   E270 : Short_Integer; pragma Import (Ada, E270, "gnat_E");
   E053 : Short_Integer; pragma Import (Ada, E053, "interfaces__c_E");
   E089 : Short_Integer; pragma Import (Ada, E089, "interfaces__c__strings_E");
   E055 : Short_Integer; pragma Import (Ada, E055, "system__os_lib_E");
   E105 : Short_Integer; pragma Import (Ada, E105, "ada__tags_E");
   E094 : Short_Integer; pragma Import (Ada, E094, "ada__strings__text_buffers_E");
   E091 : Short_Integer; pragma Import (Ada, E091, "ada__streams_E");
   E580 : Short_Integer; pragma Import (Ada, E580, "system__file_control_block_E");
   E133 : Short_Integer; pragma Import (Ada, E133, "system__finalization_root_E");
   E131 : Short_Integer; pragma Import (Ada, E131, "ada__finalization_E");
   E579 : Short_Integer; pragma Import (Ada, E579, "system__file_io_E");
   E237 : Short_Integer; pragma Import (Ada, E237, "system__storage_pools_E");
   E257 : Short_Integer; pragma Import (Ada, E257, "system__storage_pools__subpools_E");
   E006 : Short_Integer; pragma Import (Ada, E006, "ada__calendar_E");
   E277 : Short_Integer; pragma Import (Ada, E277, "ada__calendar__delays_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "ada__calendar__time_zones_E");
   E575 : Short_Integer; pragma Import (Ada, E575, "ada__text_io_E");
   E498 : Short_Integer; pragma Import (Ada, E498, "gnat__secure_hashes_E");
   E500 : Short_Integer; pragma Import (Ada, E500, "gnat__secure_hashes__md5_E");
   E496 : Short_Integer; pragma Import (Ada, E496, "gnat__md5_E");
   E507 : Short_Integer; pragma Import (Ada, E507, "gnat__secure_hashes__sha1_E");
   E513 : Short_Integer; pragma Import (Ada, E513, "gnat__secure_hashes__sha2_common_E");
   E511 : Short_Integer; pragma Import (Ada, E511, "gnat__secure_hashes__sha2_32_E");
   E517 : Short_Integer; pragma Import (Ada, E517, "gnat__secure_hashes__sha2_64_E");
   E505 : Short_Integer; pragma Import (Ada, E505, "gnat__sha1_E");
   E509 : Short_Integer; pragma Import (Ada, E509, "gnat__sha256_E");
   E515 : Short_Integer; pragma Import (Ada, E515, "gnat__sha512_E");
   E171 : Short_Integer; pragma Import (Ada, E171, "system__flyology__scheduler_E");
   E244 : Short_Integer; pragma Import (Ada, E244, "ada__real_time_E");
   E118 : Short_Integer; pragma Import (Ada, E118, "ada__strings__maps_E");
   E150 : Short_Integer; pragma Import (Ada, E150, "ada__strings__maps__constants_E");
   E126 : Short_Integer; pragma Import (Ada, E126, "ada__strings__unbounded_E");
   E582 : Short_Integer; pragma Import (Ada, E582, "gnat__directory_operations_E");
   E458 : Short_Integer; pragma Import (Ada, E458, "system__interrupt_management__operations_E");
   E233 : Short_Integer; pragma Import (Ada, E233, "system__pool_global_E");
   E217 : Short_Integer; pragma Import (Ada, E217, "system__tasking__initialization_E");
   E207 : Short_Integer; pragma Import (Ada, E207, "system__tasking__protected_objects_E");
   E213 : Short_Integer; pragma Import (Ada, E213, "system__tasking__protected_objects__entries_E");
   E225 : Short_Integer; pragma Import (Ada, E225, "system__tasking__queuing_E");
   E464 : Short_Integer; pragma Import (Ada, E464, "system__flyology__task_results_E");
   E460 : Short_Integer; pragma Import (Ada, E460, "system__tasking__stages_E");
   E454 : Short_Integer; pragma Import (Ada, E454, "system__tasking__async_delays_E");
   E269 : Short_Integer; pragma Import (Ada, E269, "flyology__wake_sources_E");
   E279 : Short_Integer; pragma Import (Ada, E279, "flyology__cancellation_E");
   E275 : Short_Integer; pragma Import (Ada, E275, "flyology__operations_E");
   E273 : Short_Integer; pragma Import (Ada, E273, "flyology__io_E");
   E527 : Short_Integer; pragma Import (Ada, E527, "unicode_E");
   E154 : Short_Integer; pragma Import (Ada, E154, "flyology__buffers_E");
   E231 : Short_Integer; pragma Import (Ada, E231, "flyology__buffers__drivers_E");
   E252 : Short_Integer; pragma Import (Ada, E252, "flyology__bytes_E");
   E306 : Short_Integer; pragma Import (Ada, E306, "flyology__capacity_E");
   E449 : Short_Integer; pragma Import (Ada, E449, "flyology__file_open_policy_E");
   E147 : Short_Integer; pragma Import (Ada, E147, "flyology__http_E");
   E240 : Short_Integer; pragma Import (Ada, E240, "flyology__http__client_policy_E");
   E333 : Short_Integer; pragma Import (Ada, E333, "flyology__http__header_huffman_policy_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "flyology__http__headers_E");
   E246 : Short_Integer; pragma Import (Ada, E246, "flyology__http__http_2_frames_E");
   E250 : Short_Integer; pragma Import (Ada, E250, "flyology__http__http_2_huffman_E");
   E248 : Short_Integer; pragma Import (Ada, E248, "flyology__http__http_2_hpack_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "flyology__http__http_2_payloads_E");
   E265 : Short_Integer; pragma Import (Ada, E265, "flyology__http__http_2_policy_E");
   E312 : Short_Integer; pragma Import (Ada, E312, "flyology__http__http_2_requests_E");
   E267 : Short_Integer; pragma Import (Ada, E267, "flyology__http__http_2_settings_E");
   E320 : Short_Integer; pragma Import (Ada, E320, "flyology__http__http_3_frame_policy_E");
   E339 : Short_Integer; pragma Import (Ada, E339, "flyology__http__http_3_message_policy_E");
   E325 : Short_Integer; pragma Import (Ada, E325, "flyology__http__http_3_settings_policy_E");
   E327 : Short_Integer; pragma Import (Ada, E327, "flyology__http__http_3_stream_policy_E");
   E318 : Short_Integer; pragma Import (Ada, E318, "flyology__http__http_3_control_policy_E");
   E335 : Short_Integer; pragma Import (Ada, E335, "flyology__http__qpack_integer_policy_E");
   E337 : Short_Integer; pragma Import (Ada, E337, "flyology__http__qpack_static_table_E");
   E331 : Short_Integer; pragma Import (Ada, E331, "flyology__http__qpack_field_section_policy_E");
   E329 : Short_Integer; pragma Import (Ada, E329, "flyology__http__http_3_header_policy_E");
   E341 : Short_Integer; pragma Import (Ada, E341, "flyology__http__http_3_stream_receive_policy_E");
   E447 : Short_Integer; pragma Import (Ada, E447, "flyology__io__files_E");
   E301 : Short_Integer; pragma Import (Ada, E301, "flyology__io__sockets_E");
   E442 : Short_Integer; pragma Import (Ada, E442, "flyology__io__dns_E");
   E469 : Short_Integer; pragma Import (Ada, E469, "flyology__object_storage_E");
   E486 : Short_Integer; pragma Import (Ada, E486, "flyology__object_storage__s3__core_E");
   E494 : Short_Integer; pragma Import (Ada, E494, "flyology__object_storage__s3__checksum_crc_E");
   E484 : Short_Integer; pragma Import (Ada, E484, "flyology__object_storage__s3__checksum_policy_E");
   E630 : Short_Integer; pragma Import (Ada, E630, "flyology__object_storage__s3__imf_dates_E");
   E660 : Short_Integer; pragma Import (Ada, E660, "flyology__object_storage__s3__model_E");
   E608 : Short_Integer; pragma Import (Ada, E608, "flyology__object_storage__s3__sigv4_encoding_E");
   E490 : Short_Integer; pragma Import (Ada, E490, "flyology__object_storage__s3__wire_core_E");
   E492 : Short_Integer; pragma Import (Ada, E492, "flyology__object_storage__secrets_E");
   E488 : Short_Integer; pragma Import (Ada, E488, "flyology__object_storage__s3__checksums_E");
   E678 : Short_Integer; pragma Import (Ada, E678, "flyology__object_storage__s3__sigv4_E");
   E638 : Short_Integer; pragma Import (Ada, E638, "flyology__object_storage__tags_E");
   E414 : Short_Integer; pragma Import (Ada, E414, "flyology__quic__crypto_flight_E");
   E366 : Short_Integer; pragma Import (Ada, E366, "flyology__quic__crypto_openssl_E");
   E361 : Short_Integer; pragma Import (Ada, E361, "flyology__quic__debug_E");
   E418 : Short_Integer; pragma Import (Ada, E418, "flyology__quic__handshake_receiver_E");
   E420 : Short_Integer; pragma Import (Ada, E420, "flyology__quic__handshake_sender_E");
   E404 : Short_Integer; pragma Import (Ada, E404, "flyology__quic__initial_receiver_E");
   E408 : Short_Integer; pragma Import (Ada, E408, "flyology__quic__initial_sender_E");
   E402 : Short_Integer; pragma Import (Ada, E402, "flyology__quic__initial_connection_E");
   E422 : Short_Integer; pragma Import (Ada, E422, "flyology__quic__initial_space_E");
   E370 : Short_Integer; pragma Import (Ada, E370, "flyology__quic__one_rtt_receiver_E");
   E376 : Short_Integer; pragma Import (Ada, E376, "flyology__quic__one_rtt_sender_E");
   E378 : Short_Integer; pragma Import (Ada, E378, "flyology__quic__tls_key_schedule_E");
   E364 : Short_Integer; pragma Import (Ada, E364, "flyology__quic__application_connection_E");
   E345 : Short_Integer; pragma Import (Ada, E345, "flyology__quic__application_space_E");
   E416 : Short_Integer; pragma Import (Ada, E416, "flyology__quic__handshake_connection_E");
   E410 : Short_Integer; pragma Import (Ada, E410, "flyology__quic__handshake_space_E");
   E424 : Short_Integer; pragma Import (Ada, E424, "flyology__quic__tls_session_E");
   E396 : Short_Integer; pragma Import (Ada, E396, "flyology__quic__connection_driver_E");
   E343 : Short_Integer; pragma Import (Ada, E343, "flyology__quic__connections_E");
   E316 : Short_Integer; pragma Import (Ada, E316, "flyology__http__http_3_connection_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "flyology__http__http_3_E");
   E434 : Short_Integer; pragma Import (Ada, E434, "flyology__http__http_3_client_connection_E");
   E298 : Short_Integer; pragma Import (Ada, E298, "flyology__io__tls_E");
   E294 : Short_Integer; pragma Import (Ada, E294, "flyology__io__tls_driver_E");
   E289 : Short_Integer; pragma Import (Ada, E289, "flyology__io__connections_E");
   E310 : Short_Integer; pragma Import (Ada, E310, "flyology__io__connections__drivers_E");
   E242 : Short_Integer; pragma Import (Ada, E242, "flyology__http__http_2_client_connection_E");
   E438 : Short_Integer; pragma Import (Ada, E438, "flyology__io__tls__alpn_E");
   E436 : Short_Integer; pragma Import (Ada, E436, "flyology__io__connections__tls_E");
   E152 : Short_Integer; pragma Import (Ada, E152, "flyology__http__client_E");
   E688 : Short_Integer; pragma Import (Ada, E688, "repro_support_E");
   E596 : Short_Integer; pragma Import (Ada, E596, "sax__htable_E");
   E598 : Short_Integer; pragma Import (Ada, E598, "sax__pointers_E");
   E538 : Short_Integer; pragma Import (Ada, E538, "unicode__ccs_E");
   E540 : Short_Integer; pragma Import (Ada, E540, "unicode__ccs__iso_8859_1_E");
   E542 : Short_Integer; pragma Import (Ada, E542, "unicode__ccs__iso_8859_15_E");
   E547 : Short_Integer; pragma Import (Ada, E547, "unicode__ccs__iso_8859_2_E");
   E550 : Short_Integer; pragma Import (Ada, E550, "unicode__ccs__iso_8859_3_E");
   E552 : Short_Integer; pragma Import (Ada, E552, "unicode__ccs__iso_8859_4_E");
   E554 : Short_Integer; pragma Import (Ada, E554, "unicode__ccs__windows_1251_E");
   E559 : Short_Integer; pragma Import (Ada, E559, "unicode__ccs__windows_1252_E");
   E534 : Short_Integer; pragma Import (Ada, E534, "unicode__ces_E");
   E591 : Short_Integer; pragma Import (Ada, E591, "sax__symbols_E");
   E602 : Short_Integer; pragma Import (Ada, E602, "sax__locators_E");
   E600 : Short_Integer; pragma Import (Ada, E600, "sax__exceptions_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "unicode__ces__utf32_E");
   E562 : Short_Integer; pragma Import (Ada, E562, "unicode__ces__basic_8bit_E");
   E566 : Short_Integer; pragma Import (Ada, E566, "unicode__ces__utf16_E");
   E568 : Short_Integer; pragma Import (Ada, E568, "unicode__ces__utf8_E");
   E588 : Short_Integer; pragma Import (Ada, E588, "sax__models_E");
   E586 : Short_Integer; pragma Import (Ada, E586, "sax__attributes_E");
   E604 : Short_Integer; pragma Import (Ada, E604, "sax__utils_E");
   E536 : Short_Integer; pragma Import (Ada, E536, "unicode__encodings_E");
   E525 : Short_Integer; pragma Import (Ada, E525, "input_sources_E");
   E584 : Short_Integer; pragma Import (Ada, E584, "input_sources__file_E");
   E570 : Short_Integer; pragma Import (Ada, E570, "input_sources__strings_E");
   E573 : Short_Integer; pragma Import (Ada, E573, "sax__readers_E");
   E523 : Short_Integer; pragma Import (Ada, E523, "flyology__object_storage__s3__xml_E");
   E614 : Short_Integer; pragma Import (Ada, E614, "flyology__object_storage__s3__acl_E");
   E646 : Short_Integer; pragma Import (Ada, E646, "flyology__object_storage__s3__bucket_controls_E");
   E606 : Short_Integer; pragma Import (Ada, E606, "flyology__object_storage__s3__buckets_E");
   E648 : Short_Integer; pragma Import (Ada, E648, "flyology__object_storage__s3__copies_E");
   E634 : Short_Integer; pragma Import (Ada, E634, "flyology__object_storage__s3__deletions_E");
   E644 : Short_Integer; pragma Import (Ada, E644, "flyology__object_storage__s3__attributes_E");
   E650 : Short_Integer; pragma Import (Ada, E650, "flyology__object_storage__s3__encryption_E");
   E652 : Short_Integer; pragma Import (Ada, E652, "flyology__object_storage__s3__errors_E");
   E656 : Short_Integer; pragma Import (Ada, E656, "flyology__object_storage__s3__lifecycle_E");
   E658 : Short_Integer; pragma Import (Ada, E658, "flyology__object_storage__s3__listings_E");
   E624 : Short_Integer; pragma Import (Ada, E624, "flyology__object_storage__s3__logging_E");
   E668 : Short_Integer; pragma Import (Ada, E668, "flyology__object_storage__s3__multipart_E");
   E670 : Short_Integer; pragma Import (Ada, E670, "flyology__object_storage__s3__multipart_uploads_E");
   E672 : Short_Integer; pragma Import (Ada, E672, "flyology__object_storage__s3__notifications_E");
   E674 : Short_Integer; pragma Import (Ada, E674, "flyology__object_storage__s3__object_lock_E");
   E632 : Short_Integer; pragma Import (Ada, E632, "flyology__object_storage__s3__object_reads_E");
   E620 : Short_Integer; pragma Import (Ada, E620, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E640 : Short_Integer; pragma Import (Ada, E640, "flyology__object_storage__s3__analytics_E");
   E642 : Short_Integer; pragma Import (Ada, E642, "flyology__object_storage__s3__annotations_E");
   E654 : Short_Integer; pragma Import (Ada, E654, "flyology__object_storage__s3__intelligent_tiering_E");
   E618 : Short_Integer; pragma Import (Ada, E618, "flyology__object_storage__s3__inventory_E");
   E666 : Short_Integer; pragma Import (Ada, E666, "flyology__object_storage__s3__metrics_E");
   E676 : Short_Integer; pragma Import (Ada, E676, "flyology__object_storage__s3__replication_E");
   E521 : Short_Integer; pragma Import (Ada, E521, "flyology__object_storage__s3__strict_xml_codecs_E");
   E519 : Short_Integer; pragma Import (Ada, E519, "flyology__object_storage__s3__generated_list_directory_buckets_xml_E");
   E636 : Short_Integer; pragma Import (Ada, E636, "flyology__object_storage__s3__tagging_E");
   E680 : Short_Integer; pragma Import (Ada, E680, "flyology__object_storage__s3__versioning_E");
   E682 : Short_Integer; pragma Import (Ada, E682, "flyology__object_storage__s3__versions_E");
   E628 : Short_Integer; pragma Import (Ada, E628, "flyology__object_storage__s3__website_E");
   E612 : Short_Integer; pragma Import (Ada, E612, "flyology__object_storage__s3__xml_writers_E");
   E610 : Short_Integer; pragma Import (Ada, E610, "flyology__object_storage__s3__generated_put_bucket_acl_xml_E");
   E616 : Short_Integer; pragma Import (Ada, E616, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E622 : Short_Integer; pragma Import (Ada, E622, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E626 : Short_Integer; pragma Import (Ada, E626, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E662 : Short_Integer; pragma Import (Ada, E662, "flyology__object_storage__s3__metadata_configurations_E");
   E664 : Short_Integer; pragma Import (Ada, E664, "flyology__object_storage__s3__metadata_tables_E");
   E481 : Short_Integer; pragma Import (Ada, E481, "flyology__object_storage__client__low_level_E");
   E479 : Short_Integer; pragma Import (Ada, E479, "flyology__object_storage__client__bounded_rest_xml_reads_E");
   E684 : Short_Integer; pragma Import (Ada, E684, "flyology__object_storage__client__paginated_rest_xml_reads_E");
   E686 : Short_Integer; pragma Import (Ada, E686, "flyology__object_storage__client__rest_xml_mutations_E");
   E477 : Short_Integer; pragma Import (Ada, E477, "flyology__object_storage__client__buckets_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      E477 := E477 - 1;
      declare
         procedure F1;
         pragma Import (Ada, F1, "flyology__object_storage__client__buckets__finalize_spec");
      begin
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology__object_storage__client__low_level__finalize_body");
      begin
         E481 := E481 - 1;
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__client__low_level__finalize_spec");
      begin
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__s3__metadata_tables__finalize_body");
      begin
         E664 := E664 - 1;
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E662 := E662 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__website__finalize_body");
      begin
         E628 := E628 - 1;
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
         E682 := E682 - 1;
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
         E680 := E680 - 1;
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__tagging__finalize_body");
      begin
         E636 := E636 - 1;
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__generated_list_directory_buckets_xml__finalize_body");
      begin
         E519 := E519 - 1;
         F12;
      end;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology__object_storage__s3__replication__finalize_body");
      begin
         E676 := E676 - 1;
         F13;
      end;
      declare
         procedure F14;
         pragma Import (Ada, F14, "flyology__object_storage__s3__replication__finalize_spec");
      begin
         F14;
      end;
      declare
         procedure F15;
         pragma Import (Ada, F15, "flyology__object_storage__s3__metrics__finalize_body");
      begin
         E666 := E666 - 1;
         F15;
      end;
      declare
         procedure F16;
         pragma Import (Ada, F16, "flyology__object_storage__s3__metrics__finalize_spec");
      begin
         F16;
      end;
      declare
         procedure F17;
         pragma Import (Ada, F17, "flyology__object_storage__s3__inventory__finalize_body");
      begin
         E618 := E618 - 1;
         F17;
      end;
      declare
         procedure F18;
         pragma Import (Ada, F18, "flyology__object_storage__s3__inventory__finalize_spec");
      begin
         F18;
      end;
      declare
         procedure F19;
         pragma Import (Ada, F19, "flyology__object_storage__s3__intelligent_tiering__finalize_body");
      begin
         E654 := E654 - 1;
         F19;
      end;
      declare
         procedure F20;
         pragma Import (Ada, F20, "flyology__object_storage__s3__intelligent_tiering__finalize_spec");
      begin
         F20;
      end;
      declare
         procedure F21;
         pragma Import (Ada, F21, "flyology__object_storage__s3__annotations__finalize_body");
      begin
         E642 := E642 - 1;
         F21;
      end;
      declare
         procedure F22;
         pragma Import (Ada, F22, "flyology__object_storage__s3__annotations__finalize_spec");
      begin
         F22;
      end;
      declare
         procedure F23;
         pragma Import (Ada, F23, "flyology__object_storage__s3__analytics__finalize_body");
      begin
         E640 := E640 - 1;
         F23;
      end;
      declare
         procedure F24;
         pragma Import (Ada, F24, "flyology__object_storage__s3__analytics__finalize_spec");
      begin
         F24;
      end;
      declare
         procedure F25;
         pragma Import (Ada, F25, "flyology__object_storage__s3__object_lock__finalize_body");
      begin
         E674 := E674 - 1;
         F25;
      end;
      declare
         procedure F26;
         pragma Import (Ada, F26, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E672 := E672 - 1;
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "flyology__object_storage__s3__notifications__finalize_spec");
      begin
         F27;
      end;
      declare
         procedure F28;
         pragma Import (Ada, F28, "flyology__object_storage__s3__multipart_uploads__finalize_body");
      begin
         E670 := E670 - 1;
         F28;
      end;
      declare
         procedure F29;
         pragma Import (Ada, F29, "flyology__object_storage__s3__multipart_uploads__finalize_spec");
      begin
         F29;
      end;
      declare
         procedure F30;
         pragma Import (Ada, F30, "flyology__object_storage__s3__multipart__finalize_body");
      begin
         E668 := E668 - 1;
         F30;
      end;
      declare
         procedure F31;
         pragma Import (Ada, F31, "flyology__object_storage__s3__multipart__finalize_spec");
      begin
         F31;
      end;
      declare
         procedure F32;
         pragma Import (Ada, F32, "flyology__object_storage__s3__logging__finalize_body");
      begin
         E624 := E624 - 1;
         F32;
      end;
      declare
         procedure F33;
         pragma Import (Ada, F33, "flyology__object_storage__s3__logging__finalize_spec");
      begin
         F33;
      end;
      declare
         procedure F34;
         pragma Import (Ada, F34, "flyology__object_storage__s3__listings__finalize_body");
      begin
         E658 := E658 - 1;
         F34;
      end;
      declare
         procedure F35;
         pragma Import (Ada, F35, "flyology__object_storage__s3__listings__finalize_spec");
      begin
         F35;
      end;
      declare
         procedure F36;
         pragma Import (Ada, F36, "flyology__object_storage__s3__lifecycle__finalize_body");
      begin
         E656 := E656 - 1;
         F36;
      end;
      declare
         procedure F37;
         pragma Import (Ada, F37, "flyology__object_storage__s3__lifecycle__finalize_spec");
      begin
         F37;
      end;
      declare
         procedure F38;
         pragma Import (Ada, F38, "flyology__object_storage__s3__errors__finalize_body");
      begin
         E652 := E652 - 1;
         F38;
      end;
      declare
         procedure F39;
         pragma Import (Ada, F39, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E650 := E650 - 1;
         F39;
      end;
      declare
         procedure F40;
         pragma Import (Ada, F40, "flyology__object_storage__s3__encryption__finalize_spec");
      begin
         F40;
      end;
      declare
         procedure F41;
         pragma Import (Ada, F41, "flyology__object_storage__s3__attributes__finalize_body");
      begin
         E644 := E644 - 1;
         F41;
      end;
      declare
         procedure F42;
         pragma Import (Ada, F42, "flyology__object_storage__s3__attributes__finalize_spec");
      begin
         F42;
      end;
      declare
         procedure F43;
         pragma Import (Ada, F43, "flyology__object_storage__s3__deletions__finalize_body");
      begin
         E634 := E634 - 1;
         F43;
      end;
      declare
         procedure F44;
         pragma Import (Ada, F44, "flyology__object_storage__s3__deletions__finalize_spec");
      begin
         F44;
      end;
      declare
         procedure F45;
         pragma Import (Ada, F45, "flyology__object_storage__s3__copies__finalize_body");
      begin
         E648 := E648 - 1;
         F45;
      end;
      declare
         procedure F46;
         pragma Import (Ada, F46, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E606 := E606 - 1;
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
         E646 := E646 - 1;
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
         E614 := E614 - 1;
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
         E523 := E523 - 1;
         F52;
      end;
      E573 := E573 - 1;
      declare
         procedure F53;
         pragma Import (Ada, F53, "sax__readers__finalize_spec");
      begin
         F53;
      end;
      E570 := E570 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "input_sources__strings__finalize_spec");
      begin
         F54;
      end;
      E584 := E584 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "input_sources__file__finalize_spec");
      begin
         F55;
      end;
      E525 := E525 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "input_sources__finalize_spec");
      begin
         F56;
      end;
      E604 := E604 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "sax__utils__finalize_spec");
      begin
         F57;
      end;
      E586 := E586 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__attributes__finalize_spec");
      begin
         F58;
      end;
      E600 := E600 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__exceptions__finalize_spec");
      begin
         F59;
      end;
      E591 := E591 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "sax__symbols__finalize_spec");
      begin
         F60;
      end;
      E598 := E598 - 1;
      declare
         procedure F61;
         pragma Import (Ada, F61, "sax__pointers__finalize_spec");
      begin
         F61;
      end;
      declare
         procedure F62;
         pragma Import (Ada, F62, "flyology__http__client__finalize_body");
      begin
         E152 := E152 - 1;
         F62;
      end;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__client__finalize_spec");
      begin
         F63;
      end;
      E436 := E436 - 1;
      declare
         procedure F64;
         pragma Import (Ada, F64, "flyology__io__connections__tls__finalize_spec");
      begin
         F64;
      end;
      E438 := E438 - 1;
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
         E242 := E242 - 1;
         F66;
      end;
      E310 := E310 - 1;
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
         E289 := E289 - 1;
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
         E298 := E298 - 1;
         F70;
      end;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__io__tls__finalize_spec");
      begin
         F71;
      end;
      E314 := E314 - 1;
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
         E343 := E343 - 1;
         F73;
      end;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__quic__connections__finalize_spec");
      begin
         F74;
      end;
      E366 := E366 - 1;
      declare
         procedure F75;
         pragma Import (Ada, F75, "flyology__quic__crypto_openssl__finalize_spec");
      begin
         F75;
      end;
      E638 := E638 - 1;
      declare
         procedure F76;
         pragma Import (Ada, F76, "flyology__object_storage__tags__finalize_spec");
      begin
         F76;
      end;
      E488 := E488 - 1;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F77;
      end;
      E442 := E442 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__io__dns__finalize_spec");
      begin
         F78;
      end;
      E301 := E301 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__io__sockets__finalize_spec");
      begin
         F79;
      end;
      E447 := E447 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__io__files__finalize_spec");
      begin
         F80;
      end;
      E252 := E252 - 1;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__bytes__finalize_spec");
      begin
         F81;
      end;
      E231 := E231 - 1;
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
         E154 := E154 - 1;
         F83;
      end;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__buffers__finalize_spec");
      begin
         F84;
      end;
      E275 := E275 - 1;
      E273 := E273 - 1;
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
      E269 := E269 - 1;
      declare
         procedure F87;
         pragma Import (Ada, F87, "flyology__wake_sources__finalize_spec");
      begin
         F87;
      end;
      E213 := E213 - 1;
      declare
         procedure F88;
         pragma Import (Ada, F88, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F88;
      end;
      E233 := E233 - 1;
      declare
         procedure F89;
         pragma Import (Ada, F89, "system__pool_global__finalize_spec");
      begin
         F89;
      end;
      E126 := E126 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "ada__strings__unbounded__finalize_spec");
      begin
         F90;
      end;
      E515 := E515 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "gnat__sha512__finalize_spec");
      begin
         F91;
      end;
      E509 := E509 - 1;
      declare
         procedure F92;
         pragma Import (Ada, F92, "gnat__sha256__finalize_spec");
      begin
         F92;
      end;
      E505 := E505 - 1;
      declare
         procedure F93;
         pragma Import (Ada, F93, "gnat__sha1__finalize_spec");
      begin
         F93;
      end;
      E496 := E496 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "gnat__md5__finalize_spec");
      begin
         F94;
      end;
      E575 := E575 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "ada__text_io__finalize_spec");
      begin
         F95;
      end;
      E257 := E257 - 1;
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
         E579 := E579 - 1;
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
      E024 := E024 + 1;
      System.Exceptions'Elab_Spec;
      E025 := E025 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E020 := E020 + 1;
      E013 := E013 + 1;
      E008 := E008 + 1;
      Ada.Assertions'Elab_Spec;
      E166 := E166 + 1;
      Ada.Containers'Elab_Spec;
      E253 := E253 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E092 := E092 + 1;
      Ada.Strings'Elab_Spec;
      E095 := E095 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E097 := E097 + 1;
      Gnat'Elab_Spec;
      E270 := E270 + 1;
      Interfaces.C'Elab_Spec;
      E053 := E053 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E089 := E089 + 1;
      System.Os_Lib'Elab_Body;
      E055 := E055 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E105 := E105 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E094 := E094 + 1;
      Ada.Streams'Elab_Spec;
      E091 := E091 + 1;
      System.File_Control_Block'Elab_Spec;
      E580 := E580 + 1;
      System.Finalization_Root'Elab_Spec;
      E133 := E133 + 1;
      Ada.Finalization'Elab_Spec;
      E131 := E131 + 1;
      System.File_Io'Elab_Body;
      E579 := E579 + 1;
      System.Storage_Pools'Elab_Spec;
      E237 := E237 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E257 := E257 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E006 := E006 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E277 := E277 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E077 := E077 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E575 := E575 + 1;
      E498 := E498 + 1;
      E500 := E500 + 1;
      Gnat.Md5'Elab_Spec;
      E496 := E496 + 1;
      E507 := E507 + 1;
      E513 := E513 + 1;
      E511 := E511 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E517 := E517 + 1;
      Gnat.Sha1'Elab_Spec;
      E505 := E505 + 1;
      Gnat.Sha256'Elab_Spec;
      E509 := E509 + 1;
      Gnat.Sha512'Elab_Spec;
      E515 := E515 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E171 := E171 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E244 := E244 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E118 := E118 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E150 := E150 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E126 := E126 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E582 := E582 + 1;
      System.Interrupt_Management.Operations'Elab_Body;
      E458 := E458 + 1;
      System.Pool_Global'Elab_Spec;
      E233 := E233 + 1;
      System.Tasking.Initialization'Elab_Body;
      E217 := E217 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E207 := E207 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E213 := E213 + 1;
      System.Tasking.Queuing'Elab_Body;
      E225 := E225 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E464 := E464 + 1;
      System.Tasking.Stages'Elab_Body;
      E460 := E460 + 1;
      System.Tasking.Async_Delays'Elab_Body;
      E454 := E454 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E269 := E269 + 1;
      Flyology.Cancellation'Elab_Spec;
      E279 := E279 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E273 := E273 + 1;
      E275 := E275 + 1;
      Unicode'Elab_Body;
      E527 := E527 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E154 := E154 + 1;
      Flyology.Buffers.Drivers'Elab_Spec;
      Flyology.Buffers.Drivers'Elab_Body;
      E231 := E231 + 1;
      Flyology.Bytes'Elab_Spec;
      E252 := E252 + 1;
      E306 := E306 + 1;
      E449 := E449 + 1;
      Flyology.Http'Elab_Spec;
      E147 := E147 + 1;
      E240 := E240 + 1;
      E333 := E333 + 1;
      Flyology.Http.Headers'Elab_Spec;
      E261 := E261 + 1;
      E246 := E246 + 1;
      Flyology.Http.Http_2_Huffman'Elab_Body;
      E250 := E250 + 1;
      Flyology.Http.Http_2_Hpack'Elab_Spec;
      E248 := E248 + 1;
      E263 := E263 + 1;
      E265 := E265 + 1;
      E312 := E312 + 1;
      E267 := E267 + 1;
      E320 := E320 + 1;
      E339 := E339 + 1;
      E325 := E325 + 1;
      E327 := E327 + 1;
      E318 := E318 + 1;
      E335 := E335 + 1;
      E337 := E337 + 1;
      E331 := E331 + 1;
      E329 := E329 + 1;
      E341 := E341 + 1;
      Flyology.Io.Files'Elab_Spec;
      Flyology.Io.Files'Elab_Body;
      E447 := E447 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E301 := E301 + 1;
      Flyology.Io.Dns'Elab_Spec;
      Flyology.Io.Dns'Elab_Body;
      E442 := E442 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E469 := E469 + 1;
      E486 := E486 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E494 := E494 + 1;
      E484 := E484 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E630 := E630 + 1;
      E660 := E660 + 1;
      E608 := E608 + 1;
      E490 := E490 + 1;
      E492 := E492 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E488 := E488 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E678 := E678 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E638 := E638 + 1;
      E414 := E414 + 1;
      Flyology.Quic.Crypto_Openssl'Elab_Spec;
      Flyology.Quic.Crypto_Openssl'Elab_Body;
      E366 := E366 + 1;
      E361 := E361 + 1;
      E418 := E418 + 1;
      E420 := E420 + 1;
      E404 := E404 + 1;
      E408 := E408 + 1;
      E402 := E402 + 1;
      E422 := E422 + 1;
      E370 := E370 + 1;
      E376 := E376 + 1;
      E378 := E378 + 1;
      E364 := E364 + 1;
      E345 := E345 + 1;
      E416 := E416 + 1;
      E410 := E410 + 1;
      E424 := E424 + 1;
      E396 := E396 + 1;
      Flyology.Quic.Connections'Elab_Spec;
      Flyology.Quic.Connections'Elab_Body;
      E343 := E343 + 1;
      E316 := E316 + 1;
      Flyology.Http.Http_3'Elab_Spec;
      Flyology.Http.Http_3'Elab_Body;
      E314 := E314 + 1;
      E434 := E434 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E294 := E294 + 1;
      Flyology.Io.Tls'Elab_Body;
      E298 := E298 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E289 := E289 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E310 := E310 + 1;
      Flyology.Http.Http_2_Client_Connection'Elab_Spec;
      Flyology.Http.Http_2_Client_Connection'Elab_Body;
      E242 := E242 + 1;
      Flyology.Io.Tls.Alpn'Elab_Spec;
      E438 := E438 + 1;
      Flyology.Io.Connections.Tls'Elab_Spec;
      Flyology.Io.Connections.Tls'Elab_Body;
      E436 := E436 + 1;
      Flyology.Http.Client'Elab_Spec;
      Flyology.Http.Client'Elab_Body;
      E152 := E152 + 1;
      E688 := E688 + 1;
      E596 := E596 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E598 := E598 + 1;
      Unicode.Ccs'Elab_Spec;
      E538 := E538 + 1;
      E540 := E540 + 1;
      E542 := E542 + 1;
      E547 := E547 + 1;
      E550 := E550 + 1;
      E552 := E552 + 1;
      E554 := E554 + 1;
      E559 := E559 + 1;
      Unicode.Ces'Elab_Spec;
      E534 := E534 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E591 := E591 + 1;
      E602 := E602 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E600 := E600 + 1;
      E564 := E564 + 1;
      E562 := E562 + 1;
      E566 := E566 + 1;
      E568 := E568 + 1;
      Sax.Models'Elab_Spec;
      E588 := E588 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E586 := E586 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E604 := E604 + 1;
      E536 := E536 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E525 := E525 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E584 := E584 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E570 := E570 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E573 := E573 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E523 := E523 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E614 := E614 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E646 := E646 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E606 := E606 + 1;
      Flyology.Object_Storage.S3.Copies'Elab_Spec;
      Flyology.Object_Storage.S3.Copies'Elab_Body;
      E648 := E648 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E634 := E634 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E644 := E644 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E650 := E650 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E652 := E652 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E656 := E656 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E658 := E658 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E624 := E624 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E668 := E668 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E670 := E670 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E672 := E672 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E674 := E674 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E632 := E632 + 1;
      E620 := E620 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E640 := E640 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E642 := E642 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E654 := E654 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E618 := E618 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E666 := E666 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E676 := E676 + 1;
      E521 := E521 + 1;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Body;
      E519 := E519 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E636 := E636 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E680 := E680 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E682 := E682 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E628 := E628 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E612 := E612 + 1;
      E610 := E610 + 1;
      E616 := E616 + 1;
      E622 := E622 + 1;
      E626 := E626 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E662 := E662 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E664 := E664 + 1;
      Flyology.Object_Storage.Client.Low_Level'Elab_Spec;
      Flyology.Object_Storage.Client.Low_Level'Elab_Body;
      E481 := E481 + 1;
      E479 := E479 + 1;
      E684 := E684 + 1;
      E686 := E686 + 1;
      Flyology.Object_Storage.Client.Buckets'Elab_Spec;
      Flyology.Object_Storage.Client.Buckets'Elab_Body;
      E477 := E477 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_client_buckets_probe");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_client_buckets_probe.o
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
