//
//  KSCxaThrowSwapper.cpp
//
//  Copyright (c) 2019 YANDEX LLC. All rights reserved.
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
//
// Inspired by facebook/fishhook
// https://github.com/facebook/fishhook
//
// Copyright (c) 2013, Facebook, Inc.
// All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//   * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//   * Neither the name Facebook nor the names of its contributors may be used to
//     endorse or promote products derived from this software without specific
//     prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "KSCxaThrowSwapper.h"

#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

#include "KSBinaryImageCache.h"
#include "KSDynamicLinker.h"
#include "KSLogger.h"
#include "KSMach-O.h"
#include "KSPlatformSpecificDefines.h"
#include "KSSystemCapabilities.h"

#if !KSCRASH_HAS_SANITIZER

// Thread-safety: `function` is the synchronization point. Writers store all other fields
// before storing `function` with release semantics. Readers must load `function` with
// acquire semantics and only access other fields if `function != 0`.
typedef struct {
    uintptr_t image;
    _Atomic(uintptr_t) function;  // Atomic: non-zero signals slot is ready (written last)
    void **binding;               // Pointer to the GOT entry, for restoring original
    bool isConstSegment;          // True if binding is in __DATA_CONST (needs mprotect)
} KSAddressPair;

// Maximum number of dylibs we expect to handle. Modern iOS apps typically have
// 300-500 dylibs, but "super apps" can exceed 2000. We pre-allocate to avoid
// realloc races during dyld callbacks. Memory impact: 4096 * 32 bytes = 128KB.
#define MAX_CXA_ORIGINALS 4096

static _Atomic(cxa_throw_type) g_cxa_throw_handler = NULL;

// Pre-allocated array to avoid realloc during concurrent dyld callbacks
static KSAddressPair g_cxa_originals[MAX_CXA_ORIGINALS];
static _Atomic(size_t) g_cxa_originals_count = 0;

// Fallback __cxa_throw for when findAddress fails during concurrent reset.
// This ensures the decorator never returns (which would be undefined behavior).
static _Atomic(uintptr_t) g_fallback_cxa_throw = 0;

// Cached page size to avoid repeated sysconf() syscalls
static uintptr_t g_page_size = 0;
static uintptr_t g_page_mask = 0;
static pthread_once_t g_page_size_once = PTHREAD_ONCE_INIT;

static void initPageSize(void)
{
    g_page_size = (uintptr_t)sysconf(_SC_PAGESIZE);
    g_page_mask = g_page_size - 1;
}

static void ensurePageSizeCached(void) { pthread_once(&g_page_size_once, initPageSize); }

static bool reserveIndex(size_t *out_index)
{
    size_t count = atomic_load_explicit(&g_cxa_originals_count, memory_order_relaxed);
    for (;;) {
        if (count >= MAX_CXA_ORIGINALS) {
            return false;
        }
        if (atomic_compare_exchange_weak_explicit(&g_cxa_originals_count, &count, count + 1, memory_order_acq_rel,
                                                  memory_order_relaxed)) {
            *out_index = count;
            return true;
        }
    }
}

static bool addPair(uintptr_t image, uintptr_t function, void **binding, bool isConstSegment)
{
    KSLOG_DEBUG("Adding address pair: image=%p, function=%p", (void *)image, (void *)function);

    // Atomically reserve a slot in the array without exceeding MAX_CXA_ORIGINALS
    size_t index = 0;
    if (!reserveIndex(&index)) {
        KSLOG_ERROR("Exceeded maximum number of dylibs (%d)", MAX_CXA_ORIGINALS);
        return false;
    }

    // Write to the reserved slot. Write function LAST with release semantics
    // to signal the slot is ready. findAddress uses acquire to read function
    // and skips zero entries, so this ensures image/binding are visible when
    // function is non-zero.
    g_cxa_originals[index].image = image;
    g_cxa_originals[index].binding = binding;
    g_cxa_originals[index].isConstSegment = isConstSegment;
    atomic_store_explicit(&g_cxa_originals[index].function, function, memory_order_release);

    // Capture the first valid __cxa_throw as fallback (only once, never cleared)
    uintptr_t expected = 0;
    atomic_compare_exchange_strong_explicit(&g_fallback_cxa_throw, &expected, function, memory_order_release,
                                            memory_order_relaxed);

    return true;
}

static uintptr_t findAddress(void *address)
{
    KSLOG_TRACE("Finding address for %p", address);

    // Read the count atomically to know how many slots have been reserved
    size_t count = atomic_load_explicit(&g_cxa_originals_count, memory_order_acquire);
    for (size_t i = 0; i < count; i++) {
        // Read function with acquire semantics. A non-zero value means the slot
        // is fully written (addPair writes function last with release semantics).
        // This acquire-release pairing ensures image/binding are visible.
        uintptr_t function = atomic_load_explicit(&g_cxa_originals[i].function, memory_order_acquire);
        if (function == 0) {
            // Slot reserved but not yet written, skip it
            continue;
        }
        if (g_cxa_originals[i].image == (uintptr_t)address) {
            return function;
        }
    }
    KSLOG_WARN("Address %p not found", address);
    return (uintptr_t)NULL;
}

static bool writeProtectedBinding(void **binding, void *value, bool isConstSegment)
{
    // __DATA_CONST segments are read-only and need mprotect to write.
    // __DATA segments are writable, so we can write directly without syscalls.
    // This avoids the vm_region syscall that ksmacho_getSectionProtection would use.
    //
    // Note: mprotect operates on page granularity. While multiple dylibs could
    // theoretically share a page, Mach-O segments are typically page-aligned in
    // memory, making it safe to toggle protection during serial image loading.
    if (!isConstSegment) {
        *binding = value;
        return true;
    }

    // Page-align the address for mprotect (must be page-aligned)
    // Uses cached page size to avoid syscall overhead
    ensurePageSizeCached();
    uintptr_t pageStart = (uintptr_t)binding & ~g_page_mask;
    size_t protectSize = (uintptr_t)binding - pageStart + sizeof(void *);

    if (mprotect((void *)pageStart, protectSize, PROT_READ | PROT_WRITE) != 0) {
        KSLOG_ERROR("mprotect failed for binding at %p: %s", (void *)binding, strerror(errno));
        return false;
    }

    *binding = value;

    // Restore read-only protection. __DATA_CONST is always non-executable and read-only,
    // so PROT_READ is the correct restoration. If this code were ever extended to other
    // segments, we'd need to query/preserve the original protection flags.
    if (mprotect((void *)pageStart, protectSize, PROT_READ) != 0) {
        KSLOG_WARN("mprotect restore failed for binding at %p: %s", (void *)binding, strerror(errno));
        // Continue anyway - the write succeeded, protection restore is best-effort
    }

    return true;
}

__attribute__((noreturn)) static void __cxa_throw_decorator(void *thrown_exception, void *tinfo, void (*dest)(void *))
{
    KSLOG_TRACE("Decorating __cxa_throw");

    cxa_throw_type handler = atomic_load_explicit(&g_cxa_throw_handler, memory_order_acquire);
    if (handler != NULL) {
        handler(thrown_exception, tinfo, dest);
    }

    uintptr_t function = 0;

    // Get the return address to identify which image threw the exception.
    // __builtin_return_address(0) returns the address our caller will return to,
    // which is in the code that executed `throw`. We use dladdr() to find which
    // image contains that address, then look up the original __cxa_throw for
    // that image. This is faster than backtrace() since it's a single register
    // read rather than a full stack walk.
    //
    // __builtin_extract_return_addr strips pointer authentication bits on ARM64e
    // and is a no-op on other architectures. We check for NULL in case the
    // builtin fails under unusual optimization/unwind settings.
    void *return_addr = __builtin_extract_return_addr(__builtin_return_address(0));
    Dl_info info;
    if (return_addr != NULL && dladdr(return_addr, &info) != 0) {
        function = findAddress(info.dli_fbase);
    }

    // If we couldn't find the image-specific original, use the fallback.
    // This can happen during concurrent ksct_swapReset() when the originals
    // array is being cleared while exceptions are in flight.
    if (function == 0) {
        function = atomic_load_explicit(&g_fallback_cxa_throw, memory_order_acquire);
        KSLOG_TRACE("Using fallback __cxa_throw at %p", (void *)function);
    }

    if (function != 0) {
        KSLOG_TRACE("Calling original __cxa_throw function at %p", (void *)function);
        cxa_throw_type original = (cxa_throw_type)function;
        original(thrown_exception, tinfo, dest);
    }

    // __cxa_throw is noreturn. If we reach here, something went very wrong.
    // Trap to make the failure visible rather than causing undefined behavior.
    KSLOG_ERROR("Failed to find any valid __cxa_throw function");
    __builtin_trap();
}

// Returns true if __cxa_throw was found and rebound in this section
static bool perform_rebinding_with_section(const section_t *dataSection, intptr_t slide, nlist_t *symtab, char *strtab,
                                           uint32_t *indirect_symtab, uintptr_t imageBase, bool isConstSegment,
                                           uint32_t nsyms, uint32_t strsize, uint32_t nindirectsyms)
{
    // Symbol names in Mach-O start with '_', so "__cxa_throw" is stored as "___cxa_throw"
    static const char kNeedle[] = "__cxa_throw";
    static const size_t kNeedleLen = sizeof(kNeedle) - 1;

    KSLOG_TRACE("Performing rebinding with section %s,%s", dataSection->segname, dataSection->sectname);

    const uint32_t numSymbols = (uint32_t)(dataSection->size / sizeof(void *));

    // Bounds check: ensure reserved1 + numSymbols doesn't exceed indirect symbol table size.
    // This prevents walking past indirect_symtab if reserved1 is corrupt.
    uint32_t start = dataSection->reserved1;
    if (start > nindirectsyms || numSymbols > nindirectsyms - start) {
        return false;
    }

    uint32_t *indirect_symbol_indices = indirect_symtab + start;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + dataSection->addr);

    // Scan for __cxa_throw. In standard Mach-O, each imported symbol appears at most once
    // per section type (lazy or non-lazy). We check both section types in process_segment.
    for (uint32_t i = 0; i < numSymbols; i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        // Bounds check: ensure symtab_index is within the symbol table
        if (symtab_index >= nsyms) {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        // Bounds check: ensure string offset allows reading the full symbol name + null terminator.
        // Use 64-bit arithmetic to avoid overflow with large offsets.
        uint64_t need = (uint64_t)strtab_offset + 1 + kNeedleLen;
        if (need >= strsize) {
            continue;
        }
        char *symbol_name = strtab + strtab_offset;
        // Fast exact match for "___cxa_throw":
        // 1. Check leading '_' (all Mach-O symbols have this prefix)
        // 2. Use memcmp for fixed-length compare (faster than strcmp for known length)
        // 3. Verify null terminator to ensure exact match, not just prefix
        if (symbol_name[0] == '_' && memcmp(symbol_name + 1, kNeedle, kNeedleLen) == 0 &&
            symbol_name[1 + kNeedleLen] == '\0') {
            // Already rebound - skip (handles re-registration case)
            if (indirect_symbol_bindings[i] == (void *)__cxa_throw_decorator) {
                return true;
            }

            // Only rebind if we successfully store the original. This prevents
            // rebinding when the array is full, which would break exception flow.
            if (addPair(imageBase, (uintptr_t)indirect_symbol_bindings[i], &indirect_symbol_bindings[i],
                        isConstSegment)) {
                if (!writeProtectedBinding(&indirect_symbol_bindings[i], (void *)__cxa_throw_decorator,
                                           isConstSegment)) {
                    KSLOG_ERROR("Failed to rebind __cxa_throw at %p", (void *)&indirect_symbol_bindings[i]);
                    return false;
                }
            }
            return true;  // Early exit - only one __cxa_throw per section
        }
    }

    return false;  // __cxa_throw not found in this section
}

// Returns true if __cxa_throw was found and rebound in this segment
static bool process_segment_direct(const segment_command_t *segment, intptr_t slide, nlist_t *symtab, char *strtab,
                                   uint32_t *indirect_symtab, uintptr_t imageBase, bool isConstSegment, uint32_t nsyms,
                                   uint32_t strsize, uint32_t nindirectsyms)
{
    if (segment == NULL) {
        return false;
    }

    KSLOG_TRACE("Processing segment %s", segment->segname);

    // Single pass through sections to find both lazy and non-lazy symbol pointer sections.
    // Use the standard Mach-O iteration pattern: sections immediately follow the segment header,
    // so (segment + 1) points to the first section, and section++ advances correctly.
    const section_t *lazy_sym_sect = NULL;
    const section_t *non_lazy_sym_sect = NULL;

    const section_t *section = (const section_t *)(segment + 1);
    for (uint32_t i = 0; i < segment->nsects; i++, section++) {
        uint32_t section_type = section->flags & SECTION_TYPE;
        if (section_type == S_LAZY_SYMBOL_POINTERS) {
            lazy_sym_sect = section;
        } else if (section_type == S_NON_LAZY_SYMBOL_POINTERS) {
            non_lazy_sym_sect = section;
        }
        // Early exit if we found both
        if (lazy_sym_sect != NULL && non_lazy_sym_sect != NULL) {
            break;
        }
    }

    // Check lazy symbol pointers first (more common location for __cxa_throw)
    if (lazy_sym_sect != NULL) {
        if (perform_rebinding_with_section(lazy_sym_sect, slide, symtab, strtab, indirect_symtab, imageBase,
                                           isConstSegment, nsyms, strsize, nindirectsyms)) {
            return true;  // Found and rebound, no need to check non-lazy
        }
    }

    // Check non-lazy symbol pointers
    if (non_lazy_sym_sect != NULL) {
        if (perform_rebinding_with_section(non_lazy_sym_sect, slide, symtab, strtab, indirect_symtab, imageBase,
                                           isConstSegment, nsyms, strsize, nindirectsyms)) {
            return true;
        }
    }

    return false;
}

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide)
{
    // Skip if handler is NULL (we're in reset state)
    if (atomic_load_explicit(&g_cxa_throw_handler, memory_order_acquire) == NULL) {
        return;
    }

    // The header pointer IS the image base address (dli_fbase in Dl_info)
    uintptr_t imageBase = (uintptr_t)header;

    // Single pass through load commands to collect all needed structures.
    // This avoids multiple passes that helper functions like ksmacho_getSegmentByNameFromHeader would require.
    const struct symtab_command *symtab_cmd = NULL;
    const struct dysymtab_command *dysymtab_cmd = NULL;
    const segment_command_t *linkedit_segment = NULL;
    const segment_command_t *data_segment = NULL;
    const segment_command_t *data_const_segment = NULL;

    uintptr_t current = (uintptr_t)header + sizeof(mach_header_t);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *cmd = (const struct load_command *)current;
        if (cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (const struct symtab_command *)cmd;
        } else if (cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (const struct dysymtab_command *)cmd;
        } else if (cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            // Cast via void* to avoid alignment warnings - load commands are properly aligned in Mach-O
            const segment_command_t *seg = (const segment_command_t *)(const void *)cmd;
            // Fast rejection: all segments we care about start with '_' (__LINKEDIT, __DATA, __DATA_CONST).
            // This avoids strcmp calls for unrelated segments like __TEXT, __PAGEZERO, etc.
            const char first = seg->segname[0];
            if (first == '_') {
                if (strcmp(seg->segname, SEG_LINKEDIT) == 0) {
                    linkedit_segment = seg;
                } else if (strcmp(seg->segname, SEG_DATA) == 0) {
                    data_segment = seg;
                } else if (strcmp(seg->segname, SEG_DATA_CONST) == 0) {
                    data_const_segment = seg;
                }
            }
        }
        current += cmd->cmdsize;
    }

    if (symtab_cmd == NULL || dysymtab_cmd == NULL || linkedit_segment == NULL) {
        return;
    }

    // Compute base addresses for symbol/string tables
    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

    // Try SEG_DATA first (more common), then SEG_DATA_CONST
    // Early exit if found - each image has at most one __cxa_throw binding
    if (process_segment_direct(data_segment, slide, symtab, strtab, indirect_symtab, imageBase, false,
                               symtab_cmd->nsyms, symtab_cmd->strsize, dysymtab_cmd->nindirectsyms)) {
        return;
    }
    process_segment_direct(data_const_segment, slide, symtab, strtab, indirect_symtab, imageBase, true,
                           symtab_cmd->nsyms, symtab_cmd->strsize, dysymtab_cmd->nindirectsyms);
}
#endif  // KSCRASH_HAS_SANITIZER

int ksct_swap(const cxa_throw_type handler)
{
    KSLOG_DEBUG("Swapping __cxa_throw handler");

#if KSCRASH_HAS_SANITIZER
    // Sanitizers (ASan, TSan, etc.) also intercept __cxa_throw and conflict
    // with our decorator, causing hangs during exception handling.
    KSLOG_DEBUG("Sanitizer detected, skipping __cxa_throw swap");
    (void)handler;
    return 0;
#else
    // Cache page size upfront to avoid syscall overhead during rebinding
    ensurePageSizeCached();

    // Reset any existing swap first to restore original bindings
    ksct_swapReset();

    // Store the handler before registering callback or scanning images
    // This ensures the handler is visible when rebind_symbols_for_image runs
    atomic_store_explicit(&g_cxa_throw_handler, handler, memory_order_release);

    // Initialize and scan all currently loaded images.
    // The callback skips already-swapped images, so re-scanning is safe.
    ksdl_init();
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    if (images != NULL) {
        for (uint32_t i = 0; i < count; i++) {
            const struct mach_header *header = images[i].imageLoadAddress;
            intptr_t slide = ksbic_getImageSlide(header);
            rebind_symbols_for_image(header, slide);
        }
    }

    // Register for future image loads (replaces any previous callback)
    ksbic_registerForImageAdded(rebind_symbols_for_image);

    return 0;
#endif
}

void ksct_swapReset(void)
{
    KSLOG_DEBUG("Resetting __cxa_throw bindings");

#if KSCRASH_HAS_SANITIZER
    KSLOG_DEBUG("Sanitizer detected, nothing to reset");
#else
    // Unregister dyld callback and prevent rebinding while reset is in progress.
    ksbic_registerForImageAdded(NULL);
    atomic_store_explicit(&g_cxa_throw_handler, NULL, memory_order_release);

    size_t count = atomic_load_explicit(&g_cxa_originals_count, memory_order_acquire);

    for (size_t i = 0; i < count; i++) {
        KSAddressPair *pair = &g_cxa_originals[i];
        // Read function atomically since it's the "ready" signal
        uintptr_t function = atomic_load_explicit(&pair->function, memory_order_acquire);
        if (function != 0 && pair->binding != NULL) {
            KSLOG_TRACE("Restoring binding at %p to %p", (void *)pair->binding, (void *)function);
            // Use stored isConstSegment to avoid vm_region syscall
            bool success = writeProtectedBinding(pair->binding, (void *)function, pair->isConstSegment);
            if (!success) {
                KSLOG_ERROR("Failed to restore binding at %p", (void *)pair->binding);
            }
            assert(success);
        }
        // Clear the slot so it's not considered "ready" anymore
        atomic_store_explicit(&pair->function, 0, memory_order_release);
    }

    atomic_store_explicit(&g_cxa_originals_count, 0, memory_order_release);
#endif
}
