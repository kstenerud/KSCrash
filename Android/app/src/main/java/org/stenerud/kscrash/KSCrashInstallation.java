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

import android.content.Context;

import java.io.IOException;
import java.util.List;

public class KSCrashInstallation {
    public List<KSCrashReportFilter> reportFilters;

    public KSCrashInstallation(List<KSCrashReportFilter> reportFilters) {
        this.reportFilters = reportFilters;
    }

    public void install(Context context) throws IOException {
        KSCrash.getInstance().install(context);
    }

    public void sendOutstandingReports(KSCrashReportFilter.CompletionCallback callback) {
        List reports = KSCrash.getInstance().getAllReports();
        KSCrashReportFilter pipeline = new KSCrashReportFilterPipeline(reportFilters);
        try {
            pipeline.filterReports(reports, callback);
        } catch (KSCrashReportFilteringFailedException e) {
            // TODO
            e.printStackTrace();
        }
    }
}
