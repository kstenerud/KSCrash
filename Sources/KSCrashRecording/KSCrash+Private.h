//
//  KSCrash+Private.h
//
//
//  Created by Gleb Linnik on 11.06.2024.
//

#ifndef KSCrash_Private_h
#define KSCrash_Private_h

#import "KSCrash.h"

@interface KSCrash()

@property (nonatomic, readwrite, assign) NSUncaughtExceptionHandler *uncaughtExceptionHandler;
@property (nonatomic, readwrite, assign) NSUncaughtExceptionHandler *currentSnapshotUserReportedExceptionHandler;

@end

#endif /* KSCrash_Private_h */
