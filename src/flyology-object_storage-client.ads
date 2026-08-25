--  Root namespace for the model-driven S3 client and its handwritten
--  convenience operations. Concrete wire operations are added only together
--  with independent compatibility tests.
package Flyology.Object_Storage.Client is

   --  What is known about publication after a conditional mutation.
   --  Outcome_Unknown always requires read-only reconciliation before any
   --  caller-selected retry.
   --  @enum Published Complete validated success proves publication
   --  @enum Precondition_Failed Complete modeled response proves no mutation
   --  @enum Definitely_Not_Published Admission or modeled response proves no
   --     mutation
   --  @enum Outcome_Unknown Publication must be reconciled by a bound read
   --  @enum Cancelled_Before_Publication Cancellation preceded admission
   type Publication_Disposition is
     (Published,
      Precondition_Failed,
      Definitely_Not_Published,
      Outcome_Unknown,
      Cancelled_Before_Publication);

   --  Stable reason domain shared by composable provider results.
   --  @enum No_Failure Successful or conclusively failed condition
   --  @enum Authentication_Failed Modeled authentication rejection
   --  @enum Authorization_Failed Modeled authorization rejection
   --  @enum Invalid_Request Local or modeled service request rejection
   --  @enum Not_Found Modeled missing destination
   --  @enum Cancelled Caller cancellation completed its drain
   --  @enum Timed_Out Absolute exchange deadline expired
   --  @enum Client_Unavailable Client could not admit or continue work
   --  @enum Connection_Failed Resolution or connection establishment failed
   --  @enum Transport_Failed Established exchange transport failed
   --  @enum Request_Source_Failed Request source violated its contract
   --  @enum Response_Too_Large Bounded destination was too small
   --  @enum Unavailable_Or_Retryable Modeled transient service response
   --  @enum Corrupt_Or_Invalid_Response Response was not conclusive or valid
   type Failure_Reason is
     (No_Failure,
      Authentication_Failed,
      Authorization_Failed,
      Invalid_Request,
      Not_Found,
      Cancelled,
      Timed_Out,
      Client_Unavailable,
      Connection_Failed,
      Transport_Failed,
      Request_Source_Failed,
      Response_Too_Large,
      Unavailable_Or_Retryable,
      Corrupt_Or_Invalid_Response);

end Flyology.Object_Storage.Client;
