//
//  KSSpinLock.h
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

#ifndef HDR_KSSpinLock_h
#define HDR_KSSpinLock_h

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** A simple spin lock implementation.
 *
 *  This lock is async-signal-safe and can be used in crash handlers.
 *  It uses atomic operations and the CPU pause instruction for efficiency.
 *
 *  WARNING: Spin locks should only be used for very short critical sections.
 *  For longer operations, use proper OS locks (pthread_mutex, os_unfair_lock).
 *
 *  Usage:
 *      static KSSpinLock lock = KSSPINLOCK_INIT;
 *
 *      ks_spinlock_lock(&lock);
 *      // critical section
 *      ks_spinlock_unlock(&lock);
 */
typedef struct {
    _Atomic(uint32_t) _opaque;
} KSSpinLock;

/** Static initializer for KSSpinLock */
#ifndef KSSPINLOCK_INIT
#define KSSPINLOCK_INIT ((KSSpinLock) { 0 })
#endif

/** Initialize a spin lock.
 *
 *  @param lock The spin lock to initialize.
 */
void ks_spinlock_init(KSSpinLock *lock);

/** Acquire the spin lock.
 *
 *  This function will spin until the lock is acquired.
 *
 *  @param lock The spin lock to acquire.
 */
void ks_spinlock_lock(KSSpinLock *lock);

/** Try to acquire the spin lock without blocking.
 *
 *  @param lock The spin lock to try to acquire.
 *  @return true if the lock was acquired, false if it was already held.
 */
bool ks_spinlock_try_lock(KSSpinLock *lock);

/** Try to acquire the spin lock, spinning for a limited number of iterations.
 *
 *  @param lock The spin lock to try to acquire.
 *  @param maxIterations Maximum number of spin iterations before giving up.
 *  @return true if the lock was acquired, false if maxIterations was reached.
 */
bool ks_spinlock_try_lock_with_spin(KSSpinLock *lock, uint32_t maxIterations);

/** Acquire the spin lock with a bounded spin.
 *
 *  This function will spin for a default number of iterations (~50,000)
 *  before giving up. This is useful in async-signal-safe contexts where
 *  indefinite blocking is not acceptable.
 *
 *  @param lock The spin lock to acquire.
 *  @return true if the lock was acquired, false if the spin limit was reached.
 */
bool ks_spinlock_lock_bounded(KSSpinLock *lock);

/** Release the spin lock.
 *
 *  @param lock The spin lock to release.
 */
void ks_spinlock_unlock(KSSpinLock *lock);

#ifdef __cplusplus
}
#endif

#endif /* HDR_KSSpinLock_h */
