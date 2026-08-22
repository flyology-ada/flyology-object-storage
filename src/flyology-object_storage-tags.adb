package body Flyology.Object_Storage.Tags is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type US.Unbounded_String;

   function Reserved_Key (Value : String) return Boolean is
     (Value'Length >= 4
      and then Value (Value'First) in 'a' | 'A'
      and then Value (Value'First + 1) in 'w' | 'W'
      and then Value (Value'First + 2) in 's' | 'S'
      and then Value (Value'First + 3) = ':');

   function Valid_Bucket_Tag_Set (Value : Tag_Set) return Boolean is
   begin
      if Value.Is_Empty
        or else Value.Length > Ada.Containers.Count_Type (Maximum_Bucket_Tags)
      then
         return False;
      end if;
      for Index in Value.First_Index .. Value.Last_Index loop
         declare
            Key  : constant String := US.To_String (Value (Index).Key);
            Text : constant String := US.To_String (Value (Index).Value);
         begin
            if Reserved_Key (Key)
              or else not Valid_Tag_Text
                (Key, Maximum_Key_Characters, Empty_Allowed => False)
              or else not Valid_Tag_Text
                (Text, Maximum_Value_Characters, Empty_Allowed => True)
            then
               return False;
            end if;
            if Index < Value.Last_Index then
               for Other in Index + 1 .. Value.Last_Index loop
                  if Value (Other).Key = Value (Index).Key then
                     return False;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      return True;
   end Valid_Bucket_Tag_Set;

end Flyology.Object_Storage.Tags;
