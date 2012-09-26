//
//  KSCrashAdvanced.h
//  KSCrash
//
//  Created by Karl Stenerud on 12-05-06.
//

#import "KSCrash.h"


/** Advanced interface to the KSCrash system.
 */
@interface KSCrash ()

/** Get the global instance.
 */
+ (KSCrash*) instance;

/** The report sink where reports get sent. */
@property(nonatomic,readwrite,retain) id<KSCrashReportFilter> sink;

/** If YES, delete any reports that are successfully sent. */
@property(nonatomic,readwrite,assign) BOOL deleteAfterSend;

/** The total number of unsent reports. */
@property(nonatomic,readonly,assign) NSUInteger reportCount;

/** Where the crash reports are stored. */
@property(nonatomic,readonly,retain) NSString* reportsPath;

/** Send any outstanding crash reports to the current sink.
 * It will only attempt to send the most recent 5 reports. All others will be
 * deleted. Once the reports are successfully sent to the server, they may be
 * deleted locally, depending on the property "deleteAfterSend".
 *
 * @param onCompletion Called when sending is complete.
 */
- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion;

/** Send the specified reports to the current sink.
 *
 * @param reports The reports to send.
 * @param onCompletion Called when sending is complete.
 */
- (void) sendReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion;

/** Get all reports, with data types corrected, as dictionaries.
 */
- (NSArray*) allReports;

/** Delete all unsent reports.
 */
- (void) deleteAllReports;

/** Redirect all log entries to the specified log file.
 *
 * @param filename The path to the logfile.
 * @param overwrite If true, overwrite the file.
 *
 * @return true if the operation was successful.
 */
+ (BOOL) redirectLogsToFile:(NSString*) filename overwrite:(BOOL) overwrite;

/** Redirect all log entries to Library/Caches/KSCrashReports/log.txt.
 * If the file exists, it will be overwritten.
 *
 * @return true if the operation was successful.
 */
+ (BOOL) logToFile;

/** TODO: Figure out how to get a collection of filename + data of everything
 * in the reports dir, ready to be attached to an email.
 * Must be able to specify maximum size.
 */
//- (NSArray*) reportsDirectoryContents;

@end

