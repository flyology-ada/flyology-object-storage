--  WIRE-2: Read_Entity_Tag_List treats an empty list element as a syntax
--  error, so If-Match / If-None-Match fields that RFC 9110 section 5.6.1
--  requires a recipient to parse and ignore ("a recipient MUST parse and
--  ignore a reasonable number of empty list elements", from memory,
--  unverified) are answered 400 InvalidArgument instead of being evaluated
--  against the tags actually present.  The program asserts the CORRECT
--  behavior at both levels: the domain predicate accepts the field, and a
--  conditional HEAD carrying it answers 200.
with Flyology.Object_Storage;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Wire_2 is

   package OS renames Flyology.Object_Storage;
   use type OS.Status;

   Bucket : constant String := "wire-two-bucket";
   Key    : constant String := "conditional.txt";
   Quote  : constant Character := '"';

   --  MD5 of "x", the ETag the memory backend reports for this body.
   Tag : constant String := "9dd4e461268c8034f5c8564e155c67a6";

   procedure Probe (Label, Field : String; Expect_200 : Boolean) is
      R : constant String := Run (Signed_Request
        ("HEAD", "/" & Bucket & "/" & Key,
         Extra_Headers => "If-Match: " & Field & CRLF));
   begin
      Note (Label & ": If-Match: " & Field & " -> status " &
            Image (Status_Code (R)));
      if Expect_200 then
         Check (Status_Code (R) = 200, Label & " answers 200");
      end if;
   end Probe;

begin
   ------------------------------------------------------------------
   --  Unit level.
   ------------------------------------------------------------------
   Note ("Valid_Object_Read_Entity_Tag_Condition (" & Quote & Tag & Quote &
         ") = " &
         Boolean'Image (OS.Valid_Object_Read_Entity_Tag_Condition
           (Quote & Tag & Quote)));
   Check (OS.Valid_Object_Read_Entity_Tag_Condition (Quote & Tag & Quote),
          "CONTROL: a plain quoted entity tag is valid");

   for Case_Index in 1 .. 3 loop
      declare
         Field : constant String :=
           (case Case_Index is
              when 1 => Quote & Tag & Quote & ",",
              when 2 => "," & Quote & Tag & Quote,
              when others =>
                Quote & Tag & Quote & ",," & Quote & "other" & Quote);
         Label : constant String :=
           (case Case_Index is
              when 1 => "trailing empty element",
              when 2 => "leading empty element",
              when others => "interior empty element");
      begin
         Note (Label & ": Valid_Object_Read_Entity_Tag_Condition (" &
               Field & ") = " &
               Boolean'Image
                 (OS.Valid_Object_Read_Entity_Tag_Condition (Field)));
         Check (OS.Valid_Object_Read_Entity_Tag_Condition (Field),
                Label & ": the field is accepted as entity-tag list syntax");
         Note (Label & ": Evaluate_Object_Read_Conditions = " &
               OS.Status'Image (OS.Evaluate_Object_Read_Conditions
                 (If_Match                => Field,
                  If_None_Match           => "",
                  Has_If_Modified_Since   => False,
                  If_Modified_Since       => 0,
                  Has_If_Unmodified_Since => False,
                  If_Unmodified_Since     => 0,
                  Entity_Tag              => Tag,
                  Modified                => 0)));
         Check (OS.Evaluate_Object_Read_Conditions
                  (If_Match                => Field,
                   If_None_Match           => "",
                   Has_If_Modified_Since   => False,
                   If_Modified_Since       => 0,
                   Has_If_Unmodified_Since => False,
                   If_Unmodified_Since     => 0,
                   Entity_Tag              => Tag,
                   Modified                => 0) = OS.Success,
                Label & ": the read condition evaluates to Success");
         Note (Label & ": Evaluate_Object_Write_Conditions = " &
               OS.Status'Image (OS.Evaluate_Object_Write_Conditions
                 (If_Match      => Field,
                  If_None_Match => "",
                  Exists        => True,
                  Entity_Tag    => Tag)));
      end;
   end loop;

   ------------------------------------------------------------------
   --  Server level.
   ------------------------------------------------------------------
   declare
      R : constant String := Run (Signed_Request ("PUT", "/" & Bucket));
   begin
      Note ("CreateBucket status " & Image (Status_Code (R)));
      Check (Status_Code (R) = 200, "CreateBucket is 200");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("PUT", "/" & Bucket & "/" & Key, "x"));
   begin
      Note ("PutObject ETag " & Header_Value (R, "ETag"));
      Check (Header_Value (R, "ETag") = Quote & Tag & Quote,
             "the stored object has the expected ETag");
   end;

   Probe ("CONTROL exact tag", Quote & Tag & Quote, True);
   Probe ("CONTROL wildcard", "*", True);
   Probe ("trailing empty element", Quote & Tag & Quote & ",", True);
   Probe ("leading empty element", "," & Quote & Tag & Quote, True);
   Probe ("interior empty element",
          Quote & Tag & Quote & ",," & Quote & "other" & Quote, True);

   --  CONTROL: a genuinely non-matching tag must still be 412, so the
   --  program is not just asserting "everything is 200".
   declare
      R : constant String := Run (Signed_Request
        ("HEAD", "/" & Bucket & "/" & Key,
         Extra_Headers =>
           "If-Match: " & Quote & "0000" & Quote & CRLF));
   begin
      Note ("CONTROL non-matching tag -> status " & Image (Status_Code (R)));
      Check (Status_Code (R) = 412,
             "CONTROL: a non-matching If-Match is 412");
   end;

   Finish;
end Repro_Wire_2;
