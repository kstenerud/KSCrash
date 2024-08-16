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

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, KSCrashAppMemoryTrackerChangeType) {
    KSCrashAppMemoryTrackerChangeTypeNone = 0,
    KSCrashAppMemoryTrackerChangeTypeLevel = 1 << 0,
    KSCrashAppMemoryTrackerChangeTypePressure = 1 << 1,
    KSCrashAppMemoryTrackerChangeTypeFootprint = 1 << 2,
} NS_SWIFT_NAME(AppMemoryTrackerChangeType);

@protocol KSCrashAppMemoryTrackerDelegate;

NS_SWIFT_NAME(AppMemoryTracker)
@interface KSCrashAppMemoryTracker : NSObject

@property(atomic, readonly) KSCrashAppMemoryState pressure;
@property(atomic, readonly) KSCrashAppMemoryState level;

@property(nonatomic, weak) id<KSCrashAppMemoryTrackerDelegate> delegate;

@property(nonatomic, readonly, nullable) KSCrashAppMemory *currentAppMemory;

- (void)start;
- (void)stop;

@end

NS_SWIFT_NAME(AppMemoryTrackerDelegate)
@protocol KSCrashAppMemoryTrackerDelegate <NSObject>

- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker
                  memory:(KSCrashAppMemory *)memory
                 changed:(KSCrashAppMemoryTrackerChangeType)changes;

@end

NS_ASSUME_NONNULL_END
