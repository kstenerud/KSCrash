---
paths:
  - "Sources/KSCrashRecording/KSCrashC.{c,h}"
  - "Sources/KSCrashRecording/include/KSCrashC.h"
  - "Sources/KSCrashRecording/KSCrashReportC.{c,h}"
  - "Sources/KSCrashRecording/include/KSCrashReportFields.h"
  - "Sources/KSCrash/ReportSend.swift"
  - "Sources/KSCrashReportModel/Models/ReportInfo.swift"
---

## Run ID

Each process gets a unique run ID (UUID string), generated once during `kscrash_install()` in `KSCrashC.c`. It is written into the `"report"` section of every crash report under the `"run_id"` key. The buffer is read-only after install, so `kscrash_getRunID()` is async-signal-safe and can be called from crash handlers.

**Purpose**: Reports from the current run may still be updated (e.g., watchdog hang reports that get resolved). The bulk Swift send, `KSCrash.sendReports(with:)`, skips reports whose `run_id` matches the current process. The check lives in `ReportSend.swift` and compares the store's `liveRunID` against `Store.runID(of:)`, a peek backed by `kscrs_copyReportRunID` that answers from the report file alone (partial-tolerant decode, no stitch), so a bulk send normally never reads or stitches anything of the live run; the decoded report's `runId` is re-checked after the full read, because a report torn at peek time can finish writing before the read. To send a current-run report deliberately, name its id in `sendReports(with:only:)`; a named report is always sent.

### Key Files

- `KSCrashC.c` / `KSCrashC.h`: UUID generation and `kscrash_getRunID()`
- `KSCrashReportFields.h`: `KSCrashField_RunID` (`"run_id"`)
- `KSCrashReportC.c`: Writes `run_id` in `writeReportInfo()`
- `Sources/KSCrash/ReportSend.swift`: the current-run exclusion in the bulk send; `KSCrash+Send.swift`: `sendReports(with:)` / `sendReports(with:only:)`
- `ReportInfo.swift`: `runId` property on the Swift model
