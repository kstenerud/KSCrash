//
//  KSThreadCache.c
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

#include "KSThreadCache.h"

// #define KSLogger_LocalLevel TRACE
#include <errno.h>
#include <mach/mach.h>
#include <memory.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "KSLogger.h"

#define SWAP_POINTERS(A, B) \
    {                       \
        void *temp = A;     \
        A = B;              \
        B = temp;           \
    }

static int g_pollingIntervalInSeconds;
static pthread_t g_cacheThread;
static KSThread *g_allMachThreads;
static KSThread *g_allPThreads;
static const char **g_allThreadNames;
static const char **g_allQueueNames;
static int g_allThreadsCount;
static _Atomic(int) g_semaphoreCount;
static bool g_searchQueueNames = false;
static bool g_hasThreadStarted = false;

static void updateThreadList(void)
{
    const task_t thisTask = mach_task_self();
    int oldThreadsCount = g_allThreadsCount;
    KSThread *allMachThreads = NULL;
    KSThread *allPThreads = NULL;
    static const char **allThreadNames;
    static const char **allQueueNames;

    mach_msg_type_number_t allThreadsCount;
    thread_act_array_t threads;
    kern_return_t kr;
    if ((kr = task_threads(thisTask, &threads, &allThreadsCount)) != KERN_SUCCESS) {
        KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
        return;
    }

    allMachThreads = calloc(allThreadsCount, sizeof(*allMachThreads));
    allPThreads = calloc(allThreadsCount, sizeof(*allPThreads));
    allThreadNames = calloc(allThreadsCount, sizeof(*allThreadNames));
    allQueueNames = calloc(allThreadsCount, sizeof(*allQueueNames));

    for (mach_msg_type_number_t i = 0; i < allThreadsCount; i++) {
        char buffer[1000];
        thread_t thread = threads[i];
        pthread_t pthread = pthread_from_mach_thread_np(thread);
        allMachThreads[i] = (KSThread)thread;
        allPThreads[i] = (KSThread)pthread;
        if (pthread != 0 && pthread_getname_np(pthread, buffer, sizeof(buffer)) == 0 && buffer[0] != 0) {
            allThreadNames[i] = strdup(buffer);
        }
        if (g_searchQueueNames && ksthread_getQueueName((KSThread)thread, buffer, sizeof(buffer)) && buffer[0] != 0) {
            allQueueNames[i] = strdup(buffer);
        }
    }

    g_allThreadsCount = g_allThreadsCount < (int)allThreadsCount ? g_allThreadsCount : (int)allThreadsCount;
    SWAP_POINTERS(g_allMachThreads, allMachThreads);
    SWAP_POINTERS(g_allPThreads, allPThreads);
    SWAP_POINTERS(g_allThreadNames, allThreadNames);
    SWAP_POINTERS(g_allQueueNames, allQueueNames);
    g_allThreadsCount = (int)allThreadsCount;

    if (allMachThreads != NULL) {
        free(allMachThreads);
    }
    if (allPThreads != NULL) {
        free(allPThreads);
    }
    if (allThreadNames != NULL) {
        for (int i = 0; i < oldThreadsCount; i++) {
            const char *name = allThreadNames[i];
            if (name != NULL) {
                free((void *)name);
            }
        }
        free(allThreadNames);
    }
    if (allQueueNames != NULL) {
        for (int i = 0; i < oldThreadsCount; i++) {
            const char *name = allQueueNames[i];
            if (name != NULL) {
                free((void *)name);
            }
        }
        free(allQueueNames);
    }

    for (mach_msg_type_number_t i = 0; i < allThreadsCount; i++) {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * allThreadsCount);
}

static void *monitorThreadCache(__unused void *const userData)
{
    static int quickPollCount = 4;
    usleep(1);
    for (;;) {
        if (g_semaphoreCount <= 0) {
            updateThreadList();
        }
        unsigned pollintInterval = (unsigned)g_pollingIntervalInSeconds;
        if (quickPollCount > 0) {
            // Lots can happen in the first few seconds of operation.
            quickPollCount--;
            pollintInterval = 1;
        }
        sleep(pollintInterval);
    }
    return NULL;
}

void kstc_init(int pollingIntervalInSeconds)
{
    if (g_hasThreadStarted == true) {
        return;
    }
    g_hasThreadStarted = true;
    g_pollingIntervalInSeconds = pollingIntervalInSeconds;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    int error = pthread_create(&g_cacheThread, &attr, &monitorThreadCache, "KSCrash Thread Cache Monitor");
    if (error != 0) {
        KSLOG_ERROR("pthread_create_suspended_np: %s", strerror(error));
    }
    pthread_attr_destroy(&attr);
}

void kstc_freeze(void)
{
    if (g_semaphoreCount++ <= 0) {
        // Sleep just in case the thread cache thread is in the middle of an update.
        usleep(1);
    }
}

void kstc_unfreeze(void)
{
    if (--g_semaphoreCount < 0) {
        // Handle extra calls to unfreeze somewhat gracefully.
        g_semaphoreCount++;
    }
}

void kstc_setSearchQueueNames(bool searchQueueNames) { g_searchQueueNames = searchQueueNames; }

// For testing purposes only. Used with extern in test files.
void kstc_reset(void)
{
    if (g_allThreadNames != NULL) {
        for (int i = 0; i < g_allThreadsCount; i++) {
            const char *name = g_allThreadNames[i];
            if (name != NULL) {
                free((void *)name);
            }
        }
        free(g_allThreadNames);
        g_allThreadNames = NULL;
    }

    if (g_allQueueNames != NULL) {
        for (int i = 0; i < g_allThreadsCount; i++) {
            const char *name = g_allQueueNames[i];
            if (name != NULL) {
                free((void *)name);
            }
        }
        free(g_allQueueNames);
        g_allQueueNames = NULL;
    }

    if (g_allMachThreads != NULL) {
        free(g_allMachThreads);
        g_allMachThreads = NULL;
    }

    if (g_allPThreads != NULL) {
        free(g_allPThreads);
        g_allPThreads = NULL;
    }

    g_allThreadsCount = 0;
    g_semaphoreCount = 0;
    g_hasThreadStarted = false;
}

KSThread *kstc_getAllThreads(int *threadCount)
{
    if (threadCount != NULL) {
        *threadCount = g_allThreadsCount;
    }
    return g_allMachThreads;
}

const char *kstc_getThreadName(KSThread thread)
{
    if (g_allThreadNames != NULL) {
        for (int i = 0; i < g_allThreadsCount; i++) {
            if (g_allMachThreads[i] == thread) {
                return g_allThreadNames[i];
            }
        }
    }
    return NULL;
}

const char *kstc_getQueueName(KSThread thread)
{
    if (g_allQueueNames != NULL) {
        for (int i = 0; i < g_allThreadsCount; i++) {
            if (g_allMachThreads[i] == thread) {
                return g_allQueueNames[i];
            }
        }
    }
    return NULL;
}
