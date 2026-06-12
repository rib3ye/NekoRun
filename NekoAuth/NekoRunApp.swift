//
//  NekoRunApp.swift
//  NekoRun
//
//  Created by Noah Tsutsui on 6/10/26.
//

import SwiftUI
import AppKit

@main
struct NekoRunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDropInstaller.install()
    }
}
