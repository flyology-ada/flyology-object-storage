--  Strict implementation oracles for buckets composable result mappings.
package Flyology.Object_Storage.Client.Buckets.Testing is

   procedure Check_List_Buckets_Result_Corpus;

   procedure Check_Create_Bucket_Certainty_Corpus;

   procedure Check_Delete_Bucket_Certainty_Corpus;

   procedure Check_Head_Bucket_Result_Corpus;

   procedure Check_Get_Bucket_Location_Result_Corpus;

   procedure Check_Get_Bucket_Policy_Result_Corpus;

   procedure Check_Get_Bucket_Policy_Status_Result_Corpus;

   procedure Check_Get_Bucket_Accelerate_Configuration_Result_Corpus;

   procedure Check_Get_Bucket_ABAC_Result_Corpus;

   procedure Check_Get_Bucket_Request_Payment_Result_Corpus;

   procedure Check_Bucket_Policy_Certainty_Corpus;

   procedure Check_Public_Access_Block_Certainty_Corpus;

   procedure Check_ABAC_Certainty_Corpus;

   procedure Check_Acceleration_Certainty_Corpus;

   procedure Check_Request_Payment_Certainty_Corpus;

   procedure Check_Ownership_Controls_Certainty_Corpus;

   procedure Check_Bucket_Encryption_Result_Corpus;
   procedure Check_Get_Bucket_Lifecycle_Result_Corpus;

   procedure Check_Get_Bucket_ACL_Result_Corpus;

   procedure Check_Metadata_Table_Configuration_Result_Corpus;

   procedure Check_Delete_Bucket_Lifecycle_Certainty_Corpus;

   procedure Check_Delete_Bucket_Replication_Certainty_Corpus;

   procedure Check_Delete_Bucket_Website_Certainty_Corpus;

   procedure Check_Delete_Bucket_Metadata_Certainty_Corpus;
   procedure Check_Delete_Bucket_Metadata_Table_Certainty_Corpus;
   procedure Check_Delete_Bucket_Metrics_Certainty_Corpus;
   procedure Check_Delete_Bucket_Analytics_Certainty_Corpus;
   procedure Check_Delete_Bucket_Intelligent_Tiering_Certainty_Corpus;

   procedure Check_Delete_Bucket_Inventory_Configuration_Certainty_Corpus;

   procedure Check_Bucket_CORS_Result_Corpus;

   procedure Check_Object_Lock_Configuration_Certainty_Corpus;

   procedure Check_Object_Lock_Configuration_Pre_Admission_Rejection
     (Client   : not null access Flyology.HTTP.Client.Client;
      Prepared : Flyology.Object_Storage.Client.Low_Level.Prepared_Request;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline);

   procedure Set_Response_Limit
     (Operation : in out Get_Object_Lock_Configuration_Operation;
      Maximum   : Natural);

   procedure Set_Response_Limit
     (Operation : in out Put_Object_Lock_Configuration_Operation;
      Maximum   : Natural);

   procedure Check_Get_Bucket_Versioning_Result_Corpus;

   procedure Check_Put_Bucket_Versioning_Certainty_Corpus;

   procedure Check_Bucket_Tagging_Certainty_Corpus;

end Flyology.Object_Storage.Client.Buckets.Testing;
