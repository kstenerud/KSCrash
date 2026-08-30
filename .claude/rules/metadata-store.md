# Metadata Store

App data set through the metadata API (`KSCrash.shared.metadata`) is recorded
live into a per-run key-value sidecar and read back at delivery, once into the
report's `user` section and once into the run summary. These rules are what
keep those two readings the same. They are settled; do not re-derive them.

## Absence is the only "no value"

Null means absence, resolved at read time, never on the write path. A `.null`
removes the key. A container keeps its key with its null members and elements
dropped, even when that leaves the container empty: the container is a value,
its nulls are not. Absence is nil or an omitted key, never `""`.

This is the app-owned bag's rule. `Metadata` is also the decoded type for
`monitor_data.<id>` and the legacy `memory_termination` section, which are not
the metadata store: those decode through `FaithfulMetadata` and keep their
nulls, because a null a monitor wrote is a value, and dropping one re-indexes
the array holding it.

A value the bag cannot hold leaves the key absent as well, in `Metadata` and in
the live store alike: a non-finite `Double` anywhere in the value refuses the
whole write, since JSON cannot carry one and a bag holding one cannot be
encoded at all.

## Every reader reaches the same verdict

Four readers walk the same records: `SidecarMetadata.keys`, the live getter,
the report stitch (`KSCrashMonitor_UserInfoStitch.m`), and the run-summary
stitch (`Store+Runs.swift`). A record one of them calls absence must be absence
to all of them, or a key shows up in the report that the summary omits, or
`keys` names a key that reads nil.

Consequences, each of which has cost someone a bug:

- Bytes that are not UTF-8, JSON that does not decode, and JSON that decodes to
  something other than a container are absence everywhere.
- A non-finite `Double` is absence on the read side too, not just refused on
  the write side: a sidecar written by another build can hold one, and
  delivering it makes the whole report or summary unencodable.
- A non-finite number nested inside a container is absence too. The C decoder
  turns `1e999` into an infinity and the report re-encodes it as `1e999`, which
  Foundation refuses, so the report is undeliverable while every other reader
  calls the record absent.
- A record whose payload does not match its type (a JSON record with no bytes,
  a scalar of the wrong width) routes to `onRemoved`, not to silence. Silence
  leaves the key showing whatever the crash-time writer put there.
- An unknown record *type* is not read, because a newer writer's value is not
  an older reader's to judge, but it is reported through `onUnknown`. The
  report stitch is the one reader that starts from a value it already holds
  (the crash-time user section), and it drops the key, since the store says
  that value was replaced.
- A container is judged against `KSKVS_MAX_VALUE_DEPTH` by every reader, not
  just by the report stitch. See "Depth is measured from where the value
  lands".

Adding a record type means editing four near-identical `KSKVSCallbacks` tables
plus the ObjC one, and a fifth, `readUserIDFromSidecar` in
`KSCrashRunContext.m`, which reads one key off the same file. That duplication
is known.

A sidecar that cannot be read is not the same as one with nothing in it, and
both stitches split it the same way: an unrecoverable file (corrupt, or gone)
delivers without metadata, and only an environmental failure that a retry could
get past holds delivery back. Returning the retry signal for an unrecoverable
file strands every report of that run forever, since finalization never gets
past it, while the same run's summary delivers.

## One representation per type

A `Date` is seconds since 1970, a plain JSON number, in the report and in the
summary alike (`MetadataValue` has no date case). No reader special-cases a
type to make its own output nicer.

## Numbers carry their own precision

`ksstring_doubleToString` writes `DBL_DIG` digits; `ksstring_floatToString`
writes `FLT_DIG`. Which one to use comes from the caller, who knows what the
value is, never from inspecting the value. Guessing ("this double is close to
its float cast, so print six digits") put epoch timestamps out by up to 84
minutes. More digits are not better either: the digits come out of a single
`double` multiply, so past `DBL_DIG` the tail is that multiply's rounding
error.

## A refused write clears the key

A value the store cannot hold leaves the key **absent**, never showing what was
there before: a wrong answer is worse than a missing one. That holds at the
capacity ceiling too, where there is no room for a removal record either, so
`kskvs_removeValue` stamps the key's existing record removed in place.
Compaction reclaims those value bytes, so a full store is not full forever.

## The ceiling is checked before compaction

At `KSKVS_MAX_CAPACITY` a compaction that reclaimed nothing will reclaim
nothing again, and it costs a capacity-sized `calloc` plus an O(n^2) scan on
the host app's thread for a write that fails anyway. The store remembers a
futile compaction and refuses cheaply until something gives the next one
work. Only a compaction that ran reports futility: one that could not allocate
its buffer has measured nothing, and reading that as futility wedges the store
for the rest of the run over a transient allocation failure. What gives the
next one work at the ceiling is an in-place removal, so the store counts the
bytes it stamped over and tries again exactly when they would fit the write.
Clearing the flag on every stamp instead made each refused write pay for a
compaction that the write after it paid for again.

Creation is bounded by the same ceiling the read path enforces, so no writer
can produce a file every reader calls corrupt.

## Locking

Two locks, and the split matters:

- **Per store**: an append takes only its own store's lock. Appends write past
  `hdr->offset` and publish by bumping it last, after a release fence, so a
  reader that sees the new cursor sees the bytes below it. The fence is the
  whole edge: the append and the read-mode load share no lock. The one write
  below the cursor is `markLastRecordRemoved`'s stamp, a single type byte over
  a record whose span does not change.
- **Process-global (`g_fileImageLock`)**: held only while an image is
  restructured or loaded whole, which is compaction, the remap that grows a
  store, creation's truncate-and-init, and the read-mode file load. Those
  rewrite or resize bytes a reader may be part way through, and a reader
  shares no object with the writer (it opens the file by path), so the
  exclusion has to be process-wide.

A reader really can be looking at a file this process is writing: a report
finalized during its own run stitches the live run's sidecar. That is why the
global lock exists, and it is not optional. What is not required is having
every ordinary write take it, which is what made a multi-megabyte send-time
read block all metadata writes in the app.

Lock order is always store lock, then global. Nothing takes them the other
way round.

`kskvs_iterate` takes no lock at all. Every caller either owns a private image
(a read-mode store is this process's own heap copy) or holds the same
serialization the writer does, and staying lock-free is also what would let a
crash handler walk a live store, where pthread calls are not async-signal-safe.
Keep it that way. Iterating a live store from outside its writer's
serialization is the one thing it does not support.

## Depth is measured from where the value lands

A stored container is re-encoded inside the report, under `report -> "user" ->
key`, so it is judged against the depth left below those two containers, not
against the whole limit. Judging it against the whole limit accepts a payload
the report encoder then cannot write, and a report that cannot be encoded is
never delivered, taking every other value with it.

The limit is `KSKVS_MAX_VALUE_DEPTH`, one place, and every reader applies it.
Foundation's own limit is far deeper, so a Swift reader that skips the check
calls a value what the report drops.

## The write path stays cheap

Preparing a value (the tree walk and JSON encode) happens outside the lock, and
not at all when there is no store. Interpretation, validation, and cleanup
belong at read and delivery time. See the Hot-Path Principle in `CLAUDE.md`.

## Key Files

- `KSKeyValueStore.{c,h}`: the record format, compaction, the ceiling, the lock
- `Sources/KSCrashMonitorPlugins/SidecarMetadata.swift`: the Swift store, `PreparedValue`, the shared JSON reader
- `Sources/KSCrash/LiveMetadata.swift`: the installed store and its synchronization
- `KSCrashMonitor_UserInfoStitch.m`: the report's `user` section at delivery
- `Sources/KSCrash/Store+Runs.swift`: the same records on the run summary
- `Sources/KSCrashReportModel/Models/Metadata.swift`, `MetadataStore.swift`: the model and the public contract
