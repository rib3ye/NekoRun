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
import Security

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
    private static let keychainAccount = "PostUploadCommand"
    private static let legacyDefaultsKey = "PostUploadCommand"

    var command: String? {
        didSet { KeychainStore.write(command, forAccount: Self.keychainAccount) }
    }

    private init() {
        // One-time migration: move any prior plaintext value out of
        // UserDefaults so other user-level processes can't rewrite it.
        if let legacy = UserDefaults.standard.string(forKey: Self.legacyDefaultsKey),
           !legacy.isEmpty,
           KeychainStore.read(account: Self.keychainAccount) == nil {
            KeychainStore.write(legacy, forAccount: Self.keychainAccount)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        self.command = KeychainStore.read(account: Self.keychainAccount)
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
        // `--` ends scp's option parsing so neither file paths nor the
        // destination can ever be interpreted as flags (CVE-2020-15778
        // class — `-oProxyCommand=` in a leading argument is the canonical
        // attack). Host/directory are also validated on save; this is
        // defense in depth.
        let scpArgs = ["-r", "--"] + urls.map(\.path) + [destination]
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
            let newHost = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newDir = dirField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let error = validateDestination(host: newHost, directory: newDir) {
                presentFailure(title: "Invalid destination", message: error)
                return
            }
            store.host = newHost
            store.directory = newDir
        }
    }

    private static func validateDestination(host: String, directory: String) -> String? {
        if host.isEmpty { return "Host cannot be empty." }
        if host.hasPrefix("-") {
            return "Host cannot start with '-' — scp/ssh would interpret it as an option."
        }
        let hostAllowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_@")
        if !host.unicodeScalars.allSatisfy({ hostAllowed.contains($0) }) {
            return "Host may only contain letters, digits, '.', '-', '_', or '@'."
        }
        if directory.isEmpty { return "Directory cannot be empty." }
        if directory.hasPrefix("-") {
            return "Directory cannot start with '-'."
        }
        let banned = CharacterSet.controlCharacters.union(.newlines)
        if directory.unicodeScalars.contains(where: { banned.contains($0) }) {
            return "Directory cannot contain control characters or newlines."
        }
        return nil
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

    @MainActor
    static func presentClearAllDataAlert() {
        let alert = NSAlert()
        alert.messageText = "Clear all NekoRun data?"
        alert.informativeText = "Removes the saved upload destination and post-upload hook. Launch at Login is unaffected."
        alert.alertStyle = .warning
        let clearButton = alert.addButton(withTitle: "Clear")
        clearButton.hasDestructiveAction = true
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            UploadDestinationStore.shared.host = nil
            UploadDestinationStore.shared.directory = nil
            PostUploadHookStore.shared.command = nil
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

            // Drain stderr and stdout on background queues while the child
            // runs. Reading them only after waitUntilExit() could deadlock:
            // the pipe buffer is ~64KB, and a hook that emits more would
            // block its own exit waiting for us to read.
            let drainQueue = DispatchQueue(label: "NekoRun.process.drain", attributes: .concurrent)
            let drainGroup = DispatchGroup()
            nonisolated(unsafe) var stderrData = Data()
            nonisolated(unsafe) var stdoutData = Data()
            drainGroup.enter()
            drainQueue.async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                drainGroup.leave()
            }
            drainGroup.enter()
            drainQueue.async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                drainGroup.leave()
            }

            process.terminationHandler = { proc in
                drainGroup.notify(queue: drainQueue) {
                    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                    let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                    if proc.terminationStatus == 0 {
                        continuation.resume(returning: .success)
                    } else {
                        let combined = [stderrText, stdoutText]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        let message = combined.isEmpty
                            ? "Exited with status \(proc.terminationStatus)."
                            : combined
                        continuation.resume(returning: .failure(message))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                // The child never started, so terminationHandler will not
                // fire. Close the read ends to unblock the drain tasks
                // (they'll observe EOF and exit), then surface the failure.
                try? stderrPipe.fileHandleForReading.close()
                try? stdoutPipe.fileHandleForReading.close()
                continuation.resume(returning: .failure(error.localizedDescription))
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

// MARK: - Keychain

// Thin wrapper around SecItem for storing secrets the app should be the
// only writer of. Items are scoped by service+account; default ACL ties
// access to the running app's code signature, so other user-level
// processes can't silently read or rewrite them.
enum KeychainStore {
    private static let service = "com.twobuttz.NekoRun"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func write(_ value: String?, forAccount account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
