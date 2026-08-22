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
}

- (void)tearDown
{
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

#pragma mark - Contention Tests

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
