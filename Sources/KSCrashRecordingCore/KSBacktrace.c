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

static atomic_flag g_captureLock = ATOMIC_FLAG_INIT;

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

static int captureBacktraceFromOtherThread(thread_t machThread, uintptr_t *addresses, int maxFrames, bool *isTruncated)
{
    if (atomic_flag_test_and_set(&g_captureLock)) {
        KSLOG_ERROR("captureBacktraceFromOtherThread: another capture is already in progress");
        if (isTruncated) {
            *isTruncated = false;
        }
        return 0;
    }

#if !TARGET_OS_WATCH
    kern_return_t kr = thread_suspend(machThread);
    if (kr != KERN_SUCCESS) {
        KSLOG_ERROR("thread_suspend (0x%x) failed: %d", machThread, kr);
        atomic_flag_clear(&g_captureLock);
        if (isTruncated) {
            *isTruncated = false;
        }
        return 0;
    }
#endif

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
    kssc_initWithUnwind(&stackCursor, maxFrames, &machineContext);

    int frameCount = 0;
    while (frameCount < maxFrames && stackCursor.advanceCursor(&stackCursor)) {
        addresses[frameCount++] = stackCursor.stackEntry.address;
    }

    if (isTruncated) {
        *isTruncated = (frameCount == maxFrames && stackCursor.advanceCursor(&stackCursor));
    }

#if !TARGET_OS_WATCH
    kr = thread_resume(machThread);
    if (kr != KERN_SUCCESS) {
        KSLOG_ERROR("thread_resume (0x%x) failed: %d", machThread, kr);
    }
#endif

    atomic_flag_clear(&g_captureLock);
    return frameCount;
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

    if (machThread == ksthread_self()) {
        return captureBacktraceFromSelf(addresses, maxFrames, isTruncated);
    }
    return captureBacktraceFromOtherThread(machThread, addresses, maxFrames, isTruncated);
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
