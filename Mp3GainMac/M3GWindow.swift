import AppKit

final class M3GWindow: NSWindow, NSWindowDelegate {
    private var originalView: NSView?

    override func awakeFromNib() {
        super.awakeFromNib()

        let osxMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        let appKitVersion = NSAppKitVersion.current.rawValue
        // Note that since Dark Mode is officially supported in macOS 10.14, this hack is only used from 10.11 to 10.13.
        // I could have removed it completely, but some people might like having the feature.
        if osxMode == "Dark",
           appKitVersion >= NSAppKitVersion.macOS10_11.rawValue,
           appKitVersion <= NSAppKitVersion.macOS10_13.rawValue,
           !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
           let contentView {
            // This dark mode hack breaks if "Increase Contrast" is enabled in Accessiblity settings, so we don't support that.
            // Since I'm already doing something that I'm not supposed to, fixing it would be a lot more work than just disabling it.
            originalView = contentView
            let contentFrame = contentView.frame
            let windowFrame = frame

            appearance = NSAppearance(named: .vibrantDark)
            titlebarAppearsTransparent = true

            // NSVisualEffectView is only available in 10.10 and later. But so is Dark mode, so I shouldn't need to check if it exists.
            let visualEffectView = NSVisualEffectView(frame: contentFrame)
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.material = .ultraDark // Ultra dark is only available in 10.11 or later.
            styleMask.insert(.fullSizeContentView)
            self.contentView = visualEffectView

            visualEffectView.addSubview(contentView)
            contentView.frame = contentLayoutRect
            setFrame(windowFrame, display: true)
            delegate = self

            addObserver(self, forKeyPath: #keyPath(contentLayoutRect), options: .new, context: nil)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(contentLayoutRect) {
            originalView?.frame = contentLayoutRect
        }
    }

    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        var region = contentLayoutRect
        region.origin.y += region.size.height
        region.size.height = 0
        return region
    }
}
