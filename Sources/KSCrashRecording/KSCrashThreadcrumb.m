//
//  KSCrashThreadcrumb.m
//
//  Created by Alexander Cohen on 2026-02-03.
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
// Inspired by:
// - Embrace EMBThreadcrumb: https://github.com/embrace-io/embrace-apple-sdk
// - Naftaly Threadcrumb: https://github.com/naftaly/Threadcrumb
//

#import "KSCrashThreadcrumb.h"

#import <dispatch/dispatch.h>
#import <pthread.h>

#import <stdatomic.h>
#import <stdio.h>
#import <string.h>

NSInteger const KSCrashThreadcrumbMaximumMessageLength = 512;

@interface KSCrashThreadcrumb () {
   @public
    char *_data;        // Message buffer, allocated to KSCrashThreadcrumbMaximumMessageLength+1
    char *_identifier;  // Thread name

    dispatch_semaphore_t _semaphore;  // Used to start work and park thread
    pthread_t _thread;
    BOOL _threadCreationFailed;
    NSLock *_lock;

    NSUInteger _index;                     // Current position in _data
    NSUInteger _messageLength;             // Length of sanitized message (set in log:)
    dispatch_semaphore_t _stackSemaphore;  // Completion signal per log
    NSArray<NSNumber *> *_stackAddresses;  // Captured, pruned stack trace
    atomic_bool _stopped;
}
@end

// Prevent tail-call optimization so each function appears as a distinct frame.
#define KSCRASH_KEEP_FRAME __attribute__((disable_tail_calls))

// Prevent inlining to preserve distinct stack frames.
#define KSCRASH_NOINLINE __attribute__((noinline))

// Extra insurance against tail-call optimization.
#define KSCRASH_THWART_TAIL_CALL __asm__ __volatile__("");

typedef void (*kscrash_crumb_func_t)(KSCrashThreadcrumb *self);

static kscrash_crumb_func_t kscrash_crumb_lookup(char c);

// Terminal handler: capture stack, signal completion, park thread.
static KSCRASH_NOINLINE void __kscrash_threadcrumb_end__(KSCrashThreadcrumb *self) KSCRASH_KEEP_FRAME
{
    // Take exactly _messageLength frames after the current frame (index 0).
    // Using the known message length avoids hardcoded tail-frame counts that
    // break under sanitizers or across OS versions.
    NSArray<NSNumber *> *stack = [NSThread.callStackReturnAddresses copy];
    NSUInteger count = stack.count;
    NSUInteger messageLength = self->_messageLength;
    if (count > 1 && messageLength > 0) {
        NSUInteger length = MIN(messageLength, count - 1);
        self->_stackAddresses = [[stack subarrayWithRange:NSMakeRange(1, length)] copy];
    } else {
        self->_stackAddresses = @[];
    }

    // Signal completion.
    dispatch_semaphore_signal(self->_stackSemaphore);

    // Park until next log or dealloc.
    dispatch_semaphore_wait(self->_semaphore, DISPATCH_TIME_FOREVER);

    KSCRASH_THWART_TAIL_CALL
}

#define CALL_NEXT_OR_END                                                         \
    kscrash_crumb_func_t func = kscrash_crumb_lookup(self->_data[self->_index]); \
    self->_index++;                                                              \
    if (func) {                                                                  \
        func(self);                                                              \
    } else {                                                                     \
        __kscrash_threadcrumb_end__(self);                                       \
    }

#define KSCRASH_REG(c)                                                                           \
    static KSCRASH_NOINLINE void __kscrash__##c##__(KSCrashThreadcrumb *self) KSCRASH_KEEP_FRAME \
    {                                                                                            \
        if (self->_data[self->_index] == 0) {                                                    \
            __kscrash_threadcrumb_end__(self);                                                   \
            return;                                                                              \
        }                                                                                        \
        CALL_NEXT_OR_END                                                                         \
        KSCRASH_THWART_TAIL_CALL                                                                 \
    }

// Generate one function per allowed character.
// clang-format off
KSCRASH_REG(A) KSCRASH_REG(B) KSCRASH_REG(C) KSCRASH_REG(D) KSCRASH_REG(E) KSCRASH_REG(F)
KSCRASH_REG(G) KSCRASH_REG(H) KSCRASH_REG(I) KSCRASH_REG(J) KSCRASH_REG(K) KSCRASH_REG(L)
KSCRASH_REG(M) KSCRASH_REG(N) KSCRASH_REG(O) KSCRASH_REG(P) KSCRASH_REG(Q) KSCRASH_REG(R)
KSCRASH_REG(S) KSCRASH_REG(T) KSCRASH_REG(U) KSCRASH_REG(V) KSCRASH_REG(W) KSCRASH_REG(X)
KSCRASH_REG(Y) KSCRASH_REG(Z) KSCRASH_REG(_)
KSCRASH_REG(a) KSCRASH_REG(b) KSCRASH_REG(c) KSCRASH_REG(d) KSCRASH_REG(e) KSCRASH_REG(f)
KSCRASH_REG(g) KSCRASH_REG(h) KSCRASH_REG(i) KSCRASH_REG(j) KSCRASH_REG(k) KSCRASH_REG(l)
KSCRASH_REG(m) KSCRASH_REG(n) KSCRASH_REG(o) KSCRASH_REG(p) KSCRASH_REG(q) KSCRASH_REG(r)
KSCRASH_REG(s) KSCRASH_REG(t) KSCRASH_REG(u) KSCRASH_REG(v) KSCRASH_REG(w) KSCRASH_REG(x)
KSCRASH_REG(y) KSCRASH_REG(z)
KSCRASH_REG(0) KSCRASH_REG(1) KSCRASH_REG(2) KSCRASH_REG(3) KSCRASH_REG(4)
KSCRASH_REG(5) KSCRASH_REG(6) KSCRASH_REG(7) KSCRASH_REG(8) KSCRASH_REG(9)
// clang-format on

#undef KSCRASH_REG

    // Lookup table entry.
    typedef struct {
    kscrash_crumb_func_t func;
    char c;
} KSCrashThreadcrumbEntry;

#define KSCRASH_ENTRY(c) { (void *)&__kscrash__##c##__, #c[0] },

// clang-format off
static KSCrashThreadcrumbEntry gKSCrashThreadcrumbTable[] = {
    KSCRASH_ENTRY(A) KSCRASH_ENTRY(B) KSCRASH_ENTRY(C) KSCRASH_ENTRY(D) KSCRASH_ENTRY(E) KSCRASH_ENTRY(F)
    KSCRASH_ENTRY(G) KSCRASH_ENTRY(H) KSCRASH_ENTRY(I) KSCRASH_ENTRY(J) KSCRASH_ENTRY(K) KSCRASH_ENTRY(L)
    KSCRASH_ENTRY(M) KSCRASH_ENTRY(N) KSCRASH_ENTRY(O) KSCRASH_ENTRY(P) KSCRASH_ENTRY(Q) KSCRASH_ENTRY(R)
    KSCRASH_ENTRY(S) KSCRASH_ENTRY(T) KSCRASH_ENTRY(U) KSCRASH_ENTRY(V) KSCRASH_ENTRY(W) KSCRASH_ENTRY(X)
    KSCRASH_ENTRY(Y) KSCRASH_ENTRY(Z) KSCRASH_ENTRY(_)
    KSCRASH_ENTRY(a) KSCRASH_ENTRY(b) KSCRASH_ENTRY(c) KSCRASH_ENTRY(d) KSCRASH_ENTRY(e) KSCRASH_ENTRY(f)
    KSCRASH_ENTRY(g) KSCRASH_ENTRY(h) KSCRASH_ENTRY(i) KSCRASH_ENTRY(j) KSCRASH_ENTRY(k) KSCRASH_ENTRY(l)
    KSCRASH_ENTRY(m) KSCRASH_ENTRY(n) KSCRASH_ENTRY(o) KSCRASH_ENTRY(p) KSCRASH_ENTRY(q) KSCRASH_ENTRY(r)
    KSCRASH_ENTRY(s) KSCRASH_ENTRY(t) KSCRASH_ENTRY(u) KSCRASH_ENTRY(v) KSCRASH_ENTRY(w) KSCRASH_ENTRY(x)
    KSCRASH_ENTRY(y) KSCRASH_ENTRY(z)
    KSCRASH_ENTRY(0) KSCRASH_ENTRY(1) KSCRASH_ENTRY(2) KSCRASH_ENTRY(3) KSCRASH_ENTRY(4)
    KSCRASH_ENTRY(5) KSCRASH_ENTRY(6) KSCRASH_ENTRY(7) KSCRASH_ENTRY(8) KSCRASH_ENTRY(9)
};
// clang-format on

#undef KSCRASH_ENTRY

// O(1) lookup table: ASCII -> function pointer.
static kscrash_crumb_func_t sKSCrashDirectLookup[256] = { 0 };

static void kscrash_initLookupTable(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (size_t i = 0; i < sizeof(gKSCrashThreadcrumbTable) / sizeof(gKSCrashThreadcrumbTable[0]); i++) {
            sKSCrashDirectLookup[(unsigned char)gKSCrashThreadcrumbTable[i].c] = gKSCrashThreadcrumbTable[i].func;
        }
    });
}

static kscrash_crumb_func_t kscrash_crumb_lookup(char c) { return sKSCrashDirectLookup[(unsigned char)c]; }

// Worker thread entry point.
static KSCRASH_NOINLINE void *__kscrash_threadcrumb_start__(void *arg) KSCRASH_KEEP_FRAME
{
    KSCrashThreadcrumb *self = (__bridge KSCrashThreadcrumb *)(arg);

    // Initial wait; subsequent waits are in __kscrash_threadcrumb_end__.
    dispatch_semaphore_wait(self->_semaphore, DISPATCH_TIME_FOREVER);

    pthread_setname_np(self->_identifier);
    while (!atomic_load(&self->_stopped)) {
        CALL_NEXT_OR_END
    }
    KSCRASH_THWART_TAIL_CALL
    return NULL;
}

@implementation KSCrashThreadcrumb

+ (void)initialize
{
    kscrash_initLookupTable();
}

- (instancetype)init
{
    return [self initWithIdentifier:@"KSCrashThreadcrumb"];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if ((self = [super init])) {
        _semaphore = dispatch_semaphore_create(0);
        _stackSemaphore = dispatch_semaphore_create(0);
        _lock = [NSLock new];
        _data = malloc(KSCrashThreadcrumbMaximumMessageLength + 1);
        _identifier = strdup(identifier.UTF8String ?: "KSCrashThreadcrumb");

        // Calculate stack size for deep recursion.
        NSUInteger pageSize = PAGE_SIZE;
        NSUInteger frameSize = 2 * 1024;  // ~2KB per frame
        NSUInteger sizeForMessage = KSCrashThreadcrumbMaximumMessageLength * frameSize;
        NSUInteger guardSize = pageSize;
        NSUInteger expectedBytes = (sizeForMessage + guardSize) * 2;  // 2x safety margin
        NSUInteger stackSize = MAX(((expectedBytes + pageSize - 1) / pageSize) * pageSize, PTHREAD_STACK_MIN);

        pthread_attr_t attr = { 0 };
        pthread_attr_init(&attr);
        pthread_attr_setstacksize(&attr, stackSize);
        _threadCreationFailed =
            (pthread_create(&_thread, &attr, __kscrash_threadcrumb_start__, (__bridge void *)self) != 0);
        pthread_attr_destroy(&attr);
    }
    return self;
}

- (void)dealloc
{
    if (!_threadCreationFailed && _thread) {
        atomic_store(&_stopped, true);
        dispatch_semaphore_signal(_semaphore);
        pthread_join(_thread, NULL);
    }
    free(_data);
    free(_identifier);
}

- (NSArray<NSNumber *> *)log:(NSString *)message
{
    static NSCharacterSet *sAllowedCharacters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSCharacterSet *allowed = [NSCharacterSet
            characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"];
        sAllowedCharacters = [allowed invertedSet];
    });

    NSArray<NSNumber *> *stack = @[];
    {
        [_lock lock];
        if (_threadCreationFailed || !_thread || !_data) {
            [_lock unlock];
            return stack;
        }

        // Strip disallowed characters.
        NSString *sanitized =
            [[message componentsSeparatedByCharactersInSet:sAllowedCharacters] componentsJoinedByString:@""];

        // Truncate if needed.
        if (sanitized.length > KSCrashThreadcrumbMaximumMessageLength) {
            sanitized = [sanitized substringToIndex:KSCrashThreadcrumbMaximumMessageLength];
        }

        // Copy to C buffer.
        memset(_data, 0, KSCrashThreadcrumbMaximumMessageLength + 1);
        if (sanitized.UTF8String) {
            strncpy(_data, sanitized.UTF8String, KSCrashThreadcrumbMaximumMessageLength);
        }
        _index = 0;
        _messageLength = sanitized.length;
        _stackAddresses = nil;

        // Signal worker thread.
        dispatch_semaphore_signal(_semaphore);

        // Wait for completion.
        dispatch_semaphore_wait(_stackSemaphore, DISPATCH_TIME_FOREVER);

        stack = [_stackAddresses copy];
        [_lock unlock];
    }

    return stack ?: @[];
}

@end
