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

Each process gets a unique run ID (UUID string), generated once during `kscrash_install()` in `KSCrashC.c`. It is written into the `"report"` section of every crash report under the `"run_id"` key. In a normal app the buffer is read-only after install, so `kscrash_getRunID()` is async-signal-safe and can be called from crash handlers.

**Purpose**: Reports from the current run may still be updated (e.g., watchdog hang reports that get resolved). The bulk Swift send, `KSCrash.sendReports(with:)`, skips reports whose `run_id` matches the current process (the check lives in `ReportSend.swift`, comparing the decoded report's `runId` with the store's `liveRunID`). To send a current-run report deliberately, name its id in `sendReports(with:only:)`; a named report is always sent.

### Out-of-process (corpse) run ID

The run id lives in a named section, `__DATA,__ks_runid`, so an out-of-process crash reporter (an iOS 27 `CrashReporterExtension`) can locate it inside a crashed process's corpse and read the **crashed run's** id. The section payload (`KSRunIDSectionPayload`) carries the KSCrash namespace identifier followed by the run id: Mach-O section names are capped at 16 bytes so the name itself can't be namespaced, and with two namespaced KSCrash copies in one app both carry the section. `kscrash_loadRunIDFromCorpse(corpse, imageAddrs, count)` scans the corpse's images for that section (via `ksbic_findSectionInTaskImage`, a cross-task Mach-O section finder in `KSBinaryImageCache`), accepts only a payload whose namespace matches its own, validates a UUID, and copies it into the extension's own run-id buffer. This makes the report the extension writes for the corpse carry the app's run ID, so it stitches against the crashed run's per-run sidecars on next launch.

In the extension the run id is **per-corpse state**: each capture first calls `kscrash_clearRunID()` and then loads (load-or-clear), so a corpse whose id cannot be read (an app without KSCrash, or one that crashed before install wrote the id) is reported with an empty run id, never a previous corpse's. These are the only paths that write the run id after install, and they only run in the extension process (never in a crash handler, and never in a normal install), so they do not affect the async-signal-safety of the in-app path.

### Key Files

- `KSCrashC.c` / `KSCrashC.h`: UUID generation, `kscrash_getRunID()`, `g_runIDSection` (the `KSRunIDSectionPayload` in the `__DATA,__ks_runid` section), `kscrash_loadRunIDFromCorpse()`, and `kscrash_clearRunID()`
- `KSBinaryImageCache.c` / `KSBinaryImageCache.h`: `ksbic_findSectionInTaskImage()`, the cross-task section finder the corpse loader uses
- `KSCrashReportFields.h`: `KSCrashField_RunID` (`"run_id"`)
- `KSCrashReportC.c`: Writes `run_id` in `writeReportInfo()`
- `Sources/KSCrash/ReportSend.swift`: the current-run exclusion in the bulk send; `KSCrash+Send.swift`: `sendReports(with:)` / `sendReports(with:only:)`
- `ReportInfo.swift`: `runId` property on the Swift model
