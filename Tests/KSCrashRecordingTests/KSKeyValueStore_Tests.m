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
    return (KSKVSConfig) { .initialCapacity = 4096 };
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

    // One past the record format's 64KB key bound.
    size_t longLen = (size_t)UINT16_MAX + 1;
    char *longKey = malloc(longLen + 1);
    memset(longKey, 'k', longLen);
    longKey[longLen] = '\0';

    XCTAssertFalse(kskvs_setString(store, longKey, "v"));
    XCTAssertEqual(stringHitsForKey(store, longKey), 0, @"nothing stored under the full key");
    longKey[UINT16_MAX] = '\0';  // the prefix a truncating writer would have stored
    XCTAssertEqual(stringHitsForKey(store, longKey), 0, @"nothing stored under a truncation either");
    XCTAssertTrue(kskvs_removeValue(store, longKey), @"a bound-length key is accepted");

    free(longKey);
    kskvs_destroy(store);
}

- (void)test_setWithLargeKeyAndValue_isAccepted
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    // Far past the retired per-store limits: only the record format's 64KB
    // bound applies, and the store grows to hold the record.
    char key[1025];
    memset(key, 'k', sizeof(key) - 1);
    key[sizeof(key) - 1] = '\0';
    size_t valueLen = UINT16_MAX;
    char *value = malloc(valueLen + 1);
    memset(value, 'v', valueLen);
    value[valueLen] = '\0';

    XCTAssertTrue(kskvs_setString(store, key, value));
    XCTAssertEqual(stringHitsForKey(store, key), 1);

    free(value);
    kskvs_destroy(store);
}

- (void)test_setWithOverlongStringValue_isRejected
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    // One past the record format's 64KB value bound.
    size_t valueLen = (size_t)UINT16_MAX + 1;
    char *value = malloc(valueLen + 1);
    memset(value, 'v', valueLen);
    value[valueLen] = '\0';

    XCTAssertFalse(kskvs_setString(store, "k", value));
    XCTAssertEqual(stringHitsForKey(store, "k"), 0, @"the key holds nothing, not a shortened value");

    free(value);
    kskvs_destroy(store);
}

static void collectJSON(const char *key, uint16_t keyLen, const char *json, uint16_t jsonLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *k = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    NSString *v = [[NSString alloc] initWithBytes:json length:jsonLen encoding:NSUTF8StringEncoding];
    if (k && v) {
        dict[k] = v;
    }
}

- (void)test_setJSON_roundTripsTheBytes_lastWriteWins
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    const char *first = "[1,2]";
    const char *second = "{\"a\":[true,null]}";
    XCTAssertTrue(kskvs_setJSON(store, "j", first, strlen(first)));
    XCTAssertTrue(kskvs_setJSON(store, "j", second, strlen(second)));
    XCTAssertFalse(kskvs_setJSON(store, "j", NULL, 0), @"no bytes is not a value");
    kskvs_destroy(store);

    KSKeyValueStore *reader = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, NULL);
    XCTAssertTrue(reader != NULL);
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    KSKVSCallbacks callbacks = { .onJSON = collectJSON };
    kskvs_iterate(reader, &callbacks, (__bridge void *)values);
    kskvs_destroy(reader);

    XCTAssertEqualObjects(values, @{ @"j" : @(second) });
}

- (void)test_setJSON_acceptsOnlyContainers
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    // Scalars have native record types; JSON bytes must open a container.
    const char *scalars[] = { "5", "\"s\"", "true", "null", "  " };
    for (size_t i = 0; i < sizeof(scalars) / sizeof(scalars[0]); i++) {
        XCTAssertFalse(kskvs_setJSON(store, "j", scalars[i], strlen(scalars[i])), @"%s", scalars[i]);
    }
    const char *padded = "  \n[1]";
    XCTAssertTrue(kskvs_setJSON(store, "j", padded, strlen(padded)), @"leading whitespace is fine");

    kskvs_destroy(store);
}

- (void)test_removeValue_tombstonesAJSONRecord
{
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    const char *json = "[1]";
    XCTAssertTrue(kskvs_setJSON(store, "j", json, strlen(json)));
    XCTAssertTrue(kskvs_removeValue(store, "j"));

    __block BOOL removed = NO;
    void (^onRemoved)(BOOL) = ^(BOOL isRemoved) {
        removed = isRemoved;
    };
    KSKVSCallbacks callbacks = { .onString = lookupTestOnString, .onRemoved = lookupTestOnRemoved };
    kskvs_lookup(store, "j", &callbacks, (__bridge void *)onRemoved);
    XCTAssertTrue(removed);
    kskvs_destroy(store);
}

- (void)test_unknownRecordType_isSkipped_notCorrupting
{
    // A future writer may add record types; an older reader must skip them
    // by length and keep reading. Hand-build: header + one type-99 record +
    // one string record.
    struct __attribute__((packed)) {
        uint32_t magic;
        uint32_t version;
        uint32_t offset;
        // record 1: unknown type
        uint16_t keyLen1;
        uint8_t type1;
        uint16_t valueLen1;
        char body1[4];  // "zz" + "xy"
        // record 2: string
        uint16_t keyLen2;
        uint8_t type2;
        uint16_t valueLen2;
        char body2[2];  // "k" + "v"
    } image = {
        .magic = 0x6B736B76u,
        .version = 1,
        .offset = sizeof(image),
        .keyLen1 = 2,
        .type1 = 99,
        .valueLen1 = 2,
        .body1 = { 'z', 'z', 'x', 'y' },
        .keyLen2 = 1,
        .type2 = 1,  // string
        .valueLen2 = 1,
        .body2 = { 'k', 'v' },
    };
    XCTAssertTrue([[NSData dataWithBytes:&image length:sizeof(image)] writeToFile:self.path atomically:YES]);

    KSKeyValueStore *reader = kskvs_create(self.path.UTF8String, KSKVSModeRead, NULL, NULL);
    XCTAssertTrue(reader != NULL);
    NSMutableDictionary *strings = [NSMutableDictionary dictionary];
    KSKVSCallbacks callbacks = { .onString = collectString };
    kskvs_iterate(reader, &callbacks, (__bridge void *)strings);
    kskvs_destroy(reader);

    XCTAssertEqualObjects(strings, @{ @"k" : @"v" });
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

- (void)test_write_stopsAtTheCapacityCeiling
{
    // Records are bounded individually but their number is not, and the file
    // only grows within a run, so the ceiling is the only thing keeping a live
    // store bounded on disk. Past it the write is refused, not truncated.
    KSKVSConfig config = [self config];
    KSKeyValueStore *store = kskvs_create(self.path.UTF8String, KSKVSModeReadWriteCreate, &config, NULL);
    XCTAssertTrue(store != NULL);

    char *value = malloc(60000);
    XCTAssertTrue(value != NULL);
    memset(value, 'x', 59999);
    value[59999] = '\0';

    BOOL refused = NO;
    for (int i = 0; i < 400 && !refused; i++) {
        char key[32];
        snprintf(key, sizeof(key), "key_%d", i);
        refused = !kskvs_setString(store, key, value);
    }
    free(value);
    XCTAssertTrue(refused, @"the store must refuse a write once it would cross the ceiling");

    // The refusal leaves the store usable: earlier records still read, and a
    // small write still succeeds.
    XCTAssertEqual([[self stringValuesIn:store][@"key_0"] length], 59999u);
    XCTAssertTrue(kskvs_setString(store, "small", "v"));
    kskvs_destroy(store);

    NSNumber *size = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.path
                                                                       error:nil] objectForKey:NSFileSize];
    XCTAssertLessThanOrEqual(size.unsignedLongLongValue, 16ull * 1024 * 1024);
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
