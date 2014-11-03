//
//  KSCrashReportFilterAppleFmt.m
//
//  Created by Karl Stenerud on 2012-02-24.
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


#import "KSCrashReportFilterAppleFmt.h"


#import <mach/machine.h>

#import "ARCSafe_MemMgmt.h"
#import "KSCrashCallCompletion.h"
#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"
#import "KSSafeCollections.h"
#import "KSSystemInfo.h"
#import "RFC3339DateTool.h"


#if defined(__LP64__)
    #define FMT_PTR_SHORT        @"0x%lx"
    #define FMT_PTR_LONG         @"0x%016lx"
    #define FMT_PTR_RJ           @"%#18lx"
    #define FMT_OFFSET           @"%lu"
#else
    #define FMT_PTR_SHORT        @"0x%lx"
    #define FMT_PTR_LONG         @"0x%08lx"
    #define FMT_PTR_RJ           @"%#10lx"
    #define FMT_OFFSET           @"%lu"
#endif

#define FMT_TRACE_PREAMBLE       @"%-4d%-31s " FMT_PTR_LONG
#define FMT_TRACE_UNSYMBOLICATED FMT_PTR_SHORT @" + " FMT_OFFSET
#define FMT_TRACE_SYMBOLICATED   @"%@ + " FMT_OFFSET

#define kAppleRedactedText @"<redacted>"

#define kExpectedMajorVersion 3


@interface KSCrashReportFilterAppleFmt ()

@property(nonatomic,readwrite,assign) KSAppleReportStyle reportStyle;

/** Convert a crash report to Apple format.
 *
 * @param JSONReport The crash report.
 *
 * @param reportStyle The style of report to generate.
 *
 * @return The converted crash report.
 */
- (NSString*) toAppleFormat:(NSDictionary*) JSONReport;

/** Determine the major CPU type.
 *
 * @param CPUArch The CPU architecture name.
 *
 * @return the major CPU type.
 */
- (NSString*) CPUType:(NSString*) CPUArch;

/** Determine the CPU architecture based on major/minor CPU architecture codes.
 *
 * @param majorCode The major part of the code.
 *
 * @param minorCode The minor part of the code.
 *
 * @return The CPU architecture.
 */
- (NSString*) CPUArchForMajor:(cpu_type_t) majorCode minor:(cpu_subtype_t) minorCode;

/** Take a UUID string and strip out all the dashes.
 *
 * @param uuid the UUID.
 *
 * @return the UUID in compact form.
 */
- (NSString*) toCompactUUID:(NSString*) uuid;

@end


@implementation KSCrashReportFilterAppleFmt

@synthesize reportStyle = _reportStyle;

/** Date formatter for Apple date format in crash reports. */
NSDateFormatter* g_dateFormatter;

/** Printing order for registers. */
NSDictionary* g_registerOrders;

+ (void) initialize
{
    g_dateFormatter = [[NSDateFormatter alloc] init];
    [g_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS ZZZ"];

    NSArray* armOrder = [NSArray arrayWithObjects:
                         @"r0", @"r1", @"r2", @"r3", @"r4", @"r5", @"r6", @"r7",
                         @"r8", @"r9", @"r10", @"r11", @"ip",
                         @"sp", @"lr", @"pc", @"cpsr",
                         nil];

    NSArray* x86Order = [NSArray arrayWithObjects:
                         @"eax", @"ebx", @"ecx", @"edx",
                         @"edi", @"esi",
                         @"ebp", @"esp", @"ss",
                         @"eflags", @"eip",
                         @"cs", @"ds", @"es", @"fs", @"gs",
                         nil];

    NSArray* x86_64Order = [NSArray arrayWithObjects:
                            @"rax", @"rbx", @"rcx", @"rdx",
                            @"rdi", @"rsi",
                            @"rbp", @"rsp",
                            @"r8", @"r9", @"r10", @"r11", @"r12", @"r13",
                            @"r14", @"r15",
                            @"rip", @"rflags",
                            @"cs", @"fs", @"gs",
                            nil];

    g_registerOrders = [[NSDictionary alloc] initWithObjectsAndKeys:
                        armOrder, @"arm",
                        armOrder, @"armv6",
                        armOrder, @"armv7",
                        armOrder, @"armv7f",
                        armOrder, @"armv7k",
                        armOrder, @"armv7s",
                        x86Order, @"x86",
                        x86Order, @"i386",
                        x86Order, @"i486",
                        x86Order, @"i686",
                        x86_64Order, @"x86_64",
                        nil];
}

+ (KSCrashReportFilterAppleFmt*) filterWithReportStyle:(KSAppleReportStyle) reportStyle
{
    return as_autorelease([[self alloc] initWithReportStyle:reportStyle]);
}

- (id) initWithReportStyle:(KSAppleReportStyle) reportStyle
{
    if((self = [super init]))
    {
        self.reportStyle = reportStyle;
    }
    return self;
}

- (int) majorVersion:(NSDictionary*) report
{
    NSDictionary* info = [self infoReport:report];
    NSDictionary* version = [info objectForKey:@KSCrashField_Version];
    return [[version objectForKey:@KSCrashField_Major] intValue];
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSDictionary* report in reports)
    {
        if([self majorVersion:report] == kExpectedMajorVersion)
        {
            [filteredReports addObjectIfNotNil:[self toAppleFormat:report]];
        }
    }

    kscrash_i_callCompletion(onCompletion, filteredReports, YES, nil);
}

- (NSString*) CPUType:(NSString*) CPUArch
{
    if([CPUArch rangeOfString:@"arm64"].location == 0)
    {
        return @"ARM-64";
    }
    if([CPUArch rangeOfString:@"arm"].location == 0)
    {
        return @"ARM";
    }
    if([CPUArch isEqualToString:@"x86"])
    {
        return @"X86";
    }
    if([CPUArch isEqualToString:@"x86_64"])
    {
        return @"X86_64";
    }
    return @"Unknown";
}

- (NSString*) CPUArchForMajor:(cpu_type_t) majorCode minor:(cpu_subtype_t) minorCode
{
    switch(majorCode)
    {
        case CPU_TYPE_ARM:
        {
            switch (minorCode)
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
                default:
                    return @"arm";
            }
            break;
        }
#ifdef CPU_TYPE_ARM64
        case CPU_TYPE_ARM64:
            return @"arm64";
#endif
        case CPU_TYPE_X86:
            return @"i386";
        case CPU_TYPE_X86_64:
            return @"x86_64";
    }
    return [NSString stringWithFormat:@"unknown(%d,%d)", majorCode, minorCode];
}

/** Convert a backtrace to a string.
 *
 * @param backtrace The backtrace to convert.
 *
 * @param reportStyle The style of report being generated.
 *
 * @param mainExecutableName Name of the app executable.
 *
 * @return The converted string.
 */
- (NSString*) backtraceString:(NSDictionary*) backtrace
                  reportStyle:(KSAppleReportStyle) reportStyle
           mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    int traceNum = 0;
    for(NSDictionary* trace in [backtrace objectForKey:@KSCrashField_Contents])
    {
        uintptr_t pc = (uintptr_t)[[trace objectForKey:@KSCrashField_InstructionAddr] longLongValue];
        uintptr_t objAddr = (uintptr_t)[[trace objectForKey:@KSCrashField_ObjectAddr] longLongValue];
        NSString* objName = [[trace objectForKey:@KSCrashField_ObjectName] lastPathComponent];
        uintptr_t symAddr = (uintptr_t)[[trace objectForKey:@KSCrashField_SymbolAddr] longLongValue];
        NSString* symName = [trace objectForKey:@KSCrashField_SymbolName];
        bool isMainExecutable = [objName isEqualToString:mainExecutableName];
        KSAppleReportStyle thisLineStyle = reportStyle;
        if(thisLineStyle == KSAppleReportStylePartiallySymbolicated)
        {
            thisLineStyle = isMainExecutable ? KSAppleReportStyleUnsymbolicated : KSAppleReportStyleSymbolicated;
        }

        NSString* preamble = [NSString stringWithFormat:FMT_TRACE_PREAMBLE, traceNum, [objName UTF8String], pc];
        NSString* unsymbolicated = [NSString stringWithFormat:FMT_TRACE_UNSYMBOLICATED, objAddr, pc - objAddr];
        NSString* symbolicated = @"(null)";
        if(thisLineStyle != KSAppleReportStyleUnsymbolicated && [symName isKindOfClass:[NSString class]])
        {
            symbolicated = [NSString stringWithFormat:FMT_TRACE_SYMBOLICATED, symName, pc - symAddr];
        }
        else
        {
            thisLineStyle = KSAppleReportStyleUnsymbolicated;
        }


        // Apple has started replacing symbols for any function/method
        // beginning with an underscore with "<redacted>" in iOS 6.
        // No, I can't think of any valid reason to do this, either.
        if(thisLineStyle == KSAppleReportStyleSymbolicated &&
           [symName isEqualToString:kAppleRedactedText])
        {
            thisLineStyle = KSAppleReportStyleUnsymbolicated;
        }

        switch (thisLineStyle)
        {
            case KSAppleReportStyleSymbolicatedSideBySide:
                [str appendFormat:@"%@ %@ (%@)\n", preamble, unsymbolicated, symbolicated];
                break;
            case KSAppleReportStyleSymbolicated:
                [str appendFormat:@"%@ %@\n", preamble, symbolicated];
                break;
            case KSAppleReportStylePartiallySymbolicated: // Should not happen
            case KSAppleReportStyleUnsymbolicated:
                [str appendFormat:@"%@ %@\n", preamble, unsymbolicated];
                break;
        }
        traceNum++;
    }

    return str;
}

- (NSString*) toCompactUUID:(NSString*) uuid
{
    return [[uuid lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

- (NSString*) stringFromDate:(NSDate*) date
{
    if(![date isKindOfClass:[NSDate class]])
    {
        return nil;
    }
    return [g_dateFormatter stringFromDate:date];
}

- (NSDictionary*) recrashReport:(NSDictionary*) report
{
    return [report objectForKey:@KSCrashField_RecrashReport];
}

- (NSDictionary*) systemReport:(NSDictionary*) report
{
    return [report objectForKey:@KSCrashField_System];
}

- (NSDictionary*) infoReport:(NSDictionary*) report
{
    return [report objectForKey:@KSCrashField_Report];
}

- (NSDictionary*) processReport:(NSDictionary*) report
{
    return [report objectForKey:@KSCrashField_ProcessState];
}

- (NSDictionary*) crashReport:(NSDictionary*) report
{
    return [report objectForKey:@KSCrashField_Crash];
}

- (NSArray*) binaryImagesReport:(NSDictionary*) report
{
    return [report objectForKey:@KSCrashField_BinaryImages];
}

- (NSDictionary*) crashedThread:(NSDictionary*) report
{
    NSDictionary* crash = [self crashReport:report];
    NSArray* threads = [crash objectForKey:@KSCrashField_Threads];
    for(NSDictionary* thread in threads)
    {
        BOOL crashed = [[thread objectForKey:@KSCrashField_Crashed] boolValue];
        if(crashed)
        {
            return thread;
        }
    }

    return [crash objectForKey:@KSCrashField_CrashedThread];
}

- (NSString*) mainExecutableNameForReport:(NSDictionary*) report
{
    NSDictionary* info = [self infoReport:report];
    return [info objectForKey:@KSCrashField_ProcessName];
}

- (NSString*) cpuArchForReport:(NSDictionary*) report
{
    NSDictionary* system = [self systemReport:report];
    cpu_type_t cpuType = [[system objectForKey:@KSSystemField_BinaryCPUType] intValue];
    cpu_subtype_t cpuSubType = [[system objectForKey:@KSSystemField_BinaryCPUSubType] intValue];
    return [self CPUArchForMajor:cpuType minor:cpuSubType];
}

- (NSString*) headerStringForReport:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];

    NSDictionary* system = [self systemReport:report];
    NSDictionary* reportInfo = [self infoReport:report];
    NSString* executablePath = [system objectForKey:@KSSystemField_ExecutablePath];
    NSString* cpuArch = [system objectForKey:@KSSystemField_CPUArch];
    NSString* cpuArchType = [self CPUType:cpuArch];
    NSDate* crashTime = [RFC3339DateTool dateFromString:[reportInfo objectForKey:@KSCrashField_Timestamp]];

    [str appendFormat:@"Incident Identifier: %@\n", [reportInfo objectForKey:@KSCrashField_ID]];
    [str appendFormat:@"CrashReporter Key:   %@\n", [system objectForKey:@KSSystemField_DeviceAppHash]];
    [str appendFormat:@"Hardware Model:      %@\n", [system objectForKey:@KSSystemField_Machine]];
    [str appendFormat:@"Process:         %@ [%@]\n",
     [system objectForKey:@KSSystemField_ProcessName],
     [system objectForKey:@KSSystemField_ProcessID]];
    [str appendFormat:@"Path:            %@\n", executablePath];
    [str appendFormat:@"Identifier:      %@\n", [system objectForKey:@KSSystemField_BundleID]];
    [str appendFormat:@"Version:         %@ (%@)\n",
     [system objectForKey:@KSSystemField_BundleShortVersion],
     [system objectForKey:@KSSystemField_BundleVersion]];
    [str appendFormat:@"Code Type:       %@\n", cpuArchType];
    [str appendFormat:@"Parent Process:  %@ [%@]\n",
     [system objectForKey:@KSSystemField_ParentProcessName],
     [system objectForKey:@KSSystemField_ParentProcessID]];
    [str appendFormat:@"\n"];
    [str appendFormat:@"Date/Time:       %@\n", [self stringFromDate:crashTime]];
    [str appendFormat:@"OS Version:      %@ %@ (%@)\n",
     [system objectForKey:@KSSystemField_SystemName],
     [system objectForKey:@KSSystemField_SystemVersion],
     [system objectForKey:@KSSystemField_OSVersion]];
    [str appendFormat:@"Report Version:  104\n"];

    return str;
}

- (NSString*) binaryImagesStringForReport:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];

    NSArray* binaryImages = [self binaryImagesReport:report];
    NSDictionary* system = [self systemReport:report];
    NSString* executablePath = [system objectForKey:@KSSystemField_ExecutablePath];

    [str appendString:@"\nBinary Images:\n"];
    NSMutableArray* images = [NSMutableArray arrayWithArray:binaryImages];
    [images sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2)
     {
         NSNumber* num1 = [(NSDictionary*)obj1 objectForKey:@KSCrashField_ImageAddress];
         NSNumber* num2 = [(NSDictionary*)obj2 objectForKey:@KSCrashField_ImageAddress];
         if(num1 == nil || num2 == nil)
         {
             return NSOrderedSame;
         }
         return [num1 compare:num2];
     }];
    for(NSDictionary* image in images)
    {
        cpu_type_t cpuType = [[image objectForKey:@KSCrashField_CPUType] intValue];
        cpu_subtype_t cpuSubtype = [[image objectForKey:@KSCrashField_CPUSubType] intValue];
        uintptr_t imageAddr = (uintptr_t)[[image objectForKey:@KSCrashField_ImageAddress] longLongValue];
        uintptr_t imageSize = (uintptr_t)[[image objectForKey:@KSCrashField_ImageSize] longLongValue];
        NSString* path = [image objectForKey:@KSCrashField_Name];
        NSString* name = [path lastPathComponent];
        NSString* uuid = [self toCompactUUID:[image objectForKey:@KSCrashField_UUID]];
        NSString* isBaseImage = [executablePath isEqualToString:path] ? @"+" : @" ";

        [str appendFormat:FMT_PTR_RJ @" - " FMT_PTR_RJ @" %@%@ %@  <%@> %@\n",
         imageAddr,
         imageAddr + imageSize - 1,
         isBaseImage,
         name,
         [self CPUArchForMajor:cpuType minor:cpuSubtype],
         uuid,
         path];
    }

    return str;
}

- (NSString*) crashedThreadCPUStateStringForReport:(NSDictionary*) report
                                           cpuArch:(NSString*) cpuArch
{
    NSDictionary* thread = [self crashedThread:report];
    if(thread == nil)
    {
        return @"";
    }
    int threadIndex = [[thread objectForKey:@KSCrashField_Index] intValue];

    NSString* cpuArchType = [self CPUType:cpuArch];

    NSMutableString* str = [NSMutableString string];

    [str appendFormat:@"\nThread %d crashed with %@ Thread State:\n",
     threadIndex, cpuArchType];

    NSDictionary* registers = [(NSDictionary*)[thread objectForKey:@KSCrashField_Registers] objectForKey:@KSCrashField_Basic];
    NSArray* regOrder = [g_registerOrders objectForKey:cpuArch];
    if(regOrder == nil)
    {
        regOrder = [[registers allKeys] sortedArrayUsingSelector:@selector(compare:)];
    }
    NSUInteger numRegisters = [regOrder count];
    NSUInteger i = 0;
    while(i < numRegisters)
    {
        NSUInteger nextBreak = i + 4;
        if(nextBreak > numRegisters)
        {
            nextBreak = numRegisters;
        }
        for(;i < nextBreak; i++)
        {
            NSString* regName = [regOrder objectAtIndex:i];
            uintptr_t addr = (uintptr_t)[[registers objectForKey:regName] longLongValue];
            [str appendFormat:@"%6s: " FMT_PTR_LONG @" ",
             [regName cStringUsingEncoding:NSUTF8StringEncoding],
             addr];
        }
        [str appendString:@"\n"];
    }

    return str;
}

- (NSString*) extraInfoStringForReport:(NSDictionary*) report
                    mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    [str appendString:@"\nExtra Information:\n"];

    NSDictionary* system = [self systemReport:report];
    NSDictionary* crash = [self crashReport:report];
    NSDictionary* error = [crash objectForKey:@KSCrashField_Error];
    NSDictionary* nsexception = [error objectForKey:@KSCrashField_NSException];
    NSDictionary* referencedObject = [nsexception objectForKey:@KSCrashField_ReferencedObject];
    if(referencedObject != nil)
    {
        [str appendFormat:@"Object referenced by NSException:\n%@\n", [self JSONForObject:referencedObject]];
    }
    
    NSDictionary* crashedThread = [self crashedThread:report];
    if(crashedThread != nil)
    {
        NSDictionary* stack = [crashedThread objectForKey:@KSCrashField_Stack];
        if(stack != nil)
        {
            [str appendFormat:@"\nStack Dump (" FMT_PTR_LONG "-" FMT_PTR_LONG "):\n\n%@\n",
             (uintptr_t)[[stack objectForKey:@KSCrashField_DumpStart] unsignedLongLongValue],
             (uintptr_t)[[stack objectForKey:@KSCrashField_DumpEnd] unsignedLongLongValue],
             [stack objectForKey:@KSCrashField_Contents]];
        }

        NSDictionary* notableAddresses = [crashedThread objectForKey:@KSCrashField_NotableAddresses];
        if(notableAddresses != nil)
        {
            [str appendFormat:@"\nNotable Addresses:\n%@\n", [self JSONForObject:notableAddresses]];
        }
    }

    NSDictionary* lastException = [[self processReport:report] objectForKey:@KSCrashField_LastDeallocedNSException];
    if(lastException != nil)
    {
        uintptr_t address = (uintptr_t)[[lastException objectForKey:@KSCrashField_Address] unsignedLongLongValue];
        NSString* name = [lastException objectForKey:@KSCrashField_Name];
        NSString* reason = [lastException objectForKey:@KSCrashField_Reason];
        referencedObject = [lastException objectForKey:@KSCrashField_ReferencedObject];
        [str appendFormat:@"\nLast deallocated NSException (" FMT_PTR_LONG "): %@: %@\n",
         address, name, reason];
        if(referencedObject != nil)
        {
            [str appendFormat:@"Referenced object:\n%@\n", [self JSONForObject:referencedObject]];
        }
        [str appendString:
         [self backtraceString:[lastException objectForKey:@KSCrashField_Backtrace]
                   reportStyle:self.reportStyle
            mainExecutableName:mainExecutableName]];
    }

    NSDictionary* appStats = [system objectForKey:@KSCrashField_AppStats];
    if(appStats != nil)
    {
        [str appendFormat:@"\nApplication Stats:\n%@\n", [self JSONForObject:appStats]];
    }

    NSDictionary* crashReport = [report objectForKey:@KSCrashField_Crash];
    NSString* diagnosis = [crashReport objectForKey:@KSCrashField_Diagnosis];
    if(diagnosis != nil)
    {
        [str appendFormat:@"\nCrashDoctor Diagnosis: %@\n", diagnosis];
    }

    return str;
}

- (NSString*) JSONForObject:(id) object
{
    NSError* error = nil;
    NSData* encoded = [KSJSONCodec encode:object
                                  options:KSJSONEncodeOptionPretty |
                       KSJSONEncodeOptionSorted
                                    error:&error];
    if(error != nil)
    {
        return [NSString stringWithFormat:@"Error encoding JSON: %@", error];
    }
    else
    {
        return as_autorelease([[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]);
    }
}

- (BOOL) isZombieNSException:(NSDictionary*) report
{
    NSDictionary* crash = [self crashReport:report];
    NSDictionary* error = [crash objectForKey:@KSCrashField_Error];
    NSDictionary* mach = [error objectForKey:@KSCrashField_Mach];
    NSString* machExcName = [mach objectForKey:@KSCrashField_ExceptionName];
    NSString* machCodeName = [mach objectForKey:@KSCrashField_CodeName];
    if(![machExcName isEqualToString:@"EXC_BAD_ACCESS"] ||
       ![machCodeName isEqualToString:@"KERN_INVALID_ADDRESS"])
    {
        return NO;
    }

    NSDictionary* lastException = [[self processReport:report] objectForKey:@KSCrashField_LastDeallocedNSException];
    if(lastException == nil)
    {
        return NO;
    }
    NSNumber* lastExceptionAddress = [lastException objectForKey:@KSCrashField_Address];

    NSDictionary* thread = [self crashedThread:report];
    NSDictionary* registers = [(NSDictionary*)[thread objectForKey:@KSCrashField_Registers] objectForKey:@KSCrashField_Basic];

    for(NSString* reg in registers)
    {
        NSNumber* address = [registers objectForKey:reg];
        if([address isEqualToNumber:lastExceptionAddress])
        {
            return YES;
        }
    }

    return NO;
}

- (NSString*) errorInfoStringForReport:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];

    NSDictionary* thread = [self crashedThread:report];
    NSDictionary* crash = [self crashReport:report];
    NSDictionary* error = [crash objectForKey:@KSCrashField_Error];
    NSDictionary* type = [error objectForKey:@KSCrashField_Type];

    NSDictionary* nsexception = [error objectForKey:@KSCrashField_NSException];
    NSDictionary* cppexception = [error objectForKey:@KSCrashField_CPPException];
    NSDictionary* lastException = [[self processReport:report] objectForKey:@KSCrashField_LastDeallocedNSException];
    NSDictionary* userException = [error objectForKey:@KSCrashField_UserReported];
    NSDictionary* mach = [error objectForKey:@KSCrashField_Mach];
    NSDictionary* signal = [error objectForKey:@KSCrashField_Signal];

    NSString* machExcName = [mach objectForKey:@KSCrashField_ExceptionName];
    if(machExcName == nil)
    {
        machExcName = @"0";
    }
    NSString* signalName = [signal objectForKey:@KSCrashField_Name];
    if(signalName == nil)
    {
        signalName = [[signal objectForKey:@KSCrashField_Signal] stringValue];
    }
    NSString* machCodeName = [mach objectForKey:@KSCrashField_CodeName];
    if(machCodeName == nil)
    {
        machCodeName = @"0x00000000";
    }

    [str appendFormat:@"\n"];
    [str appendFormat:@"Exception Type:  %@ (%@)\n", machExcName, signalName];
    [str appendFormat:@"Exception Codes: %@ at " FMT_PTR_LONG @"\n",
     machCodeName,
     (uintptr_t)[[error objectForKey:@KSCrashField_Address] longLongValue]];

    [str appendFormat:@"Crashed Thread:  %d\n",
     [[thread objectForKey:@KSCrashField_Index] intValue]];

    if(nsexception != nil)
    {
        [str appendString:[self stringWithUncaughtExceptionName:[nsexception objectForKey:@KSCrashField_Name]
                                                         reason:[error objectForKey:@KSCrashField_Reason]]];
    }
    else if([self isZombieNSException:report])
    {
        [str appendString:[self stringWithUncaughtExceptionName:[lastException objectForKey:@KSCrashField_Name]
                                                         reason:[lastException objectForKey:@KSCrashField_Reason]]];
        [str appendString:@"NOTE: This exception has been deallocated! Stack trace is crash from attempting to access this zombie exception.\n"];
    }
    else if(userException != nil)
    {
        [str appendString:[self stringWithUncaughtExceptionName:[userException objectForKey:@KSCrashField_Name]
                                                         reason:[error objectForKey:@KSCrashField_Reason]]];
        NSString* trace = [self userExceptionTrace:userException];
        if(trace.length > 0)
        {
            [str appendFormat:@"\n%@\n", trace];
        }
    }
    else if([type isEqual:@KSCrashExcType_CPPException])
    {
        [str appendString:[self stringWithUncaughtExceptionName:[cppexception objectForKey:@KSCrashField_Name]
                                                         reason:[error objectForKey:@KSCrashField_Reason]]];
    }

    if([@KSCrashExcType_Deadlock isEqualToString:[error objectForKey:@KSCrashField_Type]])
    {
        [str appendFormat:@"\nApplication main thread deadlocked\n"];
    }

    return str;
}

- (NSString*) stringWithUncaughtExceptionName:(NSString*) name reason:(NSString*) reason
{
    return [NSString stringWithFormat:
            @"\nApplication Specific Information:\n"
            @"*** Terminating app due to uncaught exception '%@', reason: '%@'\n",
            name, reason];
}

- (NSString*) userExceptionTrace:(NSDictionary*)userException
{
    NSMutableString* str = [NSMutableString string];
    NSString* line = [userException objectForKey:@KSCrashField_LineOfCode];
    if(line != nil)
    {
        [str appendFormat:@"Line: %@\n", line];
    }
    NSArray* backtrace = [userException objectForKey:@KSCrashField_Backtrace];
    for(NSString* entry in backtrace)
    {
        [str appendFormat:@"%@\n", entry];
    }

    if(str.length > 0)
    {
        return [@"Custom Backtrace:\n" stringByAppendingString:str];
    }
    return @"";
}

- (NSString*) threadStringForThread:(NSDictionary*) thread
                 mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    [str appendFormat:@"\n"];
    BOOL crashed = [[thread objectForKey:@KSCrashField_Crashed] boolValue];
    int index = [[thread objectForKey:@KSCrashField_Index] intValue];
    NSString* name = [thread objectForKey:@KSCrashField_Name];
    NSString* queueName = [thread objectForKey:@KSCrashField_DispatchQueue];

    if(name != nil)
    {
        [str appendFormat:@"Thread %d name:  %@\n", index, name];
    }
    else if(queueName != nil)
    {
        [str appendFormat:@"Thread %d name:  Dispatch queue: %@\n", index, queueName];
    }

    if(crashed)
    {
        [str appendFormat:@"Thread %d Crashed:\n", index];
    }
    else
    {
        [str appendFormat:@"Thread %d:\n", index];
    }

    [str appendString:
     [self backtraceString:[thread objectForKey:@KSCrashField_Backtrace]
               reportStyle:self.reportStyle
        mainExecutableName:mainExecutableName]];

    return str;
}

- (NSString*) threadListStringForReport:(NSDictionary*) report
                     mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    NSDictionary* crash = [self crashReport:report];
    NSArray* threads = [crash objectForKey:@KSCrashField_Threads];

    for(NSDictionary* thread in threads)
    {
        [str appendString:[self threadStringForThread:thread mainExecutableName:mainExecutableName]];
    }

    return str;
}

- (NSString*) crashReportString:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];
    NSString* executableName = [self mainExecutableNameForReport:report];

    [str appendString:[self headerStringForReport:report]];
    [str appendString:[self errorInfoStringForReport:report]];
    [str appendString:[self threadListStringForReport:report mainExecutableName:executableName]];
    [str appendString:[self crashedThreadCPUStateStringForReport:report cpuArch:[self cpuArchForReport:report]]];
    [str appendString:[self binaryImagesStringForReport:report]];
    [str appendString:[self extraInfoStringForReport:report mainExecutableName:executableName]];

    return str;
}

- (NSString*) recrashReportString:(NSDictionary*) report
{
    NSDictionary* recrashReport = [self recrashReport:report];
    if(recrashReport == nil)
    {
        return @"";
    }

    NSMutableString* str = [NSMutableString string];

    NSDictionary* system = [self systemReport:report];
    NSString* executablePath = [system objectForKey:@KSSystemField_ExecutablePath];
    NSString* executableName = [executablePath lastPathComponent];
    NSDictionary* crash = [self crashReport:recrashReport];
    NSDictionary* thread = [crash objectForKey:@KSCrashField_CrashedThread];

    [str appendString:@"\nHandler crashed while reporting:\n"];
    [str appendString:[self errorInfoStringForReport:recrashReport]];
    [str appendString:[self threadStringForThread:thread mainExecutableName:executableName]];
    [str appendString:[self crashedThreadCPUStateStringForReport:recrashReport
                                                         cpuArch:[self cpuArchForReport:report]]];
    NSString* diagnosis = [crash objectForKey:@KSCrashField_Diagnosis];
    if(diagnosis != nil)
    {
        [str appendFormat:@"\nRecrash Diagnosis: %@", diagnosis];
    }

    return str;
}


- (NSString*) toAppleFormat:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];

    [str appendString:[self crashReportString:report]];
    [str appendString:[self recrashReportString:report]];

    return str;
}

@end
