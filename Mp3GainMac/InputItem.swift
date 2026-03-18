import Foundation

final class InputItem: NSObject {
    @objc dynamic var filePath: URL?
    @objc dynamic var volume: Double = 0
    @objc dynamic var clipping = false
    @objc dynamic var trackGain: Double = 0
    /*
     State values:
     0 - Normal
     1 - Cannot undo
     2 - Unsupported file
     */
    @objc dynamic var state: UInt16 = 0

    @objc var filename: String {
        filePath?.lastPathComponent ?? ""
    }
}
