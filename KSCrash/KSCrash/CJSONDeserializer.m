//
//  CJSONDeserializer.m
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

#import "CJSONDeserializer.h"

NSString *const kJSONDeserializerErrorDomain = @"CJSONDeserializerErrorDomain";

typedef struct
    {
    void *location;
    NSUInteger length;
    } PtrRange;

@interface CJSONDeserializer () {
    NSData *_data;
    NSUInteger _scanLocation;
    char *_end;
    char *_current;
    char *_start;
    NSMutableData *_scratchData;
    CFMutableDictionaryRef _stringsByHash;
    }
@end

@implementation CJSONDeserializer

#pragma mark -

+ (CJSONDeserializer *)deserializer
    {
    return ([[self alloc] init]);
    }

- (id)init
    {
    if ((self = [super init]) != NULL)
        {
        _nullObject = [NSNull null];
        _options = kJSONDeserializationOptions_Default;

        CFDictionaryKeyCallBacks theCallbacks = {};
        _stringsByHash = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &theCallbacks, &kCFTypeDictionaryValueCallBacks);
        }
    return (self);
    }

- (void)dealloc
    {
    CFRelease(_stringsByHash);
    }

#pragma mark -

- (id)deserialize:(NSData *)inData error:(NSError **)outError
    {
    if ([self _setData:inData error:outError] == NO)
        {
        return (NULL);
        }
    id theObject = NULL;
    if ([self _scanJSONObject:&theObject sharedKeySet:NULL error:outError] == YES)
        {
        if (!(_options & kJSONDeserializationOptions_AllowFragments))
            {
            if ([theObject isKindOfClass:[NSArray class]] == NO && [theObject isKindOfClass:[NSDictionary class]] == NO)
                {
                if (outError != NULL)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_ScanningFragmentsNotAllowed description:@"Scanning fragments not allowed."];
                    return(NULL);
                    }
                }
            }
        else
            {
            if (theObject == [NSNull null])
                {
                theObject = _nullObject;
                }
            }
        }

    // If we haven't consumed all the data...
    if (_current != _end)
        {
        // Skip any remaining whitespace...
        _current = _SkipWhiteSpace(_current, _end);
        // And then error if we still haven't consumed all data...
        if (_current != _end)
            {
            if (outError != NULL)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DidNotConsumeAllData description:@"Did not consume all data."];
                }
            return(NULL);
            }
        }

    return (theObject);
    }

- (id)deserializeAsDictionary:(NSData *)inData error:(NSError **)outError
    {
    if ([self _setData:inData error:outError] == NO)
        {
        return (NULL);
        }
    NSDictionary *theDictionary = NULL;
    [self _scanJSONDictionary:&theDictionary sharedKeySet:NULL error:outError];
    return(theDictionary);
    }

- (id)deserializeAsArray:(NSData *)inData error:(NSError **)outError
    {
    if ([self _setData:inData error:outError] == NO)
        {
        return (NULL);
        }
    NSArray *theArray = NULL;
    [self _scanJSONArray:&theArray error:outError];
    return(theArray);
    }

#pragma mark -

- (NSUInteger)scanLocation
    {
    return (_current - _start);
    }

- (BOOL)_setData:(NSData *)inData error:(NSError **)outError;
    {
    if (_data == inData)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_NothingToScan underlyingError:NULL description:@"Have no data to scan."];
            }
        return(NO);
        }

    NSData *theData = inData;
    if (theData.length >= 4)
        {
        // This code is lame, but it works. Because the first character of any JSON string will always be a (ascii) control character we can work out the Unicode encoding by the bit pattern. See section 3 of http://www.ietf.org/rfc/rfc4627.txt
        const UInt8 *theChars = theData.bytes;
        NSStringEncoding theEncoding = NSUTF8StringEncoding;
        if (theChars[0] != 0 && theChars[1] == 0)
            {
            if (theChars[2] != 0 && theChars[3] == 0)
                {
                theEncoding = NSUTF16LittleEndianStringEncoding;
                }
            else if (theChars[2] == 0 && theChars[3] == 0)
                {
                theEncoding = NSUTF32LittleEndianStringEncoding;
                }
            }
        else if (theChars[0] == 0 && theChars[2] == 0 && theChars[3] != 0)
            {
            if (theChars[1] == 0)
                {
                theEncoding = NSUTF32BigEndianStringEncoding;
                }
            else if (theChars[1] != 0)
                {
                theEncoding = NSUTF16BigEndianStringEncoding;
                }
            }
        else
            {
            const UInt32 *C32 = (UInt32 *)theChars;
            if (*C32 == CFSwapInt32HostToBig(0x0000FEFF) || *C32 == CFSwapInt32HostToBig(0xFFFE0000))
                {
                theEncoding = NSUTF32StringEncoding;
                }
            else
                {
                const uint16_t *C16 = (UInt16 *)theChars;
                if (*C16 == CFSwapInt16HostToBig(0xFEFF) || *C16 == CFSwapInt16HostToBig(0xFFFE))
                    {
                    theEncoding = NSUTF16StringEncoding;
                    }
                }
            }

        if (theEncoding != NSUTF8StringEncoding)
            {
            NSString *theString = [[NSString alloc] initWithData:theData encoding:theEncoding];
            if (theString == NULL)
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotDecodeData description:NULL];
                    }
                return(NO);
                }
            theData = [theString dataUsingEncoding:NSUTF8StringEncoding];
            }
        }

    _data = theData;

    _start = (char *) _data.bytes;
    _end = _start + _data.length;
    _current = _start;
    _scratchData = NULL;

    return (YES);
    }

#pragma mark -

- (BOOL)_scanJSONObject:(id *)outObject sharedKeySet:(id *)ioSharedKeySet error:(NSError **)outError
    {
    BOOL theResult;

    _current = _SkipWhiteSpace(_current, _end);

    if (_current >= _end)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not read JSON object, input exhausted."];
            }
        return(NO);
        }

    id theObject = NULL;

    const char C = *_current;
    switch (C)
        {
        case 't':
            {
            theResult = _ScanUTF8String(self, "true", 4);
            if (theResult != NO)
                {
                theObject = (__bridge id) kCFBooleanTrue;
                }
            else
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
                    }
                }
            break;
            }
        case 'f':
            {
            theResult = _ScanUTF8String(self, "false", 5);
            if (theResult != NO)
                {
                theObject = (__bridge id) kCFBooleanFalse;
                }
            else
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
                    }
                }
            }
            break;
        case 'n':
            {
            theResult = _ScanUTF8String(self, "null", 4);
            if (theResult != NO)
                {
                theObject = _nullObject ?: [NSNull null];
                }
            else
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
                    }
                }
            }
            break;
        case '\"':
        case '\'':
            {
            theResult = [self _scanJSONStringConstant:&theObject key:NO error:outError];
            }
            break;
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
        case '-':
            {
            theResult = [self _scanJSONNumberConstant:&theObject error:outError];
            }
            break;
        case '{':
            {
            theResult = [self _scanJSONDictionary:&theObject sharedKeySet:ioSharedKeySet error:outError];
            }
            break;
        case '[':
            {
            theResult = [self _scanJSONArray:&theObject error:outError];
            }
            break;
        default:
            {
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
                }
            return(NO);
            }
            break;
        }

    if (outObject != NULL)
        {
        *outObject = theObject;
        }

    return(theResult);
    }

- (BOOL)_scanJSONDictionary:(NSDictionary **)outDictionary sharedKeySet:(id *)ioSharedKeySet error:(NSError **)outError
    {
    NSUInteger theScanLocation = _current - _start;

    _current = _SkipWhiteSpace(_current, _end);

    if (_ScanCharacter(self, '{') == NO)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryStartCharacterMissing description:@"Could not scan dictionary. Dictionary that does not start with '{' character."];
            }
        return (NO);
        }

    NSMutableDictionary *theDictionary = NULL;
    if (ioSharedKeySet != NULL && *ioSharedKeySet != NULL)
        {
        theDictionary = [NSMutableDictionary dictionaryWithSharedKeySet:*ioSharedKeySet];
        }
    else
        {
        theDictionary = [NSMutableDictionary dictionary];
        }

    if (theDictionary == NULL)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_FailedToCreateObject description:@"Could not scan dictionary. Could not allow object."];
            }
        return(NO);
        }

    NSString *theKey = NULL;
    id theValue = NULL;

    while (*_current != '}')
        {
        _current = _SkipWhiteSpace(_current, _end);

        if (*_current == '}')
            {
            break;
            }

        if ([self _scanJSONStringConstant:&theKey key:YES error:outError] == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyScanFailed description:@"Could not scan dictionary. Failed to scan a key."];
                }
            return (NO);
            }

        _current = _SkipWhiteSpace(_current, _end);

        if (_ScanCharacter(self, ':') == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyNotTerminated description:@"Could not scan dictionary. Key was not terminated with a ':' character."];
                }
            return (NO);
            }

        if ([self _scanJSONObject:&theValue sharedKeySet:NULL error:outError] == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryValueScanFailed description:@"Could not scan dictionary. Failed to scan a value."];
                }
            return (NO);
            }

        if (_nullObject == NULL && theValue == [NSNull null])
            {
            continue;
            }

        if (theKey == NULL)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyScanFailed description:@"Could not scan dictionary. Failed to scan a key."];
            return(NO);
            }
        if (theValue == NULL)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryValueScanFailed description:@"Could not scan dictionary. Failed to scan a value."];
            return(NO);
            }
        CFDictionarySetValue((__bridge CFMutableDictionaryRef)theDictionary, (__bridge void *)theKey, (__bridge void *)theValue);

        _current = _SkipWhiteSpace(_current, _end);

        if (_ScanCharacter(self, ',') == NO)
            {
            if (*_current != '}')
                {
                _current = _start + theScanLocation;
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_DictionaryNotTerminated description:@"kJSONDeserializerErrorCode_DictionaryKeyValuePairNoDelimiter"];
                    }
                return (NO);
                }
            break;
            }
        else
            {
            _current = _SkipWhiteSpace(_current, _end);

            if (*_current == '}')
                {
                break;
                }
            }
        }

    if (_ScanCharacter(self, '}') == NO)
        {
        _current = _start + theScanLocation;
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryNotTerminated description:@"Could not scan dictionary. Dictionary not terminated by a '}' character."];
            }
        return (NO);
        }

    if (outDictionary != NULL)
        {
        if (_options & kJSONDeserializationOptions_MutableContainers)
            {
            *outDictionary = theDictionary;
            }
        else
            {
            *outDictionary = [theDictionary copy];
            }
        }

    if (ioSharedKeySet != NULL && *ioSharedKeySet == NULL)
        {
        *ioSharedKeySet = [NSMutableDictionary sharedKeySetForKeys:[theDictionary allKeys]];
        }

    return (YES);
    }

- (BOOL)_scanJSONArray:(NSArray **)outArray error:(NSError **)outError
    {
    NSUInteger theScanLocation = _current - _start;

    _current = _SkipWhiteSpace(_current, _end);

    if (_ScanCharacter(self, '[') == NO)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_ArrayStartCharacterMissing description:@"Could not scan array. Array not started by a '[' character."];
            }
        return (NO);
        }

    NSMutableArray *theArray = (__bridge_transfer NSMutableArray *) CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

    _current = _SkipWhiteSpace(_current, _end);

    id theSharedKeySet = NULL;

    NSString *theValue = NULL;
    while (*_current != ']')
        {
        if ([self _scanJSONObject:&theValue sharedKeySet:&theSharedKeySet error:outError] == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_ArrayValueScanFailed underlyingError:NULL description:@"Could not scan array. Could not scan a value."];
                }
            return (NO);
            }

        if (theValue == NULL)
            {
            if (_nullObject != NULL)
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_ArrayValueIsNull description:@"Could not scan array. Value is NULL."];
                    }
                return (NO);
                }
            }
        else
            {
            CFArrayAppendValue((__bridge CFMutableArrayRef) theArray, (__bridge void *) theValue);
            }

        _current = _SkipWhiteSpace(_current, _end);

        if (_ScanCharacter(self, ',') == NO)
            {
            _current = _SkipWhiteSpace(_current, _end);

            if (*_current != ']')
                {
                _current = _start + theScanLocation;
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_ArrayNotTerminated description:@"Could not scan array. Array not terminated by a ']' character."];
                    }
                return (NO);
                }

            break;
            }

        _current = _SkipWhiteSpace(_current, _end);
        }

    if (_ScanCharacter(self, ']') == NO)
        {
        _current = _start + theScanLocation;
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_ArrayNotTerminated description:@"Could not scan array. Array not terminated by a ']' character."];
            }
        return (NO);
        }

    if (outArray != NULL)
        {
        if (_options & kJSONDeserializationOptions_MutableContainers)
            {
            *outArray = theArray;
            }
        else
            {
            *outArray = [theArray copy];
            }
        }
    return (YES);
    }

- (BOOL)_scanJSONStringConstant:(NSString **)outStringConstant key:(BOOL)inKey error:(NSError **)outError
    {
    #pragma unused (inKey)

    NSUInteger theScanLocation = _current - _start;

    if (_ScanCharacter(self, '"') == NO)
        {
        _current = _start + theScanLocation;
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_StringNotStartedWithBackslash description:@"Could not scan string constant. String not started by a '\"' character."];
            }
        return (NO);
        }

    if (_scratchData == NULL)
        {
        _scratchData = [NSMutableData dataWithCapacity:8 * 1024];
        }
    else
        {
        [_scratchData setLength:0];
        }

    PtrRange thePtrRange;
    while (_ScanCharacter(self, '"') == NO)
        {
        if ([self _scanNotQuoteCharactersIntoRange:&thePtrRange])
            {
            [_scratchData appendBytes:thePtrRange.location length:thePtrRange.length];
            }
        else if (_ScanCharacter(self, '\\') == YES)
            {
            char theCharacter = *_current++;
            switch (theCharacter)
                {
                case '"':
                case '\\':
                case '/':
                    break;
                case 'b':
                    theCharacter = '\b';
                    break;
                case 'f':
                    theCharacter = '\f';
                    break;
                case 'n':
                    theCharacter = '\n';
                    break;
                case 'r':
                    theCharacter = '\r';
                    break;
                case 't':
                    theCharacter = '\t';
                    break;
                case 'u':
                    {
                    UInt8 theBuffer[4];
                    size_t theLength = ConvertEscapes(self, theBuffer);
                    if (theLength == 0)
                        {
                        if (outError)
                            {
                            *outError = [self _error:kJSONDeserializerErrorCode_StringBadEscaping description:@"Could not decode string escape code."];
                            }
                        return(NO);
                        }
                    [_scratchData appendBytes:&theBuffer length:theLength];
                    theCharacter = 0;
                    }
                    break;
                default:
                    {
                    if (!(_options & kJSONDeserializationOptions_LaxEscapeCodes))
                        {
                        _current = _start + theScanLocation;
                        if (outError)
                            {
                            *outError = [self _error:kJSONDeserializerErrorCode_StringUnknownEscapeCode description:@"Could not scan string constant. Unknown escape code."];
                            }
                        return (NO);
                        }
                    }
                    break;
                }
            if (theCharacter != 0)
                {
                [_scratchData appendBytes:&theCharacter length:1];
                }
            }
        else
            {
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_StringNotTerminated description:@"Could not scan string constant. No terminating double quote character."];
                }
            return (NO);
            }
        }

    NSString *theString = NULL;
    if ([_scratchData length] < 80)
        {
        NSUInteger hash = [_scratchData hash];
        NSString *theFoundString = (__bridge NSString *)CFDictionaryGetValue(_stringsByHash, (const void *) hash);
        BOOL theFoundFlag = NO;
        if (theFoundString != NULL)
            {
            theString = (__bridge_transfer NSString *)CFStringCreateWithBytes(kCFAllocatorDefault, [_scratchData bytes], [_scratchData length], kCFStringEncodingUTF8, NO);
            if (theString == NULL)
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_StringCouldNotBeCreated description:@"Could not create string."];
                    }
                return(NO);
                }
            if ([theFoundString isEqualToString:theString] == YES)
                {
                theFoundFlag = YES;
                }
            }

        if (theFoundFlag == NO)
            {
            if (theString == NULL)
                {
                theString = (__bridge_transfer NSString *)CFStringCreateWithBytes(kCFAllocatorDefault, [_scratchData bytes], [_scratchData length], kCFStringEncodingUTF8, NO);
                if (theString == NULL)
                    {
                    if (outError)
                        {
                        *outError = [self _error:kJSONDeserializerErrorCode_StringCouldNotBeCreated description:@"Could not create string."];
                        }
                    return(NO);
                    }
                }
            if (_options & kJSONDeserializationOptions_MutableLeaves)
                {
                theString = [theString mutableCopy];
                }
            CFDictionarySetValue(_stringsByHash, (const void *) hash, (__bridge void *) theString);
            }
        }
    else
        {
        theString = (__bridge_transfer NSString *)CFStringCreateWithBytes(kCFAllocatorDefault, [_scratchData bytes], [_scratchData length], kCFStringEncodingUTF8, NO);
        if (theString == NULL)
            {
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_StringCouldNotBeCreated description:@"Could not create string."];
                }
            return(NO);
            }
        if (_options & kJSONDeserializationOptions_MutableLeaves)
            {
            theString = [theString mutableCopy];
            }
        }

    if (outStringConstant != NULL)
        {
        *outStringConstant = theString;
        }

    return (YES);
    }

- (BOOL)_scanJSONNumberConstant:(NSNumber **)outValue error:(NSError **)outError
    {
    _current = _SkipWhiteSpace(_current, _end);

    PtrRange theRange;
    if ([self _scanDoubleCharactersIntoRange:&theRange] == NO)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_NumberNotScannable description:@"Could not scan number constant."];
            }
        return (NO);
        }

    NSNumber *theValue = ScanNumber(theRange.location, theRange.length, NULL);
    if (theValue == NULL)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_NumberNotScannable description:@"Could not scan number constant."];
            }
        return (NO);
        }

    if (outValue)
        {
        *outValue = theValue;
        }

    return (YES);
    }

#pragma mark -

- (BOOL)_scanNotQuoteCharactersIntoRange:(PtrRange *)outValue
    {
    char *P;
    for (P = _current; P < _end && *P != '\"' && *P != '\\'; ++P)
        {
        // We're just iterating...
        }

    if (P == _current)
        {
        return (NO);
        }

    if (outValue)
        {
        *outValue = (PtrRange) {.location = _current, .length = P - _current};
        }

    _current = P;

    return (YES);
    }

#pragma mark -

- (BOOL)_scanDoubleCharactersIntoRange:(PtrRange *)outRange
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winitializer-overrides"
    static BOOL double_characters[256] = {
        [0 ... 255] = NO,
        ['0' ... '9'] = YES,
        ['e'] = YES,
        ['E'] = YES,
        ['-'] = YES,
        ['+'] = YES,
        ['.'] = YES,
        };
#pragma clang diagnostic pop

    char *P;
    for (P = _current; P < _end && double_characters[*P] == YES; ++P)
        {
        // Just iterate...
        }

    if (P == _current)
        {
        return (NO);
        }

    if (outRange)
        {
        *outRange = (PtrRange) {.location = _current, .length = P - _current};
        }

    _current = P;

    return (YES);
    }

#pragma mark -

- (NSDictionary *)_userInfoForScanLocation
    {
    NSUInteger theLine = 0;
    const char *theLineStart = _start;
    for (const char *C = _start; C < _current; ++C)
        {
        if (*C == '\n' || *C == '\r')
            {
            theLineStart = C - 1;
            ++theLine;
            }
        }

    NSUInteger theCharacter = _current - theLineStart;

    NSRange theStartRange = NSIntersectionRange((NSRange) {.location = MAX((NSInteger) self.scanLocation - 20, 0), .length = 20 + (NSInteger) self.scanLocation - 20}, (NSRange) {.location = 0, .length = _data.length});
    NSRange theEndRange = NSIntersectionRange((NSRange) {.location = self.scanLocation, .length = 20}, (NSRange) {.location = 0, .length = _data.length});

    NSString *theSnippet = [NSString stringWithFormat:@"%@!HERE>!%@",
        [[NSString alloc] initWithData:[_data subdataWithRange:theStartRange] encoding:NSUTF8StringEncoding],
        [[NSString alloc] initWithData:[_data subdataWithRange:theEndRange] encoding:NSUTF8StringEncoding]
        ];

    NSDictionary *theUserInfo;
    theUserInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInteger:theLine], @"line",
        [NSNumber numberWithUnsignedInteger:theCharacter], @"character",
        [NSNumber numberWithUnsignedInteger:self.scanLocation], @"location",
        theSnippet, @"snippet",
        NULL];
    return (theUserInfo);
    }

- (NSError *)_error:(NSInteger)inCode underlyingError:(NSError *)inUnderlyingError description:(NSString *)inDescription
    {
    NSMutableDictionary *theUserInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        inDescription, NSLocalizedDescriptionKey,
        NULL];
    [theUserInfo addEntriesFromDictionary:self._userInfoForScanLocation];
    if (inUnderlyingError)
        {
        theUserInfo[NSUnderlyingErrorKey] = inUnderlyingError;
        }
    NSError *theError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:inCode userInfo:theUserInfo];
    return (theError);
    }

- (NSError *)_error:(NSInteger)inCode description:(NSString *)inDescription
    {
    return ([self _error:inCode underlyingError:NULL description:inDescription]);
    }

#pragma mark -

inline static char *_SkipWhiteSpace(char *_current, char *_end)
    {
    char *P;
    for (P = _current; P < _end && isspace(*P); ++P)
        {
        // Just iterate...
        }

    return (P);
    }

static inline BOOL _ScanCharacter(CJSONDeserializer *deserializer, char inCharacter)
    {
    char theCharacter = *deserializer->_current;
    if (theCharacter == inCharacter)
        {
        ++deserializer->_current;
        return (YES);
        }
    else
        {
        return (NO);
        }
    }

static inline BOOL _ScanUTF8String(CJSONDeserializer *deserializer, const char *inString, size_t inLength)
    {
    if ((size_t) (deserializer->_end - deserializer->_current) < inLength)
        {
        return (NO);
        }
    if (strncmp(deserializer->_current, inString, inLength) == 0)
        {
        deserializer->_current += inLength;
        return (YES);
        }
    return (NO);
    }

static size_t ConvertEscapes(CJSONDeserializer *deserializer, UInt8 outBuffer[static 4])
    {
    if (deserializer->_end - deserializer->_current < 4)
        {
        return(0);
        }
    UInt32 C = hexdec(deserializer->_current, 4);
    deserializer->_current += 4;

    if (C >= 0xD800 && C <= 0xDBFF)
        {
        if (deserializer->_end - deserializer->_current < 6)
            {
            return(0);
            }
        if ((*deserializer->_current++) != '\\')
            {
            return(0);
            }
        if ((*deserializer->_current++) != 'u')
            {
            return(0);
            }

        UInt32 C2 = hexdec(deserializer->_current, 4);
        deserializer->_current += 4;

        if (C2 >= 0xDC00 && C2 <= 0xDFFF)
            {
            C = ((C - 0xD800) << 10) + (C2 - 0xDC00) + 0x0010000UL;
            }
        else
            {
            return(0);
            }
        }
    else if (C >= 0xDC00 && C <= 0xDFFF)
        {
        return(0);
        }

    int bytesToWrite;
    if (C < 0x80)
        {
        bytesToWrite = 1;
        }
    else if (C < 0x800)
        {
        bytesToWrite = 2;
        }
    else if (C < 0x10000)
        {
        bytesToWrite = 3;
        }
    else if (C < 0x110000)
        {
        bytesToWrite = 4;
        }
    else
        {
        return(0);
        }

    static const UInt8 firstByteMark[7] = { 0x00, 0x00, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC };
    UInt8 *target = outBuffer + bytesToWrite;
    const UInt32 byteMask = 0xBF;
    const UInt32 byteMark = 0x80;
    switch (bytesToWrite)
        {
        case 4:
            *--target = ((C | byteMark) & byteMask);
            C >>= 6;
        case 3:
            *--target = ((C | byteMark) & byteMask);
            C >>= 6;
        case 2:
            *--target = ((C | byteMark) & byteMask);
            C >>= 6;
        case 1:
            *--target =  (C | firstByteMark[bytesToWrite]);
        }

    return(bytesToWrite);
    }

// Adapted from http://stackoverflow.com/a/11068850
/** 
 * @brief convert a hexidecimal string to a signed long
 * will not produce or process negative numbers except 
 * to signal error.
 * 
 * @param hex without decoration, case insensative. 
 * 
 * @return -1 on error, or result (max sizeof(long)-1 bits)
 */
static int hexdec(const char *hex, int len)
    {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Winitializer-overrides"
    static const int hextable[] = {
       [0 ... 255] = -1,                     // bit aligned access into this table is considerably
       ['0'] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, // faster for most modern processors,
       ['A'] = 10, 11, 12, 13, 14, 15,       // for the space conscious, reduce to
       ['a'] = 10, 11, 12, 13, 14, 15        // signed char.
    };
    #pragma clang diagnostic pop

    int ret = 0;
    if (len > 0)
        {
        while (*hex && ret >= 0 && (len--))
            {
            ret = (ret << 4) | hextable[*hex++];
            }
        }
    else
        {
        while (*hex && ret >= 0)
            {
            ret = (ret << 4) | hextable[*hex++];
            }
        }
    return ret; 
    }

static NSNumber *ScanNumber(const char *start, size_t length, NSError **outError)
    {
    if (length < 1)
        {
        goto error;
        }

    const char *P = start;
    const char *end = start + length;

    // Scan for a leading - character.
    BOOL negative = NO;
    if (*P == '-')
        {
        negative = YES;
        ++P;
        }

    // Scan for integer portion
    UInt64 integer = 0;
    int integer_digits = 0;
    while (P != end && isdigit(*P))
        {
        if (integer > (UINTMAX_MAX / 10ULL))
            {
            goto fallback;
            }
        integer *= 10ULL;
        integer += *P - '0';
        ++integer_digits;
        ++P;
        }

    // If we scan a '.' character scan for fraction portion.
    UInt64 frac = 0;
    int frac_digits = 0;
    if (P != end && *P == '.')
        {
        ++P;
        while (P != end && isdigit(*P))
            {
            if (frac >= (UINTMAX_MAX / 10ULL))
                {
                goto fallback;
                }
            frac *= 10ULL;
            frac += *P - '0';
            ++frac_digits;
            ++P;
            }
        }

    // If we scan no integer digits and no fraction digits this isn't good (generally strings like "." or ".e10")
    if (integer_digits == 0 && frac_digits == 0)
        {
        goto error;
        }

    // If we scan an 'e' character scan for '+' or '-' then scan exponent portion.
    BOOL negativeExponent = NO;
    UInt64 exponent = 0;
    if (P != end && (*P == 'e' || *P == 'E'))
        {
        ++P;
        if (P != end && *P == '-')
            {
            ++P;
            negativeExponent = YES;
            }
        else if (P != end && *P == '+')
            {
            ++P;
            }

        while (P != end && isdigit(*P))
            {
            if (exponent > (UINTMAX_MAX / 10))
                {
                goto fallback;
                }
            exponent *= 10;
            exponent += *P - '0';
            ++P;
            }
        }

    // If we haven't scanned the entire length something has gone wrong
    if (P != end)
        {
        goto error;
        }

    // If we have no fraction and no exponent we're obviously an integer otherwise we're a number...
    if (frac == 0 && exponent == 0)
        {
        if (negative == NO)
            {
            return([NSNumber numberWithUnsignedLongLong:integer]);
            }
        else
            {
            if (integer >= INT64_MAX)
                {
                goto fallback;
                }
            return([NSNumber numberWithLongLong:-(long long)integer]);
            }
        }
    else
        {
        double D = (double)integer;
        if (frac_digits > 0)
            {
            double double_fract = frac / pow(10, frac_digits);
            D += double_fract;
            }
        if (negative)
            {
            D *= -1;
            }
        if (D != 0.0 && exponent != 0)
            {
            D *= pow(10, negativeExponent ? -(double)exponent : exponent);
            }

        if (isinf(D) || isnan(D))
            {
            goto fallback;
            }

        return([NSNumber numberWithDouble:D]);
        }


fallback: {
        NSString *theString = [[NSString alloc] initWithBytes:start length:length encoding:NSASCIIStringEncoding];
        NSLocale *theLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        NSDecimalNumber *theDecimalNumber = [NSDecimalNumber decimalNumberWithString:theString locale:theLocale ];
        return(theDecimalNumber);
        }
error: {
        if (outError != NULL)
            {
            *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_NumberNotScannable userInfo:@{ NSLocalizedDescriptionKey: @"Could not scan number constant." }];
            }
        return(NULL);
        }
    }


@end
