---
paths:
  - "Package.swift"
  - "KSCrash.podspec"
---

## Package.swift / Podspec Sync

`KSCrash.podspec` must stay in sync with `Package.swift`. When adding a new target or dependency in Package.swift, always add the corresponding subspec and dependency in the podspec. CI lint jobs will fail otherwise.

## Public Modules

The public API surface consists of these modules: **KSCrashRecording**, **KSCrashFilters**, **KSCrashSinks**, **KSCrashInstallations**, **KSCrashDiscSpaceMonitor**, **KSCrashBootTimeMonitor**, and **KSCrashDemangleFilter**. Public headers live in `Sources/[ModuleName]/include/*.h`.

## Swift SPM Module Naming

Swift SPM modules should **not** use the `KSCrash` prefix. Use plain names (e.g., `SwiftCore`, `Monitors`, `Profiler`, `Report`). The `KSCrash` prefix is only for C/ObjC targets.
