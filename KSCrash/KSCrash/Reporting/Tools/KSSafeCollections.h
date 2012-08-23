//
//  KSSafeCollections.h
//  KSCrash
//
//  Created by Karl Stenerud on 8/21/12.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableArray (KSSafeCollections)

- (void) safeAddObject:(id) object;

- (void) safeInsertObject:(id)anObject atIndex:(NSUInteger)index;

@end


@interface NSMutableDictionary (KSSafeCollections)

- (void) safeSetObject:(id)anObject forKey:(id)aKey;

- (void) safeSetValue:(id)value forKey:(NSString *)key;

@end
