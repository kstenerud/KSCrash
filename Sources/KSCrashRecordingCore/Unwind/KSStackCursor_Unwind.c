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

#include <mach/vm_param.h>

#include "KSBinaryImageCache.h"
#include "KSCPU.h"
#include "KSMemory.h"
#include "Unwind/KSCompactUnwind.h"
#include "Unwind/KSDwarfUnwind.h"

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

// MARK: - Address Validation

/**
 * Check if an address is valid for use as a code address.
 *
 * Addresses in the NULL page (first PAGE_SIZE bytes) are invalid. This catches:
 * - NULL pointers
 * - Uninitialized LR values
 * - Corrupted return addresses at thread boundaries (thread_start, _pthread_start)
 *
 * This approach is used by PLCrashReporter and prevents spurious frames
 * at the bottom of the stack.
 */
static inline bool isValidCodeAddress(uintptr_t address) { return address > PAGE_SIZE; }

// MARK: - Types

/** Represents a frame entry for frame pointer walking (fallback). */
typedef struct FrameEntry {
    struct FrameEntry *previous;
    uintptr_t return_address;
} FrameEntry;

// Note: KSUnwindMethod enum is defined in the header file

/** Maximum number of unwind methods (CompactUnwind, Dwarf, FramePointer). */
#define KSUNWIND_MAX_METHODS 3

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
    bool reachedEndOfStack;  // Set when FP becomes 0 (thread entry point reached)
    KSUnwindMethod lastMethod;

    // Method selection - try methods in order until one succeeds (0 = end)
    KSUnwindMethod methods[KSUNWIND_MAX_METHODS];

    // Frame pointer fallback state
    FrameEntry currentFrame;
} UnwindCursorContext;

// MARK: - Architecture-Specific Helpers

#if defined(__arm64__)

static bool tryCompactUnwindForPC(uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr, KSCompactUnwindResult *result)
{
    // Find unwind info for this PC
    KSBinaryImageUnwindInfo imageInfo;
    if (!ksbic_getUnwindInfoForAddress(pc, &imageInfo) || !imageInfo.hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Find the compact unwind entry for this function
    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo.header;
    if (!kscu_findEntry(imageInfo.unwindInfo, imageInfo.unwindInfoSize, pc, imageBase, imageInfo.slide, &entry)) {
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
    KSBinaryImageUnwindInfo imageInfo;
    if (!ksbic_getUnwindInfoForAddress(pc, &imageInfo) || !imageInfo.hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo.header;
    if (!kscu_findEntry(imageInfo.unwindInfo, imageInfo.unwindInfoSize, pc, imageBase, imageInfo.slide, &entry)) {
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
    KSBinaryImageUnwindInfo imageInfo;
    if (!ksbic_getUnwindInfoForAddress(pc, &imageInfo) || !imageInfo.hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo.header;
    if (!kscu_findEntry(imageInfo.unwindInfo, imageInfo.unwindInfoSize, pc, imageBase, imageInfo.slide, &entry)) {
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
    KSBinaryImageUnwindInfo imageInfo;
    if (!ksbic_getUnwindInfoForAddress(pc, &imageInfo) || !imageInfo.hasCompactUnwind) {
        KSLOG_TRACE("No compact unwind info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    KSCompactUnwindEntry entry;
    uintptr_t imageBase = (uintptr_t)imageInfo.header;
    if (!kscu_findEntry(imageInfo.unwindInfo, imageInfo.unwindInfoSize, pc, imageBase, imageInfo.slide, &entry)) {
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
    KSBinaryImageUnwindInfo imageInfo;
    if (!ksbic_getUnwindInfoForAddress(pc, &imageInfo) || !imageInfo.hasEhFrame) {
        KSLOG_TRACE("No DWARF eh_frame info for PC 0x%lx", (unsigned long)pc);
        return false;
    }

    // Try DWARF unwinding
    KSDwarfUnwindResult dwarfResult;
    uintptr_t imageBase = (uintptr_t)imageInfo.header;
    if (!ksdwarf_unwind(imageInfo.ehFrame, imageInfo.ehFrameSize, pc, sp, fp, lr, imageBase, &dwarfResult)) {
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

    // Only check return_address - a NULL previous just means end of chain.
    // A NULL return_address means we can't continue (invalid frame).
    if (frame.return_address == 0) {
        KSLOG_TRACE("Frame at FP 0x%lx has NULL return address", (unsigned long)ctx->fp);
        return false;
    }

    // Validate stack direction: On all Apple platforms, the stack grows downward,
    // so older frames (callers) are at higher addresses. When unwinding, the new FP
    // should be greater than the current FP. If it's less than or equal, we've hit
    // corruption or an invalid frame chain.
    uintptr_t newFP = (uintptr_t)frame.previous;
    if (newFP != 0 && newFP <= ctx->fp) {
        KSLOG_TRACE("Stack direction violation: new FP 0x%lx <= current FP 0x%lx", (unsigned long)newFP,
                    (unsigned long)ctx->fp);
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
    ctx->fp = newFP;

    return true;
}

// MARK: - Cursor Implementation

/**
 * Compute the PC to use for unwind info lookup.
 *
 * Return addresses point to the instruction AFTER the call instruction.
 * To look up unwind info for the function containing the call, we need
 * to subtract 1 from the return address. This prevents spurious frames
 * at function boundaries (e.g., _pthread_start -> thread_start).
 *
 * This technique is used by Firebase/Crashlytics (FIRCLSUnwind.c:156-180).
 *
 * @param pc The program counter value
 * @param isReturnAddress Whether this PC is a return address (vs. current instruction pointer)
 * @return The PC value to use for unwind info lookup
 */
static inline uintptr_t lookupPCForUnwind(uintptr_t pc, bool isReturnAddress)
{
    if (isReturnAddress && pc > 0) {
        return pc - 1;
    }
    return pc;
}

/** Try to unwind one frame using a specific method. Updates ctx state on success.
 *  @param isReturnAddress If true, ctx->pc is a return address and should be adjusted for lookup.
 */
static bool tryUnwindWithMethod(UnwindCursorContext *ctx, KSUnwindMethod method, uintptr_t *outAddress,
                                bool isReturnAddress)
{
    KSCompactUnwindResult result;
    uintptr_t lookupPC = lookupPCForUnwind(ctx->pc, isReturnAddress);

    switch (method) {
        case KSUnwindMethod_CompactUnwind:
            if (tryCompactUnwindForPC(lookupPC, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
                *outAddress = result.returnAddress;
                ctx->sp = result.stackPointer;
                ctx->fp = result.framePointer;
                ctx->pc = result.returnAddress;
                ctx->lastMethod = KSUnwindMethod_CompactUnwind;
                KSLOG_TRACE("Compact unwind succeeded: returnAddr=0x%lx", (unsigned long)*outAddress);
                return true;
            }
            break;

        case KSUnwindMethod_Dwarf:
            if (tryDwarfUnwindForPC(lookupPC, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
                *outAddress = result.returnAddress;
                ctx->sp = result.stackPointer;
                ctx->fp = result.framePointer;
                ctx->pc = result.returnAddress;
                ctx->lastMethod = KSUnwindMethod_Dwarf;
                KSLOG_TRACE("DWARF unwind succeeded: returnAddr=0x%lx", (unsigned long)*outAddress);
                return true;
            }
            break;

        case KSUnwindMethod_FramePointer:
            if (tryFramePointerUnwind(ctx, outAddress)) {
                ctx->pc = *outAddress;
                ctx->lastMethod = KSUnwindMethod_FramePointer;
                KSLOG_TRACE("Frame pointer unwind succeeded: returnAddr=0x%lx", (unsigned long)*outAddress);
                return true;
            }
            break;

        default:
            break;
    }
    return false;
}

#if defined(__arm64__) || defined(__arm__)
/**
 * Try to update register state after using LR, using methods in order.
 *
 * Note: We use the exact PC (not PC-1) here because ctx->pc is still the
 * instruction pointer where the crash/sample occurred, not a return address.
 * The LR value (which IS a return address) will be stored to ctx->pc after
 * this function returns.
 */
static bool tryUpdateStateAfterLR(UnwindCursorContext *ctx)
{
    KSCompactUnwindResult result;

    // Use exact PC - this is the instruction pointer, not a return address
    uintptr_t lookupPC = ctx->pc;

    for (int i = 0; i < KSUNWIND_MAX_METHODS && ctx->methods[i] != KSUnwindMethod_None; i++) {
        switch (ctx->methods[i]) {
            case KSUnwindMethod_CompactUnwind:
                if (tryCompactUnwindForPC(lookupPC, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
                    ctx->sp = result.stackPointer;
                    ctx->fp = result.framePointer;
                    ctx->pc = result.returnAddress;
                    ctx->lastMethod = KSUnwindMethod_CompactUnwind;
                    return true;
                }
                break;

            case KSUnwindMethod_Dwarf:
                if (tryDwarfUnwindForPC(lookupPC, ctx->sp, ctx->fp, ctx->lr, &result) && result.valid) {
                    ctx->sp = result.stackPointer;
                    ctx->fp = result.framePointer;
                    ctx->pc = result.returnAddress;
                    ctx->lastMethod = KSUnwindMethod_Dwarf;
                    return true;
                }
                break;

            case KSUnwindMethod_FramePointer: {
                FrameEntry frame;
                if (ctx->fp != 0 && ksmem_copySafely((const void *)ctx->fp, &frame, sizeof(frame))) {
                    // Validate stack direction: new FP must be greater than current FP
                    // (stack grows downward, so older frames are at higher addresses)
                    uintptr_t newFP = (uintptr_t)frame.previous;
                    if (newFP != 0 && newFP <= ctx->fp) {
                        KSLOG_TRACE("LR path: stack direction violation, new FP 0x%lx <= current FP 0x%lx",
                                    (unsigned long)newFP, (unsigned long)ctx->fp);
                        break;  // Try next method
                    }
                    ctx->fp = newFP;
                    ctx->pc = ctx->lr;
                    return true;
                }
                break;
            }

            default:
                break;
        }
    }
    return false;
}
#endif  // __arm64__ || __arm__

static bool advanceCursor(KSStackCursor *cursor)
{
    UnwindCursorContext *ctx = (UnwindCursorContext *)cursor->context;
    uintptr_t nextAddress = 0;

    if (cursor->state.currentDepth >= ctx->maxStackDepth) {
        cursor->state.hasGivenUp = true;
        return false;
    }

    // If we've already reached the end of the stack (FP became 0), stop.
    // This prevents spurious frames after thread entry points (thread_start, _pthread_start).
    if (ctx->reachedEndOfStack) {
        KSLOG_TRACE("Stopping unwind - already reached end of stack (FP was 0)");
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

        // Validate the LR value before using it. Invalid LR values (in the NULL page)
        // indicate we've reached the bottom of the stack (thread_start, _pthread_start).
        if (!isValidCodeAddress(nextAddress)) {
            KSLOG_TRACE("LR 0x%lx is in NULL page - terminating unwind", (unsigned long)nextAddress);
            return false;
        }

        // After using LR, we need to unwind to get the next return address
        // Try methods in order to update our register state
        if (!tryUpdateStateAfterLR(ctx)) {
            // Fallback: advance FP if possible and set PC to LR
            FrameEntry frame;
            if (ctx->fp != 0 && ksmem_copySafely((const void *)ctx->fp, &frame, sizeof(frame))) {
                // Validate stack direction before updating FP
                uintptr_t newFP = (uintptr_t)frame.previous;
                if (newFP == 0 || newFP > ctx->fp) {
                    ctx->fp = newFP;
                } else {
                    KSLOG_TRACE("LR fallback: stack direction violation, new FP 0x%lx <= current FP 0x%lx",
                                (unsigned long)newFP, (unsigned long)ctx->fp);
                    // Don't update FP on invalid frame chain
                }
            }
            // Always update PC to LR, even if FP read failed. This ensures the next
            // unwind step starts from the correct address rather than a stale PC.
            ctx->pc = ctx->lr;
        }

        // The LR frame itself wasn't unwound - we just read the register.
        // Set method to None regardless of what tryUpdateStateAfterLR did.
        ctx->lastMethod = KSUnwindMethod_None;

        // Check if FP became 0 after LR handling - mark end of stack
        if (ctx->fp == 0) {
            KSLOG_TRACE("FP is 0 after LR handling - marking end of stack");
            ctx->reachedEndOfStack = true;
        }

        goto successfulExit;
    }
#endif

    // Try each method in order until one succeeds.
    // ctx->pc is a return address at this point, so use PC-1 for unwind info lookup.
    for (int i = 0; i < KSUNWIND_MAX_METHODS && ctx->methods[i] != KSUnwindMethod_None; i++) {
        if (tryUnwindWithMethod(ctx, ctx->methods[i], &nextAddress, true /* isReturnAddress */)) {
            // Check if we've reached end of frame chain.
            // At thread entry points (thread_start, _pthread_start), FP is typically 0.
            // If FP is 0 after unwinding, we've reached the bottom of the stack.
            // Accept this frame but mark that we should stop on the next iteration.
            if (ctx->fp == 0) {
                KSLOG_TRACE("FP is 0 after unwind - marking end of stack");
                ctx->reachedEndOfStack = true;
            }
            goto successfulExit;
        }
    }

    // All methods exhausted
    return false;

successfulExit:
    // Final validation: reject addresses in the NULL page.
    // This catches corrupted return addresses and prevents spurious frames
    // at thread boundaries (thread_start, _pthread_start, etc.).
    if (!isValidCodeAddress(nextAddress)) {
        KSLOG_TRACE("Address 0x%lx is in NULL page - terminating unwind", (unsigned long)nextAddress);
        return false;
    }

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
    ctx->reachedEndOfStack = false;
    ctx->lastMethod = KSUnwindMethod_None;
    // Note: methods[] is preserved across reset
    ctx->currentFrame.previous = NULL;
    ctx->currentFrame.return_address = 0;
}

// MARK: - Public API

void kssc_initWithUnwindMethods(KSStackCursor *cursor, int maxStackDepth, const struct KSMachineContext *machineContext,
                                const KSUnwindMethod *methods, size_t methodCount)
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
    ctx->reachedEndOfStack = false;
    ctx->lastMethod = KSUnwindMethod_None;
    ctx->currentFrame.previous = NULL;
    ctx->currentFrame.return_address = 0;

    memset(ctx->methods, 0, sizeof(ctx->methods));
    if (methods != NULL && methodCount > 0) {
        size_t count = methodCount > KSUNWIND_MAX_METHODS ? KSUNWIND_MAX_METHODS : methodCount;
        memcpy(ctx->methods, methods, count * sizeof(KSUnwindMethod));
    }
}

void kssc_initWithUnwind(KSStackCursor *cursor, int maxStackDepth, const struct KSMachineContext *machineContext)
{
    kssc_initWithUnwindMethods(
        cursor, maxStackDepth, machineContext,
        (KSUnwindMethod[]) { KSUnwindMethod_CompactUnwind, KSUnwindMethod_Dwarf, KSUnwindMethod_FramePointer }, 3);
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

    // The context must be an UnwindCursorContext.
    // Verify this by checking if the advanceCursor function matches ours.
    // Cursors from kssc_initWithBacktrace or kssc_initSelfThread have different
    // context layouts and would read garbage if we cast blindly.
    if (cursor->advanceCursor != advanceCursor) {
        return KSUnwindMethod_None;
    }

    const UnwindCursorContext *ctx = (const UnwindCursorContext *)cursor->context;
    return ctx->lastMethod;
}
