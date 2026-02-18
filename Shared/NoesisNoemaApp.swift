//
//  NoesisNoemaApp.swift
//  NoesisNoema
//
//  Created by Раскольников on 2025/07/18.
//

import SwiftUI

#if os(macOS)
@main
struct NoesisNoemaApp: App {
    var body: some Scene {
        WindowGroup {
            MinimalClientView()
        }
    }
}
#endif
