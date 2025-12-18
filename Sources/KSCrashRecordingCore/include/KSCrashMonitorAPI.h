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

#include <stdbool.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashNamespace.h"
#include "KSCrashReportWriter.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Monitor API.
 * WARNING: All functions MUST be idempotent!
 */
typedef struct {
    /**
     * Initialize the monitor.
     * The monitor MUST NOT install or activate anything! This is merely to configure things for when it activates.
     * @param callbacks The callbacks that the monitor may call when reporting an exception.
     */
    void (*init)(KSCrash_ExceptionHandlerCallbacks *callbacks);

    /** Returns the unique identifier for this monitor (e.g., "mach", "signal", "profile"). */
    const char *(*monitorId)(void);

    /** Returns the flags describing this monitor's capabilities and requirements. */
    KSCrashMonitorFlag (*monitorFlags)(void);

    /** Enables or disables this monitor. */
    void (*setEnabled)(bool isEnabled);

    /** Returns whether this monitor is currently enabled. */
    bool (*isEnabled)(void);

    /** Called to allow the monitor to add contextual information to an event context. */
    void (*addContextualInfoToEvent)(KSCrash_MonitorContext *eventContext);

    /** Called after the system monitors have been enabled. */
    void (*notifyPostSystemEnable)(void);

    /**
     * Called during report writing to allow the monitor to write custom data to its section.
     *
     * This callback is invoked when the report writer encounters a monitor type it doesn't
     * have built-in handling for. The monitor can use the writer to add custom JSON data
     * to the report's error section under a key matching the monitor's ID.
     *
     * @param eventContext The monitor context containing event information.
     * @param writer The report writer to use for adding JSON elements.
     */
    void (*writeInReportSection)(const KSCrash_MonitorContext *eventContext, const KSCrashReportWriter *writer);
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
