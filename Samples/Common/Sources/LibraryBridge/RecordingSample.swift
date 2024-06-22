import Foundation
import KSCrashRecording

public class RecordingSample {
    public static func simple() {
        let config = KSCrashConfiguration()
        KSCrash.sharedInstance().install(with: config)
    }
}
