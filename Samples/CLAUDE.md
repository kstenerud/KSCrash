# Samples CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Sample app in this directory.

## Prerequisites
- Mise installed: `curl https://mise.run | sh` or follow [mise installation guide](https://mise.jdx.dev/getting-started.html)
- Xcode 15+ recommended

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

### Running Integration Tests

#### Using Tuist
```bash
mise exec -- tuist test --platform ios
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