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
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "KSLogger.h"

#ifndef KSBIC_MAX_CACHED_IMAGES
#define KSBIC_MAX_CACHED_IMAGES 2000
#endif

typedef struct {
    const struct mach_header *header;
    const char *name;
    uintptr_t imageVMAddrSlide;
    bool valid;
} KSBinaryImageCacheEntry;

static KSBinaryImageCacheEntry g_binaryImageCache[KSBIC_MAX_CACHED_IMAGES];
static uint32_t g_cachedImageCount = 0;
static pthread_rwlock_t g_imageCacheRWLock = PTHREAD_RWLOCK_INITIALIZER;

/** Add an image to the cache.
 *
 * @param header The header of the image to add.
 * @param slide The VM address slide of the image.
 */
static void ksbic_addImageCallback(const struct mach_header *header, intptr_t slide)
{
    pthread_rwlock_wrlock(&g_imageCacheRWLock);

    // Check if image already exists in cache to prevent duplication
    for (uint32_t i = 0; i < g_cachedImageCount; i++) {
        if (g_binaryImageCache[i].header == header) {
            KSLOG_DEBUG("Image already in cache at index %d, skipping.", i);
            pthread_rwlock_unlock(&g_imageCacheRWLock);
            return;
        }
    }

    if (g_cachedImageCount < KSBIC_MAX_CACHED_IMAGES) {
        uint32_t imageIndex = g_cachedImageCount;
        // Find the correct name by searching through dyld's image list
        const char *imageName = NULL;
        uint32_t dyldImageCount = _dyld_image_count();

        for (uint32_t i = 0; i < dyldImageCount; i++) {
            if (_dyld_get_image_header(i) == header) {
                imageName = _dyld_get_image_name(i);
                break;
            }
        }

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

    pthread_rwlock_unlock(&g_imageCacheRWLock);
}

/** Remove an image from the cache.
 *
 * @param header The header of the image to remove.
 * @param slide The VM address slide of the image.
 */
static void ksbic_removeImageCallback(const struct mach_header *header, intptr_t slide)
{
    pthread_rwlock_wrlock(&g_imageCacheRWLock);

    for (uint32_t i = 0; i < g_cachedImageCount; i++) {
        if (g_binaryImageCache[i].header == header) {
            if (g_binaryImageCache[i].name != NULL) {
                KSLOG_DEBUG("Removing image from cache: %s at index %d", g_binaryImageCache[i].name, i);
                free((void *)g_binaryImageCache[i].name);
            }

            for (uint32_t j = i; j < g_cachedImageCount - 1; j++) {
                g_binaryImageCache[j] = g_binaryImageCache[j + 1];
            }
            g_cachedImageCount--;
            break;
        }
    }

    pthread_rwlock_unlock(&g_imageCacheRWLock);
}

static _Atomic(bool) g_initialized = false;

void ksbic_init(void)
{
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_initialized, &expected, true)) {
        return;
    }

    KSLOG_DEBUG("Initializing binary image cache");

    _dyld_register_func_for_add_image(ksbic_addImageCallback);
    _dyld_register_func_for_remove_image(ksbic_removeImageCallback);
}

// For testing purposes only. Used with extern in test files.
void ksbic_resetCache(void)
{
    bool expected = true;
    if (!atomic_compare_exchange_strong(&g_initialized, &expected, false)) {
        return;
    }

    pthread_rwlock_wrlock(&g_imageCacheRWLock);

    for (uint32_t i = 0; i < g_cachedImageCount; i++) {
        if (g_binaryImageCache[i].name != NULL) {
            free((void *)g_binaryImageCache[i].name);
            g_binaryImageCache[i].name = NULL;
        }
    }

    memset(g_binaryImageCache, 0, sizeof(g_binaryImageCache));
    g_cachedImageCount = 0;

    pthread_rwlock_unlock(&g_imageCacheRWLock);
}

uint32_t ksbic_imageCount(void)
{
    uint32_t count;
    pthread_rwlock_rdlock(&g_imageCacheRWLock);
    count = g_cachedImageCount;
    pthread_rwlock_unlock(&g_imageCacheRWLock);
    return count;
}

const struct mach_header *ksbic_imageHeader(uint32_t index)
{
    const struct mach_header *header = NULL;
    pthread_rwlock_rdlock(&g_imageCacheRWLock);
    if (index < g_cachedImageCount) {
        header = g_binaryImageCache[index].header;
    }
    pthread_rwlock_unlock(&g_imageCacheRWLock);
    return header;
}

const char *ksbic_imageName(uint32_t index)
{
    const char *name = NULL;
    pthread_rwlock_rdlock(&g_imageCacheRWLock);
    if (index < g_cachedImageCount) {
        name = g_binaryImageCache[index].name;
    }
    pthread_rwlock_unlock(&g_imageCacheRWLock);
    return name;
}

uintptr_t ksbic_imageVMAddrSlide(uint32_t index)
{
    uintptr_t slide = 0;
    pthread_rwlock_rdlock(&g_imageCacheRWLock);
    if (index < g_cachedImageCount) {
        slide = g_binaryImageCache[index].imageVMAddrSlide;
    }
    pthread_rwlock_unlock(&g_imageCacheRWLock);
    return slide;
}
