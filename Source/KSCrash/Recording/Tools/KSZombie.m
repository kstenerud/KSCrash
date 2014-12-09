//
//  KSZombie.m
//
//  Created by Karl Stenerud on 2012-09-15.
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


#import "KSZombie.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>


// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


#if __has_feature(objc_arc)

#warning KSZombie.m must be compiled with ARC disabled. Use -fno-objc-arc when compiling this file.

void kszombie_install(__unused size_t cacheSize)
{
    NSLog(@"Error: KSZombie.m must be compiled with ARC disabled. "
          @"Use -fno-objc-arc when compiling this file.");
    NSLog(@"KSZombie is disabled.");
}

void kszombie_uninstall(void)
{
}

const char* kszombie_className(__unused const void* object)
{
    return NULL;
}

const void* kszombie_lastDeallocedNSExceptionAddress(void)
{
    return NULL;
}

const char* kszombie_lastDeallocedNSExceptionName(void)
{
    return NULL;
}

const char* kszombie_lastDeallocedNSExceptionReason(void)
{
    return NULL;
}

const uintptr_t* kszombie_lastDeallocedNSExceptionCallStack(void)
{
    return NULL;
}

const size_t kszombie_lastDeallocedNSExceptionCallStackLength(void)
{
    return 0;
}

#else

typedef struct
{
    const void* object;
    const char* className;
} Zombie;

static Zombie* g_zombieCache;
static size_t g_zombieHashMask;

static struct
{
    Class class;
    const void* address;
    char name[100];
    char reason[900];
    uintptr_t callStack[50];
    NSUInteger callStackLength;
} g_lastDeallocedException;

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
static const NSUInteger g_callStackSize = sizeof(g_lastDeallocedException.callStack) / sizeof(*g_lastDeallocedException.callStack);
#endif

static inline size_t hashIndex(const id object)
{
    uintptr_t objPtr = (uintptr_t)object;
    objPtr >>= (sizeof(object)-1);
    return objPtr & g_zombieHashMask;
}

static inline bool isPowerOf2(const size_t value)
{
    return value && !(value & (value - 1));
}

static void storeException(NSException* exception)
{
    g_lastDeallocedException.address = exception;
    strncpy(g_lastDeallocedException.name, [[exception name] UTF8String], sizeof(g_lastDeallocedException.name));
    strncpy(g_lastDeallocedException.reason, [[exception reason] UTF8String], sizeof(g_lastDeallocedException.reason));

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
    // Crashes under OS X
    NSArray* callStack = [exception callStackReturnAddresses];
    NSUInteger count = [callStack count];
    if(count > g_callStackSize)
    {
        count = g_callStackSize;
    }
    for(NSUInteger i = 0; i < count; i++)
    {
        g_lastDeallocedException.callStack[i] = [[callStack objectAtIndex:i] unsignedIntegerValue];
    }
    g_lastDeallocedException.callStackLength = count;
#endif
}

static inline void handleDealloc(id self)
{
    Zombie* zombie = g_zombieCache + hashIndex(self);
    zombie->object = self;
    Class class = object_getClass(self);
    zombie->className = class_getName(class);
    for(; class != nil; class = class_getSuperclass(class))
    {
        unlikely_if(class == g_lastDeallocedException.class)
        {
            storeException(self);
        }
    }
}

#define CREATE_ZOMBIE_CATEGORY(CLASS) \
@implementation CLASS (KSZombie) \
- (void) dealloc_KSZombieOrig \
{ \
    handleDealloc(self); \
    [self dealloc_KSZombieOrig]; \
} \
@end

CREATE_ZOMBIE_CATEGORY(NSObject)
CREATE_ZOMBIE_CATEGORY(NSProxy)

static void swizzleDealloc(Class cls)
{
    method_exchangeImplementations(class_getInstanceMethod(cls, @selector(dealloc)),
                                   class_getClassMethod(cls, @selector(dealloc_KSZombieOrig)));
}

void kszombie_install(size_t cacheSize)
{
    if(g_zombieCache != NULL)
    {
        NSLog(@"KSZombie already installed.");
        return;
    }

    if(cacheSize < 2)
    {
        NSLog(@"Error: cacheSize must be greater than 1. KSZombie NOT installed!");
        return;
    }

    if(!isPowerOf2(cacheSize))
    {
        NSLog(@"Error: %ld is not a power of 2. KSZombie NOT installed!", cacheSize);
        return;
    }

    g_zombieHashMask = cacheSize - 1;
    g_zombieCache = calloc(cacheSize, sizeof(*g_zombieCache));
    if(g_zombieCache == NULL)
    {
        NSLog(@"Error: Could not allocate %ld bytes of memory. KSZombie NOT installed!",
              cacheSize * sizeof(*g_zombieCache));
        return;
    }

    g_lastDeallocedException.class = [NSException class];
    g_lastDeallocedException.address = NULL;
    g_lastDeallocedException.name[0] = 0;
    g_lastDeallocedException.reason[0] = 0;

    swizzleDealloc([NSObject class]);
    swizzleDealloc([NSProxy class]);
}

void kszombie_uninstall(void)
{
    if(g_zombieCache == NULL)
    {
        return;
    }

    swizzleDealloc([NSObject class]);
    swizzleDealloc([NSProxy class]);

    void* ptr = g_zombieCache;
    g_zombieCache = NULL;
    dispatch_async(dispatch_get_main_queue(), ^
    {
        free(ptr);
    });
}

const char* kszombie_className(const void* object)
{
    if(g_zombieCache == NULL || object == NULL)
    {
        return NULL;
    }

    Zombie* zombie = g_zombieCache + hashIndex(object);
    if(zombie->object == object)
    {
        return zombie->className;
    }
    return NULL;
}

const void* kszombie_lastDeallocedNSExceptionAddress(void)
{
    return g_lastDeallocedException.address;
}

const char* kszombie_lastDeallocedNSExceptionName(void)
{
    return g_lastDeallocedException.name;
}

const char* kszombie_lastDeallocedNSExceptionReason(void)
{
    return g_lastDeallocedException.reason;
}

const uintptr_t* kszombie_lastDeallocedNSExceptionCallStack(void)
{
    return g_lastDeallocedException.callStack;
}

const size_t kszombie_lastDeallocedNSExceptionCallStackLength(void)
{
    return g_lastDeallocedException.callStackLength;
}

#endif
