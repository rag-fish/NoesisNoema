//
//  NoesisNoemaMobileApp.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/08/15.
//

import SwiftUI

@main
struct NoesisNoemaMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
