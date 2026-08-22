--  SQLite-backed catalog add-on. Object payloads remain external files; the
--  database provides transactional namespace, metadata, multipart, and
--  version state.
package Flyology.Object_Storage.SQLite is

   function SQLite_Version return String;
   function SQLite_Source_ID return String;
   function SQLite_Threadsafe return Boolean;

end Flyology.Object_Storage.SQLite;
