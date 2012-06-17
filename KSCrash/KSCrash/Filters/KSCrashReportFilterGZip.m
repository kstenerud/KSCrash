//
//  KSCrashReportFilterGZip.m
//  KSCrash
//
//  Created by Karl Stenerud on 5/10/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilterGZip.h"
#import "ARCSafe_MemMgmt.h"
#import "NSData+GZip.h"


@interface KSCrashReportFilterGZipCompress ()

@property(nonatomic,readwrite,assign) int compressionLevel;

@end

@implementation KSCrashReportFilterGZipCompress

@synthesize compressionLevel = _compressionLevel;

+ (KSCrashReportFilterGZipCompress*) filterWithCompressionLevel:(int) compressionLevel
{
    return as_autorelease([[self alloc] initWithCompressionLevel:compressionLevel]);
}

- (id) initWithCompressionLevel:(int) compressionLevel
{
    if((self = [super init]))
    {
        self.compressionLevel = compressionLevel;
    }
    return self;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSData* report in reports)
    {
        NSError* error = nil;
        NSData* compressedData = [report gzippedWithCompressionLevel:self.compressionLevel
                                                               error:&error];
        if(compressedData == nil)
        {
            onCompletion(filteredReports, NO, error);
            return;
        }
        else
        {
            [filteredReports addObject:compressedData];
        }
    }
    
    onCompletion(filteredReports, YES, nil);
}

@end


@implementation KSCrashReportFilterGZipDecompress

+ (KSCrashReportFilterGZipDecompress*) filter
{
    return as_autorelease([[self alloc] init]);
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSData* report in reports)
    {
        NSError* error = nil;
        NSData* decompressedData = [report gunzippedWithError:&error];
        if(decompressedData == nil)
        {
            onCompletion(filteredReports, NO, error);
            return;
        }
        else
        {
            [filteredReports addObject:decompressedData];
        }
    }
    
    onCompletion(filteredReports, YES, nil);
}

@end
