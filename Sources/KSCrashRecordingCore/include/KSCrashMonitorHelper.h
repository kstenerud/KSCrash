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

#include <unistd.h>

#include "KSCrashMonitor.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    KSCM_NotInstalled = 0,  // Monitor has never been installed
    KSCM_Installed,         // Monitor is installed
    KSCM_Uninstalled,       // Monitor was installed and then uninstalled
    KSCM_FailedInstall,     // Monitor failed to install (and we won't ever try again)
} KSCM_InstalledState;

static inline void __attribute__((noreturn)) kscm_exit(int code, bool requiresAsyncSafety)
{
    if (requiresAsyncSafety) {
        _exit(code);
    } else {
        exit(code);
    }
}

static void inline kscm_fillMonitorContext(KSCrash_MonitorContext *monitorContext, KSCrashMonitorAPI *monitorApi)
{
    if (monitorContext) {
        monitorContext->monitorId = monitorApi->monitorId(monitorApi->context);
        monitorContext->monitorFlags = monitorApi->monitorFlags(monitorApi->context);
    }
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorHelper_h */
