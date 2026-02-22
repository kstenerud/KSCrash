//
//  KSCrashReportStoreC.c
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
#include "KSCrashReportFixer.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSFileUtils.h"
#include "KSLogger.h"

// Have to use max 32-bit atomics because of MIPS.
static _Atomic(uint32_t) g_nextUniqueIDLow;
static int64_t g_nextUniqueIDHigh;
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

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
        KSLOG_ERROR("Could not open directory %s", config->reportsPath);
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
        KSLOG_ERROR("Could not open directory %s", config->reportsPath);
        goto done;
    }

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL && index < count) {
        int64_t reportID = getReportIDFromFilename(ent->d_name, config);
        if (reportID > 0) {
            reportIDs[index++] = reportID;
        }
    }

    qsort(reportIDs, (unsigned)count, sizeof(reportIDs[0]), compareInt64);

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

static char *stitchReportSidecarsIntoReport(char *report, int64_t reportID,
                                            const KSCrashReportStoreCConfiguration *const config)
{
    if (config->reportSidecarsPath == NULL) {
        return report;
    }
    DIR *dir = opendir(config->reportSidecarsPath);
    if (dir == NULL) {
        return report;
    }
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') {
            continue;
        }
        const KSCrashMonitorAPI *api = kscm_getMonitor(ent->d_name);
        if (api == NULL || api->stitchReport == NULL) {
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
        char *stitched = api->stitchReport(report, sidecarPath, KSCrashSidecarScopeReport, api->context);
        if (stitched != NULL) {
            free(report);
            report = stitched;
        }
    }
    closedir(dir);
    return report;
}

static char *stitchRunSidecarsIntoReport(char *report, const KSCrashReportStoreCConfiguration *const config)
{
    if (config->runSidecarsPath == NULL) {
        return report;
    }

    char runId[64];
    if (!kscrs_extractRunIdFromReport(report, runId, sizeof(runId))) {
        return report;
    }

    char runDir[KSCRS_MAX_PATH_LENGTH];
    if (snprintf(runDir, sizeof(runDir), "%s/%s", config->runSidecarsPath, runId) >= (int)sizeof(runDir)) {
        return report;
    }

    DIR *dir = opendir(runDir);
    if (dir == NULL) {
        return report;
    }

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
        if (api == NULL || api->stitchReport == NULL) {
            continue;
        }

        char sidecarPath[KSCRS_MAX_PATH_LENGTH];
        if (snprintf(sidecarPath, sizeof(sidecarPath), "%s/%s", runDir, ent->d_name) >= (int)sizeof(sidecarPath)) {
            continue;
        }

        char *stitched = api->stitchReport(report, sidecarPath, KSCrashSidecarScopeRun, api->context);
        if (stitched != NULL) {
            free(report);
            report = stitched;
        }
    }
    closedir(dir);
    return report;
}

// UUID: 8-4-4-4-12 hex digits with hyphens = 36 chars
#define KSCRS_UUID_STRING_LENGTH 36
#define KSCRS_MAX_REPORT_COUNT 512

/** Extract run_id from raw report bytes using strstr.
 *
 * Avoids JSON parsing entirely — just searches for the "run_id":"<uuid>"
 * pattern in the raw bytes and validates with uuid_parse. This is safe
 * because run_id is always a UUID written by our own code.
 */
static bool extractRunIdFromBytes(const char *buf, int bufLen, char *runIdOut, size_t runIdOutLen)
{
    if (buf == NULL || bufLen <= 0 || runIdOut == NULL || runIdOutLen <= KSCRS_UUID_STRING_LENGTH) {
        return false;
    }
    const char *needle = "\"run_id\":\"";
    const size_t needleLen = strlen(needle);
    const char *found = NULL;
    // buf may not be null-terminated, so use memmem-style bounded search
    for (const char *p = buf; p <= buf + bufLen - needleLen; p++) {
        if (memcmp(p, needle, needleLen) == 0) {
            found = p + needleLen;
            break;
        }
    }
    if (found == NULL || found + KSCRS_UUID_STRING_LENGTH > buf + bufLen) {
        return false;
    }
    memcpy(runIdOut, found, KSCRS_UUID_STRING_LENGTH);
    runIdOut[KSCRS_UUID_STRING_LENGTH] = '\0';

    uuid_t unused;
    return uuid_parse(runIdOut, unused) == 0;
}

/** Remove run sidecar directories that have no matching reports.
 *
 * Scans the RunSidecars directory and collects the set of active run_ids from
 * existing reports. Any run sidecar directory whose name isn't in the active
 * set is deleted. Runs once at initialization.
 *
 * Uses a lightweight byte scan (no JSON parsing, no ObjC) and reads only
 * the first 2 KB of each report — the run_id is in the report header.
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
    // run_id is in the report header — 2 KB is more than enough
    const int prefixSize = 2048;
    for (int i = 0; i < reportCount; i++) {
        char reportPath[KSCRS_MAX_PATH_LENGTH];
        getCrashReportPathByID(reportIDs[i], reportPath, config);
        char *buf;
        int bytesRead = 0;
        ksfu_readEntireFile(reportPath, &buf, &bytesRead, prefixSize);
        if (buf == NULL) {
            continue;
        }
        if (extractRunIdFromBytes(buf, bytesRead, activeRunIds[activeCount], sizeof(activeRunIds[activeCount]))) {
            activeCount++;
        }
        free(buf);
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
    time_t rawTime;
    time(&rawTime);
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
        KSLOG_ERROR("Could not create path: %s", configuration->reportsPath);
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

static char *readReportAtPath(const char *path, int64_t reportID, const KSCrashReportStoreCConfiguration *const config)
{
    char *rawReport;
    const size_t maxReportSize = 20000000;
    ksfu_readEntireFile(path, &rawReport, NULL, maxReportSize);
    if (rawReport == NULL) {
        KSLOG_ERROR("Failed to load report at path: %s", path);
        return NULL;
    }

    char *result = kscrf_fixupCrashReport(rawReport);
    free(rawReport);
    if (result == NULL) {
        KSLOG_ERROR("Failed to fixup report at path: %s", path);
        return NULL;
    }

    if (config != NULL) {
        // Run sidecars first so per-report data can override per-run data
        result = stitchRunSidecarsIntoReport(result, config);
        if (reportID > 0) {
            result = stitchReportSidecarsIntoReport(result, reportID, config);
        }
    }

    return result;
}

char *kscrs_readReportAtPath(const char *path)
{
    pthread_mutex_lock(&g_mutex);
    char *result = readReportAtPath(path, 0, NULL);
    pthread_mutex_unlock(&g_mutex);
    return result;
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
        KSLOG_ERROR("Could not open file %s: %s", crashReportPath, strerror(errno));
        goto done;
    }

    int bytesWritten = (int)write(fd, report, (unsigned)reportLength);
    if (bytesWritten < 0) {
        KSLOG_ERROR("Could not write to file %s: %s", crashReportPath, strerror(errno));
        goto done;
    } else if (bytesWritten < reportLength) {
        KSLOG_ERROR("Expected to write %d bytes to file %s, but only wrote %d", crashReportPath, reportLength,
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

void kscrs_cleanupOrphanedRunSidecars(const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    cleanupOrphanedRunSidecars(configuration);
    pthread_mutex_unlock(&g_mutex);
}
