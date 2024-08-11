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

#define __ALL_GROUPS                             \
    __PROCESS_GROUP(nsException, @"NSException") \
    __PROCESS_GROUP(cpp, @"C++")                 \
    __PROCESS_GROUP(mach, @"Mach")               \
    __PROCESS_GROUP(signal, @"Signal")           \
    __PROCESS_GROUP(other, @"Other")

#define __ALL_TRIGGERS                                                           \
    __PROCESS_TRIGGER(nsException, genericNSException, @"Generic NSException")   \
    __PROCESS_TRIGGER(nsException, nsArrayOutOfBounds, @"NSArray out-of-bounds") \
    __PROCESS_TRIGGER(cpp, runtimeException, @"Runtime Exception")               \
    __PROCESS_TRIGGER(mach, badAccess, @"EXC_BAD_ACCESS (SIGSEGV)")              \
    __PROCESS_TRIGGER(mach, busError, @"EXC_BAD_ACCESS (SIGBUS)")                \
    __PROCESS_TRIGGER(mach, illegalInstruction, @"EXC_BAD_INSTRUCTION")          \
    __PROCESS_TRIGGER(signal, abort, @"Abort")                                   \
    __PROCESS_TRIGGER(other, stackOverflow, @"Stack overflow")

NS_SWIFT_NAME(CrashTriggersList)
@interface KSCrashTriggersList : NSObject

#define __PROCESS_TRIGGER(GROUP, ID, NAME) +(void)trigger_##GROUP##_##ID;
__ALL_TRIGGERS
#undef __PROCESS_TRIGGER

@end

NS_ASSUME_NONNULL_END
