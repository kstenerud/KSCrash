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
#import "KSCrashReportFields.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "KSLogger.h"

static bool readResourceData(const char *path, KSCrash_ResourceData *out)
{
    if (!path || !out) return false;

    int fd = open(path, O_RDONLY);
    if (fd == -1) return false;

    memset(out, 0, sizeof(*out));
    bool ok = ksfu_readBytesFromFD(fd, (char *)out, (int)sizeof(*out));
    close(fd);

    if (!ok || out->magic != KSRESOURCE_MAGIC || out->version == 0 || out->version > KSCrash_Resource_CurrentVersion) {
        return false;
    }
    return true;
}

char *kscm_resource_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                 __unused void *context)
{
    if (!report || !sidecarPath || scope != KSCrashSidecarScopeRun) {
        return NULL;
    }

    KSCrash_ResourceData data = {};
    if (!readResourceData(sidecarPath, &data)) {
        KSLOG_ERROR(@"Failed to read resource sidecar at %s", sidecarPath);
        return NULL;
    }

    // Decode the report JSON
    NSData *reportData = [NSData dataWithBytesNoCopy:(void *)report length:strlen(report) freeWhenDone:NO];
    NSDictionary *decoded = [KSJSONCodec decode:reportData options:KSJSONDecodeOptionNone error:nil];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        KSLOG_ERROR(@"Failed to decode report JSON");
        return NULL;
    }
    NSMutableDictionary *dict = [decoded mutableCopy];

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
    systemDict[KSCrashField_ThermalState] = @(data.thermalState);
    systemDict[KSCrashField_ThreadCount] = @(data.threadCount);
    systemDict[KSCrashField_DataProtectionActive] = @((BOOL)data.dataProtectionActive);

    dict[KSCrashField_System] = systemDict;

    // Encode back to JSON
    NSError *error = nil;
    NSData *newData = [KSJSONCodec encode:dict options:KSJSONEncodeOptionNone error:&error];
    if (!newData) {
        KSLOG_ERROR(@"Failed to encode stitched report: %@", error);
        return NULL;
    }

    char *result = (char *)malloc(newData.length + 1);
    if (!result) {
        return NULL;
    }
    memcpy(result, newData.bytes, newData.length);
    result[newData.length] = '\0';
    return result;
}
