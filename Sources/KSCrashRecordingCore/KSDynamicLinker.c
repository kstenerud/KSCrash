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

// TODO: Remove this
static void __attribute__((noreturn)) crash(const char *reason)
{
    KSLOG_ERROR("### CRASHING APP because %s", reason);
    abort();
    // exit(1);
}

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
        return &g_state.images[index].image;
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
    } else {
        KSLOG_ERROR("### NOT FOUND");
        crash("no symbolication match found");
    }

    return symbolication;
}

//
//
//
//
//
//

// ====================================
#pragma mark - Legacy -
// ====================================

#include <limits.h>
#include <mach-o/getsect.h>

#include "KSBinaryImageCache.h"

static const segment_command_t *getSegmentNamed(const mach_header_t *const header, const char *const name)
{
    uintptr_t cmdPtr = getFirstCommand(header);
    if (cmdPtr == 0) {
        return NULL;
    }

    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *const loadCmd = (struct load_command *)cmdPtr;
        if (loadCmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            const segment_command_t *const segCmd = asSegmentCommand(loadCmd);
            if (strcmp(segCmd->segname, name) == 0) {
                return segCmd;
            }
        }
        cmdPtr += loadCmd->cmdsize;
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
static uintptr_t getSegmentBase_orig(const mach_header_t *header)
{
    const segment_command_t *segCmd = getSegmentNamed(header, SEG_LINKEDIT);
    if (segCmd == NULL) {
        return 0;
    }

    return segCmd->vmaddr - segCmd->fileoff;
}

static uintptr_t getVMSlide(const mach_header_t *header)
{
    const segment_command_t *textSegment = getSegmentNamed(header, SEG_TEXT);
    if (textSegment == NULL) {
        return 0;
    }

    uintptr_t load_addr = (uintptr_t)header;
    return load_addr - (uintptr_t)(textSegment->vmaddr);
}

/** Get the image that the specified address is part of.
 *
 * @param address The address to examine.
 * @return The image info, or NULL if none was found.
 */
static const struct dyld_image_info *getImageContainingAddress(const uintptr_t address)
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    const mach_header_t *header = NULL;

    if (!images) {
        return NULL;
    }

    for (uint32_t iImg = 0; iImg < count; iImg++) {
        const struct dyld_image_info *image = &images[iImg];
        header = (mach_header_t *)image->imageLoadAddress;
        if (header != NULL) {
            // Look for a segment command with this address within its range.
            uintptr_t cmdPtr = getFirstCommand(header);
            if (cmdPtr == 0) {
                continue;
            }
            uintptr_t addressWSlide = address - getVMSlide(header);
            for (uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++) {
                const struct load_command *loadCmd = (struct load_command *)cmdPtr;
                if (loadCmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
                    const segment_command_t *segCmd = asSegmentCommand(loadCmd);
                    if (addressWSlide >= segCmd->vmaddr && addressWSlide < segCmd->vmaddr + segCmd->vmsize) {
                        return image;
                    }
                }
                cmdPtr += loadCmd->cmdsize;
            }
        }
    }
    return NULL;
}

static bool stringsAreEqual(const char *a, const char *b)
{
    if (a == NULL && b == NULL) {
        return true;
    }
    if ((a == NULL) != (b == NULL)) {
        return false;
    }
    return strcmp(a, b) == 0;
}

static void getCrashInfo(const mach_header_t *header, KSBinaryImage *buffer)
{
    unsigned long size = 0;
#pragma clang diagnostic ignored "-Wcast-align"
    crash_info_v5_t *crashInfo =
        (crash_info_v5_t *)getsectiondata((mach_header_t *)header, SEG_DATA, KSDL_SECT_CRASH_INFO, &size);
#pragma clang diagnostic pop
    if (crashInfo == NULL) {
        return;
    }

    KSLOG_TRACE("Found crash info section in binary: %s", buffer->filePath);
    const unsigned int minimalSize = offsetof(crash_info_v5_t, reserved);  // Include message and message2
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

    if (isAccessibleNullTerminatedString(crashInfo->message)) {
        KSLOG_DEBUG("Found first message: %s", crashInfo->message);
        buffer->crashInfoMessage = crashInfo->message;
    }
    if (isAccessibleNullTerminatedString(crashInfo->message2)) {
        KSLOG_DEBUG("Found second message: %s", crashInfo->message2);
        buffer->crashInfoMessage2 = crashInfo->message2;
    }
    if (isAccessibleNullTerminatedString(crashInfo->backtrace)) {
        KSLOG_DEBUG("Found backtrace: %s", crashInfo->backtrace);
        buffer->crashInfoBacktrace = crashInfo->backtrace;
    }
    if (isAccessibleNullTerminatedString(crashInfo->signature)) {
        KSLOG_DEBUG("Found signature: %s", crashInfo->signature);
        buffer->crashInfoSignature = crashInfo->signature;
    }

    KSBinaryImage *img = ksdl_getImageForMachHeader((const struct mach_header *)header);
    KSCrashInfo info = ksdl_getCrashInfo(img);

    if (!stringsAreEqual(buffer->crashInfoMessage, info.crashInfoMessage)) {
        KSLOG_ERROR("crashInfoMessage: [%s] != [%s]", buffer->crashInfoMessage, info.crashInfoMessage);
        crash("crashInfoMessage didn't match");
    }
    if (!stringsAreEqual(buffer->crashInfoMessage2, info.crashInfoMessage2)) {
        KSLOG_ERROR("crashInfoMessage2: [%s] != [%s]", buffer->crashInfoMessage2, info.crashInfoMessage2);
        crash("crashInfoMessage2 didn't match");
    }
    if (!stringsAreEqual(buffer->crashInfoBacktrace, info.crashInfoBacktrace)) {
        KSLOG_ERROR("crashInfoBacktrace: [%s] != [%s]", buffer->crashInfoBacktrace, info.crashInfoBacktrace);
        crash("crashInfoBacktrace didn't match");
    }
    if (!stringsAreEqual(buffer->crashInfoSignature, info.crashInfoSignature)) {
        KSLOG_ERROR("crashInfoSignature: [%s] != [%s]", buffer->crashInfoSignature, info.crashInfoSignature);
        crash("crashInfoSignature didn't match");
    }
}

bool ksdl_dladdr(const uintptr_t address, Dl_info *const info)
{
    KSLOG_TRACE("Check address %p", address);
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;

    const struct dyld_image_info *image = getImageContainingAddress(address);
    if (image == NULL) {
        return false;
    }
    KSBinaryImage *testimage = ksdl_getImageContainingAddress(address);
    if (testimage == NULL) {
        KSLOG_ERROR("### image is null");
        crash("ksdl_getImageContainingAddress() returned NULL");
    }
    mach_header_t *header = (mach_header_t *)image->imageLoadAddress;

    const uintptr_t imageVMAddrSlide = getVMSlide(header);
    const uintptr_t addressWithSlide = address - imageVMAddrSlide;
    const uintptr_t segmentBase = getSegmentBase_orig(header) + imageVMAddrSlide;
    if (segmentBase == 0) {
        return false;
    }

    uintptr_t testsegmentBase = getLinkEditorBaseAddress(testimage);
    if (testsegmentBase != segmentBase) {
        KSLOG_ERROR("### segmentBase %p != testSegmentBase %p", segmentBase, testsegmentBase);
        crash("getLinkEditorBaseAddress() didn't match old function return");
    }

    info->dli_fname = image->imageFilePath;
    info->dli_fbase = (void *)header;

    // Find symbol tables and get whichever symbol is closest to the address.
    const nlist_t *bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPtr = getFirstCommand(header);
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

    KSLOG_TRACE("COMPARING TO NEW IMPLEMENTATION");
    KSSymbolication sym = ksdl_symbolicate(address);
    if ((uintptr_t)info->dli_fbase != (uintptr_t)sym.image->address) {
        KSLOG_ERROR("info->dli_fbase (%x) != sym.image->address (%x)", info->dli_fbase, sym.image->address);
        crash("dli_fbase != sym.image->address");
    }
    if (!stringsAreEqual(info->dli_fname, sym.image->filePath)) {
        KSLOG_ERROR("info->dli_fname (%s) != sym.image->filePath (%s)", info->dli_fname, sym.image->filePath);
        crash("dli_fname != sym.image->filePath");
    }
    if (!stringsAreEqual(info->dli_sname, sym.symbolName)) {
        KSLOG_ERROR("info->dli_sname (%s) != sym.symbolName (%s)", info->dli_sname, sym.symbolName);
        crash("dli_sname != sym.symbolName");
    }
    if ((uintptr_t)info->dli_saddr != sym.symbolAddress) {
        KSLOG_ERROR("info->dli_saddr (%x) != sym.symbolAddress (%x)", info->dli_saddr, sym.symbolAddress);
        crash("dli_saddr != sym.symbolAddress");
    }

    return true;
}

bool ksdl_binaryImageForHeader(const void *const header_ptr, const char *const image_name, KSBinaryImage *buffer)
{
    const mach_header_t *header = (const mach_header_t *)header_ptr;
    uintptr_t cmdPtr = getFirstCommand(header);
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
            case LC_SEGMENT_ARCH_DEPENDENT: {
                const segment_command_t *segCmd = asSegmentCommand(loadCmd);
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

    buffer->address = (const mach_header_t *)header;
    buffer->vmAddress = imageVmAddr;
    buffer->size = imageSize;
    buffer->vmAddressSlide = getVMSlide(header);
    buffer->filePath = image_name;
    buffer->uuid = uuid;
    buffer->cpuType = header->cputype;
    buffer->cpuSubType = header->cpusubtype;
    buffer->majorVersion = version >> 16;
    buffer->minorVersion = (version >> 8) & 0xff;
    buffer->revisionVersion = version & 0xff;
    getCrashInfo(header, buffer);

    KSLOG_TRACE("COMPARING TO NEW IMPLEMENTATION");
    KSBinaryImage *img = ksdl_getImageForMachHeader(header_ptr);
    if (img == NULL) {
        KSLOG_ERROR("ksdl_getImageForMachHeader returned NULL!");
        return true;
    }
    if (buffer->address != img->address) {
        KSLOG_ERROR("buffer->address (%x) != img->address (%x)", buffer->address, img->address);
        crash("buffer->address != img->address");
    }
    if (buffer->vmAddress != img->vmAddress) {
        KSLOG_ERROR("buffer->vmAddress (%x) != img->vmAddress (%x)", buffer->vmAddress, img->vmAddress);
        crash("buffer->vmAddress != img->vmAddress");
    }
    if (buffer->size != img->size) {
        KSLOG_ERROR("buffer->size (%x) != img->size (%x)", buffer->size, img->size);
        crash("buffer->size != img->size");
    }
    if (buffer->vmAddressSlide != img->vmAddressSlide) {
        KSLOG_ERROR("buffer->vmAddressSlide (%x) != img->vmAddressSlide (%x)", buffer->vmAddressSlide,
                    img->vmAddressSlide);
        crash("buffer->vmAddressSlide != img->vmAddressSlide");
    }
    if (!stringsAreEqual(buffer->filePath, img->filePath)) {
        KSLOG_ERROR("buffer->filePath (%s) != img->filePath (%s)", buffer->filePath, img->filePath);
        if (buffer->filePath != NULL) {
            // Old filler is broken here
            crash("buffer->filePath != img->filePath, and buffer->filePath != NULL");
        }
    }
    if (buffer->uuid != img->uuid) {
        KSLOG_ERROR("buffer->uuid (%p) != img->uuid (%p)", buffer->uuid, img->uuid);
        crash("buffer->uuid != img->uuid");
    }
    if (buffer->cpuType != img->cpuType) {
        KSLOG_ERROR("buffer->cpuType (%x) != img->cpuType (%x)", buffer->cpuType, img->cpuType);
        crash("buffer->cpuType != img->cpuType");
    }
    if (buffer->cpuSubType != img->cpuSubType) {
        KSLOG_ERROR("buffer->cpuSubType (%x) != img->cpuSubType (%x)", buffer->cpuSubType, img->cpuSubType);
        crash("buffer->cpuSubType != img->cpuSubType");
    }
    if (buffer->majorVersion != img->majorVersion) {
        KSLOG_ERROR("buffer->majorVersion (%x) != img->majorVersion (%x)", buffer->majorVersion, img->majorVersion);
        crash("buffer->majorVersion != img->majorVersion");
    }
    if (buffer->minorVersion != img->minorVersion) {
        KSLOG_ERROR("buffer->minorVersion (%x) != img->minorVersion (%x)", buffer->minorVersion, img->minorVersion);
        crash("buffer->minorVersion != img->minorVersion");
    }
    if (buffer->revisionVersion != img->revisionVersion) {
        KSLOG_ERROR("buffer->revisionVersion (%x) != img->revisionVersion (%x)", buffer->revisionVersion,
                    img->revisionVersion);
        crash("buffer->revisionVersion != img->revisionVersion");
    }

    KSLOG_TRACE("Finished");

    return true;
}
