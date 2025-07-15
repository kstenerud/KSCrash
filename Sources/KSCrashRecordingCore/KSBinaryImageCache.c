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

#import <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "KSLogger.h"

static _Atomic(bool) g_initialized = false;
static _Atomic(struct dyld_all_image_infos *) g_all_image_infos = NULL;

static void ksbic_set_all_image_infos(struct dyld_all_image_infos *ptr)
{
    atomic_store_explicit(&g_all_image_infos, ptr, memory_order_release);
}

static struct dyld_all_image_infos *ksbic_get_all_image_infos(void)
{
    return atomic_load_explicit(&g_all_image_infos, memory_order_acquire);
}

void ksbic_init(void)
{
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_initialized, &expected, true)) {
        return;
    }

    KSLOG_DEBUG("Initializing binary image cache");

    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t err = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (err != KERN_SUCCESS) {
        KSLOG_DEBUG("Initializing binary error");
        return;
    }
    ksbic_set_all_image_infos((struct dyld_all_image_infos *)dyld_info.all_image_info_addr);
}

const struct dyld_image_info *ksbic_beginImageAccess(int *count)
{
    struct dyld_all_image_infos *allInfo = ksbic_get_all_image_infos();
    if (!allInfo) {
        KSLOG_ERROR("Already accesing images");
        return NULL;
    }
    const struct dyld_image_info *images = allInfo->infoArray;
    if (images == NULL) {
        KSLOG_ERROR("Already accesing images");
        return NULL;
    }
    allInfo->infoArray = NULL;
    if (count) {
        *count = allInfo->infoArrayCount;
    }
    return images;
}

void ksbic_endImageAccess(const struct dyld_image_info *images)
{
    struct dyld_all_image_infos *allInfo = ksbic_get_all_image_infos();
    if (!allInfo) {
        KSLOG_ERROR("Already accesing images");
        return NULL;
    }
    if (allInfo->infoArray) {
        KSLOG_ERROR("Cannot end image access");
        return;
    }
    allInfo->infoArray = images;
}

// For testing purposes only. Used with extern in test files.
void ksbic_resetCache(void)
{
    bool expected = true;
    if (!atomic_compare_exchange_strong(&g_initialized, &expected, false)) {
        return;
    }
    ksbic_set_all_image_infos(NULL);
}
