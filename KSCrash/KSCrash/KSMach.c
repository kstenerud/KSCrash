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

#include <dispatch/dispatch.h>
#include <errno.h>
#include <mach-o/arch.h>
#include <mach/mach_time.h>
#include <mach/vm_map.h>
#include <pthread.h>
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

const char* ksmach_exceptionName(const exception_type_t exceptionType)
{
    switch (exceptionType)
    {
        case EXC_BAD_ACCESS:      return "EXC_BAD_ACCESS";
        case EXC_BAD_INSTRUCTION: return "EXC_BAD_INSTRUCTION";
        case EXC_ARITHMETIC:      return "EXC_ARITHMETIC";
        case EXC_EMULATION:       return "EXC_EMULATION";
        case EXC_SOFTWARE:        return "EXC_SOFTWARE";
        case EXC_BREAKPOINT:      return "EXC_BREAKPOINT";
        case EXC_SYSCALL:         return "EXC_SYSCALL";
        case EXC_MACH_SYSCALL:    return "EXC_MACH_SYSCALL";
        case EXC_RPC_ALERT:       return "EXC_RPC_ALERT";
        case EXC_CRASH:           return "EXC_CRASH";
        default:
            break;
    }
    return NULL;
}

const char* ksmach_kernelReturnCodeName(const kern_return_t returnCode)
{
    switch (returnCode)
    {
        case KERN_SUCCESS:                return "KERN_SUCCESS";                //  0
        case KERN_INVALID_ADDRESS:        return "KERN_INVALID_ADDRESS";        //  1
        case KERN_PROTECTION_FAILURE:     return "KERN_PROTECTION_FAILURE";     //  2
        case KERN_NO_SPACE:               return "KERN_NO_SPACE";               //  3
        case KERN_INVALID_ARGUMENT:       return "KERN_INVALID_ARGUMENT";       //  4
        case KERN_FAILURE:                return "KERN_FAILURE";                //  5
        case KERN_RESOURCE_SHORTAGE:      return "KERN_RESOURCE_SHORTAGE";      //  6
        case KERN_NOT_RECEIVER:           return "KERN_NOT_RECEIVER";           //  7
        case KERN_NO_ACCESS:              return "KERN_NO_ACCESS";              //  8
        case KERN_MEMORY_FAILURE:         return "KERN_MEMORY_FAILURE";         //  9
        case KERN_MEMORY_ERROR:           return "KERN_MEMORY_ERROR";           // 10
        case KERN_ALREADY_IN_SET:         return "KERN_ALREADY_IN_SET";         // 11
        case KERN_NOT_IN_SET:             return "KERN_NOT_IN_SET";             // 12
        case KERN_NAME_EXISTS:            return "KERN_NAME_EXISTS";            // 13
        case KERN_ABORTED:                return "KERN_ABORTED";                // 14
        case KERN_INVALID_NAME:           return "KERN_INVALID_NAME";           // 15
        case KERN_INVALID_TASK:           return "KERN_INVALID_TASK";           // 16
        case KERN_INVALID_RIGHT:          return "KERN_INVALID_RIGHT";          // 17
        case KERN_INVALID_VALUE:          return "KERN_INVALID_VALUE";          // 18
        case KERN_UREFS_OVERFLOW:         return "KERN_UREFS_OVERFLOW";         // 19
        case KERN_INVALID_CAPABILITY:     return "KERN_INVALID_CAPABILITY";     // 20
        case KERN_RIGHT_EXISTS:           return "KERN_RIGHT_EXISTS";           // 21
        case KERN_INVALID_HOST:           return "KERN_INVALID_HOST";           // 22
        case KERN_MEMORY_PRESENT:         return "KERN_MEMORY_PRESENT";         // 23
        case KERN_MEMORY_DATA_MOVED:      return "KERN_MEMORY_DATA_MOVED";      // 24
        case KERN_MEMORY_RESTART_COPY:    return "KERN_MEMORY_RESTART_COPY";    // 25
        case KERN_INVALID_PROCESSOR_SET:  return "KERN_INVALID_PROCESSOR_SET";  // 26
        case KERN_POLICY_LIMIT:           return "KERN_POLICY_LIMIT";           // 27
        case KERN_INVALID_POLICY:         return "KERN_INVALID_POLICY";         // 28
        case KERN_INVALID_OBJECT:         return "KERN_INVALID_OBJECT";         // 29
        case KERN_ALREADY_WAITING:        return "KERN_ALREADY_WAITING";        // 30
        case KERN_DEFAULT_SET:            return "KERN_DEFAULT_SET";            // 31
        case KERN_EXCEPTION_PROTECTED:    return "KERN_EXCEPTION_PROTECTED";    // 32
        case KERN_INVALID_LEDGER:         return "KERN_INVALID_LEDGER";         // 33
        case KERN_INVALID_MEMORY_CONTROL: return "KERN_INVALID_MEMORY_CONTROL"; // 34
        case KERN_INVALID_SECURITY:       return "KERN_INVALID_SECURITY";       // 35
        case KERN_NOT_DEPRESSED:          return "KERN_NOT_DEPRESSED";          // 36
        case KERN_TERMINATED:             return "KERN_TERMINATED";             // 37
        case KERN_LOCK_SET_DESTROYED:     return "KERN_LOCK_SET_DESTROYED";     // 38
        case KERN_LOCK_UNSTABLE:          return "KERN_LOCK_UNSTABLE";          // 39
        case KERN_LOCK_OWNED:             return "KERN_LOCK_OWNED";             // 40
        case KERN_LOCK_OWNED_SELF:        return "KERN_LOCK_OWNED_SELF";        // 41
        case KERN_SEMAPHORE_DESTROYED:    return "KERN_SEMAPHORE_DESTROYED";    // 42
        case KERN_RPC_SERVER_TERMINATED:  return "KERN_RPC_SERVER_TERMINATED";  // 43
        case KERN_RPC_TERMINATE_ORPHAN:   return "KERN_RPC_TERMINATE_ORPHAN";   // 44
        case KERN_RPC_CONTINUE_ORPHAN:    return "KERN_RPC_CONTINUE_ORPHAN";    // 45
        case KERN_NOT_SUPPORTED:          return "KERN_NOT_SUPPORTED";          // 46
        case KERN_NODE_DOWN:              return "KERN_NODE_DOWN";              // 47
        case KERN_NOT_WAITING:            return "KERN_NOT_WAITING";            // 48
        case KERN_OPERATION_TIMED_OUT:    return "KERN_OPERATION_TIMED_OUT";    // 49
        case KERN_CODESIGN_ERROR:         return "KERN_CODESIGN_ERROR";         // 50
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


// From Libc-763.11/pthreads/pthread_internals.h
#define kEXTERNAL_POSIX_THREAD_KEYS_MAX 512
#define kINTERNAL_POSIX_THREAD_KEYS_MAX 256

#define kTSD_KEY_COUNT (kEXTERNAL_POSIX_THREAD_KEYS_MAX + \
                        kINTERNAL_POSIX_THREAD_KEYS_MAX)

// From Libc-763.11/pthreads/pthread_internals.h
typedef struct internal_pthread
{
    long        sig;           /* Unique signature for this structure */
    struct __darwin_pthread_handler_rec* __cleanup_stack;
    int lock;                  /* Used for internal mutex on structure (actually pthread_lock_t) */
    uint32_t    detached:8,
                inherit:8,
                policy:8,
                freeStackOnExit:1,
                newstyle:1,
                kernalloc:1,
                schedset:1,
                wqthread:1,
                wqkillset:1,
                pad:2;
    size_t      guardsize;     /* size in bytes to guard stack overflow */
#if  !defined(__LP64__)
    int         pad0;          /* for backwards compatibility */
#endif
    struct sched_param param;
    uint32_t    cancel_error;
#if defined(__LP64__)
    uint32_t    cancel_pad;    /* pad value for alignment */
#endif
    struct _pthread* joiner;
#if !defined(__LP64__)
    int         pad1;          /* for backwards compatibility */
#endif
    void*       exit_value;
    semaphore_t death;         /* pthread_join() uses this to wait for death's call */
    mach_port_t kernel_thread; /* kernel thread this thread is bound to */
    void*       (*fun)(void*); /* Thread start routine */
    void*       arg;           /* Argment for thread start routine */
    int         cancel_state;  /* Whether thread can be cancelled */
    int         err_no;        /* thread-local errno */
    void*       tsd[kTSD_KEY_COUNT]; /* Thread specific data */
    // Don't care about the rest.
}* internal_pthread_t;


// From libdispatch-187.5/src/queue_internal.h
#define kDISPATCH_QUEUE_MIN_LABEL_SIZE 64

// From libdispatch-187.5/src/queue_internal.h
typedef struct internal_dispatch_queue_s
{
    const struct dispatch_queue_vtable_s* do_vtable;
    struct internal_dispatch_queue_s* volatile do_next;
    int do_ref_cnt;     // Was unsigned int in queue_internal.h
    int do_xref_cnt;    // Was unsigned int in queue_internal.h
    int do_suspend_cnt; // Was unsigned int in queue_internal.h
    struct internal_dispatch_queue_s* do_targetq;
    void* do_ctxt;
    void* do_finalizer;

    uint32_t volatile dq_running;
    uint32_t dq_width;
    struct internal_dispatch_queue_s* volatile dq_items_tail;
    struct internal_dispatch_queue_s* volatile dq_items_head;
    unsigned long dq_serialnum;
    dispatch_queue_t dq_specific_q;

    char dq_label[kDISPATCH_QUEUE_MIN_LABEL_SIZE]; // must be last
    // Don't care about the rest.
}* internal_dispatch_queue_t;


bool ksmach_getThreadQueueName(const thread_t thread,
                               char* const buffer,
                               size_t bufLength)
{
    // "Bad mojo" barely begins to describe what I'm about to do here.
    //
    // We want the dispatch queue name for a thread, but we can't get at
    // it for an arbitraty thread via any public API, so this calls for a
    // little creative hacking.
    //
    // Dispatch queues have a label associated with them, but you can only get
    // the dispatch queue associated with the CURRENT thread, not an arbitrary
    // thread. This is because internally, the queue is stored as
    // thread-specific data, and the pthreads public API can only access
    // thread-specific data for the current thread. Besides this, the TSD key
    // for each queue is only known to the dispatch queue subsystem.
    //
    // The only way around this is to recast thread_t as a pointer to a
    // non-opaque structure, step through what we think is its TSD array,
    // reinterpret THOSE pointers (which could be anything really) as non-opaque
    // queue structures, determine if they really are queues and not some other
    // data structure or invalid address or random bytes, and finally copy what
    // we think are their labels. AND we must do all of this without crashing.
    //
    // Yeah, that's right. Shit just got real.
    //
    // Fortunately, there's vm_read_overwrite() to lend a helping hand.
    //
    // The basic process is:
    //
    // 1. Reinterpret thread_t as internal_pthread_t.
    // 2. Copy the thread-specific data pointers.
    // 3. For each pointer, try to interpret as internal_dispatch_queue_t and
    //    copy its contents.
    // 4. Do some sanity checks to make sure it really is a dispatch queue
    //    we're looking at.
    // 5. Copy the queue label.
    //
    // Ready? Let's fumble our way through some random memory!


    // Space to copy what we hope is thread-specific data.
    void* tsd;

    // Space to copy data from what we hope is a queue.
    struct internal_dispatch_queue_s queue;
    if(bufLength > sizeof(queue.dq_label))
    {
        bufLength = sizeof(queue.dq_label);
    }

    // Recast the opaque thread to our hacky internal thread structure pointer.
    const pthread_t pthread = pthread_from_mach_thread_np(thread);
    const internal_pthread_t const threadStruct = (internal_pthread_t)pthread;

    // Step through thread specific data.
    for(int iTSD = 0; iTSD < kTSD_KEY_COUNT; iTSD++)
    {
        // Copy what might be a valid pointer from the thread-specific data.
        if(ksmach_copyMem(&threadStruct->tsd[iTSD], &tsd, sizeof(tsd)) != KERN_SUCCESS)
        {
            continue;
        }
        if(tsd == NULL)
        {
            continue;
        }

        // Follow the potential pointer to copy what might be a queue structure.
        if(ksmach_copyMem(tsd, &queue, sizeof(queue)) != KERN_SUCCESS)
        {
            continue;
        }

        // First sanity check: The queue label must be a null terminated string.
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
            continue;
        }

        // Second sanity check: Label length < 5 is probably invalid.
        if(iLabel < 5)
        {
            continue;
        }

        // Third sanity check: Check reference counts, etc.
        if(queue.do_ref_cnt < -1 || queue.do_ref_cnt > 100000 ||
           queue.do_xref_cnt < -1 || queue.do_xref_cnt > 100000 ||
           queue.do_suspend_cnt < -1 || queue.do_suspend_cnt > 100000 ||
           queue.dq_running > 2)
        {
            continue;
        }

        // If all checks passed, we probably have a valid queue label.
        strncpy(buffer, queue.dq_label, bufLength);
        return true;
    }

    return false;
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
    const uint8_t* pSrcMax = src + numBytes;
    const uint8_t* pSrcEnd = src + numBytes;
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
