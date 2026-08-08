//
//  KSCrash+UserInfo.m
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

#import "KSCrash+UserInfo.h"

#import "KSCrashMonitor_UserInfo.h"

@implementation KSCrash (UserInfo)

- (void)setUserInfoString:(NSString *)value forKey:(NSString *)key
{
    kscm_userinfo_setString(key.UTF8String, value.UTF8String);
}

- (void)setUserInfoInteger:(NSInteger)value forKey:(NSString *)key
{
    kscm_userinfo_setInt64(key.UTF8String, (int64_t)value);
}

- (void)setUserInfoUnsignedInteger:(NSUInteger)value forKey:(NSString *)key
{
    kscm_userinfo_setUInt64(key.UTF8String, (uint64_t)value);
}

- (void)setUserInfoDouble:(double)value forKey:(NSString *)key
{
    kscm_userinfo_setDouble(key.UTF8String, value);
}

- (void)setUserInfoBool:(BOOL)value forKey:(NSString *)key
{
    kscm_userinfo_setBool(key.UTF8String, (bool)value);
}

- (void)setUserInfoDate:(NSDate *)value forKey:(NSString *)key
{
    uint64_t nanos = (uint64_t)(value.timeIntervalSince1970 * 1e9);
    kscm_userinfo_setDate(key.UTF8String, nanos);
}

- (void)removeUserInfoValueForKey:(NSString *)key
{
    kscm_userinfo_removeValue(key.UTF8String);
}

@end
