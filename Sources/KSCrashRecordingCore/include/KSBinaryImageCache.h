//
// KSBinaryImageCache.h
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

#ifndef HDR_KSBinaryImageCache_h
#define HDR_KSBinaryImageCache_h

#include <mach-o/dyld.h>
#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

#if __has_feature(modules)

/**
 * From dyld_images.h
 * dyld_images.h is not always modular so we can't directly include it.
 */
struct ks_dyld_image_info {
    const struct mach_header *_Nullable imageLoadAddress; /* base address image is mapped into */
    const char *_Nullable imageFilePath;                  /* path dyld used to load the image */
    uintptr_t imageFileModDate;                           /* time_t of image file */
    /* if stat().st_mtime of imageFilePath does not match imageFileModDate, */
    /* then file has been modified since dyld loaded it */
};

#else

#include <mach-o/dyld_images.h>
typedef ks_dyld_image_info dyld_image_info;

#endif

/** Initialize the binary image cache.
 * Should be called during KSCrash activation.
 */
void ksbic_init(void);

/**
 * Get a C array of _count_ `ks_dyld_image_info`.
 */
const struct ks_dyld_image_info *_Nullable ksbic_getImages(uint32_t *_Nullable count);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBinaryImageCache_h
