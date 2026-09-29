--  SIGV4-2: Static_Credentials.Create accepts a principal of 257 .. 1_024
--  bytes, but Authentication.Valid_Principal rejects anything over 256, so
--  every correctly signed request against such a provider is answered
--  403 SignatureDoesNotMatch even though the signature matched.
--
--  Mechanism: static_credentials.ads:36 sets Maximum_Principal_Bytes to
--  1_024 and static_credentials.adb:36-40 enforces only that bound;
--  authentication.adb:18-31 caps the principal at 256 bytes (mirroring
--  flyology_http's Set_Principal contract) and authentication.adb:213-217
--  maps the failure onto Credential_Rejected, which
--  s3_applications.adb:1907-1910 renders as 403 SignatureDoesNotMatch.
--
--  Correct behaviour asserted here: a provider that Create accepted must
--  authenticate correctly signed requests (or Create must have rejected the
--  principal up front).  Either fix removes the failure; this program does
--  not prejudge which.
with Flyology.Object_Storage.Server.Static_Credentials;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;
with Repro_SigV4_Support; use Repro_SigV4_Support;

procedure Repro_SigV4_2 is

   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;

   Create_Accepted_Long : Boolean := False;

   procedure Report (Label, Response : String) is
   begin
      Note (Label & ": status " & Image (Status_Code (Response)));
      Note (Label & ": body " & Escape (Body_Of (Response)));
   end Report;

begin
   --  What Create does with a 300-byte principal.
   begin
      declare
         Probe : Static_Credentials.Provider := Static_Credentials.Create
           (Access_Key, Secret_Key, Principal => Long_Principal);
         pragma Unreferenced (Probe);
      begin
         Create_Accepted_Long := True;
      end;
   exception
      when Static_Credentials.Invalid_Credentials =>
         Create_Accepted_Long := False;
   end;
   Note ("Static_Credentials.Create with a" &
         Integer'Image (Long_Principal'Length) &
         "-byte principal accepted: " &
         Boolean'Image (Create_Accepted_Long));

   --  Control: the identical application whose provider reports a 200-byte
   --  principal serves the very same signed request.
   declare
      Created : constant String :=
        Run_Short (Signed_Request ("PUT", "/principal-bucket"));
   begin
      Report ("control (200-byte principal) CreateBucket", Created);
      Check (Status_Code (Created) = 200,
             "control: a 200-byte principal authenticates (200)");
   end;

   --  The finding: same key, same secret, same signed bytes, 300-byte
   --  principal.
   declare
      Created : constant String :=
        Run_Long (Signed_Request ("PUT", "/principal-bucket"));
   begin
      Report ("300-byte principal CreateBucket", Created);
      Check (not (Create_Accepted_Long
                  and then Status_Code (Created) = 403),
             "a principal Create accepted is not rejected at admission");
      Check (Status_Code (Created) = 200,
             "a 300-byte principal accepted by Create authenticates (200)");
      Check (not Contains (Body_Of (Created),
                           "<Code>SignatureDoesNotMatch</Code>"),
             "a correct signature is never reported as " &
             "SignatureDoesNotMatch");
   end;

   Finish;
end Repro_SigV4_2;
