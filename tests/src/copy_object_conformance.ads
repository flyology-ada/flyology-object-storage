with Flyology.Object_Storage.Backends;

--  Shared atomic CopyObject conformance for every bundled backend.
package Copy_Object_Conformance is

   procedure Exercise
     (Store           : in out
        Flyology.Object_Storage.Backends.Backend'Class;
      Bucket          : String;
      Race_Iterations : Positive := 16);

end Copy_Object_Conformance;
