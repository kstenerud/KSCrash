# Swift install

Design for issue #886, the install half of the Swift front end: the `KSCrash`
facade, `InstallConfiguration`, monitors and plugins, the runtime surface, and
the store identity scheme. Folds in #889 (send-time store to Swift). Builds on
the Swift send landed on `ac/sessions` (#882) and `ac/reports` (#898). Targets
3.0. Working reference, not committed.

## Status

Designed 2026-08-22 on `ac/reports`. Built on `ac/install` 2026-08-22..25,
Tasks 1-10, each reviewed before commit.
Deviations from the design as written:

- Metadata went further than designed: the C userInfo facade was deleted
  outright; `LiveMetadata` owns the run's UserInfo sidecar store directly
  (`SidecarMetadata` in `KSCrashMonitorPlugins` is the shared mechanics), and
  the UserInfo monitor is stitch-only.
- Sessions moved to Swift (`SessionRecorder` drives the C `kssw_*` engine; the
  session store gained an internal append/decode lock); `kscrash_getSessionID`
  and the user-changed C entry point no longer exist.
- DiscSpace/BootTime became pure Swift (`DiskMonitor`/`BootMonitor` products,
  `SidecarMetadataMonitorPlugin` + delivery stitch + `Poller`); their C targets
  are gone.
- The kvs gained `kskvs_lookup` for single-key reads.
- A metadata-store failure degrades install loudly (`metadata.unavailableReason`)
  instead of failing it.

Parked follow-ups live in the plan doc as Task 7c (container metadata via
variable-size kvs values).

Locked inputs this design executes (not re-decided here): Swift-only front end
with no `@objc` shims; iOS 15 deployment floor; the front end lands in the
existing `KSCrash` module and cuts over at the end; derived install paths with
no user-supplied paths; one identity scheme for reports and run summaries; the
crash-time core and the reclaim sweep stay C.

## Summary

Replace the Objective-C `KSCrash` class, its install configuration and its
report store with a Swift facade that reads like the send already does:
`KSCrash.shared.install(config)` on a `Sendable` final class, a value-type
`InstallConfiguration` built from a required namespace, a seven-member
`Monitors` option set, plugins registered by type, and a runtime surface that
drops everything derived or deprecated. Reports get the run summaries' identity
scheme (timestamp-named files, UUID inside) and typed `Identifiable` ids, and
the Swift store talks to C directly.

## API

The literal code an app types:

```swift
import KSCrash

// Install once, as early as possible. Synchronous and throwing.
var config = InstallConfiguration(namespace: "MyApp")
config.monitors = [.default, .zombies]
config.plugins = [MetricKitMonitor.plugin(.init(threadcrumbEnabled: true))]
config.container = .appGroup("group.com.example")
config.memoryIntrospection = .enabled(excludingClasses: ["Secret"])
config.unsafeCrashTimeCallbacks = UnsafeCrashTimeCallbacks(isWritingReport: { plan, writer in ... })
try KSCrash.shared.install(config)

// Runtime.
KSCrash.shared.setUserID("user-42")
KSCrash.shared.metadata["theme"] = "dark"
let sessionID = KSCrash.shared.sessionID
if KSCrash.shared.previousTerminationReason.isAbnormal { ... }
let mk = KSCrash.shared.installedPlugin(MetricKitMonitor.self)
for await hang in KSCrash.shared.hangEvents { ... }

// Send, unchanged from #898 except for the typed ids.
let result = try await KSCrash.shared.sendReports(with: SendConfiguration(reportPipeline: [...]))
try await KSCrash.shared.sendReports(with: sendConfig, only: [result.kept[0].id])
```

### The facade

```swift
public final class KSCrash: Sendable {
    public static let shared: KSCrash
    public func install(_ configuration: InstallConfiguration) throws
    public var installConfiguration: InstallConfiguration? { get }      // nil until install succeeds
    public func installedPlugin<M: CrashMonitor>(_ type: M.Type) -> M?  // the live monitor instance
}
```

One process-wide singleton: the C core is single-instance, so a second
facade has no meaning. Not an actor: install is synchronous by necessity, the
getters are cheap C reads, and the send already hops off the caller's actor
inside the driver. The type keeps the name `KSCrash` inside module `KSCrash`;
verified in a scratch package that `KSCrash.shared`, unqualified sibling types
and the `@_exported` re-exports all resolve, and that only module-qualified
names of other types (`KSCrash.InstallConfiguration`) fail because the type
shadows the module. Accepted; no unprefixed type in the module needs
qualifying.

### InstallConfiguration

```swift
public struct InstallConfiguration: Sendable {
    public init(namespace: String)
    public let namespace: String

    public var container: Container = .default          // .applicationSupport, .caches on tvOS
    public var monitors: Monitors = .default
    public var plugins: [any MonitorPlugin] = []
    public var maxReportCount = 50
    public var maxRunSummaryCount = 50

    public var searchesQueueNames = false
    public var memoryIntrospection: MemoryIntrospection = .disabled   // .enabled(excludingClasses:)
    public var includesConsoleLog = false
    public var printsPreviousLog = false
    public var swapsCxaThrow = true
    public var usesSwiftAsyncStackTraces = false
    public var reportsResolvedHangs = false             // needs .hangs
    public var reportsCPUExceptions = false
    public var compactsBinaryImages = false

    public var unsafeCrashTimeCallbacks: UnsafeCrashTimeCallbacks?   // nil by default
}

public enum Container: Sendable {
    case applicationSupport, caches
    case appGroup(String)
    case url(URL)                               // a custom base; the layout still applies under it
    public static var `default`: Container      // .applicationSupport; .caches on tvOS
}

public enum MemoryIntrospection: Sendable {
    case disabled
    case enabled(excludingClasses: [String])    // class names recorded by name only
}

extension InstallConfiguration {
    public struct Locations: Sendable {
        public let root, reports, reportSidecars, runs, runSidecars, data: URL
    }
    public var locations: Locations { get throws }   // InstallError.containerUnavailable if the app group does not resolve
}

/// Runs inside the crash handler: other threads are suspended and the process
/// is about to die. Nothing here may allocate, lock, or touch the Swift or
/// Objective-C runtimes; `plan` says what is safe for the event being handled.
public struct UnsafeCrashTimeCallbacks: Sendable {
    public typealias WillWriteReport = @convention(c) (UnsafeMutablePointer<ExceptionHandlingPlan>, UnsafePointer<MonitorContext>) -> Void
    public typealias IsWritingReport = @convention(c) (UnsafePointer<ExceptionHandlingPlan>, UnsafePointer<ReportWriter>) -> Void
    public typealias DidWriteReport  = @convention(c) (UnsafePointer<ExceptionHandlingPlan>, UnsafePointer<CChar>) -> Void   // the report's id

    public var willWriteReport: WillWriteReport?
    public var isWritingReport: IsWritingReport?
    public var didWriteReport: DidWriteReport?
    public init(willWriteReport: WillWriteReport? = nil, isWritingReport: IsWritingReport? = nil,
                didWriteReport: DidWriteReport? = nil)
}

public typealias ExceptionHandlingPlan = KSCrash_ExceptionHandlingPlan
public typealias MonitorContext = KSCrash_MonitorContext
// ReportWriter is the C struct's existing Swift name (NS_SWIFT_NAME); no alias needed.

config.unsafeCrashTimeCallbacks = UnsafeCrashTimeCallbacks(isWritingReport: { plan, writer in
    ReportSectionWriter(writer)?.add("theme", "dark")   // the #867 wrapper, public in KSCrashMonitorPlugins
})
```

A mutable value type: `install` takes a copy, so nothing the app does to its
variable afterwards changes anything, and `let` everywhere would only make a
wall of initializer labels. `namespace` is identity, not a knob, so it is the
one `let`.

One source of truth for the knobs: `KSCrashCConfiguration_Default()` is the
only place a default value is written, `init(namespace:)` reads its initial
values from it, and the directory names come from the C store's
`KSCRS_DEFAULT_*_FOLDER` constants on both sides. The C config itself carries
only what a switch in C reads: the two counts, the monitor mask, the knobs,
the callbacks, the class list, the plugin tables; the store paths are derived
by the C install from the root, never passed. Two tests hold the sides
together: a default Swift configuration bridged to C equals the C default
field by field, and after install `locations` equals the paths the C store
reports. Adding a knob is still three edits (C field, Swift property, bridge
line); the round-trip test catches a missed one.

Paths are derived, never supplied:
`<container>/KSCrash/<namespace>/<bundleID>/{Reports,ReportSidecars,Runs,RunSidecars,Data}`.
The bundle id keeps two processes apart by construction; the namespace is the
family key, so under an app group the app and its extension install with the
same namespace and get sibling bundle-id directories instead of sharing one
Reports folder (the #867 branch's `<container>/KSCrash/Reports` layout changes
at its rebase). For now each process sends only its own reports and run
summaries; extensions take care of their own. Sibling ingest by the host is
deferred: the natural liveness rule (a `.run` summary proves the run dead)
does not hold when summaries are disabled, so host-side ingest needs a real
liveness signal first. The namespace is
also the isolation knob for tests and command-line tools now that user paths
are gone. Namespaces are not to be reused across processes that should not
share.

The three crash-time callbacks sit behind one property whose type carries the
standard library's word for the contract. The `Unsafe` prefix is at the
assignment site, one doc comment states the rules once, and the
`@convention(c)` types make the compiler reject a capturing closure, which
is the usual way a heap object gets smuggled into the handler. The C typedefs
are `NS_SWIFT_UNAVAILABLE` already, so the Swift names are new rather than
renamed. One C change: `didWriteReport` hands over the report's UUID as a C
string, since the `int64_t` id it delivers today no longer exists. The
writer pointer stays raw in the signature (it is a C calling convention in
the handler); `ReportSectionWriter`, the extension branch's public wrapper
promoted from the Profiler's private `UnsafeReportWriter`, is how it is
used, and `KSCrash` re-exports `KSCrashMonitorPlugins` for it. If this branch
builds before #867 lands, the Profiler's copy is promoted under #867's name
and location so the two converge rather than fork.

`locations` is the one resolver of the derived layout; `install` uses the
same code, so what the property reports is where the files go.

`memoryIntrospection` is one enum so an exclusion list cannot exist without
introspection.

Dropped: `installPath`, `reportStoreConfiguration` (flattened into the two
counts; `appName`, `reportsPath`, `runSummariesPath` are derived),
`userInfoJSON` (seeded the `user` section at install; the per-key store is an
mmap write, so the window between `install` returning and the first
`metadata` write is microseconds, and one shape beats two),
`deadlockWatchdogInterval`, `enableSigTermMonitoring`, `crashNotifyCallback`,
`reportWrittenCallback`.

### Monitors

```swift
public struct Monitors: OptionSet, Sendable {
    public static let machExceptions, signals, cppExceptions, nsExceptions   // in-process fatal sources
    public static let terminations   // OOM, thermal, watchdog kills; detected at the next launch
    public static let hangs          // main-thread hangs (the 2.x "watchdog")
    public static let zombies        // deallocated-object tracking; costs CPU and memory

    public static let `default`: Monitors = [.machExceptions, .signals, .cppExceptions,
                                             .nsExceptions, .terminations, .hangs]
    public static let all: Monitors = [.default, .zombies]
}
```

The 2.x type exposed 8 detectors, 4 infrastructure bits that were force-ORed
anyway, and 12 composite masks describing internal facts (which monitors are
async-safe, which a debugger breaks). Only the choices survive. The
infrastructure bits (System, ApplicationState, UserInfo, Resource) and
UserReported are always on: UserReported installs nothing, it is a bool gate
in front of `kscm_reportUserException`, so there is nothing to opt into.
`monitors = []` is the manual-only install (no automatic detection;
`reportException` still works). Debugger handling stays automatic; the masks
that drive it become private C. The members read as what is being monitored,
hence plural and `hangs` for `watchdog`.

### Plugins

```swift
public protocol MonitorPlugin: AnyObject, Sendable {
    var api: UnsafeMutablePointer<KSCrashMonitorAPI> { get }   // must outlive the install
}

config.plugins = [
    MetricKitMonitor.plugin(.init(threadcrumbEnabled: true)),  // the #867 layer: Type.plugin(config)
    DiscSpaceMonitor.plugin(), BootTimeMonitor.plugin(),
    CMonitorPlugin(api: my_monitor_getAPI()),                  // raw C table, was BasicMonitorPlugin
]
```

The registration shape is the extension branch's settled design
(`Monitor(Type.self, configuration)` with `Type.plugin(config)` as sugar, the
`CrashMonitor` protocol in the `MonitorPlugins` product); it is adopted, not
redesigned. Changes here: `MonitorPlugin` drops `NSObject`;
`BasicMonitorPlugin` becomes `CMonitorPlugin(api:)`; the `Monitors` namespace
enum (`Monitors.metricKit`) is deleted, plugins are named by type, which frees
`Monitors` for the option set; DiscSpace and BootTime stop self-registering
through `__attribute__((constructor))` at link time and become explicit
plugins, so the config is the complete list of what is on and nothing runs
because of a link line. They stay in their own products (linking them is what
pulls in the privacy-manifest "required reason" APIs).

`installedPlugin(_:)` returns the live `M` the `Monitor<M>` wrapper created at
install; raw `CMonitorPlugin`s have no Swift instance worth returning and are
listed by `installConfiguration.plugins`.

### The facade at runtime

```swift
extension KSCrash {
    public var runID: String? { get }                  // nil before install
    public var previousRunID: String? { get }          // nil on first launch
    public var sessionID: String? { get }
    public var previousTerminationReason: TerminationReason { get }

    public func setUserID(_ userID: String?)
    public var metadata: LiveMetadata { get }

    public func reportException(_ name: String, reason: String?, language: String?,
                                lineOfCode: String?, stackTrace: [String]?,
                                logAllThreads: Bool, terminateProgram: Bool)
    public func reportException(_ exception: NSException, logAllThreads: Bool)   // needs .nsExceptions

    public var hangEvents: AsyncStream<HangEvent> { get }   // one stream per subscriber
}

public struct HangEvent: Sendable {
    public enum Change: Sendable { case started, updated, ended }   // the C KSHangChangeType
    public let change: Change
    public let startTimestamp: UInt64      // monotonic ns, as the C callback delivers them
    public let endTimestamp: UInt64
}

extension TerminationReason {
    public var isAbnormal: Bool   // crash, hang, lowBattery, memoryLimit, memoryPressure, thermal, cpu, unexplained
}

public struct Backtrace: Sendable {   // the former KSCrash+Backtrace category, same C underneath
    public let addresses: [UInt]
    public let isTruncated: Bool          // hit maxFrames before the stack ended
    public var count: Int { addresses.count }

    public static func capture(thread: pthread_t, maxFrames: Int = 128) -> Backtrace?     // nil: could not capture
    public static func capture(machThread: thread_t, maxFrames: Int = 128) -> Backtrace?
    public static func symbolicate(_ address: UInt) -> SymbolInformation?                 // a Swift struct, String names
    public static func quickSymbolicate(_ address: UInt) -> SymbolInformation?
}
```

`runID` and `previousRunID` are new on the facade (both exist in C) so an app
can correlate its own telemetry with the run summaries it sends.
`crashedLastLaunch` is gone because it was exactly
`kstermination_producesReport(previousTerminationReason)`; that set is also
exactly "the run ended badly" (it excludes the benign kills osUpgrade,
appUpgrade, reboot and the non-terminations clean, firstLaunch, none), so the
one rule lives on the Swift `TerminationReason` as `isAbnormal`, MetricKit's
word for the same idea. `crashed` was rejected as overloaded by `.crash`, and
`unclean` alone would wrongly include an OS upgrade. `stackTrace` is `[String]?` only, which
makes `UserReportedInfo.backtrace: [String]?` exactly right and closes the
parked dictionary-frames finding; nothing in-tree ever passed dictionaries.
`hangEvents` replaces `addHangObserver` plus token; observers fire on the
watchdog thread and the stream's buffer decouples them. `Backtrace.capture`
returns a value instead of filling a buffer; the C returns 0 for every
failure and cannot say which, so the Swift result is nil rather than a thrown
error with invented cases. If the C later reports why, `capture` can start
throwing without changing the struct.

Dropped: the deprecated `userInfo` dictionary and
`currentSnapshotUserReportedExceptionHandler`; `uncaughtExceptionHandler` (a
raw handler pointer nobody in-tree reads); `reportStore` (internal now);
`systemInfo` (a camelCase dictionary that is not the report's `system` section;
every report carries the typed `SystemInfo`); the seven counters
(`activeDurationSinceLastCrash`, `backgroundDurationSinceLastCrash`,
`launchesSinceLastCrash`, `sessionsSinceLastCrash`, `activeDurationSinceLaunch`,
`backgroundDurationSinceLaunch`, `sessionsSinceLaunch`), all of which every
report already carries in `system.application_stats`
(`SystemInfo.applicationStats`), so nothing leaves the report.

### Metadata

```swift
// KSCrashReportModel
public protocol MetadataStore {
    subscript<V: MetadataValueRepresentable>(key: String) -> V? { get set }
    mutating func removeValue(forKey key: String)
    var keys: [String] { get }
}
public struct Metadata: MetadataStore, Codable, Sendable { ... }   // today's type; Report.metadata: Metadata?

// KSCrash
public final class LiveMetadata: MetadataStore, Sendable { ... }   // write-through to the C user-info store
extension KSCrash { public var metadata: LiveMetadata { get } }

KSCrash.shared.metadata["theme"] = "dark"       // one kscm_userinfo_setString under the C lock
KSCrash.shared.metadata.removeValue(forKey: "theme")
let theme: String? = KSCrash.shared.metadata["theme"]
let same: String? = report.metadata?["theme"]   // identical read surface on the report
```

One protocol, two stores: the report's struct and a live view onto the C
key-value store. The live one holds nothing: every write is the matching C
setter under the user-info monitor's `os_unfair_lock`, the only lock; there is
no in-memory mirror (two copies of the same data diverge, and a second lock in
front of the real one buys nothing). Scalars only, and that falls out of what
exists: `MetadataValueRepresentable` is conformed to by exactly `String`,
`Bool`, `Int`, `Int64`, `UInt64`, `Double`, `Date`, one per C setter; arrays
and dictionaries conform only to `MetadataValueConvertible`, so the protocol's
subscript cannot take them. Nested values a crash-time callback wrote into
`user` stay readable on `Metadata` through its existing `value(forKey:as:)`
and `decoded(as:)`, which are not part of the protocol. Reads need one small C
addition, a per-key lookup under the same lock (the store is append-only with
tombstones, so it is the existing iterate with a key match); nothing reads in
the common case. `KSCrash.shared.metadata` is typed as the class, not `some
MetadataStore`, so subscript assignment compiles through a get-only property.
The six `setUserInfo` overloads and `removeUserInfoValue` go.

## The store

### One identity scheme

Report files become `<eventWallClockNs>-<report.id>.json` inside `Reports/`,
mirroring `<startNs>.run` with `run_id` inside. The name carries order only
(string sort = oldest first, no file opened); the UUID inside is the identity
and cannot drift. `report.id` is already minted at crash time
(`ksid_generate` into `ctx->eventID` in `KSCrashMonitor.c`, async-signal-safe).
Report sidecars are keyed by the same UUID:
`ReportSidecars/<monitorId>/<report.id>.ksscr`. The `<app>-report-` prefix
goes; the namespace and bundle-id directories already say whose reports these
are. The write-time reaper that enforces `maxReportCount` becomes a string
sort of names. Every report the store accepts must have an id: crash reports
do; for `kscrs_addUserReport` payloads the store mints one when the report
lacks it, since the filename needs it.

### Typed ids

```swift
extension Report: Identifiable {
    public struct ID: Hashable, Codable, Sendable, LosslessStringConvertible, ExpressibleByStringLiteral {
        public let uuid: UUID
        public init(uuid: UUID)
        public init?(_ string: String)   // nil unless it parses as a UUID
        // a string literal that is not a UUID traps: a literal is a constant, so that is a programming error
    }
    public var id: ID { report.id }      // ReportInfo.id is Report.ID, not String
}
extension RunSummary: Identifiable { public struct ID ... }   // runID is RunSummary.ID

public protocol SendPayload: Identifiable where ID: Hashable & Sendable {}
try await KSCrash.shared.sendReports(with: config, only: [report.id])
try await KSCrash.shared.sendRunSummaries(with: config, only: [summary.id])
```

A report id and a run id are different types, so mixing them is a compile
error instead of a no-op. Every id the model carries is validated at decode:
a malformed `report.id` or `run_id` fails `UUID` parsing and the payload lands
in `.kept(decodeError)` like any other bad payload. The store's filename
parser uses the same type, so a file whose name does not carry a valid UUID
is not a report. `Codable` encodes the uppercase string, so the wire format is
untouched. `public typealias ReportID = Int64` is deleted, and the store-id
versus payload-id split that #898 round 3 patched around disappears. A
`Session.ID` follows the same pattern later if wanted.

### What moves to Swift (#889)

The `Store` stops going through the Objective-C `KSCrashReportStore` (deleted
with the rest of the ObjC front end) and talks to C directly: listing is a
Swift directory scan with the name grammar above, ordering and the
selective-send filter are Swift, removal is Swift (report file, then its
sidecars), retention pruning stays where #898 round 1 put it. Reading stays
one C call by path, because the delivery-time stitch walks the monitor tables
over CF dictionaries and that is C by nature: bytes in, stitched bytes out,
decoded in Swift.

### What stays C

The crash-time path (id and path minting, `kscrs_getNextCrashReport`,
finalize), the write-time reaper, `kscrs_addUserReport`, the live-run peek,
and the reclaim sweep (settled in #898 round 5 as hardened C). The C store
shrinks to its crash-time and stitch duties.

## Modules and products

`import KSCrash` is the one consumer import: the `KSCrash` product holds the
facade, `InstallConfiguration`, `Monitors`, `LiveMetadata`, `Backtrace`, the
send, and re-exports `KSCrashReportModel` as today. `KSCrashRecording` stays a
product but is no longer where anyone looks: its ObjC front end is deleted
(`KSCrash`, `KSCrashInstallConfiguration`, `KSCrashReportStoreConfiguration`,
`KSCrashReportStore`, `KSCrashMonitorPlugin`/`KSCrashBasicMonitorPlugin`, the
Hang, UserInfo, Backtrace and Namespace categories), and what remains is the C
engine plus four ObjC utilities that are features in their own right and not
the front end: `AppMemoryTracker`, `AppStateTracker`, `CPUTracker`,
`Threadcrumb` (with `AppMemory`). Those stay reachable through the re-export
and get their own Swift ports later. C headers a plugin author needs
(`KSCrashMonitorAPI`, the exception-handling plan, the writer callback
typedefs) stay public C. `Monitors`, `MonitorPlugins`, `Profiler`,
`DiscSpaceMonitor`, `BootTimeMonitor` are unchanged as products; the last two
stop self-registering.

## Deployment floor

iOS 15 / tvOS 15 / watchOS 8 / macOS 12, visionOS 1 unchanged. Nothing in the
API forces it (concurrency back-deploys); it is the 3.0 decision and it lets
the `@available` noise go.

## Install errors

```swift
public enum InstallError: Error {
    case alreadyInstalled, pathTooLong, couldNotCreatePath, couldNotInitializeStore,
         couldNotInitializeMemory, couldNotInitializeCrashState, couldNotSetLogFilename
    case containerUnavailable(String)   // an app group that does not resolve
    case invalidConfiguration(String)   // refused before anything is touched, the string says why
}

`install` validates the configuration first: the namespace is a single
directory name, the counts are not negative, excluded class names are not
empty, every plugin table has its required entries and a unique, non-empty
monitor id. A bad configuration fails at the call site rather than as a
missing directory or a dead monitor later.
```

`noActiveMonitors` goes: with UserReported always on there is always an
active monitor, so `monitors = []` is a valid manual-only install. Gone from
the C API with the ObjC front end: the install-seeded `userInfoJSON` (config
field, `kscrash_setUserInfoJSON`/`getUserInfoJSON`, and the writer's JSON
user section; the `user` section at crash time is the callback's alone, the
per-key store is stitched at delivery), the five deprecated `kscrash_notify*`
no-ops, and `kscrash_install`'s `appName`. The framework version constants
live in `KSCrashVersion.h`.

## What gets retired

The Objective-C front end listed under Modules and products; the C-level
`KSCrashMonitorType` composites and deprecated aliases; `ReportID`; the
`Monitors` namespace enum; the constructor self-registration in DiscSpace and
BootTime; the `userInfoJSON` install seed; the Swift `setUserInfo` overloads.
The samples and integration tests move to the new surface.

## Decisions and deviations

Recorded because an alternative was on the table:

- Entry point: static `KSCrash.install(config)` returning an instance, and a
  statics-only namespace, both passed over for the shared singleton that the
  send already established.
- Type name: `ReliabilityReporter` floated and dropped; `CrashReporter` and
  nesting the types under the class passed over. `KSCrash` stays.
- Paths: optional namespace (bundle id only) and namespace-only (defaulting to
  the bundle id) passed over for required namespace plus bundle id.
- `InstallConfiguration` immutability asked and declined; value semantics
  already give the safety.
- Callbacks: left flat on the config passed over for the single
  `unsafeCrashTimeCallbacks` property.
- `Container.url(URL)` added at review: a custom base keeps the derived
  layout (namespace and bundle id) underneath, so the separation invariant
  holds; it is what tests and the integration harness use.
- Plugins accessor: `monitor(_:)` renamed `installedPlugin(_:)` so it lives in
  the plugin vocabulary, `monitors` being the option set.
- Metadata: an in-memory mirror with diffing REJECTED (two copies of one
  datum, a second lock); a JSON value slot and dot-path flattening for nested
  values both REJECTED (the live store is scalars, fast and crash-resilient);
  `MetadataAccessible` rejected as reading like accessibility,
  `MetadataEditable`/`MetadataWritable` passed over for the noun
  `MetadataStore`.
- Ids: raw `String` and bare `UUID` passed over for per-kind `Identifiable`
  structs.
- The extension branch's `installForExtensionReporting(with:)` becomes a
  second install entry on this facade at #867's rebase, under the same
  namespace and container rules; not designed here.

## Naming

`KSCrash`, `InstallConfiguration`, `Container`, `Monitors`,
`MemoryIntrospection`, `UnsafeCrashTimeCallbacks`, `MonitorPlugin`,
`CMonitorPlugin`, `LiveMetadata`, `MetadataStore` (protocol), `HangEvent`,
`Backtrace`, `SymbolInformation`, `InstallError`, `Report.ID`, `RunSummary.ID`,
`InstallConfiguration.Locations`, `ExceptionHandlingPlan`, `MonitorContext`,
`UnsafeCrashTimeCallbacks.{WillWriteReport,IsWritingReport,DidWriteReport}`;
`ReportSectionWriter` is #867's name, reused.

## Build sequence

High level; the plan has the tasks.

1. Model: `MetadataStore` protocol, `Report.ID` / `RunSummary.ID`,
   `TerminationReason.isAbnormal`.
2. C store: filename grammar and id minting, sidecar naming, reaper sort,
   id minting for added reports, per-key user-info read, required mask
   absorbs UserReported, composites go private.
3. Swift facade: `KSCrash`, `InstallConfiguration` and its types, `Monitors`,
   `MonitorPlugin`/`CMonitorPlugin`, `LiveMetadata`, `Backtrace`,
   `hangEvents`, `InstallError`, install on the C entry point.
4. Store: Swift listing/remove over the new grammar, C read by path, typed
   ids through the driver and `SendResult`.
5. Plugins: DiscSpace and BootTime wrappers, the `Monitors` enum deleted,
   MetricKit registration by type.
6. Retirement: the ObjC front end, `ReportID`, the composites; Package and
   scheme; deployment floor.
7. Samples, integration tests, README, rules docs.
