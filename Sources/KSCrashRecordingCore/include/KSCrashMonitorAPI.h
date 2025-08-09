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
    const char *(*monitorId)(void);
    KSCrashMonitorFlag (*monitorFlags)(void);
    void (*setEnabled)(bool isEnabled);
    bool (*isEnabled)(void);
    void (*addContextualInfoToEvent)(KSCrash_MonitorContext *eventContext);
    void (*notifyPostSystemEnable)(void);
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
