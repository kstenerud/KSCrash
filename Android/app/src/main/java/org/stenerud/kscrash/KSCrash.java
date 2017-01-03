package org.stenerud.kscrash;

import java.util.List;
import java.util.Map;

public class KSCrash extends Object
{
    private static final KSCrash instance = new KSCrash();
    static {
        System.loadLibrary("kscrash-lib");
    }

    private KSCrash()
    {

    }

    public static KSCrash getInstance()
    {
        return instance;
    }

    public native void install();

    public void sendAllReportsWithCallback(IKSCrashFilterCompletionCallback callback)
    {

    }

    public void deleteAllReports()
    {

    }

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
