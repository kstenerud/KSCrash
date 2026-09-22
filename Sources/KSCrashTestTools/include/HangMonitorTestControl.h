//
//  HangMonitorTestControl.h
//
//  Created by Alexander Cohen on 2026-09-19.
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

#ifndef HDR_HangMonitorTestControl_h
#define HDR_HangMonitorTestControl_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Arms the hang monitor for the duration of one test, with handler callbacks
 *  that record nothing: hang events publish as they always do, but no report is
 *  written and no store is touched.
 *
 *  A test that wants a hang arms one itself rather than relying on an install,
 *  because the monitor is process-global. Left armed, it freezes every thread
 *  and writes a report for any main-thread stall past its threshold, in
 *  whichever unrelated test happens to be running at the time.
 *
 *  Forces the monitor past its debugger check, so a hang test behaves the same
 *  under Xcode as it does in CI. Pair with `hangtest_disarm` in tearDown.
 */
void hangtest_arm(void);

/** Disables the monitor and waits for its thread to exit. */
void hangtest_disarm(void);

/** Whether the monitor is currently watching the main thread. */
bool hangtest_isArmed(void);

#ifdef __cplusplus
}
#endif

#endif  // HDR_HangMonitorTestControl_h
