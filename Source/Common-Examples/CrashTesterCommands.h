//
//  CrashTesterCommands.h
//  Example-Apps-Mac
//
//  Created by Karl Stenerud on 9/28/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <KSCrash/KSCrashReportFilter.h>

@interface CrashTesterCommands : NSObject

+ (NSString*) reportCountString;

+ (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) fmt, ...;

+ (void) printStandard;

+ (void) printUnsymbolicated;

+ (void) printPartiallySymbolicated;

+ (void) printSymbolicated;

+ (void) printSideBySide;

+ (void) printSideBySideWithUserAndSystemData;

+ (void) mailStandard;

+ (void) mailUnsymbolicated;

+ (void) mailPartiallySymbolicated;

+ (void) mailSymbolicated;

+ (void) mailSideBySide;

+ (void) mailSideBySideWithUserAndSystemData;

+ (void) sendToKSWithCompletion:(KSCrashReportFilterCompletion)completion;

+ (void) sendToQuincyWithCompletion:(KSCrashReportFilterCompletion)completion;

+ (void) sendToHockeyWithCompletion:(KSCrashReportFilterCompletion)completion;

+ (void) sendToVictoryWithUserName:(NSString*)userName
                        completion:(KSCrashReportFilterCompletion)completion;

@end
