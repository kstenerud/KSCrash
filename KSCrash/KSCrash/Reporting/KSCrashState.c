//
//  KSCrashState.c
//
//  Created by Karl Stenerud on 12-02-05.
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
#include "KSLogger.h"
#include "KSMach.h"

#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


#define kFormatVersion 1

#define kKeyFormatVersion "version"
#define kKeyCrashedLastLaunch "crashedLastLaunch"
#define kKeyActiveDurationSinceLastCrash "activeDurationSinceLastCrash"
#define kKeyBackgroundDurationSinceLastCrash "backgroundDurationSinceLastCrash"
#define kKeyLaunchesSinceLastCrash "launchesSinceLastCrash"
#define kKeySessionsSinceLastCrash "sessionsSinceLastCrash"
#define kKeySessionsSinceLaunch "sessionsSinceLaunch"


// Avoiding static functions due to linker issues.

/** Callback for adding JSON data.
 */
int kscrashstate_i_addJSONData(const char* const data,
                               const size_t length,
                               void* const userData);

/** Load the persistent state portion of a crash context.
 *
 * @param context The context to load into.
 *
 * @param path The path to the file to read.
 *
 * @return true if the operation was successful.
 */
bool kscrashstate_i_loadState(KSCrashContext* const context,
                              const char* const path);

/** Save the persistent state portion of a crash context.
 *
 * @param context The context to save from.
 *
 * @param path The path to the file to create.
 *
 * @return true if the operation was successful.
 */
bool kscrashstate_i_saveState(const KSCrashContext* const context,
                              const char* const path);


// Various helpers

int kscrashstate_i_onBooleanElement(const char* const name,
                                    const bool value,
                                    void* const userData);

int kscrashstate_i_onFloatingPointElement(const char* const name,
                                          const double value,
                                          void* const userData);

int kscrashstate_i_onIntegerElement(const char* const name,
                                    const long long value,
                                    void* const userData);

int kscrashstate_i_onNullElement(const char* const name,
                                 void* const userData);

int kscrashstate_i_onStringElement(const char* const name,
                                   const char* const value,
                                   void* const userData);

int kscrashstate_i_onStringElement(const char* const name,
                                   const char* const value,
                                   void* const userData);

int kscrashstate_i_onBeginObject(const char* const name,
                                 void* const userData);

int kscrashstate_i_onBeginArray(const char* const name,
                                void* const userData);

int kscrashstate_i_onEndContainer(void* const userData);

int kscrashstate_i_onEndData(void* const userData);



int kscrashstate_i_onBooleanElement(const char* const name,
                            const bool value,
                            void* const userData)
{
    KSCrashContext* context = userData;
    
    if(strcmp(name, kKeyCrashedLastLaunch) == 0)
    {
        context->crashedLastLaunch = value;
    }
    
    return KSJSON_OK;
}

int kscrashstate_i_onFloatingPointElement(const char* const name,
                                  const double value,
                                  void* const userData)
{
    KSCrashContext* context = userData;
    
    if(strcmp(name, kKeyActiveDurationSinceLastCrash) == 0)
    {
        context->activeDurationSinceLastCrash = value;
    }
    if(strcmp(name, kKeyBackgroundDurationSinceLastCrash) == 0)
    {
        context->backgroundDurationSinceLastCrash = value;
    }
    
    return KSJSON_OK;
}

int kscrashstate_i_onIntegerElement(const char* const name,
                            const long long value,
                            void* const userData)
{
    KSCrashContext* context = userData;
    
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
        context->launchesSinceLastCrash = (int)value;
    }
    else if(strcmp(name, kKeySessionsSinceLastCrash) == 0)
    {
        context->sessionsSinceLastCrash = (int)value;
    }
    
    // FP value might have been written as a whole number.
    return kscrashstate_i_onFloatingPointElement(name, value, userData);
}

int kscrashstate_i_onNullElement(const char* const name,
                         void* const userData)
{
    #pragma unused(name)
    #pragma unused(userData)
    return KSJSON_OK;
}

int kscrashstate_i_onStringElement(const char* const name,
                           const char* const value,
                           void* const userData)
{
    #pragma unused(name)
    #pragma unused(value)
    #pragma unused(userData)
    return KSJSON_OK;
}

int kscrashstate_i_onBeginObject(const char* const name,
                         void* const userData)
{
    #pragma unused(name)
    #pragma unused(userData)
    return KSJSON_OK;
}

int kscrashstate_i_onBeginArray(const char* const name,
                        void* const userData)
{
    #pragma unused(name)
    #pragma unused(userData)
    return KSJSON_OK;
}

int kscrashstate_i_onEndContainer(void* const userData)
{
    #pragma unused(userData)
    return KSJSON_OK;
}

int kscrashstate_i_onEndData(void* const userData)
{
    #pragma unused(userData)
    return KSJSON_OK;
}


int kscrashstate_i_addJSONData(const char* const data,
                               const size_t length,
                               void* const userData)
{
    const int fd = *((int*)userData);
    const bool success = ksfu_writeBytesToFD(fd, data, (ssize_t)length);
    return success ? KSJSON_OK : KSJSON_ERROR_CANNOT_ADD_DATA;
}

bool kscrashstate_i_loadState(KSCrashContext* const context,
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

bool kscrashstate_i_saveState(const KSCrashContext* const context,
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
    // Record crashed state into "crashed last launch" field.
    if((result = ksjson_addBooleanElement(&JSONContext,
                                          kKeyCrashedLastLaunch,
                                          context->crashed)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addFloatingPointElement(&JSONContext,
                                                kKeyActiveDurationSinceLastCrash,
                                                context->activeDurationSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addFloatingPointElement(&JSONContext,
                                                kKeyBackgroundDurationSinceLastCrash,
                                                context->backgroundDurationSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addIntegerElement(&JSONContext,
                                          kKeyLaunchesSinceLastCrash,
                                          context->launchesSinceLastCrash)) != KSJSON_OK)
    {
        goto done;
    }
    if((result = ksjson_addIntegerElement(&JSONContext,
                                          kKeySessionsSinceLastCrash,
                                          context->sessionsSinceLastCrash)) != KSJSON_OK)
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


static const char* g_stateFilePath;
static KSCrashContext* g_context;

bool kscrash_initState(const char* const stateFilePath,
                       KSCrashContext* const context)
{
    g_stateFilePath = stateFilePath;
    g_context = context;
    
    kscrashstate_i_loadState(g_context, g_stateFilePath);
    
    g_context->sessionsSinceLaunch = 1;
    g_context->activeDurationSinceLaunch = 0;
    g_context->backgroundDurationSinceLaunch = 0;
    if(g_context->crashedLastLaunch)
    {
        g_context->activeDurationSinceLastCrash = 0;
        g_context->backgroundDurationSinceLastCrash = 0;
        g_context->launchesSinceLastCrash = 0;
        g_context->sessionsSinceLastCrash = 0;
    }
    g_context->crashed = false;
    
    // Simulate first transition to foreground
    g_context->launchesSinceLastCrash++;
    g_context->sessionsSinceLastCrash++;
    g_context->applicationIsInForeground = true;
    
    return kscrashstate_i_saveState(g_context, g_stateFilePath);
}

void kscrash_notifyApplicationActive(const bool isActive)
{
    g_context->applicationIsActive = isActive;
    if(isActive)
    {
        g_context->appStateTransitionTime = mach_absolute_time();
    }
    else
    {
        double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                         g_context->appStateTransitionTime);
        g_context->activeDurationSinceLaunch += duration;
        g_context->activeDurationSinceLastCrash += duration;
    }
}

void kscrash_notifyApplicationInForeground(const bool isInForeground)
{
    g_context->applicationIsInForeground = isInForeground;
    if(isInForeground)
    {
        double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                         g_context->appStateTransitionTime);
        g_context->backgroundDurationSinceLaunch += duration;
        g_context->backgroundDurationSinceLastCrash += duration;
        g_context->sessionsSinceLastCrash++;
        g_context->sessionsSinceLaunch++;
    }
    else
    {
        g_context->appStateTransitionTime = mach_absolute_time();
        kscrashstate_i_saveState(g_context, g_stateFilePath);
    }
}

void kscrash_notifyApplicationTerminate(void)
{
    const double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                           g_context->appStateTransitionTime);
    g_context->backgroundDurationSinceLastCrash += duration;
    kscrashstate_i_saveState(g_context, g_stateFilePath);
}

void kscrash_notifyApplicationCrash(void)
{
    const double duration = ksmach_timeDifferenceInSeconds(mach_absolute_time(),
                                                           g_context->appStateTransitionTime);
    if(g_context->applicationIsActive)
    {
        g_context->activeDurationSinceLaunch += duration;
        g_context->activeDurationSinceLastCrash += duration;
    }
    else if(!g_context->applicationIsInForeground)
    {
        g_context->backgroundDurationSinceLaunch += duration;
        g_context->backgroundDurationSinceLastCrash += duration;
    }
    g_context->crashed = true;
    kscrashstate_i_saveState(g_context, g_stateFilePath);
}
