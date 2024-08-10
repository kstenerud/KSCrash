//
//  KSCrashTriggersHelper.h
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

#import "KSCrashTriggersList.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSString *KSCrashTriggerId NS_TYPED_ENUM NS_SWIFT_NAME(CrashTriggerId);
#define TRIGGER_ID(GROUP, ID) KSCrashTriggerId_##GROUP##_##ID
#define __PROCESS_TRIGGER(GROUP, ID, NAME) \
    static KSCrashTriggerId const TRIGGER_ID(GROUP, ID) NS_SWIFT_NAME(GROUP##_##ID) = @"trigger-" #GROUP "-" #ID;
__ALL_TRIGGERS
#undef __PROCESS_TRIGGER

NS_SWIFT_NAME(CrashTriggersHelper)
@interface KSCrashTriggersHelper : NSObject

+ (NSArray<NSString *> *)groupIds;
+ (NSString *)nameForGroup:(NSString *)groupId;

+ (NSArray<KSCrashTriggerId> *)triggersForGroup:(NSString *)groupId;
+ (NSString *)nameForTrigger:(KSCrashTriggerId)triggerId;

+ (void)runTrigger:(KSCrashTriggerId)triggerId;

@end

NS_ASSUME_NONNULL_END
