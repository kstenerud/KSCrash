//
//  KSCrashReportFixer.c
//
//  Created by Karl Stenerud on 2016-11-07.
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

#include <stdlib.h>
#include <string.h>

#include "KSCrashReportFields.h"
#include "KSDate.h"
#include "KSJSONCodec.h"
#include "KSLogger.h"
#include "KSSystemCapabilities.h"

#define MAX_DEPTH 100
#define MAX_NAME_LENGTH 100
#define REPORT_VERSION_COMPONENTS_COUNT 3

static const char *datePaths[][MAX_DEPTH] = {
    { "", KSCrashField_Report, KSCrashField_Timestamp },
    { "", KSCrashField_RecrashReport, KSCrashField_Report, KSCrashField_Timestamp },
};
static int datePathsCount = sizeof(datePaths) / sizeof(*datePaths);

static const char *versionPaths[][MAX_DEPTH] = {
    { "", KSCrashField_Report, KSCrashField_Version },
    { "", KSCrashField_RecrashReport, KSCrashField_Report, KSCrashField_Version },
};
static int versionPathsCount = sizeof(versionPaths) / sizeof(*versionPaths);

typedef struct {
    KSJSONEncodeContext *encodeContext;
    int reportVersionComponents[REPORT_VERSION_COMPONENTS_COUNT];
    char objectPath[MAX_DEPTH][MAX_NAME_LENGTH];
    int currentDepth;
    char *outputPtr;
    int outputBytesLeft;
} FixupContext;

static bool increaseDepth(FixupContext *context, const char *name)
{
    if (context->currentDepth >= MAX_DEPTH) {
        return false;
    }
    if (name == NULL) {
        *context->objectPath[context->currentDepth] = '\0';
    } else {
        strncpy(context->objectPath[context->currentDepth], name, sizeof(context->objectPath[context->currentDepth]));
    }
    context->currentDepth++;
    return true;
}

static bool decreaseDepth(FixupContext *context)
{
    if (context->currentDepth <= 0) {
        return false;
    }
    context->currentDepth--;
    return true;
}

static bool matchesPath(FixupContext *context, const char **path, const char *finalName)
{
    if (finalName == NULL) {
        finalName = "";
    }

    for (int i = 0; i < context->currentDepth; i++) {
        if (strncmp(context->objectPath[i], path[i], MAX_NAME_LENGTH) != 0) {
            return false;
        }
    }
    if (strncmp(finalName, path[context->currentDepth], MAX_NAME_LENGTH) != 0) {
        return false;
    }
    return true;
}

static bool matchesAPath(FixupContext *context, const char *name, const char *paths[][MAX_DEPTH], int pathsCount)
{
    for (int i = 0; i < pathsCount; i++) {
        if (matchesPath(context, paths[i], name)) {
            return true;
        }
    }
    return false;
}

static bool matchesMinVersion(FixupContext *context, int major, int minor, int patch)
{
    // Works only for report version 3.1.0 and above. See KSCrashReportVersion.h
    bool result = false;
    int *parts = context->reportVersionComponents;
    result = result || (parts[0] > major);
    result = result || (parts[0] == major && parts[1] > minor);
    result = result || (parts[0] == major && parts[1] == minor && parts[2] >= patch);
    return result;
}

static bool shouldFixDate(FixupContext *context, const char *name)
{
    return matchesAPath(context, name, datePaths, datePathsCount);
}

static bool shouldSaveVersion(FixupContext *context, const char *name)
{
    return matchesAPath(context, name, versionPaths, versionPathsCount);
}

static int onBooleanElement(const char *const name, const bool value, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    return ksjson_addBooleanElement(context->encodeContext, name, value);
}

static int onFloatingPointElement(const char *const name, const double value, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    return ksjson_addFloatingPointElement(context->encodeContext, name, value);
}

static int onIntegerElement(const char *const name, const int64_t value, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    int result = KSJSON_OK;
    if (shouldFixDate(context, name)) {
        char buffer[28];

        if (matchesMinVersion(context, 3, 3, 0)) {
            ksdate_utcStringFromMicroseconds(value, buffer);
        } else {
            ksdate_utcStringFromTimestamp((time_t)value, buffer);
        }

        result = ksjson_addStringElement(context->encodeContext, name, buffer, (int)strlen(buffer));
    } else {
        result = ksjson_addIntegerElement(context->encodeContext, name, value);
    }
    return result;
}

static int onUnsignedIntegerElement(const char *const name, const uint64_t value, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    return ksjson_addUIntegerElement(context->encodeContext, name, value);
}

static int onNullElement(const char *const name, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    return ksjson_addNullElement(context->encodeContext, name);
}

static int onStringElement(const char *const name, const char *const value, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    const char *stringValue = value;
    int result = ksjson_addStringElement(context->encodeContext, name, stringValue, (int)strlen(stringValue));
    if (shouldSaveVersion(context, name)) {
        memset(context->reportVersionComponents, 0, sizeof(context->reportVersionComponents));
        int versionPartsIndex = 0;
        char *mutableValue = strdup(value);
        char *versionPart = strtok(mutableValue, ".");
        while (versionPart != NULL && versionPartsIndex < REPORT_VERSION_COMPONENTS_COUNT) {
            context->reportVersionComponents[versionPartsIndex++] = atoi(versionPart);
            versionPart = strtok(NULL, ".");
        }
        free(mutableValue);
    }
    return result;
}

static int onBeginObject(const char *const name, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    int result = ksjson_beginObject(context->encodeContext, name);
    if (!increaseDepth(context, name)) {
        return KSJSON_ERROR_DATA_TOO_LONG;
    }
    return result;
}

static int onBeginArray(const char *const name, void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    int result = ksjson_beginArray(context->encodeContext, name);
    if (!increaseDepth(context, name)) {
        return KSJSON_ERROR_DATA_TOO_LONG;
    }
    return result;
}

static int onEndContainer(void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    int result = ksjson_endContainer(context->encodeContext);
    if (!decreaseDepth(context)) {
        // Do something;
    }
    return result;
}

static int onEndData(void *const userData)
{
    FixupContext *context = (FixupContext *)userData;
    return ksjson_endEncode(context->encodeContext);
}

static int addJSONData(const char *data, int length, void *userData)
{
    FixupContext *context = (FixupContext *)userData;
    if (length > context->outputBytesLeft) {
        return KSJSON_ERROR_DATA_TOO_LONG;
    }
    memcpy(context->outputPtr, data, length);
    context->outputPtr += length;
    context->outputBytesLeft -= length;

    return KSJSON_OK;
}

char *kscrf_fixupCrashReport(const char *crashReport)
{
    if (crashReport == NULL) {
        return NULL;
    }

    KSJSONDecodeCallbacks callbacks = {
        .onBeginArray = onBeginArray,
        .onBeginObject = onBeginObject,
        .onBooleanElement = onBooleanElement,
        .onEndContainer = onEndContainer,
        .onEndData = onEndData,
        .onFloatingPointElement = onFloatingPointElement,
        .onIntegerElement = onIntegerElement,
        .onUnsignedIntegerElement = onUnsignedIntegerElement,
        .onNullElement = onNullElement,
        .onStringElement = onStringElement,
    };
    int stringBufferLength = 10000;
    char *stringBuffer = malloc((unsigned)stringBufferLength);
    int crashReportLength = (int)strlen(crashReport);
    int fixedReportLength = (int)(crashReportLength * 1.5);
    char *fixedReport = malloc((unsigned)fixedReportLength);
    KSJSONEncodeContext encodeContext;
    FixupContext fixupContext = {
        .encodeContext = &encodeContext,
        .reportVersionComponents = { 0 },
        .currentDepth = 0,
        .outputPtr = fixedReport,
        .outputBytesLeft = fixedReportLength,
    };

    ksjson_beginEncode(&encodeContext, true, addJSONData, &fixupContext);

    int errorOffset = 0;
    int result = ksjson_decode(crashReport, (int)strlen(crashReport), stringBuffer, stringBufferLength, &callbacks,
                               &fixupContext, &errorOffset);
    *fixupContext.outputPtr = '\0';
    free(stringBuffer);
    if (result != KSJSON_OK) {
        KSLOG_ERROR("Could not decode report: %s", ksjson_stringForError(result));
        free(fixedReport);
        return NULL;
    }
    return fixedReport;
}
