#import <XCTest/XCTest.h>

#import "KSCrashDoctor.h"

@interface KSCrashDoctor_Tests : XCTestCase @end


@implementation KSCrashDoctor_Tests

- (NSDictionary<NSString *, id> *)_crashReportAsJSON:(NSString *)filename
{
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:filename withExtension:@"json"];
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
