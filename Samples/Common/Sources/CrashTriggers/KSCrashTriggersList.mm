//
//  KSCrashTriggersList.mm
//
//  Created by Nikolay Volosatov on 2024-06-23.
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

#import "KSCrashTriggersList.h"

#import <mach/mach.h>
#import <signal.h>
#import <stdexcept>

namespace sample_namespace
{
class Report
{
   public:
    static void crash() { throw std::runtime_error("C++ exception"); }
};
}  // namespace sample_namespace

extern "C" void KSStacktraceCheckCrash() __attribute__((disable_tail_calls));
NSString *const KSCrashStacktraceCheckFuncName = @"KSStacktraceCheckCrash";
void KSStacktraceCheckCrash() __attribute__((disable_tail_calls))
{
    NSException *exc = [NSException exceptionWithName:NSGenericException reason:@"Stacktrace Check" userInfo:nil];
    [exc raise];
}

NSString *const KSCrashNSExceptionStacktraceFuncName = @"exceptionWithStacktraceForException";

@implementation KSCrashTriggersList

+ (void)trigger_nsException_genericNSException
{
    NSException *exc = [NSException exceptionWithName:NSGenericException reason:@"Test" userInfo:@{ @"a" : @"b" }];
    [exc raise];
}

+ (void)trigger_nsException_nsArrayOutOfBounds
{
    NSArray *array = @[ @1, @2, @3 ];
    [array objectAtIndex:10];  // This will throw an NSRangeException
}

+ (void)trigger_cpp_runtimeException
{
    sample_namespace::Report::crash();
}

+ (void)trigger_mach_badAccess
{
    volatile int *ptr = (int *)0x42;
    *ptr = 42;  // This will cause an EXC_BAD_ACCESS (SIGSEGV)
}

+ (void)trigger_mach_busError
{
    char *ptr = (char *)malloc(sizeof(int));
    int *intPtr = (int *)(ptr + 1);  // Misaligned pointer
    *intPtr = 42;                    // This will cause an EXC_BAD_ACCESS (SIGBUS)
    free(ptr);
}

+ (void)trigger_mach_illegalInstruction
{
    void (*funcPtr)() = (void (*)())0xDEADBEEF;
    funcPtr();  // This will cause an EXC_BAD_INSTRUCTION
}

+ (void)trigger_signal_abort
{
    abort();  // This will raise a SIGABRT signal
}

+ (void)trigger_other_manyThreads
{
    NSUInteger const threadsCount = 1005;
    static NSMutableArray *allThreads = [NSMutableArray arrayWithCapacity:threadsCount + 1];

    for (NSUInteger idx = 0; idx < threadsCount; ++idx) {
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            // Sleep forever by making short "sleep" calls
            while (YES) {
                [NSThread sleepForTimeInterval:0.01];
            }
        }];
        [thread start];
        [allThreads addObject:thread];
    }

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        // Sleep 100ms to ensure other threads are running
        [NSThread sleepForTimeInterval:0.1];

        // And then actually crash (specifically in the last thread)
        KSStacktraceCheckCrash();
    }];
    [thread start];
    [allThreads addObject:thread];
}

+ (void)trigger_other_stackOverflow
{
    [self trigger_other_stackOverflow];
}

@end
