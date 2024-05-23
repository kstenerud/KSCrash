//
//  KSgetsect.c
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
// Modification of getsegbyname.c
// https://opensource.apple.com/source/cctools/cctools-921/libmacho/getsegbyname.c.auto.html
// Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
//
// @APPLE_LICENSE_HEADER_START@
//
// This file contains Original Code and/or Modifications of Original Code
// as defined in and that are subject to the Apple Public Source License
// Version 2.0 (the 'License'). You may not use this file except in
// compliance with the License. Please obtain a copy of the License at
// http://www.opensource.apple.com/apsl/ and read it before using this
// file.
//
// The Original Code and all software distributed under the License are
// distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
// EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
// INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
// Please see the License for the specific language governing rights and
// limitations under the License.
//
// @APPLE_LICENSE_HEADER_END@
//

#include "KSMach-O.h"
#include <string.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include "KSLogger.h"

const segment_command_t *ksmacho_getSegmentByNameFromHeader(const mach_header_t *header, const char *seg_name)
{
    segment_command_t *sgp;
    unsigned long i;

    sgp = (segment_command_t *) ((uintptr_t) header + sizeof(mach_header_t));
    for (i = 0; i < header->ncmds; i++)
    {
        if (sgp->cmd == LC_SEGMENT_ARCH_DEPENDENT && strncmp(sgp->segname, seg_name, sizeof(sgp->segname)) == 0)
        {
            return sgp;
        }
        sgp = (segment_command_t *) ((uintptr_t) sgp + sgp->cmdsize);
    }
    return (segment_command_t *) NULL;
}

vm_prot_t ksmacho_getSectionProtection(void *sectionStart)
{
    KSLOG_TRACE("Getting protection for section starting at %p", sectionStart);

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
        KSLOG_DEBUG("Protection obtained: %d", info.protection);
        return info.protection;
    }
    else
    {
        KSLOG_ERROR("Failed to get protection for section: %s", mach_error_string(info_ret));
        return VM_PROT_READ;
    }
}

const struct load_command *ksmacho_getCommandByTypeFromHeader(const mach_header_t *header, uint32_t command_type)
{
    if (header == NULL)
    {
        KSLOG_ERROR("Header is NULL");
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
    KSLOG_WARN("Command type %u not found", command_type);
    return NULL;
}

const section_t *ksmacho_getSectionByFlagFromSegment(const segment_command_t *dataSegment, uint32_t flag)
{
    KSLOG_TRACE("Getting section by flag %u in segment %s", flag, dataSegment->segname);

    if (strcmp(dataSegment->segname, SEG_DATA) != 0 && strcmp(dataSegment->segname, SEG_DATA_CONST) != 0)
    {
        return NULL;
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

    KSLOG_DEBUG("Section with flag %u not found in segment %s", flag, dataSegment->segname);
    return NULL;
}
