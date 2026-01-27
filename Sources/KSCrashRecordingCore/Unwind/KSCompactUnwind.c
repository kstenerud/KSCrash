//
// KSCompactUnwind.c
//
// Created by Alexander Cohen on 2025-01-16.
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

#include "Unwind/KSCompactUnwind.h"

#include "KSLogger.h"

// MARK: - __unwind_info Section Format Structures
// Based on Apple's compact_unwind_encoding.h

// Second-level page kinds
#define UNWIND_SECOND_LEVEL_REGULAR 2
#define UNWIND_SECOND_LEVEL_COMPRESSED 3

// Common encodings index sentinel
#define UNWIND_COMMON_ENCODINGS_FIRST_INDEX 127

#pragma pack(push, 1)

// __unwind_info section header
struct unwind_info_section_header {
    uint32_t version;  // Currently 1
    uint32_t commonEncodingsArraySectionOffset;
    uint32_t commonEncodingsArrayCount;
    uint32_t personalityArraySectionOffset;
    uint32_t personalityArrayCount;
    uint32_t indexSectionOffset;
    uint32_t indexCount;
    // followed by: commonEncodingsArray, personalityArray, indexArray
};

// First-level index entry
struct unwind_info_section_header_index_entry {
    uint32_t functionOffset;  // Offset from image base to function
    uint32_t secondLevelPagesSectionOffset;
    uint32_t lsdaIndexArraySectionOffset;
};

// Regular (uncompressed) second-level page header
struct unwind_info_regular_second_level_page_header {
    uint32_t kind;  // == UNWIND_SECOND_LEVEL_REGULAR
    uint16_t entryPageOffset;
    uint16_t entryCount;
};

// Regular second-level page entry
struct unwind_info_regular_second_level_entry {
    uint32_t functionOffset;
    compact_unwind_encoding_t encoding;
};

// Compressed second-level page header
struct unwind_info_compressed_second_level_page_header {
    uint32_t kind;  // == UNWIND_SECOND_LEVEL_COMPRESSED
    uint16_t entryPageOffset;
    uint16_t entryCount;
    uint16_t encodingsPageOffset;
    uint16_t encodingsCount;
};

// Compressed entry format: 24-bit function offset, 8-bit encoding index
#define UNWIND_COMPRESSED_ENTRY_FUNC_OFFSET(entry) ((entry) & 0x00FFFFFF)
#define UNWIND_COMPRESSED_ENTRY_ENCODING_INDEX(entry) (((entry) >> 24) & 0xFF)

// LSDA index entry
struct unwind_info_section_header_lsda_index_entry {
    uint32_t functionOffset;
    uint32_t lsdaOffset;
};

#pragma pack(pop)

// MARK: - Internal Helper Functions

/**
 * Binary search the first-level index to find the page containing the target.
 * Returns the index of the page, or -1 if not found.
 */
static int32_t binarySearchFirstLevelIndex(const struct unwind_info_section_header_index_entry *indices,
                                           uint32_t indexCount, uint32_t targetOffset)
{
    if (indexCount == 0) {
        return -1;
    }

    int32_t left = 0;
    int32_t right = (int32_t)indexCount - 1;
    int32_t result = -1;

    // Find the rightmost entry with functionOffset <= targetOffset
    while (left <= right) {
        int32_t mid = left + (right - left) / 2;
        if (indices[mid].functionOffset <= targetOffset) {
            result = mid;
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    // The last index entry is a sentinel with functionOffset = end of last function
    // So we need to return the entry before it if we hit the sentinel
    if (result >= 0 && (uint32_t)result >= indexCount - 1) {
        result = (int32_t)indexCount - 2;
    }

    return result;
}

/**
 * Read a uint32_t value safely from potentially unaligned memory.
 * This is async-signal-safe.
 */
static inline uint32_t readU32(const void *ptr)
{
    uint32_t value;
    __builtin_memcpy(&value, ptr, sizeof(value));
    return value;
}

/**
 * Binary search within a regular (uncompressed) second-level page.
 */
static bool searchRegularPage(const uint8_t *pageStart, uint32_t targetOffset,
                              uint32_t pageBaseOffset __attribute__((unused)), compact_unwind_encoding_t *outEncoding,
                              uint32_t *outFunctionOffset, uint32_t *outNextFunctionOffset)
{
    const struct unwind_info_regular_second_level_page_header *pageHeader =
        (const struct unwind_info_regular_second_level_page_header *)pageStart;

    if (pageHeader->entryCount == 0) {
        return false;
    }

    const struct unwind_info_regular_second_level_entry *entries =
        (const struct unwind_info_regular_second_level_entry *)(pageStart + pageHeader->entryPageOffset);

    // Binary search for the entry
    int32_t left = 0;
    int32_t right = (int32_t)pageHeader->entryCount - 1;
    int32_t result = -1;

    while (left <= right) {
        int32_t mid = left + (right - left) / 2;
        if (entries[mid].functionOffset <= targetOffset) {
            result = mid;
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    if (result < 0) {
        return false;
    }

    *outEncoding = entries[result].encoding;
    *outFunctionOffset = entries[result].functionOffset;

    // Get next function offset for length calculation
    if ((uint32_t)(result + 1) < pageHeader->entryCount) {
        *outNextFunctionOffset = entries[result + 1].functionOffset;
    } else {
        *outNextFunctionOffset = 0;  // Unknown, use page boundary
    }

    return true;
}

/**
 * Binary search within a compressed second-level page.
 */
static bool searchCompressedPage(const uint8_t *pageStart, uint32_t targetOffset, uint32_t pageBaseOffset,
                                 const uint8_t *sectionBase, const struct unwind_info_section_header *header,
                                 compact_unwind_encoding_t *outEncoding, uint32_t *outFunctionOffset,
                                 uint32_t *outNextFunctionOffset)
{
    const struct unwind_info_compressed_second_level_page_header *pageHeader =
        (const struct unwind_info_compressed_second_level_page_header *)pageStart;

    if (pageHeader->entryCount == 0) {
        return false;
    }

    const uint8_t *entriesBase = pageStart + pageHeader->entryPageOffset;

    // Entries store 24-bit function offset relative to the page's base offset
    uint32_t relativeTarget = targetOffset - pageBaseOffset;

    // Binary search for the entry
    int32_t left = 0;
    int32_t right = (int32_t)pageHeader->entryCount - 1;
    int32_t result = -1;

    while (left <= right) {
        int32_t mid = left + (right - left) / 2;
        uint32_t midEntry = readU32(entriesBase + (uint32_t)mid * sizeof(uint32_t));
        uint32_t entryFuncOffset = UNWIND_COMPRESSED_ENTRY_FUNC_OFFSET(midEntry);
        if (entryFuncOffset <= relativeTarget) {
            result = mid;
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    if (result < 0) {
        return false;
    }

    uint32_t entry = readU32(entriesBase + (uint32_t)result * sizeof(uint32_t));
    uint32_t funcOffset = UNWIND_COMPRESSED_ENTRY_FUNC_OFFSET(entry);
    uint8_t encodingIndex = UNWIND_COMPRESSED_ENTRY_ENCODING_INDEX(entry);

    // Look up the encoding
    compact_unwind_encoding_t encoding;
    if (encodingIndex < header->commonEncodingsArrayCount) {
        // Use common encoding from the header
        const uint8_t *commonEncodingsBase = sectionBase + header->commonEncodingsArraySectionOffset;
        encoding = readU32(commonEncodingsBase + encodingIndex * sizeof(uint32_t));
    } else {
        // Use page-local encoding
        uint32_t localIndex = encodingIndex - header->commonEncodingsArrayCount;
        if (localIndex < pageHeader->encodingsCount) {
            const uint8_t *pageEncodingsBase = pageStart + pageHeader->encodingsPageOffset;
            encoding = readU32(pageEncodingsBase + localIndex * sizeof(uint32_t));
        } else {
            KSLOG_TRACE("Invalid encoding index %u", encodingIndex);
            return false;
        }
    }

    *outEncoding = encoding;
    *outFunctionOffset = pageBaseOffset + funcOffset;

    // Get next function offset
    if ((uint32_t)(result + 1) < pageHeader->entryCount) {
        uint32_t nextEntry = readU32(entriesBase + (uint32_t)(result + 1) * sizeof(uint32_t));
        *outNextFunctionOffset = pageBaseOffset + UNWIND_COMPRESSED_ENTRY_FUNC_OFFSET(nextEntry);
    } else {
        *outNextFunctionOffset = 0;
    }

    return true;
}

/**
 * Search the LSDA index for a function.
 */
static uintptr_t findLSDA(const uint8_t *sectionBase, const struct unwind_info_section_header_index_entry *indexEntry,
                          uint32_t functionOffset, uintptr_t slide)
{
    if (indexEntry->lsdaIndexArraySectionOffset == 0) {
        return 0;
    }

    // LSDA index is between this index entry and the next
    // We need to calculate the count by looking at the next index entry
    // For simplicity, we'll do a linear scan since LSDA tables are typically small
    const struct unwind_info_section_header_lsda_index_entry *lsdaIndex =
        (const struct unwind_info_section_header_lsda_index_entry *)(sectionBase +
                                                                     indexEntry->lsdaIndexArraySectionOffset);

    // Linear scan for the function
    // (In a more optimized version, we'd binary search)
    for (uint32_t i = 0;; i++) {
        // Safety limit to prevent infinite loop
        if (i > 10000) {
            break;
        }

        if (lsdaIndex[i].functionOffset == 0 && lsdaIndex[i].lsdaOffset == 0) {
            break;  // End of array
        }

        if (lsdaIndex[i].functionOffset == functionOffset) {
            return (uintptr_t)lsdaIndex[i].lsdaOffset + slide;
        }

        if (lsdaIndex[i].functionOffset > functionOffset) {
            break;  // Past our function
        }
    }

    return 0;
}

// MARK: - Public API

bool kscu_findEntry(const void *unwindInfo, size_t unwindInfoSize, uintptr_t targetPC, uintptr_t imageBase,
                    uintptr_t slide, KSCompactUnwindEntry *outEntry)
{
    if (unwindInfo == NULL || unwindInfoSize < sizeof(struct unwind_info_section_header)) {
        KSLOG_TRACE("Invalid unwind info: %p, size %zu", unwindInfo, unwindInfoSize);
        return false;
    }

    const uint8_t *sectionBase = (const uint8_t *)unwindInfo;
    const struct unwind_info_section_header *header = (const struct unwind_info_section_header *)sectionBase;

    // Validate version
    if (header->version != 1) {
        KSLOG_TRACE("Unsupported unwind info version: %u", header->version);
        return false;
    }

    // Calculate target offset relative to image base
    uint32_t targetOffset = (uint32_t)(targetPC - imageBase);

    // Binary search the first-level index
    const struct unwind_info_section_header_index_entry *indices =
        (const struct unwind_info_section_header_index_entry *)(sectionBase + header->indexSectionOffset);

    int32_t pageIndex = binarySearchFirstLevelIndex(indices, header->indexCount, targetOffset);
    if (pageIndex < 0) {
        KSLOG_TRACE("Target offset 0x%x not found in first-level index", targetOffset);
        return false;
    }

    const struct unwind_info_section_header_index_entry *indexEntry = &indices[pageIndex];

    // Check if this page has a second-level page
    if (indexEntry->secondLevelPagesSectionOffset == 0) {
        KSLOG_TRACE("No second-level page for index %d", pageIndex);
        return false;
    }

    // Parse the second-level page
    const uint8_t *pageStart = sectionBase + indexEntry->secondLevelPagesSectionOffset;
    uint32_t pageKind = readU32(pageStart);

    compact_unwind_encoding_t encoding = 0;
    uint32_t functionOffset = 0;
    uint32_t nextFunctionOffset = 0;

    bool found = false;
    if (pageKind == UNWIND_SECOND_LEVEL_REGULAR) {
        found = searchRegularPage(pageStart, targetOffset, indexEntry->functionOffset, &encoding, &functionOffset,
                                  &nextFunctionOffset);
    } else if (pageKind == UNWIND_SECOND_LEVEL_COMPRESSED) {
        found = searchCompressedPage(pageStart, targetOffset, indexEntry->functionOffset, sectionBase, header,
                                     &encoding, &functionOffset, &nextFunctionOffset);
    } else {
        KSLOG_TRACE("Unknown second-level page kind: %u", pageKind);
        return false;
    }

    if (!found) {
        KSLOG_TRACE("Function not found in second-level page");
        return false;
    }

    // Populate the output entry
    if (outEntry != NULL) {
        outEntry->functionStart = imageBase + functionOffset;
        if (nextFunctionOffset > functionOffset) {
            outEntry->functionLength = nextFunctionOffset - functionOffset;
        } else {
            // Unknown length - use a reasonable default
            outEntry->functionLength = 0;
        }
        outEntry->encoding = encoding;

        // Look up personality function
        uint32_t personalityIndex = (encoding & KSCU_UNWIND_PERSONALITY_MASK) >> 28;
        if (personalityIndex > 0 && personalityIndex <= header->personalityArrayCount) {
            const uint8_t *personalitiesBase = sectionBase + header->personalityArraySectionOffset;
            uint32_t personality = readU32(personalitiesBase + (personalityIndex - 1) * sizeof(uint32_t));
            outEntry->personalityFunction = (uintptr_t)personality + slide;
        } else {
            outEntry->personalityFunction = 0;
        }

        // Look up LSDA if present
        if (encoding & KSCU_UNWIND_HAS_LSDA) {
            outEntry->lsda = findLSDA(sectionBase, indexEntry, functionOffset, slide);
        } else {
            outEntry->lsda = 0;
        }
    }

    KSLOG_TRACE("Found entry: func=0x%lx, encoding=0x%x", (unsigned long)(imageBase + functionOffset), encoding);
    return true;
}

bool kscu_encodingRequiresDwarf(compact_unwind_encoding_t encoding)
{
    // Check for DWARF mode based on the current architecture.
    // Note: Mode values overlap between architectures, so we must check
    // only the current architecture's DWARF mode.
    uint32_t mode = encoding & 0x0F000000;

#if defined(__arm64__)
    return mode == KSCU_UNWIND_ARM64_MODE_DWARF;
#elif defined(__x86_64__)
    return mode == KSCU_UNWIND_X86_64_MODE_DWARF;
#elif defined(__arm__)
    return mode == KSCU_UNWIND_ARM_MODE_DWARF;
#elif defined(__i386__)
    return mode == KSCU_UNWIND_X86_MODE_DWARF;
#else
    (void)mode;
    return false;
#endif
}

uint32_t kscu_getMode(compact_unwind_encoding_t encoding) { return encoding & 0x0F000000; }
