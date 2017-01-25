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
import android.os.AsyncTask;
import android.util.Log;

import java.io.IOException;
import java.util.List;

/**
 * The installation is the primary user-facing interface to the crash handling system.
 * A user instantiates an installation, optionally configures it, then calls install to
 * start handling crashes.
 *
 * sendOutstandingReports() will send any reports for crashes that occurred previously.
 */
public class KSCrashInstallation {
    private Context context;
    private List<KSCrashReportFilter> reportFilters;

    public KSCrashInstallation(Context context, List<KSCrashReportFilter> reportFilters) {
        this.context = context;
        this.reportFilters = reportFilters;
    }

    public void install() throws IOException {
        KSCrash.getInstance().install(this.context);
    }

    /**
     * More generalized version of this method for debugging purposes. Consider using one of the
     * other two forms instead.
     *
     * @param reports The reports to send.
     * @param callback Called upon successful completion (null = default handler - delete all reports).
     */
    public void sendOutstandingReports(final List reports, KSCrashReportFilter.CompletionCallback callback) {
        if(reports.size() > 0) {
            if (callback == null) {
                callback = new KSCrashReportFilter.CompletionCallback() {
                    @Override
                    public void onCompletion(List reports) throws KSCrashReportFilteringFailedException {
                        KSCrash.getInstance().deleteAllReports();
                    }
                };
            }
            final KSCrashReportFilter.CompletionCallback lastCallback = callback;
            final KSCrashReportFilter pipeline = new KSCrashReportFilterPipeline(reportFilters);
            new AsyncTask<Object, Object, Void>() {
                @Override
                protected Void doInBackground(Object... params) {
                    try {
                        pipeline.filterReports(reports, new KSCrashReportFilter.CompletionCallback() {
                            @Override
                            public void onCompletion(List filteredReports) throws KSCrashReportFilteringFailedException {
                                Log.i("Crash Reporter", "Sent " + reports.size() + " reports.");
                                lastCallback.onCompletion(reports);
                            }
                        });
                    } catch (KSCrashReportFilteringFailedException e) {
                        Log.e("KSCrash", "Error sending reports", e);
                    }
                    return null;
                }
            }.execute();
        } else {
            Log.i("Crash Reporter", "No reports to send.");
        }
    }

    /**
     * Send all outstanding crash reports, with a callback.
     *
     * @param callback Called upon successful completion (null = default handler - delete all reports).
     */
    public void sendOutstandingReports(KSCrashReportFilter.CompletionCallback callback) {
        sendOutstandingReports(KSCrash.getInstance().getAllReports(), callback);
    }

    /**
     * Send all outstanding reports, deleting them from disk upon successful completion.
     */
    public void sendOutstandingReports() {
        sendOutstandingReports(null);
    }
}
