//
//  KSCrashType.c
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


#include "KSCrashType.h"

#include <stdlib.h>


static const struct
{
    const KSCrashType type;
    const char* const name;
} g_crashTypes[] =
{
#define CRASHTYPE(NAME) {NAME, #NAME}
    CRASHTYPE(KSCrashTypeMachException),
    CRASHTYPE(KSCrashTypeSignal),
    CRASHTYPE(KSCrashTypeCPPException),
    CRASHTYPE(KSCrashTypeNSException),
    CRASHTYPE(KSCrashTypeMainThreadDeadlock),
    CRASHTYPE(KSCrashTypeUserReported),
};
static const int g_crashTypesCount = sizeof(g_crashTypes) / sizeof(*g_crashTypes);


const char* kscrashtype_name(const KSCrashType crashType)
{
    for(int i = 0; i < g_crashTypesCount; i++)
    {
        if(g_crashTypes[i].type == crashType)
        {
            return g_crashTypes[i].name;
        }
    }
    return NULL;
}
