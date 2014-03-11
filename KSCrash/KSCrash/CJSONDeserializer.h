//
//  CJSONDeserializer.h
//  TouchCode
//
//  Created by Jonathan Wight on 12/15/2005.
//  Copyright 2005 toxicsoftware.com. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import <Foundation/Foundation.h>

extern NSString *const kJSONDeserializerErrorDomain /* = @"CJSONDeserializerErrorDomain" */;

typedef enum {
    
    // Fundamental scanning errors
    kJSONDeserializerErrorCode_NothingToScan = -11,
    kJSONDeserializerErrorCode_CouldNotDecodeData = -12,
    kJSONDeserializerErrorCode_CouldNotScanObject = -15,
    kJSONDeserializerErrorCode_ScanningFragmentsNotAllowed = -16,
    kJSONDeserializerErrorCode_DidNotConsumeAllData = -17,
    kJSONDeserializerErrorCode_FailedToCreateObject = -18,

    // Dictionary scanning
    kJSONDeserializerErrorCode_DictionaryStartCharacterMissing = -101,
    kJSONDeserializerErrorCode_DictionaryKeyScanFailed = -102,
    kJSONDeserializerErrorCode_DictionaryKeyNotTerminated = -103,
    kJSONDeserializerErrorCode_DictionaryValueScanFailed = -104,
    kJSONDeserializerErrorCode_DictionaryNotTerminated = -106,
    
    // Array scanning
    kJSONDeserializerErrorCode_ArrayStartCharacterMissing = -201,
    kJSONDeserializerErrorCode_ArrayValueScanFailed = -202,
    kJSONDeserializerErrorCode_ArrayValueIsNull = -203,
    kJSONDeserializerErrorCode_ArrayNotTerminated = -204,
    
    // String scanning
    kJSONDeserializerErrorCode_StringNotStartedWithBackslash = -301,
    kJSONDeserializerErrorCode_StringUnicodeNotDecoded = -302,
    kJSONDeserializerErrorCode_StringUnknownEscapeCode = -303,
    kJSONDeserializerErrorCode_StringNotTerminated = -304,
    kJSONDeserializerErrorCode_StringBadEscaping = -305,
    kJSONDeserializerErrorCode_StringCouldNotBeCreated = -306,

    // Number scanning
    kJSONDeserializerErrorCode_NumberNotScannable = -401
    
} EJSONDeserializerErrorCode;

enum {
    // The first three flags map to the corresponding NSJSONSerialization flags.
    kJSONDeserializationOptions_MutableContainers = (1UL << 0),
    kJSONDeserializationOptions_MutableLeaves = (1UL << 1),
    kJSONDeserializationOptions_AllowFragments = (1UL << 2),
    kJSONDeserializationOptions_LaxEscapeCodes = (1UL << 3),
    kJSONDeserializationOptions_Default = kJSONDeserializationOptions_MutableContainers,
};
typedef NSUInteger EJSONDeserializationOptions;

@interface CJSONDeserializer : NSObject

/// Object to return instead when a null encountered in the JSON. Defaults to NSNull. Setting to null causes the deserializer to skip null values.
@property (readwrite, nonatomic, strong) id nullObject;

/// JSON must be encoded in Unicode (UTF-8, UTF-16 or UTF-32). Use this if you expect to get the JSON in another encoding.

@property (readwrite, nonatomic, assign) EJSONDeserializationOptions options;

+ (CJSONDeserializer *)deserializer;

- (id)deserialize:(NSData *)inData error:(NSError **)outError;

- (id)deserializeAsDictionary:(NSData *)inData error:(NSError **)outError;
- (id)deserializeAsArray:(NSData *)inData error:(NSError **)outError;

@end
