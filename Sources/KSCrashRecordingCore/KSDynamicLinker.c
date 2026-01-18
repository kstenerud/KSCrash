//
//  KSDynamicLinker.c
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

#include "KSDynamicLinker.h"

#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/nlist.h>
#include <mach-o/stab.h>
#include <stdatomic.h>
#include <string.h>

#include "KSBinaryImageCache.h"
#include "KSLogger.h"
#include "KSMach-O.h"
#include "KSMemory.h"
#include "KSPlatformSpecificDefines.h"

// MARK: - Symbol Cache
//
// Caches Dl_info results to avoid repeated symbol table scans.
// Uses the same async-signal-safe pattern as KSBinaryImageCache:
// - Pre-allocated static storage (no malloc)
// - Atomic pointer swap for lock-free exclusive access
// - Non-blocking fallback when cache is in use

#define KSDL_SYMBOL_CACHE_SIZE 2048

typedef struct {
    uintptr_t address;       // The looked-up address (key)
    uintptr_t symbolAddr;    // dli_saddr
    const char *symbolName;  // dli_sname (points into Mach-O string table)
    const char *imageName;   // dli_fname (points into dyld info)
    const void *imageBase;   // dli_fbase
    uint8_t hits;            // Hit count for eviction (0-255, saturating)
} KSSymbolCacheEntry;

typedef struct {
    KSSymbolCacheEntry entries[KSDL_SYMBOL_CACHE_SIZE];
    uint32_t count;  // Number of valid entries
} KSSymbolCache;

static KSSymbolCache g_symbol_cache_storage = { .count = 0 };
static _Atomic(KSSymbolCache *) g_symbol_cache_ptr = NULL;
static _Atomic(bool) g_initialized = false;

// Declared in KSBinaryImageCache.c (not in public header)
extern void ksbic_resetCache(void);

void ksdl_init(void)
{
    // Only initialize once
    if (atomic_exchange(&g_initialized, true)) {
        return;
    }

// Initialize the binary image cache first (we depend on it)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ksbic_init();
#pragma clang diagnostic pop

    // Initialize the symbol cache
    g_symbol_cache_storage.count = 0;
    atomic_store(&g_symbol_cache_ptr, &g_symbol_cache_storage);
}

void ksdl_resetCache(void)
{
    // Reset binary image cache first (it has its own locking)
    ksbic_resetCache();

    // Acquire exclusive access to the symbol cache before resetting
    KSSymbolCache *cache = atomic_exchange(&g_symbol_cache_ptr, NULL);
    if (cache != NULL) {
        cache->count = 0;
        atomic_store(&g_symbol_cache_ptr, cache);
    } else {
        // Cache is in use by another thread - reset storage directly
        // and restore pointer (the other thread will see stale data but
        // that's acceptable for a reset operation)
        g_symbol_cache_storage.count = 0;
        atomic_store(&g_symbol_cache_ptr, &g_symbol_cache_storage);
    }

    atomic_store(&g_initialized, false);
}

#ifndef KSDL_MaxCrashInfoStringLength
#define KSDL_MaxCrashInfoStringLength 4096
#endif

#pragma pack(8)
typedef struct {
    unsigned version;
    const char *message;
    const char *signature;
    const char *backtrace;
    const char *message2;
    void *reserved;
    void *reserved2;
    void *reserved3;  // First introduced in version 5
} crash_info_t;
#pragma pack()
#define KSDL_SECT_CRASH_INFO "__crash_info"

/** Perform the actual symbol lookup without caching.
 *  This scans the symbol table to find the closest symbol to the given address.
 */
static bool ksdl_dladdr_uncached(const uintptr_t address, Dl_info *const info)
{
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;

    uintptr_t imageVMAddrSlide = 0;
    uintptr_t imageSegmentBase = 0;
    const char *name = NULL;
    const struct mach_header *header =
        ksbic_getImageDetailsForAddress(address, &imageVMAddrSlide, &imageSegmentBase, &name);
    if (header == NULL) {
        return false;
    }

    const uintptr_t addressWithSlide = address - imageVMAddrSlide;
    const uintptr_t segmentBase = imageSegmentBase + imageVMAddrSlide;
    if (segmentBase == 0) {
        return false;
    }

    info->dli_fname = (char *)name;
    info->dli_fbase = (void *)header;

    // Find symbol tables and get whichever symbol is closest to the address.
    const nlist_t *bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPtr = ksmacho_firstCmdAfterHeader(header);
    if (cmdPtr == 0) {
        return false;
    }
    for (uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++) {
        const struct load_command *loadCmd = (struct load_command *)cmdPtr;
        if (loadCmd->cmd == LC_SYMTAB) {
            const struct symtab_command *symtabCmd = (struct symtab_command *)cmdPtr;
            const nlist_t *symbolTable = (nlist_t *)(segmentBase + symtabCmd->symoff);
            const uintptr_t stringTable = segmentBase + symtabCmd->stroff;

            for (uint32_t iSym = 0; iSym < symtabCmd->nsyms; iSym++) {
                // Skip all debug N_STAB symbols
                if ((symbolTable[iSym].n_type & N_STAB) != 0) {
                    continue;
                }

                // If n_value is 0, the symbol refers to an external object.
                if (symbolTable[iSym].n_value != 0) {
                    uintptr_t symbolBase = symbolTable[iSym].n_value;
                    uintptr_t currentDistance = addressWithSlide - symbolBase;
                    if ((addressWithSlide >= symbolBase) && (currentDistance <= bestDistance)) {
                        bestMatch = symbolTable + iSym;
                        bestDistance = currentDistance;
                        if (currentDistance == 0) {
                            break;  // Exact match - can't do better
                        }
                    }
                }
            }
            if (bestMatch != NULL) {
                info->dli_saddr = (void *)(bestMatch->n_value + imageVMAddrSlide);
                if (bestMatch->n_desc == 16) {
                    // This image has been stripped. The name is meaningless, and
                    // almost certainly resolves to "_mh_execute_header"
                    info->dli_sname = NULL;
                } else {
                    info->dli_sname = (char *)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);
                    if (*info->dli_sname == '_') {
                        info->dli_sname++;
                    }
                }
                break;
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }

    return true;
}

bool ksdl_dladdr(const uintptr_t address, Dl_info *const info)
{
    // Try to acquire exclusive access to the cache
    KSSymbolCache *cache = atomic_exchange(&g_symbol_cache_ptr, NULL);

    if (cache != NULL) {
        // SUCCESS: We have exclusive access to the cache

        // Single pass: search for hit AND track min-hits for potential eviction
        uint32_t minHitsIdx = 0;
        uint8_t minHits = 255;

        for (uint32_t i = 0; i < cache->count; i++) {
            if (cache->entries[i].address == address) {
                // Cache hit - populate info from cache
                KSSymbolCacheEntry *entry = &cache->entries[i];
                info->dli_fname = (char *)entry->imageName;
                info->dli_fbase = (void *)entry->imageBase;
                info->dli_sname = (char *)entry->symbolName;
                info->dli_saddr = (void *)entry->symbolAddr;

                // Increment hit count (saturating at 255)
                if (entry->hits < 255) {
                    entry->hits++;
                }

                // Release the cache
                atomic_store(&g_symbol_cache_ptr, cache);
                return true;
            }

            // Track lowest hits for potential eviction
            if (cache->entries[i].hits < minHits) {
                minHits = cache->entries[i].hits;
                minHitsIdx = i;
            }
        }

        // Cache miss - do the full lookup
        bool result = ksdl_dladdr_uncached(address, info);

        if (result) {
            // Add to cache
            uint32_t idx;
            if (cache->count < KSDL_SYMBOL_CACHE_SIZE) {
                // Cache not full - use next slot
                idx = cache->count;
                cache->count++;
            } else {
                // Cache full - evict entry with lowest hits (already found above)
                idx = minHitsIdx;
            }

            cache->entries[idx].address = address;
            cache->entries[idx].symbolAddr = (uintptr_t)info->dli_saddr;
            cache->entries[idx].symbolName = info->dli_sname;
            cache->entries[idx].imageName = info->dli_fname;
            cache->entries[idx].imageBase = info->dli_fbase;
            cache->entries[idx].hits = 1;
        }

        // Release the cache
        atomic_store(&g_symbol_cache_ptr, cache);
        return result;
    } else {
        // FAILED: Cache is in use by another caller
        // Fall back to uncached lookup
        return ksdl_dladdr_uncached(address, info);
    }
}

static bool isValidCrashInfoMessage(const char *str)
{
    if (str == NULL) {
        return false;
    }
    int maxReadableBytes = ksmem_maxReadableBytes(str, KSDL_MaxCrashInfoStringLength + 1);
    if (maxReadableBytes == 0) {
        return false;
    }
    for (int i = 0; i < maxReadableBytes; ++i) {
        if (str[i] == 0) {
            return true;
        }
    }
    return false;
}

static void getCrashInfo(const struct mach_header *header, KSBinaryImage *buffer)
{
    unsigned long size = 0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-align"
    crash_info_t *crashInfo =
        (crash_info_t *)getsectiondata((mach_header_t *)header, SEG_DATA, KSDL_SECT_CRASH_INFO, &size);
#pragma clang diagnostic pop
    if (crashInfo == NULL) {
        return;
    }

    KSLOG_TRACE("Found crash info section in binary: %s", buffer->name);
    const unsigned int minimalSize = offsetof(crash_info_t, reserved);  // Include message and message2
    if (size < minimalSize) {
        KSLOG_TRACE("Skipped reading crash info: section is too small");
        return;
    }
    if (!ksmem_isMemoryReadable(crashInfo, minimalSize)) {
        KSLOG_TRACE("Skipped reading crash info: section memory is not readable");
        return;
    }
    if (crashInfo->version != 4 && crashInfo->version != 5) {
        KSLOG_TRACE("Skipped reading crash info: invalid version '%d'", crashInfo->version);
        return;
    }
    if (crashInfo->message == NULL && crashInfo->message2 == NULL) {
        KSLOG_TRACE("Skipped reading crash info: both messages are null");
        return;
    }

    if (isValidCrashInfoMessage(crashInfo->message)) {
        KSLOG_DEBUG("Found first message: %s", crashInfo->message);
        buffer->crashInfoMessage = crashInfo->message;
    }
    if (isValidCrashInfoMessage(crashInfo->message2)) {
        KSLOG_DEBUG("Found second message: %s", crashInfo->message2);
        buffer->crashInfoMessage2 = crashInfo->message2;
    }
    if (isValidCrashInfoMessage(crashInfo->backtrace)) {
        KSLOG_DEBUG("Found backtrace: %s", crashInfo->backtrace);
        buffer->crashInfoBacktrace = crashInfo->backtrace;
    }
    if (isValidCrashInfoMessage(crashInfo->signature)) {
        KSLOG_DEBUG("Found signature: %s", crashInfo->signature);
        buffer->crashInfoSignature = crashInfo->signature;
    }
}

bool ksdl_binaryImageForHeader(const void *const header_ptr, const char *const image_name, KSBinaryImage *buffer)
{
    const struct mach_header *header = (const struct mach_header *)header_ptr;
    uintptr_t cmdPtr = ksmacho_firstCmdAfterHeader(header);
    if (cmdPtr == 0) {
        return false;
    }

    // Look for the TEXT segment to get the image size and compute ASLR slide.
    // Also look for a UUID command.
    uint64_t imageSize = 0;
    uint64_t imageVmAddr = 0;
    uintptr_t imageSlide = 0;
    uint64_t version = 0;
    uint8_t *uuid = NULL;

    for (uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++) {
        struct load_command *loadCmd = (struct load_command *)cmdPtr;
        switch (loadCmd->cmd) {
            case LC_SEGMENT: {
                struct segment_command *segCmd = (struct segment_command *)cmdPtr;
                if (strcmp(segCmd->segname, SEG_TEXT) == 0) {
                    imageSize = segCmd->vmsize;
                    imageVmAddr = segCmd->vmaddr;
                    imageSlide = (uintptr_t)header - segCmd->vmaddr;
                }
                break;
            }
            case LC_SEGMENT_64: {
                struct segment_command_64 *segCmd = (struct segment_command_64 *)cmdPtr;
                if (strcmp(segCmd->segname, SEG_TEXT) == 0) {
                    imageSize = segCmd->vmsize;
                    imageVmAddr = segCmd->vmaddr;
                    imageSlide = (uintptr_t)header - (uintptr_t)segCmd->vmaddr;
                }
                break;
            }
            case LC_UUID: {
                struct uuid_command *uuidCmd = (struct uuid_command *)cmdPtr;
                uuid = uuidCmd->uuid;
                break;
            }
            case LC_ID_DYLIB: {
                struct dylib_command *dc = (struct dylib_command *)cmdPtr;
                version = dc->dylib.current_version;
                break;
            }
            default:
                break;
        }
        cmdPtr += loadCmd->cmdsize;
    }

    buffer->address = (uintptr_t)header;
    buffer->vmAddress = imageVmAddr;
    buffer->size = imageSize;
    buffer->vmAddressSlide = imageSlide;
    buffer->name = image_name;
    buffer->uuid = uuid;
    buffer->cpuType = header->cputype;
    buffer->cpuSubType = header->cpusubtype;
    buffer->majorVersion = version >> 16;
    buffer->minorVersion = (version >> 8) & 0xff;
    buffer->revisionVersion = version & 0xff;
    getCrashInfo(header, buffer);

    return true;
}
