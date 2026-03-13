//
//  KSCrashDoctor.h
//  KSCrash
//
//  Created by Karl Stenerud on 2012-11-10.
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "KSCrashNamespace.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSCrashDoctor : NSObject

- (nullable NSString *)diagnoseCrash:(NSDictionary *)crashReport;

@end

NS_ASSUME_NONNULL_END
