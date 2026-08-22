with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.SHA256;

package body Flyology_Object_Storage_Server_Assets is

   HTML_Digest : constant String :=
     "9afc72a6c06b6f98b5c52bc09f4ae9ee47e400f572ff6001719014ee20b8d6c3";
   CSS_Digest  : constant String :=
     "8e27738ce4a1a94f4fd9aef129dd0447cdf8a708d77ecb6639c46b9b564a3cd5";
   JS_Digest   : constant String :=
     "1f5e45a72825f11bc01cfc1015cf5b3f54d6aae927bb2df1ee8dfe805394b96e";

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
