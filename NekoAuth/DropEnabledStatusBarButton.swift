//
//  DropEnabledStatusBarButton.swift
//  NekoRun
//
//  NSStatusBarButton subclass that accepts file drops, swaps to a hover
//  image while the cursor is over the button, and pulses between two
//  images while an upload is in flight.
//
//  Applied to the existing menu bar button at launch via object_setClass,
//  so this class MUST NOT declare any stored instance properties — that
//  would change instance size and crash. Per-instance state lives in
//  static properties (there is only ever one menu bar button).
//

import AppKit

final class DropEnabledStatusBarButton: NSStatusBarButton {

    // MARK: - Images

    private static let normalImage: NSImage = makeMenuBarImage(named: "MenuBarIcon")
    private static let hoverImage: NSImage = makeMenuBarImage(named: "MenuBarIconHover")

    private static func makeMenuBarImage(named name: String) -> NSImage {
        let image = NSImage(named: name) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    // MARK: - State (static; see file header)

    private static weak var sharedButton: DropEnabledStatusBarButton?
    private static var localMonitor: Any?
    private static var globalMonitor: Any?
    private static var isHovered: Bool = false
    private static var isApplyingOurImage: Bool = false

    private static var uploadRefCount: Int = 0
    private static var uploadAnimationTimer: Timer?
    private static var uploadPhase: Bool = false
    private static var isUploading: Bool { uploadRefCount > 0 }

    // MARK: - Image coercion
    //
    // SwiftUI's MenuBarExtra re-pushes its label image onto button.image during
    // layout. We intercept the setter and route any external write back to
    // whatever the current hover / upload state dictates. Only our own
    // applyCurrentImage() — gated by isApplyingOurImage — writes through.

    override var image: NSImage? {
        get { super.image }
        set {
            if Self.isApplyingOurImage {
                super.image = newValue
            } else {
                super.image = Self.desiredImage()
            }
        }
    }

    private static func desiredImage() -> NSImage {
        if isUploading {
            return uploadPhase ? hoverImage : normalImage
        }
        return isHovered ? hoverImage : normalImage
    }

    private func applyCurrentImage() {
        let desired = Self.desiredImage()
        guard super.image !== desired else { return }
        Self.isApplyingOurImage = true
        super.image = desired
        Self.isApplyingOurImage = false
        needsDisplay = true
    }

    // MARK: - Hover monitoring
    //
    // We compare cursor screen position to the button's screen frame on every
    // mouse-moved event rather than using NSTrackingArea, because
    // NSStatusBarButton's tracking is alpha-hit-tested — moving over a
    // transparent pixel of the cat would fire spurious enter/exit events.

    func startHoverMonitoring() {
        Self.sharedButton = self
        guard Self.localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]
        Self.localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.refreshHoverState()
            return event
        }
        Self.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.refreshHoverState()
        }
        applyCurrentImage()
    }

    private func refreshHoverState() {
        guard let window = self.window else { return }
        let mouseOnScreen = NSEvent.mouseLocation
        let buttonOnScreen = window.convertToScreen(convert(bounds, to: nil))
        Self.isHovered = buttonOnScreen.contains(mouseOnScreen)
        applyCurrentImage()
    }

    // MARK: - Upload animation
    //
    // Ref-counted so overlapping uploads keep the animation running until
    // the last one finishes.

    @MainActor
    static func beginUploadAnimation() {
        uploadRefCount += 1
        guard uploadAnimationTimer == nil else { return }
        uploadPhase = false
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                uploadPhase.toggle()
                sharedButton?.applyCurrentImage()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        uploadAnimationTimer = timer
        sharedButton?.applyCurrentImage()
    }

    @MainActor
    static func endUploadAnimation() {
        uploadRefCount = max(0, uploadRefCount - 1)
        guard uploadRefCount == 0 else { return }
        uploadAnimationTimer?.invalidate()
        uploadAnimationTimer = nil
        uploadPhase = false
        sharedButton?.applyCurrentImage()
    }

    // MARK: - Drag destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAcceptDrag(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAcceptDrag(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
            !urls.isEmpty
        else {
            return false
        }
        Task.detached(priority: .userInitiated) {
            await Uploader.upload(urls)
        }
        return true
    }

    private func canAcceptDrag(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }
}
