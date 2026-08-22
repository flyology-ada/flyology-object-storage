with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Shared bounded ListObjects selection.  Backends feed committed objects in
--  any order; the builder retains only the smallest Maximum + 1 distinct
--  emitted items after prefix/delimiter projection.
package Flyology.Object_Storage.Backends.Listing is

   type Builder is limited private;

   procedure Initialize (Item : in out Builder; Options : List_Options);

   procedure Consider
     (Item : in out Builder; Key : String; Info : Object_Information);

   function Finish (Item : Builder) return List_Page;

private
   type Candidate is record
      Is_Prefix : Boolean := False;
      Key       : Ada.Strings.Unbounded.Unbounded_String;
      Info      : Object_Information;
   end record;

   package Candidate_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Candidate);

   type Builder is limited record
      Options    : List_Options;
      Candidates : Candidate_Vectors.Vector;
   end record;

end Flyology.Object_Storage.Backends.Listing;
