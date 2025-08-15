//
//  KSStringConversion.h
//
//  Created by Robert B on 2025-04-23.
//
//  Copyright (c) 2025 Karl Stenerud. All rights reserved.
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

#ifndef HDR_KSStringConversion_h
#define HDR_KSStringConversion_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <uuid/uuid.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Convert an unsigned integer to a hex string.
 * This will write a maximum of 17 characters (including the NUL) to dst.
 *
 * If min_digits is greater than 1, it will prepad with zeroes to reach this number of digits
 * (up to a maximum of 16 digits).
 *
 * Returns the length of the string written to dst (not including the NUL).
 */
size_t kssc_uint64_to_hex(uint64_t value, char *dst, int min_digits, bool uppercase);

/**
 * Convert an uuid_t to an uuid string.
 * This will write 37 characters (including the NUL) to dst.
 */
void kssc_uuid_to_string(uuid_t value, char *dst);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSStringConversion_h
