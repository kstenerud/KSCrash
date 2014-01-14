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
#import "KSCrashInstallation+Private.h"
#import "ARCSafe_MemMgmt.h"
#import "KSCrashAdvanced.h"
#import "KSCrashReportFilterAlert.h"
#import "KSCString.h"
#import "KSJSONCodecObjC.h"
#import "KSLogger.h"
#import "NSError+SimpleConstructor.h"
#import <objc/runtime.h>


/** Max number of properties that can be defined for writing to the report */
#define kMaxProperties 500


typedef struct
{
    const char* key;
    const char* value;
} ReportField;

typedef struct
{
    KSReportWriteCallback userCrashCallback;
    size_t reportFieldsCount;
    ReportField* reportFields[0];
} CrashHandlerData;


static CrashHandlerData* g_crashHandlerData;


void kscinst_i_crashCallback(const KSCrashReportWriter* writer)
{
    for(size_t i = 0; i < g_crashHandlerData->reportFieldsCount; i++)
    {
        ReportField* field = g_crashHandlerData->reportFields[i];
        if(field->key != NULL && field->value != NULL)
        {
            writer->addJSONElement(writer, field->key, field->value);
        }
    }
    if(g_crashHandlerData->userCrashCallback != NULL)
    {
        g_crashHandlerData->userCrashCallback(writer);
    }
}


@interface KSCrashInstReportField: NSObject

@property(nonatomic,readonly,assign) size_t index;
@property(nonatomic,readonly,assign) ReportField* field;

@property(nonatomic,readwrite,retain) NSString* key;
@property(nonatomic,readwrite,retain) id value;

@property(nonatomic,readwrite,retain) NSMutableData* fieldBacking;
@property(nonatomic,readwrite,retain) KSCString* keyBacking;
@property(nonatomic,readwrite,retain) KSCString* valueBacking;

@end

@implementation KSCrashInstReportField

@synthesize index = _index;
@synthesize key = _key;
@synthesize value = _value;
@synthesize fieldBacking = _fieldBacking;
@synthesize keyBacking = _keyBacking;
@synthesize valueBacking= _valueBacking;

+ (KSCrashInstReportField*) fieldWithIndex:(size_t) index
{
    return as_autorelease([(KSCrashInstReportField*)[self alloc] initWithIndex:index]);
}

- (id) initWithIndex:(size_t) index
{
    if((self = [super init]))
    {
        _index = index;
        self.fieldBacking = [NSMutableData dataWithLength:sizeof(*self.field)];
    }
    return self;
}

- (void) dealloc
{
    as_release(_key);
    as_release(_value);
    as_release(_fieldBacking);
    as_release(_keyBacking);
    as_release(_valueBacking);
    as_superdealloc();
}

- (ReportField*) field
{
    return (ReportField*)self.fieldBacking.mutableBytes;
}

- (void) setKey:(NSString*) key
{
    as_autorelease_noref(_key);
    _key = as_retain(key);
    if(key == nil)
    {
        self.keyBacking = nil;
    }
    else
    {
        self.keyBacking = [KSCString stringWithString:key];
    }
    self.field->key = self.keyBacking.bytes;
}

- (void) setValue:(id) value
{
    if(value == nil)
    {
        as_autorelease_noref(_value);
        _value = nil;
        self.valueBacking = nil;
        return;
    }
    
    NSError* error = nil;
    NSData* jsonData = [KSJSONCodec encode:value options:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted error:&error];
    if(jsonData == nil)
    {
        KSLOG_ERROR(@"Could not set value %@ for property %@: %@", value, self.key, error);
    }
    else
    {
        as_autorelease_noref(_value);
        _value = as_retain(value);
        self.valueBacking = [KSCString stringWithData:jsonData];
        self.field->value = self.valueBacking.bytes;
    }
}

@end

@interface KSCrashInstallation ()

@property(nonatomic,readwrite,assign) size_t nextFieldIndex;
@property(nonatomic,readonly,assign) CrashHandlerData* crashHandlerData;
@property(nonatomic,readwrite,retain) NSMutableData* crashHandlerDataBacking;
@property(nonatomic,readwrite,retain) NSMutableDictionary* fields;
@property(nonatomic,readwrite,retain) NSArray* requiredProperties;
@property(nonatomic,readwrite,retain) KSCrashReportFilterAlert* alertFilter;

@end


@implementation KSCrashInstallation

@synthesize nextFieldIndex = _nextFieldIndex;
@synthesize crashHandlerDataBacking = _crashHandlerDataBacking;
@synthesize fields = _fields;
@synthesize requiredProperties = _requiredProperties;
@synthesize alertFilter = _alertFilter;

- (id) init
{
    [NSException raise:NSInternalInconsistencyException
                format:@"%@ does not support init. Subclasses must call initWithMaxReportFieldCount:requiredProperties:", [self class]];
    return nil;
}

- (id) initWithRequiredProperties:(NSArray*) requiredProperties
{
    if((self = [super init]))
    {
        self.crashHandlerDataBacking = [NSMutableData dataWithLength:sizeof(*self.crashHandlerData) +
                                        sizeof(*self.crashHandlerData->reportFields) * kMaxProperties];
        self.fields = [NSMutableDictionary dictionary];
        self.requiredProperties = requiredProperties;
    }
    return self;
}

- (void) dealloc
{
    KSCrash* handler = [KSCrash sharedInstance];
    @synchronized(handler)
    {
        if(g_crashHandlerData == self.crashHandlerData)
        {
            g_crashHandlerData = NULL;
            handler.onCrash = NULL;
        }
    }
    as_release(_crashHandlerDataBacking);
    as_release(_fields);
    as_release(_requiredProperties);
    as_release(_alertFilter);
    as_superdealloc();
}

- (CrashHandlerData*) crashHandlerData
{
    return (CrashHandlerData*)self.crashHandlerDataBacking.mutableBytes;
}

- (KSCrashInstReportField*) reportFieldForProperty:(NSString*) propertyName
{
    KSCrashInstReportField* field = [self.fields objectForKey:propertyName];
    if(field == nil)
    {
        field = [KSCrashInstReportField fieldWithIndex:self.nextFieldIndex];
        self.nextFieldIndex++;
        self.crashHandlerData->reportFieldsCount = self.nextFieldIndex;
        self.crashHandlerData->reportFields[field.index] = field.field;
        [self.fields setObject:field forKey:propertyName];
    }
    return field;
}

- (void) reportFieldForProperty:(NSString*) propertyName setKey:(id) key
{
    KSCrashInstReportField* field = [self reportFieldForProperty:propertyName];
    field.key = key;
}

- (void) reportFieldForProperty:(NSString*) propertyName setValue:(id) value
{
    KSCrashInstReportField* field = [self reportFieldForProperty:propertyName];
    field.value = value;
}

- (NSError*) validateProperties
{
    NSMutableString* errors = [NSMutableString string];
    for(NSString* propertyName in self.requiredProperties)
    {
        NSString* nextError = nil;
        @try
        {
            id value = [self valueForKey:propertyName];
            if(value == nil)
            {
                nextError = @"is nil";
            }
        }
        @catch (NSException *exception)
        {
            nextError = @"property not found";
        }
        if(nextError != nil)
        {
            if([errors length] > 0)
            {
                [errors appendString:@", "];
            }
            [errors appendFormat:@"%@ (%@)", propertyName, nextError];
        }
    }
    if([errors length] > 0)
    {
        return [NSError errorWithDomain:[[self class] description]
                                   code:0
                            description:@"Installation properties failed validation: %@", errors];
    }
    return nil;
}

- (NSString*) makeKeyPath:(NSString*) keyPath
{
    if([keyPath length] == 0)
    {
        return keyPath;
    }
    BOOL isAbsoluteKeyPath = [keyPath length] > 0 && [keyPath characterAtIndex:0] == '/';
    return isAbsoluteKeyPath ? keyPath : [@"user/" stringByAppendingString:keyPath];
}

- (NSArray*) makeKeyPaths:(NSArray*) keyPaths
{
    if([keyPaths count] == 0)
    {
        return keyPaths;
    }
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[keyPaths count]];
    for(NSString* keyPath in keyPaths)
    {
        [result addObject:[self makeKeyPath:keyPath]];
    }
    return result;
}

- (KSReportWriteCallback) onCrash
{
    @synchronized(self)
    {
        return self.crashHandlerData->userCrashCallback;
    }
}

- (void) setOnCrash:(KSReportWriteCallback)onCrash
{
    @synchronized(self)
    {
        self.crashHandlerData->userCrashCallback = onCrash;
    }
}

- (void) install
{
    KSCrash* handler = [KSCrash sharedInstance];
    @synchronized(handler)
    {
        g_crashHandlerData = self.crashHandlerData;
        handler.onCrash = kscinst_i_crashCallback;
        [handler install];
    }
}

- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSError* error = [self validateProperties];
    if(error != nil)
    {
        if(onCompletion != nil)
        {
            onCompletion(nil, NO, error);
        }
        return;
    }

    id<KSCrashReportFilter> sink = [self sink];
    if(sink == nil)
    {
        onCompletion(nil, NO, [NSError errorWithDomain:[[self class] description]
                                                  code:0
                                           description:@"Sink was nil (subclasses must implement method \"sink\")"]);
        return;
    }
    
    if(self.alertFilter != nil)
    {
        sink = [KSCrashReportFilterPipeline filterWithFilters:self.alertFilter, sink, nil];
    }

    KSCrash* handler = [KSCrash sharedInstance];
    handler.sink = sink;
    [handler sendAllReportsWithCompletion:onCompletion];
}

- (id<KSCrashReportFilter>) sink
{
    return nil;
}

- (void) addConditionalAlertWithTitle:(NSString*) title
                              message:(NSString*) message
                            yesAnswer:(NSString*) yesAnswer
                             noAnswer:(NSString*) noAnswer
{
    self.alertFilter = [KSCrashReportFilterAlert filterWithTitle:title
                                                         message:message
                                                       yesAnswer:yesAnswer
                                                        noAnswer:noAnswer];
    KSCrash* handler = [KSCrash sharedInstance];
    if(handler.deleteBehaviorAfterSendAll == KSCDeleteOnSucess)
    {
        // Better to delete always, or else the user will keep getting nagged
        // until he presses "yes"!
        handler.deleteBehaviorAfterSendAll = KSCDeleteAlways;
    }
}

- (void) addUnconditionalAlertWithTitle:(NSString*) title
                                message:(NSString*) message
                      dismissButtonText:(NSString*) dismissButtonText
{
    self.alertFilter = [KSCrashReportFilterAlert filterWithTitle:title
                                                         message:message
                                                       yesAnswer:dismissButtonText
                                                        noAnswer:nil];
}

@end
