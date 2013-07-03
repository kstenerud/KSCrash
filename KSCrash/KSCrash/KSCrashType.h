//
//  KSCrashType.h
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


#ifndef HDR_KSCrashType_h
#define HDR_KSCrashType_h


/** Different ways an application can crash:
 * - Mach kernel exception
 * - Fatal signal
 * - Uncaught C++ exception
 * - Uncaught Objective-C NSException
 * - Deadlock on the main thread
 * - User reported custom exception
 */
typedef enum
{
    KSCrashTypeMachException      = 0x01,
    KSCrashTypeSignal             = 0x02,
    KSCrashTypeCPPException       = 0x04,
    KSCrashTypeNSException        = 0x08,
    KSCrashTypeMainThreadDeadlock = 0x10,
    KSCrashTypeUserReported       = 0x20,
} KSCrashType;

#define KSCrashTypeAll              \
(                                   \
    KSCrashTypeMachException      | \
    KSCrashTypeSignal             | \
    KSCrashTypeCPPException       | \
    KSCrashTypeNSException        | \
    KSCrashTypeMainThreadDeadlock | \
    KSCrashTypeUserReported         \
)

#define KSCrashTypeExperimental     \
(                                   \
    KSCrashTypeMainThreadDeadlock   \
)

#define KSCrashTypeDebuggerUnsafe   \
(                                   \
    KSCrashTypeMachException      | \
    KSCrashTypeNSException          \
)

#define KSCrashTypeAsyncSafe        \
(                                   \
    KSCrashTypeMachException      | \
    KSCrashTypeSignal               \
)

/** Crash types that are safe to enable in a debugger. */
#define KSCrashTypeDebuggerSafe (KSCrashTypeAll & (~KSCrashTypeDebuggerUnsafe))

/** It is safe to catch these kinds of crashes in a production environment.
 * All other crash types should be considered experimental.
 */
#define KSCrashTypeProductionSafe (KSCrashTypeAll & (~KSCrashTypeExperimental))

const char* kscrashtype_name(KSCrashType crashType);

#endif // HDR_KSCrashType_h
