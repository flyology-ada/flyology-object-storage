with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for current S3 bucket-notification configurations.
package Flyology.Object_Storage.S3.Notifications is

   --  Raised when a document or value violates the pinned notification model.
   Malformed_Notification : exception;

   --  Exact pinned Event wire domain. These values come from the generated
   --  S3 model and determine provider-visible event selection compatibility.
   --  @enum Reduced_Redundancy_Lost_Object Reduced-redundancy object loss
   --  @enum Object_Created_All Every object-created event
   --  @enum Object_Created_Put Object created by PUT
   --  @enum Object_Created_Post Object created by POST
   --  @enum Object_Created_Copy Object created by COPY
   --  @enum Object_Created_Complete_Multipart_Upload Object created by a
   --     completed multipart upload
   --  @enum Object_Removed_All Every object-removed event
   --  @enum Object_Removed_Delete Object removed by DELETE
   --  @enum Object_Removed_Delete_Marker_Created Delete marker created
   --  @enum Object_Restore_All Every object-restore event
   --  @enum Object_Restore_Post Restore initiated
   --  @enum Object_Restore_Completed Restore completed
   --  @enum Replication_All Every replication event
   --  @enum Replication_Operation_Failed Replication failed
   --  @enum Replication_Operation_Not_Tracked Replication was not tracked
   --  @enum Replication_Operation_Missed_Threshold Replication exceeded its
   --     time threshold
   --  @enum Replication_Operation_Replicated_After_Threshold Replication
   --     completed after its time threshold
   --  @enum Object_Restore_Delete Restored copy expired
   --  @enum Lifecycle_Transition Lifecycle storage transition
   --  @enum Intelligent_Tiering Intelligent-tiering access transition
   --  @enum Object_ACL_Put Object ACL replaced
   --  @enum Lifecycle_Expiration_All Every lifecycle-expiration event
   --  @enum Lifecycle_Expiration_Delete Lifecycle object deletion
   --  @enum Lifecycle_Expiration_Delete_Marker_Created Lifecycle delete marker
   --     created
   --  @enum Object_Tagging_All Every object-tagging event
   --  @enum Object_Tagging_Put Object tags replaced
   --  @enum Object_Tagging_Delete Object tags deleted
   --  @enum Object_Annotation_All Every object-annotation event
   --  @enum Object_Annotation_Put Object annotations replaced
   --  @enum Object_Annotation_Delete Object annotations deleted
   type Event_Kind is
     (Reduced_Redundancy_Lost_Object,
      Object_Created_All,
      Object_Created_Put,
      Object_Created_Post,
      Object_Created_Copy,
      Object_Created_Complete_Multipart_Upload,
      Object_Removed_All,
      Object_Removed_Delete,
      Object_Removed_Delete_Marker_Created,
      Object_Restore_All,
      Object_Restore_Post,
      Object_Restore_Completed,
      Replication_All,
      Replication_Operation_Failed,
      Replication_Operation_Not_Tracked,
      Replication_Operation_Missed_Threshold,
      Replication_Operation_Replicated_After_Threshold,
      Object_Restore_Delete,
      Lifecycle_Transition,
      Intelligent_Tiering,
      Object_ACL_Put,
      Lifecycle_Expiration_All,
      Lifecycle_Expiration_Delete,
      Lifecycle_Expiration_Delete_Marker_Created,
      Object_Tagging_All,
      Object_Tagging_Put,
      Object_Tagging_Delete,
      Object_Annotation_All,
      Object_Annotation_Put,
      Object_Annotation_Delete);

   --  Exact pinned FilterRule Name wire domain.
   --  @enum Prefix_Filter Exact prefix wire value
   --  @enum Suffix_Filter Exact suffix wire value
   type Filter_Rule_Name is (Prefix_Filter, Suffix_Filter);

   --  Presence-preserving optional string. Empty text remains distinct from
   --  absence because the pinned string shapes establish no minimum length.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Dynamically sized event storage bounded by caller-selected XML limits.
   package Event_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Event_Kind);

   --  One FilterRule. Both members are optional in the pinned model.
   --  @field Name_Is_Set Whether Name was present
   --  @field Name Exact prefix/suffix value when present
   --  @field Value Optional exact filter value
   type Filter_Rule is record
      Name_Is_Set : Boolean;
      Name        : Filter_Rule_Name;
      Value       : Optional_String;
   end record;

   --  Dynamically sized filter-rule storage bounded by caller XML limits.
   package Filter_Rule_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Filter_Rule);

   --  Presence-preserving NotificationConfigurationFilter graph. Empty Filter
   --  and empty S3Key structures remain distinct from member absence.
   --  @field Is_Set Whether Filter was present
   --  @field Key_Is_Set Whether its S3Key structure was present
   --  @field Rules Flattened FilterRule values in wire order
   type Notification_Filter is record
      Is_Set     : Boolean;
      Key_Is_Set : Boolean;
      Rules      : Filter_Rule_Vectors.Vector;
   end record;

   --  One required topic destination and nonempty event list.
   --  @field ID Optional caller identifier
   --  @field Topic_ARN Required exact topic ARN text
   --  @field Events Required flattened events in wire order
   --  @field Filter Optional exact key filter
   type Topic_Configuration is record
      ID        : Optional_String;
      Topic_ARN : Ada.Strings.Unbounded.Unbounded_String;
      Events    : Event_Vectors.Vector;
      Filter    : Notification_Filter;
   end record;

   --  One required queue destination and nonempty event list.
   --  @field ID Optional caller identifier
   --  @field Queue_ARN Required exact queue ARN text
   --  @field Events Required flattened events in wire order
   --  @field Filter Optional exact key filter
   type Queue_Configuration is record
      ID        : Optional_String;
      Queue_ARN : Ada.Strings.Unbounded.Unbounded_String;
      Events    : Event_Vectors.Vector;
      Filter    : Notification_Filter;
   end record;

   --  One required Lambda destination and nonempty event list.
   --  @field ID Optional caller identifier
   --  @field Lambda_Function_ARN Required exact Lambda ARN text
   --  @field Events Required flattened events in wire order
   --  @field Filter Optional exact key filter
   type Lambda_Configuration is record
      ID                  : Optional_String;
      Lambda_Function_ARN : Ada.Strings.Unbounded.Unbounded_String;
      Events              : Event_Vectors.Vector;
      Filter              : Notification_Filter;
   end record;

   --  Dynamically sized topic destinations bounded by caller XML limits.
   package Topic_Configuration_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Topic_Configuration);
   --  Dynamically sized queue destinations bounded by caller XML limits.
   package Queue_Configuration_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Queue_Configuration);
   --  Dynamically sized Lambda destinations bounded by caller XML limits.
   package Lambda_Configuration_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Lambda_Configuration);

   --  Complete current NotificationConfiguration graph. An empty graph is the
   --  modeled notification-disabled configuration. EventBridge presence is an
   --  empty structure and therefore requires its own presence bit.
   --  @field Topics Flattened TopicConfiguration values in wire order
   --  @field Queues Flattened QueueConfiguration values in wire order
   --  @field Lambdas Flattened CloudFunctionConfiguration values in wire order
   --  @field Event_Bridge_Is_Set Whether EventBridgeConfiguration was present
   type Notification_Configuration is record
      Topics              : Topic_Configuration_Vectors.Vector;
      Queues              : Queue_Configuration_Vectors.Vector;
      Lambdas             : Lambda_Configuration_Vectors.Vector;
      Event_Bridge_Is_Set : Boolean;
   end record;

   --  Parse one exact GetBucketNotificationConfiguration response payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete current notification configuration
   --  @exception Malformed_Notification Document violates the pinned model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Notification_Configuration;

   --  Serialize one required PutBucketNotificationConfiguration payload.
   --  Empty configuration is valid and disables all notifications.
   --  @param Value Complete current notification configuration
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Notification Value violates the pinned model
   function Serialize
     (Value  : Notification_Configuration;
      Limits : XML.Parse_Limits) return String;

end Flyology.Object_Storage.S3.Notifications;
