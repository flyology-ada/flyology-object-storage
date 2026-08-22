with Ada.Containers;

package body Flyology.Object_Storage.Backends.Bucket_Listing is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Starts_With (Value, Prefix : String) return Boolean is
     (Prefix'Length <= Value'Length
      and then
        (Prefix'Length = 0
         or else Value
           (Value'First .. Value'First + Prefix'Length - 1) = Prefix));

   procedure Initialize
     (Item : in out Builder; Options : List_Buckets_Options) is
   begin
      Item.Options := Options;
      Item.Candidates.Clear;
      Item.Candidates.Reserve_Capacity
        (Ada.Containers.Count_Type (Options.Maximum) + 1);
   end Initialize;

   procedure Consider
     (Item : in out Builder; Name : String; Created : Unix_Time)
   is
      Prefix    : constant String := US.To_String (Item.Options.Prefix);
      After     : constant String := US.To_String (Item.Options.After);
      Insert_At : Natural := 0;
      Keep      : constant Ada.Containers.Count_Type :=
        Ada.Containers.Count_Type (Item.Options.Maximum) + 1;
      Value     : constant Listed_Bucket :=
        (Name => US.To_Unbounded_String (Name), Created => Created);
   begin
      if not Starts_With (Name, Prefix) or else Name <= After then
         return;
      end if;
      if not Item.Candidates.Is_Empty then
         for Index in Item.Candidates.First_Index ..
           Item.Candidates.Last_Index
         loop
            declare
               Existing : constant String :=
                 US.To_String (Item.Candidates (Index).Name);
            begin
               if Existing = Name then
                  return;
               elsif Name < Existing then
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

   function Finish (Item : Builder) return Bucket_Page is
      Result   : Bucket_Page;
      Returned : constant Natural := Natural'Min
        (Natural (Item.Options.Maximum), Natural (Item.Candidates.Length));
   begin
      Result.Is_Truncated := Item.Candidates.Length >
        Ada.Containers.Count_Type (Item.Options.Maximum);
      for Index in 1 .. Returned loop
         Result.Buckets.Append (Item.Candidates (Index));
      end loop;
      if Result.Is_Truncated then
         Result.Next_After := Result.Buckets (Returned).Name;
      end if;
      return Result;
   end Finish;

end Flyology.Object_Storage.Backends.Bucket_Listing;
