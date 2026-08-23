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

   Maximum_Signed_Header_Occurrences : constant := 256;

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

      function All_Amazon_Headers_Signed return Boolean is
      begin
         for Index in 1 .. Applications.Request_Header_Count (X) loop
            declare
               Name : constant String := Encoding.Lowercase
                 (Applications.Request_Header_Name (X, Index));
            begin
               if Name'Length >= 6
                 and then Name (Name'First .. Name'First + 5) = "x-amz-"
                 and then not Verification.Header_Is_Signed
                   (Parsed.Data, Name)
               then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end All_Amazon_Headers_Signed;

      function Signed_Physical_Header_Count return Natural is
         Result : Natural := 0;
      begin
         for Index in 1 .. Verification.Signed_Header_Count (Parsed.Data) loop
            declare
               Occurrences : constant Natural :=
                 Applications.Request_Header_Count
                   (X, Verification.Signed_Header_Name (Parsed.Data, Index));
            begin
               if Occurrences > Maximum_Signed_Header_Occurrences - Result
               then
                  return Maximum_Signed_Header_Occurrences + 1;
               end if;
               Result := Result + Occurrences;
            end;
         end loop;
         return Result;
      end Signed_Physical_Header_Count;
   begin
      if Authorization_Count = 0 then
         return (Status => Missing_Credentials, others => <>);
      elsif Authorization_Count /= 1
        or else Parsed.Status /= Verification.Parsed
        or else Applications.Request_Header_Count
          (X, "x-amz-content-sha256") /= 1
        or else Applications.Request_Header_Count (X, "x-amz-date") /= 1
        or else not All_Amazon_Headers_Signed
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
         Physical_Count : constant Natural := Signed_Physical_Header_Count;
         Last : Natural := 0;
         Principal : US.Unbounded_String;
         Allowed : Boolean;
      begin
         if Physical_Count > Maximum_Signed_Header_Occurrences then
            return (Status => Malformed_Credentials, others => <>);
         end if;
         declare
            Headers : SigV4.Name_Value_Array (1 .. Physical_Count);
         begin
            for Index in 1 ..
              Verification.Signed_Header_Count (Parsed.Data)
            loop
               declare
                  Name : constant String :=
                    Verification.Signed_Header_Name (Parsed.Data, Index);
               begin
                  if Applications.Request_Header_Count (X, Name) = 0 then
                     return (Status => Malformed_Credentials, others => <>);
                  end if;
                  for Occurrence in 1 ..
                    Applications.Request_Header_Count (X, Name)
                  loop
                     Last := Last + 1;
                     Headers (Last) := SigV4.Pair
                       (Name, Applications.Request_Header
                          (X, Name, Occurrence));
                  end loop;
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
         end;
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
