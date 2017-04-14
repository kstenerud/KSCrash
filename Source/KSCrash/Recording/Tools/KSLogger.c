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
#include "KSSystemCapabilities.h"

// ===========================================================================
#pragma mark - Common -
// ===========================================================================

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>


// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


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

/** Where console logs will be written */
static char g_logFilename[1024];

/** Whether logs should be written to stdout */
static bool g_logToStdout = false;

/** Write a formatted string to the log.
 *
 * @param fmt The format string, followed by its arguments.
 */
static void writeFmtToLog(const char* fmt, ...);

/** Write a formatted string to the log using a vararg list.
 *
 * @param fmt The format string.
 *
 * @param args The variable arguments.
 */
static void writeFmtArgsToLog(const char* fmt, va_list args);

/** Flush the log stream.
 */
static void flushLog(void);


static inline const char* lastPathEntry(const char* const path)
{
    const char* lastFile = strrchr(path, '/');
    return lastFile == 0 ? path : lastFile + 1;
}

static inline void writeFmtToLog(const char* fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    writeFmtArgsToLog(fmt, args);
    va_end(args);
}

#if KSLOGGER_CBufferSize > 0

/** The file descriptor where log entries get written. */
static int g_fd = -1;


static void writeToLog(const char* const str)
{
    if(g_fd >= 0)
    {
        int bytesToWrite = (int)strlen(str);
        const char* pos = str;
        while(bytesToWrite > 0)
        {
            int bytesWritten = (int)write(g_fd, pos, (unsigned)bytesToWrite);
            unlikely_if(bytesWritten == -1)
            {
                break;
            }
            bytesToWrite -= bytesWritten;
            pos += bytesWritten;
        }
    }
    if(g_logToStdout)
    {
        write(STDOUT_FILENO, str, strlen(str));
    }
}

static inline void writeFmtArgsToLog(const char* fmt, va_list args)
{
    unlikely_if(fmt == NULL)
    {
        writeToLog("(null)");
    }
    else
    {
        char buffer[KSLOGGER_CBufferSize];
        vsnprintf(buffer, sizeof(buffer), fmt, args);
        writeToLog(buffer);
    }
}

static inline void flushLog(void)
{
    // Nothing to do.
}

static inline void setLogFD(int fd)
{
    if(g_fd >= 0 && g_fd != STDOUT_FILENO && g_fd != STDERR_FILENO && g_fd != STDIN_FILENO)
    {
        close(g_fd);
    }
    g_fd = fd;
}

bool kslog_setLogFilename(const char* filename, bool overwrite)
{
    static int fd = -1;
    if(filename != NULL)
    {
        int openMask = O_WRONLY | O_CREAT;
        if(overwrite)
        {
            openMask |= O_TRUNC;
        }
        fd = open(filename, openMask, 0644);
        unlikely_if(fd < 0)
        {
            writeFmtToLog("KSLogger: Could not open %s: %s", filename, strerror(errno));
            return false;
        }
        if(filename != g_logFilename)
        {
            strncpy(g_logFilename, filename, sizeof(g_logFilename));
        }
    }
    
    setLogFD(fd);
    return true;
}

#else // if KSLogger_CBufferSize <= 0

static FILE* g_file = NULL;

static inline void setLogFD(FILE* file)
{
    if(g_file != NULL && g_file != stdout && g_file != stderr && g_file != stdin)
    {
        fclose(g_file);
    }
    g_file = file;
}

void writeToLog(const char* const str)
{
    if(g_file != NULL)
    {
        fprintf(g_file, "%s", str);
    }
    if(g_logToStdout)
    {
        fprintf(stdout, "%s", str);
    }
}

static inline void writeFmtArgsToLog(const char* fmt, va_list args)
{
    if(fmt == NULL)
    {
        writeToLog("(null)");
    }
    else
    {
        if(g_file != NULL)
        {
            vfprintf(g_file, fmt, args);
        }
        if(g_logToStdout)
        {
            vfprintf(stdout, fmt, args);
        }
    }
}

static inline void flushLog(void)
{
    fflush(g_file);
}

bool kslog_setLogFilename(const char* filename, bool overwrite)
{
    static FILE* file = NULL;
    FILE* oldFile = file;
    if(filename != NULL)
    {
        file = fopen(filename, overwrite ? "wb" : "ab");
        unlikely_if(file == NULL)
        {
            writeFmtToLog("KSLogger: Could not open %s: %s", filename, strerror(errno));
            return false;
        }
    }
    if(filename != g_logFilename)
    {
        strncpy(g_logFilename, filename, sizeof(g_logFilename));
    }

    if(oldFile != NULL)
    {
        fclose(oldFile);
    }

    setLogFD(file);
    return true;
}

#endif

bool kslog_clearLogFile()
{
    return kslog_setLogFilename(g_logFilename, true);
}

void kslog_setLogToStdout(bool enabled)
{
    g_logToStdout = enabled;
}

// ===========================================================================
#pragma mark - C -
// ===========================================================================

static void i_kslog_log(const char* const level,
                        const char* const file,
                        const int line,
                        const char* const function,
                        const char* const fmt, va_list args)
{
    if(level && file && line >= 0 && function)
    {
        writeFmtToLog("%s: %s (%u): %s: ", level, lastPathEntry(file), line, function);
    }
    writeFmtArgsToLog(fmt, args);
    writeToLog("\n");
    flushLog();
}

void i_kslog_logC(const char* const level,
                  const char* const file,
                  const int line,
                  const char* const function,
                  const char* const fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    i_kslog_log(level, file, line, function, fmt, args);
    va_end(args);
}


// ===========================================================================
#pragma mark - Objective-C -
// ===========================================================================

#if KSCRASH_HAS_OBJC
#include <CoreFoundation/CoreFoundation.h>

void i_kslog_logObjC(const char* const level,
                     const char* const file,
                     const int line,
                     const char* const function,
                     CFStringRef fmt, ...)
{
    if(fmt == NULL)
    {
        i_kslog_logC(level, file, line, function, "(null)");
    }
    else
    {
        int bufferLength = (int)CFStringGetLength(fmt) * 4 + 1;
        char* stringBuffer = malloc((unsigned)bufferLength);
        if(CFStringGetCString(fmt, stringBuffer, (CFIndex)bufferLength, kCFStringEncodingUTF8))
        {
            va_list args;
            va_start(args,fmt);
            i_kslog_log(level, file, line, function, stringBuffer, args);
            va_end(args);
        }
        else
        {
            i_kslog_logC(level, file, line, function,
                "Could not convert log string to UTF-8. No logging performed.");
        }
        free(stringBuffer);
    }
}
#endif // KSCRASH_HAS_OBJC
