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

import java.net.URL;
import java.util.LinkedList;
import java.util.List;

/**
 * Sends standard KSCrash reports over HTTP.
 */
public class KSCrashInstallationStandard extends KSCrashInstallation {

    /**
     * Constructor.
     *
     * @param context A context.
     * @param url The URL to post the reports to.
     */
    public KSCrashInstallationStandard(Context context, URL url) {
        super(context, generateFilters(url));
    }

    private static List<KSCrashReportFilter> generateFilters(URL url) {
        List<KSCrashReportFilter> reportFilters = new LinkedList<KSCrashReportFilter>();
        reportFilters.add(new KSCrashReportFilterJSONEncode(4));
        reportFilters.add(new KSCrashReportFilterGZipCompress());
        reportFilters.add(new KSCrashReportFilterHttp(url, "report", "json.gz"));

        return reportFilters;
    }
}
