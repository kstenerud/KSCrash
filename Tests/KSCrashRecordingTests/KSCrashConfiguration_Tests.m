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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void)setUp
{
    clearCallbackData();
    clearLegacyCallbackData();
}

- (void)testInitializationDefaults
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    XCTAssertEqual(config.monitors, KSCrashMonitorTypeProductionSafeMinimal);
    XCTAssertNil(config.userInfoJSON);
    AssertAround(config.deadlockWatchdogInterval, 0.0);
    XCTAssertFalse(config.enableQueueNameSearch);
    XCTAssertFalse(config.enableMemoryIntrospection);
    XCTAssertNil(config.doNotIntrospectClasses);
    XCTAssertEqual(config.isWritingReportCallback, NULL);
    XCTAssertEqual(config.didWriteReportCallback, NULL);
    XCTAssertFalse(config.addConsoleLogToReport);
    XCTAssertFalse(config.printPreviousLogOnStartup);
    XCTAssertEqual(config.reportStoreConfiguration.maxReportCount, 5);
    XCTAssertTrue(config.enableSwapCxaThrow);
    XCTAssertFalse(config.enableCompactBinaryImages);
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
    config.enableCompactBinaryImages = YES;

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
    XCTAssertTrue(cConfig.enableCompactBinaryImages);

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
    config.enableCompactBinaryImages = YES;

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
    XCTAssertTrue(copy.enableCompactBinaryImages);
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
    BOOL willWriteReportCallbackCalled;
    BOOL isWritingReportCallbackCalled;
    BOOL didWriteReportCallbackCalled;
    int64_t capturedReportID;
    const KSCrash_MonitorContext *capturedContext;
    const KSCrash_ExceptionHandlingPlan *capturedPlan;
    const struct KSCrashReportWriter *capturedWriter;
} g_callbackData;

static void clearCallbackData(void) { memset(&g_callbackData, 0, sizeof(g_callbackData)); }

static void willWriteReportCallback(KSCrash_ExceptionHandlingPlan *const plan,
                                    const KSCrash_MonitorContext *const context)
{
    g_callbackData.willWriteReportCallbackCalled = YES;
    g_callbackData.capturedPlan = plan;
    g_callbackData.capturedContext = context;
}

static void isWritingReportCallback(const KSCrash_ExceptionHandlingPlan *const plan,
                                    const struct KSCrashReportWriter *writer)
{
    g_callbackData.isWritingReportCallbackCalled = YES;
    g_callbackData.capturedPlan = plan;
    g_callbackData.capturedWriter = writer;
}

static void didWriteReportCallback(const KSCrash_ExceptionHandlingPlan *const plan, int64_t reportID)
{
    g_callbackData.didWriteReportCallbackCalled = YES;
    g_callbackData.capturedReportID = reportID;
    g_callbackData.capturedPlan = plan;
}

- (void)testCallbacksInCConfiguration
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    config.willWriteReportCallback = willWriteReportCallback;
    config.isWritingReportCallback = isWritingReportCallback;
    config.didWriteReportCallback = didWriteReportCallback;

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertNotEqual(config.willWriteReportCallback, NULL);
    XCTAssertNotEqual(config.isWritingReportCallback, NULL);
    XCTAssertNotEqual(config.didWriteReportCallback, NULL);
    XCTAssertNotEqual(cConfig.willWriteReportCallback, NULL);
    XCTAssertNotEqual(cConfig.isWritingReportCallback, NULL);
    XCTAssertNotEqual(cConfig.didWriteReportCallback, NULL);

    KSCrash_ExceptionHandlingPlan testPlan = (KSCrash_ExceptionHandlingPlan) { .isFatal = true,
                                                                               .crashedDuringExceptionHandling = true,
                                                                               .shouldWriteReport = true };
    KSCrash_MonitorContext monitorContext = { 0 };
    cConfig.willWriteReportCallback(&testPlan, &monitorContext);
    XCTAssertTrue(g_callbackData.willWriteReportCallbackCalled);
    XCTAssertEqual(g_callbackData.capturedPlan, &testPlan);
    XCTAssertEqual(g_callbackData.capturedContext, &monitorContext);

    KSCrash_ExceptionHandlingPlan testPlan2 = (KSCrash_ExceptionHandlingPlan) { .isFatal = true,
                                                                                .crashedDuringExceptionHandling = true,
                                                                                .shouldWriteReport = true };
    const struct KSCrashReportWriter *testWriter = (const struct KSCrashReportWriter *)(uintptr_t)0xdeadbeef;
    cConfig.isWritingReportCallback(&testPlan2, testWriter);
    XCTAssertTrue(g_callbackData.isWritingReportCallbackCalled);
    XCTAssertEqual(g_callbackData.capturedPlan, &testPlan2);
    XCTAssertEqual(g_callbackData.capturedWriter, testWriter);

    KSCrash_ExceptionHandlingPlan testPlan3 = (KSCrash_ExceptionHandlingPlan) { .isFatal = false,
                                                                                .crashedDuringExceptionHandling = true,
                                                                                .shouldWriteReport = true,
                                                                                .shouldRecordAllThreads = true };
    int64_t testReportID = 12345;
    cConfig.didWriteReportCallback(&testPlan3, testReportID);
    XCTAssertTrue(g_callbackData.didWriteReportCallbackCalled);
    XCTAssertEqual(g_callbackData.capturedPlan, &testPlan3);
    XCTAssertEqual(g_callbackData.capturedReportID, testReportID);

    KSCrashCConfiguration_Release(&cConfig);
}

#pragma mark - Backward Compatibility Tests

static struct {
    BOOL legacyCrashNotifyCallbackCalled;
    BOOL legacyReportWrittenCallbackCalled;
    int64_t legacyCapturedReportID;
    const struct KSCrashReportWriter *legacyCapturedWriter;
} g_legacyCallbackData;

static void clearLegacyCallbackData(void) { memset(&g_legacyCallbackData, 0, sizeof(g_legacyCallbackData)); }

- (void)testDeprecatedCrashNotifyCallbackConversion
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    config.crashNotifyCallback = ^(const struct KSCrashReportWriter *writer) {
        g_legacyCallbackData.legacyCrashNotifyCallbackCalled = YES;
        g_legacyCallbackData.legacyCapturedWriter = writer;
    };

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertNotEqual(cConfig.crashNotifyCallback, NULL);

    const struct KSCrashReportWriter *testWriter = (const struct KSCrashReportWriter *)(uintptr_t)0xcafebabe;
    cConfig.crashNotifyCallback(testWriter);
    XCTAssertTrue(g_legacyCallbackData.legacyCrashNotifyCallbackCalled);
    XCTAssertEqual(g_legacyCallbackData.legacyCapturedWriter, testWriter);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testDeprecatedReportWrittenCallbackConversion
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    config.reportWrittenCallback = ^(int64_t reportID) {
        g_legacyCallbackData.legacyReportWrittenCallbackCalled = YES;
        g_legacyCallbackData.legacyCapturedReportID = reportID;
    };

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertNotEqual(cConfig.reportWrittenCallback, NULL);

    int64_t testReportID = 54321;
    cConfig.reportWrittenCallback(testReportID);
    XCTAssertTrue(g_legacyCallbackData.legacyReportWrittenCallbackCalled);
    XCTAssertEqual(g_legacyCallbackData.legacyCapturedReportID, testReportID);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testMixedCallbackUsage
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.crashNotifyCallback = ^(const struct KSCrashReportWriter *writer) {
        g_legacyCallbackData.legacyCrashNotifyCallbackCalled = YES;
        g_legacyCallbackData.legacyCapturedWriter = writer;
    };
    config.reportWrittenCallback = ^(int64_t reportID) {
        g_legacyCallbackData.legacyReportWrittenCallbackCalled = YES;
        g_legacyCallbackData.legacyCapturedReportID = reportID;
    };

    config.isWritingReportCallback = isWritingReportCallback;
    config.didWriteReportCallback = didWriteReportCallback;

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    // Verify both types of callbacks are set
    XCTAssertNotEqual(cConfig.crashNotifyCallback, NULL);
    XCTAssertNotEqual(cConfig.reportWrittenCallback, NULL);
    XCTAssertNotEqual(cConfig.isWritingReportCallback, NULL);
    XCTAssertNotEqual(cConfig.didWriteReportCallback, NULL);

    // Test deprecated crash callback
    const struct KSCrashReportWriter *testWriter = (const struct KSCrashReportWriter *)(uintptr_t)0xdeadcafe;
    cConfig.crashNotifyCallback(testWriter);
    XCTAssertTrue(g_legacyCallbackData.legacyCrashNotifyCallbackCalled);
    XCTAssertEqual(g_legacyCallbackData.legacyCapturedWriter, testWriter);

    // Test new crash callback
    KSCrash_ExceptionHandlingPlan testPlan = (KSCrash_ExceptionHandlingPlan) {
        .isFatal = true,
        .crashedDuringExceptionHandling = false,
    };
    const struct KSCrashReportWriter *testWriter2 = (const struct KSCrashReportWriter *)(uintptr_t)0xbeefcafe;
    cConfig.isWritingReportCallback(&testPlan, testWriter2);
    XCTAssertTrue(g_callbackData.isWritingReportCallbackCalled);
    XCTAssertEqual(g_callbackData.capturedWriter, testWriter2);

    // Test deprecated report written callback
    int64_t testReportID1 = 11111;
    cConfig.reportWrittenCallback(testReportID1);
    XCTAssertTrue(g_legacyCallbackData.legacyReportWrittenCallbackCalled);
    XCTAssertEqual(g_legacyCallbackData.legacyCapturedReportID, testReportID1);

    // Test new report written callback
    int64_t testReportID2 = 22222;
    cConfig.didWriteReportCallback(&testPlan, testReportID2);
    XCTAssertTrue(g_callbackData.didWriteReportCallbackCalled);
    XCTAssertEqual(g_callbackData.capturedReportID, testReportID2);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testCopyingWithDeprecatedCallbacks
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.crashNotifyCallback = ^(const struct KSCrashReportWriter *writer) {
        g_legacyCallbackData.legacyCrashNotifyCallbackCalled = YES;
        g_legacyCallbackData.legacyCapturedWriter = writer;
    };
    config.reportWrittenCallback = ^(int64_t reportID) {
        g_legacyCallbackData.legacyReportWrittenCallbackCalled = YES;
        g_legacyCallbackData.legacyCapturedReportID = reportID;
    };

    config.isWritingReportCallback = isWritingReportCallback;
    config.didWriteReportCallback = didWriteReportCallback;
    KSCrashConfiguration *copiedConfig = [config copy];

    XCTAssertNotNil(copiedConfig.crashNotifyCallback);
    XCTAssertNotNil(copiedConfig.reportWrittenCallback);
    XCTAssertNotEqual(copiedConfig.isWritingReportCallback, NULL);
    XCTAssertNotEqual(copiedConfig.didWriteReportCallback, NULL);

    KSCrashCConfiguration copiedCConfig = [copiedConfig toCConfiguration];

    const struct KSCrashReportWriter *testWriter = (const struct KSCrashReportWriter *)(uintptr_t)0xc0ffee;
    copiedCConfig.crashNotifyCallback(testWriter);
    XCTAssertTrue(g_legacyCallbackData.legacyCrashNotifyCallbackCalled);
    XCTAssertEqual(g_legacyCallbackData.legacyCapturedWriter, testWriter);

    int64_t testReportID = 99999;
    copiedCConfig.reportWrittenCallback(testReportID);
    XCTAssertTrue(g_legacyCallbackData.legacyReportWrittenCallbackCalled);
    XCTAssertEqual(g_legacyCallbackData.legacyCapturedReportID, testReportID);

    KSCrashCConfiguration_Release(&copiedCConfig);
}

- (void)testNilDeprecatedCallbacks
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];

    config.crashNotifyCallback = nil;
    config.reportWrittenCallback = nil;

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertEqual(cConfig.crashNotifyCallback, NULL);
    XCTAssertEqual(cConfig.reportWrittenCallback, NULL);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testDefaultDeprecatedCallbacks
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    KSCrashCConfiguration cConfig = [config toCConfiguration];
    XCTAssertEqual(cConfig.crashNotifyCallback, NULL);
    XCTAssertEqual(cConfig.reportWrittenCallback, NULL);

    KSCrashCConfiguration_Release(&cConfig);
}

#pragma mark - Plugin Tests

static const char *testPluginMonitorId(__unused void *context) { return "test_plugin"; }
static KSCrashMonitorFlag testPluginMonitorFlags(__unused void *context) { return (KSCrashMonitorFlag)0; }
static bool g_testPluginEnabled = false;
static void testPluginSetEnabled(bool isEnabled, __unused void *context) { g_testPluginEnabled = isEnabled; }
static bool testPluginIsEnabled(__unused void *context) { return g_testPluginEnabled; }

- (void)testPluginInitWithAPI
{
    KSCrashMonitorAPI api = { 0 };
    api.monitorId = testPluginMonitorId;
    KSCrashBasicMonitorPlugin *plugin = [[KSCrashBasicMonitorPlugin alloc] initWithAPI:&api];
    XCTAssertEqual(plugin.api, &api);
    XCTAssertEqual(strcmp(plugin.api->monitorId(NULL), "test_plugin"), 0);
}

- (void)testPluginWithAPI
{
    KSCrashMonitorAPI api = { 0 };
    api.monitorId = testPluginMonitorId;
    KSCrashBasicMonitorPlugin *plugin = [KSCrashBasicMonitorPlugin pluginWithAPI:&api];
    XCTAssertEqual(plugin.api, &api);
}

- (void)testPluginsDefaultNil
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    XCTAssertNil(config.plugins);
}

- (void)testPluginsToCConfiguration
{
    KSCrashMonitorAPI api1 = { 0 };
    api1.monitorId = testPluginMonitorId;
    api1.monitorFlags = testPluginMonitorFlags;
    api1.setEnabled = testPluginSetEnabled;
    api1.isEnabled = testPluginIsEnabled;

    KSCrashBasicMonitorPlugin *plugin1 = [[KSCrashBasicMonitorPlugin alloc] initWithAPI:&api1];

    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.plugins = @[ plugin1 ];

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertEqual(cConfig.plugins.length, 1);
    XCTAssertNotEqual(cConfig.plugins.apis, NULL);
    XCTAssertEqual(strcmp(cConfig.plugins.apis[0].monitorId(NULL), "test_plugin"), 0);
    XCTAssertNotEqual(cConfig.plugins.release, NULL);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testPluginsToCConfigurationNil
{
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.plugins = nil;

    KSCrashCConfiguration cConfig = [config toCConfiguration];

    XCTAssertEqual(cConfig.plugins.length, 0);
    XCTAssertEqual(cConfig.plugins.apis, NULL);
    XCTAssertEqual(cConfig.plugins.release, NULL);

    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testPluginsCopyWithZone
{
    KSCrashMonitorAPI api = { 0 };
    api.monitorId = testPluginMonitorId;
    KSCrashBasicMonitorPlugin *plugin = [[KSCrashBasicMonitorPlugin alloc] initWithAPI:&api];

    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    config.plugins = @[ plugin ];

    KSCrashConfiguration *copy = [config copy];

    XCTAssertEqual(copy.plugins.count, 1);
    XCTAssertEqual(copy.plugins[0].api, &api);
}

- (void)testCConfigurationDefaultPlugins
{
    KSCrashCConfiguration cConfig = KSCrashCConfiguration_Default();
    XCTAssertEqual(cConfig.plugins.apis, NULL);
    XCTAssertEqual(cConfig.plugins.length, 0);
    XCTAssertEqual(cConfig.plugins.release, NULL);
    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testCConfigurationReleaseWithReleaseFunc
{
    KSCrashCConfiguration cConfig = KSCrashCConfiguration_Default();
    cConfig.plugins.apis = malloc(sizeof(KSCrashMonitorAPI) * 1);
    cConfig.plugins.length = 1;
    cConfig.plugins.release = free;
    // Should not leak or crash
    KSCrashCConfiguration_Release(&cConfig);
}

- (void)testCConfigurationReleaseWithoutReleaseFunc
{
    KSCrashMonitorAPI stackAPI = { 0 };
    KSCrashCConfiguration cConfig = KSCrashCConfiguration_Default();
    cConfig.plugins.apis = &stackAPI;
    cConfig.plugins.length = 1;
    cConfig.plugins.release = NULL;
    // Should not crash — no free called on stack pointer
    KSCrashCConfiguration_Release(&cConfig);
}

#pragma clang diagnostic pop

@end
