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

static inline int copySafely(const void* restrict const src, void* restrict const dst, const int byteCount)
{
    vm_size_t bytesCopied = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(),
                                             (vm_address_t)src,
                                             (vm_size_t)byteCount,
                                             (vm_address_t)dst,
                                             &bytesCopied);
    if(result != KERN_SUCCESS)
    {
        return 0;
    }
    return (int)bytesCopied;
}

static inline int copyMaxPossible(const void* restrict const src, void* restrict const dst, const int byteCount)
{
    const uint8_t* pSrc = src;
    const uint8_t* pSrcMax = (uint8_t*)src + byteCount;
    const uint8_t* pSrcEnd = (uint8_t*)src + byteCount;
    uint8_t* pDst = dst;
    
    int bytesCopied = 0;
    
    // Short-circuit if no memory is readable
    if(copySafely(src, dst, 1) != 1)
    {
        return 0;
    }
    else if(byteCount <= 1)
    {
        return byteCount;
    }
    
    for(;;)
    {
        int copyLength = (int)(pSrcEnd - pSrc);
        if(copyLength <= 0)
        {
            break;
        }
        
        if(copySafely(pSrc, pDst, copyLength) == copyLength)
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

static char g_memoryTestBuffer[10240];
static inline bool isMemoryReadable(const void* const memory, const int byteCount)
{
    const int testBufferSize = sizeof(g_memoryTestBuffer);
    int bytesRemaining = byteCount;
    
    while(bytesRemaining > 0)
    {
        int bytesToCopy = bytesRemaining > testBufferSize ? testBufferSize : bytesRemaining;
        if(copySafely(memory, g_memoryTestBuffer, bytesToCopy) != bytesToCopy)
        {
            break;
        }
        bytesRemaining -= bytesToCopy;
    }
    return bytesRemaining == 0;
}

int ksmem_maxReadableBytes(const void* const memory, const int tryByteCount)
{
    const int testBufferSize = sizeof(g_memoryTestBuffer);
    const uint8_t* currentPosition = memory;
    int bytesRemaining = tryByteCount;

    while(bytesRemaining > testBufferSize)
    {
        if(!isMemoryReadable(currentPosition, testBufferSize))
        {
            break;
        }
        currentPosition += testBufferSize;
        bytesRemaining -= testBufferSize;
    }
    bytesRemaining -= copyMaxPossible(currentPosition, g_memoryTestBuffer, testBufferSize);
    return tryByteCount - bytesRemaining;
}

bool ksmem_isMemoryReadable(const void* const memory, const int byteCount)
{
    return isMemoryReadable(memory, byteCount);
}

int ksmem_copyMaxPossible(const void* restrict const src, void* restrict const dst, const int byteCount)
{
    return copyMaxPossible(src, dst, byteCount);
}

bool ksmem_copySafely(const void* restrict const src, void* restrict const dst, const int byteCount)
{
    return copySafely(src, dst, byteCount);
}
