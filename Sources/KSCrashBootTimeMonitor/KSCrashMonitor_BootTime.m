//
//  KSCrashMonitor_BootTime.c
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

#import "KSCrashMonitor_BootTime.h"

#import "KSCrashMonitorContext.h"
#import "KSDate.h"
#import "KSSysCtl.h"

#import <Foundation/Foundation.h>
#import <sys/types.h>

static volatile bool g_isEnabled = false;

__attribute__((unused)) // For tests. Declared as extern in TestCase
void kscm_bootTime_resetState(void)
{
    g_isEnabled = false;
}

/** Get a sysctl value as an NSDate.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
static const char *dateSysctl(const char *name)
{
    struct timeval value = kssysctl_timevalForName(name);
    char *buffer = malloc(21);
    ksdate_utcStringFromTimestamp(value.tv_sec, buffer);
    return buffer;
}

#pragma mark - API -

static const char *monitorId(void) { return "BootTime"; }

static void setEnabled(bool isEnabled)
{
    if (isEnabled != g_isEnabled) {
        g_isEnabled = isEnabled;
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void addContextualInfoToEvent(KSCrash_MonitorContext *eventContext)
{
    if (g_isEnabled) {
        eventContext->System.bootTime = dateSysctl("kern.boottime");
    }
}

KSCrashMonitorAPI *kscm_boottime_getAPI(void)
{
    static KSCrashMonitorAPI api = { .monitorId = monitorId,
                                     .setEnabled = setEnabled,
                                     .isEnabled = isEnabled,
                                     .addContextualInfoToEvent = addContextualInfoToEvent };
    return &api;
}

#pragma mark - Injection -

__attribute__((constructor)) static void kscm_boottime_register(void) { kscm_addMonitor(kscm_boottime_getAPI()); }
