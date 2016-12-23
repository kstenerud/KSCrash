//
//  KSStackCursor_MachineContext.c
//
//  Copyright (c) 2016 Karl Stenerud. All rights reserved.
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


#include "KSStackCursor_MachineContext.h"

#include "KSCPU.h"
#include "KSMemory.h"

#include <stdlib.h>

#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


/** Represents an entry in a frame list.
 * This is modeled after the various i386/x64 frame walkers in the xnu source,
 * and seems to work fine in ARM as well. I haven't included the args pointer
 * since it's not needed in this context.
 */
typedef struct FrameEntry
{
    /** The previous frame in the list. */
    struct FrameEntry* previous;
    
    /** The instruction address. */
    uintptr_t return_address;
} FrameEntry;


typedef struct
{
    const struct KSMachineContext* machineContext;
    FrameEntry currentFrame;
    uintptr_t instructionAddress;
    uintptr_t linkRegister;
    bool isPastFramePointer;
} MachineContextCursor;

static bool advanceCursor(KSStackCursor *cursor)
{
    MachineContextCursor* cursorContext = (MachineContextCursor*)cursor->context;
    
    if(cursor->state.currentDepth >= cursor->state.maxDepth)
    {
        return false;
    }
    
    if(cursorContext->instructionAddress == 0)
    {
        return false;
    }

    if(cursorContext->linkRegister == 0 && !cursorContext->isPastFramePointer)
    {
        // Link register, if available, is the second address in the trace.
        cursorContext->linkRegister = kscpu_linkRegister(cursorContext->machineContext);
        if(cursorContext->linkRegister != 0)
        {
            cursor->stackEntry.address = cursorContext->linkRegister;
            cursor->state.currentDepth++;
            return true;
        }
    }

    if(cursorContext->currentFrame.previous == NULL)
    {
        if(cursorContext->isPastFramePointer)
        {
            return false;
        }
        cursorContext->currentFrame.previous = (struct FrameEntry*)kscpu_framePointer(cursorContext->machineContext);
        cursorContext->isPastFramePointer = true;
    }

    if(!ksmem_copySafely(cursorContext->currentFrame.previous, &cursorContext->currentFrame, sizeof(cursorContext->currentFrame)))
    {
        return false;
    }
    if(cursorContext->currentFrame.previous == 0 || cursorContext->currentFrame.return_address == 0)
    {
        return false;
    }

    cursor->stackEntry.address = cursorContext->currentFrame.return_address;
    cursor->state.currentDepth++;
    return true;
}

void kssc_initWithMachineContext(KSStackCursor *cursor, int maxStackDepth, const struct KSMachineContext* machineContext)
{
    kssc_initCursor(cursor, maxStackDepth, kscpu_instructionAddress(machineContext));
    cursor->advanceCursor = advanceCursor;

    MachineContextCursor* cursorContext = (MachineContextCursor*)cursor->context;
    cursorContext->machineContext = machineContext;
    cursorContext->instructionAddress = cursor->stackEntry.address;
}
