//
//  KSZombie.h
//
//  Created by Karl Stenerud on 2012-09-15.
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


/* Poor man's zombie tracking.
 *
 * Benefits:
 * - Very low CPU overhead.
 * - Low memory overhead (user controllable).
 *
 * Limitations:
 * - Not guaranteed to catch all zombies.
 * - Can generate false positives or incorrect class names.
 * - KSZombie itself must be compiled with ARC disabled. You can enable ARC in
 *   your app, but KSZombie must be compiled in a separate library if you do.
 *
 * Internally, it uses a cache which is keyed off the object's address.
 * This gives fast lookups, but at the same time introduces the possibility
 * for collisions. You can mitigate this by choosing a larger cache size.
 * The total memory that will be used is 8 bytes * cache size (16 bytes on
 * 64-bit architectures). You should run your application through a profiler to
 * determine how often objects are deallocated in order to decide how large a
 * cache is optimal for your needs, however you probably shouldn't go lower than
 * 16384.
 */

#ifndef HDR_KSZombie_h
#define HDR_KSZombie_h

#ifdef __cplusplus
extern "C" {
#endif


/** Install the zombie tracker.
 *
 * @param cacheSize The size of the zombie cache. Must be a multiple of 2 and
 *                  greater than 1.
 */
void kszombie_install(size_t cacheSize);

/** Uninstall the zombie tracker.
 */
void kszombie_uninstall(void);

/** Get the class of a deallocated object pointer, if it was tracked.
 *
 * @param object A pointer to a deallocated object.
 *
 * @return The object's class name, or NULL if it wasn't found.
 */
const char* kszombie_className(const void* object);

/** Get the address of the last exception to be deallocated.
 *
 * @return The address, or NULL if no exception has been deallocated yet.
 */
const void* kszombie_lastDeallocedNSExceptionAddress(void);

/** Get the name of the last exception to be deallocated.
 *
 * @return The name.
 */
const char* kszombie_lastDeallocedNSExceptionName(void);

/** Get the reason of the last exception to be deallocated.
 *
 * @return The reason.
 */
const char* kszombie_lastDeallocedNSExceptionReason(void);

/** Get the call stack from the last exception to be deallocated.
 *
 * @return The call stack.
 */
const uintptr_t* kszombie_lastDeallocedNSExceptionCallStack(void);

/** Get the length of the call stack from the last exception to be deallocated.
 *
 * @return The call stack length.
 */
const size_t kszombie_lastDeallocedNSExceptionCallStackLength(void);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSZombie_h
