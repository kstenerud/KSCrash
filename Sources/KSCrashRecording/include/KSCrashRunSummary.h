//
//  KSCrashRunSummary.h
//
//  Created by Alexander Cohen on 2026-04-19.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <Foundation/Foundation.h>

#import "KSCrashNamespace.h"
#import "KSTerminationReason.h"

NS_ASSUME_NONNULL_BEGIN

/** Kind of host process that produced a run summary. Lets the backend bucket
 *  extension / test runs separately from main-app runs so stability metrics
 *  aren't dragged by differently-shaped run patterns.
 */
typedef NS_ENUM(NSInteger, KSCrashRunSummaryHostKind) {
    KSCrashRunSummaryHostKindApp = 0,
    KSCrashRunSummaryHostKindExtension,
    KSCrashRunSummaryHostKindXCTest,
    KSCrashRunSummaryHostKindOther,
} NS_SWIFT_NAME(RunSummary.HostKind);

@class KSCrashRunSummaryOutcome;
@class KSCrashRunSummaryDurations;
@class KSCrashRunSummarySessions;
@class KSCrashRunSummaryUsers;
@class KSCrashRunSummaryApp;
@class KSCrashRunSummaryOS;
@class KSCrashRunSummaryDevice;

// ============================================================================
#pragma mark - Outcome -
// ============================================================================

NS_SWIFT_NAME(RunSummary.Outcome)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummaryOutcome : NSObject

@property(nonatomic, readonly) KSTerminationReason terminationReason;
@property(nonatomic, readonly) BOOL cleanShutdown;
@property(nonatomic, readonly) BOOL fatalReported;
@property(nonatomic, readonly) BOOL userPerceptible;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithTerminationReason:(KSTerminationReason)terminationReason
                            cleanShutdown:(BOOL)cleanShutdown
                            fatalReported:(BOOL)fatalReported
                          userPerceptible:(BOOL)userPerceptible NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - Durations -
// ============================================================================

NS_SWIFT_NAME(RunSummary.Durations)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummaryDurations : NSObject

@property(nonatomic, readonly) int64_t activeMs;
@property(nonatomic, readonly) int64_t backgroundMs;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithActiveMs:(int64_t)activeMs backgroundMs:(int64_t)backgroundMs NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - Sessions -
// ============================================================================

NS_SWIFT_NAME(RunSummary.Sessions)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummarySessions : NSObject

@property(nonatomic, readonly) NSInteger perceptibleCount;
@property(nonatomic, readonly) NSInteger imperceptibleCount;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithPerceptibleCount:(NSInteger)perceptibleCount
                      imperceptibleCount:(NSInteger)imperceptibleCount NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - UserIDs -
// ============================================================================

NS_SWIFT_NAME(RunSummary.Users)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummaryUsers : NSObject

/** Number of distinct user IDs seen during perceptible portions of the run. */
@property(nonatomic, readonly) NSInteger perceptibleCount;

/** Number of distinct user IDs seen during imperceptible portions of the run. */
@property(nonatomic, readonly) NSInteger imperceptibleCount;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithPerceptibleCount:(NSInteger)perceptibleCount
                      imperceptibleCount:(NSInteger)imperceptibleCount NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - App -
// ============================================================================

NS_SWIFT_NAME(RunSummary.App)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummaryApp : NSObject

@property(nonatomic, readonly, copy) NSString *bundleID;
@property(nonatomic, readonly, copy) NSString *version;
@property(nonatomic, readonly, copy) NSString *shortVersion;
@property(nonatomic, readonly) KSCrashRunSummaryHostKind hostKind;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithBundleID:(NSString *)bundleID
                         version:(NSString *)version
                    shortVersion:(NSString *)shortVersion
                        hostKind:(KSCrashRunSummaryHostKind)hostKind NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - OS -
// ============================================================================

NS_SWIFT_NAME(RunSummary.OS)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummaryOS : NSObject

@property(nonatomic, readonly, copy) NSString *name;
@property(nonatomic, readonly, copy) NSString *version;
@property(nonatomic, readonly, copy) NSString *build;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithName:(NSString *)name
                     version:(NSString *)version
                       build:(NSString *)build NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - Device -
// ============================================================================

NS_SWIFT_NAME(RunSummary.Device)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummaryDevice : NSObject

@property(nonatomic, readonly, copy) NSString *model;
@property(nonatomic, readonly, copy) NSString *modelFamily;
@property(nonatomic, readonly, copy) NSString *architecture;
@property(nonatomic, readonly, copy) NSString *binaryArchitecture;
@property(nonatomic, readonly) BOOL isTranslated;
@property(nonatomic, readonly) BOOL isJailbroken;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithModel:(NSString *)model
                  modelFamily:(NSString *)modelFamily
                 architecture:(NSString *)architecture
           binaryArchitecture:(NSString *)binaryArchitecture
                 isTranslated:(BOOL)isTranslated
                 isJailbroken:(BOOL)isJailbroken NS_DESIGNATED_INITIALIZER;

@end

// ============================================================================
#pragma mark - Run Summary -
// ============================================================================

/**
 * Per-run stability/telemetry ping.
 *
 * One summary describes one completed process run (previous launch from the
 * current process's perspective). Shipped separately from crash reports so
 * the backend has a denominator for stability metrics (crash-free run rate,
 * OOM rate, clean-exit rate, etc.). Crashed runs additionally ship a full
 * crash report via the existing filter/sink pipeline.
 *
 * See `project_run_summary_schema.md` for the full schema contract,
 * invariants, and clock-source semantics.
 */
NS_SWIFT_NAME(RunSummary)
__attribute__((objc_subclassing_restricted))
@interface KSCrashRunSummary : NSObject

@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly, copy) NSString *sdkVersion;
@property(nonatomic, readonly, copy) NSString *runID;
@property(nonatomic, readonly, copy) NSString *deviceID;

/** The user ID active at termination (the one "blamed" for a crash if one
 *  occurred). Nil if no user was set or the user was logged out at end.
 */
@property(nonatomic, readonly, copy, nullable) NSString *userID;

/** Counts of distinct user IDs seen during the run, split by perceptibility.
 *  The IDs themselves are not stored; see `KSCrash.setUserID:` documentation.
 */
@property(nonatomic, readonly, strong) KSCrashRunSummaryUsers *users;

/** Unix epoch milliseconds (wall clock). */
@property(nonatomic, readonly) int64_t startedAtMs;

/** Unix epoch milliseconds (wall clock). */
@property(nonatomic, readonly) int64_t endedAtMs;

@property(nonatomic, readonly, strong) KSCrashRunSummaryOutcome *outcome;
@property(nonatomic, readonly, strong) KSCrashRunSummaryDurations *durations;
@property(nonatomic, readonly, strong) KSCrashRunSummarySessions *sessions;
@property(nonatomic, readonly, strong) KSCrashRunSummaryApp *app;
@property(nonatomic, readonly, strong) KSCrashRunSummaryOS *os;
@property(nonatomic, readonly, strong) KSCrashRunSummaryDevice *device;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithSchemaVersion:(NSInteger)schemaVersion
                           sdkVersion:(NSString *)sdkVersion
                                runID:(NSString *)runID
                             deviceID:(NSString *)deviceID
                               userID:(nullable NSString *)userID
                                users:(KSCrashRunSummaryUsers *)users
                          startedAtMs:(int64_t)startedAtMs
                            endedAtMs:(int64_t)endedAtMs
                              outcome:(KSCrashRunSummaryOutcome *)outcome
                            durations:(KSCrashRunSummaryDurations *)durations
                             sessions:(KSCrashRunSummarySessions *)sessions
                                  app:(KSCrashRunSummaryApp *)app
                                   os:(KSCrashRunSummaryOS *)os
                               device:(KSCrashRunSummaryDevice *)device NS_DESIGNATED_INITIALIZER;

/** Encode this summary as JSON using the wire schema documented in
 *  project_run_summary_schema.md. Returns nil on encoding failure.
 */
- (nullable NSData *)jsonData;

@end

NS_ASSUME_NONNULL_END
