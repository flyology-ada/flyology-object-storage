with Flyology.Buffers;
with Flyology.Cancellation;
with Flyology.HTTP.Client;

--  Bridges prepared S3 requests into caller-owned composable HTTP exchanges.
package Flyology.Object_Storage.Client.Low_Level.Scoped is

   --  Release all owned request, signing, selector, and header storage from a
   --  prepared request after its HTTP child has drained. This is an internal
   --  lifecycle boundary for composable parents; callers must not clear a
   --  request while an exchange still borrows it.
   --  @param Prepared Drained request whose retained storage is released
   procedure Clear_Prepared_Request (Prepared : in out Prepared_Request);

   --  @exclude
   --  Return the owned one-shot mutation body retained by Prepared. These
   --  accessors exist only for a parent operation that owns Prepared through
   --  terminal drain.
   --  @param Prepared Prepared request whose payload remains owned
   --  @return Number of retained request-body bytes
   function Owned_Payload_Length
     (Prepared : Prepared_Request) return Natural;

   --  @exclude
   --  @param Prepared Prepared request whose payload remains owned
   --  @param Index One-based byte index
   --  @return Exact retained request-body byte
   function Owned_Payload_Element
     (Prepared : Prepared_Request;
      Index    : Positive) return Character;

   --  Start a prepared PutObject exchange with a nonblocking source and a
   --  bounded immediate response sink. Prepared, Source, Sink, Client, Token,
   --  and their owners must outlive terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared PutObject request
   --  @param Source Nonblocking complete-object source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not PutObject
   procedure Start_Put_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared GetObject exchange into an acquired caller buffer.
   --  Typed HTTP Finish restores the exact buffer token on every outcome.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared GetObject request
   --  @param Destination Acquired bounded response buffer
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not GetObject
   procedure Start_Get_Object
     (Operation   : in out Flyology.HTTP.Client.Exchange_Operation;
      Client      : not null access Flyology.HTTP.Client.Client;
      Prepared    : not null access constant Prepared_Request;
      Destination : in out Flyology.Buffers.Unique_Buffer;
      Deadline    : Flyology.HTTP.Client.Monotonic_Deadline;
      Token       : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Start a prepared ListObjects v1 exchange into a bounded response sink.
   --  Prepared, Sink, Client, Token, and their owners must outlive terminal
   --  typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared ListObjects v1 request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not ListObjects v1
   procedure Start_List_Objects
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared service-level ListBuckets exchange into a bounded
   --  response sink. Prepared, Sink, Client, Token, and their owners must
   --  outlive terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared ListBuckets request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not ListBuckets
   procedure Start_List_Buckets
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared CreateBucket exchange with a nonblocking one-shot XML
   --  source and bounded response sink. Prepared, Source, Sink, Client, Token,
   --  and their owners must outlive terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared CreateBucket request
   --  @param Source Nonblocking one-shot serialized configuration source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not CreateBucket
   procedure Start_Create_Bucket
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared bodyless HeadBucket exchange into a response sink.
   --  Prepared, Sink, Client, Token, and their owners must outlive terminal
   --  typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared HeadBucket request
   --  @param Sink Bodyless complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not HeadBucket
   procedure Start_Head_Bucket
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared ListObjectsV2 exchange into a bounded response sink.
   --  Prepared, Sink, Client, Token, and their owners must outlive terminal
   --  typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared ListObjectsV2 request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not ListObjectsV2
   procedure Start_List_Objects_V2
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared ListObjectVersions exchange into a bounded sink.
   --  Prepared, Sink, Client, Token, and their owners must outlive terminal
   --  typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared ListObjectVersions request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not ListObjectVersions
   procedure Start_List_Object_Versions
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared GetObjectAttributes exchange into a bounded sink.
   --  Prepared, Sink, Client, Token, and their owners must outlive terminal
   --  typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared GetObjectAttributes request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not GetObjectAttributes
   procedure Start_Get_Object_Attributes
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared HeadObject exchange into a bounded immediate sink.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared HeadObject request
   --  @param Sink Bounded response sink used to reject nonempty HEAD bodies
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not HeadObject
   procedure Start_Head_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared DeleteObject exchange with a deliberately
   --  non-replayable empty source and a bounded immediate response sink.
   --  Prepared, Source, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared DeleteObject request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not DeleteObject
   procedure Start_Delete_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared DeleteObjects exchange with a nonblocking one-shot
   --  XML source and a bounded response sink. Prepared, Source, Sink, Client,
   --  Token, and their owners must outlive terminal typed Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared DeleteObjects request
   --  @param Source Nonblocking one-shot serialized batch source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not DeleteObjects
   procedure Start_Delete_Objects
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared CreateMultipartUpload exchange with a deliberately
   --  non-replayable empty source and a bounded immediate response sink.
   --  Prepared, Source, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared CreateMultipartUpload request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not CreateMultipartUpload
   procedure Start_Create_Multipart_Upload
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared CompleteMultipartUpload exchange with a nonblocking
   --  one-shot source and bounded response sink. Prepared, Source, Sink,
   --  Client, Token, and their owners must outlive terminal typed Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared CompleteMultipartUpload request
   --  @param Source Nonblocking one-shot completion XML source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not CompleteMultipartUpload
   procedure Start_Complete_Multipart_Upload
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared AbortMultipartUpload exchange with a nonblocking
   --  one-shot empty source and bounded response sink. Prepared, Source,
   --  Sink, Client, Token, and their owners must outlive terminal Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared AbortMultipartUpload request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not AbortMultipartUpload
   procedure Start_Abort_Multipart_Upload
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared ListParts exchange into a bounded response sink.
   --  Prepared, Sink, Client, Token, and their owners must outlive terminal
   --  typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared ListParts request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not ListParts
   procedure Start_List_Parts
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared ListMultipartUploads exchange into a bounded response
   --  sink. Prepared, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared ListMultipartUploads request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not ListMultipartUploads
   procedure Start_List_Multipart_Uploads
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared CopyObject exchange with a nonblocking one-shot empty
   --  source and bounded response sink. Prepared, Source, Sink, Client,
   --  Token, and their owners must outlive terminal typed Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared CopyObject request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not CopyObject
   procedure Start_Copy_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared UploadPartCopy exchange with a nonblocking one-shot
   --  empty source and bounded response sink. Prepared, Source, Sink, Client,
   --  Token, and their owners must outlive terminal typed Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared UploadPartCopy request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not UploadPartCopy
   procedure Start_Upload_Part_Copy
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared UploadPart exchange with a nonblocking one-shot source
   --  and bounded immediate response sink. Prepared, Source, Sink, Client,
   --  Token, and their owners must outlive terminal typed Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared UploadPart request
   --  @param Source Nonblocking one-shot part body source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not UploadPart
   procedure Start_Upload_Part
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared PutBucketTagging exchange with the owned one-shot XML
   --  source retained by Prepared and a bounded response sink. Prepared,
   --  Source, Sink, Client, Token, and their owners must outlive Finish.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared PutBucketTagging request
   --  @param Source Nonblocking one-shot serialized tag source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not PutBucketTagging
   procedure Start_Put_Bucket_Tagging
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared GetBucketTagging exchange into a bounded response
   --  sink. Prepared, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared GetBucketTagging request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not GetBucketTagging
   procedure Start_Get_Bucket_Tagging
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared DeleteBucketTagging exchange with a nonreplayable
   --  empty source and bounded response sink.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared DeleteBucketTagging request
   --  @param Source Nonblocking one-shot empty source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not DeleteBucketTagging
   procedure Start_Delete_Bucket_Tagging
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start prepared PutObjectTagging with an owned one-shot XML source.
   --  Prepared, Source, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared PutObjectTagging request
   --  @param Source Nonblocking one-shot serialized tag source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not PutObjectTagging
   procedure Start_Put_Object_Tagging
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start prepared GetObjectTagging into a bounded response sink.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared GetObjectTagging request
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not GetObjectTagging
   procedure Start_Get_Object_Tagging
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start prepared DeleteObjectTagging with a nonreplayable empty source.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared DeleteObjectTagging request
   --  @param Source Nonblocking one-shot empty source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not DeleteObjectTagging
   procedure Start_Delete_Object_Tagging
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

end Flyology.Object_Storage.Client.Low_Level.Scoped;
