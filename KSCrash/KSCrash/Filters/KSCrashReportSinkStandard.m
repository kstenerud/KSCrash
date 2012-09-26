//
//  KSCrashReportSinkStandard.m
//
//  Created by Karl Stenerud on 12-02-18.
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


#import "KSCrashReportSinkStandard.h"

#import "ARCSafe_MemMgmt.h"
#import "KSHTTPMultipartPostBody.h"
#import "KSHTTPRequestSender.h"
#import "NSData+GZip.h"
#import "KSJSONCodecObjC.h"
#import "KSReachability.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


@interface KSCrashReportSinkStandard ()

@property(nonatomic,readwrite,retain) NSURL* url;

@property(nonatomic,readwrite,copy) void(^onSuccess)(NSString* response);

@property(nonatomic,readwrite,retain) KSReachableOperation* reachableOperation;


@end


@implementation KSCrashReportSinkStandard

@synthesize url = _url;
@synthesize onSuccess = _onSuccess;
@synthesize reachableOperation = _reachableOperation;

+ (KSCrashReportSinkStandard*) sinkWithURL:(NSURL*) url
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
            self,
            nil];
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
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
        onCompletion(reports, NO, error);
        return;
    }
    
    [body appendData:jsonData
                name:@"reports"
         contentType:@"application/json"
            filename:@"reports.json"];
    // TODO: Disabled gzip compression until support is added server side,
    // and I've fixed a bug in appendUTF8String.
//    [body appendUTF8String:@"json"
//                      name:@"encoding"
//               contentType:@"string"
//                  filename:nil];

    request.HTTPMethod = @"POST";
    request.HTTPBody = [body data];
    [request setValue:body.contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"KSCrashReporter" forHTTPHeaderField:@"User-Agent"];
    
//    [request setHTTPBody:[[body data] gzippedWithError:nil]];
//    [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
    
    self.reachableOperation = [KSReachableOperation operationWithHost:[self.url host]
                                                            allowWWAN:YES
                                                                block:^
    {
        [[KSHTTPRequestSender sender] sendRequest:request
                                        onSuccess:^(NSHTTPURLResponse* response, NSData* data)
         {
             #pragma unused(response)
             onCompletion(reports, YES, nil);
             if(self.onSuccess)
             {
                 self.onSuccess(as_autorelease([[NSString alloc] initWithData:data
                                                                     encoding:NSUTF8StringEncoding]));
             }
         } onFailure:^(NSHTTPURLResponse* response, NSData* data)
         {
             NSString* text = as_autorelease([[NSString alloc] initWithData:data
                                                                   encoding:NSUTF8StringEncoding]);
             onCompletion(reports, NO, [NSError errorWithDomain:@"KSCrashReportSinkStandard"
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



@end
