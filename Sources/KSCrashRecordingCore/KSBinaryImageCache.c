//
// KSBinaryImageCache.c
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

#include "KSBinaryImageCache.h"

#include <mach-o/dyld.h>
#include <os/lock.h>
#include <stdlib.h>
#include <string.h>

#include "KSLogger.h"

#ifndef KSBIC_MAX_CACHED_IMAGES
#define KSBIC_MAX_CACHED_IMAGES 1000
#endif

typedef struct {
    const struct mach_header *header;
    const char *name;
    uintptr_t imageVMAddrSlide;
    bool valid;
} KSBinaryImageCacheEntry;

static KSBinaryImageCacheEntry g_binaryImageCache[KSBIC_MAX_CACHED_IMAGES];
static int g_cachedImageCount = 0;
static os_unfair_lock g_imageCacheLock = OS_UNFAIR_LOCK_INIT;

/** Add an image to the cache.
 *
 * @param header The header of the image to add.
 * @param slide The VM address slide of the image.
 */
static void ksbic_addImageCallback(const struct mach_header *header, intptr_t slide)
{
    os_unfair_lock_lock(&g_imageCacheLock);

    if (g_cachedImageCount < KSBIC_MAX_CACHED_IMAGES) {
        uint32_t imageIndex = g_cachedImageCount;
        const char *imageName = _dyld_get_image_name(imageIndex);
        if (imageName != NULL) {
            g_binaryImageCache[imageIndex].header = header;
            g_binaryImageCache[imageIndex].name = strdup(imageName);
            if (g_binaryImageCache[imageIndex].name == NULL) {
                KSLOG_ERROR("Failed to duplicate image name: %s. Not caching image.", imageName);
            } else {
                g_binaryImageCache[imageIndex].imageVMAddrSlide = (uintptr_t)slide;
                g_binaryImageCache[imageIndex].valid = true;
                g_cachedImageCount++;
                KSLOG_DEBUG("Added image to cache: %s at index %d", imageName, imageIndex);
            }
        }
    } else {
        KSLOG_ERROR("Binary image cache full. Not caching image.");
    }

    os_unfair_lock_unlock(&g_imageCacheLock);
}

/** Remove an image from the cache.
 *
 * @param header The header of the image to remove.
 * @param slide The VM address slide of the image.
 */
static void ksbic_removeImageCallback(const struct mach_header *header, intptr_t slide)
{
    os_unfair_lock_lock(&g_imageCacheLock);

    for (int i = 0; i < g_cachedImageCount; i++) {
        if (g_binaryImageCache[i].header == header) {
            if (g_binaryImageCache[i].name != NULL) {
                KSLOG_DEBUG("Removing image from cache: %s at index %d", g_binaryImageCache[i].name, i);
                free((void *)g_binaryImageCache[i].name);
            }

            for (int j = i; j < g_cachedImageCount - 1; j++) {
                g_binaryImageCache[j] = g_binaryImageCache[j + 1];
            }
            g_cachedImageCount--;
            break;
        }
    }

    os_unfair_lock_unlock(&g_imageCacheLock);
}

/** Initialize the binary image cache.
 *
 * This function is called when the library is loaded.
 */
__attribute__((constructor)) static void ksbic_initializeBinaryImageCache(void)
{
    KSLOG_DEBUG("Initializing binary image cache");

    _dyld_register_func_for_add_image(ksbic_addImageCallback);
    _dyld_register_func_for_remove_image(ksbic_removeImageCallback);

    uint32_t imageCount = _dyld_image_count();
    imageCount = imageCount > KSBIC_MAX_CACHED_IMAGES ? KSBIC_MAX_CACHED_IMAGES : imageCount;

    for (uint32_t i = 0; i < imageCount; i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        if (header != NULL) {
            ksbic_addImageCallback(header, _dyld_get_image_vmaddr_slide(i));
        }
    }
}

uint32_t ksbic_imageCount(void)
{
    return (uint32_t)g_cachedImageCount;
}

const struct mach_header *ksbic_imageHeader(uint32_t index)
{
    if (index >= (uint32_t)g_cachedImageCount) {
        return NULL;
    }
    return g_binaryImageCache[index].header;
}

const char *ksbic_imageName(uint32_t index)
{
    if (index >= (uint32_t)g_cachedImageCount) {
        return NULL;
    }
    return g_binaryImageCache[index].name;
}

uintptr_t ksbic_imageVMAddrSlide(uint32_t index)
{
    if (index >= (uint32_t)g_cachedImageCount) {
        return 0;
    }
    return g_binaryImageCache[index].imageVMAddrSlide;
}