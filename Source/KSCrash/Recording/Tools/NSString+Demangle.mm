//
//  NSMutableData+AppendUTF8.m
//
//  Created by Karl Stenerud on 2012-02-26.
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


#import "NSString+Demangle.h"
#import "Demangle.h"
#include <cxxabi.h>

@implementation NSString (Demangle)

- (NSString*) demangledAsSwift
{
    swift::Demangle::DemangleOptions options = swift::Demangle::DemangleOptions::SimplifiedUIDemangleOptions();
    std::string demangled = swift::Demangle::demangleSymbolAsString(self.UTF8String, options);
    if(demangled.length() == 0)
    {
        return nil;
    }
    return [NSString stringWithUTF8String:demangled.c_str()];
}

- (NSString*) demangledAsCPP
{
    NSString* result = nil;
    int status = 0;
    char* demangled = __cxxabiv1::__cxa_demangle(self.UTF8String, NULL, NULL, &status);

    if(status == 0 && demangled != NULL)
    {
        result = [NSString stringWithUTF8String:demangled];
    }

    if(demangled != NULL)
    {
        free(demangled);
    }

    return result;
}

@end

@interface NSString_Demangle_GH992D : NSObject @end @implementation NSString_Demangle_GH992D @end
