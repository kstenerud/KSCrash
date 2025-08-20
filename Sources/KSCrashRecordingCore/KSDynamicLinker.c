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

#include <mach-o/dyld_images.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

#include "KSLogger.h"
#include "KSMemory.h"

// ====================================
#pragma mark - Types -
// ====================================

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
} crash_info_v5_t;
#pragma pack()

typedef struct {
    KSBinaryImage image;
    atomic_bool isCached;
} CachedBinaryImage;

static struct {
    CachedBinaryImage *images;
    atomic_llong imagesCapacity;
    atomic_llong imagesCount;
} g_state;

// ====================================
#pragma mark - Constants -
// ====================================

#ifndef KSDL_MaxCrashInfoStringLength
#define KSDL_MaxCrashInfoStringLength 4096
#endif

#if __LP64__
#define MH_MAGIC_ARCH_DEPENDENT MH_MAGIC_64
#else
#define MH_MAGIC_ARCH_DEPENDENT MH_MAGIC
#endif

#define KSDL_SECT_CRASH_INFO "__crash_info"

/**
 * The minimum number of CachedBinaryImage slots that will be allocated when this module is initialized.
 * The actual number chosen will be the larger of this value or double the number of loaded libraries at startup.
 * Currently (2025), most apps tend to have between 700-1500 libraries loaded.
 */
static const size_t MIN_IMAGES_COUNT = 5000;

// ====================================
#pragma mark - Utility -
// ====================================

/**
 * Get the address of the first command following a header
 * Its actual type will be `struct load_command*`
 *
 * @param header The header to get commands for.
 *
 * @return The address of the first command, or NULL if none was found (which
 *         should not happen unless the header or image is corrupt).
 */
static uintptr_t getFirstCommand(const mach_header_t *const header)
{
    if (header == NULL) {
        return 0;
    }
    if (header->magic != MH_MAGIC_ARCH_DEPENDENT) {
        // Header is corrupt
        return 0;
    }
    return (uintptr_t)(header + 1);
}

/**
 * Get the base address of all of the structs created by the link editor.
 * All symbol and string offsets will be based off this address.
 *
 * @param image The binary image to search in.
 * @result A pointer to the link editor base address, or 0.
 */
static uintptr_t getLinkEditorBaseAddress(const KSBinaryImage *const image)
{
    const segment_command_t *segCmd = (segment_command_t *)image->linkEditorSegmentCmd;
    if (segCmd == NULL) {
        return 0;
    }
    return segCmd->vmaddr - segCmd->fileoff + image->vmAddressSlide;
}

static const segment_command_t *asSegmentCommand(const struct load_command *const loadCmd)
{
    // Promise the compiler that this really is aligned properly.
    return (segment_command_t *)__builtin_assume_aligned(loadCmd, __alignof(segment_command_t));
}

/**
 * Get a section by its segment and section names.
 *
 * Note: The section itself contains BOTH names (which may be unrelated to the segment this section is part of), so both
 * need to be compared.
 *
 * @param segCmd The command for the segment containing the section we're interested in.
 * @param segmentName The segment name to look for in the section data.
 * @param sectionName The section name to look for in the section data.
 * @param minSize The minimum size in bytes that this section must be.
 * @param vmSlide The VM slide amount for this image.
 */
static const section_t *getSectionByName(const segment_command_t *const segCmd, const char *const segmentName,
                                         const char *const sectionName, const size_t minSize, const uintptr_t vmSlide)
{
    const section_t *section = (section_t *)((uintptr_t)segCmd + sizeof(*segCmd));
    for (uint32_t i = 0; i < segCmd->nsects; i++, section++) {
        if (strncmp(section->sectname, sectionName, sizeof(section->sectname)) == 0 &&
            strncmp(section->segname, segmentName, sizeof(section->segname)) == 0) {
            if (section->size >= minSize) {
                return (section_t *)((uintptr_t)section->addr + vmSlide);
            }
        }
    }
    KSLOG_TRACE("No section found with segment %s, section %s, minSize %d", segmentName, sectionName, minSize);
    return NULL;
}

static bool isAccessibleNullTerminatedString(const char *const str)
{
    if (str == NULL) {
        return false;
    }
    // Check how much of it is readable
    const int maxReadableBytes = ksmem_maxReadableBytes(str, KSDL_MaxCrashInfoStringLength + 1);
    if (maxReadableBytes == 0) {
        return false;
    }
    // Check if the readable portion is null terminated
    for (int i = 0; i < maxReadableBytes; i++) {
        if (str[i] == 0) {
            return true;
        }
    }
    return false;
}

static const struct dyld_all_image_infos *getDyldAllImageInfo(struct task_dyld_info *infoBuffer)
{
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t err = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)infoBuffer, &count);
    if (err != KERN_SUCCESS) {
        KSLOG_ERROR("Failed to acquire TASK_DYLD_INFO");
        return NULL;
    }
    return (struct dyld_all_image_infos *)infoBuffer->all_image_info_addr;
}

static void lazyInitCachedImage(CachedBinaryImage *const image)
{
    // We don't use an atomic test and set here because it takes time to fill
    // in a cache entry, so there's no concurrency guarantee without a lock.
    // Instead, just let both callers fill in the same information concurrently
    // when there's a race condition.
    // The data is the same, so the end result is the same.
    if (image->isCached) {
        KSLOG_TRACE("Image %p for header %p is already cached with filePath %s", image, image->image.address,
                    image->image.filePath);
        return;
    }
    KSLOG_TRACE("Caching image %p for header %p", image, image->image.address);

    const mach_header_t *const header = (mach_header_t *)image->image.address;
    uintptr_t cmdPtr = getFirstCommand(header);
    if (cmdPtr == 0) {
        KSLOG_TRACE("No first command for header %p", image->image.address);
        return;
    }

    image->image.cpuType = header->cputype;
    image->image.cpuSubType = header->cpusubtype;

    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *const loadCmd = (struct load_command *)cmdPtr;
        switch (loadCmd->cmd) {
            case LC_SEGMENT_ARCH_DEPENDENT: {
                KSLOG_TRACE("LC_SEGMENT_ARCH_DEPENDENT for header %p", image->image.address);
                // By convention, there is only one instance of each "double-underscore" segment name in an image.
                const segment_command_t *const segCmd = asSegmentCommand(loadCmd);
                if (strcmp(segCmd->segname, SEG_TEXT) == 0) {
                    KSLOG_TRACE("SEG_TEXT for header %p", image->image.address);
                    image->image.textSegmentCmd = segCmd;
                    image->image.size = segCmd->vmsize;
                    image->image.vmAddress = segCmd->vmaddr;
                    image->image.vmAddressSlide = (uintptr_t)header - (uintptr_t)segCmd->vmaddr;
                } else if (strcmp(segCmd->segname, SEG_DATA) == 0) {
                    KSLOG_TRACE("SEG_DATA for header %p", image->image.address);
                    image->image.dataSegmentCmd = segCmd;
                    // __TEXT always comes before __DATA, so we can use vmAddressSlide here.
                    image->image.crashInfoSection =
                        getSectionByName(segCmd, SEG_DATA, KSDL_SECT_CRASH_INFO, offsetof(crash_info_v5_t, reserved),
                                         image->image.vmAddressSlide);
                } else if (strcmp(segCmd->segname, SEG_LINKEDIT) == 0) {
                    KSLOG_TRACE("SEG_LINKEDIT for header %p", image->image.address);
                    image->image.linkEditorSegmentCmd = segCmd;
                }
                break;
            }
            case LC_UUID: {
                KSLOG_TRACE("LC_UUID for header %p", image->image.address);
                const struct uuid_command *const uuidCmd = (struct uuid_command *)cmdPtr;
                image->image.uuid = uuidCmd->uuid;
                break;
            }
            case LC_ID_DYLIB: {
                KSLOG_TRACE("LC_ID_DYLIB for header %p", image->image.address);
                const struct dylib_command *const dc = (struct dylib_command *)cmdPtr;
                const uint64_t version = dc->dylib.current_version;
                image->image.name = (const char *)(cmdPtr + dc->dylib.name.offset);
                image->image.majorVersion = version >> 16;
                image->image.minorVersion = (version >> 8) & 0xff;
                image->image.revisionVersion = version & 0xff;
                break;
            }
            case LC_SYMTAB: {
                KSLOG_TRACE("LC_SYMTAB for header %p", image->image.address);
                // There is only one symbol table per image
                image->image.symbolTableCmd = (struct symtab_command *)cmdPtr;
                break;
            }
            default:
                break;
        }
        cmdPtr += loadCmd->cmdsize;
    }

    KSLOG_TRACE("Header %p is now cached", image->image.address);
    image->isCached = true;
    return;
}

// ====================================
#pragma mark - API -
// ====================================

void ksdl_init(void)
{
    if (g_state.images != NULL) {
        return;
    }

    struct task_dyld_info dyld_info;
    const struct dyld_all_image_infos *const infos = getDyldAllImageInfo(&dyld_info);
    if (infos == NULL) {
        return;
    }
    const size_t imageCount = infos->infoArrayCount;
    const size_t capacityCount = ((imageCount * 2) > MIN_IMAGES_COUNT) ? imageCount * 2 : MIN_IMAGES_COUNT;
    g_state.images = (CachedBinaryImage *)calloc(sizeof(*g_state.images), capacityCount);
    g_state.imagesCapacity = capacityCount;
    ksdl_refreshCache();
}

void ksdl_refreshCache(void)
{
    // Note: We don't care about concurrency in this function since the end result is the same.
    KSLOG_TRACE("Refreshing image cache");

    struct task_dyld_info dyld_info;
    const struct dyld_all_image_infos *const infos = getDyldAllImageInfo(&dyld_info);
    if (infos == NULL) {
        return;
    }
    const struct dyld_image_info *const infoArray = infos->infoArray;
    size_t imageCount = infos->infoArrayCount;

    // This should never happen, but if it does we need to contain the damage.
    // Fallout: Some images won't be available for symbolication.
    if (imageCount > g_state.imagesCapacity) {
        KSLOG_ERROR("Images count %d > than capacity %d", imageCount, g_state.imagesCapacity);
        imageCount = g_state.imagesCapacity;
    }

    // Just blast through the list, overwriting anything that doesn't match the order in the
    // dynamic linker. The worst case scenario is unnecessarily invalidated cache values, but
    // this is MUCH quicker than searching for already cached entries, and the cost of caching
    // again is low. Also, the dynamic linker doesn't reorder entries, so 99% of them won't change.
    for (size_t i = 0; i < imageCount; i++) {
        const struct dyld_image_info *const info = &infoArray[i];
        CachedBinaryImage *const cachedImage = &g_state.images[i];
        if ((const mach_header_t *)info->imageLoadAddress != cachedImage->image.address) {
            memset(&cachedImage->image, 0, sizeof(cachedImage->image));
            cachedImage->image.address = (mach_header_t *)info->imageLoadAddress;
            cachedImage->image.filePath = info->imageFilePath;
            cachedImage->isCached = false;
        }
    }
    g_state.imagesCount = imageCount;
}

size_t ksdl_imageCount(void) { return g_state.imagesCount; }

KSBinaryImage *ksdl_imageAtIndex(size_t index)
{
    if (index < g_state.imagesCount) {
        CachedBinaryImage *image = &g_state.images[index];
        lazyInitCachedImage(image);
        return &image->image;
    }
    return NULL;
}

KSBinaryImage *ksdl_getImageForMachHeader(const struct mach_header *const header)
{
    KSLOG_TRACE("Getting image for header %p", header);

    if (header == NULL) {
        KSLOG_ERROR("header was NULL");
        return NULL;
    }

    for (size_t i = 0; i < g_state.imagesCount; i++) {
        CachedBinaryImage *const cachedImage = &g_state.images[i];
        if (cachedImage->image.address == (mach_header_t *)header) {
            KSLOG_TRACE("Found header cached at index %d", i);
            lazyInitCachedImage(cachedImage);
            return &cachedImage->image;
        }
    }

    KSLOG_ERROR("Failed to get cached image for mach header %p. Did you forget to call ksdl_refreshCache()?", header);
    return NULL;
}

KSBinaryImage *ksdl_getImageContainingAddress(const uintptr_t address)
{
    for (size_t i = 0; i < g_state.imagesCount; i++) {
        CachedBinaryImage *const cachedImage = &g_state.images[i];
        lazyInitCachedImage(cachedImage);
        const uintptr_t addressWithSlide = address - cachedImage->image.vmAddressSlide;
        if (addressWithSlide >= cachedImage->image.vmAddress &&
            addressWithSlide < cachedImage->image.vmAddress + cachedImage->image.size) {
            return &cachedImage->image;
        }
    }
    return NULL;
}

KSCrashInfo ksdl_getCrashInfo(const KSBinaryImage *const image)
{
    KSCrashInfo info = { 0 };
    if (image == NULL) {
        KSLOG_ERROR("image was NULL");
        return info;
    }
    if (image->crashInfoSection == 0) {
        KSLOG_TRACE("image crashInfoSection is NULL");
        return info;
    }

    KSLOG_TRACE("Found crash info section in binary: %s", image->filePath);
    const crash_info_v5_t *const crashInfo = (crash_info_v5_t *)image->crashInfoSection;
    const unsigned int minimalSize = offsetof(crash_info_v5_t, reserved);
    if (!ksmem_isMemoryReadable(crashInfo, minimalSize)) {
        KSLOG_TRACE("Skipped reading crash info for header %p: section memory at %p is not readable. slide = %p",
                    image->address, crashInfo, image->vmAddressSlide);
        return info;
    }
    if (crashInfo->version != 4 && crashInfo->version != 5) {
        KSLOG_TRACE("Skipped reading crash info: invalid version '%d'", crashInfo->version);
        return info;
    }

    if (isAccessibleNullTerminatedString(crashInfo->message)) {
        KSLOG_DEBUG("Found first message: %s", crashInfo->message);
        info.crashInfoMessage = crashInfo->message;
    }
    if (isAccessibleNullTerminatedString(crashInfo->message2)) {
        KSLOG_DEBUG("Found second message: %s", crashInfo->message2);
        info.crashInfoMessage2 = crashInfo->message2;
    }
    if (isAccessibleNullTerminatedString(crashInfo->backtrace)) {
        KSLOG_DEBUG("Found backtrace: %s", crashInfo->backtrace);
        info.crashInfoBacktrace = crashInfo->backtrace;
    }
    if (isAccessibleNullTerminatedString(crashInfo->signature)) {
        KSLOG_DEBUG("Found signature: %s", crashInfo->signature);
        info.crashInfoSignature = crashInfo->signature;
    }
    return info;
}

KSSymbolication ksdl_symbolicate(const uintptr_t address)
{
    KSSymbolication symbolication = { 0 };
    const KSBinaryImage *const image = ksdl_getImageContainingAddress(address);
    if (image == NULL) {
        return symbolication;
    }

    symbolication.image = image;

    uintptr_t linkEditorBaseAddress = getLinkEditorBaseAddress(image);
    if (linkEditorBaseAddress == 0) {
        return symbolication;
    }

    const struct symtab_command *const symtabCmd = image->symbolTableCmd;
    const nlist_t *const symbolTable = (nlist_t *)(linkEditorBaseAddress + symtabCmd->symoff);
    const uintptr_t stringTable = linkEditorBaseAddress + symtabCmd->stroff;
    const uintptr_t imageVMAddrSlide = image->vmAddressSlide;
    const uintptr_t addressWithSlide = address - imageVMAddrSlide;

    const nlist_t *bestMatch = NULL;
    uintptr_t bestDistance = (uintptr_t)-1;

    for (uint32_t iSym = 0; iSym < symtabCmd->nsyms; iSym++) {
        // Skip all debug N_STAB symbols
        if ((symbolTable[iSym].n_type & N_STAB) != 0) {
            continue;
        }
        // If n_value is 0, the symbol refers to an external object.
        if (symbolTable[iSym].n_value == 0) {
            continue;
        }

        const uintptr_t symbolBase = symbolTable[iSym].n_value;
        const uintptr_t currentDistance = addressWithSlide - symbolBase;
        if ((addressWithSlide >= symbolBase) && (currentDistance <= bestDistance)) {
            bestMatch = symbolTable + iSym;
            bestDistance = currentDistance;
        }
    }
    if (bestMatch != NULL) {
        symbolication.symbolAddress = (uintptr_t)bestMatch->n_value + imageVMAddrSlide;
        // If desc is 16, this image has been stripped, and the name is
        // meaningless and almost certainly resolves to "_mh_execute_header"
        if (bestMatch->n_desc != 16) {
            symbolication.symbolName = (char *)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);
            if (*symbolication.symbolName == '_') {
                symbolication.symbolName++;
            }
        }
    }

    return symbolication;
}
