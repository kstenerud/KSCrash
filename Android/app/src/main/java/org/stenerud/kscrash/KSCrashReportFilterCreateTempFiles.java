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

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.LinkedList;
import java.util.List;

/**
 * Take the contents of each report and store it in a temp file.
 * The files themselves are passed on.
 *
 * Input: String or byte[]
 * Output: File
 */
public class KSCrashReportFilterCreateTempFiles implements KSCrashReportFilter {
    private String extension;
    public KSCrashReportFilterCreateTempFiles(String extension) {
        this.extension = extension;
    }
    @Override
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException {
        try {
            List<String> filenames = new LinkedList<String>();
            int index = 1;
            for(Object report: reports) {
                File tempFile = File.createTempFile("report-" + index, this.extension);
                OutputStream outStream = new FileOutputStream(tempFile);
                if(report instanceof String) {
                    Writer out = new OutputStreamWriter(outStream, "UTF-8");
                    try {
                        out.write((String)report);
                    } finally {
                        out.close();
                    }
                } else if(report instanceof byte[]) {
                    try {
                        outStream.write((byte[])report);
                    } finally {
                        outStream.close();
                    }
                } else {
                    throw new IllegalArgumentException("Unhandled class type: " + report.getClass());
                }
                reports.add(tempFile);
                index++;
            }
            completionCallback.onCompletion(filenames);
        } catch (Throwable error) {
            throw new KSCrashReportFilteringFailedException(error, reports);
        }
    }
}
