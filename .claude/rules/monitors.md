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

Built-in monitors are registered via `KSCrashMonitorType` flags in `KSCrashC.c`. External monitors can be added as plugins via `KSCrashConfiguration.plugins` (Swift: `MonitorPlugin`, ObjC: `KSCrashMonitorPlugin`), which wrap a `KSCrashMonitorAPI` and are registered at install time via `kscm_addMonitor()`. The `Monitors` Swift module provides ready-made plugins (e.g., `Monitors.metricKit`).

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
| Watchdog | `"Watchdog"` | Main thread hangs (250ms threshold); also fatal when the OS kills the app during a hang | — | Report (`KSHangSidecar`) | No |
| UserInfo | `"UserInfo"` | User-supplied key-value info (survives crashes) | — | Run (`KSKeyValueStore`) | No |
| Resource | `"Resource"` | Memory level/pressure, CPU, thermal, battery snapshots | — | Run (`KSCrash_ResourceData`) | No |

**Auto-registered monitors** (registered via `__attribute__((constructor))` when their SPM module is linked):

| Monitor | ID | Module | Detects | postSystemEnable |
|---|---|---|---|---|
| BootTime | `"BootTime"` | KSCrashBootTimeMonitor | Adds device boot time to reports | Yes |
| DiscSpace | `"DiscSpace"` | KSCrashDiscSpaceMonitor | Adds disk space info to reports | Yes |

**Plugin monitors** (registered via `KSCrashConfiguration.plugins`):

| Monitor | ID | Module | Detects | postSystemEnable |
|---|---|---|---|---|
| MetricKit | `"MetricKit"` | Monitors | Apple MetricKit diagnostics (async, hours/days post-crash) | Yes |
| Profiler | `"Profiler"` | KSCrashProfiler | Sampling profiler (thread backtraces at intervals) | No |

### Event Classification

Three fields classify each event. See `run-context.md` for how these feed into termination reason detection.

| Field | Layer | Purpose |
|---|---|---|
| `isFatal` | Report | Whether the event killed or will kill the process |
| `isCleanExit` | Report | Only meaningful when `isFatal=true`; distinguishes clean exit (SIGTERM) from dirty crash |
| `cleanShutdown` | Lifecycle sidecar | Per-run flag — determines `crashedLastLaunch` on next launch |

Rules: when `isFatal=true`, `isCleanExit` must be explicitly set. When `isFatal=false`, `isCleanExit` is meaningless. Only the Lifecycle observer and clean-exit signal handler set `cleanShutdown=true`; dirty crashes explicitly set it to `false`.

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
| MetricKit | MetricKit | true | false | unchanged |
| Profiler | Profiler | false | — | unchanged |
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
| Watchdog | Report | `KSHangSidecar` (mmap'd struct, 24 bytes) | `KSCrashMonitor_WatchdogStitch.m` |

### Monitor Lifecycle Callbacks

Monitors implement two enable-time callbacks:

- **`setEnabled(true)`** — called during `kscm_enableMonitors()`. Install handlers, create sidecars, begin monitoring.
- **`notifyPostSystemEnable()`** — called during `kscm_notifyPostSystemEnable()`, after RunContext is initialized. Read previous-run analysis and act on it (e.g., Termination injects a retroactive report). Only called for enabled monitors.

### Watchdog Monitor

The watchdog monitor uses a fixed 250ms threshold to detect hangs on the main thread. This threshold is intentionally not configurable — it aligns with Apple's definition of a "hang" (250ms+) and should not be changed. See `KSCrashMonitor_Watchdog.h` for the rationale. The legacy Deadlock monitor (`KSCrashMonitorTypeMainThreadDeadlock`) is deprecated — use Watchdog instead.

### KSCrashMonitorFlagAsyncSafe

Each monitor declares flags via its `monitorFlags()` callback. If a monitor's `setEnabled()` implementation is async-signal-safe (no ObjC, no locks, no heap allocation), it should declare `KSCrashMonitorFlagAsyncSafe`. Currently only Signal and MachException do this. The crash handling path uses `kscmr_disableAsyncSafeMonitors()` to disable only these monitors (to restore original handlers for other crash reporters). Monitors that do not declare this flag (e.g., Lifecycle, Deadlock, Watchdog, Termination) are skipped during crash-time disable because their `setEnabled()` uses ObjC messaging or other non-signal-safe operations, and they don't need cleanup since the process is terminating. If you write a new monitor whose `setEnabled()` uses ObjC or locks, do **not** set `KSCrashMonitorFlagAsyncSafe`.
