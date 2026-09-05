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
- The crash-extension suite installs in extension-reporting mode. When it loses
  the race it attaches its bridge to the winning install's live pipeline and
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
