# TODO

- [ ] Unify `KSCrashReportStoreCConfiguration`: There are two parallel configs for the report store — `g_reportStoreConfig` in `KSCrashC.c` (set during `kscrash_install`) and `KSCrashReportStore._cConfig` (created via `KSCrashReportStoreConfiguration.toCConfiguration`). They can get out of sync (e.g. `sidecarsPath` was missing from the ObjC config). These should be consolidated into a single struct owned by the install, with the report store referencing it rather than maintaining its own copy.

- [ ] Serialize backtrace/report writing: The backtrace and report writing path can only run one at a time. If two crashes or hangs trigger concurrently, the results are undefined. Add an atomic guard (e.g. `atomic_flag` or `atomic_bool`) to ensure only one report write is in progress at a time.
