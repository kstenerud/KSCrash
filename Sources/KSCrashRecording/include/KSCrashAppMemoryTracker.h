//
//  KSCrashAppMemoryTracker.h
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
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

#import "KSCrashAppMemory.h"
#include "KSCrashNamespace.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, KSCrashAppMemoryTrackerChangeType) {
    KSCrashAppMemoryTrackerChangeTypeNone = 0,
    KSCrashAppMemoryTrackerChangeTypeLevel = 1 << 0,
    KSCrashAppMemoryTrackerChangeTypePressure = 1 << 1,
    KSCrashAppMemoryTrackerChangeTypeFootprint = 1 << 2,
} NS_SWIFT_NAME(AppMemoryTrackerChangeType);

typedef void (^KSCrashAppMemoryTrackerObserverBlock)(KSCrashAppMemory *memory,
                                                     KSCrashAppMemoryTrackerChangeType changes)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

@protocol KSCrashAppMemoryTrackerDelegate;
@protocol KSCrashAppMemoryTrackerObserving;

NS_SWIFT_NAME(AppMemoryTracker)
@interface KSCrashAppMemoryTracker : NSObject

/**
 * The shared tracker. Use this unless you absolutely need your own tracker,
 * at which point you can simply allocate your own.
 */
@property(class, atomic, readonly) KSCrashAppMemoryTracker *sharedInstance NS_SWIFT_NAME(shared);

@property(atomic, readonly) KSCrashAppMemoryState pressure;
@property(atomic, readonly) KSCrashAppMemoryState level;

@property(nonatomic, readonly, nullable) KSCrashAppMemory *currentAppMemory;

/**
 * Adds an observer that implements the _KSCrashAppMemoryTrackerObserving_ protocol.
 * You do not need to remove the observer as it is held weakly.
 */
- (void)addObserver:(id<KSCrashAppMemoryTrackerObserving>)observer;

/**
 * Adds a block based observer.
 *
 *@return An object you must hold on to in order to remove the observation at a later point.
 */
- (id<KSCrashAppMemoryTrackerObserving>)addObserverWithBlock:(KSCrashAppMemoryTrackerObserverBlock)block;

/** Removes an observer */
- (void)removeObserver:(id<KSCrashAppMemoryTrackerObserving>)observer;

/**
 * Start/Stop
 *
 * WARNING: Don't call these on the shared tracker.
 */
- (void)start;
- (void)stop;

/**
 Deprecated
 */
@property(nonatomic, weak) id<KSCrashAppMemoryTrackerDelegate> delegate DEPRECATED_ATTRIBUTE;

@end

/** Implement this and add yourself to a tracker to observer transitions */
NS_SWIFT_NAME(AppMemoryTrackerObserving)
@protocol KSCrashAppMemoryTrackerObserving <NSObject>
- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker
                  memory:(KSCrashAppMemory *)memory
                 changed:(KSCrashAppMemoryTrackerChangeType)changes;
@end

/** Deprecated delegate */
NS_SWIFT_NAME(AppMemoryTrackerDelegate)
@protocol KSCrashAppMemoryTrackerDelegate <NSObject>

- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker
                  memory:(KSCrashAppMemory *)memory
                 changed:(KSCrashAppMemoryTrackerChangeType)changes;

@end

NS_ASSUME_NONNULL_END
