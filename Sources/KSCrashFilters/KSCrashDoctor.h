//
//  KSCrashDoctor.h
//  KSCrash
//
//  Created by Karl Stenerud on 2012-11-10.
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "KSCrashNamespace.h"

@interface KSCrashDoctor : NSObject

- (NSString *)diagnoseCrash:(NSDictionary *)crashReport;

@end
