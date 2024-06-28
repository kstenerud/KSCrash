//
//  KSCrashReportFilterBasic.h
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

#import "KSCrashReportFilter.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Very basic filter that passes through reports untouched.
 *
 * Input: Anything.
 * Output: Same as input (passthrough).
 */
NS_SWIFT_NAME(CrashReportFilterPassthrough)
@interface KSCrashReportFilterPassthrough : NSObject <KSCrashReportFilter>

+ (instancetype)filter;

@end

/**
 * Passes reports to a series of subfilters, then stores the results of those operations
 * as keyed values in final master reports.
 *
 * Input: Anything
 * Output: NSDictionary
 */
NS_SWIFT_NAME(CrashReportFilterCombine)
@interface KSCrashReportFilterCombine : NSObject <KSCrashReportFilter>

/** Constructor.
 *
 * @param firstFilter The first filter, followed by key, filter, key, ...
 *                    Each "filter" can be id<KSCrashReportFilter> or an NSArray
 *                    of filters (which gets wrapped in a pipeline filter).
 */
+ (instancetype)filterWithFiltersAndKeys:(nullable id)firstFilter, ... NS_REQUIRES_NIL_TERMINATION;

/** Constructor.
 *
 * @param filters An array of filters to apply. Each filter should conform to the
 *                KSCrashReportFilter protocol. If a filter is an NSArray, it will
 *                be wrapped in a pipeline filter.
 * @param keys    An array of keys corresponding to each filter. Each key will be
 *                used to store the output of its respective filter in the final
 *                report dictionary.
 */
+ (instancetype)filterWithFilters:(NSArray *)filters keys:(NSArray<NSString *> *)keys;

/** Initializer.
 *
 * @param firstFilter The first filter, followed by key, filter, key, ...
 *                    Each "filter" can be id<KSCrashReportFilter> or an NSArray
 *                    of filters (which gets wrapped in a pipeline filter).
 */
- (instancetype)initWithFiltersAndKeys:(nullable id)firstFilter, ... NS_REQUIRES_NIL_TERMINATION;

/** Initializer.
 *
 * @param filters An array of filters to apply. Each filter should conform to the
 *                KSCrashReportFilter protocol. If a filter is an NSArray, it will
 *                be wrapped in a pipeline filter.
 * @param keys    An array of keys corresponding to each filter. Each key will be
 *                used to store the output of its respective filter in the final
 *                report dictionary.
 */
- (instancetype)initWithFilters:(NSArray *)filters keys:(NSArray<NSString *> *)keys;

@end

/**
 * A pipeline of filters. Reports get passed through each subfilter in order.
 *
 * Input: Depends on what's in the pipeline.
 * Output: Depends on what's in the pipeline.
 */
NS_SWIFT_NAME(CrashReportFilterPipeline)
@interface KSCrashReportFilterPipeline : NSObject <KSCrashReportFilter>

/** The filters in this pipeline. */
@property(nonatomic, readonly, copy) NSArray<id<KSCrashReportFilter>> *filters;

/** Constructor.
 *
 * @param firstFilter The first filter, followed by filter, filter, ...
 *                    Each "filter" can be an id<KSCrashReportFilter> or an NSArray
 *                    containing filters or locations of filters (which get wrapped in a pipeline filter).
 */
+ (instancetype)filterWithFilters:(nullable id)firstFilter, ... NS_REQUIRES_NIL_TERMINATION;

/** Constructor using an array of filters.
 *
 * @param filters An array where each element can be a filter conforming to
 *                the KSCrashReportFilter protocol or a location of filters.
 *                Arrays of filters will be wrapped in a pipeline filter.
 */
+ (instancetype)filterWithFiltersArray:(NSArray *)filters;

/** Initializer.
 *
 * @param firstFilter The first filter, followed by filter, filter, ...
 *                    Each "filter" can be an id<KSCrashReportFilter> or an NSArray
 *                    containing filters or locations of filters (which get wrapped in a pipeline filter).
 */
- (instancetype)initWithFilters:(nullable id)firstFilter, ... NS_REQUIRES_NIL_TERMINATION;

/** Initializer using an array of filters.
 *
 * @param filters An array where each element can be a filter conforming to
 *                the KSCrashReportFilter protocol or a location of filters.
 *                Arrays of filters will be wrapped in a pipeline filter.
 */
- (instancetype)initWithFiltersArray:(NSArray *)filters;

/** Adds a filter to the beginning of the pipeline.
 *
 * @param filter The filter to be added. This filter must conform to the
 *               KSCrashReportFilter protocol. It will be inserted at the
 *               beginning of the existing filters in the pipeline.
 */
- (void)addFilter:(id<KSCrashReportFilter>)filter;

@end

/**
 * Takes values by key from the report and concatenates their string representations.
 *
 * Input: NSDictionary
 * Output: NSString
 */
NS_SWIFT_NAME(CrashReportFilterConcatenate)
@interface KSCrashReportFilterConcatenate : NSObject <KSCrashReportFilter>

/** Constructor.
 *
 * @param separatorFmt Formatting text to use when separating the values. You may include
 *                     %@ in the formatting text to include the key name as well.
 * @param firstKey Series of keys to extract from the source report.
 */
+ (instancetype)filterWithSeparatorFmt:(NSString *)separatorFmt keys:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;

/** Constructor using an array of keys.
 *
 * @param separatorFmt Formatting text to use when separating the values. You may include
 *                     %@ in the formatting text to include the key name as well.
 * @param keys         An array of keys whose corresponding values will be concatenated
 *                     from the source report.
 */
+ (instancetype)filterWithSeparatorFmt:(NSString *)separatorFmt keysArray:(NSArray<NSString *> *)keys;

/** Initializer.
 *
 * @param separatorFmt Formatting text to use when separating the values. You may include
 *                     %@ in the formatting text to include the key name as well.
 * @param firstKey Series of keys to extract from the source report.
 */
- (instancetype)initWithSeparatorFmt:(NSString *)separatorFmt keys:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;

/** Initializer using an array of keys.
 *
 * @param separatorFmt Formatting text to use when separating the values. You may include
 *                     %@ in the formatting text to include the key name as well.
 * @param keys         An array of keys whose corresponding values will be concatenated
 *                     from the source report.
 */
- (instancetype)initWithSeparatorFmt:(NSString *)separatorFmt keysArray:(NSArray<NSString *> *)keys;

@end

/**
 * Fetches subsets of data from the source reports. All other data is discarded.
 *
 * Input: NSDictionary
 * Output: NSDictionary
 */
NS_SWIFT_NAME(CrashReportFilterSubset)
@interface KSCrashReportFilterSubset : NSObject <KSCrashReportFilter>

/** Constructor.
 *
 * @param firstKeyPath Series of key paths to search in the source reports.
 */
+ (instancetype)filterWithKeys:(id)firstKeyPath, ... NS_REQUIRES_NIL_TERMINATION;

/** Constructor using an array of key paths.
 *
 * @param keyPaths An array of key paths to search for in the source reports.
 *                 Each key path will extract a subset of data from the reports.
 */
+ (instancetype)filterWithKeysArray:(NSArray<NSString *> *)keyPaths;

/** Initializer.
 *
 * @param firstKeyPath Series of key paths to search in the source reports.
 */
- (instancetype)initWithKeys:(id)firstKeyPath, ... NS_REQUIRES_NIL_TERMINATION;

/** Initializer using an array of key paths.
 *
 * @param keyPaths An array of key paths to search for in the source reports.
 *                 Each key path will extract a subset of data from the reports.
 */
- (instancetype)initWithKeysArray:(NSArray<NSString *> *)keyPaths;

@end

/**
 * Convert UTF-8 data to an NSString.
 *
 * Input: NSData
 * Output: NSString
 */
NS_SWIFT_NAME(CrashReportFilterDataToString)
@interface KSCrashReportFilterDataToString : NSObject <KSCrashReportFilter>

+ (instancetype)filter;

@end

/**
 * Convert NSString to UTF-8 encoded NSData.
 *
 * Input: NSString
 * Output: NSData
 */
NS_SWIFT_NAME(CrashReportFilterStringToData)
@interface KSCrashReportFilterStringToData : NSObject <KSCrashReportFilter>

+ (instancetype)filter;

@end

NS_ASSUME_NONNULL_END
