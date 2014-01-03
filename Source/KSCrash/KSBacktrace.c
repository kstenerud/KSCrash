//
//  KSBacktrace.c
//
//  Created by Karl Stenerud on 2012-01-28.
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


#include "KSBacktrace_Private.h"

#include "KSArchSpecific.h"
#include "KSDynamicLinker.h"
#include "KSMach.h"


/** Remove any pointer tagging in a frame address.
 * Frames are always aligned to double the default pointer size (8 bytes for
 * 32 bit architectures, 16 bytes for 64 bit) in the System V ABI.
 */
#define DETAG_FRAME_CALLER_ADDRESS(A) ((A) & ~(sizeof(uintptr_t)*2-1))

/** Represents an entry in a frame list.
 * This is modeled after the various i386/x64 frame walkers in the xnu source,
 * and seems to work fine in ARM as well. I haven't included the args pointer
 * since it's not needed in this context.
 */
typedef struct KSFrameEntry
{
    /** The previous frame in the list. */
    const struct KSFrameEntry* const previous;

    /** The instruction address. */
    const uintptr_t caller;
} KSFrameEntry;


// Avoiding static functions due to linker issues.



int ksbt_backtraceLength(const STRUCT_MCONTEXT_L* const machineContext)
{
    const uintptr_t instructionAddress = ksmach_instructionAddress(machineContext);

    if(instructionAddress == 0)
    {
        return 0;
    }

    KSFrameEntry frame = {0};
    const uintptr_t framePtr = ksmach_framePointer(machineContext);
    if(framePtr == 0 ||
       ksmach_copyMem((void*)framePtr, &frame, sizeof(frame)) != KERN_SUCCESS)
    {
        return 1;
    }
    for(int i = 1; i < kBacktraceGiveUpPoint; i++)
    {
        if(frame.previous == 0 ||
           ksmach_copyMem(frame.previous, &frame, sizeof(frame)) != KERN_SUCCESS)
        {
            return i;
        }
    }

    return kBacktraceGiveUpPoint;
}

bool ksbt_isBacktraceTooLong(const STRUCT_MCONTEXT_L* const machineContext,
                             int maxLength)
{
    const uintptr_t instructionAddress = ksmach_instructionAddress(machineContext);

    if(instructionAddress == 0)
    {
        return 0;
    }

    KSFrameEntry frame = {0};
    const uintptr_t framePtr = ksmach_framePointer(machineContext);
    if(framePtr == 0 ||
       ksmach_copyMem((void*)framePtr, &frame, sizeof(frame)) != KERN_SUCCESS)
    {
        return 1;
    }
    for(int i = 1; i < maxLength; i++)
    {
        if(frame.previous == 0 ||
           ksmach_copyMem(frame.previous, &frame, sizeof(frame)) != KERN_SUCCESS)
        {
            return false;
        }
    }

    return true;
}

int ksbt_backtraceThreadState(const STRUCT_MCONTEXT_L* const machineContext,
                              uintptr_t*const backtraceBuffer,
                              const int skipEntries,
                              const int maxEntries)
{
    const uintptr_t instructionAddress = ksmach_instructionAddress(machineContext);

    if(maxEntries == 0)
    {
        return 0;
    }

    int startPoint = 0;
    if(skipEntries == 0)
    {
        backtraceBuffer[0] = instructionAddress;

        if(maxEntries == 1)
        {
            return 1;
        }

        startPoint = 1;
    }

    KSFrameEntry frame = {0};

    const uintptr_t framePtr = ksmach_framePointer(machineContext);
    if(framePtr == 0 ||
       ksmach_copyMem((void*)framePtr, &frame, sizeof(frame)) != KERN_SUCCESS)
    {
        return 0;
    }
    for(int i = 1; i < skipEntries; i++)
    {
        if(frame.previous == 0 ||
           ksmach_copyMem(frame.previous, &frame, sizeof(frame)) != KERN_SUCCESS)
        {
            return 0;
        }
    }

    int i;
    for(i = startPoint; i < maxEntries; i++)
    {
        backtraceBuffer[i] = DETAG_FRAME_CALLER_ADDRESS(frame.caller);
        if(backtraceBuffer[i] == 0 ||
           frame.previous == 0 ||
           ksmach_copyMem(frame.previous, &frame, sizeof(frame)) != KERN_SUCCESS)
        {
            break;
        }
    }
    return i;
}

int ksbt_backtraceThread(const thread_t thread,
                         uintptr_t* const backtraceBuffer,
                         const int maxEntries)
{
    STRUCT_MCONTEXT_L machineContext;

    if(!ksmach_threadState(thread, &machineContext))
    {
        return 0;
    }

    return ksbt_backtraceThreadState(&machineContext,
                                     backtraceBuffer,
                                     0,
                                     maxEntries);
}

int ksbt_backtracePthread(const pthread_t thread,
                          uintptr_t* const backtraceBuffer,
                          const int maxEntries)
{
    const thread_t mach_thread = ksmach_machThreadFromPThread(thread);
    if(mach_thread == 0)
    {
        return 0;
    }
    return ksbt_backtraceThread(mach_thread, backtraceBuffer, maxEntries);
}

int ksbt_backtraceSelf(uintptr_t* const backtraceBuffer,
                       const int maxEntries)
{
    return ksbt_backtraceThread(ksmach_thread_self(),
                                backtraceBuffer,
                                maxEntries);
}


void ksbt_symbolicate(const uintptr_t* const backtraceBuffer,
                      Dl_info* const symbolsBuffer,
                      const int numEntries)
{
    for(int i = 0; i < numEntries; i++)
    {
        ksdl_dladdr(backtraceBuffer[i], &symbolsBuffer[i]);
    }
}
