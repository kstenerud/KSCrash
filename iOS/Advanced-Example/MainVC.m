//
//  MainVC.m
//  Advanced-Example
//

#import "MainVC.h"

#import <KSCrash/KSCrash.h>
#import "AppDelegate.h"
#import <KSCrash/KSCrashInstallation.h>

/**
 * Some sensitive info that should not be printed out at any time.
 *
 * If you have Objective-C introspection turned on, it would normally
 * introspect this class, unless you add it to the list of
 * "do not introspect classes" in KSCrash. We do precisely this in 
 * -[AppDelegate configureAdvancedSettings]
 */
@interface SensitiveInfo: NSObject

@property(nonatomic, readwrite, strong) NSString* password;

@end

@implementation SensitiveInfo

@end



@interface MainVC ()

@property(nonatomic, readwrite, strong) SensitiveInfo* info;

@end

@implementation MainVC

- (id) initWithCoder:(NSCoder *)aDecoder
{
    if((self = [super initWithCoder:aDecoder]))
    {
        // This info could be leaked during introspection unless you tell KSCrash to ignore it.
        // See -[AppDelegate configureAdvancedSettings] for more info.
        self.info = [SensitiveInfo new];
        self.info.password = @"it's a secret!";
    }
    return self;
}

- (void) viewDidLoad {
    [super viewDidLoad];

    UIButton * reportExceptionBtn = [[UIButton alloc] initWithFrame:CGRectMake(60, 100, 200, 50)];
    reportExceptionBtn.backgroundColor = [UIColor orangeColor];
    [reportExceptionBtn setTitle:@"Report Exception" forState:UIControlStateNormal];
    [reportExceptionBtn setTitle:@"Report Exception" forState:UIControlStateHighlighted];
    [reportExceptionBtn addTarget:self action:@selector(onReportedCrash:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reportExceptionBtn];

    UIButton * reportUncaughtExceptionBtn = [[UIButton alloc] initWithFrame:CGRectMake(60, 200, 200, 50)];
    reportUncaughtExceptionBtn.backgroundColor = [UIColor greenColor];
    [reportUncaughtExceptionBtn setTitle:@"Uncaught Exception" forState:UIControlStateNormal];
    [reportUncaughtExceptionBtn setTitle:@"Uncaught Exception" forState:UIControlStateHighlighted];
    [reportUncaughtExceptionBtn addTarget:self action:@selector(onCrash:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reportUncaughtExceptionBtn];
}

- (void) onReportedCrash:(id)sender {
    NSException* ex = [NSException exceptionWithName:@"testing exception name" reason:@"testing exception reason" userInfo:@{@"testing exception key":@"testing exception value"}];
    [KSCrash sharedInstance].currentSnapshotUserReportedExceptionHandler(ex);
    [KSCrash sharedInstance].monitoring = KSCrashMonitorTypeProductionSafe;
    [self sendAllExceptions];
}

- (void) sendAllExceptions {
    AppDelegate* appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;

    [appDelegate.crashInstallation sendAllReportsWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
        if(completed) {
            NSLog(@"\n****Sent %lu reports", (unsigned long)[filteredReports count]);
            NSLog(@"\n%@", filteredReports);
            //        [[KSCrash sharedInstance] deleteAllReports];
        } else {
            NSLog(@"Failed to send reports: %@", error);
        }
    }];
}

- (IBAction) onCrash:(__unused id) sender
{
    char* invalid = (char*)-1;
    *invalid = 1;
}

@end
