---
paths:
  - "Package.swift"
---

## Public Modules

The public API surface consists of these modules: **KSCrashRecording**, **KSCrashFilters**, **KSCrashSinks**, **KSCrashDiscSpaceMonitor**, **KSCrashBootTimeMonitor**, and **KSCrashDemangleFilter**. Public headers live in `Sources/[ModuleName]/include/*.h`.

## Swift SPM Module Naming

All SPM modules (targets) use the `KSCrash` prefix, Swift and C/ObjC alike (e.g., `KSCrashSwiftCore`, `KSCrashMonitors`, `KSCrashProfiler`, `KSCrashReportModel`). Library **product** names stay unprefixed (e.g., `Monitors`, `Report`), matching the C targets: a consumer depends on the `Report` product and writes `import KSCrashReportModel`. The Swift report-model module is `KSCrashReportModel`, not `KSCrashReport`, because `KSCrashReport` is already the public ObjC protocol (Swift-named `CrashReport`) and a module/type name clash breaks qualified references.

## KSCrashNamespace.h

Never edit `KSCrashNamespace.h` by hand — always run `make namespace` to regenerate it. This must be done after adding or removing any C/ObjC symbols.
