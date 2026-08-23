with Flyology.Object_Storage.Backends;

--  Strict backend-neutral object-version state-machine conformance.
package Versioned_Object_Conformance is

   procedure Exercise
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String);

end Versioned_Object_Conformance;
