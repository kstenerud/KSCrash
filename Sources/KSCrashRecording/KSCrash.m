//
//  KSCrash.m
//
//  Created by Karl Stenerud on 2012-01-28.
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

#import "KSCrash.h"
#import "KSCrash+Private.h"

#import "KSCrashC.h"
#import "KSCrashConfiguration+Private.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_AppState.h"
#import "KSCrashMonitor_Memory.h"
#import "KSCrashMonitor_System.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"
#import "KSNSErrorHelper.h"
#import "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#include <inttypes.h>
#if KSCRASH_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif

// ============================================================================
#pragma mark - Globals -
// ============================================================================

@interface KSCrash ()

@property(nonatomic, readwrite, copy) NSString *bundleName;
@property(nonatomic, strong) KSCrashConfiguration *configuration;

@end

static BOOL gIsSharedInstanceCreated = NO;

NSString *kscrash_getBundleName(void)
{
    NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
    if (bundleName == nil) {
        bundleName = @"Unknown";
    }
    return bundleName;
}

NSString *kscrash_getDefaultInstallPath(void)
{
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([directories count] == 0) {
        KSLOG_ERROR(@"Could not locate cache directory path.");
        return nil;
    }
    NSString *cachePath = [directories objectAtIndex:0];
    if ([cachePath length] == 0) {
        KSLOG_ERROR(@"Could not locate cache directory path.");
        return nil;
    }
    NSString *pathEnd = [@"KSCrash" stringByAppendingPathComponent:kscrash_getBundleName()];
    return [cachePath stringByAppendingPathComponent:pathEnd];
}

@implementation KSCrash

// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

+ (void)load
{
    [[self class] classDidBecomeLoaded];
}

+ (void)initialize
{
    if (self == [KSCrash class]) {
        [[self class] subscribeToNotifications];
    }
}

+ (instancetype)sharedInstance
{
    static KSCrash *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[KSCrash alloc] init];
        gIsSharedInstanceCreated = YES;
    });
    return sharedInstance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _bundleName = kscrash_getBundleName();
    }
    return self;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

- (NSDictionary *)userInfo
{
    const char *userInfoJSON = kscrash_getUserInfoJSON();
    if (userInfoJSON != NULL && strlen(userInfoJSON) > 0) {
        NSError *error = nil;
        NSData *jsonData = [NSData dataWithBytes:userInfoJSON length:strlen(userInfoJSON)];
        NSDictionary *userInfoDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        free((void *)userInfoJSON);  // Free the allocated memory

        if (error != nil) {
            KSLOG_ERROR(@"Error parsing JSON: %@", error.localizedDescription);
            return nil;
        }
        return userInfoDict;
    }
    return nil;
}

- (void)setUserInfo:(NSDictionary *)userInfo
{
    NSError *error = nil;
    NSData *userInfoJSON = nil;

    if (userInfo != nil) {
        userInfoJSON = [NSJSONSerialization dataWithJSONObject:userInfo options:NSJSONWritingSortedKeys error:&error];

        if (error != nil) {
            KSLOG_ERROR(@"Could not serialize user info: %@", error.localizedDescription);
            return;
        }
    }

    const char *userInfoCString = userInfoJSON ? [userInfoJSON bytes] : NULL;
    kscrash_setUserInfoJSON(userInfoCString);
}

- (BOOL)reportsMemoryTerminations
{
    return ksmemory_get_fatal_reports_enabled();
}

- (void)setReportsMemoryTerminations:(BOOL)reportsMemoryTerminations
{
    ksmemory_set_fatal_reports_enabled(reportsMemoryTerminations);
}

- (NSDictionary *)systemInfo
{
    KSCrash_MonitorContext fakeEvent = { 0 };
    kscm_system_getAPI()->addContextualInfoToEvent(&fakeEvent);
    NSMutableDictionary *dict = [NSMutableDictionary new];

#define COPY_STRING(A) \
    if (fakeEvent.System.A) dict[@ #A] = [NSString stringWithUTF8String:fakeEvent.System.A]
#define COPY_PRIMITIVE(A) dict[@ #A] = @(fakeEvent.System.A)
    COPY_STRING(systemName);
    COPY_STRING(systemVersion);
    COPY_STRING(machine);
    COPY_STRING(model);
    COPY_STRING(kernelVersion);
    COPY_STRING(osVersion);
    COPY_PRIMITIVE(isJailbroken);
    COPY_STRING(bootTime);  // this field is populated in an optional monitor
    COPY_STRING(appStartTime);
    COPY_STRING(executablePath);
    COPY_STRING(executableName);
    COPY_STRING(bundleID);
    COPY_STRING(bundleName);
    COPY_STRING(bundleVersion);
    COPY_STRING(bundleShortVersion);
    COPY_STRING(appID);
    COPY_STRING(cpuArchitecture);
    COPY_PRIMITIVE(cpuType);
    COPY_PRIMITIVE(cpuSubType);
    COPY_PRIMITIVE(binaryCPUType);
    COPY_PRIMITIVE(binaryCPUSubType);
    COPY_STRING(timezone);
    COPY_STRING(processName);
    COPY_PRIMITIVE(processID);
    COPY_PRIMITIVE(parentProcessID);
    COPY_STRING(deviceAppHash);
    COPY_STRING(buildType);
    COPY_PRIMITIVE(storageSize);  // this field is populated in an optional monitor
    COPY_PRIMITIVE(memorySize);
    COPY_PRIMITIVE(freeMemory);
    COPY_PRIMITIVE(usableMemory);

    return [dict copy];
}

- (BOOL)installWithConfiguration:(KSCrashConfiguration *)configuration error:(NSError **)error
{
    self.configuration = [configuration copy] ?: [KSCrashConfiguration new];
    self.configuration.installPath = configuration.installPath ?: kscrash_getDefaultInstallPath();

    if (self.configuration.reportStoreConfiguration.appName == nil) {
        self.configuration.reportStoreConfiguration.appName = self.bundleName;
    }
    if (self.configuration.reportStoreConfiguration.reportsPath == nil) {
        self.configuration.reportStoreConfiguration.reportsPath = [self.configuration.installPath
            stringByAppendingPathComponent:[KSCrashReportStore defaultInstallSubfolder]];
    }
    KSCrashReportStore *reportStore =
        [KSCrashReportStore storeWithConfiguration:self.configuration.reportStoreConfiguration error:error];
    if (reportStore == nil) {
        return NO;
    }

    KSCrashCConfiguration config = [self.configuration toCConfiguration];
    KSCrashInstallErrorCode result =
        kscrash_install(self.bundleName.UTF8String, self.configuration.installPath.UTF8String, &config);
    KSCrashCConfiguration_Release(&config);
    if (result != KSCrashInstallErrorNone) {
        if (error != NULL) {
            *error = [KSCrash errorForInstallErrorCode:result];
        }
        return NO;
    }

    _reportStore = reportStore;
    return YES;
}

- (void)reportUserException:(NSString *)name
                     reason:(NSString *)reason
                   language:(NSString *)language
                 lineOfCode:(NSString *)lineOfCode
                 stackTrace:(NSArray *)stackTrace
              logAllThreads:(BOOL)logAllThreads
           terminateProgram:(BOOL)terminateProgram
{
    const char *cName = [name cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cReason = [reason cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cLanguage = [language cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cLineOfCode = [lineOfCode cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cStackTrace = NULL;

    if (stackTrace != nil) {
        NSError *error = nil;
        NSData *jsonData = [KSJSONCodec encode:stackTrace options:0 error:&error];
        if (jsonData == nil || error != nil) {
            KSLOG_ERROR(@"Error encoding stack trace to JSON: %@", error);
            // Don't return, since we can still record other useful information.
        }
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        cStackTrace = [jsonString cStringUsingEncoding:NSUTF8StringEncoding];
    }

    kscrash_reportUserException(cName, cReason, cLanguage, cLineOfCode, cStackTrace, logAllThreads, terminateProgram);
}

// ============================================================================
#pragma mark - Advanced API -
// ============================================================================

#define SYNTHESIZE_CRASH_STATE_PROPERTY(TYPE, NAME) \
    -(TYPE)NAME { return kscrashstate_currentState()->NAME; }

SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, activeDurationSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, backgroundDurationSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSInteger, launchesSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSInteger, sessionsSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, activeDurationSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, backgroundDurationSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSInteger, sessionsSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(BOOL, crashedLastLaunch)

// ============================================================================
#pragma mark - Utility -
// ============================================================================

- (NSMutableData *)nullTerminated:(NSData *)data
{
    if (data == nil) {
        return NULL;
    }
    NSMutableData *mutable = [NSMutableData dataWithData:data];
    [mutable appendBytes:"\0" length:1];
    return mutable;
}

+ (NSError *)errorForInstallErrorCode:(KSCrashInstallErrorCode)errorCode
{
    NSString *errorDescription;
    switch (errorCode) {
        case KSCrashInstallErrorNone:
            return nil;
        case KSCrashInstallErrorAlreadyInstalled:
            errorDescription = @"KSCrash is already installed";
            break;
        case KSCrashInstallErrorInvalidParameter:
            errorDescription = @"Invalid parameter provided";
            break;
        case KSCrashInstallErrorPathTooLong:
            errorDescription = @"Path is too long";
            break;
        case KSCrashInstallErrorCouldNotCreatePath:
            errorDescription = @"Could not create path";
            break;
        case KSCrashInstallErrorCouldNotInitializeStore:
            errorDescription = @"Could not initialize crash report store";
            break;
        case KSCrashInstallErrorCouldNotInitializeMemory:
            errorDescription = @"Could not initialize memory management";
            break;
        case KSCrashInstallErrorCouldNotInitializeCrashState:
            errorDescription = @"Could not initialize crash state";
            break;
        case KSCrashInstallErrorCouldNotSetLogFilename:
            errorDescription = @"Could not set log filename";
            break;
        case KSCrashInstallErrorNoActiveMonitors:
            errorDescription = @"No crash monitors were activated";
            break;
        default:
            errorDescription = @"Unknown error occurred";
            break;
    }
    return [NSError errorWithDomain:KSCrashErrorDomain
                               code:errorCode
                           userInfo:@{ NSLocalizedDescriptionKey : errorDescription }];
}

// ============================================================================
#pragma mark - Notifications -
// ============================================================================

+ (void)subscribeToNotifications
{
#if KSCRASH_HAS_UIAPPLICATION
    NSNotificationCenter *nCenter = [NSNotificationCenter defaultCenter];
    [nCenter addObserver:self
                selector:@selector(applicationDidBecomeActive)
                    name:UIApplicationDidBecomeActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillResignActive)
                    name:UIApplicationWillResignActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationDidEnterBackground)
                    name:UIApplicationDidEnterBackgroundNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillEnterForeground)
                    name:UIApplicationWillEnterForegroundNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillTerminate)
                    name:UIApplicationWillTerminateNotification
                  object:nil];
#endif
#if KSCRASH_HAS_NSEXTENSION
    NSNotificationCenter *nCenter = [NSNotificationCenter defaultCenter];
    [nCenter addObserver:self
                selector:@selector(applicationDidBecomeActive)
                    name:NSExtensionHostDidBecomeActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillResignActive)
                    name:NSExtensionHostWillResignActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationDidEnterBackground)
                    name:NSExtensionHostDidEnterBackgroundNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillEnterForeground)
                    name:NSExtensionHostWillEnterForegroundNotification
                  object:nil];
#endif
}

+ (void)classDidBecomeLoaded
{
    kscrash_notifyObjCLoad();
}

+ (void)applicationDidBecomeActive
{
    kscrash_notifyAppActive(true);
}

+ (void)applicationWillResignActive
{
    kscrash_notifyAppActive(false);
}

+ (void)applicationDidEnterBackground
{
    kscrash_notifyAppInForeground(false);
}

+ (void)applicationWillEnterForeground
{
    kscrash_notifyAppInForeground(true);
}

+ (void)applicationWillTerminate
{
    kscrash_notifyAppTerminate();
}

@end

//! Project version number for KSCrashFramework.
const double KSCrashFrameworkVersionNumber = 2.0000;

//! Project version string for KSCrashFramework.
const unsigned char KSCrashFrameworkVersionString[] = "2.0.0-rc.2";
