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

#ifndef HDR_KSCPU_h
#define HDR_KSCPU_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSArchSpecific.h"

#include <mach/mach.h>
#include <stdbool.h>
#include <sys/ucontext.h>

/** Get the current CPU architecture.
 *
 * @return The current architecture.
 */
const char* kscpu_currentArch(void);

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
bool kscpu_fillState(thread_t thread,
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
uintptr_t kscpu_framePointer(const STRUCT_MCONTEXT_L* machineContext);

/** Get the current stack pointer for a machine context.
 *
 * @param machineContext The machine context.
 *
 * @return The context's stack pointer.
 */
uintptr_t kscpu_stackPointer(const STRUCT_MCONTEXT_L* machineContext);

/** Get the address of the instruction about to be, or being executed by a
 * machine context.
 *
 * @param machineContext The machine context.
 *
 * @return The context's next instruction address.
 */
uintptr_t kscpu_instructionAddress(const STRUCT_MCONTEXT_L* machineContext);

/** Get the address stored in the link register (arm only). This may
 * contain the first return address of the stack.
 *
 * @param machineContext The machine context.
 *
 * @return The link register value.
 */
uintptr_t kscpu_linkRegister(const STRUCT_MCONTEXT_L* machineContext);

/** Get the address whose access caused the last fault.
 *
 * @param machineContext The machine context.
 *
 * @return The faulting address.
 */
uintptr_t kscpu_faultAddress(const STRUCT_MCONTEXT_L* machineContext);

/** Get a thread's thread state and place it in a machine context.
 *
 * @param thread The thread to fetch state for.
 *
 * @param machineContext The machine context to store the state in.
 *
 * @return true if successful.
 */
bool kscpu_threadState(thread_t thread, STRUCT_MCONTEXT_L* machineContext);

/** Get a thread's floating point state and place it in a machine context.
 *
 * @param thread The thread to fetch state for.
 *
 * @param machineContext The machine context to store the state in.
 *
 * @return true if successful.
 */
bool kscpu_floatState(thread_t thread, STRUCT_MCONTEXT_L* machineContext);

/** Get a thread's exception state and place it in a machine context.
 *
 * @param thread The thread to fetch state for.
 *
 * @param machineContext The machine context to store the state in.
 *
 * @return true if successful.
 */
bool kscpu_exceptionState(thread_t thread, STRUCT_MCONTEXT_L* machineContext);

/** Get the number of normal (not floating point or exception) registers the
 *  currently running CPU has.
 *
 * @return The number of registers.
 */
int kscpu_numRegisters(void);

/** Get the name of a normal register.
 *
 * @param regNumber The register index.
 *
 * @return The register's name or NULL if not found.
 */
const char* kscpu_registerName(int regNumber);

/** Get the value stored in a normal register.
 *
 * @param regNumber The register index.
 *
 * @return The register's current value.
 */
uint64_t kscpu_registerValue(const STRUCT_MCONTEXT_L* machineContext, int regNumber);

/** Get the number of exception registers the currently running CPU has.
 *
 * @return The number of registers.
 */
int kscpu_numExceptionRegisters(void);

/** Get the name of an exception register.
 *
 * @param regNumber The register index.
 *
 * @return The register's name or NULL if not found.
 */
const char* kscpu_exceptionRegisterName(int regNumber);

/** Get the value stored in an exception register.
 *
 * @param regNumber The register index.
 *
 * @return The register's current value.
 */
uint64_t kscpu_exceptionRegisterValue(const STRUCT_MCONTEXT_L* machineContext, int regNumber);

/** Get the direction in which the stack grows on the current architecture.
 *
 * @return 1 or -1, depending on which direction the stack grows in.
 */
int kscpu_stackGrowDirection(void);
    
    
#ifdef __cplusplus
}
#endif

#endif // HDR_KSCPU_h
