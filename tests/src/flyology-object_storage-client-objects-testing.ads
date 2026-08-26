with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;

--  Strict implementation oracles for objects composable result mappings.
package Flyology.Object_Storage.Client.Objects.Testing is

   procedure Check_Put_Certainty_Corpus;

   procedure Check_Delete_Certainty_Corpus;

   procedure Check_Delete_Objects_Certainty_Corpus;

   procedure Check_List_Objects_Result_Corpus;

   procedure Check_Object_Tagging_Certainty_Corpus;

   procedure Check_Legal_Hold_Certainty_Corpus;

   procedure Check_Legal_Hold_Pre_Admission_Rejection
     (Client   : not null access Flyology.HTTP.Client.Client;
      Prepared : Flyology.Object_Storage.Client.Low_Level.Prepared_Request;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline);

   procedure Set_Response_Limit
     (Operation : in out Get_Legal_Hold_Operation;
      Maximum   : Natural);

   procedure Set_Response_Limit
     (Operation : in out Put_Legal_Hold_Operation;
      Maximum   : Natural);

end Flyology.Object_Storage.Client.Objects.Testing;
