//
//  KSCrashHandler_MachException.c
//
//  Created by Karl Stenerud on 12-02-04.
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


#include "KSCrashHandler_MachException.h"

#include "KSCrashHandler_Common.h"
#include "KSLogger.h"
#include "KSMach.h"

#include <errno.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>


/** A mach exception message (according to ux_exception.c).
 */
typedef struct
{
    /** Mach header. */
    mach_msg_header_t          header;
    
    // Start of the kernel processed data.
    
    /** Basic message body data. */
    mach_msg_body_t            body;
    
    /** The thread that raised the exception. */
    mach_msg_port_descriptor_t thread;
    
    /** The task that raised the exception. */
    mach_msg_port_descriptor_t task;
    
    // End of the kernel processed data.
    
    /** Network Data Representation. */
    NDR_record_t               NDR;
    
    /** The exception that was raised. */
    exception_type_t           exception;
    
    /** The number of codes. */
    mach_msg_type_number_t     codeCount;
    
    /** Exception code and subcode. */
    // ux_exception.c defines this as mach_exception_data_t for some reason.
    // But it's not actually a pointer; it's an embedded array.
    // On 32-bit systems, only the lower 32 bits of the code and subcode
    // are valid.
    mach_exception_data_type_t code[0];
    
    /** Padding to avoid RCV_TOO_LARGE. */
    char                       padding[512];
} MachExceptionMessage;

/** A mach reply message (according to ux_exception.c).
 */
typedef struct
{
    /** Mach header. */
    mach_msg_header_t header;
    
    /** Network Data Representation. */
    NDR_record_t      NDR;
    
    /** Return code. */
    kern_return_t     returnCode;
} MachReplyMessage;


/** Flag noting if we've installed our custom handlers or not.
 * It's not fully thread safe, but it's safer than locking and slightly better
 * than nothing.
 */
static volatile sig_atomic_t g_installed = 0;

/** Holds exception port info regarding the previously installed exception
 * handlers.
 */
static struct
{
    exception_mask_t        masks[EXC_TYPES_COUNT];
    exception_handler_t     ports[EXC_TYPES_COUNT];
    exception_behavior_t    behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t   flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t  count;
} g_previousExceptionPorts;

/** Our exception port. */
static mach_port_t g_exceptionPort = MACH_PORT_NULL;

/** Context to fill with crash information. */
static KSCrashContext* g_crashContext;

/** Called when a crash occurs. */
void(*ksmachexc_onCrash)();


// Avoiding static methods due to linker issue.

/** Get all parts of the machine state required for a dump.
 * This includes basic thread state, and exception registers.
 *
 * @param thread The thread to get state for.
 *
 * @param machineContext The machine context to fill out.
 */
bool ksmachexc_i_fetchMachineState(const thread_t thread,
                                   _STRUCT_MCONTEXT* const machineContext);

/** Our exception handler thread routine.
 * Wait for an exception message, uninstall our exception port, record the
 * exception information, and write a report.
 */
void* ksmachexc_i_handleExceptions(void* const userData);


bool ksmachexc_i_fetchMachineState(const thread_t thread,
                                   _STRUCT_MCONTEXT* const machineContext)
{
    if(!ksmach_threadState(thread, machineContext))
    {
        return false;
    }
    
    if(!ksmach_exceptionState(thread, machineContext))
    {
        return false;
    }
    
    return true;
}

void* ksmachexc_i_handleExceptions(void* const userData)
{
    #pragma unused(userData)
    
    MachExceptionMessage exceptionMessage = {{0}};
    MachReplyMessage replyMessage = {{0}};
    
    kern_return_t kr;
    
    // Loop so we don't exit when mach_msg() fails.
    for(;;)
    {
        // Wait for a message.
        kr = mach_msg(&exceptionMessage.header,
                      MACH_RCV_MSG,
                      0,
                      sizeof(exceptionMessage),
                      g_exceptionPort,
                      MACH_MSG_TIMEOUT_NONE,
                      MACH_PORT_NULL);
        if(kr != KERN_SUCCESS)
        {
            KSLOG_ERROR("mach_msg: %s", mach_error_string(kr));
            // On failure, loop around and wait again.
            continue;
        }
        
        bool suspendSuccessful = ksmach_suspendAllThreads();
        
        kscrash_uninstallAsyncSafeHandlers();
        
        // Don't report if another handler has already.
        if(!g_crashContext->crashed)
        {
            g_crashContext->crashed = true;
            
            if(suspendSuccessful)
            {
                _STRUCT_MCONTEXT machineContext;
                if(ksmachexc_i_fetchMachineState(exceptionMessage.thread.name, &machineContext))
                {
                    if(exceptionMessage.exception == EXC_BAD_ACCESS)
                    {
                        g_crashContext->faultAddress = ksmach_faultAddress(&machineContext);
                    }
                    else
                    {
                        g_crashContext->faultAddress = ksmach_instructionAddress(&machineContext);
                    }
                }
                
                g_crashContext->crashType = KSCrashTypeMachException;
                g_crashContext->machCrashedThread = exceptionMessage.thread.name;
                g_crashContext->machExceptionType = exceptionMessage.exception;
                g_crashContext->machExceptionCode = exceptionMessage.code[0];
                g_crashContext->machExceptionSubcode = exceptionMessage.code[1];
                
                ksmachexc_onCrash();
            }
        }
        
        if(suspendSuccessful)
        {
            ksmach_resumeAllThreads();
        }
        
        // Send a reply saying "I didn't handle this exception".
        replyMessage.header = exceptionMessage.header;
        replyMessage.NDR = exceptionMessage.NDR;
        replyMessage.returnCode = KERN_FAILURE;
        
        mach_msg(&replyMessage.header,
                 MACH_SEND_MSG,
                 sizeof(replyMessage),
                 0,
                 MACH_PORT_NULL,
                 MACH_MSG_TIMEOUT_NONE,
                 MACH_PORT_NULL);
        
        // End this thread.
        pthread_exit(NULL);
    }
}


bool kscrash_installMachExceptionHandler(KSCrashContext* const context,
                                         void(*onCrash)())
{
    if(!g_installed)
    {
        // Guarding against double-calls is more important than guarding against
        // reciprocal calls.
        g_installed = 1;
        
        if(ksmach_isBeingTraced())
        {
            // Different debuggers hook into different exception types.
            // For example, GDB uses EXC_BAD_ACCESS for single stepping,
            // and LLDB uses EXC_SOFTWARE to stop a debug session.
            // All in all, it's safer to not hook into the mach exception
            // system at all while being debugged.
            g_installed = 0;
            return false;
        }
        
        g_crashContext = context;
        ksmachexc_onCrash = onCrash;
        
        const task_t thisTask = mach_task_self();
        exception_mask_t mask = EXC_MASK_BAD_ACCESS |
        EXC_MASK_BAD_INSTRUCTION |
        EXC_MASK_ARITHMETIC |
        EXC_MASK_SOFTWARE |
        EXC_MASK_BREAKPOINT;
        
        kern_return_t kr;
        
        // Save existing exception data so it can be restored later.
        kr = task_get_exception_ports(thisTask,
                                      mask,
                                      g_previousExceptionPorts.masks,
                                      &g_previousExceptionPorts.count,
                                      g_previousExceptionPorts.ports,
                                      g_previousExceptionPorts.behaviors,
                                      g_previousExceptionPorts.flavors);
        if(kr != KERN_SUCCESS)
        {
            KSLOG_ERROR("task_get_exception_ports: %s", mach_error_string(kr));
            g_installed = 0;
            return false;
        }
        
        // Allocate a new port with receive rights.
        kr = mach_port_allocate(thisTask,
                                MACH_PORT_RIGHT_RECEIVE,
                                &g_exceptionPort);
        if(kr != KERN_SUCCESS)
        {
            KSLOG_ERROR("mach_port_allocate: %s", mach_error_string(kr));
            g_installed = 0;
            return false;
        }
        
        // Add send rights.
        kr = mach_port_insert_right(thisTask,
                                    g_exceptionPort,
                                    g_exceptionPort,
                                    MACH_MSG_TYPE_MAKE_SEND);
        if(kr != KERN_SUCCESS)
        {
            KSLOG_ERROR("mach_port_insert_right: %s", mach_error_string(kr));
            mach_port_deallocate(thisTask, g_exceptionPort);
            g_installed = 0;
            return false;
        }
        
        // Install our port as an exception handler.
        kr = task_set_exception_ports(thisTask,
                                      mask,
                                      g_exceptionPort,
                                      EXCEPTION_DEFAULT,
                                      THREAD_STATE_NONE);
        if(kr != KERN_SUCCESS)
        {
            KSLOG_ERROR("task_set_exception_ports: %s", mach_error_string(kr));
            mach_port_deallocate(thisTask, g_exceptionPort);
            g_installed = 0;
            return false;
        }
        
        // Create a thread to listen for exception messages.
        // Throw away the thread handle since the thread will destroy itself.
        pthread_t exceptionThread;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        int err = pthread_create(&exceptionThread,
                                 &attr,
                                 &ksmachexc_i_handleExceptions,
                                 NULL);
        pthread_attr_destroy(&attr);
        if(err != 0)
        {
            KSLOG_ERROR("pthread_create: %s", strerror(errno));
            kscrash_uninstallMachExceptionHandler();
            return false;
        }
    }
    return true;
}


void kscrash_uninstallMachExceptionHandler(void)
{
    if(g_installed)
    {
        // Guarding against double-calls is more important than guarding against
        // reciprocal calls.
        g_installed = 0;
        
        const task_t thisTask = mach_task_self();
        kern_return_t kr;
        
        // Reinstall old exception ports.
        for(mach_msg_type_number_t i = 0; i < g_previousExceptionPorts.count; i++)
        {
            kr = task_set_exception_ports(thisTask,
                                          g_previousExceptionPorts.masks[i],
                                          g_previousExceptionPorts.ports[i],
                                          g_previousExceptionPorts.behaviors[i],
                                          g_previousExceptionPorts.flavors[i]);
            if(kr != KERN_SUCCESS)
            {
                KSLOG_ERROR("task_set_exception_ports: %s",
                            mach_error_string(kr));
            }
        }
    }
}
