//
//  KSCrashMonitorHelper.h
//
//  Created by Gleb Linnik on 03.06.2024.
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

#ifndef KSCrashMonitorHelper_h
#define KSCrashMonitorHelper_h

#include "KSCrashMonitor.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

static void inline kscm_fillMonitorContext(KSCrash_MonitorContext *monitorContext, KSCrashMonitorAPI *monitorApi)
{
    if (monitorContext) {
        monitorContext->monitorId = monitorApi->monitorId();
        monitorContext->monitorFlags = monitorApi->monitorFlags();
    }
}

/**
 * Initialize an API by replacing all callbacks with default no-op implementations.
 * Note: This will only initialize APIs that haven't been initialized yet (where the "init" method is still NULL), which
 * prevents it from overwriting an already setup API.
 * @param api The API to initialize.
 * @return true if api has been initialized (i.e. api->init was NULL before the call), false otherwise.
 */
bool kscm_initAPI(KSCrashMonitorAPI *api);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorHelper_h */
