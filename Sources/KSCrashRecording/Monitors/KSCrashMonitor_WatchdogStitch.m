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

#import "KSCrashAppTransitionState.h"
#import "KSCrashMonitor_Watchdog.h"
#import "KSCrashReportFields.h"
#import "KSCrashRunContext.h"
#import "KSFileUtils.h"

#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>

#import "KSLogger.h"

CFDictionaryRef kscm_watchdog_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, __unused void *context)
{
    if (!reportDict || !sidecarPath) {
        return NULL;
    }
    if (scope != KSCrashSidecarScopeRun) {
        CFRetain(reportDict);
        return reportDict;
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

    bool recovered = sc.recovered;

    NSMutableDictionary *dict = [(__bridge NSDictionary *)reportDict mutableCopy];

    // Navigate to crash.error, create hang section from sidecar data.
    id crashVal = dict[KSCrashField_Crash];
    if (![crashVal isKindOfClass:[NSDictionary class]]) {
        KSLOG_ERROR(@"Malformed report: 'crash' is missing or not a dictionary");
        return NULL;
    }
    NSMutableDictionary *crash = [crashVal mutableCopy];

    id errorVal = crash[KSCrashField_Error];
    if (![errorVal isKindOfClass:[NSDictionary class]]) {
        KSLOG_ERROR(@"Malformed report: 'error' is missing or not a dictionary");
        return NULL;
    }
    NSMutableDictionary *errorDict = [errorVal mutableCopy];

    // Build the hang section entirely from the sidecar.
    NSMutableDictionary *hang = [NSMutableDictionary dictionary];
    hang[KSCrashField_HangStartNanoseconds] = @(sc.startTimestamp);
    hang[KSCrashField_HangStartRole] = @(kstaskrole_toString(sc.startRole));
    hang[KSCrashField_HangStartTransitionState] = @(ksapp_transitionStateToString(sc.startTransitionState));
    hang[KSCrashField_HangEndNanoseconds] = @(sc.endTimestamp);
    hang[KSCrashField_HangEndRole] = @(kstaskrole_toString(sc.endRole));
    hang[KSCrashField_HangEndTransitionState] = @(ksapp_transitionStateToString(sc.endTransitionState));

    if (recovered) {
        hang[KSCrashField_HangRecovered] = @YES;

        // Change the error type to "hang"
        errorDict[KSCrashField_Type] = KSCrashField_Hang;

        // Remove crash-only fields since this is a recovered hang, not a crash
        [errorDict removeObjectForKey:KSCrashField_Signal];
        [errorDict removeObjectForKey:KSCrashField_Mach];
        [errorDict removeObjectForKey:KSCrashField_ExitReason];
        errorDict[KSCrashField_IsFatal] = @NO;
        [errorDict removeObjectForKey:KSCrashField_IsCleanExit];
    } else {
        // Unrecovered hang: the OS killed the process, mark as fatal.
        // The report already has the correct type from the report writer.
        errorDict[KSCrashField_IsFatal] = @YES;
        errorDict[KSCrashField_IsCleanExit] = @NO;
    }

    // Write mutable copies back into their parents
    errorDict[KSCrashField_Hang] = hang;
    crash[KSCrashField_Error] = errorDict;
    dict[KSCrashField_Crash] = crash;

    return (__bridge_retained CFDictionaryRef)dict;
}
