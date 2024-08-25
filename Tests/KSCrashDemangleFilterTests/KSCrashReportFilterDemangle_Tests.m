//
//  KSCrashReportFilterDemangle_Tests.m
//
//  Created by Nikolay Volosatov on 2024-08-25.
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
#import "KSCrashReportFilterDemangle.h"

@interface KSCrashReportFilterDemangle_Tests : XCTestCase

@end

@implementation KSCrashReportFilterDemangle_Tests

- (void)setUp
{
}

#pragma mark – C++ demangling

- (void)testIncorrectCppSymbols
{
    XCTAssertNil([KSCrashReportFilterDemangle demangledCppSymbol:@""]);
    XCTAssertNil([KSCrashReportFilterDemangle demangledCppSymbol:@"23"]);
    XCTAssertNil([KSCrashReportFilterDemangle demangledCppSymbol:@"Not a symbol"]);
    XCTAssertNil([KSCrashReportFilterDemangle
        demangledCppSymbol:@"sScS12ContinuationV5yieldyAB11YieldResultOyx__GxnF"]);  // Swift
}

- (void)testCorrectCppSymbols
{
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledCppSymbol:@"_Z3foov"], @"foo()");
    XCTAssertEqualObjects(
        [KSCrashReportFilterDemangle demangledCppSymbol:@"_ZN6Widget14setStyleOptionERK12StyleOptionsb"],
        @"Widget::setStyleOption(StyleOptions const&, bool)");
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledCppSymbol:@"_ZNSt8ios_base15sync_with_stdioEb"],
                          @"std::ios_base::sync_with_stdio(bool)");
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledCppSymbol:@"_ZNKSt5ctypeIcE13_M_widen_initEv"],
                          @"std::ctype<char>::_M_widen_init() const");
}

#pragma mark – Swift demangling

- (void)testIncorrectSwiftSymbols
{
    XCTAssertNil([KSCrashReportFilterDemangle demangledSwiftSymbol:@""]);
    XCTAssertNil([KSCrashReportFilterDemangle demangledSwiftSymbol:@"23"]);
    XCTAssertNil([KSCrashReportFilterDemangle demangledSwiftSymbol:@"Not a symbol"]);
    XCTAssertNil([KSCrashReportFilterDemangle demangledSwiftSymbol:@"_ZNSt8ios_base15sync_with_stdioEb"]);  // C++
}

- (void)testCorrectSwiftSymbols
{
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledSwiftSymbol:@"$s5HelloAAC8sayHelloyyF"],
                          @"Hello.sayHello()");
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledSwiftSymbol:@"$s3Foo3BarC11doSomethingyyFZ"],
                          @"static Bar.doSomething()");
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledSwiftSymbol:@"$s3app5ModelC5valueSSvg"],
                          @"Model.value.getter");
    XCTAssertEqualObjects([KSCrashReportFilterDemangle demangledSwiftSymbol:@"$s3Foo3BarC11doSomethingySiSS_SbtF"],
                          @"Bar.doSomething(_:_:)");
}

#pragma mark - Report

- (void)testReportDemangle
{
    KSCrashReportFilterDemangle *filter = [KSCrashReportFilterDemangle new];
    KSCrashReportDictionary *mangledReport = [KSCrashReportDictionary reportWithValue:@{
        @"other_root_key" : @"A",
        KSCrashField_Crash : @ {
            @"other_crash_key" : @"B",
            KSCrashField_Threads : @[
                @{
                    KSCrashField_Backtrace : @ {
                        @"other_backtrace_key" : @"C",
                        KSCrashField_Contents : @[
                            @{
                                @"other_symbol_key" : @"D",
                                KSCrashField_SymbolName : @"_Z3foov",
                            },
                            @{
                                KSCrashField_SymbolName : @"$s5HelloAAC8sayHelloyyF",
                            },
                            @{
                                KSCrashField_SymbolName : @"Not_Mangled()",
                            },
                        ],
                    },
                },
                @{
                    @"empty_thread_key" : @"F",
                },
            ],
        },
    }];

    KSCrashReportDictionary *expectedReport = [KSCrashReportDictionary reportWithValue:@{
        @"other_root_key" : @"A",
        KSCrashField_Crash : @ {
            @"other_crash_key" : @"B",
            KSCrashField_Threads : @[
                @{
                    KSCrashField_Backtrace : @ {
                        @"other_backtrace_key" : @"C",
                        KSCrashField_Contents : @[
                            @{
                                @"other_symbol_key" : @"D",
                                KSCrashField_SymbolName : @"foo()",
                            },
                            @{
                                KSCrashField_SymbolName : @"Hello.sayHello()",
                            },
                            @{
                                KSCrashField_SymbolName : @"Not_Mangled()",
                            },
                        ],
                    },
                },
                @{
                    @"empty_thread_key" : @"F",
                },
            ],
        },
    }];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Filter callback called"];
    [filter filterReports:@[ mangledReport ]
             onCompletion:^(NSArray<id<KSCrashReport>> *filteredReports, BOOL completed, NSError *error) {
                 KSCrashReportDictionary *demangledReport = filteredReports.firstObject;
                 XCTAssertEqualObjects(demangledReport, expectedReport);
                 [expectation fulfill];
             }];

    [self waitForExpectations:@[ expectation ] timeout:0.1];
}

@end
