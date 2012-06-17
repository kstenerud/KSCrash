//
//  KSCrashHandler_Common.h
//
//  Created by Karl Stenerud on 12-02-12.
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


/* Functions common to all signal/exception handlers.
 */


#ifndef HDR_KSCrashHandler_Common_h
#define HDR_KSCrashHandler_Common_h

#ifdef __cplusplus
extern "C" {
#endif


/** Uninstall all signal and exception handlers. */
void kscrash_uninstallAllHandlers(void);

/** Uninstall all signal and exception handlers that can be uninstalled
 * in an async-safe manner.
 */
void kscrash_uninstallAsyncSafeHandlers(void);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashHandler_Common_h
