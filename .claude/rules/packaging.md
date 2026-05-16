---
paths:
  - "Package.swift"
---

## Public Modules

The public API surface consists of these modules: **KSCrashRecording**, **KSCrashFilters**, **KSCrashSinks**, **KSCrashInstallations**, **KSCrashDiscSpaceMonitor**, **KSCrashBootTimeMonitor**, and **KSCrashDemangleFilter**. Public headers live in `Sources/[ModuleName]/include/*.h`.

## Swift SPM Module Naming

Swift SPM modules should **not** use the `KSCrash` prefix. Use plain names (e.g., `SwiftCore`, `Monitors`, `Profiler`, `Report`). The `KSCrash` prefix is only for C/ObjC targets.

## KSCrashNamespace.h

Never edit `KSCrashNamespace.h` by hand — always run `make namespace` to regenerate it. This must be done after adding or removing any C/ObjC symbols.
