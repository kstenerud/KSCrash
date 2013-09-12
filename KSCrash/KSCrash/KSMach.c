//
//  KSMach.c
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


#include "KSMach.h"

#include "KSMachApple.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <errno.h>
#include <mach-o/arch.h>
#include <mach/mach_time.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>


// Avoiding static functions due to linker issues.

/** Get the current VM stats.
 *
 * @param vmStats Gets filled with the VM stats.
 *
 * @param pageSize gets filled with the page size.
 *
 * @return true if the operation was successful.
 */
bool ksmach_i_VMStats(vm_statistics_data_t* const vmStats,
                      vm_size_t* const pageSize);

static pthread_t g_topThread;

// ============================================================================
#pragma mark - General Information -
// ============================================================================

uint64_t ksmach_freeMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if(ksmach_i_VMStats(&vmStats, &pageSize))
    {
        return ((uint64_t)pageSize) * vmStats.free_count;
    }
    return 0;
}

uint64_t ksmach_usableMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if(ksmach_i_VMStats(&vmStats, &pageSize))
    {
        return ((uint64_t)pageSize) * (vmStats.active_count +
                                       vmStats.inactive_count +
                                       vmStats.wire_count +
                                       vmStats.free_count);
    }
    return 0;
}

const char* ksmach_currentCPUArch(void)
{
    const NXArchInfo* archInfo = NXGetLocalArchInfo();
    return archInfo == NULL ? NULL : archInfo->name;
}

#define RETURN_NAME_FOR_ENUM(A) case A: return #A

const char* ksmach_exceptionName(const exception_type_t exceptionType)
{
    switch (exceptionType)
    {
            RETURN_NAME_FOR_ENUM(EXC_BAD_ACCESS);
            RETURN_NAME_FOR_ENUM(EXC_BAD_INSTRUCTION);
            RETURN_NAME_FOR_ENUM(EXC_ARITHMETIC);
            RETURN_NAME_FOR_ENUM(EXC_EMULATION);
            RETURN_NAME_FOR_ENUM(EXC_SOFTWARE);
            RETURN_NAME_FOR_ENUM(EXC_BREAKPOINT);
            RETURN_NAME_FOR_ENUM(EXC_SYSCALL);
            RETURN_NAME_FOR_ENUM(EXC_MACH_SYSCALL);
            RETURN_NAME_FOR_ENUM(EXC_RPC_ALERT);
            RETURN_NAME_FOR_ENUM(EXC_CRASH);
    }
    return NULL;
}

const char* ksmach_kernelReturnCodeName(const kern_return_t returnCode)
{
    switch (returnCode)
    {
            RETURN_NAME_FOR_ENUM(KERN_SUCCESS);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_ADDRESS);
            RETURN_NAME_FOR_ENUM(KERN_PROTECTION_FAILURE);
            RETURN_NAME_FOR_ENUM(KERN_NO_SPACE);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_ARGUMENT);
            RETURN_NAME_FOR_ENUM(KERN_FAILURE);
            RETURN_NAME_FOR_ENUM(KERN_RESOURCE_SHORTAGE);
            RETURN_NAME_FOR_ENUM(KERN_NOT_RECEIVER);
            RETURN_NAME_FOR_ENUM(KERN_NO_ACCESS);
            RETURN_NAME_FOR_ENUM(KERN_MEMORY_FAILURE);
            RETURN_NAME_FOR_ENUM(KERN_MEMORY_ERROR);
            RETURN_NAME_FOR_ENUM(KERN_ALREADY_IN_SET);
            RETURN_NAME_FOR_ENUM(KERN_NOT_IN_SET);
            RETURN_NAME_FOR_ENUM(KERN_NAME_EXISTS);
            RETURN_NAME_FOR_ENUM(KERN_ABORTED);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_NAME);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_TASK);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_RIGHT);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_VALUE);
            RETURN_NAME_FOR_ENUM(KERN_UREFS_OVERFLOW);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_CAPABILITY);
            RETURN_NAME_FOR_ENUM(KERN_RIGHT_EXISTS);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_HOST);
            RETURN_NAME_FOR_ENUM(KERN_MEMORY_PRESENT);
            RETURN_NAME_FOR_ENUM(KERN_MEMORY_DATA_MOVED);
            RETURN_NAME_FOR_ENUM(KERN_MEMORY_RESTART_COPY);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_PROCESSOR_SET);
            RETURN_NAME_FOR_ENUM(KERN_POLICY_LIMIT);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_POLICY);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_OBJECT);
            RETURN_NAME_FOR_ENUM(KERN_ALREADY_WAITING);
            RETURN_NAME_FOR_ENUM(KERN_DEFAULT_SET);
            RETURN_NAME_FOR_ENUM(KERN_EXCEPTION_PROTECTED);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_LEDGER);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_MEMORY_CONTROL);
            RETURN_NAME_FOR_ENUM(KERN_INVALID_SECURITY);
            RETURN_NAME_FOR_ENUM(KERN_NOT_DEPRESSED);
            RETURN_NAME_FOR_ENUM(KERN_TERMINATED);
            RETURN_NAME_FOR_ENUM(KERN_LOCK_SET_DESTROYED);
            RETURN_NAME_FOR_ENUM(KERN_LOCK_UNSTABLE);
            RETURN_NAME_FOR_ENUM(KERN_LOCK_OWNED);
            RETURN_NAME_FOR_ENUM(KERN_LOCK_OWNED_SELF);
            RETURN_NAME_FOR_ENUM(KERN_SEMAPHORE_DESTROYED);
            RETURN_NAME_FOR_ENUM(KERN_RPC_SERVER_TERMINATED);
            RETURN_NAME_FOR_ENUM(KERN_RPC_TERMINATE_ORPHAN);
            RETURN_NAME_FOR_ENUM(KERN_RPC_CONTINUE_ORPHAN);
            RETURN_NAME_FOR_ENUM(KERN_NOT_SUPPORTED);
            RETURN_NAME_FOR_ENUM(KERN_NODE_DOWN);
            RETURN_NAME_FOR_ENUM(KERN_NOT_WAITING);
            RETURN_NAME_FOR_ENUM(KERN_OPERATION_TIMED_OUT);
            RETURN_NAME_FOR_ENUM(KERN_CODESIGN_ERROR);
    }
    return NULL;
}


// ============================================================================
#pragma mark - Thread State Info -
// ============================================================================

bool ksmach_fillState(const thread_t thread,
                      const thread_state_t state,
                      const thread_state_flavor_t flavor,
                      const mach_msg_type_number_t stateCount)
{
    mach_msg_type_number_t stateCountBuff = stateCount;
    kern_return_t kr;

    kr = thread_get_state(thread, flavor, state, &stateCountBuff);
    if(kr != KERN_SUCCESS)
    {
        KSLOG_ERROR("thread_get_state: %s", mach_error_string(kr));
        return false;
    }
    return true;
}

void ksmach_init(void)
{
    static volatile sig_atomic_t initialized = 0;
    if(!initialized)
    {
        kern_return_t kr;
        const task_t thisTask = mach_task_self();
        thread_act_array_t threads;
        mach_msg_type_number_t numThreads;

        if((kr = task_threads(thisTask, &threads, &numThreads)) != KERN_SUCCESS)
        {
            KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
            return;
        }

        g_topThread = pthread_from_mach_thread_np(threads[0]);

        for(mach_msg_type_number_t i = 0; i < numThreads; i++)
        {
            mach_port_deallocate(thisTask, threads[i]);
        }
        vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);
        initialized = true;
    }
}

thread_t ksmach_machThreadFromPThread(const pthread_t pthread)
{
    const internal_pthread_t threadStruct = (internal_pthread_t)pthread;
    thread_t machThread = 0;
    if(ksmach_copyMem(&threadStruct->kernel_thread, &machThread, sizeof(machThread)) != KERN_SUCCESS)
    {
        KSLOG_TRACE("Could not copy mach thread from %p", threadStruct->kernel_thread);
        return 0;
    }
    return machThread;
}

pthread_t ksmach_pthreadFromMachThread(const thread_t thread)
{
    internal_pthread_t threadStruct = (internal_pthread_t)g_topThread;
    thread_t machThread = 0;

    for(int i = 0; i < 50; i++)
    {
        if(ksmach_copyMem(&threadStruct->kernel_thread, &machThread, sizeof(machThread)) != KERN_SUCCESS)
        {
            break;
        }
        if(machThread == thread)
        {
            return (pthread_t)threadStruct;
        }

        if(ksmach_copyMem(&threadStruct->plist.tqe_next, &threadStruct, sizeof(threadStruct)) != KERN_SUCCESS)
        {
            break;
        }
    }
    return 0;
}

bool ksmach_getThreadName(const thread_t thread,
                          char* const buffer,
                          size_t bufLength)
{
    const pthread_t pthread = ksmach_pthreadFromMachThread(thread);
    const internal_pthread_t threadStruct = (internal_pthread_t)pthread;
    size_t copyLength = bufLength > MAXTHREADNAMESIZE ? MAXTHREADNAMESIZE : bufLength;

    if(ksmach_copyMem(threadStruct->pthread_name, buffer, copyLength) != KERN_SUCCESS)
    {
        KSLOG_TRACE("Could not copy thread name from %p", threadStruct->pthread_name);
        return false;
    }
    buffer[copyLength-1] = 0;
    return true;
}

bool ksmach_getThreadQueueName(const thread_t thread,
                               char* const buffer,
                               size_t bufLength)
{
    struct internal_dispatch_queue_s* pQueue;
    struct internal_dispatch_queue_s queue;

    if(bufLength > sizeof(queue.dq_label))
    {
        bufLength = sizeof(queue.dq_label);
    }

    // Recast the opaque thread to our hacky internal thread structure pointer.
    const pthread_t pthread = ksmach_pthreadFromMachThread(thread);
    const internal_pthread_t threadStruct = (internal_pthread_t)pthread;

    if(ksmach_copyMem(&threadStruct->tsd[dispatch_queue_key], &pQueue, sizeof(pQueue)) != KERN_SUCCESS)
    {
        KSLOG_TRACE("Could not copy queue pointer from %p", &threadStruct->tsd[dispatch_queue_key]);
        return false;
    }

    if(pQueue == NULL)
    {
        KSLOG_TRACE("Queue pointer is NULL");
        return false;
    }

    if(ksmach_copyMem(pQueue, &queue, sizeof(queue)) != KERN_SUCCESS)
    {
        KSLOG_TRACE("Could not copy queue data from %p", pQueue);
        return false;
    }

    // Queue label must be a null terminated string.
    int iLabel;
    for(iLabel = 0; iLabel < (int)sizeof(queue.dq_label); iLabel++)
    {
        if(queue.dq_label[iLabel] < ' ' || queue.dq_label[iLabel] > '~')
        {
            break;
        }
    }
    if(queue.dq_label[iLabel] != 0)
    {
        // Found a non-null, invalid char.
        KSLOG_TRACE("Queue label contains invalid chars");
        return false;
    }

    strncpy(buffer, queue.dq_label, bufLength);
    KSLOG_TRACE("Queue label = %s", buffer);
    return true;
}


// ============================================================================
#pragma mark - Binary Image Info -
// ============================================================================

uint32_t ksmach_imageNamed(const char* const imageName, bool exactMatch)
{
    const uint32_t imageCount = _dyld_image_count();

    for(uint32_t iImg = 0; iImg < imageCount; iImg++)
    {
        const char* name = _dyld_get_image_name(iImg);
        if(exactMatch)
        {
            if(strcmp(name, imageName) == 0)
            {
                return iImg;
            }
        }
        else
        {
            if(strstr(name, imageName) != NULL)
            {
                return iImg;
            }
        }
    }
    return UINT32_MAX;
}

const uint8_t* ksmach_imageUUID(const char* const imageName, bool exactMatch)
{
    const uint32_t iImg = ksmach_imageNamed(imageName, exactMatch);
    if(iImg != UINT32_MAX)
    {
        const struct mach_header* header = _dyld_get_image_header(iImg);
        if(header != NULL)
        {
            uintptr_t cmdPtr = ksmach_firstCmdAfterHeader(header);
            if(cmdPtr != 0)
            {
                for(uint32_t iCmd = 0;iCmd < header->ncmds; iCmd++)
                {
                    const struct load_command* loadCmd = (struct load_command*)cmdPtr;
                    if(loadCmd->cmd == LC_UUID)
                    {
                        struct uuid_command* uuidCmd = (struct uuid_command*)cmdPtr;
                        return uuidCmd->uuid;
                    }
                    cmdPtr += loadCmd->cmdsize;
                }
            }
        }
    }
    return NULL;
}

uintptr_t ksmach_firstCmdAfterHeader(const struct mach_header* const header)
{
    switch(header->magic)
    {
        case MH_MAGIC:
        case MH_CIGAM:
            return (uintptr_t)(header + 1);
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((struct mach_header_64*)header) + 1);
        default:
            // Header is corrupt
            return 0;
    }
}


// ============================================================================
#pragma mark - Utility -
// ============================================================================

static inline bool isThreadInList(thread_t thread, thread_t* list, int listCount)
{
    for(int i = 0; i < listCount; i++)
    {
        if(list[i] == thread)
        {
            return true;
        }
    }
    return false;
}

bool ksmach_suspendAllThreads(void)
{
    return ksmach_suspendAllThreadsExcept(NULL, 0);
}

bool ksmach_suspendAllThreadsExcept(thread_t* exceptThreads, int exceptThreadsCount)
{
    kern_return_t kr;
    const task_t thisTask = mach_task_self();
    const thread_t thisThread = mach_thread_self();
    thread_act_array_t threads;
    mach_msg_type_number_t numThreads;

    if((kr = task_threads(thisTask, &threads, &numThreads)) != KERN_SUCCESS)
    {
        KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
        return false;
    }

    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        thread_t thread = threads[i];
        if(thread != thisThread && !isThreadInList(thread, exceptThreads, exceptThreadsCount))
        {
            if((kr = thread_suspend(thread)) != KERN_SUCCESS)
            {
                KSLOG_ERROR("thread_suspend (%08x): %s",
                            thread, mach_error_string(kr));
                // Don't treat this as a fatal error.
            }
        }
    }

    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);

    return true;
}

bool ksmach_resumeAllThreads(void)
{
    return ksmach_resumeAllThreadsExcept(NULL, 0);
}

bool ksmach_resumeAllThreadsExcept(thread_t* exceptThreads, int exceptThreadsCount)
{
    kern_return_t kr;
    const task_t thisTask = mach_task_self();
    const thread_t thisThread = mach_thread_self();
    thread_act_array_t threads;
    mach_msg_type_number_t numThreads;

    if((kr = task_threads(thisTask, &threads, &numThreads)) != KERN_SUCCESS)
    {
        KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
        return false;
    }

    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        thread_t thread = threads[i];
        if(thread != thisThread && !isThreadInList(thread, exceptThreads, exceptThreadsCount))
        {
            if((kr = thread_resume(thread)) != KERN_SUCCESS)
            {
                KSLOG_ERROR("thread_resume (%08x): %s",
                            thread, mach_error_string(kr));
                // Don't treat this as a fatal error.
            }
        }
    }

    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
    {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);

    return true;
}

kern_return_t ksmach_copyMem(const void* const src,
                             void* const dst,
                             const size_t numBytes)
{
    vm_size_t bytesCopied = 0;
    return vm_read_overwrite(mach_task_self(),
                             (vm_address_t)src,
                             (vm_size_t)numBytes,
                             (vm_address_t)dst,
                             &bytesCopied);
}

size_t ksmach_copyMaxPossibleMem(const void* const src,
                                 void* const dst,
                                 const size_t numBytes)
{
    const uint8_t* pSrc = src;
    const uint8_t* pSrcMax = (uint8_t*)src + numBytes;
    const uint8_t* pSrcEnd = (uint8_t*)src + numBytes;
    uint8_t* pDst = dst;

    size_t bytesCopied = 0;

    // Short-circuit if no memory is readable
    if(ksmach_copyMem(src, dst, 1) != KERN_SUCCESS)
    {
        return 0;
    }
    else if(numBytes <= 1)
    {
        return numBytes;
    }

    for(;;)
    {
        ssize_t copyLength = pSrcEnd - pSrc;
        if(copyLength <= 0)
        {
            break;
        }

        if(ksmach_copyMem(pSrc, pDst, (size_t)copyLength) == KERN_SUCCESS)
        {
            bytesCopied += (size_t)copyLength;
            pSrc += copyLength;
            pDst += copyLength;
            pSrcEnd = pSrc + (pSrcMax - pSrc) / 2;
        }
        else
        {
            if(copyLength <= 1)
            {
                break;
            }
            pSrcMax = pSrcEnd;
            pSrcEnd = pSrc + copyLength / 2;
        }
    }
    return bytesCopied;
}

double ksmach_timeDifferenceInSeconds(const uint64_t endTime,
                                      const uint64_t startTime)
{
    // From http://lists.apple.com/archives/perfoptimization-dev/2005/Jan/msg00039.html

    static double conversion = 0;

    if(conversion == 0)
    {
        mach_timebase_info_data_t info = {0};
        kern_return_t kr = mach_timebase_info(&info);
        if(kr != KERN_SUCCESS)
        {
            KSLOG_ERROR("mach_timebase_info: %s", mach_error_string(kr));
            return 0;
        }

        conversion = 1e-9 * (double)info.numer / (double)info.denom;
    }

    return conversion * (endTime - startTime);
}

/** Check if the current process is being traced or not.
 *
 * @return true if we're being traced.
 */
bool ksmach_isBeingTraced(void)
{
    struct kinfo_proc procInfo;
    size_t structSize = sizeof(procInfo);
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};

    if(sysctl(mib, sizeof(mib)/sizeof(*mib), &procInfo, &structSize, NULL, 0) != 0)
    {
        KSLOG_ERROR("sysctl: %s", strerror(errno));
        return false;
    }

    return (procInfo.kp_proc.p_flag & P_TRACED) != 0;
}


// ============================================================================
#pragma mark - (internal) -
// ============================================================================

bool ksmach_i_VMStats(vm_statistics_data_t* const vmStats,
                      vm_size_t* const pageSize)
{
    kern_return_t kr;
    const mach_port_t hostPort = mach_host_self();

    if((kr = host_page_size(hostPort, pageSize)) != KERN_SUCCESS)
    {
        KSLOG_ERROR("host_page_size: %s", mach_error_string(kr));
        return false;
    }

    mach_msg_type_number_t hostSize = sizeof(*vmStats) / sizeof(natural_t);
    kr = host_statistics(hostPort,
                         HOST_VM_INFO,
                         (host_info_t)vmStats,
                         &hostSize);
    if(kr != KERN_SUCCESS)
    {
        KSLOG_ERROR("host_statistics: %s", mach_error_string(kr));
        return false;
    }
    
    return true;
}
