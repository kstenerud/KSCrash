---
applyTo: "Sources/KSCrashRecording/Monitors/KSCrashMonitor_Watchdog*,Sources/KSCrashRecording/Monitors/KSCrashMonitor_Lifecycle.m,Sources/KSCrashRecording/KSCrashRunContext.m,Tests/KSCrashRecordingTests/KSCrashMonitor_Watchdog*,Tests/KSCrashRecordingTests/KSCrashMonitor_Lifecycle_Tests.m,Tests/KSCrashRecordingTests/KSCrashMonitor_Termination_Tests.m,Samples/Tests/WatchdogTests.swift"
---

# Watchdog decisions

Settled decisions for the watchdog monitor and how a hang feeds the run summary.
Do not flag code that follows them. When a decision changes or a new one is
made, it is recorded here.

- **A hang still in progress when the process ends is a hang, whatever ended the
  process.** No fatal event deletes its report, with one exception: when hang
  reporting is off, only a hang that ends the app is reported on its own, so a
  fatal event or a normal exit during the hang removes the hang's report. The
  fatal event's report still carries the hang in `crash.error.hang`, and the run
  summary still says a hang was in progress. A normal exit is caught by the
  monitor's own exit handler, since it is no fatal event and the main thread
  does not go idle again to end the hang.
- **The exit handler covers a hang in progress when it runs, not one that starts
  after it.** `atexit` handlers run in reverse order, so one the app registered
  before installing KSCrash runs after the watchdog's. A hang that handler causes
  with hang reporting off keeps its report, which is delivered as a non-fatal
  hang. This is left on purpose: it takes a slow handler registered first, and the
  result is a report the app turned off, not a wrong one. Starting no hang after
  the exit handler would lose the watchdog kill that a hang in that handler can
  still end in. Deciding at delivery (a reporting-off hang in a run that exited
  cleanly is not delivered) would need the store to drop a report from a stitch.
- **The delivery stitch decides the cause of death.** An unrecovered watchdog
  report is a watchdog kill only when the run's lifecycle shows neither a crash
  handler nor a clean exit. Otherwise it is a non-fatal `hang`: the hang was in
  progress, and something else ended the process. The stitch reads the run
  through RunContext (`ksruncontext_contextForRunID`), and a watchdog report
  with no readable sidecar gets the same decision in the final pass.
- **The run summary ranks a crash over a hang over a clean exit.** A crash ends
  the run whatever else was going on. A hang outranks a clean exit, SIGTERM
  included, because the app was stuck when it stopped.
- **A report records its own moment.** `hang_recovered` says whether the hang
  had ended by the time of that report. A report finalized during a hang says
  false and keeps saying it after the hang recovers; that is what was true when
  it was taken.
- **The "since last crash" counters reset after any run that ended with a hang
  in progress.** They follow the run summary's `isAbnormal`, the one rule a
  consumer deriving them from summaries can apply.
- **The hang is recorded before its report is written.** The run sidecar first,
  then the lifecycle's hang flag.
- **Started is sent once the hang is recorded, report included.** A listener
  runs arbitrary code, and announcing the hang before the main thread is
  captured lets the main thread recover meanwhile, leaving the report a stack
  from after the hang. A hang written without a report (it yields to a report
  already in flight, or the app's `willWriteReport` skips it) is announced once
  it is recorded.
- **A hang that cannot be recorded is not followed.** When its sidecar or its
  report cannot be written, whatever was recorded is removed, the flag comes
  down, and listeners get Failed in place of Started, with nothing after it.
  Half a record is not delivered as the whole one. A hang that yields to a
  report already in flight, or whose report the app skips, is not a failure: it
  is recorded, without a report.
- **A hang's record is marked ended the moment the main thread goes idle.** The
  main thread marks the sidecar recovered and lowers the lifecycle's hang flag
  as it goes idle (memory writes into the mapped sidecar and a spinlock, no file
  I/O), so a process that ends while the watchdog thread is still writing the
  report or running a listener is not taken for one that ended in a hang. A
  sidecar attached after that is marked ended as it is attached. The report, its
  finalize and the events stay on the watchdog thread.
- **Sidecar file work never runs under the monitor's lock.** The sidecar is
  built at a temporary path with every field written and renamed into place,
  then only attached under the lock.
- **A hang that has ended is marked ended in its sidecar before the sidecar is
  removed.** There is always an instant between a hang ending and its sidecar
  going, and whatever reads it then should see a hang that ended. A failed
  hang's sidecar is removed as it is, since that hang is not over.
- **A hang's report goes before its sidecar.** A process ending between the two
  leaves a sidecar no report points at, which the next send reclaims, rather
  than a report with no sidecar to say its hang recovered.
- **A hang follows the settings it started with.** The hang-reporting setting is
  read when the hang starts. Turning the watchdog off during a hang lets that
  hang finish as though it were still on (the monitor still answers enabled, so
  the crash pipeline still calls it), and the monitor stops once it has. Turning
  it back on before then keeps following the same hang. Only tests turn a
  monitor off mid-run; making that the rule, and shrinking this path to a plain
  stop, is [#1042](https://github.com/kstenerud/KSCrash/issues/1042).
- **Everything after detection happens on the watchdog thread.** The main thread
  only marks a hang's record ended and hands the hang over. Started, Updated,
  Ended and Failed all come from the watchdog thread, so listeners see them in
  order and need no lock, and the hang report's finalization never runs on the
  host's main thread.
- **A crash while a report is still being written is left to report staging
  ([#924](https://github.com/kstenerud/KSCrash/issues/924)).** With hang
  reporting off, the crash handler cannot remove a hang report whose path is not
  attached yet, and neither can the exit handler; that was left on purpose. A
  report the writer cut short (a full disk) is taken as written, which is also
  [#924](https://github.com/kstenerud/KSCrash/issues/924)'s to fix.
- **A saved hang report is only stitched while `.hangs` is on.** The store
  stitches with the monitors the current launch registered, so a launch with
  hangs off delivers an earlier run's hang report unstitched. The fix belongs to
  the store, in [#1041](https://github.com/kstenerud/KSCrash/issues/1041).
