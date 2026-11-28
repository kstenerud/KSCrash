---
applyTo: "Sources/KSCrashRecording/KSCrashReportStoreC.m,Sources/KSCrashRecording/include/KSCrashReportStoreC.h,Sources/KSCrash/Store.swift,Sources/KSCrash/Store+TakeIn.swift,Sources/KSCrash/SendDriver.swift,Tests/KSCrashRecordingTests/KSCrashReportStoreC_*,Tests/KSCrashTests/StoreTests.swift"
---

# Report store decisions

Settled decisions for the report store and taking reports in. Do not flag code
that follows them. When a decision changes or a new one is made, it is recorded
here.

- **Only a take-in holds the take-in claim.** One take-in runs per store
  directory at a time, and a send that finds the claim taken skips its sources
  for that send rather than waiting. Nothing else takes that claim, the end of
  send cleanup included: a holder that takes nothing in turns that skip into a
  send whose sources are never read, which happens at launch when a run-summary
  send with nothing to send finishes while a report send is starting.
- **Each leftover is swept where its writer's exclusion already holds.** A
  report write's `.tmp` is swept at the end of a send, under `g_mutex`, because
  every writer of one holds `g_mutex` from opening it until it is renamed or
  removed. A take-in's `.incoming` copy is swept by a take-in at its start,
  under its claim, because the copy is written outside `g_mutex`. The one case
  this leaves is a crash in the middle of a cross-volume copy in an app whose
  later sends have no sources: one stray file that nothing lists. That needs a
  copy across volumes, which only happens when a rename fails with `EXDEV`, and
  is not worth a second record of take-in activity or a claim held by cleanup.
- **Neither sweep runs at `kscrs_initialize`.** It is on the app's startup
  path; a leftover is not a report name, so nothing reads it while it waits.
- **A take-in's copy stays outside `g_mutex`.** The app's own threads take
  `g_mutex` to add user reports and finalize hangs, and a whole report's copy
  and flush must not hold them up. (The crash handler never takes `g_mutex`.)
- **A sweep removes only a report name plus its suffix.** Anything else in the
  reports directory is not the store's to remove.
