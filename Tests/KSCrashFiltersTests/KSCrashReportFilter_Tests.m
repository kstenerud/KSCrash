//
//  KSCrashReportFilter_Tests.m
//
//  Created by Karl Stenerud on 2012-05-12.
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

#import <XCTest/XCTest.h>

#import "KSCrashReport.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterGZip.h"
#import "KSCrashReportFilterJSON.h"

@interface KSCrash_TestNilFilter : NSObject <KSCrashReportFilter>

@end

@implementation KSCrash_TestNilFilter

+ (KSCrash_TestNilFilter *)filter
{
    return [[self alloc] init];
}

- (void)filterReports:(__unused NSArray *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    onCompletion(nil, YES, nil);
}

@end

@interface KSCrash_TestFilter : NSObject <KSCrashReportFilter>

@property(nonatomic, readwrite, assign) NSTimeInterval delay;
@property(nonatomic, readwrite, assign) BOOL completed;
@property(nonatomic, readwrite, strong) NSError *error;
@property(nonatomic, readwrite, strong) NSTimer *timer;
@property(nonatomic, readwrite, copy) NSArray<id<KSCrashReport>> *reports;
@property(nonatomic, readwrite, copy) KSCrashReportFilterCompletion onCompletion;

@end

@implementation KSCrash_TestFilter

+ (KSCrash_TestFilter *)filterWithDelay:(NSTimeInterval)delay completed:(BOOL)completed error:(NSError *)error
{
    return [[self alloc] initWithDelay:delay completed:completed error:error];
}

- (id)initWithDelay:(NSTimeInterval)delay completed:(BOOL)completed error:(NSError *)error
{
    if ((self = [super init])) {
        _delay = delay;
        _completed = completed;
        _error = error;
    }
    return self;
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    self.reports = reports;
    self.onCompletion = onCompletion;
    if (self.delay > 0) {
        self.timer = [NSTimer timerWithTimeInterval:self.delay
                                             target:self
                                           selector:@selector(onTimeUp)
                                           userInfo:nil
                                            repeats:NO];
    } else {
        [self onTimeUp];
    }
}

- (void)onTimeUp
{
    kscrash_callCompletion(self.onCompletion, self.reports, self.completed, self.error);
}

@end

@interface KSCrashReportFilter_Tests : XCTestCase

@property(nonatomic, copy) NSArray<KSCrashReportString *> *reports;
@property(nonatomic, copy) NSArray<KSCrashReportData *> *reportsWithData;
@property(nonatomic, copy) NSArray<KSCrashReportDictionary *> *reportsWithDict;

@end

@implementation KSCrashReportFilter_Tests

#if __has_feature(objc_arc)

- (void)setUp
{
    self.reports = @[
        [KSCrashReportString reportWithValue:@"1"],
        [KSCrashReportString reportWithValue:@"2"],
        [KSCrashReportString reportWithValue:@"3"],
    ];
    self.reportsWithData = @[
        [KSCrashReportData reportWithValue:[@"1" dataUsingEncoding:NSUTF8StringEncoding]],
        [KSCrashReportData reportWithValue:[@"2" dataUsingEncoding:NSUTF8StringEncoding]],
        [KSCrashReportData reportWithValue:[@"3" dataUsingEncoding:NSUTF8StringEncoding]],
    ];
    self.reportsWithDict = @[
        [KSCrashReportDictionary reportWithValue:@{
            @"first" : @"1",
            @"second" : @"a",
            @"third" : @"b",
        }],
    ];
}

- (void)testPassthroughLeak
{
    __block NSArray *reports = @[ [KSCrashReportString reportWithValue:@""] ];
    __weak id weakRef = reports;

    __block KSCrashReportFilterPassthrough *filter = [KSCrashReportFilterPassthrough filter];
    [filter filterReports:reports
             onCompletion:^(__unused NSArray *filteredReports, __unused BOOL completed, __unused NSError *error) {
                 filter = nil;
                 reports = nil;
                 dispatch_async(dispatch_get_main_queue(), ^{
                     XCTAssertNil(weakRef, @"Object leaked");
                 });
             }];
}

- (void)testPipeline
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrashReportFilterPassthrough filter], [KSCrashReportFilterPassthrough filter], nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testPipelineInit
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterPipeline alloc]
        initWithFilters:[KSCrashReportFilterPassthrough filter], [KSCrashReportFilterPassthrough filter], nil];
    filter = filter;

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testPipelineNoFilters
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPipeline filterWithFilters:nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterPipelineIncomplete
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrash_TestFilter filterWithDelay:0 completed:NO error:nil], nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertNotNil(filteredReports, @"");
                 XCTAssertFalse(completed, @"");
                 XCTAssertNil(error, @"");
             }];
}

- (void)testFilterPipelineNilReports
{
    id<KSCrashReportFilter> filter =
        [KSCrashReportFilterPipeline filterWithFilters:[KSCrash_TestNilFilter filter], nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertNil(filteredReports, @"");
                 XCTAssertFalse(completed, @"");
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testPiplelineLeak1
{
    __block NSArray *reports = [NSArray arrayWithArray:self.reports];
    __block id<KSCrashReportFilter> filter = [KSCrash_TestFilter filterWithDelay:0.1 completed:YES error:nil];

    __weak id weakReports = reports;
    __weak id weakFilter = filter;

    __block KSCrashReportFilterPipeline *pipeline = [KSCrashReportFilterPipeline filterWithFilters:filter, nil];
    [pipeline filterReports:reports
               onCompletion:^(__unused NSArray *filteredReports, __unused BOOL completed, __unused NSError *error) {
                   reports = nil;
                   filter = nil;
                   pipeline = nil;
                   XCTAssertTrue(completed, @"");
                   dispatch_async(dispatch_get_main_queue(), ^{
                       XCTAssertNil(weakReports, @"Object leaked");
                       XCTAssertNil(weakFilter, @"Object leaked");
                   });
               }];
}

- (void)testPiplelineLeak2
{
    __block NSArray *reports = [NSArray arrayWithArray:self.reports];
    __block id<KSCrashReportFilter> filter = [KSCrash_TestFilter filterWithDelay:0.1 completed:NO error:nil];

    __weak id weakReports = reports;
    __weak id weakFilter = filter;

    __block KSCrashReportFilterPipeline *pipeline = [KSCrashReportFilterPipeline filterWithFilters:filter, nil];
    [pipeline filterReports:reports
               onCompletion:^(__unused NSArray *filteredReports, __unused BOOL completed, __unused NSError *error) {
                   reports = nil;
                   filter = nil;
                   pipeline = nil;
                   XCTAssertFalse(completed, @"");
                   dispatch_async(dispatch_get_main_queue(), ^{
                       XCTAssertNil(weakReports, @"Object leaked");
                       XCTAssertNil(weakFilter, @"Object leaked");
                   });
               }];
}

#endif

- (void)testFilterPassthrough
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPassthrough filter];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterStringToData
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterStringToData filter];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reportsWithData, @"");
             }];
}

- (void)testFilterDataToString
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterDataToString filter];

    [filter filterReports:self.reportsWithData
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterPipeline
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrashReportFilterStringToData filter], [KSCrashReportFilterDataToString filter], nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterCombine
{
    id<KSCrashReportFilter> filter =
        [KSCrashReportFilterCombine filterWithFiltersAndKeys:[KSCrashReportFilterPassthrough filter], @"normal",
                                                             [KSCrashReportFilterStringToData filter], @"data", nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 for (NSUInteger i = 0; i < self.reports.count; i++) {
                     id exp1 = [[self.reports objectAtIndex:i] value];
                     id exp2 = [[self.reportsWithData objectAtIndex:i] value];
                     KSCrashReportDictionary *entry = [filteredReports objectAtIndex:i];
                     id result1 = entry.value[@"normal"];
                     id result2 = entry.value[@"data"];
                     XCTAssertNotNil(result1);
                     XCTAssertNotNil(result2);
                     XCTAssertEqualObjects(result1, exp1, @"");
                     XCTAssertEqualObjects(result2, exp2, @"");
                 }
             }];
}

- (void)testFilterCombineInit
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterCombine alloc]
        initWithFiltersAndKeys:[KSCrashReportFilterPassthrough filter], @"normal",
                               [KSCrashReportFilterStringToData filter], @"data", nil];
    filter = filter;

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 for (NSUInteger i = 0; i < [self.reports count]; i++) {
                     id exp1 = [[self.reports objectAtIndex:i] value];
                     id exp2 = [[self.reportsWithData objectAtIndex:i] value];
                     KSCrashReportDictionary *entry = [filteredReports objectAtIndex:i];
                     id result1 = entry.value[@"normal"];
                     id result2 = entry.value[@"data"];
                     XCTAssertNotNil(result1);
                     XCTAssertNotNil(result2);
                     XCTAssertEqualObjects(result1, exp1, @"");
                     XCTAssertEqualObjects(result2, exp2, @"");
                 }
             }];
}

- (void)testFilterCombineNoFilters
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterCombine filterWithFiltersAndKeys:nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 for (NSUInteger i = 0; i < [self.reports count]; i++) {
                     id exp = [self.reports objectAtIndex:i];
                     NSString *entry = [filteredReports objectAtIndex:i];
                     XCTAssertEqualObjects(entry, exp, @"");
                 }
             }];
}

- (void)testFilterCombineIncomplete
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterCombine
        filterWithFiltersAndKeys:[KSCrash_TestFilter filterWithDelay:0 completed:NO error:nil], @"Blah", nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertNotNil(filteredReports, @"");
                 XCTAssertFalse(completed, @"");
                 XCTAssertNil(error, @"");
             }];
}

- (void)testFilterCombineNilReports
{
    id<KSCrashReportFilter> filter =
        [KSCrashReportFilterCombine filterWithFiltersAndKeys:[KSCrash_TestNilFilter filter], @"Blah", nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertNil(filteredReports, @"");
                 XCTAssertFalse(completed, @"");
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testFilterCombineArray
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterCombine
        filterWithFiltersAndKeys:[NSArray arrayWithObject:[KSCrashReportFilterPassthrough filter]], @"normal",
                                 [NSArray arrayWithObject:[KSCrashReportFilterStringToData filter]], @"data", nil];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 for (NSUInteger i = 0; i < [self.reports count]; i++) {
                     id exp1 = [[self.reports objectAtIndex:i] value];
                     id exp2 = [[self.reportsWithData objectAtIndex:i] value];
                     KSCrashReportDictionary *entry = [filteredReports objectAtIndex:i];
                     id result1 = entry.value[@"normal"];
                     id result2 = entry.value[@"data"];
                     XCTAssertNotNil(result1);
                     XCTAssertNotNil(result2);
                     XCTAssertEqualObjects(result1, exp1, @"");
                     XCTAssertEqualObjects(result2, exp2, @"");
                 }
             }];
}

- (void)testFilterCombineMissingKey
{
    id<KSCrashReportFilter> filter =
        [KSCrashReportFilterCombine filterWithFiltersAndKeys:[KSCrashReportFilterPassthrough filter], @"normal",
                                                             [KSCrashReportFilterStringToData filter],
                                                             // Missing key
                                                             nil];

    [filter filterReports:self.reports
             onCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertFalse(completed, @"");
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testConcatenate
{
    NSString *expected = @"1,a";
    id<KSCrashReportFilter> filter = [KSCrashReportFilterConcatenate filterWithSeparatorFmt:@","
                                                                                       keys:@"first", @"second", nil];

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([filteredReports objectAtIndex:0], expected, @"");
             }];
}

- (void)testConcatenateInit
{
    NSString *expected = @"1,a";
    id<KSCrashReportFilter> filter =
        [[KSCrashReportFilterConcatenate alloc] initWithSeparatorFmt:@"," keys:@"first", @"second", nil];
    filter = filter;

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([filteredReports objectAtIndex:0], expected, @"");
             }];
}

- (void)testSubset
{
    id<KSCrashReport> expected = [KSCrashReportDictionary reportWithValue:@{
        @"first" : @"1",
        @"third" : @"b",
    }];
    id<KSCrashReportFilter> filter = [KSCrashReportFilterSubset filterWithKeys:@"first", @"third", nil];

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([filteredReports objectAtIndex:0], expected, @"");
             }];
}

- (void)testSubsetBadKeyPath
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterSubset filterWithKeys:@"first", @"aaa", nil];

    [filter filterReports:self.reportsWithDict
             onCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertFalse(completed, @"");
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testSubsetInit
{
    id<KSCrashReport> expected = [KSCrashReportDictionary reportWithValue:@{
        @"first" : @"1",
        @"third" : @"b",
    }];
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterSubset alloc] initWithKeys:@"first", @"third", nil];
    filter = filter;

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([filteredReports objectAtIndex:0], expected, @"");
             }];
}

@end
