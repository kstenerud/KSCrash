//
//  Configuration.h
//  CrashTester
//

#ifndef CrashTester_Configuration_h
#define CrashTester_Configuration_h


// Takanshi error reporting server.
// (A Python open source project. It runs on Google App Engine)
// https://github.com/kelp404/Victory
// "victory-demo.appspot.com" is your server domain
// "cf22ec3f-1703-476c-9a72-57d72bdebaa1" is your application key
#define kVictoryURL [NSURL URLWithString:@"https://victory-demo.appspot.com/api/v1/crash/cf22ec3f-1703-476c-9a72-57d72bdebaa1"]

// Hockey configuration. Please get your own app ID. This one is for internal testing!
//#define kHockeyAppID @"7f74dc8aae8bf6effd35b48e32a08298" // Don't use this ID!
#define kHockeyAppID @"PLEASE_GET_YOUR_OWN_APP_ID_AT_HOCKEYAPP.NET"

// Quincy configuration. Reconfigure to point to your Quincy app.
#define kQuincyReportURL [NSURL URLWithString:@"http://localhost:8888/quincy/crash_v200.php"]

// JSON API configuration.
#define kReportHost @"localhost"
//#define kReportHost @"192.168.1.214"
#define kReportURL [NSURL URLWithString:@"http://" kReportHost @":8000/api/crashes/"]


// Set to true to write all log entries to Library/Caches/KSCrashReports/Crash-Tester/Crash-Tester-CrashLog.txt
#define kRedirectConsoleLogToDefaultFile false


#endif
