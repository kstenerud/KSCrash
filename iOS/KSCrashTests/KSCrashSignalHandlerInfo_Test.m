//
//  KSCrashSignalHandlerInfo_Test.m
//  KSCrashTests
//
//  Created by Jonathon Copeland on 8/30/22.
//  Copyright © 2022 Karl Stenerud. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <KSCrash/KSCrash.h>
#import <KSCrash/KSSignalInfo.h>

@interface KSCrashSignalHandlerInfo_Test : XCTestCase

@end

@implementation KSCrashSignalHandlerInfo_Test

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

// these tests will only work if a debugger is not attached.

- (void)testGetInstalledSignalInformationWhileKSCrashInstalled {
    
    //given
    
    KSCrash* ksc = [KSCrash sharedInstance];
    [ksc install];
    
    int numSignals = kssignal_numFatalSignals();
    
    //when
    NSArray* signalInfo = [ksc getInstalledSignalInformation];

    //then
    XCTAssertTrue(numSignals == (int)signalInfo.count, @"Returned Signal Info Should Match Number of possible Monitored Signals");
    
    for(NSDictionary* dict in signalInfo)
    {
        NSNumber* v = dict[@"SignalHandlerIsEmbrace"];
        XCTAssertTrue(v.boolValue, @"Should all be the kscrash signal handler");
    }
}

- (void)testGetInstalledSignalInformationWhileKSCrashNotInstalled {
    
    //given
    
    KSCrash* ksc = [KSCrash sharedInstance];
    
    int numSignals = kssignal_numFatalSignals();
    
    //when
    NSArray* signalInfo = [ksc getInstalledSignalInformation];

    //then
    XCTAssertFalse(numSignals == signalInfo.count, @"Returned Signal Info Should Not Work if KSCrash is not installed");
}

@end
