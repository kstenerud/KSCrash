//
//  KSCrashReportSinkQuincyHockey.m
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


#import "KSCrashReportSinkCustomService.h"
#import "CJSONSerializer.h"
#import "ARCSafe_MemMgmt.h"
#import "KSCrashReportFields.h"
#import "KSHTTPMultipartPostBody.h"
#import "KSHTTPRequestSender.h"
#import "NSData+GZip.h"
#import "KSCrashCallCompletion.h"
#import "KSCrashReportFilterAppleFmt.h"
#import "KSJSONCodecObjC.h"
#import "KSReachabilityKSCrash.h"
#import "Container+DeepSearch.h"
#import "NSError+SimpleConstructor.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


#define kFilterKeyStandard @"standard"
#define kFilterKeyApple @"apple"


@interface KSCrashReportSinkCustomService ()

@property(nonatomic, readwrite, retain) NSString* userIDKey;
@property(nonatomic, readwrite, retain) NSString* contactEmailKey;
@property(nonatomic, readwrite, retain) NSArray* crashDescriptionKeys;
@property(nonatomic,readwrite,retain) NSURL* url;
@property(nonatomic,readwrite,retain) KSReachableOperationKSCrash* reachableOperation;

@end


@implementation KSCrashReportSinkCustomService

@synthesize url = _url;
@synthesize userIDKey = _userIDKey;
@synthesize contactEmailKey = _contactEmailKey;
@synthesize crashDescriptionKeys = _crashDescriptionKeys;
@synthesize reachableOperation = _reachableOperation;
@synthesize waitUntilReachable = _waitUntilReachable;

+ (KSCrashReportSinkCustomService *) sinkWithURL:(NSURL*) url
                               userIDKey:(NSString*) userIDKey
                         contactEmailKey:(NSString*) contactEmailKey
                    crashDescriptionKeys:(NSArray*) crashDescriptionKeys
{
    return as_autorelease([[self alloc] initWithURL:url
                                          userIDKey:userIDKey
                                    contactEmailKey:contactEmailKey
                               crashDescriptionKeys:crashDescriptionKeys]);
}

- (id) initWithURL:(NSURL*) url
         userIDKey:(NSString*) userIDKey
   contactEmailKey:(NSString*) contactEmailKey
crashDescriptionKeys:(NSArray*) crashDescriptionKeys
{
    if((self = [super init]))
    {
        self.url = url;
        self.userIDKey = userIDKey;
        self.contactEmailKey = contactEmailKey;
        self.crashDescriptionKeys = crashDescriptionKeys;
        self.waitUntilReachable = YES;
    }
    return self;
}

- (void) dealloc
{
    as_release(_reachableOperation);
    as_release(_url);
    as_release(_userIDKey);
    as_release(_contactEmailKey);
    as_release(_crashDescriptionKeys);
    as_superdealloc();
}

- (id <KSCrashReportFilter>) defaultCrashReportFilterSet
{
    return [KSCrashReportFilterPipeline filterWithFilters:
            [KSCrashReportFilterCombine filterWithFiltersAndKeys:
             [KSCrashReportFilterPassthrough filter],
             kFilterKeyStandard,
             [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
             kFilterKeyApple,
             nil],
            self,
            nil];
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

- (NSString*) descriptionForReport:(NSDictionary*) report keys:(NSArray*) keys
{
    NSMutableString* str = [NSMutableString string];
    NSUInteger count = [keys count];
    for(NSUInteger i = 0; i < count; i++)
    {
        NSString* stringValue = nil;
        NSString* key = [keys objectAtIndex:i];
        id value = [report objectForKeyPath:key];
        if([value isKindOfClass:[NSString class]])
        {
            stringValue = value;
        }
        else if([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]])
        {
            NSError* error = nil;
            NSData* encoded = [KSJSONCodec encode:value options:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty error:&error];
            if(error != nil)
            {
                KSLOG_ERROR(@"Could not encode report section %@: %@", key, error);
                continue;
            }
            stringValue = as_autorelease([[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]);
        }
        else if(value == nil)
        {
            KSLOG_WARN(@"Report section %@ not found", key);
        }
        else
        {
            KSLOG_ERROR(@"Could not encode report section %@: Don't know how to encode class %@", key, [value class]);
        }
        if(stringValue != nil)
        {
            if(i > 0)
            {
                [str appendString:@"\n\n"];
            }
            [str appendFormat:@"%@:\n", key];
            [str appendString:stringValue];
        }
    }
    return str;
}

- (NSDictionary *) toJSONFormat:(NSDictionary*) reportTuple
{
    NSDictionary* report = [reportTuple objectForKey:kFilterKeyStandard];
    NSString* appleReport = [reportTuple objectForKey:kFilterKeyApple];
    NSDictionary* systemDict = [report objectForKey:@KSCrashField_System];
    NSString* userID = self.userIDKey == nil ? @"NO USER" : [self blankForNil:[report objectForKeyPath:self.userIDKey]];
    NSString* contactEmail = self.contactEmailKey == nil ? @"NO EMAIL" : [self blankForNil:[report objectForKeyPath:self.contactEmailKey]];
    NSString* crashReportDescription = [self.crashDescriptionKeys count] == 0 ? @"NO DESC" : [self descriptionForReport:report keys:self.crashDescriptionKeys];
    
    NSMutableDictionary *crashDict = [[NSMutableDictionary alloc] init];
    
    [crashDict setObject:[systemDict objectForKey:@"CFBundleExecutable"] forKey:@"ApplicationName"];
    [crashDict setObject:[systemDict objectForKey:@"CFBundleIdentifier"] forKey:@"BundleIdentifier"];
    [crashDict setObject:[systemDict objectForKey:@"system_version"] forKey:@"SystemVersion"];
    [crashDict setObject:[systemDict objectForKey:@"machine"] forKey:@"Platform"];
    [crashDict setObject:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] forKey:@"SenderVersion"];
    [crashDict setObject:[systemDict objectForKey:@"CFBundleVersion"] forKey:@"Version"];
    [crashDict setObject:[self cdataEscaped:appleReport] forKey:@"Log"];
    [crashDict setObject:userID forKey:@"UserID"];
    [crashDict setObject:contactEmail forKey:@"Contact"];
    [crashDict setObject:[self cdataEscaped:crashReportDescription] forKey:@"Description"];

    return crashDict;
}

- (NSData*) toJSONBody:(NSArray*) reports
{
    NSMutableArray *arrayReports = [[NSMutableArray alloc] init];
    
    for(NSDictionary* report in reports)
    {
        NSDictionary* formattedReport = [self toJSONFormat:report];
        [arrayReports addObject:formattedReport];
    }
    
    NSError *error = nil;
    
    return [[CJSONSerializer serializer] serializeArray:arrayReports error:&error];
    
}

- (void) filterReports:(NSArray*) reports
              bodyName:(NSString*) bodyName
       bodyContentType:(NSString*) bodyContentType
          bodyFilename:(NSString*) bodyFilename
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(self.url == nil)
    {
        if(onCompletion != nil)
        {
            onCompletion(reports, NO, [NSError errorWithDomain:[[self class] description]
                                                          code:0
                                                   description:@"url was nil"]);
        }
        return;
    }
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:self.url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15];
    
    NSData *dataToSend = [self toJSONBody:reports];
    
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.timeoutInterval = 15;
    request.HTTPMethod = @"POST";
    [request setValue:@"KSCrash/iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-type"];
    [request setValue:[NSString stringWithFormat:@"%d", [dataToSend length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody: dataToSend];
    
    dispatch_block_t sendOperation = ^
    {
        KSLOG_TRACE(@"Sending request to %@", request.URL);
        [[KSHTTPRequestSender sender] sendRequest:request
                                        onSuccess:^(__unused NSHTTPURLResponse* response,
                                                    __unused NSData* data)
         {
             KSLOG_DEBUG(@"Post successful");
             kscrash_i_callCompletion(onCompletion, reports, YES, nil);
         } onFailure:^(NSHTTPURLResponse* response, NSData* data)
         {
             NSString* text = as_autorelease([[NSString alloc] initWithData:data
                                                                   encoding:NSUTF8StringEncoding]);
             KSLOG_DEBUG(@"Post failed. Code %d", response.statusCode);
             KSLOG_TRACE(@"Response text:\n%@", text);
             kscrash_i_callCompletion(onCompletion, reports, NO,
                                      [NSError errorWithDomain:[[self class] description]
                                                          code:response.statusCode
                                                   description:text]);
         } onError:^(NSError* error)
         {
             KSLOG_DEBUG(@"Posting error: %@", error);
             kscrash_i_callCompletion(onCompletion, reports, NO, error);
         }];
    };
    
    if(self.waitUntilReachable)
    {
        KSLOG_TRACE(@"Starting reachable operation to host %@", [self.url host]);
        self.reachableOperation = [KSReachableOperationKSCrash operationWithHost:[self.url host]
                                                                       allowWWAN:YES
                                                                           block:sendOperation];
    }
    else
    {
        sendOperation();
    }
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
