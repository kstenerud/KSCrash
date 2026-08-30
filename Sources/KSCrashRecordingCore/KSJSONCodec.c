//
//  KSJSONCodec.c
//
//  Created by Karl Stenerud on 2012-01-07.
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

#include "KSJSONCodec.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <float.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "KSString.h"

// ============================================================================
#pragma mark - Configuration -
// ============================================================================

/** Set to 1 if you're also compiling KSLogger and want to use it here */
#ifndef KSJSONCODEC_UseKSLogger
#define KSJSONCODEC_UseKSLogger 1
#endif

#if KSJSONCODEC_UseKSLogger
#include "KSLogger.h"
#else
#define KSLOG_DEBUG(FMT, ...)
#endif

/** The work buffer size to use when escaping string values.
 * There's little reason to change this since nothing ever gets truncated.
 */
#ifndef KSJSONCODEC_WorkBufferSize
#define KSJSONCODEC_WorkBufferSize 512
#endif

// ============================================================================
#pragma mark - Helpers -
// ============================================================================

// Compiler hints for "if" statements
#define likely_if(x) if (__builtin_expect(x, 1))
#define unlikely_if(x) if (__builtin_expect(x, 0))

/** Used for writing hex string values. */
static char g_hexNybbles[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

const char *ksjson_stringForError(const int error)
{
    switch (error) {
        case KSJSON_ERROR_INVALID_CHARACTER:
            return "Invalid character";
        case KSJSON_ERROR_DATA_TOO_LONG:
            return "Data too long";
        case KSJSON_ERROR_CANNOT_ADD_DATA:
            return "Cannot add data";
        case KSJSON_ERROR_INCOMPLETE:
            return "Incomplete data";
        case KSJSON_ERROR_INVALID_DATA:
            return "Invalid data";
        default:
            return "(unknown error)";
    }
}

// ============================================================================
#pragma mark - Encode -
// ============================================================================

/** Add JSON encoded data to an external handler.
 * The external handler will decide how to handle the data (store/transmit/etc).
 *
 * @param context The encoding context.
 *
 * @param data The encoded data.
 *
 * @param length The length of the data.
 *
 * @return KSJSON_OK if the data was handled successfully.
 */
#define addJSONData(CONTEXT, DATA, LENGTH) (CONTEXT)->addJSONData(DATA, LENGTH, (CONTEXT)->userData)

/** Escape a string portion for use with JSON and send to data handler.
 *
 * @param context The JSON context.
 *
 * @param string The string to escape and write.
 *
 * @param length The length of the string.
 *
 * @return KSJSON_OK if the data was handled successfully.
 */
static int appendEscapedString(KSJSONEncodeContext *const context, const char *restrict const string, int length)
{
    char workBuffer[KSJSONCODEC_WorkBufferSize];
    const char *const srcEnd = string + length;

    const char *restrict src = string;
    char *restrict dst = workBuffer;

    // Simple case (no escape or special characters)
    for (; src < srcEnd && *src != '\\' && *src != '\"' && (unsigned char)*src >= ' '; src++) {
        *dst++ = *src;
    }

    // Deal with complicated case (if any)
    for (; src < srcEnd; src++) {
        switch (*src) {
            case '\\':
            case '\"':
                *dst++ = '\\';
                *dst++ = *src;
                break;
            case '\b':
                *dst++ = '\\';
                *dst++ = 'b';
                break;
            case '\f':
                *dst++ = '\\';
                *dst++ = 'f';
                break;
            case '\n':
                *dst++ = '\\';
                *dst++ = 'n';
                break;
            case '\r':
                *dst++ = '\\';
                *dst++ = 'r';
                break;
            case '\t':
                *dst++ = '\\';
                *dst++ = 't';
                break;
            default:
                unlikely_if((unsigned char)*src < ' ')
                {
                    KSLOG_DEBUG("Invalid character 0x%02x in string: %s", *src, string);
                    return KSJSON_ERROR_INVALID_CHARACTER;
                }
                *dst++ = *src;
        }
    }
    int encLength = (int)(dst - workBuffer);
    dst -= encLength;
    return addJSONData(context, dst, encLength);
}

/** Escape a string for use with JSON and send to data handler.
 *
 * @param context The JSON context.
 *
 * @param string The string to escape and write.
 *
 * @param length The length of the string.
 *
 * @return KSJSON_OK if the data was handled successfully.
 */
static int addEscapedString(KSJSONEncodeContext *const context, const char *restrict const string, int length)
{
    int result = KSJSON_OK;

    // Keep adding portions until the whole string has been processed.
    int offset = 0;
    while (offset < length) {
        int toAdd = length - offset;
        unlikely_if(toAdd > KSJSONCODEC_WorkBufferSize / 2) { toAdd = KSJSONCODEC_WorkBufferSize / 2; }
        result = appendEscapedString(context, string + offset, toAdd);
        unlikely_if(result != KSJSON_OK) { break; }
        offset += toAdd;
    }
    return result;
}

/** Escape and quote a string for use with JSON and send to data handler.
 *
 * @param context The JSON context.
 *
 * @param string The string to escape and write.
 *
 * @param length The length of the string.
 *
 * @return KSJSON_OK if the data was handled successfully.
 */
static int addQuotedEscapedString(KSJSONEncodeContext *const context, const char *restrict const string, int length)
{
    int result;
    unlikely_if((result = addJSONData(context, "\"", 1)) != KSJSON_OK) { return result; }
    result = addEscapedString(context, string, length);

    // Always close string, even if we failed to write its content
    int closeResult = addJSONData(context, "\"", 1);

    return result || closeResult;
}

/** Check the result of snprintf and handle error cases.
 *
 * @param written The return value from snprintf.
 * @param buffSize The size of the buffer passed to snprintf.
 * @param bytesWritten Pointer to store the number of bytes written.
 * @return KSJSON_OK if successful, or an error code.
 */
static int checkWriteResult(int written, size_t buffSize, int *bytesWritten)
{
    if (written < 0) {
        // An encoding error occurred
        return KSJSON_ERROR_INVALID_CHARACTER;
    } else if (written >= (int)buffSize) {
        // The number was too long to fit in the buffer
        // Note: In this case, buffer is still null-terminated, but truncated
        return KSJSON_ERROR_DATA_TOO_LONG;
    }
    *bytesWritten = written;
    return KSJSON_OK;
}

/** Format a double value to a string buffer.
 *
 * @param buff The buffer to write to.
 * @param buffSize The size of the buffer.
 * @param value The double value to format.
 * @param bytesWritten Pointer to store the number of bytes written.
 * @return KSJSON_OK if successful, or an error code.
 */
static int formatDouble(char *buff, size_t buffSize, double value, int *bytesWritten)
{
    int written = (int)ksstring_doubleToString(value, buff, buffSize);
    return checkWriteResult(written, buffSize, bytesWritten);
}

/** Format an int64_t value to a string buffer.
 *
 * @param buff The buffer to write to.
 * @param buffSize The size of the buffer.
 * @param value The int64_t value to format.
 * @param bytesWritten Pointer to store the number of bytes written.
 * @return KSJSON_OK if successful, or an error code.
 */
static int formatInt64(char *buff, size_t buffSize, int64_t value, int *bytesWritten)
{
    int written = (int)ksstring_int64ToDecimal(value, buff, buffSize);
    return checkWriteResult(written, buffSize, bytesWritten);
}

/** Format a uint64_t value to a string buffer.
 *
 * @param buff The buffer to write to.
 * @param buffSize The size of the buffer.
 * @param value The uint64_t value to format.
 * @param bytesWritten Pointer to store the number of bytes written.
 * @return KSJSON_OK if successful, or an error code.
 */
static int formatUint64(char *buff, size_t buffSize, uint64_t value, int *bytesWritten)
{
    int written = (int)ksstring_uint64ToDecimal(value, buff, buffSize);
    return checkWriteResult(written, buffSize, bytesWritten);
}

/** Add a formatted number to the JSON encoding context.
 *
 * @param context The JSON encoding context.
 * @param name The name of the element.
 * @param buff The buffer containing the formatted number.
 * @param written The number of characters in the formatted number.
 * @return KSJSON_OK if successful, or an error code.
 */
static int addFormattedNumber(KSJSONEncodeContext *const context, const char *const name, const char *buff, int written)
{
    int result = ksjson_beginElement(context, name);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addJSONData(context, buff, written);
}

int ksjson_beginElement(KSJSONEncodeContext *const context, const char *const name)
{
    int result = KSJSON_OK;

    // Decide if a comma is warranted.
    unlikely_if(context->containerFirstEntry) { context->containerFirstEntry = false; }
    else
    {
        unlikely_if((result = addJSONData(context, ",", 1)) != KSJSON_OK) { return result; }
    }

    // Pretty printing
    unlikely_if(context->prettyPrint && context->containerLevel > 0)
    {
        unlikely_if((result = addJSONData(context, "\n", 1)) != KSJSON_OK) { return result; }
        for (int i = 0; i < context->containerLevel; i++) {
            unlikely_if((result = addJSONData(context, "    ", 4)) != KSJSON_OK) { return result; }
        }
    }

    // Add a name field if we're in an object.
    if (context->isObject[context->containerLevel]) {
        unlikely_if(name == NULL)
        {
            KSLOG_DEBUG("Name was null inside an object");
            return KSJSON_ERROR_INVALID_DATA;
        }
        unlikely_if((result = addQuotedEscapedString(context, name, (int)strlen(name))) != KSJSON_OK) { return result; }
        unlikely_if(context->prettyPrint)
        {
            unlikely_if((result = addJSONData(context, ": ", 2)) != KSJSON_OK) { return result; }
        }
        else
        {
            unlikely_if((result = addJSONData(context, ":", 1)) != KSJSON_OK) { return result; }
        }
    }
    return result;
}

int ksjson_addRawJSONData(KSJSONEncodeContext *const context, const char *const data, const int length)
{
    return addJSONData(context, data, length);
}

int ksjson_addBooleanElement(KSJSONEncodeContext *const context, const char *const name, const bool value)
{
    int result = ksjson_beginElement(context, name);
    unlikely_if(result != KSJSON_OK) { return result; }
    if (value) {
        return addJSONData(context, "true", 4);
    } else {
        return addJSONData(context, "false", 5);
    }
}

int ksjson_addFloatingPointElement(KSJSONEncodeContext *const context, const char *const name, double value)
{
    char buff[64];
    int bytesWritten = 0;
    int result = formatDouble(buff, sizeof(buff), value, &bytesWritten);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addFormattedNumber(context, name, buff, bytesWritten);
}

int ksjson_addFloatElement(KSJSONEncodeContext *const context, const char *const name, float value)
{
    char buff[64];
    int written = (int)ksstring_floatToString(value, buff, sizeof(buff));
    int bytesWritten = 0;
    int result = checkWriteResult(written, sizeof(buff), &bytesWritten);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addFormattedNumber(context, name, buff, bytesWritten);
}

int ksjson_addIntegerElement(KSJSONEncodeContext *const context, const char *const name, int64_t value)
{
    char buff[21];
    int bytesWritten = 0;
    int result = formatInt64(buff, sizeof(buff), value, &bytesWritten);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addFormattedNumber(context, name, buff, bytesWritten);
}

int ksjson_addUIntegerElement(KSJSONEncodeContext *const context, const char *const name, uint64_t value)
{
    char buff[21];
    int bytesWritten = 0;
    int result = formatUint64(buff, sizeof(buff), value, &bytesWritten);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addFormattedNumber(context, name, buff, bytesWritten);
}

int ksjson_addNullElement(KSJSONEncodeContext *const context, const char *const name)
{
    int result = ksjson_beginElement(context, name);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addJSONData(context, "null", 4);
}

int ksjson_addStringElement(KSJSONEncodeContext *const context, const char *const name, const char *const value,
                            int length)
{
    unlikely_if(value == NULL) { return ksjson_addNullElement(context, name); }
    int result = ksjson_beginElement(context, name);
    unlikely_if(result != KSJSON_OK) { return result; }
    if (length == KSJSON_SIZE_AUTOMATIC) {
        length = (int)strlen(value);
    }
    return addQuotedEscapedString(context, value, length);
}

int ksjson_beginStringElement(KSJSONEncodeContext *const context, const char *const name)
{
    int result = ksjson_beginElement(context, name);
    unlikely_if(result != KSJSON_OK) { return result; }
    return addJSONData(context, "\"", 1);
}

int ksjson_appendStringElement(KSJSONEncodeContext *const context, const char *const value, int length)
{
    return addEscapedString(context, value, length);
}

int ksjson_endStringElement(KSJSONEncodeContext *const context) { return addJSONData(context, "\"", 1); }

int ksjson_addDataElement(KSJSONEncodeContext *const context, const char *name, const char *value, int length)
{
    int result = KSJSON_OK;
    result = ksjson_beginDataElement(context, name);
    if (result == KSJSON_OK) {
        result = ksjson_appendDataElement(context, value, length);
    }
    if (result == KSJSON_OK) {
        result = ksjson_endDataElement(context);
    }
    return result;
}

int ksjson_beginDataElement(KSJSONEncodeContext *const context, const char *const name)
{
    return ksjson_beginStringElement(context, name);
}

int ksjson_appendDataElement(KSJSONEncodeContext *const context, const char *const value, int length)
{
    unsigned char *currentByte = (unsigned char *)value;
    unsigned char *end = currentByte + length;
    char chars[2];
    int result = KSJSON_OK;
    while (currentByte < end) {
        chars[0] = g_hexNybbles[(*currentByte >> 4) & 15];
        chars[1] = g_hexNybbles[*currentByte & 15];
        result = addJSONData(context, chars, sizeof(chars));
        if (result != KSJSON_OK) {
            break;
        }
        currentByte++;
    }
    return result;
}

int ksjson_endDataElement(KSJSONEncodeContext *const context) { return ksjson_endStringElement(context); }

int ksjson_beginArray(KSJSONEncodeContext *const context, const char *const name)
{
    // isObject[] is indexed by containerLevel, so refuse rather than run off the end.
    unlikely_if(context->containerLevel + 1 >= KSJSON_MAX_CONTAINER_DEPTH) { return KSJSON_ERROR_DATA_TOO_LONG; }

    likely_if(context->containerLevel >= 0)
    {
        int result = ksjson_beginElement(context, name);
        unlikely_if(result != KSJSON_OK) { return result; }
    }

    context->containerLevel++;
    context->isObject[context->containerLevel] = false;
    context->containerFirstEntry = true;

    return addJSONData(context, "[", 1);
}

int ksjson_beginObject(KSJSONEncodeContext *const context, const char *const name)
{
    // isObject[] is indexed by containerLevel, so refuse rather than run off the end.
    unlikely_if(context->containerLevel + 1 >= KSJSON_MAX_CONTAINER_DEPTH) { return KSJSON_ERROR_DATA_TOO_LONG; }

    likely_if(context->containerLevel >= 0)
    {
        int result = ksjson_beginElement(context, name);
        unlikely_if(result != KSJSON_OK) { return result; }
    }

    context->containerLevel++;
    context->isObject[context->containerLevel] = true;
    context->containerFirstEntry = true;

    return addJSONData(context, "{", 1);
}

int ksjson_endContainer(KSJSONEncodeContext *const context)
{
    unlikely_if(context->containerLevel <= 0) { return KSJSON_OK; }

    bool isObject = context->isObject[context->containerLevel];
    context->containerLevel--;

    // Pretty printing
    unlikely_if(context->prettyPrint && !context->containerFirstEntry)
    {
        int result;
        unlikely_if((result = addJSONData(context, "\n", 1)) != KSJSON_OK) { return result; }
        for (int i = 0; i < context->containerLevel; i++) {
            unlikely_if((result = addJSONData(context, "    ", 4)) != KSJSON_OK) { return result; }
        }
    }
    context->containerFirstEntry = false;
    return addJSONData(context, isObject ? "}" : "]", 1);
}

void ksjson_beginEncode(KSJSONEncodeContext *const context, bool prettyPrint, KSJSONAddDataFunc addJSONDataFunc,
                        void *const userData)
{
    memset(context, 0, sizeof(*context));
    context->addJSONData = addJSONDataFunc;
    context->userData = userData;
    context->prettyPrint = prettyPrint;
    context->containerFirstEntry = true;
}

int ksjson_endEncode(KSJSONEncodeContext *const context)
{
    int result = KSJSON_OK;
    while (context->containerLevel > 0) {
        unlikely_if((result = ksjson_endContainer(context)) != KSJSON_OK) { return result; }
    }
    return result;
}

// ============================================================================
#pragma mark - Decode -
// ============================================================================

#define INV 0x11111

struct KSJSONDecodeContext;

/** Pull more data into the decode window. See requestMoreData(). */
typedef int (*KSJSONRefillFunc)(struct KSJSONDecodeContext *context, const char *preserveFrom);

typedef struct KSJSONDecodeContext {
    /** Pointer to current work area in the buffer. */
    const char *bufferPtr;
    /** Pointer to the end of the buffer. */
    const char *bufferEnd;
    /** Pointer to a buffer for storing a decoded name. */
    char *nameBuffer;
    /** Length of the name buffer. */
    int nameBufferLength;
    /** Pointer to a buffer for storing a decoded string. */
    char *stringBuffer;
    /** Length of the string buffer. */
    int stringBufferLength;
    /** True when bufferEnd is the end of the data itself rather than the end of a window
     * onto more of it. A number has no closing delimiter, so this is what separates "the
     * number ends here" from "read more before deciding". */
    bool bufferEndIsEOF;
    /** Pulls more data into the window, or NULL when the data is all in memory. Set by
     * whoever owns the buffer, since only they know where the rest of it lives. */
    KSJSONRefillFunc refill;
    /** The callbacks to call while decoding. */
    KSJSONDecodeCallbacks *const callbacks;
    /** Data that was specified when calling ksjson_decode(). */
    void *userData;
    /** Containers currently open. decodeElement recurses per level, so this
     *  is what keeps a deeply nested document from overflowing the stack; it
     *  also keeps the decoder from accepting documents the encoder could not
     *  write back out. */
    int containerDepth;
} KSJSONDecodeContext;

/** Ask for more data when an element runs past the end of the window.
 *
 * Everything from the current position onward is kept and moved to the front, so an element
 * straddling a window boundary can be rescanned from its start once the rest arrives.
 *
 * @return KSJSON_OK if the window changed at all, which includes learning that the data has
 *         ended. KSJSON_ERROR_INCOMPLETE if there is nothing more to read.
 *         KSJSON_ERROR_DATA_TOO_LONG if what must be preserved already fills the window.
 */
static int requestMoreData(KSJSONDecodeContext *context)
{
    unlikely_if(context->bufferEndIsEOF || context->refill == NULL) { return KSJSON_ERROR_INCOMPLETE; }
    return context->refill(context, context->bufferPtr);
}

/** Skip whitespace, pulling in more data whenever the window runs out while doing it.
 *
 * Whitespace is the one thing that can consume a whole window without any element being
 * parsed, so a file with enough leading space would otherwise look truncated before the
 * decoder ever asked for the rest of it.
 */
static void skipWhitespace(KSJSONDecodeContext *context)
{
    for (;;) {
        while (context->bufferPtr < context->bufferEnd && isspace((unsigned char)*context->bufferPtr)) {
            context->bufferPtr++;
        }
        if (context->bufferPtr < context->bufferEnd || requestMoreData(context) != KSJSON_OK) {
            return;
        }
    }
}

/** Make sure at least `count` bytes are in the window, for elements whose length is known
 * up front. Anything scanned to an unknown length refills from its own start instead.
 *
 * @return false if the data ended before that many bytes were available.
 */
static bool ensureBuffered(KSJSONDecodeContext *context, const int count)
{
    while (context->bufferEnd - context->bufferPtr < count) {
        unlikely_if(requestMoreData(context) != KSJSON_OK) { return false; }
    }
    return true;
}

/** Anything that may legally follow a JSON value. A number has no closing delimiter of its
 * own, so this is the only thing separating "1" from the first half of "1x".
 */
static bool isJSONValueDelimiter(const char ch)
{
    return isspace((unsigned char)ch) || ch == ',' || ch == ']' || ch == '}';
}

/** Skip trailing whitespace and require that nothing else follows.
 *
 * Without this a payload is only ever as valid as its first element, so "1 2", "truejunk"
 * and "{}[]" would all pass by decoding the part that parses and ignoring the rest.
 */
static int requireEndOfData(KSJSONDecodeContext *context)
{
    skipWhitespace(context);
    unlikely_if(context->bufferPtr < context->bufferEnd)
    {
        KSLOG_DEBUG("Trailing data after the top level element");
        return KSJSON_ERROR_INVALID_CHARACTER;
    }
    return KSJSON_OK;
}

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

/** Encode a UTF-16 character to UTF-8. The dest pointer gets incremented
 * by however many bytes were needed for the conversion (1-4).
 *
 * @param character The UTF-16 character.
 *
 * @param dst Where to write the UTF-8 character.
 *
 * @return KSJSON_OK if the encoding was successful.
 */
static int writeUTF8(unsigned int character, char **dst);

/** Decode a string value.
 *
 * @param context The decoding context.
 *
 * @param dstBuffer Buffer to hold the decoded string.
 *
 * @param dstBufferLength Length of the destination buffer.
 *
 * @return KSJSON_OK if successful.
 */
static int decodeString(KSJSONDecodeContext *context, char *dstBuffer, int dstBufferLength);

/** Decode a JSON element.
 *
 * @param name This element's name (or NULL if it has none).
 *
 * @param context The decoding context.
 *
 * @return KSJSON_OK if successful.
 */
static int decodeElement(const char *const name, KSJSONDecodeContext *context);

static int decodeNumber(const char *const name, KSJSONDecodeContext *context, const int sign);

static int writeUTF8(unsigned int character, char **dst)
{
    likely_if(character <= 0x7f)
    {
        **dst = (char)character;
        (*dst)++;
        return KSJSON_OK;
    }
    if (character <= 0x7ff) {
        (*dst)[0] = (char)(0xc0 | (character >> 6));
        (*dst)[1] = (char)(0x80 | (character & 0x3f));
        *dst += 2;
        return KSJSON_OK;
    }
    if (character <= 0xffff) {
        (*dst)[0] = (char)(0xe0 | (character >> 12));
        (*dst)[1] = (char)(0x80 | ((character >> 6) & 0x3f));
        (*dst)[2] = (char)(0x80 | (character & 0x3f));
        *dst += 3;
        return KSJSON_OK;
    }
    // RFC3629 restricts UTF-8 to end at 0x10ffff.
    if (character <= 0x10ffff) {
        (*dst)[0] = (char)(0xf0 | (character >> 18));
        (*dst)[1] = (char)(0x80 | ((character >> 12) & 0x3f));
        (*dst)[2] = (char)(0x80 | ((character >> 6) & 0x3f));
        (*dst)[3] = (char)(0x80 | (character & 0x3f));
        *dst += 4;
        return KSJSON_OK;
    }

    // If we get here, the character cannot be converted to valid UTF-8.
    KSLOG_DEBUG("Invalid unicode: 0x%04x", character);
    return KSJSON_ERROR_INVALID_CHARACTER;
}

static int decodeString(KSJSONDecodeContext *context, char *dstBuffer, int dstBufferLength)
{
    *dstBuffer = '\0';
    unlikely_if(*context->bufferPtr != '\"')
    {
        KSLOG_DEBUG("Expected '\"' but got '%c'", *context->bufferPtr);
        return KSJSON_ERROR_INVALID_CHARACTER;
    }

    // The closing quote is at an unknown distance, so when the window runs out before it
    // turns up, pull more in and scan the whole string again from its opening quote.
    // Refilling moves the string to the front, so bufferPtr stays valid across the retry.
    const char *srcEnd = NULL;
    bool fastCopy = true;
    for (;;) {
        const char *src = context->bufferPtr + 1;
        fastCopy = true;
        for (; src < context->bufferEnd && *src != '\"'; src++) {
            unlikely_if(*src == '\\')
            {
                fastCopy = false;
                src++;
            }
        }
        likely_if(src < context->bufferEnd)
        {
            srcEnd = src;
            break;
        }

        const int result = requestMoreData(context);
        unlikely_if(result == KSJSON_ERROR_INCOMPLETE)
        {
            KSLOG_DEBUG("Premature end of data");
            return KSJSON_ERROR_INCOMPLETE;
        }
        unlikely_if(result != KSJSON_OK) { return result; }
    }

    const char *src = context->bufferPtr + 1;
    int length = (int)(srcEnd - src);
    // With no escapes the source span is exactly what it decodes to, so this is the limit
    // itself. With escapes the source is longer than the value, and charging the source
    // would refuse values that do fit, so the unescape loop below measures its own output.
    if (fastCopy && length >= dstBufferLength) {
        KSLOG_DEBUG("String is too long");
        return KSJSON_ERROR_DATA_TOO_LONG;
    }

    context->bufferPtr = srcEnd + 1;

    // If no escape characters were encountered, we can fast copy.
    likely_if(fastCopy)
    {
        memcpy(dstBuffer, src, (size_t)length);
        dstBuffer[length] = 0;
        return KSJSON_OK;
    }

    char *dst = dstBuffer;
    // One byte held back for the terminator, so a write is in bounds while dst < dstEnd.
    // Room is always compared by subtracting, never by forming dst + width, which could
    // point past the end of the buffer.
    char *const dstEnd = dstBuffer + dstBufferLength - 1;

    for (; src < srcEnd; src++) {
        unlikely_if(dstEnd - dst < 1)
        {
            KSLOG_DEBUG("String is too long");
            return KSJSON_ERROR_DATA_TOO_LONG;
        }
        likely_if(*src != '\\') { *dst++ = *src; }
        else
        {
            src++;
            switch (*src) {
                case '"':
                    *dst++ = '\"';
                    continue;
                case '\\':
                    *dst++ = '\\';
                    continue;
                case 'n':
                    *dst++ = '\n';
                    continue;
                case 'r':
                    *dst++ = '\r';
                    continue;
                case '/':
                    *dst++ = '/';
                    continue;
                case 't':
                    *dst++ = '\t';
                    continue;
                case 'b':
                    *dst++ = '\b';
                    continue;
                case 'f':
                    *dst++ = '\f';
                    continue;
                case 'u': {
                    unlikely_if(src + 5 > srcEnd)
                    {
                        KSLOG_DEBUG("Premature end of data");
                        return KSJSON_ERROR_INCOMPLETE;
                    }
                    unsigned int accum = g_hexConversion[(unsigned)src[1]] << 12 |
                                         g_hexConversion[(unsigned)src[2]] << 8 |
                                         g_hexConversion[(unsigned)src[3]] << 4 | g_hexConversion[(unsigned)src[4]];
                    unlikely_if(accum > 0xffff)
                    {
                        KSLOG_DEBUG("Invalid unicode sequence: %c%c%c%c", src[1], src[2], src[3], src[4]);
                        return KSJSON_ERROR_INVALID_CHARACTER;
                    }

                    // UTF-16 Trail surrogate on its own.
                    unlikely_if(accum >= 0xdc00 && accum <= 0xdfff)
                    {
                        KSLOG_DEBUG("Unexpected trail surrogate: 0x%04x", accum);
                        return KSJSON_ERROR_INVALID_CHARACTER;
                    }

                    // UTF-16 Lead surrogate.
                    unlikely_if(accum >= 0xd800 && accum <= 0xdbff)
                    {
                        // Fetch trail surrogate.
                        unlikely_if(src + 11 > srcEnd)
                        {
                            KSLOG_DEBUG("Premature end of data");
                            return KSJSON_ERROR_INCOMPLETE;
                        }
                        unlikely_if(src[5] != '\\' || src[6] != 'u')
                        {
                            KSLOG_DEBUG("Expected \"\\u\" but got: \"%c%c\"", src[5], src[6]);
                            return KSJSON_ERROR_INVALID_CHARACTER;
                        }
                        src += 6;
                        unsigned int accum2 =
                            g_hexConversion[(unsigned)src[1]] << 12 | g_hexConversion[(unsigned)src[2]] << 8 |
                            g_hexConversion[(unsigned)src[3]] << 4 | g_hexConversion[(unsigned)src[4]];
                        unlikely_if(accum2 < 0xdc00 || accum2 > 0xdfff)
                        {
                            KSLOG_DEBUG("Invalid trail surrogate: 0x%04x", accum2);
                            return KSJSON_ERROR_INVALID_CHARACTER;
                        }
                        // And combine 20 bit result.
                        // The pair encodes the code point biased down by 0x10000, which is
                        // why the surrogate range can cover the whole astral plane in 20
                        // bits. Leaving the bias off turns every emoji into an unrelated
                        // character in the private use area.
                        accum = 0x10000 + (((accum - 0xd800) << 10) | (accum2 - 0xdc00));
                    }

                    // Charge the code point what it actually costs. The check at the top of
                    // the loop only accounted for one byte, and reserving the widest
                    // encoding for every escape would refuse values that do fit.
                    const ptrdiff_t utf8Width = accum < 0x80 ? 1 : accum < 0x800 ? 2 : accum < 0x10000 ? 3 : 4;
                    unlikely_if(dstEnd - dst < utf8Width)
                    {
                        KSLOG_DEBUG("String is too long");
                        return KSJSON_ERROR_DATA_TOO_LONG;
                    }
                    int result = writeUTF8(accum, &dst);
                    unlikely_if(result != KSJSON_OK) { return result; }
                    src += 4;
                    continue;
                }
                default:
                    KSLOG_DEBUG("Invalid control character '%c'", *src);
                    return KSJSON_ERROR_INVALID_CHARACTER;
            }
        }
    }

    *dst = 0;
    return KSJSON_OK;
}

/** How a number token ended. */
typedef enum {
    /** A whole number, correctly delimited. */
    NumberScan_Complete,
    /** The window ran out mid-token; more data would settle it. */
    NumberScan_NeedsMoreData,
    /** The data ran out mid-token. */
    NumberScan_Truncated,
    /** Not a number, or not one JSON accepts. */
    NumberScan_Invalid,
} NumberScanResult;

/** Match a number against the JSON grammar without converting or consuming it:
 *
 *     -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
 *
 * The sign is the caller's, already consumed. Every place the scan can run out of window is
 * reported separately from running out of data, because only the second one ends a number:
 * a number has no closing delimiter, so the end of a file window says nothing about whether
 * more digits follow.
 *
 * @param outEnd Set to one past the last character of the token.
 * @param outIsInteger Set false if a fraction or exponent means it cannot be one.
 */
static NumberScanResult scanNumberToken(const KSJSONDecodeContext *const context, const char **outEnd,
                                        bool *outIsInteger)
{
    const char *ptr = context->bufferPtr;
    const char *const end = context->bufferEnd;
    bool isInteger = true;
    // Whether the token would be whole if the data stopped right here.
    bool completeAtEnd = false;

#define NUMBER_RAN_OUT()                                               \
    do {                                                               \
        if (!context->bufferEndIsEOF) return NumberScan_NeedsMoreData; \
        if (!completeAtEnd) return NumberScan_Truncated;               \
        *outEnd = ptr;                                                 \
        *outIsInteger = isInteger;                                     \
        return NumberScan_Complete;                                    \
    } while (0)

    if (ptr >= end) NUMBER_RAN_OUT();
    if (!isdigit((unsigned char)*ptr)) return NumberScan_Invalid;

    // Integer part: a lone zero, or a non-zero digit and whatever follows it.
    if (*ptr == '0') {
        ptr++;
        if (ptr < end && isdigit((unsigned char)*ptr)) return NumberScan_Invalid;
    } else {
        while (ptr < end && isdigit((unsigned char)*ptr)) {
            ptr++;
        }
    }
    completeAtEnd = true;
    if (ptr >= end) NUMBER_RAN_OUT();

    // Fraction: '.' must be followed by at least one digit.
    if (*ptr == '.') {
        isInteger = false;
        completeAtEnd = false;
        ptr++;
        if (ptr >= end) NUMBER_RAN_OUT();
        if (!isdigit((unsigned char)*ptr)) return NumberScan_Invalid;
        while (ptr < end && isdigit((unsigned char)*ptr)) {
            ptr++;
        }
        completeAtEnd = true;
        if (ptr >= end) NUMBER_RAN_OUT();
    }

    // Exponent: 'e' must be followed by an optional sign and at least one digit.
    if (*ptr == 'e' || *ptr == 'E') {
        isInteger = false;
        completeAtEnd = false;
        ptr++;
        if (ptr >= end) NUMBER_RAN_OUT();
        if (*ptr == '+' || *ptr == '-') {
            ptr++;
            if (ptr >= end) NUMBER_RAN_OUT();
        }
        if (!isdigit((unsigned char)*ptr)) return NumberScan_Invalid;
        while (ptr < end && isdigit((unsigned char)*ptr)) {
            ptr++;
        }
        completeAtEnd = true;
        if (ptr >= end) NUMBER_RAN_OUT();
    }

#undef NUMBER_RAN_OUT

    // Something follows, and it has to be something a value may be followed by, or this is
    // the leading part of a longer piece of nonsense such as "1x" or "1.2.3".
    if (!isJSONValueDelimiter(*ptr)) return NumberScan_Invalid;

    *outEnd = ptr;
    *outIsInteger = isInteger;
    return NumberScan_Complete;
}

/** Decode a JSON number.
 *
 * sscanf stops at the first character it cannot use, so it would read "1e" as 1 and "1.2.3"
 * as 1.2 rather than rejecting either. Nothing reaches it until the whole token has matched
 * the grammar.
 *
 * @param sign Already consumed by the caller, along with the '-' it came from.
 */
static int decodeNumber(const char *const name, KSJSONDecodeContext *context, const int sign)
{
    const char *tokenEnd = NULL;
    bool isInteger = true;

    for (bool scanned = false; !scanned;) {
        switch (scanNumberToken(context, &tokenEnd, &isInteger)) {
            case NumberScan_Complete:
                scanned = true;
                break;
            case NumberScan_Invalid:
                KSLOG_DEBUG("Not a valid number");
                return KSJSON_ERROR_INVALID_CHARACTER;
            case NumberScan_Truncated:
                KSLOG_DEBUG("Premature end of number");
                return KSJSON_ERROR_INCOMPLETE;
            case NumberScan_NeedsMoreData:
            default: {
                // Refilling moves the token to the front of the window, so the next scan
                // starts from bufferPtr again rather than from anything cached here.
                const int result = requestMoreData(context);
                unlikely_if(result != KSJSON_OK) { return result; }
                break;
            }
        }
    }

    const char *const start = context->bufferPtr;
    const int length = (int)(tokenEnd - start);
    context->bufferPtr = tokenEnd;

    if (isInteger) {
        uint64_t accum = 0;
        bool isOverflow = false;
        for (const char *digit = start; digit < tokenEnd; digit++) {
            const uint64_t nextDigit = (uint64_t)(*digit - '0');
            unlikely_if((isOverflow = accum > (ULLONG_MAX / 10))) { break; }
            accum *= 10;
            unlikely_if((isOverflow = accum > (ULLONG_MAX - nextDigit))) { break; }
            accum += nextDigit;
        }

        if (!isOverflow) {
            if (sign > 0) {
                if (accum <= (uint64_t)LLONG_MAX) {
                    return context->callbacks->onIntegerElement(name, (int64_t)accum, context->userData);
                }
                return context->callbacks->onUnsignedIntegerElement(name, accum, context->userData);
            }
            if (accum <= ((uint64_t)LLONG_MAX + 1)) {
                const int64_t signedAccum = accum == ((uint64_t)LLONG_MAX + 1) ? LLONG_MIN : -(int64_t)accum;
                return context->callbacks->onIntegerElement(name, signedAccum, context->userData);
            }
        }
        // Too big for either integer type, so take it as floating point instead.
    }

    // The buffer is not necessarily NULL-terminated, so copy the validated token out before
    // handing it to sscanf.
    unlikely_if(length >= context->stringBufferLength)
    {
        KSLOG_DEBUG("Number is too long.");
        return KSJSON_ERROR_DATA_TOO_LONG;
    }
    memcpy(context->stringBuffer, start, (size_t)length);
    context->stringBuffer[length] = '\0';

    double value;
    sscanf(context->stringBuffer, "%lg", &value);
    value *= sign;
    return context->callbacks->onFloatingPointElement(name, value, context->userData);
}

static int decodeElement(const char *const name, KSJSONDecodeContext *context)
{
    skipWhitespace(context);
    unlikely_if(context->bufferPtr >= context->bufferEnd)
    {
        KSLOG_DEBUG("Premature end of data");
        return KSJSON_ERROR_INCOMPLETE;
    }

    int sign = 1;
    int result;

    switch (*context->bufferPtr) {
        case '[': {
            unlikely_if(context->containerDepth + 1 >= KSJSON_MAX_CONTAINER_DEPTH)
            {
                KSLOG_DEBUG("Too many nested containers");
                return KSJSON_ERROR_DATA_TOO_LONG;
            }
            context->containerDepth++;
            context->bufferPtr++;
            result = context->callbacks->onBeginArray(name, context->userData);
            unlikely_if(result != KSJSON_OK) return result;
            while (context->bufferPtr < context->bufferEnd) {
                skipWhitespace(context);
                unlikely_if(context->bufferPtr >= context->bufferEnd) { break; }
                unlikely_if(*context->bufferPtr == ']')
                {
                    context->bufferPtr++;
                    context->containerDepth--;
                    return context->callbacks->onEndContainer(context->userData);
                }
                result = decodeElement(NULL, context);
                unlikely_if(result != KSJSON_OK) return result;
                skipWhitespace(context);
                unlikely_if(context->bufferPtr >= context->bufferEnd) { break; }
                likely_if(*context->bufferPtr == ',') { context->bufferPtr++; }
                else unlikely_if(*context->bufferPtr != ']')
                {
                    KSLOG_DEBUG("Expected ',' or ']' but got '%c'", *context->bufferPtr);
                    return KSJSON_ERROR_INVALID_CHARACTER;
                }
            }
            KSLOG_DEBUG("Premature end of data");
            return KSJSON_ERROR_INCOMPLETE;
        }
        case '{': {
            unlikely_if(context->containerDepth + 1 >= KSJSON_MAX_CONTAINER_DEPTH)
            {
                KSLOG_DEBUG("Too many nested containers");
                return KSJSON_ERROR_DATA_TOO_LONG;
            }
            context->containerDepth++;
            context->bufferPtr++;
            result = context->callbacks->onBeginObject(name, context->userData);
            unlikely_if(result != KSJSON_OK) return result;
            while (context->bufferPtr < context->bufferEnd) {
                skipWhitespace(context);
                unlikely_if(context->bufferPtr >= context->bufferEnd) { break; }
                unlikely_if(*context->bufferPtr == '}')
                {
                    context->bufferPtr++;
                    context->containerDepth--;
                    return context->callbacks->onEndContainer(context->userData);
                }
                result = decodeString(context, context->nameBuffer, context->nameBufferLength);
                unlikely_if(result != KSJSON_OK) return result;
                skipWhitespace(context);
                unlikely_if(context->bufferPtr >= context->bufferEnd) { break; }
                unlikely_if(*context->bufferPtr != ':')
                {
                    KSLOG_DEBUG("Expected ':' but got '%c'", *context->bufferPtr);
                    return KSJSON_ERROR_INVALID_CHARACTER;
                }
                context->bufferPtr++;
                skipWhitespace(context);
                result = decodeElement(context->nameBuffer, context);
                unlikely_if(result != KSJSON_OK) return result;
                skipWhitespace(context);
                unlikely_if(context->bufferPtr >= context->bufferEnd) { break; }
                likely_if(*context->bufferPtr == ',') { context->bufferPtr++; }
                else unlikely_if(*context->bufferPtr != '}')
                {
                    KSLOG_DEBUG("Expected ',' or '}' but got '%c'", *context->bufferPtr);
                    return KSJSON_ERROR_INVALID_CHARACTER;
                }
            }
            KSLOG_DEBUG("Premature end of data");
            return KSJSON_ERROR_INCOMPLETE;
        }
        case '\"': {
            result = decodeString(context, context->stringBuffer, context->stringBufferLength);
            unlikely_if(result != KSJSON_OK) return result;
            result = context->callbacks->onStringElement(name, context->stringBuffer, context->userData);
            return result;
        }
        case 'f': {
            unlikely_if(!ensureBuffered(context, 5))
            {
                KSLOG_DEBUG("Premature end of data");
                return KSJSON_ERROR_INCOMPLETE;
            }
            unlikely_if(!(context->bufferPtr[1] == 'a' && context->bufferPtr[2] == 'l' &&
                          context->bufferPtr[3] == 's' && context->bufferPtr[4] == 'e'))
            {
                KSLOG_DEBUG("Expected \"false\" but got \"f%c%c%c%c\"", context->bufferPtr[1], context->bufferPtr[2],
                            context->bufferPtr[3], context->bufferPtr[4]);
                return KSJSON_ERROR_INVALID_CHARACTER;
            }
            context->bufferPtr += 5;
            return context->callbacks->onBooleanElement(name, false, context->userData);
        }
        case 't': {
            unlikely_if(!ensureBuffered(context, 4))
            {
                KSLOG_DEBUG("Premature end of data");
                return KSJSON_ERROR_INCOMPLETE;
            }
            unlikely_if(!(context->bufferPtr[1] == 'r' && context->bufferPtr[2] == 'u' && context->bufferPtr[3] == 'e'))
            {
                KSLOG_DEBUG("Expected \"true\" but got \"t%c%c%c\"", context->bufferPtr[1], context->bufferPtr[2],
                            context->bufferPtr[3]);
                return KSJSON_ERROR_INVALID_CHARACTER;
            }
            context->bufferPtr += 4;
            return context->callbacks->onBooleanElement(name, true, context->userData);
        }
        case 'n': {
            unlikely_if(!ensureBuffered(context, 4))
            {
                KSLOG_DEBUG("Premature end of data");
                return KSJSON_ERROR_INCOMPLETE;
            }
            unlikely_if(!(context->bufferPtr[1] == 'u' && context->bufferPtr[2] == 'l' && context->bufferPtr[3] == 'l'))
            {
                KSLOG_DEBUG("Expected \"null\" but got \"n%c%c%c\"", context->bufferPtr[1], context->bufferPtr[2],
                            context->bufferPtr[3]);
                return KSJSON_ERROR_INVALID_CHARACTER;
            }
            context->bufferPtr += 4;
            return context->callbacks->onNullElement(name, context->userData);
        }
        case '-':
            sign = -1;
            context->bufferPtr++;
            // Fallthrough
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-fallthrough"
        case '0':
#pragma clang diagnostic pop
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
            return decodeNumber(name, context, sign);
        default:
            KSLOG_DEBUG("Invalid character '%c'", *context->bufferPtr);
            return KSJSON_ERROR_INVALID_CHARACTER;
    }
}

int ksjson_decode(const char *const data, int length, char *stringBuffer, int stringBufferLength,
                  KSJSONDecodeCallbacks *const callbacks, void *const userData, const int startDepth,
                  int *const errorOffset)
{
    char *nameBuffer = stringBuffer;
    int nameBufferLength = stringBufferLength / 4;
    stringBuffer = nameBuffer + nameBufferLength;
    stringBufferLength -= nameBufferLength;
    KSJSONDecodeContext context = { .bufferPtr = (char *)data,
                                    .bufferEnd = (char *)data + length,
                                    .bufferEndIsEOF = true,
                                    .nameBuffer = nameBuffer,
                                    .nameBufferLength = nameBufferLength,
                                    .stringBuffer = stringBuffer,
                                    .stringBufferLength = (int)stringBufferLength,
                                    .callbacks = callbacks,
                                    .containerDepth = startDepth,
                                    .userData = userData };

    int result = decodeElement(NULL, &context);
    likely_if(result == KSJSON_OK) { result = requireEndOfData(&context); }
    likely_if(result == KSJSON_OK) { result = callbacks->onEndData(userData); }

    // Where the decoder actually stopped. This used to report a pointer that was never
    // advanced, so every error came back at offset 0.
    unlikely_if(result != KSJSON_OK && errorOffset != NULL) { *errorOffset = (int)(context.bufferPtr - data); }
    return result;
}

struct JSONFromFileContext;
typedef void (*UpdateDecoderCallback)(struct JSONFromFileContext *context);

typedef struct JSONFromFileContext {
    KSJSONEncodeContext *encodeContext;
    KSJSONDecodeContext *decodeContext;
    char *bufferStart;
    /** How much bufferStart can hold. bufferEnd moves as the window fills and drains, so it
     * cannot stand in for this. */
    int bufferCapacity;
    const char *sourceFilename;
    int fd;
    bool isEOF;
    bool closeLastContainer;
    /** Containers open right now. Only the checking callbacks maintain this; the embedding
     * callbacks let the encoder track depth for them. */
    int containerDepth;
    UpdateDecoderCallback updateDecoderCallback;
} JSONFromFileContext;

static void updateDecoder_doNothing(__unused struct JSONFromFileContext *context) {}

static int refillDecoder_readFile(KSJSONDecodeContext *decodeContext, const char *const preserveFrom)
{
    JSONFromFileContext *context = (JSONFromFileContext *)decodeContext->userData;

    char *const start = context->bufferStart;
    const int keep = (int)(decodeContext->bufferEnd - preserveFrom);
    unlikely_if(keep >= context->bufferCapacity)
    {
        // The element already spans the whole window, so there is nowhere to put more of it.
        KSLOG_DEBUG("Element is longer than the read window");
        return KSJSON_ERROR_DATA_TOO_LONG;
    }

    // Move what is still needed to the front, keeping the cursor pointing at the same byte.
    const ptrdiff_t shift = preserveFrom - start;
    memmove(start, preserveFrom, (size_t)keep);
    decodeContext->bufferPtr -= shift;

    const int fillLength = context->bufferCapacity - keep;
    int bytesRead = (int)read(context->fd, start + keep, (unsigned)fillLength);
    unlikely_if(bytesRead < 0)
    {
        // errno numerically, not via strerror: this runs at crash time and Apple's strerror
        // calloc()s its return buffer.
        KSLOG_ERROR("Error reading file %s: errno %d", context->sourceFilename, errno);
        bytesRead = 0;
    }

    // Only ever point at bytes read() actually wrote; the rest of the window is whatever
    // was there before.
    decodeContext->bufferEnd = start + keep + bytesRead;
    unlikely_if(bytesRead < fillLength)
    {
        // A short read is the only proof of EOF we get. Until one happens, the end of the
        // window says nothing about the end of the file.
        context->isEOF = true;
        decodeContext->bufferEndIsEOF = true;
    }
    return KSJSON_OK;
}

static void updateDecoder_readFile(struct JSONFromFileContext *context)
{
    likely_if(!context->isEOF)
    {
        const char *const ptr = context->decodeContext->bufferPtr;
        const int remaining = (int)(context->decodeContext->bufferEnd - ptr);
        unlikely_if(remaining < context->bufferCapacity / 2)
        {
            (void)refillDecoder_readFile(context->decodeContext, ptr);
        }
    }
}

static int addJSONFromFile_onBooleanElement(const char *const name, const bool value, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_addBooleanElement(context->encodeContext, name, value);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onFloatingPointElement(const char *const name, const double value, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_addFloatingPointElement(context->encodeContext, name, value);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onIntegerElement(const char *const name, const int64_t value, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_addIntegerElement(context->encodeContext, name, value);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onUnsignedIntegerElement(const char *const name, const uint64_t value, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_addUIntegerElement(context->encodeContext, name, value);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onNullElement(const char *const name, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_addNullElement(context->encodeContext, name);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onStringElement(const char *const name, const char *const value, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_addStringElement(context->encodeContext, name, value, (int)strlen(value));
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onBeginObject(const char *const name, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_beginObject(context->encodeContext, name);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onBeginArray(const char *const name, void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = ksjson_beginArray(context->encodeContext, name);
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onEndContainer(void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    int result = KSJSON_OK;
    if (context->closeLastContainer || context->encodeContext->containerLevel > 2) {
        result = ksjson_endContainer(context->encodeContext);
    }
    context->updateDecoderCallback(context);
    return result;
}

static int addJSONFromFile_onEndData(__unused void *const userData) { return KSJSON_OK; }

// The checking callbacks below run the same decoder the embedding callbacks do, but reach
// no encoder, so a payload that fails leaves nothing written anywhere. They still pump the
// buffer refill, because decodeElement only advances the file window from its callbacks,
// and they count containers, because the decoder has no depth limit of its own while the
// encoder's isObject[] does.

static int check_onScalarElement(void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    context->updateDecoderCallback(context);
    return KSJSON_OK;
}

static int check_onBooleanElement(__unused const char *const name, __unused const bool value, void *const userData)
{
    return check_onScalarElement(userData);
}

static int check_onFloatingPointElement(__unused const char *const name, __unused const double value,
                                        void *const userData)
{
    return check_onScalarElement(userData);
}

static int check_onIntegerElement(__unused const char *const name, __unused const int64_t value, void *const userData)
{
    return check_onScalarElement(userData);
}

static int check_onUnsignedIntegerElement(__unused const char *const name, __unused const uint64_t value,
                                          void *const userData)
{
    return check_onScalarElement(userData);
}

static int check_onNullElement(__unused const char *const name, void *const userData)
{
    return check_onScalarElement(userData);
}

static int check_onStringElement(__unused const char *const name, __unused const char *const value,
                                 void *const userData)
{
    return check_onScalarElement(userData);
}

static int check_onBeginContainer(void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    unlikely_if(context->containerDepth + 1 >= KSJSON_MAX_CONTAINER_DEPTH) { return KSJSON_ERROR_DATA_TOO_LONG; }
    context->containerDepth++;
    context->updateDecoderCallback(context);
    return KSJSON_OK;
}

static int check_onBeginObject(__unused const char *const name, void *const userData)
{
    return check_onBeginContainer(userData);
}

static int check_onBeginArray(__unused const char *const name, void *const userData)
{
    return check_onBeginContainer(userData);
}

static int check_onEndContainer(void *const userData)
{
    JSONFromFileContext *context = (JSONFromFileContext *)userData;
    context->containerDepth--;
    context->updateDecoderCallback(context);
    return KSJSON_OK;
}

static int check_onEndData(__unused void *const userData) { return KSJSON_OK; }

static KSJSONDecodeCallbacks checkCallbacks(void)
{
    return (KSJSONDecodeCallbacks) {
        .onBeginArray = check_onBeginArray,
        .onBeginObject = check_onBeginObject,
        .onBooleanElement = check_onBooleanElement,
        .onEndContainer = check_onEndContainer,
        .onEndData = check_onEndData,
        .onFloatingPointElement = check_onFloatingPointElement,
        .onIntegerElement = check_onIntegerElement,
        .onUnsignedIntegerElement = check_onUnsignedIntegerElement,
        .onNullElement = check_onNullElement,
        .onStringElement = check_onStringElement,
    };
}

static KSJSONDecodeCallbacks embedCallbacks(void)
{
    return (KSJSONDecodeCallbacks) {
        .onBeginArray = addJSONFromFile_onBeginArray,
        .onBeginObject = addJSONFromFile_onBeginObject,
        .onBooleanElement = addJSONFromFile_onBooleanElement,
        .onEndContainer = addJSONFromFile_onEndContainer,
        .onEndData = addJSONFromFile_onEndData,
        .onFloatingPointElement = addJSONFromFile_onFloatingPointElement,
        .onIntegerElement = addJSONFromFile_onIntegerElement,
        .onUnsignedIntegerElement = addJSONFromFile_onUnsignedIntegerElement,
        .onNullElement = addJSONFromFile_onNullElement,
        .onStringElement = addJSONFromFile_onStringElement,
    };
}

/** One decode pass over a payload already in memory.
 *
 * The caller owns the buffers so that the checking pass and the embedding pass share one
 * set instead of stacking two of them on the crash-time stack.
 *
 * @param encodeContext Where to emit, or NULL when only checking.
 * @param startDepth Containers already open at the destination, so a payload is judged
 *                   against the depth actually left to it rather than the whole limit.
 */
static int decodeJSONElement(const char *const jsonData, const int jsonDataLength, const char *const name,
                             KSJSONDecodeCallbacks *const callbacks, KSJSONEncodeContext *const encodeContext,
                             const bool closeLastContainer, const int startDepth, char *const nameBuffer,
                             char *const stringBuffer)
{
    KSJSONDecodeContext decodeContext = {
        .bufferPtr = jsonData,
        .bufferEnd = jsonData + jsonDataLength,
        // The whole payload is in hand, so its end is the end of the data.
        .bufferEndIsEOF = true,
        .nameBuffer = nameBuffer,
        .nameBufferLength = KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1,
        .stringBuffer = stringBuffer,
        .stringBufferLength = KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1,
        .callbacks = callbacks,
        .userData = NULL,
    };
    JSONFromFileContext jsonContext = {
        .encodeContext = encodeContext,
        .decodeContext = &decodeContext,
        .bufferStart = (char *)jsonData,
        .sourceFilename = NULL,
        .fd = -1,
        .closeLastContainer = closeLastContainer,
        .containerDepth = startDepth,
        .isEOF = false,
        .updateDecoderCallback = updateDecoder_doNothing,
    };
    decodeContext.userData = &jsonContext;

    const int result = decodeElement(name, &decodeContext);
    unlikely_if(result != KSJSON_OK) { return result; }
    return requireEndOfData(&decodeContext);
}

/** One decode pass over an already-open file. See decodeJSONElement() for the buffers. */
static int decodeJSONFile(const int fd, const char *const filename, const char *const name,
                          KSJSONDecodeCallbacks *const callbacks, KSJSONEncodeContext *const encodeContext,
                          const bool closeLastContainer, const int startDepth, char *const nameBuffer,
                          char *const stringBuffer, char *const fileBuffer)
{
    KSJSONDecodeContext decodeContext = {
        .bufferPtr = fileBuffer,
        .bufferEnd = fileBuffer + KSJSON_EMBEDDED_FILE_WINDOW,
        .bufferEndIsEOF = false,
        .refill = refillDecoder_readFile,
        .nameBuffer = nameBuffer,
        .nameBufferLength = KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1,
        .stringBuffer = stringBuffer,
        .stringBufferLength = KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1,
        .callbacks = callbacks,
        .userData = NULL,
    };
    JSONFromFileContext jsonContext = {
        .encodeContext = encodeContext,
        .decodeContext = &decodeContext,
        .bufferStart = fileBuffer,
        .bufferCapacity = KSJSON_EMBEDDED_FILE_WINDOW,
        .sourceFilename = filename,
        .fd = fd,
        .closeLastContainer = closeLastContainer,
        .containerDepth = startDepth,
        .isEOF = false,
        .updateDecoderCallback = updateDecoder_readFile,
    };
    decodeContext.userData = &jsonContext;

    // Manually trigger a data load.
    decodeContext.bufferPtr = decodeContext.bufferEnd;
    jsonContext.updateDecoderCallback(&jsonContext);

    const int result = decodeElement(name, &decodeContext);
    unlikely_if(result != KSJSON_OK) { return result; }
    return requireEndOfData(&decodeContext);
}

int ksjson_checkJSONElement(const KSJSONEncodeContext *const destination, const char *const jsonData,
                            const int jsonDataLength)
{
    char nameBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    char stringBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    KSJSONDecodeCallbacks callbacks = checkCallbacks();

    return decodeJSONElement(jsonData, jsonDataLength, NULL, &callbacks, NULL, true, destination->containerLevel,
                             nameBuffer, stringBuffer);
}

int ksjson_checkJSONFile(const KSJSONEncodeContext *const destination, const char *const filename)
{
    char nameBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    char stringBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    char fileBuffer[KSJSON_EMBEDDED_FILE_WINDOW];
    KSJSONDecodeCallbacks callbacks = checkCallbacks();

    int fd = open(filename, O_RDONLY);
    unlikely_if(fd < 0) { return KSJSON_ERROR_CANNOT_ADD_DATA; }

    int result = decodeJSONFile(fd, filename, NULL, &callbacks, NULL, true, destination->containerLevel, nameBuffer,
                                stringBuffer, fileBuffer);
    close(fd);
    return result;
}

int ksjson_addJSONFromFile(KSJSONEncodeContext *const encodeContext, const char *restrict const name,
                           const char *restrict const filename, const bool closeLastContainer)
{
    char nameBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    char stringBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    char fileBuffer[KSJSON_EMBEDDED_FILE_WINDOW];

    int fd = open(filename, O_RDONLY);
    unlikely_if(fd < 0) { return KSJSON_ERROR_CANNOT_ADD_DATA; }

    // Check before emitting anything. The encoder writes as the decoder reads, so a file
    // that only fails partway would leave a truncated element behind that the caller can
    // neither see nor take back. Rejecting up front leaves the name free for the caller.
    KSJSONDecodeCallbacks callbacks = checkCallbacks();
    int result = decodeJSONFile(fd, filename, NULL, &callbacks, NULL, true, encodeContext->containerLevel, nameBuffer,
                                stringBuffer, fileBuffer);

    if (result == KSJSON_OK) {
        unlikely_if(lseek(fd, 0, SEEK_SET) != 0) { result = KSJSON_ERROR_CANNOT_ADD_DATA; }
        else
        {
            int containerLevel = encodeContext->containerLevel;
            callbacks = embedCallbacks();
            result = decodeJSONFile(fd, filename, name, &callbacks, encodeContext, closeLastContainer, 0, nameBuffer,
                                    stringBuffer, fileBuffer);
            // The file passed the check, so a failure here is the encoder refusing to take
            // data, meaning the destination is already lost. Rebalance anyway so whatever
            // the caller does next is at least not nested inside this element.
            while ((closeLastContainer || result != KSJSON_OK) && encodeContext->containerLevel > containerLevel) {
                ksjson_endContainer(encodeContext);
            }
        }
    }

    close(fd);
    return result;
}

int ksjson_addJSONElement(KSJSONEncodeContext *const encodeContext, const char *restrict const name,
                          const char *restrict const jsonData, const int jsonDataLength, const bool closeLastContainer)
{
    char nameBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];
    char stringBuffer[KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1];

    // Rejected before anything is written. See ksjson_addJSONFromFile().
    KSJSONDecodeCallbacks callbacks = checkCallbacks();
    int result = decodeJSONElement(jsonData, jsonDataLength, NULL, &callbacks, NULL, true,
                                   encodeContext->containerLevel, nameBuffer, stringBuffer);
    unlikely_if(result != KSJSON_OK) { return result; }

    int containerLevel = encodeContext->containerLevel;
    callbacks = embedCallbacks();
    result = decodeJSONElement(jsonData, jsonDataLength, name, &callbacks, encodeContext, closeLastContainer, 0,
                               nameBuffer, stringBuffer);
    while ((closeLastContainer || result != KSJSON_OK) && encodeContext->containerLevel > containerLevel) {
        ksjson_endContainer(encodeContext);
    }

    return result;
}
