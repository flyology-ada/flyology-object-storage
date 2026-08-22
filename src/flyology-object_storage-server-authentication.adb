with Ada.Calendar.Formatting;
with Flyology.HTTP;
with Flyology.Object_Storage.S3.SigV4_Encoding;

package body Flyology.Object_Storage.Server.Authentication is

   package Applications renames Flyology.HTTP.Server.Applications;
   package SigV4 renames S3.SigV4;
   package Encoding renames S3.SigV4_Encoding;
   package Verification renames S3.SigV4_Verification;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Flyology.HTTP.Origin_Scheme;
   use type Verification.Parse_Status;

   function Valid_Principal (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value'Length > 256 then
         return False;
      end if;
      for Character_Value of Value loop
         if Character'Pos (Character_Value) < 32
           or else Character'Pos (Character_Value) = 127
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Principal;

   function Timestamp_Time
     (Value : String; Valid : out Boolean) return Ada.Calendar.Time
   is
      function Digit (Index : Positive) return Natural is
        (Character'Pos (Value (Index)) - Character'Pos ('0'));
      Year : Natural;
      Month : Natural;
      Day : Natural;
      Hour : Natural;
      Minute : Natural;
      Second : Natural;
   begin
      Valid := Encoding.Valid_Timestamp (Value);
      if not Valid then
         return Ada.Calendar.Time_Of (2000, 1, 1);
      end if;
      Year := 1_000 * Digit (Value'First) +
        100 * Digit (Value'First + 1) +
        10 * Digit (Value'First + 2) + Digit (Value'First + 3);
      Month := 10 * Digit (Value'First + 4) + Digit (Value'First + 5);
      Day := 10 * Digit (Value'First + 6) + Digit (Value'First + 7);
      Hour := 10 * Digit (Value'First + 9) + Digit (Value'First + 10);
      Minute := 10 * Digit (Value'First + 11) + Digit (Value'First + 12);
      Second := 10 * Digit (Value'First + 13) + Digit (Value'First + 14);
      return Ada.Calendar.Formatting.Time_Of
        (Ada.Calendar.Year_Number (Year),
         Ada.Calendar.Month_Number (Month),
         Ada.Calendar.Day_Number (Day),
         Ada.Calendar.Formatting.Hour_Number (Hour),
         Ada.Calendar.Formatting.Minute_Number (Minute),
         Ada.Calendar.Formatting.Second_Number (Second),
         Time_Zone => 0);
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         Valid := False;
         return Ada.Calendar.Time_Of (2000, 1, 1);
   end Timestamp_Time;

   function Verify_Request
     (X           : Applications.Exchange;
      Credentials : in out Credential_Provider'Class;
      Rules       : Policy := Default_Policy;
      Now         : Ada.Calendar.Time := Ada.Calendar.Clock) return Outcome
   is
      Authorization_Text : constant String :=
        Applications.Request_Header (X, "authorization");
      Parsed : constant Verification.Parse_Result :=
        Verification.Parse (Authorization_Text);
      Payload_Hash : constant String :=
        Applications.Request_Header (X, "x-amz-content-sha256");
      Timestamp : constant String :=
        Applications.Request_Header (X, "x-amz-date");
      Session_Token : constant String :=
        Applications.Request_Header (X, "x-amz-security-token");
      Authorization_Count : constant Natural :=
        Applications.Request_Header_Count (X, "authorization");
      Timestamp_Valid : Boolean;
      Request_Time : Ada.Calendar.Time;
   begin
      if Authorization_Count = 0 then
         return (Status => Missing_Credentials, others => <>);
      elsif Authorization_Count /= 1
        or else Parsed.Status /= Verification.Parsed
        or else Applications.Request_Header_Count
          (X, "x-amz-content-sha256") /= 1
        or else Applications.Request_Header_Count (X, "x-amz-date") /= 1
        or else
          (Payload_Hash /= SigV4.Unsigned_Payload
           and then not Encoding.Valid_SHA256_Hex (Payload_Hash))
        or else (Applications.Request_Header_Count
                   (X, "x-amz-security-token") > 0
                 and then (Applications.Request_Header_Count
                              (X, "x-amz-security-token") /= 1
                           or else not Verification.Header_Is_Signed
                             (Parsed.Data, "x-amz-security-token")))
      then
         return (Status => Malformed_Credentials, others => <>);
      end if;
      Request_Time := Timestamp_Time (Timestamp, Timestamp_Valid);
      if not Timestamp_Valid
        or else Verification.Scope_Date (Parsed.Data) /=
          Timestamp (Timestamp'First .. Timestamp'First + 7)
      then
         return (Status => Malformed_Credentials, others => <>);
      end if;
      declare
         Difference : constant Duration :=
           (if Now >= Request_Time then Now - Request_Time
            else Request_Time - Now);
      begin
         if Difference > Rules.Maximum_Clock_Skew then
            return (Status => Request_Time_Too_Skewed, others => <>);
         end if;
      end;
      if US.Length (Rules.Expected_Region) > 0
        and then Verification.Region (Parsed.Data) /=
          US.To_String (Rules.Expected_Region)
      then
         return (Status => Wrong_Region, others => <>);
      elsif Payload_Hash = SigV4.Unsigned_Payload
        and then Applications.Request_Scheme (X) /=
          Flyology.HTTP.Secure_HTTPS
      then
         return (Status => Insecure_Unsigned_Payload, others => <>);
      end if;
      declare
         Headers : SigV4.Name_Value_Array
           (1 .. Verification.Signed_Header_Count (Parsed.Data));
         Principal : US.Unbounded_String;
         Allowed : Boolean;
      begin
         for Index in Headers'Range loop
            declare
               Name : constant String :=
                 Verification.Signed_Header_Name (Parsed.Data, Index);
            begin
               if Applications.Request_Header_Count (X, Name) = 0 then
                  return (Status => Malformed_Credentials, others => <>);
               end if;
               Headers (Index) := SigV4.Pair
                 (Name, Applications.Request_Header (X, Name));
            end;
         end loop;
         Credentials.Authenticate
           (Parsed.Data, Applications.Request_Method (X),
            Applications.Request_Target (X), Headers, Payload_Hash,
            Session_Token, Allowed, Principal);
         if not Allowed
           or else not Valid_Principal (US.To_String (Principal))
         then
            return (Status => Credential_Rejected, others => <>);
         end if;
         return
           (Status       => Authenticated,
            Principal    => Principal,
            Payload_Hash => US.To_Unbounded_String (Payload_Hash));
      end;
   exception
      when Constraint_Error =>
         return (Status => Malformed_Credentials, others => <>);
   end Verify_Request;

end Flyology.Object_Storage.Server.Authentication;
