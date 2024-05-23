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

#include <stdlib.h>
#include <stdio.h>
#include <execinfo.h>
#include <dlfcn.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

#include "KSgetsect.h"
#include "KSPlatformSpecificDefines.h"

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST  "__DATA_CONST"
#endif

typedef struct
{
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
    if (g_cxa_originals_count == g_cxa_originals_capacity)
    {
        g_cxa_originals_capacity *= 2;
        g_cxa_originals = (KSAddressPair *) realloc(g_cxa_originals, sizeof(KSAddressPair) * g_cxa_originals_capacity);
    }
    memcpy(&g_cxa_originals[g_cxa_originals_count++], &pair, sizeof(KSAddressPair));
}

static uintptr_t findAddress(void *address)
{
    for (size_t i = 0; i < g_cxa_originals_count; i++)
    {
        if (g_cxa_originals[i].image == (uintptr_t) address)
        {
            return g_cxa_originals[i].function;
        }
    }
    return (uintptr_t) NULL;
}

static void __cxa_throw_decorator(void *thrown_exception, void *tinfo, void (*dest)(void *))
{
    const int k_requiredFrames = 2;

    g_cxa_throw_handler(thrown_exception, tinfo, dest);

    void *backtraceArr[k_requiredFrames];
    int count = backtrace(backtraceArr, k_requiredFrames);

    Dl_info info;
    if (count >= k_requiredFrames)
    {
        if (dladdr(backtraceArr[k_requiredFrames - 1], &info) != 0)
        {
            uintptr_t function = findAddress(info.dli_fbase);
            if (function != (uintptr_t) NULL)
            {
                cxa_throw_type original = (cxa_throw_type) function;
                original(thrown_exception, tinfo, dest);
            }
        }
    }
}

static vm_prot_t get_protection(void *sectionStart)
{
    mach_port_t task = mach_task_self();
    vm_size_t size = 0;
    vm_address_t address = (vm_address_t) sectionStart;
    memory_object_name_t object;
#if __LP64__
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_basic_info_data_64_t info;
    kern_return_t info_ret =
        vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_64_t) &info, &count, &object);
#else
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT;
    vm_region_basic_info_data_t info;
    kern_return_t info_ret =
        vm_region(task, &address, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &count, &object);
#endif
    if (info_ret == KERN_SUCCESS)
    {
        return info.protection;
    }
    else
    {
        return VM_PROT_READ;
    }
}

static struct load_command *getCommand(const mach_header_t *header, uint32_t command_type)
{
    if (header == NULL)
    {
        return NULL;
    }

    uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
    struct load_command *cur_seg_cmd = NULL;

    for (uint i = 0; i < header->ncmds; i++)
    {
        cur_seg_cmd = (struct load_command *)cur;
        if (cur_seg_cmd->cmd == command_type)
        {
            return cur_seg_cmd;
        }
        cur += cur_seg_cmd->cmdsize;
    }
    return NULL;
}

static void perform_rebinding_with_section(const section_t *section,
                                           intptr_t slide,
                                           nlist_t *symtab,
                                           char *strtab,
                                           uint32_t *indirect_symtab)
{
    const bool isDataConst = strcmp(section->segname, SEG_DATA_CONST) == 0;
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **) ((uintptr_t) slide + section->addr);
    vm_prot_t oldProtection = VM_PROT_READ;
    if (isDataConst)
    {
        oldProtection = get_protection(indirect_symbol_bindings);
        if (mprotect(indirect_symbol_bindings, section->size, PROT_READ | PROT_WRITE) != 0)
        {
            perror("mprotect failed");
            return;
        }
    }
    for (uint i = 0; i < section->size / sizeof(void *); i++)
    {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS ||
            symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS))
        {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        bool symbol_name_longer_than_1 = symbol_name[0] && symbol_name[1];
        if (symbol_name_longer_than_1 && strcmp(&symbol_name[1], g_cxa_throw_name) == 0)
        {
            Dl_info info;
            if (dladdr(section, &info) != 0)
            {
                KSAddressPair pair = {(uintptr_t) info.dli_fbase, (uintptr_t) indirect_symbol_bindings[i]};
                addPair(pair);
            }
            indirect_symbol_bindings[i] = (void *) __cxa_throw_decorator;
            continue;
        }
    }
    if (isDataConst)
    {
        int protection = 0;
        if (oldProtection & VM_PROT_READ)
        {
            protection |= PROT_READ;
        }
        if (oldProtection & VM_PROT_WRITE)
        {
            protection |= PROT_WRITE;
        }
        if (oldProtection & VM_PROT_EXECUTE)
        {
            protection |= PROT_EXEC;
        }
        mprotect(indirect_symbol_bindings, section->size, protection);
    }
}

static const section_t *get_section_by_flag(const segment_command_t *dataSegment, uint32_t flag)
{
    if (strcmp(dataSegment->segname, SEG_DATA) != 0 && strcmp(dataSegment->segname, SEG_DATA_CONST) != 0)
    {
        return false;
    }
    uintptr_t cur = (uintptr_t)dataSegment + sizeof(segment_command_t);
    const section_t *sect = NULL;

    for (uint j = 0; j < dataSegment->nsects; j++)
    {
        sect = (const section_t *)(cur + j * sizeof(section_t));
        if ((sect->flags & SECTION_TYPE) == flag)
        {
            return sect;
        }
    }

    return NULL;
}

static void process_segment(const struct mach_header *header,
                            intptr_t slide,
                            const char *segname,
                            nlist_t *symtab,
                            char *strtab,
                            uint32_t *indirect_symtab)
{
    const segment_command_t *segment = ksgs_getsegbynamefromheader((mach_header_t *)header, segname);
    if (segment != NULL)
    {
        const section_t *lazy_sym_sect = get_section_by_flag(segment, S_LAZY_SYMBOL_POINTERS);
        const section_t *non_lazy_sym_sect = get_section_by_flag(segment, S_NON_LAZY_SYMBOL_POINTERS);

        if (lazy_sym_sect != NULL)
        {
            perform_rebinding_with_section(lazy_sym_sect, slide, symtab, strtab, indirect_symtab);
        }
        if (non_lazy_sym_sect != NULL)
        {
            perform_rebinding_with_section(non_lazy_sym_sect, slide, symtab, strtab, indirect_symtab);
        }
    }
}

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide)
{
    Dl_info info;
    if (dladdr(header, &info) == 0) { return; }

    const struct symtab_command *symtab_cmd = (struct symtab_command *)getCommand(header, LC_SYMTAB);
    const struct dysymtab_command *dysymtab_cmd = (struct dysymtab_command *)getCommand(header, LC_DYSYMTAB);
    const segment_command_t *linkedit_segment = ksgs_getsegbynamefromheader((mach_header_t *) header, SEG_LINKEDIT);

    if (symtab_cmd == NULL || dysymtab_cmd == NULL || linkedit_segment == NULL) { return; }

    // Find base symbol/string table addresses
    uintptr_t linkedit_base = (uintptr_t) slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *) (linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *) (linkedit_base + symtab_cmd->stroff);

    // Get indirect symbol table (array of uint32_t indices into symbol table)
    uint32_t *indirect_symtab = (uint32_t *) (linkedit_base + dysymtab_cmd->indirectsymoff);

    process_segment(header, slide, SEG_DATA, symtab, strtab, indirect_symtab);
    process_segment(header, slide, SEG_DATA_CONST, symtab, strtab, indirect_symtab);
}

int ksct_swap(const cxa_throw_type handler)
{
    if (g_cxa_originals == NULL)
    {
        g_cxa_originals_capacity = 25;
        g_cxa_originals = (KSAddressPair *) malloc(sizeof(KSAddressPair) * g_cxa_originals_capacity);
    }
    g_cxa_originals_count = 0;

    if (g_cxa_throw_handler == NULL)
    {
        g_cxa_throw_handler = handler;
        _dyld_register_func_for_add_image(rebind_symbols_for_image);
    }
    else
    {
        g_cxa_throw_handler = handler;
        uint32_t c = _dyld_image_count();
        for (uint32_t i = 0; i < c; i++)
        {
            rebind_symbols_for_image(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
        }
    }
    return 0;
}
