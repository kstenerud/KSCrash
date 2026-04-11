//
//  KSCPURingBuffer.c
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

#include "KSCPURingBuffer.h"

#include <string.h>

void kscpuring_init(KSCPURingBuffer *ring) { memset(ring, 0, sizeof(*ring)); }

void kscpuring_push(KSCPURingBuffer *ring, KSCPURingSample sample)
{
    ring->entries[ring->head] = sample;
    ring->head = (ring->head + 1) % KSCPU_RING_BUFFER_CAPACITY;
    if (ring->count < KSCPU_RING_BUFFER_CAPACITY) {
        ring->count++;
    }
}

uint32_t kscpuring_count(const KSCPURingBuffer *ring) { return ring->count; }

KSCPURingSample kscpuring_newest(const KSCPURingBuffer *ring)
{
    if (ring->count == 0) {
        return (KSCPURingSample) { 0 };
    }
    uint32_t idx = (ring->head + KSCPU_RING_BUFFER_CAPACITY - 1) % KSCPU_RING_BUFFER_CAPACITY;
    return ring->entries[idx];
}

KSCPURingSample kscpuring_oldestForWindow(const KSCPURingBuffer *ring, uint64_t windowNs)
{
    if (ring->count == 0) {
        return (KSCPURingSample) { 0 };
    }

    uint32_t oldestIdx = (ring->head + KSCPU_RING_BUFFER_CAPACITY - ring->count) % KSCPU_RING_BUFFER_CAPACITY;
    KSCPURingSample best = ring->entries[oldestIdx];

    KSCPURingSample newest = kscpuring_newest(ring);
    if (windowNs >= newest.wallNs) {
        return best;
    }

    uint64_t cutoffNs = newest.wallNs - windowNs;
    for (uint32_t i = 0; i < ring->count; i++) {
        uint32_t idx = (oldestIdx + i) % KSCPU_RING_BUFFER_CAPACITY;
        if (ring->entries[idx].wallNs <= cutoffNs) {
            best = ring->entries[idx];
        } else {
            break;
        }
    }
    return best;
}

double kscpuring_averageForWindow(const KSCPURingBuffer *ring, uint64_t windowNs, uint8_t coreCount)
{
    if (ring->count < 2 || coreCount == 0) {
        return 0;
    }

    KSCPURingSample newest = kscpuring_newest(ring);
    KSCPURingSample oldest = kscpuring_oldestForWindow(ring, windowNs);

    if (oldest.wallNs == 0 || oldest.wallNs == newest.wallNs) {
        return 0;
    }

    double wallDelta = (double)(newest.wallNs - oldest.wallNs);
    if (wallDelta < (double)windowNs) {
        return 0;
    }

    double cpuDelta = (double)(newest.cpuTimeNs - oldest.cpuTimeNs);
    return (cpuDelta / wallDelta) / coreCount;
}
