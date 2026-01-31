//
//  KSCrashMonitorPlugin.h
//
//  Created by Alex Cohen on 2026-01-31.
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
#import "KSCrashMonitorAPI.h"

NS_ASSUME_NONNULL_BEGIN

/** A wrapper around a C `KSCrashMonitorAPI` for use in Objective-C configuration.
 *
 * Use this class to pass plugin monitors to `KSCrashConfiguration.plugins`.
 * The underlying `KSCrashMonitorAPI` pointer must remain valid for the lifetime
 * of the plugin (typically a static or global).
 */
NS_SWIFT_NAME(MonitorPlugin)
@interface KSCrashMonitorPlugin : NSObject

/** The underlying C monitor API. */
@property(nonatomic, readonly) KSCrashMonitorAPI *api;

/** Creates a plugin wrapping the given monitor API.
 *
 * @param api A pointer to a `KSCrashMonitorAPI` struct. Must remain valid
 *            for the lifetime of this object.
 */
- (instancetype)initWithAPI:(KSCrashMonitorAPI *)api NS_DESIGNATED_INITIALIZER;
+ (instancetype)pluginWithAPI:(KSCrashMonitorAPI *)api;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
