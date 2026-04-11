# Migration Guide: KSCrash 2.5.x to 2.6

KSCrash 2.6 is fully backward-compatible with 2.5.x. No code changes are required to upgrade, but you will see deprecation warnings for some APIs. This guide covers what changed and how to adopt the new features.

## No Source-Breaking Changes

All renamed or removed APIs have deprecated aliases preserved. All new configuration fields default to zero/nil, so existing `KSCrashCConfiguration` initializers continue to work.

## Deprecations

### Monitor Types

| Deprecated | Replacement |
|---|---|
| `KSCrashMonitorTypeMainThreadDeadlock` | `KSCrashMonitorTypeWatchdog` |
| `KSCrashMonitorTypeMemoryTermination` | `KSCrashMonitorTypeTermination` |

The Watchdog monitor replaces the Deadlock monitor with a production-stable implementation that uses run-loop observation and a fixed 250ms threshold (matching Apple's hang definition). It integrates with the sidecar system for recovery tracking and startup hang suppression.

The Termination monitor replaces the Memory Termination monitor and covers all OS-level terminations (OOM, thermal, CPU, reboot), not just memory.

### Configuration

| Deprecated | Replacement |
|---|---|
| `deadlockWatchdogInterval` | `KSCrashMonitorTypeWatchdog` (fixed 250ms threshold) |
| `enableSigTermMonitoring` | Removed (SIGTERM is now always caught) |
| `crashNotifyCallback` | `isWritingReportCallback` |
| `reportWrittenCallback` | `didWriteReportCallback` |

The new crash callbacks provide async-safety context via a `plan` field that tells you whether it's safe to call ObjC/Swift or allocate memory.

### KSCrash API

| Deprecated | Replacement |
|---|---|
| `userInfo` property (NSDictionary) | Per-key API in `KSCrash+UserInfo.h` |
| `KSCrashAppStateTrackerObserving` protocol | `addObserverWithBlock:` |

The per-key user info API (`setUserInfoString:forKey:`, `setUserInfoInteger:forKey:`, etc.) uses an mmap'd key-value store instead of JSON serialization, making it async-signal-safe with zero crash-time overhead.

## Behavioral Changes

### `crashedLastLaunch` scope expansion

`KSCrash.crashedLastLaunch` now returns `true` for:
- Crashes (same as before)
- Resource terminations (OOM, thermal, CPU watchdog)
- Unrecovered hangs

It does **not** return `true` for clean exits, reboots, OS/app upgrades, or non-fatal events.

For more granular classification, use the new `previousTerminationReason` property.

### New required monitors

`KSCrashMonitorTypeRequired` now includes `KSCrashMonitorTypeUserInfo` and `KSCrashMonitorTypeResource`. These are infrastructure monitors that are always enabled regardless of your monitor selection. They don't generate reports on their own, they store per-run state used by other monitors.

### Gradual migration

If you want to keep exactly the same behavior as 2.5.1 while you evaluate the new monitors, use:

```swift
config.monitors = .compatible251
```

This excludes Watchdog, Termination, and the new infrastructure monitors from the active set.

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

Returns one of: `.none`, `.clean`, `.crash`, `.hang`, `.firstLaunch`, `.osUpgrade`, `.appUpgrade`, `.reboot`, `.lowBattery`, `.memoryLimit`, `.memoryPressure`, `.thermal`, `.cpu`, `.unexplained`.

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

Currently processes `MXCrashDiagnostic` payloads only. Hang and CPU exception diagnostics are not yet supported.

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

let profiler = Profiler<Sample128>()
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
