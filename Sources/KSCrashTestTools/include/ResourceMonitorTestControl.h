//
//  ResourceMonitorTestControl.h
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

#ifndef HDR_ResourceMonitorTestControl_h
#define HDR_ResourceMonitorTestControl_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** The Resource monitor's battery and protected-data values, as its run sidecar holds them. */
typedef struct {
    uint8_t batteryLevel;
    uint8_t batteryState;
    uint64_t batteryUpdatedAtNs;
    uint8_t dataProtectionActive;
    uint64_t dataProtectionUpdatedAtNs;
} ResourceTestSnapshot;

/** Enables the Resource monitor with its run sidecar at `sidecarPath`, for one test.
 *  Pair with `resourcetest_disarm` in tearDown.
 */
void resourcetest_arm(const char *sidecarPath);

/** Disables the Resource monitor and drops its sidecar path. */
void resourcetest_disarm(void);

/** Reads the sidecar the monitor was armed with.
 *
 *  @param sidecarPath The path given to `resourcetest_arm`.
 *  @param outSnapshot Receives the values.
 *  @return Whether the sidecar could be read.
 */
bool resourcetest_read(const char *sidecarPath, ResourceTestSnapshot *outSnapshot);

#ifdef __cplusplus
}
#endif

#endif  // HDR_ResourceMonitorTestControl_h
