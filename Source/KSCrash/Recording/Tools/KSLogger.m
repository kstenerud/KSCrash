//
//  KSLogger.m
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


#import "KSLogger.h"

/** Write a string to the log.
 *
 * @param str The string to write.
 */
void kslog_i_writeToLog(const char* const str);

/** Interpret the path as a unix file path and return the last path entry.
 * e.g. "/some/path/to/a/file.txt" will result in "file.txt"
 *
 * @param path The path to interpret.
 *
 * @return The last path entry.
 */
const char* kslog_i_lastPathEntry(const char* const path);


// ===========================================================================
#pragma mark - Objective-C -
// ===========================================================================

void i_kslog_logObjCBasic(NSString* fmt, ...)
{
    if(fmt == nil)
    {
        kslog_i_writeToLog("(null)");
        return;
    }

    va_list args;
    va_start(args,fmt);
    CFStringRef entry = CFStringCreateWithFormatAndArguments(NULL, NULL, (__bridge CFStringRef)fmt, args);
    va_end(args);

    kslog_i_writeToLog([(__bridge NSString*)entry UTF8String]);
    kslog_i_writeToLog("\n");

    CFRelease(entry);
}

void i_kslog_logObjC(const char* const level,
                     const char* const file,
                     const int line,
                     const char* const function,
                     NSString* fmt, ...)
{
    if(fmt == nil)
    {
        i_kslog_logObjCBasic(@"%s: %s (%u): %s: (null)",
                             level, kslog_i_lastPathEntry(file), line, function);
    }
    else
    {
        va_list args;
        va_start(args,fmt);
        CFStringRef entry = CFStringCreateWithFormatAndArguments(NULL, NULL, (__bridge CFStringRef)fmt, args);
        va_end(args);

        i_kslog_logObjCBasic(@"%s: %s (%u): %s: %@",
                             level, kslog_i_lastPathEntry(file), line, function, (__bridge id)entry);

        CFRelease(entry);
    }
}
