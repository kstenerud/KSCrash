//
//  KSHang.h
//
//  Created by Alexander Cohen on 2025-12-08.
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

#ifndef KSHang_h
#define KSHang_h

#include <mach/task_policy.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/param.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Internal model representing a hang event.
 *
 * This struct captures the state of a detected hang, including timestamps
 * and task roles at the start and end of the hang period.
 */
typedef struct KSHangState {
    /** Monotonic timestamp (in nanoseconds) when the hang started. */
    uint64_t timestamp;

    /** Task role when the hang started. */
    task_role_t role;

    /** Monotonic timestamp (in nanoseconds) of the current/end state. */
    uint64_t endTimestamp;

    /** Task role at the current/end state. */
    task_role_t endRole;

    /** The report ID assigned to this hang. */
    int64_t reportId;

    /** Path to the crash report file on disk. */
    char path[PATH_MAX];

    /** Whether this hang state is currently active. */
    bool active;
} KSHangState;

/** Initialize a hang state with the given start timestamp and role. */
static inline void kshangstate_init(KSHangState *state, uint64_t timestamp, task_role_t role)
{
    memset(state, 0, sizeof(*state));
    state->timestamp = timestamp;
    state->role = role;
    state->endTimestamp = timestamp;
    state->endRole = role;
    state->active = true;
}

/** Clear a hang state to its zero/inactive state. */
static inline void kshangstate_clear(KSHangState *state) { memset(state, 0, sizeof(*state)); }

/** Returns the duration of the hang in seconds. */
static inline double kshangstate_interval(const KSHangState *state)
{
    return (double)(state->endTimestamp - state->timestamp) / 1000000000.0;
}

#ifdef __cplusplus
}
#endif

#endif /* KSHang_h */
