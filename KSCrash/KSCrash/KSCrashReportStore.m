//
//  KSCrashReportStore.m
//
//  Created by Karl Stenerud on 2012-02-05.
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


#import "KSCrashReportStore.h"

#import "ARCSafe_MemMgmt.h"
#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"
#import "NSDictionary+Merge.h"
#import "RFC3339DateTool.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


// ============================================================================
#pragma mark - Constants -
// ============================================================================

#define kCrashReportPrimarySuffix @"-CrashReport-"
#define kCrashReportSecondarySuffix @"-SecondaryCrashReport-"


// ============================================================================
#pragma mark - Meta Data -
// ============================================================================

/**
 * Metadata class to hold name and creation date for a file, with
 * default comparison based on the creation date (ascending).
 */
@interface KSCrashReportInfo: NSObject

@property(nonatomic,readonly,retain) NSString* reportID;
@property(nonatomic,readonly,retain) NSDate* creationDate;

+ (KSCrashReportInfo*) reportInfoWithID:(NSString*) reportID
                           creationDate:(NSDate*) creationDate;

- (id) initWithID:(NSString*) reportID creationDate:(NSDate*) creationDate;

- (NSComparisonResult) compare:(KSCrashReportInfo*) other;

@end

@implementation KSCrashReportInfo

@synthesize reportID = _reportID;
@synthesize creationDate = _creationDate;

+ (KSCrashReportInfo*) reportInfoWithID:(NSString*) reportID
                           creationDate:(NSDate*) creationDate
{
    return as_autorelease([[self alloc] initWithID:reportID
                                      creationDate:creationDate]);
}

- (id) initWithID:(NSString*) reportID creationDate:(NSDate*) creationDate
{
    if((self = [super init]))
    {
        _reportID = as_retain(reportID);
        _creationDate = as_retain(creationDate);
    }
    return self;
}

- (void) dealloc
{
    as_release(_reportID);
    as_release(_creationDate);
    as_superdealloc();
}

- (NSComparisonResult) compare:(KSCrashReportInfo*) other
{
    return [_creationDate compare:other->_creationDate];
}

@end


// ============================================================================
#pragma mark - Main Class -
// ============================================================================

@interface KSCrashReportStore ()

@property(nonatomic,readwrite,retain) NSString* path;
@property(nonatomic,readwrite,retain) NSString* bundleName;

@end


@implementation KSCrashReportStore

#pragma mark Properties

@synthesize path = _path;
@synthesize bundleName = _bundleName;


#pragma mark Construction

+ (KSCrashReportStore*) storeWithPath:(NSString*) path
{
    return as_autorelease([[self alloc] initWithPath:path]);
}

- (id) initWithPath:(NSString*) path
{
    if((self = [super init]))
    {
        self.path = path;
        self.bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
    }
    return self;
}

- (void) dealloc
{
    as_release(_path);
    as_release(_bundleName);
    as_superdealloc();
}

#pragma mark API

- (NSArray*) reportIDs
{
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* filenames = [fm contentsOfDirectoryAtPath:self.path error:&error];
    if(filenames == nil)
    {
        KSLOG_ERROR(@"Could not get contents of directory %@: %@", self.path, error);
        return nil;
    }

    NSMutableArray* reports = [NSMutableArray arrayWithCapacity:[filenames count]];
    for(NSString* filename in filenames)
    {
        NSString* reportId = [self reportIDFromFilename:filename];
        if(reportId != nil)
        {
            NSString* fullPath = [self.path stringByAppendingPathComponent:filename];
            NSDictionary* fileAttribs = [fm attributesOfItemAtPath:fullPath error:&error];
            if(fileAttribs == nil)
            {
                KSLOG_ERROR(@"Could not read file attributes for %@: %@", fullPath, error);
            }
            else
            {
                [reports addObject:[KSCrashReportInfo reportInfoWithID:reportId
                                                          creationDate:[fileAttribs valueForKey:NSFileCreationDate]]];
            }
        }
    }
    [reports sortUsingSelector:@selector(compare:)];

    NSMutableArray* sortedIDs = [NSMutableArray arrayWithCapacity:[reports count]];
    for(KSCrashReportInfo* info in reports)
    {
        [sortedIDs addObject:info.reportID];
    }
    return sortedIDs;
}

- (NSUInteger) reportCount
{
    return [[self reportIDs] count];
}

- (NSDictionary*) reportWithID:(NSString*) reportID
{
    NSError* error = nil;

    NSDictionary* report = [self readReport:[self pathToPrimaryReportWithID:reportID]
                                      error:&error];
    if(error != nil)
    {
        if(report == nil)
        {
            report = [NSDictionary dictionary];
        }
        NSMutableDictionary* primaryReport = as_autorelease([report mutableCopy]);
        [primaryReport setObject:[NSNumber numberWithBool:YES] forKey:@KSCrashField_Incomplete];
        NSMutableDictionary* secondaryReport = as_autorelease([[self readReport:[self pathToSecondaryReportWithID:reportID]
                                                                          error:&error] mutableCopy]);
        if(secondaryReport == nil)
        {
            report = primaryReport;
        }
        else
        {
            if(error != nil)
            {
                [secondaryReport setObject:[NSNumber numberWithBool:YES] forKey:@KSCrashField_Incomplete];
            }
            [secondaryReport setObject:[self fixupCrashReport:primaryReport]
                                forKey:@KSCrashField_OriginalReport];
            report = secondaryReport;
        }
    }

    return [self fixupCrashReport:report];
}

- (NSArray*) allReports
{
    NSArray* reportIDs = [self reportIDs];
    NSMutableArray* reports = [NSMutableArray arrayWithCapacity:[reportIDs count]];
    for(NSString* reportID in reportIDs)
    {
        NSDictionary* report = [self reportWithID:reportID];
        if(report != nil)
        {
            [reports addObject:report];
        }
    }

    return reports;
}

- (void) deleteReportWithID:(NSString*) reportID
{
    NSError* error = nil;
    NSString* filename = [self pathToPrimaryReportWithID:reportID];

    [[NSFileManager defaultManager] removeItemAtPath:filename error:&error];
    if(error != nil)
    {
        KSLOG_ERROR(@"Could not delete file %@: %@", filename, error);
    }

    // Don't care if this succeeds or not since it may not exist.
    [[NSFileManager defaultManager] removeItemAtPath:[self pathToSecondaryReportWithID:reportID]
                                               error:&error];
}

- (void) deleteAllReports
{
    for(NSString* reportID in [self reportIDs])
    {
        [self deleteReportWithID:reportID];
    }
}

- (void) pruneReportsLeaving:(int) numReports
{
    NSArray* reportIDs = [self reportIDs];
    int deleteCount = (int)[reportIDs count] - numReports;
    for(int i = 0; i < deleteCount; i++)
    {
        [self deleteReportWithID:[reportIDs objectAtIndex:(NSUInteger)i]];
    }
}


#pragma mark Utility

- (NSDictionary*) fixupCrashReport:(NSDictionary*) report
{
    if(![report isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"Report should be a dictionary, not %@", [report class]);
        return report;
    }

    NSMutableDictionary* mutableReport = as_autorelease([report mutableCopy]);
    NSMutableDictionary* mutableInfo = as_autorelease([[report objectForKey:@KSCrashField_Report] mutableCopy]);
    [mutableReport setObject:mutableInfo forKey:@KSCrashField_Report];

    // Timestamp gets stored as a unix timestamp. Convert it to rfc3339.
    [self convertTimestamp:@KSCrashField_Timestamp inReport:mutableInfo];

    [self mergeDictWithKey:@KSCrashField_SystemAtCrash
           intoDictWithKey:@KSCrashField_System
                  inReport:mutableReport];

    [self mergeDictWithKey:@KSCrashField_UserAtCrash
           intoDictWithKey:@KSCrashField_User
                  inReport:mutableReport];

    return mutableReport;
}

- (void) mergeDictWithKey:(NSString*) srcKey
          intoDictWithKey:(NSString*) dstKey
                 inReport:(NSMutableDictionary*) report
{
    NSDictionary* srcDict = [report objectForKey:srcKey];
    if(srcDict == nil)
    {
        // It's OK if the source dict didn't exist.
        return;
    }
    if(![srcDict isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"'%@' should be a dictionary, not %@", srcKey, [srcDict class]);
        return;
    }

    NSDictionary* dstDict = [report objectForKey:dstKey];
    if(dstDict == nil)
    {
        dstDict = [NSDictionary dictionary];
    }
    if(![dstDict isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"'%@' should be a dictionary, not %@", dstKey, [dstDict class]);
        return;
    }

    [report setObject:[srcDict mergedInto:dstDict] forKey:dstKey];
    [report removeObjectForKey:srcKey];
}

- (void) convertTimestamp:(NSString*) key
                 inReport:(NSMutableDictionary*) report
{
    NSNumber* timestamp = [report objectForKey:key];
    if(timestamp == nil)
    {
        KSLOG_ERROR(@"entry '%@' not found", key);
        return;
    }
    if(![timestamp isKindOfClass:[NSNumber class]])
    {
        KSLOG_ERROR(@"'%@' should be a number, not %@", key, [key class]);
        return;
    }
    [report setValue:[RFC3339DateTool stringFromUNIXTimestamp:[timestamp unsignedLongLongValue]]
              forKey:key];
}

- (NSString*) primaryReportFilenameWithID:(NSString*) reportID
{
    return [NSString stringWithFormat:@"%@" kCrashReportPrimarySuffix "%@.json",
            self.bundleName, reportID];
}

- (NSString*) secondaryReportFilenameWithID:(NSString*) reportID
{
    return [NSString stringWithFormat:@"%@" kCrashReportSecondarySuffix "%@.json",
            self.bundleName, reportID];
}

- (NSString*) reportIDFromFilename:(NSString*) filename
{
    NSString* prefix = [NSString stringWithFormat:@"%@" kCrashReportPrimarySuffix,
                        self.bundleName];
    NSString* suffix = @".json";
    if([filename rangeOfString:prefix].location == 0 &&
       [filename rangeOfString:suffix].location != NSNotFound)
    {
        NSUInteger prefixLength = [prefix length];
        NSUInteger suffixLength = [suffix length];
        NSRange range = NSMakeRange(prefixLength, [filename length] - prefixLength - suffixLength);
        return [filename substringWithRange:range];
    }
    return nil;
}

- (NSString*) pathToPrimaryReportWithID:(NSString*) reportID
{
    NSString* filename = [self primaryReportFilenameWithID:reportID];
    return [self.path stringByAppendingPathComponent:filename];
}

- (NSString*) pathToSecondaryReportWithID:(NSString*) reportID
{
    NSString* filename = [self secondaryReportFilenameWithID:reportID];
    return [self.path stringByAppendingPathComponent:filename];
}

- (NSDictionary*) readReport:(NSString*) path error:(NSError**) error
{
    NSData* jsonData = [NSData dataWithContentsOfFile:path options:0 error:error];
    if(jsonData == nil)
    {
        KSLOG_ERROR(@"Could not load from %@: %@", path, *error);
        return nil;
    }

    NSDictionary* report = (NSDictionary*)[KSJSONCodec decode:jsonData
                                                      options:KSJSONDecodeOptionIgnoreNullInArray |
                                           KSJSONDecodeOptionIgnoreNullInObject |
                                           KSJSONDecodeOptionKeepPartialObject
                                                        error:error];
    if(*error != nil)
    {
        KSLOG_ERROR(@"Error decoding JSON data from %@: %@", path, *error);
    }
    if(![report isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"Report should be a dictionary, not %@", [report class]);
        return nil;
    }

    return report;
}

@end
