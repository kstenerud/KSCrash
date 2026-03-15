//
//  KSTerminationReason.h
//
//  Created by Alexander Cohen on 2026-03-15.
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

#ifndef KSTerminationReason_h
#define KSTerminationReason_h

#include <stdbool.h>

#include "KSCrashNamespace.h"
#ifdef __OBJC__
#include <Foundation/Foundation.h>
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(_name)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// clang-format off
/** Reason the previous run was terminated. */
#ifdef __OBJC__
typedef NS_ENUM(NSInteger, KSTerminationReason)
#else
enum
#endif
{
    KSTerminationReasonNone = 0,
    // Expected exits
    KSTerminationReasonClean,
    KSTerminationReasonCrash,
    KSTerminationReasonHang,
    KSTerminationReasonFirstLaunch,
    // Resource reasons
    KSTerminationReasonLowBattery,
    KSTerminationReasonMemoryLimit,
    KSTerminationReasonMemoryPressure,
    KSTerminationReasonThermal,
    KSTerminationReasonCPU,
    // System change reasons
    KSTerminationReasonOSUpgrade,
    KSTerminationReasonAppUpgrade,
    KSTerminationReasonReboot,
    // Fallback
    KSTerminationReasonUnexplained,
} NS_SWIFT_NAME(TerminationReason);
#ifndef __OBJC__
typedef int KSTerminationReason;
#endif
// clang-format on

/** Returns the string representation of a termination reason. */
const char *kstermination_reasonToString(KSTerminationReason reason);

/** Whether the given termination reason produces a crash report. */
bool kstermination_producesReport(KSTerminationReason reason);

#ifdef __cplusplus
}
#endif

#endif  // KSTerminationReason_h
