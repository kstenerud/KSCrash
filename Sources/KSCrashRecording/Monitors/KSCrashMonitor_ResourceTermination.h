//
//  KSCrashMonitor_ResourceTermination.h
//
//  Created by Alexander Cohen on 2026-03-07.
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

/* ResourceTermination monitor — retroactive detection of OS-killed runs.
 *
 * On launch, reads the previous run's Lifecycle and Resource sidecars to
 * determine whether the process was killed by the OS (OOM, thermal, CPU,
 * battery depletion) without any crash handler having run.  If so, injects
 * a user report attributed to the previous run ID.
 *
 * This replaces the old Memory monitor's OOM breadcrumb approach.
 */

#ifndef KSCrashMonitor_ResourceTermination_h
#define KSCrashMonitor_ResourceTermination_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Reason the OS terminated a previous run. */
typedef enum {
    KSResourceTerminationReasonNone = 0,
    KSResourceTerminationReasonLowBattery,
    KSResourceTerminationReasonMemoryLimit,
    KSResourceTerminationReasonMemoryPressure,
    KSResourceTerminationReasonThermal,
    KSResourceTerminationReasonCPU,
    KSResourceTerminationReasonUnexplained,
} KSResourceTerminationReason;

/** Returns the string representation of a termination reason. */
const char *ksresourcetermination_reasonToString(KSResourceTerminationReason reason);

/** Access the ResourceTermination Monitor API. */
KSCrashMonitorAPI *kscm_resourcetermination_getAPI(void);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashMonitor_ResourceTermination_h
