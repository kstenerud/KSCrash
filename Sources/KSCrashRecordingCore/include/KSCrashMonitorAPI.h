//
//  KSCrashMonitorAPI.h
//
//  Created by Karl Stenerud on 2025-08-09.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#ifndef HDR_KSCrashMonitorAPI_h
#define HDR_KSCrashMonitorAPI_h

#include <CoreFoundation/CFDictionary.h>
#include <stdbool.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashNamespace.h"
#include "KSCrashReportWriter.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The id of a monitor that never set one. Not an identity: several monitors can be
 *  unconfigured at once, so the registry does not treat it as a duplicate.
 */
#define KSCRASH_MONITOR_ID_UNSET "unset"

/** Scope of a sidecar file being stitched into a report. */
typedef CF_CLOSED_ENUM(int, KSCrashSidecarScope) {
    /** Per-report sidecar: one file per report, stored in Sidecars/<monitorId>/<reportID>.ksscr */
    KSCrashSidecarScopeReport = 0,
    /** Per-run sidecar: one file per process run, stored in RunSidecars/<runID>/<monitorId>.ksscr */
    KSCrashSidecarScopeRun = 1,
    /** The final pass, after all sidecar stitching: every registered monitor implementing
     *  createStitchedReport is called once with a NULL sidecarPath, in (priority, id) order.
     *  The last chance to modify a report before it is handed out; a monitor draws on the
     *  report itself (e.g. its own embedded section), not a sidecar file. Monitors with
     *  nothing to add return the input retained, the same convention as an unhandled scope.
     */
    KSCrashSidecarScopeFinal = 2,
} CF_SWIFT_NAME(SidecarScope);

/**
 * Monitor API.
 * WARNING: All functions MUST be idempotent!
 *
 * Every callback receives a `context` pointer as its last parameter.
 * This is the same pointer stored in the `context` field of this struct,
 * allowing Swift (or other) monitors to recover instance state without globals.
 * Built-in C monitors set context to NULL and ignore the parameter.
 */
typedef struct KSCrashMonitorAPI {
    /** Opaque pointer passed as the last argument to every callback.
     *  Monitors can use this to store instance-specific data (e.g., an
     *  Unmanaged<Self> pointer in Swift). NULL for built-in C monitors. */
    void *context;

    /** Ordering hint for sidecar stitching. When several monitors' sidecars stitch into the same
     *  report, their createStitchedReport callbacks run in ascending priority order, so a
     *  higher-priority monitor is applied last and wins on any overlapping keys. Defaults to 0;
     *  ties break deterministically on monitor id. */
    int priority;

    /**
     * Initialize the monitor.
     * The monitor MUST NOT install or activate anything! This is merely to configure things for when it activates.
     * @param callbacks The callbacks that the monitor may call when reporting an exception.
     * @param context The monitor's opaque context pointer.
     */
    void (*init)(KSCrash_ExceptionHandlerCallbacks *callbacks, void *context);

    /** Returns the unique identifier for this monitor (e.g., "mach", "signal", "profile"). */
    const char *(*monitorId)(void *context);

    /** Returns the flags describing this monitor's capabilities and requirements. */
    KSCrashMonitorFlag (*monitorFlags)(void *context);

    /** Enables or disables this monitor. */
    void (*setEnabled)(bool isEnabled, void *context);

    /** Returns whether this monitor is currently enabled. */
    bool (*isEnabled)(void *context);

    /** Called to allow the monitor to add contextual information to an event context. */
    void (*addContextualInfoToEvent)(KSCrash_MonitorContext *eventContext, void *context);

    /** Called after all monitors have been enabled but before RunContext
     *  reads sidecars.  Use this to populate current-run sidecar data that
     *  RunContext needs for its analysis (e.g. boot time, disc space). */
    void (*notifyPostMonitorsEnabled)(void *context);

    /** Called after RunContext has been initialized with previous-run data.
     *  Use this to act on the termination reason (e.g. inject a report). */
    void (*notifyPostSystemEnable)(void *context);

    /**
     * Called during report writing to allow the monitor to write custom data to its section.
     *
     * This callback is invoked when the report writer encounters a monitor type it doesn't
     * have built-in handling for. The monitor can use the writer to add custom JSON data
     * to the report's error section under a key matching the monitor's ID.
     *
     * @param eventContext The monitor context containing event information.
     * @param writer The report writer to use for adding JSON elements.
     * @param context The monitor's opaque context pointer.
     *
     * @note This callback is optional. If NULL, no custom section will be written for this monitor.
     */
    void (*writeInReportSection)(const KSCrash_MonitorContext *eventContext, const KSCrashReportWriter *writer,
                                 void *context);

    /**
     * Called at report delivery time to stitch sidecar data into a report.
     *
     * When the report store finds a matching sidecar file for this monitor,
     * it calls this function to merge sidecar data into the decoded report
     * dictionary before delivery.
     *
     * Placement contract: a custom monitor puts its data in a
     * framework-owned namespace, under `monitor_data.<monitorID>` at the
     * report root (delivery-time data) or under `crash.error.<monitorID>`
     * (the crashing monitor's own section). Those locations survive typed
     * delivery. Mutating standard report fields is reserved for built-in
     * monitors whose fields exist in the typed report model; additions to
     * arbitrary unmodeled fields elsewhere are not preserved in delivered
     * payloads.
     *
     * Follows the CF Create Rule: the caller owns the returned dictionary
     * and must release it (via CFRelease or __bridge_transfer to ARC).
     * The input reportDict is owned by the caller; the callback must not
     * release it.
     *
     * @param reportDict The decoded report dictionary. Owned by the caller,
     *        the callback must not release it.
     * @param sidecarPath The full path to the sidecar file for this report.
     * @param scope Whether this is a per-report or per-run sidecar.
     * @param context The monitor's opaque context pointer.
     *
     * @return A +1 CFDictionaryRef with the (possibly modified) report,
     *         or NULL on failure. NULL signals a stitch error: during
     *         finalization this aborts the write-back so the report can
     *         be retried on next app launch; during normal reads the
     *         error is silent and the original dict is kept.
     *
     * @note Optional. If NULL, no stitching is performed.
     *       Runs at normal app startup time, not during crash handling.
     */
    CFDictionaryRef (*createStitchedReport)(CFDictionaryRef reportDict, const char *sidecarPath,
                                            KSCrashSidecarScope scope, void *context);
} KSCrashMonitorAPI;

/**
 * Initialize an API by replacing all callbacks with default no-op implementations.
 * Note: This will only initialize APIs that haven't been initialized yet (where the "init" method is still NULL), which
 * prevents it from overwriting an already setup API.
 * @param api The API to initialize.
 * @return true if api has been initialized (i.e. api->init was NULL before the call), false otherwise.
 */
bool kscma_initAPI(KSCrashMonitorAPI *api);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitorAPI_h
