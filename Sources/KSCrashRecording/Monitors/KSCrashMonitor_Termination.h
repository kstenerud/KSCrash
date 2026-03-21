//
//  KSCrashMonitor_Termination.h
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

/* Termination monitor — retroactive detection of why the previous run ended.
 *
 * On launch, reads the previous run's Lifecycle, Resource, and System sidecars
 * to determine whether the process was killed by the OS (OOM, thermal, CPU,
 * battery depletion) or ended due to a system change (OS upgrade, app upgrade,
 * reboot) without any crash handler having run.  If so, injects a user report
 * attributed to the previous run ID.
 *
 * System changes (OS upgrade, app upgrade, reboot) are checked first because
 * they explain an unclean shutdown without it being a crash. Resource reasons
 * are checked next, falling back to "unexplained" if nothing matches.
 */

#ifndef KSCrashMonitor_Termination_h
#define KSCrashMonitor_Termination_h

#include "KSCrashMonitorAPI.h"
#include "KSCrashRunContext.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Access the Termination Monitor API. */
KSCrashMonitorAPI *kscm_termination_getAPI(void);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashMonitor_Termination_h
