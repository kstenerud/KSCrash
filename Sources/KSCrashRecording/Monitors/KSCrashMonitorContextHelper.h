//
//  KSCrashMonitorContextHelper.h
//
//  Created by Gleb Linnik on 15.06.2024.
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

#ifndef KSCrashMonitorContextHelper_h
#define KSCrashMonitorContextHelper_h

#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

static void inline ksmc_fillMonitorContext(KSCrash_MonitorContext *monitorContext, KSCrashMonitorAPI *monitorApi)
{
    if (monitorContext) {
        monitorContext->monitorId = kscm_getMonitorId(monitorApi);
        monitorContext->monitorFlags = kscm_getMonitorFlags(monitorApi);
    }
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorContextHelper_h */
