package org.stenerud.kscrash;

import java.util.List;

/**
 * Created by karl on 2016-12-28.
 */

public interface IKSCrashFilterCompletionCallback
{
    public void onFilteringDidComplete(List reports);
    public void onFilteringDidNotComplete(List reports, String error);
}
