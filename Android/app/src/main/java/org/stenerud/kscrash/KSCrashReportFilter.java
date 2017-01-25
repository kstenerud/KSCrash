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

import java.util.List;

/**
 * Transforms reports.
 *
 * The transformed reports are returned via the completion callback.
 *
 * Each filter implementation takes a specific data type as input and returns a possibly different
 * data type. The expected types are listed in the implementation documentation.
 */
public interface KSCrashReportFilter {
    public interface CompletionCallback {
        /**
         * Receive a notification of a completed filter operation.
         * @param reports The transformed reports.
         * @throws KSCrashReportFilteringFailedException
         */
        public void onCompletion(List reports) throws KSCrashReportFilteringFailedException;
    }

    /**
     * Filter some reports.
     *
     * @param reports The reports to filter.
     * @param completionCallback The callback to call with the filtered reports.
     * @throws KSCrashReportFilteringFailedException
     */
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException;
}
