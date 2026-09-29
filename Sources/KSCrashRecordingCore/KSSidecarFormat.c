//
//  KSSidecarFormat.c
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

#include "KSSidecarFormat.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "KSFileUtils.h"
#include "KSLogger.h"

KSCrashSidecarReadResult kssidecar_read(const KSSidecarFormat *format, const char *path, void *out, size_t outSize)
{
    if (out == NULL) {
        return KSCrashSidecarReadUnrecoverable;
    }
    memset(out, 0, outSize);
    if (format == NULL || format->versionSizes == NULL || format->versionCount == 0 ||
        outSize != format->versionSizes[format->versionCount - 1]) {
        KSLOG_ERROR("Sidecar read called with a format that does not match its struct");
        return KSCrashSidecarReadUnrecoverable;
    }
    if (path == NULL) {
        return KSCrashSidecarReadUnrecoverable;
    }

    int fd = open(path, O_RDONLY);
    if (fd == -1) {
        // Before logging: the logger's own writes can replace errno.
        int openError = errno;
        if (openError == ENOENT) {
            return KSCrashSidecarReadUnrecoverable;
        }
        KSLOG_ERROR("Failed to open sidecar at %s: %s", path, strerror(openError));
        return KSCrashSidecarReadFailure;
    }
    struct stat st;
    if (fstat(fd, &st) != 0) {
        int statError = errno;
        close(fd);
        KSLOG_ERROR("Failed to stat sidecar at %s: %s", path, strerror(statError));
        return KSCrashSidecarReadFailure;
    }

    // The file's size says which version it holds: the newest one whose struct
    // fits. A file is one byte longer than its struct (ksfu_mmap sizes it by
    // writing a byte past the end), so "fits" is at least, not exactly. Reading
    // only that version's size means an older file never takes a read that runs
    // off its end.
    uint8_t sizedVersion = 0;
    for (uint8_t version = format->versionCount; version > 0; version--) {
        if (st.st_size >= (off_t)format->versionSizes[version - 1]) {
            sizedVersion = version;
            break;
        }
    }
    if (sizedVersion == 0) {
        // Shorter than any version: the run died part way through creating it.
        close(fd);
        KSLOG_ERROR("Sidecar at %s is %lld bytes, too short for any version", path, (long long)st.st_size);
        return KSCrashSidecarReadUnrecoverable;
    }
    bool didRead = ksfu_readBytesFromFD(fd, (char *)out, (int)format->versionSizes[sizedVersion - 1]);
    close(fd);
    if (!didRead) {
        // The size was checked above, so either the read itself failed, or the
        // file was re-created under us between fstat and read (ksfu_mmap opens
        // with O_TRUNC, and the watchdog re-creates its run sidecar on every
        // hang). A later read can get past either. A re-created file caught
        // after it reached full size but before its header was written reads
        // as magic 0 and is Unrecoverable below instead.
        memset(out, 0, outSize);
        return KSCrashSidecarReadFailure;
    }

    // The header is the struct's first member (KSSIDECAR_ASSERT_LAYOUT), so it
    // is the first bytes read.
    KSSidecarHeader header;
    memcpy(&header, out, sizeof(header));
    // The declared version has to be the one the size implies. Anything else
    // (version 0, a newer build's version, a version whose fields the file is
    // too short to hold) is a verdict about the bytes that no later read changes.
    if (header.magic != format->magic || header.version != sizedVersion) {
        KSLOG_ERROR("Invalid sidecar at %s (magic=0x%x version=%d, %lld bytes)", path, header.magic, header.version,
                    (long long)st.st_size);
        memset(out, 0, outSize);
        return KSCrashSidecarReadUnrecoverable;
    }
    return KSCrashSidecarReadOK;
}
