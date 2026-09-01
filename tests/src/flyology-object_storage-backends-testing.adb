package body Flyology.Object_Storage.Backends.Testing is

   function Maximum_Bucket_Configuration_Bytes_For_Testing
     return Byte_Count is (Maximum_Bucket_Configuration_Bytes);

   procedure Reset_Unsupported_Bucket_Metadata_Get_For_Testing
     (Value      : out Bucket_Metadata_State;
      Configured : out Boolean;
      Result     : out Status) is
   begin
      Reset_Unsupported_Bucket_Metadata_Get
        (Value, Configured, Result);
   end Reset_Unsupported_Bucket_Metadata_Get_For_Testing;

   function Unsupported_Bucket_Metadata_Status_For_Testing return Status is
     (Unsupported_Bucket_Metadata_Status);

end Flyology.Object_Storage.Backends.Testing;
