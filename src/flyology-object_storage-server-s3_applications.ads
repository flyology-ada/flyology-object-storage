with Ada.Calendar;
with Flyology.HTTP.Server.Applications;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.MFA;
with Flyology.Object_Storage.Server.Metadata_Results;

--  Binds one pluggable backend and credential provider into an authenticated
--  path-style S3 application callback. Each Handle call owns its request and
--  response streams synchronously; no borrowed exchange escapes the call.
--  This is a single-tenant application boundary: every credential accepted
--  by Credentials must report the same tenant/account-owner Principal for the
--  bound Store. Expected-owner checks compare against that stable Principal;
--  a multi-tenant credential provider requires a separate application/store
--  binding per tenant.
--  @formal Backend_Type Concrete pluggable backend type
--  @formal Store Backend instance owned by the application
--  @formal Credential_Provider_Type Concrete credential-provider type
--  @formal Credentials Credential provider owned by the application
--  @formal MFA_Verifier Optional MFA proof verifier
--  @formal Rules Authentication policy
--  @formal Clock Trusted wall-clock source
--  @formal Metadata_Provider Optional caller-owned metadata result provider;
--  null makes metadata creates and updates return NotImplemented without
--  backend mutation; reads and deletes do not consult it and remain subject
--  to the Store's optional metadata capability
generic
   type Backend_Type (<>) is limited new Backends.Backend with private;
   Store : in out Backend_Type;
   type Credential_Provider_Type (<>) is limited new
     Authentication.Credential_Provider with private;
   Credentials : in out Credential_Provider_Type;
   MFA_Verifier : MFA.Verifier_Access := null;
   Rules       : Authentication.Policy := Authentication.Default_Policy;
   with function Clock return Ada.Calendar.Time is Ada.Calendar.Clock;
   Metadata_Provider : Metadata_Results.Provider_Access := null;
package Flyology.Object_Storage.Server.S3_Applications is

   --  Serve one Flyology HTTP exchange. The current slice implements the
   --  service-level ListBuckets, path-style
   --  Create/GetBucketLocation/Put/GetBucketVersioning/Head/DeleteBucket,
   --  GetBucketAcl,
   --  Put/Get/DeletePublicAccessBlock,
   --  Put/Get/Head/DeleteObject, GetObjectAcl, DeleteObjects,
   --  ListObjects v1/v2, and core
   --  multipart operations,
   --  including ListParts and ListMultipartUploads. Unsupported S3 operations
   --  receive a typed NotImplemented response and never reach the backend.
   --  The ACL reads derive one owner-only FULL_CONTROL policy from the stable
   --  single-tenant Principal and the application's private-only bucket and
   --  object mutation profile; they do not imply persisted ACL state.
   --  @param X Borrowed request-scoped Flyology HTTP exchange
   procedure Handle
     (X : in out Flyology.HTTP.Server.Applications.Exchange);

end Flyology.Object_Storage.Server.S3_Applications;
