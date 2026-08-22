--  Bounded, HTTP-independent parsing of S3 origin-form request targets.
package Flyology.Object_Storage.S3.Requests
  with SPARK_Mode => On
is

   Maximum_Target_Length : constant := 8 * 1_024;

   subtype Target_Offset is Natural range 0 .. Maximum_Target_Length;

   type Target_Status is (Target_Parsed, Malformed_Target);
   type Target_Kind is
     (Service_Target, Bucket_Target, Object_Target, Invalid_Target);

   --  One-based offsets relative to the first byte of the supplied target.
   --  Zero denotes an absent component. Query offsets exclude the '?'.
   type Target_Result is record
      Status       : Target_Status := Malformed_Target;
      Kind         : Target_Kind := Invalid_Target;
      Bucket_First : Target_Offset := 0;
      Bucket_Last  : Target_Offset := 0;
      Key_First    : Target_Offset := 0;
      Key_Last     : Target_Offset := 0;
      Has_Query    : Boolean := False;
      Query_First  : Target_Offset := 0;
      Query_Last   : Target_Offset := 0;
   end record;

   --  Parse a bounded origin-form path-style S3 request target. Percent
   --  escapes are strict, '+' remains literal, bucket names and decoded keys
   --  are validated, and fragments are rejected. Virtual-host addressing is
   --  intentionally classified by a later host-aware layer.
   --  @param Value Original HTTP request target
   --  @return Classification and component offsets
   function Parse_Target (Value : String) return Target_Result;

   --  Return the validated percent-decoded path-style bucket component.
   --  @param Value Original target passed to Parse_Target
   --  @param Parsed Parse_Target result for Value
   --  @return Bucket name, or an empty string when unavailable
   function Bucket_Name
     (Value : String; Parsed : Target_Result) return String;

   --  Return the validated percent-decoded object key.
   --  @param Value Original target passed to Parse_Target
   --  @param Parsed Parse_Target result for Value
   --  @return Object key, or an empty string for a non-object target
   function Object_Key
     (Value : String; Parsed : Target_Result) return String;

   --  Return the raw query string without its leading '?'.
   --  @param Value Original target passed to Parse_Target
   --  @param Parsed Parse_Target result for Value
   --  @return Raw query bytes, including percent escapes
   function Query_String
     (Value : String; Parsed : Target_Result) return String;

end Flyology.Object_Storage.S3.Requests;
