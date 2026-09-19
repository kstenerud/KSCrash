# Testing

## One KSCrash install per process

`kscrash_install` (and everything built on it) runs once per process; a second
install fails with `alreadyInstalled`. Under `swift test`, every test bundle is
aggregated into ONE runner process, so all suites share a single install and
whichever suite installs first wins. Under `xcodebuild test`, bundles get their
own runner processes and each side gets full coverage.

The suites share the process politely; keep it that way:

- `TestInstall` (KSCrashTests) installs the real Swift front end on first use.
  When it loses the race it throws a loud `XCTSkip`, never a failure: a red
  that means "run order" and not "bug" trains people to ignore reds.
- The race is not left to run order. The suites that install in
  extension-reporting mode (the crash-extension suite, the MetricKit
  end-to-end test) check whether the run selected any KSCrashTests suite
  (the runner's `-XCTest` argument), and if so look up `KSCrashTestsInstallClaim`
  through the runtime and let `TestInstall` claim the process first, because
  they can attach to a live pipeline and keep running while `TestInstall`'s
  suites can only skip. That keeps the install, metadata and hang suites in
  the aggregate run, which is what the sanitizer lane executes, while a
  filtered run of the extension suite alone still installs in
  extension-reporting mode.
- The crash-extension suite installs in extension-reporting mode when it has
  the process to itself (its own bundle under xcodebuild). When it loses the
  race it attaches its bridge to the winning install's live pipeline and
  reads reports back from that install's report area instead of its own.
- Tests that only need a run id never install: they seed it through
  `kscrash_testcode_setRunID`.
- Never reset the whole monitor system from a tearDown
  (`kscm_testcode_resetState` wipes the registered monitors and pipeline
  callbacks for every later suite); use the narrow seams
  (`kscm_testcode_clearHandlingFatalException`, save/restore) instead.

A new suite that needs an install must either go through `TestInstall`, or
tolerate losing the race the same way (attach or skip loudly, with the "why"
in the message).
