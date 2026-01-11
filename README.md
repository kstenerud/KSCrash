# KSCrash

![KSCrash](https://github.com/user-attachments/assets/9478bde6-78ae-4d59-b8ab-dc6db4137b9f)

[![Run Unit Tests](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/unit-tests.yml)
[![CocoaPods Lint](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml/badge.svg)](https://github.com/kstenerud/KSCrash/actions/workflows/cocoapods-lint.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kstenerud/KSCrash)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkstenerud%2FKSCrash%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kstenerud/KSCrash)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/kstenerud?style=flat&logo=githubsponsors&label=Sponsors)](https://github.com/sponsors/kstenerud)

**The ultimate crash reporter for Apple platforms.**

KSCrash captures crashes and terminations with deep diagnostic information, helping you understand exactly what went wrong. Supports iOS 12+, macOS 10.14+, tvOS 12+, watchOS 5+, and visionOS 1+.

## Features

- **Full crash coverage** - Mach exceptions, signals, C++/Objective-C exceptions, watchdog timeouts, and OOM detection
- **Deep diagnostics** - Memory introspection, on-device symbolication, and automated crash diagnosis
- **Proactive monitoring** - Memory pressure tracking, hang detection, and sampling profiler
- **Flexible reporting** - JSON or Apple-format reports with HTTP upload, email, or custom delivery

## Quick Start

### Installation

**Swift Package Manager:**
```swift
.package(url: "https://github.com/kstenerud/KSCrash.git", .upToNextMajor(from: "2.5.0"))
```

**CocoaPods:**
```ruby
pod 'KSCrash', '~> 2.5'
```

### Basic Usage

Initialize KSCrash early in your app's lifecycle (in `init()`, not `didFinishLaunching`):

```swift
import KSCrashInstallations

@main
struct MyApp: App {
    init() {
        let installation = CrashInstallationStandard.shared
        installation.url = URL(string: "https://your-server.com/crashes")!
        installation.install(with: nil)
        installation.sendAllReports { reports, error in
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

For detailed documentation, see the [Wiki](https://github.com/kstenerud/KSCrash/wiki).

## Community

- **Slack** - [Join the KSCrash Slack](https://join.slack.com/t/kscrash/shared_invite/zt-3lq7n9ss7-m97NrPJW3l9pvpZl17ztbg)
- **GitHub Discussions** - Ask questions and share ideas
- **Discord** - [Join the KSCrash Discord](https://discord.gg/HK6emPCm)

## Support the Project

If KSCrash has been valuable for your projects, consider [sponsoring on GitHub](https://github.com/sponsors/kstenerud).

## License

MIT License - Copyright (c) 2012 Karl Stenerud

See [LICENSE](LICENSE) for full text.
