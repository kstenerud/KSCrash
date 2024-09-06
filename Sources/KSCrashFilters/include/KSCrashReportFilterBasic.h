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

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * Initializer.
 *
 * @param filterDictionary A dictionary where each key-value pair represents a filter
 *                         and its corresponding key. The keys are strings that will
 *                         be used to store the output of their respective filters in
 *                         the final report dictionary. The values are the filters to
 *                         apply. Each filter should conform to the KSCrashReportFilter
 *                         protocol.
 *
 * @return An initialized instance of the class.
 */
- (instancetype)initWithFilters:(NSDictionary<NSString *, id<KSCrashReportFilter>> *)filterDictionary;

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

/** Initializer using an array of filters.
 *
 * @param filters An array of filters, where each filter conforms to
 *                the KSCrashReportFilter protocol.
 */
- (instancetype)initWithFilters:(NSArray<id<KSCrashReportFilter>> *)filters;

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

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Initializer using an array of keys.
 *
 * @param separatorFmt Formatting text to use when separating the values. You may include
 *                     %@ in the formatting text to include the key name as well.
 * @param keys         An array of keys whose corresponding values will be concatenated
 *                     from the source report.
 */
- (instancetype)initWithSeparatorFmt:(NSString *)separatorFmt keys:(NSArray<NSString *> *)keys;

@end

/**
 * Fetches subsets of data from the source reports. All other data is discarded.
 *
 * Input: NSDictionary
 * Output: NSDictionary
 */
NS_SWIFT_NAME(CrashReportFilterSubset)
@interface KSCrashReportFilterSubset : NSObject <KSCrashReportFilter>

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Initializer using an array of key paths.
 *
 * @param keyPaths An array of key paths to search for in the source reports.
 *                 Each key path will extract a subset of data from the reports.
 */
- (instancetype)initWithKeys:(NSArray<NSString *> *)keyPaths;

@end

/**
 * Convert UTF-8 data to an NSString.
 *
 * Input: NSData
 * Output: NSString
 */
NS_SWIFT_NAME(CrashReportFilterDataToString)
@interface KSCrashReportFilterDataToString : NSObject <KSCrashReportFilter>

@end

/**
 * Convert NSString to UTF-8 encoded NSData.
 *
 * Input: NSString
 * Output: NSData
 */
NS_SWIFT_NAME(CrashReportFilterStringToData)
@interface KSCrashReportFilterStringToData : NSObject <KSCrashReportFilter>

@end

NS_ASSUME_NONNULL_END
