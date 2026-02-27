//
//  KSCrashMonitor_LifecycleStitch.m
//
//  Created by Alexander Cohen on 2026-02-26.
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

#import "KSCrashMonitor_Lifecycle.h"

#import "KSCrashReportFields.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "KSLogger.h"

static double nsToSeconds(uint64_t ns) { return (double)ns / 1000000000.0; }

char *kscm_lifecycle_stitchReport(const char *report, const char *sidecarPath, __unused KSCrashSidecarScope scope,
                                  __unused void *context)
{
    if (!report || !sidecarPath) {
        return NULL;
    }

    // Read the binary struct from disk
    KSCrash_LifecycleData lc = {};
    int fd = open(sidecarPath, O_RDONLY);
    if (fd == -1) {
        KSLOG_ERROR(@"Failed to open lifecycle sidecar at %s: %s", sidecarPath, strerror(errno));
        return NULL;
    }
    if (!ksfu_readBytesFromFD(fd, (char *)&lc, (int)sizeof(lc))) {
        KSLOG_ERROR(@"Failed to read lifecycle sidecar at %s", sidecarPath);
        close(fd);
        return NULL;
    }
    close(fd);

    if (lc.magic != KSLIFECYCLE_MAGIC || lc.version == 0 || lc.version > KSCrash_Lifecycle_CurrentVersion) {
        KSLOG_ERROR(@"Invalid lifecycle sidecar at %s (magic=0x%x version=%d)", sidecarPath, lc.magic, lc.version);
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

    // Build application_stats from the sidecar struct
    NSMutableDictionary *statsDict = [NSMutableDictionary dictionary];
    statsDict[KSCrashField_AppActive] = @((BOOL)lc.applicationIsActive);
    statsDict[KSCrashField_AppInFG] = @((BOOL)lc.applicationIsInForeground);
    statsDict[KSCrashField_LaunchesSinceCrash] = @(lc.launchesSinceLastCrash);
    statsDict[KSCrashField_SessionsSinceCrash] = @(lc.sessionsSinceLastCrash);
    statsDict[KSCrashField_ActiveTimeSinceCrash] = @(nsToSeconds(lc.activeDurationSinceLastCrashNs));
    statsDict[KSCrashField_BGTimeSinceCrash] = @(nsToSeconds(lc.backgroundDurationSinceLastCrashNs));
    statsDict[KSCrashField_SessionsSinceLaunch] = @(lc.sessionsSinceLaunch);
    statsDict[KSCrashField_ActiveTimeSinceLaunch] = @(nsToSeconds(lc.activeDurationSinceLaunchNs));
    statsDict[KSCrashField_BGTimeSinceLaunch] = @(nsToSeconds(lc.backgroundDurationSinceLaunchNs));

    systemDict[KSCrashField_AppStats] = statsDict;
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
