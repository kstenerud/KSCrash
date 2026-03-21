# CLAUDE.md

## Build and Test Commands

- Build (debug): `swift build`
- Build (release): `swift build -c release`
- Build specific product: `swift build --product Recording`
- Run tests: `swift test`
- Run specific test target: `swift test --filter KSCrashCore_Tests`
- Run specific test case: `swift test --filter KSCrash_Tests/testUserInfo`
- List tests: `swift test list`
- Tests with code coverage: `swift test --enable-code-coverage`
- Tests in parallel: `swift test --parallel`
- Update dependencies: `swift package update`
- Resolve dependencies: `swift package resolve`

### Sanitizers

Run sanitizers frequently, especially after changes to crash handling, threading, or memory management:

```bash
swift test --sanitize address    # memory errors
swift test --sanitize thread     # data races
swift test --sanitize undefined  # undefined behavior
```

**Known Issue**: Do not use `--filter` with sanitizers due to a bug in Xcode's xctest helper. Run the full test suite instead. See: https://github.com/swiftlang/swift-package-manager/issues/9546

### Formatting

```bash
make all              # format everything (C/C++/ObjC + Swift) — PREFERRED
make format           # C/C++/ObjC only
make check-format     # check C/C++/ObjC only
make swift-format     # Swift only
make check-swift-format  # check Swift only
make namespace        # regenerate KSCrashNamespace.h (required after adding/removing C symbols)
swift format format --in-place --configuration .swift-format <file>  # single Swift file
```

## Project Structure

- `Package.swift`: KSCrash framework with multiple library products
- `KSCrash.podspec`: CocoaPods spec — must stay in sync with Package.swift
- `Samples/`: Sample app (Tuist-based) and integration tests
- `.mise.toml`: Tool version management (Tuist). Setup: `mise install && mise trust`
- `Example-Reports/`: Reference crash reports
- `Samples/CLAUDE.md`: Instructions for generating crash reports with the sample app

## Architecture Overview

KSCrash is a layered crash reporting framework:

- **Recording**: Core crash detection and reporting
- **Filters**: Processing crash reports
- **Sinks**: Handling report destinations
- **Installations**: Pre-configured setups
- **Monitors**: Crash detection mechanisms (see `.claude/rules/monitors.md` for the full reference)
- **RunContext**: Cross-monitor shared state and previous-run analysis (see `.claude/rules/run-context.md`)

Public modules (API surface): KSCrashRecording, KSCrashFilters, KSCrashSinks, KSCrashInstallations, KSCrashDiscSpaceMonitor, KSCrashBootTimeMonitor, KSCrashDemangleFilter, Monitors (Swift), Report (Swift), KSCrashProfiler (Swift). Public headers: `Sources/[ModuleName]/include/*.h`.

## Verbose Logging

KSLogger uses compile-time log levels for async-signal-safety:

```bash
swift build -Xcc -DKSLogger_Level=50
swift test -Xcc -DKSLogger_Level=50
```

Log levels: `ERROR=10`, `WARN=20`, `INFO=30`, `DEBUG=40`, `TRACE=50`.
