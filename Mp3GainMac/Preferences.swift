import Foundation

@objc enum TagFormat: Int {
    case ape = 0   // APE
    case id3v2 = 1   // ID3v2
    case none = 2  // None
}

final class Preferences: NSObject {
    static let shared = Preferences()

    private enum Keys {
        static let numProcesses = "m3g_NumProcesses"
        static let rememberOptions = "m3g_RememberOptions"
        static let volume = "m3g_Volume"
        static let noClipping = "m3g_NoClipping"
        static let hideWarning = "m3g_HideWarning"
        static let tagFormat = "m3g_TagFormat"
    }

    private override init() {}

    @objc var maxCores: UInt32 {
        var numCores: UInt32 = 0
        var length = MemoryLayout<UInt32>.size
        sysctlbyname("hw.ncpu", &numCores, &length, nil, 0)
        return numCores
    }

    @objc var numProcesses: Int {
        get {
            let maxCores = Int(self.maxCores)
            var fallback = 2
            if maxCores >= 4 {
                fallback = 4
            }
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Keys.numProcesses) != nil {
                let userProcesses = defaults.integer(forKey: Keys.numProcesses)
                if userProcesses <= maxCores {
                    fallback = userProcesses
                }
            }
            return fallback
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.numProcesses)
        }
    }

    @objc var rememberOptions: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Keys.rememberOptions) != nil {
                return defaults.bool(forKey: Keys.rememberOptions)
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.rememberOptions)
        }
    }

    @objc var volume: Float {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Keys.volume) != nil {
                return defaults.float(forKey: Keys.volume)
            }
            return 89.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.volume)
        }
    }

    @objc var noClipping: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Keys.noClipping) != nil {
                return defaults.bool(forKey: Keys.noClipping)
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.noClipping)
        }
    }

    @objc var hideWarning: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Keys.hideWarning) != nil {
                return defaults.bool(forKey: Keys.hideWarning)
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.hideWarning)
        }
    }
    
    @objc var tagFormat: Int {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Keys.tagFormat) != nil {
                let tagFormat = defaults.integer(forKey: Keys.tagFormat)
                if(tagFormat >= TagFormat.ape.rawValue && tagFormat <= TagFormat.none.rawValue) {
                    return tagFormat
                }
            }
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.tagFormat)
        }
    }
}
