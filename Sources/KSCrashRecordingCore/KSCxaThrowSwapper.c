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

#include <dlfcn.h>
#include <errno.h>
#include <execinfo.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>

#include "KSLogger.h"
#include "KSMach-O.h"
#include "KSPlatformSpecificDefines.h"

typedef struct {
    uintptr_t image;
    uintptr_t function;
} KSAddressPair;

static cxa_throw_type g_cxa_throw_handler = NULL;
static const char *const g_cxa_throw_name = "__cxa_throw";

static KSAddressPair *g_cxa_originals = NULL;
static size_t g_cxa_originals_capacity = 0;
static size_t g_cxa_originals_count = 0;

static void addPair(KSAddressPair pair)
{
    KSLOG_DEBUG("Adding address pair: image=%p, function=%p", (void *)pair.image, (void *)pair.function);

    if (g_cxa_originals_count == g_cxa_originals_capacity) {
        g_cxa_originals_capacity *= 2;
        g_cxa_originals = (KSAddressPair *)realloc(g_cxa_originals, sizeof(KSAddressPair) * g_cxa_originals_capacity);
        if (g_cxa_originals == NULL) {
            KSLOG_ERROR("Failed to realloc memory for g_cxa_originals: %s", strerror(errno));
            return;
        }
    }
    memcpy(&g_cxa_originals[g_cxa_originals_count++], &pair, sizeof(KSAddressPair));
}

static uintptr_t findAddress(void *address)
{
    KSLOG_TRACE("Finding address for %p", address);

    for (size_t i = 0; i < g_cxa_originals_count; i++) {
        if (g_cxa_originals[i].image == (uintptr_t)address) {
            return g_cxa_originals[i].function;
        }
    }
    KSLOG_WARN("Address %p not found", address);
    return (uintptr_t)NULL;
}

static void __cxa_throw_decorator(void *thrown_exception, void *tinfo, void (*dest)(void *))
{
#define REQUIRED_FRAMES 2

    KSLOG_TRACE("Decorating __cxa_throw");

    g_cxa_throw_handler(thrown_exception, tinfo, dest);

    void *backtraceArr[REQUIRED_FRAMES];
    int count = backtrace(backtraceArr, REQUIRED_FRAMES);

    Dl_info info;
    if (count >= REQUIRED_FRAMES) {
        if (dladdr(backtraceArr[REQUIRED_FRAMES - 1], &info) != 0) {
            uintptr_t function = findAddress(info.dli_fbase);
            if (function != (uintptr_t)NULL) {
                KSLOG_TRACE("Calling original __cxa_throw function at %p", (void *)function);
                cxa_throw_type original = (cxa_throw_type)function;
                original(thrown_exception, tinfo, dest);
            }
        }
    }
#undef REQUIRED_FRAMES
}

static void perform_rebinding_with_section(const section_t *dataSection, intptr_t slide, nlist_t *symtab, char *strtab,
                                           uint32_t *indirect_symtab)
{
    KSLOG_TRACE("Performing rebinding with section %s,%s", dataSection->segname, dataSection->sectname);

    const bool isDataConst = strcmp(dataSection->segname, SEG_DATA_CONST) == 0;
    uint32_t *indirect_symbol_indices = indirect_symtab + dataSection->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + dataSection->addr);
    vm_prot_t oldProtection = VM_PROT_READ;
    if (isDataConst) {
        oldProtection = ksmacho_getSectionProtection(indirect_symbol_bindings);
        if (mprotect(indirect_symbol_bindings, dataSection->size, PROT_READ | PROT_WRITE) != 0) {
            KSLOG_DEBUG("mprotect failed to set PROT_READ | PROT_WRITE for section %s,%s: %s", dataSection->segname,
                        dataSection->sectname, strerror(errno));
            return;
        }
    }
    for (uint i = 0; i < dataSection->size / sizeof(void *); i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        bool symbol_name_longer_than_1 = symbol_name[0] && symbol_name[1];
        if (symbol_name_longer_than_1 && strcmp(&symbol_name[1], g_cxa_throw_name) == 0) {
            Dl_info info;
            if (dladdr(dataSection, &info) != 0) {
                KSAddressPair pair = { (uintptr_t)info.dli_fbase, (uintptr_t)indirect_symbol_bindings[i] };
                addPair(pair);
            }
            indirect_symbol_bindings[i] = (void *)__cxa_throw_decorator;
            continue;
        }
    }
    if (isDataConst) {
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
        if (mprotect(indirect_symbol_bindings, dataSection->size, protection) != 0) {
            KSLOG_ERROR("mprotect failed to restore protection for section %s,%s: %s", dataSection->segname,
                        dataSection->sectname, strerror(errno));
        }
    }
}

static void process_segment(const struct mach_header *header, intptr_t slide, const char *segname, nlist_t *symtab,
                            char *strtab, uint32_t *indirect_symtab)
{
    KSLOG_DEBUG("Processing segment %s", segname);

    const segment_command_t *segment = ksmacho_getSegmentByNameFromHeader((mach_header_t *)header, segname);
    if (segment != NULL) {
        const section_t *lazy_sym_sect = ksmacho_getSectionByTypeFlagFromSegment(segment, S_LAZY_SYMBOL_POINTERS);
        const section_t *non_lazy_sym_sect =
            ksmacho_getSectionByTypeFlagFromSegment(segment, S_NON_LAZY_SYMBOL_POINTERS);

        if (lazy_sym_sect != NULL) {
            perform_rebinding_with_section(lazy_sym_sect, slide, symtab, strtab, indirect_symtab);
        }
        if (non_lazy_sym_sect != NULL) {
            perform_rebinding_with_section(non_lazy_sym_sect, slide, symtab, strtab, indirect_symtab);
        }
    } else {
        KSLOG_WARN("Segment %s not found", segname);
    }
}

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide)
{
    KSLOG_TRACE("Rebinding symbols for image with slide %p", (void *)slide);

    Dl_info info;
    if (dladdr(header, &info) == 0) {
        KSLOG_WARN("dladdr failed");
        return;
    }
    KSLOG_DEBUG("Image name: %s", info.dli_fname);
    if (slide == 0) {
        KSLOG_DEBUG("Zero slide, can't do anything with it");
        return;
    }

    const struct symtab_command *symtab_cmd =
        (struct symtab_command *)ksmacho_getCommandByTypeFromHeader((const mach_header_t *)header, LC_SYMTAB);
    const struct dysymtab_command *dysymtab_cmd =
        (struct dysymtab_command *)ksmacho_getCommandByTypeFromHeader((const mach_header_t *)header, LC_DYSYMTAB);
    const segment_command_t *linkedit_segment =
        ksmacho_getSegmentByNameFromHeader((mach_header_t *)header, SEG_LINKEDIT);

    if (symtab_cmd == NULL || dysymtab_cmd == NULL || linkedit_segment == NULL) {
        KSLOG_WARN("Required commands or segments not found");
        return;
    }

    // Find base symbol/string table addresses
    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

    // Get indirect symbol table (array of uint32_t indices into symbol table)
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

    process_segment(header, slide, SEG_DATA, symtab, strtab, indirect_symtab);
    process_segment(header, slide, SEG_DATA_CONST, symtab, strtab, indirect_symtab);
}

int ksct_swap(const cxa_throw_type handler)
{
    KSLOG_DEBUG("Swapping __cxa_throw handler");

    if (g_cxa_originals == NULL) {
        g_cxa_originals_capacity = 25;
        g_cxa_originals = (KSAddressPair *)malloc(sizeof(KSAddressPair) * g_cxa_originals_capacity);
        if (g_cxa_originals == NULL) {
            KSLOG_ERROR("Failed to allocate memory for g_cxa_originals: %s", strerror(errno));
            return -1;
        }
    }
    g_cxa_originals_count = 0;

    if (g_cxa_throw_handler == NULL) {
        g_cxa_throw_handler = handler;
        _dyld_register_func_for_add_image(rebind_symbols_for_image);
    } else {
        g_cxa_throw_handler = handler;
        uint32_t c = _dyld_image_count();
        for (uint32_t i = 0; i < c; i++) {
            rebind_symbols_for_image(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
        }
    }
    return 0;
}
