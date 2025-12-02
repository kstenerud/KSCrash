//
// KSBinaryImageCache.h
//
// Created by Gleb Linnik on 2025-04-20.
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

#ifndef HDR_KSBinaryImageCache_h
#define HDR_KSBinaryImageCache_h

#include <mach-o/dyld.h>
#include <stdbool.h>
#include <stdint.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnon-modular-include-in-module"
#include <mach-o/dyld_images.h>
#pragma clang diagnostic pop

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Type that describes a dyld image
 */
typedef struct dyld_image_info ks_dyld_image_info;

/**
 * Cached image address range for fast lookups.
 * Stores pre-computed address bounds, ASLR slide, and segment base.
 */
typedef struct {
    uintptr_t startAddress;   // Image load address (header pointer)
    uintptr_t endAddress;     // End of image address space (exclusive)
    uintptr_t slide;          // Pre-computed ASLR slide
    uintptr_t segmentBase;    // Pre-computed segment base for symbol lookups (vmaddr - fileoff for __LINKEDIT)
    const struct mach_header *_Nullable header;
    const char *_Nullable name;
} KSBinaryImageRange;

/** Initialize the binary image cache.
 * Should be called during KSCrash activation.
 */
void ksbic_init(void);

/**
 * Get a C array of _count_ `ks_dyld_image_info`.
 */
const ks_dyld_image_info *_Nullable ksbic_getImages(uint32_t *_Nullable count);

/**
 * Find the binary image containing the given address.
 *
 * Uses a lazily-populated cache with lock-free exclusive access.
 * The cache pointer is atomically swapped to NULL during use, so concurrent
 * callers fall back to linear scan without blocking.
 *
 * This function is async-signal-safe.
 *
 * @param address The memory address to search for.
 * @param outSlide If not NULL and found, receives the pre-computed ASLR slide.
 * @param outName If not NULL and found, receives the image file path.
 * @return The mach_header of the containing image, or NULL if not found.
 */
const struct mach_header *_Nullable ksbic_findImageForAddress(uintptr_t address,
                                                               uintptr_t *_Nullable outSlide,
                                                               const char *_Nullable *_Nullable outName);

/**
 * Find the binary image containing the given address with full details.
 *
 * Same as ksbic_findImageForAddress but also returns the segment base
 * needed for symbol table lookups.
 *
 * This function is async-signal-safe.
 *
 * @param address The memory address to search for.
 * @param outSlide If not NULL and found, receives the pre-computed ASLR slide.
 * @param outSegmentBase If not NULL and found, receives the segment base for symbol lookups.
 * @param outName If not NULL and found, receives the image file path.
 * @return The mach_header of the containing image, or NULL if not found.
 */
const struct mach_header *_Nullable ksbic_getImageDetailsForAddress(uintptr_t address,
                                                                     uintptr_t *_Nullable outSlide,
                                                                     uintptr_t *_Nullable outSegmentBase,
                                                                     const char *_Nullable *_Nullable outName);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBinaryImageCache_h
