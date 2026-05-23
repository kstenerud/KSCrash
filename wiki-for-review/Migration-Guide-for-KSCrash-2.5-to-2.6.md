# Migration Guide: KSCrash 2.5.x to 2.6

KSCrash 2.6 is fully backward-compatible with 2.5.x. No code changes are required to upgrade, but
you will see deprecation warnings for some APIs. This guide covers what changed and how to adopt the
new features.

## No Source-Breaking Changes

All renamed or removed APIs have deprecated aliases preserved. All new configuration fields default
to zero/nil, so existing `KSCrashCConfiguration` initializers continue to work.

## Deprecations

### Monitor Types

| Deprecated                             | Replacement                     |
| -------------------------------------- | ------------------------------- |
| `KSCrashMonitorTypeMainThreadDeadlock` | `KSCrashMonitorTypeWatchdog`    |
| `KSCrashMonitorTypeMemoryTermination`  | `KSCrashMonitorTypeTermination` |

The Watchdog monitor replaces the Deadlock monitor with a production-stable implementation that uses
run-loop observation and a fixed 250ms threshold (matching Apple's hang definition). It integrates
with the sidecar system for recovery tracking and startup hang suppression.

The Termination monitor replaces the Memory Termination monitor and covers all OS-level terminations
(OOM, thermal, CPU, reboot), not just memory.

### Configuration

| Deprecated                 | Replacement                                          |
| -------------------------- | ---------------------------------------------------- |
| `deadlockWatchdogInterval` | `KSCrashMonitorTypeWatchdog` (fixed 250ms threshold) |
| `enableSigTermMonitoring`  | Removed (SIGTERM is now always caught)               |
| `crashNotifyCallback`      | `isWritingReportCallback`                            |
| `reportWrittenCallback`    | `didWriteReportCallback`                             |

The new crash callbacks provide async-safety context via a `plan` field that tells you whether it's
safe to call ObjC/Swift or allocate memory.

### KSCrash API

| Deprecated                                 | Replacement                         |
| ------------------------------------------ | ----------------------------------- |
| `userInfo` property (NSDictionary)         | Per-key API in `KSCrash+UserInfo.h` |
| `KSCrashAppStateTrackerObserving` protocol | `addObserverWithBlock:`             |

The per-key user info API (`setUserInfoString:forKey:`, `setUserInfoInteger:forKey:`, etc.) uses an
mmap'd key-value store instead of JSON serialization, making it async-signal-safe with zero
crash-time overhead.

## Behavioral Changes

### `crashedLastLaunch` scope expansion

`KSCrash.crashedLastLaunch` now returns `true` for:

- Crashes (same as before)
- Resource terminations (OOM, thermal, CPU watchdog)
- Unrecovered hangs

It does **not** return `true` for clean exits, reboots, OS/app upgrades, or non-fatal events.

For more granular classification, use the new `previousTerminationReason` property.

### New required monitors

`KSCrashMonitorTypeRequired` now includes `KSCrashMonitorTypeUserInfo` and
`KSCrashMonitorTypeResource`. These are infrastructure monitors that are always enabled regardless
of your monitor selection. They don't generate reports on their own, they store per-run state used
by other monitors.

### Gradual migration

If you want to keep exactly the same behavior as 2.5.1 while you evaluate the new monitors, use:

```swift
config.monitors = .compatible251
```

This excludes Watchdog, Termination, and the new infrastructure monitors from the active set.

### Typed fields on `AppMemoryInfo` (Swift `Report`)

`AppMemoryInfo.memoryLevel` and `memoryPressure` are now `MemoryState` (mirrors
`KSCrashAppMemoryState`: `.normal`, `.warn`, `.urgent`, `.critical`, `.terminal`, plus
`.unknown(String)` for forward-compat values). `AppMemoryInfo.appTransitionState` is now
`AppTransitionState` to match the sibling field on `ApplicationStats`. Code that was reading these
as `String?` needs to switch on the enum (or read `.rawValue` for the original string).

### `KSLogger.h` level-alias opt-out

`KSLogger.h` lets you set the build-time level with the short names
`TRACE`/`DEBUG`/`INFO`/`WARN`/`ERROR` (e.g. `-DKSLogger_Level=WARN`) by temporarily redefining those
identifiers as numeric levels inside the header. If your project already uses those names for
something else and you would rather not have them touched, define `KSLOGGER_NO_LEVEL_ALIASES=1`; the
short names are then unused and both `KSLogger_Level` and any per-file `KSLogger_LocalLevel` must
use the prefixed form (`KSLogger_Level_Warn`) or the numeric value.

```bash
swift build -Xcc -DKSLOGGER_NO_LEVEL_ALIASES=1 -Xcc -DKSLogger_Level=KSLogger_Level_Warn
```

The prefixed logging macros (`KSLOG_DEBUG`, `KSLOG_ERROR`, etc.) are available either way.

## Report Format Changes

The JSON report structure is backward-compatible: all fields present in 2.5.1 are still present (or
moved with clear mapping). New fields are additive. If you parse reports, no existing code will
break, but you may want to start consuming the new fields.

### Removed Fields

| Field                | Notes             |
| -------------------- | ----------------- |
| `system.freeStorage` | Always 0, removed |
| `system.storage`     | Always 0, removed |

### Moved Fields

| 2.5.1 Location                           | 2.6 Location                                    |
| ---------------------------------------- | ----------------------------------------------- |
| `system.app_memory.app_transition_state` | `system.application_stats.app_transition_state` |

### New Fields

**Crash classification** (in `crash.error`):

| Field           | Description                                                                                  |
| --------------- | -------------------------------------------------------------------------------------------- |
| `is_fatal`      | Whether the event killed the process                                                         |
| `is_clean_exit` | Distinguishes clean exit (SIGTERM) from dirty crash. Only meaningful when `is_fatal` is true |

**Report metadata** (in `report`):

| Field        | Description                                                                                   |
| ------------ | --------------------------------------------------------------------------------------------- |
| `monitor_id` | Which monitor caught the event (e.g., `"Signal"`, `"MachException"`, `"Watchdog"`)            |
| `run_id`     | Unique UUID for the process run. Used to correlate reports and sidecars from the same session |

**Backtrace enrichment** (in each backtrace frame):

| Field         | Description                                                                                                          |
| ------------- | -------------------------------------------------------------------------------------------------------------------- |
| `object_uuid` | UUID of the binary image for this frame. Enables direct symbolication without scanning the full `binary_images` list |

**App state** (in `system.application_stats`):

| Field              | Description                                                               |
| ------------------ | ------------------------------------------------------------------------- |
| `task_role`        | Process task role (`"FOREGROUND"`, `"BACKGROUND"`, `"UNSPECIFIED"`, etc.) |
| `user_perceptible` | Whether the app was visible to the user at crash time                     |

**Resource snapshots** (in `system`):

| Field                      | Description                                              |
| -------------------------- | -------------------------------------------------------- |
| `battery_state`            | Battery state enum (0 = unknown)                         |
| `low_power_mode_enabled`   | Low Power Mode active                                    |
| `thermal_state`            | Thermal state enum (0 = nominal)                         |
| `cpu_average_usage_permil` | Sliding-window CPU usage in permil (0-1000)              |
| `cpu_usage_user`           | User-space CPU usage                                     |
| `cpu_usage_system`         | System CPU usage                                         |
| `cpu_state`                | CPU state string (`"normal"`, `"warning"`, `"critical"`) |
| `cpu_core_count`           | Number of CPU cores                                      |
| `data_protection_active`   | Whether data protection is active                        |
| `thread_count`             | Number of threads at crash time                          |

**Process timing** (in `system`):

| Field                         | Description                                  |
| ----------------------------- | -------------------------------------------- |
| `process_start_monotonic_ns`  | Process start time in monotonic nanoseconds  |
| `process_start_wall_clock_ns` | Process start time as wall clock nanoseconds |

### New Report Types

#### Hang Reports (Watchdog)

Hang reports are produced by the Watchdog monitor when the main thread stalls. A fatal hang occurs
when the OS kills the app (SIGKILL) during a hang. A recovered hang is retained as a non-fatal
report when `enableHangReporting` is true. Both types include a `hang` section in `crash.error` with
timing and state from the mmap'd sidecar:

```json
"crash": {
  "error": {
    "type": "mach",
    "is_fatal": true,
    "is_clean_exit": false,
    "hang": {
      "hang_start_nanos": 654204315902125,
      "hang_start_role": "UNSPECIFIED",
      "hang_start_transition_state": "active",
      "hang_end_nanos": 654207070528458,
      "hang_end_role": "UNSPECIFIED",
      "hang_end_transition_state": "active"
    },
    "exit_reason": {
      "code": 2343432205
    },
    "mach": {
      "exception": 10,
      "exception_name": "EXC_CRASH"
    },
    "signal": {
      "signal": 9
    }
  }
}
```

| Field                                          | Description                                                                               |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `crash.error.hang.hang_start_nanos`            | Monotonic timestamp when the hang began                                                   |
| `crash.error.hang.hang_start_role`             | Task role at hang start (`"FOREGROUND"`, `"BACKGROUND"`, `"UNSPECIFIED"`)                 |
| `crash.error.hang.hang_start_transition_state` | App transition state at hang start (`"startup"`, `"active"`, `"terminating"`)             |
| `crash.error.hang.hang_end_nanos`              | Monotonic timestamp when the hang ended (recovery or kill)                                |
| `crash.error.hang.hang_end_role`               | Task role at hang end                                                                     |
| `crash.error.hang.hang_end_transition_state`   | App transition state at hang end                                                          |
| `crash.error.hang.hang_recovered`              | `true` if the hang resolved before the OS killed the app. Only present on recovered hangs |
| `crash.error.exit_reason.code`                 | Darwin exit reason code from the previous termination                                     |

For recovered (non-fatal) hangs, the `signal` and `mach` sections are removed and `crash.error.type`
is changed to `"hang"`.

The `report.monitor_id` is `"Watchdog"` for hang reports.

#### Profile Reports

Profile reports are written by the Profiler module. They use a deduplicated frame format to minimize
file size: unique frames are symbolicated once, and each sample references frames by index. Profile
reports omit the `binary_images` section since each frame already includes `object_uuid`.

```json
"report": {
  "monitor_id": "profile",
  "finalized": true,
  "type": "standard"
},
"crash": {
  "error": {
    "type": "profile",
    "is_fatal": false,
    "profile": {
      "name": "my-session",
      "id": "CA579409-1D76-4C21-99FA-531FBA84CBF2",
      "duration": 480961958,
      "expected_sample_interval": 10000000,
      "time_units": "nanoseconds",
      "time_start_epoch": 1776032889461301000,
      "time_start_uptime": 654207615368333,
      "time_end_uptime": 654207867720833,
      "frames": [
        {
          "symbol_name": "main",
          "symbol_addr": 4377604536,
          "instruction_addr": 4377604587,
          "object_name": "MyApp",
          "object_addr": 4377493504,
          "object_uuid": "FDECDBB8-12EB-328F-80E7-2BCEA7D31540"
        }
      ],
      "samples": [
        {
          "time_start_uptime": 654207616100583,
          "time_end_uptime": 654207616231541,
          "duration": 130958,
          "frames": [4, 2, 0]
        }
      ]
    }
  }
}
```

| Field                                          | Description                                                           |
| ---------------------------------------------- | --------------------------------------------------------------------- |
| `crash.error.profile.name`                     | Profile session name passed to `beginProfile(named:)`                 |
| `crash.error.profile.id`                       | Unique UUID for this profile session                                  |
| `crash.error.profile.duration`                 | Total profile duration in nanoseconds                                 |
| `crash.error.profile.expected_sample_interval` | Configured sampling interval in nanoseconds                           |
| `crash.error.profile.time_start_epoch`         | Wall-clock start time in nanoseconds since epoch                      |
| `crash.error.profile.time_start_uptime`        | Monotonic start timestamp in nanoseconds                              |
| `crash.error.profile.time_end_uptime`          | Monotonic end timestamp in nanoseconds                                |
| `crash.error.profile.frames`                   | Array of unique symbolicated frames                                   |
| `crash.error.profile.samples`                  | Array of samples, each with `frames` as indexes into the frames array |

## New Features

### Watchdog (Hang Detection)

```swift
config.monitors = [.machException, .signal, .cppException, .nsException, .watchdog, .termination]
config.enableHangReporting = true  // optional: retain resolved hangs as non-fatal reports
```

### Termination Detection

```swift
// After install:
let reason = KSCrash.shared.previousTerminationReason
```

Returns one of: `.none`, `.clean`, `.crash`, `.hang`, `.firstLaunch`, `.osUpgrade`, `.appUpgrade`,
`.reboot`, `.lowBattery`, `.memoryLimit`, `.memoryPressure`, `.thermal`, `.cpu`, `.unexplained`.

### CPU Monitoring

```swift
config.enableCPUExceptionReporting = true  // non-fatal reports on CPU warning/critical
```

### Per-Key User Info

```swift
KSCrash.shared.setUserInfoString("premium", forKey: "accountType")
KSCrash.shared.setUserInfoBool(true, forKey: "hasOnboarded")
KSCrash.shared.removeUserInfoValue(forKey: "oldKey")  // removeUserInfoValueForKey: in ObjC
```

### MetricKit Integration

Currently processes `MXCrashDiagnostic` payloads only. Hang and CPU exception diagnostics are not
yet supported.

```swift
import Monitors

config.plugins = [Monitors.metricKit]
```

### Report Module (Swift)

```swift
import Report

let data = try Data(contentsOf: reportURL)
let report = try JSONDecoder().decode(BasicCrashReport.self, from: data)
print(report.crash.error.type)
```

### Profiler

```swift
import KSCrashProfiler
import Darwin

let profiler = TimeProfiler(machThread: pthread_mach_thread_np(pthread_self()))
let profileID = profiler.beginProfile(named: "my-session")
// ... later ...
if let profile = profiler.endProfile(id: profileID) {
    // Write the profile to a crash report (synchronous I/O, use a background queue)
    DispatchQueue.global().async {
        if let url = profile.writeReport() {
            print("Report written to: \(url.path)")
        }
    }
}
```

`TimeProfiler` is the concrete time-sampling profiler. It conforms to the generic `Profiler`
protocol, which is the begin/end contract a future `AllocationProfiler` will also adopt. The
companion `TimeProfile` (returned from `endProfile`) conforms to `Profile`. Sample width and
retention are runtime parameters on `init`:

```swift
TimeProfiler(
    machThread: pthread_mach_thread_np(pthread_self()),
    interval: 0.01,             // 10ms between samples (1ms minimum)
    maxFrames: 128,             // hard-capped at KSSC_MAX_STACK_DEPTH
    retentionSeconds: 30,       // ring buffer length
    unwindMethods: .fast        // compact unwind + frame pointer, skip DWARF
)
```

### Compact Binary Images

```swift
config.enableCompactBinaryImages = true  // only include images referenced by backtraces
```

### Per-Report Sending

```swift
if let store = KSCrash.shared.reportStore {
    let reportID = store.nextReportID
    if reportID != KSCrashReportNoID {
        store.sendReport(withID: reportID) { reports, completed, error in
            // handle result
        }
    }
}
```
