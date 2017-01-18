package org.stenerud.kscrash;

import java.io.BufferedWriter;
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
