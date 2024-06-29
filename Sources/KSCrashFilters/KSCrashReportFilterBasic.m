//
//  KSCrashReportFilterBasic.m
//
//  Created by Karl Stenerud on 2012-05-11.
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

#import "KSCrashReportFilterBasic.h"
#import "KSCrashReport.h"
#import "KSNSDictionaryHelper.h"
#import "KSNSErrorHelper.h"
#import "KSVarArgs.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@implementation KSCrashReportFilterPassthrough

+ (instancetype)filter
{
    return [[self alloc] init];
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    kscrash_callCompletion(onCompletion, reports, YES, nil);
}

@end

@interface KSCrashReportFilterCombine ()

@property(nonatomic, readwrite, retain) NSArray *filters;
@property(nonatomic, readwrite, retain) NSArray *keys;

@end

@implementation KSCrashReportFilterCombine

@synthesize filters = _filters;
@synthesize keys = _keys;

- (instancetype)initWithFilters:(NSArray *)filters keys:(NSArray<NSString *> *)keys
{
    if ((self = [super init])) {
        self.filters = filters;
        self.keys = keys;
    }
    return self;
}

+ (KSVA_Block)argBlockWithFilters:(NSMutableArray *)filters andKeys:(NSMutableArray *)keys
{
    __block BOOL isKey = FALSE;
    KSVA_Block block = ^(id entry) {
        if (isKey) {
            if (entry == nil) {
                KSLOG_ERROR(@"key entry was nil");
            } else {
                [keys addObject:entry];
            }
        } else {
            if ([entry isKindOfClass:[NSArray class]]) {
                entry = [KSCrashReportFilterPipeline filterWithFilters:entry, nil];
            }
            if (![entry conformsToProtocol:@protocol(KSCrashReportFilter)]) {
                KSLOG_ERROR(@"Not a filter: %@", entry);
                // Cause next key entry to fail as well.
                return;
            } else {
                [filters addObject:entry];
            }
        }
        isKey = !isKey;
    };
    return [block copy];
}

+ (instancetype)filterWithFiltersAndKeys:(id)firstFilter, ...
{
    NSMutableArray *filters = [NSMutableArray array];
    NSMutableArray *keys = [NSMutableArray array];
    ksva_iterate_list(firstFilter, [self argBlockWithFilters:filters andKeys:keys]);
    return [[self class] filterWithFilters:filters keys:keys];
}

+ (instancetype)filterWithFilters:(NSArray *)filters keys:(NSArray<NSString *> *)keys
{
    return [[self alloc] initWithFilters:filters keys:keys];
}

- (instancetype)initWithFiltersAndKeys:(id)firstFilter, ...
{
    NSMutableArray *filters = [NSMutableArray array];
    NSMutableArray *keys = [NSMutableArray array];
    ksva_iterate_list(firstFilter, [[self class] argBlockWithFilters:filters andKeys:keys]);
    return [self initWithFilters:filters keys:keys];
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray *filters = self.filters;
    NSArray *keys = self.keys;
    NSUInteger filterCount = [filters count];

    if (filterCount == 0) {
        kscrash_callCompletion(onCompletion, reports, YES, nil);
        return;
    }

    if (filterCount != [keys count]) {
        kscrash_callCompletion(
            onCompletion, reports, NO,
            [KSNSErrorHelper errorWithDomain:[[self class] description]
                                        code:0
                                 description:@"Key/filter mismatch (%d keys, %d filters", [keys count], filterCount]);
        return;
    }

    NSMutableArray *reportSets = [NSMutableArray arrayWithCapacity:filterCount];

    __block NSUInteger iFilter = 0;
    __block KSCrashReportFilterCompletion filterCompletion = nil;
    __block __weak KSCrashReportFilterCompletion weakFilterCompletion = nil;
    dispatch_block_t disposeOfCompletion = [^{
        // Release self-reference on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            filterCompletion = nil;
        });
    } copy];
    filterCompletion = [^(NSArray<KSCrashReport *> *filteredReports, BOOL completed, NSError *filterError) {
        if (!completed || filteredReports == nil) {
            if (!completed) {
                kscrash_callCompletion(onCompletion, filteredReports, completed, filterError);
            } else if (filteredReports == nil) {
                kscrash_callCompletion(onCompletion, filteredReports, NO,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"filteredReports was nil"]);
            }
            disposeOfCompletion();
            return;
        }

        // Normal run until all filters exhausted.
        [reportSets addObject:filteredReports];
        if (++iFilter < filterCount) {
            id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterReports:reports onCompletion:weakFilterCompletion];
            return;
        }

        // All filters complete, or a filter failed.
        // Build final "filteredReports" array.
        NSUInteger reportCount = [(NSArray *)[reportSets objectAtIndex:0] count];
        NSMutableArray<KSCrashReport *> *combinedReports = [NSMutableArray arrayWithCapacity:reportCount];
        for (NSUInteger iReport = 0; iReport < reportCount; iReport++) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:filterCount];
            for (NSUInteger iSet = 0; iSet < filterCount; iSet++) {
                NSString *key = keys[iSet];
                NSArray *reportSet = reportSets[iSet];
                if (iReport < reportSet.count) {
                    KSCrashReport *report = reportSet[iReport];
                    dict[key] = report.dictionaryValue ?: report.stringValue ?: report.dataValue;
                }
            }
            KSCrashReport *report = [KSCrashReport reportWithDictionary:dict];
            [combinedReports addObject:report];
        }

        kscrash_callCompletion(onCompletion, combinedReports, completed, filterError);
        disposeOfCompletion();
    } copy];
    weakFilterCompletion = filterCompletion;

    // Initial call with first filter to start everything going.
    id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}

@end

@interface KSCrashReportFilterPipeline ()

@property(nonatomic, readwrite, copy) NSArray<id<KSCrashReportFilter>> *filters;

@end

@implementation KSCrashReportFilterPipeline

@synthesize filters = _filters;

+ (instancetype)filterWithFilters:(id)firstFilter, ...
{
    ksva_list_to_nsarray(firstFilter, filters);
    return [[self class] filterWithFiltersArray:filters];
}

+ (instancetype)filterWithFiltersArray:(NSArray *)filters
{
    return [[self alloc] initWithFiltersArray:filters];
}

- (instancetype)initWithFilters:(id)firstFilter, ...
{
    ksva_list_to_nsarray(firstFilter, filters);
    return [self initWithFiltersArray:filters];
}

- (instancetype)initWithFiltersArray:(NSArray *)filters
{
    if ((self = [super init])) {
        NSMutableArray *expandedFilters = [NSMutableArray array];
        for (id<KSCrashReportFilter> filter in filters) {
            if ([filter isKindOfClass:[NSArray class]]) {
                [expandedFilters addObjectsFromArray:(NSArray *)filter];
            } else {
                [expandedFilters addObject:filter];
            }
        }
        _filters = [expandedFilters copy];
    }
    return self;
}

- (void)addFilter:(id<KSCrashReportFilter>)filter
{
    self.filters = [@[ filter ] arrayByAddingObjectsFromArray:self.filters];
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray *filters = self.filters;
    NSUInteger filterCount = [filters count];

    if (filterCount == 0) {
        kscrash_callCompletion(onCompletion, reports, YES, nil);
        return;
    }

    __block NSUInteger iFilter = 0;
    __block KSCrashReportFilterCompletion filterCompletion;
    __block __weak KSCrashReportFilterCompletion weakFilterCompletion = nil;
    dispatch_block_t disposeOfCompletion = [^{
        // Release self-reference on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            filterCompletion = nil;
        });
    } copy];
    filterCompletion = [^(NSArray<KSCrashReport *> *filteredReports, BOOL completed, NSError *filterError) {
        if (!completed || filteredReports == nil) {
            if (!completed) {
                kscrash_callCompletion(onCompletion, filteredReports, completed, filterError);
            } else if (filteredReports == nil) {
                kscrash_callCompletion(onCompletion, filteredReports, NO,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"filteredReports was nil"]);
            }
            disposeOfCompletion();
            return;
        }

        // Normal run until all filters exhausted or one
        // filter fails to complete.
        if (++iFilter < filterCount) {
            id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterReports:filteredReports onCompletion:weakFilterCompletion];
            return;
        }

        // All filters complete, or a filter failed.
        kscrash_callCompletion(onCompletion, filteredReports, completed, filterError);
        disposeOfCompletion();
    } copy];
    weakFilterCompletion = filterCompletion;

    // Initial call with first filter to start everything going.
    id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}

@end

@interface KSCrashReportFilterConcatenate ()

@property(nonatomic, readwrite, retain) NSString *separatorFmt;
@property(nonatomic, readwrite, retain) NSArray<NSString *> *keys;

@end

@implementation KSCrashReportFilterConcatenate

@synthesize separatorFmt = _separatorFmt;
@synthesize keys = _keys;

+ (instancetype)filterWithSeparatorFmt:(NSString *)separatorFmt keys:(id)firstKey, ...
{
    ksva_list_to_nsarray(firstKey, keys);
    return [[self class] filterWithSeparatorFmt:separatorFmt keysArray:keys];
}

+ (instancetype)filterWithSeparatorFmt:(NSString *)separatorFmt keysArray:(NSArray<NSString *> *)keys
{
    return [[self alloc] initWithSeparatorFmt:separatorFmt keysArray:keys];
}

- (instancetype)initWithSeparatorFmt:(NSString *)separatorFmt keys:(id)firstKey, ...
{
    ksva_list_to_nsarray(firstKey, keys);
    return [self initWithSeparatorFmt:separatorFmt keysArray:keys];
}

- (instancetype)initWithSeparatorFmt:(NSString *)separatorFmt keysArray:(NSArray<NSString *> *)keys
{
    if ((self = [super init])) {
        NSMutableArray *realKeys = [NSMutableArray array];
        for (id key in keys) {
            if ([key isKindOfClass:[NSArray class]]) {
                [realKeys addObjectsFromArray:(NSArray *)key];
            } else {
                [realKeys addObject:key];
            }
        }

        self.separatorFmt = separatorFmt;
        self.keys = realKeys;
    }
    return self;
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReport *report in reports) {
        BOOL firstEntry = YES;
        NSMutableString *concatenated = [NSMutableString string];
        for (NSString *key in self.keys) {
            if (firstEntry) {
                firstEntry = NO;
            } else {
                [concatenated appendFormat:self.separatorFmt, key];
            }
            id object = [KSNSDictionaryHelper objectInDictionary:report.dictionaryValue forKeyPath:key];
            [concatenated appendFormat:@"%@", object];
        }
        [filteredReports addObject:concatenated];
    }
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@interface KSCrashReportFilterSubset ()

@property(nonatomic, readwrite, retain) NSArray *keyPaths;

@end

@implementation KSCrashReportFilterSubset

@synthesize keyPaths = _keyPaths;

+ (instancetype)filterWithKeys:(id)firstKeyPath, ...
{
    ksva_list_to_nsarray(firstKeyPath, keyPaths);
    return [[self class] filterWithKeysArray:keyPaths];
}

+ (instancetype)filterWithKeysArray:(NSArray<NSString *> *)keyPaths
{
    return [[self alloc] initWithKeysArray:keyPaths];
}

- (instancetype)initWithKeys:(id)firstKeyPath, ...
{
    ksva_list_to_nsarray(firstKeyPath, keyPaths);
    return [self initWithKeysArray:keyPaths];
}

- (instancetype)initWithKeysArray:(NSArray<NSString *> *)keyPaths
{
    if ((self = [super init])) {
        NSMutableArray *realKeyPaths = [NSMutableArray array];
        for (id keyPath in keyPaths) {
            if ([keyPath isKindOfClass:[NSArray class]]) {
                [realKeyPaths addObjectsFromArray:(NSArray *)keyPath];
            } else {
                [realKeyPaths addObject:keyPath];
            }
        }

        self.keyPaths = realKeyPaths;
    }
    return self;
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<KSCrashReport *> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReport *report in reports) {
        NSDictionary *reportDict = report.dictionaryValue;
        if (reportDict == nil) {
            KSLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }

        NSMutableDictionary *subset = [NSMutableDictionary dictionary];
        for (NSString *keyPath in self.keyPaths) {
            id object = [KSNSDictionaryHelper objectInDictionary:reportDict forKeyPath:keyPath];
            if (object == nil) {
                kscrash_callCompletion(onCompletion, filteredReports, NO,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"Report did not have key path %@", keyPath]);
                return;
            }
            [subset setObject:object forKey:[keyPath lastPathComponent]];
        }
        KSCrashReport *subsetReport = [KSCrashReport reportWithDictionary:subset];
        [filteredReports addObject:subsetReport];
    }
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterDataToString

+ (instancetype)filter
{
    return [[self alloc] init];
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<KSCrashReport *> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReport *report in reports) {
        NSData *data = report.dataValue;
        if (data == nil) {
            KSLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }

        NSString *converted = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [filteredReports addObject:[KSCrashReport reportWithString:converted]];
    }

    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterStringToData

+ (instancetype)filter
{
    return [[self alloc] init];
}

- (void)filterReports:(NSArray<KSCrashReport *> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<KSCrashReport *> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReport *report in reports) {
        NSString *string = report.stringValue;
        if (string == nil) {
            KSLOG_ERROR(@"Unexpected non-string report: %@", report);
            continue;
        }

        NSData *converted = [string dataUsingEncoding:NSUTF8StringEncoding];
        if (converted == nil) {
            kscrash_callCompletion(onCompletion, filteredReports, NO,
                                   [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                               code:0
                                                        description:@"Could not convert report to UTF-8"]);
            return;
        } else {
            [filteredReports addObject:[KSCrashReport reportWithData:converted]];
        }
    }

    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end
