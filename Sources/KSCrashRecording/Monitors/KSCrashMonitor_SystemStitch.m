//
//  KSCrashMonitor_SystemStitch.m
//
//  Created by Alexander Cohen on 2026-02-20.
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

#import "KSCrashReportFields.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>

#import "KSLogger.h"

static void setStringIfNonEmpty(NSMutableDictionary *dict, NSString *key, const char *value)
{
    if (value && value[0] != '\0') {
        dict[key] = @(value);
    }
}

char *kscm_system_stitchReport(const char *report, const char *sidecarPath, __unused KSCrashSidecarScope scope,
                               __unused void *context)
{
    if (!report || !sidecarPath) {
        return NULL;
    }

    // Read the binary struct from disk
    KSCrash_SystemData sc = {};
    int fd = open(sidecarPath, O_RDONLY);
    if (fd == -1) {
        KSLOG_ERROR(@"Failed to open system sidecar at %s: %s", sidecarPath, strerror(errno));
        return NULL;
    }
    if (!ksfu_readBytesFromFD(fd, (char *)&sc, (int)sizeof(sc))) {
        KSLOG_ERROR(@"Failed to read system sidecar at %s", sidecarPath);
        close(fd);
        return NULL;
    }
    close(fd);

    if (sc.magic != KSSYS_MAGIC || sc.version == 0 || sc.version > KSCrash_System_CurrentVersion) {
        KSLOG_ERROR(@"Invalid system sidecar at %s (magic=0x%x version=%d)", sidecarPath, sc.magic, sc.version);
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

    // Populate system fields from the struct
    setStringIfNonEmpty(systemDict, KSCrashField_SystemName, sc.systemName);
    setStringIfNonEmpty(systemDict, KSCrashField_SystemVersion, sc.systemVersion);
    setStringIfNonEmpty(systemDict, KSCrashField_Machine, sc.machine);
    setStringIfNonEmpty(systemDict, KSCrashField_Model, sc.model);
    setStringIfNonEmpty(systemDict, KSCrashField_KernelVersion, sc.kernelVersion);
    setStringIfNonEmpty(systemDict, KSCrashField_OSVersion, sc.osVersion);
    systemDict[KSCrashField_Jailbroken] = @(sc.isJailbroken);
    systemDict[KSCrashField_ProcTranslated] = @(sc.procTranslated);
    setStringIfNonEmpty(systemDict, KSCrashField_AppStartTime, sc.appStartTime);
    setStringIfNonEmpty(systemDict, KSCrashField_ExecutablePath, sc.executablePath);
    setStringIfNonEmpty(systemDict, KSCrashField_Executable, sc.executableName);
    setStringIfNonEmpty(systemDict, KSCrashField_BundleID, sc.bundleID);
    setStringIfNonEmpty(systemDict, KSCrashField_BundleName, sc.bundleName);
    setStringIfNonEmpty(systemDict, KSCrashField_BundleVersion, sc.bundleVersion);
    setStringIfNonEmpty(systemDict, KSCrashField_BundleShortVersion, sc.bundleShortVersion);
    setStringIfNonEmpty(systemDict, KSCrashField_AppUUID, sc.appID);
    setStringIfNonEmpty(systemDict, KSCrashField_CPUArch, sc.cpuArchitecture);
    setStringIfNonEmpty(systemDict, KSCrashField_BinaryArch, sc.binaryArchitecture);
    setStringIfNonEmpty(systemDict, KSCrashField_ClangVersion, sc.clangVersion);
    systemDict[KSCrashField_CPUType] = @(sc.cpuType);
    systemDict[KSCrashField_CPUSubType] = @(sc.cpuSubType);
    systemDict[KSCrashField_BinaryCPUType] = @(sc.binaryCPUType);
    systemDict[KSCrashField_BinaryCPUSubType] = @(sc.binaryCPUSubType);
    setStringIfNonEmpty(systemDict, KSCrashField_TimeZone, sc.timezone);
    setStringIfNonEmpty(systemDict, KSCrashField_ProcessName, sc.processName);
    systemDict[KSCrashField_ProcessID] = @(sc.processID);
    systemDict[KSCrashField_ParentProcessID] = @(sc.parentProcessID);
    setStringIfNonEmpty(systemDict, KSCrashField_DeviceAppHash, sc.deviceAppHash);
    setStringIfNonEmpty(systemDict, KSCrashField_BuildType, sc.buildType);

    if (sc.bootTimestamp != 0) {
        char bootTimeBuf[KSDATE_BUFFERSIZE];
        ksdate_utcStringFromTimestamp((time_t)sc.bootTimestamp, bootTimeBuf, sizeof(bootTimeBuf));
        setStringIfNonEmpty(systemDict, KSCrashField_BootTime, bootTimeBuf);
    }

    if (sc.storageSize > 0) {
        systemDict[KSCrashField_Storage] = @(sc.storageSize);
    }
    if (sc.freeStorageSize > 0) {
        systemDict[KSCrashField_FreeStorage] = @(sc.freeStorageSize);
    }

    // Memory sub-object
    NSMutableDictionary *memoryDict;
    id memVal = systemDict[KSCrashField_Memory];
    if ([memVal isKindOfClass:[NSDictionary class]]) {
        memoryDict = [memVal mutableCopy];
    } else {
        memoryDict = [NSMutableDictionary dictionary];
    }
    memoryDict[KSCrashField_Size] = @(sc.memorySize);
    memoryDict[KSCrashField_Free] = @(sc.freeMemory);
    memoryDict[KSCrashField_Usable] = @(sc.usableMemory);
    systemDict[KSCrashField_Memory] = memoryDict;

    // Also stitch processName into report.report.process_name if present
    id reportInfoVal = dict[KSCrashField_Report];
    if ([reportInfoVal isKindOfClass:[NSDictionary class]] && sc.processName[0] != '\0') {
        NSMutableDictionary *reportInfo = [reportInfoVal mutableCopy];
        reportInfo[KSCrashField_ProcessName] = @(sc.processName);
        dict[KSCrashField_Report] = reportInfo;
    }

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
