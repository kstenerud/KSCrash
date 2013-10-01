//
//  Crasher.h
//
//  Created by Karl Stenerud on 2012-01-28.
//

#import <Foundation/Foundation.h>

@interface Crasher : NSObject

- (void) throwUncaughtNSException;

- (void) dereferenceBadPointer;

- (void) dereferenceNullPointer;

- (void) useCorruptObject;

- (void) spinRunloop;

- (void) causeStackOverflow;

- (void) doAbort;

- (void) doDiv0;

- (void) doIllegalInstruction;

- (void) accessDeallocatedObject;

- (void) accessDeallocatedPtrProxy;

- (void) zombieNSException;

- (void) corruptMemory;

- (void) deadlock;

- (void) pthreadAPICrash;

- (void) userDefinedCrash;

- (void) throwUncaughtCPPException;

@end
