//
//  KSCrashState.c
//
//  Created by Karl Stenerud on 2012-02-05.
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


#include "KSCrashState.h"

#include "KSFileUtils.h"
#include "KSJSONCodec.h"
#include "KSMach.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


// ============================================================================
#pragma mark - Constants -
// ============================================================================

#define kFormatVersion 1

#define kKeyFormatVersion "version"
#define kKeyCrashedLastLaunch "crashedLastLaunch"
#define kKeyActiveDurationSinceLastCrash "activeDurationSinceLastCrash"
#define kKeyBackgroundDurationSinceLastCrash "backgroundDurationSinceLastCrash"
#define kKeyLaunchesSinceLastCrash "launchesSinceLastCrash"
#define kKeySessionsSinceLastCrash "sessionsSinceLastCrash"
#define kKeySessionsSinceLaunch "sessionsSinceLaunch"


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** Location where stat file is stored. */
static const char* g_stateFilePath;

/** Current state. */
static KSCrash_State* g_state;


// Avoiding static functions due to linker issues.

// ============================================================================
#pragma mark - JSON Encoding -
// ============================================================================

int kscrashstate_i_onBooleanElement(const char* const name,
                                    const bool value,
                                    void* const userData)
{
    KSCrash_State* state = userData;

    if(strcmp(name, kKeyCrashedLastLaunch) == 0)
    {
        state->crashedLastLaunch = value;
    }

    return KSJSON_OK;
}

int kscrashstate_i_onFloatingPointElement(const char* const name,
                                          const double value,
                                          void* const userData)
{
    KSCrash_State* state = userData;

    if(strcmp(name, kKeyActiveDurationSinceLastCrash) == 0)
    {
        state->activeDurationSinceLastCrash = value;
    }
    if(strcmp(name, kKeyBackgroundDurationSinceLastCrash) == 0)
    {
        state->backgroundDurationSinceLastCrash = value;
    }

    return KSJSON_OK;
}

int kscrashstate_i_onIntegerElement(const char* const name,
                                    const long long value,
                                    void* const userData)
{
    KSCrash_State* state = userData;

    if(strcmp(name, kKeyFormatVersion) == 0)
    {
        if(value != kFormatVersion)
        {
            KSLOG_ERROR("Expected version 1 but got %lld", value);
            return KSJSON_ERROR_INVALID_DATA;
        }
    }
    else if(strcmp(name, kKeyLaunchesSinceLastCrash) == 0)
    {
        state->launchesSinceLastCrash = (int)value;
    }
    else if(strcmp(name, kKeySessionsSinceLastCrash) == 0)
    {
        state->sessionsSinceLastCrash = (int)value;
    }

    // FP value might have been written as a whole number.
    return kscrashstate_i_onFloatingPointElement(name, value, userData);
}

int kscrashstate_i_onNullElement(__unused const char* const name,
                                 __unused void* const userData)
{
    return KSJSON_OK;
}

int kscrashstate_i_onStringElement(__unused const char* const name,
                                   __unused const char* const value,
                                   __unused void* const userData)
{
    return KSJSON_OK;
}

int kscrashstate_i_onBeginObject(__unused const char* const name,
                                 __unused void* const userData)
{
    return KSJSON_OK;
}

int kscrashstate_i_onBeginArray(__unused const char* const name,
                                __unused void* const userData)
{
    return KSJSON_OK;
}

int kscrashstate_i_onEndContainer(__unused void* const userData)
{
    return KSJSON_OK;
}

int kscrashstate_i_onEndData(__unused void* const userData)
{
    return KSJSON_OK;
}


/** Callback for adding JSON data.
 */
int kscrashstate_i_addJSONData(const char* const data,
                               const size_t length,
                               void* const userData)
{
    const int fd = *((int*)userData);
    const bool success = ksfu_writeBytesToFD(fd, data, (ssize_t)length);
    return success ? KSJSON_OK : KSJSON_ERROR_CANNOT_ADD_DATA;
}


// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Load the persistent state portion of a crash context.
 *
 * @param context The context to load into.
 *
 * @param path The path to the file to read.
 *
 * @return true if the operation was successful.
 */
bool kscrashstate_i_loadState(KSCrash_State* const context,
                              const char* const path)
{
    // Stop if the file doesn't exist.
    // This is expected on the first run of the app.
    const int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        return false;
    }
    close(fd);

    char* data;
    size_t length;
    if(!ksfu_readEntireFile(path, &data, &length))
    {
        KSLOG_ERROR("%s: Could not load file", path);
        return false;
    }

    KSJSONDecodeCallbacks callbacks;
    callbacks.onBeginArray = kscrashstate_i_onBeginArray;
    callbacks.onBeginObject = kscrashstate_i_onBeginObject;
    callbacks.onBooleanElement = kscrashstate_i_onBooleanElement;
    callbacks.onEndContainer = kscrashstate_i_onEndContainer;
    callbacks.onEndData = kscrashstate_i_onEndData;
    callbacks.onFloatingPointElement = kscrashstate_i_onFloatingPointElement;
    callbacks.onIntegerElement = kscrashstate_i_onIntegerElement;
    callbacks.onNullElement = kscrashstate_i_onNullElement;
    callbacks.onStringElement = kscrashstate_i_onStringElement;

    size_t errorOffset = 0;

    const int result = ksjson_decode(data,
                                     length,
                                     &callbacks,
                                     context,
                                     &errorOffset);
    free(data);
    if(result != KSJSON_OK)
    {
        KSLOG_ERROR("%s, offset %d: %s",
                    path, errorOffset, ksjson_stringForError(result));
        return false;
    }
    return true;
}

/** Save the persistent state portion of a crash context.
 *
 * @param context The context to save from.
 *
 * @param path The path to the file to create.
 *
 * @return true if the operation was successful.
 */
bool kscrashstate_i_saveState(const KSCrash_State* const state,
                              const char* const path)
{
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if(fd < 0)
    {
        KSLOG_ERROR("Could not open file %s for writing: %s",
                    path,
                    strerror(errno));
        return false;
    }

    KSJSONEncodeContext JSONContext;
    ksjson_beginEncode(&JSONContext,
                       true,
                       kscrashstate_i_addJSONData,
                       &fd);

    int result;
    if((result = ksjson_beginObject(&JSONContext, NULL)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addIntegerElement(&JSONContext,
                                          kKeyFormatVersion,
                                          kFormatVersion)) != KSJSON_OK)
    {
        goto done;
    }
    // Record this launch crashed state into "crashed last launch" field.
    if((result = ksjson_addBooleanElement(&JSONContext,
                                          kKeyCrashedLastLaunch,
                                          state->crashedThisLaunch)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addFloatingPointElement(&JSONContext,
                                                kKeyActiveDurationSinceLastCrash,
                                                state->activeDurationSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addFloatingPointElement(&JSONContext,
                                                kKeyBackgroundDurationSinceLastCrash,
                                                state->backgroundDurationSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addIntegerElement(&JSONContext,
                                          kKeyLaunchesSinceLastCrash,
                                          state->launchesSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addIntegerElement(&JSONContext,
                                          kKeySessionsSinceLastCrash,
                                          state->sessionsSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    result = ksjson_endEncode(&JSONContext);

done:
    close(fd);
    if(result != KSJSON_OK)
    {
        KSLOG_ERROR("%s: %s",
                    path, ksjson_stringForError(result));
        return false;
    }
    return true;
}


// ============================================================================
#pragma mark - API -
// ============================================================================

bool kscrashstate_init(const char* const stateFilePath,
                       KSCrash_State* const state)
{
    g_stateFilePath = stateFilePath;
    g_state = state;

    kscrashstate_i_loadState(state, stateFilePath);

    state->sessionsSinceLaunch = 1;
    state->activeDurationSinceLaunch = 0;
    state->backgroundDurationSinceLaunch = 0;
    if(state->crashedLastLaunch)
    {
        state->activeDurationSinceLastCrash = 0;
        state->backgroundDurationSinceLastCrash = 0;
        state->launchesSinceLastCrash = 0;
        state->sessionsSinceLastCrash = 0;
    }
    state->crashedThisLaunch = false;

    // Simulate first transition to foreground
    state->launchesSinceLastCrash++;
    state->sessionsSinceLastCrash++;
    state->applicationIsInForeground = true;

    return kscrashstate_i_saveState(state, stateFilePath);
}

void kscrashstate_notifyAppActive(const bool isActive)
{
    KSCrash_State* const state = g_state;

    state->applicationIsActive = isActive;
    if(isActive)
    {
        state->appStateTransitionTime = mach_absolute_time();
    }
    else
    {
        double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                         state->appStateTransitionTime);
        state->activeDurationSinceLaunch += duration;
        state->activeDurationSinceLastCrash += duration;
    }
}

void kscrashstate_notifyAppInForeground(const bool isInForeground)
{
    KSCrash_State* const state = g_state;
    const char* const stateFilePath = g_stateFilePath;

    state->applicationIsInForeground = isInForeground;
    if(isInForeground)
    {
        double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                         state->appStateTransitionTime);
        state->backgroundDurationSinceLaunch += duration;
        state->backgroundDurationSinceLastCrash += duration;
        state->sessionsSinceLastCrash++;
        state->sessionsSinceLaunch++;
    }
    else
    {
        state->appStateTransitionTime = mach_absolute_time();
        kscrashstate_i_saveState(state, stateFilePath);
    }
}

void kscrashstate_notifyAppTerminate(void)
{
    KSCrash_State* const state = g_state;
    const char* const stateFilePath = g_stateFilePath;

    const double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                           state->appStateTransitionTime);
    state->backgroundDurationSinceLastCrash += duration;
    kscrashstate_i_saveState(state, stateFilePath);
}

void kscrashstate_notifyAppCrash(void)
{
    KSCrash_State* const state = g_state;
    const char* const stateFilePath = g_stateFilePath;

    const double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                           state->appStateTransitionTime);
    if(state->applicationIsActive)
    {
        state->activeDurationSinceLaunch += duration;
        state->activeDurationSinceLastCrash += duration;
    }
    else if(!state->applicationIsInForeground)
    {
        state->backgroundDurationSinceLaunch += duration;
        state->backgroundDurationSinceLastCrash += duration;
    }
    state->crashedThisLaunch = true;
    kscrashstate_i_saveState(state, stateFilePath);
}

const KSCrash_State* const kscrashstate_currentState(void)
{
    return g_state;
}
