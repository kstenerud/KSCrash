//
//  KSMachineContext.h
//
//  Created by Karl Stenerud on 2016-12-02.
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


#ifndef HDR_KSMachineContext_h
#define HDR_KSMachineContext_h

#ifdef __cplusplus
extern "C" {
#endif

#include "KSThread.h"
#include <stdbool.h>

#define KSMC_NEW_CONTEXT(NAME) \
    char ksmc_##NAME##_storage[ksmc_contextSize()]; \
    KSMachineContext NAME = (KSMachineContext)ksmc_##NAME##_storage

typedef void* KSMachineContext;
    
int ksmc_contextSize();

bool ksmc_getContextForThread(KSThread thread, KSMachineContext destinationContext, bool isCrashedContext);
bool ksmc_getContextForSignal(void* signalUserContext, KSMachineContext destinationContext);

KSThread ksmc_getContextThread(const KSMachineContext context);
void ksmc_suspendEnvironment();
void ksmc_resumeEnvironment();
int ksmc_getThreadCount(const KSMachineContext context);
KSThread ksmc_getThreadAtIndex(const KSMachineContext context, int index);
    /** Get the index of a thread.
     *
     * @param thread The thread.
     *
     * @return The thread's index, or -1 if it couldn't be determined.
     */
int ksmc_indexOfThread(const KSMachineContext context, KSThread thread);
    bool ksmc_isCrashedContext(const KSMachineContext context);
    bool ksmc_canHaveCPUState(KSMachineContext context);
    bool ksmc_canHaveNormalStackTrace(KSMachineContext context);
    bool ksmc_canHaveCustomStackTrace(KSMachineContext context);
    bool ksmc_hasValidExceptionRegisters(const KSMachineContext context);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSMachineContext_h
