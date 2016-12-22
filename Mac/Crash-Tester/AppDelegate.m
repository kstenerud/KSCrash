//
//  AppDelegate.m
//  Crash-Tester
//
//  Created by Karl Stenerud on 9/27/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import "AppDelegate.h"
#import "Crasher.h"
#import "CrashTesterCommands.h"
#import "Configuration.h"

#import <KSCrash/KSCrash.h>

@interface AppDelegate ()

@property(nonatomic, readwrite, retain) Crasher* crasher;
@property(nonatomic, readwrite, assign) BOOL crashInHandler;

@end

@implementation AppDelegate

static BOOL g_crashInHandler = NO;

static void onCrash(const KSCrashReportWriter* writer)
{
    if(g_crashInHandler)
    {
        printf(NULL);
    }
    writer->addStringElement(writer, "test", "test");
    writer->addStringElement(writer, "intl2", "テスト２");
}

- (BOOL) crashInHandler
{
    return g_crashInHandler;
}

- (void) setCrashInHandler:(BOOL)crashInHandler
{
    g_crashInHandler = crashInHandler;
}

- (void) updateReportCount
{
    self.reportCountLabel.stringValue = [CrashTesterCommands reportCountString];
}

- (void) installCrashHandler
{
    KSCrash* handler = [KSCrash sharedInstance];

#if kRedirectConsoleLogToDefaultFile
    [handler redirectConsoleLogsToDefaultFile];
#endif

    handler.deadlockWatchdogInterval = 5.0f;
    handler.onCrash = onCrash;
    handler.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                        @"\"quote\"", @"quoted value",
                        @"blah", @"\"quoted\" key",
                        @"bslash\\", @"bslash value",
                        @"x", @"bslash\\key",
                        @"intl", @"テスト",
                        nil];

    // Don't delete after send for this demo.
    handler.deleteBehaviorAfterSendAll = KSCDeleteNever;

    [handler install];
}

- (void)applicationDidFinishLaunching:(__unused NSNotification *)aNotification
{
    [self installCrashHandler];
    self.crasher = [[Crasher alloc] init];
    [self updateReportCount];
}

- (void) onSendCompleteWithReports:(NSArray*) reports
                         completed:(BOOL) completed
                             error:(NSError*) error
{
    if(completed)
    {
        [CrashTesterCommands showAlertWithTitle:@"Success" message:@"Sent %d reports", [reports count]];
        [self updateReportCount];
    }
    else
    {
        NSLog(@"Failed to send reports: %@", error);
        [CrashTesterCommands showAlertWithTitle:@"Failed" message:@"Failed to send reports", [error localizedDescription]];
    }
}

- (IBAction)onNSException:(__unused id)sender
{
    [self.crasher throwUncaughtNSException];
}

- (IBAction)onCPPException:(__unused id)sender
{
    [self.crasher throwUncaughtCPPException];
}

- (IBAction)onBadPointer:(__unused id)sender
{
    [self.crasher dereferenceBadPointer];
}

- (IBAction)onNullPointer:(__unused id)sender
{
    [self.crasher dereferenceNullPointer];
}

- (IBAction)onCorruptObject:(__unused id)sender
{
    [self.crasher useCorruptObject];
}

- (IBAction)onSpinRunLoop:(__unused id)sender
{
    [self.crasher spinRunloop];
}

- (IBAction)onStackOverflow:(__unused id)sender
{
    [self.crasher causeStackOverflow];
}

- (IBAction)onAbort:(__unused id)sender
{
    [self.crasher doAbort];
}

- (IBAction)onDivideByZero:(__unused id)sender
{
    [self.crasher doDiv0];
}

- (IBAction)onIllegalInstruction:(__unused id)sender
{
    [self.crasher doIllegalInstruction];
}

- (IBAction)onDeallocatedObject:(__unused id)sender
{
    [self.crasher accessDeallocatedObject];
}

- (IBAction)onDeallocatedProxy:(__unused id)sender
{
    [self.crasher accessDeallocatedPtrProxy];
}

- (IBAction)onCorruptMemory:(__unused id)sender
{
    [self.crasher corruptMemory];
}

- (IBAction)onZombieNSException:(__unused id)sender
{
    [self.crasher zombieNSException];
}

- (IBAction)onCrashInHandler:(__unused id)sender
{
    self.crashInHandler = YES;
    [self.crasher dereferenceBadPointer];
}

- (IBAction)onDeadlockainQueue:(__unused id)sender
{
    [self.crasher deadlock];
}

- (IBAction)onDeadlockPThread:(__unused id)sender
{
    [self.crasher pthreadAPICrash];
}

- (IBAction)onUserDefinedCrash:(__unused id)sender
{
    [self.crasher userDefinedCrash];
}

- (IBAction)onPrintStandard:(__unused id)sender
{
    [CrashTesterCommands printStandard];
}

- (IBAction)onPrintUnsymbolicated:(__unused id)sender
{
    [CrashTesterCommands printUnsymbolicated];
}

- (IBAction)onPrintPartiallySymbolicated:(__unused id)sender
{
    [CrashTesterCommands printPartiallySymbolicated];
}

- (IBAction)onPrintSymbolicated:(__unused id)sender
{
    [CrashTesterCommands printSymbolicated];
}

- (IBAction)onPrintSideBySide:(__unused id)sender
{
    [CrashTesterCommands printSideBySide];
}

- (IBAction)onPrintSideBySideWithUserAndSystemData:(__unused id)sender
{
    [CrashTesterCommands printSideBySideWithUserAndSystemData];
}

- (IBAction)onSendToKS:(__unused id)sender
{
    [CrashTesterCommands sendToKSWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error)
     {
         [self onSendCompleteWithReports:filteredReports completed:completed error:error];
     }];
}

- (IBAction)onSendToQuincy:(__unused id)sender
{
    [CrashTesterCommands sendToQuincyWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error)
     {
         [self onSendCompleteWithReports:filteredReports completed:completed error:error];
     }];
}

- (IBAction)onSendToHockey:(__unused id)sender
{
    [CrashTesterCommands sendToHockeyWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error)
     {
         [self onSendCompleteWithReports:filteredReports completed:completed error:error];
     }];
}

- (IBAction)onSendToVictory:(__unused id)sender
{
    [CrashTesterCommands sendToVictoryWithUserName:@"Unknown"
                                        completion:^(NSArray *filteredReports, BOOL completed, NSError *error)
     {
         [self onSendCompleteWithReports:filteredReports completed:completed error:error];
     }];
}

- (IBAction)onDeleteReports:(__unused id)sender
{
    NSLog(@"Deleting reports...");
    [[KSCrash sharedInstance] deleteAllReports];
    [self updateReportCount];
}

@end
