//
//  KSCrashReportStoreC.m
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

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <uuid/uuid.h>

#include "KSCrashC.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorRegistry.h"
#include "KSCrashReportRunId.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSFileUtils.h"
#include "KSID.h"
#include "KSLogger.h"
#import "KSString.h"

#import <Foundation/Foundation.h>
#import "KSCrashReportFields.h"
#import "KSCrashReportFixer.h"
#import "KSJSONCodecObjC.h"

// The report filename grammar is declared with the store's public constants.
// The name carries order only (a string sort is oldest first); the UUID
// inside the file is the identity.
#define KSCRS_REPORT_FILENAME_SUFFIX "." KSCRS_REPORT_FILENAME_EXTENSION
#define KSCRS_REPORT_NAME_LENGTH \
    (KSCRS_REPORT_NAME_DIGITS + 1 + KSCRS_REPORT_ID_LENGTH + (int)(sizeof(KSCRS_REPORT_FILENAME_SUFFIX) - 1))

// The last name prefix minted by this process. Names are strictly increasing
// within a process even when the clock's resolution would repeat, so the
// write order is the sort order. Minted from the crash handler without
// g_mutex: threads are suspended there, so whoever holds the lock may never
// resume. Must stay lock-free for that same reason.
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "report name prefix is minted in the crash handler");
static _Atomic(uint64_t) g_lastReportNs;
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

// The stitch config used by the no-config readers (readReportAtPath,
// readReportByPathAndID, finalizeReport). Set explicitly via
// kscrs_setStitchConfig — typically by kscrash_install. Constructing a
// KSCrashReportStore does NOT touch this; only the install (or a test that
// opts in) decides whose paths the stitching uses.
static bool g_hasStitchConfig = false;
static KSCrashReportStoreCConfiguration g_stitchConfig;

void kscrs_setStitchConfig(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    if (g_hasStitchConfig) {
        KSCrashReportStoreCConfiguration_Release(&g_stitchConfig);
        g_hasStitchConfig = false;
    }
    if (configuration != NULL) {
        g_stitchConfig = KSCrashReportStoreCConfiguration_Copy(configuration);
        g_hasStitchConfig = true;
    }
    pthread_mutex_unlock(&g_mutex);
}

static uint64_t nextReportNs(void)
{
    uint64_t now = clock_gettime_nsec_np(CLOCK_REALTIME);
    uint64_t last = atomic_load(&g_lastReportNs);
    for (;;) {
        uint64_t next = now > last ? now : last + 1;
        if (atomic_compare_exchange_weak(&g_lastReportNs, &last, next)) {
            return next;
        }
    }
}

static void getCrashReportPath(uint64_t wallClockNs, const char *reportID, char *pathBuffer,
                               const KSCrashReportStoreCConfiguration *const config)
{
    // Composed by hand: this runs in the crash handler, where snprintf is
    // off-limits (Apple's libc routes it through locale locks).
    char padded[KSCRS_REPORT_NAME_DIGITS + 1];
    char digits[KSCRS_REPORT_NAME_DIGITS + 1];
    size_t digitCount = ksstring_uint64ToDecimal(wallClockNs, digits, sizeof(digits));
    size_t padCount = KSCRS_REPORT_NAME_DIGITS - digitCount;
    memset(padded, '0', padCount);
    memcpy(padded + padCount, digits, digitCount + 1);

    strlcpy(pathBuffer, config->reportsPath, KSCRS_MAX_PATH_LENGTH);
    strlcat(pathBuffer, "/", KSCRS_MAX_PATH_LENGTH);
    strlcat(pathBuffer, padded, KSCRS_MAX_PATH_LENGTH);
    strlcat(pathBuffer, "-", KSCRS_MAX_PATH_LENGTH);
    strlcat(pathBuffer, reportID, KSCRS_MAX_PATH_LENGTH);
    strlcat(pathBuffer, KSCRS_REPORT_FILENAME_SUFFIX, KSCRS_MAX_PATH_LENGTH);
}

/** Whether a directory entry is a report file; on success its id is copied out. */
static bool parseReportFilename(const char *filename, char *reportID)
{
    if (strlen(filename) != KSCRS_REPORT_NAME_LENGTH || filename[KSCRS_REPORT_NAME_DIGITS] != '-' ||
        strncmp(filename + KSCRS_REPORT_NAME_DIGITS + 1 + KSCRS_REPORT_ID_LENGTH, KSCRS_REPORT_FILENAME_SUFFIX,
                sizeof(KSCRS_REPORT_FILENAME_SUFFIX)) != 0) {
        return false;
    }
    for (int i = 0; i < KSCRS_REPORT_NAME_DIGITS; i++) {
        if (filename[i] < '0' || filename[i] > '9') {
            return false;
        }
    }
    memcpy(reportID, filename + KSCRS_REPORT_NAME_DIGITS + 1, KSCRS_REPORT_ID_LENGTH);
    reportID[KSCRS_REPORT_ID_LENGTH] = '\0';
    return ksid_isValid(reportID);
}

typedef struct {
    char name[KSCRS_REPORT_NAME_LENGTH + 1];
} ReportName;

static int compareReportNames(const void *a, const void *b)
{
    const ReportName *nameA = a;
    const ReportName *nameB = b;
    return strncmp(nameA->name, nameB->name, sizeof(nameA->name));
}

/** The report filenames in the store, oldest first. Returns the count (an
 * absent directory is 0) and hands back a malloc'd array the caller frees,
 * or -1 when the directory cannot be enumerated (a partial listing must not
 * read as complete). Not for the crash handler.
 */
static int listReportNames(ReportName **namesOut, const KSCrashReportStoreCConfiguration *const config)
{
    *namesOut = NULL;
    DIR *dir = opendir(config->reportsPath);
    if (dir == NULL) {
        if (errno == ENOENT) {
            return 0;
        }
        KSLOG_ERROR(@"Could not open directory %s", config->reportsPath);
        return -1;
    }
    int count = 0;
    int capacity = 0;
    ReportName *names = NULL;
    for (;;) {
        errno = 0;
        struct dirent *ent = readdir(dir);
        if (ent == NULL) {
            if (errno != 0) {
                KSLOG_ERROR(@"Could not enumerate directory %s", config->reportsPath);
                closedir(dir);
                free(names);
                return -1;
            }
            break;
        }
        char reportID[KSID_SIZE];
        if (!parseReportFilename(ent->d_name, reportID)) {
            continue;
        }
        if (count == capacity) {
            capacity = capacity == 0 ? 16 : capacity * 2;
            ReportName *grown = realloc(names, sizeof(ReportName) * (size_t)capacity);
            if (grown == NULL) {
                closedir(dir);
                free(names);
                return -1;
            }
            names = grown;
        }
        strlcpy(names[count].name, ent->d_name, sizeof(names[count].name));
        count++;
    }
    closedir(dir);
    if (count > 0) {
        qsort(names, (size_t)count, sizeof(ReportName), compareReportNames);
    }
    *namesOut = names;
    return count;
}

/** The path of the report with this id, by scanning the store's directory.
 * false when no such report exists or the store cannot be enumerated.
 * A single readdir pass: id-addressed operations run once per pending report,
 * so this deliberately skips listReportNames's sort and allocation.
 */
static bool findReportPath(const char *reportID, char *pathBuffer, const KSCrashReportStoreCConfiguration *const config)
{
    if (!ksid_isValid(reportID)) {
        return false;
    }
    DIR *dir = opendir(config->reportsPath);
    if (dir == NULL) {
        if (errno != ENOENT) {
            KSLOG_ERROR(@"Could not open directory %s", config->reportsPath);
        }
        return false;
    }
    bool found = false;
    for (;;) {
        errno = 0;
        struct dirent *ent = readdir(dir);
        if (ent == NULL) {
            if (errno != 0) {
                KSLOG_ERROR(@"Could not enumerate directory %s", config->reportsPath);
            }
            break;
        }
        char candidate[KSID_SIZE];
        if (parseReportFilename(ent->d_name, candidate) && strncmp(candidate, reportID, KSID_SIZE) == 0) {
            found = snprintf(pathBuffer, KSCRS_MAX_PATH_LENGTH, "%s/%s", config->reportsPath, ent->d_name) <
                    KSCRS_MAX_PATH_LENGTH;
            break;
        }
    }
    closedir(dir);
    return found;
}

static int getReportCount(const KSCrashReportStoreCConfiguration *const config)
{
    ReportName *names = NULL;
    int count = listReportNames(&names, config);
    free(names);
    return count;
}

static bool getReportSidecarFilePath(const char *sidecarsBasePath, const char *monitorId, const char *name,
                                     const char *extension, char *pathBuffer, size_t pathBufferLength)
{
    if (sidecarsBasePath == NULL || monitorId == NULL || name == NULL || extension == NULL || pathBuffer == NULL ||
        pathBufferLength == 0) {
        return false;
    }
    char monitorDir[KSCRS_MAX_PATH_LENGTH];
    if (snprintf(monitorDir, sizeof(monitorDir), "%s/%s", sidecarsBasePath, monitorId) >= (int)sizeof(monitorDir)) {
        return false;
    }
    ksfu_makePath(monitorDir);
    if (snprintf(pathBuffer, pathBufferLength, "%s/%s.%s", monitorDir, name, extension) >= (int)pathBufferLength) {
        return false;
    }
    return true;
}

static bool getReportSidecarFilePathForReport(const char *sidecarsBasePath, const char *monitorId, const char *reportID,
                                              char *pathBuffer, size_t pathBufferLength)
{
    if (!ksid_isValid(reportID)) {
        return false;
    }
    return getReportSidecarFilePath(sidecarsBasePath, monitorId, reportID, "ksscr", pathBuffer, pathBufferLength);
}

static bool getRunSidecarFilePath(const char *runSidecarsPath, const char *monitorId, char *pathBuffer,
                                  size_t pathBufferLength)
{
    if (runSidecarsPath == NULL || monitorId == NULL || pathBuffer == NULL || pathBufferLength == 0) {
        return false;
    }
    const char *runID = kscrash_getRunID();
    if (runID == NULL || runID[0] == '\0') {
        return false;
    }
    char runDir[KSCRS_MAX_PATH_LENGTH];
    if (snprintf(runDir, sizeof(runDir), "%s/%s", runSidecarsPath, runID) >= (int)sizeof(runDir)) {
        return false;
    }
    ksfu_makePath(runDir);
    if (snprintf(pathBuffer, pathBufferLength, "%s/%s." KSCRS_RUN_SIDECAR_EXTENSION, runDir, monitorId) >=
        (int)pathBufferLength) {
        return false;
    }
    return true;
}

static void deleteReportSidecarsForReport(const char *reportID, const KSCrashReportStoreCConfiguration *const config)
{
    if (config->reportSidecarsPath == NULL) {
        return;
    }
    DIR *dir = opendir(config->reportSidecarsPath);
    if (dir == NULL) {
        return;
    }
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') {
            continue;
        }
        char sidecarPath[KSCRS_MAX_PATH_LENGTH];
        if (snprintf(sidecarPath, sizeof(sidecarPath), "%s/%s/%s.ksscr", config->reportSidecarsPath, ent->d_name,
                     reportID) < (int)sizeof(sidecarPath)) {
            ksfu_removeFile(sidecarPath, false, NULL);
        }
    }
    closedir(dir);
}

static NSDictionary *stitchReportSidecarsIntoReport(NSDictionary *report, const char *reportID,
                                                    const KSCrashReportStoreCConfiguration *const config,
                                                    bool *stitchFailed)
{
    if (config->reportSidecarsPath == NULL) {
        return report;
    }
    DIR *dir = opendir(config->reportSidecarsPath);
    if (dir == NULL) {
        // ENOENT is expected when no report sidecars exist yet
        if (errno != ENOENT && stitchFailed != NULL) {
            *stitchFailed = true;
        }
        return report;
    }
    NSDictionary *result = report;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') {
            continue;
        }
        const KSCrashMonitorAPI *api = kscm_getMonitor(ent->d_name);
        if (api == NULL || api->createStitchedReport == NULL) {
            continue;
        }
        char sidecarPath[KSCRS_MAX_PATH_LENGTH];
        if (snprintf(sidecarPath, sizeof(sidecarPath), "%s/%s/%s.ksscr", config->reportSidecarsPath, ent->d_name,
                     reportID) >= (int)sizeof(sidecarPath)) {
            continue;
        }
        if (access(sidecarPath, F_OK) != 0) {
            continue;
        }
        CFDictionaryRef stitched = api->createStitchedReport((__bridge CFDictionaryRef)result, sidecarPath,
                                                             KSCrashSidecarScopeReport, api->context);
        if (stitched != NULL) {
            result = (__bridge_transfer NSDictionary *)stitched;
        } else if (stitchFailed != NULL) {
            *stitchFailed = true;
        }
    }
    closedir(dir);
    return result;
}

static NSDictionary *stitchRunSidecarsIntoReport(NSDictionary *report,
                                                 const KSCrashReportStoreCConfiguration *const config,
                                                 bool *stitchFailed)
{
    if (config->runSidecarsPath == NULL) {
        return report;
    }

    // Extract run_id directly from the decoded dict
    id reportSection = report[KSCrashField_Report];
    if (![reportSection isKindOfClass:[NSDictionary class]]) {
        return report;
    }
    NSString *runIdStr = reportSection[KSCrashField_RunID];
    if (![runIdStr isKindOfClass:[NSString class]] || runIdStr.length == 0) {
        return report;
    }
    // Defense-in-depth: reject non-UUID run_ids to prevent path traversal
    uuid_t unused;
    if (uuid_parse(runIdStr.UTF8String, unused) != 0) {
        return report;
    }

    char runDir[KSCRS_MAX_PATH_LENGTH];
    if (snprintf(runDir, sizeof(runDir), "%s/%s", config->runSidecarsPath, runIdStr.UTF8String) >=
        (int)sizeof(runDir)) {
        return report;
    }

    DIR *dir = opendir(runDir);
    if (dir == NULL) {
        // ENOENT is expected when no run sidecars exist for this run_id
        if (errno != ENOENT && stitchFailed != NULL) {
            *stitchFailed = true;
        }
        return report;
    }

    NSDictionary *result = report;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') {
            continue;
        }
        // Strip .ksscr extension to get monitorId
        char monitorId[256];
        const char *dot = strrchr(ent->d_name, '.');
        if (dot == NULL || strcmp(dot, ".ksscr") != 0) {
            continue;
        }
        size_t nameLen = (size_t)(dot - ent->d_name);
        if (nameLen == 0 || nameLen >= sizeof(monitorId)) {
            continue;
        }
        memcpy(monitorId, ent->d_name, nameLen);
        monitorId[nameLen] = '\0';

        const KSCrashMonitorAPI *api = kscm_getMonitor(monitorId);
        if (api == NULL || api->createStitchedReport == NULL) {
            continue;
        }

        char sidecarPath[KSCRS_MAX_PATH_LENGTH];
        if (snprintf(sidecarPath, sizeof(sidecarPath), "%s/%s", runDir, ent->d_name) >= (int)sizeof(sidecarPath)) {
            continue;
        }

        CFDictionaryRef stitched = api->createStitchedReport((__bridge CFDictionaryRef)result, sidecarPath,
                                                             KSCrashSidecarScopeRun, api->context);
        if (stitched != NULL) {
            result = (__bridge_transfer NSDictionary *)stitched;
        } else if (stitchFailed != NULL) {
            *stitchFailed = true;
        }
    }
    closedir(dir);
    return result;
}

// UUID: 8-4-4-4-12 hex digits with hyphens = 36 chars
#define KSCRS_UUID_STRING_LENGTH 36

// Run ids that keep a run's on-disk data alive via a still-queued report: the
// current run, plus one per report (a report references its run's sidecars and
// its .sessions, which the report stitch reads for session_id).
static NSSet<NSString *> *reportReferencedRunIDs(const KSCrashReportStoreCConfiguration *const config)
{
    NSMutableSet<NSString *> *runIDs = [NSMutableSet setWithObject:@(kscrash_getRunID())];
    DIR *dir = opendir(config->reportsPath);
    if (dir == NULL) {
        // Can't read the reports dir (e.g. fd exhaustion): return nil so the
        // caller aborts rather than treating every reported run as an orphan.
        return nil;
    }
    for (;;) {
        errno = 0;
        struct dirent *ent = readdir(dir);
        if (ent == NULL) {
            // readdir returns NULL for both end-of-directory and error; a
            // nonzero errno means a real failure, so abort rather than reclaim
            // on a partial listing.
            if (errno != 0) {
                closedir(dir);
                return nil;
            }
            break;
        }
        // Only a report-named file references a run; artifacts such as
        // "<report>.json.tmp" are not reports and never abort the pass.
        char reportID[KSID_SIZE];
        if (!parseReportFilename(ent->d_name, reportID)) {
            continue;
        }
        char reportPath[KSCRS_MAX_PATH_LENGTH];
        if (snprintf(reportPath, sizeof(reportPath), "%s/%s", config->reportsPath, ent->d_name) >=
            (int)sizeof(reportPath)) {
            continue;
        }
        char runID[KSCRS_UUID_STRING_LENGTH + 1];
        KSCrashRunIdResult result = kscrs_extractRunIdFromReportFile(reportPath, runID, sizeof(runID));
        if (result == KSCrashRunIdResultReadError) {
            // Couldn't read a queued report: abort rather than risk reclaiming
            // run data it still references.
            closedir(dir);
            return nil;
        }
        if (result == KSCrashRunIdResultFound) {
            [runIDs addObject:@(runID)];
        }
    }
    closedir(dir);
    return runIDs;
}

// Run ids referenced by the .run summaries still on disk (a summary keeps its
// .sessions and run sidecars alive for the send-time merge and metadata
// stitch). run_id is a top-level summary key. Returns nil when a queued
// summary cannot be READ (a transient I/O failure must not be mistaken for
// absence), mirroring reportReferencedRunIDs: the caller then skips the pass.
// A summary that reads but does not DECODE, or decodes without a usable
// run_id, is deterministic garbage: the writer always emits run_id and a
// crash between O_TRUNC and the write during persist fails the strict
// decode, so nothing the store wrote can look like this. It can never
// reference, deliver, or surface anything, and nothing else ever removes
// it, so it is deleted here.
static NSSet<NSString *> *summaryReferencedRunIDs(const char *runSummariesPath)
{
    NSMutableSet<NSString *> *runIDs = [NSMutableSet set];
    NSString *dir = @(runSummariesPath);
    NSError *listError = nil;
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&listError];
    if (entries == nil) {
        // A missing directory means no summaries were ever recorded; any other
        // listing failure hides live references.
        BOOL missing =
            [listError.domain isEqualToString:NSCocoaErrorDomain] && listError.code == NSFileReadNoSuchFileError;
        return missing ? runIDs : nil;
    }
    for (NSString *entry in entries) {
        if (![entry.pathExtension.lowercaseString isEqualToString:@"run"]) {
            continue;
        }
        NSString *path = [dir stringByAppendingPathComponent:entry];
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
        if (data == nil) {
            // Deleted since the listing (a concurrent send) references nothing;
            // any other read failure hides live references.
            BOOL missing =
                [readError.domain isEqualToString:NSCocoaErrorDomain] && readError.code == NSFileReadNoSuchFileError;
            if (missing) {
                continue;
            }
            return nil;
        }
        // Strict decode: a torn file fails here and joins the garbage branch.
        id json = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
        id runID = [json isKindOfClass:[NSDictionary class]] ? json[KSCrashRunSummaryField_RunID] : nil;
        if ([runID isKindOfClass:[NSString class]] && [runID length] > 0) {
            [runIDs addObject:runID];
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
    }
    return runIDs;
}

// Reclaim on-disk data for runs nothing references any more. Idempotent: it
// recomputes the reference sets each call, so it can run at the end of any send
// flow. RunSidecars and .sessions are both kept while a report OR a summary
// references the run: reports stitch run sidecars and session ids at delivery,
// and a pending summary needs its .sessions for the record merge and its
// UserInfo run sidecar for the metadata stitch.
static void reclaimOrphanedRunData(const KSCrashReportStoreCConfiguration *const config)
{
    @autoreleasepool {
        // Before install there is no current run id, and the previous run's
        // data is not yet referenced by anything (its .run is persisted BY
        // install). Nothing can be judged orphaned yet, so a reclaim from a
        // standalone pre-install store must be a no-op.
        const char *currentRunID = kscrash_getRunID();
        if (currentRunID == NULL || currentRunID[0] == '\0') {
            return;
        }
        NSSet<NSString *> *reportRefs = reportReferencedRunIDs(config);
        if (reportRefs == nil) {
            // Couldn't enumerate reports; skip rather than orphan live run data.
            return;
        }
        NSSet<NSString *> *summaryRefs =
            config->runSummariesPath != NULL ? summaryReferencedRunIDs(config->runSummariesPath) : [NSSet set];
        if (summaryRefs == nil) {
            // Couldn't read a queued summary; skip rather than orphan live run data.
            return;
        }
        NSMutableSet<NSString *> *refs = [reportRefs mutableCopy];
        [refs unionSet:summaryRefs];
        NSFileManager *fm = [NSFileManager defaultManager];

        if (config->runSidecarsPath != NULL) {
            NSString *dir = @(config->runSidecarsPath);
            for (NSString *entry in [fm contentsOfDirectoryAtPath:dir error:nil]) {
                if (![entry hasPrefix:@"."] && ![refs containsObject:entry]) {
                    [fm removeItemAtPath:[dir stringByAppendingPathComponent:entry] error:nil];
                }
            }
        }

        if (config->runSummariesPath != NULL) {
            NSString *dir = @(config->runSummariesPath);
            for (NSString *entry in [fm contentsOfDirectoryAtPath:dir error:nil]) {
                if (![entry.pathExtension.lowercaseString isEqualToString:@KSCRS_SESSIONS_FILENAME_EXTENSION]) {
                    continue;
                }
                if (![refs containsObject:entry.stringByDeletingPathExtension]) {
                    [fm removeItemAtPath:[dir stringByAppendingPathComponent:entry] error:nil];
                }
            }
        }
    }
}

static bool deleteReportAtPath(const char *path, const char *reportID,
                               const KSCrashReportStoreCConfiguration *const config)
{
    int removeErrno = 0;
    bool removed = ksfu_removeFile(path, true, &removeErrno);
    // A report that still exists will be re-sent, and that delivery needs
    // its sidecars for the on-read stitch; delete them only once the report
    // file is gone (removed now, or already absent).
    if (removed || removeErrno == ENOENT) {
        deleteReportSidecarsForReport(reportID, config);
    }
    // Orphaned run-data cleanup is deferred to kscrs_reclaimOrphanedRunData,
    // called from the send flows — not on the startup path.
    return removed;
}

static bool deleteReportWithID(const char *reportID, const KSCrashReportStoreCConfiguration *const config)
{
    char path[KSCRS_MAX_PATH_LENGTH];
    if (findReportPath(reportID, path, config)) {
        return deleteReportAtPath(path, reportID, config);
    }
    // No report file; its sidecars are already-deletable orphans.
    deleteReportSidecarsForReport(reportID, config);
    return false;
}

static void pruneReports(const KSCrashReportStoreCConfiguration *const config)
{
    if (config->maxReportCount <= 0) {
        return;
    }
    ReportName *names = NULL;
    int count = listReportNames(&names, config);
    // Names sort oldest first, so the excess is the head of the list. The
    // listing already holds each victim's filename; deleting by path keeps
    // this a single directory scan on the startup path.
    for (int i = 0; i < count - config->maxReportCount; i++) {
        char reportID[KSID_SIZE];
        char path[KSCRS_MAX_PATH_LENGTH];
        if (parseReportFilename(names[i].name, reportID) &&
            snprintf(path, sizeof(path), "%s/%s", config->reportsPath, names[i].name) < (int)sizeof(path)) {
            deleteReportAtPath(path, reportID, config);
        }
    }
    free(names);
}

// Public API

KSCrashInstallErrorCode kscrs_initialize(const KSCrashReportStoreCConfiguration *const configuration)
{
    KSCrashInstallErrorCode result = KSCrashInstallErrorNone;
    pthread_mutex_lock(&g_mutex);
    if (ksfu_makePath(configuration->reportsPath) == false) {
        KSLOG_ERROR(@"Could not create path: %s", configuration->reportsPath);
        result = KSCrashInstallErrorCouldNotCreatePath;
    } else {
        if (configuration->reportSidecarsPath != NULL) {
            ksfu_makePath(configuration->reportSidecarsPath);
        }
        if (configuration->runSidecarsPath != NULL) {
            ksfu_makePath(configuration->runSidecarsPath);
        }
        pruneReports(configuration);
    }
    pthread_mutex_unlock(&g_mutex);
    return result;
}

void kscrs_getNextCrashReport(const char *reportID, char *crashReportPathBuffer,
                              const KSCrashReportStoreCConfiguration *const configuration)
{
    // Deliberately outside g_mutex: this runs in the crash handler. The
    // atomic prefix is what keeps concurrent names distinct and ordered.
    getCrashReportPath(nextReportNs(), reportID, crashReportPathBuffer, configuration);
}

int kscrs_getReportCount(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    int count = getReportCount(configuration);
    pthread_mutex_unlock(&g_mutex);
    return count;
}

static bool isReportFinalized(NSDictionary *dict)
{
    id section = dict[KSCrashField_Report];
    if (![section isKindOfClass:[NSDictionary class]]) {
        return false;
    }
    id val = section[KSCrashField_Finalized];
    return [val isKindOfClass:[NSNumber class]] && [val boolValue];
}

static void setReadStatus(KSCrashReportReadStatus *status, KSCrashReportReadStatus value)
{
    if (status != NULL) {
        *status = value;
    }
}

static char *readReportAtPath(const char *path, const char *reportID,
                              const KSCrashReportStoreCConfiguration *const config, KSCrashReportReadStatus *status)
{
    @autoreleasepool {
        char *rawReport;
        int rawLength = 0;
        if (!ksfu_readEntireFile(path, &rawReport, &rawLength, KSCRS_MAX_REPORT_SIZE)) {
            KSLOG_ERROR(@"Failed to load report at path: %s", path);
            setReadStatus(status, KSCrashReportReadStatusUnreadable);
            return NULL;
        }

        // Decode once at the top.
        // objc_precise_lifetime: rawReport is accessed again in the finalized-report
        // fast path below, so jsonData (which owns it via freeWhenDone:YES) must not
        // be released early by the optimizer.
        __attribute__((objc_precise_lifetime)) NSData *jsonData = [NSData dataWithBytesNoCopy:rawReport
                                                                                       length:(NSUInteger)rawLength
                                                                                 freeWhenDone:YES];
        NSMutableDictionary *dict =
            [KSJSONCodec decode:jsonData
                        options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                                KSJSONDecodeOptionKeepPartialObject
                          error:nil];
        if (![dict isKindOfClass:[NSDictionary class]]) {
            KSLOG_ERROR(@"Failed to decode report at path: %s", path);
            setReadStatus(status, KSCrashReportReadStatusUndecodable);
            return NULL;
        }

        // Fixup (timestamp conversion) always runs, even on finalized reports.
        NSDictionary *report = kscrf_fixupReportDict(dict);

        // Finalized reports already went through stitching, so skip it.
        if (!isReportFinalized(report)) {
            if (config != NULL) {
                // Run sidecars first so per-report data can override per-run data
                report = stitchRunSidecarsIntoReport(report, config, NULL);
                if (reportID != NULL) {
                    report = stitchReportSidecarsIntoReport(report, reportID, config, NULL);
                }
            }
        }

        // Encode once at the bottom
        NSData *encoded = [KSJSONCodec encode:report options:KSJSONEncodeOptionPretty error:nil];
        if (!encoded) {
            KSLOG_ERROR(@"Failed to encode report at path: %s", path);
            setReadStatus(status, KSCrashReportReadStatusUnreadable);
            return NULL;
        }
        char *result = (char *)malloc(encoded.length + 1);
        if (!result) {
            setReadStatus(status, KSCrashReportReadStatusUnreadable);
            return NULL;
        }
        memcpy(result, encoded.bytes, encoded.length);
        result[encoded.length] = '\0';
        setReadStatus(status, KSCrashReportReadStatusOK);
        return result;
    }
}

char *kscrs_readReportAtPath(const char *path)
{
    pthread_mutex_lock(&g_mutex);
    const KSCrashReportStoreCConfiguration *config = g_hasStitchConfig ? &g_stitchConfig : NULL;
    char *result = readReportAtPath(path, NULL, config, NULL);
    pthread_mutex_unlock(&g_mutex);
    return result;
}

char *kscrs_readReportByPathAndID(const char *path, const char *reportID)
{
    pthread_mutex_lock(&g_mutex);
    const KSCrashReportStoreCConfiguration *config = g_hasStitchConfig ? &g_stitchConfig : NULL;
    char *result = readReportAtPath(path, reportID, config, NULL);
    pthread_mutex_unlock(&g_mutex);
    return result;
}

bool kscrs_finalizeReport(const char *reportPath, const char *reportID)
{
    if (reportPath == NULL || reportPath[0] == '\0' || !ksid_isValid(reportID)) {
        return false;
    }

    // Hold g_mutex for the entire read → stitch → write-back → sidecar
    // cleanup sequence so that a concurrent deletion cannot create a
    // window where the write-back resurrects a deleted report.
    pthread_mutex_lock(&g_mutex);

    if (!g_hasStitchConfig) {
        pthread_mutex_unlock(&g_mutex);
        return false;
    }

    @autoreleasepool {
        char *rawReport;
        int rawLength = 0;
        if (!ksfu_readEntireFile(reportPath, &rawReport, &rawLength, KSCRS_MAX_REPORT_SIZE)) {
            pthread_mutex_unlock(&g_mutex);
            return false;
        }

        // Decode once
        NSData *jsonData = [NSData dataWithBytesNoCopy:rawReport length:(NSUInteger)rawLength freeWhenDone:YES];
        NSMutableDictionary *dict =
            [KSJSONCodec decode:jsonData
                        options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                                KSJSONDecodeOptionKeepPartialObject
                          error:nil];
        if (![dict isKindOfClass:[NSDictionary class]]) {
            pthread_mutex_unlock(&g_mutex);
            return false;
        }
        // Already finalized, nothing to do
        if (isReportFinalized(dict)) {
            pthread_mutex_unlock(&g_mutex);
            return true;
        }

        // Fixup
        NSDictionary *report = kscrf_fixupReportDict(dict);
        bool stitchFailed = false;
        report = stitchRunSidecarsIntoReport(report, &g_stitchConfig, &stitchFailed);
        report = stitchReportSidecarsIntoReport(report, reportID, &g_stitchConfig, &stitchFailed);
        if (stitchFailed) {
            KSLOG_ERROR(@"Stitching failed for report %s, skipping finalization to allow retry on next read", reportID);
            pthread_mutex_unlock(&g_mutex);
            return false;
        }

        // Set finalized flag directly on the dict
        NSMutableDictionary *finalDict;
        if ([report isKindOfClass:[NSMutableDictionary class]]) {
            finalDict = (NSMutableDictionary *)report;
        } else {
            finalDict = [report mutableCopy];
        }
        NSMutableDictionary *reportSection = finalDict[KSCrashField_Report];
        if ([reportSection isKindOfClass:[NSDictionary class]] &&
            ![reportSection isKindOfClass:[NSMutableDictionary class]]) {
            reportSection = [reportSection mutableCopy];
        } else if (![reportSection isKindOfClass:[NSDictionary class]]) {
            reportSection = [NSMutableDictionary dictionary];
        }
        reportSection[KSCrashField_Finalized] = @YES;
        finalDict[KSCrashField_Report] = reportSection;

        // Encode once
        NSData *encoded = [KSJSONCodec encode:finalDict options:KSJSONEncodeOptionPretty error:nil];
        if (!encoded) {
            KSLOG_ERROR(@"Failed to encode finalized report");
            pthread_mutex_unlock(&g_mutex);
            return false;
        }

        // Atomic write: write to .tmp then rename
        char tmpPath[KSCRS_MAX_PATH_LENGTH];
        int written = snprintf(tmpPath, sizeof(tmpPath), "%s.tmp", reportPath);
        if (written < 0 || written >= (int)sizeof(tmpPath)) {
            KSLOG_ERROR(@"Report path too long for temp file: %s", reportPath);
            pthread_mutex_unlock(&g_mutex);
            return false;
        }
        int fd = open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            KSLOG_ERROR(@"Failed to open temp file for finalization: %s (%s)", tmpPath, strerror(errno));
            pthread_mutex_unlock(&g_mutex);
            return false;
        }
        bool writeOk = ksfu_writeBytesToFD(fd, (const char *)encoded.bytes, (int)encoded.length);
        close(fd);

        if (!writeOk) {
            KSLOG_ERROR(@"Failed to write finalized report to %s", tmpPath);
            unlink(tmpPath);
            pthread_mutex_unlock(&g_mutex);
            return false;
        }

        if (rename(tmpPath, reportPath) != 0) {
            KSLOG_ERROR(@"Failed to rename finalized report %s -> %s: %s", tmpPath, reportPath, strerror(errno));
            unlink(tmpPath);
            pthread_mutex_unlock(&g_mutex);
            return false;
        }

        // Sidecars are not deleted here — they sit inert on disk (reads
        // skip stitching for finalized reports) and get cleaned up when
        // the report itself is deleted after consumption.

        pthread_mutex_unlock(&g_mutex);
        return true;
    }
}

char *kscrs_readReport(const char *reportID, const KSCrashReportStoreCConfiguration *const configuration,
                       KSCrashReportReadStatus *status)
{
    pthread_mutex_lock(&g_mutex);
    char path[KSCRS_MAX_PATH_LENGTH];
    char *result = NULL;
    if (findReportPath(reportID, path, configuration)) {
        result = readReportAtPath(path, reportID, configuration, status);
    } else {
        setReadStatus(status, KSCrashReportReadStatusUnreadable);
    }
    pthread_mutex_unlock(&g_mutex);
    return result;
}

char *kscrs_copyReportRunID(const char *reportID, const KSCrashReportStoreCConfiguration *const configuration)
{
    // g_mutex: kscrs_addUserReport writes the report path in place, so an
    // unlocked peek could read a half-written report.
    pthread_mutex_lock(&g_mutex);
    char path[KSCRS_MAX_PATH_LENGTH];
    char *result = NULL;
    if (findReportPath(reportID, path, configuration)) {
        // The extractor stops at report.run_id, so a report torn mid-write
        // still answers with its run.
        char runID[KSCRS_UUID_STRING_LENGTH + 1];
        if (kscrs_extractRunIdFromReportFile(path, runID, sizeof(runID)) == KSCrashRunIdResultFound) {
            result = strdup(runID);
        }
    }
    pthread_mutex_unlock(&g_mutex);
    return result;
}

/** The payload with report.id set to `reportID`. nil with `isObjectOut`
 * false when the payload is not a JSON object (such a report is stored as
 * given and never delivered); nil with `isObjectOut` true when a real JSON
 * object could not be re-encoded, which must fail the add rather than store
 * bytes whose report.id does not match the filename.
 */
static NSData *payloadWithInjectedID(const char *report, int reportLength, const char *reportID, bool *isObjectOut)
{
    @autoreleasepool {
        *isObjectOut = false;
        NSData *data = [NSData dataWithBytesNoCopy:(void *)report length:(NSUInteger)reportLength freeWhenDone:NO];
        NSMutableDictionary *dict =
            [KSJSONCodec decode:data
                        options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                                KSJSONDecodeOptionKeepPartialObject
                          error:nil];
        if (![dict isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        *isObjectOut = true;
        NSMutableDictionary *root = [dict isKindOfClass:[NSMutableDictionary class]] ? dict : [dict mutableCopy];
        id section = root[KSCrashField_Report];
        NSMutableDictionary *reportSection =
            [section isKindOfClass:[NSDictionary class]] ? [section mutableCopy] : [NSMutableDictionary dictionary];
        reportSection[KSCrashField_ID] = @(reportID);
        root[KSCrashField_Report] = reportSection;
        return [KSJSONCodec encode:root options:KSJSONEncodeOptionPretty error:nil];
    }
}

bool kscrs_addUserReport(const char *report, int reportLength,
                         const KSCrashReportStoreCConfiguration *const configuration, char reportIDOut[KSID_SIZE])
{
    if (report == NULL || reportLength < 0 || reportIDOut == NULL) {
        return false;
    }
    pthread_mutex_lock(&g_mutex);
    // The report's own id is its identity when it carries a valid one;
    // otherwise one is minted and written into the payload, so the file's
    // report.id always matches its name.
    NSData *payload = nil;
    bool payloadIsObject = false;
    if (kscrs_extractReportIdFromReportBytes(report, reportLength, reportIDOut, KSID_SIZE) != KSCrashRunIdResultFound) {
        ksid_generate(reportIDOut);
        payload = payloadWithInjectedID(report, reportLength, reportIDOut, &payloadIsObject);
        if (payload == nil && payloadIsObject) {
            KSLOG_ERROR(@"Could not inject the report id; not storing the report");
            pthread_mutex_unlock(&g_mutex);
            return false;
        }
    } else {
        // The extractor accepts any case, but the store's grammar (filenames,
        // listing) is uppercase; canonicalize, and rewrite the payload when
        // that changes the text so report.id still matches the filename.
        uuid_t parsed;
        if (uuid_parse(reportIDOut, parsed) != 0) {
            pthread_mutex_unlock(&g_mutex);
            return false;
        }
        char canonical[KSID_SIZE];
        uuid_unparse_upper(parsed, canonical);
        if (strncmp(canonical, reportIDOut, KSID_SIZE) != 0) {
            strlcpy(reportIDOut, canonical, KSID_SIZE);
            payload = payloadWithInjectedID(report, reportLength, reportIDOut, &payloadIsObject);
            if (payload == nil && payloadIsObject) {
                KSLOG_ERROR(@"Could not canonicalize the report id; not storing the report");
                pthread_mutex_unlock(&g_mutex);
                return false;
            }
        }
    }
    const char *bytes = payload != nil ? payload.bytes : report;
    int length = payload != nil ? (int)payload.length : reportLength;
    char crashReportPath[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPath(nextReportNs(), reportIDOut, crashReportPath, configuration);
    bool written = false;
    int fd = open(crashReportPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        KSLOG_ERROR(@"Could not open file %s: %s", crashReportPath, strerror(errno));
    } else {
        written = ksfu_writeBytesToFD(fd, bytes, length);
        if (!written) {
            KSLOG_ERROR(@"Could not write to file %s", crashReportPath);
        }
        close(fd);
    }
    pthread_mutex_unlock(&g_mutex);
    return written;
}

void kscrs_deleteAllReports(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    ksfu_deleteContentsOfPath(configuration->reportsPath);
    if (configuration->reportSidecarsPath != NULL) {
        ksfu_deleteContentsOfPath(configuration->reportSidecarsPath);
    }
    // Run data (sidecars, .sessions) is shared with queued summaries and the
    // live run; orphaned run-data cleanup is deferred to
    // kscrs_reclaimOrphanedRunData, called from the send flows.
    pthread_mutex_unlock(&g_mutex);
}

bool kscrs_deleteReportWithID(const char *reportID, const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    bool removed = deleteReportWithID(reportID, configuration);
    pthread_mutex_unlock(&g_mutex);
    return removed;
}

bool kscrs_getReportSidecarFilePath(const char *monitorId, const char *name, const char *extension, char *pathBuffer,
                                    size_t pathBufferLength,
                                    const KSCrashReportStoreCConfiguration *const configuration)
{
    return getReportSidecarFilePath(configuration->reportSidecarsPath, monitorId, name, extension, pathBuffer,
                                    pathBufferLength);
}

bool kscrs_getReportSidecarFilePathForReport(const char *monitorId, const char *reportID, char *pathBuffer,
                                             size_t pathBufferLength,
                                             const KSCrashReportStoreCConfiguration *const configuration)
{
    return getReportSidecarFilePathForReport(configuration->reportSidecarsPath, monitorId, reportID, pathBuffer,
                                             pathBufferLength);
}

bool kscrs_getRunSidecarFilePath(const char *monitorId, char *pathBuffer, size_t pathBufferLength,
                                 const KSCrashReportStoreCConfiguration *const configuration)
{
    return getRunSidecarFilePath(configuration->runSidecarsPath, monitorId, pathBuffer, pathBufferLength);
}

bool kscrs_getRunSidecarFilePathForRunID(const char *monitorId, const char *runID, char *pathBuffer,
                                         size_t pathBufferLength,
                                         const KSCrashReportStoreCConfiguration *const configuration)
{
    if (configuration == NULL || monitorId == NULL || runID == NULL || runID[0] == '\0' || pathBuffer == NULL ||
        pathBufferLength == 0) {
        return false;
    }
    const char *runSidecarsPath = configuration->runSidecarsPath;
    if (runSidecarsPath == NULL) {
        return false;
    }
    // Reject non-UUID runIDs to prevent path traversal.
    uuid_t parsed;
    if (uuid_parse(runID, parsed) != 0) {
        return false;
    }
    if (snprintf(pathBuffer, pathBufferLength, "%s/%s/%s.ksscr", runSidecarsPath, runID, monitorId) >=
        (int)pathBufferLength) {
        return false;
    }
    return true;
}

bool kscrs_getSummarySidecarFilePath(const char *runID, const char *extension, char *pathBuffer,
                                     size_t pathBufferLength,
                                     const KSCrashReportStoreCConfiguration *const configuration)
{
    if (configuration == NULL || runID == NULL || runID[0] == '\0' || extension == NULL || extension[0] == '\0' ||
        pathBuffer == NULL || pathBufferLength == 0) {
        return false;
    }
    const char *runSummariesPath = configuration->runSummariesPath;
    if (runSummariesPath == NULL) {
        return false;
    }
    // Reject non-UUID runIDs to prevent path traversal.
    uuid_t parsed;
    if (uuid_parse(runID, parsed) != 0) {
        return false;
    }
    // Path building only: read paths (the delivery stitches) must not mutate
    // disk. The session writer's call site creates the directory before
    // writing.
    if (snprintf(pathBuffer, pathBufferLength, "%s/%s.%s", runSummariesPath, runID, extension) >=
        (int)pathBufferLength) {
        return false;
    }
    return true;
}

void kscrs_reclaimOrphanedRunData(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    reclaimOrphanedRunData(configuration);
    pthread_mutex_unlock(&g_mutex);
}
