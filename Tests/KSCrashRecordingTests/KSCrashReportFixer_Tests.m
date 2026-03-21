//
//  KSCrashReportFixer_Tests.m
//  KSCrash-iOS
//
//  Created by Karl on 2016-11-07.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "KSCrashReportFixer.h"
#import "KSJSONCodecObjC.h"
#import "KSTestModuleConfig.h"

@interface KSCrashReportFixer_Tests : XCTestCase

@end

@implementation KSCrashReportFixer_Tests

- (void)testLoadCrash
{
    NSBundle *bundle = KS_TEST_MODULE_BUNDLE;
    NSString *rawPath = [bundle pathForResource:@"raw" ofType:@"json"];
    NSData *rawData = [NSData dataWithContentsOfFile:rawPath];
    XCTAssertNotNil(rawData);

    NSError *error = nil;
    NSMutableDictionary *rawReport =
        [KSJSONCodec decode:rawData
                    options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                            KSJSONDecodeOptionKeepPartialObject
                      error:&error];
    XCTAssertNotNil(rawReport);
    XCTAssertNil(error);

    NSDictionary *fixedReport = kscrf_fixupReportDict(rawReport);
    XCTAssertNotNil(fixedReport);

    NSString *processedPath = [bundle pathForResource:@"processed" ofType:@"json"];
    NSData *processedData = [NSData dataWithContentsOfFile:processedPath];
    id processedObjects = [NSJSONSerialization JSONObjectWithData:processedData options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(processedObjects);

    XCTAssertEqualObjects(fixedReport, processedObjects);
}

@end
