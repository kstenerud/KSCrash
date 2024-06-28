//
//  KSString.h
//
//  Created by Karl Stenerud on 2012-09-15.
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

#ifndef HDR_KSString_h
#define HDR_KSString_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Check if a memory location contains a null terminated UTF-8 string.
 *
 * @param memory The memory location to test.
 *
 * @param minLength The minimum length to be considered a valid string.
 *
 * @param maxLength The maximum length to be considered a valid string.
 */
bool ksstring_isNullTerminatedUTF8String(const void *memory, int minLength, int maxLength);

/** Extract a hex value in the form "0x123456789abcdef" from a string.
 *
 * @param string The string to search.
 *
 * @param stringLength The length of the string.
 *
 * @param result Buffer to hold the resulting value.
 *
 * @return true if the operation was successful.
 */
bool ksstring_extractHexValue(const char *string, int stringLength, uint64_t *result);

/** Safely compares two strings.
 *
 * Compares str1 and str2 using strcmp if both are non-NULL. If either
 * or both strings are NULL, performs a safe comparison considering NULL as
 * the lowest value.
 *
 * @param str1 The first string, can be NULL.
 * @param str2 The second string, can be NULL.
 *
 * @return An integer value indicating the comparison result:
 *         - Returns 0 if both strings are NULL or both strings are non-NULL
 *           and identical.
 *         - Returns a negative value if str1 is NULL and str2 is non-NULL,
 *           or if both strings are non-NULL and str1 is less than str2.
 *         - Returns a positive value if str1 is non-NULL and str2 is NULL,
 *           or if both strings are non-NULL and str1 is greater than str2.
 */
int ksstring_safeStrcmp(const char *str1, const char *str2);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSString_h
