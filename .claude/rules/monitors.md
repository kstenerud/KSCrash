---
paths:
  - "Sources/KSCrashRecording/Monitors/**"
  - "Sources/KSCrashRecordingCore/**/KSCrashMonitor*.{c,h}"
  - "Sources/KSCrashBootTimeMonitor/**"
  - "Sources/KSCrashDiscSpaceMonitor/**"
  - "Sources/Monitors/**"
  - "Sources/KSCrashRecording/include/KSCrashMonitorType.h"
  - "Sources/KSCrashRecording/include/KSCrashMonitorPlugin.h"
---

## Monitors

Built-in monitors are registered via `KSCrashMonitorType` flags in `KSCrashC.c`. External monitors can be added as plugins via `KSCrashConfiguration.plugins` (Swift: `MonitorPlugin`, ObjC: `KSCrashMonitorPlugin`), which wrap a `KSCrashMonitorAPI` and are registered at install time via `kscm_addMonitor()`. The `KSCrashMonitors` Swift module provides ready-made plugins (e.g., `config.plugins = [MetricKitMonitor.plugin(.init())]`; see `.claude/rules/swift-monitors.md` for the Swift monitor layer).

### Monitor Reference

**Built-in monitors** (registered via `KSCrashMonitorType` flags):

| Monitor | ID | Detects | Flags | Sidecar | postSystemEnable |
|---|---|---|---|---|---|
| MachException | `"MachException"` | Mach-level exceptions (EXC_BAD_ACCESS, etc.) | AsyncSafe, DebuggerUnsafe | — | No |
| Signal | `"Signal"` | POSIX signals (SIGSEGV, SIGABRT, SIGTERM, etc.) | AsyncSafe | — | No |
| CPPException | `"CPPException"` | Uncaught C++ exceptions via `__cxa_throw` | — | — | No |
| NSException | `"NSException"` | Uncaught ObjC exceptions; also user-reported (non-fatal) | — | — | No |
| Deadlock | `"MainThreadDeadlock"` | Main thread blocked too long (deprecated — use Watchdog) | — | — | No |
| User | `"UserReported"` | User-triggered reports (API call) | — | — | No |
| System | `"System"` | Device/OS/app info (model, OS version, memory, disk) | — | Run (`KSCrash_SystemData`) | No |
| Termination | `"Termination"` | OS-level terminations that cannot be caught at runtime (OOM, thermal kill, CPU watchdog, reboot, upgrades) | — | — | Yes |
| Lifecycle | `"Lifecycle"` | App state transitions, cleanShutdown flag | — | Run (`KSCrash_LifecycleData`) | Yes |
| Zombie | `"Zombie"` | Messages sent to deallocated ObjC objects | — | — | No |
| Watchdog | `"Watchdog"` | Main thread hangs (250ms threshold); also fatal when the OS kills the app during a hang | — | Run (`KSHangSidecar`) | No |
| UserInfo | `"UserInfo"` | User-supplied key-value info (survives crashes) | — | Run (`KSKeyValueStore`) | No |
| Resource | `"Resource"` | Memory level/pressure, CPU, thermal, battery snapshots; optionally emits non-fatal EXC_RESOURCE reports on CPU warning/critical transitions (`enableCPUExceptionReporting`) | — | Run (`KSCrash_ResourceData`) | No |

**Auto-registered monitors** (registered via `__attribute__((constructor))` when their SPM module is linked):

| Monitor | ID | Module | Detects | postMonitorsEnabled | postSystemEnable |
|---|---|---|---|---|---|
| BootTime | `"BootTime"` | KSCrashBootTimeMonitor | Adds device boot time to reports | Yes | No |
| DiscSpace | `"DiscSpace"` | KSCrashDiscSpaceMonitor | Adds disk space info to reports | Yes | No |

**Plugin monitors** (registered via `KSCrashConfiguration.plugins`):

| Monitor | ID | Module | Detects | postSystemEnable |
|---|---|---|---|---|
| MetricKit | `"MetricKit"` | Monitors | Apple MetricKit diagnostics (async, hours/days post-crash). Built on the Swift monitor layer (`.claude/rules/swift-monitors.md`). | No |
| Profiler | `"profile"` (the id doubles as the report's `crash.error.type` and section key; never rename) | KSCrashProfiler | Sampling profiler (thread backtraces at intervals) | No |
| Corpse | `"Corpse"` | Monitors | Other processes' corpses, from an iOS 27 CrashReportExtension. In the extension, `KSCrash.installForExtensionReporting(with:)` registers it and `KSCrash.captureCrashReport` drives it. In the app that ingests the extension's reports, register it via `config.plugins = [CrashReportExtensionMonitor.plugin()]`: it detects nothing there and stitches in the final pass (priority `KSCrashStitchPriorityCorpse`, above every sidecar layer), replacing run-cached values with the report's embedded at-death snapshot data and then moving that snapshot out of `crash.error.Corpse` to the report root as `corpse` (a monitor section can only be written inside the error, but the snapshot describes the whole dead process). Its reports carry `error.type = "mach"` (context `errorTypeOverride`). Built on the Swift monitor layer (`.claude/rules/swift-monitors.md`). | No (never fires in extension mode) |

**Extension-reporting install** (`kscrash_installForExtensionReporting`): a reporter-only process that writes reports about other processes and detects no crashes of its own. It initializes the report store and pipeline, registers the given plugins, enables them, and fires `notifyPostMonitorsEnabled`; it runs no crash-detection monitors, no RunContext (so `notifyPostSystemEnable` never fires), no run id of its own (a capture loads the crashed run's), no run summaries, no console log, and no pruning. On the app side, `KSCrashReportStoreConfiguration.extensionAppGroupIdentifier` names the same App Group; `sendAllReports` then first moves the extension's reports into the app store (no re-IDing, nanosecond ID seeds make collisions a non-event, and the move never replaces an existing file), where they stitch against their run's sidecars and send like any other report.

### Event Classification

Three fields classify each event. See `run-context.md` for how these feed into termination reason detection.

| Field | Layer | Purpose |
|---|---|---|
| `isFatal` | Report | Whether the event killed or will kill the process |
| `isCleanExit` | Report | Only meaningful when `isFatal=true`; distinguishes clean exit (SIGTERM) from dirty crash |
| `cleanShutdown` | Lifecycle sidecar | Per-run flag — determines `crashedLastLaunch` on next launch |

Rules: when `isFatal=true`, `isCleanExit` must be explicitly set. When `isFatal=false`, `isCleanExit` is meaningless. Only the Lifecycle observer and clean-exit signal handler set `cleanShutdown=true`; dirty crashes explicitly set it to `false`.

**Remote-subject exception**: an event with `requirements.isRemoteSubject` (a corpse report written by a crash extension) describes another task's death. Its `isFatal` classifies the event for the report only; no process-local effect fires: no threads of the reporting process are suspended, no fatal handler state latches, monitors stay enabled, and Lifecycle leaves `cleanShutdown`/`fatalReported` untouched. Consumers that react to "this process is dying" must use `kscexc_isLocallyFatal()`, never bare `isFatal`.

**Event matrix:**

| Event | Monitor | isFatal | isCleanExit | cleanShutdown |
|---|---|---|---|---|
| Signal (SIGABRT, SIGSEGV, etc.) | Signal | true | false | false |
| SIGTERM | Signal | true | true | true |
| Mach exception | MachException | true | false | false |
| C++ exception | CPPException | true | false | false |
| NSException (real crash) | NSException | true | false | false |
| NSException (user-reported) | NSException | false | — | unchanged |
| Deadlock | Deadlock | true | false | false |
| Watchdog (standalone hang) | Watchdog | false | — | unchanged |
| Watchdog (unrecovered, OS kills app) | WatchdogStitch | true | false | false (never set) |
| Watchdog (recovered, stitched) | WatchdogStitch | false | — | unchanged |
| User report (terminate) | User | true | false | false |
| User report (non-fatal) | User | false | — | unchanged |
| Memory (breadcrumb, current run) | Memory | false | — | unchanged |
| Memory (OOM confirmed, stitched) | Memory | true | false | false (never set) |
| MetricKit (crash) | MetricKit | true | false | unchanged |
| MetricKit (hang) | MetricKit | false | — | unchanged |
| MetricKit (memory exception, iOS 27+) | MetricKit | true | false | unchanged |
| Profiler | Profiler | false | — | unchanged |
| CPU exception (warning/critical) | Resource | false | — | unchanged |
| Corpse capture (remote subject) | Corpse | true (for the subject) | false | unchanged (remote-subject exception) |
| Recrash (crash-in-handler) | Monitor.c | true | false | false |
| Normal exit (UIKit terminating) | Lifecycle observer | — | — | true |

### Sidecar Usage

Monitors that write sidecar data each have a corresponding `*Stitch.m` file that merges the data into reports at delivery time:

| Monitor | Sidecar scope | Data format | Stitch file |
|---|---|---|---|
| Lifecycle | Run | `KSCrash_LifecycleData` (mmap'd struct) | `KSCrashMonitor_LifecycleStitch.m` |
| Resource | Run | `KSCrash_ResourceData` (mmap'd struct) | `KSCrashMonitor_ResourceStitch.m` |
| System | Run | `KSCrash_SystemData` (mmap'd struct) | `KSCrashMonitor_SystemStitch.m` |
| UserInfo | Run | `KSKeyValueStore` (key-value file) | `KSCrashMonitor_UserInfoStitch.m` |
| Watchdog | Run | `KSHangSidecar` (mmap'd struct, 24 bytes) | `KSCrashMonitor_WatchdogStitch.m` |

### Monitor Lifecycle Callbacks

Monitors implement three enable-time callbacks:

- **`setEnabled(true)`** — called during `kscm_enableMonitors()`. Install handlers, create sidecars, begin monitoring.
- **`notifyPostMonitorsEnabled()`** — called during `kscm_notifyPostMonitorsEnabled()`, after all monitors are enabled but before RunContext init. Populate current-run sidecar data that RunContext needs for its analysis (e.g., BootTime writes `kern.boottime`, DiscSpace writes storage sizes). Optional (NULL-safe).
- **`notifyPostSystemEnable()`** — called during `kscm_notifyPostSystemEnable()`, after RunContext is initialized. Read previous-run analysis and act on it (e.g., Termination injects a retroactive report). Only called for enabled monitors.

### Watchdog Monitor

The watchdog monitor uses a fixed 250ms threshold to detect hangs on the main thread. This threshold is intentionally not configurable — it aligns with Apple's definition of a "hang" (250ms+) and should not be changed. See `KSCrashMonitor_Watchdog.h` for the rationale. The legacy Deadlock monitor (`KSCrashMonitorTypeMainThreadDeadlock`) is deprecated — use Watchdog instead.

### MetricKit Monitor

The MetricKit monitor turns each received diagnostic into a report. It consumes two delivery mechanisms: the legacy `MXMetricManagerSubscriber` handles `MXDiagnosticPayload`s (crash, hang, metrics) on every OS version, and on iOS 27+ the `MetricManager.diagnosticReports` async stream adds memory exceptions, the only source of `MemoryExceptionDiagnostic`. Every other case of that stream is ignored, so the two paths never overlap. The stream code is gated to Xcode 27+ (Swift 6.4) targeting iOS device or simulator; under Xcode 26 the package builds without it. The two mechanisms deliver on different threads, so skeleton-report production is serialized with a dedicated lock (`skeletonLock`). Each added report posts `diagnosticReportAddedNotification` with that report's id in `userInfo`; per-diagnostic handling lives in one `MetricKitMonitor+<Kind>Diagnostic.swift` file per kind.

`MXCrashDiagnostic` becomes a normal (fatal) crash report. A `MemoryExceptionDiagnostic` is modelled like the heuristic OOMs so `KSCrashDoctor` diagnoses it the same way: a fatal `.termination` with `terminationReason == .memoryLimit`, tagged `error.subtype == .memoryException` to tell it apart from other terminations, carrying the call stack the diagnostic provides. Crash and memory reports are the dead run's last moment, so they are left unfinalized and the store stitches that run's aligned sidecars in on read. `MXHangDiagnostic` becomes a **profile report**: its `callStackTree` is a sample-merged trie across all threads, not a single backtrace, so it is converted to weighted per-thread samples (`MXCallStackTree.extractProfileData`) and stored in `ProfileInfo`. The report's `error.type` is `.profile` and it carries the generic `error.subtype == .hang` to identify the hang; this is the same discriminator the watchdog-driven `HangProfiler` should use, rather than matching on a profile name. Because a hang has no per-sample timing, each sample carries a `count` (multiplicity) and the profile's monotonic timing fields are nil; only `duration` (the hang duration) is set. Hang reports are non-fatal, describe a moment within a run that kept going, and stay finalized, so they do not touch current-run `cleanShutdown` and no sidecar stitching applies. CPU/diskWrite/appLaunch diagnostics are not yet ingested (dump-only).

### KSCrashMonitorFlagAsyncSafe

Each monitor declares flags via its `monitorFlags()` callback. If a monitor's `setEnabled()` implementation is async-signal-safe (no ObjC, no locks, no heap allocation), it should declare `KSCrashMonitorFlagAsyncSafe`. Currently only Signal and MachException do this. The crash handling path uses `kscmr_disableAsyncSafeMonitors()` to disable only these monitors (to restore original handlers for other crash reporters). Monitors that do not declare this flag (e.g., Lifecycle, Deadlock, Watchdog, Termination) are skipped during crash-time disable because their `setEnabled()` uses ObjC messaging or other non-signal-safe operations, and they don't need cleanup since the process is terminating. If you write a new monitor whose `setEnabled()` uses ObjC or locks, do **not** set `KSCrashMonitorFlagAsyncSafe`.
