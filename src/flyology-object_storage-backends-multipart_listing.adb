with Ada.Containers;
with Ada.Strings.Fixed;

package body Flyology.Object_Storage.Backends.Multipart_Listing is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type US.Unbounded_String;

   function Starts_With (Value, Prefix : String) return Boolean is
     (Prefix'Length <= Value'Length
      and then
        (Prefix'Length = 0
         or else Value
           (Value'First .. Value'First + Prefix'Length - 1) = Prefix));

   function Before (Left, Right : Candidate) return Boolean is
      Left_Key  : constant String := US.To_String (Left.Key);
      Right_Key : constant String := US.To_String (Right.Key);
   begin
      return Left_Key < Right_Key
        or else
          (Left_Key = Right_Key
           and then
             (Left.Initiated < Right.Initiated
              or else
                (Left.Initiated = Right.Initiated
                 and then US.To_String (Left.Upload_ID) <
                   US.To_String (Right.Upload_ID))));
   end Before;

   function Same (Left, Right : Candidate) return Boolean is
     (Left.Key = Right.Key and then Left.Upload_ID = Right.Upload_ID);

   procedure Initialize
     (Item : in out Builder; Options : List_Multipart_Uploads_Options) is
   begin
      Item.Options := Options;
      Item.Candidates.Clear;
      Item.Candidates.Reserve_Capacity
        (Ada.Containers.Count_Type (Options.Maximum) + 1);
   end Initialize;

   procedure Consider
     (Item      : in out Builder;
      Key       : String;
      Upload_ID : String;
      Initiated : Unix_Time;
      Options   : Multipart_Options)
   is
      Prefix    : constant String := US.To_String (Item.Options.Prefix);
      Delimiter : constant String := US.To_String (Item.Options.Delimiter);
      After_Key : constant String := US.To_String (Item.Options.After.Key);
      After_ID  : constant String :=
        US.To_String (Item.Options.After.Upload_ID);
      Delimiter_At : Natural := 0;
      Value     : Candidate;
      Insert_At : Natural := 0;
      Keep      : constant Ada.Containers.Count_Type :=
        Ada.Containers.Count_Type (Item.Options.Maximum) + 1;
   begin
      if not Starts_With (Key, Prefix) then
         return;
      end if;
      if Delimiter'Length > 0 and then Prefix'Length < Key'Length then
         Delimiter_At := Ada.Strings.Fixed.Index
           (Key, Delimiter, From => Key'First + Prefix'Length);
      end if;
      if Delimiter_At /= 0 then
         Value.Is_Prefix := True;
         Value.Key := US.To_Unbounded_String
           (Key (Key'First .. Delimiter_At + Delimiter'Length - 1));
      else
         Value.Key := US.To_Unbounded_String (Key);
         Value.Upload_ID := US.To_Unbounded_String (Upload_ID);
         Value.Initiated := Initiated;
         Value.Options := Options;
      end if;

      declare
         Candidate_Key : constant String := US.To_String (Value.Key);
         Candidate_ID  : constant String := US.To_String (Value.Upload_ID);
      begin
         if Candidate_Key < After_Key
           or else
             (Candidate_Key = After_Key
              and then
                (After_ID'Length = 0 or else Candidate_ID <= After_ID))
         then
            return;
         end if;
      end;

      if not Item.Candidates.Is_Empty then
         for Index in Item.Candidates.First_Index ..
           Item.Candidates.Last_Index
         loop
            if Same (Item.Candidates (Index), Value) then
               return;
            elsif Before (Value, Item.Candidates (Index)) then
               Insert_At := Index;
               exit;
            end if;
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

   function Finish (Item : Builder) return Multipart_Upload_Page is
      Result : Multipart_Upload_Page;
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
               Result.Uploads.Append
                 (Listed_Multipart_Upload'
                    (Key       => Value.Key,
                     Upload_ID => Value.Upload_ID,
                     Initiated => Value.Initiated,
                     Options   => Value.Options));
            end if;
         end;
      end loop;
      if Result.Is_Truncated then
         if Returned = 0 then
            Result.Next_After := Item.Options.After;
         else
            Result.Next_After.Key := Item.Candidates (Returned).Key;
            Result.Next_After.Upload_ID :=
              Item.Candidates (Returned).Upload_ID;
         end if;
      end if;
      return Result;
   end Finish;

end Flyology.Object_Storage.Backends.Multipart_Listing;
