with Ada.Calendar;
with Flyology.HTTP.Server.Applications;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Server.Authentication;

--  Binds one pluggable backend and credential provider into an authenticated
--  path-style S3 application callback. Each Handle call owns its request and
--  response streams synchronously; no borrowed exchange escapes the call.
generic
   type Backend_Type (<>) is limited new Backends.Backend with private;
   Store : in out Backend_Type;
   type Credential_Provider_Type (<>) is limited new
     Authentication.Credential_Provider with private;
   Credentials : in out Credential_Provider_Type;
   Rules       : Authentication.Policy := Authentication.Default_Policy;
   with function Clock return Ada.Calendar.Time is Ada.Calendar.Clock;
package Flyology.Object_Storage.Server.S3_Applications is

   --  Serve one Flyology HTTP exchange. The current slice implements the
   --  path-style Create/Head/DeleteBucket, Put/Get/Head/DeleteObject,
   --  DeleteObjects, ListObjects v1/v2, and core multipart operations,
   --  including ListParts and ListMultipartUploads. Unsupported S3 operations
   --  receive a typed NotImplemented response and never reach the backend.
   --  @param X Borrowed request-scoped Flyology HTTP exchange
   procedure Handle
     (X : in out Flyology.HTTP.Server.Applications.Exchange);

end Flyology.Object_Storage.Server.S3_Applications;
