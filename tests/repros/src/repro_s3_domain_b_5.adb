--  S3-DOMAIN-B-5: Attributes.Valid_Storage_Class hard-codes thirteen storage
--  classes.  The pinned model's StorageClass enumeration has fifteen: the two
--  AWS Backup classes are missing, so a valid GetObjectAttributes response
--  carrying AWS_BACKUP_WARM or AWS_BACKUP_LOW_COST_WARM is rejected as
--  Malformed_Attributes and every typed client reports Invalid_Response
--  ("malformed GetObjectAttributes response").  This program prints the
--  model's enumeration, then decodes such a response through the same
--  client entry point the convenience clients use.
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Model;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_B_5 is

   package Attributes renames Flyology.Object_Storage.S3.Attributes;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Model renames Flyology.Object_Storage.S3.Model;
   package US renames Ada.Strings.Unbounded;

   function Response_Body (Storage_Class : String) return String is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<GetObjectAttributesResponse " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<ETag>""9a0364b9e99bb480dd25e1f0284c8555""</ETag>" &
      "<StorageClass>" & Storage_Class & "</StorageClass>" &
      "<ObjectSize>7</ObjectSize>" &
      "</GetObjectAttributesResponse>");

   procedure Decode (Storage_Class : String; Must_Work : Boolean) is
      Payload : constant String := Response_Body (Storage_Class);
   begin
      begin
         declare
            Parsed : constant Attributes.Get_Object_Attributes_Result :=
              Attributes.Parse_Result (Payload);
         begin
            Note ("  S3.Attributes.Parse_Result: accepted, StorageClass=[" &
                  US.To_String (Parsed.Storage_Class) & "]");
         end;
      exception
         when Error : others =>
            Note ("  S3.Attributes.Parse_Result: " &
                  Ada.Exceptions.Exception_Name (Error) & ": " &
                  Ada.Exceptions.Exception_Message (Error));
      end;
      begin
         declare
            Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
              Low_Level.Decode_Get_Object_Attributes_Response
                (Status => 200, Payload => Payload);
         begin
            Note ("  Client.Low_Level: accepted, kind=" &
                  Low_Level.Get_Object_Attributes_Outcome_Kind'Image
                    (Outcome.Kind));
            if Must_Work then
               Check (True, "client decodes StorageClass " & Storage_Class);
            end if;
         end;
      exception
         when Error : others =>
            Note ("  Client.Low_Level: " &
                  Ada.Exceptions.Exception_Name (Error) & ": " &
                  Ada.Exceptions.Exception_Message (Error));
            if Must_Work then
               Check (False, "client decodes StorageClass " & Storage_Class);
            end if;
      end;
   end Decode;

begin
   Note ("=== the pinned model's StorageClass enumeration ===");
   declare
      Output : constant Model.Shape_Reference :=
        Model.Output_Shape (Model.Get_Object_Attributes_Operation);
      Enum   : Model.Shape_Reference := Model.No_Shape;
   begin
      Check (Output /= Model.No_Shape,
             "control: the model has a GetObjectAttributes output shape");
      for Member in 1 .. Model.Member_Count (Output) loop
         if Model.Member_Name (Output, Member) = "StorageClass" then
            Enum := Model.Member_Shape (Output, Member);
         end if;
      end loop;
      Check (Enum /= Model.No_Shape,
             "control: the output shape has a StorageClass member");
      Note ("model StorageClass values (" &
            Image (Model.Enumeration_Count (Enum)) & "):");
      for Index in 1 .. Model.Enumeration_Count (Enum) loop
         Note ("    " & Model.Enumeration_Value (Enum, Index));
      end loop;
   end;

   Note ("");
   Note ("=== control: a class the codec knows ===");
   Note ("STANDARD");
   Decode ("STANDARD", False);
   Note ("GLACIER_IR");
   Decode ("GLACIER_IR", False);

   Note ("");
   Note ("=== the two modeled classes the codec does not know ===");
   Note ("AWS_BACKUP_WARM");
   Decode ("AWS_BACKUP_WARM", True);
   Note ("AWS_BACKUP_LOW_COST_WARM");
   Decode ("AWS_BACKUP_LOW_COST_WARM", True);

   Finish;
end Repro_S3_Domain_B_5;
