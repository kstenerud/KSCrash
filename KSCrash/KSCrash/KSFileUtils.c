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


const char* ksfu_lastPathEntry(const char* const path)
{
    if(path == NULL)
    {
        return NULL;
    }

    char* lastFile = strrchr(path, '/');
    return lastFile == NULL ? path : lastFile + 1;
}

bool ksfu_writeBytesToFD(const int fd,
                         const char* const bytes,
                         ssize_t length)
{
    const char* pos = bytes;
    while(length > 0)
    {
        ssize_t bytesWritten = write(fd, pos, (size_t)length);
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

bool ksfu_readBytesFromFD(const int fd,
                          char* const bytes,
                          ssize_t length)
{
    char* pos = bytes;
    while(length > 0)
    {
        ssize_t bytesRead = read(fd, pos, (size_t)length);
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

bool ksfu_readEntireFile(const char* const path,
                         char** data,
                         size_t* length)
{
    struct stat st;
    if(stat(path, &st) < 0)
    {
        KSLOG_ERROR("Could not stat %s: %s", path, strerror(errno));
        return false;
    }

    void* mem = NULL;
    int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open %s: %s", path, strerror(errno));
        return false;
    }

    mem = malloc((size_t)st.st_size);
    if(mem == NULL)
    {
        KSLOG_ERROR("Out of memory");
        goto failed;
    }

    if(!ksfu_readBytesFromFD(fd, mem, (ssize_t)st.st_size))
    {
        goto failed;
    }

    close(fd);
    *length = (size_t)st.st_size;
    *data = mem;
    return true;

failed:
    close(fd);
    if(mem != NULL)
    {
        free(mem);
    }
    return false;
}

bool ksfu_writeStringToFD(const int fd, const char* const string)
{
    if(*string != 0)
    {
        size_t bytesToWrite = strlen(string);
        const char* pos = string;
        while(bytesToWrite > 0)
        {
            ssize_t bytesWritten = write(fd, pos, bytesToWrite);
            if(bytesWritten == -1)
            {
                KSLOG_ERROR("Could not write to fd %d: %s",
                            fd, strerror(errno));
                return false;
            }
            bytesToWrite -= (size_t)bytesWritten;
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

ssize_t ksfu_readLineFromFD(const int fd,
                            char* const buffer,
                            const int maxLength)
{
    char* end = buffer + maxLength - 1;
    *end = 0;
    char* ch;
    for(ch = buffer; ch < end; ch++)
    {
        ssize_t bytesRead = read(fd, ch, 1);
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
    return ch - buffer;
}
