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

#ifdef __cplusplus
extern "C" {
#endif

static inline void kscm_setMonitorEnabled(const KSCrashMonitorAPI *api, bool isEnabled)
{
    if (api != NULL && api->setEnabled != NULL) {
        api->setEnabled(isEnabled);
    }
}

static inline bool kscm_isMonitorEnabled(const KSCrashMonitorAPI *api)
{
    if (api != NULL && api->isEnabled != NULL) {
        return api->isEnabled();
    }
    return false;
}

static inline const char *kscm_getMonitorId(const KSCrashMonitorAPI *api)
{
    if (api != NULL && api->monitorId != NULL) {
        return api->monitorId();
    }
    return NULL;
}

static inline KSCrashMonitorFlag kscm_getMonitorFlags(const KSCrashMonitorAPI *api)
{
    if (api != NULL && api->monitorFlags != NULL) {
        return api->monitorFlags();
    }
    return KSCrashMonitorFlagNone;
}

static inline void kscm_addContextualInfoToEvent(const KSCrashMonitorAPI *api,
                                                 struct KSCrash_MonitorContext *eventContext)
{
    if (api != NULL && api->addContextualInfoToEvent != NULL) {
        api->addContextualInfoToEvent(eventContext);
    }
}

static inline void kscm_notifyPostSystemEnable(const KSCrashMonitorAPI *api)
{
    if (api != NULL && api->notifyPostSystemEnable != NULL) {
        api->notifyPostSystemEnable();
    }
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorHelper_h */
