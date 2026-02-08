# Benchmarks CLAUDE.md

This file provides guidance when working with the Benchmarks app in this directory.

## Prerequisites
- Mise installed: `curl https://mise.run | sh` or follow [mise installation guide](https://mise.jdx.dev/getting-started.html)
- Xcode 16+ recommended
- For device testing: Apple Developer account and connected iOS device

## Version Management
This project uses Mise to pin the Tuist version for consistency across development and CI environments.

- **Tuist version**: Defined in `../.mise.toml`
- **Install tools**: `mise install` (installs Tuist version from config)
- **Trust config**: `mise trust` (required once for security)
- **Run Tuist**: `mise exec -- tuist <command>` or activate mise in your shell

## Benchmarks Workflow

### Quick Start
1. Install tools: `mise install`
2. Trust config: `mise trust` (first time only)
3. Generate project: `mise exec -- tuist generate`
4. Open workspace: `open KSCrashBenchmarks.xcworkspace`
5. Select the Benchmarks scheme and run tests

### Running on Simulator
```bash
# Generate the project
mise exec -- tuist generate

# Run all benchmarks on iOS Simulator
xcodebuild -workspace KSCrashBenchmarks.xcworkspace \
  -scheme Benchmarks \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

### Running on Device
For accurate performance measurements, run benchmarks on a physical device:

```bash
# Generate the project
mise exec -- tuist generate

# Run benchmarks on connected device (replace device name as needed)
xcodebuild -workspace KSCrashBenchmarks.xcworkspace \
  -scheme Benchmarks \
  -destination 'platform=iOS,name=Your iPhone' \
  -allowProvisioningUpdates \
  test
```

**Note:** Device testing requires:
- Code signing configured in Xcode (open workspace, select team in Signing & Capabilities)
- Or add `CODE_SIGN_STYLE` and `DEVELOPMENT_TEAM` to Project.swift settings

### Running Specific Benchmarks
```bash
# Run only crash report benchmarks
xcodebuild test -workspace KSCrashBenchmarks.xcworkspace \
  -scheme Benchmarks \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BenchmarkTests/KSCrashReportBenchmarks

# Run only thread benchmarks
xcodebuild test -workspace KSCrashBenchmarks.xcworkspace \
  -scheme Benchmarks \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BenchmarkTests/KSThreadBenchmarks
```

## Available Benchmark Suites

The benchmarks test KSCrash's core crash capture performance:

- **KSBacktraceBenchmarks** - Stack capture and symbolication
- **KSDynamicLinkerBenchmarks** - Binary image lookups and caching
- **KSMemoryBenchmarks** - Safe memory operations
- **KSJSONCodecBenchmarks** - JSON encoding performance
- **KSThreadBenchmarks** - Thread operations and caching
- **KSCrashReportBenchmarks** - Full crash report generation
- **KSProfilerBenchmarks** - Sampling profiler performance
- **KSCxaThrowBenchmarks** - C++ exception handling (warm)
- **KSCxaThrowColdBenchmarks** - C++ exception handling (cold)

## Project Structure

```
Benchmarks/
├── Project.swift          # Tuist project configuration
├── Sources/
│   └── BenchmarkApp.swift # Minimal host app
└── CLAUDE.md              # This file
```

The benchmark tests are located in the main repository:
- `Tests/KSCrashBenchmarks/` - Swift benchmarks
- `Tests/KSCrashBenchmarksObjC/` - Objective-C benchmarks
- `Tests/KSCrashBenchmarksCold/` - Cold-start benchmarks

## Writing Swift Benchmarks for BrowserStack

**Requirements for Swift benchmark classes:**

1. Inherit from `KSBenchmarkTestCase` (or `XCTestCase` directly if needed)
2. Use plain `class` — no `@objc`, `public`, or `final` annotations needed

```swift
// Correct
class KSMyBenchmarks: KSBenchmarkTestCase {
    func testBenchmarkSomething() {
        measure {
            // benchmark code
        }
    }
}
```

Swift classes inheriting from `XCTestCase` are automatically registered with the ObjC runtime, which is sufficient for BrowserStack test discovery.

## Interpreting Results

Benchmark results show:

- **Time**: Average execution time
- **Std Dev**: Measurement variability (lower is more consistent)
- **Status**: Performance rating based on thresholds

For reliable results:

- Run on device (not simulator) for accurate timing
- Close other apps to reduce interference
- Run multiple times to verify consistency
