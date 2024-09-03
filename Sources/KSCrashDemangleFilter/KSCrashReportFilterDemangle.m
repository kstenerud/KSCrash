//
//  KSCrashReportFilterDemangle.m
//
//  Created by Nikolay Volosatov on 2024-08-16.
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

#import "KSCrashReportFilterDemangle.h"

#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSDemangle_CPP.h"
#import "KSSystemCapabilities.h"
#if KSCRASH_HAS_SWIFT
#import "KSDemangle_Swift.h"
#endif

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@interface KSCrashReportFilterDemangle ()

@end

@implementation KSCrashReportFilterDemangle

+ (NSString *)demangledCppSymbol:(NSString *)symbol
{
    char *demangled = ksdm_demangleCPP(symbol.UTF8String);
    if (demangled != NULL) {
        NSString *result = [[NSString alloc] initWithBytesNoCopy:demangled
                                                          length:strlen(demangled)
                                                        encoding:NSUTF8StringEncoding
                                                    freeWhenDone:YES];
        KSLOG_DEBUG(@"Demangled a C++ symbol '%@' -> '%@'", symbol, result);
        return result;
    }
    return nil;
}

+ (NSString *)demangledSwiftSymbol:(NSString *)symbol
{
#if KSCRASH_HAS_SWIFT
    char *demangled = ksdm_demangleSwift(symbol.UTF8String);
    if (demangled != NULL) {
        NSString *result = [[NSString alloc] initWithBytesNoCopy:demangled
                                                          length:strlen(demangled)
                                                        encoding:NSUTF8StringEncoding
                                                    freeWhenDone:YES];
        KSLOG_DEBUG(@"Demangled a Swift symbol '%@' -> '%@'", symbol, result);
        return result;
    }
#endif
    return nil;
}

+ (NSString *)demangledSymbol:(NSString *)symbol
{
    return [self demangledCppSymbol:symbol] ?: [self demangledSwiftSymbol:symbol];
}

/** Recurcively demangles strings within the report.
 * @param reportObj An object within the report (dictionary, array, string etc)
 * @param path An array of strings representing keys in dictionaries. An empty key means an itteration within the array.
 * @param depth Current depth of the path
 * @return An updated object or `nil` if no changes were applied.
 */
+ (id)demangleReportObj:(id)reportObj path:(NSArray<NSString *> *)path depth:(NSUInteger)depth
{
    // Check for NSString and try demangle
    if (depth == path.count) {
        if ([reportObj isKindOfClass:[NSString class]] == NO) {
            return nil;
        }
        NSString *demangled = [self demangledSymbol:reportObj];
        return demangled;
    }

    NSString *pathComponent = path[depth];

    // NSArray:
    if (pathComponent.length == 0) {
        if ([reportObj isKindOfClass:[NSArray class]] == NO) {
            return nil;
        }
        NSArray *reportArray = reportObj;
        NSMutableArray *__block result = nil;
        [reportArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *_Nonnull stop) {
            id demangled = [self demangleReportObj:obj path:path depth:depth + 1];
            if (demangled != nil && result == nil) {
                // Initializing the updated array only on first demangled result
                result = [NSMutableArray arrayWithCapacity:reportArray.count];
                for (NSUInteger subIdx = 0; subIdx < idx; ++subIdx) {
                    [result addObject:reportArray[subIdx]];
                }
            }
            result[idx] = demangled ?: obj;
        }];
        return [result copy];
    }

    // NSDictionary:
    if ([reportObj isKindOfClass:[NSDictionary class]] == NO) {
        return nil;
    }
    NSDictionary *reportDict = reportObj;
    id demangledElement = [self demangleReportObj:reportDict[pathComponent] path:path depth:depth + 1];
    if (demangledElement == nil) {
        return nil;
    }
    NSMutableDictionary *result = [reportDict mutableCopy];
    result[pathComponent] = demangledElement;
    return [result copy];
}

#pragma mark - KSCrashReportFilter

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray *demanglePaths = @[
        @[
            KSCrashField_Crash, KSCrashField_Threads, @"", KSCrashField_Backtrace, KSCrashField_Contents, @"",
            KSCrashField_SymbolName
        ],
        @[
            KSCrashField_RecrashReport, KSCrashField_Crash, KSCrashField_Threads, @"", KSCrashField_Backtrace,
            KSCrashField_Contents, @"", KSCrashField_SymbolName
        ],
        @[ KSCrashField_Crash, KSCrashField_Error, KSCrashField_CPPException, KSCrashField_Name ],
        @[
            KSCrashField_RecrashReport, KSCrashField_Crash, KSCrashField_Error, KSCrashField_CPPException,
            KSCrashField_Name
        ],
    ];

    NSMutableArray<id<KSCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReportDictionary *report in reports) {
        if ([report isKindOfClass:[KSCrashReportDictionary class]] == NO) {
            KSLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }
        NSDictionary *reportDict = report.value;
        for (NSArray *path in demanglePaths) {
            reportDict = [[self class] demangleReportObj:reportDict path:path depth:0] ?: reportDict;
        }
        [filteredReports addObject:[KSCrashReportDictionary reportWithValue:reportDict]];
    }

    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
