with Ada.Containers;
with Ada.Strings.Fixed;

package body Flyology.Object_Storage.Backends.Listing is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Starts_With (Value, Prefix : String) return Boolean is
     (Prefix'Length <= Value'Length
      and then
        (Prefix'Length = 0
         or else Value
           (Value'First .. Value'First + Prefix'Length - 1) = Prefix));

   procedure Initialize (Item : in out Builder; Options : List_Options) is
   begin
      Item.Options := Options;
      Item.Candidates.Clear;
      Item.Candidates.Reserve_Capacity
        (Ada.Containers.Count_Type (Options.Maximum) + 1);
   end Initialize;

   procedure Consider
     (Item : in out Builder; Key : String; Info : Object_Information)
   is
      Prefix    : constant String := US.To_String (Item.Options.Prefix);
      Delimiter : constant String := US.To_String (Item.Options.Delimiter);
      After     : constant String := US.To_String (Item.Options.After);
      Delimiter_At : Natural := 0;
      Value     : Candidate;
      Insert_At : Natural := 0;
      Keep      : constant Ada.Containers.Count_Type :=
        Ada.Containers.Count_Type (Item.Options.Maximum) + 1;
   begin
      if not Starts_With (Key, Prefix) then
         return;
      end if;
      if Delimiter'Length > 0
        and then Prefix'Length < Key'Length
      then
         Delimiter_At := Ada.Strings.Fixed.Index
           (Key, Delimiter, From => Key'First + Prefix'Length);
      end if;
      if Delimiter_At /= 0 then
         Value.Is_Prefix := True;
         Value.Key := US.To_Unbounded_String
           (Key
              (Key'First .. Delimiter_At + Delimiter'Length - 1));
      else
         Value.Key := US.To_Unbounded_String (Key);
         Value.Info := Info;
      end if;

      if US.To_String (Value.Key) <= After then
         return;
      end if;
      if not Item.Candidates.Is_Empty then
         for Index in Item.Candidates.First_Index ..
           Item.Candidates.Last_Index
         loop
            declare
               Existing : constant String :=
                 US.To_String (Item.Candidates (Index).Key);
               Candidate_Key : constant String := US.To_String (Value.Key);
            begin
               if Existing = Candidate_Key then
                  return;
               elsif Candidate_Key < Existing then
                  Insert_At := Index;
                  exit;
               end if;
            end;
         end loop;
      end if;

      if Insert_At = 0 then
         Item.Candidates.Append (Value);
      else
         Item.Candidates.Insert (Insert_At, Value);
      end if;
      if Item.Candidates.Length > Keep then
         Item.Candidates.Delete_Last;
      end if;
   end Consider;

   function Finish (Item : Builder) return List_Page is
      Result : List_Page;
      Returned : constant Natural := Natural'Min
        (Item.Options.Maximum, Natural (Item.Candidates.Length));
   begin
      Result.Is_Truncated :=
        Item.Options.Maximum > 0
        and then Item.Candidates.Length >
          Ada.Containers.Count_Type (Item.Options.Maximum);
      for Index in 1 .. Returned loop
         declare
            Value : constant Candidate := Item.Candidates (Index);
         begin
            if Value.Is_Prefix then
               Result.Common_Prefixes.Append (Value.Key);
            else
               Result.Objects.Append
                 (Listed_Object'(Key => Value.Key, Info => Value.Info));
            end if;
         end;
      end loop;
      if Result.Is_Truncated then
         Result.Next_After :=
           (if Returned = 0
            then Item.Options.After
            else Item.Candidates (Returned).Key);
      end if;
      return Result;
   end Finish;

end Flyology.Object_Storage.Backends.Listing;
