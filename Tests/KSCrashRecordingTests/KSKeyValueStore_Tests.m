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

@end
