//
// KSUnwindCache.c
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

#include "Unwind/KSUnwindCache.h"

#include <mach-o/loader.h>
#include <stdatomic.h>
#include <string.h>

#include "KSBinaryImageCache.h"
#include "KSLogger.h"
#include "KSMach-O.h"

// MARK: - Constants

#define KSUC_MAX_CACHE_ENTRIES 512

// Section names for unwind data
#define KSUC_SECT_UNWIND_INFO "__unwind_info"
#define KSUC_SECT_EH_FRAME "__eh_frame"

// MARK: - Cache Storage

typedef struct {
    KSUnwindImageInfo entries[KSUC_MAX_CACHE_ENTRIES];
    uint32_t count;
} KSUnwindCache;

// Static cache storage (pre-allocated for async-signal-safety)
static KSUnwindCache g_unwind_cache_storage = { .count = 0 };

// Atomic pointer to the cache. NULL means cache is in use by another caller.
static _Atomic(KSUnwindCache *) g_unwind_cache_ptr = &g_unwind_cache_storage;

// MARK: - Internal Functions

/**
 * Look up an image in the cache by header pointer.
 * Returns the index if found, -1 otherwise.
 * Cache must be held exclusively by caller.
 */
static int32_t findInCache(const KSUnwindCache *cache, const mach_header_t *header)
{
    for (uint32_t i = 0; i < cache->count; i++) {
        if (cache->entries[i].header == header) {
            return (int32_t)i;
        }
    }
    return -1;
}

/**
 * Populate unwind info for an image by looking up its sections.
 * Returns true if any unwind data was found.
 */
static bool populateUnwindInfo(const mach_header_t *header, KSUnwindImageInfo *outInfo)
{
    if (header == NULL || outInfo == NULL) {
        return false;
    }

    // Initialize the structure
    *outInfo = (KSUnwindImageInfo) {
        .header = header,
        .unwindInfo = NULL,
        .unwindInfoSize = 0,
        .ehFrame = NULL,
        .ehFrameSize = 0,
        .slide = 0,
        .hasCompactUnwind = false,
        .hasEhFrame = false,
    };

    // Calculate slide from __TEXT segment
    const segment_command_t *textSegment = ksmacho_getSegmentByNameFromHeader(header, SEG_TEXT);
    if (textSegment == NULL) {
        KSLOG_DEBUG("No __TEXT segment found for image at %p", header);
        return false;
    }
    outInfo->slide = (uintptr_t)header - textSegment->vmaddr;

    // Look up __unwind_info section
    size_t unwindInfoSize = 0;
    const void *unwindInfo =
        ksmacho_getSectionDataByNameFromHeader(header, SEG_TEXT, KSUC_SECT_UNWIND_INFO, &unwindInfoSize);
    if (unwindInfo != NULL && unwindInfoSize > 0) {
        outInfo->unwindInfo = unwindInfo;
        outInfo->unwindInfoSize = unwindInfoSize;
        outInfo->hasCompactUnwind = true;
        KSLOG_TRACE("Found __unwind_info at %p, size %zu for image %p", unwindInfo, unwindInfoSize, header);
    }

    // Look up __eh_frame section
    size_t ehFrameSize = 0;
    const void *ehFrame = ksmacho_getSectionDataByNameFromHeader(header, SEG_TEXT, KSUC_SECT_EH_FRAME, &ehFrameSize);
    if (ehFrame != NULL && ehFrameSize > 0) {
        outInfo->ehFrame = ehFrame;
        outInfo->ehFrameSize = ehFrameSize;
        outInfo->hasEhFrame = true;
        KSLOG_TRACE("Found __eh_frame at %p, size %zu for image %p", ehFrame, ehFrameSize, header);
    }

    return outInfo->hasCompactUnwind || outInfo->hasEhFrame;
}

// MARK: - Public API

const KSUnwindImageInfo *ksunwindcache_getInfoForImage(const mach_header_t *header)
{
    if (header == NULL) {
        return NULL;
    }

    // Try to acquire exclusive access to the cache
    KSUnwindCache *cache = atomic_exchange(&g_unwind_cache_ptr, NULL);

    if (cache != NULL) {
        // SUCCESS: We have exclusive access to the cache

        // Check if already cached
        int32_t idx = findInCache(cache, header);
        if (idx >= 0) {
            // Cache hit
            const KSUnwindImageInfo *result = &cache->entries[idx];
            atomic_store(&g_unwind_cache_ptr, cache);
            return result;
        }

        // Cache miss - populate and add
        if (cache->count < KSUC_MAX_CACHE_ENTRIES) {
            KSUnwindImageInfo *newEntry = &cache->entries[cache->count];
            if (populateUnwindInfo(header, newEntry)) {
                cache->count++;
                atomic_store(&g_unwind_cache_ptr, cache);
                return newEntry;
            }
        } else {
            KSLOG_DEBUG("Unwind cache full (%u entries), cannot add image %p", KSUC_MAX_CACHE_ENTRIES, header);
        }

        // Release the cache
        atomic_store(&g_unwind_cache_ptr, cache);
        return NULL;
    } else {
        // FAILED: Cache is in use by another caller
        // Fall back to non-cached lookup
        // NOTE: This returns a stack-local pointer which is NOT safe to use!
        // However, in practice this code path is rare and the caller should
        // handle NULL gracefully.
        KSLOG_DEBUG("Unwind cache busy, cannot look up image %p", header);
        return NULL;
    }
}

const KSUnwindImageInfo *ksunwindcache_getInfoForAddress(uintptr_t address)
{
    // Find the image containing this address
    const struct mach_header *header = ksbic_findImageForAddress(address, NULL, NULL);
    if (header == NULL) {
        return NULL;
    }

    return ksunwindcache_getInfoForImage((const mach_header_t *)header);
}

void ksunwindcache_reset(void)
{
    // Acquire exclusive access to the cache before resetting
    KSUnwindCache *cache = atomic_exchange(&g_unwind_cache_ptr, NULL);
    if (cache != NULL) {
        cache->count = 0;
        atomic_store(&g_unwind_cache_ptr, cache);
    } else {
        // Cache is in use by another thread - reset storage directly
        g_unwind_cache_storage.count = 0;
        atomic_store(&g_unwind_cache_ptr, &g_unwind_cache_storage);
    }
}
