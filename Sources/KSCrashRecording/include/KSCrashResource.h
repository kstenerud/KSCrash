//
//  KSCrashResource.h
//
//  Created by Alexander Cohen on 2026-11-22.
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
 * @file KSCrashResource.h
 * @brief Feeds resource values the recorder cannot read without UIKit.
 */

#ifndef HDR_KSCrashResource_h
#define HDR_KSCrashResource_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Battery charging state, with `UIDeviceBatteryState`'s values. */
typedef enum {
    KSCrashBatteryStateUnknown = 0,
    KSCrashBatteryStateUnplugged = 1,
    KSCrashBatteryStateCharging = 2,
    KSCrashBatteryStateFull = 3,
} KSCrashBatteryState;

/** Record the battery's level and state for this run.
 *  No effect before install, or while the Resource monitor is disabled.
 *
 *  @param levelPercent The charge, 0 to 100, or 255 when it is not known.
 *  @param state The charging state.
 */
void kscm_resource_setBattery(uint8_t levelPercent, KSCrashBatteryState state);

/** Record whether protected data is available (the device is unlocked) for this run. Only the
 *  starting value is needed: later changes are recorded without another call.
 *  No effect before install, or while the Resource monitor is disabled.
 *
 *  @param isAvailable Whether protected data is available.
 */
void kscm_resource_setProtectedDataAvailable(bool isAvailable);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashResource_h
