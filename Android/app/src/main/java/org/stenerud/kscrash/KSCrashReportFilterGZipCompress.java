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

import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.LinkedList;
import java.util.List;
import java.util.zip.GZIPOutputStream;

/**
 * GZIP compress the reports.
 *
 * Input: String or byte[]
 * Output: byte[]
 */
public class KSCrashReportFilterGZipCompress implements KSCrashReportFilter {
    @Override
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException {
        List processedReports = new LinkedList();
        try {
            for(Object report: reports) {
                ByteArrayOutputStream byteStream = new ByteArrayOutputStream();
                OutputStream outStream = new GZIPOutputStream(byteStream);
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
                processedReports.add(byteStream.toByteArray());
            }
        } catch(Throwable error) {
            throw new KSCrashReportFilteringFailedException(error, reports);
        }
        completionCallback.onCompletion(processedReports);
    }
}
