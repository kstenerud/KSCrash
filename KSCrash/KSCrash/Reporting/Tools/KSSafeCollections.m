//
//  KSSafeCollections.m
//  KSCrash
//
//  Created by Karl Stenerud on 8/21/12.
//
//

#import "KSSafeCollections.h"

@implementation NSMutableArray (KSSafeCollections)

static id safeValue(id value)
{
    return value == nil ? [NSNull null] : value;
}

- (void) safeAddObject:(id) object
{
    [self addObject:safeValue(object)];
}

- (void) safeInsertObject:(id)anObject atIndex:(NSUInteger)index
{
    [self insertObject:safeValue(anObject) atIndex:index];
}

@end

@implementation NSMutableDictionary (KSSafeCollections)

- (void) safeSetObject:(id)anObject forKey:(id)aKey
{
    [self setObject:safeValue(anObject) forKey:aKey];
}

- (void) safeSetValue:(id)value forKey:(NSString *)key
{
    [self setValue:safeValue(value) forKey:key];
}

@end
