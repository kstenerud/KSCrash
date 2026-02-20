//
//  KSCrashMonitor_DiscSpace.c
//
//  Created by Gleb Linnik on 04.06.2024.
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

#import "KSCrashMonitor_DiscSpace.h"

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashMonitor_System.h"

#import <Foundation/Foundation.h>

#import <stdatomic.h>
#import <sys/mount.h>
#import <unistd.h>

static _Atomic bool g_isEnabled = false;

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscm_discSpace_resetState(void)
{
    atomic_store(&g_isEnabled, false);
}

static uint64_t getStorageSize(void)
{
    struct statfs s;
    if (statfs("/", &s) == 0) {
        return (uint64_t)s.f_blocks * (uint64_t)s.f_bsize;
    }
    return 0;
}

static uint64_t getFreeStorageSize(void)
{
    struct statfs s;
    if (statfs("/", &s) == 0) {
        return (uint64_t)s.f_bfree * (uint64_t)s.f_bsize;
    }
    return 0;
}

#pragma mark - API -

static const char *monitorId(__unused void *context) { return "DiscSpace"; }

static void setEnabled(bool isEnabled, __unused void *context) { atomic_store(&g_isEnabled, isEnabled); }

static bool isEnabled_func(__unused void *context) { return atomic_load(&g_isEnabled); }

static void notifyPostSystemEnable(__unused void *context)
{
    if (atomic_load(&g_isEnabled)) {
        kscm_system_setDiscSpace(getStorageSize(), getFreeStorageSize());
    }
}

static void addContextualInfoToEvent(__unused KSCrash_MonitorContext *eventContext, __unused void *context)
{
    if (atomic_load(&g_isEnabled)) {
        kscm_system_setFreeStorageSize(getFreeStorageSize());
    }
}

KSCrashMonitorAPI *kscm_discspace_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.notifyPostSystemEnable = notifyPostSystemEnable;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
    }
    return &api;
}

#pragma mark - Injection -

__attribute__((constructor)) static void kscm_discspace_register(void) { kscm_addMonitor(kscm_discspace_getAPI()); }
