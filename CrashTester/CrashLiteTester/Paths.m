//
//  Paths.m
//  CrashTester
//
//  Created by Karl Stenerud on 12-05-08.
//

#import "Paths.h"

@implementation Paths

+ (NSString*) pathRelativeToCaches:(NSString*) path
{
    NSArray* directories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                               NSUserDomainMask,
                                                               YES);
    if([directories count] == 0)
    {
        NSLog(@"Could not locate cache directory path.");
        return nil;
    }
    NSString* cachePath = [directories objectAtIndex:0];
    if([cachePath length] == 0)
    {
        NSLog(@"Could not locate cache directory path.");
        return nil;
    }
    return [cachePath stringByAppendingPathComponent:path];
}

+ (NSString*) reportPath
{
    return [self pathRelativeToCaches:@"MyCrashReport.json"];
}

+ (NSString*) statePath
{
    return [self pathRelativeToCaches:@"MyCrashReporterState.json"];
}

@end
