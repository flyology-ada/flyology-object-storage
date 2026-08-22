with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.SHA256;

package body Flyology_Object_Storage_Server_Assets is

   HTML_Digest : constant String :=
     "932ea9bc9ef5cf62b7484202b4f4b5c75e10415d7ee5097106dea0af5c153c50";
   CSS_Digest  : constant String :=
     "b11b8cb691dcab13e17dcf37025978fecc00e55a9402d73f7c0704c259fee96d";
   JS_Digest   : constant String :=
     "6d7d2201874226bf5ec7e2eb69f62970658c10be433a4f6e682797c742d6335b";

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
