# TODO

- [ ] Unify `KSCrashReportStoreCConfiguration`: There are two parallel configs for the report store — `g_reportStoreConfig` in `KSCrashC.c` (set during `kscrash_install`) and `KSCrashReportStore._cConfig` (created via `KSCrashReportStoreConfiguration.toCConfiguration`). They can get out of sync (e.g. `reportSidecarsPath` was missing from the ObjC config). These should be consolidated into a single struct owned by the install, with the report store referencing it rather than maintaining its own copy.

- [ ] Serialize backtrace/report writing: The backtrace and report writing path can only run one at a time. If two crashes or hangs trigger concurrently, the results are undefined. The crash pipeline should always be able to proceed (it must not be blocked), but it should set an atomic flag indicating a write is in progress so that other writers (e.g. the watchdog hang reporter) can check the flag and skip their write.

- [ ] Expose watchdog `reportsHangs` via configuration: Add a `reportsHangs` field to `KSCrashCConfiguration` / `KSCrashConfiguration` and wire it through `handleConfiguration` → a setter on the watchdog monitor. Currently hardcoded to `false` in `watchdog_create`.

- [ ] Integration test for fatal crash during hang: Verify that when a fatal exception (signal, Mach exception, etc.) occurs while a hang is in progress, only the crash report is delivered and the in-progress hang report is cleaned up. This exercises the `addContextualInfoToEvent` cleanup path in the watchdog monitor.
