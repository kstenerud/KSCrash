//
//  KSDynamicLinker.h
//
//  Created by Karl Stenerud on 2013-10-02.
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

#ifndef HDR_KSDynamicLinker_h
#define HDR_KSDynamicLinker_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"
#include "KSPlatformSpecificDefines.h"

#ifdef __cplusplus
extern "C" {
#endif

// ====================================
#pragma mark - Types -
// ====================================

/**
 * All of the information that we cache about a loaded binary image.
 */
typedef struct {
    /**
     * The filesystem path to the image (as seen from inside the container).
     *
     * Notes:
     * - Paths to images in the app itself will look like `@rpath/MyApp.debug.dylib`
     * - The main app image won't have a LC_ID_DYLIB load command, so its `name` will be NULL.
     */
    const char *name;

    /** The filesystem path to the image (as seen from outside the container) */
    const char *filePath;

    /** The address of the beginning of the image (which is also its header) */
    const mach_header_t *address;

    /** The address of this image in the virtual space (modified by ASLR) */
    uintptr_t vmAddress;

    /** The size of this image */
    size_t size;

    /** The difference between the physical address and the VM address */
    uintptr_t vmAddressSlide;

    /** This image's globally unique ID, which can be used for matching when symbolicating */
    const uint8_t *uuid;

    // Other useful info:
    int cpuType;
    int cpuSubType;
    uint64_t majorVersion;
    uint64_t minorVersion;
    uint64_t revisionVersion;

    // Meant for internal use, but may be handy elsewhere:

    /** Address of the `__TEXT` segment */
    const segment_command_t *textSegmentCmd;

    /** Address of the `__DATA` segment */
    const segment_command_t *dataSegmentCmd;

    /** Address of the `__LINKEDIT` segment */
    const segment_command_t *linkEditorSegmentCmd;

    /** Address of the symbol table */
    const struct symtab_command *symbolTableCmd;

    /** Address of the crash info section (where `crash_info_t` lives) */
    const section_t *crashInfoSection;

    // Legacy:
    const char *crashInfoMessage;
    const char *crashInfoMessage2;
    const char *crashInfoBacktrace;
    const char *crashInfoSignature;
} KSBinaryImage;

/**
 * Information returned from `ksdl_getCrashInfo()`.
 *
 * Note: All of these fields can be NULL.
 */
typedef struct {
    const char *crashInfoMessage;
    const char *crashInfoMessage2;
    const char *crashInfoBacktrace;
    const char *crashInfoSignature;
} KSCrashInfo;

/**
 * Information returned from `ksdl_symbolicate()`.
 */
typedef struct {
    /**
     * The image containing the symbol.
     * If the address searched didn't match any loaded images, this field will be NULL.
     * Note: This field may still be present if an address matched a loaded image, but didn't match any symbols within.
     */
    const KSBinaryImage *image;

    /**
     * The address of the symbol (relative to `image->vmAddress`).
     * If the address searched didn't match any symbols, this field will be 0;
     */
    uintptr_t symbolAddress;

    /**
     * The symbol name.
     * If the address searched didn't match any symbols, this field will be NULL;
     */
    const char *symbolName;
} KSSymbolication;

// ====================================
#pragma mark - API -
// ====================================

/**
 * Initialize the dynamic linker cache.
 * This MUST be called before any other dynamic linker method.
 */
void ksdl_init(void);

/**
 * Refresh the dynamic linker cache with the latest linker info from the system.
 * Although the documentation says that nothing will modify images after the app is loaded,
 * actual testing has shown otherwise (likely only while debugging, but still...)
 *
 * This method should be called before servicing an exception.
 *
 * Note: This function only updates the list to mark the new images as needing caching.
 * It doesn't actually cache them, so it's very quick.
 */
void ksdl_refreshCache(void);

/**
 * Get the number of cached binary images.
 */
size_t ksdl_imageCount(void);

/**
 * Get the cached binary image at the specified index.
 *
 * @param index The index to fetch from.
 * @return The cached binary image, or NULL if the index was out of range.
 */
KSBinaryImage *ksdl_imageAtIndex(size_t index);

/**
 * Get all available information about an image pointed to by a mach header.
 * This function will cache any found data for future calls.
 *
 * Note: May return NULL if the cache is out of sync with the currently loaded images.
 * Be sure to call `ksdl_refreshCache()` first to get the most up-to-date information.
 *
 * @param header The mach header pointing to the image of interest
 * @return Information about the header, or NULL if we couldn't find any.
 */
KSBinaryImage *ksdl_getImageForMachHeader(const struct mach_header *header);

/**
 * Get all available information about any image that contains code at the specified address.
 * This function will cache any found data for future calls.
 *
 * Note: May return NULL if none of the images it knows about contain the address.
 * Be sure to call `ksdl_refreshCache()` first to get the most up-to-date information.
 *
 * @param address The address to search for.
 * @return Information about any matching image, or NULL if we couldn't find any.
 */
KSBinaryImage *ksdl_getImageContainingAddress(const uintptr_t address);

/**
 * Get any crash information associated with an image.
 * This should be called with the image containing the address where the crash occurred.
 *
 * @param image The image to collect information for.
 * @return The crash information.
 */
KSCrashInfo ksdl_getCrashInfo(const KSBinaryImage *image);

/**
 * Symbolicate an address.
 *
 * @param address The address of an instruction being executed.
 * @return The symbolication (if any was found).
 */
KSSymbolication ksdl_symbolicate(uintptr_t address);

// ====================================
#pragma mark - Legacy API -
// ====================================

#include <dlfcn.h>

/** Get information about a binary image based on mach_header.
 *
 * @param header_ptr The pointer to mach_header of the image.
 *
 * @param image_name The name of the image.
 *
 * @param buffer A structure to hold the information.
 *
 * @return True if the image was successfully queried.
 */
bool ksdl_binaryImageForHeader(const void *const header_ptr, const char *const image_name, KSBinaryImage *buffer);

/** async-safe version of dladdr.
 *
 * This method searches the dynamic loader for information about any image
 * containing the specified address. It may not be entirely successful in
 * finding information, in which case any fields it could not find will be set
 * to NULL.
 *
 * Unlike dladdr(), this method does not make use of locks, and does not call
 * async-unsafe functions.
 *
 * @param address The address to search for.
 * @param info Gets filled out by this function.
 * @return true if at least some information was found.
 */
bool ksdl_dladdr(const uintptr_t address, Dl_info *const info);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSDynamicLinker_h
