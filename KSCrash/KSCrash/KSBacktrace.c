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
#include "KSMach.h"

#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>


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

/** Get the image index that the specified address is part of.
 *
 * @param address The address to examine.
 * @return The index of the image it is part of, or UINT_MAX if none was found.
 */
uint32_t ksbt_imageIndexContainingAddress(const uintptr_t address);

/** Get the segment base address of the specified image.
 *
 * This is required for any symtab command offsets.
 *
 * @param index The image index.
 * @return The image's base address, or 0 if none was found.
 */
uintptr_t ksbt_segmentBaseOfImageIndex(const uint32_t idx);

/** async-safe version of dladdr.
 *
 * This method searches the dynamic loader for information about any image
 * containing the specified address. It may not be entirely successful in
 * finding information, in which case any fields it could not find will be set
 * to NULL.
 *
 * Unlike dladdr(), this method does not make use of locks, and does not call
 * async-unsafe functions.
 *
 * @param address The address to search for.
 * @param info Gets filled out by this function.
 * @return true if at least some information was found.
 */
bool ksbt_dladdr(const uintptr_t address, Dl_info* const info);


uint32_t ksbt_imageIndexContainingAddress(const uintptr_t address)
{
    const uint32_t imageCount = _dyld_image_count();
    const struct mach_header* header = 0;

    for(uint32_t iImg = 0; iImg < imageCount; iImg++)
    {
        header = _dyld_get_image_header(iImg);
        if(header != NULL)
        {
            // Look for a segment command with this address within its range.
            uintptr_t addressWSlide = address - (uintptr_t)_dyld_get_image_vmaddr_slide(iImg);
            uintptr_t cmdPtr = ksmach_firstCmdAfterHeader(header);
            if(cmdPtr == 0)
            {
                continue;
            }
            for(uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++)
            {
                const struct load_command* loadCmd = (struct load_command*)cmdPtr;
                if(loadCmd->cmd == LC_SEGMENT)
                {
                    const struct segment_command* segCmd = (struct segment_command*)cmdPtr;
                    if(addressWSlide >= segCmd->vmaddr &&
                       addressWSlide < segCmd->vmaddr + segCmd->vmsize)
                    {
                        return iImg;
                    }
                }
                else if(loadCmd->cmd == LC_SEGMENT_64)
                {
                    const struct segment_command_64* segCmd = (struct segment_command_64*)cmdPtr;
                    if(addressWSlide >= segCmd->vmaddr &&
                       addressWSlide < segCmd->vmaddr + segCmd->vmsize)
                    {
                        return iImg;
                    }
                }
                cmdPtr += loadCmd->cmdsize;
            }
        }
    }
    return UINT_MAX;
}

uintptr_t ksbt_segmentBaseOfImageIndex(const uint32_t idx)
{
    const struct mach_header* header = _dyld_get_image_header(idx);

    // Look for a segment command and return the file image address.
    uintptr_t cmdPtr = ksmach_firstCmdAfterHeader(header);
    if(cmdPtr == 0)
    {
        return 0;
    }
    for(uint32_t i = 0;i < header->ncmds; i++)
    {
        const struct load_command* loadCmd = (struct load_command*)cmdPtr;
        if(loadCmd->cmd == LC_SEGMENT)
        {
            const struct segment_command* segmentCmd = (struct segment_command*)cmdPtr;
            if(strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0)
            {
                return segmentCmd->vmaddr - segmentCmd->fileoff;
            }
        }
        else if(loadCmd->cmd == LC_SEGMENT_64)
        {
            const struct segment_command_64* segmentCmd = (struct segment_command_64*)cmdPtr;
            if(strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0)
            {
                return (uintptr_t)(segmentCmd->vmaddr - segmentCmd->fileoff);
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }

    return 0;
}

bool ksbt_dladdr(const uintptr_t address, Dl_info* const info)
{
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;

    const uint32_t idx = ksbt_imageIndexContainingAddress(address);
    if(idx == UINT_MAX)
    {
        return false;
    }
    const struct mach_header* header = _dyld_get_image_header(idx);
    const uintptr_t imageVMAddrSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(idx);
    const uintptr_t addressWithSlide = address - imageVMAddrSlide;
    const uintptr_t segmentBase = ksbt_segmentBaseOfImageIndex(idx) + imageVMAddrSlide;
    if(segmentBase == 0)
    {
        return false;
    }

    info->dli_fname = _dyld_get_image_name(idx);
    info->dli_fbase = (void*)header;

    // Find symbol tables and get whichever symbol is closest to the address.
    const STRUCT_NLIST* bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPtr = ksmach_firstCmdAfterHeader(header);
    if(cmdPtr == 0)
    {
        return false;
    }
    for(uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++)
    {
        const struct load_command* loadCmd = (struct load_command*)cmdPtr;
        if(loadCmd->cmd == LC_SYMTAB)
        {
            const struct symtab_command* symtabCmd = (struct symtab_command*)cmdPtr;
            const STRUCT_NLIST* symbolTable = (STRUCT_NLIST*)(segmentBase + symtabCmd->symoff);
            const uintptr_t stringTable = segmentBase + symtabCmd->stroff;

            for(uint32_t iSym = 0; iSym < symtabCmd->nsyms; iSym++)
            {
                // If n_value is 0, the symbol refers to an external object.
                if(symbolTable[iSym].n_value != 0)
                {
                    uintptr_t symbolBase = symbolTable[iSym].n_value;
                    uintptr_t currentDistance = addressWithSlide - symbolBase;
                    if((addressWithSlide >= symbolBase) &&
                       (currentDistance <= bestDistance))
                    {
                        bestMatch = symbolTable + iSym;
                        bestDistance = currentDistance;
                    }
                }
            }
            if(bestMatch != NULL)
            {
                info->dli_saddr = (void*)(bestMatch->n_value + imageVMAddrSlide);
                info->dli_sname = (char*)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);
                if(*info->dli_sname == '_')
                {
                    info->dli_sname++;
                }
                // This happens if all symbols have been stripped.
                if(info->dli_saddr == info->dli_fbase && bestMatch->n_type == 3)
                {
                    info->dli_sname = NULL;
                }
                break;
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }

    return true;
}

int ksbt_backtraceLength(const _STRUCT_MCONTEXT* const machineContext)
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

bool ksbt_isBacktraceTooLong(const _STRUCT_MCONTEXT* const machineContext,
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

int ksbt_backtraceThreadState(const _STRUCT_MCONTEXT* const machineContext,
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
    _STRUCT_MCONTEXT machineContext;

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
    return ksbt_backtraceThread(mach_thread_self(),
                                backtraceBuffer,
                                maxEntries);
}


void ksbt_symbolicate(const uintptr_t* const backtraceBuffer,
                      Dl_info* const symbolsBuffer,
                      const int numEntries)
{
    for(int i = 0; i < numEntries; i++)
    {
        ksbt_dladdr(backtraceBuffer[i], &symbolsBuffer[i]);
    }
}
