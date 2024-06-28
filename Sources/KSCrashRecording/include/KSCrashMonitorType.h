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

#ifdef __OBJC__
#include <Foundation/Foundation.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(_name)
#endif

// clang-format off

/** Various aspects of the system that can be monitored:
 * - Mach kernel exception
 * - Fatal signal
 * - Uncaught C++ exception
 * - Uncaught Objective-C NSException
 * - Deadlock on the main thread
 * - User reported custom exception
 */
typedef
#ifdef __OBJC__
NS_OPTIONS(NSUInteger, KSCrashMonitorType)
#else /* __OBJC__ */
enum
#endif /* __OBJC__ */
{
    /** No monitoring. */
    KSCrashMonitorTypeNone               = 0,

    /** Monitor Mach kernel exceptions. */
    KSCrashMonitorTypeMachException      = 1 << 0,

    /** Monitor fatal signals. */
    KSCrashMonitorTypeSignal             = 1 << 1,

    /** Monitor uncaught C++ exceptions. */
    KSCrashMonitorTypeCPPException       = 1 << 2,

    /** Monitor uncaught Objective-C NSExceptions. */
    KSCrashMonitorTypeNSException        = 1 << 3,

    /** Detect deadlocks on the main thread. */
    KSCrashMonitorTypeMainThreadDeadlock = 1 << 4,

    /** Monitor user-reported custom exceptions. */
    KSCrashMonitorTypeUserReported       = 1 << 5,

    /** Track and inject system information. */
    KSCrashMonitorTypeSystem             = 1 << 6,

    /** Track and inject application state information. */
    KSCrashMonitorTypeApplicationState   = 1 << 7,

    /** Track memory issues and last zombie NSException. */
    KSCrashMonitorTypeZombie             = 1 << 8,

    /** Monitor memory to detect OOMs at startup. */
    KSCrashMonitorTypeMemoryTermination  = 1 << 9,

    /** Enable all monitoring options. */
    KSCrashMonitorTypeAll = (
                             KSCrashMonitorTypeMachException |
                             KSCrashMonitorTypeSignal |
                             KSCrashMonitorTypeCPPException |
                             KSCrashMonitorTypeNSException |
                             KSCrashMonitorTypeMainThreadDeadlock |
                             KSCrashMonitorTypeUserReported |
                             KSCrashMonitorTypeSystem |
                             KSCrashMonitorTypeApplicationState |
                             KSCrashMonitorTypeZombie |
                             KSCrashMonitorTypeMemoryTermination
                             ),

    /** Fatal monitors track exceptions that lead to error termination of the process.. */
    KSCrashMonitorTypeFatal = (
                               KSCrashMonitorTypeMachException |
                               KSCrashMonitorTypeSignal |
                               KSCrashMonitorTypeCPPException |
                               KSCrashMonitorTypeNSException |
                               KSCrashMonitorTypeMainThreadDeadlock
                               ),

    /** Enable experimental monitoring options. */
    KSCrashMonitorTypeExperimental = KSCrashMonitorTypeMainThreadDeadlock,

    /** Monitor options unsafe for use with a debugger. */
    KSCrashMonitorTypeDebuggerUnsafe = KSCrashMonitorTypeMachException,

    /** Monitor options that are async-safe. */
    KSCrashMonitorTypeAsyncSafe = (KSCrashMonitorTypeMachException | KSCrashMonitorTypeSignal),

    /** Optional monitor options. */
    KSCrashMonitorTypeOptional = KSCrashMonitorTypeZombie,

    /** Monitor options that are async-unsafe. */
    KSCrashMonitorTypeAsyncUnsafe = (KSCrashMonitorTypeAll & (~KSCrashMonitorTypeAsyncSafe)),

    /** Monitor options safe to enable in a debugger. */
    KSCrashMonitorTypeDebuggerSafe = (KSCrashMonitorTypeAll & (~KSCrashMonitorTypeDebuggerUnsafe)),

    /** Monitor options safe for production environments. */
    KSCrashMonitorTypeProductionSafe = (KSCrashMonitorTypeAll & (~KSCrashMonitorTypeExperimental)),

    /** Minimal set of production-safe monitor options. */
    KSCrashMonitorTypeProductionSafeMinimal = (KSCrashMonitorTypeProductionSafe & (~KSCrashMonitorTypeOptional)),

    /** Required monitor options for essential operation. */
    KSCrashMonitorTypeRequired = (
                                  KSCrashMonitorTypeSystem |
                                  KSCrashMonitorTypeApplicationState |
                                  KSCrashMonitorTypeMemoryTermination
                                  ),

    /** Disable automatic reporting; only manual reports are allowed. */
    KSCrashMonitorTypeManual = (KSCrashMonitorTypeRequired | KSCrashMonitorTypeUserReported)
} NS_SWIFT_NAME(MonitorType)
#ifndef __OBJC__
KSCrashMonitorType
#endif
;

// clang-format on

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitorType_h
