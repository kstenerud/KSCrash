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

#ifdef __cplusplus
extern "C" {
#endif


#include <sys/types.h>

/** Convert a UNIX timestamp to an RFC3339 string representation.
 *
 * @param timestamp The date to convert.
 *
 * @param buffer21Chars A buffer of at least 21 chars to hold the RFC3339 date string.
 */
void ksdate_utcStringFromTimestamp(time_t timestamp, char* buffer21Chars);

/** Convert microseconds returned from `gettimeofday` to an RFC3339 string representation.
 *
 * @param microseconds The microseconds to convert.
 *
 * @param buffer28Chars A buffer of at least 28 chars to hold the RFC3339 date string with milliseconds precision.
 */
void ksdate_utcStringFromMicroseconds(int64_t microseconds, char* buffer28Chars);

#ifdef __cplusplus
}
#endif

#endif /* KSDate_h */
