# Swift Install Implementation Plan

> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Objective-C `KSCrash` front end (facade, install configuration, report store) with the Swift API in the design doc, give reports the run summaries' identity scheme with typed ids, and move the send-time store onto C directly.

**Architecture:** The spec is `docs/design/2026-08-22-swift-install.md`. The model gains `MetadataStore`, `Report.ID`, `RunSummary.ID` and `TerminationReason.isAbnormal`. The C store switches to `<eventWallClockNs>-<report.id>.json` filenames with the UUID as the identity, absorbs UserReported into the required mask, and learns a per-key user-info read. The Swift `Store` calls `kscrs_*` directly. A new Swift `KSCrash` facade with `InstallConfiguration`, `Monitors`, plugins, `LiveMetadata`, `Backtrace` and `hangEvents` replaces the ObjC classes, which are deleted in the same step. DiscSpace and BootTime become explicit plugins. Samples, docs, Package and the deployment floor follow.

**Tech Stack:** Swift (the `KSCrash` umbrella module, `KSCrashReportModel`), C/ObjC in `KSCrashRecording` and `KSCrashRecordingCore`, SPM, XCTest.

**Spec:** `docs/design/2026-08-22-swift-install.md`

## Global Constraints

- Branch: `ac/reports` (off `ac/sessions`). Work lands as commits on this branch; never touch PR state (no merges, no retargets, no unapproved pushes).
- This is the 3.0 line (`develop`): source breakage is expected; never flag or hedge on API breaks.
- Locked inputs, not re-decided: Swift-only front end, no `@objc` shims; iOS 15 floor; the front end lives in the existing `KSCrash` module; derived install paths; crash-time core, stitch and reclaim stay C.
- Layout: `<container>/KSCrash/<namespace>/<bundleID>/{Reports,ReportSidecars,Runs,RunSidecars,Data}`. `container` defaults to Application Support, Caches on tvOS. `maxReportCount` defaults to 50, `maxRunSummaryCount` to 50.
- No em dashes anywhere: prose, code comments, commit messages, docs.
- New source files carry the standard KSCrash MIT header (template in `.claude/rules/code-style.md`).
- Comments state contracts only, terse; public surface never describes implementation.
- Absence is nil/omitted, never `""`.
- Before EVERY commit: `make all` then `make namespace` (never hand-edit `KSCrashNamespace.h`), then review the full diff. No push without approval.
- Commit messages: short imperative subject, plain prose body if needed.
- Tests land in the same task as the code, no red-first ceremony. Sanitizer gate is ASan only (`swift test --sanitize address`; TSan/UBSan are broken in the current toolchain).
- Tee all test output to files under the session scratchpad for inspection.
- Every intermediate commit must build (`swift build`) and pass `swift test`; the tree is never left broken at the end of a turn.

---

### Task 1: Model: `RunSummary.ID`, `MetadataStore`, `isAbnormal`

**Scope note (execution):** `Report.ID` cannot exist before Task 4: `Report` already satisfies `SendPayload` with `ID = ReportID` (Int64), the store's key until the C store switch. Task 1 ships `RunSummary.ID` (typed, validated, used for `ReportInfo.runId`, the run listing, the send's claims and selection), `MetadataStore`, and `isAbnormal`; `Report.ID` and `SendPayload: Identifiable` land in Task 4 with the store. Test fixtures use `testRunID("TAG")` (SendTestSupport), a deterministic UUID per tag; valid UUID strings pass through unchanged.

**Files:**
- Modify: `Sources/KSCrashReportModel/Report.swift` (`Report: Identifiable`)
- Modify: `Sources/KSCrashReportModel/Models/ReportInfo.swift:58` (`id: Report.ID`)
- Modify: `Sources/KSCrashReportModel/Models/RunSummary.swift:261,325` (`id: RunSummary.ID`, wire key `run_id`)
- Create: `Sources/KSCrashReportModel/Models/PayloadID.swift` (the two `ID` structs)
- Create: `Sources/KSCrashReportModel/MetadataStore.swift`
- Modify: `Sources/KSCrashReportModel/Models/Metadata.swift` (conform)
- Modify: `Sources/KSCrashReportModel/Models/TerminationReason.swift` (`isAbnormal`)
- Modify: `Sources/KSCrash/SendResult.swift:33-45` (`SendPayload: Identifiable`, drop the hand-declared `ID` associatedtype and the conformance bodies)
- Modify: `Sources/KSCrash/Store+Runs.swift:261` (`RunSummary` extension using `id`)
- Modify: `Sources/KSCrash/Store.swift:314` (`RunIdentity.runID` decodes into `RunSummary.ID`)
- Test: `Tests/KSCrashReportModelTests/PayloadIDTests.swift` (new), `Tests/KSCrashReportModelTests/MetadataTests.swift`, `Tests/KSCrashReportModelTests/RunSummaryModelTests.swift`, `Tests/KSCrashReportModelTests/CrashReportDecodingTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension Report: Identifiable {
      public struct ID: Hashable, Codable, Sendable, CustomStringConvertible {
          public let uuid: UUID
          public init(uuid: UUID)
          public init?(_ string: String)          // nil unless String is a UUID
          public var description: String { uuid.uuidString }   // uppercase
      }
      public var id: ID { report.id }
  }
  extension RunSummary: Identifiable { public struct ID /* same shape */; public var id: ID }   // replaces runID
  public protocol MetadataStore {
      subscript<V: MetadataValueRepresentable>(key: String) -> V? { get set }
      mutating func removeValue(forKey key: String)
      var keys: [String] { get }
  }
  extension Metadata: MetadataStore {}
  extension TerminationReason { public var isAbnormal: Bool }
  ```
- Consumed later by: Task 4 (store listing parses `Report.ID`), Task 5/6 (facade), Task 9 (samples).

- [ ] **Step 1: Add `PayloadID.swift`**

One file, two structs, identical bodies; a private generic helper keeps them in sync:

```swift
import Foundation

extension Report {
    /// The report's identity: the UUID minted when the report was recorded.
    public struct ID: Hashable, Codable, Sendable, CustomStringConvertible {
        public let uuid: UUID
        public init(uuid: UUID) { self.uuid = uuid }
        public init?(_ string: String) {
            guard let uuid = UUID(uuidString: string) else { return nil }
            self.uuid = uuid
        }
        public var description: String { uuid.uuidString }
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let uuid = UUID(uuidString: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "report id is not a UUID: \(raw)"))
            }
            self.uuid = uuid
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(uuid.uuidString)
        }
    }
    public var id: ID { report.id }
}

extension RunSummary {
    /// The run's identity: the run id minted at launch.
    public struct ID: Hashable, Codable, Sendable, CustomStringConvertible { /* same body as Report.ID */ }
}
```

`ReportInfo.id` becomes `public let id: Report.ID`; `RunSummary.runID` becomes `public let id: RunSummary.ID` with `case id = "run_id"`. Fix every `runID` use in the model, `Store.swift`, `Store+Runs.swift`, `SendDriver.swift`/`RunSummarySend.swift` and tests (`grep -rn "\.runID" Sources Tests`).

- [ ] **Step 2: `MetadataStore` protocol and `Metadata` conformance**

```swift
/// Keyed access to scalar metadata. Conformers are the report's metadata and the live store.
public protocol MetadataStore {
    subscript<V: MetadataValueRepresentable>(key: String) -> V? { get set }
    mutating func removeValue(forKey key: String)
    var keys: [String] { get }
}

extension Metadata: MetadataStore {
    public subscript<V: MetadataValueRepresentable>(key: String) -> V? {
        get { value(forKey: key, as: V.self) }
        set {
            if let newValue { set(newValue, forKey: key) } else { removeValue(forKey: key) }
        }
    }
    public var keys: [String] { Array(storage.keys).sorted() }
}
```

The protocol lives in `MetadataStore.swift`; the conformance lives in `Metadata.swift` because `keys` reads the private `storage`. `Metadata` already has `value(forKey:as:)`, `set(_:forKey:)`, `removeValue(forKey:)` and a `subscript<Value: MetadataValueRepresentable>(key:) -> Value?` getter at `Metadata.swift:70`; replace that getter with the protocol's get/set subscript so there is one.

- [ ] **Step 3: `TerminationReason.isAbnormal`**

```swift
extension TerminationReason {
    /// The previous run ended in something KSCrash reports: a crash, hang, or resource kill.
    public var isAbnormal: Bool {
        switch self {
        case .crash, .hang, .lowBattery, .memoryLimit, .memoryPressure, .thermal, .cpu, .unexplained: return true
        case .none, .clean, .firstLaunch, .osUpgrade, .appUpgrade, .reboot, .unknown: return false
        }
    }
}
```

- [ ] **Step 4: `SendPayload` refines `Identifiable`**

In `SendResult.swift` replace the protocol and the two conformances:

```swift
public protocol SendPayload: PipelineValue, Identifiable where ID: Hashable & Sendable {}
extension Report: SendPayload {}
extension RunSummary: SendPayload {}
```

`SendResult.Item.id: Payload.ID` is unchanged in spelling and now means `Report.ID` / `RunSummary.ID`. `sendRunSummaries(with:only:)` takes `[RunSummary.ID]`; `sendReports(with:only:)` keeps `[ReportID]` until Task 4 (it still maps to the Int64 store id there).

- [ ] **Step 5: Tests**

`PayloadIDTests.swift`:

```swift
final class PayloadIDTests: XCTestCase {
    func testParsesUppercaseAndLowercaseUUIDs() {
        XCTAssertNotNil(Report.ID("4C1B2F3E-0000-4000-8000-000000000001"))
        XCTAssertNotNil(Report.ID("4c1b2f3e-0000-4000-8000-000000000001"))
        XCTAssertNil(Report.ID("not-a-uuid"))
        XCTAssertNil(Report.ID(""))
    }
    func testDescriptionIsUppercase() {
        XCTAssertEqual(Report.ID("4c1b2f3e-0000-4000-8000-000000000001")?.description, "4C1B2F3E-0000-4000-8000-000000000001")
    }
    func testCodableRoundTripsTheString() throws {
        let id = Report.ID("4C1B2F3E-0000-4000-8000-000000000001")!
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"4C1B2F3E-0000-4000-8000-000000000001\"")
        XCTAssertEqual(try JSONDecoder().decode(Report.ID.self, from: data), id)
    }
    func testMalformedIDFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(Report.ID.self, from: Data("\"nope\"".utf8)))
    }
    func testReportAndRunIDsAreDistinctTypes() {
        // Compile-time property: a function taking [Report.ID] does not accept [RunSummary.ID].
        func takes(_: [Report.ID]) {}
        takes([Report.ID(uuid: UUID())])
    }
}
```

Add to `MetadataTests.swift`: subscript set/get/remove through `MetadataStore` (`var m = Metadata(); m["a"] = 1; XCTAssertEqual(m["a"] as Int?, 1); m["a"] = nil as Int?; XCTAssertFalse(m.contains("a"))`), `keys` sorted. Add to `CrashReportDecodingTests.swift`: a fixture with `"report": {"id": "bogus"}` throws `DecodingError`. Add a `TerminationReasonTests.swift` case iterating every reason against the expected `isAbnormal` table. Update `RunSummaryModelTests.swift` for `id`.

- [ ] **Step 6: Build, test, commit**

Run: `swift build 2>&1 | tail -3 && swift test --filter KSCrashReportModelTests 2>&1 | tee "$SCRATCH/t1-model.log" | tail -5`, then the full `swift test` (the `KSCrash` module compiles against the new ids).
Expected: 0 failures.
Commit (after `make all`, `make namespace`, diff review): `Type report and run ids and add MetadataStore`.

---

### Task 2: C store: UUID identity, timestamped filenames, string report ids

**Scope note (execution):** executed together with Task 4 as one commit. The string ids force the Swift side to retype its report ids anyway (the ObjC store and `ReportID` sat between the two), so the intermediate `ReportID = String` pass Task 4 would have replaced was skipped: the C grammar, `Report.ID`, `SendPayload: Identifiable`, the Swift store over C and the ObjC store deletion landed in one step. Extra C facts learned: names are kept strictly increasing within the process by an atomic last-prefix (`clock_gettime_nsec_np` is microsecond-grained); `kscrs_addUserReport` returns `bool` with an out id and injects the minted id into JSON-object payloads; `kscrash_addUserReport` gained the out id; `kscrash_getReportStoreConfiguration()`, `kscrash_getReportsPath()`, `kscrash_isInstalled()` are new; the deprecated `reportWrittenCallback` (int64 id) died here rather than in Task 5; `ksid_isValid` is new in KSID.

**Files:**
- Modify: `Sources/KSCrashRecording/KSCrashReportStoreC.m` (filename grammar 95-110, listing 111-184, sidecar naming 203-255, reaper 556-571, ids 571-584, `kscrs_getNextCrashReport` 606-617, read/delete/copyRunID 850-932, `kscrs_addUserReport` 880-911)
- Modify: `Sources/KSCrashRecording/include/KSCrashReportStoreC.h` and `KSCrashReportStoreC+Private.h` (signatures take `const char *reportID`)
- Modify: `Sources/KSCrashRecording/KSCrashC.c:225-285` (crash path: pass `monitorContext->eventID`; `didWriteReport` delivers the id string)
- Modify: `Sources/KSCrashRecordingCore/include/KSCrashReportWriterCallbacks.h:78` (`KSCrashDidWriteReportCallback(plan, const char *reportID)`)
- Modify: `Sources/KSCrashRecordingCore/include/KSCrashMonitorContext.h:190` (`KSCrash_ExceptionHandlerResult.reportId` becomes `char reportId[37]`)
- Modify: `Sources/KSCrashRecordingCore/include/KSID.h` + `KSID.c` (add `bool ksid_isValid(const char *id)`, pure character check, async-signal-safe)
- Modify: `Sources/KSCrashRecording/Monitors/*.m` and `Sources/KSCrashMonitors/**` that read `reportId`/`int64_t reportID` (`grep -rn "reportId\b\|int64_t reportID" Sources`), `Sources/KSCrashRecording/KSCrashReportStore.m` (ObjC store: id parameters become `NSString *`, kept compiling until Task 4 deletes it)
- Test: `Tests/KSCrashRecordingTests/KSCrashReportStoreC_Tests.m`, `Tests/KSCrashRecordingTests/KSCrashReportFinalizer_Tests.m`, `Tests/KSCrashRecordingTests/KSCrashReportStore_Tests.m`

**Interfaces:**
- Produces (C):
  ```c
  #define KSCRS_REPORT_ID_LENGTH 36                      // uppercase UUID text, no NUL
  // Filename: "<wallClockNs>-<UUID>.json"; wallClockNs is decimal, zero-padded to 20 digits so strcmp == time order.
  void  kscrs_getNextCrashReport(const char *reportID, char *crashReportPathBuffer, const KSCrashReportStoreCConfiguration *config);
  int   kscrs_getReportIDs(char reportIDs[][KSCRS_REPORT_ID_LENGTH + 1], int count, const KSCrashReportStoreCConfiguration *config);  // oldest first, -1 on enumeration failure (contract unchanged)
  char *kscrs_readReport(const char *reportID, ..., KSCrashReportReadStatus *status);
  char *kscrs_copyReportRunID(const char *reportID, ...);
  bool  kscrs_deleteReportWithID(const char *reportID, ...);
  bool  kscrs_addUserReport(const char *report, int reportLength, const KSCrashReportStoreCConfiguration *config, char reportIDOut[KSCRS_REPORT_ID_LENGTH + 1]);   // mints an id when report.id is missing or not a UUID, and injects it
  bool  kscrs_getReportSidecarFilePathForReport(const char *monitorId, const char *reportID, char *pathBuffer, size_t len);   // ReportSidecars/<monitorId>/<UUID>.ksscr
  typedef void (*KSCrashDidWriteReportCallback)(const KSCrash_ExceptionHandlingPlan *plan, const char *reportID);
  ```
- Consumed by: Task 4 (Swift store calls these), Task 5 (facade callbacks), Task 7 (MetricKit `diagnosticReportIDs` becomes `[Report.ID]`).

- [ ] **Step 1: Filename grammar and path helpers**

Replace `getCrashReportPathByID` / `getReportIDFromFilename`:

```c
// "<wallClockNs>-<UUID>.json". The name carries order only; the UUID inside the file is the identity.
static void getCrashReportPath(uint64_t wallClockNs, const char *reportID, char *pathBuffer,
                               const KSCrashReportStoreCConfiguration *const config)
{
    snprintf(pathBuffer, KSCRS_MAX_PATH_LENGTH, "%s/%020llu-%s.json", config->reportsPath,
             (unsigned long long)wallClockNs, reportID);
}

// Parses "<20 digits>-<36 char UUID>.json"; false for anything else (the file is not a report).
static bool parseReportFilename(const char *filename, uint64_t *wallClockNs, char reportID[KSCRS_REPORT_ID_LENGTH + 1])
{
    size_t len = strlen(filename);
    if (len != 20 + 1 + KSCRS_REPORT_ID_LENGTH + 5 || filename[20] != '-' || strcmp(filename + len - 5, ".json") != 0) {
        return false;
    }
    for (int i = 0; i < 20; i++) { if (!isdigit((unsigned char)filename[i])) return false; }
    memcpy(reportID, filename + 21, KSCRS_REPORT_ID_LENGTH);
    reportID[KSCRS_REPORT_ID_LENGTH] = '\0';
    if (!ksid_isValid(reportID)) return false;   // NEW in KSID.h: 36 chars, 8-4-4-4-12, uppercase hex and dashes
    if (wallClockNs) *wallClockNs = strtoull(filename, NULL, 10);
    return true;
}
```

Crash time: `kscrs_getNextCrashReport(reportID, pathBuffer, config)` takes the caller's id (the monitor context's `eventID`) and uses `clock_gettime_nsec_np(CLOCK_REALTIME)` for the name; it is still outside `g_mutex` and still async-signal-safe (`snprintf` with integers and strings only, as today). `getNextUniqueID`/`g_nextUniqueID`/`initializeIDs` are deleted.

Listing: `getReportIDs` fills an array of id strings, sorted by filename (`qsort` with `strcmp` on the full names, then copy the ids out), keeping the `-1` readdir contract from `695b4ad3`. The lookup by id (`getCrashReportPathByID` callers: read, delete, copyRunID, sidecars) becomes a directory scan for the name whose UUID part matches; with at most `maxReportCount` files that is one `opendir`, same as today's count.

- [ ] **Step 2: Sidecars, reaper, add, read, delete**

- `getReportSidecarFilePathForReport`: `"%s/%s/%s.ksscr"` with the UUID; `deleteReportSidecarsForReport(const char *reportID, ...)` likewise.
- `pruneReports`: list names, delete the first `count - maxReportCount` (names sort oldest first).
- `kscrs_addUserReport`: parse `report.id` out of the JSON with the existing streaming extractor used by `kscrs_copyReportRunID` (look for `"report"` then `"id"`); if absent or not `ksid_isValid`, `ksid_generate` one and inject it by rewriting the `report` object (`KSJSONCodec` decode, set, encode; this path is never crash-time). Write the file under the new name; return the id through `reportIDOut`.
- `kscrs_readReport(const char *reportID, ...)`, `kscrs_copyReportRunID`, `kscrs_deleteReportWithID`: resolve path by id, rest unchanged. `kscrs_readReportByPathAndID` and `kscrs_finalizeReport` take the id string.

- [ ] **Step 3: The crash path and the did-write callback**

In `KSCrashC.c` `onExceptionEvent`: `kscrs_getNextCrashReport(monitorContext->eventID, crashReportFilePath, &g_reportStoreConfig)`; `strlcpy(result->reportId, monitorContext->eventID, sizeof(result->reportId))`; `g_didWriteReportCallback(&plan, monitorContext->eventID)`. Update `KSCrash_ExceptionHandlerResult.reportId` to `char reportId[37]` and every reader (`grep -rn "reportId" Sources`). The legacy `reportWrittenCallback(int64_t)` adapter is deleted here (it dies anyway in Task 5).

- [ ] **Step 4: Tests**

In `KSCrashReportStoreC_Tests.m` (existing cases adapt from Int64 ids to strings):

```objc
- (void)testCrashReportFilenameCarriesTimeThenUUID
{
    char path[KSCRS_MAX_PATH_LENGTH];
    kscrs_getNextCrashReport("4C1B2F3E-0000-4000-8000-000000000001", path, &self.config);
    NSString *name = [[NSString stringWithUTF8String:path] lastPathComponent];
    XCTAssertTrue([name hasSuffix:@"-4C1B2F3E-0000-4000-8000-000000000001.json"]);
    XCTAssertEqual([name rangeOfString:@"-"].location, 20u);   // 20 decimal digits of wall-clock ns
}
- (void)testListingIsOldestFirstByName   // write three files with ascending ns prefixes out of order; expect sorted ids
- (void)testFilesThatAreNotReportsAreIgnored   // "notes.txt", "1234-nope.json", lowercase uuid
- (void)testAddUserReportMintsAnIDWhenMissing   // report JSON without report.id -> returned id is a UUID and the stored JSON carries it
- (void)testAddUserReportKeepsAValidID
- (void)testPruneDeletesOldestByName
- (void)testSidecarPathUsesTheUUID        // ReportSidecars/<monitorId>/<UUID>.ksscr
- (void)testDidWriteReportCallbackReceivesTheIDString   // install with a didWrite callback into a static buffer, record a user report via kscrash_reportUserException, assert the buffer is a UUID equal to the listed id
```

- [ ] **Step 5: Build, test, commit**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tee "$SCRATCH/t2-cstore.log" | tail -5`. Also `swift test --sanitize address 2>&1 | tee "$SCRATCH/t2-asan.log" | tail -5` (C changed).
Expected: 0 failures; the ObjC store and the Swift `ReportBridge` still compile because their id type changes ride along (`NSString *` / `String` in `listReportIDsWithError:` etc., a mechanical edit in this task).
Commit: `Name report files by time and identify them by UUID`.

---

### Task 3: C monitors and user info: always-on UserReported, private composites, per-key read

**Scope note (execution):** the public C type keeps the bits plus two sets, `KSCrashMonitorTypeDefault` (every detector but Zombie) and `KSCrashMonitorTypeAll`, because the C config's default and the Swift `Monitors.default`/`.all` need a named value; only `Required` is private. The deprecated Deadlock monitor went with its `MainThreadDeadlock` alias and `deadlockWatchdogInterval` (C config, ObjC config, report-writer branch, tests); the `deadlock` wire value stays in the model for old reports. The read API is public C in a new `KSCrashUserInfo.h` (`KSCrashUserInfoValue`, the key and string limits, `kscrash_copyUserInfoValue`, `kscrash_copyUserInfoKeys`), with the `kscm_userinfo_*` twins on the monitor; Task 6 consumes it as is. Review outcome: `KSCrashMonitorTypeWatchdog` renamed `KSCrashMonitorTypeHang` (the bit only; the monitor id `Watchdog` is a wire value and stays), and the keys read is an enumeration with a callback rather than a caller buffer or a `char **`.

**Files:**
- Modify: `Sources/KSCrashRecording/include/KSCrashMonitorType.h` (keep the 12 bits and `None`; move every composite plus the deprecated aliases to a new private `Sources/KSCrashRecording/KSCrashMonitorType+Private.h`; `Required` gains `UserReported`)
- Modify: `Sources/KSCrashRecording/KSCrashC.c:300-320,560-566` (`setMonitors` uses the private header; the `No crash monitors are active` failure is removed)
- Modify: `Sources/KSCrashRecording/include/KSCrashError.h:59` (delete `KSCrashInstallErrorNoActiveMonitors`)
- Modify: `Sources/KSCrashRecording/Monitors/KSCrashMonitor_UserInfo.{h,c}` (per-key read)
- Modify: `Sources/KSCrashRecordingCore/include/KSKeyValueStore.h` + `.c` (nothing new; the read uses `kskvs_iterate`)
- Test: `Tests/KSCrashRecordingTests/KSCrashMonitorSelection_Tests.m`, `Tests/KSCrashRecordingTests/KSCrashMonitor_UserInfo_Tests.m` (new or existing), `Tests/KSCrashRecordingTests/KSCrash_Tests.m`

**Interfaces:**
- Produces (C):
  ```c
  typedef enum { KSUserInfoValueNone, KSUserInfoValueString, KSUserInfoValueInt64, KSUserInfoValueUInt64,
                 KSUserInfoValueDouble, KSUserInfoValueBool, KSUserInfoValueDate } KSUserInfoValueType;
  typedef struct { KSUserInfoValueType type; union { int64_t i64; uint64_t u64; double d; bool b; uint64_t dateNs; } value;
                   char string[KSUSERINFO_MAX_STRING_LENGTH + 1]; } KSUserInfoValue;
  bool kscm_userinfo_copyValue(const char *key, KSUserInfoValue *out);   // false when absent or removed; under g_lock
  void kscm_userinfo_enumerateKeys(KSCrashUserInfoKeyCallback callback, void *context);   // live keys, callback outside the lock
  ```
- Consumed by: Task 6 (`LiveMetadata`).

- [ ] **Step 1: Required mask absorbs UserReported; composites go private**

`KSCrashMonitorType.h` keeps: the 12 `1 << n` bits, `KSCrashMonitorTypeNone`, and a comment that `System`, `ApplicationState`, `UserInfo`, `Resource` and `UserReported` are always enabled. `KSCrashMonitorType+Private.h` holds `Required` (now `System | ApplicationState | UserInfo | Resource | UserReported`), `All`, `Fatal`, `DebuggerUnsafe`, `AsyncSafe`, `Optional`, `AsyncUnsafe`, `DebuggerSafe`, `ProductionSafe`, `ProductionSafeMinimal`; `Experimental`, `Manual`, `MainThreadDeadlock`, `MemoryTermination`, `Compatible251` are deleted. `setMonitors` in `KSCrashC.c` is unchanged in logic. Fix the in-tree users (`grep -rn "KSCrashMonitorType[A-Z]" Sources Tests` minus the 12 bits): `KSCrashC.c`, the two tests that use `DebuggerSafe`/`ProductionSafeMinimal`/`MemoryTermination`, and the ObjC config default (dies in Task 5; point it at the private header meanwhile).

- [ ] **Step 2: Drop the no-active-monitors failure**

With the required mask always non-empty `kscm_enableMonitors()` cannot come back false for "nothing enabled"; remove the check and `KSCrashInstallErrorNoActiveMonitors` (and its ObjC error mapping in `KSCrash.m` until Task 5 deletes the file). Keep a `KSLOG_ERROR` if `kscm_enableMonitors` still returns false for a registry failure and map it to `KSCrashInstallErrorCouldNotInitializeCrashState`.

- [ ] **Step 3: Per-key read on the user-info monitor**

```c
typedef struct { const char *key; KSUserInfoValue *out; bool found; } LookupCtx;
static void onString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx) {
    LookupCtx *l = ctx;
    if (keyLen == strlen(l->key) && memcmp(key, l->key, keyLen) == 0) {
        l->out->type = KSUserInfoValueString; size_t n = valueLen < KSUSERINFO_MAX_STRING_LENGTH ? valueLen : KSUSERINFO_MAX_STRING_LENGTH;
        memcpy(l->out->string, value, n); l->out->string[n] = '\0'; l->found = true;
    }
}
/* onInt64/onUInt64/onDouble/onBool/onDate set the union; onRemoved clears found and sets type None. */
bool kscm_userinfo_copyValue(const char *key, KSUserInfoValue *out)
{
    if (g_store == NULL || key == NULL || out == NULL) return false;
    LookupCtx ctx = { .key = key, .out = out, .found = false };
    os_unfair_lock_lock(&g_lock);
    kskvs_iterate(g_store, &(KSKVSCallbacks){ .onString = onString, /* ... */ .onRemoved = onRemoved }, &ctx);
    os_unfair_lock_unlock(&g_lock);
    return ctx.found;
}
```

`kskvs_iterate` replays the append-only records in order, so the last callback for a key wins, which is exactly the "latest value" semantic the stitch relies on. `kscm_userinfo_copyKeys` collects distinct live keys the same way (a small fixed table; the sidecar's capacity bounds it).

- [ ] **Step 4: Tests**

`KSCrashMonitorSelection_Tests.m`: `testUserReportedIsAlwaysEnabled` (install with `KSCrashMonitorTypeNone`, `kscrash_reportUserException` writes a report), `testEmptyMonitorSetInstalls` (no `NoActiveMonitors` error). User-info tests: set string/int/date then `kscm_userinfo_copyValue` returns each with the right type; removed key returns false; overwritten key returns the latest; `copyKeys` lists the live keys only.

- [ ] **Step 5: Build, test, commit**

Run: `swift build && swift test 2>&1 | tee "$SCRATCH/t3-monitors.log" | tail -5`; ASan run.
Commit: `Always enable user-reported exceptions and read user info by key`.

---

### Task 4: Swift `Store` over C, typed ids through the send, ObjC store deleted

**Files:**
- Modify: `Sources/KSCrash/Store.swift` (production init builds the bridge from `kscrs_*`; `ReportBridge` ids become `Report.ID`; listing parses filenames in Swift)
- Modify: `Sources/KSCrash/KSCrash+Send.swift` (`sendReports(with:only:)` takes `[Report.ID]`; store construction reads the C paths)
- Modify: `Sources/KSCrash/SendDriver.swift`, `ReportSend.swift`, `RunSummarySend.swift` (id types)
- Delete: `Sources/KSCrash/` any `ReportID` typealias; `Sources/KSCrashRecording/KSCrashReportStore.m`, `include/KSCrashReportStore.h`, `Tests/KSCrashRecordingTests/KSCrashReportStore_Tests.m` (the ObjC store and its tests; the C tests in `KSCrashReportStoreC_Tests.m` keep the coverage)
- Modify: `Sources/KSCrashRecording/KSCrash.m`, `KSCrashInstallConfiguration.m` (drop the `reportStore` property and `KSCrashReportStoreConfiguration`; the ObjC facade installs with the store config inline until Task 5 deletes it)
- Modify: `Sources/KSCrashMonitors/MetricKit/**` (`diagnosticReportIDs: [Report.ID]`, `kscrs_addUserReport` out-param)
- Test: `Tests/KSCrashTests/StoreTests.swift`, `ReportSendTests.swift`, `SendTestSupport.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ReportBridge: Sendable {
      let list: @Sendable () throws -> [Report.ID]          // oldest first
      let read: @Sendable (Report.ID) throws -> Data?       // nil = not readable now (skip), throws = corrupt
      let runID: @Sendable (Report.ID) -> RunSummary.ID?
      let remove: @Sendable (Report.ID) throws -> Void
  }
  extension Store {
      init(runsDirectory: URL, runSidecarsDirectory: URL, reportsDirectory: URL, liveRunID: RunSummary.ID?, maxRunCount: Int, storeConfig: UnsafePointer<KSCrashReportStoreCConfiguration>)   // production
      func snapshotReportIDs() throws -> [Report.ID]
      func report(_ id: Report.ID) throws -> Report?
      func removeReport(_ id: Report.ID) throws
  }
  extension KSCrash {   // still the ObjC class in this task
      public func sendReports(with configuration: SendConfiguration, only ids: [Report.ID]) async throws -> SendResult<Report>
  }
  ```
- Consumes: Task 2's C signatures; Task 1's ids.

- [ ] **Step 1: Listing and removal in Swift**

`snapshotReportIDs()` enumerates `reportsDirectory` with `FileManager.contentsOfDirectory(atPath:)` (throws on an unreadable directory; an absent directory is `[]`, matching the C contract), keeps names matching `^\d{20}-([0-9A-F-]{36})\.json$` whose UUID part parses as `Report.ID`, sorts by name, maps to ids. Removal calls `kscrs_deleteReportWithID(id.description, config)` (the C also removes the sidecars) and throws `StoreError.removeFailed(id)` on `false`. Reading calls `kscrs_readReport(id.description, config, &status)` and maps `status` as `ReportBridge.read` does today (corrupt throws, unreadable nil). `runID(of:)` calls `kscrs_copyReportRunID` and wraps the string in `RunSummary.ID`.

The production `init` stops taking a `CrashReportStore` and takes the directories plus a pointer to the C store config (`kscrash_getReportStoreConfiguration()`; add that accessor to `KSCrashC.h` if the config is not already reachable, returning `&g_reportStoreConfig`). The test-seam init keeps its closure `ReportBridge`.

- [ ] **Step 2: Delete the ObjC store**

Remove `KSCrashReportStore.{h,m}` and their test file; remove `KSCrashReportStoreConfiguration` from `KSCrashInstallConfiguration.{h,m}` (the ObjC config carries `maxReportCount`/`maxRunSummaryCount` directly for the one task it has left); `KSCrash.reportStore` goes, `KSCrash+Send.swift` resolves the store from `kscrash_getReportsPath()` (add next to `kscrash_getRunSummariesPath`) and the installed flag (`kscrash_isInstalled()`, add if absent). `grep -rn "CrashReportStore\|KSCrashReportStore\b" Sources Tests Samples` must come back empty except the C store.

- [ ] **Step 3: Tests**

`StoreTests.swift`: `testSnapshotReportIDsParsesNamesOldestFirst` (write `00000000000000000002-<B>.json`, `00000000000000000001-<A>.json`, `notes.txt`, `00000000000000000003-bogus.json` into a temp reports dir through the production init with a stub C config pointing at it; expect `[A, B]`), `testSnapshotReportIDsThrowsOnUnreadableDirectory` (chmod 000 the directory), `testRemoveReportDeletesFileAndSidecars` (through the real C store: `kscrs_addUserReport` a report, add a sidecar via `kscrs_getReportSidecarFilePathForReport`, remove, assert both gone). `ReportSendTests.swift`: `sendReports(only:)` with a `Report.ID` that is not present matches nothing; ids in `SendResult` equal `report.id` of the delivered payloads (capture via a stage).

- [ ] **Step 4: Build, test, commit**

Run: `swift build && swift test 2>&1 | tee "$SCRATCH/t4-store.log" | tail -5`; ASan run.
Commit: `Drive the Swift store from the C report store directly`.

---

### Task 5: The Swift facade and `InstallConfiguration`; the ObjC front end deleted

**Scope note (execution):** `MonitorPlugin`/`CMonitorPlugin` live in a new `KSCrashMonitorPlugins` target (product `MonitorPlugins`, the extension branch's name), depended on by `KSCrash` and `KSCrashMonitors` and re-exported by `KSCrash`; `KSCrashSwiftCore` has no C dependency so it could not host a protocol naming `KSCrashMonitorAPI`. `kscrash_install` lost its `appName` parameter and the store config its `appName` field (the filename prefix is gone). The path helpers moved from `KSCrash.m` to `KSCrashPaths.m`; `kscrash_setUserID`, `kscrash_getPreviousTerminationReason`, and `kscrash_reportNSException` (`KSCrashC+NSException.m`, which registers for the NSException monitor's reporter at load) landed here rather than in Task 6 because the ported ObjC tests need them. The framework version constants moved to `KSCrashVersion.c` and the release workflow's sed targets follow. The facade's lock is `KSCrashSwiftCore.UnfairLock` (the iOS 15 floor predates `OSAllocatedUnfairLock`). The NSException, watchdog, user-id, and namespace ObjC tests now exercise the C entry points; `KSCrash_Tests.m` and `KSCrashInstallConfiguration_Tests.m` died with their classes. Review round: `Install+C.swift` is `InstallBridge.swift` (`InstallConfiguration.install(at:)`); `install` validates first (`InstallError.invalidConfiguration`); `Container.url(URL)` for a custom base; the `userInfoJSON` path (C config field, wrappers, the writer's JSON user section and its PR #865 guard, ten writer tests) is gone, the crash-time `user` section is the callback's alone; the deprecated `kscrash_notify*` no-ops are gone; `KSCrashVersion.h` holds the version externs. Removing `userInfoJSON` exposed a latent layout hazard: `KSCrashMonitorType` was `NS_OPTIONS(NSUInteger)` under ObjC/Swift but a 4-byte `enum` in C, and the pointer that followed `monitors` had padded both layouts to the same offsets; `KSCrashMonitorType` is now `unsigned long` in C with a `_Static_assert` in `KSCrashC.c`. Config sync round: `KSCrashCConfiguration` lost `reportStoreConfiguration` (replaced by the two counts; paths are derived in C from `KSCRS_DEFAULT_*_FOLDER`, with `deriveReportsSiblingDir` and its tests gone), `enableSigTermMonitoring`, `crashNotifyCallback` (+ adapter, + `KSReportWriteCallback`); `InstallConfiguration.init` reads its defaults from `KSCrashCConfiguration_Default()` (C `maxReportCount` default is now 50); `Locations` uses the C folder constants; `InstallBridge.makeCConfiguration()` is the testable half; tests `test_bridge_roundTripsTheCDefaults` and `test_locations_matchTheCStoresPaths`. The MetricKit JSON dumper keeps `kscrash_documentsPath()` because it deliberately writes to Documents (user-visible) and `KSCrashMonitors` does not depend on `KSCrash`.

**Files:**
- Create: `Sources/KSCrash/KSCrash.swift` (the class, `shared`, `install`, `installConfiguration`, `installedPlugin`, state under an `OSAllocatedUnfairLock`)
- Create: `Sources/KSCrash/InstallConfiguration.swift` (+ `Container`, `MemoryIntrospection`, `Locations`)
- Create: `Sources/KSCrash/UnsafeCrashTimeCallbacks.swift` (+ `ExceptionHandlingPlan`, `MonitorContext` typealiases)
- Create: `Sources/KSCrash/Monitors.swift` (the option set; `var cValue: KSCrashMonitorType`)
- Create: `Sources/KSCrash/MonitorPlugin.swift` (`MonitorPlugin`, `CMonitorPlugin`)
- Create: `Sources/KSCrash/InstallError.swift`
- Create: `Sources/KSCrash/Install+C.swift` (builds `KSCrashCConfiguration` from the Swift config, calls `kscrash_install`, maps the error code; the logic of `-[KSCrashInstallConfiguration toCConfiguration]` moves here)
- Modify: `Sources/KSCrash/KSCrash+Send.swift` (extension now targets the Swift class)
- Modify: `Sources/KSCrash/Exports.swift` (keep `@_exported import KSCrashRecording` for the C surface; the ObjC class is gone so there is no ambiguity)
- Delete: `Sources/KSCrashRecording/KSCrash.{m}`, `include/KSCrash.h`, `KSCrash+Private.h`, `KSCrash+Namespace.{h,m}`, `KSCrash+UserInfo.{h,m}`, `KSCrash+Hang.{h,m}`, `KSCrash+Backtrace.{h,m}`, `KSCrashInstallConfiguration.{h,m}`, `KSCrashInstallConfiguration+Private.h`, `include/KSCrashMonitorPlugin.h`, `KSCrashBasicMonitorPlugin.m`; tests `KSCrash_Tests.m`, `KSCrashInstallConfiguration_Tests.m`, `KSCrash_UserID_Tests.m`, and the facade uses in `KSCrashMonitor_NSException_Tests.m`, `KSCrashMonitor_Watchdog_Tests.m`, `KSCrashReportFinalizer_Tests.m` (they install through C directly or through the Swift facade from a Swift test)
- Modify: `Sources/KSCrashRecording/KSCrashC.c` + `include/KSCrashC.h`: `kscrash_install(const char *bundleID, const char *installPath, KSCrashCConfiguration *)` (the `appName` parameter is gone with the filename prefix), `kscrash_isInstalled()`, `kscrash_getReportsPath()`; the `kscm_nsexception_setOnEnabledHandler` hook that fed `uncaughtExceptionHandler` is removed
- Modify: `Sources/KSCrashRecording/include/KSCrashCConfiguration.h`: drop `appName`, `userInfoJSON`, `deadlockWatchdogInterval`, `enableSigTermMonitoring`, `crashNotifyCallback`, `reportWrittenCallback` and their `Default`/`Release` lines; `KSCrashC.c handleConfiguration` loses the legacy adapters
- Modify: `Sources/KSCrashMonitors/MetricKit/MetricKitMonitor.swift` (conforms to the Swift `MonitorPlugin`, no `NSObject`), `Sources/KSCrashMonitors/Monitors.swift` (deleted in Task 7; for now `Monitors.metricKit` is renamed `MetricKitPlugins.metricKit` to free the name)
- Test: `Tests/KSCrashTests/InstallConfigurationTests.swift`, `MonitorsTests.swift`, `KSCrashInstallTests.swift` (new)

**Interfaces:**
- Produces (exactly the spec's "The facade" and "InstallConfiguration" blocks):
  ```swift
  public final class KSCrash: Sendable {
      public static let shared: KSCrash
      public func install(_ configuration: InstallConfiguration) throws
      public var installConfiguration: InstallConfiguration? { get }
      public func installedPlugin<M: CrashMonitor>(_ type: M.Type) -> M?   // until the #867 layer lands, constrained to `M: MonitorPlugin` and returns the registered plugin object
  }
  public struct InstallConfiguration: Sendable { public init(namespace: String); public let namespace: String; /* knobs per spec */ }
  public enum Container: Sendable { case applicationSupport, caches, appGroup(String); public static var `default`: Container }
  public enum MemoryIntrospection: Sendable { case disabled, enabled(excludingClasses: [String]) }
  extension InstallConfiguration { public struct Locations: Sendable { public let root, reports, reportSidecars, runs, runSidecars, data: URL }; public var locations: Locations { get throws } }
  public struct UnsafeCrashTimeCallbacks: Sendable { typealiases WillWriteReport/IsWritingReport/DidWriteReport; vars; init }
  public typealias ExceptionHandlingPlan = KSCrash_ExceptionHandlingPlan
  public typealias MonitorContext = KSCrash_MonitorContext
  public struct Monitors: OptionSet, Sendable { machExceptions, signals, cppExceptions, nsExceptions, terminations, hangs, zombies; `default`; all }
  public protocol MonitorPlugin: AnyObject, Sendable { var api: UnsafeMutablePointer<KSCrashMonitorAPI> { get } }
  public final class CMonitorPlugin: MonitorPlugin { public init(api: UnsafeMutablePointer<KSCrashMonitorAPI>) }
  public enum InstallError: Error, Equatable { alreadyInstalled, pathTooLong, couldNotCreatePath, couldNotInitializeStore, couldNotInitializeMemory, couldNotInitializeCrashState, couldNotSetLogFilename, containerUnavailable(String) }
  ```
- Consumes: Task 3's private composites (`Monitors.cValue` ORs the 7 bits; the required mask is added in C), Task 4's store.

- [ ] **Step 1: `Monitors`**

```swift
public struct Monitors: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let machExceptions = Monitors(rawValue: KSCrashMonitorTypeMachException.rawValue)
    public static let signals        = Monitors(rawValue: KSCrashMonitorTypeSignal.rawValue)
    public static let cppExceptions  = Monitors(rawValue: KSCrashMonitorTypeCPPException.rawValue)
    public static let nsExceptions   = Monitors(rawValue: KSCrashMonitorTypeNSException.rawValue)
    public static let terminations   = Monitors(rawValue: KSCrashMonitorTypeTermination.rawValue)
    public static let hangs          = Monitors(rawValue: KSCrashMonitorTypeWatchdog.rawValue)
    public static let zombies        = Monitors(rawValue: KSCrashMonitorTypeZombie.rawValue)
    public static let `default`: Monitors = [.machExceptions, .signals, .cppExceptions, .nsExceptions, .terminations, .hangs]
    public static let all: Monitors = [.default, .zombies]
    var cValue: KSCrashMonitorType { KSCrashMonitorType(rawValue: rawValue) }
}
```

- [ ] **Step 2: `InstallConfiguration`, `Container`, `Locations`**

```swift
public struct InstallConfiguration: Sendable {
    public let namespace: String
    public var container: Container = .default
    public var monitors: Monitors = .default
    public var plugins: [any MonitorPlugin] = []
    public var maxReportCount = 50
    public var maxRunSummaryCount = 50
    public var searchesQueueNames = false
    public var memoryIntrospection: MemoryIntrospection = .disabled
    public var includesConsoleLog = false
    public var printsPreviousLog = false
    public var swapsCxaThrow = true
    public var usesSwiftAsyncStackTraces = false
    public var reportsResolvedHangs = false
    public var reportsCPUExceptions = false
    public var compactsBinaryImages = false
    public var unsafeCrashTimeCallbacks: UnsafeCrashTimeCallbacks?
    public init(namespace: String) { self.namespace = namespace }
}

public enum Container: Sendable, Equatable {
    case applicationSupport, caches, appGroup(String)
    public static var `default`: Container {
        #if os(tvOS)
        return .caches
        #else
        return .applicationSupport
        #endif
    }
}

extension InstallConfiguration {
    public struct Locations: Sendable, Equatable {
        public let root, reports, reportSidecars, runs, runSidecars, data: URL
    }
    public var locations: Locations { get throws {
        let base: URL
        switch container {
        case .applicationSupport: base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        case .caches:             base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        case .appGroup(let id):
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { throw InstallError.containerUnavailable(id) }
            base = url
        }
        let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let root = base.appendingPathComponent(String(cString: kscrash_namespaceIdentifier()), isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true).appendingPathComponent(bundleID, isDirectory: true)
        return Locations(root: root, reports: root.appendingPathComponent("Reports"), reportSidecars: root.appendingPathComponent("ReportSidecars"),
                         runs: root.appendingPathComponent("Runs"), runSidecars: root.appendingPathComponent("RunSidecars"), data: root.appendingPathComponent("Data"))
    } }
}
```

`Bundle.main.bundleIdentifier` is nil for command-line tools and some test hosts; the process name is the documented fallback.

- [ ] **Step 3: Install**

`Install+C.swift` builds `KSCrashCConfiguration_Default()`, sets `reportStoreConfiguration` paths from `locations` (`strdup`ed, released after the call), `monitors = configuration.monitors.cValue`, the bools, the class list, the callbacks (`willWriteReportCallback = configuration.unsafeCrashTimeCallbacks?.willWriteReport` and friends; the types are identical `@convention(c)` functions so they assign directly), and the plugins (`apis` array of `plugin.api.pointee` copies, `release` freeing it, exactly as the ObjC code did at `KSCrashInstallConfiguration.m` `toCConfiguration`). Then `kscrash_install(bundleID, root.path, &config)` and map `KSCrashInstallErrorCode` to `InstallError`. On success store the configuration and the plugins under the lock.

`KSCrash.swift`:

```swift
public final class KSCrash: Sendable {
    public static let shared = KSCrash()
    private struct State { var configuration: InstallConfiguration? }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private init() {}

    public func install(_ configuration: InstallConfiguration) throws {
        let locations = try configuration.locations
        try state.withLock { s in
            if s.configuration != nil { throw InstallError.alreadyInstalled }
            try installInC(configuration, locations: locations)     // Install+C.swift
            s.configuration = configuration
        }
    }
    public var installConfiguration: InstallConfiguration? { state.withLock { $0.configuration } }
}
```

`InstallConfiguration` contains `[any MonitorPlugin]` (class references) and `@convention(c)` pointers, both `Sendable`, so the struct is `Sendable` without `@unchecked`.

- [ ] **Step 4: Delete the ObjC front end and re-home the send**

Delete the files listed above. `KSCrash+Send.swift`'s `extension KSCrash` now extends the Swift class; its `store(...)` helper uses `kscrash_isInstalled()` and the C paths. `kscrash_install` drops `appName`. Port the deleted ObjC tests: `KSCrash_UserID_Tests` and the NSException/Watchdog facade cases move into `Tests/KSCrashTests/KSCrashInstallTests.swift` using the Swift facade; pure-C coverage stays in the C test files. `ksruncontext`/lifecycle notifications that `KSCrash.m` wired through app-state observers: check `grep -n "NSNotification\|UIApplication" Sources/KSCrashRecording/KSCrash.m` before deleting; anything found moves into `KSCrash.swift`'s install (today `KSCrash.m` wires only `kscm_nsexception_setOnEnabledHandler`, which dies with `uncaughtExceptionHandler`).

- [ ] **Step 5: Tests**

`InstallConfigurationTests.swift`:

```swift
func testDefaults() {
    let c = InstallConfiguration(namespace: "T")
    XCTAssertEqual(c.monitors, .default); XCTAssertEqual(c.maxReportCount, 50); XCTAssertEqual(c.maxRunSummaryCount, 50)
    XCTAssertNil(c.unsafeCrashTimeCallbacks); XCTAssertEqual(c.memoryIntrospection, .disabled); XCTAssertTrue(c.swapsCxaThrow)
    #if os(tvOS)
    XCTAssertEqual(c.container, .caches)
    #else
    XCTAssertEqual(c.container, .applicationSupport)
    #endif
}
func testLocationsLayout() throws {
    let l = try InstallConfiguration(namespace: "Ns").locations
    XCTAssertEqual(l.reports.lastPathComponent, "Reports")
    XCTAssertEqual(l.root.lastPathComponent, Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
    XCTAssertEqual(l.root.deletingLastPathComponent().lastPathComponent, "Ns")
    XCTAssertEqual(l.root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, String(cString: kscrash_namespaceIdentifier()))
}
func testUnavailableAppGroupThrows() {
    var c = InstallConfiguration(namespace: "Ns"); c.container = .appGroup("group.does.not.exist")
    XCTAssertThrowsError(try c.locations) { XCTAssertEqual($0 as? InstallError, .containerUnavailable("group.does.not.exist")) }
}
```

`MonitorsTests.swift`: `default` excludes zombies, `all` includes them, `cValue` of `[.hangs]` equals `KSCrashMonitorTypeWatchdog`, `[]` maps to `KSCrashMonitorTypeNone`. `KSCrashInstallTests.swift` (process-wide install, one test class, serial): install with a UUID namespace into `.caches`, assert `installConfiguration` round-trips, `locations.reports` exists on disk, a second `install` throws `.alreadyInstalled`, `installedPlugin` returns the `CMonitorPlugin` registered. The unit-test process installs once per run (the C core cannot uninstall), so this class is the one place that installs; mark other facade tests to run against an installed state or without one as documented.

- [ ] **Step 6: Build, test, commit**

Run: `swift build && swift test 2>&1 | tee "$SCRATCH/t5-facade.log" | tail -5`; ASan run. `make namespace` will shift symbols (files deleted); regenerate, never hand-edit.
Commit: `Add the Swift KSCrash facade and retire the Objective-C front end`.

---

### Task 6: Runtime surface: metadata, ids, exceptions, hangs, backtraces

**Files:**
- Create: `Sources/KSCrash/LiveMetadata.swift`
- Create: `Sources/KSCrash/KSCrash+Runtime.swift` (`runID`, `previousRunID`, `sessionID`, `previousTerminationReason`, `setUserID`, `metadata`, `reportException` x2)
- Create: `Sources/KSCrash/KSCrash+Hangs.swift` (`HangEvent`, `hangEvents`)
- Create: `Sources/KSCrash/Backtrace.swift` (`Backtrace`, `SymbolInformation`)
- Modify: `Sources/KSCrashRecording/include/KSCrashC.h` + `.c`: keep the `kscrash_setUserInfo*`/`kscrash_removeUserInfoValue` wrappers (the monitor header stays private) and add `bool kscrash_copyUserInfoValue(const char *key, KSCrashUserInfoValue *out)`, `void kscrash_enumerateUserInfoKeys(KSCrashUserInfoKeyCallback, void *context)`, `void kscrash_setUserID(const char *userID)` (the two calls `-[KSCrash setUserID:]` made: `kscm_userinfo_setString("com.kscrash.userid", userID)` then `kscm_lifecycle_observeUser(userID)`), `KSTerminationReason kscrash_getPreviousTerminationReason(void)` (wraps `ksruncontext_previousRunContext()->terminationReason`)
- Create: `Sources/KSCrashRecording/KSCrashC+NSException.m` with `void kscrash_reportNSException(NSException *exception, bool logAllThreads)`: registers `kscm_nsexception_setOnEnabledHandler` at load (the hook `KSCrash.m` registered in `-init`), keeps the `KSCrashCustomNSExceptionReporter *` it receives in a static, and forwards; a no-op with a `KSLOG_WARN` when the NSException monitor is not enabled (declared in `KSCrashC.h` under `#ifdef __OBJC__`)
- Test: `Tests/KSCrashTests/LiveMetadataTests.swift`, `KSCrashRuntimeTests.swift`, `BacktraceTests.swift`, `HangEventsTests.swift`

**Interfaces:**
- Produces (the spec's "The facade at runtime" and "Metadata" blocks verbatim): `LiveMetadata: MetadataStore`, `KSCrash.metadata: LiveMetadata`, `runID: String?`, `previousRunID: String?`, `sessionID: String?`, `previousTerminationReason: TerminationReason`, `setUserID(_:)`, `reportException(_ name:reason:language:lineOfCode:stackTrace:logAllThreads:terminateProgram:)`, `reportException(_ exception: NSException, logAllThreads:)`, `hangEvents: AsyncStream<HangEvent>`, `struct HangEvent { enum Change { started, updated, ended }; change; startTimestamp; endTimestamp }`, `struct Backtrace { addresses; isTruncated; count; static capture(thread:maxFrames:); capture(machThread:maxFrames:); symbolicate; quickSymbolicate }`, `struct SymbolInformation { returnAddress, callInstruction, symbolAddress: UInt; symbolName, imageName: String?; imageUUID: UUID?; imageAddress: UInt; imageSize: UInt64 }`.

- [ ] **Step 1: `LiveMetadata`**

```swift
public final class LiveMetadata: MetadataStore, Sendable {
    public subscript<V: MetadataValueRepresentable>(key: String) -> V? {
        get {
            var raw = KSUserInfoValue()
            guard kscrash_copyUserInfoValue(key, &raw) else { return nil }
            return V.decode(from: MetadataValue(raw))   // MetadataValue(raw) maps the C union; date -> the same value Date.metadataValue produces
        }
        set {
            guard let newValue else { kscrash_removeUserInfoValue(key); return }
            switch newValue.metadataValue {
            case .string(let s): kscrash_setUserInfoString(key, s)
            case .integer(let i): kscrash_setUserInfoInt(key, i)
            case .unsignedInteger(let u): kscrash_setUserInfoUInt(key, u)
            case .double(let d): kscrash_setUserInfoDouble(key, d)
            case .bool(let b): kscrash_setUserInfoBool(key, b)
            case .null: kscrash_removeUserInfoValue(key)
            case .array, .object: preconditionFailure("MetadataValueRepresentable never produces containers")
            }
        }
    }
    public func removeValue(forKey key: String) { kscrash_removeUserInfoValue(key) }
    public var keys: [String] { /* kscrash_enumerateUserInfoKeys with a callback collecting into an array, then sorted */ }
}
```

`Date` needs care: `Date.metadataValue` is whatever `MetadataValue.swift:145` makes it (check: if it is `.double(timeIntervalSince1970)` then the setter must call `kscrash_setUserInfoDate` for dates so the stitch emits a date; special-case `newValue as? Date` before the switch, and on read map `KSUserInfoValueDate` to the same `MetadataValue` shape `Date.metadataValue` produces so `Date.decode` round-trips).

- [ ] **Step 2: Runtime getters and exceptions**

```swift
extension KSCrash {
    public var runID: String? { kscrash_isInstalled() ? String(cString: kscrash_getRunID()) : nil }
    public var previousRunID: String? { let s = String(cString: kscrash_getLastRunID()); return s.isEmpty ? nil : s }
    public var sessionID: String? { kslifecycle_currentSessionID().map { String(cString: $0) } }
    public var previousTerminationReason: TerminationReason { TerminationReason(rawValue: String(cString: kstermination_reasonToString(kscrash_getPreviousTerminationReason()))) ?? .none }
    public func setUserID(_ userID: String?) { kscrash_setUserID(userID) }       // nil clears, as today
    public var metadata: LiveMetadata { LiveMetadata.shared }                    // one instance, holds nothing
    public func reportException(_ name: String, reason: String?, language: String?, lineOfCode: String?,
                                stackTrace: [String]?, logAllThreads: Bool, terminateProgram: Bool) {
        let frames = stackTrace.map { try? JSONEncoder().encode($0) }.flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }
        kscrash_reportUserException(name, reason, language, lineOfCode, frames, logAllThreads, terminateProgram)
    }
    public func reportException(_ exception: NSException, logAllThreads: Bool) { kscrash_reportNSException(exception, logAllThreads) }  // move the ObjC -reportNSException: body into a C-callable shim in KSCrashMonitor_NSException.m if no C entry exists
}
```

Before writing `reportException(_ exception:)`, check `grep -n "reportNSException" Sources/KSCrashRecording/*.m Sources/KSCrashRecording/Monitors/*.m` for the entry the ObjC facade used and expose it from C.

- [ ] **Step 3: `hangEvents`**

```swift
public struct HangEvent: Sendable, Equatable {
    public enum Change: Sendable { case started, updated, ended }
    public let change: Change
    public let startTimestamp: UInt64
    public let endTimestamp: UInt64
}
extension KSCrash {
    public var hangEvents: AsyncStream<HangEvent> {
        AsyncStream { continuation in
            let box = Unmanaged.passRetained(HangObserverBox(continuation))
            let token = kshang_addHangObserver({ change, start, end, ctx in
                Unmanaged<HangObserverBox>.fromOpaque(ctx!).takeUnretainedValue().continuation.yield(HangEvent(change: .init(change), startTimestamp: start, endTimestamp: end))
            }, box.toOpaque())
            continuation.onTermination = { _ in kshang_removeHangObserver(token); box.release() }
        }
    }
}
```

`HangEvent.Change.init(_ c: KSHangChangeType)` maps started/updated/ended and ignores `none`. The C observer fires on the watchdog thread; `yield` is safe from any thread.

- [ ] **Step 4: `Backtrace`**

```swift
public struct Backtrace: Sendable, Equatable {
    public let addresses: [UInt]
    public let isTruncated: Bool
    public var count: Int { addresses.count }
    public static func capture(thread: pthread_t, maxFrames: Int = 128) -> Backtrace? {
        var buffer = [UInt](repeating: 0, count: max(maxFrames, 1)); var truncated = false
        let n = Int(ksbt_captureBacktraceWithTruncation(thread, &buffer, Int32(buffer.count), &truncated))
        return n > 0 ? Backtrace(addresses: Array(buffer.prefix(n)), isTruncated: truncated) : nil
    }
    public static func capture(machThread: thread_t, maxFrames: Int = 128) -> Backtrace? { /* ksbt_captureBacktraceFromMachThreadWithTruncation */ }
    public static func symbolicate(_ address: UInt) -> SymbolInformation? { var info = KSSymbolInformation(); return ksbt_symbolicateAddress(address, &info) ? SymbolInformation(info) : nil }
    public static func quickSymbolicate(_ address: UInt) -> SymbolInformation? { /* ksbt_quickSymbolicateAddress */ }
}
```

The C `KSSymbolInformation` pointers (`symbolName`, `imageName`, `imageUUID`) are copied into Swift `String?`/`UUID?` in `SymbolInformation.init(_:)`.

- [ ] **Step 5: Tests**

`LiveMetadataTests` (run after the install in `KSCrashInstallTests`, same serial class or a shared installed fixture): set a String/Int/UInt/Double/Bool/Date and read each back typed; nil assignment removes; a wrong type reads nil; `keys` lists live keys. `KSCrashRuntimeTests`: `runID` is a UUID after install, `previousTerminationReason` is a case (not `.unknown`), `sessionID` non-nil once a session is cut (set a user id). `BacktraceTests` (port `KSBacktraceTests.swift` cases): `capture(thread: pthread_self())` is non-nil with `count > 0`, `maxFrames: 2` sets `isTruncated`, `symbolicate` of a known function address yields its name. `HangEventsTests`: subscribe, block the main thread past the 250ms threshold from a test with `.hangs` enabled, expect `.started` then `.ended`; cancelling the task removes the observer (`kshang_addHangObserver` count via a second subscription still working).

- [ ] **Step 6: Build, test, commit**

Run: `swift build && swift test 2>&1 | tee "$SCRATCH/t6-runtime.log" | tail -5`; ASan run.
Commit: `Add the facade's runtime surface`.

---

### Task 7: Plugins by type: DiscSpace, BootTime, MetricKit

**Files:**
- Create: `Sources/KSCrashDiscSpaceMonitor/DiscSpaceMonitor.swift`, `Sources/KSCrashBootTimeMonitor/BootTimeMonitor.swift` (Swift wrappers exposing `.plugin()`; the targets gain Swift sources, so their `cSettings`-only target definitions get a sibling Swift target or become mixed-language per the packaging rule in `.claude/rules/packaging.md`: read it first and follow it)
- Modify: `Sources/KSCrashDiscSpaceMonitor/KSCrashMonitor_DiscSpace.m:102`, `Sources/KSCrashBootTimeMonitor/KSCrashMonitor_BootTime.m:80` (delete the `__attribute__((constructor))` registration)
- Delete: `Sources/KSCrashMonitors/Monitors.swift` (the namespace enum)
- Modify: `Sources/KSCrashMonitors/MetricKit/MetricKitMonitor.swift` (`public static func plugin() -> MetricKitMonitor`; the instance is the plugin until the #867 layer replaces the class with `Monitor<MetricKitMonitor>`; `diagnosticReportIDs: [Report.ID]`)
- Modify: `Tests/KSCrashMonitorsTests/MetricKitMonitor_Tests.swift` (hold the instance), `Tests/KSCrashDiscSpaceMonitorTests`, `Tests/KSCrashBootTimeMonitorTests` (register explicitly)
- Modify: `Package.swift` (targets/products for the two wrappers), `.swiftpm/xcode/xcshareddata/xcschemes/KSCrash-Package.xcscheme` (a `BuildActionEntry` per new library target)

**Interfaces:**
- Produces:
  ```swift
  public enum DiscSpaceMonitor { public static func plugin() -> any MonitorPlugin }   // CMonitorPlugin(api: kscm_discspace_getAPI())
  public enum BootTimeMonitor { public static func plugin() -> any MonitorPlugin }
  extension MetricKitMonitor { public static func plugin() -> MetricKitMonitor }
  ```

- [ ] **Step 1: Wrappers and de-registration**

```swift
import KSCrash
public enum DiscSpaceMonitor {
    /// Register in `InstallConfiguration.plugins`. Linking this product no longer enables the monitor.
    public static func plugin() -> any MonitorPlugin { CMonitorPlugin(api: kscm_discspace_getAPI()) }
}
```

Remove the constructor functions. If `packaging.md` forbids mixed C/Swift targets, add `KSCrashDiscSpaceMonitorSwift`/`KSCrashBootTimeMonitorSwift` targets depending on the C ones and fold both into the existing `DiscSpaceMonitor`/`BootTimeMonitor` products.

- [ ] **Step 2: MetricKit by type**

Delete `Monitors.swift`; `MetricKitMonitor.plugin()` returns a new instance; the tests keep a `let monitor = MetricKitMonitor.plugin()` and pass it to install. `diagnosticReportIDs` becomes `[Report.ID]` using Task 2's `kscrs_addUserReport` out-param.

- [ ] **Step 3: Tests**

DiscSpace/BootTime: installing without the plugin leaves no `disk_space`/`boot_time` fields in a written report; installing with `plugins: [DiscSpaceMonitor.plugin()]` writes them (reuse the existing monitor test fixtures, now with explicit registration). MetricKit: `plugin()` instances are distinct, `installedPlugin(MetricKitMonitor.self)` returns the registered one after install.

- [ ] **Step 4: Build, test, commit**

Run: `swift build && swift test 2>&1 | tee "$SCRATCH/t7-plugins.log" | tail -5`.
Commit: `Register DiscSpace, BootTime and MetricKit as explicit plugins`.

---

### Task 7b: Sessions to Swift

Sessions are C by construction order only: cuts run on normal threads, and the
stitch reads `.sessions` files at delivery, never live state. Mirror the
metadata reshape. A Swift `SessionRecorder` owns the live session writer and
drives the C `kssw_*` engine; it cuts on user changes (from `setUserID`) and on
perceptibility transitions. The C Lifecycle monitor keeps app-state observation
and the mmap'd LifecycleData for termination inference, and notifies Swift of
transitions through a registered callback, so there is one observer and the
policy lives above it. Swift owns the user and the live session id.
Deletes `kscrash_notifyUserChanged` and `kscrash_getSessionID`. Rework the
Lifecycle C tests for the narrowed monitor; Swift tests cover recording.
Decided with the metadata reshape (2026-08-24); sized comparable or larger.

### Task 7c: Container metadata via variable-size kvs values

Lift the fixed value-size limits in `KSKeyValueStore` so a value can be any
length, then let `LiveMetadata` accept arrays and dictionaries by storing them
as JSON-encoded values (encode on set, decode on get). This is per-value JSON,
not a mirrored store; the scalars stay typed records. Includes the format
bump for variable-size records, reader compatibility for existing files, the
delivery-time stitch and run-summary merge decoding container values, and
lifting the 1024-byte string truncation. Decided 2026-08-24 during the Task 6
review (the assertion in `LiveMetadata`'s unreachable container branch is the
interim state).

### Task 7d: Pure-Swift disk and boot monitors (folded into Task 7, built 2026-08-24)

Replace the C kernels of DiskMonitor and BootMonitor with Swift: a timer poll
for statfs (free disk becomes poll-interval-stale instead of measured at the
crash; the at-crash refresh in addContextualInfoToEvent is the one thing Swift
cannot do), boot time read once at enable. Values travel through a run sidecar
and a delivery-time stitch into the typed `system` fields (stitching runs at
delivery, so a Swift plugin can do it; a reserved metadata key was considered
and rejected because it lands in the user section). Deletes both C targets and
their privacy manifests move to the Swift targets. Raised during the
Task 7 review (2026-08-24); do it with or after the typed-stitch work, which
gives the stitch a clean shape.

### Task 7e: Sibling-store ingest (deferred)

Under an app group the app and its extensions install sibling bundle-id
directories for one namespace, but each process sends only its own reports and
run summaries; the host does not ingest siblings. Deferred 2026-08-26 because
the candidate liveness rule (a `.run` summary proves a sibling run dead) fails
when summaries are disabled (`maxRunSummaryCount = 0`); host ingest needs a
real liveness signal (e.g. a per-run lock or heartbeat) before it can safely
read, send, or reclaim a sibling's data.

### Task 8: Deployment floor, Package, retirement sweep

**Files:**
- Modify: `Package.swift:202-208` (platforms: `.iOS(.v15), .tvOS(.v15), .watchOS(.v8), .macOS(.v12), .visionOS(.v1)`)
- Modify: `Samples/**/Project.swift` / Tuist manifests and `Samples/Tests` deployment targets to match (grep `deploymentTargets` under `Samples`)
- Modify: every `@available(iOS 13|14, macOS 10.15|11|12, tvOS 13|14, watchOS 6|7|8, *)` that the new floor makes redundant (`grep -rn "@available" Sources | grep -v "iOS 16\|iOS 17\|iOS 18\|iOS 26\|iOS 27"`), and `#if available` guards likewise
- Modify: `Sources/KSCrashRecording/include/KSCrashMonitorType.h` (final shape after Task 3), `KSCrashReportFields.h` (nothing to drop; verify), `KSCrashError.h` (the `NoActiveMonitors` code gone in Task 3; drop `InvalidParameter` if no C path returns it any more)
- Modify: `Tests/NamespaceTests/SPMApproach/CrashLibA/.../Library.m`, `CrashLibB` (install through the C API: `kscrash_install` with a `KSCrashCConfiguration`; they are ObjC libraries proving two namespaced copies coexist, and the ObjC facade they called is gone)
- Modify: `Makefile` / `scripts` if any reference deleted files (`grep -rn "KSCrashReportStore.h\|KSCrashInstallConfiguration" Makefile scripts .github`)
- Modify: `.github/workflows/*.yml` matrix entries that test below the floor (`unit-tests (iOS, ~18.2, 14, 16.2)` style rows pin Xcode/OS; raise any simulator OS below 15 / 8 / 12)

- [ ] **Step 1: Floor and availability sweep**

Set the platforms, then build; delete every `@available` / `#available` whose versions are at or below the floor and fix the resulting warnings.

- [ ] **Step 2: Namespace tests and leftovers**

`CrashLibA/B` call `kscrash_install` directly. Run `grep -rn "KSCrashInstallConfiguration\|CrashInstallConfiguration\|KSCrashReportStore\b\|CrashReportStore\|MonitorType\.\|Monitors\.metricKit\|setUserInfo(\|reportUserException\|addHangObserver\|crashedLastLaunch\|ReportID\b" Sources Tests Samples scripts .github` and clear every hit that is not the C store.

- [ ] **Step 3: Build, test, commit**

Run: `swift build && swift test 2>&1 | tee "$SCRATCH/t8-floor.log" | tail -5`; `swift build --product DiscSpaceMonitor` and `--product BootTimeMonitor`; `make namespace-check` and `make check-format`.
Commit: `Raise the deployment floor and sweep the retired surface`.

---

### Task 9: Samples and integration tests on the new surface

**Files:**
- Modify: `Samples/Common/Sources/LibraryBridge/InstallBridge.swift` (`InstallConfiguration`, `container` picker replaces `BasePath`, `isWritingReport` via `unsafeCrashTimeCallbacks` with `ReportSectionWriter` if available else the raw writer calls it makes today, `reportStore` property gone)
- Delete: `Samples/Common/Sources/LibraryBridge/CrashReportStore+Bridge.swift` (the sample's store listing becomes `try config.locations.reports` plus `FileManager`, or the `sendReports` result)
- Modify: `Samples/Common/Sources/SampleUI/Components/MonitorTypeView.swift` (seven `Monitors` toggles plus `default`/`all`), `Screens/InstallView.swift` (container picker), `Screens/MainView.swift`, `Screens/ReportingView.swift`
- Modify: `Samples/Common/Sources/IntegrationTestsHelper/InstallConfig.swift` (`namespace: String` replaces `installPath`; `container: .caches`; writes `locations` into the state file), `KSCrashState.swift` (drop the seven counters and `crashedLastLaunch`, add `previousTerminationReason` and `isAbnormal`), `ReportConfig.swift`, `UserReportConfig.swift` (`reportException`)
- Modify: `Samples/Tests/Core/IntegrationTestBase.swift:82-110,195-240,246-331` (the harness keeps `installUrl` as its scratch directory for the state/action files; KSCrash's reports directory is read from the state file the app writes, `state.locations.reports`), `Samples/Tests/WatchdogTests.swift:105,165`, `IntegrationTests.swift`, `TerminationReasonTests.swift` (`crashedLastLaunch` assertions become `state.previousTerminationReason.isAbnormal`)
- Modify: `Samples/Sources/LeaksTest.swift` (install + `metadata`)

**Interfaces:**
- Consumes Tasks 5 to 7. Produces nothing for later tasks.

- [ ] **Step 1: Helper and harness**

`InstallConfig` gains `public var namespace: String` and `public init(namespace: String)`; `install()` builds `InstallConfiguration(namespace:)`, sets `container = .caches` (the simulator/macOS test host can read it), applies the optional knobs, installs, then appends `KSCrash.shared.installConfiguration!.locations` (URL strings) to the test state file. `IntegrationTestBase` passes `InstallConfig(namespace: UUID().uuidString)` and resolves `reportsUrl` from the state once the app has installed (`waitForState`), replacing the `installUrl.appendingPathComponent("Reports")` lines at 195, 205, 235. Console-log lookup at line 143 reads `locations.data/ConsoleLog.txt`.

- [ ] **Step 2: Sample app**

`InstallBridge`: `@Published var container: Container = .default`, `config = InstallConfiguration(namespace: "Sample")`, the writing callback moved under `unsafeCrashTimeCallbacks`. `MonitorTypeView` lists the seven members with `default`/`all` buttons. The reports screen lists `try? config.locations.reports` contents by name and uses `sendReports` for delivery as it does today.

- [ ] **Step 3: Build and run**

Run from `Samples/`: `tuist generate` then `xcodebuild build-for-testing` for the macOS scheme, and the macOS integration tests (`xcodebuild test -scheme ... -destination 'platform=macOS'`), teeing to `$SCRATCH/t9-samples.log`. tvOS and watchOS `build-for-testing` for the sample targets.
Expected: builds; macOS integration suite green (note the local flakiness memory: rerun a flaky case once before reading a failure as real).
Commit: `Move the samples and integration tests to the Swift install`.

---

### Task 10: Docs

**Files:**
- Modify: `README.md:40-70` (Setup shows `InstallConfiguration(namespace:)` + `KSCrash.shared.install`, Custom User Data shows `metadata`, Hang Detection shows `.hangs` and `hangEvents`, the 2.6 deprecations section becomes a 3.0 migration list: renamed knobs, dropped members, `isAbnormal`, `reportException`, plugins by type, DiscSpace/BootTime explicit)
- Modify: `.claude/rules/monitors.md:8-20` (registration: `Monitors` option set, always-on set, plugins by type), `.claude/rules/monitor-sidecars.md:5-6,31` (file references, `<container>/KSCrash/<namespace>/<bundleID>/` layout, `ReportSidecars/<monitorId>/<UUID>.ksscr`), `.claude/rules/sessions.md` (key files: the ObjC store is gone; `RunSummary.id`), `.claude/rules/run-id.md` (report filename grammar if it mentions `-report-`), `.claude/CLAUDE.md` (Architecture: install is Swift; module list)
- Modify: `docs/design/2026-08-22-swift-install.md` Status section (built, deviations if any)
- Modify: public doc comments on every new Swift type (contract only)

- [ ] **Step 1: Write the docs**, then `grep -rn "installPath\|CrashInstallConfiguration\|sendAllReports\|setUserInfo\|reportUserException\|Monitors.metricKit\|productionSafeMinimal" README.md .claude docs/design/2026-08-22-swift-install.md` must return only the design doc's own "dropped" lines.

- [ ] **Step 2: Commit**: `Document the Swift install`.

---

### Task 10b: Publish the 2.6-to-3.0 migration guide

`docs/wiki/Migration-Guide-for-KSCrash-2.6-to-3.0.md` (written 2026-08-25,
mirroring the 2.5-to-2.6 wiki guide's structure) is committed in-repo rather
than the wiki for now. If it later moves to the wiki, the README's migration
table links to it then.

### Task 11: Full gate

- [ ] `make all` and `make namespace`, tree clean afterwards except the intended diff.
- [ ] `swift test 2>&1 | tee "$SCRATCH/gate-full.log" | tail -5`: 0 failures.
- [ ] `swift test --sanitize address 2>&1 | tee "$SCRATCH/gate-asan.log" | tail -5`: 0 failures.
- [ ] `swift test --build-system native 2>&1 | tee "$SCRATCH/gate-aggregate.log" | tail -5` (aggregate single-process shape): 0 failures.
- [ ] `xcodebuild test` on the watchOS and tvOS simulators for `KSCrashTests`, `KSCrashRecordingTests`, `KSCrashReportModelTests` (the platform builds do not compile test bundles; the tests must run), teed.
- [ ] Samples: macOS `xcodebuild test`, tvOS/watchOS `build-for-testing`.
- [ ] Every intermediate commit builds: `git rebase --exec 'swift build' <base>` or a loop over `git rev-list`.
- [ ] Report the tallies with the log paths; no push without approval.

---

## Self-review notes

- Spec coverage: facade and naming (Task 5), `InstallConfiguration` with `Locations`, `Container`, `MemoryIntrospection`, `UnsafeCrashTimeCallbacks` (Task 5), `Monitors` (Tasks 3, 5), plugins and DiscSpace/BootTime/MetricKit (Tasks 5, 7), runtime surface incl. `isAbnormal`, `reportException`, `hangEvents`, `Backtrace` (Tasks 1, 6), `MetadataStore`/`LiveMetadata` (Tasks 1, 3, 6), store identity and typed ids (Tasks 1, 2, 4), what moves to Swift / stays C (Tasks 2, 4), modules and products (Tasks 5, 7, 8), deployment floor (Task 8), `InstallError` (Tasks 3, 5), retirement (Tasks 4, 5, 8), samples (Task 9), docs (Task 10).
- Known dependency on the extension branch: `installedPlugin` and `MetricKitMonitor.plugin(config)` take the #867 `Monitor<M>`/`CrashMonitor` shape when that branch lands; until then Task 5's `installedPlugin` is constrained to `MonitorPlugin` and Task 7's `plugin()` returns the instance. Recorded in the design doc; no work here depends on #867 being merged.
