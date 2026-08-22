with Flyology.Object_Storage.Backends;

--  Shared atomic conditional-Put conformance for every bundled backend.
package Conditional_Put_Conformance is

   procedure Exercise
     (Store           : in out
        Flyology.Object_Storage.Backends.Backend'Class;
      Bucket          : String;
      Race_Iterations : Positive := 32);

end Conditional_Put_Conformance;
