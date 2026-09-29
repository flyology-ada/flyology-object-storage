with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;

--  Local helpers for the SQLite reproduction programs: a one-shot buffered
--  Byte_Source, a collecting Byte_Sink, a collecting Annotation_Byte_Sink,
--  and a fresh scratch root.  Deliberately self-contained so that nothing
--  under tests/src or sqlite/tests/src has to change.
package Repro_SQLite_Support is

   package US renames Ada.Strings.Unbounded;
   package OS renames Flyology.Object_Storage;
   package BE renames Flyology.Object_Storage.Backends;

   function Fresh_Root (Label : String) return String;
   --  Create (and return) a brand-new empty directory under the scratch
   --  area.  The name embeds Label, the process id and a counter.

   type Buffer_Source is limited new BE.Byte_Source with record
      Data     : US.Unbounded_String;
      Position : Natural := 0;
      Length   : BE.Source_Length := (Kind => BE.Unknown);
   end record;

   overriding function Declared_Length
     (Item : Buffer_Source) return BE.Source_Length is (Item.Length);

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   function Source_Of (Value : String) return Buffer_Source;

   type Buffer_Sink is limited new BE.Byte_Sink with record
      Data           : US.Unbounded_String;
      Begin_Count    : Natural := 0;
      First          : OS.Byte_Count := 0;
      Content_Length : OS.Byte_Count := 0;
      Partial        : Boolean := False;
      Snapshot       : OS.Object_Information;
   end record;

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : OS.Object_Information;
      First          : OS.Byte_Count;
      Content_Length : OS.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   type Annotation_Sink is limited new BE.Annotation_Byte_Sink with record
      Data        : US.Unbounded_String;
      Begin_Count : Natural := 0;
      Info        : OS.Object_Annotation_Information :=
        (Size => 0, Modified => 0, others => <>);
   end record;

   overriding procedure Begin_Annotation
     (Item     : in out Annotation_Sink;
      Info     : OS.Object_Annotation_Information;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Annotation_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   function Image (Value : OS.Status) return String;

end Repro_SQLite_Support;
