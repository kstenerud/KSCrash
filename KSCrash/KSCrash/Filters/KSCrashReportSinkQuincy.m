//
//  KSCrashReportSinkQuincy.m
//
//  Created by Karl Stenerud on 12-02-26.
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
#import "KSHTTPMultipartPostBody.h"
#import "KSHTTPRequestSender.h"
#import "KSLogger.h"
#import "NSData+GZip.h"
#import "KSCrashReportFilterAppleFmt.h"
#import "KSJSONCodecObjC.h"
#import "KSReachability.h"


#define kFilterKeyStandard @"standard"
#define kFilterKeyApple @"apple"


@interface KSCrashReportFilterQuincy ()

- (NSString*) cdataEscaped:(NSString*) string;

- (NSString*) toQuincyFormat:(NSDictionary*) reportTuple;

- (NSString*) blankForNil:(NSString*) string;

@end


@implementation KSCrashReportFilterQuincy

+ (KSCrashReportFilterQuincy*) filter
{
    return as_autorelease([[self alloc] init]);
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
    NSDictionary* systemDict = [report objectForKey:@"system"];
    NSDictionary* userDict = [report objectForKey:@"user"];
    NSString* userID = [self blankForNil:[userDict valueForKey:@"userID"]];
    NSString* contactEmail = [self blankForNil:[userDict valueForKey:@"contactEmail"]];
    NSString* crashReportDescription = [self blankForNil:[userDict valueForKey:@"crashReportDescription"]];
    
    return [NSString stringWithFormat:
            @"<crash>"
            @"<applicationname>%@</applicationname>"
            @"<bundleidentifier>%@</bundleidentifier>"
            @"<systemversion>%@</systemversion>"
            @"<platform>%@</platform>"
            @"<senderversion>%@</senderversion>"
            @"<version>%@</version>"
            @"<log><![CDATA[%@]]></log>"
            @"<userid>%@</userid>"
            @"<contact>%@</contact>"
            @"<description><![CDATA[%@]]></description>"
            @"</crash>",
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
    return [NSArray arrayWithObjects:
            [KSCrashReportFilterCombine filterWithFiltersAndKeys:
             [KSCrashReportFilterPassthrough filter],
             kFilterKeyStandard,
             [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
             kFilterKeyApple,
             nil],
            [KSCrashReportFilterQuincy filter],
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
    
    self.reachableOperation = [KSReachableOperation operationWithHost:[self.url host]
                                                            allowWWAN:NO
                                                                block:^
    {
        KSLOG_TRACE(@"Posting to %@:\n%@", self.url,
                    as_autorelease([[NSString alloc] initWithData:[body data] encoding:NSUTF8StringEncoding]));
        [[KSHTTPRequestSender sender] sendRequest:request
                                        onSuccess:^(NSHTTPURLResponse* response, NSData* data)
         {
             #pragma unused(response)
             onCompletion(reports, YES, nil);
             if(blockSelf.onSuccess)
             {
                 blockSelf.onSuccess(as_autorelease([[NSString alloc] initWithData:data
                                                                          encoding:NSUTF8StringEncoding]));
             }
         } onFailure:^(NSHTTPURLResponse* response, NSData* data)
         {
             NSString* text = as_autorelease([[NSString alloc] initWithData:data
                                                                   encoding:NSUTF8StringEncoding]);
             onCompletion(reports, NO, [NSError errorWithDomain:@"KSCrashReportSinkQuincy"
                                                           code:response.statusCode
                                                       userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                 text,
                                                                 NSLocalizedDescriptionKey,
                                                                 nil]]);
         } onError:^(NSError* error2)
         {
             onCompletion(reports, NO, error2);
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
