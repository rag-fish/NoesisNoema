//
//  FullScreenTestView.swift
//  NoesisNoemaMobile
//
//  Diagnostic view to test full-screen layout rendering
//

import SwiftUI

struct FullScreenTestView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea(.all, edges: .all)

            VStack(spacing: 20) {
                Text("Full Screen OK")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(.systemGray))

                Text("If you see gaps, the issue is at system level")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea(.all, edges: .all)
    }
}

struct FullScreenTestView_Previews: PreviewProvider {
    static var previews: some View {
        FullScreenTestView()
    }
}
