# Proof Status: Flyology.Object_Storage validation core
<!-- Reflect the top-level goal given. Items in the list below are moved from
     Not Started to In Progress to Reviewed and finally to Proved and Finalized. -->

The latest post-GetObject-conditional-hardening forced six-unit manifest-wide level-0
proof completed with 405/405 checks proved, warnings as errors, zero justified
checks, and zero Assume statements.

## Proved and Finalized
<!-- Before marking an item complete here, follow the Widen Scope step
     (Strategic Loop Step 5) in workflow.md in the /gnatprove Skill. -->

- [x] Flyology.Object_Storage validation and range domain (level 0, all)
  - [x] Starts_With
  - [x] Ends_With
  - [x] Looks_Like_IPv4
  - [x] Valid_Bucket_Name
  - [x] Valid_Object_Key
  - [x] Resolve_Range (23 attributed prover checks)
- [x] Flyology.Object_Storage.S3.Core (level 0, all)
  - [x] Can_Transition
  - [x] Valid_Part_Size
  - [x] Valid_Multipart_Part_Size
  - [x] Multipart_Part_Count
  - [x] Valid_Multipart_Plan
  - [x] Valid_Completion_Order
  - [x] Valid_Consecutive_Completion_Order
  - [x] Parse_Range_Header
  - [x] Compatibility rename of the shared Resolve_Range
- [x] Flyology.Object_Storage.S3.Model (level 0, all; generated descriptor)
  - [x] 116 operation identities and REST traits
  - [x] 718 shape identities and scalar/container traits
  - [x] structure members, locations, requirements, and XML traits
  - [x] enumerations, errors, checksums, and authentication traits
- [x] Flyology.Object_Storage.S3.Wire_Core (level 0, all; 35 checks)
  - [x] Parse_Natural
  - [x] Parse_Byte_Count
  - [x] Parse_Boolean
  - [x] Valid_Base64
- [x] Flyology.Object_Storage.S3.Requests
      (level 0, all; 82 attributed prover checks)
  - [x] Character_At
  - [x] Is_Hex
  - [x] Hex_Value
  - [x] Valid_Escapes
  - [x] Decode
  - [x] Parse_Target
  - [x] Bucket_Name
  - [x] Object_Key
  - [x] Query_String
- [x] Flyology.Object_Storage.S3.SigV4_Encoding (level 0, all)
  - [x] URI_Encode
  - [x] Lowercase
  - [x] Normalize_Header_Value
  - [x] Valid_Timestamp
  - [x] validation helpers

## Reviewed
<!-- Review proved implementations for proof-antipatterns before moving them. -->

## In Progress
<!-- A proof worker executes the tactical loop for the item below. -->

## Not Started
<!-- New or discovered proof-bearing subprograms belong here. -->

- [ ] None

## Discovered Obligations

- [x] Proved the bounded escape cursor invariant and increasing variant.
- [x] Re-verified the `Valid_Escapes` caller after adding its bounded-domain
      precondition.
- [x] Proved the decode cursor, output-length, and initialized-prefix
      invariants and increasing variant.
- [x] Proved the query-marker processed-prefix invariant.
- [x] Proved defensive query-slice ordering and overflow-safe rebased indexes.
- [x] Proved `Character_At` with its exact offset-domain contract and
      re-verified every caller.
- [x] Proved the leading-whitespace loop invariant and increasing variant.
- [x] Proved the trailing-whitespace loop invariant and decreasing variant.
- [x] Proved the hyphen-position loop invariant.
- [x] Re-proved callers after helper numeric changes.
- [x] Widened to the entire unit with a forced level-0 run.
- [x] Proved the S3 core rules in a warnings-as-errors unit run; the recorded
      combined report contains 51/51 proved checks and zero assumptions.
- [x] Widened the forced proof manifest to SigV4 byte canonicalization; the
      authoritative `obj/proof/gnatprove/gnatprove.out` report contains
      118/118 proved checks and zero justified or assumed checks.
- [x] Isolated proof from XML/Ada's aggregate GPR while retaining the
      registry-resolved Flyology parent project.
- [x] Widened the forced manifest to attacker-controlled wire scalar parsing;
      the authoritative report now includes canonical fixed-length base64
      checksum validation.
- [x] Re-proved the forced manifest after adding the checksummed multipart
      consecutive-order rule; the authoritative report contains 161/161
      proved checks.
- [x] Added the pinned generated S3 model to the forced manifest after a
      scoped run, reviewed it for proof suppressions and assumptions, then
      widened to 202/202 proved checks with zero justified or assumed checks.
- [x] Re-widened the forced manifest after the semantic `Valid_Timestamp`
      implementation.
- [x] Re-widened the forced manifest after adding `Parse_Range_Header`.
- [x] Re-widened the forced manifest after adding
      `Flyology.Object_Storage.S3.Requests`.
- [x] Completed the six-unit warnings-as-errors widening with 399/399 checks,
      zero justified checks, and zero Assume statements.
- [x] Re-proved the shared atomic-snapshot `Resolve_Range` after moving its
      implementation from S3.Core to Flyology.Object_Storage, then completed
      a post-refactor 399/399 six-unit widening.
- [x] Proved overflow-safe automatic multipart part counting and plan
      validation, then completed a warnings-as-errors 405/405 six-unit
      widening with no assumptions or justified checks.
- [x] Re-ran the forced six-unit manifest after strict DeleteObject parsing,
      shared status widening, and atomic absent-bucket classification; all
      405/405 checks remain proved with no assumptions or justified checks.
- [x] Re-ran the forced six-unit manifest after ListBuckets presence and token
      bounds, high-level pagination, and response-fidelity hardening; all
      405/405 checks remain proved with no assumptions or justified checks.
- [x] Re-ran the forced six-unit manifest after strict authenticated
      HeadObject query routing; all 405/405 checks remain proved with no
      assumptions or justified checks.
- [x] Re-ran the forced six-unit manifest after HeadObject conditional,
      expected-owner, encryption-policy, and range hardening; all 405/405
      checks remain proved with no assumptions or justified checks.
- [x] Re-ran the forced six-unit manifest after atomic GetObject conditions,
      strict response-interval validation, and high-level ranged downloads;
      all 405/405 checks remain proved with no assumptions or justified checks.
