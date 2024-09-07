#import <XCTest/XCTest.h>

#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFilterDoctor.h"
#import "KSTestModuleConfig.h"

@interface KSCrashDoctor_Tests : XCTestCase
@end

@implementation KSCrashDoctor_Tests

- (KSCrashReportDictionary *)_crashReportAsJSON:(NSString *)filename
{
    NSURL *url = [KS_TEST_MODULE_BUNDLE URLForResource:filename withExtension:@"json"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSDictionary *reportDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [KSCrashReportDictionary reportWithValue:reportDict];
}

- (KSCrashReportDictionary *)_filteredReport:(KSCrashReportDictionary *)report
{
    KSCrashReportDictionary *__block result = nil;
    KSCrashReportFilterDoctor *filter = [KSCrashReportFilterDoctor new];
    [filter filterReports:@[ report ]
             onCompletion:^(NSArray<id<KSCrashReport>> *filteredReports, NSError *error) {
                 result = filteredReports.firstObject;
                 XCTAssertNil(error);
             }];
    return result;
}

- (void)testGracefulTermination
{
    KSCrashReportDictionary *report = [self _crashReportAsJSON:@"sigterm"];
    KSCrashReportDictionary *resultReport = [self _filteredReport:report];
    NSString *diagnostic = resultReport.value[KSCrashField_Crash][KSCrashField_Diagnosis];
    XCTAssertEqual(diagnostic, @"The OS request the app be gracefully terminated.");
}

- (void)testOOM
{
    KSCrashReportDictionary *report = [self _crashReportAsJSON:@"oom"];
    KSCrashReportDictionary *resultReport = [self _filteredReport:report];
    NSString *diagnostic = resultReport.value[KSCrashField_Crash][KSCrashField_Diagnosis];
    XCTAssertEqual(diagnostic, @"The app was terminated due to running out of memory (OOM).");
}

@end
