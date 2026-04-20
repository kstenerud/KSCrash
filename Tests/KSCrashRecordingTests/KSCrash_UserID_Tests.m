//
//  KSCrash_UserID_Tests.m
//
//  Created by Alexander Cohen on 2026-04-19.
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

#import "KSCrash.h"
#import "KSCrashMonitor_UserInfo.h"
#import "KSKeyValueStore.h"

// Declared in KSCrashMonitor_UserInfo.c for testing.
extern void kscm_userinfo_test_reset(void);
extern KSKeyValueStore *kscm_userinfo_test_getStore(void);
extern bool kscm_userinfo_test_createStore(const char *path);

#pragma mark - Store inspection helpers

static void collectString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)ctx;
    NSString *k = [[NSString alloc] initWithBytes:key length:keyLen encoding:NSUTF8StringEncoding];
    NSString *v = [[NSString alloc] initWithBytes:value length:valueLen encoding:NSUTF8StringEncoding];
    if (k && v) {
        dict[k] = v;
    }
}

static NSDictionary<NSString *, NSString *> *currentStringValues(void)
{
    KSKeyValueStore *store = kscm_userinfo_test_getStore();
    if (store == NULL) {
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *dict = [NSMutableDictionary dictionary];
    KSKVSCallbacks callbacks = { .onString = collectString };
    kskvs_iterate(store, &callbacks, (__bridge void *)dict);
    return dict;
}

@interface KSCrash_UserID_Tests : XCTestCase
@end

@implementation KSCrash_UserID_Tests {
    NSString *_tempDir;
}

- (void)setUp
{
    [super setUp];
    kscm_userinfo_test_reset();
    _tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:_tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *storePath = [_tempDir stringByAppendingPathComponent:@"userinfo.ksskv"];
    XCTAssertTrue(kscm_userinfo_test_createStore(storePath.UTF8String),
                  @"Test setup must create a UserInfo store for write-through verification");
}

- (void)tearDown
{
    kscm_userinfo_test_reset();
    if (_tempDir) {
        [[NSFileManager defaultManager] removeItemAtPath:_tempDir error:nil];
    }
    [super tearDown];
}

- (void)test_setUserID_writesReservedKeyToUserInfoSidecar
{
    [KSCrash.sharedInstance setUserID:@"alice"];

    NSDictionary<NSString *, NSString *> *values = currentStringValues();
    XCTAssertEqualObjects(values[@"com.kscrash.userid"], @"alice");
}

- (void)test_setUserID_replacesPreviousValue
{
    [KSCrash.sharedInstance setUserID:@"alice"];
    [KSCrash.sharedInstance setUserID:@"bob"];

    NSDictionary<NSString *, NSString *> *values = currentStringValues();
    XCTAssertEqualObjects(values[@"com.kscrash.userid"], @"bob");
}

- (void)test_setUserID_nilRemovesFromSidecar
{
    [KSCrash.sharedInstance setUserID:@"alice"];
    [KSCrash.sharedInstance setUserID:nil];

    NSDictionary<NSString *, NSString *> *values = currentStringValues();
    XCTAssertNil(values[@"com.kscrash.userid"], @"Passing nil must remove the key from the sidecar");
}

@end
