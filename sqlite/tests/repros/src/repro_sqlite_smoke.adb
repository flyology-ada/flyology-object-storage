--  Harness smoke test for the SQLite reproduction crate: open a store on a
--  fresh scratch root, create a bucket, PUT and GET a small object through
--  the Backends interface, then close the store by leaving its scope and
--  reopen it to confirm the publication survived.  Must PASS.
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with Repro_Support; use Repro_Support;
with Repro_SQLite_Support; use Repro_SQLite_Support;

procedure Repro_SQLite_Smoke is
   use type Flyology.Object_Storage.Status;
   package OSB renames Flyology.Object_Storage.Backends;
   package SQL_Backend renames Flyology.Object_Storage.Backends.SQLite;

   Root   : constant String := Fresh_Root ("smoke");
   Bucket : constant String := "smoke-bucket";
   Key    : constant String := "hello.txt";
   Body_Text : constant String := "hello sqlite";
   Never  : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;
begin
   Note ("root " & Root);
   declare
      Store  : SQL_Backend.Store := SQL_Backend.Open (Root);
      Result : Flyology.Object_Storage.Status;
   begin
      Note ("root directory " & SQL_Backend.Root_Directory (Store));
      Store.Create_Bucket (Bucket, null, Never, Result);
      Note ("Create_Bucket " & Image (Result));
      Check (Result = Flyology.Object_Storage.Success,
             "Create_Bucket succeeds on a fresh SQLite root");

      declare
         Source : Buffer_Source := Source_Of (Body_Text);
         Info   : Flyology.Object_Storage.Object_Information;
         Identity : OSB.Version_Identity;
      begin
         Store.Put_Object
           (Bucket, Key, Source, Flyology.Object_Storage.Default_Put_Options,
            null, Never, Info, Identity, Result);
         Note ("Put_Object " & Image (Result) &
               " size " & Image_64 (Long_Long_Integer (Info.Size)) &
               " etag " & Ada.Strings.Unbounded.To_String (Info.Entity_Tag));
         Check (Result = Flyology.Object_Storage.Success,
                "Put_Object succeeds");
         Check (Info.Size = Body_Text'Length,
                "Put_Object reports the streamed size");
      end;

      declare
         Sink : Buffer_Sink;
         Info : Flyology.Object_Storage.Object_Information;
      begin
         Store.Get_Object
           (Bucket, Key, Flyology.Object_Storage.Whole_Object, Sink,
            null, Never, Info, Result);
         Note ("Get_Object " & Image (Result) &
               " bytes " & Image (Ada.Strings.Unbounded.Length (Sink.Data)));
         Check (Result = Flyology.Object_Storage.Success,
                "Get_Object succeeds");
         Check (Ada.Strings.Unbounded.To_String (Sink.Data) = Body_Text,
                "Get_Object round-trips the body");
         Check (Sink.Begin_Count = 1, "Get_Object calls Begin_Object once");
      end;
   end;
   Note ("store closed (scope exit)");

   declare
      Store  : SQL_Backend.Store := SQL_Backend.Open (Root);
      Result : Flyology.Object_Storage.Status;
      Sink   : Buffer_Sink;
      Info   : Flyology.Object_Storage.Object_Information;
   begin
      Store.Get_Object
        (Bucket, Key, Flyology.Object_Storage.Whole_Object, Sink,
         null, Never, Info, Result);
      Note ("reopened Get_Object " & Image (Result));
      Check (Result = Flyology.Object_Storage.Success,
             "the object survives close and reopen");
      Check (Ada.Strings.Unbounded.To_String (Sink.Data) = Body_Text,
             "the reopened body matches");
   end;
   Finish;
end Repro_SQLite_Smoke;
