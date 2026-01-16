//
// KSUnwindCache.h
//
// Created by Alexander Cohen on 2025-01-16.
//
// Copyright (c) 2012 Karl Stenerud. All rights reserved.
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

#ifndef KSUnwindCache_h
#define KSUnwindCache_h

#include <mach-o/loader.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "KSPlatformSpecificDefines.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Cached unwind information for a single binary image.
 * Contains pointers to __unwind_info and __eh_frame sections.
 */
typedef struct {
    const mach_header_t *header;  // Mach-O header for this image

    // Compact unwind info (__TEXT,__unwind_info)
    const void *unwindInfo;  // Pointer to __unwind_info section data
    size_t unwindInfoSize;   // Size of __unwind_info section

    // DWARF eh_frame (__TEXT,__eh_frame)
    const void *ehFrame;  // Pointer to __eh_frame section data
    size_t ehFrameSize;   // Size of __eh_frame section

    // Pre-computed image slide for address calculations
    uintptr_t slide;

    // Flags indicating available unwind data
    bool hasCompactUnwind;  // True if __unwind_info is present
    bool hasEhFrame;        // True if __eh_frame is present
} KSUnwindImageInfo;

/**
 * Get cached unwind information for a binary image.
 *
 * This function uses a lock-free cache to store unwind section pointers
 * for binary images. If the image is not in the cache, it will be
 * looked up and added.
 *
 * The returned pointer is valid as long as the binary image remains loaded.
 * The caller should NOT free the returned pointer.
 *
 * This function is async-signal-safe.
 *
 * @param header The mach_header of the binary image.
 * @return Pointer to cached unwind info, or NULL if the image has no unwind data.
 */
const KSUnwindImageInfo *ksunwindcache_getInfoForImage(const mach_header_t *header);

/**
 * Get cached unwind information for an address.
 *
 * This is a convenience function that first finds the binary image
 * containing the address, then returns its unwind info.
 *
 * This function is async-signal-safe.
 *
 * @param address The memory address to look up.
 * @return Pointer to cached unwind info, or NULL if not found or no unwind data.
 */
const KSUnwindImageInfo *ksunwindcache_getInfoForAddress(uintptr_t address);

/**
 * Clear the unwind cache.
 *
 * This is primarily useful for testing purposes.
 */
void ksunwindcache_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* KSUnwindCache_h */
