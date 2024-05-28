//
//  KSHTTPMultipartPostBody.m
//
//  Created by Karl Stenerud on 2012-02-19.
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


#import "KSHTTPMultipartPostBody.h"

#import "NSMutableData+AppendUTF8.h"
#import "NSString+URLEncode.h"


/**
 * Represents a single field in a multipart HTTP body.
 */
@interface KSHTTPPostField: NSObject

/** This field's binary encoded contents. */
@property(nonatomic,readonly,retain) NSData* data;

/** This field's name. */
@property(nonatomic,readonly,retain) NSString* name;

/** This field's content-type. */
@property(nonatomic,readonly,retain) NSString* contentType;

/** This field's filename. */
@property(nonatomic,readonly,retain) NSString* filename;

+ (KSHTTPPostField*) data:(NSData*) data
                     name:(NSString*) name
              contentType:(NSString*) contentType
                 filename:(NSString*) filename;

- (id) initWithData:(NSData*) data
               name:(NSString*) name
        contentType:(NSString*) contentType
           filename:(NSString*) filename;

@end


@implementation KSHTTPPostField

@synthesize data = _data;
@synthesize name = _name;
@synthesize contentType = _contentType;
@synthesize filename = _filename;

+ (KSHTTPPostField*) data:(NSData*) data
                     name:(NSString*) name
              contentType:(NSString*) contentType
                 filename:(NSString*) filename
{
    return [[self alloc] initWithData:data
                                 name:name
                          contentType:contentType
                             filename:filename];
}

- (id) initWithData:(NSData*) data
               name:(NSString*) name
        contentType:(NSString*) contentType
           filename:(NSString*) filename
{
    NSParameterAssert(data);
    NSParameterAssert(name);
    
    if((self = [super init]))
    {
        _data = data;
        _name = name;
        _contentType = contentType;
        _filename = filename;
    }
    return self;
}

@end


@interface KSHTTPMultipartPostBody ()

@property(nonatomic,readwrite,retain) NSMutableArray* fields;
@property(nonatomic,readwrite,retain) NSString* boundary;

@end


@implementation KSHTTPMultipartPostBody

@synthesize contentType = _contentType;
@synthesize fields = _fields;
@synthesize boundary = _boundary;

+ (KSHTTPMultipartPostBody*) body
{
    return [[self alloc] init];
}

- (id) init
{
    if((self = [super init]))
    {
        NSString *uuid = [[NSUUID UUID] UUIDString];
        _boundary = [[uuid lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        _fields = [[NSMutableArray alloc] init];
        _contentType = [[NSString alloc] initWithFormat:@"multipart/form-data; boundary=%@", _boundary];
    }
    return self;
}

- (void) appendData:(NSData*) data
               name:(NSString*) name
        contentType:(NSString*) contentType
           filename:(NSString*) filename
{
    [_fields addObject:[KSHTTPPostField data:data
                                        name:name
                                 contentType:contentType
                                    filename:filename]];
}

- (void) appendUTF8String:(NSString*) string
                     name:(NSString*) name
              contentType:(NSString*) contentType
                 filename:(NSString*) filename
{
    const char* cString = [string cStringUsingEncoding:NSUTF8StringEncoding];
    [self appendData:[NSData dataWithBytes:cString length:strlen(cString)]
                name:name
         contentType:contentType
            filename:filename];
}

- (NSString*) toStringWithQuotesEscaped:(NSString*) value
{
    return [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

- (NSData*) data
{
    NSUInteger baseSize = 0;
    for(KSHTTPPostField* desc in _fields)
    {
        baseSize += [desc.data length] + 200;
    }
    
    NSMutableData* data = [NSMutableData dataWithCapacity:baseSize];
    BOOL firstFieldSent = NO;
    for(KSHTTPPostField* field in _fields)
    {
        if (firstFieldSent) {
            [data appendUTF8String:@"\r\n"];
        } else {
            firstFieldSent = YES;
        }
        [data appendUTF8Format:@"--%@\r\n", _boundary];
        if(field.filename != nil)
        {
            [data appendUTF8Format:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",
             [self toStringWithQuotesEscaped:field.name],
             [self toStringWithQuotesEscaped:field.filename]];
        }
        else
        {
            [data appendUTF8Format:@"Content-Disposition: form-data; name=\"%@\"\r\n",
             [self toStringWithQuotesEscaped:field.name]];
        }
        if(field.contentType != nil)
        {
            [data appendUTF8Format:@"Content-Type: %@\r\n", field.contentType];
        }
        [data appendUTF8Format:@"\r\n", _boundary];
        [data appendData:field.data];
    }
    [data appendUTF8Format:@"\r\n--%@--\r\n", _boundary];
    
    return data;
}

@end

