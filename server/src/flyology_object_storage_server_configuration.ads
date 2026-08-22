with Ada.Strings.Unbounded;
with Flyology.IO.Sockets;

package Flyology_Object_Storage_Server_Configuration is

   type Backend_Kind is (Memory, Files, SQLite);
   subtype Server_Capacity is Positive range 1 .. 4_096;

   type Settings is record
      Backend      : Backend_Kind := Memory;
      Storage_Root : Ada.Strings.Unbounded.Unbounded_String;
      Admin_Credentials_Path : Ada.Strings.Unbounded.Unbounded_String;
      S3_Address   : Flyology.IO.Sockets.IP_Address :=
        Flyology.IO.Sockets.Loopback_IPv4;
      S3_Port      : Flyology.IO.Sockets.Port := 9_000;
      Admin_Port   : Flyology.IO.Sockets.Port := 9_001;
      Capacity     : Server_Capacity := 128;
   end record;

   --  Read and validate the server environment. With no overrides, the
   --  server starts a loopback-only memory store and bootstraps credentials.
   --  Files and SQLite require an explicit storage root.
   function Load return Settings;

   function Image (Value : Backend_Kind) return String;

end Flyology_Object_Storage_Server_Configuration;
