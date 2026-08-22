with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.SHA256;

package body Flyology_Object_Storage_Server_Assets is

   HTML_Digest : constant String :=
     "3d0ee7bfc5d3698ef3b01715b4bcf4081010eca4816e03f67aa8ad098cb37c9c";
   CSS_Digest  : constant String :=
     "9c6c7298f3a1ea0364ba68c89cb65f21aebb140190b35518c3940c805d9f2c74";
   JS_Digest   : constant String :=
     "1254cb64e32ff96d84044df0443fc564365396cd0adba712d1ebdaeb6a17e622";

   function Root return String is
   begin
      if Ada.Environment_Variables.Exists ("FLYOLOGY_ADMIN_ASSET_ROOT") then
         return Ada.Environment_Variables.Value ("FLYOLOGY_ADMIN_ASSET_ROOT");
      elsif Ada.Directories.Exists ("assets/index.html") then
         return "assets";
      elsif Ada.Directories.Exists ("server/assets/index.html") then
         return "server/assets";
      else
         raise Constraint_Error with "management assets not found";
      end if;
   end Root;

   function Read_All (Path : String) return Unbounded_String is
      File   : Ada.Text_IO.File_Type;
      Result : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Result, Ada.Text_IO.Get_Line (File));
         Append (Result, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Read_All;

   procedure Verify
     (Name, Expected : String; Value : Unbounded_String)
   is
   begin
      if GNAT.SHA256.Digest (To_String (Value)) /= Expected then
         raise Constraint_Error with
           "management asset failed integrity check: " & Name;
      end if;
   end Verify;

   procedure Load (Item : out Bundle) is
      Directory : constant String := Root;
   begin
      Item.HTML := Read_All
        (Ada.Directories.Compose (Directory, "index.html"));
      Item.Stylesheet := Read_All
        (Ada.Directories.Compose (Directory, "app.css"));
      Item.Script := Read_All
        (Ada.Directories.Compose (Directory, "app.js"));
      Verify ("index.html", HTML_Digest, Item.HTML);
      Verify ("app.css", CSS_Digest, Item.Stylesheet);
      Verify ("app.js", JS_Digest, Item.Script);
   end Load;

end Flyology_Object_Storage_Server_Assets;
