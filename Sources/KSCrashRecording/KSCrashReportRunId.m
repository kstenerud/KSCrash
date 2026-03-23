//
//  KSCrashReportRunId.m
//
//  Created by Alexander Cohen on 2026-03-22.
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

#include "KSCrashReportRunId.h"

#include <stdlib.h>
#include <string.h>
#include <uuid/uuid.h>

#include "KSCrashReportStoreC+Private.h"
#include "KSFileUtils.h"
#include "KSJSONCodec.h"

#import <Foundation/Foundation.h>

#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"

// UUID string length: 8-4-4-4-12 = 36 chars
#define KSCRS_UUID_STRING_LENGTH 36

// Sentinel returned from callbacks to stop decoding early.
// Any non-KSJSON_OK value halts ksjson_decode; 999 is chosen to
// avoid colliding with real KSJSONError codes (1..6).
#define KSJSON_STOP 999

typedef struct {
    char *runIdOut;
    size_t runIdOutLen;
    bool inReport;  // true while inside the top-level "report" object
    int nesting;    // container nesting depth relative to the report object
    int depth;      // overall container depth (1 = inside root object)
    bool found;
} RunIdSearchContext;

static int onRunIdString(const char *name, const char *value, void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    if (ctx->inReport && ctx->nesting == 0 && name != NULL && strcmp(name, "run_id") == 0) {
        size_t len = strlen(value);
        if (len == KSCRS_UUID_STRING_LENGTH && len < ctx->runIdOutLen) {
            uuid_t unused;
            if (uuid_parse(value, unused) == 0) {
                memcpy(ctx->runIdOut, value, len);
                ctx->runIdOut[len] = '\0';
                ctx->found = true;
                return KSJSON_STOP;
            }
        }
    }
    return KSJSON_OK;
}

static int onRunIdBeginObject(const char *name, void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    // Only match "report" as a direct child of the root object (depth 1).
    // This avoids false matches on nested objects named "report" inside
    // other top-level keys (e.g. {"meta": {"report": {}}, "report": {...}}).
    if (ctx->inReport) {
        ctx->nesting++;
    } else if (name != NULL && strcmp(name, "report") == 0 && ctx->depth == 1) {
        ctx->inReport = true;
    }
    ctx->depth++;
    return KSJSON_OK;
}

static int onRunIdBeginArray(__unused const char *name, void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    if (ctx->inReport) {
        ctx->nesting++;
    }
    ctx->depth++;
    return KSJSON_OK;
}

static int onRunIdEndContainer(void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    if (ctx->inReport) {
        if (ctx->nesting == 0) {
            // Leaving the "report" object, stop early.
            ctx->inReport = false;
            ctx->depth--;
            return KSJSON_STOP;
        }
        ctx->nesting--;
    }
    ctx->depth--;
    return KSJSON_OK;
}

// No-op callbacks for element types we don't care about.
// Every slot must be non-NULL because ksjson_decode dispatches unconditionally.
// clang-format off
static int onIgnoreBool(__unused const char *n, __unused bool v, __unused void *u) { return KSJSON_OK; }
static int onIgnoreFloat(__unused const char *n, __unused double v, __unused void *u) { return KSJSON_OK; }
static int onIgnoreInt(__unused const char *n, __unused int64_t v, __unused void *u) { return KSJSON_OK; }
static int onIgnoreUInt(__unused const char *n, __unused uint64_t v, __unused void *u) { return KSJSON_OK; }
static int onIgnoreNull(__unused const char *n, __unused void *u) { return KSJSON_OK; }
static int onIgnore(__unused void *u) { return KSJSON_OK; }
// clang-format on

/** ObjC fallback: full-decode the report and extract report.run_id.
 *  Only called when the streaming decoder fails (e.g. oversized key/string
 *  trips KSJSON_ERROR_DATA_TOO_LONG before run_id is reached).
 */
static bool extractRunIdWithFullDecode(const char *rawReport, int length, char *runIdOut, __unused size_t runIdOutLen)
{
    @autoreleasepool {
        NSData *data = [NSData dataWithBytesNoCopy:(void *)rawReport length:(NSUInteger)length freeWhenDone:NO];
        NSDictionary *dict =
            [KSJSONCodec decode:data
                        options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                                KSJSONDecodeOptionKeepPartialObject
                          error:nil];
        if (![dict isKindOfClass:[NSDictionary class]]) {
            return false;
        }
        id reportSection = dict[KSCrashField_Report];
        if (![reportSection isKindOfClass:[NSDictionary class]]) {
            return false;
        }
        NSString *runId = reportSection[KSCrashField_RunID];
        if (![runId isKindOfClass:[NSString class]] || runId.length != KSCRS_UUID_STRING_LENGTH) {
            return false;
        }
        const char *utf8 = runId.UTF8String;
        uuid_t unused;
        if (uuid_parse(utf8, unused) != 0) {
            return false;
        }
        memcpy(runIdOut, utf8, KSCRS_UUID_STRING_LENGTH);
        runIdOut[KSCRS_UUID_STRING_LENGTH] = '\0';
        return true;
    }
}

bool kscrs_extractRunIdFromReportFile(const char *reportPath, char *runIdOut, size_t runIdOutLen)
{
    if (reportPath == NULL || runIdOut == NULL || runIdOutLen <= KSCRS_UUID_STRING_LENGTH) {
        return false;
    }

    char *rawReport = NULL;
    int length = 0;
    ksfu_readEntireFile(reportPath, &rawReport, &length, KSCRS_MAX_REPORT_SIZE);
    if (rawReport == NULL) {
        return false;
    }

    RunIdSearchContext ctx = {
        .runIdOut = runIdOut,
        .runIdOutLen = runIdOutLen,
    };

    char stringBuffer[4096];
    KSJSONDecodeCallbacks callbacks = {
        .onBooleanElement = onIgnoreBool,
        .onFloatingPointElement = onIgnoreFloat,
        .onIntegerElement = onIgnoreInt,
        .onUnsignedIntegerElement = onIgnoreUInt,
        .onNullElement = onIgnoreNull,
        .onStringElement = onRunIdString,
        .onBeginObject = onRunIdBeginObject,
        .onBeginArray = onRunIdBeginArray,
        .onEndContainer = onRunIdEndContainer,
        .onEndData = onIgnore,
    };
    int result = ksjson_decode(rawReport, length, stringBuffer, sizeof(stringBuffer), &callbacks, &ctx, NULL);

    if (ctx.found) {
        free(rawReport);
        return true;
    }

    // If the streaming decoder failed because a key or string exceeded the
    // scratch buffer, fall back to a full ObjC decode. This handles valid
    // reports with oversized keys/values before report.run_id.
    if (result == KSJSON_ERROR_DATA_TOO_LONG) {
        bool found = extractRunIdWithFullDecode(rawReport, length, runIdOut, runIdOutLen);
        free(rawReport);
        return found;
    }

    free(rawReport);
    return false;
}
