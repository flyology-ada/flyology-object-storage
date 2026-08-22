--  Strict canonical IMF-fixdate policy used by S3 timestamp members.  This
--  is intentionally not a generic RFC 9110 HTTP-date recipient: S3 SDKs
--  serialize the Expires timestamp in the canonical IMF form.
package Flyology.Object_Storage.S3.IMF_Dates
  with SPARK_Mode => On
is
   type Metadata_Time_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Metadata_Time;
         when False =>
            null;
      end case;
   end record;

   --  Parse exactly IMF-fixdate, including a weekday consistent with the
   --  proleptic Gregorian date.  Leap second 60 is normalized to the next
   --  minute; the year-9999 terminal leap second is outside Metadata_Time.
   function Parse (Text : String) return Metadata_Time_Result;

   --  Render one typed metadata timestamp as the 29-byte IMF-fixdate form.
   function Image (Value : Metadata_Time) return String
   with Post => Image'Result'Length = 29;
end Flyology.Object_Storage.S3.IMF_Dates;
