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
  - Common/Package.swift: Local package referenced by the sample app
  - Tests/: Integration tests for the framework

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