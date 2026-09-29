Title: Lifecycle and Notifications serializers reject U+007F that their own parsers and Replication accept
Labels: bug
Refs: none

## Summary

Three otherwise identical UTF-8 validators guard the lifecycle, notification and replication serializers. Two of them stop the single-byte range one code point early, at `16#7E#` instead of `16#7F#`, so a lifecycle or notification configuration containing U+007F in any text member can be read from a server and never written back: `Serialize` raises before the request is built. U+007F is not a C0 control, XML 1.0 admits it, the matching parsers accept it, and the replication serializer accepts the same byte in the same position. The lifecycle serializer also accepts U+0080, an actual C1 control, so the stated control-character rationale does not describe what the range does.

## Problem

Commit `5fe6e3e`.

The lifecycle validator's single-byte arm stops at `16#7E#` (`src/flyology-object_storage-s3-lifecycle.adb:789-792`):

```ada
               if First in 16#20# .. 16#7E#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
```

The notification validator is identical (`src/flyology-object_storage-s3-notifications.adb:503-506`):

```ada
               if First in 16#20# .. 16#7E#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
```

The replication validator, otherwise the same code, is one byte wider (`src/flyology-object_storage-s3-replication.adb:828-831`):

```ada
               if First in 16#20# .. 16#7F#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
```

The failure happens in `Add_Text`, before escaping and before any request is built (`src/flyology-object_storage-s3-lifecycle.adb:852-856`):

```ada
      procedure Add_Text (Text : String) is
      begin
         if not Valid_XML_UTF8 (Text) then
            raise Malformed_Lifecycle with
              "invalid lifecycle XML text";
```

and identically for notifications (`src/flyology-object_storage-s3-notifications.adb:566-570`):

```ada
      procedure Add_Text (Text : String) is
      begin
         if not Valid_XML_UTF8 (Text) then
            raise Malformed_Notification with
              "invalid bucket-notification XML text";
```

The comment that justifies the range names two properties, and neither holds for U+007F (`src/flyology-object_storage-s3-lifecycle.adb:771-773`):

```ada
      --  XML 1.0 text is UTF-8 and excludes raw C0 controls other than tab,
      --  line feed, and carriage return. This structural wire authority keeps
      --  the serializer from emitting bytes the matching parser must reject.
```

U+007F is not a C0 control, and the matching parser does not reject it. The shared escape boundary every other codec writes through rejects only bytes below 32 other than tab, line feed and carriage return (`src/flyology-object_storage-s3-xml.adb:229-234`):

```ada
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise XML_Error with "invalid XML character";
```

so `Escape_Text` does not front-run the validators either, and the same byte survives `Replication.Serialize` and every writer-based codec.

The value is reachable from the crate's own key domain, which excludes only NUL (`src/flyology-object_storage.adb:479-490`):

```ada
   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
      for Character_Value of Value loop
         if Character_Value = Character'Val (0) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Object_Key;
```

so a lifecycle `Prefix` or a tag value derived from an object key holding U+007F is a legal, if unusual, configuration.

No existing test covers U+007F. `tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb` and `tests/src/s3_bucket_notification_configuration_corpus.adb` exercise C0 controls and invalid UTF-8 only, so the one-byte gap between the three validators is untested in both directions.

## What happens now

Spike: for each of Lifecycle, Notifications and Replication the program below parses a minimal valid configuration and hands the parsed value straight back to `Serialize`, once with a plain ASCII identifier and once with U+007F in it. Replication with U+007F is the key control: identical shape, identical byte, accepted. A final case uses U+0080 to show the boundary is not about control characters.

```ada
   DEL : constant String := (1 => Character'Val (16#7F#));

   function Lifecycle_Document (Suffix : String) return String is
     ("<LifecycleConfiguration><Rule><ID>rule" & Suffix & "</ID>" &
      "<Status>Enabled</Status><Expiration><Days>1</Days></Expiration>" &
      "</Rule></LifecycleConfiguration>");
...
         Value : constant Lifecycle.Lifecycle_Configuration :=
           Lifecycle.Parse (Document, XML.Default_Limits);
      begin
         ...
            Written : constant String :=
              Lifecycle.Serialize (Value, XML.Default_Limits);
...
   Round_Trip_Replication ("ID with U+007F", Replication_Document (DEL));
   Round_Trip_Lifecycle ("ID with U+007F", Lifecycle_Document (DEL));
   Round_Trip_Notifications ("Id with U+007F", Notification_Document (DEL));
   Round_Trip_Lifecycle
     ("ID with U+0080",
      Lifecycle_Document (Character'Val (16#C2#) & Character'Val (16#80#)));
```

Output, exit status 1:

```
  -- DEL byte value 127
  -- lifecycle plain ASCII ID: Parse accepted (140 bytes)
  -- lifecycle plain ASCII ID: Serialize produced 188 bytes
  ok: lifecycle plain ASCII ID: Serialize round-trips Parse
  -- notifications plain ASCII Id: Parse accepted (196 bytes)
  -- notifications plain ASCII Id: Serialize produced 244 bytes
  ok: notifications plain ASCII Id: Serialize round-trips Parse
  -- replication plain ASCII ID: Parse accepted (211 bytes)
  -- replication plain ASCII ID: Serialize produced 259 bytes
  ok: replication plain ASCII ID: Serialize round-trips Parse
  -- replication ID with U+007F: Parse accepted (210 bytes)
  -- replication ID with U+007F: Serialize produced 258 bytes
  ok: replication ID with U+007F: Serialize round-trips Parse
  -- lifecycle ID with U+007F: Parse accepted (139 bytes)
  -- lifecycle ID with U+007F: Serialize REJECTED, invalid lifecycle XML text
  FAILED: lifecycle ID with U+007F: Serialize round-trips Parse
  -- notifications Id with U+007F: Parse accepted (195 bytes)
  -- notifications Id with U+007F: Serialize REJECTED, invalid bucket-notification XML text
  FAILED: notifications Id with U+007F: Serialize round-trips Parse
  -- lifecycle ID with U+0080: Parse accepted (140 bytes)
  -- lifecycle ID with U+0080: Serialize produced 188 bytes
  ok: lifecycle ID with U+0080: Serialize round-trips Parse
BUG REPRODUCED: 2 failed expectation(s)
```

All three parsers accept the byte, the replication serializer writes it back, and the lifecycle serializer writes back U+0080, which is a real C1 control. The rejected cases differ from their controls by that one byte.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A configuration that `Lifecycle.Parse` or `Notifications.Parse` accepts must survive the matching `Serialize`. U+007F is XML 1.0 text, the shared escape boundary at `src/flyology-object_storage-s3-xml.adb:229-234` admits it, and the replication serializer already emits it, so the two narrow validators are the only place in the crate that refuses it.

## Suggested treatment

Change `16#7E#` to `16#7F#` at `src/flyology-object_storage-s3-lifecycle.adb:789` and `src/flyology-object_storage-s3-notifications.adb:503`, matching `src/flyology-object_storage-s3-replication.adb:828`. No public declaration changes and no new value is introduced; the accepted byte range widens by one code point, to the range the sibling serializer already uses. The comment at `src/flyology-object_storage-s3-lifecycle.adb:771-773` should be corrected with it, since it describes a C0-control rule that the range does not implement.

The regression test belongs in `tests/src/object_storage_test_cases.adb`, in the lifecycle and notification round-trip regions: parse a configuration whose `ID` and `Id` carry U+007F and require `Serialize` to return the same document. The spike is the test. The two configuration corpora, `tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb` and `tests/src/s3_bucket_notification_configuration_corpus.adb`, assert nothing about U+007F today and need no change.

## Severity

A lifecycle or notification configuration containing U+007F in `ID`, `Prefix`, a tag key or value, `Id`, or a filter value can be read from a server but never written back: `Serialize` raises `Malformed_Lifecycle` or `Malformed_Notification` before any request is built, so nothing is sent, nothing is lost, and no server sees a bad document. It needs an unusual byte to arrive in a configuration value, most plausibly a prefix or tag derived from an object key that the crate's own `Valid_Object_Key` permits, and no reachable caller produces it by accident. The failure is a clean exception with a correct diagnostic. Deterministic.
