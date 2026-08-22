with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Tags;

procedure Files_Open_Probe is
   use type Flyology.Object_Storage.Status;
   package US renames Ada.Strings.Unbounded;
   package Storage renames Flyology.Object_Storage;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Tags renames Flyology.Object_Storage.Tags;
   Action : constant String :=
     (if Ada.Command_Line.Argument_Count = 1
      then "open" else Ada.Command_Line.Argument (1));
   Root : constant String :=
     Ada.Command_Line.Argument
       (if Ada.Command_Line.Argument_Count = 1 then 1 else 2);
begin
   declare
      Store : Files.Store := Files.Open (Root);
      Result : Storage.Status;
   begin
      if Action = "open" then
         Ada.Text_IO.Put_Line ("files open probe: OK");
      elsif Action = "prepare-bucket-tags" then
         declare
            Value : Tags.Tag_Set;
         begin
            Value.Append
              (Tags.Tag'
                 (Key   => US.To_Unbounded_String ("state"),
                  Value => US.To_Unbounded_String ("outside-safe")));
            Store.Create_Bucket
              ("probe-bucket", null, Ada.Real_Time.Time_Last, Result);
            if Result /= Storage.Success then
               raise Program_Error with "could not create probe bucket";
            end if;
            Store.Put_Bucket_Tags
              ("probe-bucket", Value, null, Ada.Real_Time.Time_Last,
               Result);
            if Result /= Storage.Success then
               raise Program_Error with "could not create probe tags";
            end if;
         end;
      elsif Action = "delete-must-fail" then
         Store.Delete_Bucket_Tags
           ("probe-bucket", null, Ada.Real_Time.Time_Last, Result);
         if Result /= Storage.Backend_Unavailable then
            raise Program_Error with
              "poisoned tag path did not fail closed:" & Result'Image;
         end if;
      else
         raise Program_Error with "unknown files probe action";
      end if;
   end;
end Files_Open_Probe;
