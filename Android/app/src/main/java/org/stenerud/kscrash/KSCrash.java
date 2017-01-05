package org.stenerud.kscrash;

import android.content.Context;

import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.Map;

public class KSCrash extends Object
{
    private static final KSCrash instance = new KSCrash();
    static {
        System.loadLibrary("kscrash-lib");
    }

    private KSCrash() {}

    public static KSCrash getInstance()
    {
        return instance;
    }

    public void install(Context context) throws IOException {
        String appName = context.getApplicationInfo().processName;
        File installDir = new File(context.getCacheDir().getAbsolutePath(), "KSCrash");
        install(appName, installDir.getCanonicalPath());
    }

    public native void install(String appName, String installDir);

    public void sendAllReportsWithCallback(IKSCrashFilterCompletionCallback callback)
    {

    }

    public native void deleteAllReports();

    public void reportUserException(String name,
                                    String reason,
                                    String language,
                                    int lineOfCode,
                                    List<String> stackTrace,
                                    boolean shouldLogAllThreads,
                                    boolean shouldTerminateProgram)
    {

    }

    public void setUserInfo(Map userInfo)
    {

    }

    public void setActiveMonitors()
    {

    }

    public void setSearchThreadNames(boolean shouldSearchThreadNames)
    {

    }

    public void setIntrospectMemory(boolean shouldIntrospectMemory)
    {

    }

    public void setAddConsoleLogToReport(boolean shouldAddConsoleLogToReport)
    {

    }
}
