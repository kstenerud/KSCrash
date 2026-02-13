# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

### Swift Package Manager

- Format code: `make format`
- Check formatting: `make check-format`
- Build Swift package (debug): `swift build`
- Build Swift package (release): `swift build -c release`
- Run Swift tests: `swift test`
- Run Swift tests with verbose output: `swift test --verbose`
- Run specific test target: `swift test --filter KSCrashCore_Tests`
- Run specific test case: `swift test --filter KSCrash_Tests/testUserInfo`
- Show package structure: `swift package describe`
  ```
  # Sample output:
  Name: KSCrash
  Manifest display name: KSCrash
  Path: /Users/glinnik/Developer/KSCrash
  Tools version: 5.3
  Dependencies:
  ```
- Show package dependencies: `swift package show-dependencies`
  ```
  # Sample output:
  No external dependencies found
  ```

## Project Structure

- Main Package.swift: Defines the KSCrash framework with multiple library products
- KSCrash.podspec: CocoaPods spec — must stay in sync with Package.swift. When adding a new target or dependency in Package.swift, always add the corresponding subspec and dependency in the podspec. CI lint jobs will fail otherwise.
- Samples/: Contains sample app and integration tests
  - Uses Tuist for project generation (Project.swift)
  - Tuist version managed by Mise (see .mise.toml)
  - Common/Package.swift: Local package referenced by the sample app
  - Tests/: Integration tests for the framework
- .mise.toml: Version management for development tools (currently Tuist)

## Tool Version Management

This project uses [Mise](https://mise.jdx.dev/) to manage development tool versions for consistency across environments.

### Setup
```bash
# Install Mise (if not already installed)
curl https://mise.run | sh

# Install tools defined in .mise.toml
mise install

# Trust the configuration (required once for security)
mise trust
```

### Usage
```bash
# Run tools via mise (ensures correct version)
mise exec -- tuist generate

# Or activate mise in your shell for direct tool access
eval "$(mise activate zsh)"  # or bash/fish
tuist generate  # Now uses the pinned version
```

### Tool Versions
- **Tuist**: Version defined in `.mise.toml`
- **CI**: Automatically uses same versions via `jdx/mise-action`

## Common Development Tasks

### Swift Package Workflows

#### Building Specific Products
```bash
# Build specific product
swift build --product Recording
# Sample output: Building for debugging...
# Build of product 'Recording' complete!

# Build specific product in release mode
swift build -c release --product Filters
# Sample output: Building for release...
# Build of product 'Filters' complete!
```

#### Testing with Options
```bash
# Run tests with code coverage
swift test --enable-code-coverage
# Enables code coverage reporting for test runs

# List all tests (note: replaced deprecated --list-tests option)
swift test list
# Sample output: Lists all test methods in the project
# KSCrash_Tests/testUserInfo
# KSCrash_Tests/testUserInfoIfNil
# etc.

# Run tests in parallel
swift test --parallel
# Sample output: Runs tests concurrently for faster execution
```

#### Testing with Sanitizers

**IMPORTANT**: Run tests with sanitizers frequently to catch memory errors, data races, and undefined behavior early. This is especially critical for crash handling code.

```bash
# Address Sanitizer - detects memory errors (buffer overflows, use-after-free, etc.)
swift test --sanitize address

# Thread Sanitizer - detects data races between threads
swift test --sanitize thread

# Undefined Behavior Sanitizer - detects undefined behavior
swift test --sanitize undefined
```

**Known Issue**: Do not use `--filter` with sanitizers due to a bug in Xcode's xctest helper utility. Run the full test suite instead. See: https://github.com/swiftlang/swift-package-manager/issues/9546

Run all three sanitizers after making changes to core crash handling code, threading code, or memory management. All sanitizer runs should complete with zero warnings.

#### Managing Dependencies
```bash
# Update package dependencies
swift package update
# Updates all dependencies to their latest allowable versions

# Resolve package dependencies
swift package resolve
# Makes sure all dependencies are downloaded and at correct versions
```

### Linting and Formatting

**IMPORTANT**: Always use `make all` to format and lint all code (both C/C++/Objective-C and Swift) in a single command. This ensures consistent formatting across the entire codebase.

```bash
# Format and lint everything (PREFERRED)
make all
# Runs both C/C++/Objective-C and Swift formatting
```

#### C/C++/Objective-C Formatting
```bash
# Check formatting issues
make check-format
# Sample output checks C/C++/Objective-C files against clang-format rules
# Shows warnings for files that don't meet formatting standards

# Apply automatic formatting
make format
# Automatically reformats all C/C++/Objective-C files according to project style
```

#### Swift Formatting
```bash
# Check Swift formatting issues
make check-swift-format
# Checks all Swift files in Sources/, Tests/, and Samples/ directories against .swift-format configuration
# Requires Swift 6.0+ (included with Xcode 16+)

# Apply Swift formatting
make swift-format
# Automatically reformats all Swift files in Sources/, Tests/, and Samples/ according to .swift-format configuration
# Requires Swift 6.0+ (included with Xcode 16+)

# Format specific Swift file
swift format format --in-place --configuration .swift-format <file>
```

### Viewing Crash Reports
- Check Example-Reports/ directory for reference reports
- See Samples/CLAUDE.md for instructions on using the sample app to generate reports

## Architecture Overview

KSCrash is implemented as a layered architecture with these key components:

- **Recording**: Core crash detection and reporting
- **Filters**: Processing crash reports
- **Sinks**: Handling report destinations
- **Installations**: Pre-configured setups
- **Monitors**: Various crash detection mechanisms. Built-in monitors are registered via `KSCrashMonitorType` flags. External monitors can be added as plugins via `KSCrashConfiguration.plugins` (Swift: `MonitorPlugin`, ObjC: `KSCrashMonitorPlugin`), which wrap a `KSCrashMonitorAPI` and are registered at install time via `kscm_addMonitor()`. The `Monitors` Swift module provides ready-made plugins (e.g., `Monitors.metricKit`).

## Watchdog Monitor

The watchdog monitor uses a fixed 250ms threshold to detect hangs on the main thread. This threshold is intentionally not configurable — it aligns with Apple's definition of a "hang" (250ms+) and should not be changed. See `KSCrashMonitor_Watchdog.h` for the rationale.

## Run ID

Each process gets a unique run ID (UUID string), generated once during `kscrash_install()` in `KSCrashC.c`. It is written into the `"report"` section of every crash report under the `"run_id"` key. The buffer is read-only after install, so `kscrash_getRunID()` is async-signal-safe and can be called from crash handlers.

`sendAllReportsWithCompletion:` uses the run ID to skip reports from the current process run, since those reports may still be updated while the process is alive (e.g., sidecar data appended by a monitor). To force-send a specific report regardless, use `sendReportWithID:completion:`.

### Key Files

- `KSCrashC.c` / `KSCrashC.h`: `kscrash_getRunID()` — generates and returns the run ID
- `KSCrashReportFields.h`: `KSCrashField_RunID` (`"run_id"`)
- `KSCrashReportC.c`: Writes `run_id` in `writeReportInfo()`
- `KSCrashReportStore.m`: Filters current-run reports in `sendAllReportsWithCompletion:`
- `ReportInfo.swift`: `runId` property on the Swift model

## Threadcrumb

Threadcrumb is a technique for encoding short messages into a thread's call stack so they can be recovered from crash reports via symbolication. Each allowed character (A-Z, a-z, 0-9, _) maps to a unique function symbol (e.g., `__kscrash__A__`, `__kscrash__B__`). When `log:` is called, these functions are chained recursively to build a stack that mirrors the message. The thread then parks, preserving the shaped stack until the next message or deallocation.

### How It Works

1. Call `[threadcrumb log:@"ABC123"]`
2. The implementation chains function calls: `__kscrash__A__` → `__kscrash__B__` → `__kscrash__C__` → ...
3. The thread parks with this stack intact
4. If a crash occurs, the stack is captured in the crash report
5. During symbolication (locally or on a backend), the frames resolve to their character symbols
6. The original message can be reconstructed by parsing the symbol names

### Resource Considerations

Threadcrumb should be used sparingly or not at all if not needed. Each instance consumes a thread — even though it's parked and idle, it's still a limited system resource. The best approach is to encode a short identifier (like a run ID) that points to more data stored elsewhere, rather than trying to encode large amounts of information directly.

There's a tradeoff between sending a full report as-is without extra on-device work versus having enough embedded data to use the payload effectively. A single identifier that can be used to look up additional context strikes the right balance.

### Use Cases

- **Run ID encoding**: We use threadcrumb to encode the KSCrash run ID into a parked thread for MetricKit correlation
- **Breadcrumbs**: Encode the current application state or user action
- **Feature flags**: Encode active feature flags or A/B test variants
- **Any data that needs to survive a crash**: Since the data lives in the stack, it's captured by any crash reporter

### Backend Symbolication

When a crash report is symbolicated server-side, the threadcrumb frames resolve to their character symbols. The backend can parse these symbol names to reconstruct the encoded message without any special client-side coordination — just symbolicate the stack and read the function names.

### Alternatives Considered

**MetricKit signposts**: We initially tried using `mxSignpost` to log the run ID, but signposts are flaky and often dropped for various reasons, making them unreliable for correlation.

**Payload timestamps**: MetricKit payload timestamps are imprecise — they often represent a time range or the delivery date rather than the actual crash time, making it impossible to reliably match to a specific run.

The threadcrumb approach works because all crash reporters capture call stacks with instruction addresses. By shaping a thread's stack to encode data, we get that data back through standard symbolication.

### Key Files

- `KSCrashThreadcrumb.h/.m`: The threadcrumb implementation
- `MetricKitRunIdHandler.swift`: Uses threadcrumb to encode/decode run IDs for MetricKit correlation

## Monitor Sidecar Files

Sidecars allow monitors to store auxiliary data alongside crash reports without modifying the main report. This is important for monitors (like the Watchdog) that need to update report data after initial writing — doing so with ObjC JSON parsing during a hang would risk deadlocking on the same runtime locks being monitored.

### How Sidecars Work

1. **Writing**: A monitor can request a sidecar path at any time and write auxiliary data there. For example, a monitor might write the initial sidecar during event handling and update it periodically afterwards as conditions change.

2. **At report delivery time** (next app launch): When the report store reads a report via `kscrs_readReport`, it scans the sidecar directories for matching files and calls each monitor's `stitchReport` callback to merge sidecar data into the report before delivery.

3. **Cleanup**: Sidecars are automatically deleted when their associated report is deleted (via `kscrs_deleteReportWithID` or `kscrs_deleteAllReports`).

### Directory Layout

```
<installPath>/
├── Reports/
│   └── myapp-report-00789abc00000001.json
└── Sidecars/
    ├── Watchdog/
    │   └── 00789abc00000001.ksscr
    └── AnotherMonitor/
        └── 00789abc00000001.ksscr
```

Each monitor gets a subdirectory named after its `monitorId`. Sidecar files are named `<reportID>.ksscr` (hex-formatted).

### Requesting a Sidecar Path (Monitor Side)

Monitors receive a `KSCrash_ExceptionHandlerCallbacks` struct during `init()`. The `getSidecarPath` field is a `KSCrashSidecarPathProviderFunc`:

```c
typedef bool (*KSCrashSidecarPathProviderFunc)(const char *monitorId, int64_t reportID,
                                               char *pathBuffer, size_t pathBufferLength);
```

Usage from within a monitor:

```c
static KSCrash_ExceptionHandlerCallbacks *g_callbacks;

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks) {
    g_callbacks = callbacks;
}

// Later, when you have a reportID:
char sidecarPath[KSCRS_MAX_PATH_LENGTH];
if (g_callbacks->getSidecarPath &&
    g_callbacks->getSidecarPath("MyMonitor", reportID, sidecarPath, sizeof(sidecarPath))) {
    // Write sidecar data to sidecarPath using C file I/O
}
```

The callback creates the monitor's subdirectory automatically and returns `false` if sidecars are not configured or the path is too long.

### Stitching Sidecars into Reports (Monitor Side)

To merge sidecar data into reports at delivery time, implement the `stitchReport` field in `KSCrashMonitorAPI`:

```c
char *(*stitchReport)(const char *report, int64_t reportID, const char *sidecarPath);
```

- `report`: NULL-terminated JSON string of the full crash report.
- `sidecarPath`: Path to this monitor's sidecar file for the given report.
- Returns: A `malloc`'d NULL-terminated string with the modified report, or `NULL` to leave the report unchanged. The caller frees the returned buffer.

This runs at normal app startup time (not during crash handling), so ObjC and heap allocation are safe here.

### Configuration

The sidecars directory is configured via `KSCrashReportStoreCConfiguration.sidecarsPath`. If left `NULL` (the default), it is automatically set to `<installPath>/Sidecars` during `kscrash_install`. The report store creates this directory at initialization.

### Key Files

- `KSCrashMonitorContext.h`: `KSCrashSidecarPathProviderFunc` typedef and `getSidecarPath` callback field
- `KSCrashMonitorAPI.h`: `stitchReport` callback field on `KSCrashMonitorAPI`
- `KSCrashMonitor.h/.c`: `kscm_setSidecarPathProvider()` to register the path provider
- `KSCrashReportStoreC.c`: Internal sidecar path generation, cleanup, and stitching logic
- `KSCrashReportStoreC+Private.h`: `kscrs_getSidecarPath()` exported for use by the path provider
- `KSCrashCConfiguration.h`: `sidecarsPath` field on `KSCrashReportStoreCConfiguration`
- `KSCrashC.c`: Wires up the sidecar path provider callback during install

## Critical Development Guidelines

### Async Signal Safety

**IMPORTANT**: Much of KSCrash's core code runs inside crash handlers (signal handlers, Mach exception handlers). This code must be async-signal-safe, meaning it can only call functions that are safe to call from a signal handler context.

**What this means in practice:**
- **No heap allocation**: Do not use `malloc`, `calloc`, `free`, `new`, or any function that allocates memory. Use pre-allocated buffers or stack allocation instead.
- **No locks**: Do not use mutexes, semaphores, or other synchronization primitives that could deadlock if the crash occurred while holding a lock.
- **No Objective-C**: Do not call Objective-C methods or use `@synchronized`. The Objective-C runtime is not async-signal-safe.
- **Limited C library functions**: Many standard C functions are not safe. Safe functions include `memcpy`, `memset`, `strlen`, and similar simple operations.
- **Use atomic operations**: For thread safety, use C11 atomics (`<stdatomic.h>`) which are lock-free and signal-safe.

**However, the same code also runs outside of crash handlers** (during normal operation, initialization, background threads). This dual-use means:
- Code must be correct in both contexts
- You cannot assume "it's fine because it only runs in crash handlers" - that's often false
- Thread safety must be considered alongside signal safety
- Use patterns like atomic exchange (see `KSThreadCache.c`, `KSBinaryImageCache.c`) for lock-free synchronization that works in both contexts

**Writing monitors and `KSCrashMonitorFlagAsyncSafe`**: Each monitor declares flags via its `monitorFlags()` callback. If a monitor's `setEnabled()` implementation is async-signal-safe (no ObjC, no locks, no heap allocation), it should declare `KSCrashMonitorFlagAsyncSafe`. Currently only Signal and MachException do this. The crash handling path uses `kscmr_disableAsyncSafeMonitors()` to disable only these monitors (to restore original handlers for other crash reporters). Monitors that do not declare this flag (e.g., Memory, Deadlock, Watchdog) are skipped during crash-time disable because their `setEnabled()` uses ObjC messaging or other non-signal-safe operations, and they don't need cleanup since the process is terminating. If you write a new monitor whose `setEnabled()` uses ObjC or locks, do **not** set `KSCrashMonitorFlagAsyncSafe`.

When in doubt, check the POSIX list of async-signal-safe functions and follow the patterns established in existing crash handling code.

## Verbose Logging

KSLogger uses compile-time log levels for async-signal-safety. To enable verbose logging during development, pass the log level as a compiler flag:

```bash
swift build -Xcc -DKSLogger_Level=50
swift test -Xcc -DKSLogger_Level=50
```

Log levels: `ERROR=10`, `WARN=20`, `INFO=30`, `DEBUG=40`, `TRACE=50`.

## Run ID

Each process generates a UUID (`run_id`) once during `kscrash_install()`. This ID is written into the `"report"` section of every crash report.

**Purpose**: Reports from the current run may still be updated (e.g., watchdog hang reports that get resolved). `sendAllReportsWithCompletion:` automatically excludes reports whose `run_id` matches the current process. To force-send a current-run report, use `sendReportWithID:includeCurrentRun:completion:` with `includeCurrentRun:YES`.

**Async-signal-safety**: `kscrash_getRunID()` returns a pointer to a static buffer that is written once during install and read-only afterward, so it is safe to call from crash handlers.

**Key files**:
- `KSCrashC.c` / `KSCrashC.h`: UUID generation and `kscrash_getRunID()`
- `KSCrashReportC.c`: Writes `run_id` into the report's `"report"` section
- `KSCrashReportStore.m` / `KSCrashReportStore.h`: Filtering logic and `sendReportWithID:` API
- `ReportInfo.swift`: `runId` property on the Swift report model

## Code Style Guidelines

### Inline Comments

Comment for your future self — the person who has to change this code safely without re-deriving the scary parts. Focus on:

- **Invariants that would break silently**: lock ordering, why a field is atomic (or isn't), why something is intentionally *not* guarded.
- **Non-obvious "why"**: if the reason for a choice isn't clear from the code alone, say why. "Load enterTime once — a second load could see a newer value if the main thread briefly woke" is useful. "Loads enterTime" is not.
- **Threading contracts**: which thread runs a function, and what's safe to touch from it.
- **Simulated or fake values**: when code produces synthetic data (e.g., faking a SIGKILL for watchdog reports), say what it's mimicking and who undoes it.
- **Crash-time constraints**: if code runs in a signal handler or with all threads suspended, say so and say what that means (no lock, no ObjC, etc.).

Do **not** comment:
- What a function does when the name already says it (`monotonicUptime`, `currentTaskRole`).
- Every struct field — only the ones with non-obvious lifetimes, ownership, or threading rules.
- Obvious control flow or standard patterns.

A good test: if removing the comment would make a future change risky, keep it. If the code reads fine without it, skip it.

### Formatting

- C/C++/Objective-C: Follow clang-format style defined in the project
- Swift: Follow Swift standard conventions and Xcode's recommended settings
- Formatting applies to files with extensions: .c, .cpp, .h, .m, .mm
- Use consistent naming patterns:
  - Classes: `KSCrashMonitor_*`, `KSCrash*` (prefix with KS)
  - Methods: descriptive, camelCase
  - **Swift SPM modules**: Do **not** use the `KSCrash` prefix. Use plain names (e.g., `SwiftCore`, `Monitors`, `Profiler`, `Report`). The `KSCrash` prefix is only for C/ObjC targets.
- Error handling: Use proper error handling conventions for Objective-C/Swift
- Module organization: Maintain the existing module structure
- API design: Keep public APIs clean and well-documented
- **Testing**: Always run sanitizers (ASan, TSan, UBSan) after changes to catch issues early

### File Headers

Every source file must include a header with the following components:

1. **Filename**: The name of the file as a comment
2. **Created by**: Author name and creation date
3. **Copyright**: Original copyright year (2012) and copyright holder (Karl Stenerud)
4. **License**: The MIT license text

**Standard header format:**
```c
//
//  KSExample.c
//
//  Created by Your Name on YYYY-MM-DD.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
```

**For files derived from or inspired by other projects:**
If a file is based on code from another project, include the original copyright and license after the KSCrash license:

```c
//
//  KSExample.c
//
//  Created by Your Name on YYYY-MM-DD.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// [KSCrash MIT license text...]
//
// Inspired by original-project/original-file
// https://github.com/original/project
//
// [Original project's copyright and license text...]
//
```