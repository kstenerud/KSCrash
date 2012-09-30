//
//  KSSystemInfo.m
//
//  Created by Karl Stenerud on 2012-02-05.
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


#import "KSSystemInfo.h"
#import "KSSystemInfoC.h"

#import "ARCSafe_MemMgmt.h"
#import "KSMach.h"
#import "KSSafeCollections.h"
#import "KSSysCtl.h"
#import "KSJSONCodecObjC.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#import <CommonCrypto/CommonDigest.h>
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
#import <UIKit/UIKit.h>
#endif


@implementation KSSystemInfo

// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Get a sysctl value as an NSNumber.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSNumber*) int32Sysctl:(NSString*) name
{
    return [NSNumber numberWithInt:
            kssysctl_int32ForName([name cStringUsingEncoding:NSUTF8StringEncoding])];
}

/** Get a sysctl value as an NSNumber.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSNumber*) int64Sysctl:(NSString*) name
{
    return [NSNumber numberWithLongLong:
            kssysctl_int64ForName([name cStringUsingEncoding:NSUTF8StringEncoding])];
}

/** Get a sysctl value as an NSString.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSString*) stringSysctl:(NSString*) name
{
    NSString* str = nil;
    size_t size = kssysctl_stringForName([name cStringUsingEncoding:NSUTF8StringEncoding],
                                         NULL,
                                         0);

    if(size <= 0)
    {
        return @"";
    }

    char* value = malloc(size);

    if(kssysctl_stringForName([name cStringUsingEncoding:NSUTF8StringEncoding],
                              value,
                              size) != 0)
    {
        str = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
    }

    free(value);

    return str;
}

/** Get a sysctl value as an NSDate.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSDate*) dateSysctl:(NSString*) name
{
    NSDate* result = nil;

    struct timeval value = kssysctl_timevalForName([name cStringUsingEncoding:NSUTF8StringEncoding]);
    if(!(value.tv_sec == 0 && value.tv_usec == 0))
    {
        result = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)value.tv_sec];
    }

    return result;
}

/** Convert raw UUID bytes to a human-readable string.
 *
 * @param uuidBytes The UUID bytes (must be 16 bytes long).
 *
 * @return The human readable form of the UUID.
 */
+ (NSString*) uuidBytesToString:(const uint8_t*) uuidBytes
{
    CFUUIDRef uuidRef = CFUUIDCreateFromUUIDBytes(NULL, *((CFUUIDBytes*)uuidBytes));
    NSString* str = (as_bridge_transfer NSString*)CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);

    return as_autorelease(str);
}

/** Get this application's UUID.
 *
 * @return The UUID.
 */
+ (NSString*) appUUID
{
    NSString* result = nil;
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSDictionary* infoDict = [mainBundle infoDictionary];

    NSString* exePath = [infoDict objectForKey:@"CFBundleExecutablePath"];
    if(exePath != nil)
    {
        const uint8_t* uuidBytes = ksmach_imageUUID([exePath UTF8String], true);
        if(uuidBytes != NULL)
        {
            result = [self uuidBytesToString:uuidBytes];
        }
    }

    return result;
}

/** Generate a 20 byte SHA1 hash that remains unique across a single device and
 * application. This is slightly different from the Apple crash report key,
 * which is unique to the device, regardless of the application.
 *
 * @return The stringified hex representation of the hash for this device + app.
 */
+ (NSString*) deviceAndAppHash
{
    NSMutableData* data = [NSMutableData dataWithLength:6];

    // Get the MAC address.
    if(!kssysctl_getMacAddress("en0", [data mutableBytes]))
    {
        return nil;
    }

    // Append some device-specific data.
    [data appendData:[[self stringSysctl:@"hw.machine"] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[[self stringSysctl:@"hw.model"] dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[[self currentCPUArch] dataUsingEncoding:NSUTF8StringEncoding]];

    // Append the bundle ID.
    NSData* bundleID = [[[NSBundle mainBundle] bundleIdentifier]
                        dataUsingEncoding:NSUTF8StringEncoding];
    if(bundleID != nil)
    {
        [data appendData:bundleID];
    }

    // SHA the whole thing.
    uint8_t sha[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], [data length], sha);

    NSMutableString* hash = [NSMutableString string];
    for(size_t i = 0; i < sizeof(sha); i++)
    {
        [hash appendFormat:@"%02x", sha[i]];
    }

    return hash;
}

/** Get the current CPU's architecture.
 *
 * @return The current CPU archutecture.
 */
+ (NSString*) currentCPUArch
{
    return [NSString stringWithUTF8String:ksmach_currentCPUArch()];
}

/** Get the name of a process.
 *
 * @param pid The process ID.
 *
 * @return The process name, or "unknown" if none was found.
 */
+ (NSString*) processName:(int) pid
{
    struct kinfo_proc procInfo;
    if(kssysctl_getProcessInfo(pid, &procInfo))
    {
        return [NSString stringWithCString:procInfo.kp_proc.p_comm
                                  encoding:NSUTF8StringEncoding];
    }
    return @"unknown";
}

/** Check if the current device is jailbroken.
 *
 * @return YES if the device is jailbroken.
 */
+ (BOOL) isJailbroken
{
    return ksmach_imageNamed("MobileSubstrate", false) != UINT32_MAX;
}


// ============================================================================
#pragma mark - API -
// ============================================================================

+ (NSDictionary*) systemInfo
{
    NSMutableDictionary* sysInfo = [NSMutableDictionary dictionary];

    NSBundle* mainBundle = [NSBundle mainBundle];
    NSDictionary* infoDict = [mainBundle infoDictionary];

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
    [sysInfo safeSetObject:[UIDevice currentDevice].systemName forKey:@"system_name"];
    [sysInfo safeSetObject:[UIDevice currentDevice].systemVersion forKey:@"system_version"];
#endif
    [sysInfo safeSetObject:[self stringSysctl:@"hw.machine"] forKey:@"machine"];
    [sysInfo safeSetObject:[self stringSysctl:@"hw.model"] forKey:@"model"];
    [sysInfo safeSetObject:[self stringSysctl:@"kern.version"] forKey:@"kernel_version"];
    [sysInfo safeSetObject:[self stringSysctl:@"kern.osversion"] forKey:@"os_version"];
    [sysInfo safeSetObject:[self int32Sysctl:@"hw.cpufrequency"] forKey:@"cpu_freq"];
    [sysInfo safeSetObject:[self int32Sysctl:@"hw.busfrequency"] forKey:@"bus_freq"];
    [sysInfo safeSetObject:[self int64Sysctl:@"hw.memsize"] forKey:@"mem_size"];
    [sysInfo safeSetObject:[NSNumber numberWithBool:[self isJailbroken]] forKey:@"jailbroken"];
    [sysInfo safeSetObject:[self dateSysctl:@"kern.boottime"] forKey:@"boot_time"];
    [sysInfo safeSetObject:[NSDate date] forKey:@"app_start_time"];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleExecutablePath"] forKey:@"CFBundleExecutablePath"];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleExecutable"] forKey:@"CFBundleExecutable"];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleIdentifier"] forKey:@"CFBundleIdentifier"];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleName"] forKey:@"CFBundleName"];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleVersion"] forKey:@"CFBundleVersion"];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleShortVersionString"] forKey:@"CFBundleShortVersionString"];
    [sysInfo safeSetObject:[self appUUID] forKey:@"app_uuid"];
    [sysInfo safeSetObject:[self currentCPUArch] forKey:@"cpu_arch"];
    [sysInfo safeSetObject:[[NSTimeZone localTimeZone] abbreviation] forKey:@"time_zone"];
    [sysInfo safeSetObject:[NSProcessInfo processInfo].processName forKey:@"process_name"];
    [sysInfo safeSetObject:[NSNumber numberWithInt:[NSProcessInfo processInfo].processIdentifier] forKey:@"process_id"];
    [sysInfo safeSetObject:[NSNumber numberWithInt:getppid()] forKey:@"parent_process_id"];
    [sysInfo safeSetObject:[self processName:getppid()] forKey:@"parent_process_name"];
    [sysInfo safeSetObject:[self deviceAndAppHash] forKey:@"device_app_hash"];

    return sysInfo;
}

@end

const char* kssysteminfo_toJSON(void)
{
    NSError* error;
    NSDictionary* systemInfo = [NSMutableDictionary dictionaryWithDictionary:[KSSystemInfo systemInfo]];
    NSMutableData* jsonData = (NSMutableData*)[KSJSONCodec encode:systemInfo
                                                          options:KSJSONEncodeOptionSorted
                                                            error:&error];
    if(error != nil)
    {
        KSLOG_ERROR(@"Could not serialize system info: %@", error);
        return NULL;
    }
    if(![jsonData isKindOfClass:[NSMutableData class]])
    {
        jsonData = [NSMutableData dataWithData:jsonData];
    }

    [jsonData appendBytes:"\0" length:1];
    return strdup([jsonData bytes]);
}
