//
//  KSDebug.c
//
//  Created by Karl Stenerud on 2012-01-29.
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


#include "KSDebug.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>


/** Check if the current process is being traced or not.
 *
 * @return true if we're being traced.
 */
bool ksdebug_isBeingTraced(void)
{
    const char* filename = "/proc/self/status";
    int fd = open(filename, O_RDONLY);
    if(fd < 0)
    {
        KSLOG_ERROR("Error opening %s: %s", filename, strerror(errno));
        return false;
    }

    char buffer[1000];
    int bytesRead = read(fd, buffer, sizeof(buffer) - 1);
    close(fd);
    if(bytesRead <= 0)
    {
        KSLOG_ERROR("Error reading %s: %s", filename, strerror(errno));
        return false;
    }

    buffer[bytesRead] = 0;
    const char tracerPidText[] = "TracerPid:";
    const char* tracerPointer = strstr(buffer, tracerPidText);
    if(tracerPointer == NULL)
    {
        return false;
    }

    tracerPointer += sizeof(tracerPidText);
    return atoi(tracerPointer) > 0;
}
