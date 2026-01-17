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

#include <errno.h>
#include <mach/mach.h>
#include <memory.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

// MARK: - Types

typedef struct {
    KSThread *machThreads;
    KSThread *pthreads;
    const char **threadNames;
    const char **queueNames;
    int count;
} KSThreadCacheData;

// MARK: - Globals

static atomic_int g_pollingIntervalInSeconds;
static pthread_t g_cacheThread;
static atomic_bool g_searchQueueNames;
static atomic_bool g_initialized;

/** The active cache. NULL means either not initialized or currently acquired. */
static _Atomic(KSThreadCacheData *) g_activeCache;

/** Cache acquired by freeze(). */
static _Atomic(KSThreadCacheData *) g_frozenCache;

// MARK: - Private Helpers

static void freeCache(KSThreadCacheData *cache)
{
    if (cache == NULL) {
        return;
    }

    if (cache->threadNames != NULL) {
        for (int i = 0; i < cache->count; i++) {
            if (cache->threadNames[i] != NULL) {
                free((void *)cache->threadNames[i]);
            }
        }
        free(cache->threadNames);
    }

    if (cache->queueNames != NULL) {
        for (int i = 0; i < cache->count; i++) {
            if (cache->queueNames[i] != NULL) {
                free((void *)cache->queueNames[i]);
            }
        }
        free(cache->queueNames);
    }

    if (cache->machThreads != NULL) {
        free(cache->machThreads);
    }

    if (cache->pthreads != NULL) {
        free(cache->pthreads);
    }

    free(cache);
}

static KSThreadCacheData *createCache(bool searchQueueNames)
{
    const task_t thisTask = mach_task_self();
    mach_msg_type_number_t threadCount;
    thread_act_array_t threads;
    kern_return_t kr;

    if ((kr = task_threads(thisTask, &threads, &threadCount)) != KERN_SUCCESS) {
        KSLOG_ERROR("task_threads: %s", mach_error_string(kr));
        return NULL;
    }

    KSThreadCacheData *cache = calloc(1, sizeof(*cache));
    if (cache == NULL) {
        KSLOG_ERROR("Failed to allocate thread cache");
        goto cleanup_threads;
    }

    cache->count = (int)threadCount;
    cache->machThreads = calloc(threadCount, sizeof(*cache->machThreads));
    cache->pthreads = calloc(threadCount, sizeof(*cache->pthreads));
    cache->threadNames = calloc(threadCount, sizeof(*cache->threadNames));
    cache->queueNames = calloc(threadCount, sizeof(*cache->queueNames));

    if (cache->machThreads == NULL || cache->pthreads == NULL || cache->threadNames == NULL ||
        cache->queueNames == NULL) {
        KSLOG_ERROR("Failed to allocate thread cache arrays");
        freeCache(cache);
        cache = NULL;
        goto cleanup_threads;
    }

    for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
        char buffer[1000];
        thread_t thread = threads[i];
        pthread_t pthread = pthread_from_mach_thread_np(thread);

        cache->machThreads[i] = (KSThread)thread;
        cache->pthreads[i] = (KSThread)pthread;

        if (pthread != 0 && pthread_getname_np(pthread, buffer, sizeof(buffer)) == 0 && buffer[0] != 0) {
            cache->threadNames[i] = strdup(buffer);
        }

        if (searchQueueNames && ksthread_getQueueName((KSThread)thread, buffer, sizeof(buffer)) && buffer[0] != 0) {
            cache->queueNames[i] = strdup(buffer);
        }
    }

cleanup_threads:
    for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * threadCount);

    return cache;
}

static void updateCache(void)
{
    // Acquire exclusive access to the cache
    KSThreadCacheData *oldCache = atomic_exchange(&g_activeCache, NULL);
    if (oldCache == NULL) {
        // Cache is currently acquired by another caller (e.g., crash handler)
        // Skip this update cycle
        return;
    }

    bool searchQueueNames = atomic_load(&g_searchQueueNames);
    KSThreadCacheData *newCache = createCache(searchQueueNames);

    if (newCache == NULL) {
        // Failed to create new cache, restore the old one
        atomic_store(&g_activeCache, oldCache);
        return;
    }

    // Install new cache and free old
    atomic_store(&g_activeCache, newCache);
    freeCache(oldCache);
}

static void *monitorThreadCache(__unused void *const userData)
{
    static int quickPollCount = 4;
    usleep(1);

    for (;;) {
        updateCache();

        unsigned pollInterval = (unsigned)atomic_load(&g_pollingIntervalInSeconds);
        if (quickPollCount > 0) {
            // Lots can happen in the first few seconds of operation.
            quickPollCount--;
            pollInterval = 1;
        }
        sleep(pollInterval);
    }
    return NULL;
}

// MARK: - Public API

void kstc_init(int pollingIntervalInSeconds)
{
    if (atomic_exchange(&g_initialized, true)) {
        return;
    }

    atomic_store(&g_pollingIntervalInSeconds, pollingIntervalInSeconds);
    atomic_store(&g_searchQueueNames, false);
    atomic_store(&g_frozenCache, NULL);

    // Create initial cache
    KSThreadCacheData *initialCache = createCache(false);
    atomic_store(&g_activeCache, initialCache);

    // Start background monitoring thread
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    int error = pthread_create(&g_cacheThread, &attr, &monitorThreadCache,
                               KSCRASH_NS_STRING("KSCrash") " Thread Cache Monitor");
    if (error != 0) {
        KSLOG_ERROR("pthread_create: %s", strerror(error));
    }
    pthread_attr_destroy(&attr);
}

void kstc_freeze(void)
{
    // Acquire exclusive access to the cache
    KSThreadCacheData *cache = atomic_exchange(&g_activeCache, NULL);

    // If cache was unavailable (in use by background thread), wait briefly and retry
    if (cache == NULL) {
        usleep(1);
        cache = atomic_exchange(&g_activeCache, NULL);
    }

    atomic_store(&g_frozenCache, cache);
}

void kstc_unfreeze(void)
{
    KSThreadCacheData *cache = atomic_exchange(&g_frozenCache, NULL);
    if (cache != NULL) {
        atomic_store(&g_activeCache, cache);
    }
}

void kstc_setSearchQueueNames(bool searchQueueNames) { atomic_store(&g_searchQueueNames, searchQueueNames); }

KSThread *kstc_getAllThreads(int *threadCount)
{
    KSThreadCacheData *cache = atomic_load(&g_frozenCache);
    if (cache == NULL) {
        if (threadCount != NULL) {
            *threadCount = 0;
        }
        return NULL;
    }

    if (threadCount != NULL) {
        *threadCount = cache->count;
    }
    return cache->machThreads;
}

const char *kstc_getThreadName(KSThread thread)
{
    KSThreadCacheData *cache = atomic_load(&g_frozenCache);
    if (cache == NULL || cache->machThreads == NULL || cache->threadNames == NULL) {
        return NULL;
    }

    for (int i = 0; i < cache->count; i++) {
        if (cache->machThreads[i] == thread) {
            return cache->threadNames[i];
        }
    }
    return NULL;
}

const char *kstc_getQueueName(KSThread thread)
{
    KSThreadCacheData *cache = atomic_load(&g_frozenCache);
    if (cache == NULL || cache->machThreads == NULL || cache->queueNames == NULL) {
        return NULL;
    }

    for (int i = 0; i < cache->count; i++) {
        if (cache->machThreads[i] == thread) {
            return cache->queueNames[i];
        }
    }
    return NULL;
}

// MARK: - Testing API

// For testing purposes only. Used with extern in test files.
void kstc_reset(void)
{
    // Clear frozen cache (don't free - it may point to same memory as activeCache)
    atomic_store(&g_frozenCache, NULL);

    // Free the active cache
    KSThreadCacheData *cache = atomic_exchange(&g_activeCache, NULL);
    freeCache(cache);

    atomic_store(&g_searchQueueNames, false);
    atomic_store(&g_initialized, false);
}
