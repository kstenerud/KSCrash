//
//  KSCrashRunSummary.m
//
//  Created by Alexander Cohen on 2026-04-19.
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

#import "KSCrashRunSummary.h"

@implementation KSCrashRunSummaryOutcome

- (instancetype)initWithTerminationReason:(KSTerminationReason)terminationReason
                            cleanShutdown:(BOOL)cleanShutdown
                            fatalReported:(BOOL)fatalReported
                          userPerceptible:(BOOL)userPerceptible
{
    if ((self = [super init])) {
        _terminationReason = terminationReason;
        _cleanShutdown = cleanShutdown;
        _fatalReported = fatalReported;
        _userPerceptible = userPerceptible;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryDurations

- (instancetype)initWithActiveMs:(int64_t)activeMs backgroundMs:(int64_t)backgroundMs
{
    if ((self = [super init])) {
        _activeMs = activeMs;
        _backgroundMs = backgroundMs;
    }
    return self;
}

@end

@implementation KSCrashRunSummarySessions

- (instancetype)initWithPerceptibleCount:(NSInteger)perceptibleCount imperceptibleCount:(NSInteger)imperceptibleCount
{
    if ((self = [super init])) {
        _perceptibleCount = perceptibleCount;
        _imperceptibleCount = imperceptibleCount;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryUsers

- (instancetype)initWithPerceptibleCount:(NSInteger)perceptibleCount imperceptibleCount:(NSInteger)imperceptibleCount
{
    if ((self = [super init])) {
        _perceptibleCount = perceptibleCount;
        _imperceptibleCount = imperceptibleCount;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryApp

- (instancetype)initWithBundleID:(NSString *)bundleID
                         version:(NSString *)version
                    shortVersion:(NSString *)shortVersion
                        hostKind:(KSCrashRunSummaryHostKind)hostKind
{
    if ((self = [super init])) {
        _bundleID = [bundleID copy];
        _version = [version copy];
        _shortVersion = [shortVersion copy];
        _hostKind = hostKind;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryOS

- (instancetype)initWithName:(NSString *)name version:(NSString *)version build:(NSString *)build
{
    if ((self = [super init])) {
        _name = [name copy];
        _version = [version copy];
        _build = [build copy];
    }
    return self;
}

@end

@implementation KSCrashRunSummaryDevice

- (instancetype)initWithModel:(NSString *)model
                  modelFamily:(NSString *)modelFamily
                 architecture:(NSString *)architecture
           binaryArchitecture:(NSString *)binaryArchitecture
                 isTranslated:(BOOL)isTranslated
                 isJailbroken:(BOOL)isJailbroken
{
    if ((self = [super init])) {
        _model = [model copy];
        _modelFamily = [modelFamily copy];
        _architecture = [architecture copy];
        _binaryArchitecture = [binaryArchitecture copy];
        _isTranslated = isTranslated;
        _isJailbroken = isJailbroken;
    }
    return self;
}

@end

@implementation KSCrashRunSummary

- (instancetype)initWithSchemaVersion:(NSInteger)schemaVersion
                           sdkVersion:(NSString *)sdkVersion
                                runID:(NSString *)runID
                             deviceID:(NSString *)deviceID
                               userID:(NSString *)userID
                                users:(KSCrashRunSummaryUsers *)users
                          startedAtMs:(int64_t)startedAtMs
                            endedAtMs:(int64_t)endedAtMs
                              outcome:(KSCrashRunSummaryOutcome *)outcome
                            durations:(KSCrashRunSummaryDurations *)durations
                             sessions:(KSCrashRunSummarySessions *)sessions
                                  app:(KSCrashRunSummaryApp *)app
                                   os:(KSCrashRunSummaryOS *)os
                               device:(KSCrashRunSummaryDevice *)device
{
    if ((self = [super init])) {
        _schemaVersion = schemaVersion;
        _sdkVersion = [sdkVersion copy];
        _runID = [runID copy];
        _deviceID = [deviceID copy];
        _userID = [userID copy];
        _users = users;
        _startedAtMs = startedAtMs;
        _endedAtMs = endedAtMs;
        _outcome = outcome;
        _durations = durations;
        _sessions = sessions;
        _app = app;
        _os = os;
        _device = device;
    }
    return self;
}

@end
