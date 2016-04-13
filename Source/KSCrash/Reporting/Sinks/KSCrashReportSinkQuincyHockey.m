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


#import "KSCrashReportSinkQuincyHockey.h"

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
#import <mach/machine.h>
#import "KSSystemInfo.h"
#import "NSString+URLEncode.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


#define kFilterKeyStandard @"standard"
#define kFilterKeyApple @"apple"
#define kQuincyUUIDUserDefault @"QuincyKitAppInstallationUUID"


@interface KSCrashReportSinkQuincy ()

@property(nonatomic, readwrite, retain) NSString* userIDKey;
@property(nonatomic, readwrite, retain) NSString* userNameKey;
@property(nonatomic, readwrite, retain) NSString* contactEmailKey;
@property(nonatomic, readwrite, retain) NSArray* crashDescriptionKeys;
@property(nonatomic,readwrite,retain) NSURL* url;
@property(nonatomic,readwrite,retain) KSReachableOperationKSCrash* reachableOperation;

@end


@implementation KSCrashReportSinkQuincy

@synthesize url = _url;
@synthesize userIDKey = _userIDKey;
@synthesize userNameKey = _userNameKey;
@synthesize contactEmailKey = _contactEmailKey;
@synthesize crashDescriptionKeys = _crashDescriptionKeys;
@synthesize reachableOperation = _reachableOperation;
@synthesize waitUntilReachable = _waitUntilReachable;

+ (KSCrashReportSinkQuincy*) sinkWithURL:(NSURL*) url
                               userIDKey:(NSString*) userIDKey
                             userNameKey:(NSString*) userNameKey
                         contactEmailKey:(NSString*) contactEmailKey
                    crashDescriptionKeys:(NSArray*) crashDescriptionKeys
{
    return [[self alloc] initWithURL:url
                           userIDKey:userIDKey
                         userNameKey:userNameKey
                     contactEmailKey:contactEmailKey
                crashDescriptionKeys:crashDescriptionKeys];
}

- (id) initWithURL:(NSURL*) url
         userIDKey:(NSString*) userIDKey
       userNameKey:(NSString*) userNameKey
   contactEmailKey:(NSString*) contactEmailKey
crashDescriptionKeys:(NSArray*) crashDescriptionKeys
{
    if((self = [super init]))
    {
        self.url = url;
        self.userIDKey = userIDKey;
        self.userNameKey = userNameKey;
        self.contactEmailKey = contactEmailKey;
        self.crashDescriptionKeys = crashDescriptionKeys;
        self.waitUntilReachable = YES;
    }
    return self;
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
            stringValue = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
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

- (NSString*) quincyInstallUUID
{
    static NSString *installUUID = nil;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate,
    ^{
        NSString *priorValue = [[NSUserDefaults standardUserDefaults] stringForKey:kQuincyUUIDUserDefault];
        if (priorValue)
        {
            installUUID = priorValue;
        }
        else
        {
            CFUUIDRef uuidObj = CFUUIDCreate(NULL);
            installUUID = (NSString*) CFBridgingRelease(CFUUIDCreateString(NULL, uuidObj));
            CFRelease(uuidObj);
            [[NSUserDefaults standardUserDefaults] setObject:installUUID forKey:kQuincyUUIDUserDefault];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    });
    
    return installUUID;
}

- (NSString*) quincyArchFromCpuType:(cpu_type_t)cpuType cpuSubType:(cpu_subtype_t)cpuSubType
{
    NSString *arch = @"???";
    
    switch (cpuType)
    {
        case CPU_TYPE_ARM:
            switch (cpuSubType)
            {
                case CPU_SUBTYPE_ARM_V6:
                    arch = @"armv6";
                    break;
                    
                case CPU_SUBTYPE_ARM_V7:
                    arch = @"armv7";
                    break;
                    
                case CPU_SUBTYPE_ARM_V7S:
                    arch = @"armv7s";
                    break;
                    
                default:
                    arch = @"arm-unknown";
                    break;
            }
            break;

#ifdef CPU_TYPE_ARM64
        case CPU_TYPE_ARM64:
            switch (cpuSubType)
            {
                case CPU_SUBTYPE_ARM_ALL:
                    arch = @"arm64";
                    break;

#ifdef CPU_SUBTYPE_ARM_V8
                case CPU_SUBTYPE_ARM_V8:
                    arch = @"arm64";
                    break;
#endif

                default:
                    arch = @"arm64-unknown";
                    break;
            }
            break;
#endif

        case CPU_TYPE_X86:
            arch = @"i386";
            break;
            
        case CPU_TYPE_X86_64:
            arch = @"x86_64";
            break;
            
        case CPU_TYPE_POWERPC:
            arch = @"powerpc";
            break;
    }
    
    return arch;
}

- (NSString*) uuidsFromReport:(NSDictionary*) standardReport
{
    NSMutableString* uuidString = [NSMutableString string];
    NSArray* binaryImages = [standardReport objectForKey:@KSCrashField_BinaryImages];
    if(binaryImages == nil)
    {
        return @"";
    }
    
    NSDictionary* systemInfo = [standardReport objectForKey:@KSCrashField_System];
    NSString* processPath = [systemInfo objectForKey:@KSSystemField_ExecutablePath];
    NSString* appContainerPath = [[processPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    
    for(NSDictionary* image in binaryImages)
    {
        NSString* imagePath = [[image objectForKey:@KSCrashField_Name] stringByStandardizingPath];
        NSString* imageType;
        if(processPath && [imagePath isEqualToString:processPath])
        {
            imageType = @"app";
        }
        else if(appContainerPath && [imagePath hasPrefix:appContainerPath])
        {
            imageType = @"framework";
        }
        else
        {
            // Only include the UUID information for the app binary or frameworks contained in
            // the app.
            continue;
        }
        
        NSString* uuid = [image objectForKey:@KSCrashField_UUID];
        if(uuid == nil)
        {
            uuid = @"???";
        }
        else
        {
            uuid = [[uuid lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        }
        cpu_type_t cpuType = [[image objectForKey:@KSCrashField_CPUType] intValue];
        cpu_subtype_t cpuSubType = [[image objectForKey:@KSCrashField_CPUSubType] intValue];
        NSString* arch = [self quincyArchFromCpuType:cpuType cpuSubType:cpuSubType];
        [uuidString appendFormat:@"<uuid type=\"%@\" arch=\"%@\">%@</uuid>", imageType, arch, uuid];
    }
    
    return uuidString;
}

- (NSString*) toQuincyFormat:(NSDictionary*) reportTuple
{
    NSDictionary* report = [reportTuple objectForKey:kFilterKeyStandard];
    NSString* appleReport = [reportTuple objectForKey:kFilterKeyApple];
    NSDictionary* systemDict = [report objectForKey:@KSCrashField_System];
    NSString* userID = self.userIDKey == nil ? nil : [self blankForNil:[report objectForKeyPath:self.userIDKey]];
    NSString* userName = self.userNameKey == nil ? nil : [self blankForNil:[report objectForKeyPath:self.userNameKey]];
    NSString* contactEmail = self.contactEmailKey == nil ? nil : [self blankForNil:[report objectForKeyPath:self.contactEmailKey]];
    NSString* crashReportDescription = [self.crashDescriptionKeys count] == 0 ? nil : [self descriptionForReport:report keys:self.crashDescriptionKeys];
    NSString* uuids = [self uuidsFromReport:report];
    NSDictionary* reportInfo = [report objectForKey:@KSCrashField_Report];
    
    NSString* result = [NSString stringWithFormat:
                        @"\n    <crash>\n"
                        @"        <applicationname>%@</applicationname>\n"
                        @"        <uuids>\n"
                        @"          %@\n"
                        @"        </uuids>\n"
                        @"        <bundleidentifier>%@</bundleidentifier>\n"
                        @"        <systemversion>%@</systemversion>\n"
                        @"        <platform>%@</platform>\n"
                        @"        <senderversion>%@</senderversion>\n"
                        @"        <version>%@</version>\n"
                        @"        <uuid>%@</uuid>\n"
                        @"        <log><![CDATA[%@]]></log>\n"
                        @"        <userid>%@</userid>\n"
                        @"        <username>%@</username>\n"
                        @"        <contact>%@</contact>\n"
                        @"        <installstring>%@</installstring>\n"
                        @"        <description><![CDATA[%@]]></description>\n"
                        @"    </crash>",
                        [systemDict objectForKey:@"CFBundleExecutable"],
                        uuids,
                        [systemDict objectForKey:@"CFBundleIdentifier"],
                        [systemDict objectForKey:@"system_version"],
                        [systemDict objectForKey:@"machine"],
                        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                        [systemDict objectForKey:@"CFBundleVersion"],
                        [reportInfo objectForKey:@KSCrashField_ID],
                        [self cdataEscaped:appleReport],
                        userID,
                        userName,
                        contactEmail,
                        [self quincyInstallUUID],
                        [self cdataEscaped:crashReportDescription]];
    return result;
}

- (NSData*) toQuincyBody:(NSArray*) reports
{
    NSMutableString* xmlString = [NSMutableString stringWithString:@"<crashes>"];

    for(NSDictionary* report in reports)
    {
        NSString* reportString = [self toQuincyFormat:report];
        [xmlString appendString:reportString];
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
             NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
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


@interface KSCrashReportSinkHockey ()

@property(nonatomic,readwrite,retain) NSString* appIdentifier;

@end


@implementation KSCrashReportSinkHockey

@synthesize appIdentifier = _appIdentifier;

+ (KSCrashReportSinkHockey*) sinkWithAppIdentifier:(NSString*) appIdentifier
                                         userIDKey:(NSString*) userIDKey
                                       userNameKey:(NSString*) userNameKey
                                   contactEmailKey:(NSString*) contactEmailKey
                              crashDescriptionKeys:(NSArray*) crashDescriptionKeys
{
    return [[self alloc] initWithAppIdentifier:appIdentifier
                                     userIDKey:userIDKey
                                   userNameKey:userNameKey
                               contactEmailKey:contactEmailKey
                          crashDescriptionKeys:crashDescriptionKeys];
}

- (id) initWithAppIdentifier:(NSString*) appIdentifier
                   userIDKey:(NSString*) userIDKey
                 userNameKey:(NSString*) userNameKey
             contactEmailKey:(NSString*) contactEmailKey
        crashDescriptionKeys:(NSArray*) crashDescriptionKeys
{
    if((self = [super initWithURL:[self urlWithAppIdentifier:appIdentifier]
                        userIDKey:userIDKey
                      userNameKey:userNameKey
                  contactEmailKey:contactEmailKey
             crashDescriptionKeys:crashDescriptionKeys]))
    {
        self.appIdentifier = appIdentifier;
    }
    return self;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(self.appIdentifier == nil)
    {
        if(onCompletion != nil)
        {
            onCompletion(reports, NO, [NSError errorWithDomain:[[self class] description]
                                                          code:0
                                                   description:@"appIdentifier was nil"]);
        }
        return;
    }

    [self filterReports:reports
               bodyName:@"xml"
        bodyContentType:@"text/xml"
           bodyFilename:@"crash.xml"
           onCompletion:onCompletion];
}

- (NSURL*) urlWithAppIdentifier:(NSString*) appIdentifier
{
    NSString* urlString = [NSString stringWithFormat:@"https://sdk.hockeyapp.net/api/2/apps/%@/crashes",
                           [appIdentifier URLEncoded]];
    return [NSURL URLWithString:urlString];
}

@end
