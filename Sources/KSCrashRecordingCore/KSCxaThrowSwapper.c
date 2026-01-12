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
#include <execinfo.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
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

typedef struct {
    uintptr_t image;
    _Atomic(uintptr_t) function;  // Atomic: non-zero signals slot is ready (written last)
    void **binding;               // Pointer to the GOT entry, for restoring original
} KSAddressPair;

// Maximum number of dylibs we expect to handle. Modern iOS apps typically have
// 300-500 dylibs. We pre-allocate to avoid realloc races during dyld callbacks.
#define MAX_CXA_ORIGINALS 2048

static _Atomic(cxa_throw_type) g_cxa_throw_handler = NULL;
static const char *const g_cxa_throw_name = "__cxa_throw";

// Pre-allocated array to avoid realloc during concurrent dyld callbacks
static KSAddressPair g_cxa_originals[MAX_CXA_ORIGINALS];
static _Atomic(size_t) g_cxa_originals_count = 0;

// Track whether we've registered the dyld callback
static _Atomic(bool) g_dyld_callback_registered = false;

// Fallback __cxa_throw for when findAddress fails during concurrent reset.
// This ensures the decorator never returns (which would be undefined behavior).
static _Atomic(uintptr_t) g_fallback_cxa_throw = 0;

// Cached page size to avoid repeated sysconf() syscalls
static uintptr_t g_page_size = 0;
static uintptr_t g_page_mask = 0;

static void ensurePageSizeCached(void)
{
    if (g_page_size == 0) {
        g_page_size = (uintptr_t)sysconf(_SC_PAGESIZE);
        g_page_mask = g_page_size - 1;
    }
}

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

static bool addPair(uintptr_t image, uintptr_t function, void **binding)
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

static bool writeProtectedBinding(void **binding, void *value)
{
    vm_prot_t oldProtection = ksmacho_getSectionProtection(binding);
    bool needsProtectionChange = !(oldProtection & VM_PROT_WRITE);

    // Page-align the address for mprotect (must be page-aligned)
    // Uses cached page size to avoid syscall overhead
    ensurePageSizeCached();
    uintptr_t pageStart = (uintptr_t)binding & ~g_page_mask;
    size_t protectSize = (uintptr_t)binding - pageStart + sizeof(void *);

    if (needsProtectionChange) {
        if (mprotect((void *)pageStart, protectSize, PROT_READ | PROT_WRITE) != 0) {
            KSLOG_ERROR("mprotect failed for binding at %p: %s", (void *)binding, strerror(errno));
            return false;
        }
    }

    *binding = value;

    if (needsProtectionChange) {
        int protection = 0;
        if (oldProtection & VM_PROT_READ) {
            protection |= PROT_READ;
        }
        if (oldProtection & VM_PROT_WRITE) {
            protection |= PROT_WRITE;
        }
        if (oldProtection & VM_PROT_EXECUTE) {
            protection |= PROT_EXEC;
        }
        mprotect((void *)pageStart, protectSize, protection);
    }

    return true;
}

__attribute__((noreturn)) static void __cxa_throw_decorator(void *thrown_exception, void *tinfo, void (*dest)(void *))
{
#define REQUIRED_FRAMES 2

    KSLOG_TRACE("Decorating __cxa_throw");

    cxa_throw_type handler = atomic_load_explicit(&g_cxa_throw_handler, memory_order_acquire);
    if (handler != NULL) {
        handler(thrown_exception, tinfo, dest);
    }

    uintptr_t function = 0;

    void *backtraceArr[REQUIRED_FRAMES];
    int count = backtrace(backtraceArr, REQUIRED_FRAMES);

    Dl_info info;
    if (count >= REQUIRED_FRAMES) {
        if (dladdr(backtraceArr[REQUIRED_FRAMES - 1], &info) != 0) {
            function = findAddress(info.dli_fbase);
        }
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

#undef REQUIRED_FRAMES
}

// Returns true if __cxa_throw was found and rebound in this section
static bool perform_rebinding_with_section(const section_t *dataSection, intptr_t slide, nlist_t *symtab, char *strtab,
                                           uint32_t *indirect_symtab, uintptr_t imageBase)
{
    KSLOG_TRACE("Performing rebinding with section %s,%s", dataSection->segname, dataSection->sectname);

    uint32_t *indirect_symbol_indices = indirect_symtab + dataSection->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + dataSection->addr);
    const uint32_t numSymbols = (uint32_t)(dataSection->size / sizeof(void *));

    // Scan for __cxa_throw - there's at most one per section, so exit early when found
    for (uint32_t i = 0; i < numSymbols; i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        // Symbol names in Mach-O start with '_', so "__cxa_throw" is stored as "___cxa_throw"
        if (symbol_name[0] && symbol_name[1] && strcmp(&symbol_name[1], g_cxa_throw_name) == 0) {
            // Found __cxa_throw - should never be already rebound since we always reset first
            assert(indirect_symbol_bindings[i] != (void *)__cxa_throw_decorator);

            // Only rebind if we successfully store the original. This prevents
            // rebinding when the array is full, which would break exception flow.
            if (addPair(imageBase, (uintptr_t)indirect_symbol_bindings[i], &indirect_symbol_bindings[i])) {
                // Use writeProtectedBinding to handle mprotect for just this pointer
                writeProtectedBinding(&indirect_symbol_bindings[i], (void *)__cxa_throw_decorator);
            }
            return true;  // Early exit - only one __cxa_throw per section
        }
    }

    return false;  // __cxa_throw not found in this section
}

// Returns true if __cxa_throw was found and rebound in this segment
static bool process_segment(const struct mach_header *header, intptr_t slide, const char *segname, nlist_t *symtab,
                            char *strtab, uint32_t *indirect_symtab, uintptr_t imageBase)
{
    KSLOG_TRACE("Processing segment %s", segname);

    const segment_command_t *segment = ksmacho_getSegmentByNameFromHeader((mach_header_t *)header, segname);
    if (segment == NULL) {
        return false;
    }

    // Check lazy symbol pointers first (more common location for __cxa_throw)
    const section_t *lazy_sym_sect = ksmacho_getSectionByTypeFlagFromSegment(segment, S_LAZY_SYMBOL_POINTERS);
    if (lazy_sym_sect != NULL) {
        if (perform_rebinding_with_section(lazy_sym_sect, slide, symtab, strtab, indirect_symtab, imageBase)) {
            return true;  // Found and rebound, no need to check non-lazy
        }
    }

    // Check non-lazy symbol pointers
    const section_t *non_lazy_sym_sect = ksmacho_getSectionByTypeFlagFromSegment(segment, S_NON_LAZY_SYMBOL_POINTERS);
    if (non_lazy_sym_sect != NULL) {
        if (perform_rebinding_with_section(non_lazy_sym_sect, slide, symtab, strtab, indirect_symtab, imageBase)) {
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

    // Skip images with zero slide - they can't have rebindable symbols
    if (slide == 0) {
        return;
    }

    // Get required Mach-O structures for symbol resolution
    const struct symtab_command *symtab_cmd =
        (struct symtab_command *)ksmacho_getCommandByTypeFromHeader((const mach_header_t *)header, LC_SYMTAB);
    const struct dysymtab_command *dysymtab_cmd =
        (struct dysymtab_command *)ksmacho_getCommandByTypeFromHeader((const mach_header_t *)header, LC_DYSYMTAB);
    const segment_command_t *linkedit_segment =
        ksmacho_getSegmentByNameFromHeader((mach_header_t *)header, SEG_LINKEDIT);

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
    if (process_segment(header, slide, SEG_DATA, symtab, strtab, indirect_symtab, imageBase)) {
        return;
    }
    process_segment(header, slide, SEG_DATA_CONST, symtab, strtab, indirect_symtab, imageBase);
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

    bool expected = false;
    if (atomic_compare_exchange_strong_explicit(&g_dyld_callback_registered, &expected, true, memory_order_acq_rel,
                                                memory_order_acquire)) {
        // First time: register for future image loads
        _dyld_register_func_for_add_image(rebind_symbols_for_image);
    } else {
        // Already registered: manually scan all currently loaded images
        // Prefer lock-free access via BinaryImageCache, fall back to dyld functions
        ksdl_init();
        uint32_t count = 0;
        const ks_dyld_image_info *images = ksbic_getImages(&count);
        if (images != NULL) {
            for (uint32_t i = 0; i < count; i++) {
                const struct mach_header *header = images[i].imageLoadAddress;
                intptr_t slide = ksbic_getImageSlide(header);
                rebind_symbols_for_image(header, slide);
            }
        } else {
            // Fallback: use lock-based dyld functions
            count = _dyld_image_count();
            for (uint32_t i = 0; i < count; i++) {
                rebind_symbols_for_image(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
            }
        }
    }
    return 0;
#endif
}

void ksct_swapReset(void)
{
    KSLOG_DEBUG("Resetting __cxa_throw bindings");

#if KSCRASH_HAS_SANITIZER
    KSLOG_DEBUG("Sanitizer detected, nothing to reset");
#else
    // Prevent dyld add-image rebinding while reset is in progress.
    atomic_store_explicit(&g_cxa_throw_handler, NULL, memory_order_release);

    size_t count = atomic_load_explicit(&g_cxa_originals_count, memory_order_acquire);

    for (size_t i = 0; i < count; i++) {
        KSAddressPair *pair = &g_cxa_originals[i];
        // Read function atomically since it's the "ready" signal
        uintptr_t function = atomic_load_explicit(&pair->function, memory_order_acquire);
        if (function != 0 && pair->binding != NULL) {
            KSLOG_TRACE("Restoring binding at %p to %p", (void *)pair->binding, (void *)function);
            bool success = writeProtectedBinding(pair->binding, (void *)function);
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
