---
paths:
  - "Sources/KSCrashRecording/KSCrashReportStoreC.c"
  - "Sources/KSCrashRecording/KSCrashReportStoreC+Private.h"
  - "Sources/KSCrashRecording/KSCrashReportStore.m"
  - "Sources/KSCrashRecording/include/KSCrashReportStore*.h"
  - "Sources/KSCrashRecording/include/KSCrashCConfiguration.h"
  - "Sources/KSCrashRecordingCore/include/KSCrashMonitorContext.h"
  - "Sources/KSCrashRecordingCore/include/KSCrashMonitorAPI.h"
  - "Sources/KSCrashRecording/Monitors/*Sidecar*"
  - "Sources/KSCrashRecording/Monitors/*Stitch*"
  - "Sources/KSCrashRecording/KSCrashC.c"
  - "Sources/KSCrashRecording/include/KSCrashC.h"
---

## Monitor Sidecar Files

Sidecars allow monitors to store auxiliary data alongside crash reports without modifying the main report. This is important for monitors (like the Watchdog) that need to update report data after initial writing — doing so with ObjC JSON parsing during a hang would risk deadlocking on the same runtime locks being monitored.

### How Sidecars Work

1. **Writing**: A monitor can request a sidecar path at any time and write auxiliary data there. For example, a monitor might write the initial sidecar during event handling and update it periodically afterwards as conditions change.

2. **At report delivery time** (next app launch): When the report store reads a report via `kscrs_readReport`, it scans the sidecar directories for matching files and calls each monitor's `createStitchedReport` callback to merge sidecar data into the report before delivery.

3. **Cleanup**: Sidecars are automatically deleted when their associated report is deleted (via `kscrs_deleteReportWithID` or `kscrs_deleteAllReports`).

### Directory Layout

```
<installPath>/
├── Reports/
│   └── myapp-report-00789abc00000001.json
├── Sidecars/                                          (per-report)
│   ├── Watchdog/
│   │   └── 00789abc00000001.ksscr
│   └── AnotherMonitor/
│       └── 00789abc00000001.ksscr
└── RunSidecars/                                       (per-run)
    └── a1b2c3d4-e5f6-7890-abcd-ef1234567890/
        └── Watchdog.ksscr
```

Per-report sidecars: `Sidecars/<monitorId>/<reportID>.ksscr` — one file per report per monitor. Per-run sidecars: `RunSidecars/<runID>/<monitorId>.ksscr` — one file per process run per monitor, shared across all reports from that run.

### Requesting a Sidecar Path (Monitor Side)

Monitors receive a `KSCrash_ExceptionHandlerCallbacks` struct during `init()`. Two path callbacks are available:

- `getReportSidecarPath` (`KSCrashReportSidecarPathProviderFunc`) — per-report sidecar, tied to a specific crash report ID.
- `getRunSidecarPath` (`KSCrashSidecarRunPathProviderFunc`) — per-run sidecar, shared across all reports from the current process run.

Usage from within a monitor:

```c
static KSCrash_ExceptionHandlerCallbacks *g_callbacks;

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks) {
    g_callbacks = callbacks;
}

// Per-report sidecar (when you have a reportID):
char sidecarPath[KSCRS_MAX_PATH_LENGTH];
if (g_callbacks->getReportSidecarPath &&
    g_callbacks->getReportSidecarPath("MyMonitor", reportID, sidecarPath, sizeof(sidecarPath))) {
    // Write sidecar data to sidecarPath using C file I/O
}

// Per-run sidecar (no reportID needed):
char runSidecarPath[KSCRS_MAX_PATH_LENGTH];
if (g_callbacks->getRunSidecarPath &&
    g_callbacks->getRunSidecarPath("MyMonitor", runSidecarPath, sizeof(runSidecarPath))) {
    // Write per-run data to runSidecarPath using C file I/O
}
```

Both callbacks create the necessary subdirectories automatically and return `false` if sidecars are not configured or the path is too long.

### Stitching Sidecars into Reports (Monitor Side)

To merge sidecar data into reports at delivery time, implement the `createStitchedReport` field in `KSCrashMonitorAPI`:

```c
CFDictionaryRef (*createStitchedReport)(CFDictionaryRef reportDict, const char *sidecarPath,
                                        KSCrashSidecarScope scope, void *context);
```

Follows the CF Create Rule:

- `reportDict`: The decoded report dictionary (toll-free bridged to NSDictionary). Owned by the caller, the callback must not release it.
- `sidecarPath`: Path to this monitor's sidecar file for the given report.
- `scope`: `KSCrashSidecarScopeReport` for per-report sidecars, `KSCrashSidecarScopeRun` for per-run sidecars.
- `context`: The monitor's opaque context pointer (same as `api->context`).
- Returns: A +1 `CFDictionaryRef` with the (possibly modified) report, or `NULL` on failure. The caller takes ownership via `__bridge_transfer` to ARC. For no-op returns (e.g. wrong scope), `CFRetain` the input and return it.

`NULL` signals a stitch error. During finalization this aborts the write-back so the report can be retried on next app launch. During normal reads the error is silent and the original dict is kept.

Run sidecars are stitched first, then per-report sidecars, so per-report data can override per-run data.

This runs at normal app startup time (not during crash handling), so ObjC and heap allocation are safe here.

### Configuration

The sidecars directories are configured via `KSCrashReportStoreCConfiguration.reportSidecarsPath` and `runSidecarsPath`. If left `NULL` (the default), they are automatically set to `<installPath>/Sidecars` and `<installPath>/RunSidecars` during `kscrash_install`. The report store creates these directories at initialization. Orphaned run sidecar directories (those with no matching reports) are cleaned up automatically during `kscrs_initialize`.

### Key Files

- `KSCrashMonitorContext.h`: `KSCrashReportSidecarPathProviderFunc`, `KSCrashSidecarRunPathProviderFunc` typedefs and `getReportSidecarPath`, `getRunSidecarPath` callback fields
- `KSCrashMonitorAPI.h`: `createStitchedReport` callback field on `KSCrashMonitorAPI`
- `KSCrashMonitor.h/.c`: `kscm_setReportSidecarPathProvider()` and `kscm_setRunSidecarPathProvider()` to register path providers
- `KSCrashReportStoreC.c`: Internal sidecar path generation, cleanup, stitching, and orphan cleanup logic
- `KSCrashReportStoreC+Private.h`: `kscrs_getReportSidecarFilePathForReport()` and `kscrs_getRunSidecarFilePath()` exported for use by path providers
- `KSCrashCConfiguration.h`: `reportSidecarsPath` and `runSidecarsPath` fields on `KSCrashReportStoreCConfiguration`
- `KSCrashC.c`: Wires up the sidecar path provider callbacks during install

### Report Finalization

By default, sidecars are stitched into reports at next app launch when the report store reads them. Finalization stitches sidecars at runtime instead, so the report reflects current-session state rather than whatever state exists at next launch.

Finalization is triggered by passing `finalize=true` to `handleWithResult`. The handler writes the report and fires `didWriteReport` inside the event callback, then resumes suspended threads, frees the exception slot, and finally calls the separate `onFinalizeReport` callback which runs `kscrs_finalizeReport`. This ordering ensures finalization (ObjC/JSON/file I/O) never runs while threads are suspended.

Monitors that finalize: User (non-terminal), NSException (user-reported), Profiler. Watchdog manages its own finalization in `finalizeResolvedHang()` after the hang resolves, so it passes `finalize=false`. Finalization is ignored for fatal reports.

Finalization is not async-signal-safe, so it must only be used for non-fatal reports where the app continues running normally. Already-finalized reports are skipped on next-launch reads to avoid redundant stitching.
