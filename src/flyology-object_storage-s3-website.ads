with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 bucket website configuration reads.
package Flyology.Object_Storage.S3.Website is

   --  Raised when a document violates the pinned website model.
   Malformed_Website : exception;

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text when present
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Exact pinned Protocol wire domain.
   --  @enum HTTP Exact lowercase http wire value
   --  @enum HTTPS Exact lowercase https wire value
   type Protocol is (HTTP, HTTPS);

   --  Presence-preserving optional protocol.
   --  @field Is_Set Whether Protocol was present
   --  @field Value Exact protocol when present
   type Optional_Protocol is record
      Is_Set : Boolean;
      Value  : Protocol;
   end record;

   --  Optional whole-site redirect. HostName is required when present.
   --  @field Is_Set Whether RedirectAllRequestsTo was present
   --  @field Host_Name Required exact target host when present
   --  @field Scheme Optional exact redirect protocol
   type Redirect_All_Requests is record
      Is_Set    : Boolean;
      Host_Name : Ada.Strings.Unbounded.Unbounded_String;
      Scheme    : Optional_Protocol;
   end record;

   --  Optional index document. Suffix is required when present.
   --  @field Is_Set Whether IndexDocument was present
   --  @field Suffix Required exact suffix when present
   type Index_Document is record
      Is_Set : Boolean;
      Suffix : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional error document. Key is required and nonempty when present.
   --  @field Is_Set Whether ErrorDocument was present
   --  @field Key Required exact nonempty object key when present
   type Error_Document is record
      Is_Set : Boolean;
      Key    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional routing condition. Its modeled members are independent.
   --  @field Is_Set Whether Condition was present
   --  @field HTTP_Error_Code Optional exact HTTP error code text
   --  @field Key_Prefix Optional exact key prefix
   type Routing_Condition is record
      Is_Set          : Boolean;
      HTTP_Error_Code : Optional_String;
      Key_Prefix      : Optional_String;
   end record;

   --  Required redirect within one routing rule. All modeled members are
   --  independently optional in the pinned structural model.
   --  @field Host_Name Optional exact target host
   --  @field HTTP_Redirect_Code Optional exact redirect code text
   --  @field Scheme Optional exact redirect protocol
   --  @field Replace_Key_Prefix Optional replacement prefix
   --  @field Replace_Key Optional replacement key
   type Routing_Redirect is record
      Host_Name          : Optional_String;
      HTTP_Redirect_Code : Optional_String;
      Scheme             : Optional_Protocol;
      Replace_Key_Prefix : Optional_String;
      Replace_Key        : Optional_String;
   end record;

   --  One ordered routing rule.
   --  @field Condition Optional complete routing condition
   --  @field Redirect Required complete redirect
   type Routing_Rule is record
      Condition : Routing_Condition;
      Redirect  : Routing_Redirect;
   end record;

   --  Ordered RoutingRule values bounded by caller-selected XML limits.
   package Routing_Rule_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Routing_Rule);

   --  Presence-preserving optional nonflattened RoutingRules list.
   --  @field Is_Set Whether RoutingRules was present
   --  @field Rules Exact rules in wire order
   type Routing_Rules is record
      Is_Set : Boolean;
      Rules  : Routing_Rule_Vectors.Vector;
   end record;

   --  Complete presence-preserving GetBucketWebsite payload. The pinned
   --  structural model does not encode the documented top-level one-of rule,
   --  so members remain independently represented.
   --  @field Redirect_All Optional whole-site redirect
   --  @field Index Optional index document
   --  @field Error Optional error document
   --  @field Routes Optional ordered routing rules
   type Website_Configuration is record
      Redirect_All : Redirect_All_Requests;
      Index        : Index_Document;
      Error        : Error_Document;
      Routes       : Routing_Rules;
   end record;

   --  Parse one exact nonempty GetBucketWebsite payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving website configuration
   --  @exception Malformed_Website Document violates the pinned model
   function Parse
     (Document : String; Limits : S3.XML.Parse_Limits)
      return Website_Configuration;

end Flyology.Object_Storage.S3.Website;
