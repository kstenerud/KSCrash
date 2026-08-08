//
//  KSCrashReportFilterAppleFmt_Tests.m
//
//  Created by Alexander Cohen on 2026-02-09.
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
#import "KSCrashReportFields.h"
#import "KSCrashReportFilterAppleFmt.h"

@interface KSCrashReportFilterAppleFmt_Tests : XCTestCase
@end

@implementation KSCrashReportFilterAppleFmt_Tests

/// Helper: builds a minimal report dict that the Apple format filter will accept.
/// The report must have version 3 for the filter to process it.
- (NSDictionary *)_minimalReportWithCrash:(NSDictionary *)crash
{
    return @{
        KSCrashField_Report : @ {
            KSCrashField_Version : @"3.0",
            KSCrashField_ID : @"test-id",
        },
        KSCrashField_System : @ {
            KSCrashField_SystemName : @"iOS",
            KSCrashField_SystemVersion : @"17.0",
            KSCrashField_Machine : @"iPhone14,2",
            KSCrashField_CPUArch : @"arm64",
        },
        KSCrashField_Crash : crash,
    };
}

/// Runs the Apple format filter on a report and returns the result string.
- (NSString *)_appleFormatStringForReport:(NSDictionary *)report
{
    KSCrashReportFilterAppleFmt *filter =
        [[KSCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicated];
    KSCrashReportDictionary *input = [KSCrashReportDictionary reportWithValue:report];

    __block NSString *result = nil;
    [filter filterReports:@[ input ]
             onCompletion:^(NSArray<id<KSCrashReport>> *filteredReports, NSError *error) {
                 XCTAssertNil(error);
                 XCTAssertEqual(filteredReports.count, 1);
                 KSCrashReportString *stringReport = (KSCrashReportString *)filteredReports.firstObject;
                 result = stringReport.value;
             }];
    return result;
}

- (void)testLastExceptionBacktracePresent
{
    NSDictionary *crash = @{
        KSCrashField_Error : @ {
            KSCrashField_Type : @"nsexception",
        },
        KSCrashField_Threads : @[
            @{
                KSCrashField_Index : @0,
                KSCrashField_Crashed : @YES,
                KSCrashField_CurrentThread : @YES,
                KSCrashField_Backtrace : @ {
                    KSCrashField_Contents : @[
                        @{
                            KSCrashField_InstructionAddr : @0x3000,
                            KSCrashField_ObjectAddr : @0x1000,
                            KSCrashField_ObjectName : @"MyApp",
                            KSCrashField_SymbolAddr : @0x2F00,
                            KSCrashField_SymbolName : @"handleUncaughtException",
                        },
                    ],
                    KSCrashField_Skipped : @0,
                },
            },
        ],
        KSCrashField_LastExceptionBacktrace : @ {
            KSCrashField_Contents : @[
                @{
                    KSCrashField_InstructionAddr : @0x1000,
                    KSCrashField_ObjectAddr : @0x0,
                    KSCrashField_ObjectName : @"CoreFoundation",
                    KSCrashField_SymbolAddr : @0x0F00,
                    KSCrashField_SymbolName : @"__exceptionPreprocess",
                },
                @{
                    KSCrashField_InstructionAddr : @0x2000,
                    KSCrashField_ObjectAddr : @0x0,
                    KSCrashField_ObjectName : @"libobjc.A.dylib",
                    KSCrashField_SymbolAddr : @0x1F00,
                    KSCrashField_SymbolName : @"objc_exception_throw",
                },
            ],
            KSCrashField_Skipped : @0,
        },
    };
    NSDictionary *report = [self _minimalReportWithCrash:crash];
    NSString *result = [self _appleFormatStringForReport:report];
    XCTAssertNotNil(result);

    // The section header should be present.
    XCTAssertTrue([result containsString:@"Last Exception Backtrace:"],
                  @"Should contain 'Last Exception Backtrace:' section");

    // The exception backtrace symbols should appear after the section header.
    NSRange sectionRange = [result rangeOfString:@"Last Exception Backtrace:"];
    NSString *sectionContent = [result substringFromIndex:sectionRange.location];
    XCTAssertTrue([sectionContent containsString:@"__exceptionPreprocess"],
                  @"Last exception backtrace should contain __exceptionPreprocess");
    XCTAssertTrue([sectionContent containsString:@"objc_exception_throw"],
                  @"Last exception backtrace should contain objc_exception_throw");
}

- (void)testLastExceptionBacktraceAbsent
{
    NSDictionary *crash = @{
        KSCrashField_Error : @ {
            KSCrashField_Type : @"mach",
        },
        KSCrashField_Threads : @[
            @{
                KSCrashField_Index : @0,
                KSCrashField_Crashed : @YES,
                KSCrashField_CurrentThread : @YES,
                KSCrashField_Backtrace : @ {
                    KSCrashField_Contents : @[
                        @{
                            KSCrashField_InstructionAddr : @0x3000,
                            KSCrashField_ObjectAddr : @0x1000,
                            KSCrashField_ObjectName : @"MyApp",
                            KSCrashField_SymbolAddr : @0x2F00,
                            KSCrashField_SymbolName : @"main",
                        },
                    ],
                    KSCrashField_Skipped : @0,
                },
            },
        ],
    };
    NSDictionary *report = [self _minimalReportWithCrash:crash];
    NSString *result = [self _appleFormatStringForReport:report];
    XCTAssertNotNil(result);

    // The section should NOT be present for non-exception crashes.
    XCTAssertFalse([result containsString:@"Last Exception Backtrace:"],
                   @"Should not contain 'Last Exception Backtrace:' for mach crashes");
}

@end
