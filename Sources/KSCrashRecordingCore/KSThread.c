//
//  KSThread.c
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

#include "KSThread.h"

#include "KSMemory.h"
#include "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#include <assert.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <mach/thread_info.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/sysctl.h>

#include "KSLogger.h"

static const char *thread_state_names[] = {
    // Defined in mach/thread_info.h
    NULL, "TH_STATE_RUNNING", "TH_STATE_STOPPED", "TH_STATE_WAITING", "TH_STATE_UNINTERRUPTIBLE", "TH_STATE_HALTED",
};

static const int thread_state_names_count = sizeof(thread_state_names) / sizeof(*thread_state_names);

const char *ksthread_state_name(int state)
{
    if (state < 1 || state >= thread_state_names_count) {
        return NULL;
    }
    return thread_state_names[state];
}

KSThread ksthread_self(void)
{
    thread_t thread_self = mach_thread_self();
    mach_port_deallocate(mach_task_self(), thread_self);
    return (KSThread)thread_self;
}

static _Atomic KSThread g_mainThread;

void ksthread_storeMainThreadValue(KSThread thread)
{
    atomic_store_explicit(&g_mainThread, thread, memory_order_release);
}

KSThread ksthread_main(void) { return atomic_load_explicit(&g_mainThread, memory_order_acquire); }

bool ksthread_getThreadName(const KSThread thread, char *const buffer, int bufLength)
{
    // WARNING: This implementation is no longer async-safe!

    const pthread_t pthread = pthread_from_mach_thread_np((thread_t)thread);
    return pthread_getname_np(pthread, buffer, (unsigned)bufLength) == 0;
}

bool ksthread_getThreadNameFromKernel(const KSThread thread, char *const buffer, int bufLength)
{
    if (bufLength < 1) {
        return false;
    }
    thread_extended_info_data_t info = { 0 };
    mach_msg_type_number_t count = THREAD_EXTENDED_INFO_COUNT;
    if (thread_info((thread_t)thread, THREAD_EXTENDED_INFO, (thread_info_t)&info, &count) != KERN_SUCCESS) {
        return false;
    }
    // pth_name is not guaranteed terminated at its full width; bound the copy and
    // terminate ourselves instead of trusting a terminator to be there.
    int copyLength = bufLength - 1;
    if (copyLength > (int)sizeof(info.pth_name)) {
        copyLength = (int)sizeof(info.pth_name);
    }
    memcpy(buffer, info.pth_name, (size_t)copyLength);
    buffer[copyLength] = 0;
    return buffer[0] != 0;
}

int ksthread_getThreadState(const KSThread thread)
{
    integer_t infoBuffer[THREAD_BASIC_INFO_COUNT] = { 0 };
    thread_basic_info_t info = (thread_basic_info_t)infoBuffer;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    kern_return_t kr = 0;

    kr = thread_info((thread_t)thread, THREAD_BASIC_INFO, (thread_info_t)info, &count);
    if (kr != KERN_SUCCESS) {
        KSLOG_TRACE(
            "Error getting thread_info with flavor "
            "THREAD_BASIC_INFO from mach thread : %s",
            mach_error_string(kr));
        return TH_STATE_UNSET;
    }

    if (!ksmem_isMemoryReadable(info, sizeof(*info))) {
        KSLOG_DEBUG("Thread %p has an invalid thread basic info %p", thread, info);
        return TH_STATE_UNSET;
    }

    return info->run_state;
}

// A queue's label is read straight out of the queue object rather than through
// dispatch_queue_get_label, which checks nothing but NULL before loading the label pointer from a
// fixed offset. The pointer handed to it comes from a slot inside a thread that can exit mid-read,
// so it can be a queue that has been released, or bytes that are no longer a queue at all, and
// libdispatch would fault on them where nothing can catch it. That offset is private, so it is
// derived from queues whose label this process already knows: a layout the derivation cannot make
// sense of turns queue names off rather than reading whatever now sits at a remembered offset.

// libdispatch asserts that both kinds probed below fit in 128 bytes, so the search stays inside
// the probe rather than matching bytes that follow it.
#define QUEUE_PROBE_SIZE 128
#define QUEUE_LABEL_OFFSET_UNDERIVED (-1)
#define QUEUE_LABEL_OFFSET_UNAVAILABLE (-2)

static _Atomic int g_queueLabelOffset = QUEUE_LABEL_OFFSET_UNDERIVED;

static const char *queueLabelAt(const void *const queue, const int offset)
{
    const char *label = NULL;
    if (!ksmem_copySafely((const uint8_t *)queue + offset, &label, (int)sizeof(label))) {
        return NULL;
    }
    return label;
}

/** Get the offset at which a dispatch queue holds the pointer to its label.
 *
 * @return The offset in bytes, or a negative value if it could not be established.
 */
static int queueLabelOffset(void)
{
    // Racing callers derive the same offset from the same two queues, so the only cost of a race
    // is a repeated search.
    int offset = atomic_load(&g_queueLabelOffset);
    if (offset != QUEUE_LABEL_OFFSET_UNDERIVED) {
        return offset;
    }

    // Two queues of different kinds, because an offset holding the label in both is the label
    // rather than one kind's coincidence: the main queue is a static object and a global queue is
    // a root queue, and both live as long as the process. An unlabelled probe would read back
    // libdispatch's own empty string, which is stored nowhere in the object, so it finds nothing
    // rather than agreeing on the wrong place.
    dispatch_queue_t mainQueue = (dispatch_queue_t)dispatch_get_main_queue();
    dispatch_queue_t globalQueue = (dispatch_queue_t)dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    const char *const mainLabel = dispatch_queue_get_label(mainQueue);
    const char *const globalLabel = dispatch_queue_get_label(globalQueue);

    // The first agreement, not the only one: a second would mean a field mirrors the label in both
    // probes, and mirrors either hold for every queue or produce bytes the label check rejects.
    offset = QUEUE_LABEL_OFFSET_UNAVAILABLE;
    for (int candidate = 0; candidate + (int)sizeof(mainLabel) <= QUEUE_PROBE_SIZE;
         candidate += (int)sizeof(mainLabel)) {
        if (queueLabelAt(mainQueue, candidate) == mainLabel && queueLabelAt(globalQueue, candidate) == globalLabel) {
            offset = candidate;
            break;
        }
    }
    if (offset == QUEUE_LABEL_OFFSET_UNAVAILABLE) {
        KSLOG_WARN("Could not find where a dispatch queue keeps its label. Queue names are off.");
    }

    atomic_store(&g_queueLabelOffset, offset);
    return offset;
}

bool ksthread_getQueueName(const KSThread thread, char *const buffer, int bufLength)
{
    // WARNING: This implementation is no longer async-safe!

    // The copy below casts bufLength to size_t, so a non-positive length would turn into an
    // enormous one.
    if (bufLength < 1) {
        return false;
    }

    integer_t infoBuffer[THREAD_IDENTIFIER_INFO_COUNT] = { 0 };
    thread_info_t info = infoBuffer;
    mach_msg_type_number_t inOutSize = THREAD_IDENTIFIER_INFO_COUNT;
    kern_return_t kr = 0;

    kr = thread_info((thread_t)thread, THREAD_IDENTIFIER_INFO, info, &inOutSize);
    if (kr != KERN_SUCCESS) {
        KSLOG_TRACE("Error getting thread_info with flavor THREAD_IDENTIFIER_INFO from mach thread : %s",
                    mach_error_string(kr));
        return false;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-align"
    thread_identifier_info_t idInfo = (thread_identifier_info_t)info;
#pragma clang diagnostic pop
    if (!ksmem_isMemoryReadable(idInfo, sizeof(*idInfo))) {
        KSLOG_DEBUG("Thread %p has an invalid thread identifier info %p", thread, idInfo);
        return false;
    }
    dispatch_queue_t *dispatch_queue_ptr = (dispatch_queue_t *)idInfo->dispatch_qaddr;
    // thread_handle shouldn't be 0 also, because
    // identifier_info->dispatch_qaddr =  identifier_info->thread_handle +
    // get_dispatchqueue_offset_from_proc(thread->task->bsd_info);
    if (dispatch_queue_ptr == NULL || idInfo->thread_handle == 0) {
        KSLOG_TRACE("This thread doesn't have a dispatch queue attached : %p", thread);
        return false;
    }

    // The slot belongs to `thread`, which can exit mid-read, and checking readability then
    // dereferencing leaves a window between the two. copySafely returns an error where a
    // dereference would fault.
    dispatch_queue_t dispatch_queue = NULL;
    if (!ksmem_copySafely(dispatch_queue_ptr, &dispatch_queue, (int)sizeof(dispatch_queue)) || dispatch_queue == NULL) {
        KSLOG_TRACE("This thread doesn't have a dispatch queue attached : %p", thread);
        return false;
    }

    // The queue gets the same treatment, and for a stronger reason: the slot is only known to have
    // held eight readable bytes, and libdispatch would dereference whatever they are.
    const int labelOffset = queueLabelOffset();
    const char *queue_name = labelOffset < 0 ? NULL : queueLabelAt(dispatch_queue, labelOffset);
    if (queue_name == NULL) {
        KSLOG_TRACE("Error while getting dispatch queue name : %p", dispatch_queue);
        return false;
    }

    // Same reason, and maxReadableBytes first because copying bufLength bytes outright
    // fails when the label sits near the end of its mapping.
    const int readable = ksmem_maxReadableBytes(queue_name, bufLength);
    if (readable < 1 || !ksmem_copySafely(queue_name, buffer, readable)) {
        KSLOG_TRACE("Could not read the queue label : %p", dispatch_queue);
        return false;
    }

    // Queue label must be a printable, NUL terminated string.
    int iLabel;
    for (iLabel = 0; iLabel < readable; iLabel++) {
        if (buffer[iLabel] == 0) {
            break;
        }
        if (buffer[iLabel] < ' ' || buffer[iLabel] > '~') {
            KSLOG_TRACE("Queue label contains invalid chars");
            return false;
        }
    }
    if (iLabel == readable) {
        KSLOG_TRACE("Queue label is not NUL terminated within %d bytes", bufLength);
        return false;
    }

    KSLOG_TRACE("Queue label = %s", buffer);
    return true;
}
