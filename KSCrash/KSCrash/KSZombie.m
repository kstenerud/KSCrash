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


#if __has_feature(objc_arc)

void kszombie_install(unsigned int cacheSize)
{
    #pragma unused(cacheSize)
    NSLog(@"Error: KSZombie must be compiled with ARC disabled. You may use ARC"
          " in your app, but you must compile this library without ARC.");
}

void kszombie_uninstall(void)
{
}

const char* kszombie_className(const void* object)
{
    #pragma unused(object)
    return NULL;
}

#else

typedef struct
{
    const void* object;
    const char* className;
} Zombie;

static Zombie* g_zombieCache;
static unsigned int g_zombieHashMask;

static inline unsigned int hashIndex(const id object)
{
    uintptr_t objPtr = (uintptr_t)object;
    objPtr >>= (sizeof(object)-1);
    return objPtr & g_zombieHashMask;
}

static inline bool isPowerOf2(const unsigned int value)
{
    return value && !(value & (value - 1));
}

#define CREATE_ZOMBIE_CATEGORY(CLASS) \
@implementation CLASS (KSZombie) \
- (void) dealloc_KSZombieOrig \
{ \
    Zombie* zombie = g_zombieCache + hashIndex(self); \
    zombie->object = self; \
    zombie->className = class_getName(object_getClass(self)); \
    [self dealloc_KSZombieOrig]; \
} \
@end

CREATE_ZOMBIE_CATEGORY(NSObject);
CREATE_ZOMBIE_CATEGORY(NSProxy);

static void swizzleDealloc(Class cls)
{
    method_exchangeImplementations(class_getInstanceMethod(cls, @selector(dealloc)),
                                   class_getClassMethod(cls, @selector(dealloc_KSZombieOrig)));
}

void kszombie_install(unsigned int cacheSize)
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
        NSLog(@"Error: %d is not a power of 2. KSZombie NOT installed!", cacheSize);
        return;
    }

    g_zombieHashMask = cacheSize - 1;
    g_zombieCache = calloc(cacheSize, sizeof(*g_zombieCache));
    if(g_zombieCache == NULL)
    {
        NSLog(@"Error: Could not allocate %d bytes of memory. KSZombie NOT installed!",
              cacheSize * (unsigned int)sizeof(*g_zombieCache));
        return;
    }

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
    if(g_zombieCache == NULL)
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

#endif
