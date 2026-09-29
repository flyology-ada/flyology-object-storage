with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;

--  Shared helpers for the BACKEND-FILES reproduction programs: a fresh
--  scratch root per run, a string-backed Byte_Source, and sinks that collect
--  an object or annotation payload in memory.
package Repro_Backend_Files_Support is

   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package US renames Ada.Strings.Unbounded;

   function Make_Root (Label : String) return String;
   --  Create and return a fresh empty directory under the scratch area.

   procedure Drop_Root (Path : String);
   --  Remove the tree created by Make_Root; silently ignores failures.

   --  One-shot source over a String payload.
   type String_Source (Length : Natural) is limited new Backends.Byte_Source
   with record
      Payload : String (1 .. Length);
      Sent    : Natural := 0;
   end record;

   overriding function Declared_Length
     (Item : String_Source) return Backends.Source_Length;

   overriding procedure Read
     (Item     : in out String_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   function Source_Of (Payload : String) return String_Source;

   --  Collecting object sink.
   type Collecting_Sink is limited new Backends.Byte_Sink with record
      Data    : US.Unbounded_String;
      Started : Boolean := False;
      Info    : Storage.Object_Information;
   end record;

   overriding procedure Begin_Object
     (Item           : in out Collecting_Sink;
      Info           : Storage.Object_Information;
      First          : Storage.Byte_Count;
      Content_Length : Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Collecting_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   --  Collecting annotation sink.
   type Collecting_Annotation_Sink is limited new
     Backends.Annotation_Byte_Sink with record
      Data    : US.Unbounded_String;
      Started : Boolean := False;
   end record;

   overriding procedure Begin_Annotation
     (Item     : in out Collecting_Annotation_Sink;
      Info     : Storage.Object_Annotation_Information;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Collecting_Annotation_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   function Directory_Exists (Path : String) return Boolean;

   function Count_Generation_Directories (Path : String) return Natural;
   --  Directories named "generation-*" anywhere under Path (recursive);
   --  0 when Path does not exist.

end Repro_Backend_Files_Support;
