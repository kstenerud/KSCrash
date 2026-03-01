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
#import "KSKeyValueStore.h"

#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#include <string.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Iteration Callbacks -
// ============================================================================

static void onString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    NSString *nsVal = [[NSString alloc] initWithBytes:value length:valueLen encoding:NSUTF8StringEncoding];
    if (nsKey && nsVal) {
        dict[nsKey] = nsVal;
    }
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

static void onDate(const char *key, uint16_t keyLen, uint64_t nanosecondsSince1970, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) {
        NSTimeInterval seconds = (NSTimeInterval)nanosecondsSince1970 / 1e9;
        dict[nsKey] = [NSDate dateWithTimeIntervalSince1970:seconds];
    }
}

// ============================================================================
#pragma mark - Stitch -
// ============================================================================

char *kscm_userinfo_stitchReport(const char *report, const char *sidecarPath, __unused KSCrashSidecarScope scope,
                                 __unused void *context)
{
    if (!report || !sidecarPath) {
        return NULL;
    }

    // Read sidecar via KSKeyValueStore (validates magic, version).
    KSKeyValueStore *store = kskvs_create(sidecarPath, KSKVSModeRead, NULL);
    if (store == NULL) {
        return NULL;
    }

    NSMutableDictionary *sidecarDict = [NSMutableDictionary dictionary];
    KSKVSCallbacks callbacks = {
        .onString = onString,
        .onInt64 = onInt64,
        .onUInt64 = onUInt64,
        .onDouble = onDouble,
        .onBool = onBool,
        .onDate = onDate,
    };
    kskvs_iterate(store, &callbacks, (__bridge void *)sidecarDict);
    kskvs_destroy(store);

    if ([sidecarDict count] == 0) {
        return NULL;
    }

    // Decode the report
    NSData *reportData = [NSData dataWithBytesNoCopy:(void *)report length:strlen(report) freeWhenDone:NO];
    NSDictionary *decoded = [KSJSONCodec decode:reportData options:KSJSONDecodeOptionNone error:nil];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        KSLOG_ERROR(@"Failed to decode report JSON for UserInfo stitch");
        return NULL;
    }
    NSMutableDictionary *dict = [decoded mutableCopy];

    // Merge into the "user" section.
    // If report["user"] already exists (from old kscrash_setUserInfoJSON), merge on top.
    NSMutableDictionary *userSection;
    id existing = dict[KSCrashField_User];
    if ([existing isKindOfClass:[NSDictionary class]]) {
        userSection = [existing mutableCopy];
    } else {
        userSection = [NSMutableDictionary dictionary];
    }

    [userSection addEntriesFromDictionary:sidecarDict];
    dict[KSCrashField_User] = userSection;

    // Encode back to JSON
    NSError *error = nil;
    NSData *newData = [KSJSONCodec encode:dict options:KSJSONEncodeOptionNone error:&error];
    if (!newData) {
        KSLOG_ERROR(@"Failed to encode stitched UserInfo report: %@", error);
        return NULL;
    }

    char *result = (char *)malloc(newData.length + 1);
    if (!result) {
        return NULL;
    }
    memcpy(result, newData.bytes, newData.length);
    result[newData.length] = '\0';
    return result;
}
