//
//  KSCrashReportSinkVictory.m
//
//  Created by Kelp on 2013-03-14.
//
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
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

#import "KSSystemCapabilities.h"

#if KSCRASH_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif
#import "KSCrashReportSinkVictory.h"

#import "KSCrashCallCompletion.h"
#import "KSHTTPMultipartPostBody.h"
#import "KSHTTPRequestSender.h"
#import "NSData+GZip.h"
#import "KSJSONCodecObjC.h"
#import "KSReachabilityKSCrash.h"
#import "NSError+SimpleConstructor.h"
#import "KSSystemCapabilities.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


@interface KSCrashReportSinkVictory ()

@property(nonatomic,readwrite,retain) NSURL* url;
@property(nonatomic,readwrite,retain) NSString* userName;
@property(nonatomic,readwrite,retain) NSString* userEmail;

@property(nonatomic,readwrite,retain) KSReachableOperationKSCrash* reachableOperation;


@end


@implementation KSCrashReportSinkVictory

@synthesize url = _url;
@synthesize userName = _userName;
@synthesize userEmail = _userEmail;
@synthesize reachableOperation = _reachableOperation;

+ (KSCrashReportSinkVictory*) sinkWithURL:(NSURL*) url
                                   userName:(NSString*) userName
                                  userEmail:(NSString*) userEmail
{
    return [[self alloc] initWithURL:url userName:userName userEmail:userEmail];
}

- (id) initWithURL:(NSURL*) url
          userName:(NSString*) userName
         userEmail:(NSString*) userEmail
{
    if((self = [super init]))
    {
        self.url = url;
        if (userName == nil || [userName length] == 0) {
#if KSCRASH_HAS_UIDEVICE
            self.userName = UIDevice.currentDevice.name;
#else
            self.userName = @"unknown";
#endif
        }
        else {
            self.userName = userName;
        }
        self.userEmail = userEmail;
    }
    return self;
}

- (id <KSCrashReportFilter>) defaultCrashReportFilterSet
{
    return self;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    // update user information in reports with KVC
    for (NSDictionary *report in reports) {
        NSDictionary *userDict = [report objectForKey:@"user"];
        if (userDict) {
            // user member is exist
            [userDict setValue:self.userName forKey:@"name"];
            [userDict setValue:self.userEmail forKey:@"email"];
        }
        else {
            // no user member, append user dictionary
            [report setValue:@{@"name": self.userName, @"email": self.userEmail} forKey:@"user"];
        }
    }
    
    NSError* error = nil;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:self.url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15];
    KSHTTPMultipartPostBody* body = [KSHTTPMultipartPostBody body];
    NSData* jsonData = [KSJSONCodec encode:reports
                                   options:KSJSONEncodeOptionSorted
                                     error:&error];
    if(jsonData == nil)
    {
        kscrash_i_callCompletion(onCompletion, reports, NO, error);
        return;
    }
    
    [body appendData:jsonData
                name:@"reports"
         contentType:@"application/json"
            filename:@"reports.json"];

    // POST http request
    // Content-Type: multipart/form-data; boundary=xxx
    // Content-Encoding: gzip
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[body data] gzippedWithCompressionLevel:-1 error:nil];
    [request setValue:body.contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
    [request setValue:@"KSCrashReporter" forHTTPHeaderField:@"User-Agent"];

    self.reachableOperation = [KSReachableOperationKSCrash operationWithHost:[self.url host]
                                                                   allowWWAN:YES
                                                                       block:^
    {
        [[KSHTTPRequestSender sender] sendRequest:request
                                        onSuccess:^(__unused NSHTTPURLResponse* response, __unused NSData* data)
         {
             kscrash_i_callCompletion(onCompletion, reports, YES, nil);
         } onFailure:^(NSHTTPURLResponse* response, NSData* data)
         {
             NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
             kscrash_i_callCompletion(onCompletion, reports, NO,
                                      [NSError errorWithDomain:[[self class] description]
                                                          code:response.statusCode
                                                   description:text]);
         } onError:^(NSError* error2)
         {
             kscrash_i_callCompletion(onCompletion, reports, NO, error2);
         }];
    }];
}

@end
