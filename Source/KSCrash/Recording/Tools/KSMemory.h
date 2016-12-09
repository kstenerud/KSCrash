//
//  KSMemory.h
//
//  Created by Karl Stenerud on 2012-01-29.
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


/* Utility functions for querying the mach kernel.
 */


#ifndef HDR_ksmemory_h
#define HDR_ksmemory_h

#ifdef __cplusplus
extern "C" {
#endif


#include <stdbool.h>
#include <stdint.h>


// ============================================================================
#pragma mark - General Information -
// ============================================================================

/** Get the total memory that is currently free.
 *
 * @return total free memory.
 */
uint64_t ksmem_freeMemory(void);

/** Get the total memory that is currently usable.
 *
 * @return total usable memory.
 */
uint64_t ksmem_usableMemory(void);


// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Copy memory safely. If the memory is not accessible, returns false
 * rather than crashing.
 *
 * @param src The source location to copy from.
 *
 * @param dst The location to copy to.
 *
 * @param numBytes The number of bytes to copy.
 *
 * @return true if successful.
 */
bool ksmem_copySafely(const void* src, void* dst, int numBytes);

/** Copies up to numBytes of data from src to dest, stopping if memory
 * becomes inaccessible.
 *
 * @param src The source location to copy from.
 *
 * @param dst The location to copy to.
 *
 * @param numBytes The number of bytes to copy.
 *
 * @return The number of bytes actually copied.
 */
int ksmem_copyMaxPossible(const void* src, void* dst, int numBytes);

#ifdef __cplusplus
}
#endif

#endif // HDR_ksmemory_h
