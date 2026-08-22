with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;

package Object_Tagging_Race_Conformance is

   procedure Exercise
     (Store         : aliased in out
        Flyology.Object_Storage.Backends.Backend'Class;
      Bucket        : String;
      Key           : String;
      Expected_Tags : Flyology.Object_Storage.Object_Tag_Set;
      Iterations    : Positive := 32);

end Object_Tagging_Race_Conformance;
