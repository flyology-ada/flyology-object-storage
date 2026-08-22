with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Shared bounded selection for ListMultipartUploads. Backends feed active
--  uploads in any order while holding their snapshot gate.
package Flyology.Object_Storage.Backends.Multipart_Listing is

   type Builder is limited private;

   procedure Initialize
     (Item : in out Builder; Options : List_Multipart_Uploads_Options);

   procedure Consider
     (Item      : in out Builder;
      Key       : String;
      Upload_ID : String;
      Initiated : Unix_Time;
      Options   : Multipart_Options);

   function Finish (Item : Builder) return Multipart_Upload_Page;

private
   type Candidate is record
      Is_Prefix : Boolean := False;
      Key       : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
      Initiated : Unix_Time := 0;
      Options   : Multipart_Options;
   end record;

   package Candidate_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Candidate);

   type Builder is limited record
      Options    : List_Multipart_Uploads_Options;
      Candidates : Candidate_Vectors.Vector;
   end record;

end Flyology.Object_Storage.Backends.Multipart_Listing;
