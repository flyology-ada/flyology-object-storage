package Flyology.Object_Storage.Backends.Testing is

   function Maximum_Bucket_Configuration_Bytes_For_Testing
     return Byte_Count;

   procedure Reset_Unsupported_Bucket_Metadata_Get_For_Testing
     (Value      : out Bucket_Metadata_State;
      Configured : out Boolean;
      Result     : out Status);

   function Unsupported_Bucket_Metadata_Status_For_Testing return Status;

end Flyology.Object_Storage.Backends.Testing;
