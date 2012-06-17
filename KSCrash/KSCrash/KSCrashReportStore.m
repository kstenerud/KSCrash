//
//  KSCrashReporter.m
//
//  Created by Karl Stenerud on 12-02-05.
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
#import "KSLogger.h"
#import "KSJSONCodecObjC.h"
#import "RFC3339DateTool.h"


/**
 * Metadata class to hold name and creation date for a file, with
 * default comparison based on the creation date (ascending).
 */
@interface KSCrashReportInfo: NSObject

@property(nonatomic,readonly,retain) NSString* name;
@property(nonatomic,readonly,retain) NSDate* creationDate;

+ (KSCrashReportInfo*) reportInfoWithName:(NSString*) name
                             creationDate:(NSDate*) creationDate;

- (id) initWithName:(NSString*) name creationDate:(NSDate*) creationDate;

- (NSComparisonResult) compare:(KSCrashReportInfo*) other;

@end

@implementation KSCrashReportInfo

@synthesize name = _name;
@synthesize creationDate = _creationDate;

+ (KSCrashReportInfo*) reportInfoWithName:(NSString*) name
                             creationDate:(NSDate*) creationDate
{
    return as_autorelease([[self alloc] initWithName:name
                                        creationDate:creationDate]);
}

- (id) initWithName:(NSString*) name creationDate:(NSDate*) creationDate
{
    if((self = [super init]))
    {
        _name = as_retain(name);
        _creationDate = as_retain(creationDate);
    }
    return self;
}

- (void) dealloc
{
    as_release(_name);
    as_release(_creationDate);
    as_superdealloc();
}

- (NSComparisonResult) compare:(KSCrashReportInfo*) other
{
    return [_creationDate compare:other->_creationDate];
}

@end


@interface KSCrashReportStore ()

@property(nonatomic,readwrite,retain) NSString* path;

@property(nonatomic,readwrite,retain) NSString* filenamePrefix;

/** Fix up a raw crash report.
 *
 * @param report The report to fix.
 *
 * @return The cooked crash report.
 */
- (NSDictionary*) fixupCrashReport:(NSDictionary*) report;

- (bool) mergeDictWithKey:(NSString*) srcKey
          intoDictWithKey:(NSString*) dstKey
                 inReport:(NSMutableDictionary*) report;

- (bool) convertTimestamp:(NSString*) key
                 inReport:(NSMutableDictionary*) report;

@end


@implementation KSCrashReportStore

@synthesize path = _path;
@synthesize filenamePrefix = _filenamePrefix;

+ (KSCrashReportStore*) storeWithPath:(NSString*) path
                       filenamePrefix:(NSString*) filenamePrefix
{
    return as_autorelease([[self alloc] initWithPath:path
                                      filenamePrefix:filenamePrefix]);
}

- (id) initWithPath:(NSString*) path
     filenamePrefix:(NSString*) filenamePrefix
{
    if((self = [super init]))
    {
        self.path = path;
        self.filenamePrefix = filenamePrefix;
    }
    return self;
}

- (void) dealloc
{
    as_release(_path);
    as_release(_filenamePrefix);
    as_superdealloc();
}

- (NSArray*) reportNamesUnsorted
{
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* filenames = [fm contentsOfDirectoryAtPath:self.path error:&error];
    if(filenames == nil)
    {
        KSLOG_ERROR(@"Could not get contents of directory %@: %@", self.path, error);
        return nil;
    }
    
    NSMutableArray* reportNames = [NSMutableArray arrayWithCapacity:[filenames count]];
    for(NSString* filename in filenames)
    {
        if([filename rangeOfString:self.filenamePrefix].location != NSNotFound)
        {
            [reportNames addObject:filename];
        }
    }
    
    return reportNames;
}

- (NSArray*) reportNames
{
    NSError* error = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* filenames = [self reportNamesUnsorted];
    if(filenames == nil)
    {
        return nil;
    }
    
    NSMutableArray* reports = [NSMutableArray arrayWithCapacity:[filenames count]];
    for(NSString* filename in filenames)
    {
        NSString* fullPath = [self.path stringByAppendingPathComponent:filename];
        NSDictionary* fileAttribs = [fm attributesOfItemAtPath:fullPath error:&error];
        if(fileAttribs == nil)
        {
            KSLOG_ERROR(@"Could not read file attributes for %@: %@", fullPath, error);
        }
        else
        {
            [reports addObject:[KSCrashReportInfo reportInfoWithName:filename
                                                        creationDate:[fileAttribs valueForKey:NSFileCreationDate]]];
        }
    }
    [reports sortUsingSelector:@selector(compare:)];
    
    NSMutableArray* sortedNames = [NSMutableArray arrayWithCapacity:[reports count]];
    for(KSCrashReportInfo* info in reports)
    {
        [sortedNames addObject:info.name];
    }
    return sortedNames;
}

- (NSDictionary*) reportNamed:(NSString*) name
{
    NSError* error = nil;
    
    NSString* filename = [self.path stringByAppendingPathComponent:name];
    NSData* jsonData = [NSData dataWithContentsOfFile:filename options:0 error:&error];
    if(jsonData == nil)
    {
        KSLOG_ERROR(@"Could not load from %@: %@", filename, error);
        return nil;
    }
    
    NSDictionary* report = (NSDictionary*)[KSJSONCodec decode:jsonData
                                                      options:KSJSONDecodeOptionIgnoreNullInArray |
                                           KSJSONDecodeOptionIgnoreNullInObject
                                                        error:&error];
    if(report == nil)
    {
        KSLOG_ERROR(@"Could not decode JSON data from %@: %@", filename, error);
        return nil;
    }
    if(![report isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"Report should be a dictionary, not %@", [report class]);
        return nil;
    }
    
    return [self fixupCrashReport:report];
}

- (NSArray*) allReports
{
    NSArray* reportNames = [self reportNames];
    NSMutableArray* reports = [NSMutableArray arrayWithCapacity:[reportNames count]];
    for(NSString* name in reportNames)
    {
        NSDictionary* report = [self reportNamed:name];
        if(report != nil)
        {
            [reports addObject:report];
        }
    }

    return reportNames;
}

- (void) deleteReportNamed:(NSString*) name
{
    NSError* error = nil;
    NSString* filename = [self.path stringByAppendingPathComponent:name];
    
    [[NSFileManager defaultManager] removeItemAtPath:filename error:&error];
    if(error != nil)
    {
        KSLOG_ERROR(@"Could not delete file %@: %@", filename, error);
    }
}

- (void) deleteAllReports
{
    for(NSString* name in [self reportNamesUnsorted])
    {
        [self deleteReportNamed:name];
    }
}

- (void) pruneReportsLeaving:(int) numReports
{
    NSArray* reportNames = [self reportNames];
    int deleteCount = (int)[reportNames count] - numReports;
    for(int i = 0; i < deleteCount; i++)
    {
        [self deleteReportNamed:[reportNames objectAtIndex:(NSUInteger)i]];
    }
}

- (NSDictionary*) fixupCrashReport:(NSDictionary*) report
{
    if(![report isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"Report should be a dictionary, not %@", [report class]);
        return nil;
    }
    
    NSMutableDictionary* mutableReport = as_autorelease([report mutableCopy]);
    
    // Timestamp gets stored as a unix timestamp. Convert it to rfc3339.
    if(![self convertTimestamp:@"timestamp" inReport:mutableReport])
    {
        return nil;
    }
    
    if(![self mergeDictWithKey:@"system_atcrash"
               intoDictWithKey:@"system"
                      inReport:mutableReport])
    {
        return nil;
    }
    
    if(![self mergeDictWithKey:@"user_atcrash"
               intoDictWithKey:@"user"
                      inReport:mutableReport])
    {
        return nil;
    }
    
    return mutableReport;
}

- (bool) mergeDictWithKey:(NSString*) srcKey
          intoDictWithKey:(NSString*) dstKey
                 inReport:(NSMutableDictionary*) report
{
    NSDictionary* srcDict = [report objectForKey:srcKey];
    if(srcDict == nil)
    {
        // It's OK if the source dict didn't exist.
        return true;
    }
    
    if(![srcDict isKindOfClass:[NSDictionary class]])
    {
        KSLOG_ERROR(@"'%@' should be a dictionary, not %@", srcKey, [srcDict class]);
        return false;
    }
    
    if([srcDict count] > 0)
    {
        NSDictionary* dstDict = [report objectForKey:dstKey];
        if(dstDict == nil)
        {
            dstDict = [NSDictionary dictionary];
        }
        if(![dstDict isKindOfClass:[NSDictionary class]])
        {
            KSLOG_ERROR(@"'%@' should be a dictionary, not %@", dstKey, [dstDict class]);
            return false;
        }
        NSMutableDictionary* mutableDict = as_autorelease([dstDict mutableCopy]);
        [mutableDict addEntriesFromDictionary:srcDict];
        [report setObject:mutableDict forKey:dstKey];
    }
    [report removeObjectForKey:srcKey];
    return true;
}

- (bool) convertTimestamp:(NSString*) key
                 inReport:(NSMutableDictionary*) report
{
    NSNumber* timestamp = [report objectForKey:key];
    if(timestamp == nil)
    {
        KSLOG_ERROR(@"entry '%@' not found", key);
        return false;
    }
    if(![timestamp isKindOfClass:[NSNumber class]])
    {
        KSLOG_ERROR(@"'%@' should be a numner, not %@", key, [key class]);
        return false;
    }
    [report setValue:[RFC3339DateTool stringFromUNIXTimestamp:[timestamp unsignedLongLongValue]]
              forKey:key];
    return true;
}

@end
