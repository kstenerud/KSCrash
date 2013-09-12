//
//  AppDelegate+UI.m
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import "AppDelegate+UI.h"
#import "ARCSafe_MemMgmt.h"
#import "LoadableCategory.h"
#import "CommandTVC.h"
#import "Configuration.h"
#import "Crasher.h"

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



MAKE_CATEGORIES_LOADABLE(AppDelegate_UI)


@implementation AppDelegate (UI)

#pragma mark Public Methods

- (UIViewController*) createRootViewController
{
    __unsafe_unretained id blockSelf = self;
    CommandTVC* cmdController = [self commandTVCWithCommands:[self topLevelCommands]];
    cmdController.getTitleBlock = ^NSString* (__unused UIViewController* controller)
    {
        return [NSString stringWithFormat:@"Crash Tester: %@", [blockSelf reportCountString]];
    };
    return as_autorelease([[UINavigationController alloc] initWithRootViewController:cmdController]);
}


#pragma mark Utility

- (CommandTVC*) commandTVCWithCommands:(NSArray*) commands
{
    CommandTVC* cmdController = as_autorelease([[CommandTVC alloc] initWithStyle:UITableViewStylePlain]);
    [cmdController.commands addObjectsFromArray:commands];
    [self setBackButton:cmdController];
    return cmdController;
}

- (void) setBackButton:(UIViewController*) controller
{
    controller.navigationItem.backBarButtonItem =
    as_autorelease([[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                    style:UIBarButtonItemStyleBordered
                                                   target:nil
                                                   action:nil]);
}

- (NSString*) reportCountString
{
    return [NSString stringWithFormat:@"%d Reports", [[KSCrash sharedInstance] reportCount]];
}

- (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) fmt, ...
{
    va_list args;
    va_start(args, fmt);
    NSString* message = as_autorelease([[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);

    [as_autorelease([[UIAlertView alloc] initWithTitle:title
                                               message:message
                                              delegate:nil
                                     cancelButtonTitle:@"OK"
                                     otherButtonTitles:nil]) show];
}


#pragma mark Commands

- (NSArray*) topLevelCommands
{
    __unsafe_unretained id blockSelf = self;
    NSMutableArray* commands = [NSMutableArray array];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Manage Reports"
                     accessoryType:UITableViewCellAccessoryDisclosureIndicator
                             block:^(UIViewController* controller)
      {
          CommandTVC* cmdController = [self commandTVCWithCommands:[blockSelf manageCommands]];
          cmdController.getTitleBlock = ^NSString* (__unused UIViewController* controllerInner)
          {
              return [NSString stringWithFormat:@"Manage (%@)", [blockSelf reportCountString]];
          };
          [controller.navigationController pushViewController:cmdController animated:YES];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Crash"
                     accessoryType:UITableViewCellAccessoryDisclosureIndicator
                             block:^(UIViewController* controller)
      {
          CommandTVC* cmdController = [self commandTVCWithCommands:[blockSelf crashCommands]];
          cmdController.title = @"Crash";
          [controller.navigationController pushViewController:cmdController animated:YES];
      }]];
    
    return commands;
}

- (NSArray*) manageCommands
{
    __unsafe_unretained id blockSelf = self;
    NSMutableArray* commands = [NSMutableArray array];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Print To Console"
                     accessoryType:UITableViewCellAccessoryDisclosureIndicator
                             block:^(UIViewController* controller)
      {
          CommandTVC* cmdController = [self commandTVCWithCommands:[blockSelf printCommands]];
          cmdController.getTitleBlock = ^NSString* (__unused UIViewController* controllerInner)
          {
              return [NSString stringWithFormat:@"Print (%@)", [blockSelf reportCountString]];
          };
          [controller.navigationController pushViewController:cmdController animated:YES];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send To Server"
                     accessoryType:UITableViewCellAccessoryDisclosureIndicator
                             block:^(UIViewController* controller)
      {
          CommandTVC* cmdController = [self commandTVCWithCommands:[blockSelf sendCommands]];
          cmdController.getTitleBlock = ^NSString* (__unused UIViewController* controllerInner)
          {
              return [NSString stringWithFormat:@"Send (%@)", [blockSelf reportCountString]];
          };
          [controller.navigationController pushViewController:cmdController animated:YES];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send As E-Mail"
                     accessoryType:UITableViewCellAccessoryDisclosureIndicator
                             block:^(UIViewController* controller)
      {
          CommandTVC* cmdController = [self commandTVCWithCommands:[blockSelf mailCommands]];
          cmdController.getTitleBlock = ^NSString* (__unused UIViewController* controllerInner)
          {
              return [NSString stringWithFormat:@"Mail (%@)", [blockSelf reportCountString]];
          };
          [controller.navigationController pushViewController:cmdController animated:YES];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Delete All Reports"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Deleting reports...");
          [[KSCrash sharedInstance] deleteAllReports];
          [(CommandTVC*)controller reloadTitle];
      }]];
    
    return commands;
}

- (NSArray*) mailCommands
{
    NSMutableArray* commands = [NSMutableArray array];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Standard Reports"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Mailing standard reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          KSCrashReportSinkEMail* sink = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                              message:nil
                                                                          filenameFmt:@"StandardReport-%d.json.gz"];
          crashReporter.sink = [sink defaultCrashReportFilterSet];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Unsymbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Mailing unsymbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleUnsymbolicated],
                                [KSCrashReportFilterStringToData filter],
                                [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                   subject:@"Crash Reports"
                                                                   message:nil
                                                               filenameFmt:@"AppleUnsymbolicatedReport-%d.txt.gz"],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Partial)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Mailing partially symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStylePartiallySymbolicated],
                                [KSCrashReportFilterStringToData filter],
                                [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                   subject:@"Crash Reports"
                                                                   message:nil
                                                               filenameFmt:@"ApplePartialSymbolicatedReport-%d.txt.gz"],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Symbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Mailing symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
                                [KSCrashReportFilterStringToData filter],
                                [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                   subject:@"Crash Reports"
                                                                   message:nil
                                                               filenameFmt:@"AppleSymbolicatedReport-%d.txt.gz"],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Side-By-Side)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Mailing side-by-side symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                                [KSCrashReportFilterStringToData filter],
                                [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                                [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                   subject:@"Crash Reports"
                                                                   message:nil
                                                               filenameFmt:@"AppleSideBySideReport-%d.txt.gz"],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style + user & system data"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Mailing side-by-side symbolicated apple reports with system and user data...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          KSCrashReportSinkEMail* sink = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                            subject:@"Crash Reports"
                                                                            message:nil
                                                                        filenameFmt:@"AppleSystemUserReport-%d.txt.gz"];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashFilterSets appleFmtWithUserAndSystemData:KSAppleReportStyleSymbolicatedSideBySide
                                                                      compressed:YES],
                                sink,
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];

    return commands;
}

- (NSArray*) printCommands
{
    NSMutableArray* commands = [NSMutableArray array];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Standard Reports"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Printing standard reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
                                [KSCrashReportFilterDataToString filter],
                                [KSCrashReportSinkConsole filter],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Unsymbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Printing unsymbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleUnsymbolicated],
                                [KSCrashReportSinkConsole filter],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Partial)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Printing partially symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStylePartiallySymbolicated],
                                [KSCrashReportSinkConsole filter],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Symbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Printing symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
                                [KSCrashReportSinkConsole filter],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Side-By-Side)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Printing side-by-side symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                                [KSCrashReportSinkConsole filter],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style + user & system data"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          NSLog(@"Printing side-by-side symbolicated apple reports with system and user data...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:
                                [KSCrashFilterSets appleFmtWithUserAndSystemData:KSAppleReportStyleSymbolicatedSideBySide
                                                                      compressed:NO],
                                [KSCrashReportSinkConsole filter],
                                nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];

    return commands;
}

- (void) onSendCompleteWithController:(UIViewController*) controller
                              reports:(NSArray*) reports
                            completed:(BOOL) completed
                                error:(NSError*) error
{
    if(completed)
    {
        [self showAlertWithTitle:@"Success" message:@"Sent %d reports", [reports count]];
        [(CommandTVC*)controller reloadTitle];
    }
    else
    {
        NSLog(@"Failed to send reports: %@", error);
        [self showAlertWithTitle:@"Failed" message:@"Failed to send reports", [error localizedDescription]];
    }
}

- (NSArray*) sendCommands
{
    __unsafe_unretained id blockSelf = self;
    NSMutableArray* commands = [NSMutableArray array];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send to KS"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Sending reports to KS...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [[KSCrashReportSinkStandard sinkWithURL:kReportURL] defaultCrashReportFilterSet];
          [crashReporter sendAllReportsWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
           {
               [blockSelf onSendCompleteWithController:controller
                                               reports:filteredReports
                                             completed:completed
                                                 error:error];
           }];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send to Quincy"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Sending reports to Quincy...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [[KSCrashReportSinkQuincy sinkWithURL:kQuincyReportURL
                                                          userIDKey:nil
                                                    contactEmailKey:nil
                                               crashDescriptionKeys:nil] defaultCrashReportFilterSet];
          [crashReporter sendAllReportsWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
           {
               [blockSelf onSendCompleteWithController:controller
                                               reports:filteredReports
                                             completed:completed
                                                 error:error];
           }];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send to Hockey"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Sending reports to Hockey...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [[KSCrashReportSinkHockey sinkWithAppIdentifier:kHockeyAppID
                                                                    userIDKey:nil
                                                              contactEmailKey:nil
                                                         crashDescriptionKeys:nil] defaultCrashReportFilterSet];
          [crashReporter sendAllReportsWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
           {
               [blockSelf onSendCompleteWithController:controller
                                               reports:filteredReports
                                             completed:completed
                                                 error:error];
           }];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send to Victory"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Sending reports to Victory...");
          KSCrash* crashReporter = [KSCrash sharedInstance];
          crashReporter.sink = [[KSCrashReportSinkVictory sinkWithURL:kVictoryURL
                                                               userName:[[UIDevice currentDevice] name]
                                                              userEmail:nil] defaultCrashReportFilterSet];
          [crashReporter sendAllReportsWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
           {
               [blockSelf onSendCompleteWithController:controller
                                               reports:filteredReports
                                             completed:completed
                                                 error:error];
           }];
      }]];
    
    return commands;
}

- (NSArray*) crashCommands
{
    NSMutableArray* commands = [NSMutableArray array];
    __block AppDelegate* blockSelf = self;
    
    [commands addObject:
     [CommandEntry commandWithName:@"NSException"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher throwUncaughtNSException];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"C++ Exception"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher throwUncaughtCPPException];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Bad Pointer"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher dereferenceBadPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Null Pointer"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher dereferenceNullPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Corrupt Object"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher useCorruptObject];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Spin Run Loop"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher spinRunloop];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Stack Overflow"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher causeStackOverflow];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Abort"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher doAbort];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Divide By Zero"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher doDiv0];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Illegal Instruction"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher doIllegalInstruction];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deallocated Object"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher accessDeallocatedObject];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deallocated Proxy"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher accessDeallocatedPtrProxy];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Corrupt Memory"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher corruptMemory];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Zombie NSException"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher zombieNSException];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Crash in Handler"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          blockSelf.crashInHandler = YES;
          [blockSelf.crasher dereferenceBadPointer];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deadlock main queue"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher deadlock];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deadlock pthread"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher pthreadAPICrash];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"User Defined (soft) Crash"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [blockSelf.crasher userDefinedCrash];
      }]];


    return commands;
}

@end
