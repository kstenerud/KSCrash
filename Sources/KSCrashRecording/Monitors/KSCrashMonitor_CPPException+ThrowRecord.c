//
//  KSCrashMonitor_CPPException+ThrowRecord.c
//
//  Created by Mischan Toosarani-Hausberger on 2026-11-23.
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

#include <stdatomic.h>

#include "KSCrashMonitor_CPPException+ThrowRecord.h"

#define RECORD_COUNT 64
#define PROBE_COUNT 4

// Saving the throw stack does not increment the exception's reference count or defer
// its destruction. The owner field is NULL when free, the slot's own address while
// the throwing thread fills the cursor, and the exception's address once the cursor
// and destructor are ready to read.
// Readers must keep the exception alive while using the cursor. At final release,
// libc++abi calls kstr_release, which frees the slot and forwards to the original
// destructor if there is one.
typedef struct {
    KSStackCursor cursor;  // First member so publication can recover the containing record.
    _Atomic(void *) owner;
    ksct_destructor destroy;
} ThrowRecord;

static ThrowRecord g_records[RECORD_COUNT];

static size_t homeSlot(void *object)
{
    uintptr_t key = (uintptr_t)object >> 4;
    return (key ^ (key >> 6) ^ (key >> 12)) % RECORD_COUNT;
}

KSStackCursor *kstr_reserve(void *object)
{
    size_t home = homeSlot(object);

    for (size_t i = 0; i < PROBE_COUNT; i++) {
        ThrowRecord *slot = &g_records[(home + i) % RECORD_COUNT];
        void *expected = NULL;

        // The slot's own address is a reservation sentinel, never a live exception address.
        if (atomic_compare_exchange_strong_explicit(&slot->owner, &expected, slot, memory_order_acq_rel,
                                                    memory_order_relaxed)) {
            return &slot->cursor;
        }
    }

    return NULL;
}

void kstr_publish(KSStackCursor *cursor, void *object, ksct_destructor destructor)
{
    ThrowRecord *slot = (ThrowRecord *)cursor;
    slot->destroy = destructor;
    atomic_store_explicit(&slot->owner, object, memory_order_release);
}

static ThrowRecord *findRecord(void *object)
{
    size_t home = homeSlot(object);

    for (size_t i = 0; i < PROBE_COUNT; i++) {
        ThrowRecord *slot = &g_records[(home + i) % RECORD_COUNT];

        // Earlier slots may have been released since publication. Don't stop at a hole.
        if (atomic_load_explicit(&slot->owner, memory_order_acquire) == object) {
            return slot;
        }
    }

    return NULL;
}

const KSStackCursor *kstr_find(void *object)
{
    ThrowRecord *record = findRecord(object);
    return record != NULL ? &record->cursor : NULL;
}

void kstr_release(void *object)
{
    // Only exceptions with a published record get this destructor, so lookup must succeed.
    ThrowRecord *record = findRecord(object);
    ksct_destructor destroy = record->destroy;

    atomic_store_explicit(&record->owner, NULL, memory_order_release);

    if (destroy != NULL) {
        destroy(object);
    }
}
