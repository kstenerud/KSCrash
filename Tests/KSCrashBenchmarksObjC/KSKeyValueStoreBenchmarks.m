//
//  KSKeyValueStoreBenchmarks.m
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

#import "KSBenchmarkTestCase.h"
#import "KSKeyValueStore.h"

static const KSKVSConfig kDefaultConfig = {
    .initialCapacity = 4096,
    .maxKeyLength = 256,
    .maxStringLength = 1024,
};

@interface KSKeyValueStoreBenchmarks : KSBenchmarkTestCaseObjC
@end

@implementation KSKeyValueStoreBenchmarks

- (NSString *)tempFilePath
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"kvs_bench_%@.kvs", [[NSUUID UUID] UUIDString]];
    return [tempDir stringByAppendingPathComponent:fileName];
}

- (void)cleanupFile:(NSString *)path
{
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

#pragma mark - Write Benchmarks

/// 100 string key-value writes to a fresh store.
- (void)testBenchmarkWriteStrings
{
    [self measureBlock:^{
        NSString *path = [self tempFilePath];
        KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &kDefaultConfig);
        XCTAssertTrue(store != NULL);

        for (int i = 0; i < 100; i++) {
            char key[32], value[64];
            snprintf(key, sizeof(key), "key_%d", i);
            snprintf(value, sizeof(value), "value_for_key_%d", i);
            kskvs_setString(store, key, value);
        }

        kskvs_destroy(store);
        [self cleanupFile:path];
    }];
}

/// 100 writes of mixed types (string, int64, double, bool, date).
- (void)testBenchmarkWriteMixedTypes
{
    [self measureBlock:^{
        NSString *path = [self tempFilePath];
        KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &kDefaultConfig);
        XCTAssertTrue(store != NULL);

        for (int i = 0; i < 100; i++) {
            char key[32];
            snprintf(key, sizeof(key), "key_%d", i);

            switch (i % 5) {
                case 0:
                    kskvs_setString(store, key, "mixed_value");
                    break;
                case 1:
                    kskvs_setInt64(store, key, (int64_t)i * 1000);
                    break;
                case 2:
                    kskvs_setDouble(store, key, (double)i * 3.14);
                    break;
                case 3:
                    kskvs_setBool(store, key, i % 2 == 0);
                    break;
                case 4:
                    kskvs_setDate(store, key, (uint64_t)i * 1000000000ULL);
                    break;
            }
        }

        kskvs_destroy(store);
        [self cleanupFile:path];
    }];
}

#pragma mark - Read Benchmarks

static void benchOnString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    (*(int *)ctx)++;
}

static void benchOnInt64(const char *key, uint16_t keyLen, int64_t value, void *ctx) { (*(int *)ctx)++; }

static void benchOnDouble(const char *key, uint16_t keyLen, double value, void *ctx) { (*(int *)ctx)++; }

static void benchOnBool(const char *key, uint16_t keyLen, bool value, void *ctx) { (*(int *)ctx)++; }

static void benchOnDate(const char *key, uint16_t keyLen, uint64_t ns, void *ctx) { (*(int *)ctx)++; }

static const KSKVSCallbacks kBenchCallbacks = {
    .onString = benchOnString,
    .onInt64 = benchOnInt64,
    .onDouble = benchOnDouble,
    .onBool = benchOnBool,
    .onDate = benchOnDate,
};

/// Iterate 100 resolved records via callbacks.
- (void)testBenchmarkIterate
{
    NSString *path = [self tempFilePath];
    KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &kDefaultConfig);
    XCTAssertTrue(store != NULL);

    for (int i = 0; i < 100; i++) {
        char key[32], value[64];
        snprintf(key, sizeof(key), "key_%d", i);
        snprintf(value, sizeof(value), "value_for_key_%d", i);
        kskvs_setString(store, key, value);
    }

    [self measureBlock:^{
        int count = 0;
        kskvs_iterate(store, &kBenchCallbacks, &count);
        XCTAssertEqual(count, 100);
    }];

    kskvs_destroy(store);
    [self cleanupFile:path];
}

#pragma mark - Overwrite / Compaction / Growth

/// 100 overwrites of a single key (append-only log growth).
- (void)testBenchmarkOverwriteSameKey
{
    [self measureBlock:^{
        NSString *path = [self tempFilePath];
        KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &kDefaultConfig);
        XCTAssertTrue(store != NULL);

        for (int i = 0; i < 100; i++) {
            char value[64];
            snprintf(value, sizeof(value), "overwrite_%d", i);
            kskvs_setString(store, "same_key", value);
        }

        kskvs_destroy(store);
        [self cleanupFile:path];
    }];
}

/// Trigger compaction by overwriting keys until the store runs out of space.
/// Uses a small initial capacity so compaction fires within reasonable iteration count.
- (void)testBenchmarkCompaction
{
    const KSKVSConfig smallConfig = {
        .initialCapacity = 512,
        .maxKeyLength = 64,
        .maxStringLength = 128,
    };

    [self measureBlock:^{
        NSString *path = [self tempFilePath];
        KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &smallConfig);
        XCTAssertTrue(store != NULL);

        // Repeatedly overwrite a small set of keys to fill the log with dead entries,
        // forcing compaction when space runs out.
        for (int round = 0; round < 10; round++) {
            for (int i = 0; i < 5; i++) {
                char key[16], value[32];
                snprintf(key, sizeof(key), "k%d", i);
                snprintf(value, sizeof(value), "round_%d_val_%d", round, i);
                kskvs_setString(store, key, value);
            }
        }

        kskvs_destroy(store);
        [self cleanupFile:path];
    }];
}

/// Fill a small initial capacity (512 bytes) to force multiple growths.
- (void)testBenchmarkGrowth
{
    const KSKVSConfig smallConfig = {
        .initialCapacity = 512,
        .maxKeyLength = 64,
        .maxStringLength = 256,
    };

    [self measureBlock:^{
        NSString *path = [self tempFilePath];
        KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &smallConfig);
        XCTAssertTrue(store != NULL);

        // Each key is unique so no compaction benefit — forces pure growth.
        for (int i = 0; i < 100; i++) {
            char key[32], value[64];
            snprintf(key, sizeof(key), "unique_key_%d", i);
            snprintf(value, sizeof(value), "growing_value_for_key_%d", i);
            kskvs_setString(store, key, value);
        }

        kskvs_destroy(store);
        [self cleanupFile:path];
    }];
}

#pragma mark - Lifecycle

/// Store lifecycle: create mmap + destroy.
- (void)testBenchmarkCreateDestroy
{
    [self measureBlock:^{
        NSString *path = [self tempFilePath];
        KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &kDefaultConfig);
        XCTAssertTrue(store != NULL);
        kskvs_destroy(store);
        [self cleanupFile:path];
    }];
}

/// Open existing store in read-only mode + iterate.
- (void)testBenchmarkReadOnly
{
    NSString *path = [self tempFilePath];
    KSKeyValueStore *store = kskvs_create([path UTF8String], KSKVSModeReadWriteCreate, &kDefaultConfig);
    XCTAssertTrue(store != NULL);

    for (int i = 0; i < 100; i++) {
        char key[32], value[64];
        snprintf(key, sizeof(key), "key_%d", i);
        snprintf(value, sizeof(value), "value_for_key_%d", i);
        kskvs_setString(store, key, value);
    }
    kskvs_destroy(store);

    [self measureBlock:^{
        KSKeyValueStore *roStore = kskvs_create([path UTF8String], KSKVSModeRead, NULL);
        XCTAssertTrue(roStore != NULL);

        int count = 0;
        kskvs_iterate(roStore, &kBenchCallbacks, &count);
        XCTAssertEqual(count, 100);

        kskvs_destroy(roStore);
    }];

    [self cleanupFile:path];
}

@end
