# Samples CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Sample app in this directory.

## Prerequisites
- Tuist installed: `brew install tuist`
- Xcode 15+ recommended

## Sample App Workflow
1. Generate project: `tuist generate`
2. Open workspace: `open KSCrashSamples.xcworkspace`
3. Build and run the Sample scheme in Xcode

## Building Sample App

### Using Tuist
```bash
# Generate the project first (if not already done)
tuist generate

# Build the Sample scheme for iOS
tuist build Sample --platform ios

# Build with specific configuration
tuist build Sample --platform ios --configuration Debug
```

### Using xcodebuild
```bash
# Build the Sample scheme for iOS Simulator
xcodebuild -scheme Sample -sdk iphonesimulator

# Build with specific device
xcodebuild -scheme Sample -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Integration Tests

### Running Integration Tests

#### Using Tuist
```bash
tuist test --platform ios
```

#### Using xcodebuild
```bash
xcodebuild test -scheme Sample -testPlan Integration -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Running Specific Test
```bash
xcodebuild test -scheme Sample -testPlan Integration -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing SampleTests/NSExceptionTests/testGenericException
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