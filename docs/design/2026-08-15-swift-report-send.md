# Swift report send

Design for issue #885, the report half of the Swift async send. Builds on the
run-summary send landed on `ac/sessions` (PR #882) and supersedes the #885
leans in `2026-08-02-swift-async-send-pipeline.md`. Targets 3.0. Working
reference, not committed.

## Status

Approved and built 2026-08-15 on `ac/reports` (off `ac/sessions`), whole branch
uncommitted pending review; the plan is
`docs/plans/2026-08-15-swift-report-send.md`. The PR will target `ac/sessions`
until #882 merges, then retarget `develop`.

Two calls made during the build, both flagged for review:

- The sample integration tests asserted on Apple-format text from the deleted
  formatter. They now assert on the delivered `Report` model
  (`launchAndReportCrash()` returns the decoded delivered report), C++ symbols
  are compared mangled, and Swift symbols demangle through a small
  `swift_demangle` helper in the test file.
- The sample app's send demos were rebuilt on the Swift send: the store
  extension logs via reads, the sample pipeline is `SampleLogStage` plus a
  `KeepOnDiskStage` (throwing is how a stage keeps an item), and the
  alert-based flow was dropped with the Alert filter.

## Summary

Do for crash reports what the sessions branch did for run summaries: one async
call drives the app's pipeline one report at a time and returns lightweight
per-item results, and the Objective-C send path retires completely, filters
and sinks included.

```swift
let result = try await KSCrash.shared.sendReports(with: config)
// result: SendResult<Report>, one item per report, id = report ID
```

## API

`SendConfiguration` gains the report pipeline beside the summary one:

```swift
public struct SendConfiguration: Sendable {
    public var runSummaryPipeline: [AnyPipelineStage<RunSummary>]
    public var reportPipeline: [AnyPipelineStage<Report>]
}

extension KSCrash {
    public func sendReports(with configuration: SendConfiguration) async throws -> SendResult<Report>
    public func sendReports(with configuration: SendConfiguration, only ids: [String]) async throws
        -> SendResult<Report>
}
```

Semantics are the run-summary send's, unchanged:

- One item at a time, newest first; payloads never accumulate.
- A stage returns the payload to pass it on, returns nil to discard the item,
  or throws to keep it on disk for a later send (`.kept`).
- Concurrent sends partition the pending work through claims; a re-entrant
  send returns empty instead of deadlocking.
- Cancellation stops between items and returns the outcomes so far.
- Empty result before install; throws only on a store-level failure.
- An item that cannot be read right now is skipped: absent from that send's
  result, left on disk, retried by the next send.
- Current-run reports are skipped by `sendReports(with:)`: they may still be
  updated (an unresolved watchdog hang, for example), the same reason the
  retired ObjC send skipped them. An id named explicitly in
  `sendReports(with:only:)` is always sent, current run included; that is how
  an app delivers a user report immediately instead of next launch. The check
  is the report's `run_id` against the live run's, made per item after the
  read, matching the ObjC behavior.
- (Review round 4, 2026-08-19: the empty-pipeline purge is GONE. An empty
  pipeline for the kind being sent throws `SendError.emptyPipeline`; it can
  only mean a misconfigured caller, and the purge silently kept undecodable
  reports anyway. Deleting without consuming is `deleteAllReports`.)
- (Review round 3, 2026-08-19: `includesDeliveredPayloads` DROPPED. Payloads
  flow through the stages and never into the result; a consumer that wants
  them keeps them in a stage. `Outcome.delivered` carries nothing.)
- Item ids are typed: `SendResult<Payload: SendPayload>` with `Payload.ID`
  (`ReportID` for reports, the run id for summaries), so the retry flow is
  `sendReports(with: config, only: result.kept)`.

## Model

- `CrashReport<UserData>` becomes the non-generic `Report`; `RecrashReport`
  loses its generic the same way.
- `user: UserData?` becomes `metadata: Metadata?`; the wire key stays `user`.
  The C reader already stitches the app data into the report, so the model
  just decodes that key as a `Metadata` bag.
- `NoUserData` and `BasicCrashReport` are deleted.
- Call sites updated mechanically: the MetricKit monitor sources, the model
  tests, the sample tests.

### Data outside the fixed model

The typed send needs an explicit policy for data outside the fixed model:

1. App data (`user`): preserved as `metadata`, an arbitrary JSON object that
   can be decoded into a concrete type on demand.
2. Custom-monitor error data (`crash.error.monitor_data.<monitorID>`): preserved as
   `CrashError.monitorData`, keyed by monitor id. Callers decode their
   section at the read site with
   `error.monitorData(MyMonitorData.self, for: "my_monitor")`; no registry
   or global state is required.
3. Delivery-time monitor data (`monitor_data.<monitorID>` at the report
   root): preserved as `Report.monitorData`, same shape and accessor. This
   is the framework-owned namespace stitch callbacks use for monitor-owned
   additions.
4. Non-standard JSON passed to `addUserReport`: unsupported. The API now
   requires a standard-shaped KSCrash report. A decoding failure is skipped
   and retained rather than deleted, because it may indicate an incomplete
   model; normal retention may later evict it.

Custom stitch callbacks must place new monitor-owned data under
`monitor_data.<monitorID>` (or `crash.error.monitor_data.<monitorID>` for the crashing
monitor's own section); mutations to arbitrary unmodeled report fields are
not preserved in delivered payloads. Only built-in schema owners may mutate
standard report fields, and those mutations must be represented by the typed
`Report` model.

Supported extension channels therefore remain lossless and typed on demand,
while non-standard report shapes are explicitly outside the send contract. A
follow-up (not this branch) reshapes the extension stitch API around this
contract: extension stitchers return a JSON payload the framework places
under `monitor_data`, and the whole-dictionary callback becomes
schema-owners-only in fact, not just by contract. That follow-up gets its
own design document and implementation plan before any code.

## The store

One internal `Store` replaces the `RunDataStore` + `RunStore` split; the
per-run handle owning its own file operations was style, not necessity, and
two store types read as two stores.

```swift
struct Store: Sendable {
    init(runsDirectory: URL, runSidecarsDirectory: URL,
         liveRunID: String?, reportStore: CrashReportStore)

    func snapshot() throws -> Snapshot
    func pruneRunSummaries(keepingNewest max: Int)

    func summary(of run: Run) -> RunSummary?
    func removeSummary(of run: Run) throws

    func report(_ id: ReportID) -> Report?
    func removeReport(_ id: ReportID) throws

    func reclaimOrphans()
}

/// Point-in-time view of the disk, as one movable value. Pure data, no I/O.
struct Snapshot: Sendable {
    let runs: [Run]          // Run = runID + the file paths captured at listing
    let reportIDs: [ReportID]
}
```

- The production init takes the C-backed report store and derives the report
  half and the reclaim from it internally; the closure seam behind them
  (`ReportBridge`) is private plumbing, reachable only through a test-only
  init. Nothing bridge-shaped appears on the store's working interface.
- `snapshot()` is a pure read: each directory listed once, runs and report
  IDs captured together, so a send can never mix state from two listings.
  Retention is explicit instead: the drivers call
  `pruneRunSummaries(keepingNewest:)` before snapshotting, with the cap
  passed down from the resolved install config, so the store holds no
  retention policy. Both drivers prune, so an app that only ever sends
  reports still cannot grow `.run` files without bound. Report retention
  stays a write-time concern (`maxReportCount` in C); there is no send-time
  report prune.
- One `.run` per run, by construction: the writer's filename is
  deterministic (the dead run's own start time), so even the one real
  re-persist window overwrites rather than duplicates. `Run.summaryFile` is
  a single URL; a stray hand-made duplicate loses to the newest and is left
  for pruning.
- `Run` is inert: a runID plus captured paths, no methods. Store methods take
  the `Run` value and only touch its captured paths, never resolving a runID
  back to a path (the path-traversal defense carried over). Report access is
  ID-keyed and safe: IDs are numeric, come from directory enumeration, and
  the C store owns the canonical filename.
- The contract is symmetric between the halves. Enumeration throws on a
  store-level failure. A read returns nil when the item cannot be delivered
  right now (missing file, stale snapshot entry, or a read failure a retry
  could succeed at): skipped, kept on disk, retried next send. `.kept` is
  reserved for pipeline stages throwing. Removes throw; the driver logs and
  moves on.
- Reads stay C. `kscrs_readReport` already performs every stitch (session_id,
  userInfo, monitor stitches); Swift decodes the returned JSON into `Report`.
  Loads run inline like summaries; no queue hop unless it measurably hurts.
- Small C bridge changes: `kscrs_deleteReportWithID` gains a success return,
  and report enumeration distinguishes failure from empty (namespace regen).
- Unknown-vs-absent carries over untouched for summaries: an absent
  `.sessions` or an absent or corrupt UserInfo sidecar degrades gracefully, a
  retryable failure makes the run wait.

## The send driver

`ReportSend` mirrors `RunSummarySend` line for line: claim, read under the
claim, run the pipeline, delete on delivered or discarded, keep on throw,
defer-reclaim on every exit path. New `SendClaims.reports` instance; the
claim key is the report ID string. Summary and report sends can run at the
same time; they touch different files, and the reclaim they both end with is
the hardened C sweep (`kscrs_reclaimOrphanedRunData`), idempotent under its
own lock.

## Concurrency

Unchanged from the summaries design: snapshots are immutable values and any
number may exist; exclusivity lives in the per-item claims. An explicit
begin/end snapshot held by the store was considered and rejected: claims
already give per-item exclusivity, a held snapshot is a lifetime hazard (a
cancelled send leaves it open), and one-snapshot-at-a-time reintroduces the
"send already in progress" failure the claims design removed.

## What gets retired

- `-[KSCrash sendAllReportsWithConfiguration:completion:]` and the store-side
  send machinery behind it.
- `KSCrashSendConfiguration` and `KSCrashReportFilter.h` (protocol and
  completion type).
- The Filters, Sinks, and DemangleFilter modules and their products, with
  their `Package.swift` entries and `KSCrash-Package.xcscheme` build entries.
- KSCrashDoctor and the C++/Swift demanglers die with their modules. Both are
  real feature loss, accepted: they return later as Swift pipeline stages,
  recoverable from git history.
- The sample app and its integration tests move to the Swift send.

## Decisions and deviations

Recorded because they differ from the 2026-08-02 doc or from prior behavior:

- Flat report items, not the run-grouped `RunStore.reports()` the old doc
  sketched. Grouping only served a pure-Swift reclaim that is not happening;
  reports are independent items.
- The reclaim stays the hardened C sweep. "Becomes pure Swift at #885" is
  superseded; rewriting just-hardened GC is churn plus risk for zero behavior
  change.
- No queue hop for report loads. The old doc's lean is superseded; add one
  only on evidence.
- Reports deliver newest first. The retired ObjC send went oldest first.
- Empty pipelines throw `SendError.emptyPipeline` (round 4 reversal of the
  purge-by-default call, both kinds).
- The C report store largely moves to Swift at the install rewrite (#886),
  not here. The crash-time surface stays C regardless (report writing, ID
  minting in the handler, `kscrs_getNextCrashReport`); enumeration, read,
  and delete are the movable parts.

## Naming

`Report`, `ReportID` (internal, Int64), `Store`, `Snapshot`, `Run`,
`ReportSend`, `SendClaims.reports`. The public surface adds only
`sendReports` and `reportPipeline`.

## Build sequence

1. Branch `ac/reports` off `ac/sessions`.
2. Model: the `Report` rename, de-generic, `metadata`.
3. Store merge: `Store` + `Snapshot` + inert `Run`, the symmetric contract,
   the C bridge returns.
4. `ReportSend`, `sendReports`, `SendClaims.reports`.
5. Retirement: ObjC send, filters, sinks, demangle, Package/scheme/samples.
6. Docs and rules updates; tests throughout (mirror `RunSummarySendTests`,
   model tests, sample integration tests).
