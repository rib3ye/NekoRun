//
//  LoginItemManager.swift
//  NekoRun
//
//  Wraps SMAppService.mainApp so NekoRun can be toggled to launch at login.
//

import AppKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemManager {
    static let shared = LoginItemManager()

    private(set) var isEnabled: Bool

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("NekoRun: failed to toggle login item: \(error.localizedDescription)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
