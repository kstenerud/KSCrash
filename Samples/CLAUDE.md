# Samples CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Sample app in this directory.

## Prerequisites
- Mise installed: `curl https://mise.run | sh` or follow [mise installation guide](https://mise.jdx.dev/getting-started.html)
- Xcode 26 or later

## Version Management
This project uses Mise to pin the Tuist version for consistency across development and CI environments.

- **Tuist version**: Defined in `../.mise.toml` 
- **Install tools**: `mise install` (installs Tuist version from config)
- **Trust config**: `mise trust` (required once for security)
- **Run Tuist**: `mise exec -- tuist <command>` or activate mise in your shell

## Sample App Workflow
1. Install tools: `mise install`
2. Trust config: `mise trust` (first time only)
3. Generate project: `mise exec -- tuist generate`
4. Open workspace: `open KSCrashSamples.xcworkspace`
5. Build and run the Sample scheme in Xcode

## Building Sample App

### Using Tuist (via Mise)
```bash
# Install and trust tools first
mise install
mise trust

# Generate the project first (if not already done)
mise exec -- tuist generate

# Build the Sample scheme for iOS
mise exec -- tuist build Sample --platform ios

# Build with specific configuration
mise exec -- tuist build Sample --platform ios --configuration Debug
```

### Using Tuist (if activated in shell)
```bash
# Add to your shell profile (~/.zshrc, ~/.bashrc)
eval "$(mise activate zsh)"  # or bash/fish

# Then use tuist directly
tuist generate
tuist build Sample --platform ios
```

### Using xcodebuild
```bash
# Build the Sample scheme for iOS Simulator
xcodebuild -scheme Sample -sdk iphonesimulator

# Build with specific device
xcodebuild -scheme Sample -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Integration Tests

The integration tests run on the Mac whatever platform they test. They launch the Sample app
themselves (a child process on macOS, `simctl` on a simulator), crash it on purpose, relaunch it
to send the report, and check what arrives. XCTest never launches or watches the app. On a
simulator platform they create a fresh simulator for the run and delete it afterwards.

### Running Integration Tests
CI (`.github/workflows/integration-tests.yml`) is the reference. Locally, from `Samples/`:
```bash
mise exec -- tuist generate --no-open

# Simulator platforms only: build the app for that simulator (tests look for it in the
# same derived data). Use the tvOS, watchOS or visionOS Simulator destination to match.
xcodebuild build -workspace KSCrashSamples.xcworkspace -scheme Sample -configuration Release \
    -destination 'generic/platform=iOS Simulator'

# The tests always run on macOS; KSCRASH_IT_PLATFORM (required) names the platform they drive.
TEST_RUNNER_KSCRASH_IT_PLATFORM=iOS xcodebuild test -workspace KSCrashSamples.xcworkspace \
    -scheme Sample -destination 'platform=macOS'
```
Add `-only-testing:SampleTests/NSExceptionTests/testGenericException` to run one test. On a
simulator platform the tests create a simulator for the run and delete it afterwards;
`KSCRASH_IT_DEVICE`, `KSCRASH_IT_RUNTIME` and `KSCRASH_IT_DEVICE_TYPE` (each passed with the
`TEST_RUNNER_` prefix) choose one instead.

A test class that only applies to some platforms lists them in `platforms`, and is skipped
elsewhere with the reason in the results. Retries are off: a flaky test is a bug to fix.

### Enhanced Security
A second macOS lane runs the suite against the Sample built the way an app adopting Xcode's
Enhanced Security capability is built: arm64e, signed with `EnhancedSecurity.entitlements`.
macOS enforces those entitlements from 26 on, with System Integrity Protection enabled.
`EnhancedSecurityTests` runs only in this lane and fails it if the app is not arm64e or is not
under the restrictions. Locally, from `Samples/`:
```bash
xcodebuild build -workspace KSCrashSamples.xcworkspace -scheme Sample -configuration Release \
    -destination 'platform=macOS' -derivedDataPath /tmp/es \
    ENABLE_POINTER_AUTHENTICATION=YES KSCRASH_SAMPLE_ENTITLEMENTS=EnhancedSecurity.entitlements

TEST_RUNNER_KSCRASH_IT_PLATFORM=macOS TEST_RUNNER_KSCRASH_IT_ENHANCED_SECURITY=1 \
    TEST_RUNNER_KSCRASH_IT_APP=/tmp/es/Build/Products/Release/Sample.app \
    xcodebuild test -workspace KSCrashSamples.xcworkspace -scheme Sample -destination 'platform=macOS'
```

### Available Test Types
- NSException (generic exception)
- Mach exception (bad access)
- C++ exception (runtime exception)
- Signal (abort, termination)
- User reported exceptions

## Sample App Features

### Crash Types
The sample app demonstrates various crash types that KSCrash can detect:
- Signal crashes (abort, segmentation fault)
- NSExceptions
- C++ exceptions
- Deadlocks
- Memory issues
- User-reported crashes

### Generating and Viewing Crash Reports
1. Launch the app and navigate to the Crash tab
2. Select a crash type to trigger
3. After relaunching the app, navigate to the Reports tab to view crash reports
4. Use the UI to export or send reports for further analysis