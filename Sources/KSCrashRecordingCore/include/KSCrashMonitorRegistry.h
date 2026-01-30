//
//  KSCrashMonitorRegistry.h
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

#ifndef HDR_KSCrashMonitorRegistry_h
#define HDR_KSCrashMonitorRegistry_h

#include <stdbool.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Monitor list lockless algorithm:
 *
 * We choose an array of 100 entries because there will never be that many monitors in existence. No further allocations
 * are made.
 * - To iterate: Traverse the entire array, ignoring any null pointers.
 * - To add an entry:
 *   - Search the array for a hole (null pointer)
 *   - Try to atomically swap in the monitor API pointer.
 *   - If the swap fails, continue searching for the next hole and repeat.
 *   - Once a swap is successful, iterate again, removing duplicates in case someone else also added the same API.
 * - To remove an entry: Search for the pointer in the array and swap it for null.
 */
#define KSCRASH_MONITOR_API_COUNT 100
typedef struct {
    _Atomic(const KSCrashMonitorAPI *) apis[KSCRASH_MONITOR_API_COUNT];
} KSCrashMonitorAPIList;

/**
 * Activates all added crash monitors.
 *
 * Enables all monitors that have been added to the system. However, not all
 * monitors may be activated due to certain conditions. Monitors that are
 * considered unsafe in a debugging environment or require specific safety
 * measures for asynchronous operations may not be activated. The function
 * checks the current environment and adjusts the activation status of each
 * monitor accordingly.
 *
 * @return bool True if at least one monitor was successfully activated, false if no monitors were activated.
 */
bool kscmr_activateMonitors(KSCrashMonitorAPIList *monitorList);

/**
 * Disables all active crash monitors.
 *
 * Turns off all currently active monitors.
 */
void kscmr_disableAllMonitors(KSCrashMonitorAPIList *monitorList);

/**
 * Disables only crash monitors that have the KSCrashMonitorFlagAsyncSafe flag.
 *
 * This is safe to call from a crash handler (signal handler context) because
 * it only disables monitors whose setEnabled() implementation is async-signal-safe.
 * Non-async-safe monitors (e.g., Memory, Deadlock, Watchdog) are skipped since
 * their cleanup may involve ObjC messaging or other non-signal-safe operations,
 * and they don't need cleanup anyway since the process is terminating.
 */
void kscmr_disableAsyncSafeMonitors(KSCrashMonitorAPIList *monitorList);

/**
 * Adds a crash monitor to the system.
 *
 * @param api Pointer to the monitor's API.
 * @return `true` if the monitor was successfully added, `false` if it was not.
 *
 * This function attempts to add a monitor to the system. Monitors with `NULL`
 * identifiers or identical identifiers to already added monitors are not
 * added to avoid issues and duplication. Even if a monitor is successfully
 * added, it does not guarantee that the monitor will be activated. Activation
 * depends on various factors, including the environment, debugger presence,
 * and async safety requirements.
 */
bool kscmr_addMonitor(KSCrashMonitorAPIList *monitorList, const KSCrashMonitorAPI *api);

/**
 * Removes a crash monitor from the system.
 *
 * @param api Pointer to the monitor's API.
 *
 * If the monitor is found, it is removed from the system.
 */
void kscmr_removeMonitor(KSCrashMonitorAPIList *monitorList, const KSCrashMonitorAPI *api);

/**
 * Iterates through all monitors and calls their `addContextualInfoToEvent` callback.
 *
 * @param monitorList The list of monitors to iterate.
 * @param ctx The monitor context to be populated with contextual information.
 */
void kscmr_addContextualInfoToEvent(KSCrashMonitorAPIList *monitorList, struct KSCrash_MonitorContext *ctx);

/**
 * Retrieves a monitor from the list by its unique identifier.
 *
 * @param monitorList The list of monitors to search.
 * @param monitorId The unique identifier of the monitor to retrieve.
 * @return A pointer to the monitor's API, or NULL if no monitor with the given ID exists.
 */
const KSCrashMonitorAPI *kscmr_getMonitor(KSCrashMonitorAPIList *monitorList, const char *monitorId);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitorRegistry_h
