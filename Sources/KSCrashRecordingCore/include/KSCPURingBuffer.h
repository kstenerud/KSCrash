//
//  KSCPURingBuffer.h
//
//  Created by Alexander Cohen on 2026-04-09.
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

// Fixed-capacity ring buffer of CPU time samples for sliding-window averages.
// Not thread-safe — caller must serialize access.

#ifndef KSCPURingBuffer_h
#define KSCPURingBuffer_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** A single sample in the ring buffer. */
typedef struct {
    uint64_t wallNs;     // monotonic (continuous) nanoseconds
    uint64_t cpuTimeNs;  // cumulative user + system CPU nanoseconds
} KSCPURingSample;

/** Maximum number of samples the ring buffer can hold. */
#define KSCPU_RING_BUFFER_CAPACITY 48

/** Ring buffer of CPU time samples. */
typedef struct {
    KSCPURingSample entries[KSCPU_RING_BUFFER_CAPACITY];
    uint32_t head;   // next write position
    uint32_t count;  // number of valid entries (0..CAPACITY)
} KSCPURingBuffer;

/** Initialize (or reset) a ring buffer to empty. */
void kscpuring_init(KSCPURingBuffer *ring);

/** Push a new sample into the ring buffer. */
void kscpuring_push(KSCPURingBuffer *ring, KSCPURingSample sample);

/** Number of valid entries. */
uint32_t kscpuring_count(const KSCPURingBuffer *ring);

/** Get the newest sample. Returns a zero sample if the ring is empty. */
KSCPURingSample kscpuring_newest(const KSCPURingBuffer *ring);

/** Find the oldest sample whose wallNs is at or before (newestWallNs - windowNs).
 *  Falls back to the oldest available sample if the ring hasn't filled that far.
 *  Returns a zero sample if the ring is empty. */
KSCPURingSample kscpuring_oldestForWindow(const KSCPURingBuffer *ring, uint64_t windowNs);

/** Compute average CPU fraction over a window.
 *  Returns 0 if the ring doesn't span the full window or has fewer than 2 entries.
 *  Result is normalized by coreCount: 1.0 = 100% of all cores. */
double kscpuring_averageForWindow(const KSCPURingBuffer *ring, uint64_t windowNs, uint8_t coreCount);

#ifdef __cplusplus
}
#endif

#endif  // KSCPURingBuffer_h
