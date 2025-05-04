# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

- Format code: `make format`
- Check formatting: `make check-format`
- Run Swift tests: `swift test`
- Run single Swift test target: `swift test --target KSCrashRecordingTests`
- Run integration tests: `xcodebuild test -scheme Sample -testPlan Integration -destination 'platform=iOS Simulator,name=iPhone 15'`
- Build Swift package: `swift build`
- Generate Xcode project: `tuist generate`
- Build sample app: `tuist build`

## Project Structure

- Main Package.swift: Defines the KSCrash framework with multiple library products
- Samples/: Contains sample app and integration tests
  - Uses Tuist for project generation (Project.swift)
  - Common/Package.swift: Local package referenced by the sample app
  - Tests/: Integration tests for the framework

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