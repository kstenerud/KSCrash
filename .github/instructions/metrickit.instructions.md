---
applyTo: "Sources/KSCrashMonitors/MetricKit/**,Tests/KSCrashMonitorsTests/MetricKit*"
---

# MetricKit decisions

Settled decisions for the MetricKit monitor. Do not flag code that follows them.
When a decision changes or a new one is made, it is recorded here.

- **One MetricKit API per process.** On iOS 27+, where the OS and the build
  have them, only the `MetricManager` streams are used; everywhere else, only
  the legacy `MXMetricManagerSubscriber`. Never both.
- **Frames without an address get no new report field.** A 27+ frame with no
  `address` is kept apart from other frames when building a profile (by its
  binary and offset), but its offset is not serialized. Every real payload seen
  carries addresses, and the SDK documents no address-less case.
- **MetricKit's time range is the delivery's period, not the event's time.**
  `MXDiagnostic` has no timestamp of its own, only the payload's
  `timeStampBegin`/`timeStampEnd`, and on 27 the diagnostics delivered together
  share one `timeRange` too (a CPU exception and a watchdog crash for the same
  process came with the same range, which matched the legacy payload's). Neither
  end has to fall inside the run: a disk write range was an instant 1.3 s before
  its run's recorded start, a CPU exception's ended 37 s after its run ended.
  So `report.timestamp` is the range's end on every MetricKit report, and a
  report with no run ID also carries the whole range in
  `monitor_data.MetricKit.time_range` (`begin_ms`, `end_ms`, the unit of a run
  summary's `started_at_ms`), for a backend to match the run whose window it
  overlaps.
- **A legacy diagnostic's bundle ID comes from its JSON before iOS 26.**
  `MXMetaData.bundleIdentifier` exists only on 26+, but the diagnostic's
  `jsonRepresentation()` carries `diagnosticMetaData.bundleIdentifier` (seen in
  an iOS 18.3.1 payload). Only a diagnostic that names no bundle at all is
  taken to be the app's own, with the app's bundle ID and device hash.
- **A finalized MetricKit report has no `system.process_name`.** MetricKit
  gives none, and the skeleton report has none either: its `system` section is
  filled only by the System stitch at delivery, which a finalized report (hang,
  disk write, CPU) never gets, and `report.process_name` comes from the event
  context, which only the corpse monitor sets. It is not filled from this
  process: the field stays absent rather than take a value MetricKit did not
  give.
- **A disk write profile has no start time and no duration.** MetricKit gives
  neither when the writes it counted began nor how long they took, so
  `time_start_epoch` and `duration` are absent. The time MetricKit does give is
  the report's time range. Never fill a field MetricKit does not give.
- **A CPU exception profile has a duration but no start time.** Its `duration`
  is `totalSampledTime`, which the SDK documents as the "total time that the
  application was sampled for during the CPU exception". MetricKit does not
  say when that sampling started, so `time_start_epoch` is absent. The totals
  (`total_cpu_time_ns`, `total_sampled_time_ns`) are in the monitor data.
- **A value from the current run goes on a MetricKit report only if it cannot
  differ between runs of the app.** The report describes an earlier run.
- **The run ID comes from the threadcrumb, never from StateReporting** (#962).
  Apple does not recommend high-cardinality stable metadata, and a run ID is
  unique to every run. StateReporting also rate-limits: reporting "more
  frequently than user interaction timescales can trigger rate limiting,
  causing state updates to go unlogged" (`SRStateReporter.h`), and a lost
  update is a lost run ID. On iOS 27.0.1 MetricKit attached no state to any
  diagnostic in our tests either.
  Reports with no run ID (disk writes, CPU exceptions) are matched to their run
  by the backend, using the device hash, process ID and time range (see
  `docs/wiki/Whats-New-in-KSCrash-3.0.md`, "Matching a report to its run").
- **A fixture test fails when the fixture decodes to the wrong kind.** Skipping
  is only for runtimes without the API.
