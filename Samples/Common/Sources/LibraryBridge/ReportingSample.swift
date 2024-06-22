import Foundation
import KSCrashRecording
import KSCrashFilters
import KSCrashSinks

public class ReportingSample {
    public static func logToConsole() {
        KSCrash.sharedInstance().sink = KSCrashReportSinkConsole.filter().defaultCrashReportFilterSet()
        KSCrash.sharedInstance().sendAllReports { _, _, _ in
            print("Done!")
            KSCrash.sharedInstance().deleteAllReports()
        }
    }
}
