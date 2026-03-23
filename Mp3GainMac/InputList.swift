import AppKit

final class InputList: NSObject, NSTableViewDataSource {
    private var list: [InputItem] = []

    var count: Int {
        list.count
    }

    func addObject(_ item: InputItem) {
        let hasAlready = list.contains { $0.filePath?.path == item.filePath?.path }
        if !hasAlready {
            list.append(item)
        }
    }

    func object(at index: Int) -> InputItem {
        list[index]
    }

    func allObjects() -> [InputItem] {
        list
    }

    func clear() {
        list.removeAll()
    }

    func remove(at index: Int) {
        list.remove(at: index)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        list.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0, row < list.count, let identifier = tableColumn?.identifier.rawValue else {
            return nil
        }

        let item = list[row]
        switch identifier {
        case "File":
            return item.filename
        case "Volume":
            if item.volume > 0 {
                return String(format: "%.2f dB", item.volume)
            } else if item.state == 1 {
                return NSLocalizedString("NoUndo", tableName: "ui_text", comment: "Can't Undo")
            } else if item.state == 2 {
                return NSLocalizedString("UnsupportedFile", tableName: "ui_text", comment: "Unsupported File")
            } else if item.state == 3 {
                return NSLocalizedString("Not_MP3_file", tableName: "ui_text", comment: "Not MP3 file")
            }
            return nil
        case "Clipping":
            return item.clipping
                ? NSLocalizedString("Yes", tableName: "ui_text", comment: "Yes")
                : NSLocalizedString("No", tableName: "ui_text", comment: "No")
        case "TrackGain" where item.volume > 0:
            // Not a mistake, don't use item.track_gain.
            return String(format: "%.2f dB", item.trackGain)
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // We always want to light up the table itself
        tableView.setDropRow(-1, dropOperation: .on)
        let fileList = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if fileList.contains(where: \ .isFileURL) {
            return .copy
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let fileList = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let fileManager = FileManager.default
        for url in fileList where url.isFileURL {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // You're getting 5 as the default, unless I make this configurable some day
                    addDirectory(url.path, subFoldersRemaining: 5)
                } else {
                    addFile(url.path)
                }
            }
        }
        tableView.reloadData()
        return false
    }

    func addFile(_ filePath: String) {
        // Note: Assumes file already exists. You should check this before calling this.
        let lower = filePath.lowercased()
        guard lower.hasSuffix(".mp3") || lower.hasSuffix(".mp4") || lower.hasSuffix(".m4a") else {
            return
        }

        let item = InputItem()
        item.filePath = URL(fileURLWithPath: filePath)
        addObject(item)
    }

    func addDirectory(_ folderPath: String, subFoldersRemaining depth: Int) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: folderPath) else {
            return
        }

        let normalizedFolder = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        for file in files.sorted() {
            let filePath = normalizedFolder + file
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    addFile(filePath)
                } else if depth > 0 {
                    addDirectory(filePath, subFoldersRemaining: depth - 1)
                }
            }
        }
    }
}
