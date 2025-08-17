//
//  KSCrashConfiguration_Tests.m
//
//  Created by Gleb Linnik on 13.06.2024.
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
#import <objc/runtime.h>
#import "KSCrashConfiguration+Private.h"
#import "KSCrashConfiguration.h"

#define AssertAround(FLOAT_VALUE, COMPARED_TO)                          \
    XCTAssertGreaterThanOrEqual(FLOAT_VALUE, (COMPARED_TO) - 0.000001); \
    XCTAssertLessThanOrEqual(FLOAT_VALUE, (COMPARED_TO) + 0.000001)

@interface KSCrashConfigurationTests : XCTestCase
@end

@implementation KSCrashConfigurationTests

- (void)testInitializationDefaults
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    XCTAssertEqual(config.monitors, KSCrashMonitorTypeProductionSafeMinimal);
    XCTAssertNil(config.userInfoJSON);
    AssertAround(config.deadlockWatchdogInterval, 0.0);
    XCTAssertFalse(config.enableQueueNameSearch);
    XCTAssertFalse(config.enableMemoryIntrospection);
    XCTAssertNil(config.doNotIntrospectClasses);
    XCTAssertEqual(config.crashNotifyCallbackWithPolicy, NULL);
    XCTAssertEqual(config.reportWrittenCallbackWithPolicy, NULL);
    XCTAssertFalse(config.addConsoleLogToReport);
    XCTAssertFalse(config.printPreviousLogOnStartup);
    XCTAssertEqual(config.reportStoreConfiguration.maxReportCount, 5);
    XCTAssertTrue(config.enableSwapCxaThrow);
}

- (void)testToCConfiguration
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.monitors = KSCrashMonitorTypeDebuggerSafe;
    config.userInfoJSON = @{ @"key" : @"value" };
    config.deadlockWatchdogInterval = 5.0;
    config.enableQueueNameSearch = YES;
    config.enableMemoryIntrospection = YES;
    config.doNotIntrospectClasses = @[ @"ClassA", @"ClassB" ];
    config.addConsoleLogToReport = YES;
    config.printPreviousLogOnStartup = YES;
    config.reportStoreConfiguration.maxReportCount = 10;
    config.enableSwapCxaThrow = NO;

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertEqual(cConfig.monitors, KSCrashMonitorTypeDebuggerSafe);
    XCTAssertTrue(cConfig.userInfoJSON != NULL);
    XCTAssertEqual(strcmp(cConfig.userInfoJSON, "{\"key\":\"value\"}"), 0);
    AssertAround(cConfig.deadlockWatchdogInterval, 5.0);
    XCTAssertTrue(cConfig.enableQueueNameSearch);
    XCTAssertTrue(cConfig.enableMemoryIntrospection);
    XCTAssertEqual(cConfig.doNotIntrospectClasses.length, 2);
    XCTAssertEqual(strcmp(cConfig.doNotIntrospectClasses.strings[0], "ClassA"), 0);
    XCTAssertEqual(strcmp(cConfig.doNotIntrospectClasses.strings[1], "ClassB"), 0);
    XCTAssertTrue(cConfig.addConsoleLogToReport);
    XCTAssertTrue(cConfig.printPreviousLogOnStartup);
    XCTAssertEqual(cConfig.reportStoreConfiguration.maxReportCount, 10);
    XCTAssertFalse(cConfig.enableSwapCxaThrow);

    // Free memory allocated for C string array
    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testCopyWithZone
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.monitors = KSCrashMonitorTypeDebuggerSafe;
    config.userInfoJSON = @{ @"key" : @"value" };
    config.deadlockWatchdogInterval = 5.0;
    config.enableQueueNameSearch = YES;
    config.enableMemoryIntrospection = YES;
    config.doNotIntrospectClasses = @[ @"ClassA", @"ClassB" ];
    config.addConsoleLogToReport = YES;
    config.printPreviousLogOnStartup = YES;
    config.reportStoreConfiguration.maxReportCount = 10;
    config.enableSwapCxaThrow = NO;

    KSCrashConfiguration *copy = [config copy];

    XCTAssertEqual(copy.monitors, KSCrashMonitorTypeDebuggerSafe);
    XCTAssertEqualObjects(copy.userInfoJSON, @{ @"key" : @"value" });
    AssertAround(copy.deadlockWatchdogInterval, 5.0);
    XCTAssertTrue(copy.enableQueueNameSearch);
    XCTAssertTrue(copy.enableMemoryIntrospection);
    XCTAssertEqualObjects(copy.doNotIntrospectClasses, (@[ @"ClassA", @"ClassB" ]));
    XCTAssertTrue(copy.addConsoleLogToReport);
    XCTAssertTrue(copy.printPreviousLogOnStartup);
    XCTAssertEqual(copy.reportStoreConfiguration.maxReportCount, 10);
    XCTAssertFalse(copy.enableSwapCxaThrow);
}

- (void)testEmptyDictionaryForJSONConversion
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.userInfoJSON = @{};
    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertTrue(cConfig.userInfoJSON != NULL);
    XCTAssertEqual(strcmp(cConfig.userInfoJSON, "{}"), 0);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testLargeDataForJSONConversion
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    NSMutableDictionary *largeDict = [NSMutableDictionary dictionary];
    for (int i = 0; i < 1000; i++) {
        NSString *key = [NSString stringWithFormat:@"key%d", i];
        NSString *value = [NSString stringWithFormat:@"value%d", i];
        largeDict[key] = value;
    }
    config.userInfoJSON = largeDict;
    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertTrue(cConfig.userInfoJSON != NULL);
    NSString *jsonString = [NSString stringWithUTF8String:cConfig.userInfoJSON];
    XCTAssertTrue([jsonString containsString:@"key999"]);
    XCTAssertTrue([jsonString containsString:@"value999"]);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testSpecialCharactersInStrings
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.userInfoJSON = @{ @"key" : @"value with special characters: @#$%^&*()" };
    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertTrue(cConfig.userInfoJSON != NULL);
    XCTAssertTrue(strstr(cConfig.userInfoJSON, "special characters: @#$%^&*()") != NULL);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testNilAndEmptyArraysForCStringConversion
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    // Test with nil array
    config.doNotIntrospectClasses = nil;
    KSCrashCConfiguration cConfig1 = [config toCConfiguration];
    XCTAssertTrue(cConfig1.doNotIntrospectClasses.strings == NULL);

    // Test with empty array
    config.doNotIntrospectClasses = @[];
    KSCrashCConfiguration cConfig2 = [config toCConfiguration];
    XCTAssertTrue(cConfig2.doNotIntrospectClasses.strings != NULL);
    XCTAssertEqual(cConfig2.doNotIntrospectClasses.length, 0);

    KSCrashCConfiguration_Release(&cConfig1);
    KSCrashCConfiguration_Release(&cConfig2);
}

- (void)testCopyingWithNilProperties
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.userInfoJSON = nil;
    config.doNotIntrospectClasses = nil;

    KSCrashConfiguration *copy = [config copy];
    XCTAssertNil(copy.userInfoJSON);
    XCTAssertNil(copy.doNotIntrospectClasses);
}

static struct {
    BOOL crashNotifyCallbackCalled;
    BOOL reportWrittenCallbackCalled;
    int64_t capturedReportID;
    KSCrash_ExceptionHandlingPolicy capturedPolicy;
    const struct KSCrashReportWriter *capturedWriter;
} g_callbackData;

static void clearCallbackData(void) { memset(&g_callbackData, 0, sizeof(g_callbackData)); }

static void onCrash(const KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter *writer)
{
    g_callbackData.crashNotifyCallbackCalled = YES;
    g_callbackData.capturedPolicy = policy;
    g_callbackData.capturedWriter = writer;
}

static void onReportWritten(KSCrash_ExceptionHandlingPolicy policy, int64_t reportID)
{
    g_callbackData.reportWrittenCallbackCalled = YES;
    g_callbackData.capturedReportID = reportID;
    g_callbackData.capturedPolicy = policy;
}

- (void)testCallbacksInCConfiguration
{
    clearCallbackData();
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    config.crashNotifyCallbackWithPolicy = onCrash;
    config.reportWrittenCallbackWithPolicy = onReportWritten;

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertNotEqual(config.crashNotifyCallbackWithPolicy, NULL);
    XCTAssertNotEqual(config.reportWrittenCallbackWithPolicy, NULL);
    XCTAssertNotEqual(cConfig.crashNotifyCallbackWithPolicy, NULL);
    XCTAssertNotEqual(cConfig.reportWrittenCallbackWithPolicy, NULL);

    KSCrash_ExceptionHandlingPolicy testPolicy = (KSCrash_ExceptionHandlingPolicy) {
        .isFatal = true, .crashedDuringExceptionHandling = true, .shouldWriteReport = true
    };
    const struct KSCrashReportWriter *testWriter = (const struct KSCrashReportWriter *)(uintptr_t)0xdeadbeef;
    cConfig.crashNotifyCallbackWithPolicy(testPolicy, testWriter);
    XCTAssertTrue(g_callbackData.crashNotifyCallbackCalled);
    XCTAssertEqual(memcmp(&g_callbackData.capturedPolicy, &testPolicy, sizeof(testPolicy)), 0);
    XCTAssertEqual(g_callbackData.capturedWriter, testWriter);

    testPolicy.isFatal = false;
    testPolicy.shouldRecordThreads = true;
    int64_t testReportID = 12345;
    cConfig.reportWrittenCallbackWithPolicy(testPolicy, testReportID);
    XCTAssertTrue(g_callbackData.reportWrittenCallbackCalled);
    XCTAssertEqual(memcmp(&g_callbackData.capturedPolicy, &testPolicy, sizeof(testPolicy)), 0);
    XCTAssertEqual(g_callbackData.capturedReportID, testReportID);

    KSCrashCConfiguration_Release(&cConfig);
}

@end
