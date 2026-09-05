//
//  KSCrashMonitor_ResourceStitch.m
//
//  Created by Alexander Cohen on 2026-03-03.
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

#import "KSCrashMonitor_Resource.h"

#import "KSCrashAppMemory.h"
#import "KSCrashCPUTracker.h"
#import "KSCrashReportFields.h"
#import "KSFileUtils.h"

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "KSLogger.h"

/** Read the resource sidecar, saying whether reading again could go better. */
static KSCrashSidecarReadResult readResourceData(const char *path, KSCrash_ResourceData *out)
{
    if (!path || !out) return KSCrashSidecarReadFailure;

    int fd = open(path, O_RDONLY);
    if (fd == -1) return errno == ENOENT ? KSCrashSidecarReadUnrecoverable : KSCrashSidecarReadFailure;

    memset(out, 0, sizeof(*out));
    bool ok = ksfu_readBytesFromFD(fd, (char *)out, (int)sizeof(*out));
    close(fd);

    // A short read means the run died part way through writing this, and a
    // wrong magic or version is a verdict about the bytes: neither changes on
    // a later read.
    if (!ok || out->magic != KSRESOURCE_MAGIC || out->version == 0 || out->version > KSCrash_Resource_CurrentVersion) {
        return KSCrashSidecarReadUnrecoverable;
    }
    return KSCrashSidecarReadOK;
}

CFDictionaryRef kscm_resource_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, __unused void *context)
{
    if (reportDict == NULL) {
        return NULL;
    }
    if (scope != KSCrashSidecarScopeRun) {
        // Not this monitor's scope (e.g. the final pass, which has no sidecar file).
        CFRetain(reportDict);
        return reportDict;
    }
    if (sidecarPath == NULL) {
        return NULL;
    }

    KSCrash_ResourceData data = {};
    KSCrashSidecarReadResult readResult = readResourceData(sidecarPath, &data);
    if (readResult == KSCrashSidecarReadFailure) {
        KSLOG_ERROR(@"Failed to read resource sidecar at %s", sidecarPath);
        return NULL;
    }
    if (readResult != KSCrashSidecarReadOK) {
        // NULL is the retry signal, and retrying this never gets further: it
        // would stop the report being finalized for good. Deliver it without
        // the resource section.
        KSLOG_ERROR(@"Unreadable resource sidecar at %s; delivering without it", sidecarPath);
        CFRetain(reportDict);
        return reportDict;
    }

    NSMutableDictionary *dict = [(__bridge NSDictionary *)reportDict mutableCopy];

    // Navigate to or create report.system
    NSMutableDictionary *systemDict;
    id systemVal = dict[KSCrashField_System];
    if ([systemVal isKindOfClass:[NSDictionary class]]) {
        systemDict = [systemVal mutableCopy];
    } else {
        systemDict = [NSMutableDictionary dictionary];
    }

    // Stitch app_memory — same format as KSCrashMonitor_Memory serialization,
    // minus timestamp and transition state (those belong to Memory/Lifecycle).
    NSMutableDictionary *appMemoryDict;
    id appMemoryVal = systemDict[KSCrashField_AppMemory];
    if ([appMemoryVal isKindOfClass:[NSDictionary class]]) {
        appMemoryDict = [appMemoryVal mutableCopy];
    } else {
        appMemoryDict = [NSMutableDictionary dictionary];
    }
    appMemoryDict[KSCrashField_MemoryFootprint] = @(data.memoryFootprint);
    appMemoryDict[KSCrashField_MemoryRemaining] = @(data.memoryRemaining);
    appMemoryDict[KSCrashField_MemoryLimit] = @(data.memoryLimit);
    appMemoryDict[KSCrashField_MemoryPressure] =
        @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)data.memoryPressure));
    appMemoryDict[KSCrashField_MemoryLevel] = @(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)data.memoryLevel));
    systemDict[KSCrashField_AppMemory] = appMemoryDict;

    // Stitch resource fields
    if (data.batteryLevel != 255) {
        systemDict[KSCrashField_BatteryLevel] = @(data.batteryLevel);
    }
    systemDict[KSCrashField_BatteryState] = @(data.batteryState);
    systemDict[KSCrashField_LowPowerModeEnabled] = @((BOOL)data.lowPowerMode);
    systemDict[KSCrashField_CPUCoreCount] = @(data.cpuCoreCount);
    systemDict[KSCrashField_CPUUsageUser] = @(data.cpuUsageUser);
    systemDict[KSCrashField_CPUUsageSystem] = @(data.cpuUsageSystem);
    systemDict[KSCrashField_CPUState] = @(KSCrashCPUStateToString((KSCrashCPUState)data.cpuState));
    systemDict[KSCrashField_CPUAverageUsagePermil] = @(data.cpuAverageUsagePermil);
    if (data.cpuWallTimeInWindowNs > 0) {
        systemDict[KSCrashField_CPUTimeInWindow] = @((double)data.cpuTimeInWindowNs / 1e9);
        systemDict[KSCrashField_CPUWallTimeInWindow] = @((double)data.cpuWallTimeInWindowNs / 1e9);
    }
    systemDict[KSCrashField_ThermalState] = @(data.thermalState);
    systemDict[KSCrashField_ThreadCount] = @(data.threadCount);
    systemDict[KSCrashField_DataProtectionActive] = @((BOOL)data.dataProtectionActive);

    dict[KSCrashField_System] = systemDict;

    return (__bridge_retained CFDictionaryRef)dict;
}
