//
//  KSCrashConfiguration.m
//
//
//  Created by Gleb Linnik on 11.06.2024.
//

#import "KSCrashConfiguration.h"
#import <objc/runtime.h>
#import "KSCrashConfiguration+Private.h"

@implementation KSCrashConfiguration

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _monitors = 0;
        _userInfoJSON = nil;
        _deadlockWatchdogInterval = 0.0;
        _enableQueueNameSearch = NO;
        _enableMemoryIntrospection = NO;
        _doNotIntrospectClasses = nil;
        _crashNotifyCallback = nil;
        _reportWrittenCallback = nil;
        _addConsoleLogToReport = NO;
        _printPreviousLogOnStartup = NO;
        _maxReportCount = 5;
        _enableSwapCxaThrow = NO;
        _deleteBehaviorAfterSendAll = KSCDeleteAlways;  // Used only in Obj-C interface
    }
    return self;
}

- (KSCrashConfig)toCConfiguration
{
    KSCrashConfig config;

    config.monitors = self.monitors;
    config.userInfoJSON = self.userInfoJSON ? [self jsonStringFromDictionary:self.userInfoJSON] : NULL;
    config.deadlockWatchdogInterval = self.deadlockWatchdogInterval;
    config.enableQueueNameSearch = self.enableQueueNameSearch;
    config.enableMemoryIntrospection = self.enableMemoryIntrospection;
    config.doNotIntrospectClasses.strings = [self createCStringArrayFromNSArray:self.doNotIntrospectClasses];
    config.doNotIntrospectClasses.length = (int)[self.doNotIntrospectClasses count];
    config.crashNotifyCallback = (KSReportWriteCallback)imp_implementationWithBlock(self.crashNotifyCallback);
    config.reportWrittenCallback = (KSReportWrittenCallback)imp_implementationWithBlock(self.reportWrittenCallback);
    config.addConsoleLogToReport = self.addConsoleLogToReport;
    config.printPreviousLogOnStartup = self.printPreviousLogOnStartup;
    config.maxReportCount = self.maxReportCount;
    config.enableSwapCxaThrow = self.enableSwapCxaThrow;

    return config;
}

- (const char**)createCStringArrayFromNSArray:(NSArray<NSString*>*)nsArray
{
    if (!nsArray) return NULL;

    const char** cArray = malloc(sizeof(char*) * [nsArray count]);
    for (NSUInteger i = 0; i < [nsArray count]; i++)
    {
        cArray[i] = strdup([nsArray[i] UTF8String]);
    }
    return cArray;
}

- (const char*)jsonStringFromDictionary:(NSDictionary*)dictionary
{
    NSError* error;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!jsonData)
    {
        NSLog(@"Error converting dictionary to JSON: %@", error.localizedDescription);
        return NULL;
    }
    const char* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding].UTF8String;
    return strdup(jsonString);  // strdup to ensure it's a copy that's safe to free later
}

#pragma mark - NSCopying

- (nonnull id)copyWithZone:(nullable NSZone*)zone
{
    KSCrashConfiguration* copy = [[KSCrashConfiguration allocWithZone:zone] init];
    copy.monitors = self.monitors;
    copy.userInfoJSON = [self.userInfoJSON copyWithZone:zone];
    copy.deadlockWatchdogInterval = self.deadlockWatchdogInterval;
    copy.enableQueueNameSearch = self.enableQueueNameSearch;
    copy.enableMemoryIntrospection = self.enableMemoryIntrospection;
    copy.doNotIntrospectClasses = [[NSArray allocWithZone:zone] initWithArray:self.doNotIntrospectClasses
                                                                    copyItems:YES];
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
