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

/** Send any outstanding crash reports to the current sink.
 * It will only attempt to send the most recent 5 reports. All others will be
 * deleted. Once the reports are successfully sent to the server, they may be
 * deleted locally, depending on the property "deleteAfterSend".
 */
- (void) sendAllReports;

/** Send the specified reports to the current sink.
 *
 * @param reports The reports to send.
 */
- (void) sendReports:(NSArray*) reports;

/** Get all reports, with data types corrected, as dictionaries.
 */
- (NSArray*) allReports;

/** Delete all unsent reports.
 */
- (void) deleteAllReports;

@end

