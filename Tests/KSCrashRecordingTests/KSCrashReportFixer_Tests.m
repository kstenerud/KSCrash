//
//  KSCrashReportFixer_Tests.m
//  KSCrash-iOS
//
//  Created by Karl on 2016-11-07.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "KSCrashReportFixer.h"

#ifdef SWIFTPM_MODULE_BUNDLE
#define KS_TEST_MODULE_BUNDLE SWIFTPM_MODULE_BUNDLE
#else
#define KS_TEST_MODULE_BUNDLE ([NSBundle bundleForClass:[self class]])
#endif

@interface KSCrashReportFixer_Tests : XCTestCase

@end

@implementation KSCrashReportFixer_Tests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testLoadCrash
{
    NSBundle* bundle = KS_TEST_MODULE_BUNDLE;
    NSString* rawPath = [bundle pathForResource:@"raw" ofType:@"json"];
    NSData* rawData = [NSData dataWithContentsOfFile:rawPath];
    char* fixedBytes = kscrf_fixupCrashReport(rawData.bytes);
//    NSLog(@"%@", [[NSString alloc] initWithData:[NSData dataWithBytes:fixedBytes length:strlen(fixedBytes)] encoding:NSUTF8StringEncoding]);
    NSData* fixedData = [NSData dataWithBytesNoCopy:fixedBytes length:strlen(fixedBytes)];
    NSError* error = nil;
    id fixedObjects = [NSJSONSerialization JSONObjectWithData:fixedData options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fixedObjects);

    NSString* processedPath = [bundle pathForResource:@"processed" ofType:@"json"];
    NSData* processedData = [NSData dataWithContentsOfFile:processedPath];
    id processedObjects = [NSJSONSerialization JSONObjectWithData:processedData options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(processedObjects);

    XCTAssertEqualObjects(fixedObjects, processedObjects);
}

@end
