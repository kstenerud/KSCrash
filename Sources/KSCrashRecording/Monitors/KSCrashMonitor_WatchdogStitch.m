//
//  KSCrashMonitor_WatchdogStitch.m
//
//  Created by Alexander Cohen on 2026-02-01.
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

#import "KSCrashMonitor_WatchdogSidecar.h"

#import "KSCrashMonitor_Watchdog.h"
#import "KSCrashReportFields.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>

#import "KSLogger.h"

char *kscm_watchdog_stitchReport(const char *report, int64_t reportID, const char *sidecarPath)
{
    (void)reportID;

    if (!report || !sidecarPath) {
        return NULL;
    }

    // Read the sidecar from disk (can't use ksfu_mmap — it truncates with O_TRUNC)
    KSHangSidecar sc = {};
    int fd = open(sidecarPath, O_RDONLY);
    if (fd == -1) {
        KSLOG_ERROR(@"Failed to open sidecar at %s: %s", sidecarPath, strerror(errno));
        return NULL;
    }
    if (!ksfu_readBytesFromFD(fd, (char *)&sc, (int)sizeof(sc))) {
        KSLOG_ERROR(@"Failed to read sidecar at %s", sidecarPath);
        close(fd);
        return NULL;
    }
    close(fd);

    if (sc.magic != KSHANG_SIDECAR_MAGIC || sc.version == 0 || sc.version > KSHANG_SIDECAR_CURRENT_VERSION) {
        KSLOG_ERROR(@"Invalid sidecar at %s (magic=0x%x version=%d)", sidecarPath, sc.magic, sc.version);
        return NULL;
    }

    uint64_t endTimestamp = sc.endTimestamp;
    task_role_t endRole = sc.endRole;
    bool recovered = sc.recovered;

    // Decode the report using the same codec the old code used
    NSData *reportData = [NSData dataWithBytesNoCopy:(void *)report length:strlen(report) freeWhenDone:NO];
    NSMutableDictionary *dict = [[KSJSONCodec decode:reportData options:KSJSONDecodeOptionNone error:nil] mutableCopy];
    if (!dict) {
        KSLOG_ERROR(@"Failed to decode report JSON");
        return NULL;
    }

    // Navigate to crash.error.hang
    NSMutableDictionary *crash = dict[KSCrashField_Crash];
    NSMutableDictionary *errorDict = crash[KSCrashField_Error];
    NSMutableDictionary *hang = errorDict[KSCrashField_Hang];

    if (!hang) {
        return NULL;
    }

    // Update end timestamps from sidecar
    hang[KSCrashField_HangEndNanoseconds] = @(endTimestamp);
    hang[KSCrashField_HangEndRole] = @(kscm_stringFromRole(endRole));

    if (recovered) {
        // Mark as recovered hang
        hang[KSCrashField_HangRecovered] = @YES;

        // Change the error type to "hang"
        errorDict[KSCrashField_Type] = KSCrashField_Hang;

        // Remove signal, mach, and exit reason since this is a recovered hang, not a crash
        [errorDict removeObjectForKey:KSCrashField_Signal];
        [errorDict removeObjectForKey:KSCrashField_Mach];
        [errorDict removeObjectForKey:KSCrashField_ExitReason];
    }

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
