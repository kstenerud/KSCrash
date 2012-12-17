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
#import <KSCrash/KSCrashReportSinkQuincy.h>
#import <KSCrash/KSCrashReportSinkStandard.h>



MAKE_CATEGORIES_LOADABLE(AppDelegate_UI)


@interface AppDelegate (UIPrivate)

- (void) setBackButton:(UIViewController*) controller;

- (NSString*) reportCountString;

- (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) message;

- (CommandTVC*) commandTVCWithCommands:(NSArray*) commands;

- (NSArray*) crashCommands;

- (NSArray*) manageCommands;

- (NSArray*) printCommands;

- (NSArray*) mailCommands;

- (NSArray*) sendCommands;

- (NSArray*) topLevelCommands;

@end


@implementation AppDelegate (UI)

#pragma mark Public Methods

- (UIViewController*) createRootViewController
{
    // Don't delete after send for this demo.
    [KSCrash instance].deleteAfterSend = NO;
    
    __unsafe_unretained id blockSelf = self;
    CommandTVC* cmdController = [self commandTVCWithCommands:[self topLevelCommands]];
    cmdController.getTitleBlock = ^NSString* (UIViewController* controller)
    {
        #pragma unused(controller)
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
    return [NSString stringWithFormat:@"%d Reports", [[KSCrash instance] reportCount]];
}

- (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) message
{
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
          cmdController.getTitleBlock = ^NSString* (UIViewController* controllerInner)
          {
              #pragma unused(controllerInner)
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
          cmdController.getTitleBlock = ^NSString* (UIViewController* controllerInner)
          {
              #pragma unused(controllerInner)
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
          cmdController.getTitleBlock = ^NSString* (UIViewController* controllerInner)
          {
              #pragma unused(controllerInner)
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
          cmdController.getTitleBlock = ^NSString* (UIViewController* controllerInner)
          {
              #pragma unused(controllerInner)
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
          [[KSCrash instance] deleteAllReports];
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
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Mailing standard reports...");
          KSCrash* crashReporter = [KSCrash instance];
          KSCrashReportSinkEMail* filter = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                          filenameFmt:@"StandardReport-%d.json.gz"];
          NSArray* filters = [filter defaultCrashReportFilterSet];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Unsymbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Mailing unsymbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          KSCrashReportSinkEMail* filter = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                          filenameFmt:@"AppleUnsymbolicatedReport-%d.txt.gz"];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleUnsymbolicated],
                              [KSCrashReportFilterStringToData filter],
                              [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                              filter,
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Partial)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Mailing partially symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          KSCrashReportSinkEMail* filter = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                          filenameFmt:@"ApplePartialSymbolicatedReport-%d.txt.gz"];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStylePartiallySymbolicated],
                              [KSCrashReportFilterStringToData filter],
                              [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                              filter,
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Symbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Mailing symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          KSCrashReportSinkEMail* filter = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                          filenameFmt:@"AppleSymbolicatedReport-%d.txt.gz"];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
                              [KSCrashReportFilterStringToData filter],
                              [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                              filter,
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Side-By-Side)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Mailing side-by-side symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          KSCrashReportSinkEMail* filter = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                          filenameFmt:@"AppleSideBySideReport-%d.txt.gz"];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                              [KSCrashReportFilterStringToData filter],
                              [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
                              filter,
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style + user & system data"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Mailing side-by-side symbolicated apple reports with system and user data...");
          KSCrash* crashReporter = [KSCrash instance];
          KSCrashReportSinkEMail* filter = [KSCrashReportSinkEMail sinkWithRecipients:nil
                                                                              subject:@"Crash Reports"
                                                                          filenameFmt:@"AppleSystemUserReport-%d.txt.gz"];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashFilterSets appleFmtWithUserAndSystemData:KSAppleReportStyleSymbolicatedSideBySide
                                                                    compressed:YES],
                              filter,
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
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
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Printing standard reports...");
          KSCrash* crashReporter = [KSCrash instance];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
                              [KSCrashReportFilterDataToString filter],
                              [KSCrashReportSinkConsole filter],
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Unsymbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Printing unsymbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleUnsymbolicated],
                              [KSCrashReportSinkConsole filter],
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Partial)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Printing partially symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStylePartiallySymbolicated],
                              [KSCrashReportSinkConsole filter],
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Symbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Printing symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
                              [KSCrashReportSinkConsole filter],
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Side-By-Side)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Printing side-by-side symbolicated apple reports...");
          KSCrash* crashReporter = [KSCrash instance];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                              [KSCrashReportSinkConsole filter],
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style + user & system data"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          NSLog(@"Printing side-by-side symbolicated apple reports with system and user data...");
          KSCrash* crashReporter = [KSCrash instance];
          NSArray* filters = [NSArray arrayWithObjects:
                              [KSCrashFilterSets appleFmtWithUserAndSystemData:KSAppleReportStyleSymbolicatedSideBySide
                                                                    compressed:NO],
                              [KSCrashReportSinkConsole filter],
                              nil];
          crashReporter.sink = [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];

    return commands;
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
          KSCrash* crashReporter = [KSCrash instance];
          crashReporter.sink = [KSCrashReportSinkStandard sinkWithURL:kReportURL
                                                            onSuccess:^(NSString* response)
                                {
                                    NSLog(@"Success. Response = %@", response);
                                    [blockSelf showAlertWithTitle:@"Success" message:response];
                                    [(CommandTVC*)controller reloadTitle];
                                }];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send to Quincy"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Sending reports to Quincy...");
          KSCrash* crashReporter = [KSCrash instance];
          crashReporter.sink = [KSCrashReportSinkQuincy sinkWithURL:kQuincyReportURL
                                                          onSuccess:^(NSString* response)
                                {
                                    NSLog(@"Success. Response = %@", response);
                                    [blockSelf showAlertWithTitle:@"Success" message:response];
                                    [(CommandTVC*)controller reloadTitle];
                                }];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Send to Hockey"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          NSLog(@"Sending reports to Hockey...");
          KSCrash* crashReporter = [KSCrash instance];
          crashReporter.sink = [KSCrashReportSinkHockey sinkWithAppIdentifier:kHockeyAppID
                                                                    onSuccess:^(NSString* response)
                                {
                                    NSLog(@"Success. Response = %@", response);
                                    [blockSelf showAlertWithTitle:@"Success" message:response];
                                    [(CommandTVC*)controller reloadTitle];
                                }];
          [crashReporter sendAllReportsWithCompletion:nil];
      }]];
    
    return commands;
}

- (NSArray*) crashCommands
{
    NSMutableArray* commands = [NSMutableArray array];
    
    [commands addObject:
     [CommandEntry commandWithName:@"NSException"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher throwException];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Bad Pointer"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher dereferenceBadPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Null Pointer"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher dereferenceNullPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Corrupt Object"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher useCorruptObject];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Spin Run Loop"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher spinRunloop];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Stack Overflow"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher causeStackOverflow];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Abort"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher doAbort];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Divide By Zero"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher doDiv0];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Illegal Instruction"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher doIllegalInstruction];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deallocated Object"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
           #pragma unused(controller)
          [self.crasher accessDeallocatedObject];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deallocated Proxy"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher accessDeallocatedPtrProxy];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Corrupt Memory"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher corruptMemory];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Zombie NSException"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher zombieNSException];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Crash in Handler"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          self.crashInHandler = YES;
          [self.crasher dereferenceBadPointer];
      }]];

    [commands addObject:
     [CommandEntry commandWithName:@"Deadlock main queue"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(UIViewController* controller)
      {
          #pragma unused(controller)
          [self.crasher deadlock];
      }]];
    

    return commands;
}

@end
