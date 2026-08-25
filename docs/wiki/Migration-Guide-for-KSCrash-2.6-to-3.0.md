# Migration Guide: KSCrash 2.6 to 3.0

KSCrash 3.0 replaces the Objective-C front end with a Swift API. The C recording
core, the on-disk report contents, and the crash-time behavior are unchanged;
what changed is how you install, configure, and talk to KSCrash at runtime.

Unlike 2.6, **3.0 is source-breaking**: the ObjC facade (`KSCrash.h`,
`KSCrashInstallConfiguration`, `KSCrashReportStore`) is gone, with no deprecated
aliases. Migration is mechanical; this guide maps every removed surface to its
replacement.

## Install

```swift
// 2.6
import KSCrashRecording
let config = CrashInstallConfiguration()
config.installPath = myPath
try KSCrash.shared.install(with: config)

// 3.0
import KSCrash
var config = InstallConfiguration(namespace: "MyApp")
try KSCrash.shared.install(config)
```

`InstallConfiguration` is a value type with one required argument, the
**namespace**: KSCrash derives its whole directory tree from it
(`<container>/KSCrash/<namespace>/<bundleID>/…`), so there is no `installPath`.
Pick where the tree lives with `config.container`: `.default`
(Application Support; Caches on tvOS), `.caches`, `.appGroup("group.id")`, or
`.url(customBase)`. `config.locations` returns the resolved directories
(`root`, `reports`, `runs`, …) without installing.

| 2.6                                   | 3.0                                        |
| ------------------------------------- | ------------------------------------------ |
| `installPath`                         | `namespace` + `container`                  |
| `enableQueueNameSearch`               | `searchesQueueNames`                       |
| `enableMemoryIntrospection` + `doNotIntrospectClasses` | `memoryIntrospection` (`.disabled` / `.enabled(excludingClasses:)`) |
| `addConsoleLogToReport`               | `includesConsoleLog`                       |
| `printPreviousLogOnStartup`           | `printsPreviousLog`                        |
| `enableSwapCxaThrow`                  | `swapsCxaThrow`                            |
| `enableSwiftAsyncStackTraces`         | `usesSwiftAsyncStackTraces`                |
| `enableHangReporting`                 | `reportsResolvedHangs`                     |
| `enableCPUExceptionReporting`         | `reportsCPUExceptions`                     |
| `enableCompactBinaryImages`           | `compactsBinaryImages`                     |
| `userInfoJSON` install seed           | removed; set `KSCrash.shared.metadata` after install |
| `maxReportCount` default 5            | default 50 (`maxRunSummaryCount` likewise) |
| `isWritingReportCallback` etc. on the config | `unsafeCrashTimeCallbacks` (see below)  |

Install throws `InstallError` (`.alreadyInstalled`, `.invalidConfiguration(…)`,
`.containerUnavailable(…)`, …) instead of `KSCrashInstallError` codes.

## Monitors

`MonitorType` masks and the composite sets (`.productionSafe`, `.required`,
`.optional`, …) are replaced by the `Monitors` option set with seven detectors:

```swift
config.monitors = .default            // everything but zombies
config.monitors = [.machExceptions, .signals, .nsExceptions, .hangs]
```

| 2.6 `MonitorType`      | 3.0 `Monitors`     |
| ---------------------- | ------------------ |
| `.machException`       | `.machExceptions`  |
| `.signal`              | `.signals`         |
| `.cppException`        | `.cppExceptions`   |
| `.nsException`         | `.nsExceptions`    |
| `.watchdog`            | `.hangs`           |
| `.termination`        | `.terminations`    |
| `.zombie`             | `.zombies`         |
| `.userReported`        | always on          |
| `.system`, `.applicationState` (infrastructure) | always on |
| composites (`.all`, `.productionSafe`, …) | `.default`, `.all`, or build your own set |

UserReported and the infrastructure monitors (System, Lifecycle, UserInfo,
Resource) can no longer be turned off; they capture nothing on their own.

## Plugins

Linking `DiscSpaceMonitor` or `BootTimeMonitor` no longer enables anything, and
the `Monitors.metricKit` singleton is gone. Optional monitors are plugin
*instances*:

```swift
config.plugins = [DiskMonitor.plugin(), BootMonitor.plugin(), MetricKitMonitor.plugin()]
// later:
let metricKit = KSCrash.shared.installedPlugin(MetricKitMonitor.self)
```

The products are renamed `DiskMonitor` and `BootMonitor` (`import
KSCrashDiskMonitor` / `KSCrashBootMonitor`); both are pure Swift now, recording
into a run sidecar and stitching `storage` / `freeStorage` / `boot_time` into
the report's `system` section at delivery. Custom monitors conform to
`MonitorPlugin` (module `KSCrashMonitorPlugins`); a C monitor table wraps in
`CMonitorPlugin(api:)`.

## Runtime surface

| 2.6                                          | 3.0                                            |
| -------------------------------------------- | ---------------------------------------------- |
| `setUserInfo(_:forKey:)` / per-key getters   | `KSCrash.shared.metadata["key"] = value` (a typed `MetadataStore`; same crash-safe store underneath) |
| `crashedLastLaunch`                          | `previousTerminationReason.isAbnormal`         |
| `sessionsSinceLaunch` and the other counters | removed; derive from run summaries' session records |
| `reportUserException(...)`                   | `reportException(_:reason:language:lineOfCode:stackTrace:logAllThreads:terminateProgram:)` |
| `report(_ exception:logAllThreads:)`         | `reportException(_ exception:logAllThreads:)`  |
| `KSCrash+Hang.h` `addHangObserver:`          | `KSCrash.shared.hangEvents` (an `AsyncStream<HangEvent>`) |
| `KSCrash+Backtrace.h`                        | `Backtrace.capture(thread:maxFrames:)`, `Backtrace.symbolicate(_:)` |
| `userID` setter                              | `setUserID(_:)` (unchanged meaning: metadata key + session boundary) |
| `systemInfo` dictionary                      | removed; the data is on every report's `system` section |

`runID`, `previousRunID`, and `sessionID` remain, now typed
(`RunSummary.ID`).

## Crash-time callbacks

The three callbacks move off the configuration's top level into
`UnsafeCrashTimeCallbacks`, named for what they are; the C function types are
unchanged, and everything in them must stay async-signal-safe:

```swift
var callbacks = UnsafeCrashTimeCallbacks()
callbacks.isWritingReport = { plan, writer in ... }   // C convention, no captures
config.unsafeCrashTimeCallbacks = callbacks
```

`didWriteReport` now receives the report id as a string (`const char *`)
instead of an `int64_t`.

## Reports and sending

Report identity changed: `ReportID` (an `Int64`) is gone. Reports are keyed by
`Report.ID`, a validated UUID that is also written into the report as
`report.id`, and filenames are `<timestamp>-<UUID>.json`. `CrashReportStore` is
gone with it; reading and deleting go through the async Swift send
(`sendReports(with:)` / `sendReports(with:only:)` with pipeline stages), which
is unchanged from 2.6's Swift send apart from the id type. A report also
carries `report.session_id`, the session open when it was finalized.

## Deployment floor

3.0 requires iOS 15, tvOS 15, watchOS 8, macOS 12, visionOS 1 (from iOS 13 /
tvOS 13 / watchOS 6 / macOS 10.15).

## If you were on the C API

`kscrash_install(installPath, KSCrashCConfiguration)` still exists and is the
supported path for embedders that cannot take Swift (the namespaced-library
setup uses it). The C user-info setters are gone; metadata is Swift-only.
