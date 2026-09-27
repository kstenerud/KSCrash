//
//  KSNSExceptionClass.h
//
//  Created by Alexander Cohen on 2026-09-27.
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

#ifndef HDR_KSNSExceptionClass_h
#define HDR_KSNSExceptionClass_h

#include <objc/objc.h>
#include <stdbool.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Whether cls is NSException or inherits from it.
 *
 *  The one test for what counts as an NSException, shared by every path that has to tell one
 *  apart from other thrown types, so that they all reach the same verdict.
 *
 *  It walks the superclass chain through the runtime without sending a message, so asking
 *  initializes no class. The runtime may take its lock and allocate while naming a class, so
 *  this is not for a signal handler or while other threads are suspended.
 *
 *  @param cls The class to test. Nil is not an NSException.
 */
bool ksobjc_isNSExceptionClass(Class cls);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSNSExceptionClass_h
