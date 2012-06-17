//
//  KSCrashReportWriter.h
//
//  Created by Karl Stenerud on 12-01-28.
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


/* Writes a crash report to disk.
 */


#ifndef HDR_KSCrashReportWriter_h
#define HDR_KSCrashReportWriter_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSCrashContext.h"


/** Write a crash report to a file descriptor.
 *
 * @param crashContext Contextual information about the crash and environment.
 *                     The caller must fill this out before passing it in.
 *
 * @param fd The file descriptor to write to.
 */
void kscrash_writeCrashReport(KSCrashContext* crashContext,
                              const char* path);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashReportWriter_h
