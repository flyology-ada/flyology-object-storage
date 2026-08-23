with Ada.Real_Time;
with Ada.Directories;
with Ada.Containers;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage;

package body Multipart_Part_Conformance is

   use type Flyology.Object_Storage.Status;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Containers.Count_Type;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Ordinary_File_Count (Directory : String) return Natural is
      Search : Ada.Directories.Search_Type;
      Directory_Entry : Ada.Directories.Directory_Entry_Type;
      Result : Natural := 0;
   begin
      if not Ada.Directories.Exists (Directory) then
         return 0;
      end if;
      Ada.Directories.Start_Search
        (Search, Directory, "*", (Ada.Directories.Ordinary_File => True,
                                  others => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Directory_Entry);
         Result := Result + 1;
      end loop;
      Ada.Directories.End_Search (Search);
      return Result;
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Ordinary_File_Count;

   type Boundary_Source is new
     Flyology.Object_Storage.Backends.Byte_Source with
   record
      Length : Flyology.Object_Storage.Byte_Count;
      Reads  : Natural := 0;
   end record;

   overriding function Declared_Length
     (Item : Boundary_Source)
      return Flyology.Object_Storage.Backends.Source_Length is
     (Kind  => Flyology.Object_Storage.Backends.Known,
      Bytes => Item.Length);

   overriding procedure Read
     (Item     : in out Boundary_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Item.Reads := Item.Reads + 1;
      Data := (others => 0);
      Last := Data'First - 1;
      Finished := True;
   end Read;

   type Seed_Source is new
     Flyology.Object_Storage.Backends.Byte_Source with
   record
      Sent : Boolean := False;
   end record;

   overriding function Declared_Length
     (Item : Seed_Source)
      return Flyology.Object_Storage.Backends.Source_Length is
     (Kind => Flyology.Object_Storage.Backends.Known, Bytes => 1);

   overriding procedure Read
     (Item     : in out Seed_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Data := (others => 0);
      if Item.Sent then
         Last := Data'First - 1;
      else
         Data (Data'First) := 16#A5#;
         Last := Data'First;
         Item.Sent := True;
      end if;
      Finished := Item.Sent;
   end Read;

   procedure Exercise_Global_Size_Boundary
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String;
      Label  : String)
   is
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      package US renames Ada.Strings.Unbounded;
      Upload_ID : US.Unbounded_String;
      Info      : Object_Information;
      Prior     : Object_Information;
      Result    : Status;
   begin
      Store.Create_Multipart_Upload
        (Bucket, "global-part-boundary", Default_Multipart_Options,
         null, Ada.Real_Time.Time_Last, Upload_ID, Result);
      Require (Result = Success, Label & " boundary upload create failed");

      declare
         Seed : Seed_Source;
      begin
         Store.Put_Multipart_Part
           (Bucket, "global-part-boundary", US.To_String (Upload_ID), 1,
            Seed, null, Ada.Real_Time.Time_Last, Prior, Result);
         Require
           (Result = Success and then Prior.Size = 1,
            Label & " boundary prior-part seed failed");
      end;

      declare
         Exact : Boundary_Source :=
           (Length => Maximum_Multipart_Part_Size, Reads => 0);
      begin
         Store.Put_Multipart_Part
           (Bucket, "global-part-boundary", US.To_String (Upload_ID), 1,
            Exact, null, Ada.Real_Time.Time_Last, Info, Result);
         Require
           (Result = Invalid_Request and then Exact.Reads = 1,
            Label & " exact 5 GiB declaration was rejected before source");
      end;

      declare
         Oversized : Boundary_Source :=
           (Length => Maximum_Multipart_Part_Size + 1, Reads => 0);
      begin
         Store.Put_Multipart_Part
           (Bucket, "global-part-boundary", US.To_String (Upload_ID), 1,
            Oversized, null, Ada.Real_Time.Time_Last, Info, Result);
         Require
           (Result = Entity_Too_Large and then Oversized.Reads = 0,
            Label & " 5 GiB+1 declaration reached source or wrong status");
      end;

      declare
         Page : Multipart_Part_Page;
      begin
         Store.List_Multipart_Parts
           (Bucket, "global-part-boundary", US.To_String (Upload_ID),
            (After => 0, Maximum => 1), null, Ada.Real_Time.Time_Last,
            Page, Result);
         Require
           (Result = Success
            and then Page.Parts.Length = 1
            and then Page.Parts.First_Element.Number = 1
            and then Page.Parts.First_Element.Info = Prior,
            Label & " rejected boundary attempt changed the prior part");
      end;

      Store.Abort_Multipart_Upload
        (Bucket, "global-part-boundary", US.To_String (Upload_ID),
         No_Abort_Multipart_Conditions, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Success, Label & " boundary upload cleanup failed");
   end Exercise_Global_Size_Boundary;

end Multipart_Part_Conformance;
