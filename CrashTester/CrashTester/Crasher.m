//
//  Crasher.m
//
//  Created by Karl Stenerud on 2012-01-28.
//

#import "Crasher.h"
#import "ARCSafe_MemMgmt.h"

@interface MyClass: NSObject @end
@implementation MyClass @end

@interface MyProxy: NSProxy @end
@implementation MyProxy @end

@interface RefHolder: NSObject
{
    as_unsafe_unretained id _ref;
}
@property(nonatomic, readwrite, assign) id ref;

@end

@implementation RefHolder

- (id) ref
{
    return _ref;
}

- (void) setRef:(id) ref
{
    _ref = ref;
}

@end


@implementation Crasher

int* g_crasher_null_ptr = NULL;
int g_crasher_denominator = 0;

+ (void) throwException
{
    id data = @"a";
    [data objectAtIndex:0];
}

+ (void) dereferenceBadPointer
{
    char* ptr = (char*)-1;
    *ptr = 1;
}

+ (void) dereferenceNullPointer
{
    *g_crasher_null_ptr = 1;
}

+ (void) useCorruptObject
{
    // From http://landonf.bikemonkey.org/2011/09/14
    
    // Random data
    void* pointers[] = {NULL, NULL, NULL};
    void* randomData[] = {"a","b",pointers,"d","e","f"};
    
    // A corrupted/under-retained/re-used piece of memory
    struct {void* isa;} corruptObj = {randomData};
    
    // Message an invalid/corrupt object.
    // This will deadlock if called in a crash handler.
    [(as_bridge id)&corruptObj class];
}

+ (void) spinRunloop
{
    // From http://landonf.bikemonkey.org/2011/09/14
    
    dispatch_async(dispatch_get_main_queue(), ^
    {
        NSLog(@"ERROR: Run loop should be dead but isn't!");
    });
    *g_crasher_null_ptr = 1;
}

+ (void) causeStackOverflow
{
    [self causeStackOverflow];
}

+ (void) doAbort
{
    abort();
}

+ (void) doDiv0
{
    int value = 10;
    value /= g_crasher_denominator;
    NSLog(@"%d", value);
}

+ (void) doIllegalInstruction
{
    unsigned int data[] = {0x11111111, 0x11111111};
    void (*funcptr)() = (void (*)())data;
    funcptr();
}

+ (void) accessDeallocatedPtr
{
    RefHolder* ref = as_autorelease([RefHolder new]);
    ref.ref = as_autorelease([MyClass new]);

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"Object = %@", ref.ref);
                   });
}

+ (void) accessDeallocatedPtrProxy
{
    RefHolder* ref = as_autorelease([RefHolder new]);
    ref.ref = as_autorelease([MyProxy alloc]);

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"Object = %@", ref.ref);
                   });
}

@end
