//
// KSStackCursor_Unwind.c
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

#include "Unwind/KSStackCursor_Unwind.h"

#include "KSCPU.h"
#include "KSMemory.h"
#include "Unwind/KSCompactUnwind.h"
#include "Unwind/KSDwarfUnwind.h"
#include "Unwind/KSUnwindCache.h"

#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

// MARK: - Types

/** Represents a frame entry for frame pointer walking (fallback). */
typedef struct FrameEntry {
    struct FrameEntry *previous;
    uintptr_t return_address;
} FrameEntry;

// Note: KSUnwindMethod enum is defined in the header file

/** Internal context for the unwind cursor. */
typedef struct {
    const struct KSMachineContext *machineContext;
    int maxStackDepth;

    // Current register state (updated as we unwind)
    uintptr_t pc;  // Program counter / instruction pointer
    uintptr_t sp;  // Stack pointer
    uintptr_t fp;  // Frame pointer
    uintptr_t lr;  // Link register (ARM only)

    // State tracking
    bool isFirstFrame;
    bool usedLinkRegister;
    bool fallbackToFramePointer;
    KSUnwindMethod lastMethod;

    // Frame pointer fallback state
    FrameEntry currentFrame;
} UnwindCursorContext;

// MARK: - Architecture-Specific Helpers

#if defined(__arm64__)

static bool tryCompactUnwindForPC(uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr, KSCompactUnwindResult *result)
{
    // Find unwind info for this PC
    const KSUnwindImageInfo *imageInfo = ksunwindcache_getInfoForAddress(pc);
    if (imageInfo == NULL || !imageInfo->hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Find the compact unwind entry for this function
    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo->header;
    if (!kscu_findEntry(imageInfo->unwindInfo, imageInfo->unwindInfoSize, pc, imageBase, imageInfo->slide, &entry)) {
        KSLOG_TRACE("No compact unwind entry for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Check if this encoding requires DWARF
    if (kscu_encodingRequiresDwarf(entry.encoding)) {
        KSLOG_TRACE("Encoding 0x%x requires DWARF for PC 0x%lx", entry.encoding, (unsigned long)pc);
        return false;
    }

    // Decode the compact unwind encoding
    return kscu_arm64_decode(entry.encoding, pc, sp, fp, lr, result);
}

#elif defined(__x86_64__)

static bool tryCompactUnwindForPC(uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr __attribute__((unused)),
                                  KSCompactUnwindResult *result)
{
    const KSUnwindImageInfo *imageInfo = ksunwindcache_getInfoForAddress(pc);
    if (imageInfo == NULL || !imageInfo->hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo->header;
    if (!kscu_findEntry(imageInfo->unwindInfo, imageInfo->unwindInfoSize, pc, imageBase, imageInfo->slide, &entry)) {
        KSLOG_TRACE("No compact unwind entry for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    if (kscu_encodingRequiresDwarf(entry.encoding)) {
        KSLOG_TRACE("Encoding 0x%x requires DWARF for PC 0x%lx", entry.encoding, (unsigned long)pc);
        return false;
    }

    return kscu_x86_64_decode(entry.encoding, pc, sp, fp, result);
}

#elif defined(__arm__)

static bool tryCompactUnwindForPC(uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr, KSCompactUnwindResult *result)
{
    const KSUnwindImageInfo *imageInfo = ksunwindcache_getInfoForAddress(pc);
    if (imageInfo == NULL || !imageInfo->hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo->header;
    if (!kscu_findEntry(imageInfo->unwindInfo, imageInfo->unwindInfoSize, pc, imageBase, imageInfo->slide, &entry)) {
        KSLOG_TRACE("No compact unwind entry for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    if (kscu_encodingRequiresDwarf(entry.encoding)) {
        KSLOG_TRACE("Encoding 0x%x requires DWARF for PC 0x%lx", entry.encoding, (unsigned long)pc);
        return false;
    }

    return kscu_arm_decode(entry.encoding, pc, sp, fp, lr, result);
}

#elif defined(__i386__)

static bool tryCompactUnwindForPC(uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr __attribute__((unused)),
                                  KSCompactUnwindResult *result)
{
    const KSUnwindImageInfo *imageInfo = ksunwindcache_getInfoForAddress(pc);
    if (imageInfo == NULL || !imageInfo->hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo->header;
    if (!kscu_findEntry(imageInfo->unwindInfo, imageInfo->unwindInfoSize, pc, imageBase, imageInfo->slide, &entry)) {
        KSLOG_TRACE("No compact unwind entry for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    if (kscu_encodingRequiresDwarf(entry.encoding)) {
        KSLOG_TRACE("Encoding 0x%x requires DWARF for PC 0x%lx", entry.encoding, (unsigned long)pc);
        return false;
    }

    return kscu_x86_decode(entry.encoding, pc, sp, fp, result);
}

#else
// Unsupported architecture - compact unwind always fails
static bool tryCompactUnwindForPC(uintptr_t pc __attribute__((unused)), uintptr_t sp __attribute__((unused)),
                                  uintptr_t fp __attribute__((unused)), uintptr_t lr __attribute__((unused)),
                                  KSCompactUnwindResult *result __attribute__((unused)))
{
    return false;
}
#endif

// MARK: - DWARF Unwinding

static bool tryDwarfUnwindForPC(uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr, KSCompactUnwindResult *result)
{
    // Find unwind info for this PC
    const KSUnwindImageInfo *imageInfo = ksunwindcache_getInfoForAddress(pc);
    if (imageInfo == NULL || !imageInfo->hasEhFrame) {
        KSLOG_TRACE("No DWARF eh_frame info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Try DWARF unwinding
    KSDwarfUnwindResult dwarfResult;
    uintptr_t imageBase = (uintptr_t)imageInfo->header;
    if (!ksdwarf_unwind(imageInfo->ehFrame, imageInfo->ehFrameSize, pc, sp, fp, lr, imageBase, &dwarfResult)) {
        KSLOG_TRACE("DWARF unwind failed for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    if (!dwarfResult.valid) {
        return false;
    }

    // Copy results to compact unwind result format
    result->valid = true;
    result->returnAddress = dwarfResult.returnAddress;
    result->stackPointer = dwarfResult.stackPointer;
    result->framePointer = dwarfResult.framePointer;
    result->savedRegisterMask = 0;

    KSLOG_TRACE("DWARF unwind succeeded: returnAddr=0x%lx", (unsigned long)result->returnAddress);
    return true;
}

// MARK: - Frame Pointer Fallback

static bool tryFramePointerUnwind(UnwindCursorContext *ctx, uintptr_t *outReturnAddress)
{
    if (ctx->fp == 0) {
        return false;
    }

    // Read the frame entry at FP
    FrameEntry frame;
    if (!ksmem_copySafely((const void *)ctx->fp, &frame, sizeof(frame))) {
        KSLOG_TRACE("Failed to read frame at FP 0x%lx", (unsigned long)ctx->fp);
        return false;
    }

    if (frame.previous == 0 || frame.return_address == 0) {
        return false;
    }

    *outReturnAddress = frame.return_address;
    ctx->currentFrame = frame;

    // Calculate SP from current FP BEFORE updating it
    // On x86/x86_64, SP = FP + 16 (after the saved FP and return address)
    // On ARM64, similar layout
#if defined(__x86_64__) || defined(__arm64__)
    ctx->sp = ctx->fp + 16;
#elif defined(__i386__) || defined(__arm__)
    ctx->sp = ctx->fp + 8;
#endif

    // Update FP for next iteration (AFTER calculating SP)
    ctx->fp = (uintptr_t)frame.previous;

    return true;
}

// MARK: - Cursor Implementation

static bool advanceCursor(KSStackCursor *cursor)
{
    UnwindCursorContext *ctx = (UnwindCursorContext *)cursor->context;
    uintptr_t nextAddress = 0;

    if (cursor->state.currentDepth >= ctx->maxStackDepth) {
        cursor->state.hasGivenUp = true;
        return false;
    }

    // First frame: return the current instruction pointer
    if (ctx->isFirstFrame) {
        ctx->isFirstFrame = false;
        ctx->pc = kscpu_instructionAddress(ctx->machineContext);
        ctx->sp = kscpu_stackPointer(ctx->machineContext);
        ctx->fp = kscpu_framePointer(ctx->machineContext);
        ctx->lr = kscpu_linkRegister(ctx->machineContext);

        if (ctx->pc == 0) {
            return false;
        }

        nextAddress = ctx->pc;
        goto successfulExit;
    }

    // For ARM architectures, the link register contains the return address for the first call
    // Use it before trying to unwind
#if defined(__arm64__) || defined(__arm__)
    if (!ctx->usedLinkRegister && ctx->lr != 0) {
        ctx->usedLinkRegister = true;
        nextAddress = ctx->lr;
        ctx->lastMethod = KSUnwindMethod_None;

        // After using LR, we need to unwind to get the next return address
        // Try compact unwind to update our register state
        KSCompactUnwindResult result;
        if (tryCompactUnwindForPC(ctx->pc, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
            ctx->sp = result.stackPointer;
            ctx->fp = result.framePointer;
            ctx->pc = result.returnAddress;
            ctx->lastMethod = KSUnwindMethod_CompactUnwind;
        }

        goto successfulExit;
    }
#endif

    // Already in frame pointer fallback mode?
    if (ctx->fallbackToFramePointer) {
        if (tryFramePointerUnwind(ctx, &nextAddress)) {
            ctx->lastMethod = KSUnwindMethod_FramePointer;
            goto successfulExit;
        }
        return false;
    }

    // Try compact unwind first
    KSCompactUnwindResult result;
    if (tryCompactUnwindForPC(ctx->pc, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
        nextAddress = result.returnAddress;
        ctx->sp = result.stackPointer;
        ctx->fp = result.framePointer;
        ctx->pc = nextAddress;
        ctx->lastMethod = KSUnwindMethod_CompactUnwind;
        KSLOG_TRACE("Compact unwind succeeded: returnAddr=0x%lx", (unsigned long)nextAddress);
        goto successfulExit;
    }

    // Try DWARF CFI (placeholder for Phase 4)
    if (tryDwarfUnwindForPC(ctx->pc, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
        nextAddress = result.returnAddress;
        ctx->sp = result.stackPointer;
        ctx->fp = result.framePointer;
        ctx->pc = nextAddress;
        ctx->lastMethod = KSUnwindMethod_Dwarf;
        KSLOG_TRACE("DWARF unwind succeeded: returnAddr=0x%lx", (unsigned long)nextAddress);
        goto successfulExit;
    }

    // Fall back to frame pointer walking
    KSLOG_TRACE("Falling back to frame pointer walking from PC 0x%lx", (unsigned long)ctx->pc);
    ctx->fallbackToFramePointer = true;

    if (tryFramePointerUnwind(ctx, &nextAddress)) {
        ctx->lastMethod = KSUnwindMethod_FramePointer;
        goto successfulExit;
    }

    // All methods exhausted
    return false;

successfulExit:
    cursor->stackEntry.address = kscpu_normaliseInstructionPointer(nextAddress);
    cursor->state.currentDepth++;
    return true;
}

static void resetCursor(KSStackCursor *cursor)
{
    kssc_resetCursor(cursor);
    UnwindCursorContext *ctx = (UnwindCursorContext *)cursor->context;

    ctx->pc = 0;
    ctx->sp = 0;
    ctx->fp = 0;
    ctx->lr = 0;
    ctx->isFirstFrame = true;
    ctx->usedLinkRegister = false;
    ctx->fallbackToFramePointer = false;
    ctx->lastMethod = KSUnwindMethod_None;
    ctx->currentFrame.previous = NULL;
    ctx->currentFrame.return_address = 0;
}

// MARK: - Public API

void kssc_initWithUnwind(KSStackCursor *cursor, int maxStackDepth, const struct KSMachineContext *machineContext)
{
    kssc_initCursor(cursor, resetCursor, advanceCursor);

    UnwindCursorContext *ctx = (UnwindCursorContext *)cursor->context;
    ctx->machineContext = machineContext;
    ctx->maxStackDepth = maxStackDepth;
    ctx->pc = 0;
    ctx->sp = 0;
    ctx->fp = 0;
    ctx->lr = 0;
    ctx->isFirstFrame = true;
    ctx->usedLinkRegister = false;
    ctx->fallbackToFramePointer = false;
    ctx->lastMethod = KSUnwindMethod_None;
    ctx->currentFrame.previous = NULL;
    ctx->currentFrame.return_address = 0;
}

const char *kssc_unwindMethodName(KSUnwindMethod method)
{
    switch (method) {
        case KSUnwindMethod_None:
            return "none";
        case KSUnwindMethod_CompactUnwind:
            return "compact_unwind";
        case KSUnwindMethod_Dwarf:
            return "dwarf";
        case KSUnwindMethod_FramePointer:
            return "frame_pointer";
        default:
            return "unknown";
    }
}

KSUnwindMethod kssc_getUnwindMethod(const KSStackCursor *cursor)
{
    if (cursor == NULL) {
        return KSUnwindMethod_None;
    }

    // The context must be an UnwindCursorContext
    // We can verify this by checking if the advanceCursor function matches
    // For safety, we just assume it's correct if non-NULL
    const UnwindCursorContext *ctx = (const UnwindCursorContext *)cursor->context;
    return ctx->lastMethod;
}
