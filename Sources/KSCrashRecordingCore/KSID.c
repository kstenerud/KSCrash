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

#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static int ks_getentropy(void *buf, size_t len) { return syscall(SYS_getentropy, buf, len); }
#pragma clang diagnostic pop

static const char g_hexChars[] = "0123456789ABCDEF";

void ksid_generate(char *destinationBuffer37Bytes)
{
    unsigned char bytes[16];
    // getentropy is a direct syscall with no userspace locks,
    // avoiding the corecrypto RNG lock that uuid_generate uses.
    if (ks_getentropy(bytes, sizeof(bytes)) != 0) {
        memset(bytes, 0, sizeof(bytes));
    }
    // UUID v4: version 4 in bytes[6], variant 1 in bytes[8]
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    // Format as XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
    // Dash positions after byte indices 3, 5, 7, 9
    static const int dashAfter[] = { 3, 5, 7, 9 };
    int d = 0;
    int pos = 0;
    for (int i = 0; i < 16; i++) {
        destinationBuffer37Bytes[pos++] = g_hexChars[bytes[i] >> 4];
        destinationBuffer37Bytes[pos++] = g_hexChars[bytes[i] & 0x0F];
        if (d < 4 && i == dashAfter[d]) {
            destinationBuffer37Bytes[pos++] = '-';
            d++;
        }
    }
    destinationBuffer37Bytes[pos] = '\0';
}
