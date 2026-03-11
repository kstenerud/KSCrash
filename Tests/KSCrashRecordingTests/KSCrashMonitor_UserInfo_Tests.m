//
//  KSCrashMonitor_UserInfo_Tests.m
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

#import <XCTest/XCTest.h>

#import "KSCrashMonitor_UserInfo.h"
#import "KSKeyValueStore.h"

#include <string.h>

// Declared in the .c file for testing
extern void kscm_userinfo_test_reset(void);
extern KSKeyValueStore *kscm_userinfo_test_getStore(void);
extern bool kscm_userinfo_test_createStore(const char *path);

#pragma mark - Helpers

/** Iterate the store via kskvs_iterate and build a dictionary of resolved values. */
static void dictOnString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    NSString *nsVal = [[NSString alloc] initWithBytes:value length:valueLen encoding:NSUTF8StringEncoding];
    if (nsKey && nsVal) dict[nsKey] = nsVal;
}

static void dictOnInt64(const char *key, uint16_t keyLen, int64_t value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) dict[nsKey] = @(value);
}

static void dictOnUInt64(const char *key, uint16_t keyLen, uint64_t value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) dict[nsKey] = @(value);
}

static void dictOnDouble(const char *key, uint16_t keyLen, double value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) dict[nsKey] = @(value);
}

static void dictOnBool(const char *key, uint16_t keyLen, bool value, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *nsKey = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    if (nsKey) dict[nsKey] = @(value);
}

static NSDictionary *currentUserInfoDict(void)
{
    KSKeyValueStore *store = kscm_userinfo_test_getStore();
    if (store == NULL) {
        return nil;
    }

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    KSKVSCallbacks callbacks = {
        .onString = dictOnString,
        .onInt64 = dictOnInt64,
        .onUInt64 = dictOnUInt64,
        .onDouble = dictOnDouble,
        .onBool = dictOnBool,
    };
    kskvs_iterate(store, &callbacks, (__bridge void *)dict);

    return dict.count > 0 ? [dict copy] : nil;
}

#pragma mark - Tests

@interface KSCrashMonitor_UserInfo_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_UserInfo_Tests

- (void)setUp
{
    [super setUp];
    kscm_userinfo_test_reset();
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *storePath = [self.tempDir stringByAppendingPathComponent:@"test.kskvs"];
    kscm_userinfo_test_createStore(storePath.UTF8String);
}

- (void)tearDown
{
    kscm_userinfo_test_reset();
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Basic Types

- (void)testSetString
{
    kscm_userinfo_setString("name", "Alice");
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"name"], @"Alice");
}

- (void)testSetInt64
{
    kscm_userinfo_setInt64("count", -42);
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"count"], @(-42));
}

- (void)testSetUInt64
{
    kscm_userinfo_setUInt64("big", UINT64_MAX);
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"big"], @(UINT64_MAX));
}

- (void)testSetDouble
{
    kscm_userinfo_setDouble("pi", 3.14159);
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualWithAccuracy([dict[@"pi"] doubleValue], 3.14159, 1e-10);
}

- (void)testSetBoolTrue
{
    kscm_userinfo_setBool("flag", true);
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"flag"], @YES);
}

- (void)testSetBoolFalse
{
    kscm_userinfo_setBool("flag", false);
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"flag"], @NO);
}

#pragma mark - Remove

- (void)testRemoveKey
{
    kscm_userinfo_setString("temp", "value");
    XCTAssertNotNil(currentUserInfoDict()[@"temp"]);

    kscm_userinfo_removeValue("temp");
    XCTAssertNil(currentUserInfoDict());
}

- (void)testSetStringNullRemoves
{
    kscm_userinfo_setString("key", "val");
    kscm_userinfo_setString("key", NULL);
    XCTAssertNil(currentUserInfoDict());
}

#pragma mark - Last Write Wins

- (void)testLastWriteWins
{
    kscm_userinfo_setString("color", "red");
    kscm_userinfo_setString("color", "blue");
    kscm_userinfo_setString("color", "green");
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"color"], @"green");
}

- (void)testOverwriteWithDifferentType
{
    kscm_userinfo_setString("val", "hello");
    kscm_userinfo_setInt64("val", 99);
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"val"], @(99));
}

#pragma mark - Multiple Keys

- (void)testMultipleKeys
{
    kscm_userinfo_setString("a", "1");
    kscm_userinfo_setInt64("b", 2);
    kscm_userinfo_setBool("c", true);

    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"a"], @"1");
    XCTAssertEqualObjects(dict[@"b"], @(2));
    XCTAssertEqualObjects(dict[@"c"], @YES);
}

#pragma mark - Edge Cases

- (void)testNullKeyIsIgnored
{
    kscm_userinfo_setString(NULL, "val");
    XCTAssertNil(currentUserInfoDict());
}

- (void)testEmptyKeyIsIgnored
{
    kscm_userinfo_setString("", "val");
    XCTAssertNil(currentUserInfoDict());
}

- (void)testEmptyStringValue
{
    kscm_userinfo_setString("empty", "");
    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"empty"], @"");
}

#pragma mark - Compaction

- (void)testCompactionReducesOffset
{
    // Write many values for the same key to fill the buffer, then set a final
    // value. Compaction should keep only the last record.
    for (int i = 0; i < 100; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "value_%d", i);
        kscm_userinfo_setString("repeated", buf);
    }

    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"repeated"], @"value_99");
}

- (void)testCompactionRemovesTombstones
{
    kscm_userinfo_setString("a", "1");
    kscm_userinfo_setString("b", "2");
    kscm_userinfo_removeValue("a");

    // Force compaction by filling enough to trigger it
    for (int i = 0; i < 200; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "val_%d", i);
        kscm_userinfo_setString("fill", buf);
    }

    NSDictionary *dict = currentUserInfoDict();
    XCTAssertNil(dict[@"a"]);
    XCTAssertNotNil(dict[@"fill"]);
}

#pragma mark - Growth

- (void)testGrowthBeyondInitialCapacity
{
    // Write enough data to exceed the 4096 initial capacity
    for (int i = 0; i < 500; i++) {
        char key[32];
        snprintf(key, sizeof(key), "key_%d", i);
        char val[32];
        snprintf(val, sizeof(val), "value_%d", i);
        kscm_userinfo_setString(key, val);
    }

    NSDictionary *dict = currentUserInfoDict();
    XCTAssertEqualObjects(dict[@"key_0"], @"value_0");
    XCTAssertEqualObjects(dict[@"key_499"], @"value_499");
    XCTAssertEqual(dict.count, 500u);
}

@end
