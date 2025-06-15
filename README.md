
![Untitled](https://github.com/user-attachments/assets/9478bde6-78ae-4d59-b8ab-dc6db4137b9f)

[![Run Unit Tests](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml)
[![CocoaPods Lint](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kstenerud/KSCrash)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kstenerud/KSCrash)

## 🚀 KSCrash 2.0 Released!

KSCrash 2.0 is now available with significant improvements and enhancements. If you are upgrading from version 1.x, please refer to the migration guide for details on transitioning to the latest version:

➡️ [Migration Guide for KSCrash 1.x to 2.0](https://github.com/kstenerud/KSCrash/wiki/Migration-Guide-for-KSCrash-1.x-to-2.0)

## Another crash reporter? Why?

Because while the existing crash reporters do report crashes, there's a heck
of a lot more that they COULD do. Here are some key features of KSCrash:

* On-device symbolication in a way that supports re-symbolication offline
  (necessary for iOS versions where many functions have been redacted).
* Generates full Apple reports, with every field filled in.
* 32-bit and 64-bit mode.
* Supports all Apple devices, including Apple Watch.
* Handles errors that can only be caught at the mach level, such as stack
  overflow.
* Tracks the REAL cause of an uncaught C++ exception.
* Handles a crash in the crash handler itself (or in the user crash handler
  callback).
* Detects zombie (deallocated) object access attempts.
* Recovers lost NSException messages in cases of zombies or memory corruption.
* Introspects objects in registers and on the stack (C strings and Objective-C
  objects, including ivars).
* Extracts information about objects referenced by an exception (such as
  "unrecognized selector sent to instance 0xa26d9a0")
* Its pluggable server reporting architecture makes it easy to adapt to any API
  service.
* Dumps the stack contents.
* Diagnoses crash causes (Crash Doctor).
* Records lots of information beyond what the Apple crash report can, in a JSON
  format.
* Supports including extra data that the programmer supplies (before and during
  a crash).

### KSCrash handles the following kinds of crashes:

* Mach kernel exceptions
* Fatal signals
* C++ exceptions
* Objective-C exceptions
* Main thread deadlock (experimental)
* Custom crashes (e.g. from scripting languages)

[Here are some examples of the reports it can generate.](https://github.com/kstenerud/KSCrash/tree/master/Example-Reports/_README.md)

## Call for help!

My life has changed enough over the past few years that I can't keep up with giving KSCrash the love it needs.

![I want you](https://c1.staticflickr.com/9/8787/28351252396_eeec9bb146.jpg)

I'm looking for someone to help me maintain this package, make sure issues get handled, merges are properly vetted, and code quality remains high. Please contact me personally (kstenerud at my gmail address) or comment in https://github.com/kstenerud/KSCrash/issues/313

## How to Install KSCrash

### Swift Package Manager (SPM)

#### Option 1: Using Xcode UI

1. In Xcode, go to File > Add Packages...
2. Enter: `https://github.com/kstenerud/KSCrash.git`
3. Select the desired version/branch
4. Choose your target(s)
5. Click "Add Package"

#### Option 2: Using Package.swift

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/kstenerud/KSCrash.git", .upToNextMajor(from: "2.2.0"))
]
```

Then, include "Installations" as a dependency for your target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "Installations", package: "KSCrash"),
        ]),
]
```

### CocoaPods

1. Add to your `Podfile`:
   ```ruby
   pod 'KSCrash', '~> 2.2'
   ```

2. Run:
   ```
   $ pod install
   ```

3. Use the generated `.xcworkspace` file.

### Post-Installation Setup

Add the following to your `AppDelegate.swift` file:

#### Import KSCrash

For Swift Package Manager:

```swift
import KSCrashInstallations
```

For CocoaPods:

```swift
import KSCrash
```

#### Configure AppDelegate

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let installation = CrashInstallationStandard.shared
        installation.url = URL(string: "http://put.your.url.here")!

        // Install the crash reporting system
        let config = KSCrashConfiguration()
        config.monitors = [.machException, .signal]
        installation.install(with: config) // set `nil` for default config

        // Optional: Add an alert confirmation (recommended for email installation)
        installation.addConditionalAlert(
            withTitle: "Crash Detected",
            message: "The app crashed last time it was launched. Send a crash report?",
            yesAnswer: "Sure!",
            noAnswer: "No thanks"
        )

        return true
    }
}
```

#### Other Installation Types

##### Email Installation

```swift
let installation = CrashInstallationEmail.shared
installation.recipients = ["some@email.address"] // Specify recipients for email reports
// Optional: Send Apple-style reports instead of JSON
installation.setReportStyle(.apple, useDefaultFilenameFormat: true)
```

##### Console Installation

```swift
let installation = CrashInstallationConsole.shared
installation.printAppleFormat = true // Print crash reports in Apple format for testing
```

#### Sending Reports

To send any outstanding crash reports, call:

```swift
installation.sendAllReports { reports, completed, error in
    // Stuff to do when report sending is complete
}
```

### Optional Monitors

KSCrash includes two optional monitor modules: `BootTimeMonitor` and `DiscSpaceMonitor`. These modules are not included by default and must be explicitly added if needed. They contain privacy-concerning APIs that require showing crash reports to the user before sending this information off the device.

To include these modules:

- With CocoaPods:
  ```ruby
  pod 'KSCrash/BootTimeMonitor'
  pod 'KSCrash/DiscSpaceMonitor'
  ```

- With SPM, add to your target dependencies:
  ```swift
  .product(name: "BootTimeMonitor", package: "KSCrash"),
  .product(name: "DiscSpaceMonitor", package: "KSCrash"),
  ```

If these modules are linked, they act automatically and require no additional setup. It is the responsibility of the library user to implement the necessary UI for user consent.

For more information, see Apple's documentation on [Disk space APIs](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api#4278397) and [System boot time APIs](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api#4278394).

### Optional Demangling

KSCrash has an optional module that provides demangling for both C++ and Swift symbols: `DemangleFilter`. This module contains a KSCrash filter (`CrashReportFilterDemangle`) that can be used for demangling symbols in crash reports during the `sendAllReports` call *(if this filter is added to the filters pipeline)*.

This module is used automatically if you use the `Installations` API. If you want to avoid demangling, you can set `isDemangleEnabled` in the `CrashInstallation` instance to `false`.

If you don't use the `Installations` API, you can include this module manually:

- With CocoaPods:
  ```ruby
  pod 'KSCrash/DemangleFilter'
  ```

- With SPM, add to your target dependencies:
  ```swift
  .product(name: "DemangleFilter", package: "KSCrash"),
  ```

The `CrashReportFilterDemangle` class also has a static API that you can use yourself in case you need to demangle a C++ or Swift symbol.

## What's New?

### Out-of-Memory Crash Detection

KSCrash now includes advanced memory tracking capabilities to help detect and prevent out-of-memory crashes. The new `KSCrashAppMemoryTracker` allows you to monitor your app's memory usage, pressure, and state transitions in real-time. This feature enables proactive memory management, helping you avoid system-initiated terminations due to excessive memory use. Check out the "Advanced Usage" section for more details on how to implement this in your app.

### C++ Exception Handling

That's right! Normally if your app terminates due to an uncaught C++ exception,
all you get is this:

    Thread 0 name:  Dispatch queue: com.apple.main-thread
    Thread 0 Crashed:
    0   libsystem_kernel.dylib          0x9750ea6a 0x974fa000 + 84586 (__pthread_kill + 10)
    1   libsystem_sim_c.dylib           0x04d56578 0x4d0f000 + 292216 (abort + 137)
    2   libc++abi.dylib                 0x04ed6f78 0x4ed4000 + 12152 (abort_message + 102)
    3   libc++abi.dylib                 0x04ed4a20 0x4ed4000 + 2592 (_ZL17default_terminatev + 29)
    4   libobjc.A.dylib                 0x013110d0 0x130b000 + 24784 (_ZL15_objc_terminatev + 109)
    5   libc++abi.dylib                 0x04ed4a60 0x4ed4000 + 2656 (_ZL19safe_handler_callerPFvvE + 8)
    6   libc++abi.dylib                 0x04ed4ac8 0x4ed4000 + 2760 (_ZSt9terminatev + 18)
    7   libc++abi.dylib                 0x04ed5c48 0x4ed4000 + 7240 (__cxa_rethrow + 77)
    8   libobjc.A.dylib                 0x01310fb8 0x130b000 + 24504 (objc_exception_rethrow + 42)
    9   CoreFoundation                  0x01f2af98 0x1ef9000 + 204696 (CFRunLoopRunSpecific + 360)
    ...

No way to track what the exception was or where it was thrown from!

Now with KSCrash, you get the uncaught exception type, description, and where it was thrown from:

    Application Specific Information:
    *** Terminating app due to uncaught exception 'MyException', reason: 'Something bad happened...'

    Thread 0 name:  Dispatch queue: com.apple.main-thread
    Thread 0 Crashed:
    0   Crash-Tester                    0x0000ad80 0x1000 + 40320 (-[Crasher throwUncaughtCPPException] + 0)
    1   Crash-Tester                    0x0000842e 0x1000 + 29742 (__32-[AppDelegate(UI) crashCommands]_block_invoke343 + 78)
    2   Crash-Tester                    0x00009523 0x1000 + 34083 (-[CommandEntry executeWithViewController:] + 67)
    3   Crash-Tester                    0x00009c0a 0x1000 + 35850 (-[CommandTVC tableView:didSelectRowAtIndexPath:] + 154)
    4   UIKit                           0x0016f285 0xb4000 + 766597 (-[UITableView _selectRowAtIndexPath:animated:scrollPosition:notifyDelegate:] + 1194)
    5   UIKit                           0x0016f4ed 0xb4000 + 767213 (-[UITableView _userSelectRowAtPendingSelectionIndexPath:] + 201)
    6   Foundation                      0x00b795b3 0xb6e000 + 46515 (__NSFireDelayedPerform + 380)
    7   CoreFoundation                  0x01f45376 0x1efa000 + 308086 (__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__ + 22)
    8   CoreFoundation                  0x01f44e06 0x1efa000 + 306694 (__CFRunLoopDoTimer + 534)
    9   CoreFoundation                  0x01f2ca82 0x1efa000 + 207490 (__CFRunLoopRun + 1810)
    10  CoreFoundation                  0x01f2bf44 0x1efa000 + 204612 (CFRunLoopRunSpecific + 276)
    ...

### Custom Crashes & Stack Traces

You can now report your own custom crashes and stack traces (think scripting
languages):
```objective-c
- (void) reportUserException:(NSString*) name
                      reason:(NSString*) reason
                  lineOfCode:(NSString*) lineOfCode
                  stackTrace:(NSArray*) stackTrace
            terminateProgram:(BOOL) terminateProgram;
```

See KSCrash.h for details.

### Unstable Features

The following features should be considered "unstable" and are disabled by default:

- Deadlock detection

## Recommended Reading

If possible, you should read the following header files to fully understand
what features KSCrash has, and how to use them:

* KSCrash.h
* KSCrashInstallation.h
* KSCrashInstallation(SPECIFIC TYPE).h
* [Architecture.md](https://github.com/kstenerud/KSCrash/wiki/KSCrash-Architecture)

## Understanding the KSCrash Codebase

KSCrash is structured into several modules, divided into public and private APIs:

### Public API Modules

1. **Recording**: `KSCrashRecording` - Handles crash event recording.
2. **Reporting**:
   - **Filters**: `KSCrashFilters` - Processes crash reports.
   - **Sinks**: `KSCrashSinks` - Manages report destinations.
   - **Installations**: `KSCrashInstallations` - Provides easy-to-use setups for different reporting scenarios.

### Optional Modules

- **DiscSpaceMonitor**: `KSCrashDiscSpaceMonitor` - Monitors available disk space.
- **BootTimeMonitor**: `KSCrashBootTimeMonitor` - Tracks device boot time.
- **DemangleFilter**: `KSCrashDemangleFilter` - Demangle symbols in crashes as part of reporing pipeline.

### Private API Modules

- `KSCrashRecordingCore`: Core functionality for crash recording.
- `KSCrashReportingCore`: Core functionality for crash reporting.
- `KSCrashCore`: Core system capabilities logic.

Users should interact with the public API modules, while the private modules handle internal operations. The optional modules can be included for additional functionality as needed.

**Also see a quick code tour [here](https://github.com/kstenerud/KSCrash/wiki/A-Brief-Tour-of-the-KSCrash-Code-and-Architecture).**

## Advanced Usage

### Enabling on-device symbolication

On-device symbolication requires basic symbols to be present in the final
build. To enable this, go to your app's build settings and set **Strip Style**
to **Debugging Symbols**. Doing so increases your final binary size by about
5%, but you get on-device symbolication.

### Enabling advanced functionality:

KSCrash has advanced functionality that can be very useful when examining crash
reports in the wild. Some involve minor trade-offs, so most of them are
disabled by default.

#### Custom User Data (userInfo in KSCrash.h)

You can store custom user data to the next crash report by setting the
**userInfo** property in KSCrash.h.

#### Zombie Tracking (KSCrashMonitorTypeZombie in KSCrashMonitorType.h)

KSCrash has the ability to detect zombie instances (dangling pointers to
deallocated objects). It does this by recording the address and class of any
object that gets deallocated. It stores these values in a cache, keyed off the
deallocated object's address. This means that the smaller you set the cache
size, the greater the chance that a hash collision occurs and you lose
information about a previously deallocated object.

With zombie tracking enabled, KSCrash will also detect a lost NSException and
print its contents. Certain kinds of memory corruption or stack corruption
crashes can cause the exception to deallocate early, further twarting efforts
to debug your app, so this feature can be quite handy at times.

Trade off: Zombie tracking at the cost of adding very slight overhead to object
           deallocation, and having some memory reserved.

#### Deadlock Detection (KSCrashMonitorTypeMainThreadDeadlock in KSCrashMonitorType.h)

**WARNING WARNING WARNING WARNING WARNING WARNING WARNING**

**This feature is UNSTABLE! It can false-positive and crash your app!**

If your main thread deadlocks, your user interface will become unresponsive,
and the user will have to manually shut down the app (for which there will be
no crash report). With deadlock detection enabled, a watchdog timer is set up.
If anything holds the main thread for longer than the watchdog timer duration,
KSCrash will shut down the app and give you a stack trace showing what the
main thread was doing at the time.

This is wonderful, but you must be careful: App initialization generally
occurs on the main thread. If your initialization code takes longer than the
watchdog timer, your app will be forcibly shut down during start up! If you
enable this feature, you MUST ensure that NONE of your normally running code
holds the main thread for longer than the watchdog value! At the same time,
you'll want to set the timer to a low enough value that the user doesn't
become impatient and shut down the app manually before the watchdog triggers!

Trade off: Deadlock detection, but you must be a lot more careful about what
           runs on the main thread!

#### Memory Introspection (introspectMemory in KSCrash.h)

When an app crashes, there are usually objects and strings in memory that are
being referenced by the stack, registers, or even exception messages. When
enabled, KSCrash will introspect these memory regions and store their contents
in the crash report.

You can also specify a list of classes that should not be introspected by
setting the **doNotIntrospectClasses** property in KSCrash.

#### Custom crash handling code (onCrash in KSCrash.h)

If you want to do some extra processing after a crash occurs (perhaps to add
more contextual data to the report), you can do so.

However, you must ensure that you only use async-safe code, and above all else
never call Objective-C code from that method! There are many cases where you
can get away with doing so anyway, but there are certain classes of crashes
where handler code that disregards this warning will cause the crash handler
to crash! Note that if this happens, KSCrash will detect it and write a full
report anyway, though your custom handler code may not fully run.

Trade off: Custom crash handling code, but you must be careful what you put
           in it!

#### KSCrash log redirection

This takes whatever KSCrash would have printed to the console, and writes it
to a file instead. I mostly use this for debugging KSCrash itself, but it could
be useful for other purposes, so I've exposed an API for it.

#### Out-of-Memory Crash Detection (KSCrashAppMemoryTracker)

KSCrash now includes advanced memory tracking capabilities to help detect and prevent out-of-memory crashes. The `KSCrashAppMemoryTracker` class monitors your app's memory usage, pressure, and state transitions. It provides real-time updates on memory conditions, allowing you to respond dynamically to different memory states (Normal, Warn, Urgent, Critical, Terminal). By implementing the `KSCrashAppMemoryTrackerDelegate` protocol, you can receive notifications about memory changes and take appropriate actions to reduce memory usage, potentially avoiding system-initiated terminations due to memory pressure.

To use this feature:

```swift
let memoryTracker = AppMemoryTracker()
memoryTracker.delegate = self
memoryTracker.start()
```

In your delegate method:

```swift
func appMemoryTracker(_ tracker: AppMemoryTracker, memory: AppMemory, changed changes: AppMemoryTrackerChangeType) {
    if changes.contains(.level) {
        // Respond to memory level changes
    }
}
```

This feature helps you implement proactive memory management strategies in your app.

## License

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
