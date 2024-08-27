//
//  KSCrashConfiguration.m
//
//  Created by Gleb Linnik on 11.06.2024.
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

#import "KSCrashConfiguration.h"
#import <objc/runtime.h>
#import "KSCrashConfiguration+Private.h"

@implementation KSCrashConfiguration

- (instancetype)init
{
    self = [super init];
    if (self) {
        KSCrashCConfiguration cConfig = KSCrashCConfiguration_Default();
        _installPath = nil;
        _monitors = cConfig.monitors;

        if (cConfig.userInfoJSON != NULL) {
            NSData *data = [NSData dataWithBytes:cConfig.userInfoJSON length:strlen(cConfig.userInfoJSON)];
            NSError *error = nil;
            _userInfoJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (error) {
                _userInfoJSON = nil;  // Handle the error appropriately
            }
        } else {
            _userInfoJSON = nil;
        }

        _deadlockWatchdogInterval = cConfig.deadlockWatchdogInterval;
        _enableQueueNameSearch = cConfig.enableQueueNameSearch ? YES : NO;
        _enableMemoryIntrospection = cConfig.enableMemoryIntrospection ? YES : NO;
        _doNotIntrospectClasses = nil;
        _crashNotifyCallback = nil;
        _reportWrittenCallback = nil;
        _addConsoleLogToReport = cConfig.addConsoleLogToReport ? YES : NO;
        _printPreviousLogOnStartup = cConfig.printPreviousLogOnStartup ? YES : NO;
        _maxReportCount = cConfig.maxReportCount;
        _enableSwapCxaThrow = cConfig.enableSwapCxaThrow ? YES : NO;

        _deleteBehaviorAfterSendAll = KSCDeleteAlways;  // Used only in Obj-C interface
    }
    return self;
}

- (KSCrashCConfiguration)toCConfiguration
{
    KSCrashCConfiguration config = KSCrashCConfiguration_Default();

    config.monitors = self.monitors;
    config.userInfoJSON = self.userInfoJSON ? [self jsonStringFromDictionary:self.userInfoJSON] : NULL;
    config.deadlockWatchdogInterval = self.deadlockWatchdogInterval;
    config.enableQueueNameSearch = self.enableQueueNameSearch;
    config.enableMemoryIntrospection = self.enableMemoryIntrospection;
    config.doNotIntrospectClasses.strings = [self createCStringArrayFromNSArray:self.doNotIntrospectClasses];
    config.doNotIntrospectClasses.length = (int)[self.doNotIntrospectClasses count];
    if (self.crashNotifyCallback) {
        config.crashNotifyCallback = (KSReportWriteCallback)imp_implementationWithBlock(self.crashNotifyCallback);
    }
    if (config.reportWrittenCallback) {
        config.reportWrittenCallback = (KSReportWrittenCallback)imp_implementationWithBlock(self.reportWrittenCallback);
    }
    config.addConsoleLogToReport = self.addConsoleLogToReport;
    config.printPreviousLogOnStartup = self.printPreviousLogOnStartup;
    config.maxReportCount = self.maxReportCount;
    config.enableSwapCxaThrow = self.enableSwapCxaThrow;

    return config;
}

- (const char **)createCStringArrayFromNSArray:(NSArray<NSString *> *)nsArray
{
    if (!nsArray) return NULL;

    const char **cArray = malloc(sizeof(char *) * [nsArray count]);
    for (NSUInteger i = 0; i < [nsArray count]; i++) {
        cArray[i] = strdup([nsArray[i] UTF8String]);
    }
    return cArray;
}

- (const char *)jsonStringFromDictionary:(NSDictionary *)dictionary
{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!jsonData) {
        NSLog(@"Error converting dictionary to JSON: %@", error.localizedDescription);
        return NULL;
    }
    const char *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding].UTF8String;
    return strdup(jsonString);  // strdup to ensure it's a copy that's safe to free later
}

#pragma mark - NSCopying

- (nonnull id)copyWithZone:(nullable NSZone *)zone
{
    KSCrashConfiguration *copy = [[KSCrashConfiguration allocWithZone:zone] init];
    copy.monitors = self.monitors;
    copy.userInfoJSON = [self.userInfoJSON copyWithZone:zone];
    copy.deadlockWatchdogInterval = self.deadlockWatchdogInterval;
    copy.enableQueueNameSearch = self.enableQueueNameSearch;
    copy.enableMemoryIntrospection = self.enableMemoryIntrospection;
    copy.doNotIntrospectClasses = self.doNotIntrospectClasses
                                      ? [[NSArray allocWithZone:zone] initWithArray:self.doNotIntrospectClasses
                                                                          copyItems:YES]
                                      : nil;
    copy.crashNotifyCallback = [self.crashNotifyCallback copy];
    copy.reportWrittenCallback = [self.reportWrittenCallback copy];
    copy.addConsoleLogToReport = self.addConsoleLogToReport;
    copy.printPreviousLogOnStartup = self.printPreviousLogOnStartup;
    copy.maxReportCount = self.maxReportCount;
    copy.enableSwapCxaThrow = self.enableSwapCxaThrow;
    copy.deleteBehaviorAfterSendAll = self.deleteBehaviorAfterSendAll;
    return copy;
}

@end
