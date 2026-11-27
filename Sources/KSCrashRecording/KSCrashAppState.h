//
//  KSCrashAppState.h
//
//  Created by Alexander Cohen on 2026-11-27.
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

/* The shared app-state tracker's state, for C code that cannot message the tracker.
 * The tracker writes it in the same step that changes its own state, so it is never
 * behind the tracker, as a copy kept up to date by an observer can be.
 */

#ifndef HDR_KSCrashAppState_h
#define HDR_KSCrashAppState_h

#include <stdbool.h>

#include "KSCrashAppTransitionState.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The shared tracker's current transition state.
 *  Lock-free (atomic load). Safe from any thread.
 *
 *  @return The state the shared tracker is in.
 */
KSCrashAppTransitionState ksapp_currentTransitionState(void);

/** Whether the app has been active at least once this run. Startup lasts until it
 *  has: startup can pass through Foregrounding, which also happens on every return
 *  from the background, so the transition state alone cannot say this.
 *  Lock-free (atomic load). Safe from any thread.
 *
 *  @return true once the shared tracker has been Active.
 */
bool ksapp_hasBeenActive(void);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashAppState_h
