//
//  KSID.c
//
//  Copyright (c) 2016 Karl Stenerud. All rights reserved.
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

#include "KSID.h"

#include <stdint.h>
#include <uuid/uuid.h>

// clang-format off
static const char g_hexDigitsUpper[] = { '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F' };
// clang-format on

// UUID segment byte counts: 8-4-4-4-12 hex chars = 4-2-2-2-6 bytes
static const int g_uuidSegmentLengths[] = { 4, 2, 2, 2, 6 };

static void uuidToString(const uuid_t uuid, char *dst)
{
    char *p = dst;
    int byteIndex = 0;
    for (int seg = 0; seg < 5; seg++) {
        for (int i = 0; i < g_uuidSegmentLengths[seg]; i++) {
            uint8_t b = uuid[byteIndex++];
            *p++ = g_hexDigitsUpper[b >> 4];
            *p++ = g_hexDigitsUpper[b & 0xF];
        }
        if (seg < 4) {
            *p++ = '-';
        }
    }
    *p = '\0';
}

void ksid_generate(char *destinationBuffer37Bytes)
{
    uuid_t uuid;
    uuid_generate(uuid);
    uuidToString(uuid, destinationBuffer37Bytes);
}
