//
//  KSStackCursor_SelfThread.c
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


#include "KSStackCursor_SelfThread.h"
#include "KSStackCursor_Backtrace.h"
#include <unwind.h>

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#define MAX_BACKTRACE_LENGTH (KSSC_CONTEXT_SIZE - sizeof(KSStackCursor_Backtrace_Context) / sizeof(void*) - 1)

typedef struct
{
    KSStackCursor_Backtrace_Context SelfThreadContextSpacer;
    uintptr_t backtrace[0];
} SelfThreadContext;

typedef struct
{
    void** current;
    void** end;
} BacktracePosition;

static _Unwind_Reason_Code unwindCallback(struct _Unwind_Context* context, void* arg)
{
    BacktracePosition* position = (BacktracePosition*)arg;
    uintptr_t pc = _Unwind_GetIP(context);
    if(pc != 0)
    {
        if (position->current >= position->end)
        {
            return _URC_END_OF_STACK;
        }
        *position->current++ = (void*)pc;
    }
    return _URC_NO_REASON;
}

void kssc_initSelfThread(KSStackCursor *cursor, int skipEntries)
{
    SelfThreadContext* context = (SelfThreadContext*)cursor->context;
    void** backtrace = (void**)context->backtrace;
    BacktracePosition state = {backtrace, backtrace + MAX_BACKTRACE_LENGTH};
    _Unwind_Backtrace(unwindCallback, &state);
    int backtraceLength = (int)(state.current - backtrace);
    kssc_initWithBacktrace(cursor, context->backtrace, backtraceLength, skipEntries + 1);
}
