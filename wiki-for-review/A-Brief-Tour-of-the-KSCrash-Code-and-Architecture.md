This document introduces you to the main code areas of KSCrash and how they fit together.


### The Heart of KSCrash

The heart of KSCrash lives in [`KSCrashC.c`](https://github.com/kstenerud/KSCrash/blob/master/Sources/KSCrashRecording/KSCrashC.c)

This file contains all of the most important access points to the KSCrash system.

`KSCrashC.c` functions are also Objective-C/Swift wrapped in [`KSCrash.m`](https://github.com/kstenerud/KSCrash/blob/master/Sources/KSCrashRecording/KSCrash.m)

These are the main parts of `KSCrashC.c`:

#### Installation

`kscrash_install()` installs and prepares the KSCrash system to handle crashes. You configure KSCrash by creating and populating a `KSCrashCConfiguration` struct with your desired settings. Installation runs a four-step startup sequence:

1. **`kscm_enableMonitors()`** installs signal/Mach handlers and creates sidecars for the current run.
2. **`kscm_notifyPostMonitorsEnabled()`** lets monitors populate current-run sidecar data (e.g., boot time, disk space).
3. **`ksruncontext_init()`** reads previous run's sidecars, compares against current system state, and determines the termination reason.
4. **`kscm_notifyPostSystemEnable()`** tells monitors RunContext is ready so they can act on previous-run data (e.g., Termination injects a report).

#### Configuration

All of the main configuration settings are set via `KSCrashCConfiguration`.

#### App State

App state is tracked by `KSCrashAppStateTracker`, which observes UIKit/AppKit lifecycle notifications (didFinishLaunching, didBecomeActive, willResignActive, didEnterBackground, willTerminate, etc.) and translates them into `KSCrashAppTransitionState` values. The Lifecycle monitor consumes these transitions to maintain the `cleanShutdown` flag and other per-run state.

#### Crash Entry Point

The function `onExceptionEvent()` is the callback invoked by monitors when a crash or event occurs. It checks the exception handling plan, writes the JSON crash report via `kscrashreport_writeStandardReport()`, and then allows the crash to take its natural course.

#### User Reports and User Info

`KSCrashC.c` also exposes `kscrash_reportUserException()` for custom crash reports, `kscrash_addUserReport()` for arbitrary user reports, and the per-key user info setters (`kscrash_setUserInfoString()`, etc.).


### Detecting Crashes

Crashes are detected via one of the [monitors](https://github.com/kstenerud/KSCrash/tree/master/Sources/KSCrashRecording/Monitors), which set up the data in a consistent way before passing control to `onExceptionEvent()`.

Key monitors to understand:

- **Signal / MachException**: The traditional crash handlers. Async-signal-safe, run in crash context.
- **Watchdog** (`KSCrashMonitor_Watchdog.c`): Observes the main run loop with a CFRunLoopObserver. When the main thread blocks for 250ms+, it suspends all threads, writes a crash report, and starts updating a sidecar file with the latest hang duration. When the hang resolves, it either finalizes the report (if hang reporting is enabled) or deletes it.
- **Termination** (`KSCrashMonitor_Termination.m`): Runs during `notifyPostSystemEnable`, reads the RunContext's termination reason, and injects a retroactive report if needed.
- **Lifecycle** (`KSCrashMonitor_Lifecycle.m`): Tracks app state transitions and maintains the `cleanShutdown` flag in its sidecar.
- **Resource** (`KSCrashMonitor_Resource.m`): Periodically snapshots memory, CPU, thermal, and battery state into its sidecar.


### Sidecar System

Monitors that need to update data after writing the initial report use sidecar files. These are small mmap'd binary structs that can be updated with simple memory writes (the kernel flushes dirty pages to disk).

- **Per-report sidecars** (`Sidecars/<monitorId>/<reportID>.ksscr`): The Watchdog monitor uses this to store hang timing and recovery state.
- **Per-run sidecars** (`RunSidecars/<runID>/<monitorId>.ksscr`): Lifecycle, Resource, System, and UserInfo use these to store state that applies to all reports from a process run.

At next launch, the stitch pipeline in `KSCrashReportStoreC.c` reads each sidecar and calls the monitor's `createStitchedReport` callback to merge the data into the report JSON. Run sidecars are stitched first, then per-report sidecars.

Stitch files: `KSCrashMonitor_LifecycleStitch.m`, `KSCrashMonitor_ResourceStitch.m`, `KSCrashMonitor_SystemStitch.m`, `KSCrashMonitor_UserInfoStitch.m`, `KSCrashMonitor_WatchdogStitch.m`.


### RunContext

`KSCrashRunContext.m` is the cross-monitor analysis layer. It reads the previous run's Lifecycle, Resource, and System sidecars and determines why the previous process ended. The `KSTerminationReason` enum classifies the result (Clean, Crash, Hang, MemoryLimit, MemoryPressure, CPU, Thermal, LowBattery, Reboot, OSUpgrade, AppUpgrade, Unexplained, FirstLaunch).


### Recording Crashes

Crashes are recorded to a JSON file via `kscrashreport_writeStandardReport()` in [`KSCrashReportC.c`](https://github.com/kstenerud/KSCrash/blob/master/Sources/KSCrashRecording/KSCrashReportC.c). It makes use of a number of [tools](https://github.com/kstenerud/KSCrash/tree/master/Sources/KSCrashRecordingCore) to accomplish this.


### Report Management

Report management is primarily done in [`KSCrashReportStoreC.c`](https://github.com/kstenerud/KSCrash/blob/master/Sources/KSCrashRecording/KSCrashReportStoreC.c). This file also handles sidecar path generation, sidecar stitching into reports, report finalization, and orphaned sidecar cleanup.


### Reporting

Reporting is done using a system of [filters](https://github.com/kstenerud/KSCrash/tree/master/Sources/KSCrashFilters) and [sinks](https://github.com/kstenerud/KSCrash/tree/master/Sources/KSCrashSinks). Generally, to adapt KSCrash to your needs, you'd create your own sink.


### Installations

The [installation](https://github.com/kstenerud/KSCrash/tree/master/Sources/KSCrashInstallations) system makes the user API easier by hiding most of the filter/sink stuff behind a simpler interface.

No code depends on the installation code, and KSCrash can work just fine without it.


### Swift Modules

- **Report** (`Sources/Report/`): Strongly-typed Swift model for crash reports. `CrashReport<UserData>` is the main entry point.
- **Monitors** (`Sources/Monitors/`): Plugin monitors. Currently provides MetricKit integration.
- **KSCrashProfiler** (`Sources/KSCrashProfiler/`): Sampling profiler with ring buffer architecture.
- **SwiftCore** (`Sources/SwiftCore/`): Internal utilities (UnfairLock).
