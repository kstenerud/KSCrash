//
//  KSCrashReportFilter.m
//  KSCrash
//
//  Created by Karl Stenerud on 5/10/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilter.h"
#import "ARCSafe_MemMgmt.h"
#import "KSSafeCollections.h"
#import "KSVarArgs.h"


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

+ (KSVA_Block) argBlockWithFilters:(NSMutableArray*) filters andKeys:(NSMutableArray*) keys
{
    __block BOOL isKey = FALSE;
    KSVA_Block block = ^(id entry)
    {
        if(isKey)
        {
            [keys addObject:entry];
        }
        else
        {
            if([entry isKindOfClass:[NSArray class]])
            {
                entry = [KSCrashReportFilterPipeline filterWithFilters:entry, nil];
            }
            NSAssert([entry conformsToProtocol:@protocol(KSCrashReportFilter)], @"Not a filter");
            [filters addObject:entry];
        }
        isKey = !isKey;
    };
    return as_autorelease([block copy]);
}

+ (KSCrashReportFilterCombine*) filterWithFiltersAndKeys:(id) firstFilter, ...
{
    NSMutableArray* filters = [NSMutableArray array];
    NSMutableArray* keys = [NSMutableArray array];
    ksva_iterate_list(firstFilter, [self argBlockWithFilters:filters andKeys:keys]);
    return as_autorelease([[self alloc] initWithFilters:filters keys:keys]);
}

- (id) initWithFiltersAndKeys:(id) firstFilter, ...
{
    NSMutableArray* filters = [NSMutableArray array];
    NSMutableArray* keys = [NSMutableArray array];
    ksva_iterate_list(firstFilter, [[self class] argBlockWithFilters:filters andKeys:keys]);
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

+ (KSCrashReportFilterPipeline*) filterWithFilters:(id) firstFilter, ...
{
    ksva_list_to_nsarray(firstFilter, filters);
    return as_autorelease([[self alloc] initWithFiltersArray:filters]);
}

- (id) initWithFilters:(id) firstFilter, ...
{
    ksva_list_to_nsarray(firstFilter, filters);
    return [self initWithFiltersArray:filters];
}

- (id) initWithFiltersArray:(NSArray*) filters
{
    if((self = [super init]))
    {
        NSMutableArray* expandedFilters = [NSMutableArray array];
        for(id<KSCrashReportFilter> filter in filters)
        {
            if([filter isKindOfClass:[NSArray class]])
            {
                [expandedFilters addObjectsFromArray:(NSArray*)filter];
            }
            else
            {
                [expandedFilters addObject:filter];
            }
        }
        self.filters = expandedFilters;
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


@interface KSCrashReportFilterConcatenate ()

@property(nonatomic, readwrite, retain) NSString* separatorFmt;
@property(nonatomic, readwrite, retain) NSArray* keys;

@end

@implementation KSCrashReportFilterConcatenate

@synthesize separatorFmt = _separatorFmt;
@synthesize keys = _keys;

+ (KSCrashReportFilterConcatenate*) filterWithSeparatorFmt:(NSString*) separatorFmt keys:(id) firstKey, ...
{
    ksva_list_to_nsarray(firstKey, keys);
    return as_autorelease([[self alloc] initWithSeparatorFmt:separatorFmt keysArray:keys]);
}

- (id) initWithSeparatorFmt:(NSString*) separatorFmt keys:(id) firstKey, ...
{
    ksva_list_to_nsarray(firstKey, keys);
    return [self initWithSeparatorFmt:separatorFmt keysArray:keys];
}

- (id) initWithSeparatorFmt:(NSString*) separatorFmt keysArray:(NSArray*) keys
{
    if((self = [super init]))
    {
        NSMutableArray* realKeys = [NSMutableArray array];
        for(id key in keys)
        {
            if([key isKindOfClass:[NSArray class]])
            {
                [realKeys addObjectsFromArray:(NSArray*)key];
            }
            else
            {
                [realKeys addObject:key];
            }
        }

        self.separatorFmt = separatorFmt;
        self.keys = realKeys;
    }
    return self;
}

- (void) dealloc
{
    as_release(_separatorFmt);
    as_release(_keys);
    as_superdealloc();
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        NSMutableString* concatenated = [NSMutableString string];
        for(NSString* key in self.keys)
        {
            [concatenated appendFormat:self.separatorFmt, key];
            [concatenated appendString:[report valueForKey:key]];
        }
        [filteredReports addObject:concatenated];
    }
    onCompletion(filteredReports, YES, nil);
}

@end


@interface KSCrashReportFilterSubset ()

@property(nonatomic, readwrite, retain) NSArray* keys;

@end

@implementation KSCrashReportFilterSubset

@synthesize keys = _keys;

+ (KSCrashReportFilterSubset*) filterWithKeys:(id) firstKey, ...
{
    ksva_list_to_nsarray(firstKey, keys);
    return as_autorelease([[self alloc] initWithKeysArray:keys]);
}

- (id) initWithKeys:(id) firstKey, ...
{
    ksva_list_to_nsarray(firstKey, keys);
    return [self initWithKeysArray:keys];
}

- (id) initWithKeysArray:(NSArray*) keys
{
    if((self = [super init]))
    {
        NSMutableArray* realKeys = [NSMutableArray array];
        for(id key in keys)
        {
            if([key isKindOfClass:[NSArray class]])
            {
                [realKeys addObjectsFromArray:(NSArray*)key];
            }
            else
            {
                [realKeys addObject:key];
            }
        }

        self.keys = realKeys;
    }
    return self;
}

- (void) dealloc
{
    as_release(_keys);
    as_superdealloc();
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        NSMutableDictionary* subset = [NSMutableDictionary dictionary];
        for(NSString* key in self.keys)
        {
            [subset safeSetObject:[report objectForKey:key] forKey:key];
        }
        [filteredReports addObject:subset];
    }
    onCompletion(filteredReports, YES, nil);
}

@end
