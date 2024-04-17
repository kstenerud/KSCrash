//
//  KSReachability.m
//
//  Created by Karl Stenerud on 2012-05-05.
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


#import "KSReachabilityKSCrash.h"

#import <netdb.h>


#define kKVOProperty_Flags     @"flags"
#define kKVOProperty_Reachable @"reachable"
#define kKVOProperty_WWANOnly  @"WWANOnly"

#if KSCRASH_HAS_REACHABILITY
@interface KSReachabilityKSCrash ()

@property(nonatomic,readwrite,retain) NSString* hostname;
@property(nonatomic,readwrite,assign) SCNetworkReachabilityFlags flags;
@property(nonatomic,readwrite,assign) BOOL reachable;
@property(nonatomic,readwrite,assign) BOOL WWANOnly;
@property(nonatomic,readwrite,assign) SCNetworkReachabilityRef reachabilityRef;

- (id) initWithReachabilityRef:(SCNetworkReachabilityRef) reachabilityRef;

- (id) initWithAddress:(const struct sockaddr*) address;

- (id) initWithHost:(NSString*) hostname;

- (NSString*) extractHostName:(NSString*) potentialURL;

- (void) onReachabilityFlagsChanged:(SCNetworkReachabilityFlags) flags;

static void onReachabilityChanged(SCNetworkReachabilityRef target,
                                  SCNetworkReachabilityFlags flags,
                                  void* info);

@end


@implementation KSReachabilityKSCrash

@synthesize onReachabilityChanged = _onReachabilityChanged;
@synthesize flags = _flags;
@synthesize reachable = _reachable;
@synthesize WWANOnly = _WWANOnly;
@synthesize reachabilityRef = _reachabilityRef;
@synthesize hostname = _hostname;
@synthesize notificationName = _notificationName;

+ (KSReachabilityKSCrash*) reachabilityToHost:(NSString*) hostname
{
    return [[self alloc] initWithHost:hostname];
}


+ (KSReachabilityKSCrash*) reachabilityToLocalNetwork
{
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(IN_LINKLOCALNETNUM);
    
    return [[self alloc] initWithAddress:(const struct sockaddr*)&address];
}

- (id) initWithHost:(NSString*) hostname
{
    hostname = [self extractHostName:hostname];
    if([hostname length] == 0)
    {
        struct sockaddr_in address;
        bzero(&address, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;
        
        return [self initWithAddress:(const struct sockaddr*)&address];
    }
    
    return [self initWithReachabilityRef:
            SCNetworkReachabilityCreateWithName(NULL, (const char* _Nonnull)[hostname UTF8String])];
}

- (id) initWithAddress:(const struct sockaddr*) address
{
    return [self initWithReachabilityRef:
            SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address)];
}

- (id) initWithReachabilityRef:(SCNetworkReachabilityRef) reachabilityRef
{
    if((self = [super init]))
    {
        if(reachabilityRef == NULL)
        {
            goto failed;
        }

        SCNetworkReachabilityContext context =
        {
            0,
            (__bridge void*)self,
            NULL,
            NULL,
            NULL
        };

        if(!SCNetworkReachabilitySetCallback(reachabilityRef,
                                             onReachabilityChanged,
                                             &context))
        {
            goto failed;
        }

        if(!SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef,
                                                     CFRunLoopGetCurrent(),
                                                     kCFRunLoopDefaultMode))
        {
            goto failed;
        }

        dispatch_async(dispatch_get_global_queue(0,0), ^
                       {
                           @autoreleasepool {
                           
                               SCNetworkReachabilityFlags flags;
                               if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
                               {
                                   dispatch_async(dispatch_get_main_queue(), ^
                                                  {
                                                      @autoreleasepool {
                                                          [self onReachabilityFlagsChanged:flags];
                                                      }
                                                  });
                               }
                           }
                       });

        self.reachabilityRef = reachabilityRef;

        return self;
    }

failed:
    if(reachabilityRef)
    {
        CFRelease(reachabilityRef);
    }
    self.reachabilityRef = NULL;
    return nil;
}

- (void) dealloc
{
    if(_reachabilityRef != NULL)
    {
        SCNetworkReachabilityUnscheduleFromRunLoop(_reachabilityRef,
                                                   CFRunLoopGetCurrent(),
                                                   kCFRunLoopDefaultMode);
        CFRelease(_reachabilityRef);
    }
}

- (NSString*) extractHostName:(NSString*) potentialURL
{
    if(potentialURL == nil)
    {
        return nil;
    }

    NSString* host = [[NSURL URLWithString:potentialURL] host];
    if(host != nil)
    {
        return host;
    }
    return potentialURL;
}

- (BOOL) isReachableWithFlags:(SCNetworkReachabilityFlags) flags
{
    if(!(flags & kSCNetworkReachabilityFlagsReachable))
    {
        // Not reachable at all.
        return NO;
    }
    
    if(!(flags & kSCNetworkReachabilityFlagsConnectionRequired))
    {
        // Reachable with no connection required.
        return YES;
    }
    
    if((flags & (kSCNetworkReachabilityFlagsConnectionOnDemand |
                 kSCNetworkReachabilityFlagsConnectionOnTraffic)) &&
       !(flags & kSCNetworkReachabilityFlagsInterventionRequired))
    {
        // Automatic connection with no user intervention required.
        return YES;
    }
    
    return NO;
}

- (void) onReachabilityFlagsChanged:(SCNetworkReachabilityFlags) flags
{
    if(_flags != flags)
    {
        BOOL reachable = [self isReachableWithFlags:flags];
#if TARGET_OS_IPHONE
        BOOL WWANOnly = reachable && (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
#else
        BOOL WWANOnly = NO;
#endif
        
        BOOL rChanged = _reachable != reachable;
        BOOL wChanged = _WWANOnly != WWANOnly;
        
        [self willChangeValueForKey:kKVOProperty_Flags];
        if(rChanged) [self willChangeValueForKey:kKVOProperty_Reachable];
        if(wChanged) [self willChangeValueForKey:kKVOProperty_WWANOnly];
        
        _flags = flags;
        _reachable = reachable;
        _WWANOnly = WWANOnly;
        
        [self didChangeValueForKey:kKVOProperty_Flags];
        if(rChanged) [self didChangeValueForKey:kKVOProperty_Reachable];
        if(wChanged) [self didChangeValueForKey:kKVOProperty_WWANOnly];
        
        if(self.onReachabilityChanged != nil)
        {
            self.onReachabilityChanged(self);
        }
        
        if(self.notificationName != nil)
        {
            NSNotificationCenter* nCenter = [NSNotificationCenter defaultCenter];
            [nCenter postNotificationName:self.notificationName object:self];
        }
    }
}

- (BOOL) updateFlags
{
    SCNetworkReachabilityFlags flags;
    if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
    {
        [self onReachabilityFlagsChanged:flags];
        return YES;
    }
    return NO;
}

static void onReachabilityChanged(__unused SCNetworkReachabilityRef target,
                                  SCNetworkReachabilityFlags flags,
                                  void* info)
{
    KSReachabilityKSCrash* reachability = (__bridge KSReachabilityKSCrash*) info;
    
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       @autoreleasepool {
                           [reachability onReachabilityFlagsChanged:flags];
                       }
                   });
}

@end


@interface KSReachableOperationKSCrash ()

@property(nonatomic,readwrite,retain) KSReachabilityKSCrash* reachability;

@end


@implementation KSReachableOperationKSCrash

@synthesize reachability = _reachability;

+ (KSReachableOperationKSCrash*) operationWithHost:(NSString*) host
                                         allowWWAN:(BOOL) allowWWAN
                                             block:(void(^)(void)) block
{
    return [[self alloc] initWithHost:host allowWWAN:allowWWAN block:block];
}

- (id) initWithHost:(NSString*) host
          allowWWAN:(BOOL) allowWWAN
              block:(void(^)(void)) block
{
    if((self = [super init]))
    {
        self.reachability = [KSReachabilityKSCrash reachabilityToHost:host];
        
        __unsafe_unretained KSReachableOperationKSCrash* blockSelf = self;
        self.reachability.onReachabilityChanged = ^(KSReachabilityKSCrash* reachability)
        {
            if(reachability.reachable)
            {
                if(allowWWAN || !reachability.WWANOnly)
                {
                    block();
                    blockSelf.reachability = nil;
                }
            }
        };
    }
    return self;
}

@end

#else

@implementation KSReachabilityKSCrash

@synthesize onReachabilityChanged = _onReachabilityChanged;
@synthesize reachable = _reachable;
@synthesize WWANOnly = _WWANOnly;
@synthesize hostname = _hostname;
@synthesize notificationName = _notificationName;

+ (KSReachabilityKSCrash*) reachabilityToHost:(__unused NSString*) hostname
{
    return [[self alloc] init];
}


+ (KSReachabilityKSCrash*) reachabilityToLocalNetwork
{
    return [[self alloc] init];
}

- (BOOL) updateFlags
{
    return NO;
}

@end

@implementation KSReachableOperationKSCrash

+ (KSReachableOperationKSCrash*) operationWithHost:(NSString*) host
                                         allowWWAN:(BOOL) allowWWAN
                                             block:(void(^)(void)) block;
{
    return [[self alloc] initWithHost:host allowWWAN:allowWWAN block:block];
}

- (id) initWithHost:(__unused NSString*) hostname
          allowWWAN:(__unused BOOL) allowWWAN
              block:(void(^)(void)) block;
{
    if((self = [super init]))
    {
        // Just lie and pretend that we always have reachability.
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
    }
    return self;
}

@end

#endif
