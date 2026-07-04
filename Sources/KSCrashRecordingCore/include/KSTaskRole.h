//
//  KSTaskRole.h
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

#ifndef KSTaskRole_h
#define KSTaskRole_h

#include <mach/mach_types.h>
#include <stdbool.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Query the current task role from the kernel.
 *
 * Returns the task_role_t value (e.g. TASK_FOREGROUND_APPLICATION).
 * Returns TASK_UNSPECIFIED on tvOS/watchOS or on failure.
 */
int kstaskrole_current(void);

/** Query a specific task's role from the kernel.
 *
 * Unlike kstaskrole_current, failure is reported rather than folded into TASK_UNSPECIFIED:
 * a corpse port's query can genuinely fail, and "unspecified" is also a real role, so a
 * caller recording the role as data must be able to tell the two apart.
 *
 * @param task The task to query (e.g. a corpse port).
 * @param outRole On success, receives the task_role_t value. Untouched on failure.
 * @return true on success, false when the kernel query fails (always false on tvOS/watchOS).
 */
bool kstaskrole_forTask(task_t task, int *outRole);

/** Returns a human-readable string for a task role.
 *
 * @param role The task_role_t value to convert.
 * @return A string representation of the role (e.g., "FOREGROUND_APPLICATION").
 */
const char *kstaskrole_toString(int /*task_role_t*/ role);

#ifdef __cplusplus
}
#endif

#endif  // KSTaskRole_h
