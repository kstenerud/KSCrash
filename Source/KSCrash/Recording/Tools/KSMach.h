//
//  KSMach.h
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


/* Utility functions for querying the mach kernel.
 */


#ifndef HDR_KSMach_h
#define HDR_KSMach_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSArchSpecific.h"

#include <mach/mach.h>
#include <pthread.h>
#include <stdbool.h>
#include <sys/ucontext.h>


// ============================================================================
#pragma mark - Initialization -
// ============================================================================

/** Initializes KSMach.
 * Some functions (currently only ksmach_pthreadFromMachThread) require
 * initialization before use.
 */
void ksmach_init(void);


// ============================================================================
#pragma mark - General Information -
// ============================================================================

/** Get the total memory that is currently free.
 *
 * @return total free memory.
 */
uint64_t ksmach_freeMemory(void);

/** Get the total memory that is currently usable.
 *
 * @return total usable memory.
 */
uint64_t ksmach_usableMemory(void);

/** Get the current CPU architecture.
 *
 * @return The current architecture.
 */
const char* ksmach_currentCPUArch(void);

/** Get the name of a mach exception.
 *
 * @param exceptionType The exception type.
 *
 * @return The exception's name or NULL if not found.
 */
const char* ksmach_exceptionName(exception_type_t exceptionType);

/** Get the name of a mach kernel return code.
 *
 * @param code The return code.
 *
 * @return The code's name or NULL if not found.
 */
const char* ksmach_kernelReturnCodeName(kern_return_t returnCode);


// ============================================================================
#pragma mark - Thread State Info -
// ============================================================================

/** Fill in state information about a thread.
 *
 * @param thread The thread to get information about.
 *
 * @param state Pointer to buffer for state information.
 *
 * @param flavor The kind of information to get (arch specific).
 *
 * @param stateCount Number of entries in the state information buffer.
 *
 * @return true if state fetching was successful.
 */
bool ksmach_fillState(thread_t thread,
                      thread_state_t state,
                      thread_state_flavor_t flavor,
                      mach_msg_type_number_t stateCount);

/** Get the frame pointer for a machine context.
 * The frame pointer marks the top of the call stack.
 *
 * @param machineContext The machine context.
 *
 * @return The context's frame pointer.
 */
uintptr_t ksmach_framePointer(const STRUCT_MCONTEXT_L* machineContext);

/** Get the current stack pointer for a machine context.
 *
 * @param machineContext The machine context.
 *
 * @return The context's stack pointer.
 */
uintptr_t ksmach_stackPointer(const STRUCT_MCONTEXT_L* machineContext);

/** Get the address of the instruction about to be, or being executed by a
 * machine context.
 *
 * @param machineContext The machine context.
 *
 * @return The context's next instruction address.
 */
uintptr_t ksmach_instructionAddress(const STRUCT_MCONTEXT_L* machineContext);

/** Get the address stored in the link register (arm only). This may
 * contain the first return address of the stack.
 *
 * @param machineContext The machine context.
 *
 * @return The link register value.
 */
uintptr_t ksmach_linkRegister(const STRUCT_MCONTEXT_L* machineContext);

/** Get the address whose access caused the last fault.
 *
 * @param machineContext The machine context.
 *
 * @return The faulting address.
 */
uintptr_t ksmach_faultAddress(const STRUCT_MCONTEXT_L* machineContext);

/** Get a thread's thread state and place it in a machine context.
 *
 * @param thread The thread to fetch state for.
 *
 * @param machineContext The machine context to store the state in.
 *
 * @return true if successful.
 */
bool ksmach_threadState(thread_t thread, STRUCT_MCONTEXT_L* machineContext);

/** Get a thread's floating point state and place it in a machine context.
 *
 * @param thread The thread to fetch state for.
 *
 * @param machineContext The machine context to store the state in.
 *
 * @return true if successful.
 */
bool ksmach_floatState(thread_t thread, STRUCT_MCONTEXT_L* machineContext);

/** Get a thread's exception state and place it in a machine context.
 *
 * @param thread The thread to fetch state for.
 *
 * @param machineContext The machine context to store the state in.
 *
 * @return true if successful.
 */
bool ksmach_exceptionState(thread_t thread, STRUCT_MCONTEXT_L* machineContext);

/** Get the number of normal (not floating point or exception) registers the
 *  currently running CPU has.
 *
 * @return The number of registers.
 */
int ksmach_numRegisters(void);

/** Get the name of a normal register.
 *
 * @param regNumber The register index.
 *
 * @return The register's name or NULL if not found.
 */
const char* ksmach_registerName(int regNumber);

/** Get the value stored in a normal register.
 *
 * @param regNumber The register index.
 *
 * @return The register's current value.
 */
uint64_t ksmach_registerValue(const STRUCT_MCONTEXT_L* machineContext,
                              int regNumber);

/** Get the number of exception registers the currently running CPU has.
 *
 * @return The number of registers.
 */
int ksmach_numExceptionRegisters(void);

/** Get the name of an exception register.
 *
 * @param regNumber The register index.
 *
 * @return The register's name or NULL if not found.
 */
const char* ksmach_exceptionRegisterName(int regNumber);

/** Get the value stored in an exception register.
 *
 * @param regNumber The register index.
 *
 * @return The register's current value.
 */
uint64_t ksmach_exceptionRegisterValue(const STRUCT_MCONTEXT_L* machineContext,
                                       int regNumber);

/** Get the direction in which the stack grows on the current architecture.
 *
 * @return 1 or -1, depending on which direction the stack grows in.
 */
int ksmach_stackGrowDirection(void);

/** Get a thread's name. Internally, a thread name will
 * never be more than 64 characters long.
 *
 * @param thread The thread whose name to get.
 *
 * @oaram buffer Buffer to hold the name.
 *
 * @param bufLength The length of the buffer.
 *
 * @return true if a name was found.
 */
bool ksmach_getThreadName(const thread_t thread, char* const buffer, size_t bufLength);

/** Get the name of a thread's dispatch queue. Internally, a queue name will
 * never be more than 64 characters long.
 *
 * @param thread The thread whose queue name to get.
 *
 * @oaram buffer Buffer to hold the name.
 *
 * @param bufLength The length of the buffer.
 *
 * @return true if a name or label was found.
 */
bool ksmach_getThreadQueueName(thread_t thread, char* buffer, size_t bufLength);


// ============================================================================
#pragma mark - Utility -
// ============================================================================

/* Get the current mach thread ID.
 * mach_thread_self() receives a send right for the thread port which needs to
 * be deallocated to balance the reference count. This function takes care of
 * all of that for you.
 *
 * @return The current thread ID.
 */
thread_t ksmach_thread_self();

/** Get a mach thread's corresponding posix thread.
 *
 * @param thread The mach thread.
 *
 * @return The corresponding posix thread, or 0 if an error occurred.
 */
pthread_t ksmach_pthreadFromMachThread(const thread_t thread);

/** Get a posix thread's corresponding mach thread.
 *
 * @param pthread The posix thread.
 *
 * @return The corresponding mach thread, or 0 if an error occurred.
 */
thread_t ksmach_machThreadFromPThread(const pthread_t pthread);

/** Suspend all threads except for the current one.
 *
 * @return true if thread suspention was at least partially successful.
 */
bool ksmach_suspendAllThreads(void);

/** Suspend all threads except for the current one and the specified threads.
 *
 * @param exceptThreads The threads to avoid suspending.
 *
 * @param exceptThreadsCount The number of threads to avoid suspending.
 *
 * @return true if thread suspention was at least partially successful.
 */
bool ksmach_suspendAllThreadsExcept(thread_t* exceptThreads, int exceptThreadsCount);

/** Resume all threads except for the current one.
 *
 * @return true if thread resumption was at least partially successful.
 */
bool ksmach_resumeAllThreads(void);

/** Resume all threads except for the current one and the specified threads.
 *
 * @param exceptThreads The threads to avoid resuming.
 *
 * @param exceptThreadsCount The number of threads to avoid resuming.
 *
 * @return true if thread resumption was at least partially successful.
 */
bool ksmach_resumeAllThreadsExcept(thread_t* exceptThreads, int exceptThreadsCount);

/** Copy memory safely. If the memory is not accessible, returns false
 * rather than crashing.
 *
 * @param src The source location to copy from.
 *
 * @param dst The location to copy to.
 *
 * @param numBytes The number of bytes to copy.
 *
 * @return KERN_SUCCESS or an error code.
 */
kern_return_t ksmach_copyMem(const void* src, void* dst, size_t numBytes);

/** Copies up to numBytes of data from src to dest, stopping if memory
 * becomes inaccessible.
 *
 * @param src The source location to copy from.
 *
 * @param dst The location to copy to.
 *
 * @param numBytes The number of bytes to copy.
 *
 * @return The number of bytes actually copied.
 */
size_t ksmach_copyMaxPossibleMem(const void* src, void* dst, size_t numBytes);

/** Get the difference in seconds between two timestamps fetched via
 * mach_absolute_time().
 *
 * @param endTime The greater of the two times.
 *
 * @param startTime The lesser of the two times.
 *
 * @return The difference between the two timestamps in seconds.
 */
double ksmach_timeDifferenceInSeconds(uint64_t endTime, uint64_t startTime);

/** Check if the current process is being traced or not.
 *
 * @return true if we're being traced.
 */
bool ksmach_isBeingTraced(void);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSMach_h
