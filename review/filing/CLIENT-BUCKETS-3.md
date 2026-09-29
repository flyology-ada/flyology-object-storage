Title: List_Page with a nonempty Prefix raises Invalid_Response against MinIO, which filters without echoing <Prefix>
Labels: bug, documentation
Refs: none

## Summary

The ListBuckets decoder requires a server that was sent `prefix=` to echo `<Prefix>` with the same presence and bytes, a rule written down in the ListBuckets qualification document. The pinned MinIO release filters correctly and does not echo the element, so `Client.Buckets.List_Page` with a nonempty `Prefix` raises `Low_Level.Invalid_Response` for a valid, correctly filtered page, and the parameter-record overload reports `Corrupt_Or_Invalid_Response`. MinIO is one of the servers the compatibility matrix claims for ListBuckets, no maintained document says the `Prefix` parameter does not work against it, and the diagnostic the caller gets names neither the prefix nor the server.

## Problem

Commit `5fe6e3e`.

The rule is enforced in the ListBuckets response check (`src/flyology-object_storage-client-low_level.adb:4139-4149`):

```ada
               if Natural (Page.Buckets.Length) >
                 Natural (Prepared.Requested_List_Buckets_Max)
                 or else
                   (if Prepared.Requested_List_Buckets_Has_Prefix
                    then not Page.Has_Prefix
                      or else US.To_String (Page.Prefix) /= Requested_Prefix
                    else Page.Has_Prefix and then US.Length (Page.Prefix) > 0)
               then
                  raise Invalid_Response with
                    "ListBuckets response does not match prepared request";
               end if;
```

`not Page.Has_Prefix` is the clause that fires: a server that filters without echoing is rejected exactly like one that echoes the wrong prefix. The per-bucket check that follows (`src/flyology-object_storage-client-low_level.adb:4150-4172`) independently verifies that every returned name begins with the requested prefix, so the echo rule is not what establishes that the page is filtered.

Any nonempty `Prefix` arms it. The convenience overload sets the presence flag from the string length (`src/flyology-object_storage-client-buckets.adb:189-197`):

```ada
      Parameters : constant Low_Level.List_Buckets_Parameters :=
        (Max_Buckets            => Maximum,
         Has_Max_Buckets        => True,
         Continuation_Token     =>
           US.To_Unbounded_String (Continuation_Token),
         Has_Continuation_Token => Continuation_Token'Length > 0,
         Prefix                 => US.To_Unbounded_String (Prefix),
         Has_Prefix             => Prefix'Length > 0,
         Bucket_Region          => US.To_Unbounded_String (Bucket_Region));
```

and the convenience turns the resulting invalid response into an exception whose message names neither the prefix nor the server (`src/flyology-object_storage-client-buckets.adb:137-141`):

```ada
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "ListBuckets response is invalid or exceeds the XML limit";
```

The rule is deliberate and documented (`docs/qualification/list-buckets.md:13-16`):

```
page cannot exceed the exact prepared maximum. An explicitly supplied prefix
must be echoed with the same presence and bytes, every returned bucket name
must remain in that prefix, and nonempty returned bucket-region metadata must
match an exact requested region.
```

The interop consequence is that a public parameter stops working against a server the matrix lists. `src/flyology-object_storage-client-buckets.ads:961` documents the parameter with no restriction:

```ada
   --  @param Prefix Optional bucket-name prefix filter
```

and `docs/compatibility/s3.md:12` claims the operation across the whole matrix:

```
| ListBuckets | memory, files, SQLite | complete typed, composable, and paginated convenience clients; authenticated server | atomic backend pagination, strict request-bound presence/query/XML and signed socket/server corpora, owner-driven restart/cancellation, plus native/lightweight clients and s5cmd across the six-server matrix |
```

The prose section for the operation describes the strict binding as a feature and does not exclude any server (`docs/compatibility/s3.md:493-495`):

```
clients exercise fragmented success and structured S3 error responses over
real sockets. The composable client additionally gates exact prefix/maximum
and returned-region binding, physical singleton headers, typed failure and
```

MinIO does not echo the element. The image pinned at `tests/scripts/test-minio.sh:5` is `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`, whose `--version` reports

```
minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)
Runtime: go1.24.6 linux/arm64
```

and its answer to `GET /?max-buckets=10&prefix=flyology` is a `200 OK` carrying `Owner`, one correctly filtered `Bucket`, and no `<Prefix>` element at all. Driven live against that container, `List_Page (Prefix => "flyology")` raises, while the same call with no prefix returns a page:

```
  -- List_Page (Prefix => flyology) raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : ListBuckets response is invalid or exceeds the XML limit
  -- List_Page (no prefix, control): kind PAGE_AVAILABLE, status 200
  -- composable List_Page (Prefix => flyology): kind LIST_BUCKETS_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- composable List_Page: HTTP_Result = RESPONSE_INVALID
```

The pinned model documents the echo for AWS but does not require it. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```
ListBucketsOutput required: None
Prefix member: {'shape': 'Prefix', 'documentation': '<p>If <code>Prefix</code> was sent with the request, it is included in the response.</p> <p>All bucket names in the response begin with the specified bucket name prefix.</p>'}
```

`ListBucketsOutput` has no `required` list, so `Prefix` is an ordinary optional member and the shape itself does not mandate the echo. The rule is repository policy.

No maintained gate would notice. The real-server corpus calls `List_Page` without a prefix (`tests/src/s3_implementation_corpus.adb:3181-3184`):

```ada
         Outcome : constant Client_Buckets.List_Outcome :=
           Client_Buckets.List_Page
             (HTTP, Origin, Identity, Maximum => 1_000,
              Timeout => 30.0);
```

The socket corpus does exercise the echo rule, but only with a prefix that is present and wrong (`tests/src/s3_http_socket_corpus.adb:2164-2171`):

```ada
      Wrong_List_Buckets_Prefix_XML : constant String :=
        "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Owner><ID>socket-owner</ID></Owner>" &
        "<Buckets><Bucket><Name>socket-bucket</Name>" &
        "<CreationDate>2026-08-22T01:02:03.000Z</CreationDate>" &
        "<BucketRegion>us-east-1</BucketRegion>" &
        "</Bucket></Buckets><Prefix>other-</Prefix>" &
        "</ListAllMyBucketsResult>";
```

asserted at `tests/src/s3_http_socket_corpus.adb:11387-11388`:

```ada
               Require_Invalid_List_Buckets
                 ("ListBuckets accepted a wrong echoed prefix");
```

None of the five documents that assertion drives omits `<Prefix>` while a prefix was requested, so the case MinIO produces is untested.

## What happens now

Spike: the program below replays MinIO's exact `ListAllMyBucketsResult` for `GET /?max-buckets=10&prefix=flyology` from a scripted loopback origin and drives both the convenience `List_Page` and the parameter-record `List_Page` with `Prefix => "flyology"`, asserting that a page is returned and holds the one matching bucket. The control legs replay the identical document with `<Prefix>flyology</Prefix>` added.

```ada
   Prefix : constant String := "flyology";

   function List_Document (Echo : Boolean) return String is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" & ASCII.LF &
      "<ListAllMyBucketsResult " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe8cf1b6ce98d885" &
      "5f66bdbf4</ID><DisplayName>minio</DisplayName></Owner>" &
      "<Buckets><Bucket><Name>flyology-review-buckets</Name>" &
      "<CreationDate>2026-09-07T06:18:28.511Z</CreationDate></Bucket>" &
      "</Buckets>" &
      (if Echo then "<Prefix>" & Prefix & "</Prefix>" else "") &
      "</ListAllMyBucketsResult>");
```

The bucket name in that document does begin with the requested prefix, so the per-bucket check is satisfied. The two calls and their assertions:

```ada
         Result : constant Buckets.List_Outcome := Buckets.List_Page
           (HTTP, Origin, Identity, Maximum => 10, Prefix => Prefix,
            Timeout => 10.0);
      begin
...
         Check (Result.Kind = Buckets.Page_Available,
                Label & ": the prefix-filtered page is returned");
         if Result.Kind = Buckets.Page_Available then
...
            Check (Natural (Result.Page.Buckets.Length) = 1,
                   Label & ": the page holds the one matching bucket");
...
      Parameters.Prefix := Ada.Strings.Unbounded.To_Unbounded_String (Prefix);
      Parameters.Has_Prefix := True;
      declare
         Result : constant Buckets.List_Buckets_Result := Buckets.List_Page
           (HTTP, Origin, Parameters, Identity, Timeout => 10.0);
      begin
...
         Check (Result.Failure = Client_API.No_Failure,
                Label & ": the composable listing succeeds");
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:58253
  -- --- MinIO shape: 200 ListAllMyBucketsResult with no <Prefix> ---
  -- minio/convenience: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : ListBuckets response is invalid or exceeds the XML limit
  FAILED: minio/convenience: the prefix-filtered page is returned
  -- minio/composable: kind LIST_BUCKETS_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE
  FAILED: minio/composable: the composable listing succeeds
  -- --- control: the same document echoing <Prefix>flyology</Prefix> ---
  -- echoed/convenience: kind PAGE_AVAILABLE, status 200
  ok: echoed/convenience: the prefix-filtered page is returned
  -- echoed/convenience: buckets in page = 1
  ok: echoed/convenience: the page holds the one matching bucket
  -- echoed/composable: kind LIST_BUCKETS_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  ok: echoed/composable: the composable listing succeeds
  -- request 1: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  -- request 2: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  -- request 3: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  -- request 4: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  ok: the origin served all four exchanges
BUG REPRODUCED: 2 failed expectation(s)
```

The control document differs from the failing one by the eight-element `<Prefix>flyology</Prefix>` and nothing else, and it parses into a page holding the one matching bucket. The echo rule is the whole difference.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image; shapes checked against the pinned botocore S3 model.

## What should happen

Either a prefixed `List_Page` returns the page that MinIO's answer represents, because every returned bucket name is inside the requested prefix and the count is within the prepared maximum, or the documentation states that a nonempty `Prefix` is not supported against servers that filter without echoing. Today `docs/qualification/list-buckets.md:13-16` requires the echo, `docs/compatibility/s3.md:12` claims ListBuckets "across the six-server matrix", and `src/flyology-object_storage-client-buckets.ads:961` offers the parameter with no restriction, so the three cannot all be true at once.

## Suggested treatment

This needs a maintainer decision, because either direction changes documented policy or a public contract under the "Decision authority" section of `AGENTS.md`:

- Keep the strict echo rule and document the limitation. State at `src/flyology-object_storage-client-buckets.ads:961` and in the ListBuckets rows of `docs/compatibility/s3.md` that a nonempty `Prefix` requires a server that echoes `<Prefix>`, and name MinIO as one that does not. No code changes, and the client keeps refusing to present an unfiltered page as a filtered one, but a public parameter stays unusable against a matrix-listed server.
- Relax the presence half of the rule. Change `not Page.Has_Prefix or else US.To_String (Page.Prefix) /= Requested_Prefix` at `src/flyology-object_storage-client-low_level.adb:4143-4144` to reject only a present and different prefix, keeping the per-bucket containment check at `:4150-4172` that already proves every returned name is inside the requested prefix. This is a new public policy about what a filtered page is allowed to mean: an absent echo would no longer prove the server applied the filter, and the containment check would become the sole evidence. `docs/qualification/list-buckets.md:13-16` would have to be reworded, since "must be echoed with the same presence and bytes" is the sentence being changed.

Either way the diagnostic should name the real cause. `src/flyology-object_storage-client-buckets.adb:137-141` reports every invalid ListBuckets response as "invalid or exceeds the XML limit", which sends the caller looking for an oversized document.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing prefix fixtures: add a `ListAllMyBucketsResult` that omits `<Prefix>` while the prepared request carries one, with a bucket name inside the prefix, and assert the chosen outcome. The existing assertion at `:11387-11388` uses `Wrong_List_Buckets_Prefix_XML` (`:2164-2171`), which echoes a different prefix, and must keep failing under either option. If the rule is relaxed, `tests/src/s3_implementation_corpus.adb:3181-3184` should also gain a prefixed `List_Page` call, since that is the gate that would have caught the interop break against a real server. The spike is the test.

## Severity

Anyone who passes the public `Prefix` parameter to `List_Page` against MinIO gets an exception from the convenience overload, or `Corrupt_Or_Invalid_Response` from the parameter-record overload, for a response that is a valid and correctly filtered page. The same applies to any server that filters without echoing the element. The failure is total for that parameter against that server, but it needs a caller who uses the prefix filter at all, and the unprefixed listing that the compatibility corpus exercises keeps working, which is why no maintained gate reports it. The behaviour is intended and written down, so the defect is the combination of a documented strict rule, a compatibility claim that covers the server, and parameter documentation that carries no restriction. The check is a comparison of two strings against a parsed document, with no timing or state involved. Deterministic.
