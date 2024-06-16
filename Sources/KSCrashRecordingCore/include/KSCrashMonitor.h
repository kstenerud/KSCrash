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

#include "KSThread.h"
#include "KSCrashMonitorFlag.h"

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct KSCrash_MonitorContext;

typedef struct
{
    const char* (*monitorId)(void);
    KSCrashMonitorFlag (*monitorFlags)(void);
    void (*setEnabled)(bool isEnabled);
    bool (*isEnabled)(void);
    void (*addContextualInfoToEvent)(struct KSCrash_MonitorContext* eventContext);
    void (*notifyPostSystemEnable)(void);
} KSCrashMonitorAPI;

// ============================================================================
#pragma mark - External API -
// ============================================================================

/**
 * Activates all added crash monitors.
 */
void kscm_activateMonitors(void);

/**
 * Disables all active crash monitors.
 */
void kscm_disableAllMonitors(void);

/**
 * Adds a crash monitor to the system.
 *
 * @param api Pointer to the monitor's API.
 */
void kscm_addMonitor(KSCrashMonitorAPI* api);

/**
 * Remove a crash monitor from the system.
 *
 * @param api Pointer to the monitor's API.
 */
void kscm_removeMonitor(const KSCrashMonitorAPI* api);

/**
 * Sets the callback for event capture.
 *
 * @param onEvent Callback function for events.
 */
void kscm_setEventCallback(void (*onEvent)(struct KSCrash_MonitorContext* monitorContext));

// Uncomment and implement if needed.
/**
 * Retrieves active crash monitors.
 *
 * @return Active monitors.
 */
//KSCrashMonitorType kscm_getActiveMonitors(void);

// ============================================================================
#pragma mark - Internal API -
// ============================================================================

/** Notify that a fatal exception has been captured.
 *  This allows the system to take appropriate steps in preparation.
 *
 * @oaram isAsyncSafeEnvironment If true, only async-safe functions are allowed from now on.
 */
bool kscm_notifyFatalExceptionCaptured(bool isAsyncSafeEnvironment);

/** Start general exception processing.
 *
 * @oaram context Contextual information about the exception.
 */
void kscm_handleException(struct KSCrash_MonitorContext* context);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashMonitor_h
