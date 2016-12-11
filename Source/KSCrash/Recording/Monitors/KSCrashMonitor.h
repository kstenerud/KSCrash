//
//  KSCrashMonitor.h
//
//  Created by Karl Stenerud on 2012-02-12.
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


/** Keeps watch for crashes and informs via callback when on occurs.
 */


#ifndef HDR_KSCrashMonitor_h
#define HDR_KSCrashMonitor_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSCrashMonitorType.h"

struct KSCrash_MonitorContext;

/** Install monitors.
 *
 * @param context Contextual information for the crash handlers.
 *
 * @param monitorTypers The crash types to install handlers for.
 *
 * @param onCrash Function to call when a crash occurs.
 *
 * @return which crash handlers were installed successfully.
 */
KSCrashMonitorType kscrashmonitor_installWithContext(struct KSCrash_MonitorContext* context,
                                                KSCrashMonitorType monitorTypers,
                                                void (*onCrash)(void));

/** Uninstall monitors.
 *
 * @param monitorTypers The crash types to install handlers for.
 */
void kscrashmonitor_uninstall(KSCrashMonitorType monitorTypers);


// Internal API

/** Prepare the context for handling a new crash.
 */
void kscrashmonitor_beginHandlingCrash(struct KSCrash_MonitorContext* context);

/** Clear a monitor context.
 */
void kscrashmonitor_clearContext(struct KSCrash_MonitorContext* context);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashMonitor_h
