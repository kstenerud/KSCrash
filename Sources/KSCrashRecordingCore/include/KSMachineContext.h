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

#include <mach/mach.h>
#include <stdbool.h>

#include "KSCrashNamespace.h"
#include "KSMachineContext_Apple.h"
#include "KSThread.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Suspend the runtime environment.
 *
 * This function is idempotent.
 *
 * @param threadsToSuspend Pointer to where the threads list pointer will be stored. The pointed-to value MUST be NULL
 * or else this function will no-op!
 * @param threadsToSuspendCount Pointer to where the count of suspended threads will be stored.
 */
void ksmc_suspendEnvironment(thread_act_array_t *threadsToSuspend, mach_msg_type_number_t *threadsToSuspendCount);

/**
 * Resume the runtime environment.
 *
 * This function is idempotent.
 *
 * @param suspendedThreads Pointer to where the threads list pointer is stored. The threads list pointer will be set to
 * NULL on completion.
 * @param suspendedThreadsCount Pointer to where the count of suspended threads is stored. The count will be set to
 * 0 on completion.
 */
void ksmc_resumeEnvironment(thread_act_array_t *suspendedThreads, mach_msg_type_number_t *suspendedThreadsCount);

/** Get the internal size of a machine context.
 */
int ksmc_contextSize(void);

/** Fill in a machine context from a thread.
 *
 * @param thread The thread to get information from.
 * @param destinationContext The context to fill.
 * @param isCrashedContext Used to indicate that this is the thread that crashed,
 *
 * @return true if successful.
 */
bool ksmc_getContextForThread(KSThread thread, struct KSMachineContext *destinationContext, bool isCrashedContext);

/** Fill in a machine context from a signal handler.
 * A signal handler context is always assumed to be a crashed context.
 *
 * @param signalUserContext The signal context to get information from.
 * @param destinationContext The context to fill.
 *
 * @return true if successful.
 */
bool ksmc_getContextForSignal(void *signalUserContext, struct KSMachineContext *destinationContext);

/** Get the thread associated with a machine context.
 *
 * @param context The machine context.
 *
 * @return The associated thread.
 */
KSThread ksmc_getThreadFromContext(const struct KSMachineContext *const context);

/** Get the number of threads stored in a machine context.
 *
 * @param context The machine context.
 *
 * @return The number of threads.
 */
int ksmc_getThreadCount(const struct KSMachineContext *const context);

/** Get a thread from a machine context.
 *
 * @param context The machine context.
 * @param index The index of the thread to retrieve.
 *
 * @return The thread.
 */
KSThread ksmc_getThreadAtIndex(const struct KSMachineContext *const context, int index);

/** Get the index of a thread.
 *
 * @param context The machine context.
 * @param thread The thread.
 *
 * @return The thread's index, or -1 if it couldn't be determined.
 */
int ksmc_indexOfThread(const struct KSMachineContext *const context, KSThread thread);

/** Check if this is a crashed context.
 */
bool ksmc_isCrashedContext(const struct KSMachineContext *const context);

/** Check if this context can have stored CPU state.
 */
bool ksmc_canHaveCPUState(const struct KSMachineContext *const context);

/** Check if this context has valid exception registers.
 */
bool ksmc_hasValidExceptionRegisters(const struct KSMachineContext *const context);

/** Add a thread to the reserved threads list.
 *
 * @param thread The thread to add to the list.
 */
void ksmc_addReservedThread(KSThread thread);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSMachineContext_h
