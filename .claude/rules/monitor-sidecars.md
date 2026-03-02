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

2. **At report delivery time** (next app launch): When the report store reads a report via `kscrs_readReport`, it scans the sidecar directories for matching files and calls each monitor's `stitchReport` callback to merge sidecar data into the report before delivery.

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

To merge sidecar data into reports at delivery time, implement the `stitchReport` field in `KSCrashMonitorAPI`:

```c
char *(*stitchReport)(const char *report, const char *sidecarPath, KSCrashSidecarScope scope, void *context);
```

- `report`: NULL-terminated JSON string of the full crash report.
- `sidecarPath`: Path to this monitor's sidecar file for the given report.
- `scope`: `KSCrashSidecarScopeReport` for per-report sidecars, `KSCrashSidecarScopeRun` for per-run sidecars.
- `context`: The monitor's opaque context pointer (same as `api->context`).
- Returns: A `malloc`'d NULL-terminated string with the modified report, or `NULL` to leave the report unchanged. The caller frees the returned buffer.

Run sidecars are stitched first, then per-report sidecars, so per-report data can override per-run data.

This runs at normal app startup time (not during crash handling), so ObjC and heap allocation are safe here.

### Configuration

The sidecars directories are configured via `KSCrashReportStoreCConfiguration.reportSidecarsPath` and `runSidecarsPath`. If left `NULL` (the default), they are automatically set to `<installPath>/Sidecars` and `<installPath>/RunSidecars` during `kscrash_install`. The report store creates these directories at initialization. Orphaned run sidecar directories (those with no matching reports) are cleaned up automatically during `kscrs_initialize`.

### Key Files

- `KSCrashMonitorContext.h`: `KSCrashReportSidecarPathProviderFunc`, `KSCrashSidecarRunPathProviderFunc` typedefs and `getReportSidecarPath`, `getRunSidecarPath` callback fields
- `KSCrashMonitorAPI.h`: `stitchReport` callback field on `KSCrashMonitorAPI`
- `KSCrashMonitor.h/.c`: `kscm_setReportSidecarPathProvider()` and `kscm_setRunSidecarPathProvider()` to register path providers
- `KSCrashReportStoreC.c`: Internal sidecar path generation, cleanup, stitching, and orphan cleanup logic
- `KSCrashReportStoreC+Private.h`: `kscrs_getReportSidecarFilePathForReport()` and `kscrs_getRunSidecarFilePath()` exported for use by path providers
- `KSCrashCConfiguration.h`: `reportSidecarsPath` and `runSidecarsPath` fields on `KSCrashReportStoreCConfiguration`
- `KSCrashC.c`: Wires up the sidecar path provider callbacks during install
