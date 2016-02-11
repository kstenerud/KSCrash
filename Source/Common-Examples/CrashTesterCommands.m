//
//  CrashTesterCommands.m
//  Example-Apps-Mac
//
//  Created by Karl Stenerud on 9/28/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import "CrashTesterCommands.h"
#import "Configuration.h"

#import <KSCrash/KSCrashAdvanced.h>
#import <KSCrash/KSCrashReportFilterSets.h>
#import <KSCrash/KSCrashReportFilter.h>
#import <KSCrash/KSCrashReportFilterAppleFmt.h>
#import <KSCrash/KSCrashReportFilterBasic.h>
#import <KSCrash/KSCrashReportFilterGZip.h>
#import <KSCrash/KSCrashReportFilterJSON.h>
#import <KSCrash/KSCrashReportSinkConsole.h>
#import <KSCrash/KSCrashReportSinkEMail.h>
#import <KSCrash/KSCrashReportSinkQuincyHockey.h>
#import <KSCrash/KSCrashReportSinkStandard.h>
#import <KSCrash/KSCrashReportSinkVictory.h>

@implementation CrashTesterCommands

+ (NSString*) reportCountString
{
    int reportCount = (int)[[KSCrash sharedInstance] reportCount];
    if(reportCount == 1)
    {
        return @"1 Report";
    }
    else
    {
        return [NSString stringWithFormat:@"%d Reports", reportCount];
    }
}

+ (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) fmt, ...
{
    va_list args;
    va_start(args, fmt);
    NSString* message = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
    [[[UIAlertView alloc] initWithTitle:title
                                message:message
                               delegate:nil
                      cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];
#else
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert runModal];
#endif
}


+ (void) sendReportsWithMessage:(NSString*)message
                           sink:(id<KSCrashReportFilter>)sink
{
    [self sendReportsWithMessage:message sink:sink completion:nil];
}

+ (void) sendReportsWithMessage:(NSString*)message
                           sink:(id<KSCrashReportFilter>)sink
                     completion:(KSCrashReportFilterCompletion)completion
{
    NSLog(@"%@", message);
    KSCrash* crashReporter = [KSCrash sharedInstance];
    crashReporter.sink = sink;
    [crashReporter sendAllReportsWithCompletion:completion];
}

+ (void) printStandard
{
    [self sendReportsWithMessage:@"Printing standard reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
                                  [KSCrashReportFilterDataToString filter],
                                  [KSCrashReportSinkConsole filter],
                                  nil]];
}

+ (void) printUnsymbolicated
{
    [self sendReportsWithMessage:@"Printing unsymbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleUnsymbolicated],
                                  [KSCrashReportSinkConsole filter],
                                  nil]];
}

+ (void) printPartiallySymbolicated
{
    [self sendReportsWithMessage:@"Printing partially symbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStylePartiallySymbolicated],
                                  [KSCrashReportSinkConsole filter],
                                  nil]];
}

+ (void) printSymbolicated
{
    [self sendReportsWithMessage:@"Printing symbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
                                  [KSCrashReportSinkConsole filter],
                                  nil]];
}

+ (void) printSideBySide
{
    [self sendReportsWithMessage:@"Apple Style (Side-By-Side)"
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                                  [KSCrashReportSinkConsole filter],
                                  nil]];
}

+ (void) printSideBySideWithUserAndSystemData
{
    [self sendReportsWithMessage:@"Printing side-by-side symbolicated apple reports with system and user data..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashFilterSets appleFmtWithUserAndSystemData:KSAppleReportStyleSymbolicatedSideBySide
                                                                        compressed:NO],
                                  [KSCrashReportSinkConsole filter],
                                  nil]];
}

+ (void) mailStandard
{
    [self sendReportsWithMessage:@"Mailing standard reports..."
                            sink:[[KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                    subject:@"Crash Reports"
                                                                    message:nil
                                                                filenameFmt:@"StandardReport-%d.json.gz"] defaultCrashReportFilterSet]];
}

+ (void) mailUnsymbolicated
{
    [self sendReportsWithMessage:@"Mailing unsymbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleUnsymbolicated],
                                  [KSCrashReportFilterStringToData filter],
                                  [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                  [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                     subject:@"Crash Reports"
                                                                     message:nil
                                                                 filenameFmt:@"AppleUnsymbolicatedReport-%d.txt.gz"],
                                  nil]];
}

+ (void) mailPartiallySymbolicated
{
    [self sendReportsWithMessage:@"Mailing partially symbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStylePartiallySymbolicated],
                                  [KSCrashReportFilterStringToData filter],
                                  [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                  [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                     subject:@"Crash Reports"
                                                                     message:nil
                                                                 filenameFmt:@"ApplePartialSymbolicatedReport-%d.txt.gz"],
                                  nil]];
}

+ (void) mailSymbolicated
{
    [self sendReportsWithMessage:@"Mailing symbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
                                  [KSCrashReportFilterStringToData filter],
                                  [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                  [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                     subject:@"Crash Reports"
                                                                     message:nil
                                                                 filenameFmt:@"AppleSymbolicatedReport-%d.txt.gz"],
                                  nil]];
}

+ (void) mailSideBySide
{
    [self sendReportsWithMessage:@"Mailing side-by-side symbolicated apple reports..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                                  [KSCrashReportFilterStringToData filter],
                                  [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                  [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                     subject:@"Crash Reports"
                                                                     message:nil
                                                                 filenameFmt:@"AppleSideBySideReport-%d.txt.gz"],
                                  nil]];
}

+ (void) mailSideBySideWithUserAndSystemData
{
    [self sendReportsWithMessage:@"Mailing side-by-side symbolicated apple reports with system and user data..."
                            sink:[KSCrashReportFilterPipeline filterWithFilters:
                                  [KSCrashFilterSets appleFmtWithUserAndSystemData:KSAppleReportStyleSymbolicatedSideBySide
                                                                        compressed:YES],
                                  [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                     subject:@"Crash Reports"
                                                                     message:nil
                                                                 filenameFmt:@"AppleSystemUserReport-%d.txt.gz"],
                                  nil]];
}

+ (void) sendToKSWithCompletion:(KSCrashReportFilterCompletion)completion
{
    [self sendReportsWithMessage:@"Sending reports to KS..."
                           sink:[[KSCrashReportSinkStandard sinkWithURL:kReportURL] defaultCrashReportFilterSet]
                      completion:completion];
}

+ (void) sendToQuincyWithCompletion:(KSCrashReportFilterCompletion)completion
{
    [self sendReportsWithMessage:@"Sending reports to Quincy..."
                            sink:[[KSCrashReportSinkQuincy sinkWithURL:kQuincyReportURL
                                                             userIDKey:nil
                                                           userNameKey:nil
                                                       contactEmailKey:nil
                                                  crashDescriptionKeys:nil] defaultCrashReportFilterSet]
                      completion:completion];
}

+ (void) sendToHockeyWithCompletion:(KSCrashReportFilterCompletion)completion
{
    [self sendReportsWithMessage:@"Sending reports to Hockey..."
                            sink:[[KSCrashReportSinkHockey sinkWithAppIdentifier:kHockeyAppID
                                                                       userIDKey:nil
                                                                     userNameKey:nil
                                                                 contactEmailKey:nil
                                                            crashDescriptionKeys:nil] defaultCrashReportFilterSet]
                      completion:completion];
}

+ (void) sendToVictoryWithUserName:(NSString*)userName
                        completion:(KSCrashReportFilterCompletion)completion
{
    [self sendReportsWithMessage:@"Sending reports to Victory..."
                            sink:[[KSCrashReportSinkVictory sinkWithURL:kVictoryURL
                                                               userName:userName
                                                              userEmail:nil] defaultCrashReportFilterSet]
                      completion:completion];
}

@end
