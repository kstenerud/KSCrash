//
//  AppDelegate.swift
//  Swift-Tester
//
//  Created by karl on 2016-01-28.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

import UIKit
import KSCrash

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        let emailAddress = "your@email.here"
        
        let installation = KSCrashInstallationEmail.sharedInstance()
        installation.recipients = [emailAddress]
        installation.subject = "Crash Report"
        installation.message = "This is a crash report"
        installation.filenameFmt = "crash-report-%d.json.gz"
//        installation.reportStyle = KSCrashEmailReportStyleJSON
        
        installation.addConditionalAlertWithTitle("Crash Detected",
            message: "The app crashed last time it was launched. Send a crash report?",
            yesAnswer: "Sure!",
            noAnswer: "No thanks")

        installation.install()

        installation.sendAllReportsWithCompletion { (reports, completed, error) -> Void in
            if(completed) {
                print("Sent \(reports.count) reports")
            } else {
                print("Failed to send reports: \(error)")
            }
        }
        
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

