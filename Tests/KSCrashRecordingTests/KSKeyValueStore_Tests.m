//
//  KSKeyValueStore_Tests.m
//
//  Created by Alexander Cohen on 2026-08-14.
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

#import "KSKeyValueStore.h"

static void collectString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *k = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    NSString *v = [[NSString alloc] initWithBytes:value length:valueLen encoding:NSUTF8StringEncoding];
    if (k && v) {
        dict[k] = v;
    }
}

static void lookupTestOnInt64(__unused const char *key, __unused uint16_t keyLen, int64_t value, void *ctx)
{
    void (^block)(int64_t) = (__bridge void (^)(int64_t))ctx;
    block(value);
}

static void lookupTestOnString(__unused const char *key, __unused uint16_t keyLen, __unused const char *value,
                               __unused uint16_t valueLen, void *ctx)
{
    void (^block)(BOOL) = (__bridge void (^)(BOOL))ctx;
    block(NO);
}

static void lookupTestOnRemoved(__unused const char *key, __unused uint16_t keyLen, void *ctx)
{
    void (^block)(BOOL) = (__bridge void (^)(BOOL))ctx;
    block(YES);
}

@interface KSKeyValueStore_Tests : XCTestCase
@end

@implementation KSKeyValueStore_Tests {
    NSString *_dir;
}

- (void)setUp
{
    [super setUp];
    _dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:_dir error:nil];
    [super tearDown];
}

- (NSString *)path
{
    return [_dir stringByAppendingPathComponent:@"store.kvs"];
}

- (KSKVSConfig)config
{
    return (KSKVSConfig) { .initialCapacity = 4096, .maxKeyLength = 64, .maxStringLength = 256 };
}

- (void)test_create_roundTrip_reportsSuccess
{
    KSKVSConfig config = [self config];
    KSKVSOpenStatus status = KSKVSOpenFailure;
    KSKeyValueStore *writer = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, &status);
    XCTAssertTrue(writer != NULL);
    XCTAssertEqual(status, KSKVSOpenSuccess);
    kskvs_setString(writer, "k", "v");
    kskvs_destroy(writer);

    status = KSKVSOpenFailure;
    KSKeyValueStore *reader = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, &status);
    XCTAssertTrue(reader != NULL);
    XCTAssertEqual(status, KSKVSOpenSuccess);
    kskvs_destroy(reader);
}

static void lookupOnString(__unused const char *key, __unused uint16_t keyLen, __unused const char *value,
                           __unused uint16_t valueLen, void *ctx)
{
    (*(int *)ctx)++;
}

/** How many string records resolve for this key. */
static int stringHitsForKey(KSKeyValueStore *store, const char *key)
{
    int hits = 0;
    KSKVSCallbacks callbacks = { .onString = lookupOnString };
    kskvs_lookup(store, key, &callbacks, &hits);
    return hits;
}

- (void)test_write_onAReadModeStore_isRejected_andTheStoreIsUnchanged
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *writer = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(kskvs_setString(writer, "k", "v"));
    kskvs_destroy(writer);

    KSKeyValueStore *reader = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, NULL);
    XCTAssertTrue(reader != NULL);
    XCTAssertFalse(kskvs_setString(reader, "k2", "fits-without-growing"));
    XCTAssertFalse(kskvs_removeValue(reader, "k"));
    XCTAssertEqual(stringHitsForKey(reader, "k"), 1);
    XCTAssertEqual(stringHitsForKey(reader, "k2"), 0);
    kskvs_destroy(reader);
}

- (void)test_setWithOverlongKey_isRejected_notTruncated
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    char longKey[66];
    memset(longKey, 'k', sizeof(longKey) - 1);
    longKey[sizeof(longKey) - 1] = '\0';  // 65 chars, one past maxKeyLength

    XCTAssertFalse(kskvs_setString(store, longKey, "v"));
    XCTAssertEqual(stringHitsForKey(store, longKey), 0, @"nothing stored under the full key");
    longKey[64] = '\0';  // the 64-char prefix a truncating writer would have stored
    XCTAssertEqual(stringHitsForKey(store, longKey), 0, @"nothing stored under a truncation either");
    XCTAssertTrue(kskvs_removeValue(store, longKey), @"a limit-length key is accepted");

    kskvs_destroy(store);
}

- (void)test_setWithLimitLengthKeyAndValue_isAccepted
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    char key[65];
    memset(key, 'k', sizeof(key) - 1);
    key[sizeof(key) - 1] = '\0';  // exactly maxKeyLength
    char value[257];
    memset(value, 'v', sizeof(value) - 1);
    value[sizeof(value) - 1] = '\0';  // exactly maxStringLength

    XCTAssertTrue(kskvs_setString(store, key, value));
    XCTAssertEqual(stringHitsForKey(store, key), 1);

    kskvs_destroy(store);
}

- (void)test_setWithOverlongStringValue_isRejected
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    char value[258];
    memset(value, 'v', sizeof(value) - 1);
    value[sizeof(value) - 1] = '\0';  // 257 chars, one past maxStringLength

    XCTAssertFalse(kskvs_setString(store, "k", value));
    XCTAssertEqual(stringHitsForKey(store, "k"), 0, @"the key holds nothing, not a shortened value");

    kskvs_destroy(store);
}

- (void)test_read_absentFile_reportsAbsent
{
    KSKVSOpenStatus status = KSKVSOpenSuccess;
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, &status);
    XCTAssertTrue(store == NULL);
    XCTAssertEqual(status, KSKVSOpenAbsent);
}

- (void)test_read_truncatedFile_reportsCorrupt
{
    [[NSData dataWithBytes:"\x01\x02" length:2] writeToFile:self.path atomically:YES];
    KSKVSOpenStatus status = KSKVSOpenSuccess;
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, &status);
    XCTAssertTrue(store == NULL);
    XCTAssertEqual(status, KSKVSOpenCorrupt);
}

- (void)test_read_badMagic_reportsCorrupt
{
    uint8_t bytes[32];
    memset(bytes, 0xFF, sizeof(bytes));
    [[NSData dataWithBytes:bytes length:sizeof(bytes)] writeToFile:self.path atomically:YES];
    KSKVSOpenStatus status = KSKVSOpenSuccess;
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, &status);
    XCTAssertTrue(store == NULL);
    XCTAssertEqual(status, KSKVSOpenCorrupt);
}

- (void)test_read_unreadableFile_reportsFailure
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *writer = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(writer != NULL);
    kskvs_destroy(writer);
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0 } ofItemAtPath:self.path error:nil];

    KSKVSOpenStatus status = KSKVSOpenSuccess;
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, &status);
    XCTAssertTrue(store == NULL);
    XCTAssertEqual(status, KSKVSOpenFailure);

    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0644 } ofItemAtPath:self.path error:nil];
}

#pragma mark - Compaction and growth

- (NSDictionary<NSString *, NSString *> *)stringValuesIn:(KSKeyValueStore *)store
{
    NSMutableDictionary<NSString *, NSString *> *dict = [NSMutableDictionary dictionary];
    KSKVSCallbacks callbacks = { .onString = collectString };
    kskvs_iterate(store, &callbacks, (__bridge void *)dict);
    return dict;
}

- (void)test_write_compactionKeepsOnlyTheLastRecordForAKey
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);
    for (int i = 0; i < 100; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "value_%d", i);
        kskvs_setString(store, "repeated", buf);
    }
    XCTAssertEqualObjects([self stringValuesIn:store][@"repeated"], @"value_99");
    kskvs_destroy(store);
}

- (void)test_write_compactionDropsTombstones
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);
    kskvs_setString(store, "a", "1");
    kskvs_setString(store, "b", "2");
    kskvs_removeValue(store, "a");
    // Enough churn to force compaction past the removed key.
    for (int i = 0; i < 200; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "val_%d", i);
        kskvs_setString(store, "fill", buf);
    }
    NSDictionary *values = [self stringValuesIn:store];
    XCTAssertNil(values[@"a"]);
    XCTAssertEqualObjects(values[@"b"], @"2");
    XCTAssertNotNil(values[@"fill"]);
    kskvs_destroy(store);
}

- (void)test_write_growsBeyondInitialCapacity
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);
    for (int i = 0; i < 500; i++) {
        char key[32];
        snprintf(key, sizeof(key), "key_%d", i);
        char val[32];
        snprintf(val, sizeof(val), "value_%d", i);
        kskvs_setString(store, key, val);
    }
    NSDictionary *values = [self stringValuesIn:store];
    XCTAssertEqualObjects(values[@"key_0"], @"value_0");
    XCTAssertEqualObjects(values[@"key_499"], @"value_499");
    XCTAssertEqual(values.count, 500u);
    kskvs_destroy(store);
}

#pragma mark - Lookup

- (void)test_lookup_answersTheLatestWriteForTheKeyOnly
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);
    kskvs_setString(store, "other", "noise");
    kskvs_setString(store, "k", "first");
    kskvs_setInt64(store, "k", 42);
    NSMutableDictionary *strings = [NSMutableDictionary dictionary];
    __block int64_t intValue = 0;
    __block int fired = 0;
    KSKVSCallbacks callbacks = { .onString = collectString };
    kskvs_lookup(store, "other", &callbacks, (__bridge void *)strings);
    XCTAssertEqualObjects(strings[@"other"], @"noise");
    XCTAssertEqual(strings.count, 1u, @"only the looked-up key fires");
    // The last write for "k" was the int64; the string record must not fire.
    void (^onInt)(int64_t) = ^(int64_t value) {
        intValue = value;
        fired++;
    };
    KSKVSCallbacks intCallbacks = { .onString = collectString, .onInt64 = lookupTestOnInt64 };
    kskvs_lookup(store, "k", &intCallbacks, (__bridge void *)onInt);
    XCTAssertEqual(intValue, 42);
    XCTAssertEqual(fired, 1);
    kskvs_destroy(store);
}

- (void)test_lookup_firesOnRemovedForATombstone_andNothingWhenAbsent
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);
    kskvs_setString(store, "gone", "was here");
    kskvs_removeValue(store, "gone");
    __block int removed = 0;
    __block int strings = 0;
    void (^witness)(BOOL) = ^(BOOL wasRemoved) {
        if (wasRemoved) {
            removed++;
        } else {
            strings++;
        }
    };
    KSKVSCallbacks callbacks = { .onString = lookupTestOnString, .onRemoved = lookupTestOnRemoved };
    kskvs_lookup(store, "gone", &callbacks, (__bridge void *)witness);
    XCTAssertEqual(removed, 1);
    XCTAssertEqual(strings, 0);
    kskvs_lookup(store, "never", &callbacks, (__bridge void *)witness);
    XCTAssertEqual(removed, 1, @"an absent key fires nothing");
    XCTAssertEqual(strings, 0);
    kskvs_destroy(store);
}

@end
