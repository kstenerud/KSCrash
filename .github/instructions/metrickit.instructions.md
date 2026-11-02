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
- **Legacy diagnostics use the payload's `timeStampEnd`.** `MXDiagnostic` has no
  timestamp of its own; the payload's time range is the only time the legacy
  API gives, so every legacy kind (crash, hang, disk write) uses its end.
- **A diagnostic that names no bundle is the app's own.** `MXMetaData.bundleIdentifier`
  exists only on iOS 26+, so a legacy payload before 26 is taken to be the app's,
  and gets the app's bundle ID and device hash.
- **A disk write profile has no start time and no duration.** MetricKit gives
  neither when the writes it counted began nor how long they took, so
  `time_start_epoch` and `duration` are absent. The diagnostic's own time is
  `report.timestamp`. Never fill a field MetricKit does not give.
- **A value from the current run goes on a MetricKit report only if it cannot
  differ between runs of the app.** The report describes an earlier run.
- **The run ID comes from the threadcrumb, never from StateReporting** (#962).
  Apple does not recommend high-cardinality stable metadata, and a run ID is
  unique to every run. StateReporting also rate-limits: reporting "more
  frequently than user interaction timescales can trigger rate limiting,
  causing state updates to go unlogged" (`SRStateReporter.h`), and a lost
  update is a lost run ID. On iOS 27.0.1 MetricKit attached no state to any
  diagnostic in our tests either.
  Reports with no run ID (disk writes) are matched to their run by the backend,
  using the device hash, process ID and timestamp (see
  `docs/wiki/Whats-New-in-KSCrash-3.0.md`, "Matching a report to its run").
- **A fixture test fails when the fixture decodes to the wrong kind.** Skipping
  is only for runtimes without the API.
