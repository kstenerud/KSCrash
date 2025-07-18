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
#include <string.h>

#include "KSBinaryImageCache.h"
#include "KSLogger.h"
#include "KSMemory.h"
#include "KSPlatformSpecificDefines.h"

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

#include <mach-o/loader.h>
#include <stdint.h>
#include <string.h>

static uintptr_t vmSlideFromHeader(const struct mach_header *mh)
{
    uintptr_t load_addr = (uintptr_t)mh;

    if (mh->magic == MH_MAGIC_64) {
        const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
        uintptr_t ptr = (uintptr_t)(mh64 + 1);

        for (uint32_t i = 0; i < mh64->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)ptr;

            if (lc->cmd == LC_SEGMENT_64) {
                // Ensure safe cast via alignment assumption
                const struct segment_command_64 *seg = (const struct segment_command_64 *)__builtin_assume_aligned(
                    lc, __alignof(struct segment_command_64));

                if (strcmp(seg->segname, "__TEXT") == 0) {
                    return load_addr - (uintptr_t)(seg->vmaddr);
                }
            }

            ptr += lc->cmdsize;
        }

    } else if (mh->magic == MH_MAGIC) {
        const struct mach_header *mh32 = mh;
        uintptr_t ptr = (uintptr_t)(mh32 + 1);

        for (uint32_t i = 0; i < mh32->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)ptr;

            if (lc->cmd == LC_SEGMENT) {
                const struct segment_command *seg =
                    (const struct segment_command *)__builtin_assume_aligned(lc, __alignof(struct segment_command));

                if (strcmp(seg->segname, "__TEXT") == 0) {
                    return load_addr - (uintptr_t)(seg->vmaddr);
                }
            }

            ptr += lc->cmdsize;
        }
    }

    return 0;
}

/** Get the address of the first command following a header (which will be of
 * type struct load_command).
 *
 * @param header The header to get commands for.
 *
 * @return The address of the first command, or NULL if none was found (which
 *         should not happen unless the header or image is corrupt).
 */
static uintptr_t firstCmdAfterHeader(const struct mach_header *const header)
{
    switch (header->magic) {
        case MH_MAGIC:
        case MH_CIGAM:
            return (uintptr_t)(header + 1);
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((struct mach_header_64 *)header) + 1);
        default:
            // Header is corrupt
            return 0;
    }
}

/** Get the image header that the specified address is part of.
 *
 * @param address The address to examine.
 * @param outName On output, the name if the header in question.
 * @return The header of the image, or NULL if none was found.
 */
static const struct mach_header *imageContainingAddress(const uintptr_t address, char **outName)
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    const struct mach_header *header = NULL;

    if (!images) {
        return NULL;
    }

    for (uint32_t iImg = 0; iImg < count; iImg++) {
        header = images[iImg].imageLoadAddress;
        if (header != NULL) {
            // Look for a segment command with this address within its range.
            uintptr_t addressWSlide = address - vmSlideFromHeader(header);
            uintptr_t cmdPtr = firstCmdAfterHeader(header);
            if (cmdPtr == 0) {
                continue;
            }
            for (uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++) {
                const struct load_command *loadCmd = (struct load_command *)cmdPtr;
                if (loadCmd->cmd == LC_SEGMENT) {
                    const struct segment_command *segCmd = (struct segment_command *)cmdPtr;
                    if (addressWSlide >= segCmd->vmaddr && addressWSlide < segCmd->vmaddr + segCmd->vmsize) {
                        if (outName) {
                            *outName = (char *)images[iImg].imageFilePath;
                        }
                        return header;
                    }
                } else if (loadCmd->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *segCmd = (struct segment_command_64 *)cmdPtr;
                    if (addressWSlide >= segCmd->vmaddr && addressWSlide < segCmd->vmaddr + segCmd->vmsize) {
                        if (outName) {
                            *outName = (char *)images[iImg].imageFilePath;
                        }
                        return header;
                    }
                }
                cmdPtr += loadCmd->cmdsize;
            }
        }
    }
    return NULL;
}

/** Get the segment base address of the specified image.
 *
 * This is required for any symtab command offsets.
 *
 * @param header The image header.
 * @return The image's base address, or 0 if none was found.
 */
static uintptr_t segmentBaseOfImage(const struct mach_header *header)
{
    if (header == NULL) {
        return 0;
    }

    // Look for a segment command and return the file image address.
    uintptr_t cmdPtr = firstCmdAfterHeader(header);
    if (cmdPtr == 0) {
        return 0;
    }
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *loadCmd = (struct load_command *)cmdPtr;
        if (loadCmd->cmd == LC_SEGMENT) {
            const struct segment_command *segmentCmd = (struct segment_command *)cmdPtr;
            if (strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0) {
                return segmentCmd->vmaddr - segmentCmd->fileoff;
            }
        } else if (loadCmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segmentCmd = (struct segment_command_64 *)cmdPtr;
            if (strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0) {
                return (uintptr_t)(segmentCmd->vmaddr - segmentCmd->fileoff);
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }

    return 0;
}

bool ksdl_dladdr(const uintptr_t address, Dl_info *const info)
{
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;

    char *name = NULL;
    const struct mach_header *header = imageContainingAddress(address, &name);
    if (header == NULL) {
        return false;
    }

    const uintptr_t imageVMAddrSlide = vmSlideFromHeader(header);
    const uintptr_t addressWithSlide = address - imageVMAddrSlide;
    const uintptr_t segmentBase = segmentBaseOfImage(header) + imageVMAddrSlide;
    if (segmentBase == 0) {
        return false;
    }

    info->dli_fname = name;
    info->dli_fbase = (void *)header;

    // Find symbol tables and get whichever symbol is closest to the address.
    const nlist_t *bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPtr = firstCmdAfterHeader(header);
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
    uintptr_t cmdPtr = firstCmdAfterHeader(header);
    if (cmdPtr == 0) {
        return false;
    }

    // Look for the TEXT segment to get the image size.
    // Also look for a UUID command.
    uint64_t imageSize = 0;
    uint64_t imageVmAddr = 0;
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
                }
                break;
            }
            case LC_SEGMENT_64: {
                struct segment_command_64 *segCmd = (struct segment_command_64 *)cmdPtr;
                if (strcmp(segCmd->segname, SEG_TEXT) == 0) {
                    imageSize = segCmd->vmsize;
                    imageVmAddr = segCmd->vmaddr;
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
    buffer->vmAddressSlide = vmSlideFromHeader(header);
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
