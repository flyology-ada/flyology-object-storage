with System;

--  Internal best-effort erasure for credential and derived-key storage.
private package Flyology.Object_Storage.Secrets is

   procedure Wipe (Value : in out String);

   procedure Wipe (Address : System.Address; Bytes : Natural);

end Flyology.Object_Storage.Secrets;
