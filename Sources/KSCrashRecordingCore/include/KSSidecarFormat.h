//
//  KSSidecarFormat.h
//
//  Created by Alexander Cohen on 2026-09-28.
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

/* The on-disk format every mmap'd run sidecar shares, and the one reader for
 * all of them.
 *
 * A sidecar is a fixed-layout struct that a monitor maps with ksfu_mmap and
 * updates in place while the run lives, and that is read back from the file
 * once the run is over. The struct begins with a KSSidecarHeader. Versions only
 * ever append fields, so every older version's layout is a prefix of the
 * current one, and a file's size says which version it holds.
 *
 * Adding a sidecar:
 *   1. Declare the struct with a KSSidecarHeader named `header` as its first
 *      member, and fixed-width fields only (no pointers, no bool, no platform
 *      typedefs), so the layout is the same on every architecture.
 *   2. Define its magic, a size macro for each version, and its current
 *      version, then check the layout with KSSIDECAR_ASSERT_LAYOUT.
 *   3. Add a typed reader that hands kssidecar_read a KSSidecarFormat listing
 *      those sizes.
 *
 * Adding a version: append the fields, add the new size macro, bump the
 * current version, add the size to the reader's list, and name the version's
 * first field in a KSSIDECAR_ASSERT_VERSION_START. The layout assert fails the
 * build when the size changed without a new size macro, and each reader asserts
 * it lists one size per version. Only the version-start assert catches a field
 * inserted into a padding hole instead of appended, and only once it is
 * written, so it is not optional.
 */

#ifndef HDR_KSSidecarFormat_h
#define HDR_KSSidecarFormat_h

#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The first bytes of every sidecar: which sidecar the file is, and which
 *  version of its layout.
 *
 *  Packed so it is exactly the five bytes the sidecars have always begun with.
 *  Unpacked it would pad to eight and move every field after it, and no file
 *  already on disk would read.
 */
typedef struct __attribute__((packed)) {
    /** Which sidecar this is; each sidecar has its own. */
    int32_t magic;
    /** Which version of that sidecar's layout the file holds, from 1. */
    uint8_t version;
} KSSidecarHeader;

_Static_assert(sizeof(KSSidecarHeader) == 5,
               "KSSidecarHeader must stay packed; every sidecar's fields follow its 5 bytes");

/** A sidecar's on-disk format. */
typedef struct {
    /** The magic every file of this sidecar begins with. */
    int32_t magic;
    /** The struct's size at each version, oldest first: versionSizes[v - 1] is
     *  version v. Each is larger than the one before, and the last is the
     *  current version. */
    const size_t *versionSizes;
    /** How many entries `versionSizes` has, which is also the current version. */
    uint8_t versionCount;
} KSSidecarFormat;

/** Reads a sidecar file into its struct. Fields newer than the file's version
 *  read as zero.
 *
 * @param format The sidecar's magic and its struct's size at each version.
 * @param path The file to read.
 * @param out The struct to fill. Zeroed on anything but OK.
 * @param outSize The size of `out`, which must be the current version's size.
 *
 * @return OK when `out` holds the file's data. Unrecoverable when no later read
 *         gets further: a missing file, a file too short for any version, a
 *         wrong magic, a version that disagrees with the file's size, or a
 *         NULL `path`, `out`, or `format` (or an `outSize` that is not the
 *         current version's size). Failure only when the I/O itself failed,
 *         which a later read may get past.
 */
KSCrashSidecarReadResult kssidecar_read(const KSSidecarFormat *format, const char *path, void *out, size_t outSize);

/** Checks at compile time that `Type` is laid out as a sidecar: it begins with
 *  its header and is `currentSize` bytes. A size change without a new version
 *  fails here. */
#define KSSIDECAR_ASSERT_LAYOUT(Type, currentSize)                                             \
    _Static_assert(offsetof(Type, header) == 0, #Type " must begin with its KSSidecarHeader"); \
    _Static_assert(sizeof(Type) == (currentSize), #Type " changed size; append the fields as a new version")

/** Checks at compile time that `field`, the first field a version added, starts
 *  exactly where the previous version ended. A field inserted into a padding
 *  hole keeps the size unchanged but misreads every older file; this catches
 *  it. */
#define KSSIDECAR_ASSERT_VERSION_START(Type, field, previousSize) \
    _Static_assert(offsetof(Type, field) == (previousSize),       \
                   #Type "." #field " must start where the previous version ended")

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSSidecarFormat_h
