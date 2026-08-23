with Flyology.Object_Storage.Backends;

--  Shared atomic conditional-Put conformance for every bundled backend.
package Conditional_Put_Conformance is

   procedure Exercise
     (Store           : in out
        Flyology.Object_Storage.Backends.Backend'Class;
      Bucket          : String;
      Race_Iterations : Positive := 32);

   --  Re-read the final complete PutObject tuple left by Exercise. Files and
   --  SQLite call this after reopening their durable stores.
   procedure Verify_Tuple
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String);

end Conditional_Put_Conformance;
