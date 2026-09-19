//
//  KSCrashSystem.h
//
//  Created by Alexander Cohen on 2026-01-19.
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

/**
 * @file KSCrashSystem.h
 * @brief Feeds system facts the recorder classifies against.
 */

#ifndef HDR_KSCrashSystem_h
#define HDR_KSCrashSystem_h

#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Record the device's boot time (seconds since epoch) for this run.
 *  Termination classification compares it across runs to detect reboots.
 *  Call before monitors finish enabling; the boot monitor plugin does this.
 *  No effect before install.
 */
void kscm_system_setBootTime(int64_t bootTimestamp);

/** Record the device's total and free storage (bytes) for this run.
 *  The disk monitor plugin records at enable and on each poll.
 *  No effect before install.
 */
void kscm_system_setDiscSpace(uint64_t storageSize, uint64_t freeStorageSize);

struct KSCrash_MonitorContext;

/** Monitor-table event hook: refreshes the run's free storage so a report
 *  carries the value from its own moment. Assign to a plugin table's
 *  addContextualInfoToEvent; safe in any handler context.
 */
void kscm_system_refreshFreeStorageAtEvent(struct KSCrash_MonitorContext *eventContext, void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashSystem_h
