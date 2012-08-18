//
//  KSSystemInfo.m
//
//  Created by Karl Stenerud on 12-02-05.
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
#import "KSSysCtl.h"
#import "KSLogger.h"
#import "KSJSONCodecObjC.h"

#import <CommonCrypto/CommonDigest.h>

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
#import <UIKit/UIKit.h>
#endif


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


@interface KSSystemInfo ()

/** Get a sysctl value as an NSNumber.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSNumber*) int32Sysctl:(NSString*) name;

/** Get a sysctl value as an NSNumber.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSNumber*) int64Sysctl:(NSString*) name;

/** Get a sysctl value as an NSString.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSString*) stringSysctl:(NSString*) name;

/** Get a sysctl value as an NSDate.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
+ (NSDate*) dateSysctl:(NSString*) name;

/** Convert raw UUID bytes to a human-readable string.
 *
 * @param uuidBytes The UUID bytes (must be 16 bytes long).
 *
 * @return The human readable form of the UUID.
 */
+ (NSString*) uuidBytesToString:(const uint8_t*) uuidBytes;

/** Get this application's UUID.
 *
 * @return The UUID.
 */
+ (NSString*) appUUID;

/** Generate a 20 byte SHA1 hash that remains unique across a single device and
 * application. This is slightly different from the Apple crash report key,
 * which is unique to the device, regardless of the application.
 *
 * @return The stringified hex representation of the hash for this device + app.
 */
+ (NSString*) deviceAndAppHash;

/** Get the current CPU's architecture.
 *
 * @return The current CPU archutecture.
 */
+ (NSString*) currentCPUArch;

/** Check if the current device is jailbroken.
 *
 * @return YES if the device is jailbroken.
 */
+ (BOOL) isJailbroken;

/** Get the name of a process.
 *
 * @param pid The process ID.
 *
 * @return The process name, or "unknown" if none was found.
 */
+ (NSString*) processName:(int) pid;

/** Safely associate a (potentially null) object with a key.
 *
 * @param dict The dictionary to set the object in.
 *
 * @param object The object to set.
 *
 * @param key The key to use.
 */
+ (void) dict:(NSMutableDictionary*) dict
    setObject:(id) object
       forKey:(NSString*) key;

@end


@implementation KSSystemInfo

+ (NSNumber*) int32Sysctl:(NSString*) name
{
    return [NSNumber numberWithInt:
            kssysctl_int32ForName([name cStringUsingEncoding:NSUTF8StringEncoding])];
}

+ (NSNumber*) int64Sysctl:(NSString*) name
{
    return [NSNumber numberWithLongLong:
            kssysctl_int64ForName([name cStringUsingEncoding:NSUTF8StringEncoding])];
}

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

+ (NSString*) uuidBytesToString:(const uint8_t*) uuidBytes
{
    CFUUIDRef uuidRef = CFUUIDCreateFromUUIDBytes(NULL, *((CFUUIDBytes*)uuidBytes));
    NSString* str = (as_bridge_transfer NSString*)CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    
    return as_autorelease(str);
}

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

+ (NSString*) currentCPUArch
{
    return [NSString stringWithUTF8String:ksmach_currentCPUArch()];
}

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

+ (BOOL) isJailbroken
{
    return ksmach_imageNamed("MobileSubstrate", false) != UINT32_MAX;
}

+ (void) dict:(NSMutableDictionary*) dict
    setObject:(id) object
       forKey:(NSString*) key
{
    if(key == nil)
    {
        KSLOG_ERROR(@"Cannot set object %@ for key %@", object, key);
        return;
    }
    
    if(object == nil)
    {
        object = [NSNull null];
    }
    
    [dict setObject:object forKey:key];
}

+ (NSDictionary*) systemInfo
{
    NSMutableDictionary* sysInfo = [NSMutableDictionary dictionary];
    
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSDictionary* infoDict = [mainBundle infoDictionary];
    
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
    [self dict:sysInfo setObject:[UIDevice currentDevice].systemName forKey:@"system_name"];
    [self dict:sysInfo setObject:[UIDevice currentDevice].systemVersion forKey:@"system_version"];
#endif
    [self dict:sysInfo setObject:[self stringSysctl:@"hw.machine"] forKey:@"machine"];
    [self dict:sysInfo setObject:[self stringSysctl:@"hw.model"] forKey:@"model"];
    [self dict:sysInfo setObject:[self stringSysctl:@"kern.version"] forKey:@"kernel_version"];
    [self dict:sysInfo setObject:[self stringSysctl:@"kern.osversion"] forKey:@"os_version"];
    [self dict:sysInfo setObject:[self int32Sysctl:@"hw.cpufrequency"] forKey:@"cpu_freq"];
    [self dict:sysInfo setObject:[self int32Sysctl:@"hw.busfrequency"] forKey:@"bus_freq"];
    [self dict:sysInfo setObject:[self int64Sysctl:@"hw.memsize"] forKey:@"mem_size"];
    [self dict:sysInfo setObject:[NSNumber numberWithBool:[self isJailbroken]] forKey:@"jailbroken"];
    [self dict:sysInfo setObject:[self dateSysctl:@"kern.boottime"] forKey:@"boot_time"];
    [self dict:sysInfo setObject:[NSDate date] forKey:@"app_start_time"];
    [self dict:sysInfo setObject:[infoDict objectForKey:@"CFBundleExecutablePath"] forKey:@"CFBundleExecutablePath"];
    [self dict:sysInfo setObject:[infoDict objectForKey:@"CFBundleExecutable"] forKey:@"CFBundleExecutable"];
    [self dict:sysInfo setObject:[infoDict objectForKey:@"CFBundleIdentifier"] forKey:@"CFBundleIdentifier"];
    [self dict:sysInfo setObject:[infoDict objectForKey:@"CFBundleName"] forKey:@"CFBundleName"];
    [self dict:sysInfo setObject:[infoDict objectForKey:@"CFBundleVersion"] forKey:@"CFBundleVersion"];
    [self dict:sysInfo setObject:[infoDict objectForKey:@"CFBundleShortVersionString"] forKey:@"CFBundleShortVersionString"];
    [self dict:sysInfo setObject:[self appUUID] forKey:@"app_uuid"];
    [self dict:sysInfo setObject:[self currentCPUArch] forKey:@"cpu_arch"];
    [self dict:sysInfo setObject:[[NSTimeZone localTimeZone] abbreviation] forKey:@"time_zone"];
    [self dict:sysInfo setObject:[NSProcessInfo processInfo].processName forKey:@"process_name"];
    [self dict:sysInfo setObject:[NSNumber numberWithInt:[NSProcessInfo processInfo].processIdentifier] forKey:@"process_id"];
    [self dict:sysInfo setObject:[NSNumber numberWithInt:getppid()] forKey:@"parent_process_id"];
    [self dict:sysInfo setObject:[self processName:getppid()] forKey:@"parent_process_name"];
    [self dict:sysInfo setObject:[self deviceAndAppHash] forKey:@"device_app_hash"];
    
    return sysInfo;
}

@end
