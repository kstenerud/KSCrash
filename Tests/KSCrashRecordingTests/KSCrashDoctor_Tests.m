#import <XCTest/XCTest.h>

#import "KSCrashDoctor.h"

// This is duplicated from `KSCrashReportFixer_Tests.m`
#ifdef SWIFTPM_MODULE_BUNDLE
#define KS_TEST_MODULE_BUNDLE SWIFTPM_MODULE_BUNDLE
#else
#define KS_TEST_MODULE_BUNDLE ([NSBundle bundleForClass:[self class]])
#endif

@interface KSCrashDoctor_Tests : XCTestCase @end

@implementation KSCrashDoctor_Tests

- (NSDictionary<NSString *, id> *)_crashReportAsJSON:(NSString *)filename
{
    NSURL *url = [KS_TEST_MODULE_BUNDLE URLForResource:filename withExtension:@"json"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (void) testGracefulTermination
{
    id report = [self _crashReportAsJSON:@"sigterm"];
    NSString *diagnostic = [[[KSCrashDoctor alloc] init] diagnoseCrash:report];
    XCTAssertEqual(diagnostic, @"The OS request the app be gracefully terminated.");
}

@end
