//
//  KSCrash+UserInfo.h
//
//  Created by Alexander Cohen on 2026-03-01.
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

#import "KSCrash.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSCrash (UserInfo)

/** Set a string value for the given key in the crash report's user section.
 *  Passing nil for value removes the key. Usable before or after install.
 */
- (void)setUserInfoString:(nullable NSString *)value forKey:(NSString *)key NS_SWIFT_NAME(setUserInfo(_:forKey:));

/** Set an integer value for the given key. */
- (void)setUserInfoInteger:(NSInteger)value forKey:(NSString *)key NS_SWIFT_NAME(setUserInfo(_:forKey:));

/** Set an unsigned integer value for the given key. */
- (void)setUserInfoUnsignedInteger:(NSUInteger)value forKey:(NSString *)key NS_SWIFT_NAME(setUserInfo(_:forKey:));

/** Set a double value for the given key. */
- (void)setUserInfoDouble:(double)value forKey:(NSString *)key NS_SWIFT_NAME(setUserInfo(_:forKey:));

/** Set a boolean value for the given key. */
- (void)setUserInfoBool:(BOOL)value forKey:(NSString *)key NS_SWIFT_NAME(setUserInfo(_:forKey:));

/** Set a date value for the given key. */
- (void)setUserInfoDate:(NSDate *)value forKey:(NSString *)key NS_SWIFT_NAME(setUserInfo(_:forKey:));

/** Remove the value for the given key. */
- (void)removeUserInfoValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
