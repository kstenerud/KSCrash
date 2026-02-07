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
 * Callback type for image addition notifications.
 * Same signature as _dyld_register_func_for_add_image callbacks.
 *
 * @param mh The mach_header of the added image.
 * @param vmaddr_slide The ASLR slide of the image.
 */
typedef void (*ksbic_imageCallback)(const struct mach_header *_Nonnull mh, intptr_t vmaddr_slide);

/**
 * Register a callback to be invoked when new images are loaded.
 *
 * The callback will be called for each image as it is added to the process.
 * This uses the dyld notification mechanism internally.
 *
 * Note: Only one callback can be registered at a time. Registering a new
 * callback replaces any previously registered callback.
 *
 * @param callback The callback function to invoke, or NULL to unregister.
 */
void ksbic_registerForImageAdded(ksbic_imageCallback _Nullable callback);

/** Initialize the binary image cache.
 * @deprecated Use ksdl_init() instead, which initializes both symbol and image caches.
 */
__attribute__((deprecated("Use ksdl_init() instead"))) void ksbic_init(void);

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
const struct mach_header *_Nullable ksbic_findImageForAddress(uintptr_t address, uintptr_t *_Nullable outSlide,
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
const struct mach_header *_Nullable ksbic_getImageDetailsForAddress(uintptr_t address, uintptr_t *_Nullable outSlide,
                                                                    uintptr_t *_Nullable outSegmentBase,
                                                                    const char *_Nullable *_Nullable outName);

/**
 * Compute the ASLR slide for a Mach-O image from its header.
 *
 * The slide is calculated by finding the __TEXT segment and computing
 * the difference between the load address and the segment's vmaddr.
 *
 * This function is async-signal-safe and does not use locks.
 *
 * @param header The mach_header of the image.
 * @return The ASLR slide, or 0 if the header is NULL or __TEXT segment not found.
 */
intptr_t ksbic_getImageSlide(const struct mach_header *_Nullable header);

/**
 * Cached unwind information for a binary image.
 */
typedef struct {
    const struct mach_header *_Nullable header;
    const void *_Nullable unwindInfo;
    size_t unwindInfoSize;
    const void *_Nullable ehFrame;
    size_t ehFrameSize;
    uintptr_t slide;
    bool hasCompactUnwind;
    bool hasEhFrame;
} KSBinaryImageUnwindInfo;

/**
 * Get the mach_header of the main executable.
 *
 * The main executable is always the first entry in the dyld image list.
 *
 * @return The mach_header of the main executable, or NULL if not available.
 */
const struct mach_header *_Nullable ksbic_getAppHeader(void);

/**
 * Get the mach_header of the dyld shared library.
 *
 * dyld is not included in the normal image list returned by ksbic_getImages().
 * This function provides access to dyld's header for cache lookups and
 * binary image reporting.
 *
 * @return The mach_header of dyld, or NULL if not available.
 */
const struct mach_header *_Nullable ksbic_getDyldHeader(void);

/**
 * Get the LC_UUID for a binary image.
 *
 * Returns a pointer to the 16-byte UUID in the Mach-O header, or NULL if not found.
 * The pointer is valid for the lifetime of the loaded image.
 *
 * This function is async-signal-safe.
 *
 * @param header The mach_header of the image.
 * @return Pointer to 16-byte UUID data, or NULL if not found.
 */
const uint8_t *_Nullable ksbic_getUUIDForHeader(const struct mach_header *_Nullable header);

/**
 * Get cached unwind information for a binary image.
 *
 * This function is async-signal-safe.
 *
 * @param header The mach_header of the image.
 * @param outInfo If not NULL and found, receives the cached unwind info.
 * @return true if the image was found, false otherwise.
 */
bool ksbic_getUnwindInfoForHeader(const struct mach_header *_Nullable header,
                                  KSBinaryImageUnwindInfo *_Nullable outInfo);

/**
 * Get cached unwind information for an address.
 *
 * This function is async-signal-safe.
 *
 * @param address The memory address to look up.
 * @param outInfo If not NULL and found, receives the cached unwind info.
 * @return true if the image was found, false otherwise.
 */
bool ksbic_getUnwindInfoForAddress(uintptr_t address, KSBinaryImageUnwindInfo *_Nullable outInfo);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBinaryImageCache_h
