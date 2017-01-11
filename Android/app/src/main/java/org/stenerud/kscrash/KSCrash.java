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

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class KSCrash
{
    public enum MonitorType {
        // Note: This must be kept in sync with KSCrashMonitorType.h
        None(0),

        Signal           (0x02),
        CPPException     (0x04),
        UserReported     (0x20),
        System           (0x40),
        ApplicationState (0x80),

        All          (Signal.value | CPPException.value | UserReported.value | System.value | ApplicationState.value),
        Experimental (None.value),
        Optional     (None.value),
        Required     (System.value | ApplicationState.value),

        DebuggerUnsafe        (Signal.value | CPPException.value),
        DebuggerSafe          (All.value & ~DebuggerUnsafe.value),
        RequiresAsyncSafety   (Signal.value),
        RequiresNoAsyncSafety (All.value & ~RequiresAsyncSafety.value),
        ProductionSafe        (All.value & ~Experimental.value),
        ProductionSafeMinimal (ProductionSafe.value & ~Optional.value),
        Manual                (Required.value | UserReported.value);

        public final int value;
        MonitorType(int value) {this.value = value;}
    }

    static {
        System.loadLibrary("kscrash-lib");
        initJNI();
    }
    private static final KSCrash instance = new KSCrash();
    public static KSCrash getInstance()
    {
        return instance;
    }
    private KSCrash() {}

    private static Thread.UncaughtExceptionHandler oldUncaughtExceptionHandler;

    /** Install the crash reporter.
     *
     * @param context The application context.
     */
    public void install(Context context) throws IOException {
        String appName = context.getApplicationInfo().processName;
        File installDir = new File(context.getCacheDir().getAbsolutePath(), "KSCrash");
        install(appName, installDir.getCanonicalPath());

        // TODO: Put this elsewhere
        oldUncaughtExceptionHandler = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
            @Override
            public void uncaughtException(Thread t, Throwable e) {
                KSCrash.this.reportJavaException(e);
                KSCrash.oldUncaughtExceptionHandler.uncaughtException(t, e);
            }
        });
    }

    /** Delete all reports on disk.
     */
    public native void deleteAllReports();

    /** Add a custom report to the store.
     *
     * @param report The report's contents (must be JSON encodable).
     */
    public void addUserReport(Map report) {
        JSONObject object = new JSONObject(report);
        internalAddUserReportJSON(object.toString());
    }

    /** Report a custom, user defined exception.
     * This can be useful when dealing with scripting languages.
     *
     * If terminateProgram is true, all sentries will be uninstalled and the application will
     * terminate with an abort().
     *
     * @param name The exception name (for namespacing exception types).
     *
     * @param reason A description of why the exception occurred.
     *
     * @param language A unique language identifier.
     *
     * @param lineOfCode A copy of the offending line of code (NULL = ignore).
     *
     * @param stackTrace JSON encoded array containing stack trace information (one frame per array entry).
     *                   The frame structure can be anything you want, including bare strings.
     *
     * @param shouldLogAllThreads If true, suspend all threads and log their state. Note that this incurs a
     *                      performance penalty, so it's best to use only on fatal errors.
     *
     * @param shouldTerminateProgram If true, do not return from this function call. Terminate the program instead.
     */
    public void reportUserException(String name,
                                    String reason,
                                    String language,
                                    String module,
                                    int lineOfCode,
                                    JSONArray stackTrace,
                                    boolean shouldLogAllThreads,
                                    boolean shouldTerminateProgram) {
        String line = module + " line " + lineOfCode;
        internalReportUserException(name, reason, language, line, stackTrace.toString(), shouldLogAllThreads, shouldTerminateProgram);
    }

    /** Report a Java exception.
     *
     * @param exception The exception.
     */
    public void reportJavaException(Throwable exception) {
        try {
            JSONArray array = new JSONArray();
            for(StackTraceElement element: exception.getStackTrace())
            {
                JSONObject object = new JSONObject();
                object.put("file", element.getFileName());
                object.put("line", element.getLineNumber());
                object.put("class", element.getClassName());
                object.put("method", element.getMethodName());
                object.put("native", element.isNativeMethod());
                array.put(object);
            }
            reportUserException(exception.getClass().getName(),
                    exception.getMessage(),
                    "java",
                    exception.getStackTrace()[0].getFileName(),
                    exception.getStackTrace()[0].getLineNumber(),
                    array,
                    false,
                    false);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    /** Set the user-supplied data.
     *
     * @param userInfo JSON-encodable user-supplied information.
     */
    public void setUserInfo(Map userInfo) {
        JSONObject object = new JSONObject(userInfo);
        internalSetUserInfoJSON(object.toString());
    }

    /** Set which monitors will be active..
     * Some crash monitors may not be enabled depending on circumstances (e.g. running
     * in a debugger).
     *
     * @param monitors The monitors to install.
     */
    public void setActiveMonitors(MonitorType[] monitors) {
        int activeMonitors = 0;
        for(MonitorType monitor: monitors) {
            activeMonitors |= monitor.value;
        }
        internalSetActiveMonitors(activeMonitors);
    }

    /** Get all the crash reports.
     *
     * @return The crash reports.
     */
    public List<JSONObject> getAllReports() {
        List<String> rawReports = internalGetAllReports();
        List<JSONObject> reports = new ArrayList<JSONObject>(rawReports.size());
        for(String rawReport: rawReports) {
            JSONObject report;
            try {
                report = new JSONObject(rawReport);
                reports.add(report);
            } catch (JSONException e) {
                e.printStackTrace();
            }
        }
        return reports;
    }

    /** Set the maximum number of reports allowed on disk before old ones get deleted.
     *
     * @param maxReportCount The maximum number of reports.
     */
    public native void setMaxReportCount(int maxReportCount);

    /** If true, introspect memory contents during a crash.
     * C strings near the stack pointer or referenced by cpu registers or exceptions will be
     * recorded in the crash report, along with their contents.
     *
     * Default: false
     */
    public native void setIntrospectMemory(boolean shouldIntrospectMemory);

    /** Set if KSLOG console messages should be appended to the report.
     *
     * @param shouldAddConsoleLogToReport If true, add the log to the report.
     */
    public native void setAddConsoleLogToReport(boolean shouldAddConsoleLogToReport);

    /** Notify the crash reporter of the application active state.
     *
     * @param isActive true if the application is active, otherwise false.
     */
    public native void notifyAppActive(boolean isActive);

    /** Notify the crash reporter of the application foreground/background state.
     *
     * @param isInForeground true if the application is in the foreground, false if
     *                 it is in the background.
     */
    public native void notifyAppInForeground(boolean isInForeground);

    /** Notify the crash reporter that the application is terminating.
     */
    public native void notifyAppTerminate();

    /** Notify the crash reporter that the application has crashed.
     */
    public native void notifyAppCrash();

    private native void internalSetActiveMonitors(int activeMonitors);
    private static native void initJNI();
    private native void install(String appName, String installDir);
    private native List<String> internalGetAllReports();
    private native void internalAddUserReportJSON(String userReportJSON);
    private native void internalSetUserInfoJSON(String userInfoJSON);
    private native void internalReportUserException(String name,
                                                    String reason,
                                                    String language,
                                                    String lineOfCode,
                                                    String stackTraceJSON,
                                                    boolean shouldLogAllThreads,
                                                    boolean shouldTerminateProgram);
}
