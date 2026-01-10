# KSCrash 3.0 Proposal

## Summary
KSCrash currently cannot produce reports for terminations that lack crash-time callbacks—OOM, SIGKILL, watchdog kills. When iOS terminates an app this way, there's no opportunity to capture context, so these events go unreported.

This proposal introduces a run-scoped data model where each app launch writes all data for that run into a dedicated folder. Crash-time data stays minimal and async-safe, while metadata is continuously updated via mmap-backed structs (example: [`KSCrash_Memory`](Sources/KSCrashRecording/Monitors/KSCrashMonitor_Memory.h)). Reports are stitched from crash data + latest metadata at send time. For terminations without crash-time callbacks, reports are assembled on next launch using the prior run's metadata.

## Goals

### Outcomes
- Enable report generation for terminations without crash-time callbacks (OOM, SIGKILL, watchdog).
- Reduce data loss by preserving metadata across unexpected terminations.
- Make report assembly deterministic by stitching data by run id.

### Design Constraints
- Keep crash-time writes minimal and async-signal-safe.
- Ensure stitched reports match today's report schema with no breaking changes.
- Preserve compatibility for apps that read directly from the reports directory.

### Approach
- Separate crash-time data from continuously-updated metadata.
- Use mmap-backed binary files for all persistent state.

## Non-Goals
- Avoiding the next-launch dependency for OS-terminated processes. This is inherent for OOM/SIGKILL on iOS/tvOS.
- Building a new report transport layer or changing the existing JSON report schema beyond additive fields.

## Proposed Architecture

### Run ID and Folder Layout
Create a unique run id at startup (UUID) and use it for all data produced in that run.

Example layout:
- `Data/Runs/<run-id>/`
- `Data/Runs/<run-id>/meta/`
- `Data/Runs/<run-id>/meta/memory.bin` (KSCrashMonitor_Memory)
- `Data/Runs/<run-id>/meta/app_state.bin` (KSCrashMonitor_AppState)
- `Data/Runs/<run-id>/meta/watchdog.bin` (KSCrashMonitor_Watchdog)
- `Data/Runs/<run-id>/meta/system.bin` (KSCrashMonitor_System)
- `Data/Runs/<run-id>/term/`
- `Data/Runs/<run-id>/term/signal.bin` (KSCrashMonitor_Signal)
- `Data/Runs/<run-id>/term/mach.bin` (KSCrashMonitor_MachException)
- `Data/Runs/<run-id>/term/cpp_exception.bin` (KSCrashMonitor_CPPException)
- `Data/Runs/<run-id>/term/ns_exception.bin` (KSCrashMonitor_NSException)
- `Data/Runs/<run-id>/manifest.json` (optional registry of metadata files)

Store:
- A rolling list of the last N run ids (exposed via an API) for startup stitching.
- `run_id` inside every report JSON.

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         APP RUNNING                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Metadata writers (continuous)      Crash handlers (on crash)  │
│   ┌─────────────────────────┐        ┌─────────────────────┐    │
│   │ memory.bin              │        │ signal.bin          │    │
│   │ app_state.bin           │        │ mach.bin            │    │
│   │ system.bin              │        │ cpp_exception.bin   │    │
│   └──────────┬──────────────┘        └──────────┬──────────┘    │
│              │                                  │               │
│              ▼                                  ▼               │
│         Data/Runs/<run-id>/meta/      Data/Runs/<run-id>/term/  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ App terminates
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        NEXT LAUNCH                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                   Startup Processing                    │   │
│   │                                                         │   │
│   │  1. Read prior run's term/*.bin (if exists)             │   │
│   │  2. Read prior run's meta/*.bin                         │   │
│   │  3. Stitch into JSON report                             │   │
│   │  4. Move to reports directory                           │   │
│   │  5. Delete processed run folder                         │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│                    Reports/<report-id>.json                     │
│                    (existing format, existing location)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Crash Data vs Metadata
- **Crash data**: written at crash time under `term/` as an mmap-backed struct named after the monitor that wrote it. Must be async-safe.
- **Metadata**: written throughout the run. Each monitor defines its own struct and uses a new API to read/write its mmap-backed data stored under `Data/Runs/<run-id>/meta/`.

### Why Binary at Crash Time?
Crash-time storage uses binary structs rather than JSON for three reasons:
1. **Async-signal-safety**: Writing a fixed-size struct via mmap requires no memory allocation, no locks, and no string formatting—all of which are unsafe in signal handlers.
2. **Speed**: A single `memcpy` to an mmap'd region is faster than JSON serialization, minimizing time spent in the crash handler.
3. **Atomicity**: Small, fixed-size writes are less likely to produce corrupted partial data if the process is killed mid-write.

JSON conversion happens at stitch time, outside the crash context, where these constraints don't apply.

### Metadata API
A new internal API allows each monitor to persist its own structured data. The API provides:
- Versioned, mmap-backed storage for fixed-size structs
- Async-signal-safe writes (no allocation, no locks)
- Thread-safe concurrent access

This follows the pattern already established by `KSCrashMonitor_Memory`. The implementation details (header format, synchronization protocol) will be specified separately.

### Report Stitching
Stitch in the background when the app loads reports, then load:
- `term/<monitor>.bin` for that `run_id` if it exists.
- The latest metadata snapshot(s) from `meta/*.bin`.

Merge metadata into the report with per-component timestamps. If metadata is missing, send crash data alone.

When reports are loaded, give each monitor a chance to load its metadata and add what it needs to the report. This mirrors the crash-time contextual collection flow, but runs on the next launch where signal-safety constraints do not apply.

Reports can still be written inline while the app is running (hang monitor, profiling, user reports). This uses the same APIs as today, but stitching happens live using the current in-memory metadata snapshots.

## Startup Processing
On launch, process the `Runs/` folder before the app accesses reports:

1. Enumerate run folders from prior launches (using the rolling run id list).
2. For each prior run:
   - If `term/*.bin` exists → a catchable crash occurred. Stitch crash data + metadata into a JSON report.
   - If no `term/*.bin` exists → the app terminated without a crash callback. Apply termination heuristics (see below) to determine cause.
   - Move the resulting JSON report into the current reports directory.
   - Delete the processed run folder.

### Termination Heuristics (TBD)
When no crash data exists, infer termination cause from metadata:
- **OOM**: High memory footprint, memory pressure level critical, no clean exit flag.
- **Watchdog**: App was in background, exceeded allowed background time.
- **User force-quit**: Clean app state, no pressure indicators.
- **Unknown**: Insufficient data to determine cause; optionally generate a "terminated unexpectedly" report or skip.

These heuristics require further analysis and will be detailed in a follow-up document.

## OOM Handling in the New Model
- Do not write a dedicated OOM report during runtime.
- Persist memory metadata continuously (footprint, remaining, level, pressure, transition state).
- On next launch, read the prior run's metadata and treat as OOM if heuristics match and no other fatal signal was recorded.

## Migration / Compatibility
- Keep existing report JSON structure; only add metadata timestamps if needed. The final stitched report remains JSON even though crash-time storage is binary.
- Use versioned metadata headers to allow forward-compatible reads.
- Leave existing report store behavior intact; stitching happens during report load.
- Retention stays app-configurable via the existing report retention constants.
- Transition plan: perform stitching very early on launch and move the resulting reports into the current reports directory so existing report flows (including apps reading the directory directly) continue to work.

## Open Questions

- What termination types can be inferred, and what are the heuristics for each?
- What's the cleanup policy for run folders (count, age, size limits)?
- Should stitching run synchronously at launch or be deferred to background processing? (Synchronous may be necessary when detecting repeated early crashes; background minimizes launch latency.)
- How should partial metadata (some files missing) be handled during stitching?

## Conclusion
This approach makes KSCrash more robust by decoupling crash-time writes from evolving metadata, reducing the amount of work performed in fragile crash contexts, and preserving state across unexpected terminations. The result is fewer silent failures and higher-quality reports for edge-case terminations that currently go unreported—while keeping the public report format stable.

Future iterations could leverage the metadata infrastructure for broader observability (performance telemetry, efficiency metrics), but the immediate goal is better crash coverage.
