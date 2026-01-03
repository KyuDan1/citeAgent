//
//  AppDelegate.swift
//  macOS (App)
//
//  Created by kyudan on 1/4/26.
//

import Cocoa
import SwiftUI

@available(macOS 12.0, *)
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var floatingWindow: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create floating navigator window
        createFloatingNavigator()
    }

    func createFloatingNavigator() {
        // Create a floating panel (always on top)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = "CiteAgent"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        // Set initial position (top-right corner)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 260
            let y = screenFrame.maxY - 200
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Create SwiftUI view and set as content
        let contentView = FloatingNavigatorView()
        panel.contentView = NSHostingView(rootView: contentView)

        panel.makeKeyAndOrderFront(nil)
        self.floatingWindow = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running even if floating window is closed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
