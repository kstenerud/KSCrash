//
//  KSCrashC_ReportResult_Tests.m
//
//  Created by Alexander Cohen on 2026-09-17.
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

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_MachException.h"
#import "KSMachineContext.h"

#include <pthread.h>
#include <signal.h>
#include <stdio.h>

extern void kscrash_testcode_onExceptionEvent(struct KSCrash_MonitorContext *monitorContext,
                                              KSCrash_ReportResult *result);

@interface KSCrashC_ReportResult_Tests : XCTestCase
@end

@implementation KSCrashC_ReportResult_Tests

- (void)testReportPathResultNamesOnlyAWrittenReport
{
    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));
    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "REPORTRESULT");
    context.offendingMachineContext = &machineContext;
    context.registersAreValid = true;
    context.omitBinaryImages = true;
    context.monitorId = kscm_machexception_getAPI()->monitorId(NULL);
    context.mach.type = EXC_BAD_ACCESS;
    context.signal.signum = SIGBUS;
    context.requirements.shouldWriteReport = true;

    // The directory does not exist yet, so the report file cannot be created.
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSString *reportPath = [directory stringByAppendingPathComponent:@"report.json"];
    context.reportPath = reportPath.UTF8String;

    KSCrash_ReportResult result = { 0 };
    kscrash_testcode_onExceptionEvent(&context, &result);
    XCTAssertTrue(result.path[0] == '\0', @"A report that was never created must not be handed back");
    XCTAssertEqual(result.reportId, (int64_t)0);

    // Control: with the directory in place, the same event hands back the report it wrote.
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:directory
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:nil]);
    @try {
        result = (KSCrash_ReportResult) { 0 };
        kscrash_testcode_onExceptionEvent(&context, &result);
        XCTAssertEqualObjects([NSString stringWithUTF8String:result.path], reportPath);
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:reportPath]);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
    }
}

@end
