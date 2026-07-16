//
//  KSCrashJSONNumber.h
//
//  Created by Alexander Cohen on 2026-07-15.
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

#ifndef HDR_KSCrashJSONNumber_h
#define HDR_KSCrashJSONNumber_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Shared predicates for validating already-decoded JSON scalar values. Both the
// run-summary decoder and the session-log reader need to tell a genuine JSON
// integer/boolean apart from a look-alike, and must agree on where the cutoffs
// are; keeping one definition prevents the two readers from drifting.

// NSJSONSerialization represents JSON booleans as __NSCFBoolean, a subclass of
// NSNumber — so `isKindOfClass:[NSNumber class]` accepts booleans as numbers and
// vice versa. Disambiguate via CFBooleanGetTypeID so {"schema_version": true} or
// {"clean_shutdown": 2} are rejected as malformed instead of silently coerced.
static inline BOOL ksjson_isBoolean(id _Nullable value)
{
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

// True only for NSNumber values whose backing type is integral and whose
// magnitude fits int64_t. The schema uses integer fields for every scalar
// (counts, ms timestamps, schema_version), so a fractional value like
// {"started_at_ms": 1.5e9} is malformed, and an out-of-range value like
// {"started_at_ms": 9223372036854775808} must be rejected rather than wrapped
// via -longLongValue.
static inline BOOL ksjson_isInteger(id _Nullable value)
{
    if (![value isKindOfClass:[NSNumber class]] || ksjson_isBoolean(value)) {
        return NO;
    }
    const char *type = [(NSNumber *)value objCType];
    // Float/double carry 'f' / 'd'; every integral type code is something else
    // (c, i, s, l, q, C, I, S, L, Q). Bool ('B') is already filtered.
    if (type == NULL || type[0] == 'f' || type[0] == 'd') {
        return NO;
    }
    NSNumber *number = value;
    return [number compare:@(INT64_MIN)] != NSOrderedAscending && [number compare:@(INT64_MAX)] != NSOrderedDescending;
}

NS_ASSUME_NONNULL_END

#endif  // HDR_KSCrashJSONNumber_h
