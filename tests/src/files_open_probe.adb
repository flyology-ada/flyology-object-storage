with Ada.Command_Line;
with Ada.Text_IO;
with Flyology.Object_Storage.Backends.Files;

procedure Files_Open_Probe is
   Store : Flyology.Object_Storage.Backends.Files.Store :=
     Flyology.Object_Storage.Backends.Files.Open
       (Ada.Command_Line.Argument (1));
   pragma Unreferenced (Store);
begin
   Ada.Text_IO.Put_Line ("files open probe: OK");
end Files_Open_Probe;
