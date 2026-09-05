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
    return ksstring_int64ToDecimal((int64_t)value, dst, bufSize);
}

size_t ksstring_int64ToDecimal(int64_t value, char *dst, size_t bufSize)
{
    if (bufSize == 0) {
        return 0;
    }

    if (value >= 0) {
        return ksstring_uint64ToDecimal((uint64_t)value, dst, bufSize);
    }

    // Negative: prepend '-' then format the magnitude
    uint64_t magnitude = (uint64_t)(-(value + 1)) + 1u;
    if (bufSize < 2) {
        // Can't write even the '-'; compute required length via a temp buffer
        char tmp[21];
        size_t magLen = ksstring_uint64ToDecimal(magnitude, tmp, sizeof(tmp));
        if (bufSize == 1) dst[0] = '\0';
        return magLen + 1;
    }
    dst[0] = '-';
    size_t len = ksstring_uint64ToDecimal(magnitude, dst + 1, bufSize - 1);
    return len + 1;
}

size_t ksstring_uint64ToDecimal(uint64_t value, char *dst, size_t bufSize)
{
    if (bufSize == 0) {
        return 0;
    }

    if (value == 0) {
        if (bufSize >= 2) {
            dst[0] = '0';
            dst[1] = '\0';
        } else {
            dst[0] = '\0';
        }
        return 1;  // snprintf semantics: required length is always 1
    }

    char buf[21];
    int pos = 20;
    buf[pos] = '\0';

    while (value > 0) {
        buf[--pos] = (char)('0' + (value % 10));
        value /= 10;
    }

    size_t len = (size_t)(20 - pos);
    size_t writeLen = (len < bufSize) ? len : bufSize - 1;
    memcpy(dst, buf + pos, writeLen);
    dst[writeLen] = '\0';
    return len;  // snprintf semantics: return required length, not bytes written
}

static size_t copyLiteral(const char *src, char *dst, size_t bufSize)
{
    size_t len = strlen(src);
    size_t writeLen = (len < bufSize) ? len : (bufSize > 0 ? bufSize - 1 : 0);
    memcpy(dst, src, writeLen);
    if (bufSize > 0) {
        dst[writeLen] = '\0';
    }
    return len;  // snprintf semantics: required length, not bytes written
}

// Signal-safe pow10 lookup table (avoids libm pow which may lock).
// MARK: - Shortest round-trip decimal conversion

// A small fixed-width unsigned integer, enough for exact decimal conversion of
// any double: the largest intermediate is the mantissa scaled by 2^1077 and by
// 10^324, well under 48 limbs. Everything lives on the stack and no libc beyond
// memmove/memset is touched, so the conversion stays async-signal-safe.
#define KSBIG_LIMBS 48

typedef struct {
    uint32_t limb[KSBIG_LIMBS];  // little-endian
    int len;                     // significant limbs; 0 means zero
} KSBigInt;

static void bigSetU64(KSBigInt *b, uint64_t value)
{
    memset(b, 0, sizeof(*b));
    b->limb[0] = (uint32_t)value;
    b->limb[1] = (uint32_t)(value >> 32);
    b->len = b->limb[1] != 0 ? 2 : (b->limb[0] != 0 ? 1 : 0);
}

static void bigMulSmall(KSBigInt *b, uint32_t multiplier)
{
    uint64_t carry = 0;
    for (int i = 0; i < b->len; i++) {
        uint64_t product = (uint64_t)b->limb[i] * multiplier + carry;
        b->limb[i] = (uint32_t)product;
        carry = product >> 32;
    }
    if (carry != 0 && b->len < KSBIG_LIMBS) {
        b->limb[b->len++] = (uint32_t)carry;
    }
}

static void bigMulPow10(KSBigInt *b, int power)
{
    static const uint32_t smallPowers[] = { 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000 };
    while (power >= 9) {
        bigMulSmall(b, 1000000000u);
        power -= 9;
    }
    if (power > 0) {
        bigMulSmall(b, smallPowers[power]);
    }
}

static void bigShiftLeft(KSBigInt *b, int bits)
{
    if (b->len == 0 || bits <= 0) {
        return;
    }
    const int limbs = bits / 32;
    const int rest = bits % 32;
    if (rest != 0) {
        uint32_t carry = 0;
        for (int i = 0; i < b->len; i++) {
            uint32_t v = b->limb[i];
            b->limb[i] = (v << rest) | carry;
            carry = v >> (32 - rest);
        }
        if (carry != 0 && b->len < KSBIG_LIMBS) {
            b->limb[b->len++] = carry;
        }
    }
    if (limbs != 0) {
        if (b->len + limbs > KSBIG_LIMBS) {
            b->len = KSBIG_LIMBS - limbs;  // cannot happen for a double; keeps the memmove in bounds
        }
        memmove(b->limb + limbs, b->limb, (size_t)b->len * sizeof(uint32_t));
        memset(b->limb, 0, (size_t)limbs * sizeof(uint32_t));
        b->len += limbs;
    }
}

static int bigCompare(const KSBigInt *a, const KSBigInt *b)
{
    if (a->len != b->len) {
        return a->len < b->len ? -1 : 1;
    }
    for (int i = a->len - 1; i >= 0; i--) {
        if (a->limb[i] != b->limb[i]) {
            return a->limb[i] < b->limb[i] ? -1 : 1;
        }
    }
    return 0;
}

// a + b, compared against c: the termination tests need r + m+ against s
// without materializing the sum in a third buffer more than once.
static int bigCompareSum(const KSBigInt *a, const KSBigInt *b, const KSBigInt *c)
{
    KSBigInt sum = *a;
    const int len = b->len > sum.len ? b->len : sum.len;
    uint64_t carry = 0;
    for (int i = 0; i < len; i++) {
        uint64_t v = (uint64_t)(i < sum.len ? sum.limb[i] : 0) + (i < b->len ? b->limb[i] : 0) + carry;
        sum.limb[i] = (uint32_t)v;
        carry = v >> 32;
    }
    sum.len = len;
    if (carry != 0 && sum.len < KSBIG_LIMBS) {
        sum.limb[sum.len++] = (uint32_t)carry;
    }
    return bigCompare(&sum, c);
}

// a -= b, requiring a >= b.
static void bigSub(KSBigInt *a, const KSBigInt *b)
{
    int64_t borrow = 0;
    for (int i = 0; i < a->len; i++) {
        int64_t v = (int64_t)a->limb[i] - (i < b->len ? b->limb[i] : 0) - borrow;
        borrow = v < 0 ? 1 : 0;
        a->limb[i] = (uint32_t)(v + (borrow ? ((int64_t)1 << 32) : 0));
    }
    while (a->len > 0 && a->limb[a->len - 1] == 0) {
        a->len--;
    }
}

// r / s for a quotient known to be a single decimal digit, leaving the
// remainder in r.
static uint32_t bigDivDigit(KSBigInt *r, const KSBigInt *s)
{
    uint32_t quotient = 0;
    while (quotient < 9 && bigCompare(r, s) >= 0) {
        bigSub(r, s);
        quotient++;
    }
    return quotient;
}

static int bitLength(uint64_t v)
{
    int bits = 0;
    while (v != 0) {
        bits++;
        v >>= 1;
    }
    return bits;
}

// The shortest decimal digits that read back as exactly f * 2^e under
// round-to-nearest-even, for a binary format with `mantissaBits` bits of
// significand whose smallest exponent is `minExponent`. This is the classic
// free-format algorithm of Steele & White, in the Burger & Dybvig form: it
// generates digits from an exact integer scaling of the value and stops as soon
// as the digits so far lie inside the value's rounding interval. Writes the
// digits as ASCII, returns their count, and sets `*decimalPoint` so that the
// value is 0.d1d2...dn * 10^decimalPoint.
static int shortestDigits(uint64_t f, int e, int mantissaBits, int minExponent, char *digits, int *decimalPoint)
{
    const bool even = (f & 1) == 0;
    const uint64_t hiddenBit = (uint64_t)1 << (mantissaBits - 1);
    KSBigInt r, s, mPlus, mMinus;

    // Scale so that r/s == value and the rounding interval is [r-m-, r+m+]/s,
    // all integers. A significand that is exactly a power of two has a lower
    // neighbour twice as close, so its interval is asymmetric.
    if (e >= 0) {
        if (f != hiddenBit) {
            bigSetU64(&r, f);
            bigShiftLeft(&r, e + 1);
            bigSetU64(&s, 2);
            bigSetU64(&mPlus, 1);
            bigShiftLeft(&mPlus, e);
            mMinus = mPlus;
        } else {
            bigSetU64(&r, f);
            bigShiftLeft(&r, e + 2);
            bigSetU64(&s, 4);
            bigSetU64(&mPlus, 1);
            bigShiftLeft(&mPlus, e + 1);
            bigSetU64(&mMinus, 1);
            bigShiftLeft(&mMinus, e);
        }
    } else {
        if (e == minExponent || f != hiddenBit) {
            bigSetU64(&r, f);
            bigShiftLeft(&r, 1);
            bigSetU64(&s, 1);
            bigShiftLeft(&s, -e + 1);
            bigSetU64(&mPlus, 1);
            bigSetU64(&mMinus, 1);
        } else {
            bigSetU64(&r, f);
            bigShiftLeft(&r, 2);
            bigSetU64(&s, 1);
            bigShiftLeft(&s, -e + 2);
            bigSetU64(&mPlus, 2);
            bigSetU64(&mMinus, 1);
        }
    }

    // Estimate ceil(log10(value)); the fixup below corrects an estimate that
    // is one too low, which the small negative nudge makes the only error.
    int k = (int)ceil((double)(e + bitLength(f) - 1) * 0.30102999566398114 - 1e-10);
    if (k >= 0) {
        bigMulPow10(&s, k);
    } else {
        bigMulPow10(&r, -k);
        bigMulPow10(&mPlus, -k);
        bigMulPow10(&mMinus, -k);
    }
    // Too low: the first digit would be 10 or more.
    const int highTest = even ? 0 : 1;  // r + m+ >= s when even, > s otherwise
    if (bigCompareSum(&r, &mPlus, &s) >= highTest) {
        k++;
    } else {
        bigMulSmall(&r, 10);
        bigMulSmall(&mPlus, 10);
        bigMulSmall(&mMinus, 10);
    }

    int count = 0;
    for (;;) {
        uint32_t d = bigDivDigit(&r, &s);
        const bool low = even ? bigCompare(&r, &mMinus) <= 0 : bigCompare(&r, &mMinus) < 0;
        const bool high = bigCompareSum(&r, &mPlus, &s) >= highTest;
        if (!low && !high) {
            digits[count++] = (char)('0' + d);
            bigMulSmall(&r, 10);
            bigMulSmall(&mPlus, 10);
            bigMulSmall(&mMinus, 10);
            continue;
        }
        if (low && high) {
            // Both neighbours are in range: take the closer, rounding a tie up.
            KSBigInt twice = r;
            bigShiftLeft(&twice, 1);
            if (bigCompare(&twice, &s) >= 0) {
                d++;
            }
        } else if (high) {
            d++;
        }
        // A digit that rounded up to ten carries into the ones before it.
        int i = count;
        while (d == 10) {
            if (i == 0) {
                // Every digit so far was a nine: the value is a power of ten.
                digits[0] = '1';
                count = 1;
                k++;
                *decimalPoint = k;
                return count;
            }
            i--;
            d = (uint32_t)(digits[i] - '0') + 1;
            if (d < 10) {
                digits[i] = (char)('0' + d);
                count = i + 1;
                *decimalPoint = k;
                return count;
            }
        }
        digits[count++] = (char)('0' + d);
        break;
    }
    // Trailing zeros carry no information.
    while (count > 1 && digits[count - 1] == '0') {
        count--;
    }
    *decimalPoint = k;
    return count;
}

// Lay `count` digits with the decimal point after `decimalPoint` of them out
// the way the JSON writer always has: positional with at least one digit on
// either side of the point, or scientific with an explicit exponent sign once
// the exponent leaves [-4, sciThreshold).
static size_t layoutDigits(bool negative, const char *digits, int count, int decimalPoint, int sciThreshold, char *dst,
                           size_t bufSize)
{
    // Sign, up to 17 digits, a point, up to 4 leading zeros, "e", a sign and
    // three exponent digits fit with room to spare.
    char scratch[48];
    char *p = scratch;
    char *end = scratch + sizeof(scratch) - 1;
    const int exponent = decimalPoint - 1;  // d1.d2d3... * 10^exponent

    if (negative) {
        *p++ = '-';
    }
    if (exponent >= sciThreshold || exponent < -4) {
        *p++ = digits[0];
        if (count > 1) {
            *p++ = '.';
            for (int i = 1; i < count && p < end; i++) {
                *p++ = digits[i];
            }
        }
        if (p < end) *p++ = 'e';
        int absExponent = exponent;
        if (exponent < 0) {
            if (p < end) *p++ = '-';
            absExponent = -exponent;
        } else {
            if (p < end) *p++ = '+';
        }
        char expBuf[12];
        size_t elen = ksstring_intToDecimal(absExponent, expBuf, sizeof(expBuf));
        for (size_t i = 0; i < elen && p < end; i++) {
            *p++ = expBuf[i];
        }
    } else if (decimalPoint <= 0) {
        // 0.000ddd
        *p++ = '0';
        *p++ = '.';
        for (int i = 0; i < -decimalPoint && p < end; i++) {
            *p++ = '0';
        }
        for (int i = 0; i < count && p < end; i++) {
            *p++ = digits[i];
        }
    } else {
        // ddd.ddd, padding the integer part with zeros past the digits we have
        for (int i = 0; i < decimalPoint && p < end; i++) {
            *p++ = i < count ? digits[i] : '0';
        }
        if (p < end) *p++ = '.';
        if (decimalPoint < count) {
            for (int i = decimalPoint; i < count && p < end; i++) {
                *p++ = digits[i];
            }
        } else if (p < end) {
            *p++ = '0';
        }
    }

    *p = '\0';
    size_t scratchLen = (size_t)(p - scratch);
    // Copy scratch to dst with snprintf semantics: return the required length,
    // write at most bufSize-1 chars plus NUL.
    size_t writeLen = (scratchLen < bufSize) ? scratchLen : bufSize - 1;
    memcpy(dst, scratch, writeLen);
    dst[writeLen] = '\0';
    return scratchLen;
}

static size_t formatFloatingPoint(double value, bool isFloat, char *dst, size_t bufSize)
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

    // Take the value apart into an integer significand and a binary exponent.
    uint64_t significand;
    int exponent;
    int mantissaBits;
    int minExponent;
    int sciThreshold;
    if (isFloat) {
        float single = (float)value;
        uint32_t bits;
        memcpy(&bits, &single, sizeof(bits));
        uint32_t fraction = bits & 0x7fffffu;
        int biased = (int)((bits >> 23) & 0xffu);
        mantissaBits = 24;
        minExponent = -149;
        sciThreshold = FLT_DIG;
        if (biased == 0) {
            significand = fraction;
            exponent = minExponent;
        } else {
            significand = fraction | ((uint32_t)1 << 23);
            exponent = biased - 127 - 23;
        }
    } else {
        uint64_t bits;
        memcpy(&bits, &value, sizeof(bits));
        uint64_t fraction = bits & 0xfffffffffffffull;
        int biased = (int)((bits >> 52) & 0x7ffu);
        mantissaBits = 53;
        minExponent = -1074;
        sciThreshold = DBL_DIG;
        if (biased == 0) {
            significand = fraction;
            exponent = minExponent;
        } else {
            significand = fraction | ((uint64_t)1 << 52);
            exponent = biased - 1023 - 52;
        }
    }

    char digits[24];
    int decimalPoint = 0;
    int count = shortestDigits(significand, exponent, mantissaBits, minExponent, digits, &decimalPoint);
    return layoutDigits(signbit(value), digits, count, decimalPoint, sciThreshold, dst, bufSize);
}

size_t ksstring_doubleToString(double value, char *dst, size_t bufSize)
{
    // The digits are the shortest that read back as this exact double, and no
    // more: a fixed count either loses the low end (fifteen put an epoch
    // timestamp out by up to 84 minutes, and printed DBL_MAX as a number that
    // parses to infinity) or, past what a double carries, prints noise.
    return formatFloatingPoint(value, false, dst, bufSize);
}

size_t ksstring_floatToString(float value, char *dst, size_t bufSize)
{
    // The shortest digits that read back as this float, so 0.2f is "0.2", not
    // the 0.200000002980232 of its widening. Callers that know the value is a
    // float come here; everything else is a double and goes above.
    return formatFloatingPoint((double)value, true, dst, bufSize);
}
