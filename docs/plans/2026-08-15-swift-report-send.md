# Swift Report Send Implementation Plan

> Steps use checkbox (`- [ ]`) syntax for tracking. Executed inline with a diff review at every commit boundary.

**Goal:** Add `sendReports(with:)`, the Swift async report send mirroring the run-summary send, and retire the Objective-C send path (filters and sinks included).

**Architecture:** The spec is `docs/design/2026-08-15-swift-report-send.md`. The model's `CrashReport<UserData>` becomes non-generic `Report` with `metadata: Metadata?`. One internal `Store` (merging today's `RunDataStore` + `RunStore`) serves both sends through an immutable `Snapshot`. A new `ReportSend` driver mirrors `RunSummarySend`. The ObjC send, `KSCrashSendConfiguration`, `KSCrashReportFilter`, and the Filters/Sinks/DemangleFilter modules are deleted.

**Tech Stack:** Swift (KSCrash umbrella module, KSCrashReportModel), ObjC/C bridge in KSCrashRecording, SPM.

## Global Constraints

- Branch: `ac/reports`, created off `ac/sessions`. The PR will target `ac/sessions` until #882 merges.
- This is the 3.0 line (`develop`): source breakage is expected; never flag or hedge on API breaks.
- No em dashes anywhere: prose, code comments, commit messages, docs.
- New source files carry the standard KSCrash MIT header (template in `.claude/rules/code-style.md`).
- Comments state contracts only, terse; public headers never describe implementation.
- Absence is nil/omitted, never `""`.
- Before EVERY commit: `make all` then `make namespace` (never hand-edit `KSCrashNamespace.h`), then review the full diff. No push without approval.
- Commit messages: short imperative subject, plain prose body if needed.
- Tests land in the same task as the code, no red-first ceremony. Sanitizer gate is ASan only (`swift test --sanitize address`; TSan/UBSan are broken in the current toolchain, see memory notes).
- Tee all test output to files under the session scratchpad for inspection.

---

### Task 1: Branch, `Report` rename, de-generic, `metadata`

**Files:**
- Rename: `Sources/KSCrashReportModel/CrashReport.swift` -> `Sources/KSCrashReportModel/Report.swift` (`git mv`)
- Modify: `Sources/KSCrashMonitors/MetricKit/Implementation/*.swift` (5 files using `CrashReport<...>`/`BasicCrashReport`/`NoUserData`)
- Modify: `Tests/KSCrashReportModelTests/CrashReportEncodingTests.swift`, `CrashReportDecoder.swift`, `CrashReportDecodingTests.swift`
- Modify: `Tests/KSCrashTests/UmbrellaResolutionTests.swift`, `Tests/KSCrashMonitorsTests/MetricKitMonitor_Tests.swift`
- Modify: `Samples/Tests/WatchdogTests.swift`, `Samples/Tests/IntegrationTests.swift`, `Samples/Tests/Core/IntegrationTestBase.swift`

**Interfaces:**
- Produces: `public struct Report: Codable, Sendable, Equatable` with the former `CrashReport` fields, `recrashReport: RecrashReport?`, and `metadata: Metadata?` replacing `user: UserData?` (CodingKey `"user"`). `public final class RecrashReport: Codable, Sendable, Equatable` non-generic. `NoUserData` and `BasicCrashReport` no longer exist.

**Grown during review (2026-08-16/17), part of this task's model commit** (see
the design doc's "Data outside the fixed model" section for the policy):
- `CrashError.monitorData: [String: Metadata]?`: unknown object keys under
  `crash.error` preserved via a hand-written Codable (dynamic-key pass; known
  keys stay typed, non-object unknowns are ignored).
- `Report.monitorData: [String: Metadata]?`: the framework-owned root
  `monitor_data` namespace, a plain modeled CodingKey.
- Typed read-site accessor `monitorData(_:for:)` on both, backed by
  `Metadata.decoded(as:)`. No registry, no global state.
- `addUserReport` doc contract in `KSCrashC.h`/`KSCrashReportStoreC.h`
  (standard report shape only), placement contract in `KSCrashMonitorAPI.h`
  and `.claude/rules/monitor-sidecars.md`.
- Tests: custom error sections (multiple monitors, scalar junk ignored, typed
  accessor, wrong-type throws), root namespace decode, absent-is-nil, wire-key
  round-trip on both channels.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b ac/reports ac/sessions
```

- [ ] **Step 2: Rewrite the model type**

`git mv Sources/KSCrashReportModel/CrashReport.swift Sources/KSCrashReportModel/Report.swift`, then:

```swift
public final class RecrashReport: Codable, Sendable {
    public let report: Report
    public init(report: Report) { self.report = report }
    public init(from decoder: Decoder) throws { self.report = try Report(from: decoder) }
    public func encode(to encoder: Encoder) throws { try report.encode(to: encoder) }
}

extension RecrashReport: Equatable {
    public static func == (lhs: RecrashReport, rhs: RecrashReport) -> Bool { lhs.report == rhs.report }
}

public struct Report: Codable, Sendable, Equatable {
    public let binaryImages: [BinaryImage]?
    public let crash: Crash
    public let debug: DebugInfo?
    public let process: ProcessState?
    public let report: ReportInfo
    public let recrashReport: RecrashReport?
    public let system: SystemInfo?
    /// App data attached via the userInfo API.
    public let metadata: Metadata?
    public let incomplete: Bool?

    enum CodingKeys: String, CodingKey {
        case binaryImages = "binary_images"
        case crash, debug, process, report
        case recrashReport = "recrash_report"
        case system
        case metadata = "user"
        case incomplete
    }
}
```

Keep the existing memberwise `init` shape (defaulted optionals), updating `user:` to `metadata:`. Delete `NoUserData` and `BasicCrashReport`. Update the doc comment to drop the generic explanation (contract only).

- [ ] **Step 3: Fix every call site**

Update the MetricKit implementation files, the three model test files, `UmbrellaResolutionTests`, `MetricKitMonitor_Tests`, and the three `Samples/Tests` files: `CrashReport<X>` -> `Report`, `BasicCrashReport`/`CrashReport<NoUserData>` -> `Report`, `user:` labels/reads -> `metadata:` where they touch the model. Verify completion:

```bash
grep -rn "CrashReport<\|BasicCrashReport\|NoUserData" Sources Tests Samples
```

Expected: no matches.

- [ ] **Step 4: Add a metadata decode test**

In the model decoding tests, assert a report JSON with `"user": {"plan": "pro"}` decodes into `metadata` with `value(forKey: "plan") == "pro"`, and that a report without `user` decodes with `metadata == nil`.

- [ ] **Step 5: Build and test**

```bash
swift build 2>&1 | tee <scratchpad>/task1-build.log
swift test --filter KSCrashReportModelTests 2>&1 | tee <scratchpad>/task1-model.log
swift test --filter KSCrashMonitorsTests 2>&1 | tee <scratchpad>/task1-monitors.log
swift test --filter KSCrashTests 2>&1 | tee <scratchpad>/task1-umbrella.log
```

Expected: PASS. (Samples compile is gated in Task 6.)

- [ ] **Step 6: `make all`, `make namespace`, show diff, commit on approval**

Subject: `Rename CrashReport to Report and replace its generic user data with Metadata`

---

### Task 2: Merge `RunDataStore` + `RunStore` into `Store` (no behavior change)

**Files:**
- Create: `Sources/KSCrash/Store.swift` (Store core, `Run`, `Snapshot`)
- Create: `Sources/KSCrash/Store+Runs.swift` (summary read/delete, sessions merge, metadata stitch)
- Delete: `Sources/KSCrash/RunDataStore.swift`, `Sources/KSCrash/RunStore.swift` (content moves)
- Modify: `Sources/KSCrash/RunSummarySend.swift`, `Sources/KSCrash/KSCrash+Send.swift`
- Rename/Modify: `Tests/KSCrashTests/RunDataStoreTests.swift` -> `StoreTests.swift`; adjust `Tests/KSCrashTests/RunSummarySendTests.swift`

**Interfaces:**
- Consumes: existing `RunSummary`, C readers (`kssr_*`, `kskvs_*`), `kscrash_get*` path getters.
- Produces:

```swift
struct Store: Sendable {
    init(runsDirectory: URL, runSidecarsDirectory: URL, maxRunCount: Int,
         liveRunID: String?, reclaim: @escaping @Sendable () -> Void)
    func snapshot() throws -> Snapshot
    func summary(of run: Run) -> RunSummary?
    func removeSummary(of run: Run) throws
    func reclaimOrphans()
}
struct Snapshot: Sendable { let runs: [Run] }     // gains reportIDs in Task 3
struct Run: Sendable {                            // inert: data only, no methods
    let runID: String
    let summaryFiles: [URL]                       // newest first
    let sessionsFile: URL?
    let sidecarDirectory: URL?
}
```

- [ ] **Step 1: Move the code**

`Store.swift`: the header comment, `Run`, `Snapshot`, `init`, `snapshot()` (today's `runs()` body returning `Snapshot(runs:)`), `prune()`, `parsedRunFilenameNs`, `reclaimOrphans()`. `Store+Runs.swift`: `summary(of:)`, `removeSummary(of:)`, and the private sessions-merge and metadata-stitch helpers from `RunStore.swift`, converted from methods on the handle to methods on `Store` taking `run: Run`. Fold `hasSummaryOnDisk` away: `summary(of:)` already returns nil when no captured file is readable, which covers artifact-only runs and stale snapshot entries; keep the comment explaining that under a claim this is race-free. Preserve every existing comment that states an invariant (path-traversal defense, unknown-vs-absent, duplicate `.run` handling).

- [ ] **Step 2: Update the driver and wiring**

In `RunSummarySend.send`: `var runs = try store.snapshot().runs`; replace `guard run.hasSummaryOnDisk, let summary = run.summary()` with `guard let summary = store.summary(of: run)`; `removeSummary(of: run)` via `store`. In `KSCrash+Send.swift`, `runDataStore(reportStore:)` becomes `store(reportStore:)` returning `Store?`.

- [ ] **Step 3: Update tests mechanically**

`git mv Tests/KSCrashTests/RunDataStoreTests.swift Tests/KSCrashTests/StoreTests.swift`; constructions become `Store(...)`, `store.runs()` call sites become `store.snapshot().runs`, handle-method calls become store-method calls. `RunSummarySendTests.makeStore()` returns `Store`. No assertion changes: this task must be behavior-neutral, and the unchanged assertions are the proof.

- [ ] **Step 4: Build and test**

```bash
swift test --filter KSCrashTests 2>&1 | tee <scratchpad>/task2-umbrella.log
```

Expected: PASS with zero assertion edits.

- [ ] **Step 5: `make all`, `make namespace`, show diff, commit on approval**

Subject: `Merge the run stores into one Store with an immutable Snapshot`

---

### Task 3: Report half of `Store` plus the C/ObjC bridge

**Files:**
- Modify: `Sources/KSCrashRecording/include/KSCrashReportStoreC.h`, `Sources/KSCrashRecording/KSCrashReportStoreC.m` (delete returns bool; enumeration signals failure)
- Modify: `Sources/KSCrashRecording/include/KSCrashReportStore.h`, `Sources/KSCrashRecording/KSCrashReportStore.m` (two bridge methods)
- Modify: `Sources/KSCrash/Store.swift` (`ReportBridge`, `reportIDs` on `Snapshot`)
- Create: `Sources/KSCrash/Store+Reports.swift`
- Modify: `Sources/KSCrash/KSCrash+Send.swift` (bridge wiring)
- Modify: `Tests/KSCrashTests/StoreTests.swift`, `Tests/KSCrashTests/RunSummarySendTests.swift` (new init param)

**Interfaces:**
- Consumes: existing `- (nullable KSCrashReportData *)reportDataForID:(int64_t)reportID` on `KSCrashReportStore` (raw stitched JSON read; already public).
- Produces:

```swift
typealias ReportID = Int64
struct ReportBridge: Sendable {
    let list: @Sendable () throws -> [ReportID]
    let read: @Sendable (ReportID) -> Data?
    let remove: @Sendable (ReportID) throws -> Void
    static let none = ReportBridge(list: { [] }, read: { _ in nil }, remove: { _ in })
}
// Store gains: init(..., reports: ReportBridge)
// Snapshot gains: let reportIDs: [ReportID]      // newest first
// Store gains: func report(_ id: ReportID) -> Report?
//              func removeReport(_ id: ReportID) throws
```

ObjC bridge (public header, 3.0):

```objc
/** All unsent report IDs, or nil if the reports directory cannot be read. */
- (nullable NSArray<NSNumber *> *)listReportIDsWithError:(NSError **)error;

/** Delete one report. Returns NO if the report file could not be removed. */
- (BOOL)removeReportWithID:(KSCrashReportID)reportID error:(NSError **)error;
```

- [ ] **Step 1: C changes**

`kscrs_deleteReportWithID` returns `bool` (false when the report file exists but cannot be unlinked; deleting sidecars stays best-effort). `kscrs_getReportCount`/`kscrs_getReportIDs` return `-1` when the reports directory cannot be enumerated (today's behavior on absence, an empty store, stays `0`). Update the header doc comments (contract only) and every in-repo caller of these three functions to the new returns. Run `make namespace`.

- [ ] **Step 2: ObjC bridge methods**

Implement the two methods above in `KSCrashReportStore.m` over the C functions, building an `NSError` (domain `KSCrashErrorDomain` pattern used in the file) on failure. They import to Swift as `listReportIDs() throws -> [NSNumber]` and `removeReport(withID:) throws`.

- [ ] **Step 3: Swift store half**

`Store+Reports.swift`:

```swift
extension Store {
    /// The stitched report, decoded. nil when the item cannot be delivered
    /// right now (missing file or failed read/decode): skipped, kept on
    /// disk, retried by the next send.
    func report(_ id: ReportID) -> Report? {
        guard let data = reports.read(id) else { return nil }
        return try? JSONDecoder().decode(Report.self, from: data)
    }

    func removeReport(_ id: ReportID) throws {
        try reports.remove(id)
    }
}
```

`snapshot()` appends `reportIDs: try reports.list().sorted(by: >)` (IDs are chronological, so descending is newest first). Existing tests pass `reports: .none`.

- [ ] **Step 4: Wire the real bridge**

In `KSCrash+Send.store(reportStore:)`:

```swift
reports: ReportBridge(
    list: { try reportStore.listReportIDs().map(\.int64Value) },
    read: { reportStore.reportData(for: $0)?.value },  // confirm the data property name on KSCrashReportData
    remove: { try reportStore.removeReport(withID: $0) }
)
```

- [ ] **Step 5: Store tests with a fake bridge**

In `StoreTests`: a bridge over an in-memory `[ReportID: Data]` (UnfairLock-wrapped). Cases: `snapshot().reportIDs` sorted newest first; `list` throwing makes `snapshot()` throw; `report(_:)` decodes a fixture JSON built from `Report` via `JSONEncoder`; undecodable data returns nil; `removeReport` propagates the bridge error.

- [ ] **Step 6: Build, test, commit**

```bash
swift test --filter KSCrashTests 2>&1 | tee <scratchpad>/task3-umbrella.log
swift test --filter KSCrashRecordingTests 2>&1 | tee <scratchpad>/task3-recording.log
```

Expected: PASS. Then `make all`, `make namespace`, show diff, commit on approval.

Subject: `Add the report half of Store over a C bridge that reports failures`

---

### Task 4: `ReportSend` driver and the `sendReports` API

**Files:**
- Create: `Sources/KSCrash/ReportSend.swift`
- Modify: `Sources/KSCrash/RunSummarySend.swift` (extract the shared pipeline runner; add `static let reports` to `SendClaims`)
- Modify: `Sources/KSCrash/SendConfiguration.swift`, `Sources/KSCrash/KSCrash+Send.swift`
- Create: `Tests/KSCrashTests/ReportSendTests.swift`

**Interfaces:**
- Consumes: `Store.snapshot().reportIDs`, `Store.report(_:)`, `Store.removeReport(_:)`, `Store.liveRunID`, `SendClaims`, `AnyPipelineStage`, `SendResult`.
- Produces:

```swift
// SendConfiguration
public var reportPipeline: [AnyPipelineStage<Report>]   // init param, default []

// KSCrash
public func sendReports(with configuration: SendConfiguration) async throws -> SendResult<Report>
public func sendReports(with configuration: SendConfiguration, only ids: [String]) async throws -> SendResult<Report>

// internal, shared with RunSummarySend
enum PipelineOutcome<P> { case delivered(P); case discarded; case kept(any Error) }
func runPipeline<P>(_ payload: P, through stages: [AnyPipelineStage<P>]) async -> PipelineOutcome<P>
```

- [ ] **Step 1: Extract the shared pipeline runner**

Move `RunSummarySend`'s private `ProcessOutcome`/`process` into an internal generic `runPipeline(_:through:)` (new bottom section of `PipelineStage.swift`); `RunSummarySend` uses it. No behavior change; summary tests still pass.

- [ ] **Step 2: The driver**

`ReportSend.swift`, mirroring `RunSummarySend` structure, comments included where the invariant carries over:

```swift
enum ReportSend {
    #if hasAttribute(concurrent)
        @concurrent
    #endif
    static func send(
        store: Store?,
        pipeline: [AnyPipelineStage<Report>],
        includesDeliveredPayloads: Bool,
        only selection: Set<ReportID>? = nil,
        claims: SendClaims = .reports
    ) async throws -> SendResult<Report> {
        guard let store else { return SendResult(items: []) }
        var ids = try store.snapshot().reportIDs
        if let selection {
            ids = ids.filter { selection.contains($0) }
        }
        defer { store.reclaimOrphans() }

        var items: [SendResult<Report>.Item] = []
        for id in ids {
            if Task.isCancelled { break }
            guard claims.claim(String(id)) else { continue }
            defer { claims.release(String(id)) }
            let start = DispatchTime.now()
            guard let report = store.report(id) else { continue }
            // A current-run report may still be updated, so the bulk send
            // skips it; an explicitly named id is a deliberate choice and
            // is always sent.
            if selection == nil, let live = store.liveRunID, report.report.runId == live {
                continue
            }
            let outcome: SendResult<Report>.Outcome
            switch await runPipeline(report, through: pipeline) {
            case .delivered(let final):
                remove(id, from: store)
                outcome = .delivered(includesDeliveredPayloads ? final : nil)
            case .discarded:
                remove(id, from: store)
                outcome = .discarded
            case .kept(let error):
                outcome = .kept(error)
            }
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            items.append(.init(id: String(id), outcome: outcome,
                               duration: TimeInterval(elapsedNs) / 1_000_000_000))
        }
        return SendResult(items: items)
    }

    private static func remove(_ id: ReportID, from store: Store) {
        do { try store.removeReport(id) } catch {
            os_log(.error, "Failed to delete report %lld", id)
        }
    }
}
```

`SendClaims` gains `static let reports = SendClaims()`.

- [ ] **Step 3: The public API**

`SendConfiguration` gains `reportPipeline` (empty default; doc comment carries the same loud purge warning as the summary pipeline, plus the memory note for `includesDeliveredPayloads` with MB payloads). `KSCrash+Send.swift` gains the two `sendReports` methods calling `ReportSend.send`; the `only:` variant maps ids with `Int64.init` (unparseable ids match nothing) into a `Set`. Doc comments mirror `sendRunSummaries` and state the current-run rule: skipped by the bulk send, always sent when named in `only:`.

- [ ] **Step 4: Tests**

`ReportSendTests.swift`, following `RunSummarySendTests` helpers (`ClosureStage` over `Report`, `assertOutcomes`, a `Report` fixture builder with a settable `runId`, and the in-memory fake bridge from Task 3). Cases:

1. Delivered: two reports, pass-through stage, both delivered newest first, files removed.
2. Discard: stage returns nil, report removed, `.discarded`.
3. Kept: stage throws, report stays, `.kept`.
4. Empty pipeline purges everything.
5. Claims: pre-claimed id is not an item and is untouched.
6. Cancellation between items returns partial outcomes.
7. Unreadable data: not an item, file stays.
8. Current-run report skipped by bulk send; same id via `only:` delivers.
9. `only:` with unknown and unparseable ids sends nothing.
10. `includesDeliveredPayloads` carries the final payload.
11. Delete failure: outcome still `.delivered`, error logged.

- [ ] **Step 5: Build, test, commit**

```bash
swift test --filter KSCrashTests 2>&1 | tee <scratchpad>/task4-umbrella.log
```

Expected: PASS. `make all`, `make namespace`, show diff, commit on approval.

Subject: `Add the Swift async report send`

---

### Task 5: Retire the Objective-C send, filters, sinks, demangler

**Files:**
- Modify: `Sources/KSCrashRecording/include/KSCrash.h` + `KSCrash.m` (drop `sendAllReportsWithConfiguration:completion:`, `sendReportWithID:configuration:completion:`)
- Modify: `Sources/KSCrashRecording/include/KSCrashReportStore.h` + `KSCrashReportStore.m` (drop the three send methods, the filter machinery, `KSCrashReportCleanupPolicy` if nothing else uses it, the `KSCrashReportFilter.h` import)
- Delete: `Sources/KSCrashRecording/include/KSCrashSendConfiguration.h` + its `.m`, `Sources/KSCrashRecording/include/KSCrashReportFilter.h`
- Delete: `Sources/KSCrashFilters/`, `Sources/KSCrashSinks/`, `Sources/KSCrashDemangleFilter/`, `Tests/KSCrashFiltersTests/`, `Tests/KSCrashDemangleFilterTests/`
- Modify: `Package.swift` (remove products `Reporting`, `Filters`, `Sinks`, `DemangleFilter`; remove targets `KSCrashFilters`, `KSCrashSinks`, `KSCrashDemangleFilter` and their test targets and `Targets` constants)
- Modify: `KSCrash-Package.xcscheme` (remove the three targets' BuildActionEntries)
- Modify: `Samples/Sources/LeaksTest.swift` (drop the filter/sink/demangle exercises; keep the rest of the leaks scenarios)
- Modify: `.claude/CLAUDE.md` and `.claude/rules/api-stability.md` public-module lists (same-change doc sync)

**Interfaces:**
- Consumes: nothing new. After this task the only send paths are `sendRunSummaries` and `sendReports`.

- [ ] **Step 1: Trim the recording layer**

Remove the send methods from `KSCrash.h/.m` and `KSCrashReportStore.h/.m` along with the private filter-chain code in the `.m` (chain runner, completion plumbing, the current-run skip that now lives in Swift). Keep `reportCount`, `reportIDs`, `nextReportID`, `reportForID:`, `reportDataForID:`, `deleteAllReports`, `deleteReportWithID:`, `reclaimOrphanedRunData`, and the Task 3 bridge methods. Delete `KSCrashSendConfiguration.*` and `KSCrashReportFilter.h`.

- [ ] **Step 2: Delete the modules**

`git rm -r` the three source directories and two test directories; update `Package.swift` and the xcscheme. Then:

```bash
grep -rn "KSCrashSendConfiguration\|KSCrashReportFilter\|CrashReportFilter\|CrashReportSink\|Demangle" Sources Tests Samples Package.swift
```

Expected: no matches (the Swift `SendConfiguration` does not match these patterns).

- [ ] **Step 3: Samples**

Rework `Samples/Sources/LeaksTest.swift`: delete the filter/sink/demangle sections (they exercised deleted API); if a delivery exercise is still wanted there, use `sendReports(with:)` with a `ClosureStage`-style printing stage. Check `Samples/CLAUDE.md` for build instructions; do not restructure anything else.

- [ ] **Step 4: Docs in the same change**

`.claude/CLAUDE.md`: remove KSCrashFilters, KSCrashSinks, KSCrashDemangleFilter from the public-modules line. `.claude/rules/api-stability.md`: same list. Do not touch the wiki.

- [ ] **Step 5: Build, test, commit**

```bash
swift build 2>&1 | tee <scratchpad>/task5-build.log
swift test 2>&1 | tee <scratchpad>/task5-test.log
```

Expected: PASS with the deleted test targets gone. `make all`, `make namespace` (C symbols were removed), show diff, commit on approval.

Subject: `Retire the Objective-C report send, filters, sinks, and demangler`

---

### Task 6: Full gate

**Files:**
- No new code. Fixes for anything the gate finds happen in place (root cause, even if pre-existing).

- [ ] **Step 1: Native aggregate suite**

```bash
swift test --build-system native 2>&1 | tee <scratchpad>/gate-native.log
```

- [ ] **Step 2: ASan**

```bash
swift test --sanitize address 2>&1 | tee <scratchpad>/gate-asan.log
```

(No `--filter` with sanitizers; known xctest bug.)

- [ ] **Step 3: Platform builds with test bundles**

watchOS and tvOS simulator `xcodebuild test` shapes per the `project_ci_test_shapes` memory note; iOS simulator destination is iPhone 17 Pro.

- [ ] **Step 4: Samples**

From `Samples/` (per `Samples/CLAUDE.md` and the `project_samples_build` memory note): tuist `build-for-testing` so SampleTests compiles against the new API.

- [ ] **Step 5: Wrap up**

All green: report the results with the log paths, then stop. PR creation is a separate, explicitly approved step (body previewed first, base `ac/sessions`).
