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

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <mach/mach.h>


// ============================================================================
#pragma mark - (internal) -
// ============================================================================

/** Get the current VM stats.
 *
 * @param vmStats Gets filled with the VM stats.
 *
 * @param pageSize gets filled with the page size.
 *
 * @return true if the operation was successful.
 */
static bool VMStats(vm_statistics_data_t* const vmStats, vm_size_t* const pageSize)
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


// ============================================================================
#pragma mark - General Information -
// ============================================================================

uint64_t ksmach_freeMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if(VMStats(&vmStats, &pageSize))
    {
        return ((uint64_t)pageSize) * vmStats.free_count;
    }
    return 0;
}

uint64_t ksmach_usableMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if(VMStats(&vmStats, &pageSize))
    {
        return ((uint64_t)pageSize) * (vmStats.active_count +
                                       vmStats.inactive_count +
                                       vmStats.wire_count +
                                       vmStats.free_count);
    }
    return 0;
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

kern_return_t ksmach_copyMem(const void* const src, void* const dst, const int numBytes)
{
    vm_size_t bytesCopied = 0;
    return vm_read_overwrite(mach_task_self(),
                             (vm_address_t)src,
                             (vm_size_t)numBytes,
                             (vm_address_t)dst,
                             &bytesCopied);
}

int ksmach_copyMaxPossibleMem(const void* const src, void* const dst, const int numBytes)
{
    const uint8_t* pSrc = src;
    const uint8_t* pSrcMax = (uint8_t*)src + numBytes;
    const uint8_t* pSrcEnd = (uint8_t*)src + numBytes;
    uint8_t* pDst = dst;

    int bytesCopied = 0;

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
        int copyLength = (int)(pSrcEnd - pSrc);
        if(copyLength <= 0)
        {
            break;
        }

        if(ksmach_copyMem(pSrc, pDst, copyLength) == KERN_SUCCESS)
        {
            bytesCopied += copyLength;
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
