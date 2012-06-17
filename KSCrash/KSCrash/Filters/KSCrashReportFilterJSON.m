//
//  KSCrashReportFilterJSON.m
//  KSCrash
//
//  Created by Karl Stenerud on 5/9/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilterJSON.h"
#import "ARCSafe_MemMgmt.h"
#import "KSLogger.h"


@interface KSCrashReportFilterJSONEncode ()

@property(nonatomic,readwrite,assign) KSJSONEncodeOption encodeOptions;

@end


@implementation KSCrashReportFilterJSONEncode

@synthesize encodeOptions = _encodeOptions;

+ (KSCrashReportFilterJSONEncode*) filterWithOptions:(KSJSONEncodeOption) options
{
    return as_autorelease([(KSCrashReportFilterJSONEncode*)[self alloc] initWithOptions:options]);
}

- (id) initWithOptions:(KSJSONEncodeOption) options
{
    if((self = [super init]))
    {
        self.encodeOptions = options;
    }
    return self;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        NSError* error = nil;
        NSData* jsonData = [KSJSONCodec encode:report
                                       options:self.encodeOptions
                                         error:&error];
        if(jsonData == nil)
        {
            onCompletion(filteredReports, NO, error);
            return;
        }
        else
        {
            [filteredReports addObject:jsonData];
        }
    }
    
    onCompletion(filteredReports, YES, nil);
}

@end


@interface KSCrashReportFilterJSONDecode ()

@property(nonatomic,readwrite,assign) KSJSONDecodeOption decodeOptions;

@end


@implementation KSCrashReportFilterJSONDecode

@synthesize decodeOptions = _encodeOptions;

+ (KSCrashReportFilterJSONDecode*) filterWithOptions:(KSJSONDecodeOption) options
{
    return as_autorelease([(KSCrashReportFilterJSONDecode*)[self alloc] initWithOptions:options]);
}

- (id) initWithOptions:(KSJSONDecodeOption) options
{
    if((self = [super init]))
    {
        self.decodeOptions = options;
    }
    return self;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSData* data in reports)
    {
        NSError* error = nil;
        NSDictionary* report = [KSJSONCodec decode:data
                                           options:self.decodeOptions
                                             error:&error];
        if(report == nil)
        {
            onCompletion(filteredReports, NO, error);
            return;
        }
        else
        {
            [filteredReports addObject:report];
        }
    }
    
    onCompletion(filteredReports, YES, nil);
}

@end
