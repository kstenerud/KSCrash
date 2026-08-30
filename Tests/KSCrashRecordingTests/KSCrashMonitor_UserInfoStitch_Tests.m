//
//  KSCrashMonitor_UserInfoStitch_Tests.m
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
#import "KSCrashReportFields.h"
#import "KSKeyValueStore.h"

#include <string.h>

#pragma mark - Helpers

static const KSKVSConfig kTestConfig = {
    .initialCapacity = 4096,
};

static NSString *createTempDir(void)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

/** Build a sidecar file using KSKeyValueStore API. Returns the file path. */
static NSString *buildSidecarFile(NSString *dir, void (^block)(KSKeyValueStore *store))
{
    NSString *path = [dir stringByAppendingPathComponent:@"UserInfo.ksscr"];
    KSKeyValueStore *store = kskvs_create(path.UTF8String, KSKVSModeReadWriteCreate, &kTestConfig, NULL);
    if (store == NULL) {
        return nil;
    }
    if (block) {
        block(store);
    }
    kskvs_destroy(store);
    return path;
}

static NSDictionary *makeMinimalReport(void)
{
    return @{
        @"crash" : @ { @"error" : @ { @"type" : @"signal" } },
    };
}

static NSDictionary *makeReportWithUserSection(NSDictionary *user)
{
    return @{
        @"crash" : @ { @"error" : @ { @"type" : @"signal" } },
        KSCrashField_User : user,
    };
}

/** Write raw bytes to a file (for invalid-sidecar tests). */
static NSString *writeRawSidecar(NSString *dir, NSData *data)
{
    NSString *path = [dir stringByAppendingPathComponent:@"UserInfo.ksscr"];
    [data writeToFile:path atomically:YES];
    return path;
}

#pragma mark - Tests

@interface KSCrashMonitor_UserInfoStitch_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_UserInfoStitch_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = createTempDir();
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - NULL / Invalid Input

- (void)testNullReportReturnsNull
{
    XCTAssertTrue(kscm_userinfo_createStitchedReport(NULL, "/tmp/fake", KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(
        kscm_userinfo_createStitchedReport((__bridge CFDictionaryRef) @{}, NULL, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testMissingSidecarFileReturnsNull
{
    NSString *missing = [self.tempDir stringByAppendingPathComponent:@"missing.ksscr"];
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef) @{}, missing.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

#pragma mark - Invalid Sidecar

- (void)testBadMagicReturnsNull
{
    // Write raw bytes with wrong magic -- KSKeyValueStore will reject it.
    uint8_t badHeader[12] = { 0xEF, 0xBE, 0xAD, 0xDE, 1, 0, 0, 0, 12, 0, 0, 0 };
    NSData *data = [NSData dataWithBytes:badHeader length:sizeof(badHeader)];
    NSString *path = writeRawSidecar(self.tempDir, data);

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

- (void)testEmptySidecarReturnsNull
{
    NSString *path = writeRawSidecar(self.tempDir, [NSData data]);
    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

#pragma mark - Stitch String Values

- (void)testStitchStringValue
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "user_id", "abc123");
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"user_id"], @"abc123");
}

- (void)testStitchDropsAScalarJSONRecord
{
    // The writer refuses non-container JSON, so scalar bytes can only come
    // from a torn or foreign file; hand-build one and prove the reader
    // refuses them too. Layout: header + one JSON record with body "j" + "5".
    struct __attribute__((packed)) {
        uint32_t magic;
        uint32_t version;
        uint32_t offset;
        uint16_t keyLen;
        uint8_t type;
        uint16_t valueLen;
        char body[2];
    } image = {
        .magic = 0x6B736B76u,
        .version = 1,
        .offset = sizeof(image),
        .keyLen = 1,
        .type = 7,  // JSON
        .valueLen = 1,
        .body = { 'j', '5' },
    };
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"scalar.kvs"];
    XCTAssertTrue([[NSData dataWithBytes:&image length:sizeof(image)] writeToFile:path atomically:YES]);

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);
    XCTAssertNil(result[KSCrashField_User][@"j"], @"a scalar in a JSON record is absence, not a value");
}

- (void)testStitchJSONContainerValues
{
    // The nulls persist (the write path stores containers as given) and are
    // dropped here at read: the stitched report never carries an NSNull.
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        const char *tags = "[\"a\",null,\"b\"]";
        kskvs_setJSON(store, "tags", tags, strlen(tags));
        const char *cart = "{\"items\":3,\"nope\":null,\"flags\":[true]}";
        kskvs_setJSON(store, "cart", cart, strlen(cart));
        const char *bad = "{broken";
        kskvs_setJSON(store, "bad", bad, strlen(bad));
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *user = result[KSCrashField_User];
    NSArray *expectedTags = @[ @"a", @"b" ];
    XCTAssertEqualObjects(user[@"tags"], expectedTags);
    NSDictionary *expectedCart = @{ @"items" : @3, @"flags" : @[ @YES ] };
    XCTAssertEqualObjects(user[@"cart"], expectedCart);
    XCTAssertNil(user[@"bad"], @"undecodable JSON bytes drop the entry, never fail the stitch");
}

- (void)testStitchDropsAJSONRecordWithInvalidUTF8
{
    // Parses as JSON structure but the string bytes are invalid UTF-8 (a torn
    // or foreign record): the entry is absence, and the stitch must not crash.
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        const char bad[] = "[\"\xC3\x28\"]";
        kskvs_setJSON(store, "bad", bad, sizeof(bad) - 1);
        kskvs_setString(store, "good", "v");
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *user = result[KSCrashField_User];
    XCTAssertNil(user[@"bad"]);
    XCTAssertEqualObjects(user[@"good"], @"v");
}

#pragma mark - Stitch Integer Values

- (void)testStitchInt64Value
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setInt64(store, "score", -999);
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"score"], @(-999));
}

#pragma mark - Stitch Bool Values

- (void)testStitchBoolValue
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setBool(store, "premium", true);
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"premium"], @YES);
}

#pragma mark - Stitch Double Values

- (void)testStitchDoubleValue
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setDouble(store, "lat", 37.7749);
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualWithAccuracy([result[KSCrashField_User][@"lat"] doubleValue], 37.7749, 1e-4);
}

#pragma mark - Last Write Wins

- (void)testLastWriteWins
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "color", "red");
        kskvs_setString(store, "color", "blue");
        kskvs_setString(store, "color", "green");
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"color"], @"green");
}

#pragma mark - Tombstones

- (void)testTombstoneExcludesKey
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "temp", "data");
        kskvs_removeValue(store, "temp");
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    // Sidecar has no live keys -> returns unchanged copy (NULL means failure)
    XCTAssertTrue(result != nil);
}

- (void)testTombstoneRemovesExistingUserKey
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "keep", "yes");
        kskvs_setString(store, "remove_me", "gone");
        kskvs_removeValue(store, "remove_me");
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"keep"], @"yes");
    XCTAssertNil(result[KSCrashField_User][@"remove_me"]);
}

- (void)testTombstoneRemovesPreExistingReportKey
{
    // Sidecar only has a removal for "old_key" which exists in the report.
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_removeValue(store, "old_key");
    });

    NSDictionary *report = makeReportWithUserSection(@{ @"old_key" : @"old_val", @"keep" : @"yes" });
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertNil(result[KSCrashField_User][@"old_key"]);
    XCTAssertEqualObjects(result[KSCrashField_User][@"keep"], @"yes");
}

#pragma mark - Merge With Existing User Section

- (void)testMergeWithExistingUserSection
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "new_key", "new_val");
    });

    NSDictionary *report = makeReportWithUserSection(@{ @"old_key" : @"old_val" });
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *user = result[KSCrashField_User];
    XCTAssertEqualObjects(user[@"old_key"], @"old_val");
    XCTAssertEqualObjects(user[@"new_key"], @"new_val");
}

- (void)testSidecarOverridesExistingUserKey
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "shared", "from_sidecar");
    });

    NSDictionary *report = makeReportWithUserSection(@{ @"shared" : @"from_json" });
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"shared"], @"from_sidecar");
}

#pragma mark - Empty Report

- (void)testStitchIntoEmptyReport
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "key", "val");
    });

    // Report with no user section
    NSDictionary *report = @{ @"crash" : @ {} };
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    XCTAssertEqualObjects(result[KSCrashField_User][@"key"], @"val");
}

#pragma mark - Multiple Types

- (void)testMultipleTypesInSingleSidecar
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "name", "Test");
        kskvs_setInt64(store, "count", 42);
        kskvs_setBool(store, "active", true);
        kskvs_setDouble(store, "score", 9.5);
    });

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *user = result[KSCrashField_User];
    XCTAssertEqualObjects(user[@"name"], @"Test");
    XCTAssertEqualObjects(user[@"count"], @(42));
    XCTAssertEqualObjects(user[@"active"], @YES);
    XCTAssertEqualWithAccuracy([user[@"score"] doubleValue], 9.5, 1e-10);
}

- (void)testHeaderOnlySidecarReturnsInputUnchanged
{
    // Create a sidecar with no records.
    NSString *path = buildSidecarFile(self.tempDir, nil);

    NSDictionary *report = makeMinimalReport();
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_userinfo_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    // No records -> returns unchanged copy (NULL means failure)
    XCTAssertTrue(result != nil);
}

@end
