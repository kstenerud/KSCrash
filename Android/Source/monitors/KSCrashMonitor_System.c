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


#import "KSCrashMonitor_System.h"

#import "KSCrashMonitorContext.h"
#import "KSDate.h"
#import "KSSysCtl.h"
#import "KSSystemCapabilities.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


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

/** Get a sysctl value as a null terminated string.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
static const char* stringSysctl(const char* name)
{
    int size = (int)kssysctl_stringForName(name, NULL, 0);
    if(size <= 0)
    {
        return NULL;
    }

    char* value = malloc((size_t)size);
    if(kssysctl_stringForName(name, value, size) <= 0)
    {
        free(value);
        return NULL;
    }
    
    return value;
}

static const char* dateString(time_t date)
{
    char* buffer = malloc(21);
    ksdate_utcStringFromTimestamp(date, buffer);
    return buffer;
}

/** Get a sysctl value as an NSDate.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
static const char* dateSysctl(const char* name)
{
    struct timeval value = kssysctl_timevalForName(name);
    return dateString(value.tv_sec);
}

/** Check if the current build is a debug build.
 *
 * @return YES if the app was built in debug mode.
 */
static bool isDebugBuild()
{
#ifdef DEBUG
    return YES;
#else
    return NO;
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
