//
//  AppDelegate+UI.m
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import "AppDelegate+UI.h"
#import "LoadableCategory.h"
#import "CommandTVC.h"
#import "Crasher.h"
#import "CrashTesterCommands.h"

#import <KSCrash/KSCrash.h>
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
#import <CrashLib/CrashLib.h>
#import <CrashLib/CRLFramelessDWARF.h>
#import <objc/runtime.h>

MAKE_CATEGORIES_LOADABLE(AppDelegate_UI)


@implementation AppDelegate (UI)

#pragma mark Public Methods

- (UIViewController*) createRootViewController
{
    CommandTVC* cmdController = [self commandTVCWithCommands:[self topLevelCommands]];
    cmdController.getTitleBlock = ^NSString* (__unused UIViewController* controller)
    {
        return [NSString stringWithFormat:@"Crash Tester: %@", [CrashTesterCommands reportCountString]];
    };
    return [[UINavigationController alloc] initWithRootViewController:cmdController];
}


#pragma mark Utility

- (CommandTVC*) commandTVCWithCommands:(NSArray*) commands
{
    CommandTVC* cmdController = [[CommandTVC alloc] initWithStyle:UITableViewStylePlain];
    [cmdController.commands addObjectsFromArray:commands];
    [self setBackButton:cmdController];
    return cmdController;
}

- (void) setBackButton:(UIViewController*) controller
{
    controller.navigationItem.backBarButtonItem =
    [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                     style:UIBarButtonItemStyleDone
                                    target:nil
                                    action:nil];
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
              return [NSString stringWithFormat:@"Manage (%@)", [CrashTesterCommands reportCountString]];
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
    
    
    [commands addObject:
     [CommandEntry commandWithName:@"CrashProbe Crashes"
                     accessoryType:UITableViewCellAccessoryDisclosureIndicator
                             block:^(UIViewController* controller)
      {
          CommandTVC* cmdController = [self commandTVCWithCommands:[blockSelf crash2Commands]];
          cmdController.title = @"CrashProbe Crashes";
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
              return [NSString stringWithFormat:@"Print (%@)", [CrashTesterCommands reportCountString]];
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
              return [NSString stringWithFormat:@"Send (%@)", [CrashTesterCommands reportCountString]];
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
              return [NSString stringWithFormat:@"Mail (%@)", [CrashTesterCommands reportCountString]];
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
          [CrashTesterCommands mailStandard];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Unsymbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands mailUnsymbolicated];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Partial)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands mailPartiallySymbolicated];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Symbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands mailSymbolicated];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Side-By-Side)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands mailSideBySide];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style + user & system data"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands mailSideBySideWithUserAndSystemData];
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
          [CrashTesterCommands printStandard];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Unsymbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands printUnsymbolicated];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Partial)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands printPartiallySymbolicated];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Symbolicated)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands printSymbolicated];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style (Side-By-Side)"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands printSideBySide];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Apple Style + user & system data"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [CrashTesterCommands printSideBySideWithUserAndSystemData];
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
        [CrashTesterCommands showAlertWithTitle:@"Success" message:@"Sent %d reports", [reports count]];
        [(CommandTVC*)controller reloadTitle];
    }
    else
    {
        NSLog(@"Failed to send reports: %@", error);
        [CrashTesterCommands showAlertWithTitle:@"Failed" message:@"Failed to send reports", [error localizedDescription]];
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
          [CrashTesterCommands sendToKSWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
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
          [CrashTesterCommands sendToQuincyWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
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
          [CrashTesterCommands sendToHockeyWithCompletion:^(NSArray* filteredReports, BOOL completed, NSError* error)
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
          [CrashTesterCommands sendToVictoryWithUserName:[[UIDevice currentDevice] name]
                                              completion:^(NSArray* filteredReports, BOOL completed, NSError* error)
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
          [self.crasher throwUncaughtNSException];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"C++ Exception"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher throwUncaughtCPPException];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Bad Pointer"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher dereferenceBadPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Null Pointer"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher dereferenceNullPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Corrupt Object"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher useCorruptObject];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Spin Run Loop"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher spinRunloop];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Stack Overflow"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher causeStackOverflow];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Abort"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher doAbort];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Divide By Zero"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher doDiv0];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Illegal Instruction"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher doIllegalInstruction];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Deallocated Object"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher accessDeallocatedObject];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Deallocated Proxy"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher accessDeallocatedPtrProxy];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Corrupt Memory"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher corruptMemory];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Zombie NSException"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher zombieNSException];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Crash in Handler"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          blockSelf.crashInHandler = YES;
          [self.crasher dereferenceBadPointer];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Deadlock main queue"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher deadlock];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"Deadlock pthread"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher pthreadAPICrash];
      }]];
    
    [commands addObject:
     [CommandEntry commandWithName:@"User Defined (soft) Crash"
                     accessoryType:UITableViewCellAccessoryNone
                             block:^(__unused UIViewController* controller)
      {
          [self.crasher userDefinedCrash];
      }]];
    
    
    return commands;
}

#define NEW_CRASH(TEXT, CLASS) \
[commands addObject: \
[CommandEntry commandWithName:TEXT \
accessoryType:UITableViewCellAccessoryNone \
block:^(__unused UIViewController* controller) \
{ \
[[CLASS new] crash]; \
}]]

- (CRLCrash*) getSwiftCrashObject
{
    unsigned int classCount = 0;
    Class* classes = objc_copyClassList(&classCount);
    Class foundClass = nil;
    
    for(unsigned int i=0; i < classCount; i++)
    {
        Class testClass = classes[i];
        if (testClass != NULL &&
            class_getSuperclass(testClass) == [CRLCrash class] &&
            strstr(class_getName(testClass), "CRLCrashSwift") != NULL)
        {
            foundClass = testClass;
            break;
        }
    }
    free(classes);
    return [foundClass new];
}

- (NSArray*) crash2Commands
{
    NSMutableArray* commands = [NSMutableArray array];
    
    NEW_CRASH(@"Async Safe Thread", CRLCrashAsyncSafeThread);
    NEW_CRASH(@"CXX Exception", CRLCrashCXXException);
    NEW_CRASH(@"ObjC Exception", CRLCrashObjCException);
    NEW_CRASH(@"NSLog", CRLCrashNSLog);
    NEW_CRASH(@"ObjC Msg Send", CRLCrashObjCMsgSend);
    NEW_CRASH(@"Released Object", CRLCrashReleasedObject);
    NEW_CRASH(@"RO Page", CRLCrashROPage);
    NEW_CRASH(@"Privileged Instruction", CRLCrashPrivInst);
    NEW_CRASH(@"Undefined Instruction", CRLCrashUndefInst);
    NEW_CRASH(@"NULL", CRLCrashNULL);
    NEW_CRASH(@"Garbage", CRLCrashGarbage);
    NEW_CRASH(@"NX Page", CRLCrashNXPage);
    NEW_CRASH(@"Stack Guard", CRLCrashStackGuard);
    NEW_CRASH(@"Trap", CRLCrashTrap);
    NEW_CRASH(@"Abort", CRLCrashAbort);
    NEW_CRASH(@"Corrupt Malloc", CRLCrashCorruptMalloc);
    NEW_CRASH(@"Corrupt ObjC", CRLCrashCorruptObjC);
    NEW_CRASH(@"Overwrite Link Register", CRLCrashOverwriteLinkRegister);
    NEW_CRASH(@"Smash Stack Bottom", CRLCrashSmashStackBottom);
    NEW_CRASH(@"Smash Stack Top", CRLCrashSmashStackTop);
    NEW_CRASH(@"Frameless Dwarf", CRLFramelessDWARF);

    [commands addObject: \
     [CommandEntry commandWithName:@"Swift" \
                     accessoryType:UITableViewCellAccessoryNone \
                             block:^(__unused UIViewController* controller) \
    { \
        [[self getSwiftCrashObject] crash]; \
    }]];

    
    return commands;
}

@end
