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

- (void)filterReports:(__unused NSArray *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    onCompletion(nil, nil);
}

@end

@interface KSCrash_TestFilter : NSObject <KSCrashReportFilter>

@property(nonatomic, readwrite, assign) NSTimeInterval delay;
@property(nonatomic, readwrite, strong) NSError *error;
@property(nonatomic, readwrite, strong) NSTimer *timer;
@property(nonatomic, readwrite, copy) NSArray<id<KSCrashReport>> *reports;
@property(nonatomic, readwrite, copy) KSCrashReportFilterCompletion onCompletion;

@end

@implementation KSCrash_TestFilter

+ (KSCrash_TestFilter *)filterWithDelay:(NSTimeInterval)delay error:(NSError *)error
{
    return [[self alloc] initWithDelay:delay error:error];
}

- (id)initWithDelay:(NSTimeInterval)delay error:(NSError *)error
{
    if ((self = [super init])) {
        _delay = delay;
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
    kscrash_callCompletion(self.onCompletion, self.reports, self.error);
}

@end

@interface KSCrashReportFilter_Tests : XCTestCase

@property(nonatomic, copy) NSArray<KSCrashReportString *> *reports;
@property(nonatomic, copy) NSArray<KSCrashReportData *> *reportsWithData;
@property(nonatomic, copy) NSArray<KSCrashReportDictionary *> *reportsWithDict;
@property(nonatomic, strong) NSError *testError;

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
    self.testError = [NSError errorWithDomain:@"test" code:-23 userInfo:nil];
}

- (void)testPassthroughLeak
{
    __block NSArray *reports = @[ [KSCrashReportString reportWithValue:@""] ];
    __weak id weakRef = reports;

    __block KSCrashReportFilterPassthrough *filter = [KSCrashReportFilterPassthrough new];
    [filter filterReports:reports
             onCompletion:^(__unused NSArray *filteredReports, __unused NSError *error) {
                 filter = nil;
                 reports = nil;
                 dispatch_async(dispatch_get_main_queue(), ^{
                     XCTAssertNil(weakRef, @"Object leaked");
                 });
             }];
}

- (void)testPipeline
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        [KSCrashReportFilterPassthrough new],
        [KSCrashReportFilterPassthrough new],
    ]];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testPipelineInit
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        [KSCrashReportFilterPassthrough new],
        [KSCrashReportFilterPassthrough new],
    ]];
    filter = filter;

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testPipelineNoFilters
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPipeline new];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterPipelineError
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterPipeline alloc]
        initWithFilters:@[ [KSCrash_TestFilter filterWithDelay:0 error:self.testError] ]];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNotNil(filteredReports);
                 XCTAssertEqualObjects(error, self.testError);
             }];
}

- (void)testFilterPipelineNilReports
{
    id<KSCrashReportFilter> filter =
        [[KSCrashReportFilterPipeline alloc] initWithFilters:@[ [KSCrash_TestNilFilter new] ]];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(filteredReports, @"");
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testPiplelineLeak1
{
    __block NSArray *reports = [NSArray arrayWithArray:self.reports];
    __block id<KSCrashReportFilter> filter = [KSCrash_TestFilter filterWithDelay:0.1 error:nil];

    __weak id weakReports = reports;
    __weak id weakFilter = filter;

    __block KSCrashReportFilterPipeline *pipeline = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[ filter ]];
    [pipeline filterReports:reports
               onCompletion:^(__unused NSArray *filteredReports, __unused NSError *error) {
                   reports = nil;
                   filter = nil;
                   pipeline = nil;
                   dispatch_async(dispatch_get_main_queue(), ^{
                       XCTAssertNil(weakReports, @"Object leaked");
                       XCTAssertNil(weakFilter, @"Object leaked");
                   });
               }];
}

- (void)testPiplelineLeak2
{
    __block NSArray *reports = [NSArray arrayWithArray:self.reports];
    __block id<KSCrashReportFilter> filter = [KSCrash_TestFilter filterWithDelay:0.1 error:nil];

    __weak id weakReports = reports;
    __weak id weakFilter = filter;

    __block KSCrashReportFilterPipeline *pipeline = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[ filter ]];
    [pipeline filterReports:reports
               onCompletion:^(__unused NSArray *filteredReports, __unused NSError *error) {
                   reports = nil;
                   filter = nil;
                   pipeline = nil;
                   dispatch_async(dispatch_get_main_queue(), ^{
                       XCTAssertNil(weakReports, @"Object leaked");
                       XCTAssertNil(weakFilter, @"Object leaked");
                   });
               }];
}

#endif

- (void)testFilterPassthrough
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPassthrough new];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterStringToData
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterStringToData new];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reportsWithData, @"");
             }];
}

- (void)testFilterDataToString
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterDataToString new];

    [filter filterReports:self.reportsWithData
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterPipeline
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterPipeline alloc]
        initWithFilters:@[ [KSCrashReportFilterStringToData new], [KSCrashReportFilterDataToString new] ]];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects(filteredReports, self.reports, @"");
             }];
}

- (void)testFilterCombine
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterCombine alloc] initWithFilters:@{
        @"normal" : [KSCrashReportFilterPassthrough new],
        @"data" : [KSCrashReportFilterStringToData new],
    }];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
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

- (void)testFilterCombineNoFilters
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterCombine alloc] initWithFilters:@{}];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
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
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterCombine alloc]
        initWithFilters:@{ @"Blah" : [KSCrash_TestFilter filterWithDelay:0 error:self.testError] }];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNotNil(filteredReports, @"");
                 XCTAssertEqualObjects(error, self.testError, @"");
             }];
}

- (void)testFilterCombineNilReports
{
    id<KSCrashReportFilter> filter =
        [[KSCrashReportFilterCombine alloc] initWithFilters:@{ @"Blah" : [KSCrash_TestNilFilter new] }];

    [filter filterReports:self.reports
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(filteredReports, @"");
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testConcatenate
{
    NSString *expected = @"1,a";
    id<KSCrashReportFilter> filter =
        [[KSCrashReportFilterConcatenate alloc] initWithSeparatorFmt:@"," keys:@[ @"first", @"second" ]];

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([[filteredReports objectAtIndex:0] untypedValue], expected, @"");
             }];
}

- (void)testConcatenateInit
{
    NSString *expected = @"1,a";
    id<KSCrashReportFilter> filter =
        [[KSCrashReportFilterConcatenate alloc] initWithSeparatorFmt:@"," keys:@[ @"first", @"second" ]];
    filter = filter;

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([[filteredReports objectAtIndex:0] untypedValue], expected, @"");
             }];
}

- (void)testSubset
{
    id<KSCrashReport> expected = [KSCrashReportDictionary reportWithValue:@{
        @"first" : @"1",
        @"third" : @"b",
    }];
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterSubset alloc] initWithKeys:@[ @"first", @"third" ]];

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([filteredReports objectAtIndex:0], expected, @"");
             }];
}

- (void)testSubsetBadKeyPath
{
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterSubset alloc] initWithKeys:@[ @"first", @"aaa" ]];

    [filter filterReports:self.reportsWithDict
             onCompletion:^(__unused NSArray *filteredReports, NSError *error) {
                 XCTAssertNotNil(error, @"");
             }];
}

- (void)testSubsetInit
{
    id<KSCrashReport> expected = [KSCrashReportDictionary reportWithValue:@{
        @"first" : @"1",
        @"third" : @"b",
    }];
    id<KSCrashReportFilter> filter = [[KSCrashReportFilterSubset alloc] initWithKeys:@[ @"first", @"third" ]];
    filter = filter;

    [filter filterReports:self.reportsWithDict
             onCompletion:^(NSArray *filteredReports, NSError *error) {
                 XCTAssertNil(error, @"");
                 XCTAssertEqualObjects([filteredReports objectAtIndex:0], expected, @"");
             }];
}

@end
