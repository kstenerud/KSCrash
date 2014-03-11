//
//  KSCrashInstallationCustomService.h
//  KSCrash
//
//  Created by David Velarde on 3/11/14.
//  Copyright (c) 2014 Karl Stenerud. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KSCrashInstallation.h"
#import "KSCrashReportWriter.h"

@interface KSCrashInstallationCustomService : KSCrashInstallation

#pragma mark - Basic properties (nil by default) -
// ======================================================================

// The values of these properties will be written to the next crash report.

@property(nonatomic,readwrite,retain) NSString* userID;
@property(nonatomic,readwrite,retain) NSString* contactEmail;
@property(nonatomic,readwrite,retain) NSString* crashDescription;


// ======================================================================
#pragma mark - Advanced settings (normally you don't need to change these) -
// ======================================================================

// The above properties will be written to the user section report using the
// following keys.

@property(nonatomic,readwrite,retain) NSString* userIDKey;
@property(nonatomic,readwrite,retain) NSString* contactEmailKey;
@property(nonatomic,readwrite,retain) NSString* crashDescriptionKey;

/** Data stored under these keys will be appended to the description
 * (in JSON format) before sending to Quincy/Hockey.
 */
@property(nonatomic,readwrite,retain) NSArray* extraDescriptionKeys;

/** If YES, wait until the host becomes reachable before trying to send.
 * If NO, it will attempt to send right away, and either succeed or fail.
 *
 * Default: YES
 */
@property(nonatomic,readwrite,assign) BOOL waitUntilReachable;

@property(nonatomic, readwrite, retain) NSURL* url;


+ (KSCrashInstallationCustomService*) sharedInstance;

@end
