#import "CrashTriggers.h"

@implementation CrashTriggers

+ (void)nsexception
{
    NSException *exc = [NSException exceptionWithName:NSGenericException
                                               reason:@"Test"
                                             userInfo:@{ @"a": @"b"}];
    [exc raise];
}

@end
