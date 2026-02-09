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
- **Monitors**: Various crash detection mechanisms

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

## Code Style Guidelines

- C/C++/Objective-C: Follow clang-format style defined in the project
- Swift: Follow Swift standard conventions and Xcode's recommended settings
- Formatting applies to files with extensions: .c, .cpp, .h, .m, .mm
- Use consistent naming patterns:
  - Classes: `KSCrashMonitor_*`, `KSCrash*` (prefix with KS)
  - Methods: descriptive, camelCase
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