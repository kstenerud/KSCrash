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


@interface Crasher ()

@property(nonatomic, readwrite, retain) NSLock* lock;

@end


@implementation Crasher

@synthesize lock = _lock;

- (id) init
{
    if((self = [super init]))
    {
        self.lock = as_autorelease([[NSLock alloc] init]);
    }
    return self;
}

- (void) dealloc
{
    as_release(_lock);
    as_superdealloc();
}

int* g_crasher_null_ptr = NULL;
int g_crasher_denominator = 0;

- (void) throwException
{
    id data = @"a";
    [data objectAtIndex:0];
}

- (void) dereferenceBadPointer
{
    char* ptr = (char*)-1;
    *ptr = 1;
}

- (void) dereferenceNullPointer
{
    *g_crasher_null_ptr = 1;
}

- (void) useCorruptObject
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

- (void) spinRunloop
{
    // From http://landonf.bikemonkey.org/2011/09/14
    
    dispatch_async(dispatch_get_main_queue(), ^
    {
        NSLog(@"ERROR: Run loop should be dead but isn't!");
    });
    *g_crasher_null_ptr = 1;
}

- (void) causeStackOverflow
{
    [self causeStackOverflow];
}

- (void) doAbort
{
    abort();
}

- (void) doDiv0
{
    int value = 10;
    value /= g_crasher_denominator;
    NSLog(@"%d", value);
}

- (void) doIllegalInstruction
{
    unsigned int data[] = {0x11111111, 0x11111111};
    void (*funcptr)() = (void (*)())data;
    funcptr();
}

- (void) accessDeallocatedObject
{
//    NSArray* array = [[NSArray alloc] initWithObjects:@"", nil];
//    [array release];
//    void* ptr = array;
//    memset(ptr, 0xe1, 16);
//    [array objectAtIndex:10];
//    return;

    RefHolder* ref = as_autorelease([RefHolder new]);
    ref.ref = [NSArray arrayWithObjects:@"test1", @"test2", nil];

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"Object = %@", [ref.ref objectAtIndex:1]);
                   });
}

- (void) accessDeallocatedPtrProxy
{
    RefHolder* ref = as_autorelease([RefHolder new]);
    ref.ref = as_autorelease([MyProxy alloc]);

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       NSLog(@"Object = %@", ref.ref);
                   });
}

- (void) zombieNSException
{
    @try
    {
        [NSException raise:@"TurboEncabulatorException" format:@"Spurving bearing failure: Barescent skor motion non-sinusoidal"];
    }
    @catch (NSException *exception)
    {
        RefHolder* ref = as_autorelease([RefHolder new]);
        ref.ref = exception;

        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           NSLog(@"Exception = %@", ref.ref);
                       });
    }
}

- (void) corruptMemory
{
    size_t stringsize = sizeof(uintptr_t) * 2 + 2;
    NSString* string = [NSString stringWithFormat:@"%d", 1];
    NSLog(@"%@", string);
    void* cast = (as_bridge void*)string;
    uintptr_t address = (uintptr_t)cast;
    void* ptr = (void*)address + stringsize;
    memset(ptr, 0xa1, 500);
}

- (void) deadlock
{
    [self.lock lock];
    [NSThread sleepForTimeInterval:0.2f];
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       [self.lock lock];
                   });
}

@end
