//
//  KSDynamicLinker.h
//
//  Created by Karl Stenerud on 2013-10-02.
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

#ifndef HDR_KSDynamicLinker_h
#define HDR_KSDynamicLinker_h

#include <dlfcn.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t address;
    uint64_t vmAddress;
    uint64_t size;
    uint64_t vmAddressSlide;
    const char *name;
    const uint8_t *uuid;
    int32_t cpuType;
    int32_t cpuSubType;
    uint64_t majorVersion;
    uint64_t minorVersion;
    uint64_t revisionVersion;
    const char *crashInfoMessage;
    const char *crashInfoMessage2;
    const char *crashInfoBacktrace;
    const char *crashInfoSignature;
} KSBinaryImage;

/** Initialize the dynamic linker module.
 * Sets up the symbol cache for fast lookups.
 * Should be called during KSCrash activation.
 */
void ksdl_init(void);

/** Reset all caches (symbol cache and binary image cache).
 * For testing purposes only.
 */
void ksdl_resetCache(void);

/** Get information about a binary image based on mach_header.
 *
 * @param header_ptr The pointer to mach_header of the image.
 *
 * @param image_name The name of the image.
 *
 * @param buffer A structure to hold the information.
 *
 * @return True if the image was successfully queried.
 */
bool ksdl_binaryImageForHeader(const void *const header_ptr, const char *const image_name, KSBinaryImage *buffer);

/** async-safe version of dladdr.
 *
 * This method searches the dynamic loader for information about any image
 * containing the specified address. It may not be entirely successful in
 * finding information, in which case any fields it could not find will be set
 * to NULL.
 *
 * Unlike dladdr(), this method does not make use of locks, and does not call
 * async-unsafe functions.
 *
 * @param address The address to search for.
 * @param info Gets filled out by this function.
 * @return true if at least some information was found.
 */
bool ksdl_dladdr(const uintptr_t address, Dl_info *const info);

/** The __crash_info strings read out of one image of a task.
 * Every non-NULL field is heap-allocated; release with ksdl_freeCrashInfoStrings.
 */
typedef struct {
    char *message;
    char *message2;
    char *backtrace;
    char *signature;
} KSCrashInfoStrings;

/** Read the __DATA,__crash_info strings from an image of @c task.
 *
 * The section coordinates and the message strings are read out of @c task (cross-task), so this
 * works against another process (e.g. a corpse). Allocates; not async-signal-safe.
 *
 * @param task The task whose image to read.
 *
 * @param loadAddress The image's load address in @c task.
 *
 * @param buffer Receives the strings found; all fields NULL when none.
 *
 * @return true if at least one string was found.
 */
bool ksdl_readCrashInfoFromTaskImage(task_t task, uintptr_t loadAddress, KSCrashInfoStrings *buffer);

/** Free the strings of a KSCrashInfoStrings and NULL its fields.
 *
 * @param strings The strings to free. Fields that are NULL are ignored.
 */
void ksdl_freeCrashInfoStrings(KSCrashInfoStrings *strings);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSDynamicLinker_h
