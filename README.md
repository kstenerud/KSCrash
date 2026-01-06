# KSCrash

[![Run Unit Tests](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml)
[![CocoaPods Lint](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kstenerud/KSCrash)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kstenerud/KSCrash)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/kstenerud?style=flat&logo=githubsponsors&label=Sponsors)](https://github.com/sponsors/kstenerud)

**The ultimate crash and termination reporter for Apple platforms.**

KSCrash provides comprehensive crash and termination detection with deep system introspection capabilities. It captures detailed diagnostic information that goes far beyond standard crash reports, helping you understand exactly what happened when your app crashed or was terminated.

## Platform Support

- iOS 12.0+
- macOS 10.14+
- tvOS 12.0+
- watchOS 5.0+
- visionOS 1.0+

## Features

### Crash and Termination Coverage

KSCrash detects and reports all major crash and termination types:

- **Mach Kernel Exceptions** - Low-level system crashes including stack overflow
- **Fatal Signals** - SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, and more
- **C++ Exceptions** - Full exception type, message, and throw location
- **Objective-C NSExceptions** - Complete exception details with recovery from memory corruption
- **Watchdog Terminations** - App hangs and responsiveness issues
- **Out-of-Memory Terminations** - Detect OOM kills on next launch
- **Custom Crashes** - Report crashes from scripting languages or custom error handlers

### Deep Diagnostics

- **On-Device Symbolication** - Generate readable stack traces on the device itself. Supports offline resymbolication for iOS versions with redacted symbols. Server-side symbolication is recommended when available for the most accurate results.
- **Memory Introspection** - Inspect objects and strings referenced in registers, stack, and exception messages during a crash
- **Lost Exception Recovery** - Recover NSException messages even when memory corruption or stack overflow has occurred
- **Crash Doctor** - Automated crash diagnosis to help identify root causes

### Proactive Monitoring

- **Memory Tracking** - Monitor memory pressure levels (Normal, Warn, Urgent, Critical, Terminal) to prevent out-of-memory terminations before they happen
- **Hang Detection** - Detect main thread hangs and capture thread states before watchdog termination
- **Sampling Profiler** - Capture thread backtraces at regular intervals to analyze performance or debug hangs

### Flexible Reporting

- **Multiple Output Formats** - JSON with extensive metadata, or Apple-standard crash reports
- **Pluggable Architecture** - Filters for processing, sinks for destinations, and pre-configured installations
- **Built-in Integrations** - HTTP upload, email reporting, and console output
- **Custom Data** - Attach your own metadata to crash reports

### Production Ready

- **Async-Signal Safe** - Core crash handling code is carefully designed to avoid deadlocks and secondary crashes
- **Crash-in-Handler Protection** - Handles crashes that occur within the crash handler itself

## Installation

### Swift Package Manager

**Using Xcode:**

1. Go to File > Add Packages...
2. Enter: `https://github.com/kstenerud/KSCrash.git`
3. Select the version and add to your target

**Using Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/kstenerud/KSCrash.git", .upToNextMajor(from: "2.5.0"))
]
```

Add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Installations", package: "KSCrash"),
    ]
)
```

### CocoaPods

```ruby
pod 'KSCrash', '~> 2.0'
```

## Quick Start

**Important:** Initialize KSCrash as early as possible in your app's lifecycle. Crashes that occur before initialization will not be captured. The AppDelegate or UIApplicationDelegate `init()` method is ideal. Avoid waiting until `didFinishLaunchingWithOptions` as crashes during early app startup would be missed.

### UIKit App

```swift
import KSCrashInstallations  // SPM
// import KSCrash            // CocoaPods

class AppDelegate: UIResponder, UIApplicationDelegate {

    override init() {
        super.init()
        setupCrashReporting()
    }

    private func setupCrashReporting() {
        let installation = CrashInstallationStandard.shared
        installation.url = URL(string: "https://your-crash-server.com/reports")!
        installation.install(with: nil)
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Send any pending crash reports
        CrashInstallationStandard.shared.sendAllReports { reports, completed, error in
            if completed {
                print("Sent \(reports.count) crash reports")
            }
        }
        return true
    }
}
```

### SwiftUI App

```swift
import SwiftUI
import KSCrashInstallations

@main
struct MyApp: App {

    init() {
        let installation = CrashInstallationStandard.shared
        installation.url = URL(string: "https://your-crash-server.com/reports")!
        installation.install(with: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await sendCrashReports()
                }
        }
    }

    private func sendCrashReports() async {
        CrashInstallationStandard.shared.sendAllReports { reports, completed, error in
            if completed {
                print("Sent \(reports.count) crash reports")
            }
        }
    }
}
```

### SDK Integration

If you're building an SDK that needs to process crash reports directly:

```swift
import KSCrashRecording
import KSCrashFilters

class MyCrashSDK {

    func install() {
        // Install KSCrash with your configuration
        let config = KSCrashConfiguration()
        KSCrash.shared.install(with: config)
    }

    func processReports() {
        // Retrieve and process reports yourself
        let reportStore = KSCrash.shared.reportStore
        let reportIDs = reportStore.reportIDs

        for reportID in reportIDs {
            if let report = reportStore.report(for: reportID) {
                // Process the report as needed
                sendToYourBackend(report: report)

                // Delete after successful processing
                reportStore.deleteReport(with: reportID)
            }
        }
    }

    private func sendToYourBackend(report: CrashReport) {
        // Your custom report handling
    }
}
```

### Custom Configuration

```swift
let config = KSCrashConfiguration()
config.monitors = [.machException, .signal, .cppException, .nsException]

installation.install(with: config)
```

### Email Reports

```swift
let installation = CrashInstallationEmail.shared
installation.recipients = ["crashes@yourcompany.com"]
installation.setReportStyle(.apple, useDefaultFilenameFormat: true)

// Optional: Ask user before sending
installation.addConditionalAlert(
    withTitle: "Crash Detected",
    message: "Would you like to send a crash report?",
    yesAnswer: "Send",
    noAnswer: "Don't Send"
)

installation.install(with: nil)
```

## Advanced Features

### Memory Monitoring

KSCrash uses memory tracking internally to detect out-of-memory terminations. You can observe memory state changes to proactively manage memory in your app using the shared instance:

```swift
import KSCrashRecording

class MyClass {
    // Hold a reference to keep the observer active
    private var memoryObserver: AnyObject?

    func startObservingMemory() {
        memoryObserver = AppMemoryTracker.shared.addObserver { memory, changes in
            if memory.level == .critical {
                // Release non-essential resources
                self.clearCaches()
            }
        }
    }

    func stopObservingMemory() {
        // Setting to nil removes the observer
        memoryObserver = nil
    }
}
```

### Custom User Data

Attach contextual information to crash reports:

```swift
KSCrash.shared.userInfo = [
    "user_id": "12345",
    "session_id": sessionId,
    "feature_flags": enabledFeatures
]
```

### On-Device Symbolication

To enable on-device symbolication, set **Strip Style** to **Debugging Symbols** in your build settings. This adds approximately 5% to binary size but enables readable stack traces directly on the device. For production apps, server-side symbolication with dSYM files is recommended when possible for the most accurate and complete results.

### Sampling Profiler

Capture thread backtraces at regular intervals to analyze performance or debug hangs:

```swift
import KSCrashProfiler

let profiler = Profiler<Sample128>(thread: pthread_self())
let id = profiler.beginProfile(named: "AppLaunch")
// ... do work ...
if let profile = profiler.endProfile(id: id) {
    // Write report to disk from background queue
    DispatchQueue.global().async {
        _ = profile.writeReport()
    }
}
```

Add the Profiler module to your target:

```swift
// SPM
.product(name: "Profiler", package: "KSCrash"),

// CocoaPods
pod 'KSCrash/Profiler'
```

## Optional Modules

### Symbol Demangling

The `DemangleFilter` module provides C++ and Swift symbol demangling. It's included automatically when using the Installations API. To disable:

```swift
installation.isDemangleEnabled = false
```

### Privacy-Sensitive Monitors

These modules require user consent before transmitting data:

- **BootTimeMonitor** - Device boot time information
- **DiscSpaceMonitor** - Available disk space

Add them explicitly if needed:

```swift
// SPM
.product(name: "BootTimeMonitor", package: "KSCrash"),
.product(name: "DiscSpaceMonitor", package: "KSCrash"),

// CocoaPods
pod 'KSCrash/BootTimeMonitor'
pod 'KSCrash/DiscSpaceMonitor'
```

## Architecture

KSCrash uses a modular architecture:

| Module | Purpose |
|--------|---------|
| **Recording** | Crash detection and capture |
| **Filters** | Report processing and transformation |
| **Sinks** | Report delivery (HTTP, email, console) |
| **Installations** | Pre-configured setups for common use cases |
| **Profiler** | Thread sampling and performance profiling |

For detailed architecture information, see the [Architecture Guide](https://github.com/kstenerud/KSCrash/wiki/KSCrash-Architecture).

## Example Reports

See [Example-Reports](Example-Reports/_README.md) for sample crash reports in both JSON and Apple formats.

## Community

Join the conversation and get help:

- **Slack** - [Join the KSCrash Slack](https://join.slack.com/t/kscrash/shared_invite/zt-3lq7n9ss7-m97NrPJW3l9pvpZl17ztbg)
- **GitHub Discussions** - Ask questions and share ideas on GitHub

## Support the Project

If KSCrash has been valuable for your projects, consider [sponsoring the project on GitHub](https://github.com/sponsors/kstenerud). Your support helps maintain and improve the framework.

## License

KSCrash is available under the MIT license.

```text
Copyright (c) 2012 Karl Stenerud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
the documentation of any redistributions of the template files themselves
(but not in projects built using the templates).

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
