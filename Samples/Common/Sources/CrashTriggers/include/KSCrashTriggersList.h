//
//  KSCrashTriggersList.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const KSCrashStacktraceCheckFuncName;
extern NSString *const KSCrashNSExceptionStacktraceFuncName;

#define __ALL_GROUPS                             \
    __PROCESS_GROUP(nsException, @"NSException") \
    __PROCESS_GROUP(cpp, @"C++")                 \
    __PROCESS_GROUP(mach, @"Mach")               \
    __PROCESS_GROUP(signal, @"Signal")           \
    __PROCESS_GROUP(multiple, @"Multiple")       \
    __PROCESS_GROUP(other, @"Other")

#define __ALL_TRIGGERS                                                           \
    __PROCESS_TRIGGER(nsException, genericNSException, @"Generic NSException")   \
    __PROCESS_TRIGGER(nsException, nsArrayOutOfBounds, @"NSArray out-of-bounds") \
    __PROCESS_TRIGGER(cpp, runtimeException, @"Runtime Exception")               \
    __PROCESS_TRIGGER(mach, badAccess, @"EXC_BAD_ACCESS (SIGSEGV)")              \
    __PROCESS_TRIGGER(mach, busError, @"EXC_BAD_ACCESS (SIGBUS)")                \
    __PROCESS_TRIGGER(mach, illegalInstruction, @"EXC_BAD_INSTRUCTION")          \
    __PROCESS_TRIGGER(signal, abort, @"Abort")                                   \
    __PROCESS_TRIGGER(multiple, mach_mach, @"Mach + Mach")                       \
    __PROCESS_TRIGGER(multiple, mach_signal, @"Mach + Signal")                   \
    __PROCESS_TRIGGER(multiple, mach_cpp, @"Mach + CPP")                         \
    __PROCESS_TRIGGER(multiple, mach_ns, @"Mach + NSException")                  \
    __PROCESS_TRIGGER(multiple, mach_user, @"Mach + User")                       \
    __PROCESS_TRIGGER(multiple, signal_mach, @"Signal + Mach")                   \
    __PROCESS_TRIGGER(multiple, signal_signal, @"Signal + Signal")               \
    __PROCESS_TRIGGER(multiple, signal_cpp, @"Signal + CPP")                     \
    __PROCESS_TRIGGER(multiple, signal_ns, @"Signal + NSException")              \
    __PROCESS_TRIGGER(multiple, signal_user, @"Signal + User")                   \
    __PROCESS_TRIGGER(multiple, cpp_mach, @"CPP + Mach")                         \
    __PROCESS_TRIGGER(multiple, cpp_signal, @"CPP + Signal")                     \
    __PROCESS_TRIGGER(multiple, cpp_cpp, @"CPP + CPP")                           \
    __PROCESS_TRIGGER(multiple, cpp_ns, @"CPP + NSException")                    \
    __PROCESS_TRIGGER(multiple, cpp_user, @"CPP + User")                         \
    __PROCESS_TRIGGER(multiple, ns_mach, @"NSException + Mach")                  \
    __PROCESS_TRIGGER(multiple, ns_signal, @"NSException + Signal")              \
    __PROCESS_TRIGGER(multiple, ns_cpp, @"NSException + CPP")                    \
    __PROCESS_TRIGGER(multiple, ns_ns, @"NSException + NSException")             \
    __PROCESS_TRIGGER(multiple, ns_user, @"NSException + User")                  \
    __PROCESS_TRIGGER(multiple, user_mach, @"User + Mach")                       \
    __PROCESS_TRIGGER(multiple, user_signal, @"User + Signal")                   \
    __PROCESS_TRIGGER(multiple, user_cpp, @"User + CPP")                         \
    __PROCESS_TRIGGER(multiple, user_ns, @"User + NSException")                  \
    __PROCESS_TRIGGER(multiple, user_user, @"User + User")                       \
    __PROCESS_TRIGGER(other, manyThreads, @"Many Threads")                       \
    __PROCESS_TRIGGER(other, stackOverflow, @"Stack overflow")

NS_SWIFT_NAME(CrashTriggersList)
@interface KSCrashTriggersList : NSObject

#define __PROCESS_TRIGGER(GROUP, ID, NAME) +(void)trigger_##GROUP##_##ID;
__ALL_TRIGGERS
#undef __PROCESS_TRIGGER

@end

NS_ASSUME_NONNULL_END
