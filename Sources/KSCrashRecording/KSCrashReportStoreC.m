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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <uuid/uuid.h>

#include "KSCrashC.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorRegistry.h"
#include "KSCrashReportRunId.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSDate.h"
#include "KSFileUtils.h"
#include "KSLogger.h"

#import <Foundation/Foundation.h>
#import "KSCrashReportFields.h"
#import "KSCrashReportFixer.h"
#import "KSJSONCodecObjC.h"

// Have to use max 32-bit atomics because of MIPS.
static _Atomic(uint32_t) g_nextUniqueIDLow;
static int64_t g_nextUniqueIDHigh;
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

// Saved during kscrs_initialize so kscrs_readReportAtPath can stitch sidecars.
static bool g_hasStoredConfig = false;
static KSCrashReportStoreCConfiguration g_storedConfig;

static int compareInt64(const void *a, const void *b)
{
    int64_t diff = *(int64_t *)a - *(int64_t *)b;
    if (diff < 0) {
        return -1;
    } else if (diff > 0) {
        return 1;
    }
    return 0;
}

static inline int64_t getNextUniqueID(void) { return g_nextUniqueIDHigh + g_nextUniqueIDLow++; }

static void getCrashReportPathByID(int64_t id, char *pathBuffer, const KSCrashReportStoreCConfiguration *const config)
{
    snprintf(pathBuffer, KSCRS_MAX_PATH_LENGTH, "%s/%s-report-%016llx.json", config->reportsPath, config->appName,
             (uint64_t)id);
}

static int64_t getReportIDFromFilename(const char *filename, const KSCrashReportStoreCConfiguration *const config)
{
    char scanFormat[100];
    snprintf(scanFormat, sizeof(scanFormat), "%s-report-%%" PRIx64 ".json", config->appName);

    int64_t reportID = 0;
    sscanf(filename, scanFormat, &reportID);
    return reportID;
}

static int getReportCount(const KSCrashReportStoreCConfiguration *const config)
{
    int count = 0;
    DIR *dir = opendir(config->reportsPath);
    if (dir == NULL) {
        KSLOG_ERROR(@"Could not open directory %s", config->reportsPath);
        goto done;
    }
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (getReportIDFromFilename(ent->d_name, config) > 0) {
            count++;
        }
    }

done:
    if (dir != NULL) {
        closedir(dir);
    }
    return count;
}

static int getReportIDs(int64_t *reportIDs, int count, const KSCrashReportStoreCConfiguration *const config)
{
    int index = 0;
    DIR *dir = opendir(config->reportsPath);
    if (dir == NULL) {
        KSLOG_ERROR(@"Could not open directory %s", config->reportsPath);
        goto done;
    }

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL && index < count) {
        int64_t reportID = getReportIDFromFilename(ent->d_name, config);
        if (reportID > 0) {
            reportIDs[index++] = reportID;
        }
    }

    qsort(reportIDs, (unsigned)index, sizeof(reportIDs[0]), compareInt64);

done:
    if (dir != NULL) {
        closedir(dir);
    }
    return index;
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

static bool getReportSidecarFilePathForReport(const char *sidecarsBasePath, const char *monitorId, int64_t reportID,
                                              char *pathBuffer, size_t pathBufferLength)
{
    char name[32];
    snprintf(name, sizeof(name), "%016llx", (unsigned long long)reportID);
    return getReportSidecarFilePath(sidecarsBasePath, monitorId, name, "ksscr", pathBuffer, pathBufferLength);
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
    if (snprintf(pathBuffer, pathBufferLength, "%s/%s.ksscr", runDir, monitorId) >= (int)pathBufferLength) {
        return false;
    }
    return true;
}

static void deleteReportSidecarsForReport(int64_t reportID, const KSCrashReportStoreCConfiguration *const config)
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
        if (snprintf(sidecarPath, sizeof(sidecarPath), "%s/%s/%016llx.ksscr", config->reportSidecarsPath, ent->d_name,
                     (unsigned long long)reportID) < (int)sizeof(sidecarPath)) {
            ksfu_removeFile(sidecarPath, false);
        }
    }
    closedir(dir);
}

static NSDictionary *stitchReportSidecarsIntoReport(NSDictionary *report, int64_t reportID,
                                                    const KSCrashReportStoreCConfiguration *const config,
                                                    bool *stitchFailed)
{
    if (config->reportSidecarsPath == NULL) {
        return report;
    }
    DIR *dir = opendir(config->reportSidecarsPath);
    if (dir == NULL) {
        if (stitchFailed != NULL) {
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
        if (snprintf(sidecarPath, sizeof(sidecarPath), "%s/%s/%016llx.ksscr", config->reportSidecarsPath, ent->d_name,
                     (unsigned long long)reportID) >= (int)sizeof(sidecarPath)) {
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
        if (stitchFailed != NULL) {
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
#define KSCRS_MAX_REPORT_COUNT 512

/** Remove run sidecar directories that have no matching reports.
 *
 * Scans the RunSidecars directory and collects the set of active run_ids
 * from existing reports by JSON-decoding report["report"]["run_id"].
 * Any run sidecar directory whose name isn't in the active set is deleted.
 * Runs once at initialization.
 */
static void cleanupOrphanedRunSidecars(const KSCrashReportStoreCConfiguration *const config)
{
    if (config->runSidecarsPath == NULL) {
        return;
    }

    const char *currentRunID = kscrash_getRunID();

    int64_t reportIDs[KSCRS_MAX_REPORT_COUNT];
    int reportCount = getReportIDs(reportIDs, KSCRS_MAX_REPORT_COUNT, config);

    int capacity = reportCount + 1;  // +1 for current run
    char (*activeRunIds)[KSCRS_UUID_STRING_LENGTH + 1] = calloc((size_t)capacity, sizeof(*activeRunIds));
    if (activeRunIds == NULL) {
        return;
    }
    int activeCount = 0;

    // Always preserve the current run's sidecar directory
    memcpy(activeRunIds[activeCount], currentRunID, KSCRS_UUID_STRING_LENGTH);
    activeRunIds[activeCount][KSCRS_UUID_STRING_LENGTH] = '\0';
    activeCount++;

    for (int i = 0; i < reportCount; i++) {
        char reportPath[KSCRS_MAX_PATH_LENGTH];
        getCrashReportPathByID(reportIDs[i], reportPath, config);
        if (kscrs_extractRunIdFromReportFile(reportPath, activeRunIds[activeCount],
                                             sizeof(activeRunIds[activeCount]))) {
            activeCount++;
        }
    }

    DIR *dir = opendir(config->runSidecarsPath);
    if (dir != NULL) {
        struct dirent *ent;
        while ((ent = readdir(dir)) != NULL) {
            if (ent->d_name[0] == '.') {
                continue;
            }
            bool found = false;
            for (int i = 0; i < activeCount; i++) {
                if (strcmp(ent->d_name, activeRunIds[i]) == 0) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                char runDir[KSCRS_MAX_PATH_LENGTH];
                if (snprintf(runDir, sizeof(runDir), "%s/%s", config->runSidecarsPath, ent->d_name) <
                    (int)sizeof(runDir)) {
                    ksfu_deleteContentsOfPath(runDir);
                    ksfu_removeFile(runDir, false);
                }
            }
        }
        closedir(dir);
    }

    free(activeRunIds);
}

static void deleteReportWithID(int64_t reportID, const KSCrashReportStoreCConfiguration *const config)
{
    char path[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(reportID, path, config);
    ksfu_removeFile(path, true);
    deleteReportSidecarsForReport(reportID, config);
    // Run sidecar orphan cleanup is deferred to kscrs_cleanupOrphanedRunSidecars,
    // called during sendAllReports — not on the startup path.
}

static void pruneReports(const KSCrashReportStoreCConfiguration *const config)
{
    if (config->maxReportCount <= 0) {
        return;
    }
    int reportCount = getReportCount(config);
    if (reportCount > config->maxReportCount) {
        int64_t reportIDs[reportCount];
        reportCount = getReportIDs(reportIDs, reportCount, config);

        for (int i = 0; i < reportCount - config->maxReportCount; i++) {
            deleteReportWithID(reportIDs[i], config);
        }
    }
}
// clang-format off
static void initializeIDs(void)
{
    time_t rawTime = (time_t)ksdate_seconds();
    struct tm time;
    gmtime_r(&rawTime, &time);
    int64_t baseID = (int64_t)time.tm_sec
                   + (int64_t)time.tm_min * 61
                   + (int64_t)time.tm_hour * 61 * 60
                   + (int64_t)time.tm_yday * 61 * 60 * 24
                   + (int64_t)time.tm_year * 61 * 60 * 24 * 366;
    baseID <<= 23;

    g_nextUniqueIDHigh = baseID & ~(int64_t)0xffffffff;
    g_nextUniqueIDLow = (uint32_t)(baseID & 0xffffffff);
}
// clang-format on

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
        initializeIDs();

        if (g_hasStoredConfig) {
            KSCrashReportStoreCConfiguration_Release(&g_storedConfig);
        }
        g_storedConfig = KSCrashReportStoreCConfiguration_Copy((KSCrashReportStoreCConfiguration *)configuration);
        g_hasStoredConfig = true;
    }
    pthread_mutex_unlock(&g_mutex);
    return result;
}

int64_t kscrs_getNextCrashReport(char *crashReportPathBuffer,
                                 const KSCrashReportStoreCConfiguration *const configuration)
{
    int64_t nextID = getNextUniqueID();
    if (crashReportPathBuffer) {
        getCrashReportPathByID(nextID, crashReportPathBuffer, configuration);
    }
    return nextID;
}

int kscrs_getReportCount(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    int count = getReportCount(configuration);
    pthread_mutex_unlock(&g_mutex);
    return count;
}

int kscrs_getReportIDs(int64_t *reportIDs, int count, const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    count = getReportIDs(reportIDs, count, configuration);
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

static char *readReportAtPath(const char *path, int64_t reportID, const KSCrashReportStoreCConfiguration *const config)
{
    @autoreleasepool {
        char *rawReport;
        int rawLength = 0;
        ksfu_readEntireFile(path, &rawReport, &rawLength, KSCRS_MAX_REPORT_SIZE);
        if (rawReport == NULL) {
            KSLOG_ERROR(@"Failed to load report at path: %s", path);
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
            return NULL;
        }

        // Finalized reports already went through fixup and stitching at
        // recovery time, so return the raw bytes as-is.
        if (isReportFinalized(dict)) {
            return strdup(rawReport);
        }

        // Fixup (timestamp conversion)
        NSDictionary *report = kscrf_fixupReportDict(dict);

        if (config != NULL) {
            // Run sidecars first so per-report data can override per-run data
            report = stitchRunSidecarsIntoReport(report, config, NULL);
            if (reportID > 0) {
                report = stitchReportSidecarsIntoReport(report, reportID, config, NULL);
            }
        }

        // Encode once at the bottom
        NSData *encoded = [KSJSONCodec encode:report options:KSJSONEncodeOptionPretty error:nil];
        if (!encoded) {
            KSLOG_ERROR(@"Failed to encode report at path: %s", path);
            return NULL;
        }
        char *result = (char *)malloc(encoded.length + 1);
        if (!result) {
            return NULL;
        }
        memcpy(result, encoded.bytes, encoded.length);
        result[encoded.length] = '\0';
        return result;
    }
}

char *kscrs_readReportAtPath(const char *path)
{
    pthread_mutex_lock(&g_mutex);
    const KSCrashReportStoreCConfiguration *config = g_hasStoredConfig ? &g_storedConfig : NULL;
    char *result = readReportAtPath(path, 0, config);
    pthread_mutex_unlock(&g_mutex);
    return result;
}

char *kscrs_readReportByPathAndID(const char *path, int64_t reportID)
{
    pthread_mutex_lock(&g_mutex);
    const KSCrashReportStoreCConfiguration *config = g_hasStoredConfig ? &g_storedConfig : NULL;
    char *result = readReportAtPath(path, reportID, config);
    pthread_mutex_unlock(&g_mutex);
    return result;
}

bool kscrs_finalizeReport(const char *reportPath, int64_t reportID)
{
    if (reportPath == NULL || reportPath[0] == '\0' || reportID <= 0) {
        return false;
    }

    // Hold g_mutex for the entire read → stitch → write-back → sidecar
    // cleanup sequence so that a concurrent deletion cannot create a
    // window where the write-back resurrects a deleted report.
    pthread_mutex_lock(&g_mutex);

    if (!g_hasStoredConfig) {
        pthread_mutex_unlock(&g_mutex);
        return false;
    }

    @autoreleasepool {
        char *rawReport;
        int rawLength = 0;
        ksfu_readEntireFile(reportPath, &rawReport, &rawLength, KSCRS_MAX_REPORT_SIZE);
        if (rawReport == NULL) {
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
        report = stitchRunSidecarsIntoReport(report, &g_storedConfig, &stitchFailed);
        report = stitchReportSidecarsIntoReport(report, reportID, &g_storedConfig, &stitchFailed);
        if (stitchFailed) {
            KSLOG_ERROR(@"Stitching failed for report %lld, skipping finalization to allow retry on next read",
                        (long long)reportID);
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

char *kscrs_readReport(int64_t reportID, const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    char path[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(reportID, path, configuration);
    char *result = readReportAtPath(path, reportID, configuration);
    pthread_mutex_unlock(&g_mutex);
    return result;
}

int64_t kscrs_addUserReport(const char *report, int reportLength,
                            const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    int64_t currentID = getNextUniqueID();
    char crashReportPath[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(currentID, crashReportPath, configuration);

    int fd = open(crashReportPath, O_WRONLY | O_CREAT, 0644);
    if (fd < 0) {
        KSLOG_ERROR(@"Could not open file %s: %s", crashReportPath, strerror(errno));
        goto done;
    }

    int bytesWritten = (int)write(fd, report, (unsigned)reportLength);
    if (bytesWritten < 0) {
        KSLOG_ERROR(@"Could not write to file %s: %s", crashReportPath, strerror(errno));
        goto done;
    } else if (bytesWritten < reportLength) {
        KSLOG_ERROR(@"Expected to write %d bytes to file %s, but only wrote %d", reportLength, crashReportPath,
                    bytesWritten);
    }

done:
    if (fd >= 0) {
        close(fd);
    }
    pthread_mutex_unlock(&g_mutex);

    return currentID;
}

void kscrs_deleteAllReports(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    ksfu_deleteContentsOfPath(configuration->reportsPath);
    if (configuration->reportSidecarsPath != NULL) {
        ksfu_deleteContentsOfPath(configuration->reportSidecarsPath);
    }
    if (configuration->runSidecarsPath != NULL) {
        ksfu_deleteContentsOfPath(configuration->runSidecarsPath);
    }
    pthread_mutex_unlock(&g_mutex);
}

void kscrs_deleteReportWithID(int64_t reportID, const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    deleteReportWithID(reportID, configuration);
    pthread_mutex_unlock(&g_mutex);
}

bool kscrs_getReportSidecarFilePath(const char *monitorId, const char *name, const char *extension, char *pathBuffer,
                                    size_t pathBufferLength,
                                    const KSCrashReportStoreCConfiguration *const configuration)
{
    return getReportSidecarFilePath(configuration->reportSidecarsPath, monitorId, name, extension, pathBuffer,
                                    pathBufferLength);
}

bool kscrs_getReportSidecarFilePathForReport(const char *monitorId, int64_t reportID, char *pathBuffer,
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

void kscrs_cleanupOrphanedRunSidecars(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    cleanupOrphanedRunSidecars(configuration);
    pthread_mutex_unlock(&g_mutex);
}
