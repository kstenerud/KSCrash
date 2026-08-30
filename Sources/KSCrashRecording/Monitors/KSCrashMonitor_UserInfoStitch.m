//
//  KSCrashMonitor_UserInfoStitch.m
//
//  Created by Alexander Cohen on 2026-03-01.
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

#import "KSCrashMonitor_UserInfo.h"
#import "KSJSONCodecObjC.h"
#import "KSKeyValueStore.h"

#import "KSCrashReportFields.h"

#import <Foundation/Foundation.h>
#include <string.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Iteration Callbacks -
// ============================================================================

/** A key whose final record does not read as a value is absent, not unchanged:
 *  the crash-time callback may already have written the same key into the user
 *  section, and it must not go on serving a value the store says was replaced.
 *  This is the same outcome the live getter, `keys`, and the run-summary
 *  stitch produce for that record. */
static void resolveToAbsence(NSMutableDictionary *dict, NSString *key) { [dict removeObjectForKey:key]; }

static void onString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey == nil) {
        return;
    }
    NSString *nsVal = [[NSString alloc] initWithBytes:value length:valueLen encoding:NSUTF8StringEncoding];
    if (nsVal == nil) {
        resolveToAbsence(dict, nsKey);
        return;
    }
    dict[nsKey] = nsVal;
}

static void onInt64(const char *key, uint16_t keyLen, int64_t value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        dict[nsKey] = @(value);
    }
}

static void onUInt64(const char *key, uint16_t keyLen, uint64_t value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        dict[nsKey] = @(value);
    }
}

static void onDouble(const char *key, uint16_t keyLen, double value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        dict[nsKey] = @(value);
    }
}

static void onBool(const char *key, uint16_t keyLen, bool value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        dict[nsKey] = @(value);
    }
}

static void onDate(const char *key, uint16_t keyLen, int64_t nanosecondsSince1970, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        // Seconds since 1970, the model's date representation, not an NSDate:
        // the encoder would turn an NSDate into a second-resolution UTC
        // string, which reads back as a string rather than the instant that
        // was set, and would disagree with the same run's summary.
        NSTimeInterval seconds = (NSTimeInterval)nanosecondsSince1970 / 1e9;
        dict[nsKey] = @(seconds);
    }
}

// These bytes are re-encoded inside the finalized report, under
// report -> "user" -> key, so two containers are already open when the
// encoder reaches them. Judging the payload against the whole depth limit
// instead would accept one the report encoder cannot write, and a report that
// cannot be encoded is never delivered, taking every other value with it.
static const int kUserSectionEncodeDepth = 2;

static void onJSON(const char *key, uint16_t keyLen, const char *json, uint16_t jsonLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey == nil) {
        return;
    }
    // The store does not validate JSON, so undecodable bytes (a torn or
    // foreign record) are absence, never a delivery failure; so is anything
    // but a container, the only JSON values. Nulls inside a container are
    // dropped here too: null means absence, resolved at read time like the
    // finalized-report reads, never on the write path.
    // FailOnUnrepresentableString because the whole record is one value: the
    // live getter and the run-summary stitch read these bytes with Foundation,
    // which rejects the document, so dropping just the bad member here would
    // put a value in the report that every other reader calls absent.
    NSData *data = [NSData dataWithBytesNoCopy:(void *)json length:jsonLen freeWhenDone:NO];
    id value = [KSJSONCodec decode:data
                           options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                                   KSJSONDecodeOptionFailOnUnrepresentableString
                        startDepth:kUserSectionEncodeDepth
                             error:nil];
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]) {
        dict[nsKey] = value;
    } else {
        resolveToAbsence(dict, nsKey);
    }
}

// ============================================================================
#pragma mark - Tombstone Callback -
// ============================================================================

static void onRemoved(const char *key, uint16_t keyLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        [dict removeObjectForKey:nsKey];
    }
}

// ============================================================================
#pragma mark - Stitch -
// ============================================================================

CFDictionaryRef kscm_userinfo_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   __unused KSCrashSidecarScope scope, __unused void *context)
{
    if (!reportDict || !sidecarPath) {
        return NULL;
    }

    // Read sidecar via KSKeyValueStore (validates magic, version).
    KSKeyValueStore *store = kskvs_create(sidecarPath, KSKVSModeRead, NULL, NULL);
    if (store == NULL) {
        return NULL;
    }

    NSMutableDictionary *dict = [(__bridge NSDictionary *)reportDict mutableCopy];

    // Start from the existing user section (if any).
    NSMutableDictionary *userSection;
    id existing = dict[KSCrashField_User];
    if ([existing isKindOfClass:[NSDictionary class]]) {
        userSection = [existing mutableCopy];
    } else {
        userSection = [NSMutableDictionary dictionary];
    }
    // Iterate sidecar directly into userSection: live values overwrite, tombstones remove.
    KSKVSCallbacks callbacks = {
        .onString = onString,
        .onInt64 = onInt64,
        .onUInt64 = onUInt64,
        .onDouble = onDouble,
        .onBool = onBool,
        .onDate = onDate,
        .onJSON = onJSON,
        .onRemoved = onRemoved,
    };
    kskvs_iterate(store, &callbacks, (__bridge void *)userSection);
    kskvs_destroy(store);

    // If nothing changed, CFRetain and return the input (CF Create Rule).
    // NULL is reserved for errors per the createStitchedReport contract.
    bool noChange;
    if ([existing isKindOfClass:[NSDictionary class]]) {
        noChange = [userSection isEqualToDictionary:existing];
    } else {
        noChange = ([userSection count] == 0);
    }
    if (noChange) {
        CFRetain(reportDict);
        return reportDict;
    }

    dict[KSCrashField_User] = userSection;

    return (__bridge_retained CFDictionaryRef)dict;
}
