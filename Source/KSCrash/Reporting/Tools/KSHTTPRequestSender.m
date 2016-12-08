//
//  KSHTTPRequestSender.m
//
//  Created by Karl Stenerud on 2012-02-19.
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


#import "KSHTTPRequestSender.h"
#import "NSError+SimpleConstructor.h"


@implementation KSHTTPRequestSender

+ (KSHTTPRequestSender*) sender
{
    return [[self alloc] init];
}

- (void) handleResponse:(NSURLResponse*) response
                   data:(NSData*) data
                  error:(NSError*) error
              onSuccess:(void(^)(NSHTTPURLResponse* response, NSData* data)) successBlock
              onFailure:(void(^)(NSHTTPURLResponse* response, NSData* data)) failureBlock
                onError:(void(^)(NSError* error)) errorBlock
{
    if(error == nil)
    {
        if(response == nil)
        {
            error = [NSError errorWithDomain:[[self class] description]
                                        code:0
                                 description:@"Response was nil"];
        }
        
        if(![response isKindOfClass:[NSHTTPURLResponse class]])
        {
            error = [NSError errorWithDomain:[[self class] description]
                                        code:0
                                 description:@"Response was of type %@. Expected NSHTTPURLResponse",
                     [response class]];
        }
    }
    
    if(error == nil)
    {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        if((httpResponse.statusCode / 100) != 2)
        {
            if(failureBlock != nil)
            {
                dispatch_async(dispatch_get_main_queue(), ^
                               {
                                   failureBlock(httpResponse, data);
                               });
            }
        }
        else if(successBlock != nil)
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               successBlock(httpResponse, data);
                           });
        }
    }
    else
    {
        if(errorBlock != nil)
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               errorBlock(error);
                           });
        }
    }
}

- (void) sendRequest:(NSURLRequest*) request
           onSuccess:(void(^)(NSHTTPURLResponse* response, NSData* data)) successBlock
           onFailure:(void(^)(NSHTTPURLResponse* response, NSData* data)) failureBlock
             onError:(void(^)(NSError* error)) errorBlock
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 70000
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        @autoreleasepool {
            NSURLResponse* response = nil;
            NSError* error = nil;
            NSData* data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&response
                                                             error:&error];
            [self handleResponse:response data:data error:error onSuccess:successBlock onFailure:failureBlock onError:errorBlock];
        }
    });
#else
    NSURLSession* session = [NSURLSession sharedSession];
    NSURLSessionTask* task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [self handleResponse:response data:data error:error onSuccess:successBlock onFailure:failureBlock onError:errorBlock];
    }];
    [task resume];
#endif
}

@end
