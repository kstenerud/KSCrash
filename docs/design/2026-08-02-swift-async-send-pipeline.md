# Swift async send pipeline for run summaries

Design for issue #888 stage 2, overlapping #885 (Swift async streaming send), #886
(Swift front end), #884 (snapshot-driven send), and #889 (move the send-time store
to Swift). Targets 3.0. Working reference, not committed.

## Status

The model and pipeline work is landed on `ac/runsummary-swift` and the tree matches
this document: the Swift `RunSummary`, `Metadata` (+ `RunSummary.metadata`), the
`KSCrash` umbrella module in its final one-generic shape (no envelope, no `Custom`),
the iOS 13 floor bump, the dropped ObjC `NS_SWIFT_NAME` collisions, and the CI wiring.
Remaining: the store (below), the send driver, and retiring the ObjC send.
`CrashReport` de-generic + its `metadata` is deferred to the report pipeline (#885).
The report send is designed in `2026-08-15-swift-report-send.md`, which
supersedes this document's #885 leans (queue-hop for report loads, run-grouped
`RunStore.reports()`, pure-Swift reclaim).

## Summary

Replace the Objective-C batch delivery of run summaries with a Swift-native async send.
One call drives a user-registered pipeline one summary at a time and returns lightweight
per-item results:

```swift
let result = try await KSCrash.shared.sendRunSummaries(with: config)
// result: per-run items (id, outcome, duration); payloads only when configured
```

The pipeline is a list of uniform stages over the payload itself, and the stages are the
single consumer concept: full payloads exist one at a time, inside a stage, and nowhere
else (never in a returned array, never all in memory). A stage returns the payload
(possibly modified) to pass it on, returns nil to discard it, or throws to leave it for
a later send. Reaching the end means the summary is done: the store reclaims the run's
artifacts (reference-aware, so a `.sessions` a not-yet-sent crash report still needs
survives). App-supplied data rides on the payload as `metadata`, so there is no separate
envelope and no per-pipeline custom-data generic. The report send (#885) uses the same
shape: same call form, same pipeline protocol, same result kind, ids instead of
payloads.

## Deployment target (done)

Package floor raised to iOS 13 / tvOS 13 / watchOS 6 / macOS 10.15, the minimum for
Swift concurrency. Project-wide source break, acceptable on the 3.0 line.

## Metadata

App data (the value set on `KSCrash.userInfo`) is fundamentally a heterogeneous JSON
bag, so it is modeled as one rather than a generic. `Metadata` lives in
`KSCrashReportModel`, is `Codable`/`Equatable`/`Sendable`, and is backed by an internal
`JSONValue` enum with a hand-written codec so the wire form is real JSON. Callers never
touch the enum:

```swift
public struct Metadata: Codable, Equatable, Sendable {
    // loose key access
    public mutating func set(_ value: some JSONValueConvertible, forKey key: String)
    public func value<V: JSONValueDecodable>(forKey key: String, as type: V.Type = V.self) -> V?
    public mutating func removeValue(forKey key: String)
    public func contains(_ key: String) -> Bool
    public var isEmpty: Bool

    // whole-bag typed access, both directions
    public func decoded<T: Decodable>(as type: T.Type) throws -> T      // bag -> your type
    public static func from(_ value: some Encodable) throws -> Metadata // your type -> bag
}
```

So a caller can pull one key typed (`value(forKey:as:)`), reconstitute the whole bag as
their own struct (`decoded(as:)`), or build a bag from a struct (`Metadata.from(_:)`).

`Date` is first-class: it conforms to `MetadataValueRepresentable` backed by
`.double(timeIntervalSince1970)` (wire form is a plain JSON double). The metadata
stitch maps the KV sidecar's date type through it, so a value written with the typed
`setUserInfo(_: Date, forKey:)` setter reads back as a `Date` from the summary's
metadata, and pipeline stages can set `Date` values directly.

## Payloads

Both payload types carry the app's metadata as a plain field and stay non-generic value
types:

```swift
public struct RunSummary: Codable, Sendable, Equatable {
    // ... existing stage-1 fields ...
    public let metadata: Metadata?
}

public struct CrashReport: Codable, Sendable {   // was CrashReport<UserData>
    // ... existing fields ...
    public let metadata: Metadata?
}
```

`CrashReport` drops its `<UserData>` generic so both payloads handle app data
identically. `metadata` is **stitched at delivery** from that run's userInfo stitch
file, keyed by `run_id`, the same way `session_id` is stitched from `.sessions` and
`UserInfoStitch` adds userInfo to reports. It is never read live (live applies only when
finalizing a report during the run itself) and is not baked into the `.run`. `metadata`
is nil when the run persisted no userInfo.

## The pipeline

One generic protocol over the payload, shared by run summaries now and reports later:

```swift
public typealias PipelineValue = Codable & Sendable

public protocol PipelineStage<Payload>: Sendable {
    associatedtype Payload: PipelineValue
    func process(_ payload: Payload) async throws -> Payload?
}
```

Per-item outcomes:

| Stage does | Meaning | Store action |
| --- | --- | --- |
| returns the payload (maybe modified) | pass to the next stage | continue |
| the last stage returns the payload | done | reclaim the run (delete `.run`; `.sessions` only if unreferenced), report it delivered |
| returns nil | intentionally discard (for example sampled out) | reclaim the run, do not retry, report it discarded |
| throws | transient failure for this item | keep on disk, retry next send, do not stop the stream |

A sending stage encodes the payload (`try JSONEncoder().encode(summary)`, metadata
included) and does its network call, then returns it. Enriching is returning a copy with
a changed `metadata`; transforming is returning a changed payload.

Because `any PipelineStage<...>` is a parameterized existential (needs macOS 13 /
iOS 16), a pipeline stores type-erased stages, now over one generic:

```swift
public struct AnyPipelineStage<Payload: PipelineValue>: Sendable {
    public init<Stage: PipelineStage>(_ stage: Stage) where Stage.Payload == Payload
    public func process(_ payload: Payload) async throws -> Payload?
}
```

## The send API

On the shared `KSCrash` singleton, driving the store internally. One async call, one
send; the call iterates internally and returns lightweight per-item results:

```swift
extension KSCrash {
    public func sendRunSummaries(with config: SendConfiguration) async throws -> SendResult<RunSummary>
    public func sendRunSummaries(with config: SendConfiguration, only ids: [String]) async throws
        -> SendResult<RunSummary>
}

public struct SendResult<Payload: PipelineValue>: Sendable {
    public struct Item: Sendable {
        public let id: String            // the on-disk item's id (run ID here)
        public let outcome: Outcome
        public let duration: TimeInterval  // load + pipeline time, for metrics
    }
    public enum Outcome: Sendable {
        case delivered(Payload?)  // completed the pipeline, deleted from disk; the
                                  // final post-pipeline payload when configured, else nil
        case discarded            // a stage returned nil: deleted from disk, never sent again
        case kept(any Error)      // a stage threw this: stays on disk, retried next send
    }
    public let items: [Item]      // processing order
    // convenience: delivered/discarded/kept id lists, deliveredPayloads
}
```

`SendResult` is generic over the payload exactly like `PipelineStage`, so the report
send (#885) returns `SendResult<CrashReport>` from the same definition. The payload
type parameter is also what identifies which send a result is for; that suffices as
long as results are held as their concrete types. Open point: if #885 produces a
consumer that type-erases results from both sends into one place (for example a
shared metrics sink), that consumer needs an explicit kind discriminator, to be added
then, not before. By default the
result carries ids, outcomes, and timing, never payloads: a full `RunSummary` exists
only inside the per-item loop while its stages run, so a send holds at most one payload
in memory regardless of how many runs are pending, and an app that wants the values
consumes them one at a time through a stage. Setting
`SendConfiguration.includesDeliveredPayloads` opts in to carrying each delivered item's
final post-pipeline payload in the result, an explicit trade of memory for convenience
(trivial for summaries, a documented decision for reports). The earlier
`RunSummarySendSequence` (a caller-driven `AsyncSequence`) was built and then dropped:
iteration bought nothing (delivery already lives in stages, the set is small, progress
is uninteresting for telemetry) and its iterator/lease machinery was the complexity
cost.

Semantics:

- The `only:` variant sends just the named runs: unselected runs are not that send's
  items (untouched on disk, absent from the result, like runs claimed by a concurrent
  send), unknown ids match nothing, and an empty list sends nothing. It exists because
  selection is not expressible through stages (a stage can only discard destructively
  or keep-with-error), and it is a separate function rather than a nilable parameter
  so that an accidentally-nil array can never turn a subset send into a full one. The
  natural call site is retrying: `sendRunSummaries(with: config, only: result.kept)`.
- Runs are processed newest first (by start timestamp), so the freshest summaries ship
  first and an interrupted send still delivered the most valuable ones.
- A per-item pipeline failure is silent: the run stays on disk, is reported under
  `kept`, and the send moves on. It retries on the next send; there is no per-item
  backoff or cap, bounded only by `maxRunSummaryCount` pruning (a known limitation).
- The call throws only on a store-level failure (for example the runs directory cannot
  be read).
- The send's disk work never runs on the caller's actor: the driver is `@concurrent`,
  which pins it to the global concurrent executor under every language mode, including
  the Swift 6.2+ semantics where nonisolated async functions otherwise inherit the
  caller's actor. A `@MainActor` caller can await it safely.
- Accepted tradeoff (summaries only): the per-item file reads block a cooperative-pool
  thread for their duration, which is fine at summary sizes (a few KB per artifact,
  microseconds each). This acceptance does NOT automatically extend to #885: report
  files reach MBs, so per-item blocking grows to tens or hundreds of milliseconds
  there, and the report send must decide explicitly between accepting that (still
  bounded, one item at a time) or hopping just the blocking load through a
  continuation onto a utility dispatch queue (floor-compatible; `TaskExecutor` needs
  a far newer OS). Decided at #885: no hop, report loads run inline too, revisited
  only on evidence (see `2026-08-15-swift-report-send.md`).
- Cancellation is honored between runs: the send stops cleanly and returns the
  outcomes so far. Stages are expected to honor cancellation within their own work.
- An empty pipeline means every summary trivially reaches the end: a purge. All
  summaries are reclaimed and reported as delivered; an app that wants the data first
  adds a stage.

## Concurrent sends

Sends do not exclude each other; they partition. A process-wide claims set (one lock)
holds the runIDs currently being processed: each send claims a run before working on it
and skips runs another send holds, so two concurrent sends split the pending work and a
run can never be double-delivered. A skipped run simply does not appear in that send's
result. This replaces the earlier fail-fast "send already in progress" error, and it is
what makes a send re-entrancy-safe by construction: a send started from inside a stage
finds the outer send's runs claimed and returns an empty result instead of deadlocking.
Parallelism inside a send (processing several items concurrently, interesting for
report uploads at #885) can arrive later as a configuration knob on this same shape.

## Configuration

```swift
public struct SendConfiguration: Sendable {
    public var runSummaryPipeline: [AnyPipelineStage<RunSummary>]
}
```

A report pipeline (`[AnyPipelineStage<CrashReport>]`) can be added when the report send
path is done (#885), reusing `PipelineStage` and `AnyPipelineStage`.

## Module layout

- **KSCrashReportModel** (leaf) holds the pure data types: `RunSummary` (+ `metadata`),
  `CrashReport` (+ `metadata`, de-generic), and the `Metadata` / JSON value model.
- **`KSCrash`** (new umbrella; product `KSCrash`; depends on `KSCrashRecording` +
  `KSCrashReportModel`) holds `PipelineStage`, `AnyPipelineStage`, `SendConfiguration`,
  and the `sendRunSummaries` driver, and `@_exported import`s the public modules so a
  consumer writes a single `import KSCrash`.

## RunSummary and the ObjC name collisions (done)

Because the umbrella re-exports both modules, the ObjC framework's Swift aliases that
collide with the model (`RunSummary`, `TerminationReason`, `CrashReport`, `ReportType`,
`CPUState`, `AppTransitionState`) were dropped (their `NS_SWIFT_NAME`s removed, and
`KSCrashNamespace.h` regenerated), so those names resolve to the Swift model. The ObjC
types keep their `KSCrash*` Swift names.

## Design intent that must survive the rework

The run-summary path was shaped around startup cost, and that intent is part of the
contract, not an implementation detail:

- **Install stays minimal.** The persist is synchronous inside `kscrash_install`: C
  sidecar reads, one small JSON write through a C fd. No scanning, no pruning, no
  read-back at install (retention is deliberately a send-path concern). Nothing in
  this rework may add work here; the stage-3 writer change must produce the same or
  less (it drops the intermediate ObjC model graph, keeping the same dict build,
  serialization, and C write).
- **All heavy work lives at send time**, off the critical path: decode, sessions
  merge, metadata stitch, pipeline I/O. That is why metadata is stitched at send and
  never baked into the `.run`, which also keeps the install write small.
- **Cheap-by-construction stays.** The `.sessions` writer creates its file lazily (a
  run that records nothing writes nothing); the snapshot is bounded by `maxRunCount`;
  handles are cheap and per-item work is lazy. The Swift store must not trade these
  away for convenience.
- **Crash-time code is untouched** by this track.

## The store (snapshot-driven, #884 and #889)

One criterion decides the language split: what the crash system must be able to touch
stays C; what runs entirely outside it is pure Swift.

In C, unchanged: run-sidecar writes and sidecar path building (monitors write during
event handling), `kscrash_getRunID`, and the install path (the `.run` persist and its
userID read). The `.sessions` and UserInfo KV writers also stay in the recording layer
for now, not for signal safety (neither runs at crash time) but because SPM gives an
ObjC target no way to import a Swift target.

The on-disk formats each keep exactly one reader, the existing C one, and Swift calls
it; a format is never parsed by two implementations. `KSSessionStore.{c,h}` lives in
`KSCrashRecordingCore` beside `KSKeyValueStore` (both headers in its `include/`), and
the umbrella `KSCrash` target depends on `KSCrashRecordingCore`, so the store calls
`kssr_*` and `kskvs_*` directly. `kscrs_reclaimOrphanedRunData` likewise stays the one
reclaim, shared with the ObjC report send until #885.

The store logic itself (enumerate, snapshot, decode `.run`, merge, stitch, delete,
drive the pipeline) is Swift: two internal types in the umbrella module.

```swift
struct RunDataStore: Sendable {
    init(runsDirectory: URL, runSidecarsDirectory: URL, maxRunCount: Int)

    /// Immutable snapshot of every past run with data on disk, newest first.
    /// Prunes to maxRunCount first. The live run is excluded.
    func runs() throws -> [RunStore]

    /// Remove shared run data nothing references any more.
    func reclaimOrphans()
}

struct RunStore: Sendable {
    let runID: String

    /// The run's summary in deliverable form: decoded `.run` with session
    /// records merged and metadata stitched from the run's UserInfo sidecar.
    /// nil when this run has no summary (already sent, or never written).
    func summary() -> RunSummary?

    /// Delete this run's own `.run`. Never touches shared files.
    func removeSummary() throws
}
```

(`summary()` is non-throwing in the implementation: decode happens at snapshot
time, where an undecodable `.run` is skipped, so the read path only degrades.)

`runs()` builds the snapshot by grouping all artifacts by runID: `.run` files decode
to their runID, `.sessions` filenames and `RunSidecars/` subdirectories are runID
already. The union, minus the live run, is the set of past runs, so a run whose
summary already shipped but whose `.sessions` a pending crash report still holds is a
store with no summary. Orphans are not a separate concept. Each `.run` is decoded
transiently at snapshot time just to extract its identity (the runID that keys the
store); the payload is discarded immediately and re-read per item under the send's
claim, so a send holds at most one summary in memory regardless of backlog, and the
per-item duration covers the read and decode.

`summary()` is the whole read contract: the caller never sees merge or stitch as
separate steps. Degradation matches today's ObjC path: an unreadable `.sessions`
means empty records (with the same end-inference for the open final session), a
missing UserInfo sidecar means nil metadata, an undecodable `.run` throws and the
driver skips that run.

The store's one invariant: a `RunStore` deletes only what it exclusively owns (its
`.run`, later its reports). Shared files (`.sessions`, the sidecar directory) are
deleted only by `reclaimOrphans()`, because "still referenced" is a question about
the whole directory. This branch it delegates to the hardened C sweep (the "does this
run still have reports" scan lives there); #885 keeps that C sweep and treats reports
as flat ID-keyed items rather than growing `RunStore.reports()` (see
`2026-08-15-swift-report-send.md`).

The store is fully synchronous and value-semantic: `runs()` returns an array of cheap
handles, per-item laziness lives in `summary()`, and the async send call is the only
async surface. Store-level async sequences were considered and rejected: the set is
bounded, #884 forces eager materialization, and stacking iterators changes nothing
about when I/O happens.

The send path's C surface is small and explicit: the format readers (`kssr_*`,
`kskvs_*`), the pass-B reclaim via the already-public `-reclaimOrphanedRunData`, and
resolved locations via new C getters in the `kscrash_getRunID` style
(`kscrash_getRunSummariesPath`, `kscrash_getRunSidecarsPath`, plus the resolved
`maxRunSummaryCount`), since the defaults resolve during install in `KSCrashC.c` and
Swift must not re-derive them.

## What gets retired

Retired (done): `KSCrashRunFilter`, `KSCrashRunFilterCompletion`,
`KSCrashSendConfiguration.runSummaryFilters`,
`-[KSCrash sendAllRunSummariesWithConfiguration:completion:]` with its store backing
(`runSummaryByMergingSessions`, `_runSummaryLock`, `_isSendingRunSummaries`,
`runRunFilterChain`), the `KSCrashRunSummary+Merge` category, and the C
`ksruncontext_pruneRunSummaries` (pruning lives in the Swift snapshot step). Also done
(stage 3 of #888): the install-time writer builds the wire dictionary directly and
the Objective-C `KSCrashRunSummary` model and codec are deleted; the host-kind enum
moved to the Lifecycle monitor header beside the sidecar byte it describes.

## Naming

`Metadata`, `PipelineValue`, `PipelineStage`, `AnyPipelineStage`, `SendConfiguration`,
`sendRunSummaries(with:)`, `SendResult`, and the umbrella module/product `KSCrash`
(internal: `RunDataStore`, `RunStore`, `SendClaims`). New Swift type names avoid the
"Crash" prefix; module target names keep the `KSCrash` prefix per the packaging rule.

## Build sequence

1. Deployment-floor bump. (Done.)
2. Drop the colliding ObjC `NS_SWIFT_NAME`s + regenerate the namespace. (Done.)
3. `Metadata` and its value model in `KSCrashReportModel`; `RunSummary.metadata`.
   (Done. `CrashReport` de-generic + its `metadata` deferred to #885.)
4. Rework the `KSCrash` module to the final shape: `PipelineStage<Payload>`,
   `AnyPipelineStage<Payload>`, non-generic `SendConfiguration`. (Done.)
5. Make the C readers reachable from Swift: `KSSessionStore.{c,h}` moves to
   `KSCrashRecordingCore`, and the umbrella target depends on it. (Done.)
6. `RunDataStore` + `RunStore` (snapshot, summary read with merge + stitch, own-file
   delete, Swift prune), plus the resolved-location C getters. (Done.)
7. The async `sendRunSummaries` returning `SendResult`, with per-run claims for
   concurrent sends.
8. Retire the Objective-C run-summary send and the C prune.
9. Tests throughout.
