//
//  KSCrashMonitorType.h
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


#ifndef HDR_KSCrashMonitorType_h
#define HDR_KSCrashMonitorType_h

#ifdef __cplusplus
extern "C" {
#endif


/** Various aspects of the system that can be monitored:
 * - Mach kernel exception
 * - Fatal signal
 * - Uncaught C++ exception
 * - Uncaught Objective-C NSException
 * - Deadlock on the main thread
 * - User reported custom exception
 */
typedef enum
{
    KSCrashMonitorTypeMachException      = 0x01,
    KSCrashMonitorTypeSignal             = 0x02,
    KSCrashMonitorTypeCPPException       = 0x04,
    KSCrashMonitorTypeNSException        = 0x08,
    KSCrashMonitorTypeMainThreadDeadlock = 0x10,
    KSCrashMonitorTypeUserReported       = 0x20,
} KSCrashMonitorType;

#define KSCrashMonitorTypeAll              \
(                                   \
    KSCrashMonitorTypeMachException      | \
    KSCrashMonitorTypeSignal             | \
    KSCrashMonitorTypeCPPException       | \
    KSCrashMonitorTypeNSException        | \
    KSCrashMonitorTypeMainThreadDeadlock | \
    KSCrashMonitorTypeUserReported         \
)

#define KSCrashMonitorTypeExperimental     \
(                                   \
    KSCrashMonitorTypeMainThreadDeadlock   \
)

#define KSCrashMonitorTypeDebuggerUnsafe   \
(                                   \
    KSCrashMonitorTypeMachException      | \
    KSCrashMonitorTypeNSException          \
)

#define KSCrashMonitorTypeAsyncSafe        \
(                                   \
    KSCrashMonitorTypeMachException      | \
    KSCrashMonitorTypeSignal               \
)

/** Monitors that are safe to enable in a debugger. */
#define KSCrashMonitorTypeDebuggerSafe (KSCrashMonitorTypeAll & (~KSCrashMonitorTypeDebuggerUnsafe))

/** Monitors that are safe to use in a production environment.
 * All other monitors should be considered experimental.
 */
#define KSCrashMonitorTypeProductionSafe (KSCrashMonitorTypeAll & (~KSCrashMonitorTypeExperimental))

#define KSCrashMonitorTypeNone 0

const char* kscrashmonitortype_name(KSCrashMonitorType monitorType);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashMonitorType_h
