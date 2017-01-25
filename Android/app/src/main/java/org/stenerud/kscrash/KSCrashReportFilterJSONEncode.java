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

import org.json.JSONObject;

import java.util.LinkedList;
import java.util.List;

/**
 * Encodes objects into a JSON encoded string.
 *
 * Input: JSON encodable object
 * Output: String (JSON encoded)
 */
public class KSCrashReportFilterJSONEncode implements KSCrashReportFilter {
    private int indentDepth = -1;

    /**
     * Constructor.
     *
     * @param indentDepth The depth to indent while pretty printing (-1 = do not pretty print).
     */
    public KSCrashReportFilterJSONEncode(int indentDepth) {
        this.indentDepth = indentDepth;
    }

    /**
     * Constructor.
     * Do not pretty print.
     */
    public KSCrashReportFilterJSONEncode() {
        this(-1);
    }

    @Override
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException {
        List<String> processedReports = new LinkedList<String>();
        try {
            for (Object report : reports) {
                JSONObject object = (JSONObject)report;
                String string = null;
                if(indentDepth >= 0) {
                    string = object.toString(indentDepth);
                } else {
                    string = object.toString();
                }
                processedReports.add(string);
            }
        } catch(Throwable error) {
            throw new KSCrashReportFilteringFailedException(error, reports);
        }
        completionCallback.onCompletion(processedReports);
    }
}
