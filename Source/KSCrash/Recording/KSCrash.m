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

#import "KSCrashC.h"
#import "KSCrashCallCompletion.h"
#import "KSCrashDoctor.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFixer.h"
#import "KSCrashReportStore.h"
#import "KSCrashState.h"
#import "KSJSONCodecObjC.h"
#import "KSSingleton.h"
#import "NSError+SimpleConstructor.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#if KSCRASH_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif


// ============================================================================
#pragma mark - Globals -
// ============================================================================

@interface KSCrash ()

@property(nonatomic,readwrite,retain) NSString* bundleName;
@property(nonatomic,readwrite,retain) NSString* basePath;

// Mirrored from KSCrashAdvanced.h to provide ivars
@property(nonatomic,readwrite,retain) id<KSCrashReportFilter> sink;
@property(nonatomic,readwrite,assign) KSReportWriteCallback onCrash;
@property(nonatomic,readwrite,assign) bool printTraceToStdout;
@property(nonatomic,readwrite,assign) KSCrashDemangleLanguage demangleLanguages;

@end


static NSString* getBundleName()
{
    NSString* bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
    if(bundleName == nil)
    {
        bundleName = @"Unknown";
    }
    return bundleName;
}

static NSString* getBasePath()
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
    NSString* pathEnd = [@"KSCrash" stringByAppendingPathComponent:getBundleName()];
    return [cachePath stringByAppendingPathComponent:pathEnd];
}


@implementation KSCrash

// ============================================================================
#pragma mark - Properties -
// ============================================================================

@synthesize sink = _sink;
@synthesize userInfo = _userInfo;
@synthesize deleteBehaviorAfterSendAll = _deleteBehaviorAfterSendAll;
@synthesize handlingCrashTypes = _handlingCrashTypes;
@synthesize deadlockWatchdogInterval = _deadlockWatchdogInterval;
@synthesize printTraceToStdout = _printTraceToStdout;
@synthesize onCrash = _onCrash;
@synthesize bundleName = _bundleName;
@synthesize basePath = _basePath;
@synthesize searchThreadNames = _searchThreadNames;
@synthesize searchQueueNames = _searchQueueNames;
@synthesize introspectMemory = _introspectMemory;
@synthesize catchZombies = _catchZombies;
@synthesize doNotIntrospectClasses = _doNotIntrospectClasses;
@synthesize demangleLanguages = _demangleLanguages;


// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

IMPLEMENT_EXCLUSIVE_SHARED_INSTANCE(KSCrash)

- (id) init
{
    if((self = [super init]))
    {
        self.bundleName = getBundleName();
        self.basePath = getBasePath();
        if(self.basePath == nil)
        {
            KSLOG_ERROR(@"Failed to initialize crash handler. Crash reporting disabled.");
            return nil;
        }
        self.deleteBehaviorAfterSendAll = KSCDeleteAlways;
        self.searchThreadNames = NO;
        self.searchQueueNames = NO;
        self.introspectMemory = YES;
        self.catchZombies = NO;
    }
    return self;
}


// ============================================================================
#pragma mark - API -
// ============================================================================

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
    
    _userInfo = userInfo;
    kscrash_setUserInfoJSON([userInfoJSON bytes]);
}

- (void) setHandlingCrashTypes:(KSCrashType)handlingCrashTypes
{
    _handlingCrashTypes = kscrash_setHandlingCrashTypes(handlingCrashTypes);
}

- (void) setDeadlockWatchdogInterval:(double) deadlockWatchdogInterval
{
    _deadlockWatchdogInterval = deadlockWatchdogInterval;
    kscrash_setDeadlockWatchdogInterval(deadlockWatchdogInterval);
}

- (void) setPrintTraceToStdout:(bool)printTraceToStdout
{
    _printTraceToStdout = printTraceToStdout;
    kscrash_setPrintTraceToStdout(printTraceToStdout);
}

- (void) setOnCrash:(KSReportWriteCallback) onCrash
{
    _onCrash = onCrash;
    kscrash_setCrashNotifyCallback(onCrash);
}

- (void) setSearchThreadNames:(bool)searchThreadNames
{
    _searchThreadNames = searchThreadNames;
    kscrash_setSearchThreadNames(searchThreadNames);
}

- (void) setSearchQueueNames:(bool)searchQueueNames
{
    _searchQueueNames = searchQueueNames;
    kscrash_setSearchQueueNames(searchQueueNames);
}

- (void) setIntrospectMemory:(bool) introspectMemory
{
    _introspectMemory = introspectMemory;
    kscrash_setIntrospectMemory(introspectMemory);
}

- (void) setCatchZombies:(bool)catchZombies
{
    _catchZombies = catchZombies;
    kscrash_setCatchZombies(catchZombies);
}

- (void) setDoNotIntrospectClasses:(NSArray *)doNotIntrospectClasses
{
    _doNotIntrospectClasses = doNotIntrospectClasses;
    NSUInteger count = [doNotIntrospectClasses count];
    if(count == 0)
    {
        kscrash_setDoNotIntrospectClasses(nil, 0);
    }
    else
    {
        NSMutableData* data = [NSMutableData dataWithLength:count * sizeof(const char*)];
        const char** classes = data.mutableBytes;
        for(unsigned i = 0; i < count; i++)
        {
            classes[i] = [[doNotIntrospectClasses objectAtIndex:i] cStringUsingEncoding:NSUTF8StringEncoding];
        }
        kscrash_setDoNotIntrospectClasses(classes, (int)count);
    }
}

- (BOOL) install
{
    _handlingCrashTypes = kscrash_install(self.bundleName.UTF8String,
                                          self.basePath.UTF8String);
    if(self.handlingCrashTypes == 0)
    {
        return false;
    }

#if KSCRASH_HAS_UIAPPLICATION
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
#endif
#if KSCRASH_HAS_NSEXTENSION
    NSNotificationCenter* nCenter = [NSNotificationCenter defaultCenter];
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
    
    return true;
}

- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSArray* reports = [self allReports];
    
    KSLOG_INFO(@"Sending %d crash reports", [reports count]);
    
    [self sendReports:reports
         onCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
     {
         KSLOG_DEBUG(@"Process finished with completion: %d", completed);
         if(error != nil)
         {
             KSLOG_ERROR(@"Failed to send reports: %@", error);
         }
         if((self.deleteBehaviorAfterSendAll == KSCDeleteOnSucess && completed) ||
            self.deleteBehaviorAfterSendAll == KSCDeleteAlways)
         {
             kscrs_deleteAllReports();
         }
         kscrash_i_callCompletion(onCompletion, filteredReports, completed, error);
     }];
}

- (void) deleteAllReports
{
    kscrs_deleteAllReports();
}

- (void) reportUserException:(NSString*) name
                      reason:(NSString*) reason
                    language:(NSString*) language
                  lineOfCode:(NSString*) lineOfCode
                  stackTrace:(NSArray*) stackTrace
            terminateProgram:(BOOL) terminateProgram
{
    const char* cName = [name cStringUsingEncoding:NSUTF8StringEncoding];
    const char* cReason = [reason cStringUsingEncoding:NSUTF8StringEncoding];
    const char* cLanguage = [language cStringUsingEncoding:NSUTF8StringEncoding];
    const char* cLineOfCode = [lineOfCode cStringUsingEncoding:NSUTF8StringEncoding];
    NSError* error = nil;
    NSData* jsonData = [KSJSONCodec encode:stackTrace options:0 error:&error];
    if(jsonData == nil || error != nil)
    {
        KSLOG_ERROR(@"Error encoding stack trace to JSON: %@", error);
        // Don't return, since we can still record other useful information.
    }
    NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    const char* cStackTrace = [jsonString cStringUsingEncoding:NSUTF8StringEncoding];

    kscrash_reportUserException(cName,
                                cReason,
                                cLanguage,
                                cLineOfCode,
                                cStackTrace,
                                terminateProgram);
}

// ============================================================================
#pragma mark - Advanced API -
// ============================================================================

#define SYNTHESIZE_CRASH_STATE_PROPERTY(TYPE, NAME) \
- (TYPE) NAME \
{ \
    return kscrashstate_currentState()->NAME; \
}

SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, activeDurationSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, backgroundDurationSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(int, launchesSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(int, sessionsSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, activeDurationSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, backgroundDurationSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(int, sessionsSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(BOOL, crashedLastLaunch)

- (NSUInteger) reportCount
{
    return (NSUInteger)kscrs_getReportCount();
}

- (void) sendReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if([reports count] == 0)
    {
        kscrash_i_callCompletion(onCompletion, reports, YES, nil);
        return;
    }
    
    if(self.sink == nil)
    {
        kscrash_i_callCompletion(onCompletion, reports, NO,
                                 [NSError errorWithDomain:[[self class] description]
                                                     code:0
                                              description:@"No sink set. Crash reports not sent."]);
        return;
    }
    
    [self.sink filterReports:reports
                onCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
     {
         kscrash_i_callCompletion(onCompletion, filteredReports, completed, error);
     }];
}

- (NSData*) loadCrashReportJSONWithID:(int64_t) reportID
{
    // Have to do this the ugly way in order to avoid use of exceptions :/
    char* rawReport = NULL;
    char* fixedReport = NULL;
    NSData* jsonData = nil;

    if(reportID <= 0)
    {
        KSLOG_ERROR(@"Report ID was %llx", reportID);
        return nil;
    }
    rawReport = kscrs_readReport(reportID);
    if(rawReport == NULL)
    {
        KSLOG_ERROR(@"Failed to load report ID %llx", reportID);
    }
    else
    {
        fixedReport = kscrf_fixupCrashReport(rawReport);
        if(fixedReport == NULL)
        {
            KSLOG_ERROR(@"Failed to fixup report ID %llx", reportID);
        }
    }

    if(fixedReport != NULL)
    {
        jsonData = [NSData dataWithBytesNoCopy:fixedReport length:strlen(fixedReport) freeWhenDone:YES];
        rawReport = NULL;
    }
    if(rawReport != NULL)
    {
        free(rawReport);
    }
    return jsonData;
}

- (void) doctorReport:(NSMutableDictionary*) report
{
    NSMutableDictionary* crashReport = report[@KSCrashField_Crash];
    if(crashReport != nil)
    {
        crashReport[@KSCrashField_Diagnosis] = [[KSCrashDoctor doctor] diagnoseCrash:report];
    }
    crashReport = report[@KSCrashField_RecrashReport][@KSCrashField_Crash];
    if(crashReport != nil)
    {
        crashReport[@KSCrashField_Diagnosis] = [[KSCrashDoctor doctor] diagnoseCrash:report];
    }
}

- (NSDictionary*) reportWithID:(int64_t) reportID
{
    NSData* jsonData = [self loadCrashReportJSONWithID:reportID];
    if(jsonData == nil)
    {
        return nil;
    }

    NSError* error = nil;
    NSMutableDictionary* crashReport = [KSJSONCodec decode:jsonData
                                                   options:KSJSONDecodeOptionIgnoreNullInArray |
                                                           KSJSONDecodeOptionIgnoreNullInObject |
                                                           KSJSONDecodeOptionKeepPartialObject
                                                     error:&error];
    if(error != nil)
    {
        KSLOG_ERROR(@"Encountered error loading crash report %llx: %@", reportID, error);
    }
    if(crashReport == nil)
    {
        KSLOG_ERROR(@"Could not load crash report");
        return nil;
    }
    [self doctorReport:crashReport];

    return crashReport;
}

- (NSArray*) allReports
{
    int reportCount = kscrs_getReportCount();
    int64_t reportIDs[reportCount];
    reportCount = kscrs_getReportIDs(reportIDs, reportCount);
    NSMutableArray* reports = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for(int i = 0; i < reportCount; i++)
    {
        NSDictionary* report = [self reportWithID:reportIDs[i]];
        if(report != nil)
        {
            [reports addObject:report];
        }
    }
    
    return reports;
}

- (BOOL) redirectConsoleLogToFile
{
    return kscrash_redirectConsoleLogToFile();
}


// ============================================================================
#pragma mark - Utility -
// ============================================================================

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

@end


//! Project version number for KSCrashFramework.
const double KSCrashFrameworkVersionNumber = 1.112;

//! Project version string for KSCrashFramework.
const unsigned char KSCrashFrameworkVersionString[] = "1.11.2";
