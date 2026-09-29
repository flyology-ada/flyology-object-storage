with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;

--  Shared helpers for the BACKEND-MEMORY reproduction programs: a
--  string-backed Byte_Source, a collecting Byte_Sink, and a wall-clock
--  helper that waits until the backend's one-second Unix timestamp
--  (Ada.Calendar.Clock - Epoch, memory.adb:207) is guaranteed to advance.
package Repro_Backend_Memory_Support is

   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package US renames Ada.Strings.Unbounded;

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

   procedure Advance_One_Second;
   --  Block until the backend's whole-second Unix timestamp has changed.

   function Backend_Unix_Time return Storage.Unix_Time;
   --  The same value the memory backend stamps on a new upload.

end Repro_Backend_Memory_Support;
