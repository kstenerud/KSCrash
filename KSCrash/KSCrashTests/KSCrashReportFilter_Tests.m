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


#import <SenTestingKit/SenTestingKit.h>
#import "KSCrashCallCompletion.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterGZip.h"
#import "KSCrashReportFilterJSON.h"
#import "ARCSafe_MemMgmt.h"
#import "NSData+GZip.h"


@interface TimedTestFilter: NSObject <KSCrashReportFilter>

@property(nonatomic,readwrite,assign) BOOL completed;
@property(nonatomic,readwrite,retain) NSError* error;
@property(nonatomic,readwrite,retain) NSTimer* timer;
@property(nonatomic,readwrite,retain) NSArray* reports;
@property(nonatomic,readwrite,copy) KSCrashReportFilterCompletion onCompletion;

@end

@implementation TimedTestFilter

@synthesize completed = _completed;
@synthesize error = _error;
@synthesize reports = _reports;
@synthesize timer = _timer;
@synthesize onCompletion = _onCompletion;

+ (TimedTestFilter*) filterWithCompleted:(BOOL) completed error:(NSError*) error
{
    return as_autorelease([[self alloc] initWithCompleted:completed error:error]);
}

- (id) initWithCompleted:(BOOL) completed error:(NSError*) error
{
    if((self = [super init]))
    {
        self.completed = completed;
        self.error = error;
    }
    return self;
}

- (void) dealloc
{
    as_release(_error);
    as_release(_reports);
    as_release(_timer);
    as_release(_onCompletion);
    as_superdealloc();
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    self.reports = reports;
    self.onCompletion = onCompletion;
    self.timer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(onTimeUp) userInfo:nil repeats:NO];
}

- (void) onTimeUp
{
    kscrash_i_callCompletion(self.onCompletion, self.reports, self.completed, self.error);
}

@end


@interface KSCrashReportFilter_Tests : SenTestCase @end

@implementation KSCrashReportFilter_Tests

#if __has_feature(objc_arc)

- (void) testPassthroughLeak
{
    __block NSArray* reports = [NSArray arrayWithObject:@""];
    __weak id weakRef = reports;

    __block KSCrashReportFilterPassthrough* filter = [KSCrashReportFilterPassthrough filter];
    [filter filterReports:reports
             onCompletion:^(__unused NSArray* filteredReports,
                            __unused BOOL completed,
                            __unused NSError* error)
     {
         filter = nil;
         reports = nil;
         dispatch_async(dispatch_get_main_queue(), ^
                        {
                            STAssertNil(weakRef, @"Object leaked");
                        });
     }];
}

- (void) testPiplelineLeak1
{
    __block NSArray* reports = [NSArray arrayWithObjects:@"one", @"two", nil];
    __block id<KSCrashReportFilter> filter = [TimedTestFilter filterWithCompleted:YES error:nil];

    __weak id weakReports = reports;
    __weak id weakFilter = filter;

    __block KSCrashReportFilterPipeline* pipeline = [KSCrashReportFilterPipeline filterWithFilters:filter, nil];
    [pipeline filterReports:reports
               onCompletion:^(__unused NSArray* filteredReports,
                              __unused BOOL completed,
                              __unused NSError* error)
     {
         reports = nil;
         filter = nil;
         pipeline = nil;
         STAssertTrue(completed, @"");
         dispatch_async(dispatch_get_main_queue(), ^
                        {
                            STAssertNil(weakReports, @"Object leaked");
                            STAssertNil(weakFilter, @"Object leaked");
                        });
     }];
}

- (void) testPiplelineLeak2
{
    __block NSArray* reports = [NSArray arrayWithObjects:@"one", @"two", nil];
    __block id<KSCrashReportFilter> filter = [TimedTestFilter filterWithCompleted:NO error:nil];

    __weak id weakReports = reports;
    __weak id weakFilter = filter;

    __block KSCrashReportFilterPipeline* pipeline = [KSCrashReportFilterPipeline filterWithFilters:filter, nil];
    [pipeline filterReports:reports
               onCompletion:^(__unused NSArray* filteredReports,
                              __unused BOOL completed,
                              __unused NSError* error)
     {
         reports = nil;
         filter = nil;
         pipeline = nil;
         STAssertFalse(completed, @"");
         dispatch_async(dispatch_get_main_queue(), ^
                        {
                            STAssertNil(weakReports, @"Object leaked");
                            STAssertNil(weakFilter, @"Object leaked");
                        });
     }];
}

#endif

- (void) testFilterPassthrough
{
    NSArray* expected = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPassthrough filter];

    [filter filterReports:expected onCompletion:^(NSArray* filteredReports,
                                                  BOOL completed,
                                                  NSError* error)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error, @"");
         STAssertEqualObjects(expected, filteredReports, @"");
     }];
}

- (void) testFilterStringToData
{
    NSArray* source = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    NSArray* expected = [NSArray arrayWithObjects:
                         [@"1" dataUsingEncoding:NSUTF8StringEncoding],
                         [@"2" dataUsingEncoding:NSUTF8StringEncoding],
                         [@"3" dataUsingEncoding:NSUTF8StringEncoding],
                         nil];
    id<KSCrashReportFilter> filter = [KSCrashReportFilterStringToData filter];

    [filter filterReports:source onCompletion:^(NSArray* filteredReports,
                                                BOOL completed,
                                                NSError* error)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error, @"");
         STAssertEqualObjects(expected, filteredReports, @"");
     }];
}

- (void) testFilterDataToString
{
    NSArray* source = [NSArray arrayWithObjects:
                       [@"1" dataUsingEncoding:NSUTF8StringEncoding],
                       [@"2" dataUsingEncoding:NSUTF8StringEncoding],
                       [@"3" dataUsingEncoding:NSUTF8StringEncoding],
                       nil];
    NSArray* expected = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    id<KSCrashReportFilter> filter = [KSCrashReportFilterDataToString filter];

    [filter filterReports:source onCompletion:^(NSArray* filteredReports,
                                                BOOL completed,
                                                NSError* error)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error, @"");
         STAssertEqualObjects(expected, filteredReports, @"");
     }];
}

- (void) testFilterPipeline
{
    NSArray* expected = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    id<KSCrashReportFilter> filter = [KSCrashReportFilterPipeline filterWithFilters:
                                      [KSCrashReportFilterStringToData filter],
                                      [KSCrashReportFilterDataToString filter],
                                      nil];

    [filter filterReports:expected onCompletion:^(NSArray* filteredReports,
                                                  BOOL completed,
                                                  NSError* error)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error, @"");
         STAssertEqualObjects(expected, filteredReports, @"");
     }];
}

- (void) testFilterCombine
{
    NSArray* expected1 = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    NSArray* expected2 = [NSArray arrayWithObjects:
                          [@"1" dataUsingEncoding:NSUTF8StringEncoding],
                          [@"2" dataUsingEncoding:NSUTF8StringEncoding],
                          [@"3" dataUsingEncoding:NSUTF8StringEncoding],
                          nil];
    id<KSCrashReportFilter> filter = [KSCrashReportFilterCombine filterWithFiltersAndKeys:
                                      [KSCrashReportFilterPassthrough filter],
                                      @"normal",
                                      [KSCrashReportFilterStringToData filter],
                                      @"data",
                                      nil];

    [filter filterReports:expected1 onCompletion:^(NSArray* filteredReports,
                                                   BOOL completed,
                                                   NSError* error)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error, @"");
         for(NSUInteger i = 0; i < [expected1 count]; i++)
         {
             id exp1 = [expected1 objectAtIndex:i];
             id exp2 = [expected2 objectAtIndex:i];
             NSDictionary* entry = [filteredReports objectAtIndex:i];
             id result1 = [entry objectForKey:@"normal"];
             id result2 = [entry objectForKey:@"data"];
             STAssertEqualObjects(result1, exp1, @"");
             STAssertEqualObjects(result2, exp2, @"");
         }
     }];
}

- (void) testFilterGZipCompress
{
    NSArray* decompressed = [NSArray arrayWithObjects:
                             [@"this is a test" dataUsingEncoding:NSUTF8StringEncoding],
                             [@"here is another test" dataUsingEncoding:NSUTF8StringEncoding],
                             [@"testing is fun!" dataUsingEncoding:NSUTF8StringEncoding],
                             nil];

    NSError* error = nil;
    NSMutableArray* compressed = [NSMutableArray array];
    for(NSData* data in decompressed)
    {
        NSData* newData = [data gzippedWithCompressionLevel:-1 error:&error];
        STAssertNotNil(newData, @"");
        STAssertNil(error, @"");
        [compressed addObject:newData];
    }

    id<KSCrashReportFilter> filter = [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1];
    [filter filterReports:decompressed onCompletion:^(NSArray* filteredReports,
                                                      BOOL completed,
                                                      NSError* error2)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error2, @"");
         STAssertEqualObjects(compressed, filteredReports, @"");
     }];
}

- (void) testFilterGZipDecompress
{
    NSArray* decompressed = [NSArray arrayWithObjects:
                             [@"this is a test" dataUsingEncoding:NSUTF8StringEncoding],
                             [@"here is another test" dataUsingEncoding:NSUTF8StringEncoding],
                             [@"testing is fun!" dataUsingEncoding:NSUTF8StringEncoding],
                             nil];

    NSError* error = nil;
    NSMutableArray* compressed = [NSMutableArray array];
    for(NSData* data in decompressed)
    {
        NSData* newData = [data gzippedWithCompressionLevel:-1 error:&error];
        STAssertNotNil(newData, @"");
        STAssertNil(error, @"");
        [compressed addObject:newData];
    }

    id<KSCrashReportFilter> filter = [KSCrashReportFilterGZipDecompress filter];
    [filter filterReports:compressed onCompletion:^(NSArray* filteredReports,
                                                    BOOL completed,
                                                    NSError* error2)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error2, @"");
         STAssertEqualObjects(decompressed, filteredReports, @"");
     }];
}

- (void) testFilterJSONEncode
{
    NSArray* decoded = [NSArray arrayWithObjects:
                        [NSArray arrayWithObjects:@"1", @"2", @"3", nil],
                        [NSArray arrayWithObjects:@"4", @"5", @"6", nil],
                        [NSArray arrayWithObjects:@"7", @"8", @"9", nil],
                        nil];
    NSArray* encoded = [NSArray arrayWithObjects:
                        [@"[\"1\",\"2\",\"3\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        [@"[\"4\",\"5\",\"6\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        [@"[\"7\",\"8\",\"9\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        nil];

    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONEncode filterWithOptions:0];
    [filter filterReports:decoded onCompletion:^(NSArray* filteredReports,
                                                 BOOL completed,
                                                 NSError* error2)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error2, @"");
         STAssertEqualObjects(encoded, filteredReports, @"");
     }];
}

- (void) testFilterJSONDencode
{
    NSArray* decoded = [NSArray arrayWithObjects:
                        [NSArray arrayWithObjects:@"1", @"2", @"3", nil],
                        [NSArray arrayWithObjects:@"4", @"5", @"6", nil],
                        [NSArray arrayWithObjects:@"7", @"8", @"9", nil],
                        nil];
    NSArray* encoded = [NSArray arrayWithObjects:
                        [@"[\"1\",\"2\",\"3\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        [@"[\"4\",\"5\",\"6\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        [@"[\"7\",\"8\",\"9\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        nil];

    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONEncode filterWithOptions:0];
    [filter filterReports:decoded onCompletion:^(NSArray* filteredReports,
                                                 BOOL completed,
                                                 NSError* error2)
     {
         STAssertTrue(completed, @"");
         STAssertNil(error2, @"");
         STAssertEqualObjects(encoded, filteredReports, @"");
     }];
}

@end
