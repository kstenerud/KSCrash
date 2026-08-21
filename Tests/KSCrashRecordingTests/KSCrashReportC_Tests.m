//
//  KSCrashReportC_Tests.m
//
//  Created by Alexander Cohen on 2025-12-27.
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

#import "KSCrashMonitor.h"
#import "KSCrashMonitorAPI.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashMonitor_MachException.h"
#import "KSCrashMonitor_NSException.h"
#import "KSCrashReportC.h"
#import "KSJSONCodec.h"
#import "KSMachineContext.h"
#import "KSStackCursor_SelfThread.h"

#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>

static const char *customSectionMonitorId(__unused void *context) { return "TestCustomMonitor"; }
static const char *profileLikeMonitorId(__unused void *context) { return "profile"; }
static void writeTestMonitorSection(__unused const KSCrash_MonitorContext *eventContext,
                                    const KSCrashReportWriter *writer, __unused void *context)
{
    writer->addStringElement(writer, "custom_key", "custom_value");
}

/// A class the tests restrict via doNotIntrospectClasses.
@interface KSCrashTestRestrictedSecret : NSObject
@end
@implementation KSCrashTestRestrictedSecret
@end

@interface KSCrashReportC_Tests : XCTestCase
@end

@implementation KSCrashReportC_Tests {
    KSCrashMonitorAPI _customMonitorAPI;
    KSCrashMonitorAPI _profileLikeMonitorAPI;
}

- (void)setUp
{
    [super setUp];
    // Clear any existing userInfo before each test
    kscrashreport_setUserInfoJSON(NULL);
}

- (void)tearDown
{
    // Clean up after each test
    kscrashreport_setUserInfoJSON(NULL);
    kscm_removeMonitor(&_customMonitorAPI);
    kscm_removeMonitor(&_profileLikeMonitorAPI);
    [super tearDown];
}

/// A monitor-caused report for the monitor id `idFunc` returns, written and
/// read back.
- (NSDictionary *)writeReportForMonitor:(KSCrashMonitorAPI *)monitorAPI monitorId:(const char *(*)(void *))idFunc
{
    kscma_initAPI(monitorAPI);
    monitorAPI->monitorId = idFunc;
    monitorAPI->writeInReportSection = writeTestMonitorSection;
    kscm_addMonitor(monitorAPI);

    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));
    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "MONITORSECTIONTEST");
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.omitBinaryImages = true;
    context.monitorId = monitorAPI->monitorId(NULL);

    NSString *path = [self temporaryReportPath];
    NSDictionary *json = nil;
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);
        json = [self readJSONObjectAtPath:path];
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    return json;
}

- (void)testWriteStandardReportFencesACustomMonitorSection
{
    NSDictionary *error = [self writeReportForMonitor:&_customMonitorAPI
                                            monitorId:customSectionMonitorId][@"crash"][@"error"];

    XCTAssertEqualObjects(error[@"type"], @"TestCustomMonitor");
    XCTAssertEqualObjects(error[@"monitor_data"][@"TestCustomMonitor"][@"custom_key"], @"custom_value");
    XCTAssertNil(error[@"TestCustomMonitor"], @"The section lives only in the fenced namespace");
}

- (void)testWriteStandardReportKeepsTheProfileSectionAtItsSchemaKey
{
    NSDictionary *error = [self writeReportForMonitor:&_profileLikeMonitorAPI
                                            monitorId:profileLikeMonitorId][@"crash"][@"error"];

    XCTAssertEqualObjects(error[@"type"], @"profile");
    XCTAssertEqualObjects(error[@"profile"][@"custom_key"], @"custom_value");
    XCTAssertNil(error[@"monitor_data"], @"Profile is a typed section, not custom-monitor data");
}

- (NSString *)temporaryReportPath
{
    return [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"kscrash-report-%@.json", [NSUUID UUID].UUIDString]];
}

- (NSDictionary *)readJSONObjectAtPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data);
    if (data == nil) {
        return nil;
    }

    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    return json;
}

#pragma mark - Basic Functionality Tests

- (void)testSetAndGetUserInfo
{
    const char *testJSON = "{\"key\":\"value\"}";
    kscrashreport_setUserInfoJSON(testJSON);

    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertNotEqual(result, NULL, @"getUserInfoJSON should return non-NULL after setting");
    XCTAssertTrue(strcmp(result, testJSON) == 0, @"Retrieved JSON should match set JSON");
    free((void *)result);
}

- (void)testSetNullClearsUserInfo
{
    const char *testJSON = "{\"key\":\"value\"}";
    kscrashreport_setUserInfoJSON(testJSON);

    kscrashreport_setUserInfoJSON(NULL);

    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertEqual(result, NULL, @"getUserInfoJSON should return NULL after setting NULL");
}

- (void)testGetUserInfoReturnsNewCopy
{
    const char *testJSON = "{\"key\":\"value\"}";
    kscrashreport_setUserInfoJSON(testJSON);

    const char *result1 = kscrashreport_getUserInfoJSON();
    const char *result2 = kscrashreport_getUserInfoJSON();

    XCTAssertNotEqual(result1, result2, @"Each call should return a new copy");
    XCTAssertTrue(strcmp(result1, result2) == 0, @"Both copies should have same content");

    free((void *)result1);
    free((void *)result2);
}

#pragma mark - Contention Tests

/**
 * Test concurrent set/get operations under moderate contention.
 * Validates that operations complete without deadlock and data remains consistent.
 */
- (void)testConcurrentSetGet
{
    const int kNumThreads = 4;
    const int kIterationsPerThread = 100;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("test.concurrent", DISPATCH_QUEUE_CONCURRENT);

    __block atomic_int successfulSets = 0;
    __block atomic_int successfulGets = 0;
    __block atomic_int skippedGets = 0;

    for (int t = 0; t < kNumThreads; t++) {
        dispatch_group_async(group, queue, ^{
            char jsonBuffer[64];

            for (int i = 0; i < kIterationsPerThread; i++) {
                // Alternate between set and get operations
                if (i % 2 == 0) {
                    snprintf(jsonBuffer, sizeof(jsonBuffer), "{\"thread\":%d,\"iter\":%d}", t, i);
                    kscrashreport_setUserInfoJSON(jsonBuffer);
                    atomic_fetch_add(&successfulSets, 1);
                } else {
                    const char *result = kscrashreport_getUserInfoJSON();
                    if (result != NULL) {
                        atomic_fetch_add(&successfulGets, 1);
                        free((void *)result);
                    } else {
                        atomic_fetch_add(&skippedGets, 1);
                    }
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Verify no deadlock occurred (we reached this point)
    int totalSets = atomic_load(&successfulSets);
    int totalGets = atomic_load(&successfulGets);
    int totalSkipped = atomic_load(&skippedGets);

    XCTAssertEqual(totalSets, kNumThreads * kIterationsPerThread / 2, @"All set operations should complete");
    XCTAssertEqual(totalGets + totalSkipped, kNumThreads * kIterationsPerThread / 2,
                   @"All get operations should complete (successfully or skipped)");

    NSLog(@"Concurrent test: %d sets, %d successful gets, %d skipped gets", totalSets, totalGets, totalSkipped);
}

/**
 * Test high contention scenario with many threads competing for access.
 * Under extreme contention, the skip behavior should kick in.
 */
- (void)testHighContentionSkipBehavior
{
    const int kNumThreads = 16;
    const int kIterationsPerThread = 500;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("test.highContention", DISPATCH_QUEUE_CONCURRENT);

    __block atomic_int totalOperations = 0;
    __block atomic_int skippedGets = 0;

    // Set an initial value
    kscrashreport_setUserInfoJSON("{\"initial\":true}");

    for (int t = 0; t < kNumThreads; t++) {
        dispatch_group_async(group, queue, ^{
            char jsonBuffer[64];

            for (int i = 0; i < kIterationsPerThread; i++) {
                // Rapid fire set/get operations to create contention
                snprintf(jsonBuffer, sizeof(jsonBuffer), "{\"t\":%d,\"i\":%d}", t, i);
                kscrashreport_setUserInfoJSON(jsonBuffer);
                atomic_fetch_add(&totalOperations, 1);

                const char *result = kscrashreport_getUserInfoJSON();
                atomic_fetch_add(&totalOperations, 1);
                if (result != NULL) {
                    free((void *)result);
                } else {
                    atomic_fetch_add(&skippedGets, 1);
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    int total = atomic_load(&totalOperations);
    int skipped = atomic_load(&skippedGets);

    // Under high contention, we expect some skips, but the system should remain stable
    XCTAssertEqual(total, kNumThreads * kIterationsPerThread * 2, @"All operations should attempt to complete");

    NSLog(@"High contention test: %d total operations, %d skipped gets (%.2f%%)", total, skipped,
          (double)skipped / (kNumThreads * kIterationsPerThread) * 100.0);

    // Verify that after contention subsides, operations work normally
    const char *testJSON = "{\"postContention\":true}";
    kscrashreport_setUserInfoJSON(testJSON);
    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertNotEqual(result, NULL, @"Operations should work normally after contention subsides");
    if (result != NULL) {
        XCTAssertTrue(strcmp(result, testJSON) == 0, @"Value should be correctly set after contention");
        free((void *)result);
    }
}

/**
 * Test that rapid successive sets don't cause issues.
 */
- (void)testRapidSuccessiveSets
{
    const int kIterations = 1000;

    for (int i = 0; i < kIterations; i++) {
        char jsonBuffer[64];
        snprintf(jsonBuffer, sizeof(jsonBuffer), "{\"iteration\":%d}", i);
        kscrashreport_setUserInfoJSON(jsonBuffer);
    }

    // Final value should be set correctly
    char expectedJSON[64];
    snprintf(expectedJSON, sizeof(expectedJSON), "{\"iteration\":%d}", kIterations - 1);

    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertNotEqual(result, NULL, @"Should have a value set");
    if (result != NULL) {
        XCTAssertTrue(strcmp(result, expectedJSON) == 0, @"Last set value should persist");
        free((void *)result);
    }
}

- (void)testWriteStandardReportPreserves64BitMachCodeAndSubcode
{
#if KSCRASH_HAS_MACH
    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));

    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "MACHCODETEST");
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.registersAreValid = true;
    context.omitBinaryImages = true;
    context.monitorId = kscm_machexception_getAPI()->monitorId(NULL);
    context.crashReason = "Mach code serialization test";
    context.faultAddress = (uintptr_t)0xDEADBEEF;
    context.mach.type = EXC_BAD_ACCESS;
    context.mach.code = INT64_C(0x123456789ABCDEF0);
    context.mach.subcode = INT64_C(0x7EEDFACEDEADBEEF);
    context.signal.signum = SIGBUS;

    NSString *path = [self temporaryReportPath];
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);

        NSDictionary *json = [self readJSONObjectAtPath:path];
        NSDictionary *crash = json[@"crash"];
        NSDictionary *error = crash[@"error"];
        NSDictionary *mach = error[@"mach"];

        XCTAssertEqual([mach[@"code"] unsignedLongLongValue], UINT64_C(0x123456789ABCDEF0));
        XCTAssertEqual([mach[@"subcode"] unsignedLongLongValue], UINT64_C(0x7EEDFACEDEADBEEF));
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
#endif
}

/** Write a report carrying the given user info and hand back the file's raw bytes. */
- (NSString *)rawReportWithUserInfoJSON:(const char *)userInfoJSON
{
    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));
    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "USERINFOTEST");
    context.offendingMachineContext = &machineContext;
    context.registersAreValid = true;
    context.omitBinaryImages = true;
    context.monitorId = kscm_machexception_getAPI()->monitorId(NULL);
    context.mach.type = EXC_BAD_ACCESS;
    context.signal.signum = SIGBUS;

    kscrashreport_setUserInfoJSON(userInfoJSON);
    NSString *path = [self temporaryReportPath];
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        kscrashreport_setUserInfoJSON(NULL);
    }
}

- (NSUInteger)countOfString:(NSString *)needle in:(NSString *)haystack
{
    NSUInteger count = 0;
    NSRange search = NSMakeRange(0, haystack.length);
    while (search.length > 0) {
        NSRange found = [haystack rangeOfString:needle options:0 range:search];
        if (found.location == NSNotFound) {
            break;
        }
        count++;
        search = NSMakeRange(NSMaxRange(found), haystack.length - NSMaxRange(found));
    }
    return count;
}

// Whatever the payload is, the report gets exactly one user section and stays parseable.
// Counted against the raw bytes on purpose: NSJSONSerialization keeps the last of a
// duplicated key and would hide the very thing this is guarding.
- (void)testWriteStandardReportWritesExactlyOneUserSection
{
    NSString *oversized = [@"" stringByPaddingToLength:KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1000
                                            withString:@"x"
                                       startingAtIndex:0];
    NSMutableString *tooDeep = [NSMutableString string];
    int depth = KSJSON_MAX_CONTAINER_DEPTH + 50;
    for (int i = 0; i < depth; i++) {
        [tooDeep appendString:@"["];
    }
    [tooDeep appendString:@"1"];
    for (int i = 0; i < depth; i++) {
        [tooDeep appendString:@"]"];
    }

    NSDictionary<NSString *, NSString *> *payloads = @{
        @"object" : @"{\"ok\":1}",
        @"array" : @"[1,2,3]",
        @"string" : @"\"just a string\"",
        @"malformed" : @"{\"nope\":",
        @"oversized value" : [NSString stringWithFormat:@"{\"big\":\"%@\"}", oversized],
        @"oversized value nested" : [NSString stringWithFormat:@"{\"a\":{\"big\":\"%@\"}}", oversized],
        @"oversized value in array" : [NSString stringWithFormat:@"[\"%@\"]", oversized],
        @"oversized key" : [NSString stringWithFormat:@"{\"%@\":1}", oversized],
        @"too deep" : tooDeep,
    };

    for (NSString *label in payloads) {
        NSString *raw = [self rawReportWithUserInfoJSON:payloads[label].UTF8String];
        XCTAssertNotNil(raw, @"%@", label);

        XCTAssertEqual([self countOfString:@"\"user\":" in:raw], 1u, @"%@ must produce one user section", label);

        NSError *error = nil;
        id decoded = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                     options:0
                                                       error:&error];
        XCTAssertNotNil(decoded, @"%@ must leave the report parseable: %@", label, error);
        XCTAssertNotNil(decoded[@"debug"], @"%@ must leave later sections in the report root", label);
    }
}

// A payload the codec refuses is replaced whole by an error element carrying the original,
// rather than being partially written and then annotated.
- (void)testWriteStandardReportReplacesRejectedUserInfoWithAnError
{
    NSString *oversized = [@"" stringByPaddingToLength:KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1000
                                            withString:@"x"
                                       startingAtIndex:0];
    NSString *payload = [NSString stringWithFormat:@"{\"big\":\"%@\"}", oversized];
    NSString *raw = [self rawReportWithUserInfoJSON:payload.UTF8String];

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0
                                                           error:nil];
    XCTAssertEqualObjects(json[@"user"][@"error"], @"Invalid JSON data: Data too long");
    XCTAssertEqualObjects(json[@"user"][@"json_data"], payload, @"the rejected payload is kept verbatim");
    XCTAssertNil(json[@"user"][@"big"], @"none of the rejected payload may reach the report");
}

// Payloads within the limits are embedded as themselves, not routed through the error path.
- (void)testWriteStandardReportEmbedsAcceptedUserInfo
{
    NSString *raw = [self rawReportWithUserInfoJSON:"{\"ok\":1}"];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0
                                                           error:nil];
    XCTAssertEqualObjects(json[@"user"], @{ @"ok" : @1 });

    raw = [self rawReportWithUserInfoJSON:"[1,2,3]"];
    json = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    XCTAssertEqualObjects(json[@"user"], (@[ @1, @2, @3 ]));
}

/**
 * Test concurrent reads don't interfere with each other.
 */
- (void)testConcurrentReads
{
    const int kNumThreads = 8;
    const int kReadsPerThread = 200;

    // Set a known value
    const char *testJSON = "{\"shared\":\"value\",\"number\":42}";
    kscrashreport_setUserInfoJSON(testJSON);

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("test.concurrentReads", DISPATCH_QUEUE_CONCURRENT);

    __block atomic_int successfulReads = 0;
    __block atomic_int correctValues = 0;
    __block atomic_int skippedReads = 0;

    for (int t = 0; t < kNumThreads; t++) {
        dispatch_group_async(group, queue, ^{
            for (int i = 0; i < kReadsPerThread; i++) {
                const char *result = kscrashreport_getUserInfoJSON();
                if (result != NULL) {
                    atomic_fetch_add(&successfulReads, 1);
                    if (strcmp(result, testJSON) == 0) {
                        atomic_fetch_add(&correctValues, 1);
                    }
                    free((void *)result);
                } else {
                    atomic_fetch_add(&skippedReads, 1);
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    int reads = atomic_load(&successfulReads);
    int correct = atomic_load(&correctValues);
    int skipped = atomic_load(&skippedReads);

    XCTAssertEqual(reads + skipped, kNumThreads * kReadsPerThread, @"All read attempts should complete");
    XCTAssertEqual(reads, correct, @"All successful reads should return correct value");

    NSLog(@"Concurrent reads test: %d successful, %d correct, %d skipped", reads, correct, skipped);
}

- (void)testRestrictedClassObjectWritesASingleTypeAndNoContents
{
    __attribute__((objc_precise_lifetime)) KSCrashTestRestrictedSecret *secret = [KSCrashTestRestrictedSecret new];
    const char *restricted[] = { "KSCrashTestRestrictedSecret" };
    kscrashreport_setDoNotIntrospectClasses(restricted, 1);

    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));
    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "RESTRICTEDTEST");
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.omitBinaryImages = true;
    context.monitorId = kscm_nsexception_getAPI()->monitorId(NULL);
    context.NSException.name = "TestException";
    char reason[64];
    snprintf(reason, sizeof(reason), "Object at %p is upset", (__bridge void *)secret);
    context.crashReason = reason;

    NSString *path = [self temporaryReportPath];
    NSDictionary *json = nil;
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);
        json = [self readJSONObjectAtPath:path];
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        kscrashreport_setDoNotIntrospectClasses(NULL, 0);
    }

    NSDictionary *referenced = json[@"crash"][@"error"][@"nsexception"][@"referenced_object"];
    XCTAssertNotNil(referenced);
    // The restricted record is complete as address + type + class. The
    // raw-memory fallback must not run: it would add a second "type" key
    // (surfacing here as "unknown" or "string" under last-key-wins) and
    // could write the restricted object's memory as a string value.
    XCTAssertEqualObjects(referenced[@"type"], @"objc_object");
    XCTAssertEqualObjects(referenced[@"class"], @"KSCrashTestRestrictedSecret");
    XCTAssertNil(referenced[@"value"]);
    XCTAssertNil(referenced[@"ivars"]);
}

@end
