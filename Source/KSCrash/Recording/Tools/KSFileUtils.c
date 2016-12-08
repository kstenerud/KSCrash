//
//  KSFileUtils.c
//
//  Created by Karl Stenerud on 2012-01-28.
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


#include "KSFileUtils.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>


/** Buffer size to use in the "writeFmt" functions.
 * If the formatted output length would exceed this value, it is truncated.
 */
#ifndef KSFU_WriteFmtBufferSize
    #define KSFU_WriteFmtBufferSize 1024
#endif


// ============================================================================
#pragma mark - Utility -
// ============================================================================

static bool canDeletePath(const char* path)
{
    const char* lastComponent = strrchr(path, '/');
    if(lastComponent == NULL)
    {
        lastComponent = path;
    }
    else
    {
        lastComponent++;
    }
    if(strcmp(lastComponent, ".") == 0)
    {
        return false;
    }
    if(strcmp(lastComponent, "..") == 0)
    {
        return false;
    }
    return true;
}

static int dirContentsCount(const char* path)
{
    int count = 0;
    DIR* dir = opendir(path);
    if(dir == NULL)
    {
        KSLOG_ERROR("Error reading directory %s: %s", strerror(errno));
        return 0;
    }
    
    struct dirent* ent;
    while((ent = readdir(dir)))
    {
        count++;
    }
    
    closedir(dir);
    return count;
}

static void dirContents(const char* path, char*** entries, int* count)
{
    DIR* dir = NULL;
    char** entryList = NULL;
    int entryCount = dirContentsCount(path);
    if(entryCount <= 0)
    {
        goto done;
    }
    dir = opendir(path);
    if(dir == NULL)
    {
        KSLOG_ERROR("Error reading directory %s: %s", strerror(errno));
        goto done;
    }
    
    entryList = calloc((unsigned)entryCount, sizeof(char*));
    struct dirent* ent;
    int index = 0;
    while((ent = readdir(dir)))
    {
        if(index >= entryCount)
        {
            KSLOG_ERROR("Contents of %s have been mutated", path);
            goto done;
        }
        entryList[index] = strdup(ent->d_name);
        index++;
    }
    
done:
    if(dir != NULL)
    {
        closedir(dir);
    }
    if(entryList == NULL)
    {
        entryCount = 0;
    }
    *entries = entryList;
    *count = entryCount;
}

static void freeDirListing(char** entries, int count)
{
    if(entries != NULL)
    {
        for(int i = 0; i < count; i++)
        {
            char* ptr = entries[i];
            if(ptr != NULL)
            {
                free(ptr);
            }
        }
        free(entries);
    }
}

static bool deletePathContents(const char* path, bool deleteTopLevelPathAlso)
{
    struct stat statStruct = {0};
    if(stat(path, &statStruct) != 0)
    {
        KSLOG_ERROR("Could not stat %s: %s", strerror(errno));
        return false;
    }
    if(S_ISDIR(statStruct.st_mode))
    {
        char** entries = NULL;
        int entryCount = 0;
        dirContents(path, &entries, &entryCount);
        
        int bufferLength = KSFU_MAX_PATH_LENGTH;
        char* pathBuffer = malloc((unsigned)bufferLength);
        snprintf(pathBuffer, bufferLength, "%s/", path);
        char* pathPtr = pathBuffer + strlen(pathBuffer);
        int pathRemainingLength = bufferLength - (int)(pathPtr - pathBuffer);
        
        for(int i = 0; i < entryCount; i++)
        {
            char* entry = entries[i];
            if(entry != NULL && canDeletePath(entry))
            {
                strncpy(pathPtr, entry, pathRemainingLength);
                deletePathContents(pathBuffer, true);
            }
        }
        
        free(pathBuffer);
        freeDirListing(entries, entryCount);
        if(deleteTopLevelPathAlso)
        {
            ksfu_removeFile(path, false);
        }
    }
    else if(S_ISREG(statStruct.st_mode))
    {
        ksfu_removeFile(path, false);
    }
    else
    {
        KSLOG_ERROR("Could not delete %s: Not a regular file.", path);
        return false;
    }
    return true;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

const char* ksfu_lastPathEntry(const char* const path)
{
    if(path == NULL)
    {
        return NULL;
    }

    char* lastFile = strrchr(path, '/');
    return lastFile == NULL ? path : lastFile + 1;
}

bool ksfu_writeBytesToFD(const int fd, const char* const bytes, int length)
{
    const char* pos = bytes;
    while(length > 0)
    {
        int bytesWritten = (int)write(fd, pos, (unsigned)length);
        if(bytesWritten == -1)
        {
            KSLOG_ERROR("Could not write to fd %d: %s", fd, strerror(errno));
            return false;
        }
        length -= bytesWritten;
        pos += bytesWritten;
    }
    return true;
}

bool ksfu_readBytesFromFD(const int fd, char* const bytes, int length)
{
    char* pos = bytes;
    while(length > 0)
    {
        int bytesRead = (int)read(fd, pos, (unsigned)length);
        if(bytesRead == -1)
        {
            KSLOG_ERROR("Could not write to fd %d: %s", fd, strerror(errno));
            return false;
        }
        length -= bytesRead;
        pos += bytesRead;
    }
    return true;
}

bool ksfu_readEntireFile(const char* const path, char** data, int* length)
{
    bool isSuccessful = false;
    int bytesRead = 0;
    char* mem = NULL;
    int fd = -1;

    struct stat st;
    if(stat(path, &st) < 0)
    {
        KSLOG_ERROR("Could not stat %s: %s", path, strerror(errno));
        goto done;
    }

    fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open %s: %s", path, strerror(errno));
        goto done;
    }

    mem = malloc((unsigned)st.st_size + 1);
    if(mem == NULL)
    {
        KSLOG_ERROR("Out of memory");
        goto done;
    }

    if(!ksfu_readBytesFromFD(fd, mem, (int)st.st_size))
    {
        goto done;
    }

    bytesRead = (int)st.st_size;
    mem[bytesRead] = '\0';
    isSuccessful = true;

done:
    if(fd >= 0)
    {
        close(fd);
    }
    if(!isSuccessful && mem != NULL)
    {
        free(mem);
        mem = NULL;
    }

    *data = mem;
    if(length != NULL)
    {
        *length = bytesRead;
    }

    return isSuccessful;
}

bool ksfu_writeStringToFD(const int fd, const char* const string)
{
    if(*string != 0)
    {
        int bytesToWrite = (int)strlen(string);
        const char* pos = string;
        while(bytesToWrite > 0)
        {
            int bytesWritten = (int)write(fd, pos, (unsigned)bytesToWrite);
            if(bytesWritten == -1)
            {
                KSLOG_ERROR("Could not write to fd %d: %s",
                            fd, strerror(errno));
                return false;
            }
            bytesToWrite -= bytesWritten;
            pos += bytesWritten;
        }
        return true;
    }
    return false;
}

bool ksfu_writeFmtToFD(const int fd, const char* const fmt, ...)
{
    if(*fmt != 0)
    {
        va_list args;
        va_start(args,fmt);
        bool result = ksfu_writeFmtArgsToFD(fd, fmt, args);
        va_end(args);
        return result;
    }
    return false;
}

bool ksfu_writeFmtArgsToFD(const int fd,
                           const char* const fmt,
                           va_list args)
{
    if(*fmt != 0)
    {
        char buffer[KSFU_WriteFmtBufferSize];
        vsnprintf(buffer, sizeof(buffer), fmt, args);
        return ksfu_writeStringToFD(fd, buffer);
    }
    return false;
}

int ksfu_readLineFromFD(const int fd, char* const buffer, const int maxLength)
{
    char* end = buffer + maxLength - 1;
    *end = 0;
    char* ch;
    for(ch = buffer; ch < end; ch++)
    {
        int bytesRead = (int)read(fd, ch, 1);
        if(bytesRead < 0)
        {
            KSLOG_ERROR("Could not read from fd %d: %s", fd, strerror(errno));
            return -1;
        }
        else if(bytesRead == 0 || *ch == '\n')
        {
            break;
        }
    }
    *ch = 0;
    return (int)(ch - buffer);
}

bool ksfu_makePath(const char* absolutePath)
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

bool ksfu_removeFile(const char* path, bool mustExist)
{
    if(remove(path) < 0)
    {
        if(mustExist || errno != ENOENT)
        {
            KSLOG_ERROR("Could not delete %s: %s", path, strerror(errno));
        }
        return false;
    }
    return true;
}

bool ksfu_deleteContentsOfPath(const char* path)
{
    if(!canDeletePath(path))
    {
        return false;
    }
    
    return deletePathContents(path, false);
}
