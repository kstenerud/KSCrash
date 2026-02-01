//
//  KSCrash+Hang.m
//
//  Created by Alexander Cohen on 2026-01-28.
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

#import "KSCrash+Hang.h"

/** ObjC wrapper that ties a block observer to the C observer API.
 *  Calls kshang_removeHangObserver on dealloc for automatic cleanup.
 */
@interface KSHangBlockObserver : NSObject {
   @package
    KSHangObserverToken _token;
    KSHangObserverBlock _block;
}
@end

static void hangObserverTrampoline(KSHangChangeType change, uint64_t start, uint64_t end, void *context)
{
    KSHangBlockObserver *obj = (__bridge KSHangBlockObserver *)context;
    if (obj->_block) {
        obj->_block(change, start, end);
    }
}

@implementation KSHangBlockObserver

- (instancetype)initWithBlock:(KSHangObserverBlock)block
{
    if ((self = [super init])) {
        _block = [block copy];
        _token = kshang_addHangObserver(hangObserverTrampoline, (__bridge void *)self);
        if (_token == KSHangObserverTokenNotFound) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    if (_token != KSHangObserverTokenNotFound) {
        kshang_removeHangObserver(_token);
    }
}

@end

@implementation KSCrash (Hang)

- (id)addHangObserver:(KSHangObserverBlock)observer
{
    return [[KSHangBlockObserver alloc] initWithBlock:observer];
}

@end
