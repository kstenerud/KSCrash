//
//  KSCrashInstallation.m
//
//  Created by Karl Stenerud on 2013-02-10.
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

#import "KSCrashInstallation.h"
#import <objc/runtime.h>
#import "KSCString.h"
#import "KSCrash.h"
#import "KSCrashConfiguration.h"
#import "KSCrashInstallation+Private.h"
#import "KSCrashReportFilterAlert.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterDemangle.h"
#import "KSJSONCodecObjC.h"
#import "KSLogger.h"
#import "KSNSErrorHelper.h"

/** Max number of properties that can be defined for writing to the report */
#define kMaxProperties 500

typedef struct {
    const char *key;
    const char *value;
} ReportField;

typedef struct {
    KSReportWriteCallback userCrashCallback;
    int reportFieldsCount;
    ReportField *reportFields[0];
} CrashHandlerData;

static CrashHandlerData *g_crashHandlerData;

@interface KSCrashInstReportField : NSObject

@property(nonatomic, readonly, assign) int index;
@property(nonatomic, readonly, assign) ReportField *field;

@property(nonatomic, readwrite, copy) NSString *key;
@property(nonatomic, readwrite, strong) id value;

@property(nonatomic, readwrite, strong) NSMutableData *fieldBacking;
@property(nonatomic, readwrite, strong) KSCString *keyBacking;
@property(nonatomic, readwrite, strong) KSCString *valueBacking;

@end

@implementation KSCrashInstReportField

+ (KSCrashInstReportField *)fieldWithIndex:(int)index
{
    return [(KSCrashInstReportField *)[self alloc] initWithIndex:index];
}

- (id)initWithIndex:(int)index
{
    if ((self = [super init])) {
        _index = index;
        _fieldBacking = [NSMutableData dataWithLength:sizeof(*self.field)];
    }
    return self;
}

- (ReportField *)field
{
    return (ReportField *)self.fieldBacking.mutableBytes;
}

- (void)setKey:(NSString *)key
{
    _key = key;
    if (key == nil) {
        self.keyBacking = nil;
    } else {
        self.keyBacking = [KSCString stringWithString:key];
    }
    self.field->key = self.keyBacking.bytes;
}

- (void)setValue:(id)value
{
    if (value == nil) {
        _value = nil;
        self.valueBacking = nil;
        return;
    }

    NSError *error = nil;
    NSData *jsonData = [KSJSONCodec encode:value
                                   options:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted
                                     error:&error];
    if (jsonData == nil) {
        KSLOG_ERROR(@"Could not set value %@ for property %@: %@", value, self.key, error);
    } else {
        _value = value;
        self.valueBacking = [KSCString stringWithData:jsonData];
        self.field->value = self.valueBacking.bytes;
    }
}

@end

@interface KSCrashInstallation ()

@property(nonatomic, readwrite, assign) int nextFieldIndex;
@property(nonatomic, readonly, assign) CrashHandlerData *crashHandlerData;
@property(nonatomic, readwrite, strong) NSMutableData *crashHandlerDataBacking;
@property(nonatomic, readwrite, strong) NSMutableDictionary *fields;
@property(nonatomic, readwrite, copy) NSArray *requiredProperties;
@property(nonatomic, readwrite, strong) KSCrashReportFilterPipeline *prependedFilters;

@end

@implementation KSCrashInstallation

- (id)init
{
    [NSException raise:NSInternalInconsistencyException
                format:@"%@ does not support init. Subclasses must call initWithRequiredProperties:", [self class]];
    return nil;
}

- (id)initWithRequiredProperties:(NSArray *)requiredProperties
{
    if ((self = [super init])) {
        _isDemangleEnabled = YES;
        _crashHandlerDataBacking =
            [NSMutableData dataWithLength:sizeof(*self.crashHandlerData) +
                                          sizeof(*self.crashHandlerData->reportFields) * kMaxProperties];
        _fields = [NSMutableDictionary dictionary];
        _requiredProperties = [requiredProperties copy];
        _prependedFilters = [KSCrashReportFilterPipeline filterWithFilters:nil];
    }
    return self;
}

- (void)dealloc
{
    KSCrash *handler = [KSCrash sharedInstance];
    @synchronized(handler) {
        if (g_crashHandlerData == self.crashHandlerData) {
            g_crashHandlerData = NULL;
            // FIXME: Mutating the inner state
            //            handler.onCrash = NULL;
        }
    }
}

- (CrashHandlerData *)crashHandlerData
{
    return (CrashHandlerData *)self.crashHandlerDataBacking.mutableBytes;
}

- (KSCrashInstReportField *)reportFieldForProperty:(NSString *)propertyName
{
    KSCrashInstReportField *field = [self.fields objectForKey:propertyName];
    if (field == nil) {
        field = [KSCrashInstReportField fieldWithIndex:self.nextFieldIndex];
        self.nextFieldIndex++;
        self.crashHandlerData->reportFieldsCount = self.nextFieldIndex;
        self.crashHandlerData->reportFields[field.index] = field.field;
        [self.fields setObject:field forKey:propertyName];
    }
    return field;
}

- (void)reportFieldForProperty:(NSString *)propertyName setKey:(id)key
{
    KSCrashInstReportField *field = [self reportFieldForProperty:propertyName];
    field.key = key;
}

- (void)reportFieldForProperty:(NSString *)propertyName setValue:(id)value
{
    KSCrashInstReportField *field = [self reportFieldForProperty:propertyName];
    field.value = value;
}

- (NSError *)validateProperties
{
    NSMutableString *errors = [NSMutableString string];
    for (NSString *propertyName in self.requiredProperties) {
        NSString *nextError = nil;
        @try {
            id value = [self valueForKey:propertyName];
            if (value == nil) {
                nextError = @"is nil";
            }
        } @catch (NSException *exception) {
            nextError = @"property not found";
        }
        if (nextError != nil) {
            if ([errors length] > 0) {
                [errors appendString:@", "];
            }
            [errors appendFormat:@"%@ (%@)", propertyName, nextError];
        }
    }
    if ([errors length] > 0) {
        return [KSNSErrorHelper errorWithDomain:[[self class] description]
                                           code:0
                                    description:@"Installation properties failed validation: %@", errors];
    }
    return nil;
}

- (NSString *)makeKeyPath:(NSString *)keyPath
{
    if ([keyPath length] == 0) {
        return keyPath;
    }
    BOOL isAbsoluteKeyPath = [keyPath length] > 0 && [keyPath characterAtIndex:0] == '/';
    return isAbsoluteKeyPath ? keyPath : [@"user/" stringByAppendingString:keyPath];
}

- (NSArray *)makeKeyPaths:(NSArray *)keyPaths
{
    if ([keyPaths count] == 0) {
        return keyPaths;
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[keyPaths count]];
    for (NSString *keyPath in keyPaths) {
        [result addObject:[self makeKeyPath:keyPath]];
    }
    return result;
}

- (KSReportWriteCallback)onCrash
{
    @synchronized(self) {
        return self.crashHandlerData->userCrashCallback;
    }
}

- (void)setOnCrash:(KSReportWriteCallback)onCrash
{
    @synchronized(self) {
        self.crashHandlerData->userCrashCallback = onCrash;
    }
}

- (BOOL)installWithConfiguration:(KSCrashConfiguration *)configuration error:(NSError **)error
{
    KSCrash *handler = [KSCrash sharedInstance];
    @synchronized(handler) {
        g_crashHandlerData = self.crashHandlerData;

        configuration.crashNotifyCallback = ^(const struct KSCrashReportWriter *_Nonnull writer) {
            CrashHandlerData *crashHandlerData = g_crashHandlerData;
            if (crashHandlerData == NULL) {
                return;
            }
            for (int i = 0; i < crashHandlerData->reportFieldsCount; i++) {
                ReportField *field = crashHandlerData->reportFields[i];
                if (field->key != NULL && field->value != NULL) {
                    writer->addJSONElement(writer, field->key, field->value, true);
                }
            }
            if (crashHandlerData->userCrashCallback != NULL) {
                crashHandlerData->userCrashCallback(writer);
            }
        };

        NSError *installError = nil;
        BOOL success = [handler installWithConfiguration:configuration error:&installError];

        if (success == NO && error != NULL) {
            *error = installError;
        }

        return success;
    }
}

- (void)sendAllReportsWithCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSError *error = [self validateProperties];
    if (error != nil) {
        if (onCompletion != nil) {
            onCompletion(nil, NO, error);
        }
        return;
    }

    id<KSCrashReportFilter> sink = [self sink];
    if (sink == nil) {
        onCompletion(nil, NO,
                     [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                 code:0
                                          description:@"Sink was nil (subclasses must implement method \"sink\")"]);
        return;
    }

    NSMutableArray *sinkFilters = [@[
        self.prependedFilters,
        sink,
    ] mutableCopy];
    if (self.isDemangleEnabled) {
        [sinkFilters insertObject:[KSCrashReportFilterDemangle new] atIndex:0];
    }
    sink = [KSCrashReportFilterPipeline filterWithFiltersArray:sinkFilters];

    KSCrashReportStore *store = [KSCrash sharedInstance].reportStore;
    if (store == nil) {
        onCompletion(
            nil, NO,
            [KSNSErrorHelper
                errorWithDomain:[[self class] description]
                           code:0
                    description:@"Reporting is not allowed before the call of `installWithConfiguration:error:`"]);
        return;
    }

    store.sink = sink;
    [store sendAllReportsWithCompletion:onCompletion];
}

- (void)addPreFilter:(id<KSCrashReportFilter>)filter
{
    [self.prependedFilters addFilter:filter];
}

- (id<KSCrashReportFilter>)sink
{
    return nil;
}

- (void)addConditionalAlertWithTitle:(NSString *)title
                             message:(NSString *)message
                           yesAnswer:(NSString *)yesAnswer
                            noAnswer:(NSString *)noAnswer
{
    [self addPreFilter:[KSCrashReportFilterAlert filterWithTitle:title
                                                         message:message
                                                       yesAnswer:yesAnswer
                                                        noAnswer:noAnswer]];

    KSCrashReportStore *store = [KSCrash sharedInstance].reportStore;
    if (store.reportCleanupPolicy == KSCrashReportCleanupPolicyOnSuccess) {
        // Better to delete always, or else the user will keep getting nagged
        // until he presses "yes"!
        store.reportCleanupPolicy = KSCrashReportCleanupPolicyAlways;
    }
}

- (void)addUnconditionalAlertWithTitle:(NSString *)title
                               message:(NSString *)message
                     dismissButtonText:(NSString *)dismissButtonText
{
    [self addPreFilter:[KSCrashReportFilterAlert filterWithTitle:title
                                                         message:message
                                                       yesAnswer:dismissButtonText
                                                        noAnswer:nil]];
}

@end
