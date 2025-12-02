//
//  KSCrashReportBenchmarks.m
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

#import "KSBinaryImageCache.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashReportC.h"
#import "KSDynamicLinker.h"
#import "KSMachineContext.h"
#import "KSStackCursor_SelfThread.h"

@interface KSCrashReportBenchmarks : XCTestCase
@end

@implementation KSCrashReportBenchmarks

- (void)setUp
{
    [super setUp];
    ksdl_init();
}

- (NSString *)tempFilePath
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"benchmark_report_%@.json", [[NSUUID UUID] UUIDString]];
    return [tempDir stringByAppendingPathComponent:fileName];
}

- (void)cleanupFile:(NSString *)path
{
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

/// Benchmark writing a standard crash report with full binary images and threads
- (void)testBenchmarkWriteStandardReport
{
    // Create machine context for current thread
    __block struct KSMachineContext machineContext;
    memset(&machineContext, 0, sizeof(machineContext));
    ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true);

    // Create stack cursor for current thread
    __block KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    // Create minimal monitor context
    __block KSCrash_MonitorContext context;
    memset(&context, 0, sizeof(context));
    context.eventID[0] = 'B';
    context.eventID[1] = 'E';
    context.eventID[2] = 'N';
    context.eventID[3] = 'C';
    context.eventID[4] = 'H';
    context.eventID[5] = '\0';
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.registersAreValid = true;
    context.monitorId = "benchmark";
    context.crashReason = "Benchmark test crash";
    context.System.processName = "BenchmarkTest";
    context.System.processID = getpid();

    [self measureBlock:^{
        NSString *reportPath = [self tempFilePath];
        kscrashreport_writeStandardReport(&context, [reportPath UTF8String]);
        [self cleanupFile:reportPath];
    }];
}

/// Benchmark writing a crash report without binary images (faster path)
- (void)testBenchmarkWriteStandardReportNoBinaryImages
{
    __block struct KSMachineContext machineContext;
    memset(&machineContext, 0, sizeof(machineContext));
    ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true);

    __block KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    __block KSCrash_MonitorContext context;
    memset(&context, 0, sizeof(context));
    context.eventID[0] = 'B';
    context.eventID[1] = 'E';
    context.eventID[2] = 'N';
    context.eventID[3] = 'C';
    context.eventID[4] = 'H';
    context.eventID[5] = '\0';
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.registersAreValid = true;
    context.monitorId = "benchmark";
    context.crashReason = "Benchmark test crash";
    context.System.processName = "BenchmarkTest";
    context.System.processID = getpid();
    context.omitBinaryImages = true;

    [self measureBlock:^{
        NSString *reportPath = [self tempFilePath];
        kscrashreport_writeStandardReport(&context, [reportPath UTF8String]);
        [self cleanupFile:reportPath];
    }];
}

/// Benchmark writing multiple reports in sequence (simulates multiple crashes)
- (void)testBenchmarkWriteMultipleReports
{
    __block struct KSMachineContext machineContext;
    memset(&machineContext, 0, sizeof(machineContext));
    ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true);

    __block KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    __block KSCrash_MonitorContext context;
    memset(&context, 0, sizeof(context));
    context.eventID[0] = 'B';
    context.eventID[1] = 'E';
    context.eventID[2] = 'N';
    context.eventID[3] = 'C';
    context.eventID[4] = 'H';
    context.eventID[5] = '\0';
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.registersAreValid = true;
    context.monitorId = "benchmark";
    context.crashReason = "Benchmark test crash";
    context.System.processName = "BenchmarkTest";
    context.System.processID = getpid();

    [self measureBlock:^{
        for (int i = 0; i < 5; i++) {
            NSString *reportPath = [self tempFilePath];
            kscrashreport_writeStandardReport(&context, [reportPath UTF8String]);
            [self cleanupFile:reportPath];
        }
    }];
}

@end
