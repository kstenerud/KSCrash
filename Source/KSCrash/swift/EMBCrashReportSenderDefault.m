//
//  EMBCrashReportSenderDefault.m
//  Embrace
//
//  Created by Joni Bandoni on 23/06/2023.
//  Copyright © 2023 embrace.io. All rights reserved.
//

#import "EMBCrashReportSenderDefault.h"
#import "KSJSONCodecObjC.h"
#import "EMBPrivateConstants.h"
#import "EMBAPIConstants.h"
#import "EMBLogger.h"
#import "EMBJSExceptionUtils.h"
#import "EMBCrashReportEventCreator.h"
#import "EMBStreamingDeviceManager.h"

@interface EMBCrashReportSenderDefault ()

@property (nonatomic, strong) id<KSCrashReportReader> crashReportReader;
@property (nonatomic, assign) dispatch_queue_t queue;
@property (nonatomic, weak) id<EMBFileJSExceptionHandler> jsFileHandler;
@property (nonatomic, strong) EMBDevice *device;
@property (nonatomic, strong) id<EMBEventUploader> eventUploader;
@property (nonatomic, strong) id<EMBUserInfoMetadataProvider> userInfoMetadata;

@end

@implementation EMBCrashReportSenderDefault

@synthesize delegate;

- (instancetype)initWithCrashReportReader:(id<KSCrashReportReader>)crashReportReader
                   jsExceptionFileHandler:(id<EMBFileJSExceptionHandler>)jsFileHandler
                            eventUploader:(id<EMBEventUploader>)eventUploader
                            currentDevice:(EMBDevice *)device
                         userInfoMetadata:(id<EMBUserInfoMetadataProvider>)userInfoMetadata
                                    queue:(dispatch_queue_t)queue
{
    self = [super init];
    if (self) {
        _crashReportReader = crashReportReader;
        _jsFileHandler = jsFileHandler;
        _eventUploader = eventUploader;
        _device = device;
        _userInfoMetadata = userInfoMetadata;
        _queue = queue;
    }
    return self;
}

- (void)send:(void (^)(NSDictionary *))completion
{
    NSArray *reportIDs = [self.crashReportReader.reportIDs copy];

    if (reportIDs.count == 0) {
        if (completion) {
            completion(@{});
        }
        return;
    }
    
    if (delegate && !delegate.shouldSendCrashEvent) {
        // we're disabled, ignore
        EMBLogDebug(@"SDK is disabled, ignoring crash event");
        [self.crashReportReader deleteAllReports];
        if (completion) {
            completion(@{});
        }
        return;
    }
    
    DispatchSafely(self.queue, ^{
        [self sendReports:reportIDs onCompletion: ^(NSDictionary *crashedSessionIds) {
            completion(crashedSessionIds);
            // only log crash reports sent if there were any reports to send
            if ([reportIDs count]) {
                EMBLogInfo(@"Sent %lu crash report(s)", (unsigned long)[reportIDs count]);
            }
            
            // remove all reports at this point because we know they have at least been cached by the upload module
            [self.crashReportReader deleteAllReports];
        }];
    });
}

- (void)sendReports:(NSArray*)reportIDs onCompletion:(void (^)(NSDictionary *))completion
{
    NSMutableDictionary *crashedSessionIds = [NSMutableDictionary new];
    dispatch_group_t group_all_reports_attempt_send = dispatch_group_create();
    
    for (NSNumber* reportID in reportIDs){
        dispatch_group_enter(group_all_reports_attempt_send);
        
        NSDictionary *report = [self.crashReportReader reportWithID:reportID];
        EMBCrashReportEventCreator *eventCreator = [[EMBCrashReportEventCreator alloc] initWithJsExceptionFileHandler:self.jsFileHandler];
        EMBEvent *crashReportEvent = [eventCreator createEventWithReport:report
                                                      deviceInfoMetadata:[self.device deviceInfo]
                                                         appInfoMetadata:[self.device appInfo]
                                                        userInfoMetadata:[self.userInfoMetadata getMetadata]];
        
        //Add sessionId present in crashReport to attach to the unsent sessions later
        NSString *sessionId = [[report valueForKey:@"user"] valueForKey:EMBCrashReportSessionIdKey];
        NSString *timestamp = [[report valueForKey:@"report"] valueForKey:@"timestamp"];
        NSString *reportUUID = [[report valueForKey:@"report"] valueForKey:@"id"];
        if (sessionId) {
            [crashedSessionIds setValue:@{@"id":reportUUID, @"timestamp":timestamp} forKey:sessionId];
        }
        
        //Read jsExceptionId from report to delete it later
        NSString *jsExceptionId = [[report valueForKey:@"user"] valueForKey:EMBCrashReportJsExceptionIdKey];
        
        [self.eventUploader sendEvent:crashReportEvent completion:^(BOOL success) {
            [self.jsFileHandler removeJsException:jsExceptionId];
            // we delete the current report just in case we dont make it to the completion handler for some reason
            [self.crashReportReader deleteReportWithID:reportID];
            
            dispatch_group_leave(group_all_reports_attempt_send);
        } cacheSync:YES];
    }
    
    // we wait for the dispatch group so that we can be certain in the completion handler it is safe to delete the remaining reports
    
    dispatch_group_wait(group_all_reports_attempt_send, DISPATCH_TIME_FOREVER);
    completion([crashedSessionIds copy]);
}

@end
