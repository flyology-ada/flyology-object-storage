with Ada.Containers.Vectors;

--  Shared bounded bucket selection. Backends feed one atomic namespace
--  snapshot in any order; the builder retains the smallest Maximum + 1 names.
package Flyology.Object_Storage.Backends.Bucket_Listing is

   type Builder is limited private;

   procedure Initialize
     (Item : in out Builder; Options : List_Buckets_Options);

   procedure Consider
     (Item : in out Builder; Name : String; Created : Unix_Time);

   function Finish (Item : Builder) return Bucket_Page;

private
   package Candidate_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Bucket);

   type Builder is limited record
      Options    : List_Buckets_Options;
      Candidates : Candidate_Vectors.Vector;
   end record;

end Flyology.Object_Storage.Backends.Bucket_Listing;
