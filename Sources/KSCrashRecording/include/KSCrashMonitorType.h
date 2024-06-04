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
    KSCrashMonitorTypeNone                 = 0,
    KSCrashMonitorTypeMachException        = 1 << 0,
    KSCrashMonitorTypeSignal               = 1 << 1,
    KSCrashMonitorTypeCPPException         = 1 << 2,
    KSCrashMonitorTypeNSException          = 1 << 3,
    KSCrashMonitorTypeMainThreadDeadlock   = 1 << 4,
    KSCrashMonitorTypeUserReported         = 1 << 5,
    KSCrashMonitorTypeSystem               = 1 << 6,
    KSCrashMonitorTypeApplicationState     = 1 << 7,
    KSCrashMonitorTypeZombie               = 1 << 8,
    KSCrashMonitorTypeMemoryTermination    = 1 << 9,

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

    KSCrashMonitorTypeFatal = (
                               KSCrashMonitorTypeMachException |
                               KSCrashMonitorTypeSignal |
                               KSCrashMonitorTypeCPPException |
                               KSCrashMonitorTypeNSException |
                               KSCrashMonitorTypeMainThreadDeadlock
                               ),

    KSCrashMonitorTypeExperimental = (
                                      KSCrashMonitorTypeMainThreadDeadlock
                                      ),

    KSCrashMonitorTypeDebuggerUnsafe = (
                                        KSCrashMonitorTypeMachException
                                        ),

    KSCrashMonitorTypeAsyncSafe = (
                                   KSCrashMonitorTypeMachException |
                                   KSCrashMonitorTypeSignal
                                   ),

    KSCrashMonitorTypeOptional = (
                                  KSCrashMonitorTypeZombie
                                  ),

    KSCrashMonitorTypeAsyncUnsafe = (
                                     KSCrashMonitorTypeAll & (~KSCrashMonitorTypeAsyncSafe)
                                     ),

    KSCrashMonitorTypeDebuggerSafe = (
                                      KSCrashMonitorTypeAll & (~KSCrashMonitorTypeDebuggerUnsafe)
                                      ),

    KSCrashMonitorTypeProductionSafe = (
                                        KSCrashMonitorTypeAll & (~KSCrashMonitorTypeExperimental)
                                        ),

    KSCrashMonitorTypeProductionSafeMinimal = (
                                               KSCrashMonitorTypeProductionSafe & (~KSCrashMonitorTypeOptional)
                                               ),

    KSCrashMonitorTypeRequired = (
                                  KSCrashMonitorTypeSystem |
                                  KSCrashMonitorTypeApplicationState |
                                  KSCrashMonitorTypeMemoryTermination
                                  ),

    KSCrashMonitorTypeManual = (
                                KSCrashMonitorTypeRequired |
                                KSCrashMonitorTypeUserReported
                                )
}
#ifndef __OBJC__
KSCrashMonitorType
#endif
;

#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashMonitorType_h
