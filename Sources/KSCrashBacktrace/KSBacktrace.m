//
//  KSBacktrace.m
//
//  Created by Alexander Cohen on 2025-05-27.
//
//  Copyright (c) 2025 Alexander Cohen. All rights reserved.
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

#import "KSBacktrace.h"
#import "KSStackCursor.h"
#import "KSStackCursor_MachineContext.h"
#import "KSThread.h"

#import <Foundation/Foundation.h>

#import <mach/mach_init.h>
#import <mach/mach_port.h>
#import <mach/thread_act.h>

size_t ks_backtrace(pthread_t thread, uintptr_t *addresses, size_t count)
{
    if (!addresses || count == 0) {
        return 0;
    }

    const thread_t machThread = pthread_mach_thread_np(thread);
    if (machThread == MACH_PORT_NULL) {
        return 0;
    }

    KSMC_NEW_CONTEXT(machineContext);
    if (!ksmc_getContextForThread(machThread, machineContext, false)) {
        mach_port_deallocate(mach_task_self(), machThread);
        return 0;
    }

    size_t maxFrames = MIN(count, (size_t)KSSC_MAX_STACK_DEPTH);
    KSStackCursor stackCursor = {};
    kssc_initWithMachineContext(&stackCursor, maxFrames, machineContext);

    size_t frameCount = 0;
    while (frameCount < maxFrames && stackCursor.advanceCursor(&stackCursor)) {
        addresses[frameCount++] = stackCursor.stackEntry.address;
    }

    mach_port_deallocate(mach_task_self(), machThread);

    return frameCount;
}
