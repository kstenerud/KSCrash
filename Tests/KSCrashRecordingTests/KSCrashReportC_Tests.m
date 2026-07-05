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
#import "KSDynamicLinker.h"
#import "KSJSONCodec.h"
#import "KSMachineContext.h"
#import "KSStackCursor_SelfThread.h"

#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>

static const char *customSectionMonitorId(__unused void *context) { return "TestCustomMonitor"; }
static const char *profileLikeMonitorId(__unused void *context) { return "profile"; }
static const char *floatSectionMonitorId(__unused void *context) { return "TestFloatMonitor"; }
static void writeFloatMonitorSection(__unused const KSCrash_MonitorContext *eventContext,
                                     const KSCrashReportWriter *writer, __unused void *context)
{
    writer->addFloatElement(writer, "ratio", 0.2f);
    writer->addFloatingPointElement(writer, "precise", 0.1);
    writer->addFloatingPointElement(writer, "infinite", (double)INFINITY);
    writer->addFloatElement(writer, "notANumber", NAN);
}
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
    KSCrashMonitorAPI _floatMonitorAPI;
}

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    kscm_removeMonitor(&_customMonitorAPI);
    kscm_removeMonitor(&_profileLikeMonitorAPI);
    kscm_removeMonitor(&_floatMonitorAPI);
    [super tearDown];
}

/// A monitor-caused report for the monitor id `idFunc` returns, written and
/// read back.
- (NSDictionary *)writeReportForMonitor:(KSCrashMonitorAPI *)monitorAPI monitorId:(const char *(*)(void *))idFunc
{
    return [self writeReportForMonitor:monitorAPI monitorId:idFunc section:writeTestMonitorSection];
}

- (NSDictionary *)writeReportForMonitor:(KSCrashMonitorAPI *)monitorAPI
                              monitorId:(const char *(*)(void *))idFunc
                                section:(void (*)(const KSCrash_MonitorContext *, const KSCrashReportWriter *,
                                                  void *))section
{
    kscma_initAPI(monitorAPI);
    monitorAPI->monitorId = idFunc;
    monitorAPI->writeInReportSection = section;
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

- (void)testWriteRecrashReportPreservesTheOriginalReportID
{
    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));
    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "4c1b2f3e-0000-4000-8000-00000000000a");
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.omitBinaryImages = true;
    context.monitorId = "TestMonitor";

    NSString *path = [self temporaryReportPath];
    NSDictionary *json = nil;
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);

        // The handler crashed: the recrash context has its own fresh event
        // id, but the rewritten file keeps the identity its filename carries.
        KSCrash_MonitorContext recrashContext = { 0 };
        snprintf(recrashContext.eventID, sizeof(recrashContext.eventID), "ffffffff-ffff-4fff-8fff-ffffffffffff");
        recrashContext.offendingMachineContext = &machineContext;
        recrashContext.stackCursor = &stackCursor;
        recrashContext.omitBinaryImages = true;
        recrashContext.monitorId = "TestMonitor";
        kscrashreport_writeRecrashReport(&recrashContext, path.UTF8String, "4c1b2f3e-0000-4000-8000-00000000000a");
        json = [self readJSONObjectAtPath:path];
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }

    XCTAssertEqualObjects(json[@"report"][@"id"], @"4c1b2f3e-0000-4000-8000-00000000000a");
    XCTAssertEqualObjects(json[@"recrash_report"][@"report"][@"id"], @"4c1b2f3e-0000-4000-8000-00000000000a",
                          @"the embedded original keeps its id too");
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

- (void)testWriteStandardReportKeepsAFloatAtItsOwnPrecision
{
    // A float widened to a double and printed at DBL_DIG carries the
    // widening's noise, not the value: 0.2f comes out 0.200000002980232. The
    // writer takes floats through their own slot so the digits it prints are
    // the ones the value is worth.
    NSDictionary *section =
        [self writeReportForMonitor:&_floatMonitorAPI monitorId:floatSectionMonitorId
                            section:writeFloatMonitorSection][@"crash"][@"error"][@"monitor_data"][@"TestFloatMonitor"];

    XCTAssertEqualObjects([section[@"ratio"] stringValue], @"0.2");
    XCTAssertEqualObjects([section[@"precise"] stringValue], @"0.1");

    // JSON carries no infinity: the encoder writes `1e999`, and one of those
    // anywhere in a report makes the whole thing undeliverable, so the element
    // is left out rather than written. The keys that can be written still are.
    XCTAssertNil(section[@"infinite"]);
    XCTAssertNil(section[@"notANumber"]);
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

#pragma mark - Provided Binary Images

/** Build the minimal context the writer needs, pointing at the current thread. */
- (void)fillWriterContext:(KSCrash_MonitorContext *)context machineContext:(struct KSMachineContext *)machineContext
{
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), machineContext, true));
    snprintf(context->eventID, sizeof(context->eventID), "BINARYIMAGETEST");
    context->offendingMachineContext = machineContext;
    context->registersAreValid = true;
    context->monitorId = kscm_machexception_getAPI()->monitorId(NULL);
    context->mach.type = EXC_BAD_ACCESS;
    context->signal.signum = SIGBUS;
}

// An out-of-process report (a corpse) must list the subject's images, which the caller
// provides, not whatever happens to be loaded in the reporting process.
- (void)testWriteStandardReportUsesProvidedBinaryImages
{
    struct KSMachineContext machineContext = { 0 };
    KSCrash_MonitorContext context = { 0 };
    [self fillWriterContext:&context machineContext:&machineContext];

    const uint8_t uuid[16] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                               0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
    KSBinaryImage providedImages[2] = {
        { .address = 0x100000000,
          .vmAddress = 0x4000,
          .size = 0x8000,
          .name = "/corpse/app/Binary",
          .uuid = uuid,
          .cpuType = 16777228,
          .cpuSubType = 2 },
        { .address = 0x200000000, .size = 0x4000, .name = "/corpse/lib/Framework", .uuid = NULL, .cpuType = 16777228 },
    };
    context.providedBinaryImages = providedImages;
    context.providedBinaryImageCount = 2;

    NSString *path = [self temporaryReportPath];
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);

        NSArray *images = [self readJSONObjectAtPath:path][@"binary_images"];
        XCTAssertEqual(images.count, 2, @"Exactly the provided images, nothing from live dyld");

        NSDictionary *first = images[0];
        XCTAssertEqual([first[@"image_addr"] unsignedLongLongValue], 0x100000000);
        XCTAssertEqual([first[@"image_vmaddr"] unsignedLongLongValue], 0x4000);
        XCTAssertEqual([first[@"image_size"] unsignedLongLongValue], 0x8000);
        XCTAssertEqualObjects(first[@"name"], @"/corpse/app/Binary");
        XCTAssertEqualObjects([first[@"uuid"] lowercaseString], @"00112233-4455-6677-8899-aabbccddeeff");
        XCTAssertEqual([first[@"cpu_type"] intValue], 16777228);
        XCTAssertEqual([first[@"cpu_subtype"] intValue], 2);

        NSDictionary *second = images[1];
        XCTAssertEqual([second[@"image_addr"] unsignedLongLongValue], 0x200000000);
        XCTAssertEqualObjects(second[@"name"], @"/corpse/lib/Framework");
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

// Compact mode must not filter a provided image list: remote frames never populate the
// referenced-image set (they don't symbolicate, and the set would hold this process's
// bases anyway), so filtering would ship an empty binary_images section.
- (void)testWriteStandardReportKeepsProvidedBinaryImagesInCompactMode
{
    struct KSMachineContext machineContext = { 0 };
    KSCrash_MonitorContext context = { 0 };
    [self fillWriterContext:&context machineContext:&machineContext];

    KSBinaryImage providedImages[2] = {
        { .address = 0x100000000, .size = 0x8000, .name = "/corpse/app/Binary", .cpuType = 16777228 },
        { .address = 0x200000000, .size = 0x4000, .name = "/corpse/lib/Framework", .cpuType = 16777228 },
    };
    context.providedBinaryImages = providedImages;
    context.providedBinaryImageCount = 2;

    kscrashreport_setCompactBinaryImages(true);
    NSString *path = [self temporaryReportPath];
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);

        NSArray *images = [self readJSONObjectAtPath:path][@"binary_images"];
        XCTAssertEqual(images.count, 2, @"Compact mode must keep every provided image");
    } @finally {
        kscrashreport_setCompactBinaryImages(false);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)testWriteStandardReportDefaultsToLiveBinaryImages
{
    // The live path reads the binary image cache, which install normally initializes.
    ksdl_init();

    struct KSMachineContext machineContext = { 0 };
    KSCrash_MonitorContext context = { 0 };
    [self fillWriterContext:&context machineContext:&machineContext];

    NSString *path = [self temporaryReportPath];
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);

        NSArray *images = [self readJSONObjectAtPath:path][@"binary_images"];
        XCTAssertGreaterThan(images.count, 10, @"Without a provided list, the live process's images are written");
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

@end
