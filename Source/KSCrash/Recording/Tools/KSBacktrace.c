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

/** Remove any pointer tagging from an instruction address
 * On armv7 the least significant bit of the pointer distinguishes
 * between thumb mode (2-byte instructions) and normal mode (4-byte instructions).
 * On arm64 all instructions are 4-bytes wide so the two least significant
 * bytes should always be 0.
 * On x86_64 and i386, instructions are variable length so all bits are
 * signficant.
 */
#if defined(__arm__)
#define DETAG_INSTRUCTION_ADDRESS(A) ((A) & ~(1))
#elif defined(__arm64__)
#define DETAG_INSTRUCTION_ADDRESS(A) ((A) & ~(3))
#else
#define DETAG_INSTRUCTION_ADDRESS(A) (A)
#endif

/** Step backwards by one instruction.
 * The backtrace of an objective-C program is expected to contain return
 * addresses not call instructions, as that is what can easily be read from
 * the stack. This is not a problem except for a few cases where the return
 * address is inside a different symbol than the call address.
 */
#define CALL_INSTRUCTION_FROM_RETURN_ADDRESS(A) (DETAG_INSTRUCTION_ADDRESS((A)) - 1)

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
    const uintptr_t return_address;
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
    if(maxEntries == 0)
    {
        return 0;
    }

    int i = 0;

    if(skipEntries == 0)
    {
        const uintptr_t instructionAddress = ksmach_instructionAddress(machineContext);
        backtraceBuffer[i] = instructionAddress;
        i++;

        if(i == maxEntries)
        {
            return i;
        }
    }

    if(skipEntries <= 1)
    {
        uintptr_t linkRegister = ksmach_linkRegister(machineContext);

        if(linkRegister)
        {
            backtraceBuffer[i] = linkRegister;
            i++;

            if (i == maxEntries)
            {
                return i;
            }
        }
    }

    KSFrameEntry frame = {0};

    const uintptr_t framePtr = ksmach_framePointer(machineContext);
    if(framePtr == 0 ||
       ksmach_copyMem((void*)framePtr, &frame, sizeof(frame)) != KERN_SUCCESS)
    {
        return 0;
    }
    for(int j = 1; j < skipEntries; j++)
    {
        if(frame.previous == 0 ||
           ksmach_copyMem(frame.previous, &frame, sizeof(frame)) != KERN_SUCCESS)
        {
            return 0;
        }
    }

    for(; i < maxEntries; i++)
    {
        backtraceBuffer[i] = frame.return_address;
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
                      const int numEntries,
                      const int skippedEntries)
{
    int i = 0;

    if(!skippedEntries && i < numEntries)
    {
        ksdl_dladdr(backtraceBuffer[i], &symbolsBuffer[i]);
        i++;
    }

    for(; i < numEntries; i++)
    {
        ksdl_dladdr(CALL_INSTRUCTION_FROM_RETURN_ADDRESS(backtraceBuffer[i]), &symbolsBuffer[i]);
    }
}
