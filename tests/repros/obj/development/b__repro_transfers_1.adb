pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__repro_transfers_1.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__repro_transfers_1.adb");
pragma Suppress (Overflow_Check);

with System.Restrictions;
with Ada.Exceptions;

package body ada_main is

   E018 : Short_Integer; pragma Import (Ada, E018, "ada__exceptions_E");
   E014 : Short_Integer; pragma Import (Ada, E014, "system__soft_links_E");
   E012 : Short_Integer; pragma Import (Ada, E012, "system__exception_table_E");
   E021 : Short_Integer; pragma Import (Ada, E021, "system__exceptions_E");
   E052 : Short_Integer; pragma Import (Ada, E052, "system__soft_links__initialize_E");
   E173 : Short_Integer; pragma Import (Ada, E173, "ada__assertions_E");
   E098 : Short_Integer; pragma Import (Ada, E098, "ada__containers_E");
   E104 : Short_Integer; pragma Import (Ada, E104, "ada__io_exceptions_E");
   E009 : Short_Integer; pragma Import (Ada, E009, "ada__strings_E");
   E108 : Short_Integer; pragma Import (Ada, E108, "ada__strings__utf_encoding_E");
   E284 : Short_Integer; pragma Import (Ada, E284, "gnat_E");
   E066 : Short_Integer; pragma Import (Ada, E066, "interfaces__c_E");
   E382 : Short_Integer; pragma Import (Ada, E382, "interfaces__c__strings_E");
   E068 : Short_Integer; pragma Import (Ada, E068, "system__os_lib_E");
   E116 : Short_Integer; pragma Import (Ada, E116, "ada__tags_E");
   E106 : Short_Integer; pragma Import (Ada, E106, "ada__strings__text_buffers_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "ada__streams_E");
   E156 : Short_Integer; pragma Import (Ada, E156, "system__file_control_block_E");
   E127 : Short_Integer; pragma Import (Ada, E127, "system__finalization_root_E");
   E101 : Short_Integer; pragma Import (Ada, E101, "ada__finalization_E");
   E153 : Short_Integer; pragma Import (Ada, E153, "system__file_io_E");
   E216 : Short_Integer; pragma Import (Ada, E216, "ada__streams__stream_io_E");
   E160 : Short_Integer; pragma Import (Ada, E160, "system__storage_pools_E");
   E271 : Short_Integer; pragma Import (Ada, E271, "system__storage_pools__subpools_E");
   E064 : Short_Integer; pragma Import (Ada, E064, "ada__calendar_E");
   E291 : Short_Integer; pragma Import (Ada, E291, "ada__calendar__delays_E");
   E090 : Short_Integer; pragma Import (Ada, E090, "ada__calendar__time_zones_E");
   E587 : Short_Integer; pragma Import (Ada, E587, "ada__text_io_E");
   E510 : Short_Integer; pragma Import (Ada, E510, "gnat__secure_hashes_E");
   E512 : Short_Integer; pragma Import (Ada, E512, "gnat__secure_hashes__md5_E");
   E508 : Short_Integer; pragma Import (Ada, E508, "gnat__md5_E");
   E519 : Short_Integer; pragma Import (Ada, E519, "gnat__secure_hashes__sha1_E");
   E525 : Short_Integer; pragma Import (Ada, E525, "gnat__secure_hashes__sha2_common_E");
   E523 : Short_Integer; pragma Import (Ada, E523, "gnat__secure_hashes__sha2_32_E");
   E529 : Short_Integer; pragma Import (Ada, E529, "gnat__secure_hashes__sha2_64_E");
   E517 : Short_Integer; pragma Import (Ada, E517, "gnat__sha1_E");
   E521 : Short_Integer; pragma Import (Ada, E521, "gnat__sha256_E");
   E527 : Short_Integer; pragma Import (Ada, E527, "gnat__sha512_E");
   E180 : Short_Integer; pragma Import (Ada, E180, "system__flyology__scheduler_E");
   E162 : Short_Integer; pragma Import (Ada, E162, "ada__real_time_E");
   E056 : Short_Integer; pragma Import (Ada, E056, "ada__strings__maps_E");
   E060 : Short_Integer; pragma Import (Ada, E060, "ada__strings__maps__constants_E");
   E139 : Short_Integer; pragma Import (Ada, E139, "ada__strings__unbounded_E");
   E589 : Short_Integer; pragma Import (Ada, E589, "gnat__directory_operations_E");
   E474 : Short_Integer; pragma Import (Ada, E474, "system__interrupt_management__operations_E");
   E254 : Short_Integer; pragma Import (Ada, E254, "system__pool_global_E");
   E158 : Short_Integer; pragma Import (Ada, E158, "system__regexp_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__directories_E");
   E238 : Short_Integer; pragma Import (Ada, E238, "system__tasking__initialization_E");
   E228 : Short_Integer; pragma Import (Ada, E228, "system__tasking__protected_objects_E");
   E234 : Short_Integer; pragma Import (Ada, E234, "system__tasking__protected_objects__entries_E");
   E246 : Short_Integer; pragma Import (Ada, E246, "system__tasking__queuing_E");
   E480 : Short_Integer; pragma Import (Ada, E480, "system__flyology__task_results_E");
   E476 : Short_Integer; pragma Import (Ada, E476, "system__tasking__stages_E");
   E470 : Short_Integer; pragma Import (Ada, E470, "system__tasking__async_delays_E");
   E283 : Short_Integer; pragma Import (Ada, E283, "flyology__wake_sources_E");
   E293 : Short_Integer; pragma Import (Ada, E293, "flyology__cancellation_E");
   E289 : Short_Integer; pragma Import (Ada, E289, "flyology__operations_E");
   E287 : Short_Integer; pragma Import (Ada, E287, "flyology__io_E");
   E539 : Short_Integer; pragma Import (Ada, E539, "unicode_E");
   E225 : Short_Integer; pragma Import (Ada, E225, "flyology__buffers_E");
   E252 : Short_Integer; pragma Import (Ada, E252, "flyology__buffers__drivers_E");
   E269 : Short_Integer; pragma Import (Ada, E269, "flyology__bytes_E");
   E320 : Short_Integer; pragma Import (Ada, E320, "flyology__capacity_E");
   E465 : Short_Integer; pragma Import (Ada, E465, "flyology__file_open_policy_E");
   E221 : Short_Integer; pragma Import (Ada, E221, "flyology__http_E");
   E259 : Short_Integer; pragma Import (Ada, E259, "flyology__http__client_policy_E");
   E347 : Short_Integer; pragma Import (Ada, E347, "flyology__http__header_huffman_policy_E");
   E275 : Short_Integer; pragma Import (Ada, E275, "flyology__http__headers_E");
   E263 : Short_Integer; pragma Import (Ada, E263, "flyology__http__http_2_frames_E");
   E267 : Short_Integer; pragma Import (Ada, E267, "flyology__http__http_2_huffman_E");
   E265 : Short_Integer; pragma Import (Ada, E265, "flyology__http__http_2_hpack_E");
   E277 : Short_Integer; pragma Import (Ada, E277, "flyology__http__http_2_payloads_E");
   E279 : Short_Integer; pragma Import (Ada, E279, "flyology__http__http_2_policy_E");
   E326 : Short_Integer; pragma Import (Ada, E326, "flyology__http__http_2_requests_E");
   E281 : Short_Integer; pragma Import (Ada, E281, "flyology__http__http_2_settings_E");
   E334 : Short_Integer; pragma Import (Ada, E334, "flyology__http__http_3_frame_policy_E");
   E353 : Short_Integer; pragma Import (Ada, E353, "flyology__http__http_3_message_policy_E");
   E339 : Short_Integer; pragma Import (Ada, E339, "flyology__http__http_3_settings_policy_E");
   E341 : Short_Integer; pragma Import (Ada, E341, "flyology__http__http_3_stream_policy_E");
   E332 : Short_Integer; pragma Import (Ada, E332, "flyology__http__http_3_control_policy_E");
   E349 : Short_Integer; pragma Import (Ada, E349, "flyology__http__qpack_integer_policy_E");
   E351 : Short_Integer; pragma Import (Ada, E351, "flyology__http__qpack_static_table_E");
   E345 : Short_Integer; pragma Import (Ada, E345, "flyology__http__qpack_field_section_policy_E");
   E343 : Short_Integer; pragma Import (Ada, E343, "flyology__http__http_3_header_policy_E");
   E355 : Short_Integer; pragma Import (Ada, E355, "flyology__http__http_3_stream_receive_policy_E");
   E463 : Short_Integer; pragma Import (Ada, E463, "flyology__io__files_E");
   E315 : Short_Integer; pragma Import (Ada, E315, "flyology__io__sockets_E");
   E458 : Short_Integer; pragma Import (Ada, E458, "flyology__io__dns_E");
   E485 : Short_Integer; pragma Import (Ada, E485, "flyology__object_storage_E");
   E498 : Short_Integer; pragma Import (Ada, E498, "flyology__object_storage__s3__core_E");
   E506 : Short_Integer; pragma Import (Ada, E506, "flyology__object_storage__s3__checksum_crc_E");
   E496 : Short_Integer; pragma Import (Ada, E496, "flyology__object_storage__s3__checksum_policy_E");
   E637 : Short_Integer; pragma Import (Ada, E637, "flyology__object_storage__s3__imf_dates_E");
   E667 : Short_Integer; pragma Import (Ada, E667, "flyology__object_storage__s3__model_E");
   E697 : Short_Integer; pragma Import (Ada, E697, "flyology__object_storage__s3__requests_E");
   E615 : Short_Integer; pragma Import (Ada, E615, "flyology__object_storage__s3__sigv4_encoding_E");
   E502 : Short_Integer; pragma Import (Ada, E502, "flyology__object_storage__s3__wire_core_E");
   E504 : Short_Integer; pragma Import (Ada, E504, "flyology__object_storage__secrets_E");
   E500 : Short_Integer; pragma Import (Ada, E500, "flyology__object_storage__s3__checksums_E");
   E685 : Short_Integer; pragma Import (Ada, E685, "flyology__object_storage__s3__sigv4_E");
   E645 : Short_Integer; pragma Import (Ada, E645, "flyology__object_storage__tags_E");
   E430 : Short_Integer; pragma Import (Ada, E430, "flyology__quic__crypto_flight_E");
   E380 : Short_Integer; pragma Import (Ada, E380, "flyology__quic__crypto_openssl_E");
   E375 : Short_Integer; pragma Import (Ada, E375, "flyology__quic__debug_E");
   E434 : Short_Integer; pragma Import (Ada, E434, "flyology__quic__handshake_receiver_E");
   E436 : Short_Integer; pragma Import (Ada, E436, "flyology__quic__handshake_sender_E");
   E420 : Short_Integer; pragma Import (Ada, E420, "flyology__quic__initial_receiver_E");
   E424 : Short_Integer; pragma Import (Ada, E424, "flyology__quic__initial_sender_E");
   E418 : Short_Integer; pragma Import (Ada, E418, "flyology__quic__initial_connection_E");
   E438 : Short_Integer; pragma Import (Ada, E438, "flyology__quic__initial_space_E");
   E386 : Short_Integer; pragma Import (Ada, E386, "flyology__quic__one_rtt_receiver_E");
   E392 : Short_Integer; pragma Import (Ada, E392, "flyology__quic__one_rtt_sender_E");
   E394 : Short_Integer; pragma Import (Ada, E394, "flyology__quic__tls_key_schedule_E");
   E378 : Short_Integer; pragma Import (Ada, E378, "flyology__quic__application_connection_E");
   E359 : Short_Integer; pragma Import (Ada, E359, "flyology__quic__application_space_E");
   E432 : Short_Integer; pragma Import (Ada, E432, "flyology__quic__handshake_connection_E");
   E426 : Short_Integer; pragma Import (Ada, E426, "flyology__quic__handshake_space_E");
   E440 : Short_Integer; pragma Import (Ada, E440, "flyology__quic__tls_session_E");
   E412 : Short_Integer; pragma Import (Ada, E412, "flyology__quic__connection_driver_E");
   E357 : Short_Integer; pragma Import (Ada, E357, "flyology__quic__connections_E");
   E330 : Short_Integer; pragma Import (Ada, E330, "flyology__http__http_3_connection_E");
   E328 : Short_Integer; pragma Import (Ada, E328, "flyology__http__http_3_E");
   E450 : Short_Integer; pragma Import (Ada, E450, "flyology__http__http_3_client_connection_E");
   E701 : Short_Integer; pragma Import (Ada, E701, "flyology__task_scopes_E");
   E312 : Short_Integer; pragma Import (Ada, E312, "flyology__io__tls_E");
   E308 : Short_Integer; pragma Import (Ada, E308, "flyology__io__tls_driver_E");
   E303 : Short_Integer; pragma Import (Ada, E303, "flyology__io__connections_E");
   E324 : Short_Integer; pragma Import (Ada, E324, "flyology__io__connections__drivers_E");
   E261 : Short_Integer; pragma Import (Ada, E261, "flyology__http__http_2_client_connection_E");
   E454 : Short_Integer; pragma Import (Ada, E454, "flyology__io__tls__alpn_E");
   E452 : Short_Integer; pragma Import (Ada, E452, "flyology__io__connections__tls_E");
   E223 : Short_Integer; pragma Import (Ada, E223, "flyology__http__client_E");
   E693 : Short_Integer; pragma Import (Ada, E693, "flyology__http__client__request_bodies_E");
   E695 : Short_Integer; pragma Import (Ada, E695, "flyology__http__client__request_bodies__files_E");
   E703 : Short_Integer; pragma Import (Ada, E703, "repro_support_E");
   E603 : Short_Integer; pragma Import (Ada, E603, "sax__htable_E");
   E605 : Short_Integer; pragma Import (Ada, E605, "sax__pointers_E");
   E550 : Short_Integer; pragma Import (Ada, E550, "unicode__ccs_E");
   E552 : Short_Integer; pragma Import (Ada, E552, "unicode__ccs__iso_8859_1_E");
   E554 : Short_Integer; pragma Import (Ada, E554, "unicode__ccs__iso_8859_15_E");
   E559 : Short_Integer; pragma Import (Ada, E559, "unicode__ccs__iso_8859_2_E");
   E562 : Short_Integer; pragma Import (Ada, E562, "unicode__ccs__iso_8859_3_E");
   E564 : Short_Integer; pragma Import (Ada, E564, "unicode__ccs__iso_8859_4_E");
   E566 : Short_Integer; pragma Import (Ada, E566, "unicode__ccs__windows_1251_E");
   E571 : Short_Integer; pragma Import (Ada, E571, "unicode__ccs__windows_1252_E");
   E546 : Short_Integer; pragma Import (Ada, E546, "unicode__ces_E");
   E598 : Short_Integer; pragma Import (Ada, E598, "sax__symbols_E");
   E609 : Short_Integer; pragma Import (Ada, E609, "sax__locators_E");
   E607 : Short_Integer; pragma Import (Ada, E607, "sax__exceptions_E");
   E576 : Short_Integer; pragma Import (Ada, E576, "unicode__ces__utf32_E");
   E574 : Short_Integer; pragma Import (Ada, E574, "unicode__ces__basic_8bit_E");
   E578 : Short_Integer; pragma Import (Ada, E578, "unicode__ces__utf16_E");
   E580 : Short_Integer; pragma Import (Ada, E580, "unicode__ces__utf8_E");
   E595 : Short_Integer; pragma Import (Ada, E595, "sax__models_E");
   E593 : Short_Integer; pragma Import (Ada, E593, "sax__attributes_E");
   E611 : Short_Integer; pragma Import (Ada, E611, "sax__utils_E");
   E548 : Short_Integer; pragma Import (Ada, E548, "unicode__encodings_E");
   E537 : Short_Integer; pragma Import (Ada, E537, "input_sources_E");
   E591 : Short_Integer; pragma Import (Ada, E591, "input_sources__file_E");
   E582 : Short_Integer; pragma Import (Ada, E582, "input_sources__strings_E");
   E585 : Short_Integer; pragma Import (Ada, E585, "sax__readers_E");
   E535 : Short_Integer; pragma Import (Ada, E535, "flyology__object_storage__s3__xml_E");
   E621 : Short_Integer; pragma Import (Ada, E621, "flyology__object_storage__s3__acl_E");
   E653 : Short_Integer; pragma Import (Ada, E653, "flyology__object_storage__s3__bucket_controls_E");
   E613 : Short_Integer; pragma Import (Ada, E613, "flyology__object_storage__s3__buckets_E");
   E655 : Short_Integer; pragma Import (Ada, E655, "flyology__object_storage__s3__copies_E");
   E641 : Short_Integer; pragma Import (Ada, E641, "flyology__object_storage__s3__deletions_E");
   E651 : Short_Integer; pragma Import (Ada, E651, "flyology__object_storage__s3__attributes_E");
   E657 : Short_Integer; pragma Import (Ada, E657, "flyology__object_storage__s3__encryption_E");
   E659 : Short_Integer; pragma Import (Ada, E659, "flyology__object_storage__s3__errors_E");
   E663 : Short_Integer; pragma Import (Ada, E663, "flyology__object_storage__s3__lifecycle_E");
   E665 : Short_Integer; pragma Import (Ada, E665, "flyology__object_storage__s3__listings_E");
   E631 : Short_Integer; pragma Import (Ada, E631, "flyology__object_storage__s3__logging_E");
   E675 : Short_Integer; pragma Import (Ada, E675, "flyology__object_storage__s3__multipart_E");
   E677 : Short_Integer; pragma Import (Ada, E677, "flyology__object_storage__s3__multipart_uploads_E");
   E679 : Short_Integer; pragma Import (Ada, E679, "flyology__object_storage__s3__notifications_E");
   E681 : Short_Integer; pragma Import (Ada, E681, "flyology__object_storage__s3__object_lock_E");
   E639 : Short_Integer; pragma Import (Ada, E639, "flyology__object_storage__s3__object_reads_E");
   E627 : Short_Integer; pragma Import (Ada, E627, "flyology__object_storage__s3__paginated_rest_xml_reads_E");
   E647 : Short_Integer; pragma Import (Ada, E647, "flyology__object_storage__s3__analytics_E");
   E649 : Short_Integer; pragma Import (Ada, E649, "flyology__object_storage__s3__annotations_E");
   E661 : Short_Integer; pragma Import (Ada, E661, "flyology__object_storage__s3__intelligent_tiering_E");
   E625 : Short_Integer; pragma Import (Ada, E625, "flyology__object_storage__s3__inventory_E");
   E673 : Short_Integer; pragma Import (Ada, E673, "flyology__object_storage__s3__metrics_E");
   E683 : Short_Integer; pragma Import (Ada, E683, "flyology__object_storage__s3__replication_E");
   E533 : Short_Integer; pragma Import (Ada, E533, "flyology__object_storage__s3__strict_xml_codecs_E");
   E531 : Short_Integer; pragma Import (Ada, E531, "flyology__object_storage__s3__generated_list_directory_buckets_xml_E");
   E643 : Short_Integer; pragma Import (Ada, E643, "flyology__object_storage__s3__tagging_E");
   E687 : Short_Integer; pragma Import (Ada, E687, "flyology__object_storage__s3__versioning_E");
   E689 : Short_Integer; pragma Import (Ada, E689, "flyology__object_storage__s3__versions_E");
   E635 : Short_Integer; pragma Import (Ada, E635, "flyology__object_storage__s3__website_E");
   E619 : Short_Integer; pragma Import (Ada, E619, "flyology__object_storage__s3__xml_writers_E");
   E617 : Short_Integer; pragma Import (Ada, E617, "flyology__object_storage__s3__generated_put_bucket_acl_xml_E");
   E623 : Short_Integer; pragma Import (Ada, E623, "flyology__object_storage__s3__generated_put_bucket_inventory_configuration_xml_E");
   E629 : Short_Integer; pragma Import (Ada, E629, "flyology__object_storage__s3__generated_put_bucket_logging_xml_E");
   E633 : Short_Integer; pragma Import (Ada, E633, "flyology__object_storage__s3__generated_put_bucket_website_xml_E");
   E669 : Short_Integer; pragma Import (Ada, E669, "flyology__object_storage__s3__metadata_configurations_E");
   E671 : Short_Integer; pragma Import (Ada, E671, "flyology__object_storage__s3__metadata_tables_E");
   E493 : Short_Integer; pragma Import (Ada, E493, "flyology__object_storage__client__low_level_E");
   E691 : Short_Integer; pragma Import (Ada, E691, "flyology__object_storage__client__transfers_E");

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
         E691 := E691 - 1;
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
         E493 := E493 - 1;
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
         E671 := E671 - 1;
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology__object_storage__s3__metadata_configurations__finalize_body");
      begin
         E669 := E669 - 1;
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology__object_storage__s3__website__finalize_body");
      begin
         E635 := E635 - 1;
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
         E689 := E689 - 1;
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
         E687 := E687 - 1;
         F11;
      end;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology__object_storage__s3__tagging__finalize_body");
      begin
         E643 := E643 - 1;
         F12;
      end;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology__object_storage__s3__generated_list_directory_buckets_xml__finalize_body");
      begin
         E531 := E531 - 1;
         F13;
      end;
      declare
         procedure F14;
         pragma Import (Ada, F14, "flyology__object_storage__s3__replication__finalize_body");
      begin
         E683 := E683 - 1;
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
         E673 := E673 - 1;
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
         E625 := E625 - 1;
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
         E661 := E661 - 1;
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
         E649 := E649 - 1;
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
         E647 := E647 - 1;
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
         E681 := E681 - 1;
         F26;
      end;
      declare
         procedure F27;
         pragma Import (Ada, F27, "flyology__object_storage__s3__notifications__finalize_body");
      begin
         E679 := E679 - 1;
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
         E677 := E677 - 1;
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
         E675 := E675 - 1;
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
         E631 := E631 - 1;
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
         E665 := E665 - 1;
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
         E663 := E663 - 1;
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
         E659 := E659 - 1;
         F39;
      end;
      declare
         procedure F40;
         pragma Import (Ada, F40, "flyology__object_storage__s3__encryption__finalize_body");
      begin
         E657 := E657 - 1;
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
         E651 := E651 - 1;
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
         E641 := E641 - 1;
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
         E655 := E655 - 1;
         F46;
      end;
      declare
         procedure F47;
         pragma Import (Ada, F47, "flyology__object_storage__s3__buckets__finalize_body");
      begin
         E613 := E613 - 1;
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
         E653 := E653 - 1;
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
         E621 := E621 - 1;
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
         E535 := E535 - 1;
         F53;
      end;
      E585 := E585 - 1;
      declare
         procedure F54;
         pragma Import (Ada, F54, "sax__readers__finalize_spec");
      begin
         F54;
      end;
      E582 := E582 - 1;
      declare
         procedure F55;
         pragma Import (Ada, F55, "input_sources__strings__finalize_spec");
      begin
         F55;
      end;
      E591 := E591 - 1;
      declare
         procedure F56;
         pragma Import (Ada, F56, "input_sources__file__finalize_spec");
      begin
         F56;
      end;
      E537 := E537 - 1;
      declare
         procedure F57;
         pragma Import (Ada, F57, "input_sources__finalize_spec");
      begin
         F57;
      end;
      E611 := E611 - 1;
      declare
         procedure F58;
         pragma Import (Ada, F58, "sax__utils__finalize_spec");
      begin
         F58;
      end;
      E593 := E593 - 1;
      declare
         procedure F59;
         pragma Import (Ada, F59, "sax__attributes__finalize_spec");
      begin
         F59;
      end;
      E607 := E607 - 1;
      declare
         procedure F60;
         pragma Import (Ada, F60, "sax__exceptions__finalize_spec");
      begin
         F60;
      end;
      E598 := E598 - 1;
      declare
         procedure F61;
         pragma Import (Ada, F61, "sax__symbols__finalize_spec");
      begin
         F61;
      end;
      E605 := E605 - 1;
      declare
         procedure F62;
         pragma Import (Ada, F62, "sax__pointers__finalize_spec");
      begin
         F62;
      end;
      E695 := E695 - 1;
      declare
         procedure F63;
         pragma Import (Ada, F63, "flyology__http__client__request_bodies__files__finalize_spec");
      begin
         F63;
      end;
      E693 := E693 - 1;
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
         E223 := E223 - 1;
         F65;
      end;
      declare
         procedure F66;
         pragma Import (Ada, F66, "flyology__http__client__finalize_spec");
      begin
         F66;
      end;
      E452 := E452 - 1;
      declare
         procedure F67;
         pragma Import (Ada, F67, "flyology__io__connections__tls__finalize_spec");
      begin
         F67;
      end;
      E454 := E454 - 1;
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
         E261 := E261 - 1;
         F69;
      end;
      E324 := E324 - 1;
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
         E303 := E303 - 1;
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
         E312 := E312 - 1;
         F73;
      end;
      declare
         procedure F74;
         pragma Import (Ada, F74, "flyology__io__tls__finalize_spec");
      begin
         F74;
      end;
      E328 := E328 - 1;
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
         E357 := E357 - 1;
         F76;
      end;
      declare
         procedure F77;
         pragma Import (Ada, F77, "flyology__quic__connections__finalize_spec");
      begin
         F77;
      end;
      E380 := E380 - 1;
      declare
         procedure F78;
         pragma Import (Ada, F78, "flyology__quic__crypto_openssl__finalize_spec");
      begin
         F78;
      end;
      E645 := E645 - 1;
      declare
         procedure F79;
         pragma Import (Ada, F79, "flyology__object_storage__tags__finalize_spec");
      begin
         F79;
      end;
      E500 := E500 - 1;
      declare
         procedure F80;
         pragma Import (Ada, F80, "flyology__object_storage__s3__checksums__finalize_spec");
      begin
         F80;
      end;
      E458 := E458 - 1;
      declare
         procedure F81;
         pragma Import (Ada, F81, "flyology__io__dns__finalize_spec");
      begin
         F81;
      end;
      E315 := E315 - 1;
      declare
         procedure F82;
         pragma Import (Ada, F82, "flyology__io__sockets__finalize_spec");
      begin
         F82;
      end;
      E463 := E463 - 1;
      declare
         procedure F83;
         pragma Import (Ada, F83, "flyology__io__files__finalize_spec");
      begin
         F83;
      end;
      E269 := E269 - 1;
      declare
         procedure F84;
         pragma Import (Ada, F84, "flyology__bytes__finalize_spec");
      begin
         F84;
      end;
      E252 := E252 - 1;
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
         E225 := E225 - 1;
         F86;
      end;
      declare
         procedure F87;
         pragma Import (Ada, F87, "flyology__buffers__finalize_spec");
      begin
         F87;
      end;
      E289 := E289 - 1;
      E287 := E287 - 1;
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
      E283 := E283 - 1;
      declare
         procedure F90;
         pragma Import (Ada, F90, "flyology__wake_sources__finalize_spec");
      begin
         F90;
      end;
      E234 := E234 - 1;
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
         E062 := E062 - 1;
         F92;
      end;
      declare
         procedure F93;
         pragma Import (Ada, F93, "ada__directories__finalize_spec");
      begin
         F93;
      end;
      E158 := E158 - 1;
      declare
         procedure F94;
         pragma Import (Ada, F94, "system__regexp__finalize_spec");
      begin
         F94;
      end;
      E254 := E254 - 1;
      declare
         procedure F95;
         pragma Import (Ada, F95, "system__pool_global__finalize_spec");
      begin
         F95;
      end;
      E139 := E139 - 1;
      declare
         procedure F96;
         pragma Import (Ada, F96, "ada__strings__unbounded__finalize_spec");
      begin
         F96;
      end;
      E527 := E527 - 1;
      declare
         procedure F97;
         pragma Import (Ada, F97, "gnat__sha512__finalize_spec");
      begin
         F97;
      end;
      E521 := E521 - 1;
      declare
         procedure F98;
         pragma Import (Ada, F98, "gnat__sha256__finalize_spec");
      begin
         F98;
      end;
      E517 := E517 - 1;
      declare
         procedure F99;
         pragma Import (Ada, F99, "gnat__sha1__finalize_spec");
      begin
         F99;
      end;
      E508 := E508 - 1;
      declare
         procedure F100;
         pragma Import (Ada, F100, "gnat__md5__finalize_spec");
      begin
         F100;
      end;
      E587 := E587 - 1;
      declare
         procedure F101;
         pragma Import (Ada, F101, "ada__text_io__finalize_spec");
      begin
         F101;
      end;
      E271 := E271 - 1;
      declare
         procedure F102;
         pragma Import (Ada, F102, "system__storage_pools__subpools__finalize_spec");
      begin
         F102;
      end;
      E216 := E216 - 1;
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
         E153 := E153 - 1;
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
           True, False, True, False, True, True, False, False, 
           False, True, False, True, True, True, False, False, 
           True, False, True, True, True, False, True, True, 
           False, True, True, True, True, False, False, False, 
           True, False, False, False, False, True, True, True, 
           True, True, True, False),
         Count => (0, 0, 0, 3, 2, 2, 4, 3, 15, 0),
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
      E012 := E012 + 1;
      System.Exceptions'Elab_Spec;
      E021 := E021 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E052 := E052 + 1;
      E014 := E014 + 1;
      E018 := E018 + 1;
      Ada.Assertions'Elab_Spec;
      E173 := E173 + 1;
      Ada.Containers'Elab_Spec;
      E098 := E098 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E104 := E104 + 1;
      Ada.Strings'Elab_Spec;
      E009 := E009 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E108 := E108 + 1;
      Gnat'Elab_Spec;
      E284 := E284 + 1;
      Interfaces.C'Elab_Spec;
      E066 := E066 + 1;
      Interfaces.C.Strings'Elab_Spec;
      E382 := E382 + 1;
      System.Os_Lib'Elab_Body;
      E068 := E068 + 1;
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
      E216 := E216 + 1;
      System.Storage_Pools'Elab_Spec;
      E160 := E160 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E271 := E271 + 1;
      Ada.Calendar'Elab_Spec;
      Ada.Calendar'Elab_Body;
      E064 := E064 + 1;
      Ada.Calendar.Delays'Elab_Body;
      E291 := E291 + 1;
      Ada.Calendar.Time_Zones'Elab_Spec;
      E090 := E090 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E587 := E587 + 1;
      E510 := E510 + 1;
      E512 := E512 + 1;
      Gnat.Md5'Elab_Spec;
      E508 := E508 + 1;
      E519 := E519 + 1;
      E525 := E525 + 1;
      E523 := E523 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E529 := E529 + 1;
      Gnat.Sha1'Elab_Spec;
      E517 := E517 + 1;
      Gnat.Sha256'Elab_Spec;
      E521 := E521 + 1;
      Gnat.Sha512'Elab_Spec;
      E527 := E527 + 1;
      System.Flyology.Scheduler'Elab_Body;
      E180 := E180 + 1;
      Ada.Real_Time'Elab_Spec;
      Ada.Real_Time'Elab_Body;
      E162 := E162 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E056 := E056 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E060 := E060 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E139 := E139 + 1;
      Gnat.Directory_Operations'Elab_Spec;
      Gnat.Directory_Operations'Elab_Body;
      E589 := E589 + 1;
      System.Interrupt_Management.Operations'Elab_Body;
      E474 := E474 + 1;
      System.Pool_Global'Elab_Spec;
      E254 := E254 + 1;
      System.Regexp'Elab_Spec;
      E158 := E158 + 1;
      Ada.Directories'Elab_Spec;
      Ada.Directories'Elab_Body;
      E062 := E062 + 1;
      System.Tasking.Initialization'Elab_Body;
      E238 := E238 + 1;
      System.Tasking.Protected_Objects'Elab_Body;
      E228 := E228 + 1;
      System.Tasking.Protected_Objects.Entries'Elab_Spec;
      E234 := E234 + 1;
      System.Tasking.Queuing'Elab_Body;
      E246 := E246 + 1;
      System.Flyology.Task_Results'Elab_Body;
      E480 := E480 + 1;
      System.Tasking.Stages'Elab_Body;
      E476 := E476 + 1;
      System.Tasking.Async_Delays'Elab_Body;
      E470 := E470 + 1;
      Flyology.Wake_Sources'Elab_Spec;
      E283 := E283 + 1;
      Flyology.Cancellation'Elab_Spec;
      E293 := E293 + 1;
      Flyology.Operations'Elab_Spec;
      Flyology.Io'Elab_Spec;
      E287 := E287 + 1;
      E289 := E289 + 1;
      Unicode'Elab_Body;
      E539 := E539 + 1;
      Flyology.Buffers'Elab_Spec;
      Flyology.Buffers'Elab_Body;
      E225 := E225 + 1;
      Flyology.Buffers.Drivers'Elab_Spec;
      Flyology.Buffers.Drivers'Elab_Body;
      E252 := E252 + 1;
      Flyology.Bytes'Elab_Spec;
      E269 := E269 + 1;
      E320 := E320 + 1;
      E465 := E465 + 1;
      Flyology.Http'Elab_Spec;
      E221 := E221 + 1;
      E259 := E259 + 1;
      E347 := E347 + 1;
      Flyology.Http.Headers'Elab_Spec;
      E275 := E275 + 1;
      E263 := E263 + 1;
      Flyology.Http.Http_2_Huffman'Elab_Body;
      E267 := E267 + 1;
      Flyology.Http.Http_2_Hpack'Elab_Spec;
      E265 := E265 + 1;
      E277 := E277 + 1;
      E279 := E279 + 1;
      E326 := E326 + 1;
      E281 := E281 + 1;
      E334 := E334 + 1;
      E353 := E353 + 1;
      E339 := E339 + 1;
      E341 := E341 + 1;
      E332 := E332 + 1;
      E349 := E349 + 1;
      E351 := E351 + 1;
      E345 := E345 + 1;
      E343 := E343 + 1;
      E355 := E355 + 1;
      Flyology.Io.Files'Elab_Spec;
      Flyology.Io.Files'Elab_Body;
      E463 := E463 + 1;
      Flyology.Io.Sockets'Elab_Spec;
      Flyology.Io.Sockets'Elab_Body;
      E315 := E315 + 1;
      Flyology.Io.Dns'Elab_Spec;
      Flyology.Io.Dns'Elab_Body;
      E458 := E458 + 1;
      Flyology.Object_Storage'Elab_Spec;
      E485 := E485 + 1;
      E498 := E498 + 1;
      Flyology.Object_Storage.S3.Checksum_Crc'Elab_Body;
      E506 := E506 + 1;
      E496 := E496 + 1;
      Flyology.Object_Storage.S3.Imf_Dates'Elab_Body;
      E637 := E637 + 1;
      E667 := E667 + 1;
      E697 := E697 + 1;
      E615 := E615 + 1;
      E502 := E502 + 1;
      E504 := E504 + 1;
      Flyology.Object_Storage.S3.Checksums'Elab_Spec;
      Flyology.Object_Storage.S3.Checksums'Elab_Body;
      E500 := E500 + 1;
      Flyology.Object_Storage.S3.Sigv4'Elab_Spec;
      E685 := E685 + 1;
      Flyology.Object_Storage.Tags'Elab_Spec;
      E645 := E645 + 1;
      E430 := E430 + 1;
      Flyology.Quic.Crypto_Openssl'Elab_Spec;
      Flyology.Quic.Crypto_Openssl'Elab_Body;
      E380 := E380 + 1;
      E375 := E375 + 1;
      E434 := E434 + 1;
      E436 := E436 + 1;
      E420 := E420 + 1;
      E424 := E424 + 1;
      E418 := E418 + 1;
      E438 := E438 + 1;
      E386 := E386 + 1;
      E392 := E392 + 1;
      E394 := E394 + 1;
      E378 := E378 + 1;
      E359 := E359 + 1;
      E432 := E432 + 1;
      E426 := E426 + 1;
      E440 := E440 + 1;
      E412 := E412 + 1;
      Flyology.Quic.Connections'Elab_Spec;
      Flyology.Quic.Connections'Elab_Body;
      E357 := E357 + 1;
      E330 := E330 + 1;
      Flyology.Http.Http_3'Elab_Spec;
      Flyology.Http.Http_3'Elab_Body;
      E328 := E328 + 1;
      E450 := E450 + 1;
      E701 := E701 + 1;
      Flyology.Io.Tls'Elab_Spec;
      E308 := E308 + 1;
      Flyology.Io.Tls'Elab_Body;
      E312 := E312 + 1;
      Flyology.Io.Connections'Elab_Spec;
      Flyology.Io.Connections'Elab_Body;
      E303 := E303 + 1;
      Flyology.Io.Connections.Drivers'Elab_Spec;
      Flyology.Io.Connections.Drivers'Elab_Body;
      E324 := E324 + 1;
      Flyology.Http.Http_2_Client_Connection'Elab_Spec;
      Flyology.Http.Http_2_Client_Connection'Elab_Body;
      E261 := E261 + 1;
      Flyology.Io.Tls.Alpn'Elab_Spec;
      E454 := E454 + 1;
      Flyology.Io.Connections.Tls'Elab_Spec;
      Flyology.Io.Connections.Tls'Elab_Body;
      E452 := E452 + 1;
      Flyology.Http.Client'Elab_Spec;
      Flyology.Http.Client'Elab_Body;
      E223 := E223 + 1;
      Flyology.Http.Client.Request_Bodies'Elab_Spec;
      Flyology.Http.Client.Request_Bodies'Elab_Body;
      E693 := E693 + 1;
      Flyology.Http.Client.Request_Bodies.Files'Elab_Spec;
      Flyology.Http.Client.Request_Bodies.Files'Elab_Body;
      E695 := E695 + 1;
      E703 := E703 + 1;
      E603 := E603 + 1;
      Sax.Pointers'Elab_Spec;
      Sax.Pointers'Elab_Body;
      E605 := E605 + 1;
      Unicode.Ccs'Elab_Spec;
      E550 := E550 + 1;
      E552 := E552 + 1;
      E554 := E554 + 1;
      E559 := E559 + 1;
      E562 := E562 + 1;
      E564 := E564 + 1;
      E566 := E566 + 1;
      E571 := E571 + 1;
      Unicode.Ces'Elab_Spec;
      E546 := E546 + 1;
      Sax.Symbols'Elab_Spec;
      Sax.Symbols'Elab_Body;
      E598 := E598 + 1;
      E609 := E609 + 1;
      Sax.Exceptions'Elab_Spec;
      Sax.Exceptions'Elab_Body;
      E607 := E607 + 1;
      E576 := E576 + 1;
      E574 := E574 + 1;
      E578 := E578 + 1;
      E580 := E580 + 1;
      Sax.Models'Elab_Spec;
      E595 := E595 + 1;
      Sax.Attributes'Elab_Spec;
      Sax.Attributes'Elab_Body;
      E593 := E593 + 1;
      Sax.Utils'Elab_Spec;
      Sax.Utils'Elab_Body;
      E611 := E611 + 1;
      E548 := E548 + 1;
      Input_Sources'Elab_Spec;
      Input_Sources'Elab_Body;
      E537 := E537 + 1;
      Input_Sources.File'Elab_Spec;
      Input_Sources.File'Elab_Body;
      E591 := E591 + 1;
      Input_Sources.Strings'Elab_Spec;
      Input_Sources.Strings'Elab_Body;
      E582 := E582 + 1;
      Sax.Readers'Elab_Spec;
      Sax.Readers'Elab_Body;
      E585 := E585 + 1;
      Flyology.Object_Storage.S3.Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Xml'Elab_Body;
      E535 := E535 + 1;
      Flyology.Object_Storage.S3.Acl'Elab_Spec;
      Flyology.Object_Storage.S3.Acl'Elab_Body;
      E621 := E621 + 1;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Spec;
      Flyology.Object_Storage.S3.Bucket_Controls'Elab_Body;
      E653 := E653 + 1;
      Flyology.Object_Storage.S3.Buckets'Elab_Spec;
      Flyology.Object_Storage.S3.Buckets'Elab_Body;
      E613 := E613 + 1;
      Flyology.Object_Storage.S3.Copies'Elab_Spec;
      Flyology.Object_Storage.S3.Copies'Elab_Body;
      E655 := E655 + 1;
      Flyology.Object_Storage.S3.Deletions'Elab_Spec;
      Flyology.Object_Storage.S3.Deletions'Elab_Body;
      E641 := E641 + 1;
      Flyology.Object_Storage.S3.Attributes'Elab_Spec;
      Flyology.Object_Storage.S3.Attributes'Elab_Body;
      E651 := E651 + 1;
      Flyology.Object_Storage.S3.Encryption'Elab_Spec;
      Flyology.Object_Storage.S3.Encryption'Elab_Body;
      E657 := E657 + 1;
      Flyology.Object_Storage.S3.Errors'Elab_Spec;
      Flyology.Object_Storage.S3.Errors'Elab_Body;
      E659 := E659 + 1;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Spec;
      Flyology.Object_Storage.S3.Lifecycle'Elab_Body;
      E663 := E663 + 1;
      Flyology.Object_Storage.S3.Listings'Elab_Spec;
      Flyology.Object_Storage.S3.Listings'Elab_Body;
      E665 := E665 + 1;
      Flyology.Object_Storage.S3.Logging'Elab_Spec;
      Flyology.Object_Storage.S3.Logging'Elab_Body;
      E631 := E631 + 1;
      Flyology.Object_Storage.S3.Multipart'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart'Elab_Body;
      E675 := E675 + 1;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Spec;
      Flyology.Object_Storage.S3.Multipart_Uploads'Elab_Body;
      E677 := E677 + 1;
      Flyology.Object_Storage.S3.Notifications'Elab_Spec;
      Flyology.Object_Storage.S3.Notifications'Elab_Body;
      E679 := E679 + 1;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Spec;
      Flyology.Object_Storage.S3.Object_Lock'Elab_Body;
      E681 := E681 + 1;
      Flyology.Object_Storage.S3.Object_Reads'Elab_Spec;
      E639 := E639 + 1;
      E627 := E627 + 1;
      Flyology.Object_Storage.S3.Analytics'Elab_Spec;
      Flyology.Object_Storage.S3.Analytics'Elab_Body;
      E647 := E647 + 1;
      Flyology.Object_Storage.S3.Annotations'Elab_Spec;
      Flyology.Object_Storage.S3.Annotations'Elab_Body;
      E649 := E649 + 1;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Spec;
      Flyology.Object_Storage.S3.Intelligent_Tiering'Elab_Body;
      E661 := E661 + 1;
      Flyology.Object_Storage.S3.Inventory'Elab_Spec;
      Flyology.Object_Storage.S3.Inventory'Elab_Body;
      E625 := E625 + 1;
      Flyology.Object_Storage.S3.Metrics'Elab_Spec;
      Flyology.Object_Storage.S3.Metrics'Elab_Body;
      E673 := E673 + 1;
      Flyology.Object_Storage.S3.Replication'Elab_Spec;
      Flyology.Object_Storage.S3.Replication'Elab_Body;
      E683 := E683 + 1;
      E533 := E533 + 1;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Spec;
      Flyology.Object_Storage.S3.Generated_List_Directory_Buckets_Xml'Elab_Body;
      E531 := E531 + 1;
      Flyology.Object_Storage.S3.Tagging'Elab_Spec;
      Flyology.Object_Storage.S3.Tagging'Elab_Body;
      E643 := E643 + 1;
      Flyology.Object_Storage.S3.Versioning'Elab_Spec;
      Flyology.Object_Storage.S3.Versioning'Elab_Body;
      E687 := E687 + 1;
      Flyology.Object_Storage.S3.Versions'Elab_Spec;
      Flyology.Object_Storage.S3.Versions'Elab_Body;
      E689 := E689 + 1;
      Flyology.Object_Storage.S3.Website'Elab_Spec;
      Flyology.Object_Storage.S3.Website'Elab_Body;
      E635 := E635 + 1;
      Flyology.Object_Storage.S3.Xml_Writers'Elab_Spec;
      E619 := E619 + 1;
      E617 := E617 + 1;
      E623 := E623 + 1;
      E629 := E629 + 1;
      E633 := E633 + 1;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Configurations'Elab_Body;
      E669 := E669 + 1;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Spec;
      Flyology.Object_Storage.S3.Metadata_Tables'Elab_Body;
      E671 := E671 + 1;
      Flyology.Object_Storage.Client.Low_Level'Elab_Spec;
      Flyology.Object_Storage.Client.Low_Level'Elab_Body;
      E493 := E493 + 1;
      Flyology.Object_Storage.Client.Transfers'Elab_Spec;
      Flyology.Object_Storage.Client.Transfers'Elab_Body;
      E691 := E691 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_repro_transfers_1");

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
   --   /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/tests/repros/obj/development/repro_transfers_1.o
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
