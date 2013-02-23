//
//  KSCrashInstallationQuincyHockey.m
//
//  Created by Karl Stenerud on 2013-02-10.
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

#import "KSCrashInstallationQuincyHockey.h"

#import "ARCSafe_MemMgmt.h"
#import "KSCrashInstallation+Private.h"
#import "KSCrashReportSinkQuincyHockey.h"
#import "KSSingleton.h"
#import "NSError+SimpleConstructor.h"


#define kQuincyDefaultKeyUserID @"user_id"
#define kQuincyDefaultKeyContactEmail @"contact_email"
#define kQuincyDefaultKeyDescription @"description"


typedef enum
{
    ReportFieldUserID,
    ReportFieldContactEmail,
    ReportFieldDescription,
    ReportFieldFileContainingDescription,
    ReportFieldCount
} ReportField;


@implementation KSCrashInstallationBaseQuincyHockey

IMPLEMENT_REPORT_PROPERTY(quincyhockey, userID, UserID, NSString*);
IMPLEMENT_REPORT_PROPERTY(quincyhockey, contactEmail, ContactEmail, NSString*);
IMPLEMENT_REPORT_PROPERTY(quincyhockey, description, Description, NSString*);

- (id) initWithMaxReportFieldCount:(size_t) maxReportFieldCount
                requiredProperties:(NSArray*) requiredProperties
{
    if((self = [super initWithMaxReportFieldCount:maxReportFieldCount
                requiredProperties:requiredProperties]))
    {
        self.userIDKey = kQuincyDefaultKeyUserID;
        self.contactEmailKey = kQuincyDefaultKeyContactEmail;
        self.descriptionKey = kQuincyDefaultKeyDescription;
    }
    return self;
}

- (void) dealloc
{
    as_release(_userID);
    as_release(_userIDKey);
    as_release(_contactEmail);
    as_release(_contactEmailKey);
    as_release(_description);
    as_release(_descriptionKey);
    as_superdealloc();
}

- (NSString*) makeKeyPath:(NSString*) keyPath
{
    BOOL isAbsoluteKeyPath = [keyPath length] > 0 && [keyPath characterAtIndex:0] == '/';
    return isAbsoluteKeyPath ? keyPath : [@"user/" stringByAppendingString:keyPath];
}

@end


@implementation KSCrashInstallationQuincy

IMPLEMENT_EXCLUSIVE_SHARED_INSTANCE(KSCrashInstallationQuincy)

@synthesize url = _url;

- (id) init
{
    if((self = [super initWithMaxReportFieldCount:10
                               requiredProperties:[NSArray arrayWithObjects:
                                                   @"url",
                                                   nil]]))
    {
    }
    return self;
}

- (void) dealloc
{
    as_release(_url);
    as_superdealloc();
}

- (id<KSCrashReportFilter>) sink
{
    KSCrashReportSinkQuincy* sink = [KSCrashReportSinkQuincy sink];
    sink.url = self.url;
    NSArray* pipeline = [sink defaultCrashReportFilterSetWithUserIDKey:[self makeKeyPath:self.userIDKey]
                                                       contactEmailKey:[self makeKeyPath:self.contactEmailKey]
                                                  crashDescriptionKeys:[NSArray arrayWithObject:[self makeKeyPath:self.descriptionKey]]];
    return [KSCrashReportFilterPipeline filterWithFilters:pipeline, nil];
}

@end


@implementation KSCrashInstallationHockey

IMPLEMENT_EXCLUSIVE_SHARED_INSTANCE(KSCrashInstallationHockey)

@synthesize appIdentifier = _appIdentifier;

- (id) init
{
    if((self = [super initWithMaxReportFieldCount:10
                               requiredProperties:[NSArray arrayWithObjects:
                                                   @"appIdentifier",
                                                   nil]]))
    {
    }
    return self;
}

- (void) dealloc
{
    as_release(_appIdentifier);
    as_superdealloc();
}

- (id<KSCrashReportFilter>) sink
{
    KSCrashReportSinkHockey* sink = [KSCrashReportSinkHockey sink];
    sink.appIdentifier = self.appIdentifier;
    NSArray* pipeline = [sink defaultCrashReportFilterSetWithUserIDKey:[self makeKeyPath:self.userIDKey]
                                                       contactEmailKey:[self makeKeyPath:self.contactEmailKey]
                                                  crashDescriptionKeys:[NSArray arrayWithObject:[self makeKeyPath:self.descriptionKey]]];
    return [KSCrashReportFilterPipeline filterWithFilters:pipeline, nil];
}

@end
