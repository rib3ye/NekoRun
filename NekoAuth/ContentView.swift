//
//  ContentView.swift
//  NekoRun
//
//  The dropdown menu shown when the user clicks the cat.
//

import SwiftUI

struct ContentView: View {
    @State private var uploadStore = UploadDestinationStore.shared
    @State private var hookStore = PostUploadHookStore.shared
    @State private var loginItem = LoginItemManager.shared

    var body: some View {
        uploadSection()
        hookSection()
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { _ in loginItem.toggle() }
        ))
        Divider()
        Button("Quit NekoRun") {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private func uploadSection() -> some View {
        if let label = uploadStore.displayLabel {
            Section("Upload: \(Self.truncate(label, max: 32))") {
                Button("Change Upload Destination…") {
                    Uploader.presentChangeDestinationAlert()
                }
            }
        } else {
            Button("Set Upload Destination…") {
                Uploader.presentChangeDestinationAlert()
            }
        }
    }

    @ViewBuilder
    private func hookSection() -> some View {
        if let command = hookStore.command, !command.isEmpty {
            Section("Hook: \(Self.truncate(command, max: 32))") {
                Button("Change Post-Upload Hook…") {
                    Uploader.presentChangePostUploadHookAlert()
                }
            }
        } else {
            Button("Set Post-Upload Hook…") {
                Uploader.presentChangePostUploadHookAlert()
            }
        }
    }

    private static func truncate(_ text: String, max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max - 1)) + "…"
    }
}
