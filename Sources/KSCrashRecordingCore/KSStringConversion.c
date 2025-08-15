//
//  KSStringConversion.c
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

#include "KSStringConversion.h"

#include <math.h>
#include <memory.h>
#include <stdio.h>
#include <uuid/uuid.h>

// Max uint64 is 18446744073709551615
#define MAX_UINT64_DIGITS 20

static char g_hexNybbles[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };

static char g_hexNybblesUppercase[] = {
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
};

static int uuidSegmentLengths[5] = { 4, 2, 2, 2, 6 };

size_t kssc_uint64_to_hex(uint64_t value, char *dst, int min_digits, bool uppercase)
{
    if (min_digits < 1) {
        min_digits = 1;
    } else if (min_digits > 16) {
        min_digits = 16;
    }

    char buff[MAX_UINT64_DIGITS + 1];
    buff[sizeof(buff) - 1] = 0;
    size_t index = sizeof(buff) - 2;
    for (int digitCount = 1;; digitCount++) {
        buff[index] = uppercase ? g_hexNybblesUppercase[(value & 15)] : g_hexNybbles[(value & 15)];
        value >>= 4;
        if (value == 0 && digitCount >= min_digits) {
            break;
        }
        index--;
    }

    size_t length = sizeof(buff) - index;
    memcpy(dst, buff + index, length);
    return length - 1;
}

void kssc_uuid_to_string(uuid_t uuid, char *dst)
{
    char *currentDst = dst;
    int valueIndex = 0;
    for (int segmentIndex = 0; segmentIndex < 5; segmentIndex++) {
        int segmentLength = uuidSegmentLengths[segmentIndex];
        for (int i = 0; i < segmentLength; i++) {
            kssc_uint64_to_hex(uuid[valueIndex++], currentDst, 2, true);
            currentDst += 2;
        }
        if (segmentIndex != 4) {
            memcpy(currentDst++, "-", 1);
        }
    }
}
