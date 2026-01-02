//
//  KSSpinLock.c
//
//  Created by Alexander Cohen on 2025-12-29.
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

#include "KSSpinLock.h"

#include <stdatomic.h>

// ============================================================================
#pragma mark - CPU Pause -
// ============================================================================

/** CPU pause/yield hint for spin-wait loops.
 *
 *  This is more efficient than busy-spinning as it:
 *  - Reduces power consumption during the spin
 *  - Improves performance on hyperthreaded CPUs
 *  - Is async-signal-safe (just a CPU instruction)
 *
 *  The memory clobber acts as a compiler barrier, preventing
 *  the compiler from reordering or caching memory accesses
 *  across this point.
 */
static inline void ks_cpu_pause(void)
{
#if defined(__x86_64__) || defined(__i386__)
    __asm__ volatile("pause" ::: "memory");
#elif defined(__arm64__) || defined(__aarch64__) || defined(__arm__)
    __asm__ volatile("yield" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}

// ============================================================================
#pragma mark - Constants -
// ============================================================================

/** Default maximum spin iterations for bounded lock acquisition.
 *  At ~50-150 cycles per iteration on a 3GHz CPU, this gives ~1-2.5ms of spin time.
 */
static const uint32_t kSpinLockBoundedMaxIterations = 50000;

// ============================================================================
#pragma mark - API -
// ============================================================================

void ks_spinlock_init(KSSpinLock *lock) { atomic_store_explicit(&lock->_opaque, 0, memory_order_relaxed); }

void ks_spinlock_lock(KSSpinLock *lock)
{
    for (;;) {
        // TTAS: Spin on relaxed read first (cache-friendly, no invalidation)
        while (atomic_load_explicit(&lock->_opaque, memory_order_relaxed) != 0) {
            ks_cpu_pause();
        }
        // Only attempt exchange when lock appears free
        if (atomic_exchange_explicit(&lock->_opaque, 1, memory_order_acquire) == 0) {
            return;
        }
    }
}

bool ks_spinlock_try_lock(KSSpinLock *lock)
{
    return atomic_exchange_explicit(&lock->_opaque, 1, memory_order_acquire) == 0;
}

bool ks_spinlock_try_lock_with_spin(KSSpinLock *lock, uint32_t maxIterations)
{
    for (uint32_t i = 0; i < maxIterations; i++) {
        // TTAS: Check with relaxed read first
        if (atomic_load_explicit(&lock->_opaque, memory_order_relaxed) == 0) {
            if (atomic_exchange_explicit(&lock->_opaque, 1, memory_order_acquire) == 0) {
                return true;
            }
        }
        ks_cpu_pause();
    }
    return false;
}

bool ks_spinlock_lock_bounded(KSSpinLock *lock)
{
    return ks_spinlock_try_lock_with_spin(lock, kSpinLockBoundedMaxIterations);
}

void ks_spinlock_unlock(KSSpinLock *lock) { atomic_store_explicit(&lock->_opaque, 0, memory_order_release); }
