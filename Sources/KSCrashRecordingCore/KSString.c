//
//  KSString.m
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

#include "KSString.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "KSSystemCapabilities.h"

// Compiler hints for "if" statements
#define likely_if(x) if (__builtin_expect(x, 1))
#define unlikely_if(x) if (__builtin_expect(x, 0))

// clang-format off
static const int g_printableControlChars[0x20] =
{
    // Only tab, CR, and LF are considered printable
    // 1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

static const int g_continuationByteCount[0x40] =
{
    /*
     --0xxxxx = 1 (00-1f)
     --10xxxx = 2 (20-2f)
     --110xxx = 3 (30-37)
     --1110xx = 4 (38-3b)
     --11110x = 5 (3c-3d)
     */
    // 1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 0, 0,
};
// clang-format on

bool ksstring_isNullTerminatedUTF8String(const void *memory, int minLength, int maxLength)
{
    const unsigned char *ptr = memory;
    const unsigned char *const end = ptr + maxLength;

    for (; ptr < end; ptr++) {
        unsigned char ch = *ptr;
        unlikely_if(ch == 0) { return (ptr - (const unsigned char *)memory) >= minLength; }
        unlikely_if(ch & 0x80)
        {
            unlikely_if((ch & 0xc0) != 0xc0) { return false; }
            int continuationBytes = g_continuationByteCount[ch & 0x3f];
            unlikely_if(continuationBytes == 0 || ptr + continuationBytes >= end) { return false; }
            for (int i = 0; i < continuationBytes; i++) {
                ptr++;
                unlikely_if((*ptr & 0xc0) != 0x80) { return false; }
            }
        }
        else unlikely_if(ch < 0x20 && !g_printableControlChars[ch])
        {
            return false;
        }
    }
    return false;
}

#define INV 0xff

/** Lookup table for converting hex values to integers.
 * INV (0x11111) is used to mark invalid characters so that any attempted
 * invalid nybble conversion is always > 0xffff.
 */
static const unsigned int g_hexConversion[] = {
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, INV, INV, INV, INV, INV, INV, INV, 0xa,
    0xb, 0xc, 0xd, 0xe, 0xf, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
    INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV, INV,
};

bool ksstring_extractHexValue(const char *string, int stringLength, uint64_t *const result)
{
    if (stringLength > 0) {
        const unsigned char *current = (const unsigned char *)string;
        const unsigned char *const end = current + stringLength;
        for (;;) {
#if KSCRASH_HAS_STRNSTR
            current = (const unsigned char *)strnstr((const char *)current, "0x", (unsigned)(end - current));
#else
            current = (const unsigned char *)strstr((const char *)current, "0x");
            unlikely_if(current >= end) { return false; }
#endif
            unlikely_if(!current) { return false; }
            current += 2;

            // Must have at least one valid digit after "0x".
            unlikely_if(g_hexConversion[*current] == INV) { continue; }

            uint64_t accum = 0;
            unsigned int nybble = 0;
            while (current < end) {
                nybble = g_hexConversion[*current++];
                unlikely_if(nybble == INV) { break; }
                accum <<= 4;
                accum += nybble;
            }
            *result = accum;
            return true;
        }
    }
    return false;
}

int ksstring_safeStrcmp(const char *str1, const char *str2)
{
    if (str1 == NULL && str2 == NULL) {
        return 0;
    }

    if (str1 == NULL) {
        return -1;
    }

    if (str2 == NULL) {
        return 1;
    }

    return strcmp(str1, str2);
}

// clang-format off
static const char g_hexDigitsLower[] = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' };
static const char g_hexDigitsUpper[] = { '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F' };
// clang-format on

size_t ksstring_uint64ToHex(uint64_t value, char *dst, size_t bufSize, int minDigits, bool uppercase)
{
    if (bufSize == 0) {
        return 0;
    }

    if (minDigits < 1) {
        minDigits = 1;
    } else if (minDigits > 16) {
        minDigits = 16;
    }

    const char *digits = uppercase ? g_hexDigitsUpper : g_hexDigitsLower;
    char buf[16];
    int pos = 16;

    for (int count = 0; count < 16; count++) {
        buf[--pos] = digits[value & 0xF];
        value >>= 4;
        if (value == 0 && count + 1 >= minDigits) {
            break;
        }
    }

    size_t len = (size_t)(16 - pos);
    if (len >= bufSize) {
        len = bufSize - 1;
    }
    memcpy(dst, buf + pos, len);
    dst[len] = '\0';
    return len;
}

size_t ksstring_intToDecimal(int value, char *dst, size_t bufSize)
{
    if (bufSize == 0) {
        return 0;
    }

    if (value == 0) {
        dst[0] = '0';
        dst[bufSize > 1 ? 1 : 0] = '\0';
        return bufSize > 1 ? 1 : 0;
    }

    char buf[12];
    int pos = 11;
    buf[pos] = '\0';

    bool negative = false;
    unsigned int uval;
    if (value < 0) {
        negative = true;
        // Avoid undefined behavior on INT_MIN
        uval = (unsigned int)(-(value + 1)) + 1u;
    } else {
        uval = (unsigned int)value;
    }

    while (uval > 0) {
        buf[--pos] = (char)('0' + (uval % 10));
        uval /= 10;
    }

    if (negative) {
        buf[--pos] = '-';
    }

    size_t len = (size_t)(11 - pos);
    if (len >= bufSize) {
        len = bufSize - 1;
    }
    memcpy(dst, buf + pos, len);
    dst[len] = '\0';
    return len;
}

size_t ksstring_int64ToDecimal(int64_t value, char *dst, size_t bufSize)
{
    if (bufSize == 0) {
        return 0;
    }

    if (value == 0) {
        dst[0] = '0';
        dst[bufSize > 1 ? 1 : 0] = '\0';
        return bufSize > 1 ? 1 : 0;
    }

    char buf[21];
    int pos = 20;
    buf[pos] = '\0';

    bool negative = false;
    uint64_t uval;
    if (value < 0) {
        negative = true;
        uval = (uint64_t)(-(value + 1)) + 1u;
    } else {
        uval = (uint64_t)value;
    }

    while (uval > 0) {
        buf[--pos] = (char)('0' + (uval % 10));
        uval /= 10;
    }

    if (negative) {
        buf[--pos] = '-';
    }

    size_t len = (size_t)(20 - pos);
    if (len >= bufSize) {
        len = bufSize - 1;
    }
    memcpy(dst, buf + pos, len);
    dst[len] = '\0';
    return len;
}

size_t ksstring_uint64ToDecimal(uint64_t value, char *dst, size_t bufSize)
{
    if (bufSize == 0) {
        return 0;
    }

    if (value == 0) {
        dst[0] = '0';
        dst[bufSize > 1 ? 1 : 0] = '\0';
        return bufSize > 1 ? 1 : 0;
    }

    char buf[21];
    int pos = 20;
    buf[pos] = '\0';

    while (value > 0) {
        buf[--pos] = (char)('0' + (value % 10));
        value /= 10;
    }

    size_t len = (size_t)(20 - pos);
    if (len >= bufSize) {
        len = bufSize - 1;
    }
    memcpy(dst, buf + pos, len);
    dst[len] = '\0';
    return len;
}

static size_t copyLiteral(const char *src, char *dst, size_t bufSize)
{
    size_t len = strlen(src);
    if (len >= bufSize) {
        len = bufSize > 0 ? bufSize - 1 : 0;
    }
    memcpy(dst, src, len);
    if (bufSize > 0) {
        dst[len] = '\0';
    }
    return len;
}

// Signal-safe pow10 lookup table (avoids libm pow which may lock).
static const double g_pow10[] = {
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
};

size_t ksstring_doubleToString(double value, char *dst, size_t bufSize)
{
    if (bufSize == 0) {
        return 0;
    }

    if (isnan(value)) {
        return copyLiteral("null", dst, bufSize);
    }
    if (isinf(value)) {
        return copyLiteral(value > 0 ? "1e999" : "-1e999", dst, bufSize);
    }
    if (value == 0.0) {
        return copyLiteral(signbit(value) ? "-0.0" : "0.0", dst, bufSize);
    }

    char *p = dst;
    char *end = dst + bufSize - 1;

    if (value < 0) {
        if (p < end) {
            *p++ = '-';
        }
        value = -value;
    }

    int sigDigits;
    float fv = (float)value;
    if (fabs(value - (double)fv) <= (double)FLT_EPSILON * fabs(value)) {
        sigDigits = FLT_DIG;
    } else {
        sigDigits = DBL_DIG;
    }

    // Compute decimal exponent via binary search: normalize to [1.0, 10.0)
    // Covers full double range (~1e-308 to ~1e+308)
    int exponent = 0;
    double normalized = value;
    if (normalized >= 10.0) {
        if (normalized >= 1e256) {
            normalized /= 1e256;
            exponent += 256;
        }
        if (normalized >= 1e128) {
            normalized /= 1e128;
            exponent += 128;
        }
        if (normalized >= 1e64) {
            normalized /= 1e64;
            exponent += 64;
        }
        if (normalized >= 1e32) {
            normalized /= 1e32;
            exponent += 32;
        }
        if (normalized >= 1e16) {
            normalized /= 1e16;
            exponent += 16;
        }
        if (normalized >= 1e8) {
            normalized /= 1e8;
            exponent += 8;
        }
        if (normalized >= 1e4) {
            normalized /= 1e4;
            exponent += 4;
        }
        if (normalized >= 1e2) {
            normalized /= 1e2;
            exponent += 2;
        }
        if (normalized >= 1e1) {
            normalized /= 1e1;
            exponent += 1;
        }
    } else if (normalized < 1.0) {
        if (normalized < 1e-255) {
            normalized *= 1e256;
            exponent -= 256;
        }
        if (normalized < 1e-127) {
            normalized *= 1e128;
            exponent -= 128;
        }
        if (normalized < 1e-63) {
            normalized *= 1e64;
            exponent -= 64;
        }
        if (normalized < 1e-31) {
            normalized *= 1e32;
            exponent -= 32;
        }
        if (normalized < 1e-15) {
            normalized *= 1e16;
            exponent -= 16;
        }
        if (normalized < 1e-7) {
            normalized *= 1e8;
            exponent -= 8;
        }
        if (normalized < 1e-3) {
            normalized *= 1e4;
            exponent -= 4;
        }
        if (normalized < 1e-1) {
            normalized *= 1e2;
            exponent -= 2;
        }
        if (normalized < 1e0) {
            normalized *= 1e1;
            exponent -= 1;
        }
    }
    if (normalized >= 10.0) {
        normalized /= 10.0;
        exponent++;
    }
    if (normalized < 1.0) {
        normalized *= 10.0;
        exponent--;
    }

    bool useScientific = (exponent >= sigDigits || exponent < -4);

    // Extract significant digits as an integer
    double scale = g_pow10[sigDigits - 1];
    uint64_t allDigits = (uint64_t)(normalized * scale + 0.5);
    if (allDigits >= (uint64_t)(scale * 10.0)) {
        allDigits /= 10;
        exponent++;
    }

    char digitBuf[21];
    size_t dlen = ksstring_uint64ToDecimal(allDigits, digitBuf, sizeof(digitBuf));

    // Strip trailing zeros from digit string (keep at least first digit)
    size_t sigLen = dlen;
    while (sigLen > 1 && digitBuf[sigLen - 1] == '0') {
        sigLen--;
    }

    if (useScientific) {
        // Write mantissa
        if (dlen > 0 && p < end) {
            *p++ = digitBuf[0];
        }
        if (sigLen > 1) {
            if (p < end) *p++ = '.';
            for (size_t i = 1; i < sigLen && p < end; i++) {
                *p++ = digitBuf[i];
            }
        }
        // Write exponent with explicit sign (matches %g behavior)
        if (p < end) *p++ = 'e';
        if (exponent < 0) {
            if (p < end) *p++ = '-';
            exponent = -exponent;
        } else {
            if (p < end) *p++ = '+';
        }
        char expBuf[12];
        size_t elen = ksstring_intToDecimal(exponent, expBuf, sizeof(expBuf));
        for (size_t i = 0; i < elen && p < end; i++) {
            *p++ = expBuf[i];
        }
    } else {
        int intDigits = exponent + 1;

        // Write integer part (at least "0" for values < 1)
        if (intDigits <= 0) {
            if (p < end) *p++ = '0';
        } else {
            for (int i = 0; i < intDigits && p < end; i++) {
                *p++ = (i < (int)dlen) ? digitBuf[i] : '0';
            }
        }

        if (p < end) {
            *p++ = '.';
        }

        // Write fractional part
        // For values < 1, we need leading zeros after the decimal point
        size_t fracWritten = 0;
        if (intDigits < 0) {
            int leadingZeros = -intDigits;
            for (int i = 0; i < leadingZeros && p < end; i++) {
                *p++ = '0';
                fracWritten++;
            }
            // Then write all significant digits
            for (size_t i = 0; i < sigLen && p < end; i++) {
                *p++ = digitBuf[i];
                fracWritten++;
            }
        } else {
            // Write remaining significant digits after integer part
            int startIdx = intDigits < 0 ? 0 : intDigits;
            if (startIdx < (int)sigLen) {
                for (int i = startIdx; i < (int)sigLen && p < end; i++) {
                    *p++ = (i < (int)dlen) ? digitBuf[i] : '0';
                    fracWritten++;
                }
            }
        }
        if (fracWritten == 0 && p < end) {
            *p++ = '0';
        }
    }

    *p = '\0';
    return (size_t)(p - dst);
}
