//
//  KSCrashMonitor_UserInfo.c
//
//  Created by Alexander Cohen on 2026-03-01.
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

#include "KSCrashMonitor_UserInfo.h"

#include "KSCrashMonitor.h"
#include "KSCrashReportStoreC.h"
#include "KSFileUtils.h"

// #define KSLogger_LocalLevel TRACE
#include <os/lock.h>
#include <string.h>

#include "KSLogger.h"

#define KSUSERINFO_MONITOR_ID KSCRS_MONITOR_ID_USERINFO

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

// Delivery-time only: the live store belongs to the Swift metadata layer,
// which writes the run sidecar this monitor stitches.

static bool g_isEnabled = false;

static void monitorInit(__unused KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context) {}

static const char *monitorId(__unused void *context) { return KSUSERINFO_MONITOR_ID; }

static void setEnabled(bool isEnabled, __unused void *context) { g_isEnabled = isEnabled; }

static bool isEnabled(__unused void *context) { return g_isEnabled; }

KSCrashMonitorAPI *kscm_userinfo_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.createStitchedReport = kscm_userinfo_createStitchedReport;
    }
    return &api;
}
