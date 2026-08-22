with Flyology.Object_Storage.Backends;
with Flyology_Object_Storage_Server_Configuration;
with Flyology_Object_Storage_Server_Credentials;

generic
   type Backend_Type (<>) is limited new
     Flyology.Object_Storage.Backends.Backend with private;
   Store : in out Backend_Type;
   Configuration : Flyology_Object_Storage_Server_Configuration.Settings;
   Admin_Credential : Flyology_Object_Storage_Server_Credentials.Credential;
procedure Flyology_Object_Storage_Server_Runtime;
