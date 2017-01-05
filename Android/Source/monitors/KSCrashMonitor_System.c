//
//  KSCrashMonitor_System.m
//
//  Created by Karl Stenerud on 2012-02-05.
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

#include "KSCrashMonitor_System.h"

#include "KSCrashMonitorContext.h"
#include "KSDate.h"
#include "KSSystemCapabilities.h"
#include <sys/types.h>
#include <stdbool.h>
#include <memory.h>
#include <time.h>

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


typedef struct
{
    const char* systemName;
    const char* systemVersion;
    const char* machine;
    const char* model;
    const char* kernelVersion;
    const char* osVersion;
    bool isJailbroken;
    const char* bootTime;
    const char* appStartTime;
    const char* executablePath;
    const char* executableName;
    const char* bundleID;
    const char* bundleName;
    const char* bundleVersion;
    const char* bundleShortVersion;
    const char* appID;
    const char* cpuArchitecture;
    int cpuType;
    int cpuSubType;
    int binaryCPUType;
    int binaryCPUSubType;
    const char* timezone;
    const char* processName;
    int processID;
    int parentProcessID;
    const char* deviceAppHash;
    const char* buildType;
    uint64_t storageSize;
    uint64_t memorySize;
} SystemData;

static SystemData g_systemData;

static volatile bool g_isEnabled = false;


// ============================================================================
#pragma mark - Utility -
// ============================================================================

static const char* dateString(time_t date)
{
    char* buffer = malloc(21);
    ksdate_utcStringFromTimestamp(date, buffer);
    return buffer;
}

/** Check if the current build is a debug build.
 *
 * @return YES if the app was built in debug mode.
 */
static bool isDebugBuild()
{
#ifdef DEBUG
    return true;
#else
    return false;
#endif
}


// ============================================================================
#pragma mark - API -
// ============================================================================

static void initialize()
{
    static bool isInitialized = false;
    if(!isInitialized)
    {
        isInitialized = true;

        g_systemData.appStartTime = dateString(time(NULL));
        // TODO: The rest.
    }
}

static void setEnabled(bool isEnabled)
{
    if(isEnabled != g_isEnabled)
    {
        g_isEnabled = isEnabled;
        if(isEnabled)
        {
            initialize();
        }
    }
}

static bool isEnabled()
{
    return g_isEnabled;
}

static void addContextualInfoToEvent(KSCrash_MonitorContext* eventContext)
{
    if(g_isEnabled)
    {
#define COPY_REFERENCE(NAME) eventContext->System.NAME = g_systemData.NAME
        COPY_REFERENCE(systemName);
        COPY_REFERENCE(systemVersion);
        COPY_REFERENCE(machine);
        COPY_REFERENCE(model);
        COPY_REFERENCE(kernelVersion);
        COPY_REFERENCE(osVersion);
        COPY_REFERENCE(isJailbroken);
        COPY_REFERENCE(bootTime);
        COPY_REFERENCE(appStartTime);
        COPY_REFERENCE(executablePath);
        COPY_REFERENCE(executableName);
        COPY_REFERENCE(bundleID);
        COPY_REFERENCE(bundleName);
        COPY_REFERENCE(bundleVersion);
        COPY_REFERENCE(bundleShortVersion);
        COPY_REFERENCE(appID);
        COPY_REFERENCE(cpuArchitecture);
        COPY_REFERENCE(cpuType);
        COPY_REFERENCE(cpuSubType);
        COPY_REFERENCE(binaryCPUType);
        COPY_REFERENCE(binaryCPUSubType);
        COPY_REFERENCE(timezone);
        COPY_REFERENCE(processName);
        COPY_REFERENCE(processID);
        COPY_REFERENCE(parentProcessID);
        COPY_REFERENCE(deviceAppHash);
        COPY_REFERENCE(buildType);
        COPY_REFERENCE(storageSize);
        COPY_REFERENCE(memorySize);
    }
}

KSCrashMonitorAPI* kscm_system_getAPI()
{
    static KSCrashMonitorAPI api =
    {
        .setEnabled = setEnabled,
        .isEnabled = isEnabled,
        .addContextualInfoToEvent = addContextualInfoToEvent
    };
    return &api;
}
