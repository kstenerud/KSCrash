//
//  KSLogger.c
//
//  Created by Karl Stenerud on 11-06-25.
//
//  Copyright (c) 2011 Karl Stenerud. All rights reserved.
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


#include "KSLogger.h"

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>


/** The buffer size to use when writing log entries.
 *
 * If this value is > 0, any log entries that expand beyond this length will
 * be truncated.
 * If this value = 0, the logging system will dynamically allocate memory
 * and never truncate. However, the log functions won't be async-safe.
 *
 * Unless you're logging from within signal handlers, it's safe to set it to 0.
 */
#ifndef KSLOGGER_CBufferSize
    #define KSLOGGER_CBufferSize 1024
#endif


/** Interpret the path as a unix file path and return the last path entry.
 * e.g. "/some/path/to/a/file.txt" will result in "file.txt"
 *
 * @param path The path to interpret.
 *
 * @return The last path entry.
 */
static const char* lastPathEntry(const char* const path);

/** Write a string to the log.
 *
 * @param str The string to write.
 */
void kslog_i_write(const char* const str);

/** Write a formatted string to the log.
 *
 * @param fmt The format string, followed by its arguments.
 */
static void writeFmt(const char* fmt, ...);

/** Write a formatted string to the log using a vararg list.
 *
 * @param fmt The format string.
 *
 * @param args The variable arguments.
 */
static void writeFmtArgs(const char* fmt, va_list args);

/** Flush the log stream.
 */
static void flushLog(void);


static inline const char* lastPathEntry(const char* const path)
{
    const char* lastFile = strrchr(path, '/');
    return lastFile == 0 ? path : lastFile + 1;
}

static inline void writeFmt(const char* fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    writeFmtArgs(fmt, args);
    va_end(args);
}

#if KSLOGGER_CBufferSize > 0

/** The file descriptor where log entries get written. */
static int g_fd = STDOUT_FILENO;


void kslog_i_write(const char* const str)
{
    size_t bytesToWrite = strlen(str);
    const char* pos = str;
    while(bytesToWrite > 0)
    {
        ssize_t bytesWritten = write(g_fd, pos, bytesToWrite);
        if(bytesWritten == -1)
        {
            return;
        }
        bytesToWrite -= (size_t)bytesWritten;
        pos += bytesWritten;
    }
}

static inline void writeFmtArgs(const char* fmt, va_list args)
{
    if(fmt == NULL)
    {
        kslog_i_write("(null)");
    }
    else
    {
        char buffer[KSLOGGER_CBufferSize];
        vsnprintf(buffer, sizeof(buffer), fmt, args);
        kslog_i_write(buffer);
    }
}

static inline void flushLog(void)
{
}

bool kslog_setLogFilename(const char* filename, bool overwrite)
{
    if(filename == NULL)
    {
        g_fd = STDOUT_FILENO;
        return true;
    }

    int openMask = O_WRONLY | O_CREAT;
    if(overwrite)
    {
        openMask |= O_TRUNC;
    }
    int fd = open(filename, openMask, 0644);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open %s: %s", filename, strerror(errno));
        return false;
    }

    if(g_fd >= 0 && g_fd != STDOUT_FILENO && g_fd != STDERR_FILENO && g_fd != STDIN_FILENO)
    {
        close(g_fd);
    }
    g_fd = fd;
    return true;
}

#else // if KSLogger_CBufferSize <= 0

static FILE* g_file;

void kslog_i_write(const char* const str)
{
    fprintf(g_file, "%s", str);
}

static inline void writeFmtArgs(const char* fmt, va_list args)
{
    if(fmt == NULL)
    {
        kslog_i_write("(null)");
    }
    else
    {
        vfprintf(g_file, fmt, args);
    }
}

static inline void flushLog(void)
{
    fflush(g_file);
}

bool kslog_setLogFilename(const char* filename, bool overwrite)
{
    if(filename == NULL)
    {
        g_file = stdout;
    }

    FILE* file = fopen(filename, overwrite ? "wb" : "ab");
    if(file == NULL)
    {
        KSLOG_ERROR("Could not open %s: %s", filename, strerror(errno));
        return false;
    }

    if(g_file != stdout && g_file != stderr && g_file != stdin)
    {
        fclose(g_file);
    }
    g_file = file;
    return true;
}

#endif


void i_kslog_logCBasic(const char* const fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    writeFmtArgs(fmt, args);
    va_end(args);
    kslog_i_write("\n");
    flushLog();
}

void i_kslog_logC(const char* const level,
                  const char* const file,
                  const int line,
                  const char* const function,
                  const char* const fmt, ...)
{
    writeFmt("%s: %s (%u): %s: ", level, lastPathEntry(file), line, function);
    va_list args;
    va_start(args,fmt);
    writeFmtArgs(fmt, args);
    va_end(args);
    kslog_i_write("\n");
    flushLog();
}
