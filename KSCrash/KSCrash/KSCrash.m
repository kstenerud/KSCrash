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


#import "KSCrashAdvanced.h"

#import "ARCSafe_MemMgmt.h"
#import "KSCrashC.h"
#import "KSCrashReportStore.h"
#import "KSCrashState.h"
#import "KSJSONCodecObjC.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#import <UIKit/UIKit.h>


// ============================================================================
#pragma mark - Default Constants -
// ============================================================================

/** The maximum number of reports to keep on disk. */
#ifndef KSCRASH_MaxStoredReports
    #define KSCRASH_MaxStoredReports 5
#endif

/** The directory under "Caches" to store the crash reports. */
#ifndef KSCRASH_ReportFilesDirectory
    #define KSCRASH_ReportFilesDirectory @"KSCrashReports"
#endif


// ============================================================================
#pragma mark - Constants -
// ============================================================================

#define kCrashLogFilenameSuffix "-CrashLog.txt"
#define kCrashStateFilenameSuffix "-CrashState.json"


// ============================================================================
#pragma mark - Globals -
// ============================================================================

static KSCrash* g_instance;


// ============================================================================
#pragma mark - IVars -
// ============================================================================

@interface KSCrash ()

@property(nonatomic,readwrite,retain) KSCrashReportStore* crashReportStore;

@end


@implementation KSCrash

// ============================================================================
#pragma mark - Properties -
// ============================================================================

@synthesize crashReportStore = _crashReportStore;
@synthesize sink = _sink;
@synthesize deleteAfterSend = _deleteAfterSend;

- (void) setSink:(id<KSCrashReportFilter>)sink
{
    as_autorelease_noref(_sink);
    if([sink conformsToProtocol:@protocol(KSCrashReportDefaultFilterSet)])
    {
        _sink = [[KSCrashReportFilterPipeline alloc] initWithFilters:
                 [(id<KSCrashReportDefaultFilterSet>)sink defaultCrashReportFilterSet], nil];
    }
    else
    {
        _sink = as_retain(sink);
    }
}


// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

- (id) init
{
    return nil;
}

- (id) initWithCrashReportSink:(id<KSCrashReportFilter>) sink
                      userInfo:(NSDictionary*) userInfo
               zombieCacheSize:(unsigned int) zombieCacheSize
            printTraceToStdout:(BOOL) printTraceToStdout
                       onCrash:(KSReportWriteCallback) onCrash
{
    if(g_instance != nil)
    {
        KSLOG_ERROR(@"Only one instance allowed. Use [KSCrash instance] to access it");
        return nil;
    }

    if((self = [super init]))
    {
        self.sink = sink;
        self.deleteAfterSend = YES;

        NSString* reportFilesPath = [[self class] reportFilesPath];
        if([reportFilesPath length] == 0)
        {
            goto failed;
        }
        if(![[self class] ensureDirectoryExists:reportFilesPath])
        {
            goto failed;
        }

        NSError* error = nil;
        NSData* userInfoJSON = nil;
        if(userInfo != nil)
        {
            userInfoJSON = [self nullTerminated:[KSJSONCodec encode:userInfo
                                                            options:KSJSONEncodeOptionSorted
                                                              error:&error]];
            if(error != NULL)
            {
                KSLOG_ERROR(@"Could not serialize user info: %@", error);
            }
        }

        self.crashReportStore = [KSCrashReportStore storeWithPath:reportFilesPath];

        NSString* crashID = [self generateUUIDString];
        NSString* primaryReportPath = [self.crashReportStore pathToPrimaryReportWithID:crashID];
        NSString* secondaryReportPath = [self.crashReportStore pathToSecondaryReportWithID:crashID];

        if(!kscrash_install([primaryReportPath UTF8String],
                            [secondaryReportPath UTF8String],
                            [[[self class] stateFilePath] UTF8String],
                            [crashID UTF8String],
                            [userInfoJSON bytes],
                            zombieCacheSize,
                            printTraceToStdout,
                            onCrash))
        {
            goto failed;
        }


        NSNotificationCenter* nCenter = [NSNotificationCenter defaultCenter];
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
    }
    return self;

failed:
    KSLOG_ERROR(@"Failed to initialize crash handler. Crash reporting disabled.");
    as_release(self);
    return nil;
}

- (void) dealloc
{
    as_release(_crashReportStore);
    as_release(_sink);
    as_superdealloc();
}


// ============================================================================
#pragma mark - Utility -
// ============================================================================

+ (NSString*) bundleName
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
}

+ (NSString*) reportFilesPath
{
    NSString* bundleName = [self bundleName];
    NSString* reportFilesPath = [KSCRASH_ReportFilesDirectory stringByAppendingPathComponent:bundleName];

    NSArray* directories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                               NSUserDomainMask,
                                                               YES);
    if([directories count] == 0)
    {
        KSLOG_ERROR(@"Could not locate cache directory path.");
        return nil;
    }
    NSString* cachePath = [directories objectAtIndex:0];
    if([cachePath length] == 0)
    {
        KSLOG_ERROR(@"Could not locate cache directory path.");
        return nil;
    }
    NSString* result = [cachePath stringByAppendingPathComponent:reportFilesPath];
    if([result length] == 0)
    {
        KSLOG_ERROR(@"Could not determine report files path.");
        return nil;
    }
    return result;
}

+ (NSString*) logFilename
{
    return [NSString stringWithFormat:@"%@" kCrashLogFilenameSuffix, [[self class] bundleName]];
}

+ (NSString*) logFilePath
{
    return [[self reportFilesPath] stringByAppendingPathComponent:[self logFilename]];
}

+ (NSString*) stateFilename
{
    return [NSString stringWithFormat:@"%@" kCrashStateFilenameSuffix, [[self class] bundleName]];
}

+ (NSString*) stateFilePath
{
    return [[self reportFilesPath] stringByAppendingPathComponent:[self stateFilename]];
}

- (NSMutableData*) nullTerminated:(NSData*) data
{
    if(data == nil)
    {
        return NULL;
    }
    NSMutableData* mutable = [NSMutableData dataWithData:data];
    [mutable appendBytes:"\0" length:1];
    return mutable;
}

- (NSString*) generateUUIDString
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* uuidString = (as_bridge_transfer NSString*)CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);

    return as_autorelease(uuidString);
}

+ (BOOL) ensureDirectoryExists:(NSString*) path
{
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];

    if(![fm fileExistsAtPath:path])
    {
        if(![fm createDirectoryAtPath:path
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&error])
        {
            KSLOG_ERROR(@"Could not create directory %@: %@.", path, error);
            return NO;
        }
    }

    return YES;
}

- (void) setUserInfo:(NSDictionary*) userInfo
{
    NSError* error = nil;
    NSData* userInfoJSON = nil;
    if(userInfo != nil)
    {
        userInfoJSON = [self nullTerminated:[KSJSONCodec encode:userInfo
                                                        options:KSJSONEncodeOptionSorted
                                                          error:&error]];
        if(error != NULL)
        {
            KSLOG_ERROR(@"Could not serialize user info: %@", error);
            return;
        }
    }
    kscrash_setUserInfoJSON([userInfoJSON bytes]);
}


// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

- (void) applicationDidBecomeActive
{
    kscrashstate_notifyAppActive(true);
}

- (void) applicationWillResignActive
{
    kscrashstate_notifyAppActive(false);
}

- (void) applicationDidEnterBackground
{
    kscrashstate_notifyAppInForeground(false);
}

- (void) applicationWillEnterForeground
{
    kscrashstate_notifyAppInForeground(true);
}

- (void) applicationWillTerminate
{
    kscrashstate_notifyAppTerminate();
}


// ============================================================================
#pragma mark - API -
// ============================================================================

+ (BOOL) installWithCrashReportSink:(id<KSCrashReportFilter>) sink
{
    return [self installWithCrashReportSink:sink
                                   userInfo:nil
                            zombieCacheSize:0
                         printTraceToStdout:NO
                                    onCrash:NULL];
}

+ (BOOL) installWithCrashReportSink:(id<KSCrashReportFilter>) sink
                           userInfo:(NSDictionary*) userInfo
                    zombieCacheSize:(unsigned int) zombieCacheSize
                 printTraceToStdout:(BOOL) printTraceToStdout
                            onCrash:(KSReportWriteCallback) onCrash
{
    @synchronized(self)
    {
        if(g_instance != nil)
        {
            KSLOG_INFO(@"Already installed. Ignoring this invocation");
            return YES;
        }
        g_instance = [[self alloc] initWithCrashReportSink:sink
                                                  userInfo:userInfo
                                           zombieCacheSize:zombieCacheSize
                                        printTraceToStdout:printTraceToStdout
                                                   onCrash:onCrash];
        if(g_instance == nil)
        {
            return NO;
        }

        KSLOG_DEBUG(@"Crash reporter installed");

        return YES;
    }
}

+ (void) setUserInfo:(NSDictionary*) userInfo
{
    [g_instance setUserInfo:userInfo];
}


// ============================================================================
#pragma mark - Advanced API -
// ============================================================================

+ (KSCrash*) instance
{
    return g_instance;
}

- (NSUInteger) reportCount
{
    return [self.crashReportStore reportCount];
}

- (NSString*) crashReportsPath
{
    return self.crashReportStore.path;
}

- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(self.sink == nil)
    {
        return;
    }

    [self.crashReportStore pruneReportsLeaving:KSCRASH_MaxStoredReports];

    NSArray* reports = [self allReports];
    if([reports count] == 0)
    {
        return;
    }

    KSLOG_INFO(@"Sending %d crash reports", [reports count]);

    [self sendReports:reports
         onCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
     {
         #pragma unused(filteredReports)
         KSLOG_DEBUG(@"Process finished with completion: %d", completed);
         if(error != nil)
         {
             KSLOG_ERROR(@"Failed to send reports: %@", error);
         }
         if(self.deleteAfterSend && completed)
         {
             [self deleteAllReports];
         }
         if(onCompletion != nil)
         {
             onCompletion(filteredReports, completed, error);
         }
     }];
}

- (void) sendReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSParameterAssert(reports);
    [self.sink filterReports:reports
                onCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
     {
         if(onCompletion != nil)
         {
             onCompletion(filteredReports, completed, error);
         }
     }];
}

- (NSArray*) allReports
{
    return [self.crashReportStore allReports];
}

- (void) deleteAllReports
{
    [self.crashReportStore deleteAllReports];
}

+ (BOOL) redirectLogsToFile:(NSString*) filename overwrite:(BOOL) overwrite
{
    return kslog_setLogFilename([filename UTF8String], overwrite);
}

+ (BOOL) logToFile
{
    if(![self redirectLogsToFile:[self logFilePath] overwrite:YES])
    {
        KSLOG_ERROR(@"Could not redirect logs to %@", [self logFilePath]);
        return NO;
    }
    return YES;
}



@end
