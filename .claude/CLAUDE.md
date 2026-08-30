# CLAUDE.md

## Hot-Path Principle

KSCrash runs inside someone else's app and must never change that app's
efficiency or performance. Any path the host app drives while running
(metadata writes, monitor callbacks, recording) does as little as possible.
Defer interpretation, normalization, and cleanup to read/send time, which
happens later, off the hot path.

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
- `Samples/`: Sample app (Tuist-based) and integration tests
- `.mise.toml`: Tool version management (Tuist). Setup: `mise install && mise trust`
- `Example-Reports/`: Reference crash reports
- `Samples/CLAUDE.md`: Instructions for generating crash reports with the sample app

## Architecture Overview

KSCrash is a layered crash reporting framework:

- **Install & Runtime**: Swift-owned in the `KSCrash` module: `KSCrash.shared.install(InstallConfiguration)`, plugins by instance, `metadata` (LiveMetadata), `SessionRecorder`, `hangEvents`, `Backtrace`
- **Recording**: Core crash detection and reporting (C, driven by the Swift install)
- **Send**: The Swift async send in the `KSCrash` module (`sendReports`, `sendRunSummaries`): pending items walk a `PipelineStage` pipeline one at a time
- **Monitors**: Crash detection mechanisms (see `.claude/rules/monitors.md` for the full reference)
- **RunContext**: Cross-monitor shared state and previous-run analysis (see `.claude/rules/run-context.md`)
- **Sessions & Run Summaries**: Per-run `.sessions` log, `.run` telemetry, session_id stitching, and orphan reclaim (see `.claude/rules/sessions.md`)

Public modules (API surface): KSCrashRecording, KSCrashDiskMonitor, KSCrashBootMonitor, KSCrash (Swift umbrella, the async send), KSCrashMonitors (Swift), KSCrashMonitorPlugins (Swift, the plugin base), KSCrashReportModel (Swift), KSCrashProfiler (Swift). Public headers: `Sources/[ModuleName]/include/*.h`.

## Source-Breaking Changes

A change is source-breaking **only if it breaks code that compiled against the most recent tagged release** (`git describe --tags --abbrev=0`), not against master. Symbols, types, or shapes that do not exist at the release tag cannot be source-breaking, no matter how they evolve on master. Always verify against the release tag before acting on a review comment, automated flag, or memory note that calls something source-breaking. See `.claude/rules/api-stability.md` for the full rule and the list of changes that warrant flagging.

`develop` is the 3.0.0 line: source-breaking changes are expected and fine here. The public Objective-C API is being replaced by Swift and is going away, so removing or renaming ObjC declarations and dropping `NS_SWIFT_NAME` are normal on `develop` and must not be reported as problems. The tagged-release stability check above applies only to changes destined for a `release/*` maintenance branch.

## Verbose Logging

KSLogger uses compile-time log levels for async-signal-safety:

```bash
swift build -Xcc -DKSLogger_Level=50
swift test -Xcc -DKSLogger_Level=50
```

Log levels: `ERROR=10`, `WARN=20`, `INFO=30`, `DEBUG=40`, `TRACE=50`.
