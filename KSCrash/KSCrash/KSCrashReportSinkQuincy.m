//
//  KSCrashReportSinkQuincy.m
//
//  Created by Karl Stenerud on 2012-02-26.
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


#import "KSCrashReportSinkQuincy.h"

#import "ARCSafe_MemMgmt.h"
#import "KSCrashReportFields.h"
#import "KSHTTPMultipartPostBody.h"
#import "KSHTTPRequestSender.h"
#import "NSData+GZip.h"
#import "KSCrashReportFilterAppleFmt.h"
#import "KSJSONCodecObjC.h"
#import "KSReachability.h"
#import "Container+DeepSearch.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


#define kFilterKeyStandard @"standard"
#define kFilterKeyApple @"apple"

#define kDefaultKeyUserID @"user_id"
#define kDefaultKeyContactEmail @"contact_email"
#define kDefaultKeyDescription @"crash_description"

@interface KSCrashReportFilterQuincy ()

@property(nonatomic, readwrite, retain) NSString* userIDKey;
@property(nonatomic, readwrite, retain) NSString* contactEmailKey;
@property(nonatomic, readwrite, retain) NSString* crashDescriptionKey;

- (NSString*) cdataEscaped:(NSString*) string;

- (NSString*) toQuincyFormat:(NSDictionary*) reportTuple;

- (NSString*) blankForNil:(NSString*) string;

@end


@implementation KSCrashReportFilterQuincy

@synthesize userIDKey = _userIDKey;
@synthesize contactEmailKey = _contactEmailKey;
@synthesize crashDescriptionKey = _crashDescriptionKey;

+ (KSCrashReportFilterQuincy*) filter
{
    return [self filterWithUserIDKey:nil
                     contactEmailKey:nil
                 crashDescriptionKey:nil];
}

+ (KSCrashReportFilterQuincy*) filterWithUserIDKey:(NSString*) userIDKey
                                   contactEmailKey:(NSString*) contactEmailKey
                               crashDescriptionKey:(NSString*) crashDescriptionKey
{
    return as_autorelease([[self alloc] initWithUserIDKey:userIDKey
                                          contactEmailKey:contactEmailKey
                                      crashDescriptionKey:crashDescriptionKey]);
}

- (id) init
{
    return [self initWithUserIDKey:nil
                   contactEmailKey:nil
               crashDescriptionKey:nil];
}

- (id) initWithUserIDKey:(NSString*) userIDKey
         contactEmailKey:(NSString*) contactEmailKey
     crashDescriptionKey:(NSString*) crashDescriptionKey
{
    if((self = [super init]))
    {
        self.userIDKey = userIDKey != nil ? userIDKey : kDefaultKeyUserID;
        self.contactEmailKey = contactEmailKey != nil ? contactEmailKey : kDefaultKeyContactEmail;
        self.crashDescriptionKey = crashDescriptionKey != nil ? crashDescriptionKey : kDefaultKeyDescription;
    }
    return self;
}

- (void) dealloc
{
    as_release(_userIDKey);
    as_release(_contactEmailKey);
    as_release(_crashDescriptionKey);
    as_superdealloc();
}

- (NSString*) cdataEscaped:(NSString*) string
{
    return [string stringByReplacingOccurrencesOfString:@"]]>"
                                             withString:@"]]" @"]]><![CDATA[" @">"
                                                options:NSLiteralSearch
                                                  range:NSMakeRange(0,string.length)];
}

- (NSString*) blankForNil:(NSString*) string
{
    return string == nil ? @"" : string;
}

- (NSString*) toQuincyFormat:(NSDictionary*) reportTuple
{
    NSDictionary* report = [reportTuple objectForKey:kFilterKeyStandard];
    NSString* appleReport = [reportTuple objectForKey:kFilterKeyApple];
    NSDictionary* systemDict = [report objectForKey:@KSCrashField_System];
    NSString* userID = [self blankForNil:[report objectForKeyPath:self.userIDKey]];
    NSString* contactEmail = [self blankForNil:[report objectForKeyPath:self.contactEmailKey]];
    NSString* crashReportDescription = [self blankForNil:[report objectForKeyPath:self.crashDescriptionKey]];

    NSString* result = [NSString stringWithFormat:
                        @"\n    <crash>\n"
                        @"        <applicationname>%@</applicationname>\n"
                        @"        <bundleidentifier>%@</bundleidentifier>\n"
                        @"        <systemversion>%@</systemversion>\n"
                        @"        <platform>%@</platform>\n"
                        @"        <senderversion>%@</senderversion>\n"
                        @"        <version>%@</version>\n"
                        @"        <log><![CDATA[%@]]></log>\n"
                        @"        <userid>%@</userid>\n"
                        @"        <contact>%@</contact>\n"
                        @"        <description><![CDATA[%@]]></description>\n"
                        @"    </crash>",
                        [systemDict objectForKey:@"CFBundleExecutable"],
                        [systemDict objectForKey:@"CFBundleIdentifier"],
                        [systemDict objectForKey:@"system_version"],
                        [systemDict objectForKey:@"machine"],
                        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                        [systemDict objectForKey:@"CFBundleVersion"],
                        [self cdataEscaped:appleReport],
                        userID,
                        contactEmail,
                        [self cdataEscaped:crashReportDescription]];
    KSLOG_TRACE(@"Report:\n%@", result);
    return result;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        [filteredReports addObject:[self toQuincyFormat:report]];
    }

    onCompletion(filteredReports, YES, nil);
}

@end



@interface KSCrashReportSinkQuincy ()

/** The URL to connect to. */
@property(nonatomic,readwrite,retain) NSURL* url;

@property(nonatomic,readwrite,copy) void(^onSuccess)(NSString* response);

@property(nonatomic,readwrite,retain) KSReachableOperation* reachableOperation;

- (NSData*) toQuincyBody:(NSArray*) reports;

- (void) filterReports:(NSArray*) reports
              bodyName:(NSString*) bodyName
       bodyContentType:(NSString*) bodyContentType
          bodyFilename:(NSString*) bodyFilename
          onCompletion:(KSCrashReportFilterCompletion) onCompletion;

@end


@implementation KSCrashReportSinkQuincy

@synthesize url = _url;
@synthesize onSuccess = _onSuccess;
@synthesize reachableOperation = _reachableOperation;

+ (KSCrashReportSinkQuincy*) sinkWithURL:(NSURL*) url
                               onSuccess:(void(^)(NSString* response)) onSuccess
{
    return as_autorelease([[self alloc] initWithURL:url onSuccess:onSuccess]);
}

- (id) initWithURL:(NSURL*) url
         onSuccess:(void(^)(NSString* response)) onSuccess
{
    if((self = [super init]))
    {
        self.url = url;
        self.onSuccess = onSuccess;
    }
    return self;
}

- (void) dealloc
{
    as_release(_reachableOperation);
    as_release(_url);
    as_release(_onSuccess);
    as_superdealloc();
}

- (NSArray*) defaultCrashReportFilterSet
{
    return [self defaultCrashReportFilterSetWithUserIDKey:nil
                                          contactEmailKey:nil
                                      crashDescriptionKey:nil];
}

- (NSArray*) defaultCrashReportFilterSetWithUserIDKey:(NSString*) userIDKey
                                      contactEmailKey:(NSString*) contactEmailKey
                                  crashDescriptionKey:(NSString*) crashDescriptionKey
{
    return [NSArray arrayWithObjects:
            [KSCrashReportFilterCombine filterWithFiltersAndKeys:
             [KSCrashReportFilterPassthrough filter],
             kFilterKeyStandard,
             [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
             kFilterKeyApple,
             nil],
            [KSCrashReportFilterQuincy filterWithUserIDKey:userIDKey
                                           contactEmailKey:contactEmailKey
                                       crashDescriptionKey:crashDescriptionKey],
            self,
            nil];
}

- (NSData*) toQuincyBody:(NSArray*) reports
{
    NSMutableString* xmlString = [NSMutableString stringWithString:@"<crashes>"];

    for(NSString* report in reports)
    {
        [xmlString appendString:report];
    }
    [xmlString appendString:@"</crashes>"];

    return [xmlString dataUsingEncoding:NSUTF8StringEncoding];
}

- (void) filterReports:(NSArray*) reports
              bodyName:(NSString*) bodyName
       bodyContentType:(NSString*) bodyContentType
          bodyFilename:(NSString*) bodyFilename
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:self.url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15];

    KSHTTPMultipartPostBody* body = [KSHTTPMultipartPostBody body];

    [body appendData:[self toQuincyBody:reports]
                name:bodyName
         contentType:bodyContentType
            filename:bodyFilename];

    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.timeoutInterval = 15;
    request.HTTPMethod = @"POST";
    request.HTTPBody = [body data];
    [request setValue:@"Quincy/iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setValue:body.contentType forHTTPHeaderField:@"Content-type"];

    __unsafe_unretained KSCrashReportSinkQuincy* blockSelf = self;

    KSLOG_TRACE(@"Starting reachable operation to host %@", [self.url host]);
    self.reachableOperation = [KSReachableOperation operationWithHost:[self.url host]
                                                            allowWWAN:YES
                                                                block:^
                               {
                                   KSLOG_TRACE(@"Sending request to %@", request.URL);
                                   [[KSHTTPRequestSender sender] sendRequest:request
                                                                   onSuccess:^(NSHTTPURLResponse* response, NSData* data)
                                    {
                                        KSLOG_DEBUG(@"Post successful");
                                        #pragma unused(response)
                                        onCompletion(reports, YES, nil);
                                        if(blockSelf.onSuccess != nil)
                                        {
                                            KSLOG_TRACE(@"Calling onSuccess");
                                            blockSelf.onSuccess(as_autorelease([[NSString alloc] initWithData:data
                                                                                                     encoding:NSUTF8StringEncoding]));
                                        }
                                    } onFailure:^(NSHTTPURLResponse* response, NSData* data)
                                    {
                                        NSString* text = as_autorelease([[NSString alloc] initWithData:data
                                                                                              encoding:NSUTF8StringEncoding]);
                                        KSLOG_DEBUG(@"Post failed. Code %d", response.statusCode);
                                        KSLOG_TRACE(@"Response text:\n%@", text);
                                        onCompletion(reports, NO, [NSError errorWithDomain:@"KSCrashReportSinkQuincy"
                                                                                      code:response.statusCode
                                                                                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                            text,
                                                                                            NSLocalizedDescriptionKey,
                                                                                            nil]]);
                                    } onError:^(NSError* error)
                                    {
                                        KSLOG_DEBUG(@"Posting error: %@", error);
                                        onCompletion(reports, NO, error);
                                    }];
                               }];
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    [self filterReports:reports
               bodyName:@"xmlstring"
        bodyContentType:nil
           bodyFilename:nil
           onCompletion:onCompletion];
}

@end


@interface KSCrashReportSinkHockey ()

@property(nonatomic,readwrite,retain) NSString* appIdentifier;

- (NSString*) urlEscaped:(NSString*) string;

- (NSURL*) urlWithAppIdentifier:(NSString*) appIdentifier;

@end


@implementation KSCrashReportSinkHockey

@synthesize appIdentifier = _appIdentifier;

+ (KSCrashReportSinkHockey*) sinkWithAppIdentifier:(NSString*) appIdentifier
                                         onSuccess:(void(^)(NSString* response)) onSuccess
{
    return as_autorelease([[self alloc] initWithAppIdentifier:appIdentifier
                                                    onSuccess:onSuccess]);
}

- (id) initWithAppIdentifier:(NSString*) appIdentifier
                   onSuccess:(void(^)(NSString* response)) onSuccess
{
    if(appIdentifier == nil)
    {
        KSLOG_ERROR(@"appIdentifier was nil. Posting to Hockey will fail");
    }
    if((self = [super initWithURL:[self urlWithAppIdentifier:appIdentifier]
                        onSuccess:onSuccess]))
    {
        self.appIdentifier = appIdentifier;
    }
    return self;
}

- (void) dealloc
{
    as_release(_appIdentifier);
    as_superdealloc();
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    [self filterReports:reports
               bodyName:@"xml"
        bodyContentType:@"text/xml"
           bodyFilename:@"crash.xml"
           onCompletion:onCompletion];
}

- (NSURL*) urlWithAppIdentifier:(NSString*) appIdentifier
{
    NSString* urlString = [NSString stringWithFormat:@"https://rink.hockeyapp.net/api/2/apps/%@/crashes",
                           [self urlEscaped:appIdentifier]];
    return [NSURL URLWithString:urlString];
}

- (NSString*) urlEscaped:(NSString*) string
{
    return [string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

@end
