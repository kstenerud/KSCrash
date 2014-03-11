//
//  KSCrashInstallationCustomService.m
//  KSCrash
//
//  Created by David Velarde on 3/11/14.
//  Copyright (c) 2014 Karl Stenerud. All rights reserved.
//

#import "KSCrashInstallationCustomService.h"

#import "KSCrashInstallationQuincyHockey.h"

#import "ARCSafe_MemMgmt.h"
#import "KSCrashInstallation+Private.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportSinkCustomService.h"
#import "KSSingleton.h"
#import "NSError+SimpleConstructor.h"


#define kQuincyDefaultKeyUserID @"user_id"
#define kQuincyDefaultKeyContactEmail @"contact_email"
#define kQuincyDefaultKeyDescription @"crash_description"
#define kQuincyDefaultKeysExtraDescription [NSArray arrayWithObjects:@"/" @KSCrashField_System, @"/" @KSCrashField_User, nil]


@implementation KSCrashInstallationCustomService

IMPLEMENT_REPORT_PROPERTY(userID, UserID, NSString*);
IMPLEMENT_REPORT_PROPERTY(contactEmail, ContactEmail, NSString*);
IMPLEMENT_REPORT_PROPERTY(crashDescription, CrashDescription, NSString*);

@synthesize extraDescriptionKeys = _extraDescriptionKeys;
@synthesize waitUntilReachable = _waitUntilReachable;
@synthesize url = _url;
- (id) initWithRequiredProperties:(NSArray*) requiredProperties
{
    if((self = [super initWithRequiredProperties:requiredProperties]))
    {
        self.userIDKey = kQuincyDefaultKeyUserID;
        self.contactEmailKey = kQuincyDefaultKeyContactEmail;
        self.crashDescriptionKey = kQuincyDefaultKeyDescription;
        self.extraDescriptionKeys = kQuincyDefaultKeysExtraDescription;
        self.waitUntilReachable = YES;
    }
    return self;
}

- (void) dealloc
{
    as_release(_userID);
    as_release(_userIDKey);
    as_release(_contactEmail);
    as_release(_contactEmailKey);
    as_release(_crashDescription);
    as_release(_crashDescriptionKey);
    as_release(_extraDescriptionKeys);
    as_release(_url);
    as_superdealloc();
}

- (NSArray*) allCrashDescriptionKeys
{
    NSMutableArray* keys = [NSMutableArray array];
    if(self.crashDescriptionKey != nil)
    {
        [keys addObject:self.crashDescriptionKey];
    }
    if([self.extraDescriptionKeys count] > 0)
    {
        [keys addObjectsFromArray:self.extraDescriptionKeys];
    }
    return keys;
}

IMPLEMENT_EXCLUSIVE_SHARED_INSTANCE(KSCrashInstallationCustomService)



- (id) init
{
    if((self = [super initWithRequiredProperties:[NSArray arrayWithObjects:
                                                  @"url",
                                                  nil]]))
    {
    }
    return self;
}

- (id<KSCrashReportFilter>) sink
{
    KSCrashReportSinkCustomService* sink = [KSCrashReportSinkCustomService sinkWithURL:self.url
                                                               userIDKey:[self makeKeyPath:self.userIDKey]
                                                         contactEmailKey:[self makeKeyPath:self.contactEmailKey]
                                                    crashDescriptionKeys:[self makeKeyPaths:[self allCrashDescriptionKeys]]];
    sink.waitUntilReachable = self.waitUntilReachable;
    return [sink defaultCrashReportFilterSet];
}

@end
