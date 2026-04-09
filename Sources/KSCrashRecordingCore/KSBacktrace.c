//
// KSBacktrace.c
//
// Created by Alexander Cohen on 2025-05-27.
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

#include "KSBacktrace.h"

#include <TargetConditionals.h>
#include <stdatomic.h>
#include <sys/param.h>

#include "KSBinaryImageCache.h"
#include "KSCPU.h"
#include "KSDynamicLinker.h"
#include "KSLogger.h"
#include "KSStackCursor.h"
#include "KSStackCursor_MachineContext.h"
#include "KSStackCursor_SelfThread.h"
#include "KSSymbolicator.h"
#include "KSThread.h"
#include "Unwind/KSStackCursor_Unwind.h"

// Guards concurrent access to thread_suspend/thread_resume in backtrace capture functions.
// Only one remote-thread capture can be in flight at a time. Concurrent callers (e.g., profiler
// sampling while a crash/hang capture is happening) will get 0 frames rather than risk suspending
// an already-suspended thread. Callers should treat 0 frames as "capture unavailable, retry later".
//
// TODO: Extend this to give priority to captures from the crash pipeline so that crash/hang
// backtraces always succeed and profiler sampling yields instead.
static atomic_flag g_captureLock = ATOMIC_FLAG_INIT;

static bool takeThreadCaptureLock(void)
{
    if (atomic_flag_test_and_set(&g_captureLock)) {
        KSLOG_ERROR("takeThreadCaptureLock: another capture is already in progress");
        return false;
    }
    return true;
}

static void releaseThreadCaptureLock(void)
{
    atomic_flag_clear(&g_captureLock);
}


static bool suspendMachThread(thread_t machThread)
{
#if TARGET_OS_WATCH
    (void)machThread;
    return false;
#else
    kern_return_t kr = thread_suspend(machThread);
    if (kr != KERN_SUCCESS) {
        KSLOG_ERROR("thread_suspend (0x%x) failed: %d", machThread, kr);
        return false;
    }
    return true;
#endif
}

static bool resumeMachThread(thread_t machThread)
{
#if TARGET_OS_WATCH
    (void)machThread;
    return false;
#else
    kern_return_t kr = thread_resume(machThread);
    if (kr != KERN_SUCCESS) {
        KSLOG_ERROR("thread_resume (0x%x) failed: %d", machThread, kr);
        return false;
    }
    return true;
#endif
}

// Unwinds a thread that is already suspended. Caller must hold g_captureLock.
static int unwindSuspendedThread(thread_t machThread, uintptr_t *addresses, int maxFrames, bool *isTruncated)
{
    // Lightweight context initialization - only set what's needed for unwinding.
    // Avoids the ~4KB memset that ksmc_getContextForThread does.
    KSMachineContext machineContext = {
        .thisThread = machThread,
        .isCurrentThread = false,
        .isCrashedContext = false,
        .isSignalContext = false,
    };
    kscpu_getState(&machineContext);

    KSStackCursor stackCursor;
    // The unwinder stops when currentDepth >= maxStackDepth, so passing exactly maxFrames
    // would make the truncation probe (the extra advanceCursor call after filling the buffer)
    // always return false. We pass maxFrames+1 so the unwinder allows that one extra step.
    // This is safe: the probe result is never stored into addresses[].
    kssc_initWithUnwind(&stackCursor, maxFrames + 1, &machineContext);

    int frameCount = 0;
    while (frameCount < maxFrames && stackCursor.advanceCursor(&stackCursor)) {
        addresses[frameCount++] = stackCursor.stackEntry.address;
    }

    if (isTruncated) {
        *isTruncated = (frameCount == maxFrames && stackCursor.advanceCursor(&stackCursor));
    }

    return frameCount;
}

static int captureBacktraceFromSelf(uintptr_t *addresses, int maxFrames, bool *isTruncated)
{
    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    int frameCount = 0;
    while (frameCount < maxFrames && stackCursor.advanceCursor(&stackCursor)) {
        addresses[frameCount++] = stackCursor.stackEntry.address;
    }

    if (isTruncated) {
        *isTruncated = (frameCount == maxFrames && stackCursor.advanceCursor(&stackCursor));
    }

    return frameCount;
}

static int captureBacktraceFromSuspendedThread(thread_t machThread, uintptr_t *addresses, int maxFrames, bool *out_isTruncated)
{
    int frameCount = 0;
    bool isTruncated = false;

    if (takeThreadCaptureLock()) {
        frameCount = unwindSuspendedThread(machThread, addresses, maxFrames, &isTruncated);
        releaseThreadCaptureLock();
    }

    if (out_isTruncated) {
        *out_isTruncated = isTruncated;
    }
    return frameCount;
}

static int captureBacktraceFromRunningThread(thread_t machThread, uintptr_t *addresses, int maxFrames, bool *out_isTruncated)
{
    if (machThread == ksthread_self()) {
        return captureBacktraceFromSelf(addresses, maxFrames, out_isTruncated);
    }

    int frameCount = 0;
    bool isTruncated = false;

    if (takeThreadCaptureLock()) {
        if (suspendMachThread(machThread)) {
            frameCount = unwindSuspendedThread(machThread, addresses, maxFrames, &isTruncated);
            resumeMachThread(machThread);
        }
        releaseThreadCaptureLock();
    }

    if (out_isTruncated) {
        *out_isTruncated = isTruncated;
    }
    return frameCount;
}

int ksbt_captureBacktraceFromSuspendedMachThread(thread_t machThread, uintptr_t *addresses, int count,
                                                 bool *isTruncated)
{
    if (!addresses || count <= 0 || machThread == MACH_PORT_NULL) {
        if (isTruncated) {
            *isTruncated = false;
        }
        return 0;
    }

    int maxFrames = MIN(count, KSSC_MAX_STACK_DEPTH);
    return captureBacktraceFromSuspendedThread(machThread, addresses, maxFrames, isTruncated);
}

int ksbt_captureBacktraceFromMachThreadWithTruncation(thread_t machThread, uintptr_t *addresses, int count,
                                                      bool *isTruncated)
{
    if (!addresses || count <= 0 || machThread == MACH_PORT_NULL) {
        if (isTruncated) {
            *isTruncated = false;
        }
        return 0;
    }

    int maxFrames = MIN(count, KSSC_MAX_STACK_DEPTH);
    return captureBacktraceFromRunningThread(machThread, addresses, maxFrames, isTruncated);
}

int ksbt_captureBacktraceFromMachThread(thread_t machThread, uintptr_t *addresses, int count)
{
    return ksbt_captureBacktraceFromMachThreadWithTruncation(machThread, addresses, count, NULL);
}

int ksbt_captureBacktrace(pthread_t thread, uintptr_t *addresses, int count)
{
    return ksbt_captureBacktraceFromMachThread(pthread_mach_thread_np(thread), addresses, count);
}

int ksbt_captureBacktraceWithTruncation(pthread_t thread, uintptr_t *addresses, int count, bool *isTruncated)
{
    return ksbt_captureBacktraceFromMachThreadWithTruncation(pthread_mach_thread_np(thread), addresses, count,
                                                             isTruncated);
}

bool ksbt_quickSymbolicateAddress(uintptr_t address, struct KSSymbolInformation *result)
{
    if (!result) {
        return false;
    }

    // Initialize the dynamic linker (and binary image cache).
    // This has an atomic check so isn't expensive except for the first call.
    ksdl_init();

    uintptr_t untaggedAddress = kssymbolicator_callInstructionAddress(address);

    result->returnAddress = address;
    result->callInstruction = untaggedAddress;

    Dl_info info = {};
    if (ksdl_dladdr(untaggedAddress, &info) == false) {
        return false;
    }

    result->symbolAddress = (uintptr_t)info.dli_saddr;
    result->symbolName = info.dli_sname;
    result->imageName = info.dli_fname;
    result->imageAddress = (uintptr_t)info.dli_fbase;
    return true;
}

bool ksbt_symbolicateAddress(uintptr_t address, struct KSSymbolInformation *result)
{
    if (ksbt_quickSymbolicateAddress(address, result) == false) {
        return false;
    }

    KSBinaryImage image = {};
    if (ksdl_binaryImageForHeader((const void *)result->imageAddress, result->imageName, &image) == false) {
        return false;
    }

    result->imageSize = image.size;
    result->imageUUID = image.uuid;
    result->imageCpuType = image.cpuType;
    result->imageCpuSubType = image.cpuSubType;
    return true;
}
