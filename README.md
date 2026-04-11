
![Untitled](https://github.com/user-attachments/assets/9478bde6-78ae-4d59-b8ab-dc6db4137b9f)

[![Run Unit Tests](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml)
[![CocoaPods Lint](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kstenerud/KSCrash)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kstenerud/KSCrash)

## KSCrash 2.6

The best open-source crash reporting framework for Apple platforms. Supports iOS, macOS, tvOS, watchOS, and visionOS.

KSCrash catches Mach exceptions, signals, C++/ObjC exceptions, main thread hangs, and OS-level terminations (OOM, thermal, CPU, reboot). It generates full Apple-format crash reports with every field filled in.

If you are upgrading from 2.5.x, see the [migration guide](https://github.com/kstenerud/KSCrash/wiki/Migration-Guide-for-KSCrash-2.5-to-2.6). For upgrades from 1.x, see the [1.x to 2.0 migration guide](https://github.com/kstenerud/KSCrash/wiki/Migration-Guide-for-KSCrash-1.x-to-2.0).

## Quick Start

### Install

**SPM:** Add `https://github.com/kstenerud/KSCrash.git` in Xcode (File > Add Packages), or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kstenerud/KSCrash.git", .upToNextMajor(from: "2.6.0"))
]
```

**CocoaPods:**

```ruby
pod 'KSCrash', '~> 2.6'
```

### Setup

```swift
import KSCrashRecording // KSCrash for CocoaPods

let config = KSCrashConfiguration()
try KSCrash.shared.install(with: config)
```

That's it. KSCrash will catch crashes and store reports on disk. To send reports to a server, use an installation. See `KSCrashInstallation.h` for details.

## Features

See the [Architecture](https://github.com/kstenerud/KSCrash/wiki/KSCrash-Architecture) and [Code Tour](https://github.com/kstenerud/KSCrash/wiki/A-Brief-Tour-of-the-KSCrash-Code-and-Architecture) wiki pages for how these work under the hood.

### Hang Detection

The Watchdog monitor detects main thread hangs (250ms+) and captures full backtraces. Enable with `.watchdog` in your monitor config. See `KSCrash+Hang.h` for real-time hang observation.

### Termination Detection

Detects OS-level terminations (OOM, thermal, CPU, reboot) by comparing previous-run state at launch. Query the result with `KSCrash.shared.previousTerminationReason`.

### CPU Monitoring

Tracks CPU usage with sliding-window averages mirroring Apple's enforcement thresholds. Optionally generates non-fatal reports on warning/critical transitions via `enableCPUExceptionReporting`.

### Custom User Data

Store per-key data that persists across crashes via `KSCrash+UserInfo.h`. Uses an mmap'd key-value store with zero crash-time overhead.

### Additional Features

- **Profiler**: Sampling profiler for thread backtraces (`KSCrashProfiler` module)
- **MetricKit**: Apple diagnostic payload integration (`Monitors` module)
- **Report**: Strongly-typed Swift model for crash reports (`Report` module)
- **Zombie Detection**: Catches messages to deallocated objects
- **Memory Tracking**: Real-time memory pressure monitoring via `AppMemoryTracker`
- **Crash Doctor**: Automatic crash cause diagnosis
- **Custom Crashes**: Report exceptions from scripting languages via `reportUserException`
- **Namespacing**: Embed KSCrash in your own library without symbol clashes

For configuration options, see `KSCrashConfiguration.h`. For the full API, see `KSCrash.h`.

## Deprecations in 2.6

| Deprecated | Replacement |
|---|---|
| `userInfo` property | Per-key API in `KSCrash+UserInfo.h` |
| `deadlockWatchdogInterval` | `KSCrashMonitorTypeWatchdog` |
| `enableSigTermMonitoring` | Removed (always caught) |
| `KSCrashMonitorTypeMainThreadDeadlock` | `KSCrashMonitorTypeWatchdog` |
| `KSCrashMonitorTypeMemoryTermination` | `KSCrashMonitorTypeTermination` |
| `KSCrashAppStateTrackerObserving` | `addObserverWithBlock:` |
| `crashNotifyCallback` / `reportWrittenCallback` | `isWritingReportCallback` / `didWriteReportCallback` |

See the [migration guide](https://github.com/kstenerud/KSCrash/wiki/Migration-Guide-for-KSCrash-2.5-to-2.6) for details and rationale.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Notes

This project is tested with BrowserStack.
