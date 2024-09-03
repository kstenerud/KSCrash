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
    snprintf(pathBuffer, KSCRS_MAX_PATH_LENGTH, "%s/%s-report-%016llx.json", config->reportsPath, config->appName, id);
}

static int64_t getReportIDFromFilename(const char *filename, const KSCrashReportStoreCConfiguration *const config)
{
    char scanFormat[100];
    sprintf(scanFormat, "%s-report-%%" PRIx64 ".json", config->appName);

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

static void deleteReportWithID(int64_t reportID, const KSCrashReportStoreCConfiguration *const config)
{
    char path[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(reportID, path, config);
    ksfu_removeFile(path, true);
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
        pruneReports(configuration);
        initializeIDs();
    }
    pthread_mutex_unlock(&g_mutex);
    return KSCrashInstallErrorNone;
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

static char *readReportAtPath(const char *path)
{
    char *rawReport;
    ksfu_readEntireFile(path, &rawReport, NULL, 2000000);
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

    return result;
}

char *kscrs_readReportAtPath(const char *path)
{
    pthread_mutex_lock(&g_mutex);
    char *result = readReportAtPath(path);
    pthread_mutex_unlock(&g_mutex);
    return result;
}

char *kscrs_readReport(int64_t reportID, const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    char path[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(reportID, path, configuration);
    char *result = readReportAtPath(path);
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
    pthread_mutex_unlock(&g_mutex);
}

void kscrs_deleteReportWithID(int64_t reportID, const KSCrashReportStoreCConfiguration *const configuration)
{
    pthread_mutex_lock(&g_mutex);
    deleteReportWithID(reportID, configuration);
    pthread_mutex_unlock(&g_mutex);
}
