//
//  MenuBarDropInstaller.swift
//  NekoRun
//
//  At launch, walks NSApp.windows to find the NSStatusBarButton SwiftUI's
//  MenuBarExtra creates, swaps its class to DropEnabledStatusBarButton
//  via object_setClass, registers it for file-URL drags, and starts the
//  hover monitor. Retries briefly because the status item is created
//  asynchronously.
//

import AppKit

@MainActor
enum MenuBarDropInstaller {
    private static let maxAttempts = 20
    private static let attemptInterval: Duration = .milliseconds(100)

    static func install() {
        Task { @MainActor in
            for _ in 0..<maxAttempts {
                if attemptInstall() { return }
                try? await Task.sleep(for: attemptInterval)
            }
            NSLog("NekoRun: could not locate menu bar status item button.")
        }
    }

    private static func attemptInstall() -> Bool {
        guard let button = findStatusBarButton() else { return false }
        if !(button is DropEnabledStatusBarButton) {
            object_setClass(button, DropEnabledStatusBarButton.self)
        }
        button.registerForDraggedTypes([.fileURL])
        (button as? DropEnabledStatusBarButton)?.startHoverMonitoring()
        return true
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let button = findStatusBarButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let found = findStatusBarButton(in: subview) {
                return found
            }
        }
        return nil
    }
}
