//
//  KSMemory.c
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


#include "KSMemory.h"

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

uint64_t ksmem_freeMemory(void)
{
    vm_statistics_data_t vmStats;
    vm_size_t pageSize;
    if(VMStats(&vmStats, &pageSize))
    {
        return ((uint64_t)pageSize) * vmStats.free_count;
    }
    return 0;
}

uint64_t ksmem_usableMemory(void)
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

bool ksmem_copySafely(const void* const src, void* const dst, const int numBytes)
{
    vm_size_t bytesCopied = 0;
    return vm_read_overwrite(mach_task_self(),
                             (vm_address_t)src,
                             (vm_size_t)numBytes,
                             (vm_address_t)dst,
                             &bytesCopied) == KERN_SUCCESS;
}

int ksmem_copyMaxPossible(const void* const src, void* const dst, const int numBytes)
{
    const uint8_t* pSrc = src;
    const uint8_t* pSrcMax = (uint8_t*)src + numBytes;
    const uint8_t* pSrcEnd = (uint8_t*)src + numBytes;
    uint8_t* pDst = dst;

    int bytesCopied = 0;

    // Short-circuit if no memory is readable
    if(!ksmem_copySafely(src, dst, 1))
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

        if(ksmem_copySafely(pSrc, pDst, copyLength))
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
