//
//  RootView.swift
//  NoesisNoemaMobile
//
//  Created by Раскольников on 2025/08/15.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabRootView()
            .preferredColorScheme(.light) // Force Light Mode to fix Dark Mode visibility issues
    }
}

#Preview {
    RootView()
}
