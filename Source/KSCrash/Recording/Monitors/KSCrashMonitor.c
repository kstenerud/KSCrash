//
//  KSCrashMonitor.c
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


#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"

#include "KSCrashMonitor_Deadlock.h"
#include "KSCrashMonitor_MachException.h"
#include "KSCrashMonitor_CPPException.h"
#include "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor_Signal.h"
#include "KSCrashMonitor_User.h"
#include "KSDebug.h"
#include "KSThread.h"
#include "KSSystemCapabilities.h"

#include <memory.h>

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


// ============================================================================
#pragma mark - Globals -
// ============================================================================

typedef struct
{
    KSCrashMonitorType monitorType;
    bool (*install)(KSCrash_MonitorContext* context);
    void (*uninstall)(void);
} Monitor;

static Monitor g_monitors[] =
{
#if KSCRASH_HAS_MACH
    {
        KSCrashMonitorTypeMachException,
        kscrashmonitor_installMachHandler,
        kscrashmonitor_uninstallMachHandler,
    },
#endif
#if KSCRASH_HAS_SIGNAL
    {
        KSCrashMonitorTypeSignal,
        kscrashmonitor_installSignalHandler,
        kscrashmonitor_uninstallSignalHandler,
    },
#endif
    {
        KSCrashMonitorTypeCPPException,
        kscrashmonitor_installCPPExceptionHandler,
        kscrashmonitor_uninstallCPPExceptionHandler,
    },
    {
        KSCrashMonitorTypeNSException,
        kscrashmonitor_installNSExceptionHandler,
        kscrashmonitor_uninstallNSExceptionHandler,
    },
    {
        KSCrashMonitorTypeMainThreadDeadlock,
        kscrashmonitor_installDeadlockHandler,
        kscrashmonitor_uninstallDeadlockHandler,
    },
    {
        KSCrashMonitorTypeUserReported,
        kscrashmonitor_installUserExceptionHandler,
        kscrashmonitor_uninstallUserExceptionHandler,
    },
};
static int g_monitorsCount = sizeof(g_monitors) / sizeof(*g_monitors);

/** Context to fill with crash information. */
static KSCrash_MonitorContext* g_context = NULL;


// ============================================================================
#pragma mark - API -
// ============================================================================

KSCrashMonitorType kscrashmonitor_installWithContext(KSCrash_MonitorContext* context,
                                             KSCrashMonitorType monitorTypes,
                                             void (*onCrash)(void))
{
    if(ksdebug_isBeingTraced())
    {
        KSLOGBASIC_WARN("KSCrash: App is running in a debugger. Only user reported events will be handled.");
        monitorTypes = KSCrashMonitorTypeUserReported;
    }
    else
    {
        KSLOG_DEBUG("Installing handlers with context %p, crash types 0x%x.", context, monitorTypes);
    }

    g_context = context;
    kscrashmonitor_clearContext(g_context);
    g_context->onCrash = onCrash;

    KSCrashMonitorType installed = KSCrashMonitorTypeNone;
    for(int i = 0; i < g_monitorsCount; i++)
    {
        Monitor* monitor = &g_monitors[i];
        if(monitor->monitorType & monitorTypes)
        {
            if(monitor->install == NULL || monitor->install(context))
            {
                installed |= monitor->monitorType;
            }
        }
    }

    KSLOG_DEBUG("Installation complete. Installed types 0x%x.", installed);
    return installed;
}

void kscrashmonitor_uninstall(KSCrashMonitorType monitorTypes)
{
    KSLOG_DEBUG("Uninstalling handlers with crash types 0x%x.", monitorTypes);
    for(int i = 0; i < g_monitorsCount; i++)
    {
        Monitor* monitor = &g_monitors[i];
        if(monitor->monitorType & monitorTypes)
        {
            if(monitor->install != NULL)
            {
                monitor->uninstall();
            }
        }
    }
    KSLOG_DEBUG("Uninstall complete.");
}


// ============================================================================
#pragma mark - Private API -
// ============================================================================

void kscrashmonitor_clearContext(KSCrash_MonitorContext* context)
{
    void (*onCrash)(void) = context->onCrash;
    memset(context, 0, sizeof(*context));
    context->onCrash = onCrash;
}

void kscrashmonitor_beginHandlingCrash(KSCrash_MonitorContext* context)
{
    kscrashmonitor_clearContext(context);
    context->handlingCrash = true;
}
