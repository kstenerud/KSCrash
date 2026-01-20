//
//  KSUnwinderComparison_Tests.m
//
//  Created by Alexander Cohen on 2025-01-19.
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

#import <TargetConditionals.h>

#if !TARGET_OS_WATCH

#import <XCTest/XCTest.h>

#import "KSCrashMonitorContext.h"
#import "KSCrashReportC.h"
#import "KSDynamicLinker.h"
#import "KSMachineContext.h"
#import "KSStackCursor_MachineContext.h"
#import "KSThread.h"
#import "Unwind/KSStackCursor_Unwind.h"

#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <pthread.h>

// Worker thread state
static dispatch_semaphore_t g_workerReadySemaphore;
static dispatch_semaphore_t g_workerDoneSemaphore;
static thread_t g_workerMachThread;

// Nested functions to create a deep call stack
__attribute__((noinline)) static void workerLevel5(void)
{
    // Signal that we're ready and wait to be released
    dispatch_semaphore_signal(g_workerReadySemaphore);
    dispatch_semaphore_wait(g_workerDoneSemaphore, DISPATCH_TIME_FOREVER);
}

__attribute__((noinline)) static void workerLevel4(void) { workerLevel5(); }
__attribute__((noinline)) static void workerLevel3(void) { workerLevel4(); }
__attribute__((noinline)) static void workerLevel2(void) { workerLevel3(); }
__attribute__((noinline)) static void workerLevel1(void) { workerLevel2(); }

static void *workerThreadMain(void *arg)
{
    (void)arg;
    g_workerMachThread = pthread_mach_thread_np(pthread_self());
    workerLevel1();
    return NULL;
}

@interface KSUnwinderComparison_Tests : XCTestCase
@end

@implementation KSUnwinderComparison_Tests

- (NSString *)tempReportPath
{
    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"unwind_test_%@.json", [[NSUUID UUID] UUIDString]];
    return [tempDir stringByAppendingPathComponent:fileName];
}

- (NSDictionary *)readJSONReport:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (NSArray *)extractBacktraceFromReport:(NSDictionary *)report
{
    NSDictionary *crash = report[@"crash"];
    if (!crash) return nil;

    NSArray *threads = crash[@"threads"];
    if (!threads) return nil;

    for (NSDictionary *thread in threads) {
        if ([thread[@"crashed"] boolValue]) {
            NSDictionary *backtrace = thread[@"backtrace"];
            return backtrace[@"contents"];
        }
    }
    return nil;
}

/// Test that crash reports correctly capture backtraces from suspended threads.
- (void)testUnwinder_BacktraceFromSuspendedThread
{
    // Initialize dynamic linker (needed for report writing)
    ksdl_init();

    // Create semaphores for thread synchronization
    g_workerReadySemaphore = dispatch_semaphore_create(0);
    g_workerDoneSemaphore = dispatch_semaphore_create(0);
    g_workerMachThread = MACH_PORT_NULL;

    // Start worker thread
    pthread_t workerThread;
    pthread_create(&workerThread, NULL, workerThreadMain, NULL);

    // Wait for worker to be ready (blocked in workerLevel5)
    dispatch_semaphore_wait(g_workerReadySemaphore, DISPATCH_TIME_FOREVER);

    // Give it a moment to fully block on the semaphore
    usleep(10000);

    // Suspend the worker thread so we can safely read its registers
    kern_return_t kr = thread_suspend(g_workerMachThread);
    XCTAssertEqual(kr, KERN_SUCCESS, @"Failed to suspend worker thread");

    // Get machine context from the suspended thread
    KSMachineContext machineContext = { 0 };
    bool gotContext = ksmc_getContextForThread(g_workerMachThread, &machineContext, true);
    XCTAssertTrue(gotContext, @"Failed to get machine context");

    // Create report path
    NSString *reportPath = [self tempReportPath];

    // Create monitor context (no pre-captured cursor - unwinder will walk from registers)
    KSCrash_MonitorContext context = { 0 };
    context.eventID[0] = 'U';
    context.eventID[1] = 'N';
    context.eventID[2] = 'W';
    context.eventID[3] = '\0';
    context.offendingMachineContext = &machineContext;
    context.stackCursor = NULL;  // Force unwinder to walk from machine context
    context.registersAreValid = true;
    context.monitorId = "unwind_test";
    context.crashReason = "Unwinder test";
    context.System.processName = "UnwindTest";
    context.System.processID = getpid();
    context.omitBinaryImages = true;

    // Write report
    kscrashreport_writeStandardReport(&context, [reportPath UTF8String]);

    // Resume worker thread and let it exit
    thread_resume(g_workerMachThread);
    dispatch_semaphore_signal(g_workerDoneSemaphore);
    pthread_join(workerThread, NULL);

    // Read and parse the report
    NSDictionary *report = [self readJSONReport:reportPath];
    XCTAssertNotNil(report, @"Should be able to read report");

    // Extract backtrace
    NSArray *backtrace = [self extractBacktraceFromReport:report];
    XCTAssertNotNil(backtrace, @"Report should have backtrace");
    XCTAssertGreaterThan(backtrace.count, 0, @"Backtrace should have frames");

    NSLog(@"Total frames: %lu", (unsigned long)backtrace.count);
    for (NSUInteger i = 0; i < backtrace.count; i++) {
        NSDictionary *frame = backtrace[i];
        NSString *symbolName = frame[@"symbol_name"] ?: @"(unknown)";
        NSNumber *instructionAddr = frame[@"instruction_addr"];
        NSLog(@"Frame %2lu: 0x%llx %@", (unsigned long)i, instructionAddr ? [instructionAddr unsignedLongLongValue] : 0,
              symbolName);
    }

    // Clean up
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];
}

@end

#endif  // !TARGET_OS_WATCH
