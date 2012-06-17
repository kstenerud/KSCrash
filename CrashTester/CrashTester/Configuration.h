//
//  Configuration.h
//  CrashTester
//

#ifndef CrashTester_Configuration_h
#define CrashTester_Configuration_h


// Hockey configuration. Please get your own app ID. This one is for internal testing!
//#define kHockeyAppID @"7f74dc8aae8bf6effd35b48e32a08298" // Don't use this ID!
#define kHockeyAppID @"GET AN APP ID AT HOCKEYAPP.NET"

// Quincy configuration. Reconfigure to point to your Quincy app.
#define kQuincyReportURL [NSURL URLWithString:@"http://localhost/~kstenerud/quincy/crash_v200.php"]

// JSON API configuration.
#define kReportHost @"localhost"
//#define kReportHost @"192.168.1.214"
#define kReportURL [NSURL URLWithString:@"http://" kReportHost @":8000/api/crashes/"]


#endif
