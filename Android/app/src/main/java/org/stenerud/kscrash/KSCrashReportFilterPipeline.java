//
//  Copyright (c) 2017 Karl Stenerud. All rights reserved.
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

package org.stenerud.kscrash;

import java.util.Iterator;
import java.util.List;

/**
 * Create a pipeline of filters that get called one after the other.
 * The output of one filter is fed as input to the next.
 *
 * Input: Any
 * Output: Any
 */
public class KSCrashReportFilterPipeline implements KSCrashReportFilter {
    private List<KSCrashReportFilter> filters;

    public KSCrashReportFilterPipeline(List<KSCrashReportFilter> filters) {
        this.filters = filters;
    }

    @Override
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException {
        runNextFilter(reports, filters.iterator(), completionCallback);
    }

    private void runNextFilter(List incomingReports,
                               final Iterator<KSCrashReportFilter> iterator,
                               final CompletionCallback finalCallback) throws KSCrashReportFilteringFailedException {
        if(iterator.hasNext())
        {
            KSCrashReportFilter filter = iterator.next();
            filter.filterReports(incomingReports, new KSCrashReportFilter.CompletionCallback() {
                @Override
                public void onCompletion(List reports) throws KSCrashReportFilteringFailedException {
                    runNextFilter(reports, iterator, finalCallback);
                }
            });
        }
        else
        {
            finalCallback.onCompletion(incomingReports);
        }
    }
}
