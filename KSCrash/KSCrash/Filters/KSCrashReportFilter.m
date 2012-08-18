//
//  KSCrashReportFilter.m
//  KSCrash
//
//  Created by Karl Stenerud on 5/10/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilter.h"
#import "ARCSafe_MemMgmt.h"


@implementation KSCrashReportFilterPassthrough

+ (KSCrashReportFilterPassthrough*) filter
{
    return as_autorelease([[self alloc] init]);
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    onCompletion(reports, YES, nil);
}

@end


@interface KSCrashReportFilterCombine ()

@property(nonatomic,readwrite,retain) NSArray* filters;
@property(nonatomic,readwrite,retain) NSArray* keys;

- (id) initWithFilters:(NSArray*) filters keys:(NSArray*) keys;

@end


@implementation KSCrashReportFilterCombine

@synthesize filters = _filters;
@synthesize keys = _keys;

- (id) initWithFilters:(NSArray*) filters keys:(NSArray*) keys
{
    if((self = [super init]))
    {
        self.filters = filters;
        self.keys = keys;
    }
    return self;
}

+ (KSCrashReportFilterCombine*) filterWithFiltersAndKeys:(id) firstFilter, ...
{
    NSMutableArray* filters = [NSMutableArray array];
    NSMutableArray* keys = [NSMutableArray array];
    va_list args;
    va_start(args,firstFilter);
    for(id<KSCrashReportFilter> filter = firstFilter;
        filter != nil;
        filter = va_arg(args, id))
    {
        if([filter isKindOfClass:[NSArray class]])
        {
            filter = [KSCrashReportFilterPipeline filterWithFilters:(NSArray*)filter];
        }
        NSAssert([filter conformsToProtocol:@protocol(KSCrashReportFilter)], @"Not a filter");
        NSString* key = va_arg(args, id);
        if(key == nil)
        {
            break;
        }
        [filters addObject:filter];
        [keys addObject:key];
    }
    va_end(args);
    
    return as_autorelease([[self alloc] initWithFilters:filters keys:keys]);
}

- (id) initWithFiltersAndKeys:(id) firstFilter, ...
{
    NSMutableArray* filters = [NSMutableArray array];
    NSMutableArray* keys = [NSMutableArray array];
    va_list args;
    va_start(args,firstFilter);
    for(id<KSCrashReportFilter> filter = firstFilter;
        filter != nil;
        filter = va_arg(args, id))
    {
        if([filter isKindOfClass:[NSArray class]])
        {
            filter = [KSCrashReportFilterPipeline filterWithFilters:(NSArray*)filter];
        }
        NSAssert([filter conformsToProtocol:@protocol(KSCrashReportFilter)], @"Not a filter");
        NSString* key = va_arg(args, id);
        if(key == nil)
        {
            break;
        }
        [filters addObject:filter];
        [keys addObject:key];
    }
    va_end(args);

    return [self initWithFilters:filters keys:keys];
}

- (void) dealloc
{
    as_release(_filters);
    as_release(_keys);
    as_superdealloc();
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSArray* filters = self.filters;
    NSArray* keys = self.keys;
    NSUInteger filterCount = [filters count];
    NSMutableArray* reportSets = [NSMutableArray arrayWithCapacity:filterCount];

    __block NSUInteger iFilter = 0;
    __block KSCrashReportFilterCompletion filterCompletion;
    filterCompletion = [^(NSArray* filteredReports,
                          BOOL completed,
                          NSError* filterError)
    {
        if(completed)
        {
            [reportSets addObject:filteredReports];
            if(++iFilter < filterCount)
            {
                id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
                [filter filterReports:reports onCompletion:filterCompletion];
                return;
            }
        }
        
        NSUInteger reportCount = [(NSArray*)[reportSets objectAtIndex:0] count];
        NSMutableArray* combinedReports = [NSMutableArray arrayWithCapacity:reportCount];
        for(NSUInteger iReport = 0; iReport < reportCount; iReport++)
        {
            NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:filterCount];
            for(NSUInteger iSet = 0; iSet < filterCount; iSet++)
            {
                [dict setObject:[[reportSets objectAtIndex:iSet] objectAtIndex:iReport]
                         forKey:[keys objectAtIndex:iSet]];
            }
            [combinedReports addObject:dict];
        }

        onCompletion(combinedReports, completed, filterError);
        as_release(filterCompletion);
        filterCompletion = nil;
    } copy];
    
    id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}


@end


@interface KSCrashReportFilterPipeline ()

@property(nonatomic,readwrite,retain) NSArray* filters;

@end


@implementation KSCrashReportFilterPipeline

@synthesize filters = _filters;

+ (KSCrashReportFilterPipeline*) filterWithFilters:(NSArray*) filters
{
    return as_autorelease([[self alloc] initWithFilters:filters]);
}

- (id) initWithFilters:(NSArray*) filters
{
    if((self = [super init]))
    {
        self.filters = filters;
    }
    return self;
}

- (void) dealloc
{
    as_release(_filters);
    as_superdealloc();
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSArray* filters = self.filters;
    NSUInteger filterCount = [filters count];
    
    __block NSUInteger iFilter = 0;
    __block KSCrashReportFilterCompletion filterCompletion;
    filterCompletion = [^(NSArray* filteredReports,
                          BOOL completed,
                          NSError* filterError)
    {
        if(completed && ++iFilter < filterCount)
        {
            id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterReports:filteredReports onCompletion:filterCompletion];
            return;
        }

        onCompletion(filteredReports, completed, filterError);
        as_release(filterCompletion);
        filterCompletion = nil;
    } copy];

    id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}

@end
