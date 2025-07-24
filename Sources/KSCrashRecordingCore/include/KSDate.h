//
// KSDate.h
//
// Copyright 2016 Karl Stenerud.
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

#ifndef KSDate_h
#define KSDate_h

#include <stdint.h>
#include <sys/types.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Use this as a buffer size for date routines.
 */
#ifndef KSDATE_BUFFERSIZE
#define KSDATE_BUFFERSIZE 64
#endif

/** Convert a UNIX timestamp to an RFC3339 string representation.
 *
 * @param timestamp The date to convert.
 *
 * @param buffer A buffer of at least 21 chars to hold the RFC3339 date string.
 * @param bufferSize The size of the buffer in _buffer_.
 */
void ksdate_utcStringFromTimestamp(time_t timestamp, char *buffer, size_t bufferSize);

/** Convert microseconds returned from `gettimeofday` to an RFC3339 string representation.
 *
 * @param microseconds The microseconds to convert.
 *
 * @param buffer A buffer of at least 28 chars to hold the RFC3339 date string with milliseconds precision.
 * @param bufferSize The size of the buffer in _buffer_.
 */
void ksdate_utcStringFromMicroseconds(int64_t microseconds, char *buffer, size_t bufferSize);

/** Returns microseconds for the unix epoch.
 *
 */
uint64_t ksdate_microseconds(void);

/** Returns seconds for the unix epoch.
 *
 */
uint64_t ksdate_seconds(void);

#ifdef __cplusplus
}
#endif

#endif /* KSDate_h */
