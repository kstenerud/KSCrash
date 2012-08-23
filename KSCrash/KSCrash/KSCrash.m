//
//  KSCrashReportSystem.m
//
//  Created by Karl Stenerud on 12-01-28.
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
#import "KSCrashReporter.h"
#import "KSCrashReportStore.h"
#import "KSCrashState.h"
#import "KSLogger.h"
#import "KSJSONCodecObjC.h"

#import <UIKit/UIKit.h>


/** The maximum number of reports to keep on disk. */
#ifndef KSCRASH_MaxStoredReports
    #define KSCRASH_MaxStoredReports 5
#endif

/** The directory under "Caches" to store the crash reports. */
#ifndef KSCRASH_ReportFilesDirectory
    #define KSCRASH_ReportFilesDirectory @"KSCrashReports"
#endif


@interface KSCrash ()

@property(nonatomic,readwrite,retain) NSString* reportFilesPath;
@property(nonatomic,readwrite,retain) NSString* reportFilePrefix;
@property(nonatomic,readwrite,retain) KSCrashReportStore* crashReportStore;

- (id) initWithCrashReportSink:(id<KSCrashReportFilter>) sink
                      userInfo:(NSDictionary*) userInfo
            printTraceToStdout:(BOOL) printTraceToStdout
                       onCrash:(KSReportWriteCallback) onCrash;

- (void) setUserInfo:(NSDictionary*) userInfo;

- (NSMutableData*) nullTerminated:(NSData*) data;

- (NSString*) generateUUIDString;

- (NSString*) generateReportFilesPath:(NSString*) localReportFilesPath;

- (void) pruneReportsKeeping:(int) keepReportsCount;

- (void) applicationDidBecomeActive;
- (void) applicationWillResignActive;
- (void) applicationDidEnterBackground;
- (void) applicationWillEnterForeground;
- (void) applicationWillTerminate;

@end


@implementation KSCrash

static KSCrash* g_instance;

@synthesize reportFilesPath = _reportFilesPath;
@synthesize reportFilePrefix = _reportFilePrefix;
@synthesize crashReportStore = _crashReportStore;
@synthesize sink = _sink;
@synthesize deleteAfterSend = _deleteAfterSend;

+ (BOOL) installWithCrashReportSink:(id<KSCrashReportFilter>) sink
{
    return [self installWithCrashReportSink:sink
                                   userInfo:nil
                         printTraceToStdout:NO
                                    onCrash:NULL];
}

+ (BOOL) installWithCrashReportSink:(id<KSCrashReportFilter>) sink
                           userInfo:(NSDictionary*) userInfo
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

+ (KSCrash*) instance
{
    return g_instance;
}

- (id) init
{
    return nil;
}

- (id) initWithCrashReportSink:(id<KSCrashReportFilter>) sink
                      userInfo:(NSDictionary*) userInfo
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
        
        NSError* error = nil;
        NSFileManager* fm = [NSFileManager defaultManager];
        
        NSString* reportFilesPath = [self generateReportFilesPath:KSCRASH_ReportFilesDirectory];
        if([reportFilesPath length] == 0)
        {
            KSLOG_ERROR(@"Could not determine report files path.");
            goto failed;
        }
        if(![fm fileExistsAtPath:reportFilesPath])
        {
            if(![fm createDirectoryAtPath:reportFilesPath
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error])
            {
                KSLOG_ERROR(@"Could not create cache directory %@: %@.",
                            reportFilesPath, error);
                goto failed;
            }
        }

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
        
        NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
        NSString* reportFilePrefix = [NSString stringWithFormat:@"CrashReport-%@",
                                      [infoDict objectForKey:@"CFBundleName"]];
        
        
        NSString* crashID = [self generateUUIDString];
        NSString* reportFilePath = [reportFilesPath stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"%@-%@.json",
                                     reportFilePrefix,
                                     crashID]];
        NSString* stateFilePath = [reportFilesPath stringByAppendingPathComponent:@"kscrash_state.json"];
        
        if(!kscrash_installReporter([reportFilePath UTF8String],
                                    [stateFilePath UTF8String],
                                    [crashID UTF8String],
                                    [userInfoJSON bytes],
                                    printTraceToStdout,
                                    onCrash))
        {
            goto failed;
        }
        
        self.reportFilesPath = reportFilesPath;
        self.reportFilePrefix = reportFilePrefix;
        
        self.crashReportStore = [KSCrashReportStore storeWithPath:self.reportFilesPath
                                                   filenamePrefix:self.reportFilePrefix];
        
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
    as_release(_reportFilesPath);
    as_release(_reportFilePrefix);
    as_release(_crashReportStore);
    as_release(_sink);
    as_superdealloc();
}

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

- (NSString*) generateReportFilesPath:(NSString*) localReportFilesPath
{
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
    return [cachePath stringByAppendingPathComponent:localReportFilesPath];
}

- (void) applicationDidBecomeActive
{
    kscrash_notifyApplicationActive(true);
}

- (void) applicationWillResignActive
{
    kscrash_notifyApplicationActive(false);
}

- (void) applicationDidEnterBackground
{
    kscrash_notifyApplicationInForeground(false);
}

- (void) applicationWillEnterForeground
{
    kscrash_notifyApplicationInForeground(true);
}

- (void) applicationWillTerminate
{
    kscrash_notifyApplicationTerminate();
}

- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(self.sink == nil)
    {
        return;
    }

    [self pruneReportsKeeping:KSCRASH_MaxStoredReports];
        
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
    [self.sink filterReports:reports
                onCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
     {
         if(onCompletion != nil)
         {
             onCompletion(filteredReports, completed, error);
         }
     }];
}

- (void) pruneReportsKeeping:(int) keepReportsCount
{
    NSArray* reportNames = [self.crashReportStore reportNames];
    int reportNamesCount = (int)[reportNames count];
    
    int deleteReportsCount = reportNamesCount - keepReportsCount;
    for(int i = 0; i < deleteReportsCount; i++)
    {
        [self.crashReportStore deleteReportNamed:[reportNames objectAtIndex:(NSUInteger)i]];
    }
}

- (NSUInteger) reportCount
{
    return [[self.crashReportStore reportNames] count];
}

- (NSArray*) allReports
{
    NSMutableArray* reports = [NSMutableArray array];
    for(NSString* reportName in [self.crashReportStore reportNames])
    {
        NSDictionary* report = [self.crashReportStore reportNamed:reportName];
        if(report == nil)
        {
            KSLOG_WARN(@"Deleting corrupted report %@", reportName);
            [self.crashReportStore deleteReportNamed:reportName];
        }
        else
        {
            [reports addObject:report];
        }
    }
    return reports;
}

- (void) deleteAllReports
{
    [self.crashReportStore deleteAllReports];
}

@end
