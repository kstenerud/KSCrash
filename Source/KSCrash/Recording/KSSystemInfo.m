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
#import "KSDynamicLinker.h"
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

    NSMutableData* value = [NSMutableData dataWithLength:size];

    if(kssysctl_stringForName([name cStringUsingEncoding:NSUTF8StringEncoding],
                              value.mutableBytes,
                              size) != 0)
    {
        str = [NSString stringWithCString:value.mutableBytes encoding:NSUTF8StringEncoding];
    }

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

/** Get this application's executable path.
 *
 * @return Executable path.
 */
+ (NSString*) executablePath
{
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSDictionary* infoDict = [mainBundle infoDictionary];
    NSString* bundlePath = [mainBundle bundlePath];
    NSString* executableName = infoDict[@"CFBundleExecutable"];
    return [bundlePath stringByAppendingPathComponent:executableName];
}

/** Get this application's UUID.
 *
 * @return The UUID.
 */
+ (NSString*) appUUID
{
    NSString* result = nil;
    
    NSString* exePath = [self executablePath];

    if(exePath != nil)
    {
        const uint8_t* uuidBytes = ksdl_imageUUID([exePath UTF8String], true);
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
    NSMutableData* data = nil;

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
    if([[UIDevice currentDevice] respondsToSelector:@selector(identifierForVendor)])
    {
        data = [NSMutableData dataWithLength:16];
        [[UIDevice currentDevice].identifierForVendor getUUIDBytes:data.mutableBytes];
    }
    else
#endif
    {
        data = [NSMutableData dataWithLength:6];
        kssysctl_getMacAddress("en0", [data mutableBytes]);
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
    CC_SHA1([data bytes], (CC_LONG)[data length], sha);

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
+ (NSString*) CPUArchForCPUType:(cpu_type_t) cpuType subType:(cpu_subtype_t) subType
{
    switch(cpuType)
    {
        case CPU_TYPE_ARM:
        {
            switch (subType)
            {
                case CPU_SUBTYPE_ARM_V6:
                    return @"armv6";
                case CPU_SUBTYPE_ARM_V7:
                    return @"armv7";
                case CPU_SUBTYPE_ARM_V7F:
                    return @"armv7f";
                case CPU_SUBTYPE_ARM_V7K:
                    return @"armv7k";
#ifdef CPU_SUBTYPE_ARM_V7S
                case CPU_SUBTYPE_ARM_V7S:
                    return @"armv7s";
#endif
            }
            break;
        }
        case CPU_TYPE_X86:
            return @"x86";
        case CPU_TYPE_X86_64:
            return @"x86_64";
    }

    return nil;
}

+ (NSString*) currentCPUArch
{
    NSString* result = [self CPUArchForCPUType:kssysctl_int32ForName("hw.cputype")
                                       subType:kssysctl_int32ForName("hw.cpusubtype")];

    return result ?:[NSString stringWithUTF8String:ksmach_currentCPUArch()];
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
    return ksdl_imageNamed("MobileSubstrate", false) != UINT32_MAX;
}


// ============================================================================
#pragma mark - API -
// ============================================================================

+ (NSDictionary*) systemInfo
{
    NSMutableDictionary* sysInfo = [NSMutableDictionary dictionary];

    NSBundle* mainBundle = [NSBundle mainBundle];
    NSDictionary* infoDict = [mainBundle infoDictionary];
    const struct mach_header* header = _dyld_get_image_header(0);

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
    [sysInfo safeSetObject:[UIDevice currentDevice].systemName forKey:@KSSystemField_SystemName];
    [sysInfo safeSetObject:[UIDevice currentDevice].systemVersion forKey:@KSSystemField_SystemVersion];
#endif
    [sysInfo safeSetObject:[self stringSysctl:@"hw.machine"] forKey:@KSSystemField_Machine];
    [sysInfo safeSetObject:[self stringSysctl:@"hw.model"] forKey:@KSSystemField_Model];
    [sysInfo safeSetObject:[self stringSysctl:@"kern.version"] forKey:@KSSystemField_KernelVersion];
    [sysInfo safeSetObject:[self stringSysctl:@"kern.osversion"] forKey:@KSSystemField_OSVersion];
    [sysInfo safeSetObject:[NSNumber numberWithBool:[self isJailbroken]] forKey:@KSSystemField_Jailbroken];
    [sysInfo safeSetObject:[self dateSysctl:@"kern.boottime"] forKey:@KSSystemField_BootTime];
    [sysInfo safeSetObject:[NSDate date] forKey:@KSSystemField_AppStartTime];
    [sysInfo safeSetObject:[self executablePath] forKey:@KSSystemField_ExecutablePath];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleExecutable"] forKey:@KSSystemField_Executable];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleIdentifier"] forKey:@KSSystemField_BundleID];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleName"] forKey:@KSSystemField_BundleName];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleVersion"] forKey:@KSSystemField_BundleVersion];
    [sysInfo safeSetObject:[infoDict objectForKey:@"CFBundleShortVersionString"] forKey:@KSSystemField_BundleShortVersion];
    [sysInfo safeSetObject:[self appUUID] forKey:@KSSystemField_AppUUID];
    [sysInfo safeSetObject:[self currentCPUArch] forKey:@KSSystemField_CPUArch];
    [sysInfo safeSetObject:[self int32Sysctl:@"hw.cputype"] forKey:@KSSystemField_CPUType];
    [sysInfo safeSetObject:[self int32Sysctl:@"hw.cpusubtype"] forKey:@KSSystemField_CPUSubType];
    [sysInfo safeSetObject:[NSNumber numberWithInt:header->cputype] forKey:@KSSystemField_BinaryCPUType];
    [sysInfo safeSetObject:[NSNumber numberWithInt:header->cpusubtype] forKey:@KSSystemField_BinaryCPUSubType];
    [sysInfo safeSetObject:[[NSTimeZone localTimeZone] abbreviation] forKey:@KSSystemField_TimeZone];
    [sysInfo safeSetObject:[NSProcessInfo processInfo].processName forKey:@KSSystemField_ProcessName];
    [sysInfo safeSetObject:[NSNumber numberWithInt:[NSProcessInfo processInfo].processIdentifier] forKey:@KSSystemField_ProcessID];
    [sysInfo safeSetObject:[NSNumber numberWithInt:getppid()] forKey:@KSSystemField_ParentProcessID];
    [sysInfo safeSetObject:[self processName:getppid()] forKey:@KSSystemField_ParentProcessName];
    [sysInfo safeSetObject:[self deviceAndAppHash] forKey:@KSSystemField_DeviceAppHash];

    NSDictionary* memory = [NSDictionary dictionaryWithObject:[self int64Sysctl:@"hw.memsize"] forKey:@KSSystemField_Size];
    [sysInfo safeSetObject:memory forKey:@KSSystemField_Memory];

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

char* kssysteminfo_copyProcessName(void)
{
    return strdup([[NSProcessInfo processInfo].processName UTF8String]);
}
