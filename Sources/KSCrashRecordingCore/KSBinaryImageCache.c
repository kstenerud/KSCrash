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

#define KSBIC_MAX_CACHE_ENTRIES 512

typedef struct {
    KSBinaryImageRange entries[KSBIC_MAX_CACHE_ENTRIES];
    uint32_t count;
} KSBinaryImageRangeCache;

// Static cache storage (pre-allocated for async-signal-safety)
static KSBinaryImageRangeCache g_cache_storage = { .count = 0 };

// Atomic pointer to the cache. NULL means cache is in use by another caller.
static _Atomic(KSBinaryImageRangeCache *) g_cache_ptr = NULL;

// Compute ASLR slide, address range, and segment base in a single pass through load commands
static void computeImageInfo(const struct mach_header *header, uintptr_t *outSlide, uintptr_t *outStart,
                             uintptr_t *outEnd, uintptr_t *outSegmentBase)
{
    uintptr_t slide = 0;
    uintptr_t segmentBase = 0;
    uintptr_t minAddr = UINTPTR_MAX;
    uintptr_t maxAddr = 0;

    if (header == NULL) {
        *outSlide = 0;
        *outStart = 0;
        *outEnd = 0;
        *outSegmentBase = 0;
        return;
    }

    uintptr_t loadAddr = (uintptr_t)header;
    bool foundText = false;
    bool foundLinkedit = false;

    if (header->magic == MH_MAGIC_64) {
        const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
        uintptr_t cmdPtr = (uintptr_t)(header64 + 1);

        for (uint32_t i = 0; i < header64->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)cmdPtr;

                // Check for __TEXT to compute slide (only once)
                if (!foundText && seg->segname[0] == '_' && seg->segname[1] == '_' &&
                    seg->segname[2] == 'T' && seg->segname[3] == 'E' && seg->segname[4] == 'X' &&
                    seg->segname[5] == 'T' && seg->segname[6] == '\0') {
                    slide = loadAddr - (uintptr_t)seg->vmaddr;
                    foundText = true;
                }

                // Check for __LINKEDIT to compute segment base (only once)
                if (!foundLinkedit && seg->segname[0] == '_' && seg->segname[1] == '_' &&
                    seg->segname[2] == 'L' && seg->segname[3] == 'I' && seg->segname[4] == 'N' &&
                    seg->segname[5] == 'K' && seg->segname[6] == 'E' && seg->segname[7] == 'D' &&
                    seg->segname[8] == 'I' && seg->segname[9] == 'T' && seg->segname[10] == '\0') {
                    segmentBase = (uintptr_t)(seg->vmaddr - seg->fileoff);
                    foundLinkedit = true;
                }

                // Track address bounds for all segments
                if (seg->vmsize > 0) {
                    uintptr_t segStart = (uintptr_t)seg->vmaddr;
                    uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;
                    if (segStart < minAddr) minAddr = segStart;
                    if (segEnd > maxAddr) maxAddr = segEnd;
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
                if (!foundText && seg->segname[0] == '_' && seg->segname[1] == '_' &&
                    seg->segname[2] == 'T' && seg->segname[3] == 'E' && seg->segname[4] == 'X' &&
                    seg->segname[5] == 'T' && seg->segname[6] == '\0') {
                    slide = loadAddr - (uintptr_t)seg->vmaddr;
                    foundText = true;
                }

                // Check for __LINKEDIT to compute segment base (only once)
                if (!foundLinkedit && seg->segname[0] == '_' && seg->segname[1] == '_' &&
                    seg->segname[2] == 'L' && seg->segname[3] == 'I' && seg->segname[4] == 'N' &&
                    seg->segname[5] == 'K' && seg->segname[6] == 'E' && seg->segname[7] == 'D' &&
                    seg->segname[8] == 'I' && seg->segname[9] == 'T' && seg->segname[10] == '\0') {
                    segmentBase = (uintptr_t)(seg->vmaddr - seg->fileoff);
                    foundLinkedit = true;
                }

                // Track address bounds for all segments
                if (seg->vmsize > 0) {
                    uintptr_t segStart = (uintptr_t)seg->vmaddr;
                    uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;
                    if (segStart < minAddr) minAddr = segStart;
                    if (segEnd > maxAddr) maxAddr = segEnd;
                }
            }
            cmdPtr += lc->cmdsize;
        }
    }

    *outSlide = slide;
    // Apply slide to get actual addresses
    *outStart = (minAddr == UINTPTR_MAX) ? 0 : (minAddr + slide);
    *outEnd = (maxAddr == 0) ? 0 : (maxAddr + slide);
    *outSegmentBase = segmentBase;
}

// Linear scan through dyld images to find one containing the address
static const struct mach_header *linearScanForAddress(uintptr_t address, uintptr_t *outSlide, const char **outName,
                                                      uintptr_t *outStart, uintptr_t *outEnd,
                                                      uintptr_t *outSegmentBase)
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    if (images == NULL) {
        return NULL;
    }

    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *header = images[i].imageLoadAddress;
        if (header == NULL) {
            continue;
        }

        uintptr_t slide, start, end, segmentBase;
        computeImageInfo(header, &slide, &start, &end, &segmentBase);

        if (address >= start && address < end) {
            if (outSlide) *outSlide = slide;
            if (outName) *outName = images[i].imageFilePath;
            if (outStart) *outStart = start;
            if (outEnd) *outEnd = end;
            if (outSegmentBase) *outSegmentBase = segmentBase;
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
    g_cache_storage.count = 0;
    atomic_store(&g_cache_ptr, NULL);
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
        for (uint32_t i = 0; i < cache->count; i++) {
            KSBinaryImageRange *entry = &cache->entries[i];
            if (address >= entry->startAddress && address < entry->endAddress) {
                // Cache hit!
                if (outSlide) *outSlide = entry->slide;
                if (outSegmentBase) *outSegmentBase = entry->segmentBase;
                if (outName) *outName = entry->name;
                const struct mach_header *result = entry->header;

                // Release the cache
                atomic_store(&g_cache_ptr, cache);
                return result;
            }
        }

        // Cache miss - do linear scan
        uintptr_t slide = 0;
        const char *name = NULL;
        uintptr_t start = 0, end = 0, segmentBase = 0;
        const struct mach_header *header = linearScanForAddress(address, &slide, &name, &start, &end, &segmentBase);

        if (header != NULL && cache->count < KSBIC_MAX_CACHE_ENTRIES) {
            // Add to cache
            KSBinaryImageRange *newEntry = &cache->entries[cache->count];
            newEntry->startAddress = start;
            newEntry->endAddress = end;
            newEntry->slide = slide;
            newEntry->segmentBase = segmentBase;
            newEntry->header = header;
            newEntry->name = name;
            cache->count++;
        }

        if (outSlide) *outSlide = slide;
        if (outSegmentBase) *outSegmentBase = segmentBase;
        if (outName) *outName = name;

        // Release the cache
        atomic_store(&g_cache_ptr, cache);
        return header;
    } else {
        // FAILED: Cache is in use by another caller
        // Fall back to linear scan without caching
        uintptr_t slide = 0;
        uintptr_t segmentBase = 0;
        const char *name = NULL;
        const struct mach_header *header = linearScanForAddress(address, &slide, &name, NULL, NULL, &segmentBase);

        if (outSlide) *outSlide = slide;
        if (outSegmentBase) *outSegmentBase = segmentBase;
        if (outName) *outName = name;
        return header;
    }
}
