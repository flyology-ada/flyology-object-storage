with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML_Writers;

package body
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Website_XML
is

   package US renames Ada.Strings.Unbounded;
   package XML renames Flyology.Object_Storage.S3.XML;
   package XML_Writers renames Flyology.Object_Storage.S3.XML_Writers;
   package Website renames Flyology.Object_Storage.S3.Website;

   --  These values are owned by the pinned Botocore payload declaration;
   --  changing either changes the serialized and signed request contract.
   Root_Name : constant String := "WebsiteConfiguration";
   Namespace_URI : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";

   function Protocol_Image
     (Value : Website.Protocol) return String is
     (case Value is
         when Website.HTTP  => "http",
         when Website.HTTPS => "https");

   procedure Write_Optional_String
     (Item  : in out XML_Writers.Writer;
      Name  : String;
      Value : Website.Optional_String) is
   begin
      if Value.Is_Set then
         XML_Writers.Text_Element (Item, Name, US.To_String (Value.Value));
      end if;
   end Write_Optional_String;

   procedure Write_Optional_Protocol
     (Item  : in out XML_Writers.Writer;
      Name  : String;
      Value : Website.Optional_Protocol) is
   begin
      if Value.Is_Set then
         XML_Writers.Text_Element (Item, Name, Protocol_Image (Value.Value));
      end if;
   end Write_Optional_Protocol;

   function Serialize
     (Value  : Website.Website_Configuration;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      if Value.Error.Is_Set and then US.Length (Value.Error.Key) = 0 then
         raise Website.Malformed_Website with
           "website ErrorDocument Key is required and nonempty";
      end if;
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document (Item, Root_Name, Namespace_URI);
      if Value.Error.Is_Set then
         XML_Writers.Start_Element (Item, "ErrorDocument");
         XML_Writers.Text_Element
           (Item, "Key", US.To_String (Value.Error.Key));
         XML_Writers.End_Element (Item, "ErrorDocument");
      end if;
      if Value.Index.Is_Set then
         XML_Writers.Start_Element (Item, "IndexDocument");
         XML_Writers.Text_Element
           (Item, "Suffix", US.To_String (Value.Index.Suffix));
         XML_Writers.End_Element (Item, "IndexDocument");
      end if;
      if Value.Redirect_All.Is_Set then
         XML_Writers.Start_Element (Item, "RedirectAllRequestsTo");
         XML_Writers.Text_Element
           (Item, "HostName", US.To_String (Value.Redirect_All.Host_Name));
         Write_Optional_Protocol
           (Item, "Protocol", Value.Redirect_All.Scheme);
         XML_Writers.End_Element (Item, "RedirectAllRequestsTo");
      end if;
      if Value.Routes.Is_Set then
         XML_Writers.Start_Element (Item, "RoutingRules");
         for Rule of Value.Routes.Rules loop
            XML_Writers.Start_Element (Item, "RoutingRule");
            if Rule.Condition.Is_Set then
               XML_Writers.Start_Element (Item, "Condition");
               Write_Optional_String
                 (Item, "HttpErrorCodeReturnedEquals",
                  Rule.Condition.HTTP_Error_Code);
               Write_Optional_String
                 (Item, "KeyPrefixEquals", Rule.Condition.Key_Prefix);
               XML_Writers.End_Element (Item, "Condition");
            end if;
            XML_Writers.Start_Element (Item, "Redirect");
            Write_Optional_String
              (Item, "HostName", Rule.Redirect.Host_Name);
            Write_Optional_String
              (Item, "HttpRedirectCode",
               Rule.Redirect.HTTP_Redirect_Code);
            Write_Optional_Protocol
              (Item, "Protocol", Rule.Redirect.Scheme);
            Write_Optional_String
              (Item, "ReplaceKeyPrefixWith",
               Rule.Redirect.Replace_Key_Prefix);
            Write_Optional_String
              (Item, "ReplaceKeyWith", Rule.Redirect.Replace_Key);
            XML_Writers.End_Element (Item, "Redirect");
            XML_Writers.End_Element (Item, "RoutingRule");
         end loop;
         XML_Writers.End_Element (Item, "RoutingRules");
      end if;
      return XML_Writers.Finish (Item, Root_Name);
   exception
      when XML_Writers.Encoding_Error =>
         raise Website.Malformed_Website with
           "website serialization violates caller limits";
   end Serialize;

end
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Website_XML;
