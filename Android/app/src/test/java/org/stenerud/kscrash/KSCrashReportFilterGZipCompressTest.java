package org.stenerud.kscrash;

import org.junit.Test;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.Charset;
import java.util.LinkedList;
import java.util.List;
import java.util.zip.GZIPOutputStream;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

/**
 * Created by karl on 2017-01-12.
 */

public class KSCrashReportFilterGZipCompressTest {
    private byte[] compress(byte[] bytes) throws IOException {
        ByteArrayOutputStream byteStream = new ByteArrayOutputStream();
        OutputStream outStream = new GZIPOutputStream(byteStream);
        try {
            outStream.write(bytes);
        } finally {
            outStream.close();
        }
        return byteStream.toByteArray();
    }
    private byte[] compress(String string) throws IOException {
        return compress(string.getBytes(Charset.forName("UTF-8")));
    }

    @Test
    public void test_compress_bytes() throws Exception {
        final byte[] testBytes = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
        final byte[] expected = compress(testBytes);
        List reports = new LinkedList();
        reports.add(testBytes);
        KSCrashReportFilter filter = new KSCrashReportFilterGZipCompress();
        filter.filterReports(reports, new KSCrashReportFilter.CompletionCallback() {
            @Override
            public void onCompletion(List reports) throws KSCrashReportFilteringFailedException {
                assertArrayEquals(expected, (byte[])reports.get(0));
            }
        });
    }

    @Test
    public void test_compress_string() throws Exception {
        final String testString = "This is a test. Testing converting a string to UTF-8 and then compressing it.";
        final byte[] expected = compress(testString);
        List reports = new LinkedList();
        reports.add(testString);
        KSCrashReportFilter filter = new KSCrashReportFilterGZipCompress();
        filter.filterReports(reports, new KSCrashReportFilter.CompletionCallback() {
            @Override
            public void onCompletion(List reports) throws KSCrashReportFilteringFailedException {
                assertArrayEquals(expected, (byte[])reports.get(0));
            }
        });
    }
}
