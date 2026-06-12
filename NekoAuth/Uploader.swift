//
//  Uploader.swift
//  NekoRun
//
//  Spawns scp to copy dropped files to the configured SSH host, then
//  optionally runs a user-supplied shell command via /bin/sh -c.
//  Failures surface in an NSAlert with the BombIcon.
//

import AppKit
import Foundation
import Observation

// MARK: - Persistence

@MainActor
@Observable
final class UploadDestinationStore {
    static let shared = UploadDestinationStore()
    private static let hostKey = "UploadDestinationHost"
    private static let directoryKey = "UploadDestinationDirectory"

    var host: String? {
        didSet { Self.write(host, forKey: Self.hostKey) }
    }

    var directory: String? {
        didSet { Self.write(directory, forKey: Self.directoryKey) }
    }

    var displayLabel: String? {
        guard let host, !host.isEmpty, let directory, !directory.isEmpty else { return nil }
        return "\(host):\(directory)"
    }

    private init() {
        self.host = UserDefaults.standard.string(forKey: Self.hostKey)
        self.directory = UserDefaults.standard.string(forKey: Self.directoryKey)
    }

    private static func write(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

@MainActor
@Observable
final class PostUploadHookStore {
    static let shared = PostUploadHookStore()
    private static let key = "PostUploadCommand"

    var command: String? {
        didSet {
            if let command, !command.isEmpty {
                UserDefaults.standard.set(command, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }
    }

    private init() {
        self.command = UserDefaults.standard.string(forKey: Self.key)
    }
}

// MARK: - Uploader

enum Uploader {
    static func upload(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        let (host, directory) = await MainActor.run {
            (UploadDestinationStore.shared.host, UploadDestinationStore.shared.directory)
        }
        guard let host, !host.isEmpty, let directory, !directory.isEmpty else {
            await MainActor.run {
                presentFailure(
                    title: "Upload not configured",
                    message: "Set the upload host and directory from the NekoRun menu before dropping files."
                )
            }
            return
        }

        await MainActor.run { DropEnabledStatusBarButton.beginUploadAnimation() }
        defer {
            Task { @MainActor in DropEnabledStatusBarButton.endUploadAnimation() }
        }

        let destination = "\(host):\(directory)/"
        let scpArgs = ["-r"] + urls.map(\.path) + [destination]
        if case .failure(let message) = await run("/usr/bin/scp", scpArgs) {
            await MainActor.run { presentFailure(title: "scp failed", message: message) }
            return
        }

        let hook = await MainActor.run { PostUploadHookStore.shared.command }
        if let hook, !hook.isEmpty {
            if case .failure(let message) = await run("/bin/sh", ["-c", hook]) {
                await MainActor.run { presentFailure(title: "Post-upload hook failed", message: message) }
            }
        }
    }

    // MARK: - Editor alerts

    @MainActor
    static func presentChangeDestinationAlert() {
        let store = UploadDestinationStore.shared
        let alert = NSAlert()
        alert.messageText = "Upload Destination"
        alert.informativeText = "Set the SSH host and remote directory used when files are dropped on the menu bar icon."
        alert.alertStyle = .informational

        let width: CGFloat = 360
        let hostLabel = NSTextField(labelWithString: "Host (user@hostname):")
        hostLabel.frame = NSRect(x: 0, y: 92, width: width, height: 18)

        let hostField = NSTextField(frame: NSRect(x: 0, y: 64, width: width, height: 24))
        hostField.stringValue = store.host ?? ""
        hostField.placeholderString = "user@hostname"
        hostField.lineBreakMode = .byTruncatingMiddle

        let dirLabel = NSTextField(labelWithString: "Remote directory:")
        dirLabel.frame = NSRect(x: 0, y: 32, width: width, height: 18)

        let dirField = NSTextField(frame: NSRect(x: 0, y: 4, width: width, height: 24))
        dirField.stringValue = store.directory ?? ""
        dirField.placeholderString = "/absolute/path"
        dirField.lineBreakMode = .byTruncatingMiddle

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 114))
        container.addSubview(hostLabel)
        container.addSubview(hostField)
        container.addSubview(dirLabel)
        container.addSubview(dirField)
        alert.accessoryView = container

        let saveButton = alert.addButton(withTitle: "Save")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        let enabler = SaveButtonEnabler(button: saveButton, field: hostField)
        hostField.delegate = enabler

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = hostField
        let response = alert.runModal()
        _ = enabler  // keep delegate alive for the modal lifetime
        if response == .alertFirstButtonReturn {
            store.host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            store.directory = dirField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @MainActor
    static func presentChangePostUploadHookAlert() {
        let store = PostUploadHookStore.shared
        let alert = NSAlert()
        alert.messageText = "Post-Upload Hook"
        alert.informativeText = "Shell command run locally after files are uploaded."
        alert.alertStyle = .informational

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = store.command ?? ""
        field.placeholderString = "e.g. ssh user@host chmod -R ugo+r /path"
        field.lineBreakMode = .byTruncatingMiddle
        alert.accessoryView = field

        let saveButton = alert.addButton(withTitle: "Save")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        let enabler = SaveButtonEnabler(button: saveButton, field: field)
        field.delegate = enabler

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        _ = enabler  // keep delegate alive for the modal lifetime
        if response == .alertFirstButtonReturn {
            store.command = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Process helper

    private enum RunResult {
        case success
        case failure(String)
    }

    private static func run(_ executable: String, _ arguments: [String]) async -> RunResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<RunResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let stderrText = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stdoutText = String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if process.terminationStatus == 0 {
                continuation.resume(returning: .success)
            } else {
                let combined = [stderrText, stdoutText]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let message = combined.isEmpty
                    ? "Exited with status \(process.terminationStatus)."
                    : combined
                continuation.resume(returning: .failure(message))
            }
        }
    }

    // MARK: - Failure alert

    @MainActor
    private static func presentFailure(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let icon = NSImage(named: "ErrorIcon") {
            alert.icon = icon
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Save-button gate

@MainActor
private final class SaveButtonEnabler: NSObject, NSTextFieldDelegate {
    private weak var button: NSButton?

    init(button: NSButton, field: NSTextField) {
        self.button = button
        super.init()
        refresh(text: field.stringValue)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        refresh(text: field.stringValue)
    }

    private func refresh(text: String) {
        button?.isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
