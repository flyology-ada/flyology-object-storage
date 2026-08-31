with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  HTTP-independent AWS resource tag values shared by clients, servers, and
--  storage backends. Strings contain UTF-8 bytes; validation applies the AWS
--  Unicode category and length rules before any value crosses a backend
--  publication boundary.
package Flyology.Object_Storage.Tags is

   --  Maximum tag count accepted for one bucket tag set.
   Maximum_Bucket_Tags      : constant := 50;

   --  Maximum Unicode character count accepted for one tag key.
   Maximum_Key_Characters   : constant := 128;

   --  Maximum Unicode character count accepted for one tag value.
   Maximum_Value_Characters : constant := 256;

   --  One HTTP-independent resource tag.
   --  @field Key UTF-8 tag key bytes
   --  @field Value UTF-8 tag value bytes
   type Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Ordered dynamically sized tag storage.
   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Tag);

   --  Ordered set of resource tags.
   subtype Tag_Set is Tag_Vectors.Vector;

   --  Validate a nonempty bucket tag set: at most 50 unique, case-sensitive
   --  keys; UTF-8 scalar values in the AWS L/Z/N or `_.:/=+-@` character
   --  classes; 1..128 key and 0..256 value Unicode characters; and no
   --  user-defined key with the reserved case-insensitive `aws:` prefix.
   --  @param Value Candidate bucket tag set
   --  @return Whether every tag and the complete set satisfy the constraints
   function Valid_Bucket_Tag_Set (Value : Tag_Set) return Boolean;

end Flyology.Object_Storage.Tags;
