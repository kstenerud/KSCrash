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
    XCTAssertEqualObjects(diagnostic, @"The app exceeded its memory limit and was terminated by the OS.");
}

- (void)testWatchdogTimeout
{
    KSCrashReportDictionary *report = [self _crashReportAsJSON:@"watchdog"];
    KSCrashReportDictionary *resultReport = [self _filteredReport:report];
    NSString *diagnostic = resultReport.value[KSCrashField_Crash][KSCrashField_Diagnosis];
    XCTAssertEqualObjects(diagnostic, @"App hung for 3.99 seconds. Terminated by watchdog.");
}

static NSString *const kSentinelDiagnosis =
    @"Crashed on the Objective-C nonatomic-property race sentinel. A nonatomic property was read "
    @"on one thread while being written on another (thread-safety bug).";

- (void)testNonatomicPropertyRaceSentinel
{
    // EXC_BAD_ACCESS on 0x400000000000bad0, the sentinel a synthesized nonatomic
    // ObjC setter briefly stores mid-store (Apple ObjC runtime, rdar://148109501).
    KSCrashReportDictionary *report = [self _crashReportAsJSON:@"nonatomic_race"];
    KSCrashReportDictionary *resultReport = [self _filteredReport:report];
    NSString *diagnostic = resultReport.value[KSCrashField_Crash][KSCrashField_Diagnosis];
    XCTAssertEqualObjects(diagnostic, kSentinelDiagnosis);
}

- (void)testNonatomicPropertyRaceSentinel32Bit
{
    // On 32-bit watchOS the sentinel is its low half, 0xbad0 (cpu_arch armv7k).
    KSCrashReportDictionary *report = [self _crashReportAsJSON:@"nonatomic_race_32bit"];
    KSCrashReportDictionary *resultReport = [self _filteredReport:report];
    NSString *diagnostic = resultReport.value[KSCrashField_Crash][KSCrashField_Diagnosis];
    XCTAssertEqualObjects(diagnostic, kSentinelDiagnosis);
}

- (void)testGarbagePointerAt0xbad0On64BitIsNotSentinel
{
    // 0xbad0 is a plausible real garbage pointer on 64-bit, so it must not be
    // mistaken for the 32-bit sentinel there.
    KSCrashReportDictionary *report = [self _crashReportAsJSON:@"bad_access_0xbad0_64bit"];
    KSCrashReportDictionary *resultReport = [self _filteredReport:report];
    NSString *diagnostic = resultReport.value[KSCrashField_Crash][KSCrashField_Diagnosis];
    XCTAssertEqualObjects(diagnostic, @"Attempted to dereference garbage pointer 0xbad0.");
}

@end
