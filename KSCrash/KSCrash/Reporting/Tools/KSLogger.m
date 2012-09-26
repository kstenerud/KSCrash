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


#ifndef as_bridge
    #if __has_feature(objc_arc)
        #define as_bridge __bridge
    #else
        #define as_bridge
    #endif
#endif

extern void kslog_i_write(const char* const str);

/** Interpret the path as a unix file path and return the last path entry.
 * e.g. "/some/path/to/a/file.txt" will result in "file.txt"
 *
 * @param path The path to interpret.
 *
 * @return The last path entry.
 */
static inline const char* lastPathEntry(const char* const path)
{
    const char* const lastFile = strrchr(path, '/');
    return lastFile == 0 ? path : lastFile + 1;
}

void i_kslog_logObjCBasic(NSString* fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    CFStringRef entry = CFStringCreateWithFormatAndArguments(NULL, NULL, (as_bridge CFStringRef)fmt, args);
    va_end(args);

    int fd = kslog_getLogFD();
    if(fd == STDOUT_FILENO)
    {
        NSLog(@"%@", (as_bridge id)entry);
    }
    else
    {
        kslog_i_write([(as_bridge NSString*)entry UTF8String]);
        kslog_i_write("\n");
    }

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
                             level, lastPathEntry(file), line, function);
    }
    else
    {
        va_list args;
        va_start(args,fmt);
        CFStringRef entry = CFStringCreateWithFormatAndArguments(NULL, NULL, (as_bridge CFStringRef)fmt, args);
        va_end(args);
        
        i_kslog_logObjCBasic(@"%s: %s (%u): %s: %@",
                             level, lastPathEntry(file), line, function, (as_bridge id)entry);

        CFRelease(entry);
    }
}
