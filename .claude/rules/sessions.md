## Sessions and Run Summaries

Each process run produces two related per-run artifacts, both stored in the `Runs`
directory (a sibling of `Reports`, `runSummariesPath` in the C config):

- **`<run_id>.sessions`** — an append-only log of the run's sessions, written live
  by the Lifecycle monitor.
- **`<wallClockAtStartNs>.run`** — the run summary, a per-run telemetry record
  persisted on the *next* launch.

`run_id` is the per-run UUID (see `run-id.md`). `.sessions` filenames use it
directly; `.run` filenames use the start timestamp and carry `run_id` as a
top-level JSON key.

### Sessions (`.sessions`)

A session is one contiguous segment of a run at a single (perceptible/imperceptible,
userID) setting. A new record is cut whenever the user ID or perceptibility changes.

`KSSessionStore.{c,h}` is the append-only reader/writer. The writer
(`kssw_open`/`kssw_update`/`kssw_updateUser`/`kssw_updatePerceptible`/`kssw_close`)
opens the file lazily on the first cut, so a run that records nothing writes no file.
Each `KSSessionRecord` holds a lowercase UUID `guid` (from `ksid_generate`), the
`user`, `startedAtMs`/`endedAtMs`, and `perceptible`/`endInferred` flags.

The Swift `SessionRecorder` (`Sources/KSCrash/SessionRecorder.swift`) owns the live
writer: install opens it at the path from `kscrs_getSummarySidecarFilePath`, it
records the launch session at the tracker's current perceptibility, subscribes to
`KSCrashAppStateTracker` for perceptibility cuts, and `KSCrash.setUserID` routes
user cuts through it. This is the only session-recording path; the Lifecycle
monitor keeps app-state observation for its mmap'd `KSCrash_LifecycleData` (and
the retired per-run session/user *counts* survive as `<name>_UNUSED` slots to
keep the mmap layout stable), but no longer touches the session writer.

### session_id on reports

A report carries the id of the latest session recorded at the time it was
finalized, under `report.session_id`. For reports finalized during their own run
that is the session open at finalization; for unfinalized (fatal) reports the
stitch runs when the store reads the report for delivery, and the dead run's
last session is the latest recorded. It is added at **stitch time** (when the store reads the report
for delivery), never written at crash time: `KSCrashMonitor_LifecycleStitch.m` reads
the last guid from the crashed run's `.sessions` via `kslifecycle_copyLastSessionIDForRunID`.
It is omitted when the run recorded no session. Because it is stitch-time, the raw
on-disk report has no `session_id`; only a delivered (store-read) report does.

`KSCrash.sessionID` reads the recorder's open session id (Swift state; there is no
C accessor for the live id). `ReportInfo.sessionId` is the Swift model field.

### Run summaries (`.run`) and the send merge

The run summary is built from the previous run's context by `buildSummary` in
`KSCrashRunContext.m` (directly as the wire dictionary, keyed by
`KSCrashRunSummaryField_*`) and persisted during install
(`ksruncontext_persistPreviousRunSummary`); the model consumers see is
`RunSummary` in `KSCrashReportModel`. The persisted `.run` has an empty
`sessions.records`; the records are the single source of truth for a run's sessions and
are merged in only at send time.

At send, the Swift store (`Store.summary(of:)` in `Store+Runs.swift`, `KSCrash` module) reads
`<run_id>.sessions` through the C reader and attaches the records. There are no aggregate
session/user counts on the summary; a consumer derives whatever it needs from
`records` (each record carries its perceptibility, user, and timestamps).

### Reclaim

`kscrs_reclaimOrphanedRunData` (in `KSCrashReportStoreC.m`) runs under `g_mutex` at the
end of both send flows. It computes the referenced run IDs once and removes run data
nothing points at any more: run sidecars **and** `.sessions` are both kept while a
report or a `.run` summary references the run (a pending summary needs its `.sessions`
for the record merge and its UserInfo run sidecar for the metadata stitch), and the
live run is always kept. A queued summary that cannot be READ aborts the pass,
mirroring the unreadable-report rule; one that reads but does not DECODE, or
decodes without a usable run_id, is deterministic garbage (the writer always
emits run_id; a crash mid-persist fails the strict decode) and is deleted on
the spot. `kscrs_deleteAllReports` deletes only
reports and report sidecars; run data is left for the next send-flow reclaim, so
pending summaries keep their artifacts. See `monitor-sidecars.md` for the run-sidecar side.

### Key Files

- `KSSessionStore.{c,h}`: append-only `.sessions` reader/writer
- `Sources/KSCrash/SessionRecorder.swift`: the live session writer and cuts
- `KSCrashMonitor_Lifecycle.{h,m}`: app-state observation, `kslifecycle_copyLastSessionIDForRunID`
- `KSCrashMonitor_LifecycleStitch.m`: adds `report.session_id` at delivery
- `KSCrashRunContext.m`: `buildSummary`, `ksruncontext_persistPreviousRunSummary`
- `Sources/KSCrash/Store.swift` / `Store+Runs.swift`: the store, its run listing (`snapshotRuns()`), send-time merge and metadata stitch
- `Sources/KSCrash/SendDriver.swift` / `RunSummarySend.swift`: the shared send loop and the run-summary send built on it
- `KSCrashReportStoreC.m`: `kscrs_reclaimOrphanedRunData`
- `KSCrashReportFields.h`: `KSCrashRunSummaryField_*` wire keys, `KSCrashField_SessionID`
