---
paths:
  - "Sources/KSCrashRecording/KSCrashC.{c,h}"
  - "Sources/KSCrashRecording/include/KSCrashC.h"
  - "Sources/KSCrashRecording/KSCrashReportC.{c,h}"
  - "Sources/KSCrashRecording/include/KSCrashReportFields.h"
  - "Sources/KSCrashRecording/KSCrashReportStore.m"
  - "Sources/KSCrashRecording/include/KSCrashReportStore.h"
  - "Sources/Report/Models/ReportInfo.swift"
---

## Run ID

Each process gets a unique run ID (UUID string), generated once during `kscrash_install()` in `KSCrashC.c`. It is written into the `"report"` section of every crash report under the `"run_id"` key. The buffer is read-only after install, so `kscrash_getRunID()` is async-signal-safe and can be called from crash handlers.

**Purpose**: Reports from the current run may still be updated (e.g., watchdog hang reports that get resolved). `sendAllReportsWithCompletion:` automatically excludes reports whose `run_id` matches the current process. To force-send a current-run report, use `sendReportWithID:includeCurrentRun:completion:` with `includeCurrentRun:YES`.

### Key Files

- `KSCrashC.c` / `KSCrashC.h`: UUID generation and `kscrash_getRunID()`
- `KSCrashReportFields.h`: `KSCrashField_RunID` (`"run_id"`)
- `KSCrashReportC.c`: Writes `run_id` in `writeReportInfo()`
- `KSCrashReportStore.m` / `KSCrashReportStore.h`: Filtering logic and `sendReportWithID:` API
- `ReportInfo.swift`: `runId` property on the Swift model
