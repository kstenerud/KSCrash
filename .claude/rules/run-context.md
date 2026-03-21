---
paths:
  - "Sources/KSCrashRecording/KSCrashRunContext.{h,m}"
  - "Sources/KSCrashRecording/KSTerminationReason.{h,c}"
  - "Sources/KSCrashRecording/KSTaskRole.{h,c}"
  - "Sources/KSCrashRecording/Monitors/KSCrashMonitor_Termination.{h,m}"
  - "Sources/KSCrashRecording/KSCrashC.c"
---

## RunContext

RunContext is the shared layer for cross-monitor state. Monitors never import each other's headers — all cross-cutting reads go through RunContext.

### What It Does

On each launch, `ksruncontext_init()` reads the previous run's Lifecycle, Resource, and System sidecars, compares them against the current system state, and determines a `KSTerminationReason` for why the previous process ended. The result is cached and available via `ksruncontext_previousRunContext()`.

### Startup Sequence

Monitor startup in `kscrash_install()` is four ordered steps:

1. **`kscm_enableMonitors()`** — installs signal/Mach handlers, creates sidecars for the current run.
2. **`kscm_notifyPostMonitorsEnabled()`** — monitors populate current-run sidecar data that RunContext needs (e.g., BootTime writes `kern.boottime` so reboot detection works, DiscSpace writes storage sizes).
3. **`ksruncontext_init(pathForRunID)`** — reads previous run's sidecars, compares against the now-complete current system state, and determines the termination reason.
4. **`kscm_notifyPostSystemEnable()`** — tells monitors RunContext is ready so they can act on previous-run data (e.g., Termination injects a report, Memory checks for OOM).

This order is load-bearing: monitors must be enabled before RunContext reads their sidecars, current-run data must be populated before RunContext compares against it, and RunContext must be populated before monitors try to read it. There is no combined "activate" call — each step is explicit.

### Termination Reasons

`KSTerminationReason` classifies why the previous run ended. The `determineReason()` function in `KSCrashRunContext.m` evaluates them in priority order — lifecycle guards first, then system changes, then resource limits, then fallbacks.

**Definitive** (checked first — a crash or hang recorded in the Lifecycle sidecar must not be overridden by missing data):

| Reason | Meaning | Produces report? |
|---|---|---|
| `Clean` | `cleanShutdown` flag was set — normal app termination | No |
| `Crash` | `fatalReported` flag was set — a crash handler already wrote a report | Yes |
| `Hang` | `hangInProgress` flag was set — app was hanging when killed | Yes |

**System changes** (explain an unclean exit without it being a crash):

| Reason | Meaning | Produces report? |
|---|---|---|
| `OSUpgrade` | OS version changed between runs | No |
| `AppUpgrade` | App bundle version changed between runs | No |
| `Reboot` | Device boot time changed (with `KSCRASH_REBOOT_JITTER_SECONDS` tolerance) | No |

**Resource heuristics** (based on the last observed resource snapshot before the app was killed — the OS does not report a cause for these terminations, so they reflect the best available evidence):

| Reason | Meaning | Produces report? |
|---|---|---|
| `MemoryLimit` | App memory level reached `KSCrashAppMemoryStateCritical` | Yes |
| `MemoryPressure` | System-wide memory pressure reached `KSCrashAppMemoryStateCritical` | Yes |
| `CPU` | CPU usage exceeded `KSCRASH_CPU_USAGE_CRITICAL` permil across all cores | Yes |
| `Thermal` | Device thermal state reached `NSProcessInfoThermalStateCritical` | Yes |
| `LowBattery` | Battery at or below `KSCRASH_BATTERY_LEVEL_CRITICAL`% and `KSCrashBatteryStateUnplugged` | Yes |

**Fallbacks**:

| Reason | Meaning | Produces report? |
|---|---|---|
| `FirstLaunch` | No previous run ID exists — first install or data was wiped | No |
| `None` | RunContext hasn't been initialized yet | No |
| `Unexplained` | Previous run existed but none of the above matched | Yes |

### `ksruncontext_contextForRunID`

Loads context for any run ID, not just the previous one. Takes the path resolver as an explicit parameter (no hidden global dependency). Used internally by `ksruncontext_init()` and available for external callers that need to inspect arbitrary runs.

### Key Files

- `KSCrashRunContext.h/.m`: `KSCrashRunContext` struct, `ksruncontext_init()`, `ksruncontext_contextForRunID()`, `ksruncontext_previousRunContext()`
- `KSTerminationReason.h/.c`: `KSTerminationReason` enum, `kstermination_reasonToString()`, `kstermination_producesReport()`
- `KSTaskRole.h/.c`: `kstaskrole_current()`, `kstaskrole_toString()` — queries the Mach task role from the kernel
- `KSCrashMonitor_Termination.h/.m`: The Termination monitor — reads RunContext in `notifyPostSystemEnable` and injects a retroactive report if needed
- `KSCrashC.c`: Wires the four-step startup sequence in `kscrash_install()`
