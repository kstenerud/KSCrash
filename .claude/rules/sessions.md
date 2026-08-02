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
Each `KSSessionRecord` holds an uppercase UUID `guid` (from `ksid_generate`), the
`user`, `startedAtMs`/`endedAtMs`, and `perceptible`/`endInferred` flags.

The Lifecycle monitor owns the live writer: it opens via `getSummarySidecarPath`,
cuts on user/perceptibility transitions, and closes on clean shutdown. This is the
only session-recording path; the retired per-run session/user *counts* it used to
also maintain are gone (their `KSCrash_LifecycleData` slots survive as
`<name>_UNUSED` to keep the mmap layout stable).

### session_id on reports

A crash report carries the `session_id` of the run's last session under
`report.session_id`. It is added at **stitch time** (when the store reads the report
for delivery), never written at crash time: `KSCrashMonitor_LifecycleStitch.m` reads
the last guid from the crashed run's `.sessions` via `kslifecycle_copyLastSessionIDForRunID`.
It is omitted when the run recorded no session. Because it is stitch-time, the raw
on-disk report has no `session_id`; only a delivered (store-read) report does.

`kslifecycle_currentSessionID()` returns the current run's live session id (thread-local
buffer, **not** async-signal-safe). `KSCrash.sessionID` exposes it; `ReportInfo.sessionId`
is the Swift model field.

### Run summaries (`.run`) and the send merge

The run summary (`KSCrashRunSummary`, `NS_SWIFT_NAME(RunSummary)`) is built from the
previous run's context by `buildSummary` in `KSCrashRunContext.m` and persisted during
install (`ksruncontext_persistPreviousRunSummary`). The persisted `.run` has an empty
`sessions.records`; the records are the single source of truth for a run's sessions and
are merged in only at send time.

At send, `runSummaryByMergingSessions` reads `<run_id>.sessions` and attaches the
records via `-[KSCrashRunSummary summaryByMergingSessions:]`. There are no aggregate
session/user counts on the summary; a consumer derives whatever it needs from
`records` (each record carries its perceptibility, user, and timestamps).

### Reclaim

`kscrs_reclaimOrphanedRunData` (in `KSCrashReportStoreC.m`) runs under `g_mutex` at the
end of both send flows. It computes the referenced run IDs once and removes run data
nothing points at any more: run sidecars kept only by a report, and `.sessions` kept by
a report **or** a `.run` summary (so a summary keeps its `.sessions` alive for the
send-time merge). See `monitor-sidecars.md` for the run-sidecar side.

### Key Files

- `KSSessionStore.{c,h}`: append-only `.sessions` reader/writer
- `KSCrashMonitor_Lifecycle.{h,m}`: live session recording; `kslifecycle_currentSessionID`, `kslifecycle_copyLastSessionIDForRunID`
- `KSCrashMonitor_LifecycleStitch.m`: adds `report.session_id` at delivery
- `KSCrashRunSummary.{h,m}` / `KSCrashRunSummary+Merge.h`: the summary model, JSON codec, and `summaryByMergingSessions:`
- `KSCrashRunContext.m`: `buildSummary`, `ksruncontext_persistPreviousRunSummary`
- `KSCrashReportStore.m`: `runSummaryByMergingSessions`, send flows
- `KSCrashReportStoreC.m`: `kscrs_reclaimOrphanedRunData`
- `KSCrashReportFields.h`: `KSCrashRunSummaryField_*` wire keys, `KSCrashField_SessionID`
