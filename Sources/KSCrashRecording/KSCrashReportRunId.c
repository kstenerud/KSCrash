//
//  KSCrashReportRunId.c
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

#include "KSFileUtils.h"
#include "KSJSONCodec.h"

// UUID string length: 8-4-4-4-12 = 36 chars
#define KSCRS_UUID_STRING_LENGTH 36

// Sentinel returned from callbacks to stop decoding early.
#define KSJSON_STOP 999

typedef struct {
    char *runIdOut;
    size_t runIdOutLen;
    int depth;        // current container nesting depth (objects + arrays)
    int reportDepth;  // depth at which the "report" object was entered, or -1
    bool found;       // true once run_id has been captured
} RunIdSearchContext;

static int onRunIdString(const char *name, const char *value, void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    // Only match run_id as a direct child of the "report" object
    if (ctx->reportDepth >= 0 && ctx->depth == ctx->reportDepth && name != NULL && strcmp(name, "run_id") == 0) {
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
    ctx->depth++;
    if (ctx->depth == 2 && name != NULL && strcmp(name, "report") == 0) {
        ctx->reportDepth = ctx->depth;
    }
    return KSJSON_OK;
}

static int onRunIdBeginArray(__unused const char *name, void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    ctx->depth++;
    return KSJSON_OK;
}

static int onRunIdEndContainer(void *userData)
{
    RunIdSearchContext *ctx = (RunIdSearchContext *)userData;
    if (ctx->reportDepth >= 0 && ctx->depth == ctx->reportDepth) {
        // Leaving the "report" object without finding run_id, stop early.
        ctx->reportDepth = -1;
        ctx->depth--;
        return KSJSON_STOP;
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
static int onIgnoreName(__unused const char *n, __unused void *u) { return KSJSON_OK; }
static int onIgnore(__unused void *u) { return KSJSON_OK; }
// clang-format on

bool kscrs_extractRunIdFromReportFile(const char *reportPath, char *runIdOut, size_t runIdOutLen)
{
    if (reportPath == NULL || runIdOut == NULL || runIdOutLen <= KSCRS_UUID_STRING_LENGTH) {
        return false;
    }

    char *rawReport = NULL;
    int length = 0;
    ksfu_readEntireFile(reportPath, &rawReport, &length, 0);
    if (rawReport == NULL) {
        return false;
    }

    RunIdSearchContext ctx = {
        .runIdOut = runIdOut,
        .runIdOutLen = runIdOutLen,
        .reportDepth = -1,
    };

    char stringBuffer[512];
    KSJSONDecodeCallbacks callbacks = {
        .onBooleanElement = onIgnoreBool,
        .onFloatingPointElement = onIgnoreFloat,
        .onIntegerElement = onIgnoreInt,
        .onUnsignedIntegerElement = onIgnoreUInt,
        .onNullElement = onIgnoreName,
        .onStringElement = onRunIdString,
        .onBeginObject = onRunIdBeginObject,
        .onBeginArray = onRunIdBeginArray,
        .onEndContainer = onRunIdEndContainer,
        .onEndData = onIgnore,
    };
    ksjson_decode(rawReport, length, stringBuffer, sizeof(stringBuffer), &callbacks, &ctx, NULL);
    free(rawReport);
    return ctx.found;
}
