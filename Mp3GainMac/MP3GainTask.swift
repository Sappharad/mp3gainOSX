import Foundation

enum MP3GainActionType {
    case analyze
    case apply
    case undo
}

final class MP3GainTask: NSObject {
    private var task: Process?
    private var detailsPipe: Pipe?
    private var statusPipe: Pipe?
    private var statusReadSource: DispatchSourceRead?
    private var stderrBuffer = Data()
    private let stderrBufferQueue = DispatchQueue(label: "MP3GainTask.stderrBuffer")

    var files: [InputItem] = []
    var action: MP3GainActionType = .analyze
    var desiredDb: NSNumber?
    var noClipping = false
    var inProgress = false
    var twoPass = false
    var fatalError = false
    var failureCount = 0
    var statusValue = 0.0
    var onProcessingComplete: (() -> Void)?
    var onStatusUpdate: ((Double) -> Void)?

    static func task(with file: InputItem, action: MP3GainActionType) -> MP3GainTask {
        let task = MP3GainTask()
        task.files = [file]
        task.action = action
        task.inProgress = false
        task.twoPass = false
        task.failureCount = 0
        task.fatalError = false
        file.state = 0
        return task
    }

    static func task(with files: [InputItem], action: MP3GainActionType) -> MP3GainTask {
        let task = MP3GainTask()
        task.files = files
        task.action = action
        task.inProgress = false
        task.twoPass = false
        task.failureCount = 0
        task.fatalError = false
        return task
    }

    var taskDescription: String {
        guard !files.isEmpty else { return "" }
        if files.count > 1 {
            // When in Album mode, we always scan the tracks individually so that multiple tracks can be scanned at the same time.
            // Then we run it again in album mode, which doesn't need to rescan the files because ReplayGain tags were generated
            // during the initial scan. This allows album mode to benefit from the performance gained by scanning multiple files at once.
            return NSLocalizedString("reprocessAlbum", tableName: "ui_text", comment: "Process as Album...")
        }
        return files[0].filename
    }

    func process() {
        inProgress = true
        if files.count == 1 {
            files.forEach { $0.clipping = false } // Clear clipping flag, will be set later.
        }

        switch action {
        case .analyze:
            analyzeFile()
        case .apply:
            if files.count == 1 && (!noClipping || files[0].volume == 0) {
                // Always need 2 passes if NoClipping is off, because we don't get notified about clipping during the Apply process.
                // Can't trust previous data because they could change the desired volume on us.
                twoPass = true
                analyzeFile()
            } else {
                applyGain()
            }
        case .undo:
            undoGain()
        }
    }

    private func analyzeFile() {
        let target = desiredDb?.doubleValue ?? 89.0
        var arguments = ["-d", String(format: "%f", target - 89.0)]
        arguments.append(contentsOf: files.compactMap { $0.filePath?.path })
        doProcessing(arguments)
    }

    private func applyGain() {
        let target = desiredDb?.doubleValue ?? 89.0
        var arguments = noClipping
            ? ["-r", "-k", "-d", String(format: "%f", target - 89.0)]
            : ["-r", "-c", "-d", String(format: "%f", target - 89.0)]
        if files.count > 1 {
            arguments[0] = "-a"
        }
        arguments.append(contentsOf: files.compactMap { $0.filePath?.path })
        doProcessing(arguments)
    }

    private func undoGain() {
        guard let path = files.first?.filePath?.path else { return }
        doProcessing(["-u", path])
    }

    private func doProcessing(_ arguments: [String]) {
        let process = Process()
        self.task = process
        stderrBufferQueue.sync { stderrBuffer.removeAll(keepingCapacity: true) }

        guard let launchPath = Bundle.main.path(forResource: "aacgain", ofType: nil) else {
            handleLaunchFailure()
            return
        }

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let detailsPipe = Pipe()
        let statusPipe = Pipe()
        self.detailsPipe = detailsPipe
        self.statusPipe = statusPipe
        process.standardInput = Pipe()
        process.standardOutput = detailsPipe

        // Fun fact: Having status on stderr caused file corruption in previous releases when mp3gain was internal
        process.standardError = statusPipe

        startStatusReading(from: statusPipe.fileHandleForReading)

        process.terminationHandler = { [weak self, weak detailsPipe] proc in
            guard let self else { return }
            let statusData = self.stderrBufferQueue.sync { self.stderrBuffer }
            let detailsData = detailsPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let statusOutput = String(data: statusData, encoding: .utf8) ?? ""
            let detailsOutput = String(data: detailsData, encoding: .utf8) ?? ""

            self.stopStatusReading()
            self.handleErrorStream(statusOutput)
            if !self.fatalError {
                self.parseProcessDetails(detailsOutput)
            }

            if self.fatalError, let onProcessingComplete = self.onProcessingComplete {
                self.failureCount = 2
                onProcessingComplete()
            } else if proc.terminationStatus > 0 {
                for file in self.files where file.state == 0 {
                    file.state = 2
                }
                self.onProcessingComplete?()
            } else if proc.terminationStatus == 0, self.twoPass, self.action == .apply {
                self.twoPass = false
                self.cleanupTaskAndApply()
            } else {
                self.onProcessingComplete?()
            }
        }

        do {
            try process.run()
        } catch {
            // Failed to launch mp3gain command line tool for some reason.
            // Add this task to the end of the list if this was the first time it failed, otherwise remove it and mark it as failed.
            handleLaunchFailure()
        }
    }

    private func handleLaunchFailure() {
        if failureCount == 1 {
            for file in files where file.state == 0 {
                file.state = 2
            }
        }
        failureCount += 1
        if failureCount == 1 {
            inProgress = false
        }
        onProcessingComplete?()
    }

    private func cleanupTaskAndApply() {
        stopStatusReading()
        detailsPipe = nil
        statusPipe = nil
        task = nil

        DispatchQueue.main.async { [weak self] in
            self?.applyGain()
        }
    }

    private func parseProcessDetails(_ details: String) {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US_POSIX")

        for line in details.components(separatedBy: .newlines) {
            // The strings we search for are copy/pasted from the source of the mp3gain build we're running against, so they should be correct.
            if let range = line.range(of: "Recommended \"Track\" dB change: ") {
                let suffix = String(line[range.upperBound...])
                if let dbChange = numberFormatter.number(from: suffix)?.doubleValue {
                    updateGainValues(with: dbChange)
                }
            } else if line.contains("WARNING: some clipping may occur with this gain change!") {
                files.forEach { $0.clipping = true }
            } else if let range = line.range(of: "Applying auto-clipped mp3 gain change of ") {
                let suffix = String(line[range.upperBound...])
                if let endRange = suffix.range(of: " to ") {
                    let numberText = String(suffix[..<endRange.lowerBound])
                    if let dbChange = numberFormatter.number(from: numberText)?.doubleValue {
                        files.forEach { $0.trackGain = dbChange }
                    }
                }
            } else if let range = line.range(of: "Recommended \"Album\" dB change for all files: ") {
                let suffix = String(line[range.upperBound...])
                if let dbChange = numberFormatter.number(from: suffix)?.doubleValue {
                    updateGainValues(with: dbChange)
                }
            } else if line.contains("Can't find any valid MP3 frames") || line.contains("MPEG Layer I file, not a layer III file") {
                files.forEach { $0.state = 3 }
            } else if line.contains("is not a valid mp4/m4a file") {
                files.forEach { $0.state = 2 }
                fatalError = true
            }
        }
    }

    private func updateGainValues(with dbChange: Double) {
        let target = desiredDb?.doubleValue ?? 89.0
        for file in files {
            file.volume = target - dbChange
            file.trackGain = dbChange
        }
    }

    private func startStatusReading(from handle: FileHandle) {
        stopStatusReading()
        let source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self, weak handle] in
            guard let self, let handle else { return }
            let data = handle.availableData
            if data.isEmpty {
                self.stopStatusReading()
                return
            }
            self.stderrBufferQueue.async {
                self.stderrBuffer.append(data)
            }
            let actualText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.handleErrorStream(actualText)
        }
        statusReadSource = source
        source.resume()
    }

    private func stopStatusReading() {
        statusReadSource?.cancel()
        statusReadSource = nil
    }

    private func handleErrorStream(_ actualText: String) {
        if actualText.contains("The file was not modified.") {
            // If the end result is the file not being processed, throw away previous results
            // because we can't use them.
            for file in files {
                file.state = 2
                file.volume = 0
                fatalError = true
            }
            return
        }

        if actualText.contains("No changes to undo in") || actualText.contains("No undo information in") {
            files.forEach { $0.state = 1 }
            return
        }

        if !fatalError, files.count == 1, actualText.count > 4, let percentIndex = actualText.firstIndex(of: "%") {
            // Find the % and convert it to a double
            let number = String(actualText[..<percentIndex])
            if let progress = NumberFormatter().number(from: number)?.doubleValue {
                statusValue = progress;
                onStatusUpdate?(progress)
            }
            return
        }

        let albumMarker = "/\(files.count)]"
        if !fatalError, files.count > 1, actualText.count > 4, let albumRange = actualText.range(of: albumMarker), let bracketIndex = findLeftBracket(in: actualText, endingAt: albumRange.lowerBound) {
            let start = actualText.index(after: bracketIndex)
            let number = String(actualText[start..<albumRange.lowerBound])
            if let progress = NumberFormatter().number(from: number)?.intValue {
                if progress == files.count {
                    statusValue = 100.0
                    onStatusUpdate?(100.0)
                } else {
                    let percent = Double(progress - 1) * 100.0 / Double(files.count)
                    statusValue = percent
                    onStatusUpdate?(percent)
                }
            }
        }
    }

    private func findLeftBracket(in text: String, endingAt end: String.Index) -> String.Index? {
        var index = end
        while index > text.startIndex {
            if text[index] == "[" {
                return index
            }
            index = text.index(before: index)
        }
        return text.startIndex < text.endIndex && text[text.startIndex] == "[" ? text.startIndex : nil
    }
}
