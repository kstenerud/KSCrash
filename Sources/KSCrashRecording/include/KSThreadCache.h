//
//  KSThreadCache.h
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

/** Maintains a cache of thread information that would be difficult to retrieve
 * during a crash. This includes thread names and dispatch queue names.
 *
 * The cache uses lock-free atomic operations for thread safety. A background
 * thread periodically updates the cache, and crash handlers can acquire
 * exclusive access using kstc_freeze/kstc_unfreeze.
 *
 * Usage pattern:
 *   kstc_freeze();          // Acquire exclusive access
 *   // ... call kstc_getAllThreads, kstc_getThreadName, kstc_getQueueName ...
 *   kstc_unfreeze();        // Release access
 */

#ifndef KSThreadCache_h
#define KSThreadCache_h

#include "KSCrashNamespace.h"
#include "KSThread.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Initialize the thread cache and start the background monitoring thread.
 *
 * @param pollingIntervalInSeconds How often to refresh the thread cache.
 */
void kstc_init(int pollingIntervalInSeconds);

/** Freeze the cache to prevent updates during crash handling.
 *
 * This acquires exclusive access to the cache using lock-free atomics.
 * Must be paired with kstc_unfreeze() when done.
 */
void kstc_freeze(void);

/** Unfreeze the cache to allow updates to resume.
 *
 * Releases exclusive access acquired by kstc_freeze().
 */
void kstc_unfreeze(void);

/** Set whether to search for dispatch queue names.
 *
 * Queue name lookup can be expensive, so it's disabled by default.
 *
 * @param searchQueueNames true to enable queue name lookup.
 */
void kstc_setSearchQueueNames(bool searchQueueNames);

/** Get all cached mach threads.
 *
 * @param threadCount Output parameter for number of threads (can be NULL).
 * @return Array of mach thread IDs, or NULL if cache unavailable.
 */
KSThread *kstc_getAllThreads(int *threadCount);

/** Get the name of a thread from the cache.
 *
 * @param thread The mach thread to look up.
 * @return The thread name, or NULL if not found.
 */
const char *kstc_getThreadName(KSThread thread);

/** Get the dispatch queue name of a thread from the cache.
 *
 * @param thread The mach thread to look up.
 * @return The queue name, or NULL if not found or queue names not enabled.
 */
const char *kstc_getQueueName(KSThread thread);

#ifdef __cplusplus
}
#endif

#endif /* KSThreadCache_h */
