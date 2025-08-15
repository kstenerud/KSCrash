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
#import "CrashCallback.h"
#import "KSCrash.h"

namespace sample_namespace
{
class Report
{
   public:
    static void crash() { throw std::runtime_error("C++ exception"); }
};
}  // namespace sample_namespace

static void trigger_ns(void)
{
    NSException *exc = [NSException exceptionWithName:NSGenericException reason:@"Something broke" userInfo:nil];
    [exc raise];
}

static void trigger_cpp(void) { sample_namespace::Report::crash(); }

static void trigger_mach(void)
{
    volatile int *ptr = (int *)0x42;
    *ptr = 42;  // This will cause an EXC_BAD_ACCESS (SIGSEGV)
}

static void trigger_signal(void)
{
    abort();  // This will raise a SIGABRT signal
}

static void trigger_user(void)
{
    [KSCrash.sharedInstance reportUserException:@"User Exception"
                                         reason:@"My Reason"
                                       language:@"My Language"
                                     lineOfCode:@"loc"
                                     stackTrace:@[ @"trace line 1", @"trace line 2" ]
                                  logAllThreads:YES
                               terminateProgram:NO];
}

static void trigger_userfatal(void)
{
    [KSCrash.sharedInstance reportUserException:@"User Exception"
                                         reason:@"My Reason"
                                       language:@"My Language"
                                     lineOfCode:@"loc"
                                     stackTrace:@[ @"trace line 1", @"trace line 2" ]
                                  logAllThreads:YES
                               terminateProgram:YES];
}

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
    trigger_cpp();
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

#define TRIGGER_MULTIPLE(TYPE_A, TYPE_B)                                                      \
    setIntegrationTestCrashNotifyImplementation(                                              \
        ^(KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter *writer) { \
            if (!policy.crashedDuringExceptionHandling) {                                     \
                trigger_##TYPE_B();                                                           \
            }                                                                                 \
        });                                                                                   \
    trigger_##TYPE_A()

+ (void)trigger_multiple_mach_mach
{
    TRIGGER_MULTIPLE(mach, mach);
}
+ (void)trigger_multiple_mach_signal
{
    TRIGGER_MULTIPLE(mach, signal);
}
+ (void)trigger_multiple_mach_cpp
{
    TRIGGER_MULTIPLE(mach, cpp);
}
+ (void)trigger_multiple_mach_ns
{
    TRIGGER_MULTIPLE(mach, ns);
}
+ (void)trigger_multiple_mach_user
{
    TRIGGER_MULTIPLE(mach, user);
}

+ (void)trigger_multiple_signal_mach
{
    TRIGGER_MULTIPLE(signal, mach);
}
+ (void)trigger_multiple_signal_signal
{
    TRIGGER_MULTIPLE(signal, signal);
}
+ (void)trigger_multiple_signal_cpp
{
    TRIGGER_MULTIPLE(signal, cpp);
}
+ (void)trigger_multiple_signal_ns
{
    TRIGGER_MULTIPLE(signal, ns);
}
+ (void)trigger_multiple_signal_user
{
    TRIGGER_MULTIPLE(signal, user);
}

+ (void)trigger_multiple_cpp_mach
{
    TRIGGER_MULTIPLE(cpp, mach);
}
+ (void)trigger_multiple_cpp_signal
{
    TRIGGER_MULTIPLE(cpp, signal);
}
+ (void)trigger_multiple_cpp_cpp
{
    TRIGGER_MULTIPLE(cpp, cpp);
}
+ (void)trigger_multiple_cpp_ns
{
    TRIGGER_MULTIPLE(cpp, ns);
}
+ (void)trigger_multiple_cpp_user
{
    TRIGGER_MULTIPLE(cpp, user);
}

+ (void)trigger_multiple_ns_mach
{
    TRIGGER_MULTIPLE(ns, mach);
}
+ (void)trigger_multiple_ns_signal
{
    TRIGGER_MULTIPLE(ns, signal);
}
+ (void)trigger_multiple_ns_cpp
{
    TRIGGER_MULTIPLE(ns, cpp);
}
+ (void)trigger_multiple_ns_ns
{
    TRIGGER_MULTIPLE(ns, ns);
}
+ (void)trigger_multiple_ns_user
{
    TRIGGER_MULTIPLE(ns, user);
}

+ (void)trigger_multiple_user_mach
{
    TRIGGER_MULTIPLE(userfatal, mach);
}
+ (void)trigger_multiple_user_signal
{
    TRIGGER_MULTIPLE(userfatal, signal);
}
+ (void)trigger_multiple_user_cpp
{
    TRIGGER_MULTIPLE(userfatal, cpp);
}
+ (void)trigger_multiple_user_ns
{
    TRIGGER_MULTIPLE(userfatal, ns);
}
+ (void)trigger_multiple_user_user
{
    TRIGGER_MULTIPLE(userfatal, user);
}

@end
