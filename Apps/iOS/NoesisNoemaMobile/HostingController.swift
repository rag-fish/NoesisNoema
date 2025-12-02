//
//  HostingController.swift
//  NoesisNoemaMobile
//
//  Custom UIKit controllers for status bar and edge-to-edge layout
//

import UIKit
import SwiftUI

class NNHostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }
}
