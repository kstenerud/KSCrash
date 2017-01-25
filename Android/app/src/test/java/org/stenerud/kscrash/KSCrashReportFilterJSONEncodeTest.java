package org.stenerud.kscrash;

import org.json.JSONObject;
import org.junit.Test;

import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertEquals;

/**
 * Created by karl on 2017-01-12.
 */

public class KSCrashReportFilterJSONEncodeTest {
    @Test
    public void test_encode_dictionary() throws Exception {
        final String expected = "{}";
        Map dictionary = new HashMap();
        List reports = new LinkedList();
        reports.add(new JSONObject(dictionary));
        KSCrashReportFilter filter = new KSCrashReportFilterJSONEncode();
        filter.filterReports(reports, new KSCrashReportFilter.CompletionCallback() {
            @Override
            public void onCompletion(List reports) throws KSCrashReportFilteringFailedException {
                assertEquals(expected, reports.get(0));
            }
        });
    }
}
