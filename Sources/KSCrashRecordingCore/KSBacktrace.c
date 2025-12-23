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

#include <sys/param.h>

#include "KSBinaryImageCache.h"
#include "KSDynamicLinker.h"
#include "KSStackCursor.h"
#include "KSStackCursor_MachineContext.h"
#include "KSStackCursor_SelfThread.h"
#include "KSSymbolicator.h"
#include "KSThread.h"

int ksbt_captureBacktrace(pthread_t thread, uintptr_t *addresses, int count)
{
    return ksbt_captureBacktraceFromMachThread(pthread_mach_thread_np(thread), addresses, count);
}

int ksbt_captureBacktraceFromMachThread(thread_t machThread, uintptr_t *addresses, int count)
{
    if (!addresses || count == 0 || machThread == MACH_PORT_NULL) {
        return 0;
    }

    KSMachineContext machineContext = { 0 };
    KSStackCursor stackCursor = {};
    int maxFrames = MIN(count, KSSC_MAX_STACK_DEPTH);

    if (machThread == ksthread_self()) {
        kssc_initSelfThread(&stackCursor, 0);
    } else {
        if (!ksmc_getContextForThread(machThread, &machineContext, false)) {
            return 0;
        }
        kssc_initWithMachineContext(&stackCursor, maxFrames, &machineContext);
    }

    int frameCount = 0;
    while (frameCount < maxFrames && stackCursor.advanceCursor(&stackCursor)) {
        addresses[frameCount++] = stackCursor.stackEntry.address;
    }

    return frameCount;
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
    return true;
}
