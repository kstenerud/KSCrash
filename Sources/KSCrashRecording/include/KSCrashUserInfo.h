//
//  KSCrashUserInfo.h
//
//  Created by Alexander Cohen on 2026-08-22.
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

#ifndef KSCrashUserInfo_h
#define KSCrashUserInfo_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The per-key user info store's limits: a key's text and a string value's text. */
#define KSCRASH_USERINFO_MAX_KEY_LENGTH 256
#define KSCRASH_USERINFO_MAX_STRING_LENGTH 1024

typedef enum {
    KSCrashUserInfoValueTypeNone = 0,
    KSCrashUserInfoValueTypeString,
    KSCrashUserInfoValueTypeInt64,
    KSCrashUserInfoValueTypeUInt64,
    KSCrashUserInfoValueTypeDouble,
    KSCrashUserInfoValueTypeBool,
    /** Nanoseconds since 1970-01-01 00:00:00 UTC. */
    KSCrashUserInfoValueTypeDate,
} KSCrashUserInfoValueType;

/** One user info value as stored: the type says which member holds it. */
typedef struct {
    KSCrashUserInfoValueType type;
    union {
        int64_t int64Value;
        uint64_t uint64Value;
        double doubleValue;
        bool boolValue;
        uint64_t dateNanoseconds;
    } value;
    char string[KSCRASH_USERINFO_MAX_STRING_LENGTH + 1];
} KSCrashUserInfoValue;

/** The current value under `key`. false when the key holds no value (never
 *  set, or removed) or before install.
 */
bool kscrash_copyUserInfoValue(const char *key, KSCrashUserInfoValue *valueOut);

/** Called once per key that currently holds a value; `key` is valid for the
 *  duration of the call. The callback may read and write the store.
 */
typedef void (*KSCrashUserInfoKeyCallback)(const char *key, void *context);

/** Enumerates the keys that currently hold a value, in no particular order.
 *  Nothing is enumerated before install.
 */
void kscrash_enumerateUserInfoKeys(KSCrashUserInfoKeyCallback callback, void *context);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashUserInfo_h */
