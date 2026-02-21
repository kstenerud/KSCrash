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

#import "KSCompilerDefines.h"
#import "KSCrashC.h"
#import "KSCrashConfiguration+Private.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_AppState.h"
#import "KSCrashMonitor_Memory.h"
#import "KSCrashMonitor_System.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSDate.h"
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
    NSString *pathEnd = [KSCRASH_NS_STRING(@"KSCrash") stringByAppendingPathComponent:kscrash_getBundleName()];
    return [cachePath stringByAppendingPathComponent:pathEnd];
}

static const char *kscrash_namespacedSearchPath(NSSearchPathDirectory directory)
{
    NSArray *directories = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
    if ([directories count] == 0) {
        return NULL;
    }
    NSString *basePath = [directories objectAtIndex:0];
    if ([basePath length] == 0) {
        return NULL;
    }
    NSString *path = [basePath stringByAppendingPathComponent:KSCRASH_NS_STRING(@"KSCrash")];
    return strdup(path.UTF8String);
}

const char *kscrash_documentsPath(void)
{
    static const char *path = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = kscrash_namespacedSearchPath(NSDocumentDirectory);
    });
    return path;
}

const char *kscrash_applicationSupportPath(void)
{
    static const char *path = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = kscrash_namespacedSearchPath(NSApplicationSupportDirectory);
    });
    return path;
}

const char *kscrash_cachesPath(void)
{
    static const char *path = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = kscrash_namespacedSearchPath(NSCachesDirectory);
    });
    return path;
}

static void currentSnapshotUserReportedExceptionHandler(NSException *exception)
{
    if (!gIsSharedInstanceCreated) {
        KSLOG_ERROR(@"Shared instance must exist before this function is called.");
        return;
    }
    [[KSCrash sharedInstance] reportNSException:exception logAllThreads:YES];
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

static void onNSExceptionHandlingEnabled(NSUncaughtExceptionHandler *uncaughtExceptionHandler,
                                         KSCrashCustomNSExceptionReporter *customNSExceptionReporter)
{
    KSCrash.sharedInstance.uncaughtExceptionHandler = uncaughtExceptionHandler;
    KSCrash.sharedInstance.customNSExceptionReporter = customNSExceptionReporter;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _bundleName = kscrash_getBundleName();
        _currentSnapshotUserReportedExceptionHandler = &currentSnapshotUserReportedExceptionHandler;
        kscm_nsexception_setOnEnabledHandler(onNSExceptionHandlingEnabled);
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

        if (userInfoDict == nil) {
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

        if (userInfoJSON == nil) {
            KSLOG_ERROR(@"Could not serialize user info: %@", error.localizedDescription);
            return;
        }
    }

    NSString *userInfoString =
        userInfoJSON ? [[NSString alloc] initWithData:userInfoJSON encoding:NSUTF8StringEncoding] : nil;
    kscrash_setUserInfoJSON(userInfoString.UTF8String);
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
    NSMutableDictionary *dict = [NSMutableDictionary new];

    // System-monitor fields come from a snapshot of the mmap'd struct
    KSCrash_SystemData sd;
    if (kscm_system_getSystemData(&sd)) {
#define COPY_SYS_STR(FIELD, KEY) \
    if (sd.FIELD[0] != '\0') dict[@KEY] = [NSString stringWithUTF8String:sd.FIELD]
        COPY_SYS_STR(systemName, "systemName");
        COPY_SYS_STR(systemVersion, "systemVersion");
        COPY_SYS_STR(machine, "machine");
        COPY_SYS_STR(model, "model");
        COPY_SYS_STR(kernelVersion, "kernelVersion");
        COPY_SYS_STR(osVersion, "osVersion");
        dict[@"isJailbroken"] = @(sd.isJailbroken);
        dict[@"procTranslated"] = @(sd.procTranslated);
        COPY_SYS_STR(appStartTime, "appStartTime");
        COPY_SYS_STR(executablePath, "executablePath");
        COPY_SYS_STR(executableName, "executableName");
        COPY_SYS_STR(bundleID, "bundleID");
        COPY_SYS_STR(bundleName, "bundleName");
        COPY_SYS_STR(bundleVersion, "bundleVersion");
        COPY_SYS_STR(bundleShortVersion, "bundleShortVersion");
        COPY_SYS_STR(appID, "appID");
        COPY_SYS_STR(cpuArchitecture, "cpuArchitecture");
        COPY_SYS_STR(binaryArchitecture, "binaryArchitecture");
        COPY_SYS_STR(clangVersion, "clangVersion");
        dict[@"cpuType"] = @(sd.cpuType);
        dict[@"cpuSubType"] = @(sd.cpuSubType);
        dict[@"binaryCPUType"] = @(sd.binaryCPUType);
        dict[@"binaryCPUSubType"] = @(sd.binaryCPUSubType);
        COPY_SYS_STR(timezone, "timezone");
        COPY_SYS_STR(processName, "processName");
        dict[@"processID"] = @(sd.processID);
        dict[@"parentProcessID"] = @(sd.parentProcessID);
        COPY_SYS_STR(deviceAppHash, "deviceAppHash");
        COPY_SYS_STR(buildType, "buildType");
        dict[@"memorySize"] = @(sd.memorySize);
        dict[@"freeMemory"] = @(sd.freeMemory);
        dict[@"usableMemory"] = @(sd.usableMemory);
        if (sd.bootTimestamp > 0) {
            char bootTimeBuf[KSDATE_BUFFERSIZE];
            ksdate_utcStringFromTimestamp((time_t)sd.bootTimestamp, bootTimeBuf, sizeof(bootTimeBuf));
            dict[@"bootTime"] = [NSString stringWithUTF8String:bootTimeBuf];
        }
        if (sd.storageSize > 0) {
            dict[@"storageSize"] = @(sd.storageSize);
        }
        if (sd.freeStorageSize > 0) {
            dict[@"freeStorageSize"] = @(sd.freeStorageSize);
        }
#undef COPY_SYS_STR
    }

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
           terminateProgram:(BOOL)terminateProgram KS_KEEP_FUNCTION_IN_STACKTRACE
{
    const char *cName = [name cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cReason = [reason cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cLanguage = [language cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cLineOfCode = [lineOfCode cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cStackTrace = NULL;

    if (stackTrace != nil) {
        NSError *error = nil;
        NSData *jsonData = [KSJSONCodec encode:stackTrace options:0 error:&error];
        if (jsonData == nil) {
            KSLOG_ERROR(@"Error encoding stack trace to JSON: %@", error);
            // Don't return, since we can still record other useful information.
        }
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        cStackTrace = [jsonString cStringUsingEncoding:NSUTF8StringEncoding];
    }

    kscrash_reportUserException(cName, cReason, cLanguage, cLineOfCode, cStackTrace, logAllThreads, terminateProgram);
    KS_THWART_TAIL_CALL_OPTIMISATION
}

- (void)reportNSException:(NSException *)exception logAllThreads:(BOOL)logAllThreads KS_KEEP_FUNCTION_IN_STACKTRACE
{
    if (_customNSExceptionReporter == NULL) {
        KSLOG_ERROR(@"NSExcepttion monitor needs to be installed before reporting custom exceptions");
        return;
    }
    _customNSExceptionReporter(exception, logAllThreads);
    KS_THWART_TAIL_CALL_OPTIMISATION
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
const double KSCrashFrameworkVersionNumber = 2.0501;

//! Project version string for KSCrashFramework.
const unsigned char KSCrashFrameworkVersionString[] = "2.5.1";
