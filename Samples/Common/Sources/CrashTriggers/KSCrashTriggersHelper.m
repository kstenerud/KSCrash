//
//  KSCrashTriggersHelper.mm
//
//  Created by Nikolay Volosatov on 2024-08-10.
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

#import "KSCrashTriggersHelper.h"
#import "KSCrashTriggersList.h"

@implementation KSCrashTriggersHelper

+ (NSArray<NSString *> *)groupIds
{
    return @[
#define __PROCESS_GROUP(GROUP, NAME) @ #GROUP,
        __ALL_GROUPS
#undef __PROCESS_GROUP
    ];
}

+ (NSString *)nameForGroup:(NSString *)groupId
{
#define __PROCESS_GROUP(GROUP, NAME)          \
    if ([groupId isEqualToString:@ #GROUP]) { \
        return NAME;                          \
    }
    __ALL_GROUPS
#undef __PROCESS_GROUP
    return @"Unknown";
}

+ (NSArray<KSCrashTriggerId> *)triggersForGroup:(NSString *)groupId
{
    NSMutableArray<KSCrashTriggerId> *result = [NSMutableArray array];
#define __PROCESS_TRIGGER(GROUP, ID, NAME)        \
    if ([groupId isEqualToString:@ #GROUP]) {     \
        [result addObject:TRIGGER_ID(GROUP, ID)]; \
    }
    __ALL_TRIGGERS
#undef __PROCESS_TRIGGER
    return result;
}

+ (NSString *)nameForTrigger:(KSCrashTriggerId)triggerId
{
#define __PROCESS_TRIGGER(GROUP, ID, NAME)                   \
    if ([triggerId isEqualToString:TRIGGER_ID(GROUP, ID)]) { \
        return NAME;                                         \
    }
    __ALL_TRIGGERS
#undef __PROCESS_TRIGGER
    return @"Unknown";
}

+ (void)runTrigger:(KSCrashTriggerId)triggerId
{
#define __PROCESS_TRIGGER(GROUP, ID, NAME)                   \
    if ([triggerId isEqualToString:TRIGGER_ID(GROUP, ID)]) { \
        [KSCrashTriggersList trigger_##GROUP##_##ID];        \
        return;                                              \
    }
    __ALL_TRIGGERS
#undef __PROCESS_TRIGGER
}

@end
