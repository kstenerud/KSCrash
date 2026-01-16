//
// KSDwarfUnwind.c
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

#include "Unwind/KSDwarfUnwind.h"

#include <string.h>

#include "KSMemory.h"

#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

// MARK: - DWARF Constants

// Pointer encoding formats (DW_EH_PE_*)
#define DW_EH_PE_absptr 0x00
#define DW_EH_PE_uleb128 0x01
#define DW_EH_PE_udata2 0x02
#define DW_EH_PE_udata4 0x03
#define DW_EH_PE_udata8 0x04
#define DW_EH_PE_sleb128 0x09
#define DW_EH_PE_sdata2 0x0A
#define DW_EH_PE_sdata4 0x0B
#define DW_EH_PE_sdata8 0x0C

// Pointer encoding modifiers
#define DW_EH_PE_pcrel 0x10
#define DW_EH_PE_textrel 0x20
#define DW_EH_PE_datarel 0x30
#define DW_EH_PE_funcrel 0x40
#define DW_EH_PE_aligned 0x50
#define DW_EH_PE_indirect 0x80
#define DW_EH_PE_omit 0xFF

// CFI instruction opcodes
#define DW_CFA_advance_loc 0x40         // high 2 bits = 0x01
#define DW_CFA_offset 0x80              // high 2 bits = 0x02
#define DW_CFA_restore 0xC0             // high 2 bits = 0x03
#define DW_CFA_nop 0x00                 // extended opcode
#define DW_CFA_set_loc 0x01             // extended opcode
#define DW_CFA_advance_loc1 0x02        // extended opcode
#define DW_CFA_advance_loc2 0x03        // extended opcode
#define DW_CFA_advance_loc4 0x04        // extended opcode
#define DW_CFA_offset_extended 0x05     // extended opcode
#define DW_CFA_restore_extended 0x06    // extended opcode
#define DW_CFA_undefined 0x07           // extended opcode
#define DW_CFA_same_value 0x08          // extended opcode
#define DW_CFA_register 0x09            // extended opcode
#define DW_CFA_remember_state 0x0A      // extended opcode
#define DW_CFA_restore_state 0x0B       // extended opcode
#define DW_CFA_def_cfa 0x0C             // extended opcode
#define DW_CFA_def_cfa_register 0x0D    // extended opcode
#define DW_CFA_def_cfa_offset 0x0E      // extended opcode
#define DW_CFA_def_cfa_expression 0x0F  // extended opcode
#define DW_CFA_expression 0x10          // extended opcode
#define DW_CFA_offset_extended_sf 0x11  // extended opcode
#define DW_CFA_def_cfa_sf 0x12          // extended opcode
#define DW_CFA_def_cfa_offset_sf 0x13   // extended opcode
#define DW_CFA_val_offset 0x14          // extended opcode
#define DW_CFA_val_offset_sf 0x15       // extended opcode
#define DW_CFA_val_expression 0x16      // extended opcode
#define DW_CFA_GNU_args_size 0x2E       // GNU extension

// Maximum state stack depth for remember/restore
#define MAX_STATE_STACK_DEPTH 8

// MARK: - Internal Types

typedef struct {
    const uint8_t *data;
    const uint8_t *end;
    uintptr_t baseAddress;  // For pcrel calculations
} KSDwarfReader;

// CIE parsed data
typedef struct {
    uint8_t version;
    const char *augmentation;
    uint64_t codeAlignmentFactor;
    int64_t dataAlignmentFactor;
    uint64_t returnAddressRegister;
    uint8_t fdePointerEncoding;
    uint8_t lsdaEncoding;
    bool hasAugmentation;
    const uint8_t *initialInstructions;
    size_t initialInstructionsLen;
} KSDwarfCIE;

// FDE parsed data
typedef struct {
    uintptr_t pcStart;
    uintptr_t pcRange;
    const uint8_t *instructions;
    size_t instructionsLen;
    uintptr_t lsda;
} KSDwarfFDE;

// MARK: - Reader Helpers

static inline bool readerHasData(const KSDwarfReader *reader, size_t bytes)
{
    return reader->data + bytes <= reader->end;
}

static inline uint8_t readU8(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 1)) return 0;
    return *reader->data++;
}

static inline uint16_t readU16(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 2)) return 0;
    uint16_t value;
    memcpy(&value, reader->data, sizeof(value));
    reader->data += 2;
    return value;
}

static inline uint32_t readU32(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 4)) return 0;
    uint32_t value;
    memcpy(&value, reader->data, sizeof(value));
    reader->data += 4;
    return value;
}

static inline uint64_t readU64(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 8)) return 0;
    uint64_t value;
    memcpy(&value, reader->data, sizeof(value));
    reader->data += 8;
    return value;
}

static inline int16_t readS16(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 2)) return 0;
    int16_t value;
    memcpy(&value, reader->data, sizeof(value));
    reader->data += 2;
    return value;
}

static inline int32_t readS32(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 4)) return 0;
    int32_t value;
    memcpy(&value, reader->data, sizeof(value));
    reader->data += 4;
    return value;
}

static inline int64_t readS64(KSDwarfReader *reader)
{
    if (!readerHasData(reader, 8)) return 0;
    int64_t value;
    memcpy(&value, reader->data, sizeof(value));
    reader->data += 8;
    return value;
}

static uint64_t readULEB128(KSDwarfReader *reader)
{
    uint64_t result = 0;
    uint32_t shift = 0;
    uint8_t byte;

    do {
        if (!readerHasData(reader, 1)) return 0;
        byte = *reader->data++;
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
    } while ((byte & 0x80) && shift < 64);

    return result;
}

static int64_t readSLEB128(KSDwarfReader *reader)
{
    int64_t result = 0;
    uint32_t shift = 0;
    uint8_t byte;

    do {
        if (!readerHasData(reader, 1)) return 0;
        byte = *reader->data++;
        result |= ((int64_t)(byte & 0x7F)) << shift;
        shift += 7;
    } while ((byte & 0x80) && shift < 64);

    // Sign extend
    if (shift < 64 && (byte & 0x40)) {
        result |= -(((int64_t)1) << shift);
    }

    return result;
}

// MARK: - Pointer Encoding

static uintptr_t readEncodedPointer(KSDwarfReader *reader, uint8_t encoding, uintptr_t pcRelBase)
{
    if (encoding == DW_EH_PE_omit) {
        return 0;
    }

    uintptr_t result = 0;
    const uint8_t *startPos = reader->data;

    // Read the base value
    uint8_t format = encoding & 0x0F;
    switch (format) {
        case DW_EH_PE_absptr:
#if __LP64__
            result = readU64(reader);
#else
            result = readU32(reader);
#endif
            break;
        case DW_EH_PE_uleb128:
            result = readULEB128(reader);
            break;
        case DW_EH_PE_udata2:
            result = readU16(reader);
            break;
        case DW_EH_PE_udata4:
            result = readU32(reader);
            break;
        case DW_EH_PE_udata8:
            result = readU64(reader);
            break;
        case DW_EH_PE_sleb128:
            result = (uintptr_t)readSLEB128(reader);
            break;
        case DW_EH_PE_sdata2:
            result = (uintptr_t)readS16(reader);
            break;
        case DW_EH_PE_sdata4:
            result = (uintptr_t)readS32(reader);
            break;
        case DW_EH_PE_sdata8:
            result = (uintptr_t)readS64(reader);
            break;
        default:
            KSLOG_TRACE("Unknown pointer format: 0x%x", format);
            return 0;
    }

    // Apply modifier
    uint8_t modifier = encoding & 0x70;
    switch (modifier) {
        case 0:
            // No modifier
            break;
        case DW_EH_PE_pcrel:
            result += (uintptr_t)startPos;
            if (pcRelBase != 0) {
                result = result - (uintptr_t)startPos + pcRelBase;
            }
            break;
        case DW_EH_PE_datarel:
            result += reader->baseAddress;
            break;
        default:
            KSLOG_TRACE("Unsupported pointer modifier: 0x%x", modifier);
            break;
    }

    // Handle indirect
    if (encoding & DW_EH_PE_indirect) {
        uintptr_t indirect;
        if (ksmem_copySafely((const void *)result, &indirect, sizeof(indirect))) {
            result = indirect;
        }
    }

    return result;
}

// MARK: - CIE/FDE Parsing

static bool parseCIE(const uint8_t *cieData, size_t cieSize, KSDwarfCIE *outCIE)
{
    memset(outCIE, 0, sizeof(*outCIE));

    KSDwarfReader reader = {
        .data = cieData,
        .end = cieData + cieSize,
        .baseAddress = 0,
    };

    // Version
    outCIE->version = readU8(&reader);
    if (outCIE->version != 1 && outCIE->version != 3) {
        KSLOG_TRACE("Unsupported CIE version: %u", outCIE->version);
        return false;
    }

    // Augmentation string
    outCIE->augmentation = (const char *)reader.data;
    while (readerHasData(&reader, 1) && *reader.data != '\0') {
        reader.data++;
    }
    if (readerHasData(&reader, 1)) {
        reader.data++;  // Skip null terminator
    }

    // Code alignment factor
    outCIE->codeAlignmentFactor = readULEB128(&reader);

    // Data alignment factor
    outCIE->dataAlignmentFactor = readSLEB128(&reader);

    // Return address register
    if (outCIE->version == 1) {
        outCIE->returnAddressRegister = readU8(&reader);
    } else {
        outCIE->returnAddressRegister = readULEB128(&reader);
    }

    // Default encodings
    outCIE->fdePointerEncoding = DW_EH_PE_absptr;
    outCIE->lsdaEncoding = DW_EH_PE_omit;

    // Parse augmentation data if present
    if (outCIE->augmentation[0] == 'z') {
        outCIE->hasAugmentation = true;
        uint64_t augLen = readULEB128(&reader);
        const uint8_t *augEnd = reader.data + augLen;

        for (const char *aug = outCIE->augmentation + 1; *aug && reader.data < augEnd; aug++) {
            switch (*aug) {
                case 'L':
                    outCIE->lsdaEncoding = readU8(&reader);
                    break;
                case 'P': {
                    uint8_t personalityEncoding = readU8(&reader);
                    // Skip personality function pointer
                    readEncodedPointer(&reader, personalityEncoding, 0);
                    break;
                }
                case 'R':
                    outCIE->fdePointerEncoding = readU8(&reader);
                    break;
                case 'S':
                    // Signal frame - no data
                    break;
                default:
                    KSLOG_TRACE("Unknown augmentation: %c", *aug);
                    break;
            }
        }

        reader.data = augEnd;
    }

    // Initial instructions
    outCIE->initialInstructions = reader.data;
    outCIE->initialInstructionsLen = (size_t)(reader.end - reader.data);

    return true;
}

static bool parseFDE(const uint8_t *fdeData, size_t fdeSize, const KSDwarfCIE *cie, uintptr_t fdeAddress,
                     KSDwarfFDE *outFDE)
{
    memset(outFDE, 0, sizeof(*outFDE));

    KSDwarfReader reader = {
        .data = fdeData,
        .end = fdeData + fdeSize,
        .baseAddress = 0,
    };

    // PC start (encoded)
    outFDE->pcStart = readEncodedPointer(&reader, cie->fdePointerEncoding, fdeAddress);

    // PC range (same format but no relocation)
    uint8_t rangeFormat = cie->fdePointerEncoding & 0x0F;
    switch (rangeFormat) {
        case DW_EH_PE_absptr:
#if __LP64__
            outFDE->pcRange = readU64(&reader);
#else
            outFDE->pcRange = readU32(&reader);
#endif
            break;
        case DW_EH_PE_udata2:
            outFDE->pcRange = readU16(&reader);
            break;
        case DW_EH_PE_udata4:
            outFDE->pcRange = readU32(&reader);
            break;
        case DW_EH_PE_udata8:
            outFDE->pcRange = readU64(&reader);
            break;
        case DW_EH_PE_sdata2:
            outFDE->pcRange = (uintptr_t)(uint16_t)readS16(&reader);
            break;
        case DW_EH_PE_sdata4:
            outFDE->pcRange = (uintptr_t)(uint32_t)readS32(&reader);
            break;
        case DW_EH_PE_sdata8:
            outFDE->pcRange = readU64(&reader);
            break;
        default:
            outFDE->pcRange = readULEB128(&reader);
            break;
    }

    // Augmentation data if CIE has 'z' augmentation
    if (cie->hasAugmentation) {
        uint64_t augLen = readULEB128(&reader);
        const uint8_t *augStart = reader.data;

        // Parse LSDA if present
        if (cie->lsdaEncoding != DW_EH_PE_omit) {
            outFDE->lsda = readEncodedPointer(&reader, cie->lsdaEncoding, (uintptr_t)augStart);
        }

        reader.data = augStart + augLen;
    }

    // Instructions
    outFDE->instructions = reader.data;
    outFDE->instructionsLen = (size_t)(reader.end - reader.data);

    return true;
}

// MARK: - CFI Instruction Execution

static bool executeCFIInstructions(const uint8_t *instructions, size_t len, const KSDwarfCIE *cie, uintptr_t pcStart,
                                   uintptr_t targetPC, KSDwarfCFIRow *row, const KSDwarfCFIRow *initialState)
{
    KSDwarfReader reader = {
        .data = instructions,
        .end = instructions + len,
        .baseAddress = 0,
    };

    uintptr_t currentPC = pcStart;

    // State stack for remember/restore
    KSDwarfCFIRow stateStack[MAX_STATE_STACK_DEPTH];
    int stateStackDepth = 0;

    while (readerHasData(&reader, 1)) {
        // Stop if we've passed the target PC
        if (currentPC > targetPC) {
            break;
        }

        uint8_t opcode = readU8(&reader);
        uint8_t highBits = opcode & 0xC0;
        uint8_t lowBits = opcode & 0x3F;

        if (highBits == DW_CFA_advance_loc) {
            // Advance location by delta * code_alignment_factor
            currentPC += lowBits * cie->codeAlignmentFactor;
        } else if (highBits == DW_CFA_offset) {
            // Register at CFA + offset
            // Note: offset is unsigned (ULEB128), dataAlignmentFactor is signed (typically negative on x86_64)
            // We must cast offset to signed before multiplication to get correct negative results
            uint64_t offset = readULEB128(&reader);
            if (lowBits < KSDWARF_MAX_REGISTERS) {
                row->registers[lowBits].type = KSDwarfRuleOffset;
                row->registers[lowBits].offset = (int64_t)offset * cie->dataAlignmentFactor;
            }
        } else if (highBits == DW_CFA_restore) {
            // Restore register to its initial state from CIE
            if (lowBits < KSDWARF_MAX_REGISTERS) {
                if (initialState != NULL) {
                    row->registers[lowBits] = initialState->registers[lowBits];
                } else {
                    // No initial state available, set to undefined
                    row->registers[lowBits].type = KSDwarfRuleUndefined;
                }
            }
        } else {
            // Extended opcodes
            switch (opcode) {
                case DW_CFA_nop:
                    break;

                case DW_CFA_set_loc:
                    currentPC = readEncodedPointer(&reader, cie->fdePointerEncoding, 0);
                    break;

                case DW_CFA_advance_loc1:
                    currentPC += readU8(&reader) * cie->codeAlignmentFactor;
                    break;

                case DW_CFA_advance_loc2:
                    currentPC += readU16(&reader) * cie->codeAlignmentFactor;
                    break;

                case DW_CFA_advance_loc4:
                    currentPC += readU32(&reader) * cie->codeAlignmentFactor;
                    break;

                case DW_CFA_offset_extended: {
                    uint64_t reg = readULEB128(&reader);
                    uint64_t offset = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleOffset;
                        row->registers[reg].offset = (int64_t)offset * cie->dataAlignmentFactor;
                    }
                    break;
                }

                case DW_CFA_restore_extended: {
                    uint64_t reg = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        if (initialState != NULL) {
                            row->registers[reg] = initialState->registers[reg];
                        } else {
                            row->registers[reg].type = KSDwarfRuleUndefined;
                        }
                    }
                    break;
                }

                case DW_CFA_undefined: {
                    uint64_t reg = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleUndefined;
                    }
                    break;
                }

                case DW_CFA_same_value: {
                    uint64_t reg = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleSameValue;
                    }
                    break;
                }

                case DW_CFA_register: {
                    uint64_t reg = readULEB128(&reader);
                    uint64_t reg2 = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleRegister;
                        row->registers[reg].regNum = (uint8_t)reg2;
                    }
                    break;
                }

                case DW_CFA_remember_state:
                    if (stateStackDepth < MAX_STATE_STACK_DEPTH) {
                        stateStack[stateStackDepth++] = *row;
                    }
                    break;

                case DW_CFA_restore_state:
                    if (stateStackDepth > 0) {
                        *row = stateStack[--stateStackDepth];
                    }
                    break;

                case DW_CFA_def_cfa: {
                    uint64_t reg = readULEB128(&reader);
                    uint64_t offset = readULEB128(&reader);
                    row->cfaRule = KSDwarfRuleOffset;
                    row->cfaRegister = (uint8_t)reg;
                    row->cfaOffset = (int64_t)offset;
                    break;
                }

                case DW_CFA_def_cfa_register: {
                    uint64_t reg = readULEB128(&reader);
                    row->cfaRegister = (uint8_t)reg;
                    break;
                }

                case DW_CFA_def_cfa_offset: {
                    uint64_t offset = readULEB128(&reader);
                    row->cfaOffset = (int64_t)offset;
                    break;
                }

                case DW_CFA_def_cfa_expression: {
                    uint64_t exprLen = readULEB128(&reader);
                    row->cfaRule = KSDwarfRuleExpression;
                    row->cfaExpression = reader.data;
                    row->cfaExpressionLen = (size_t)exprLen;
                    reader.data += exprLen;
                    break;
                }

                case DW_CFA_expression: {
                    uint64_t reg = readULEB128(&reader);
                    uint64_t exprLen = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleExpression;
                        row->registers[reg].expr = reader.data;
                        row->registers[reg].exprLen = (size_t)exprLen;
                    }
                    reader.data += exprLen;
                    break;
                }

                case DW_CFA_offset_extended_sf: {
                    uint64_t reg = readULEB128(&reader);
                    int64_t offset = readSLEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleOffset;
                        row->registers[reg].offset = offset * cie->dataAlignmentFactor;
                    }
                    break;
                }

                case DW_CFA_def_cfa_sf: {
                    uint64_t reg = readULEB128(&reader);
                    int64_t offset = readSLEB128(&reader);
                    row->cfaRule = KSDwarfRuleOffset;
                    row->cfaRegister = (uint8_t)reg;
                    row->cfaOffset = offset * cie->dataAlignmentFactor;
                    break;
                }

                case DW_CFA_def_cfa_offset_sf: {
                    int64_t offset = readSLEB128(&reader);
                    row->cfaOffset = offset * cie->dataAlignmentFactor;
                    break;
                }

                case DW_CFA_val_offset: {
                    uint64_t reg = readULEB128(&reader);
                    uint64_t offset = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleValOffset;
                        row->registers[reg].offset = (int64_t)offset * cie->dataAlignmentFactor;
                    }
                    break;
                }

                case DW_CFA_val_offset_sf: {
                    uint64_t reg = readULEB128(&reader);
                    int64_t offset = readSLEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleValOffset;
                        row->registers[reg].offset = offset * cie->dataAlignmentFactor;
                    }
                    break;
                }

                case DW_CFA_val_expression: {
                    uint64_t reg = readULEB128(&reader);
                    uint64_t exprLen = readULEB128(&reader);
                    if (reg < KSDWARF_MAX_REGISTERS) {
                        row->registers[reg].type = KSDwarfRuleValExpression;
                        row->registers[reg].expr = reader.data;
                        row->registers[reg].exprLen = (size_t)exprLen;
                    }
                    reader.data += exprLen;
                    break;
                }

                case DW_CFA_GNU_args_size:
                    // Skip argument size
                    readULEB128(&reader);
                    break;

                default:
                    KSLOG_TRACE("Unknown CFI opcode: 0x%x", opcode);
                    break;
            }
        }
    }

    row->location = currentPC;
    return true;
}

// MARK: - Register Value Recovery

static uintptr_t getRegisterValue(uint8_t regNum, uintptr_t sp, uintptr_t fp, uintptr_t lr)
{
#if defined(__arm64__)
    switch (regNum) {
        case KSDWARF_ARM64_SP:
            return sp;
        case KSDWARF_ARM64_FP:
            return fp;
        case KSDWARF_ARM64_LR:
            return lr;
        default:
            return 0;
    }
#elif defined(__x86_64__)
    switch (regNum) {
        case KSDWARF_X86_64_RSP:
            return sp;
        case KSDWARF_X86_64_RBP:
            return fp;
        default:
            return 0;
    }
#elif defined(__arm__)
    switch (regNum) {
        case KSDWARF_ARM_R13:
            return sp;
        case KSDWARF_ARM_R7:
        case KSDWARF_ARM_R11:
            return fp;
        case KSDWARF_ARM_R14:
            return lr;
        default:
            return 0;
    }
#elif defined(__i386__)
    switch (regNum) {
        case KSDWARF_X86_ESP:
            return sp;
        case KSDWARF_X86_EBP:
            return fp;
        default:
            return 0;
    }
#else
    (void)regNum;
    (void)sp;
    (void)fp;
    return 0;
#endif
}

static uint8_t getReturnAddressRegister(void)
{
#if defined(__arm64__)
    return KSDWARF_ARM64_LR;
#elif defined(__x86_64__)
    return KSDWARF_X86_64_RIP;
#elif defined(__arm__)
    return KSDWARF_ARM_R14;
#elif defined(__i386__)
    return KSDWARF_X86_EIP;
#else
    return 0;
#endif
}

static uint8_t getFramePointerRegister(void)
{
#if defined(__arm64__)
    return KSDWARF_ARM64_FP;
#elif defined(__x86_64__)
    return KSDWARF_X86_64_RBP;
#elif defined(__arm__)
    return KSDWARF_ARM_R7;
#elif defined(__i386__)
    return KSDWARF_X86_EBP;
#else
    return 0;
#endif
}

static bool applyRegisterRule(const KSDwarfRegisterRule *rule, uintptr_t cfa, uintptr_t sp, uintptr_t fp, uintptr_t lr,
                              uintptr_t *outValue)
{
    switch (rule->type) {
        case KSDwarfRuleUndefined:
            return false;

        case KSDwarfRuleSameValue:
            // Value unchanged - we don't have the original value
            return false;

        case KSDwarfRuleOffset: {
            // rule->offset can be negative (register saved below CFA), so use signed arithmetic
            uintptr_t addr = (uintptr_t)((intptr_t)cfa + rule->offset);
            return ksmem_copySafely((const void *)addr, outValue, sizeof(*outValue));
        }

        case KSDwarfRuleValOffset:
            // rule->offset can be negative, so use signed arithmetic
            *outValue = (uintptr_t)((intptr_t)cfa + rule->offset);
            return true;

        case KSDwarfRuleRegister:
            *outValue = getRegisterValue(rule->regNum, sp, fp, lr);
            return *outValue != 0;

        case KSDwarfRuleExpression:
        case KSDwarfRuleValExpression:
            // LIMITATION: DWARF expression evaluation is not implemented.
            //
            // DWARF expressions are a stack-based bytecode language that can compute
            // register values or memory addresses. They are used when simple offset-based
            // rules cannot describe the unwind behavior (e.g., hand-written assembly,
            // non-standard stack manipulation).
            //
            // On Apple platforms, DWARF expressions are rare in practice:
            // - Most code uses compact unwind (__unwind_info) which doesn't use expressions
            // - Standard compiler-generated code uses simple CFA+offset rules
            // - Expressions are primarily seen in hand-optimized assembly or unusual ABI code
            //
            // If this becomes a problem in practice, implement a stack-based expression
            // evaluator supporting key opcodes: DW_OP_breg*, DW_OP_deref, DW_OP_lit*,
            // DW_OP_plus_uconst, DW_OP_call_frame_cfa. Must be async-signal-safe (no malloc).
            KSLOG_TRACE("DWARF expression evaluation not implemented");
            return false;

        case KSDwarfRuleArchitectural:
            return false;

        default:
            return false;
    }
}

// MARK: - Public API

bool ksdwarf_findFDE(const void *ehFrame, size_t ehFrameSize, uintptr_t targetPC,
                     uintptr_t imageBase __attribute__((unused)), const uint8_t **outFDE, size_t *outFDESize,
                     const uint8_t **outCIE, size_t *outCIESize)
{
    if (ehFrame == NULL || ehFrameSize == 0) {
        return false;
    }

    const uint8_t *ptr = (const uint8_t *)ehFrame;
    const uint8_t *end = ptr + ehFrameSize;

    while (ptr + 4 < end) {
        // Read length
        uint32_t length = 0;
        memcpy(&length, ptr, sizeof(length));
        ptr += 4;

        if (length == 0) {
            // End marker
            break;
        }

        bool is64bit = false;
        uint64_t actualLength = length;
        if (length == 0xFFFFFFFF) {
            // 64-bit length
            if (ptr + 8 > end) break;
            memcpy(&actualLength, ptr, sizeof(actualLength));
            ptr += 8;
            is64bit = true;
        }

        const uint8_t *entryStart = ptr;
        const uint8_t *entryEnd = ptr + actualLength;
        if (entryEnd > end) break;

        // Read CIE pointer/ID
        uint32_t ciePointer = 0;
        if (is64bit) {
            uint64_t ciePointer64;
            memcpy(&ciePointer64, ptr, sizeof(ciePointer64));
            ciePointer = (uint32_t)ciePointer64;
            ptr += 8;
        } else {
            memcpy(&ciePointer, ptr, sizeof(ciePointer));
            ptr += 4;
        }

        if (ciePointer == 0) {
            // This is a CIE, skip it
            ptr = entryEnd;
            continue;
        }

        // This is an FDE
        // ciePointer is an offset back to the CIE from the CIE pointer field
        // Per .eh_frame spec, this points to the CIE's length field (start of CIE record)
        const uint8_t *cieLengthField = (entryStart - ciePointer);
        if (cieLengthField < (const uint8_t *)ehFrame) {
            ptr = entryEnd;
            continue;
        }

        // Parse FDE to get PC range
        // First, parse the CIE - read length from the length field
        uint32_t cieLength = 0;
        memcpy(&cieLength, cieLengthField, sizeof(cieLength));
        if (cieLength == 0xFFFFFFFF) {
            // LIMITATION: 64-bit DWARF format is not supported.
            //
            // When length == 0xFFFFFFFF, the CIE/FDE uses 64-bit DWARF format where:
            // - An 8-byte length follows the 0xFFFFFFFF marker
            // - CIE ID and pointer fields are 8 bytes instead of 4
            //
            // On Apple platforms, 64-bit DWARF format is extremely rare:
            // - Apple toolchains generate 32-bit DWARF format even for 64-bit targets
            // - The 32-bit format supports lengths up to 4GB which is sufficient
            // - 64-bit format is primarily for exotic ELF systems with huge binaries
            //
            // If needed in the future, extend parsing to handle 64-bit offsets.
            KSLOG_TRACE("64-bit DWARF format not supported, skipping CIE");
            ptr = entryEnd;
            continue;
        }

        // CIE structure: [4: length][4: CIE_id=0][rest: CIE data]
        const uint8_t *cieIdField = cieLengthField + 4;    // Points to CIE_id field (which is 0)
        const uint8_t *cieDataStart = cieLengthField + 8;  // Skip length + CIE_id

        KSDwarfCIE cie;
        if (!parseCIE(cieDataStart, cieLength - 4, &cie)) {  // cieLength - 4 = size after CIE_id
            ptr = entryEnd;
            continue;
        }

        // Now parse FDE
        KSDwarfFDE fde;
        if (!parseFDE(ptr, (size_t)(entryEnd - ptr), &cie, (uintptr_t)entryStart, &fde)) {
            ptr = entryEnd;
            continue;
        }

        // Check if targetPC is in this FDE's range
        if (targetPC >= fde.pcStart && targetPC < fde.pcStart + fde.pcRange) {
            *outFDE = entryStart;
            *outFDESize = (size_t)(entryEnd - entryStart);
            // Return pointer to CIE_id field (not length field) to match ksdwarf_buildCFIRow expectations
            *outCIE = cieIdField;
            *outCIESize = cieLength;  // Size including CIE_id but not length field
            return true;
        }

        ptr = entryEnd;
    }

    return false;
}

bool ksdwarf_buildCFIRow(const uint8_t *cie, size_t cieSize, const uint8_t *fde, size_t fdeSize, uintptr_t targetPC,
                         KSDwarfCFIRow *outRow)
{
    memset(outRow, 0, sizeof(*outRow));

    // Parse CIE
    KSDwarfCIE cieData;
    const uint8_t *cieContent = cie + 4;  // Skip CIE ID (0x00000000)
    if (!parseCIE(cieContent, cieSize - 4, &cieData)) {
        KSLOG_TRACE("Failed to parse CIE");
        return false;
    }

    // Parse FDE
    KSDwarfFDE fdeData;
    const uint8_t *fdeContent = fde + 4;  // Skip CIE pointer
    if (!parseFDE(fdeContent, fdeSize - 4, &cieData, (uintptr_t)fde, &fdeData)) {
        KSLOG_TRACE("Failed to parse FDE");
        return false;
    }

    // Initialize row with CIE initial instructions
    // Pass NULL for initialState since CIE is building the initial state
    if (cieData.initialInstructions && cieData.initialInstructionsLen > 0) {
        if (!executeCFIInstructions(cieData.initialInstructions, cieData.initialInstructionsLen, &cieData,
                                    fdeData.pcStart, targetPC, outRow, NULL)) {
            KSLOG_TRACE("Failed to execute CIE initial instructions");
            return false;
        }
    }

    // Save the initial state after CIE instructions for DW_CFA_restore
    KSDwarfCFIRow initialState = *outRow;

    // Execute FDE instructions, passing the initial state for restore operations
    if (fdeData.instructions && fdeData.instructionsLen > 0) {
        if (!executeCFIInstructions(fdeData.instructions, fdeData.instructionsLen, &cieData, fdeData.pcStart, targetPC,
                                    outRow, &initialState)) {
            KSLOG_TRACE("Failed to execute FDE instructions");
            return false;
        }
    }

    return true;
}

bool ksdwarf_unwind(const void *ehFrame, size_t ehFrameSize, uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr,
                    uintptr_t imageBase, KSDwarfUnwindResult *result)
{
    if (result == NULL) {
        return false;
    }

    memset(result, 0, sizeof(*result));

    // Find FDE for this PC
    const uint8_t *fde = NULL;
    size_t fdeSize = 0;
    const uint8_t *cie = NULL;
    size_t cieSize = 0;

    if (!ksdwarf_findFDE(ehFrame, ehFrameSize, pc, imageBase, &fde, &fdeSize, &cie, &cieSize)) {
        KSLOG_TRACE("No FDE found for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Build CFI row for this PC
    KSDwarfCFIRow row;
    if (!ksdwarf_buildCFIRow(cie, cieSize, fde, fdeSize, pc, &row)) {
        KSLOG_TRACE("Failed to build CFI row for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Calculate CFA
    uintptr_t cfa = 0;
    if (row.cfaRule == KSDwarfRuleOffset) {
        uintptr_t cfaBase = getRegisterValue(row.cfaRegister, sp, fp, lr);
        if (cfaBase == 0) {
            KSLOG_TRACE("CFA base register %u has no value", row.cfaRegister);
            return false;
        }
        cfa = cfaBase + (uintptr_t)row.cfaOffset;
    } else if (row.cfaRule == KSDwarfRuleExpression) {
        KSLOG_TRACE("CFA expression evaluation not implemented");
        return false;
    } else {
        KSLOG_TRACE("Unsupported CFA rule type: %d", row.cfaRule);
        return false;
    }

    KSLOG_TRACE("CFA = 0x%lx (reg %u + %ld)", (unsigned long)cfa, row.cfaRegister, (long)row.cfaOffset);

    // Get return address
    uint8_t raReg = getReturnAddressRegister();
    uintptr_t returnAddress = 0;
    if (!applyRegisterRule(&row.registers[raReg], cfa, sp, fp, lr, &returnAddress)) {
        KSLOG_TRACE("Failed to get return address (reg %u)", raReg);
        return false;
    }

    // Get new stack pointer (usually CFA)
    result->stackPointer = cfa;

    // Get new frame pointer
    uint8_t fpReg = getFramePointerRegister();
    uintptr_t newFP = 0;
    if (applyRegisterRule(&row.registers[fpReg], cfa, sp, fp, lr, &newFP)) {
        result->framePointer = newFP;
    } else {
        result->framePointer = 0;
    }

    result->returnAddress = returnAddress;
    result->valid = true;

    KSLOG_TRACE("DWARF unwind: returnAddr=0x%lx, newSP=0x%lx, newFP=0x%lx", (unsigned long)result->returnAddress,
                (unsigned long)result->stackPointer, (unsigned long)result->framePointer);

    return true;
}
