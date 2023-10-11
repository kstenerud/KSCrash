//
//  EMBCrashReportSenderDefault.h
//  Embrace
//
//  Created by Joni Bandoni on 23/06/2023.
//  Copyright © 2023 embrace.io. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EMBUserInfoMetadataProvider.h"
#import "EMBCrashReportSender.h"
#import "KSCrash.h"
#import "EMBFileJSExceptionHandler.h"
#import "EMBServer.h"
#import "EMBDevice.h"

NS_ASSUME_NONNULL_BEGIN

@interface EMBCrashReportSenderDefault : NSObject <EMBCrashReportSender>

- (instancetype)initWithCrashReportReader:(id<KSCrashReportReader>)crashReportReader
                   jsExceptionFileHandler:(id<EMBFileJSExceptionHandler>)jsFileHandler
                            eventUploader:(id<EMBEventUploader>)eventUploader
                            currentDevice:(EMBDevice *)device
                         userInfoMetadata:(id<EMBUserInfoMetadataProvider>)userInfoMetadata
                                    queue:(dispatch_queue_t)queue;

- (void)send:(void (^)(NSDictionary *))completion;

@end

NS_ASSUME_NONNULL_END
