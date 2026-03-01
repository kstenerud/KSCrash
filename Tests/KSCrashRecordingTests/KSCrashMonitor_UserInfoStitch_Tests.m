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
#import "KSJSONCodecObjC.h"
#import "KSKeyValueStore.h"

#include <string.h>

#pragma mark - Helpers

static const KSKVSConfig kTestConfig = {
    .initialCapacity = 4096,
    .maxKeyLength = 256,
    .maxStringLength = 1024,
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
    KSKeyValueStore *store = kskvs_create(path.UTF8String, KSKVSModeReadWriteCreate, &kTestConfig);
    if (store == NULL) {
        return nil;
    }
    if (block) {
        block(store);
    }
    kskvs_destroy(store);
    return path;
}

static NSString *jsonString(NSDictionary *dict)
{
    NSData *data = [KSJSONCodec encode:dict options:KSJSONEncodeOptionNone error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSDictionary *dictFromCString(const char *json)
{
    NSData *data = [NSData dataWithBytes:json length:strlen(json)];
    return [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
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
    XCTAssertTrue(kscm_userinfo_stitchReport(NULL, "/tmp/fake", KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(kscm_userinfo_stitchReport("{}", NULL, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testMissingSidecarFileReturnsNull
{
    NSString *missing = [self.tempDir stringByAppendingPathComponent:@"missing.ksscr"];
    char *result = kscm_userinfo_stitchReport("{}", missing.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Invalid Sidecar

- (void)testBadMagicReturnsNull
{
    // Write raw bytes with wrong magic — KSKeyValueStore will reject it.
    uint8_t badHeader[12] = { 0xEF, 0xBE, 0xAD, 0xDE, 1, 0, 0, 0, 12, 0, 0, 0 };
    NSData *data = [NSData dataWithBytes:badHeader length:sizeof(badHeader)];
    NSString *path = writeRawSidecar(self.tempDir, data);

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testEmptySidecarReturnsNull
{
    NSString *path = writeRawSidecar(self.tempDir, [NSData data]);
    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Stitch String Values

- (void)testStitchStringValue
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "user_id", "abc123");
    });

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"user_id"], @"abc123");
}

#pragma mark - Stitch Integer Values

- (void)testStitchInt64Value
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setInt64(store, "score", -999);
    });

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"score"], @(-999));
}

#pragma mark - Stitch Bool Values

- (void)testStitchBoolValue
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setBool(store, "premium", true);
    });

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"premium"], @YES);
}

#pragma mark - Stitch Double Values

- (void)testStitchDoubleValue
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setDouble(store, "lat", 37.7749);
    });

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualWithAccuracy([stitched[KSCrashField_User][@"lat"] doubleValue], 37.7749, 1e-4);
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
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"color"], @"green");
}

#pragma mark - Tombstones

- (void)testTombstoneExcludesKey
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "temp", "data");
        kskvs_removeValue(store, "temp");
    });

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    // Sidecar has no live keys -> returns NULL (no changes to report)
    XCTAssertTrue(result == NULL);
}

- (void)testTombstoneRemovesExistingUserKey
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "keep", "yes");
        kskvs_setString(store, "remove_me", "gone");
        kskvs_removeValue(store, "remove_me");
    });

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"keep"], @"yes");
    XCTAssertNil(stitched[KSCrashField_User][@"remove_me"]);
}

- (void)testTombstoneRemovesPreExistingReportKey
{
    // Sidecar only has a removal for "old_key" which exists in the report.
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_removeValue(store, "old_key");
    });

    NSDictionary *report = makeReportWithUserSection(@{ @"old_key" : @"old_val", @"keep" : @"yes" });
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertNil(stitched[KSCrashField_User][@"old_key"]);
    XCTAssertEqualObjects(stitched[KSCrashField_User][@"keep"], @"yes");
}

#pragma mark - Merge With Existing User Section

- (void)testMergeWithExistingUserSection
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "new_key", "new_val");
    });

    NSDictionary *report = makeReportWithUserSection(@{ @"old_key" : @"old_val" });
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *user = stitched[KSCrashField_User];
    XCTAssertEqualObjects(user[@"old_key"], @"old_val");
    XCTAssertEqualObjects(user[@"new_key"], @"new_val");
}

- (void)testSidecarOverridesExistingUserKey
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "shared", "from_sidecar");
    });

    NSDictionary *report = makeReportWithUserSection(@{ @"shared" : @"from_json" });
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"shared"], @"from_sidecar");
}

#pragma mark - Empty Report

- (void)testStitchIntoEmptyReport
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "key", "val");
    });

    // Report with no user section
    NSDictionary *report = @{ @"crash" : @ {} };
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_User][@"key"], @"val");
}

#pragma mark - Invalid JSON Report

- (void)testInvalidJSONReturnsNull
{
    NSString *path = buildSidecarFile(self.tempDir, ^(KSKeyValueStore *store) {
        kskvs_setString(store, "key", "val");
    });

    char *result = kscm_userinfo_stitchReport("not json", path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
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
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *user = stitched[KSCrashField_User];
    XCTAssertEqualObjects(user[@"name"], @"Test");
    XCTAssertEqualObjects(user[@"count"], @(42));
    XCTAssertEqualObjects(user[@"active"], @YES);
    XCTAssertEqualWithAccuracy([user[@"score"] doubleValue], 9.5, 1e-10);
}

- (void)testHeaderOnlySidecarReturnsNull
{
    // Create a sidecar with no records.
    NSString *path = buildSidecarFile(self.tempDir, nil);

    NSDictionary *report = makeMinimalReport();
    char *result =
        kscm_userinfo_stitchReport(jsonString(report).UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    // No records -> NULL
    XCTAssertTrue(result == NULL);
}

@end
