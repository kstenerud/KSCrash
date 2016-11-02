//
//  KSCrashReportStore.c
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

#include "KSCrashReportStore.h"
#include "KSLogger.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>


static const int g_maxReports = 5;
static int64_t g_nextCrashID;
static int64_t g_nextUserReportID;
static char g_appName[KSCRS_MAX_PATH_LENGTH];
static char g_reportsPath[KSCRS_MAX_PATH_LENGTH];
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

static int compareInt64(const void* a, const void* b)
{
    int64_t diff = *(int64_t*)a - *(int64_t*)b;
    if(diff < 0)
    {
        return -1;
    }
    else if(diff > 0)
    {
        return 1;
    }
    return 0;
}

static bool makePath(const char* absolutePath)
{
    bool isSuccessful = false;
    char* pathCopy = strdup(absolutePath);
    for(char* ptr = pathCopy+1; *ptr != '\0';ptr++)
    {
        if(*ptr == '/')
        {
            *ptr = '\0';
            if(mkdir(pathCopy, S_IRWXU) < 0 && errno != EEXIST)
            {
                KSLOG_ERROR("Could not create directory %s: %s", pathCopy, strerror(errno));
                goto done;
            }
            *ptr = '/';
        }
    }
    if(mkdir(pathCopy, S_IRWXU) < 0 && errno != EEXIST)
    {
        KSLOG_ERROR("Could not create directory %s: %s", pathCopy, strerror(errno));
        goto done;
    }
    isSuccessful = true;
    
done:
    free(pathCopy);
    return isSuccessful;
}

static void removeFile(const char* path, bool mustExist)
{
    if(remove(path) < 0)
    {
        if(mustExist || errno != ENOENT)
        {
            KSLOG_ERROR("Could not delete %s: %s", path, strerror(errno));
        }
    }
}

static int readFile(const char* path, char** bufferPtr)
{
    int length = 0;
    char* buffer = NULL;
    *bufferPtr = NULL;
    
    const int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        if(errno != ENOENT)
        {
            KSLOG_ERROR("Could not open file %s: %s", path, strerror(errno));
        }
        goto done;
    }
    
    struct stat sb = {0};
    if(fstat(fd, &sb) < 0)
    {
        KSLOG_ERROR("Could not stat file %s: %s", path, strerror(errno));
        goto done;
    }
    
    length = (int)sb.st_size;
    if(length == 0)
    {
        KSLOG_ERROR("File %s is empty", path);
        goto done;
    }
    
    buffer = malloc((size_t)length);
    if(buffer == NULL)
    {
        KSLOG_ERROR("Could allocate %d bytes for file %s: %s", length, path, strerror(errno));
        goto done;
    }
    
    int bytesRead = read(fd, buffer, (size_t)length);
    if(bytesRead < 0)
    {
        KSLOG_ERROR("Error reading from file %s: %s", path, strerror(errno));
        goto done;
    }
    if(bytesRead != length)
    {
        KSLOG_ERROR("Expected to read %d bytes from file %s, but only got %ll", path, length, bytesRead);
        length = bytesRead;
    }
    *bufferPtr = buffer;
    buffer = NULL;
    
done:
    if(fd >= 0)
    {
        close(fd);
    }
    if(buffer != NULL)
    {
        free(buffer);
    }
    return length;
}

static void getCrashReportPathByID(int64_t id, char* pathBuffer)
{
    snprintf(pathBuffer, KSCRS_MAX_PATH_LENGTH, "%s/%s-report-%016llx.json", g_reportsPath, g_appName, id);
    
}

static int64_t getReportIDFromFilename(const char* filename)
{
    char scanFormat[100];
    sprintf(scanFormat, "%s-report-%%llx.json", g_appName);
    
    int64_t reportID = 0;
    sscanf(filename, scanFormat, &reportID);
    return reportID;
}

static void deleteReportWithID(int64_t id)
{
    char path[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(id, path);
    removeFile(path, true);
}

static int getReportCount()
{
    int count = 0;
    DIR* dir = opendir(g_reportsPath);
    if(dir == NULL)
    {
        KSLOG_ERROR("Could not open directory %s", g_reportsPath);
        goto done;
    }
    struct dirent* ent;
    while((ent = readdir(dir)) != NULL)
    {
        if(getReportIDFromFilename(ent->d_name) > 0)
        {
            count++;
        }
    }

done:
    if(dir != NULL)
    {
        closedir(dir);
    }
    return count;
}

static int getReportIDs(int64_t* reportIDs, int count)
{
    int index = 0;
    DIR* dir = opendir(g_reportsPath);
    if(dir == NULL)
    {
        KSLOG_ERROR("Could not open directory %s", g_reportsPath);
        goto done;
    }

    struct dirent* ent;
    while((ent = readdir(dir)) != NULL && index < count)
    {
        int64_t reportID = getReportIDFromFilename(ent->d_name);
        if(reportID > 0)
        {
            reportIDs[index++] = reportID;
        }
    }

    qsort(reportIDs, (size_t)count, sizeof(reportIDs[0]), compareInt64);

done:
    if(dir != NULL)
    {
        closedir(dir);
    }
    return index;
}

static void pruneReports()
{
    int reportCount = getReportCount();
    if(reportCount > g_maxReports)
    {
        int64_t reportIDs[reportCount];
        reportCount = getReportIDs(reportIDs, reportCount);
        
        for(int i = 0; i < reportCount - g_maxReports; i++)
        {
            deleteReportWithID(reportIDs[i]);
        }
    }
}

static void initializeIDs()
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

    g_nextCrashID = baseID | 0x400000;
    g_nextUserReportID = baseID;
}


// Public API

void kscrs_initialize(const char* appName, const char* reportsPath)
{
    pthread_mutex_lock(&g_mutex);
    strncpy(g_appName, appName, sizeof(g_appName));
    strncpy(g_reportsPath, reportsPath, sizeof(g_reportsPath));
    makePath(reportsPath);
    pruneReports();
    initializeIDs();
    pthread_mutex_unlock(&g_mutex);
}

void kscrs_getCrashReportPath(char* crashReportPathBuffer)
{
    pthread_mutex_lock(&g_mutex);
    getCrashReportPathByID(g_nextCrashID, crashReportPathBuffer);
    pthread_mutex_unlock(&g_mutex);
}

int kscrs_getReportCount()
{
    pthread_mutex_lock(&g_mutex);
    int count = getReportCount();
    pthread_mutex_unlock(&g_mutex);
    return count;
}

int kscrs_getReportIDs(int64_t* reportIDs, int count)
{
    pthread_mutex_lock(&g_mutex);
    count = getReportIDs(reportIDs, count);
    pthread_mutex_unlock(&g_mutex);
    return count;
}

void kscrs_readReport(int64_t reportID, char** reportPtr, int* reportLengthPtr)
{
    pthread_mutex_lock(&g_mutex);
    char path[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(reportID, path);
    *reportLengthPtr = readFile(path, reportPtr);
    pthread_mutex_unlock(&g_mutex);
}

void kscrs_addUserReport(const char* report, int reportLength)
{
    pthread_mutex_lock(&g_mutex);
    char crashReportPath[KSCRS_MAX_PATH_LENGTH];
    getCrashReportPathByID(g_nextUserReportID, crashReportPath);
    g_nextUserReportID++;

    int fd = open(crashReportPath, O_WRONLY | O_CREAT, 0644);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open file %s: %s", crashReportPath, strerror(errno));
        goto done;
    }

    int bytesWritten = write(fd, report, (size_t)reportLength);
    if(bytesWritten < 0)
    {
        KSLOG_ERROR("Could not write to file %s: %s", crashReportPath, strerror(errno));
        goto done;
    }
    else if(bytesWritten < (ssize_t)reportLength)
    {
        KSLOG_ERROR("Expected to write %lull bytes to file %s, but only wrote %ll", crashReportPath, reportLength, bytesWritten);
    }

done:
    if(fd >= 0)
    {
        close(fd);
    }
    pthread_mutex_unlock(&g_mutex);
}

void kscrs_deleteAllReports()
{
    pthread_mutex_lock(&g_mutex);
    DIR* dir = opendir(g_reportsPath);
    if(dir != NULL)
    {
        char pathBuffer[KSCRS_MAX_PATH_LENGTH];
        snprintf(pathBuffer, sizeof(pathBuffer), "%s/", g_reportsPath);
        char* pathPtr = pathBuffer + strlen(pathBuffer);
        int pathRemainingLength = (int)sizeof(pathBuffer) - (int)(pathPtr - pathBuffer);
        
        for(bool mustRescan = true; mustRescan; mustRescan = false)
        {
            rewinddir(dir);
            struct dirent* ent;
            while((ent = readdir(dir)))
            {
                strncpy(pathPtr, ent->d_name, pathRemainingLength);
                removeFile(pathBuffer, false);
                mustRescan = true;
            }
        }
        closedir (dir);
    }
    else
    {
        KSLOG_ERROR("Could not open directory %s", g_reportsPath);
    }
    pthread_mutex_unlock(&g_mutex);
}


// Internal API

void kscrsi_incrementCrashReportIndex()
{
    g_nextCrashID++;
}

int64_t kscrsi_getNextCrashReportID()
{
    return g_nextCrashID;
}

int64_t kscrsi_getNextUserReportID()
{
    return g_nextUserReportID;
}
