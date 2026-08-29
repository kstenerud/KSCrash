//
//  KSAtomicFlag.h
//
//  Created by Alexander Cohen on 2026-07-18.
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

#ifndef HDR_KSAtomicFlag_h
#define HDR_KSAtomicFlag_h

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** A lock-free boolean cell.
 *
 * Exists so Swift can hold a flag that a crash-time reader may consult without taking a lock.
 * Swift has no memory model for a raw pointer load, and a suspended lock holder would deadlock
 * a crash handler, so neither a plain `pointee` read nor a lock is usable: the access has to be
 * a genuine relaxed atomic, which on arm64 compiles to the same single instruction a plain load
 * would have while being well defined and clean under TSan.
 *
 * Relaxed ordering is deliberate: the flag guards nothing else, and a momentarily stale value
 * only includes or skips one monitor, which enable/disable already races benignly.
 */
typedef struct {
    _Atomic(uint32_t) value;
} KSAtomicFlag;

static inline void ksatomicflag_set(KSAtomicFlag *flag, bool value)
{
    atomic_store_explicit(&flag->value, value ? 1u : 0u, memory_order_relaxed);
}

static inline bool ksatomicflag_get(const KSAtomicFlag *flag)
{
    return atomic_load_explicit(&flag->value, memory_order_relaxed) != 0;
}

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSAtomicFlag_h
