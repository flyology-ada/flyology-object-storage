with Interfaces.C;
with Interfaces.C.Strings;
with Flyology.Object_Storage.SQLite.C;

package body Flyology.Object_Storage.SQLite is

   use type Interfaces.C.int;

   function SQLite_Version return String is
     (Interfaces.C.Strings.Value
        (Flyology.Object_Storage.SQLite.C.Libversion));

   function SQLite_Source_ID return String is
     (Interfaces.C.Strings.Value
        (Flyology.Object_Storage.SQLite.C.Source_ID));

   function SQLite_Threadsafe return Boolean is
     (Flyology.Object_Storage.SQLite.C.Threadsafe /= 0);

end Flyology.Object_Storage.SQLite;
