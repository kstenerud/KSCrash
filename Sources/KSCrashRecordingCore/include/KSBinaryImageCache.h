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
#include <mach/mach_types.h>
#include <stdbool.h>
#include <stdint.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnon-modular-include-in-module"
#include <mach-o/dyld_images.h>
#pragma clang diagnostic pop

#include "KSCrashNamespace.h"
#include "KSDynamicLinker.h"

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
    // Target runtime address of ehFrame byte 0, minus the local address of the ehFrame buffer.
    // 0 when ehFrame is mapped at its own runtime address (the live cache, or a same-address-space
    // target). Non-zero only when ehFrame is a copy of another process's section: DWARF pc-relative
    // pointers are resolved against (local pointer + this delta) so they land in the target's space.
    uintptr_t ehFrameRuntimeDelta;
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
 * Get the file path of the dyld shared library.
 *
 * @return The file path of dyld.
 */
const char *_Nonnull ksbic_getDyldPath(void);

/**
 * Get the LC_UUID for a binary image.
 *
 * Returns a pointer to the 16-byte UUID in the Mach-O header, or NULL if not found.
 * The pointer is valid for the lifetime of the loaded image.
 *
 * This function is async-signal-safe. On a cache miss the fallback path
 * includes KSLOG_DEBUG calls, but these are compiled out at the default
 * log level (ERROR) so this is not an issue in production builds.
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

/**
 * An immutable, self-contained snapshot of binary images and their unwind info.
 *
 * Unlike the live cache (which reads the running process's dyld image list), a set
 * carries each image's own segment ranges and unwind-section pointers. That makes it
 * usable to drive the unwinder against images from *another* task (e.g. a corpse), as long
 * as the section pointers stored in each entry reference bytes readable in the current
 * process.
 *
 * Opaque. Create with ksbic_createSetFromTaskImages (remote images) or
 * ksbic_createSetFromLocalImages (this process's images) and release with
 * ksbic_destroySet. Confine each set to a single thread: lookups lazily copy a remote
 * image's unwind sections out of the source task on first hit.
 */
typedef struct KSBinaryImageSet KSBinaryImageSet;

/**
 * Build an image set from the current process's loaded images.
 *
 * Allocates, so this is NOT async-signal-safe and must not run from a crash handler.
 * It is the counterpart to (and a building block for) ksbic_createSetFromTaskImages: the
 * same per-image entries describe shared-cache images that are mapped into both the target
 * task and this one.
 *
 * NOT interchangeable with ksbic_createSetFromTaskImages(mach_task_self(), ...), despite
 * describing the same images. Entries here are born fully resolved, pointing straight at
 * in-process sections, so no lookup ever allocates. The task builder instead records each
 * section's remote address for a lazy cross-task copy, which mallocs and vm_reads on first
 * hit. This is therefore the only allocation-free way to obtain a set, which is what an
 * in-process consumer that cannot allocate during lookups needs. Do not delete it as unused
 * on the strength of the task builder existing.
 *
 * @return A newly allocated set the caller must release with ksbic_destroySet, or NULL on failure.
 */
KSBinaryImageSet *_Nullable ksbic_createSetFromLocalImages(void);

/**
 * Describes one image to load into a set: its load address in the target task, and an
 * optional name. This mirrors the (baseAddress, path) pair a crash extension hands us
 * for each image of a crashed process.
 */
typedef struct {
    uintptr_t loadAddress;
    const char *_Nullable name;
} KSBinaryImageDescriptor;

/**
 * Build an image set by reading each image's Mach-O header and unwind sections from @c task.
 *
 * For every descriptor this reads the header out of @c task (via cross-task memory reads) and
 * parses it to recover the slide, segment ranges, and unwind-section coordinates. The
 * __unwind_info / __eh_frame bytes are copied out of @c task lazily, on the first lookup that
 * hits the image; the set owns those copies and frees them in ksbic_destroySet. Because the
 * bytes are copied, the resulting set can drive the unwinder against a genuinely remote process
 * (e.g. a corpse handed to a crash extension), not just the current one. The task port must
 * therefore stay valid for the set's lifetime.
 *
 * Allocates; not async-signal-safe.
 *
 * @param task The task to read image headers and sections from.
 * @param images The images to load. May be NULL only if @c count is 0.
 * @param count The number of descriptors.
 * @return A newly allocated set the caller must release with ksbic_destroySet, or NULL on failure.
 */
KSBinaryImageSet *_Nullable ksbic_createSetFromTaskImages(task_t task, const KSBinaryImageDescriptor *_Nullable images,
                                                          uint32_t count);

/**
 * Fill in the header-derived fields of a @c KSBinaryImage from an image of @c task, cross-task.
 * 64-bit images only.
 *
 * Sets exactly the fields the Mach-O header knows: address, vmAddress, vmAddressSlide, size and
 * the version triple. Everything else on the image (name, uuid, cpuType, cpuSubType, crash-info
 * strings) is the caller's to fill, and untouched fields are left alone.
 *
 * The values match what @c ksdl_binaryImageForHeader records for a local image, so a report
 * about another task describes its images identically to a local one. That matters
 * most for @c vmAddress: symbolication derives the slide as address - vmAddress, so leaving it
 * zero silently misplaces every frame in the image.
 *
 * Caller-supplied image facts are not always trustworthy: the iOS 27 CrashReportExtension hands
 * sizes computed to the end of the dyld shared cache for cache-resident images, and hands no
 * vmaddr or version at all. One load-command walk answers all of them.
 *
 * @param task The task whose image to inspect.
 * @param loadAddress The image's load address in @c task.
 * @param outImage The image to fill. Must not be NULL.
 * @return true if the header was read and carried a __TEXT segment.
 */
bool ksbic_fillTaskImage(task_t task, uintptr_t loadAddress, KSBinaryImage *_Nonnull outImage);

/**
 * Release an image set created by ksbic_createSetFromTaskImages or
 * ksbic_createSetFromLocalImages.
 *
 * @param set The set to release. NULL is allowed and ignored.
 */
void ksbic_destroySet(KSBinaryImageSet *_Nullable set);

/**
 * Which unwind sections a set lookup should resolve (copy out of a remote task).
 * Sections are copied on the first lookup that requests them: compact unwind almost always
 * suffices, so __eh_frame (often hundreds of KB per large image) is only copied when a DWARF
 * lookup actually asks for it.
 */
typedef enum {
    KSBinaryImageUnwindSectionCompactUnwind = 1 << 0,
    KSBinaryImageUnwindSectionEhFrame = 1 << 1,
} KSBinaryImageUnwindSections;

/**
 * Look up unwind information for an address within an image set.
 *
 * The set-backed equivalent of ksbic_getUnwindInfoForAddress: matches the address
 * against each image's segment ranges (so interleaved shared-cache images resolve
 * correctly) and returns that image's unwind info.
 *
 * @param set The image set to query. NULL returns false.
 * @param address The address to look up, in the address space of the set's images.
 * @param wantedSections The sections to resolve for the hit image (remote sets copy them
 *        out of the source task on first request). A section not yet requested reads as
 *        absent in the result (hasCompactUnwind / hasEhFrame false).
 * @param outInfo If not NULL and found, receives the unwind info.
 * @return true if an image containing the address was found, false otherwise.
 */
bool ksbic_getUnwindInfoForAddressInSet(const KSBinaryImageSet *_Nullable set, uintptr_t address,
                                        uint32_t wantedSections, KSBinaryImageUnwindInfo *_Nullable outInfo);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBinaryImageCache_h
