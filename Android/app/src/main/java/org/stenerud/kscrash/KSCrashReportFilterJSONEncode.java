package org.stenerud.kscrash;

import org.json.JSONObject;

import java.util.LinkedList;
import java.util.List;
import java.util.Map;

/**
 * Encodes objects into a JSON encoded string.
 *
 * Input: JSON encodable object
 * Output: String (JSON encoded)
 */
public class KSCrashReportFilterJSONEncode implements KSCrashReportFilter {
    @Override
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException {
        List<String> processedReports = new LinkedList<String>();
        try {
            for (Object report : reports) {
                processedReports.add(new JSONObject((Map) report).toString());
            }
        } catch(Throwable error) {
            throw new KSCrashReportFilteringFailedException(error, reports);
        }
        completionCallback.onCompletion(processedReports);
    }
}
