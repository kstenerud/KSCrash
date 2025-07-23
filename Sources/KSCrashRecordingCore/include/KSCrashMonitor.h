//
//  KSCrashMonitor.h
//
//  Created by Karl Stenerud on 2012-02-12.
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

/** Keeps watch for crashes and informs via callback when on occurs.
 */

#ifndef HDR_KSCrashMonitor_h
#define HDR_KSCrashMonitor_h

#include <stdbool.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorFlag.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

struct KSCrash_MonitorContext;

typedef struct {
    /**
     * Initialize the monitor.
     * The monitor MUST NOT install or activate anything! This is merely to configure things for when it activates.
     * @param callbacks The callbacks that the monitor may call when reporting an exception.
     */
    void (*init)(KSCrash_ExceptionHandlerCallbacks *callbacks);
    const char *(*monitorId)(void);
    KSCrashMonitorFlag (*monitorFlags)(void);
    void (*setEnabled)(bool isEnabled);
    bool (*isEnabled)(void);
    void (*addContextualInfoToEvent)(struct KSCrash_MonitorContext *eventContext);
    void (*notifyPostSystemEnable)(void);
} KSCrashMonitorAPI;

// ============================================================================
#pragma mark - External API -
// ============================================================================

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
bool kscm_activateMonitors(void);

/**
 * Disables all active crash monitors.
 *
 * Turns off all currently active monitors.
 */
void kscm_disableAllMonitors(void);

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
bool kscm_addMonitor(KSCrashMonitorAPI *api);

/**
 * Removes a crash monitor from the system.
 *
 * @param api Pointer to the monitor's API.
 *
 * If the monitor is found, it is removed from the system.
 */
void kscm_removeMonitor(const KSCrashMonitorAPI *api);

/**
 * Sets the callback for event capture.
 *
 * @param onEvent Callback function for events.
 *
 * Registers a callback to be invoked when an event occurs.
 */
void kscm_setEventCallback(void (*onEvent)(struct KSCrash_MonitorContext *monitorContext));

// Uncomment and implement if needed.
/**
 * Retrieves active crash monitors.
 *
 * @return Active monitors.
 */
// KSCrashMonitorType kscm_getActiveMonitors(void);

// ============================================================================
#pragma mark - Internal API -
// ============================================================================

/* Transitional APIs while converting a larger API. DO NOT CALL! These WILL go away! */
void kscm_clearAsyncSafetyState(void);

// Transitional API. This will go away in a few commits. DO NOT USE EXTERNALLY.
void kscm_regenerateEventIDs(void);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitor_h
