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

/** Write a string to stdout.
 *
 * @param str The string to write.
 */
void kslog_i_writeToStdout(const char* const str);

/** Write a formatted string to stdout.
 *
 * @param fmt The format string, followed by its arguments.
 */
static void writeFmtToStdout(const char* fmt, ...);

/** Write a formatted string to stdout using a vararg list.
 *
 * @param fmt The format string.
 *
 * @param args The variable arguments.
 */
static void writeFmtArgsToStdout(const char* fmt, va_list args);

/** Flush the stdout stream.
 */
static void flushStdout(void);



static inline const char* lastPathEntry(const char* const path)
{
    const char* lastFile = strrchr(path, '/');
    return lastFile == 0 ? path : lastFile + 1;
}

static inline void writeFmtToStdout(const char* fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    writeFmtArgsToStdout(fmt, args);
    va_end(args);
}

#if KSLOGGER_CBufferSize > 0

void kslog_i_writeToStdout(const char* const str)
{
    size_t bytesToWrite = strlen(str);
    const char* pos = str;
    while(bytesToWrite > 0)
    {
        ssize_t bytesWritten = write(STDOUT_FILENO, pos, bytesToWrite);
        if(bytesWritten == -1)
        {
            return;
        }
        bytesToWrite -= (size_t)bytesWritten;
        pos += bytesWritten;
    }
}

static inline void writeFmtArgsToStdout(const char* fmt, va_list args)
{
    if(fmt == NULL)
    {
        kslog_i_writeToStdout("(null)");
    }
    else
    {
        char buffer[KSLOGGER_CBufferSize];
        vsnprintf(buffer, sizeof(buffer), fmt, args);
        kslog_i_writeToStdout(buffer);
    }
}

static inline void flushStdout(void)
{
}

#else // if KSLogger_CBufferSize <= 0

static inline void writeToStdout(const char* const str)
{
    printf("%s", str);
}

static inline void writeFmtArgsToStdout(const char* fmt, va_list args)
{
    if(fmt == NULL)
    {
        writeToStdout("(null)");
    }
    else
    {
        vprintf(fmt, args);
    }
}

static inline void flushStdout(void)
{
    fflush(stdout);
}

#endif


void i_kslog_c_basic(const char* const fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    writeFmtArgsToStdout(fmt, args);
    va_end(args);
    kslog_i_writeToStdout("\n");
    flushStdout();
}

void i_kslog_c(const char* const level,
               const char* const file,
               const int line,
               const char* const function,
               const char* const fmt, ...)
{
    writeFmtToStdout("%s: %s (%u): %s: ",
                     level, lastPathEntry(file), line, function);
    va_list args;
    va_start(args,fmt);
    writeFmtArgsToStdout(fmt, args);
    va_end(args);
    kslog_i_writeToStdout("\n");
    flushStdout();
}
