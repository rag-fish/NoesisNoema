//
//  AppDelegate.swift
//  NoesisNoemaMobile
//
//  Created for status bar management
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Status bar visibility is handled by view controller–based appearance.
        // NNHostingController/NNNavigationController override prefersStatusBarHidden.
        return true
    }
}
