with Flyology.Object_Storage.Backends;

package Multipart_Part_Conformance is

   procedure Exercise_Global_Size_Boundary
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String;
      Label  : String);
   --  Prove the exact 5 GiB declaration reaches the source while 5 GiB+1 is
   --  rejected before source admission, without materializing either body.

   function Ordinary_File_Count (Directory : String) return Natural;
   --  Return the number of ordinary files immediately below Directory.

end Multipart_Part_Conformance;
