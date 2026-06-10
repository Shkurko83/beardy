//
//  AppDelegate.swift
//  BlackBeardEditor
//
//  Created by Butt Simpson on 27.12.2025.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeService.shared.applyAppearance(notify: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DocumentManager.shared?.persistSessionState()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DocumentManager.shared?.handleApplicationTerminate() ?? .terminateNow
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    @objc func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
