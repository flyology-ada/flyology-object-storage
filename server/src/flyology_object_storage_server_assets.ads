with Ada.Strings.Unbounded;

package Flyology_Object_Storage_Server_Assets is

   type Bundle is record
      HTML       : Ada.Strings.Unbounded.Unbounded_String;
      Stylesheet : Ada.Strings.Unbounded.Unbounded_String;
      Script     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Load the three integrity-pinned management assets. The explicit root is
   --  useful for packaged deployments but cannot replace the compiled asset
   --  set with different content.
   procedure Load (Item : out Bundle);

end Flyology_Object_Storage_Server_Assets;
