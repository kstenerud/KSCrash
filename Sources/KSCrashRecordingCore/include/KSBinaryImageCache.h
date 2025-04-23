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

#ifdef __cplusplus
extern "C" {
#endif

/** Initialize the binary image cache.
 * Should be called during KSCrash activation.
 */
void ksbic_init(void);

/** Get the number of cached binary images.
 *
 * @return The number of cached binary images.
 */
uint32_t ksbic_imageCount(void);

/** Get the header of the specified image.
 *
 * @param index The image index.
 *
 * @return The header of the image, or NULL if none was found.
 */
const struct mach_header *ksbic_imageHeader(uint32_t index);

/** Get the name of the specified image.
 *
 * @param index The image index.
 *
 * @return The name of the image, or NULL if none was found.
 */
const char *ksbic_imageName(uint32_t index);

/** Get the VM address slide of the specified image.
 *
 * @param index The image index.
 *
 * @return The VM address slide of the image, or 0 if none was found.
 */
uintptr_t ksbic_imageVMAddrSlide(uint32_t index);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBinaryImageCache_h
