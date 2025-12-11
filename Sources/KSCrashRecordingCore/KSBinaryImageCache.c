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

#include <dlfcn.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "KSLogger.h"

// MARK: - Image Address Range Cache

#define KSBIC_MAX_CACHE_ENTRIES 2048
#define KSBIC_MAX_SEGMENTS_PER_IMAGE 8

/**
 * Cached segment range for fast address-in-segment checks.
 */
typedef struct {
    uintptr_t start;  // Segment start address (with slide applied)
    uintptr_t end;    // Segment end address (exclusive, with slide applied)
} KSSegmentRange;

/**
 * Cached image address range for fast lookups.
 * Stores pre-computed segment ranges for O(1) address validation.
 */
typedef struct {
    uintptr_t startAddress;  // Min segment address (for quick rejection)
    uintptr_t endAddress;    // Max segment address (for quick rejection)
    uintptr_t slide;         // Pre-computed ASLR slide
    uintptr_t segmentBase;   // Pre-computed segment base for symbol lookups (vmaddr - fileoff for __LINKEDIT)
    const struct mach_header *_Nullable header;
    const char *_Nullable name;
    KSSegmentRange segments[KSBIC_MAX_SEGMENTS_PER_IMAGE];  // Actual segment ranges
    uint8_t segmentCount;                                   // Number of valid segments
} KSBinaryImageRange;

typedef struct {
    KSBinaryImageRange entries[KSBIC_MAX_CACHE_ENTRIES];
    uint32_t count;
} KSBinaryImageRangeCache;

// Static cache storage (pre-allocated for async-signal-safety)
static KSBinaryImageRangeCache g_cache_storage = { .count = 0 };

// Atomic pointer to the cache. NULL means cache is in use by another caller.
static _Atomic(KSBinaryImageRangeCache *) g_cache_ptr = NULL;

// Check if an address falls within any of the cached segment ranges.
// This is O(segments) but segments is typically 4-6, so very fast.
static inline bool addressInCachedSegments(const KSBinaryImageRange *entry, uintptr_t address)
{
    for (uint8_t i = 0; i < entry->segmentCount; i++) {
        if (address >= entry->segments[i].start && address < entry->segments[i].end) {
            return true;
        }
    }
    return false;
}

// Populate a cache entry with image info including segment ranges.
// Returns true if the image has valid segments, false otherwise.
static bool populateCacheEntry(const struct mach_header *header, const char *name, KSBinaryImageRange *entry)
{
    entry->header = header;
    entry->name = name;
    entry->slide = 0;
    entry->segmentBase = 0;
    entry->startAddress = 0;
    entry->endAddress = 0;
    entry->segmentCount = 0;

    if (header == NULL) {
        return false;
    }

    uintptr_t loadAddr = (uintptr_t)header;
    uintptr_t slide = 0;
    uintptr_t segmentBase = 0;
    uintptr_t minAddr = UINTPTR_MAX;
    uintptr_t maxAddr = 0;
    bool foundText = false;
    bool foundLinkedit = false;
    uint8_t segCount = 0;

    if (header->magic == MH_MAGIC_64) {
        const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
        uintptr_t cmdPtr = (uintptr_t)(header64 + 1);

        for (uint32_t i = 0; i < header64->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)cmdPtr;

                // Check for __TEXT to compute slide (only once)
                if (!foundText && seg->segname[0] == '_' && seg->segname[1] == '_' && seg->segname[2] == 'T' &&
                    seg->segname[3] == 'E' && seg->segname[4] == 'X' && seg->segname[5] == 'T' &&
                    seg->segname[6] == '\0') {
                    slide = loadAddr - (uintptr_t)seg->vmaddr;
                    foundText = true;
                }

                // Check for __LINKEDIT to compute segment base (only once)
                if (!foundLinkedit && seg->segname[0] == '_' && seg->segname[1] == '_' && seg->segname[2] == 'L' &&
                    seg->segname[3] == 'I' && seg->segname[4] == 'N' && seg->segname[5] == 'K' &&
                    seg->segname[6] == 'E' && seg->segname[7] == 'D' && seg->segname[8] == 'I' &&
                    seg->segname[9] == 'T' && seg->segname[10] == '\0') {
                    segmentBase = (uintptr_t)(seg->vmaddr - seg->fileoff);
                    foundLinkedit = true;
                }

                // Store segments with actual file content (exclude __PAGEZERO)
                if (seg->vmsize > 0 && seg->filesize > 0) {
                    uintptr_t segStart = (uintptr_t)seg->vmaddr;
                    uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;
                    if (segStart < minAddr) minAddr = segStart;
                    if (segEnd > maxAddr) maxAddr = segEnd;

                    // Store segment range (will apply slide after loop)
                    if (segCount < KSBIC_MAX_SEGMENTS_PER_IMAGE) {
                        entry->segments[segCount].start = segStart;
                        entry->segments[segCount].end = segEnd;
                        segCount++;
                    }
                }
            }
            cmdPtr += lc->cmdsize;
        }
    } else if (header->magic == MH_MAGIC) {
        uintptr_t cmdPtr = (uintptr_t)(header + 1);

        for (uint32_t i = 0; i < header->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;
            if (lc->cmd == LC_SEGMENT) {
                const struct segment_command *seg = (const struct segment_command *)cmdPtr;

                // Check for __TEXT to compute slide (only once)
                if (!foundText && seg->segname[0] == '_' && seg->segname[1] == '_' && seg->segname[2] == 'T' &&
                    seg->segname[3] == 'E' && seg->segname[4] == 'X' && seg->segname[5] == 'T' &&
                    seg->segname[6] == '\0') {
                    slide = loadAddr - (uintptr_t)seg->vmaddr;
                    foundText = true;
                }

                // Check for __LINKEDIT to compute segment base (only once)
                if (!foundLinkedit && seg->segname[0] == '_' && seg->segname[1] == '_' && seg->segname[2] == 'L' &&
                    seg->segname[3] == 'I' && seg->segname[4] == 'N' && seg->segname[5] == 'K' &&
                    seg->segname[6] == 'E' && seg->segname[7] == 'D' && seg->segname[8] == 'I' &&
                    seg->segname[9] == 'T' && seg->segname[10] == '\0') {
                    segmentBase = (uintptr_t)(seg->vmaddr - seg->fileoff);
                    foundLinkedit = true;
                }

                // Store segments with actual file content (exclude __PAGEZERO)
                if (seg->vmsize > 0 && seg->filesize > 0) {
                    uintptr_t segStart = (uintptr_t)seg->vmaddr;
                    uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;
                    if (segStart < minAddr) minAddr = segStart;
                    if (segEnd > maxAddr) maxAddr = segEnd;

                    // Store segment range (will apply slide after loop)
                    if (segCount < KSBIC_MAX_SEGMENTS_PER_IMAGE) {
                        entry->segments[segCount].start = segStart;
                        entry->segments[segCount].end = segEnd;
                        segCount++;
                    }
                }
            }
            cmdPtr += lc->cmdsize;
        }
    }

    // Apply slide to all segment ranges
    for (uint8_t i = 0; i < segCount; i++) {
        entry->segments[i].start += slide;
        entry->segments[i].end += slide;
    }

    entry->slide = slide;
    entry->segmentBase = segmentBase;
    entry->startAddress = (minAddr == UINTPTR_MAX) ? 0 : (minAddr + slide);
    entry->endAddress = (maxAddr == 0) ? 0 : (maxAddr + slide);
    entry->segmentCount = segCount;

    return (segCount > 0);
}

// Linear scan through dyld images to find one containing the address.
// If outEntry is provided, populates it with full image info for caching.
static const struct mach_header *linearScanForAddress(uintptr_t address, KSBinaryImageRange *outEntry)
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    if (images == NULL) {
        return NULL;
    }

    KSBinaryImageRange tempEntry;
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *header = images[i].imageLoadAddress;
        if (header == NULL) {
            continue;
        }

        // Populate entry with segment info
        if (!populateCacheEntry(header, images[i].imageFilePath, &tempEntry)) {
            continue;
        }

        // Check if address is in any segment of this image
        // This is critical for dyld shared cache where segments from different images can be interleaved
        if (addressInCachedSegments(&tempEntry, address)) {
            if (outEntry) {
                *outEntry = tempEntry;
            }
            return header;
        }
    }

    return NULL;
}

/// As a general rule, access to _g_all_image_infos->infoArray_ is thread safe
/// in a way that you can iterate all you want since items will never be removed
/// and the _infoCount_ is only updated after an item is added to _infoArray_.
/// Because of this, we can iterate during a signal handler, Mach exception handler
/// or even at any point within the run of the process.
///
/// More info in this comment:
/// https://github.com/kstenerud/KSCrash/pull/655#discussion_r2211271075

static struct dyld_all_image_infos *g_all_image_infos = NULL;

void ksbic_init(void)
{
    KSLOG_DEBUG("Initializing binary image cache");

    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t err = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (err != KERN_SUCCESS) {
        KSLOG_ERROR("Failed to acquire TASK_DYLD_INFO. We won't have access to binary images.");
        return;
    }
    g_all_image_infos = (struct dyld_all_image_infos *)dyld_info.all_image_info_addr;

    // Initialize the address range cache
    g_cache_storage.count = 0;
    atomic_store(&g_cache_ptr, &g_cache_storage);
}

const ks_dyld_image_info *ksbic_getImages(uint32_t *count)
{
    if (count) {
        *count = 0;
    }
    struct dyld_all_image_infos *allInfo = g_all_image_infos;
    if (allInfo == NULL) {
        KSLOG_ERROR("Cannot access binary images");
        return NULL;
    }
    const struct dyld_image_info *images = allInfo->infoArray;
    if (images == NULL) {
        KSLOG_ERROR("Unexpected state: dyld_all_image_infos->infoArray is NULL!");
        return NULL;
    }
    if (count) {
        *count = allInfo->infoArrayCount;
    }
    return (ks_dyld_image_info *)images;
}

// For testing purposes only. Used with extern in test files.
void ksbic_resetCache(void)
{
    g_all_image_infos = NULL;

    // Acquire exclusive access to the cache before resetting
    KSBinaryImageRangeCache *cache = atomic_exchange(&g_cache_ptr, NULL);
    if (cache != NULL) {
        cache->count = 0;
        atomic_store(&g_cache_ptr, cache);
    } else {
        // Cache is in use by another thread - reset storage directly
        // and restore pointer (the other thread will see stale data but
        // that's acceptable for a reset operation)
        g_cache_storage.count = 0;
        atomic_store(&g_cache_ptr, &g_cache_storage);
    }
}

const struct mach_header *ksbic_findImageForAddress(uintptr_t address, uintptr_t *outSlide, const char **outName)
{
    return ksbic_getImageDetailsForAddress(address, outSlide, NULL, outName);
}

const struct mach_header *ksbic_getImageDetailsForAddress(uintptr_t address, uintptr_t *outSlide,
                                                          uintptr_t *outSegmentBase, const char **outName)
{
    // Try to acquire exclusive access to the cache
    KSBinaryImageRangeCache *cache = atomic_exchange(&g_cache_ptr, NULL);

    if (cache != NULL) {
        // SUCCESS: We have exclusive access to the cache

        // First, search the cache for a matching entry
        // Note: In dyld shared cache, multiple images can have overlapping [start, end) bounds
        // due to shared __LINKEDIT segment, so we must verify using cached segment ranges.
        for (uint32_t i = 0; i < cache->count; i++) {
            KSBinaryImageRange *entry = &cache->entries[i];
            if (address >= entry->startAddress && address < entry->endAddress) {
                // Potential cache hit - verify address is in an actual segment (fast check)
                if (addressInCachedSegments(entry, address)) {
                    // Verified: address is in a segment of this image
                    if (outSlide) *outSlide = entry->slide;
                    if (outSegmentBase) *outSegmentBase = entry->segmentBase;
                    if (outName) *outName = entry->name;
                    const struct mach_header *result = entry->header;

                    // Release the cache
                    atomic_store(&g_cache_ptr, cache);
                    return result;
                }
                // Address is in [start, end) but not in any segment - continue searching
            }
        }

        // Cache miss - do linear scan
        KSBinaryImageRange newEntry;
        const struct mach_header *header = linearScanForAddress(address, &newEntry);

        if (header != NULL && cache->count < KSBIC_MAX_CACHE_ENTRIES) {
            // Add to cache (entry already populated by linearScanForAddress)
            cache->entries[cache->count] = newEntry;
            cache->count++;
        }

        if (header != NULL) {
            if (outSlide) *outSlide = newEntry.slide;
            if (outSegmentBase) *outSegmentBase = newEntry.segmentBase;
            if (outName) *outName = newEntry.name;
        } else {
            if (outSlide) *outSlide = 0;
            if (outSegmentBase) *outSegmentBase = 0;
            if (outName) *outName = NULL;
        }

        // Release the cache
        atomic_store(&g_cache_ptr, cache);
        return header;
    } else {
        // FAILED: Cache is in use by another caller
        // Fall back to linear scan without caching
        KSBinaryImageRange entry;
        const struct mach_header *header = linearScanForAddress(address, &entry);

        if (header != NULL) {
            if (outSlide) *outSlide = entry.slide;
            if (outSegmentBase) *outSegmentBase = entry.segmentBase;
            if (outName) *outName = entry.name;
        } else {
            if (outSlide) *outSlide = 0;
            if (outSegmentBase) *outSegmentBase = 0;
            if (outName) *outName = NULL;
        }
        return header;
    }
}
