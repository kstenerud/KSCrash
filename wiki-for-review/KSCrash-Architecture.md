KSCrash is implemented as a layered architecture. Each layer can in theory be compiled without the
layers adjacent or above.

    +-------------------------------------------------------------+
    |                         Installation                        |
    |        +----------------------------------------------------+
    |        |                  KSCrash                           |
    |    +--------------------------------------------------------+
    |    | Crash Reporting | Crash Recording | Crash Report Store |
    +----+-----------------+-----------------+--------------------+
    |       Filters        |     Monitors    |    Sidecars        |
    +----------------------+-----------------+--------------------+
    |                      |   RunContext     |
    +----------------------+-----------------+

### Installation

This top level layer provides a "clean" interface to the crash system. It is expected that the API
at this level will be largely idiomatic to the backend system it will be communicating with.

Primary entry points: KSCrashInstallation.h, KSCrashInstallationXYZ.h

### KSCrash

Handles high level configuration and installation of the crash recording and crash reporting
systems.

Primary entry point: KSCrash.h

### Crash Report Store

Provides storage and retrieval of crash reports, sidecar files, and other configuration data.
Handles sidecar stitching at report delivery time: each monitor's sidecar data is merged into the
report JSON before it leaves the device.

Primary entry point: KSCrashReportStore.h

### Crash Recording

Records a single crash event. This layer is implemented in async-safe C.

Primary entry point: KSCrashC.h

### Crash Reporting

Processes, transforms, and sends reports to a remote system.

Primary entry point: KSCrash.h

### Monitors

Detect application errors and non-fatal events. Built-in monitors are registered via
`KSCrashMonitorType` flags. Plugin monitors can be added via `KSCrashConfiguration.plugins`.

**Optional monitors** (enabled via `KSCrashMonitorType` flags):

| Monitor       | Report type     | Detects                                                            |
| ------------- | --------------- | ------------------------------------------------------------------ |
| MachException | `mach`          | Mach-level exceptions (EXC_BAD_ACCESS, etc.)                       |
| Signal        | `signal`        | POSIX signals (SIGSEGV, SIGABRT, SIGTERM, etc.)                    |
| CPPException  | `cpp_exception` | Uncaught C++ exceptions                                            |
| NSException   | `nsexception`   | Uncaught ObjC exceptions and user-reported errors                  |
| Watchdog      | `hang`          | Main thread hangs (250ms+), fatal when OS kills during hang        |
| Deadlock      | `deadlock`      | Main thread blocked; deprecated, use Watchdog                      |
| Termination   | `termination`   | OS-level terminations (OOM, thermal, CPU, reboot)                  |
| Zombie        | —               | Messages sent to deallocated ObjC objects (enhances other reports) |
| User          | `user`          | User-triggered reports via API                                     |

**Required monitors** (always enabled, cannot be disabled):

| Monitor   | Report type | Purpose                                   |
| --------- | ----------- | ----------------------------------------- |
| Lifecycle | —           | App state transitions, cleanShutdown flag |
| Resource  | —           | Memory, CPU, thermal, battery snapshots   |
| UserInfo  | —           | Per-key user data via mmap'd store        |
| System    | —           | Device/OS/app info                        |

Required monitors store per-run state in sidecar files that other monitors and RunContext use for
analysis. They don't generate reports on their own, with one exception: Resource can emit non-fatal
CPU exception reports when `enableCPUExceptionReporting` is set.

**Plugin monitors** (registered via `KSCrashConfiguration.plugins`):

| Monitor   | Module          | Report type                       | Detects                     |
| --------- | --------------- | --------------------------------- | --------------------------- |
| MetricKit | KSCrashMonitors | `mach` / `signal` / `nsexception` | Apple MetricKit diagnostics |

**Self-registering monitors** (register themselves on first use):

| Monitor  | Module          | Report type           | Purpose                        |
| -------- | --------------- | --------------------- | ------------------------------ |
| Profiler | KSCrashProfiler | `profile` (non-fatal) | Thread backtraces at intervals |

**Auto-registered monitors** (linked via SPM module):

| Monitor   | Module                  | Purpose                          |
| --------- | ----------------------- | -------------------------------- |
| BootTime  | KSCrashBootTimeMonitor  | Adds device boot time to reports |
| DiscSpace | KSCrashDiscSpaceMonitor | Adds disk space info to reports  |

Primary entry point: KSCrashMonitor.h

### Sidecars

Monitors can store auxiliary data alongside crash reports without modifying the main report JSON.
There are two scopes:

- **Per-report sidecars** (`Sidecars/`): Tied to a specific crash report. Used by the MetricKit
  monitor to store diagnostic payload data for later stitching.
- **Per-run sidecars** (`RunSidecars/`): Shared across all reports from one process run. Used by
  the Watchdog, Lifecycle, Resource, System, and UserInfo monitors to store mmap'd state that
  survives crashes; the Watchdog's holds hang timing and recovery state.

At report delivery time (next app launch), the stitch pipeline reads each monitor's sidecar and
merges it into the report JSON via `createStitchedReport` callbacks. This runs at normal startup, so
ObjC and heap allocation are safe.

### RunContext

The shared layer for cross-monitor state. On each launch, RunContext reads the previous run's
Lifecycle, Resource, and System sidecars, compares them against the current system state, and
determines a `KSTerminationReason` for why the previous process ended.

The result is cached and available via `ksruncontext_previousRunContext()`. The Termination monitor
reads this to decide whether to inject a retroactive report.

Primary entry point: KSCrashRunContext.h (internal header)

### Filters

Low level interface for transforming, processing, and sending crash reports.

Primary entry points: KSCrashReportFilter.h, KSCrashReportFilterXYZ.h
