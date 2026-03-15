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

Built-in monitors are registered via `KSCrashMonitorType` flags. External monitors can be added as plugins via `KSCrashConfiguration.plugins` (Swift: `MonitorPlugin`, ObjC: `KSCrashMonitorPlugin`), which wrap a `KSCrashMonitorAPI` and are registered at install time via `kscm_addMonitor()`. The `Monitors` Swift module provides ready-made plugins (e.g., `Monitors.metricKit`).

### Watchdog Monitor

The watchdog monitor uses a fixed 250ms threshold to detect hangs on the main thread. This threshold is intentionally not configurable — it aligns with Apple's definition of a "hang" (250ms+) and should not be changed. See `KSCrashMonitor_Watchdog.h` for the rationale.

### KSCrashMonitorFlagAsyncSafe

Each monitor declares flags via its `monitorFlags()` callback. If a monitor's `setEnabled()` implementation is async-signal-safe (no ObjC, no locks, no heap allocation), it should declare `KSCrashMonitorFlagAsyncSafe`. Currently only Signal and MachException do this. The crash handling path uses `kscmr_disableAsyncSafeMonitors()` to disable only these monitors (to restore original handlers for other crash reporters). Monitors that do not declare this flag (e.g., Lifecycle, Deadlock, Watchdog, Termination) are skipped during crash-time disable because their `setEnabled()` uses ObjC messaging or other non-signal-safe operations, and they don't need cleanup since the process is terminating. If you write a new monitor whose `setEnabled()` uses ObjC or locks, do **not** set `KSCrashMonitorFlagAsyncSafe`.
