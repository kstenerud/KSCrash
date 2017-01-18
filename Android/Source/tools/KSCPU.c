//
//  KSCPU.h
//
//  Created by Karl Stenerud on 2012-01-29.
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


#include "KSCPU.h"

#include "KSMachineContext_Android.h"
#include "KSSystemCapabilities.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


const char* kscpu_currentArch(void)
{
  // TODO
    return NULL;
}

static const char* g_registerNames[] =
{
  // TODO
    "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7",
    "r8", "r9", "r10", "r11", "ip",
    "sp", "lr", "pc", "cpsr"
};
static const int g_registerNamesCount =
sizeof(g_registerNames) / sizeof(*g_registerNames);


static const char* g_exceptionRegisterNames[] =
{
  // TODO
    "exception", "fsr", "far"
};
static const int g_exceptionRegisterNamesCount =
sizeof(g_exceptionRegisterNames) / sizeof(*g_exceptionRegisterNames);


uintptr_t kscpu_framePointer(const KSMachineContext* const context)
{
  // TODO
    return 0;
}

uintptr_t kscpu_stackPointer(const KSMachineContext* const context)
{
  // TODO
    return 0;
}

uintptr_t kscpu_instructionAddress(const KSMachineContext* const context)
{
  // TODO
    return 0;
}

uintptr_t kscpu_linkRegister(const KSMachineContext* const context)
{
  // TODO
    return 0;
}

void kscpu_getState(KSMachineContext* context)
{
  // TODO
}

int kscpu_numRegisters(void)
{
    return g_registerNamesCount;
}

const char* kscpu_registerName(const int regNumber)
{
    if(regNumber < kscpu_numRegisters())
    {
        return g_registerNames[regNumber];
    }
    return NULL;
}

uint64_t kscpu_registerValue(const KSMachineContext* const context, const int regNumber)
{
  // TODO
    return 0;
}

int kscpu_numExceptionRegisters(void)
{
    return g_exceptionRegisterNamesCount;
}

const char* kscpu_exceptionRegisterName(const int regNumber)
{
    if(regNumber < kscpu_numExceptionRegisters())
    {
        return g_exceptionRegisterNames[regNumber];
    }
    KSLOG_ERROR("Invalid register number: %d", regNumber);
    return NULL;
}

uint64_t kscpu_exceptionRegisterValue(const KSMachineContext* const context, const int regNumber)
{
  // TODO
    return 0;
}

uintptr_t kscpu_faultAddress(const KSMachineContext* const context)
{
  // TODO
    return 0;
}

int kscpu_stackGrowDirection(void)
{
  // TODO
    return -1;
}
