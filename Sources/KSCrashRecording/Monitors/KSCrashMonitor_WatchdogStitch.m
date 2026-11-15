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
#import "KSCrashC.h"
#import "KSCrashMonitor_Watchdog.h"
#import "KSCrashReportFields.h"
#import "KSCrashRunContext.h"
#import "KSFileUtils.h"
#import "KSID.h"

#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>

#import "KSLogger.h"

// Returns a +1 CFDictionaryRef per the CF Create Rule, as specified by the
// createStitchedReport contract in KSCrashMonitorAPI.h. The early-return for
// non-run scopes retains the input to satisfy this ownership requirement.
/** Read the hang sidecar, saying whether reading again could go better.
 *  Cannot use ksfu_mmap, which truncates with O_TRUNC.
 */
static KSCrashSidecarReadResult readHangSidecar(const char *path, KSHangSidecar *out)
{
    int fd = open(path, O_RDONLY);
    if (fd == -1) {
        // Before logging: the logger's own writes can replace errno.
        int openError = errno;
        KSLOG_ERROR(@"Failed to open sidecar at %s: %s", path, strerror(openError));
        return openError == ENOENT ? KSCrashSidecarReadUnrecoverable : KSCrashSidecarReadFailure;
    }
    bool didRead = ksfu_readBytesFromFD(fd, (char *)out, (int)sizeof(*out));
    close(fd);
    if (!didRead) {
        // Short of a whole sidecar: the run died part way through writing it,
        // and the bytes that are missing are not coming.
        KSLOG_ERROR(@"Failed to read sidecar at %s", path);
        return KSCrashSidecarReadUnrecoverable;
    }
    if (out->magic != KSHANG_SIDECAR_MAGIC || out->version == 0 || out->version > KSHANG_SIDECAR_CURRENT_VERSION) {
        KSLOG_ERROR(@"Invalid sidecar at %s (magic=0x%x version=%d)", path, out->magic, out->version);
        return KSCrashSidecarReadUnrecoverable;
    }
    return KSCrashSidecarReadOK;
}

static NSString *runIDOfReport(NSDictionary *report)
{
    id reportVal = report[KSCrashField_Report];
    id storedRunID = [reportVal isKindOfClass:[NSDictionary class]] ? reportVal[KSCrashField_RunID] : nil;
    return [storedRunID isKindOfClass:[NSString class]] ? storedRunID : nil;
}

/** Whether something other than the hang ended the report's run: a crash handler
 *  ran, or the run exited cleanly (SIGTERM, a normal termination), as that run's
 *  lifecycle recorded it. A run whose lifecycle cannot be read says no: nothing
 *  then shows that the hang was not what ended it.
 */
static bool runEndedByAnotherEvent(NSDictionary *report)
{
    KSCrashRunContext run = {};
    ksruncontext_contextForRunID(runIDOfReport(report).UTF8String, kscm_watchdog_runSidecarPathForRunIDProvider(),
                                 &run);
    if (!run.lifecycleValid) {
        return false;
    }
    return run.lifecycle.monitorHandlerRan || run.lifecycle.cleanExit;
}

/** A watchdog report is written as the kill the OS makes of a hang. Whether the
 *  hang is what ended the process is only known at delivery, from the run: the
 *  hang did when it had not recovered and nothing else ended the run. Otherwise
 *  the report is the hang, not a death.
 */
static void resolveWatchdogError(NSMutableDictionary *errorDict, bool recovered, NSDictionary *report)
{
    bool killedInHang = !recovered && !runEndedByAnotherEvent(report);
    if (killedInHang) {
        errorDict[KSCrashField_IsFatal] = @YES;
        errorDict[KSCrashField_IsCleanExit] = @NO;
        return;
    }
    errorDict[KSCrashField_Type] = KSCrashExcType_Hang;
    [errorDict removeObjectForKey:KSCrashField_Signal];
    [errorDict removeObjectForKey:KSCrashField_Mach];
    [errorDict removeObjectForKey:KSCrashField_ExitReason];
    errorDict[KSCrashField_IsFatal] = @NO;
    [errorDict removeObjectForKey:KSCrashField_IsCleanExit];
}

static bool isWatchdogReport(NSDictionary *report)
{
    id reportSectionVal = report[KSCrashField_Report];
    if (![reportSectionVal isKindOfClass:[NSDictionary class]]) {
        return false;
    }
    id monitorIdVal = ((NSDictionary *)reportSectionVal)[KSCrashField_MonitorId];
    return [monitorIdVal isKindOfClass:[NSString class]] && [monitorIdVal isEqualToString:@"Watchdog"];
}

/** The final pass. A watchdog report the run pass gave no hang section had no
 *  readable sidecar, and it still says what the cause of death was. An
 *  unfinalized watchdog report is from a run that ended during its hang (a
 *  recovered hang's report is finalized or deleted), so it did not recover. A
 *  report of the live run is left as it is: that run has not ended.
 */
static CFDictionaryRef stitchWithoutSidecar(CFDictionaryRef reportDict)
{
    NSDictionary *report = (__bridge NSDictionary *)reportDict;
    id crashVal = report[KSCrashField_Crash];
    id errorVal = [crashVal isKindOfClass:[NSDictionary class]] ? crashVal[KSCrashField_Error] : nil;
    id hangVal = [errorVal isKindOfClass:[NSDictionary class]] ? errorVal[KSCrashField_Hang] : nil;
    bool hasHangSection = [hangVal isKindOfClass:[NSDictionary class]] && hangVal[KSCrashField_HangRecovered] != nil;
    NSString *runID = runIDOfReport(report);
    const char *liveRunID = kscrash_getRunID();
    bool isLiveRun = runID != nil && liveRunID != NULL && strncmp(runID.UTF8String, liveRunID, KSID_SIZE) == 0;
    if (!isWatchdogReport(report) || ![errorVal isKindOfClass:[NSDictionary class]] || hasHangSection || isLiveRun) {
        CFRetain(reportDict);
        return reportDict;
    }

    NSMutableDictionary *dict = [report mutableCopy];
    NSMutableDictionary *crash = [crashVal mutableCopy];
    NSMutableDictionary *errorDict = [errorVal mutableCopy];
    resolveWatchdogError(errorDict, false, report);
    crash[KSCrashField_Error] = errorDict;
    dict[KSCrashField_Crash] = crash;
    return (__bridge_retained CFDictionaryRef)dict;
}

CFDictionaryRef kscm_watchdog_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, __unused void *context)
{
    if (reportDict == NULL) {
        return NULL;
    }
    if (scope == KSCrashSidecarScopeFinal) {
        return stitchWithoutSidecar(reportDict);
    }
    if (scope != KSCrashSidecarScopeRun) {
        CFRetain(reportDict);
        return reportDict;
    }
    if (sidecarPath == NULL) {
        return NULL;
    }

    KSHangSidecar sc = {};
    KSCrashSidecarReadResult readResult = readHangSidecar(sidecarPath, &sc);
    if (readResult == KSCrashSidecarReadFailure) {
        return NULL;
    }
    if (readResult != KSCrashSidecarReadOK) {
        // No later read gets further, and NULL here is not free: it stops this
        // report being finalized for good, and on the hang-recovery path
        // kscm_watchdog deletes the report outright. Deliver it without the
        // hang section instead; the final pass still resolves a watchdog
        // report's cause of death (stitchWithoutSidecar).
        CFRetain(reportDict);
        return reportDict;
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

    // The hang section is added to all reports from the run as context
    // (e.g., an exception that occurred during a hang).
    NSMutableDictionary *hang = [NSMutableDictionary dictionary];
    hang[KSCrashField_HangStartNanoseconds] = @(sc.startTimestamp);
    hang[KSCrashField_HangStartRole] = @(kstaskrole_toString(sc.startRole));
    hang[KSCrashField_HangStartTransitionState] = @(ksapp_transitionStateToString(sc.startTransitionState));
    if (sc.version >= KSHANG_SIDECAR_VERSION_2_0) {
        // Older sidecars never recorded it.
        hang[KSCrashField_DuringStartup] = sc.duringStartup ? @YES : @NO;
    }
    hang[KSCrashField_HangEndNanoseconds] = @(sc.endTimestamp);
    hang[KSCrashField_HangEndRole] = @(kstaskrole_toString(sc.endRole));
    hang[KSCrashField_HangEndTransitionState] = @(ksapp_transitionStateToString(sc.endTransitionState));

    // A report records its own moment: whether the hang had ended by the time
    // the report was taken. Two reports of the same hang taken at different
    // moments can differ, and both are right.
    hang[KSCrashField_HangRecovered] = recovered ? @YES : @NO;

    if (isWatchdogReport(dict)) {
        resolveWatchdogError(errorDict, recovered, dict);
    }

    // Write mutable copies back into their parents
    errorDict[KSCrashField_Hang] = hang;
    crash[KSCrashField_Error] = errorDict;
    dict[KSCrashField_Crash] = crash;

    return (__bridge_retained CFDictionaryRef)dict;
}
