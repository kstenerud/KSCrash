//
// KSBinaryImageCache.c
//
// Created by Gleb Linnik on 2025-04-20.
//
// Copyright (c) 2012 Karl Stenerud. All rights reserved.
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

#include "KSBinaryImageCache.h"

#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "KSLogger.h"

/// As a general rule, access to _g_all_image_infos->infoArray_ is thread safe
/// in a way that you can iterate all you want since items will never be removed
/// and the _infoCount_ is only updated after an item is added to _infoArray_.
/// Because of this, we can iterate during a signal handler, Mach exception handler
/// or even at any point within the run of the process.
///
/// More info in this comment:
/// https://github.com/kstenerud/KSCrash/pull/655#discussion_r2211271075

static struct dyld_all_image_infos *g_all_image_infos = NULL;

/// Atomic flag to ensure ksbic_init() only runs once, even if called
/// concurrently from multiple threads during startup.
static _Atomic bool g_all_image_infos_initialized = false;

void ksbic_init(void)
{
    // Atomically check if uninitialized (false) and set to initialized (true).
    // If another thread already initialized, this returns false and we exit early.
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_all_image_infos_initialized, &expected, true)) {
        return;
    }

    KSLOG_DEBUG("Initializing binary image cache");

    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t err = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (err != KERN_SUCCESS) {
        KSLOG_ERROR("Failed to acquire TASK_DYLD_INFO. We won't have access to binary images.");
        return;
    }
    g_all_image_infos = (struct dyld_all_image_infos *)dyld_info.all_image_info_addr;
}

// Note: We intentionally do not call ksbic_init() here if uninitialized.
// This function may be called from a signal handler during crash reporting,
// and ksbic_init() is not async-signal-safe.
const ks_dyld_image_info *ksbic_getImages(uint32_t *count)
{
    if (count) {
        *count = 0;
    }
    struct dyld_all_image_infos *allInfo = g_all_image_infos;
    if (allInfo == NULL) {
        KSLOG_ERROR("Cannot access binary images");
        return NULL;
    }
    const struct dyld_image_info *images = allInfo->infoArray;
    if (images == NULL) {
        KSLOG_ERROR("Unexpected state: dyld_all_image_infos->infoArray is NULL!");
        return NULL;
    }
    if (count) {
        *count = allInfo->infoArrayCount;
    }
    return (ks_dyld_image_info *)images;
}

// For testing purposes only. Used with extern in test files.
// Note: This is not a perfectly synchronized reset (there's a small window
// between resetting the flag and clearing the pointer), but it's sufficient
// for sequential test scenarios.
void ksbic_resetCache(void)
{
    // Reset initialization flag and clear cached pointer.
    // Only for testing so correctness doesn't matter.
    g_all_image_infos = NULL;
    g_all_image_infos_initialized = false;
}
