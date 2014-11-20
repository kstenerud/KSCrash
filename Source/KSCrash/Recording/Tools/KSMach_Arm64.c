//
//  KSMach_Arm.c
//
//  Created by Karl Stenerud on 2013-09-29.
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

#if defined (__arm64__)


#include "KSMach.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


static const char* g_registerNames[] =
{
     "x0",  "x1",  "x2",  "x3",  "x4",  "x5",  "x6",  "x7",
     "x8",  "x9", "x10", "x11", "x12", "x13", "x14", "x15",
    "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23",
    "x24", "x25", "x26", "x27", "x28", "x29",
    "fp", "lr", "sp", "pc", "cpsr"
};
static const int g_registerNamesCount =
sizeof(g_registerNames) / sizeof(*g_registerNames);


static const char* g_exceptionRegisterNames[] =
{
    "exception", "esr", "far"
};
static const int g_exceptionRegisterNamesCount =
sizeof(g_exceptionRegisterNames) / sizeof(*g_exceptionRegisterNames);


uintptr_t ksmach_framePointer(const STRUCT_MCONTEXT_L* const machineContext)
{
    return machineContext->__ss.__fp;
}

uintptr_t ksmach_stackPointer(const STRUCT_MCONTEXT_L* const machineContext)
{
    return machineContext->__ss.__sp;
}

uintptr_t ksmach_instructionAddress(const STRUCT_MCONTEXT_L* const machineContext)
{
    return machineContext->__ss.__pc;
}

uintptr_t ksmach_linkRegister(const STRUCT_MCONTEXT_L* const machineContext)
{
    return machineContext->__ss.__lr;
}

bool ksmach_threadState(const thread_t thread,
                        STRUCT_MCONTEXT_L* const machineContext)
{
    return ksmach_fillState(thread,
                            (thread_state_t)&machineContext->__ss,
                            ARM_THREAD_STATE64,
                            ARM_THREAD_STATE64_COUNT);
}

bool ksmach_floatState(const thread_t thread,
                       STRUCT_MCONTEXT_L* const machineContext)
{
    return ksmach_fillState(thread,
                            (thread_state_t)&machineContext->__ns,
                            ARM_VFP_STATE,
                            ARM_VFP_STATE_COUNT);
}

bool ksmach_exceptionState(const thread_t thread,
                           STRUCT_MCONTEXT_L* const machineContext)
{
    return ksmach_fillState(thread,
                            (thread_state_t)&machineContext->__es,
                            ARM_EXCEPTION_STATE64,
                            ARM_EXCEPTION_STATE64_COUNT);
}

int ksmach_numRegisters(void)
{
    return g_registerNamesCount;
}

const char* ksmach_registerName(const int regNumber)
{
    if(regNumber < ksmach_numRegisters())
    {
        return g_registerNames[regNumber];
    }
    return NULL;
}

uint64_t ksmach_registerValue(const STRUCT_MCONTEXT_L* const machineContext,
                              const int regNumber)
{
    if(regNumber <= 29)
    {
        return machineContext->__ss.__x[regNumber];
    }

    switch(regNumber)
    {
        case 30: return machineContext->__ss.__fp;
        case 31: return machineContext->__ss.__lr;
        case 32: return machineContext->__ss.__sp;
        case 33: return machineContext->__ss.__pc;
        case 34: return machineContext->__ss.__cpsr;
    }

    KSLOG_ERROR("Invalid register number: %d", regNumber);
    return 0;
}

int ksmach_numExceptionRegisters(void)
{
    return g_exceptionRegisterNamesCount;
}

const char* ksmach_exceptionRegisterName(const int regNumber)
{
    if(regNumber < ksmach_numExceptionRegisters())
    {
        return g_exceptionRegisterNames[regNumber];
    }
    KSLOG_ERROR("Invalid register number: %d", regNumber);
    return NULL;
}

uint64_t ksmach_exceptionRegisterValue(const STRUCT_MCONTEXT_L* const machineContext,
                                       const int regNumber)
{
    switch(regNumber)
    {
        case 0:
            return machineContext->__es.__exception;
        case 1:
            return machineContext->__es.__esr;
        case 2:
            return machineContext->__es.__far;
    }

    KSLOG_ERROR("Invalid register number: %d", regNumber);
    return 0;
}

uintptr_t ksmach_faultAddress(const STRUCT_MCONTEXT_L* const machineContext)
{
    return machineContext->__es.__far;
}

int ksmach_stackGrowDirection(void)
{
    return -1;
}


#endif
