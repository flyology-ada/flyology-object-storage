pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_transfers_minio_probe.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_transfers_minio_probe.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E008 : Short_Integer; pragma Import (Ada, E008, "ada__exceptions_E");
   E013 : Short_Integer; pragma Import (Ada, E013, "system__soft_links_E");
   E024 : Short_Integer; pragma Import (Ada, E024, "system__exception_table_E");
   E025 : Short_Integer; pragma Import (Ada, E025, "system__exceptions_E");
   E020 : Short_Integer; pragma Import (Ada, E020, "system__soft_links__initialize_E");
   E191 : Short_Integer; pragma Import (Ada, E191, "ada__assertions_E");
   E100 : Short_Integer; pragma Import (Ada, E100, "ada__containers_E");
   E106 : Short_Integer; pragma Import (Ada, E106, "ada__io_exceptions_E");
   E090 : Short_Integer; pragma Import (Ada, E090, "ada__strings_E");
   E110 : Short_Integer; pragma Import (Ada, E110, "ada__strings__utf_encoding_E");
   E290 : Short_Integer; pragma Import (Ada, E290, "gnat_E");
   E053 : Short_Integer; pragma Import (Ada, E053, "interfaces__c_E");
   E166 : Short_Integer; pragma Import (Ada, E166, "interfaces__c__strings_E");
   E055 : Short_Integer; pragma Import (Ada, E055, "system__os_lib_E");
   E118 : Short_Integer; pragma Import (Ada, E118, "ada__tags_E");
   E108 : Short_Integer; pragma Import (Ada, E108, "ada__strings__text_buffers_E");
   E105 : Short_Integer; pragma Import (Ada, E105, "ada__streams_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "system__file_control_block_E");
   E129 : Short_Integer; pragma Import (Ada, E129, "system__finalization_root_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "ada__finalization_E");
   E155 : Short_Integer; pragma Import (Ada, E155, "system__file_io_E");
   E168 : Short_Integer; pragma Import (Ada, E168, "ada__streams__stream_io_E");
   E162 : Short_Integer; pragma Import (Ada, E162, "system__storage_pools_E");
   E277 : Short_Integer; pragma Import (Ada, E277, "system__storage_pools__subpools_E");
   E006 : Short_Integer; pragma Import (Ada, E006, "ada__calendar_E");
   E297 : Short_Integer; pragma Import (Ada, E297, "ada__calendar__delays_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "ada__calendar__time_zones_E");
   E591 : Short_Integer; pragma Import (Ada, E591, "ada__text_io_E");
   E514 : Short_Integer; pragma Import (Ada, E514, "gnat__secure_hashes_E");
   E516 : Short_Integer; pragma Import (Ada, E516, "gnat__secure_hashes__md5_E");
   E512 : Short_Integer; pragma Import (Ada, E512, "gnat__md5_E");
   E523 : Short_Integer; pragma Import (Ada, E523, "gnat__secure_hashes__sha1_E");
   E529 : Short_Integer; pragma Import (Ada, E529, "gnat__secure_hashes__sha2_common_E");
   E527 : Short_Integer; pragma Import (Ada, E527, "gnat__secure_hashes__sha2_32_E");
   E533 : Short_Integer; pragma Import (Ada, E533, "gnat__secure_hashes__sha2_64_E");
   E521 : Short_Integer; pragma Import (Ada, E521, "gnat__sha1_E");
   E525 : Short_Integer; pragma Import (Ada, E525, "gnat__sha256_E");
   E531 : Short_Integer; pragma Import (Ada, E531, "gnat__sha512_E");
   E196 : Short_Integer; pragma Import (Ada, E196, "system__flyology__scheduler_E");
   E267 : Short_Integer; pragma Import (Ada, E267, "ada__real_time_E");
   E092 : Short_Integer; pragma Import (Ada, E092, "ada__strings__maps_E");
   E095 : Short_Integer; pragma Import (Ada, E095, "ada__strings__maps__constants_E");
   E141 : Short_Integer; pragma Import (Ada, E141, "ada__strings__unbounded_E");
   E593 : Short_Integer; pragma Import (Ada, E593, "gnat__directory_operations_E");
   E478 : Short_Integer; pragma Import (Ada, E478, "system__interrupt_management__operations_E");
   E258 : Short_Integer; pragma Import (Ada, E258, "system__pool_global_E");
   E160 : Short_Integer; pragma Import (Ada, E160, "system__regexp_E");
   E099 : Short_Integer; pragma Import (Ada, E099, "ada__directories_E");
   E242 : Short_Integer; pragma Import (Ada, E242, "system__tasking__initialization_E");
   E232 : Short_Integer; pragma Import (Ada, E232, "system__tasking__protected_objects_E");
   E238 : Short_Integer; pragma Import (Ada, E238, "system__tasking__protected_objects__entries_E");
   E250 : Short_Integer; pragma Import (Ada, E250, "system__tasking__queuing_E");
   E484 : Short_Integer; pragma Import (Ada, E484, "system__flyology__task_results_E");
   E480 : Short_Integer; pragma Import (Ada, E480, "system__tasking__stages_E");
   E474 : Short_Integer; pragma Import (Ada, E474, "system__tasking__async_delays_E");
   E289 : Short_Integer; pragma Import (Ada, E289, "flyology__wake_sources_E");
   E299 : Short_Integer; pragma Import (Ada, E299, "flyology__cancellation_E");
   E295 : Short_Integer; pragma Import (Ada, E295, "flyology__operations_E");
   E293 : Short_Integer; pragma Import (Ada, E293, "flyology__io_E");
   E543 : Short_Integer; pragma Import (Ada, E543, "unicode_E");
   E179 : Short_Integer; pragma Import (Ada, E179, "flyology__buffers_E");
   E256 : Short_Integer; pragma Import (Ada, E256, "flyology__buffers__drivers_E");
   E275 : Short_Integer; pragma Import (Ada, E275, "flyology__bytes_E");
   E326 : Short_Integer; pragma Import (Ada, E326, "flyology__capacity_E");
   E469 : Short_Integer; pragma Import (Ada, E469, "flyology__file_open_policy_E");
   E175 : Short_Integer; pragma Import (Ada, E175, "flyology__http_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "flyology__http__client_policy_E");
   E353 : Short_Integer; pragma Import (Ada, E353, "flyology__http__header_huffman_policy_E");
   E281 : Short_Integer; pragma Import (Ada, E281, "flyology__http__headers_E");
   E269 : Short_Integer; pragma Import (Ada, E269, "flyology__http__http_2_frames_E");
   E273 : Short_Integer; pragma Import (Ada, E273, "flyology__http__http_2_huffman_E");
   E271 : Short_Integer; pragma Import (Ada, E271, "flyology__http__http_2_hpack_E");
   E283 : Short_Integer; pragma Import (Ada, E283, "flyology__http__http_2_payloads_E");
   E285 : Short_Integer; pragma Import (Ada, E285, "flyology__http__http_2_policy_E");
   E332 : Short_Integer; pragma Import (Ada, E332, "flyology__http__http_2_requests_E");
   E287 : Short_Integer; pragma Import (Ada, E287, "flyology__http__http_2_settings_E");
   E340 : Short_Integer; pragma Import (Ada, E340, "flyology__http__http_3_frame_policy_E");
   E359 : Short_Integer; pragma Import (Ada, E359, "flyology__http__http_3_message_policy_E");
   E345 : Short_Integer; pragma Import (Ada, E345, "flyology__http__http_3_settings_policy_E");
   E347 : Short_Integer; pragma Import (Ada, E347, "flyology__http__http_3_stream_policy_E");
   E338 : Short_Integer; pragma Import (Ada, E338, "flyology__http__http_3_control_policy_E");
   E355 : Short_Integer; pragma Import (Ada, E355, "flyology__http__qpack_integer_policy_E");
   E357 : Short_Integer; pragma Import (Ada, E357, "flyology__http__qpack_static_table_E");
   E351 : Short_Integer; pragma Import (Ada, E351, "flyology__http__qpack_field_section_policy_E");
   E349 : Short_Integer; pragma Import (Ada, E349, "flyology__http__http_3_header_policy_E");
   E361 : Short_Integer; pragma Import (Ada, E361, "flyology__http__http_3_stream_receive_policy_E");
   E467 : Short_Integer; pragma Import (Ada, E467, "flyology__io__files_E");
   E321 : Short_Integer; pragma Import (Ada, E321, "flyology__io__sockets_E");
   E462 : Short_Integer; pragma Import (Ada, E462, "flyology__io__dns_E");
   E489 : Short_Integer; pragma Import (Ada, E489, "flyology__object_storage_E");
   E502 : Short_Integer; pragma Import (Ada, E502, "flyology__object_storage__s3__core_E");
   E510 : Short_Integer; pragma Import (Ada, E510, "flyology__object_storage__s3__checksum_crc_E");
   E500 : Short_Integer; pragma Import (Ada, E500, "flyology__object_storage__s3__checksum_policy_E");
   E641 : Short_Integer; pragma Import (Ada, E641, "flyology__object_storage__s3__imf_dates_E");
   E671 : Short_Integer; pragma Import (Ada, E671, "flyology__object_storage__s3__model_E");
   E701 : Short_Integer; pragma Import (Ada, E701, "flyology__object_storage__s3__requests_E");
   E619 : Short_Integer; pragma Import (Ada, E619, "flyology__object_storage__s3__sigv4_encoding_E");
   E506 : Short_Integer; pragma Import (Ada, E506, "flyology__object_storage__s3__wire_core_E");
   E508 : Short_Integer; pragma Import (Ada, E508, "flyology__object_storage__secrets_E");
   E504 : Short_Integer; pragma Import (Ada, E504, "flyology__object_storage__s3__checksums_E");
   E689 : Short_Integer; pragma Import (Ada, E689, "flyology__object_storage__s3__sigv4_E");
   E649 : Short_Integer; pragma Import (Ada, E649, "flyology__object_storage__tags_E");
   E434 : Short_Integer; pragma Import (Ada, E434, "flyology__quic__crypto_flight_E");
   E386 : Short_Integer; pragma Import (Ada, E386, "flyology__quic__crypto_openssl_E");
   E381 : Short_Integer; pragma Import (Ada, E381, "flyology__quic__debug_E");
   E438 : Short_Integer; pragma Import (Ada, E438, "flyology__quic__handshake_receiver_E");
   E440 : Short_Integer; pragma Import (Ada, E440, "flyology__quic__handshake_sender_E");
   E424 : Short_Integer; pragma Import (Ada, E424, "flyology__quic__initial_receiver_E");
   E428 : Short_Integer; pragma Import (Ada, E428, "flyology__quic__initial_sender_E");
   E422 : Short_Integer; pragma Import (Ada, E422, "flyology__quic__initial_connection_E");
   E442 : Short_Integer; pragma Import (Ada, E442, "flyology__quic__initial_space_E");
   E390 : Short_Integer; pragma Import (Ada, E390, "flyology__quic__one_rtt_receiver_E");
   E396 : Short_Integer; pragma Import (Ada, E396, "flyology__quic__one_rtt_sender_E");
   E398 : Short_Integer; pragma Import (Ada, E398, "flyology__quic__tls_key_schedule_E");
   E384 : Short_Integer; pragma Import (Ada, E384, "flyology__quic__application_connection_E");
   E365 : Short_Integer; pragma Import (Ada, E365, "flyology__quic__application_space_E");
   E436 : Short_Integer; pragma Import (Ada, E436, "flyology__quic__handshake_connection_E");
   E430 : Short_Integer; pragma Import (Ada, E430, "flyology__quic__handshake_space_E");
   E444 : Short_Integer; pragma Import (Ada, E444, "flyology__quic__tls_session_E");
   E416 : Short_Integer; pragma Import (Ada, E416, "flyology__quic__connection_driver_E");
   E363 : Short_Integer; pragma Import (Ada, E363, "flyology__quic__connections_E");
   E336 : Short_Integer; pragma Import (Ada, E336, "flyology__http__http_3_connection_E");
   E334 : Short_Integer; pragma Import (Ada, E334, "flyology__http__http_3_E");
   E454 : Short_Integer; pragma Import (Ada, E454, "flyology__http__http_3_client_connection_E");
   E705 : Short_Integer; pragma Import (Ada, E705, "flyology__task_scopes_E");
   E318 : Short_Integer; pragma Import (Ada, E318, "flyology__io__tls_E");
   E314 : Short_Integer; pragma Import (Ada, E314, "flyology__io__tls_driver_E");
   E309 : Short_Integer; pragma Import (Ada, E309, "flyology__io__connections_E");
   E330 : Short_Integer; pragma Import (Ada, E330, "flyology__io__connections__drivers_E");
   E265 : Short_Integer; pragma Import (Ada, E265, "flyology__http__http_2_client_connection_E");
   E458 : Short_Integer; pragma Import (Ada, E458, "flyology__io__tls__alpn_E");
   E456 : Short_Integer; pragma Import (Ada, E456, "flyology__io__connections__tls_E");
   E177 : Short_Integer; pragma Import (Ada, E177, "flyology__http__client_E");
   E697 : Short_Integer; pragma Import (Ada, E697, "flyology__http__client__request_bodies_E");
   E699 : Short_Integer; pragma Import (Ada, E699, "flyology__http__client__request_bodies__files_E");
   E707 : Short_Integer; pragma Import (Ada, E707, "repro_support_E");
   E607 : Short_Integer; pragma Import (Ada, E607, "sax__htable_E");
   E609 : Short_Integer; pragma Import (Ada, E609, "sax__pointers_E");
   E554 : Short_Integer; pragma Import (Ada, E554, "unicode__ccs_E");
   E556 : Short_Integer; pragma Import (Ada, E556, "unicode__ccs__iso_8859_1_E");
   E558 : Short_Integer; pragma Import (Ada, E558, "unicode__ccs__iso_8859_15_E");
   E563 : Short_Integer; pragma Import (Ada, E563, "unicode__ccs__iso_8859_2_E");
   E566 : Short_Integer; pragma Import (Ada, E566, "unicode__ccs__iso_8859_3_E");
   E568 : Short_Integer; pragma Import (Ada, E568, "unicode__ccs__iso_8859_4_E");
   E570 : Short_Integer; pragma Import (Ada, E570, "unicode__ccs__windows_1251_E");
   E575 : Short_Integer; pragma Import (Ada, E575, "unicode__ccs__windows_1252_E");
   E550 : Short_Integer; pragma Import (Ada, E550, "unicode__ces_E");
   E602 : Short_Integer; pragma Import (Ada, E602, "sax__symbols_E");
   E613 : Short_Integer; pragma Import (Ada, E613, "sax__locators_E");
   E611 : Short_Integer; pragma Import (Ada, E611, "sax__exceptions_E");
   E580 : Short_Integer; pragma Import (Ada, E580, "unicode__ces__utf32_E");
   E578 : Short_Integer; pragma Import (Ada, E578, "unicode__ces__basic_8bit_E");
   E582 : Short_Integer; pragma Import (Ada, E582, "unicode__ces__utf16_E");
   E584 : Short_Integer; pragma Import (Ada, E584, "unicode__ces__utf8_E");
   E599 : Short_Integer; pragma Import (Ada, E599, "sax__models_E");
   E597 : Short_Integer; pragma Import (Ada, E597, "sax__attributes_E");
   E615 : Short_Integer; pragma Import (Ada, E615, "sax__utils_E");
   E552 : Short_Integer; pragma Import (Ada, E552, "unicode__encodings_E");
   E541 : Short_Integer; pragma Import (Ada, E541, "input_sources_E");
   E595 : Short_Integer; pragma Import (Ada, E595, "input_sources__file_E");
   E586 : Short_Integer; pragma Import (Ada, E586, "input_sources__strings_E");
   E589 : Short_Integer; pragma Import (Ada, E589, "sax__readers_E");
   E539 : Short_Integer; pragma Import (Ada, E539, "flyology__object_storage__s3__xml_E");
   E625 : Short_Integer; pragma Import (Ada, E625, "flyology__object_storage__s3__acl_E");
   E657 : Short_Integer; pragma Import (Ada, E657, "flyology__object_storage__s3__bucket_controls_E");
   E617 : Short_Integer; pragma Import (Ada, E617, "flyology__object_storage__s3__buckets_E");
   E659 : Short_Integer; pragma Import (Ada, E659, "flyology__object_storage__s3__copies_E");
   E645 : Short_Integer; pragma Import (Ada, E645, "flyology__object_storage__s3__deletions_E");
   E655 : Short_Integer; pragma Import (Ada, E655, "flyology__object_storage__s3__attributes_E");
   E661 : Short_Integer; pragma Import (Ada, E661, "flyology__object_storage__s3__encryption_E");
   E663 : Short_Integer; pragma Import (Ada, E663, "flyology__object_storage__s3__errors_E");
   E667 : Short_Integer; pragma Import (Ada, E667, "flyology__object_storage__s3__lifecycle_E");
   E669 : Short_Integer; pragma Import (Ada, E669, "flyology__object_storage__s3__listings_E");
   E635 : Short_Integer; pragma Import (Ada, E635, "flyology__object_storage__s3__logging_E");
   E679 : Short_Integer; pragma Import (Ada, E679, "flyology__object_storage__s3__multipart_E");
   E681 : Short_Integer; pragma Import (Ada, E681, "flyology__object_storage__s3__multipart_uploads_E");
   E683 : Short_Integer; pragma Import (Ada, E683, "flyology__object_storage__s3__notifications_E");
   E685 : Short_Integer; pragma Import (Ada, E685, "flyology__object_storage__s3__object_lock_E");
   E643 : Short_Integer; pragma Import (Ada, E643, "flyology__object_storage__s3__object_reads_E");
   E631 : Short_Integer; pragma Import (Ada, E631, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E651 : Short_Integer; pragma Import (Ada, E651, "flyology__object_storage__s3__analytics_E");
   E653 : Short_Integer; pragma Import (Ada, E653, "flyology__object_storage__s3__annotations_E");
   E665 : Short_Integer; pragma Import (Ada, E665, "flyology__object_storage__s3__intelligent_tiering_E");
   E629 : Short_Integer; pragma Import (Ada, E629, "flyology__object_storage__s3__inventory_E");
   E677 : Short_Integer; pragma Import (Ada, E677, "flyology__object_storage__s3__metrics_E");
   E687 : Short_Integer; pragma Import (Ada, E687, "flyology__object_storage__s3__replication_E");
   E537 : Short_Integer; pragma Import (Ada, E537, "flyology__object_storage__s3__strict_xml_codecs_E");
   E535 : Short_Integer; pragma Import (Ada, E535, "flyology__object_storage__s3__generated_list_directory_buckets_xml_E");
   E647 : Short_Integer; pragma Import (Ada, E647, "flyology__object_storage__s3__tagging_E");
   E691 : Short_Integer; pragma Import (Ada, E691, "flyology__object_storage__s3__versioning_E");
   E693 : Short_Integer; pragma Import (Ada, E693, "flyology__object_storage__s3__versions_E");
   E639 : Short_Integer; pragma Import (Ada, E639, "flyology__object_storage__s3__website_E");
   E623 : Short_Integer; pragma Import (Ada, E623, "flyology__object_storage__s3__xml_writers_E");
   E621 : Short_Integer; pragma Import (Ada, E621, "flyology__object_storage__s3__generated_put_bucket_acl_xml_E");
   E627 : Short_Integer; pragma Import (Ada, E627, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E633 : Short_Integer; pragma Import (Ada, E633, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E637 : Short_Integer; pragma Import (Ada, E637, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E673 : Short_Integer; pragma Import (Ada, E673, "flyology__object_storage__s3__metadata_configurations_E");
   E675 : Short_Integer; pragma Import (Ada, E675, "flyology__object_storage__s3__metadata_tables_E");
   E497 : Short_Integer; pragma Import (Ada, E497, "flyology__object_storage__client__low_level_E");
   E695 : Short_Integer; pragma Import (Ada, E695, "flyology__object_storage__client__transfers_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "flyology__object_storage__client__transfers__finalize_body");
      begin
         E695 := E695 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology__object_storage__client__transfers__finalize_spec");
      begin
         F2;
      end;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology__object_storage__client__low_level__finalize_body");
      begin
         E497 := E497 - 1;
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology__object_storage__client__low_level__finalize_spec");
      begin
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology__object_storage__s3__metadata_tables__finalize_body");
      begin
         E675 := E675 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E673 := E673 - 1;
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__s3__website__finalize_body");
      begin
         E639 := E639 - 1;
         F7;
      end;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology__object_storage__s3__website__finalize_spec");
      begin
         F8;
      end;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology__object_storage__s3__versions__finalize_body");
      begin
         E693 := E693 - 1;
         F9;
      end;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology__object_storage__s3__versions__finalize_spec");
      begin
         F10;
      end;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology__object_storage__s3__versioning__finalize_body");
      begin
         E691 := E691 - 1;
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__tagging__finalize_body");
      begin
         E647 := E647 - 1;
         F12;
      end;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology__object_storage__s3__generated_list_directory_buckets_xml__finalize_body");
      begin
         E535 := E535 - 1;
         F13;
      end;
      declare
         procedure F14;
         pragma Import (Ada, F14, "flyology__object_storage__s3__replication__finalize_body");
      begin
         E687 := E687 - 1;
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
         E677 := E677 - 1;
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
         E629 := E629 - 1;
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
         E665 := E665 - 1;
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
         E653 := E653 - 1;
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
         E651 := E651 - 1;
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
         E685 := E685 - 1;
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E683 := E683 - 1;
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
         E681 := E681 - 1;
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
         E679 := E679 - 1;
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
         E635 := E635 - 1;
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
         E669 := E669 - 1;
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
         E667 := E667 - 1;
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
         E663 := E663 - 1;
         F39;
      end;
      declare
         procedure F40;
         pragma Import (Ada, F40, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E661 := E661 - 1;
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
         E655 := E655 - 1;
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
         E645 := E645 - 1;
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
         pragma Import (Ada, F46, "flyology__object_storage__s3__copies__finalize_body");
      begin
         E659 := E659 - 1;
         F46;
      end;
      declare
         procedure F47;
         pragma Import (Ada, F47, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E617 := E617 - 1;
         F47;
      end;
      declare
         procedure F48;
         pragma Import (Ada, F48, "flyology__object_storage__s3__buckets__finalize_spec");
      begin
         F48;
      end;
      declare
         procedure F49;
         pragma Import (Ada, F49, "flyology__object_storage__s3__bucket_controls__finalize_body");
      begin
         E657 := E657 - 1;
         F49;
      end;
      declare
         procedure F50;
         pragma Import (Ada, F50, "flyology__object_storage__s3__bucket_controls__finalize_spec");
      begin
         F50;
      end;
      declare
         procedure F51;
         pragma Import (Ada, F51, "flyology__object_storage__s3__acl__finalize_body");
      begin
         E625 := E625 - 1;
         F51;
      end;
      declare
         procedure F52;
         pragma Import (Ada, F52, "flyology__object_storage__s3__acl__finalize_spec");
      begin
         F52;
      end;
      declare
         procedure F53;
         pragma Import (Ada, F53, "flyology__object_storage__s3__xml__finalize_body");
      begin
         E539 := E539 - 1;
         F53;
      end;
      E589 := E589 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "sax__readers__finalize_spec");
      begin
         F54;
      end;
      E586 := E586 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "input_sources__strings__finalize_spec");
      begin
         F55;
      end;
      E595 := E595 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "input_sources__file__finalize_spec");
      begin
         F56;
      end;
      E541 := E541 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "input_sources__finalize_spec");
      begin
         F57;
      end;
      E615 := E615 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__utils__finalize_spec");
      begin
         F58;
      end;
      E597 := E597 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__attributes__finalize_spec");
      begin
         F59;
      end;
      E611 := E611 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "sax__exceptions__finalize_spec");
      begin
         F60;
      end;
      E602 := E602 - 1;
      declare
         procedure F61;
         pragma Import (Ada, F61, "sax__symbols__finalize_spec");
      begin
         F61;
      end;
      E609 := E609 - 1;
      declare
         procedure F62;
         pragma Import (Ada, F62, "sax__pointers__finalize_spec");
      begin
         F62;
      end;
      E699 := E699 - 1;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__client__request_bodies__files__finalize_spec");
      begin
         F63;
      end;
      E697 := E697 - 1;
      declare
         procedure F64;
         pragma Import (Ada, F64, "flyology__http__client__request_bodies__finalize_spec");
      begin
         F64;
      end;
      declare
         procedure F65;
         pragma Import (Ada, F65, "flyology__http__client__finalize_body");
      begin
         E177 := E177 - 1;
         F65;
      end;
      declare
         procedure F66;
         pragma Import (Ada, F66, "flyology__http__client__finalize_spec");
      begin
         F66;
      end;
      E456 := E456 - 1;
      declare
         procedure F67;
         pragma Import (Ada, F67, "flyology__io__connections__tls__finalize_spec");
      begin
         F67;
      end;
      E458 := E458 - 1;
      declare
         procedure F68;
         pragma Import (Ada, F68, "flyology__io__tls__alpn__finalize_spec");
      begin
         F68;
      end;
      declare
         procedure F69;
         pragma Import (Ada, F69, "flyology__http__http_2_client_connection__finalize_body");
      begin
         E265 := E265 - 1;
         F69;
      end;
      E330 := E330 - 1;
      declare
         procedure F70;
         pragma Import (Ada, F70, "flyology__io__connections__drivers__finalize_spec");
      begin
         F70;
      end;
      declare
         procedure F71;
         pragma Import (Ada, F71, "flyology__io__connections__finalize_body");
      begin
         E309 := E309 - 1;
         F71;
      end;
      declare
         procedure F72;
         pragma Import (Ada, F72, "flyology__io__connections__finalize_spec");
      begin
         F72;
      end;
      declare
         procedure F73;
         pragma Import (Ada, F73, "flyology__io__tls__finalize_body");
      begin
         E318 := E318 - 1;
         F73;
      end;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__io__tls__finalize_spec");
      begin
         F74;
      end;
      E334 := E334 - 1;
      declare
         procedure F75;
         pragma Import (Ada, F75, "flyology__http__http_3__finalize_spec");
      begin
         F75;
      end;
      declare
         procedure F76;
         pragma Import (Ada, F76, "flyology__quic__connections__finalize_body");
      begin
         E363 := E363 - 1;
         F76;
      end;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__quic__connections__finalize_spec");
      begin
         F77;
      end;
      E386 := E386 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__quic__crypto_openssl__finalize_spec");
      begin
         F78;
      end;
      E649 := E649 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__object_storage__tags__finalize_spec");
      begin
         F79;
      end;
      E504 := E504 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F80;
      end;
      E462 := E462 - 1;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__io__dns__finalize_spec");
      begin
         F81;
      end;
      E321 := E321 - 1;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__io__sockets__finalize_spec");
      begin
         F82;
      end;
      E467 := E467 - 1;
      declare
         procedure F83;
         pragma Import (Ada, F83, "flyology__io__files__finalize_spec");
      begin
         F83;
      end;
      E275 := E275 - 1;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__bytes__finalize_spec");
      begin
         F84;
      end;
      E256 := E256 - 1;
      declare
         procedure F85;
         pragma Import (Ada, F85, "flyology__buffers__drivers__finalize_spec");
      begin
         F85;
      end;
      declare
         procedure F86;
         pragma Import (Ada, F86, "flyology__buffers__finalize_body");
      begin
         E179 := E179 - 1;
         F86;
      end;
      declare
         procedure F87;
         pragma Import (Ada, F87, "flyology__buffers__finalize_spec");
      begin
         F87;
      end;
      E295 := E295 - 1;
      E293 := E293 - 1;
      declare
         procedure F88;
         pragma Import (Ada, F88, "flyology__io__finalize_spec");
      begin
         F88;
      end;
      declare
         procedure F89;
         pragma Import (Ada, F89, "flyology__operations__finalize_spec");
      begin
         F89;
      end;
      E289 := E289 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "flyology__wake_sources__finalize_spec");
      begin
         F90;
      end;
      E238 := E238 - 1;
      declare
         procedure F91;
         pragma Import (Ada, F91, "system__tasking__protected_objects__entries__finalize_spec");
      begin
         F91;
      end;
      declare
         procedure F92;
         pragma Import (Ada, F92, "ada__directories__finalize_body");
      begin
         E099 := E099 - 1;
         F92;
      end;
      declare
         procedure F93;
         pragma Import (Ada, F93, "ada__directories__finalize_spec");
      begin
         F93;
      end;
      E160 := E160 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "system__regexp__finalize_spec");
      begin
         F94;
      end;
      E258 := E258 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "system__pool_global__finalize_spec");
      begin
         F95;
      end;
      E141 := E141 - 1;
      declare
         procedure F96;
         pragma Import (Ada, F96, "ada__strings__unbounded__finalize_spec");
      begin
         F96;
      end;
      E531 := E531 - 1;
      declare
         procedure F97;
         pragma Import (Ada, F97, "gnat__sha512__finalize_spec");
      begin
         F97;
      end;
      E525 := E525 - 1;
      declare
         procedure F98;
         pragma Import (Ada, F98, "gnat__sha256__finalize_spec");
      begin
         F98;
      end;
      E521 := E521 - 1;
      declare
         procedure F99;
         pragma Import (Ada, F99, "gnat__sha1__finalize_spec");
      begin
         F99;
      end;
      E512 := E512 - 1;
      declare
         procedure F100;
         pragma Import (Ada, F100, "gnat__md5__finalize_spec");
      begin
         F100;
      end;
      E591 := E591 - 1;
      declare
         procedure F101;
         pragma Import (Ada, F101, "ada__text_io__finalize_spec");
      begin
         F101;
      end;
      E277 := E277 - 1;
      declare
         procedure F102;
         pragma Import (Ada, F102, "system__storage_pools__subpools__finalize_spec");
      begin
         F102;
      end;
      E168 := E168 - 1;
      declare
         procedure F103;
         pragma Import (Ada, F103, "ada__streams__stream_io__finalize_spec");
      begin
         F103;
      end;
      declare
         procedure F104;
         pragma Import (Ada, F104, "system__file_io__finalize_body");
      begin
         E155 := E155 - 1;
         F104;
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
           True, False, True, False, True, False, False, False, 
           False, True, False, True, True, True, False, False, 
           True, False, True, True, True, False, True, True, 
           False, True, True, True, True, False, False, False, 
           True, False, False, False, False, True, True, True, 
           True, True, True, False),
         Count => (0, 0, 0, 3, 2, 2, 3, 3, 14, 0),
         Unknown => (False, False, False, False, False, False, True, True, True, False));
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
      E191 := E191 + 1;
      Ada.Containers'Elab_Spec;
      E100 := E100 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E106 := E106 + 1;
      Ada.Strings'Elab_Spec;
      E090 := E090 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E110 := E110 + 1;
      Gnat'Elab_Spec;
      E290 := E290 + 1;
      Interfaces.C'Elab_Spec;
      E053 := E053 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E166 := E166 + 1;
      System.Os_Lib'Elab_Body;
      E055 := E055 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E118 := E118 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E108 := E108 + 1;
      Ada.Streams'Elab_Spec;
      E105 := E105 + 1;
      System.File_Control_Block'Elab_Spec;
      E158 := E158 + 1;
      System.Finalization_Root'Elab_Spec;
      E129 := E129 + 1;
      Ada.Finalization'Elab_Spec;
      E103 := E103 + 1;
      System.File_Io'Elab_Body;
      E155 := E155 + 1;
      Ada.Streams.Stream_Io'Elab_Spec;
      E168 := E168 + 1;
      System.Storage_Pools'Elab_Spec;
      E162 := E162 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E277 := E277 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E006 := E006 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E297 := E297 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E077 := E077 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E591 := E591 + 1;
      E514 := E514 + 1;
      E516 := E516 + 1;
      Gnat.Md5'Elab_Spec;
      E512 := E512 + 1;
      E523 := E523 + 1;
      E529 := E529 + 1;
      E527 := E527 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E533 := E533 + 1;
      Gnat.Sha1'Elab_Spec;
      E521 := E521 + 1;
      Gnat.Sha256'Elab_Spec;
      E525 := E525 + 1;
      Gnat.Sha512'Elab_Spec;
      E531 := E531 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E196 := E196 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E267 := E267 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E092 := E092 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E095 := E095 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E141 := E141 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E593 := E593 + 1;
      System.Interrupt_Management.Operations'Elab_Body;
      E478 := E478 + 1;
      System.Pool_Global'Elab_Spec;
      E258 := E258 + 1;
      System.Regexp'Elab_Spec;
      E160 := E160 + 1;
      Ada.Directories'Elab_Spec;
      Ada.Directories'Elab_Body;
      E099 := E099 + 1;
      System.Tasking.Initialization'Elab_Body;
      E242 := E242 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E232 := E232 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E238 := E238 + 1;
      System.Tasking.Queuing'Elab_Body;
      E250 := E250 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E484 := E484 + 1;
      System.Tasking.Stages'Elab_Body;
      E480 := E480 + 1;
      System.Tasking.Async_Delays'Elab_Body;
      E474 := E474 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E289 := E289 + 1;
      Flyology.Cancellation'Elab_Spec;
      E299 := E299 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E293 := E293 + 1;
      E295 := E295 + 1;
      Unicode'Elab_Body;
      E543 := E543 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E179 := E179 + 1;
      Flyology.Buffers.Drivers'Elab_Spec;
      Flyology.Buffers.Drivers'Elab_Body;
      E256 := E256 + 1;
      Flyology.Bytes'Elab_Spec;
      E275 := E275 + 1;
      E326 := E326 + 1;
      E469 := E469 + 1;
      Flyology.Http'Elab_Spec;
      E175 := E175 + 1;
      E263 := E263 + 1;
      E353 := E353 + 1;
      Flyology.Http.Headers'Elab_Spec;
      E281 := E281 + 1;
      E269 := E269 + 1;
      Flyology.Http.Http_2_Huffman'Elab_Body;
      E273 := E273 + 1;
      Flyology.Http.Http_2_Hpack'Elab_Spec;
      E271 := E271 + 1;
      E283 := E283 + 1;
      E285 := E285 + 1;
      E332 := E332 + 1;
      E287 := E287 + 1;
      E340 := E340 + 1;
      E359 := E359 + 1;
      E345 := E345 + 1;
      E347 := E347 + 1;
      E338 := E338 + 1;
      E355 := E355 + 1;
      E357 := E357 + 1;
      E351 := E351 + 1;
      E349 := E349 + 1;
      E361 := E361 + 1;
      Flyology.Io.Files'Elab_Spec;
      Flyology.Io.Files'Elab_Body;
      E467 := E467 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E321 := E321 + 1;
      Flyology.Io.Dns'Elab_Spec;
      Flyology.Io.Dns'Elab_Body;
      E462 := E462 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E489 := E489 + 1;
      E502 := E502 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E510 := E510 + 1;
      E500 := E500 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E641 := E641 + 1;
      E671 := E671 + 1;
      E701 := E701 + 1;
      E619 := E619 + 1;
      E506 := E506 + 1;
      E508 := E508 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E504 := E504 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E689 := E689 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E649 := E649 + 1;
      E434 := E434 + 1;
      Flyology.Quic.Crypto_Openssl'Elab_Spec;
      Flyology.Quic.Crypto_Openssl'Elab_Body;
      E386 := E386 + 1;
      E381 := E381 + 1;
      E438 := E438 + 1;
      E440 := E440 + 1;
      E424 := E424 + 1;
      E428 := E428 + 1;
      E422 := E422 + 1;
      E442 := E442 + 1;
      E390 := E390 + 1;
      E396 := E396 + 1;
      E398 := E398 + 1;
      E384 := E384 + 1;
      E365 := E365 + 1;
      E436 := E436 + 1;
      E430 := E430 + 1;
      E444 := E444 + 1;
      E416 := E416 + 1;
      Flyology.Quic.Connections'Elab_Spec;
      Flyology.Quic.Connections'Elab_Body;
      E363 := E363 + 1;
      E336 := E336 + 1;
      Flyology.Http.Http_3'Elab_Spec;
      Flyology.Http.Http_3'Elab_Body;
      E334 := E334 + 1;
      E454 := E454 + 1;
      E705 := E705 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E314 := E314 + 1;
      Flyology.Io.Tls'Elab_Body;
      E318 := E318 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E309 := E309 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E330 := E330 + 1;
      Flyology.Http.Http_2_Client_Connection'Elab_Spec;
      Flyology.Http.Http_2_Client_Connection'Elab_Body;
      E265 := E265 + 1;
      Flyology.Io.Tls.Alpn'Elab_Spec;
      E458 := E458 + 1;
      Flyology.Io.Connections.Tls'Elab_Spec;
      Flyology.Io.Connections.Tls'Elab_Body;
      E456 := E456 + 1;
      Flyology.Http.Client'Elab_Spec;
      Flyology.Http.Client'Elab_Body;
      E177 := E177 + 1;
      Flyology.Http.Client.Request_Bodies'Elab_Spec;
      Flyology.Http.Client.Request_Bodies'Elab_Body;
      E697 := E697 + 1;
      Flyology.Http.Client.Request_Bodies.Files'Elab_Spec;
      Flyology.Http.Client.Request_Bodies.Files'Elab_Body;
      E699 := E699 + 1;
      E707 := E707 + 1;
      E607 := E607 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E609 := E609 + 1;
      Unicode.Ccs'Elab_Spec;
      E554 := E554 + 1;
      E556 := E556 + 1;
      E558 := E558 + 1;
      E563 := E563 + 1;
      E566 := E566 + 1;
      E568 := E568 + 1;
      E570 := E570 + 1;
      E575 := E575 + 1;
      Unicode.Ces'Elab_Spec;
      E550 := E550 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E602 := E602 + 1;
      E613 := E613 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E611 := E611 + 1;
      E580 := E580 + 1;
      E578 := E578 + 1;
      E582 := E582 + 1;
      E584 := E584 + 1;
      Sax.Models'Elab_Spec;
      E599 := E599 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E597 := E597 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E615 := E615 + 1;
      E552 := E552 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E541 := E541 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E595 := E595 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E586 := E586 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E589 := E589 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E539 := E539 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E625 := E625 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E657 := E657 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E617 := E617 + 1;
      Flyology.Object_Storage.S3.Copies'Elab_Spec;
      Flyology.Object_Storage.S3.Copies'Elab_Body;
      E659 := E659 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E645 := E645 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E655 := E655 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E661 := E661 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E663 := E663 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E667 := E667 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E669 := E669 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E635 := E635 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E679 := E679 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E681 := E681 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E683 := E683 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E685 := E685 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E643 := E643 + 1;
      E631 := E631 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E651 := E651 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E653 := E653 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E665 := E665 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E629 := E629 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E677 := E677 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E687 := E687 + 1;
      E537 := E537 + 1;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Body;
      E535 := E535 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E647 := E647 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E691 := E691 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E693 := E693 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E639 := E639 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E623 := E623 + 1;
      E621 := E621 + 1;
      E627 := E627 + 1;
      E633 := E633 + 1;
      E637 := E637 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E673 := E673 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E675 := E675 + 1;
      Flyology.Object_Storage.Client.Low_Level'Elab_Spec;
      Flyology.Object_Storage.Client.Low_Level'Elab_Body;
      E497 := E497 + 1;
      Flyology.Object_Storage.Client.Transfers'Elab_Spec;
      Flyology.Object_Storage.Client.Transfers'Elab_Body;
      E695 := E695 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_transfers_minio_probe");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_transfers_minio_probe.o
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
