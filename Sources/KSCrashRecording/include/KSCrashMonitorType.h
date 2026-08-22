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

#include "KSCrashNamespace.h"

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

typedef
#ifdef __OBJC__
NS_OPTIONS(NSUInteger, KSCrashMonitorType)
#else /* __OBJC__ */
enum
#endif /* __OBJC__ */
{
    /** No monitoring. */
    KSCrashMonitorTypeNone               = 0,

    /* =======================================================================
     * Crash detectors (user-configurable)
     * ======================================================================= */

    /** Monitor Mach kernel exceptions. */
    KSCrashMonitorTypeMachException      = 1 << 0,

    /** Monitor fatal signals. */
    KSCrashMonitorTypeSignal             = 1 << 1,

    /** Monitor uncaught C++ exceptions. */
    KSCrashMonitorTypeCPPException       = 1 << 2,

    /** Monitor uncaught Objective-C NSExceptions. */
    KSCrashMonitorTypeNSException        = 1 << 3,

    /** User-reported custom exceptions. Always enabled: it installs nothing
     *  and only gates the reporting entry points. */
    KSCrashMonitorTypeUserReported       = 1 << 5,

    /** Track memory issues and last zombie NSException. */
    KSCrashMonitorTypeZombie             = 1 << 8,

    /** Detect terminations caused by resource exhaustion or system changes. */
    KSCrashMonitorTypeTermination        = 1 << 9,

    /** Tracks hangs as well as hangs that cause a termination (watchdog terminations). */
    KSCrashMonitorTypeHang           = 1 << 10,

    /* =======================================================================
     * Infrastructure (always enabled; not crash detectors, they collect the
     * context every report depends on)
     * ======================================================================= */

    /** Track and inject system information. */
    KSCrashMonitorTypeSystem             = 1 << 6,

    /** Track and inject application state information. */
    KSCrashMonitorTypeApplicationState   = 1 << 7,

    /** Track per-key user data that survives crashes. */
    KSCrashMonitorTypeUserInfo           = 1 << 11,

    /** Resource snapshots (memory, battery, CPU, thermal).
     *  Optionally emits non-fatal EXC_RESOURCE reports on CPU warning/critical
     *  transitions when enableCPUExceptionReporting is set. */
    KSCrashMonitorTypeResource           = 1 << 12,

    /* =======================================================================
     * Sets
     * ======================================================================= */
    /** Every crash detector except Zombie, whose tracking costs CPU and memory. */
    KSCrashMonitorTypeDefault = (
                                 KSCrashMonitorTypeMachException |
                                 KSCrashMonitorTypeSignal |
                                 KSCrashMonitorTypeCPPException |
                                 KSCrashMonitorTypeNSException |
                                 KSCrashMonitorTypeTermination |
                                 KSCrashMonitorTypeHang
                                 ),
    /** Every crash detector. */
    KSCrashMonitorTypeAll = (KSCrashMonitorTypeDefault | KSCrashMonitorTypeZombie),
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
