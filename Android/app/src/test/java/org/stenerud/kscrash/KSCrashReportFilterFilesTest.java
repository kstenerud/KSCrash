package org.stenerud.kscrash;

import org.junit.Test;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Scanner;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

/**
 * Created by karl on 2017-01-12.
 */

public class KSCrashReportFilterFilesTest {
    private void assertFileContains(File file, String expectedContents) throws FileNotFoundException {
        String contents = new Scanner(file).useDelimiter("\\A").next();
        assertEquals(expectedContents, contents);
    }

    private void assertFileDoesNotExist(File file) {
        try {
            new Scanner(file);
        } catch (FileNotFoundException e) {
            return;
        }
        assertTrue("File " + file + " exists when it shouldn't", false);
    }

    private File createTempDir() throws IOException {
        File tempFile = File.createTempFile("tempdir","");
        tempFile.delete();
        tempFile.mkdir();
        return tempFile;
    }

    @Test
    public void test_create_files() throws Exception {
        final List reports = new LinkedList();
        reports.add("one");
        reports.add("two");
        reports.add("three");

        KSCrashReportFilter createFilter = new KSCrashReportFilterCreateTempFiles(createTempDir(), "report", "txt");

        createFilter.filterReports(reports, new KSCrashReportFilter.CompletionCallback() {
            @Override
            public void onCompletion(List filteredReports) throws KSCrashReportFilteringFailedException {
                try {
                    for (int i = 0; i < filteredReports.size(); i++) {
                        assertFileContains((File)filteredReports.get(i), (String)reports.get(i));
                    }
                } catch(FileNotFoundException e) {
                    throw new KSCrashReportFilteringFailedException(e, filteredReports);
                }
            }
        });
    }

    @Test
    public void create_delete() throws Exception {
        final List reports = new LinkedList();
        reports.add("one");
        reports.add("two");
        reports.add("three");

        KSCrashReportFilter createFilter = new KSCrashReportFilterCreateTempFiles(createTempDir(), "report", "txt");
        KSCrashReportFilter deleteFilter = new KSCrashReportFilterDeleteFiles();
        List filters = new LinkedList();
        filters.add(createFilter);
        filters.add(deleteFilter);
        KSCrashReportFilter pipeline = new KSCrashReportFilterPipeline(filters);

        pipeline.filterReports(reports, new KSCrashReportFilter.CompletionCallback() {
            @Override
            public void onCompletion(List filteredReports) throws KSCrashReportFilteringFailedException {
                for (int i = 0; i < filteredReports.size(); i++) {
                    assertFileDoesNotExist((File)filteredReports.get(i));
                }
            }
        });
    }
}
