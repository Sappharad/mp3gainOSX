import Cocoa

@main
final class MP3GainExpressAppDelegate: NSObject, NSApplicationDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private var inputList = InputList()
    private var tasks: [MP3GainTask] = []
    private var cancelCurrentOperation = false
    private var processItemHeight: CGFloat = 52

    // Top-level XIB objects (windows, panels, and the standalone accessory view) must be
    // strong in ARC apps: macOS 10.12+ ignores releasedWhenClosed=NO for ARC-managed objects,
    // so a weak outlet to a closed or not-yet-shown window becomes nil.
    @IBOutlet var window: NSWindow!
    @IBOutlet weak var vwMainBody: NSView!
    @IBOutlet weak var tblFileList: NSTableView!
    @IBOutlet weak var txtTargetVolume: NSTextField!
    @IBOutlet var pnlProgressView: NSPanel!
    @IBOutlet weak var cvProcessFiles: NSCollectionView!
    @IBOutlet weak var lblStatus: NSTextField!
    @IBOutlet weak var pbTotalProgress: NSProgressIndicator!
    @IBOutlet weak var btnCancel: NSButton!
    @IBOutlet var vwSubfolderPicker: NSView!
    @IBOutlet weak var ddlSubfolders: NSPopUpButton!
    @IBOutlet weak var mnuAdvancedGain: NSMenu!
    @IBOutlet weak var chkAvoidClipping: NSButton!
    @IBOutlet weak var btnAdvancedMenu: NSButton!
    @IBOutlet weak var chkAlbumGain: NSButton!
    @IBOutlet var wndPreferences: NSWindow!
    @IBOutlet var pnlWarning: NSPanel!
    @IBOutlet weak var chkDoNotWarnAgain: NSButton!


    func applicationDidFinishLaunching(_ notification: Notification) {
        inputList = InputList()
        tblFileList.dataSource = inputList
        tblFileList.registerForDraggedTypes([.URL])

        cvProcessFiles.register(NSNib(nibNamed: "FileProgressViewItem", bundle: nil), forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FileProgressViewItem"))
        cvProcessFiles.delegate = self
        cvProcessFiles.dataSource = self
        let processingLayout = NSCollectionViewGridLayout()
        processingLayout.minimumItemSize = NSSize(width: cvProcessFiles.bounds.width, height: processItemHeight)
        processingLayout.maximumItemSize = NSSize(width: cvProcessFiles.bounds.width, height: processItemHeight)
        cvProcessFiles.collectionViewLayout = processingLayout
        cvProcessFiles.isSelectable = false

        let prefs = Preferences.shared
        if prefs.rememberOptions {
            txtTargetVolume.floatValue = prefs.volume
            chkAvoidClipping.state = prefs.noClipping ? .on : .off
        }

        if !prefs.hideWarning {
            let attrTitle = NSMutableAttributedString(string: NSLocalizedString("DontWarnAgain", tableName: "ui_text", comment: "Do not show this warning again"))
            attrTitle.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: attrTitle.length))
            chkDoNotWarnAgain.attributedTitle = attrTitle
            pnlWarning.makeKeyAndOrderFront(self)
        }

        // Set toolbar images as templates so they invert automatically in dark mode:
        for item in window.toolbar?.items ?? [] {
            item.image?.isTemplate = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let prefs = Preferences.shared
        if prefs.rememberOptions {
            let targetVolume = txtTargetVolume.floatValue
            if targetVolume >= 50, targetVolume <= 100 {
                prefs.volume = targetVolume
            }
            prefs.noClipping = (chkAvoidClipping.state == .on)
        }
        prefs.hideWarning = (chkDoNotWarnAgain.state == .on)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        var addedAny = false
        for url in urls {
            guard url.isFileURL else { continue }
            let path = url.path.lowercased()
            if path.hasSuffix(".mp3") || path.hasSuffix(".m4a") {
                self.inputList.addFile(url.path)
                addedAny = true
            }
        }
        // Always surface the main window when the app is asked to open files,
         // even if none of the URLs matched a supported extension.
         window.makeKeyAndOrderFront(nil)
        if addedAny {
            tblFileList.reloadData()
        }
    }

    @IBAction func showPreferences(_ sender: Any?) {
        wndPreferences.makeKeyAndOrderFront(self)
    }

    @IBAction func btnAddFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["mp3", "mp4", "m4a"]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            for file in panel.urls where file.isFileURL {
                self.inputList.addFile(file.path)
            }
            self.tblFileList.reloadData()
        }
    }

    @IBAction func btnAddFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        ddlSubfolders.removeAllItems()
        ddlSubfolders.addItems(withTitles: [
            NSLocalizedString("None", tableName: "ui_text", comment: "None"),
            NSLocalizedString("1_Below", tableName: "ui_text", comment: "1_Below"),
            NSLocalizedString("2_Below", tableName: "ui_text", comment: "2_Below"),
            NSLocalizedString("3_Below", tableName: "ui_text", comment: "3_Below"),
            NSLocalizedString("4_Below", tableName: "ui_text", comment: "4_Below"),
            NSLocalizedString("5_Below", tableName: "ui_text", comment: "5_Below")
        ])
        panel.accessoryView = vwSubfolderPicker
        if panel.responds(to: #selector(getter: NSOpenPanel.isAccessoryViewDisclosed)) {
            panel.isAccessoryViewDisclosed = true
        }

        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            let depthAmount = Int(self.ddlSubfolders.indexOfSelectedItem)
            for folder in panel.urls {
                self.inputList.addDirectory(folder.path, subFoldersRemaining: depthAmount)
            }
            self.tblFileList.reloadData()
        }
    }

    @IBAction func btnClearFile(_ sender: Any?) {
        for currentIndex in tblFileList.selectedRowIndexes.reversed() {
            inputList.remove(at: currentIndex)
        }
        tblFileList.reloadData()
    }

    @IBAction func btnClearAll(_ sender: Any?) {
        inputList.clear()
        tblFileList.reloadData()
    }

    @IBAction func btnAnalyze(_ sender: Any?) {
        if checkValidOperation(), inputList.count > 0 {
            beginProgressSheet()
            doAnalysis(album: chkAlbumGain.state == .on)
        }
    }

    @IBAction func btnApplyGain(_ sender: Any?) {
        if checkValidOperation(), inputList.count > 0 {
            beginProgressSheet()
            doModify(noClip: chkAvoidClipping.state == .on, albumMode: chkAlbumGain.state == .on)
        }
    }

    @IBAction func doGainRemoval(_ sender: Any?) {
        if inputList.count > 0 {
            beginProgressSheet()
            undoModify()
        }
    }

    @IBAction func btnCancel(_ sender: Any?) {
        // Clicking cancel stops after the currently processing files are done. It removes any that haven't started yet.
        cancelCurrentOperation = true
        lblStatus.stringValue = NSLocalizedString("Canceling_soon", tableName: "ui_text", comment: "Canceling soon")
        btnCancel.isEnabled = false

        // Remove all of the tasks that haven't started from the collection without reloading the entire list.
        let oldCount = tasks.count
        tasks = tasks.filter(\.inProgress)
        let removedCount = oldCount - tasks.count
        if removedCount > 0 {
            let removedIndexes = IndexSet(tasks.count..<oldCount)
            let removedPaths = Set(removedIndexes.map { IndexPath(item: $0, section: 0) })
            cvProcessFiles.deleteItems(at: removedPaths)
        }
        pbTotalProgress.doubleValue = Double(inputList.count - tasks.count)
    }

    @IBAction func btnShowAdvanced(_ sender: Any?) {
        mnuAdvancedGain.popUp(positioning: nil, at: btnAdvancedMenu.frame.origin, in: vwMainBody)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func checkValidOperation() -> Bool {
        let gain = txtTargetVolume.floatValue
        if gain < 50.0 || gain >= 100.0 {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("InvalidVolume", tableName: "ui_text", comment: "Invalid target volume!")
            alert.informativeText = NSLocalizedString("VolumeInfo", tableName: "ui_text", comment: "The target volume should be a number between 50 and 100 dB.")
            alert.addButton(withTitle: NSLocalizedString("OK", tableName: "ui_text", comment: "OK"))
            alert.runModal()
            return false
        }
        return true
    }

    private func getNumConcurrentTasks() -> Int {
        Preferences.shared.numProcesses
    }

    private func doAnalysis(album: Bool) {
        tasks = []
        if !album || inputList.count == 1 {
            for index in 0..<inputList.count {
                let task = MP3GainTask.task(with: inputList.object(at: index), action: .analyze)
                task.desiredDb = NSNumber(value: txtTargetVolume.floatValue)
                task.onProcessingComplete = { [weak self, weak task] in
                    guard let self, let task else { return }
                    self.handleTaskCompletion(task)
                }
                tasks.append(task)
            }
        } else {
            // This is an album - Do not process it twice because reprocessing doesn't use single file data.
            let task = MP3GainTask.task(with: inputList.allObjects(), action: .analyze)
            task.desiredDb = NSNumber(value: txtTargetVolume.floatValue)
            task.onProcessingComplete = { [weak self, weak task] in
                guard let self, let task else { return }
                self.handleTaskCompletion(task)
            }
            tasks.append(task)
        }

        cvProcessFiles.reloadData()
        for index in 0..<min(tasks.count, getNumConcurrentTasks()) {
            tasks[index].process()
        }
    }

    private func doModify(noClip: Bool, albumMode album: Bool) {
        tasks = []
        if !album || inputList.count == 1 {
            for index in 0..<inputList.count {
                let task = MP3GainTask.task(with: inputList.object(at: index), action: .apply)
                task.noClipping = noClip
                task.desiredDb = NSNumber(value: txtTargetVolume.floatValue)
                task.onProcessingComplete = { [weak self, weak task] in
                    guard let self, let task else { return }
                    self.handleTaskCompletion(task)
                }
                tasks.append(task)
            }
        } else {
            // Album mode - Don't process twice because it doesn't use analyze data
            let task = MP3GainTask.task(with: inputList.allObjects(), action: .apply)
            task.noClipping = noClip
            task.desiredDb = NSNumber(value: txtTargetVolume.floatValue)
            task.onProcessingComplete = { [weak self, weak task] in
                guard let self, let task else { return }
                self.handleTaskCompletion(task)
            }
            tasks.append(task)
        }

        cvProcessFiles.reloadData()
        for index in 0..<min(tasks.count, getNumConcurrentTasks()) {
            tasks[index].process()
        }
    }

    private func undoModify() {
        tasks = []
        for index in 0..<inputList.count {
            let task = MP3GainTask.task(with: inputList.object(at: index), action: .undo)
            task.onProcessingComplete = { [weak self, weak task] in
                guard let self, let task else { return }
                self.handleTaskCompletion(task)
            }
            tasks.append(task)
        }

        cvProcessFiles.reloadData()
        for index in 0..<min(tasks.count, getNumConcurrentTasks()) {
            tasks[index].process()
        }
    }

    private func handleTaskCompletion(_ task: MP3GainTask) {
        DispatchQueue.main.async {
            guard let completedIndex = self.tasks.firstIndex(where: { $0 === task }) else {
                return
            }

            self.tasks.remove(at: completedIndex)
            self.cvProcessFiles.deleteItems(at: [IndexPath(item: completedIndex, section: 0)])

            if task.failureCount == 1 {
                // Re-add file to end of the list on the first failure.
                let insertIndex = self.tasks.count
                self.tasks.append(task)
                self.cvProcessFiles.insertItems(at: [IndexPath(item: insertIndex, section: 0)])
            }

            self.pbTotalProgress.doubleValue = Double(self.inputList.count - self.tasks.count)

            let filesLeft = self.tasks.count
            if filesLeft == 0 {
                self.window.endSheet(self.pnlProgressView) // Tell the sheet we're done.
                self.pnlProgressView.orderOut(self) // Lets hide the sheet.
                self.tblFileList.reloadData()
                self.tasks.removeAll()
            } else if !self.cancelCurrentOperation {
                // Find next file to begin processing
                for nextTask in self.tasks where !nextTask.inProgress && (filesLeft == 1 || nextTask.files.count == 1) {
                    // Album task MUST be processed last, so check files left even though it should always be at the end of the list.
                    nextTask.process()
                    break
                }
            }
        }
    }

    private func beginProgressSheet() {
        window.beginSheet(pnlProgressView, completionHandler: nil)
        lblStatus.stringValue = NSLocalizedString("Working", tableName: "ui_text", comment: "Working...")
        pbTotalProgress.usesThreadedAnimation = true
        pbTotalProgress.startAnimation(self)
        pbTotalProgress.minValue = 0.0
        pbTotalProgress.maxValue = Double(inputList.count)
        pbTotalProgress.doubleValue = 0.0
        btnCancel.isEnabled = true
        cancelCurrentOperation = false
    }


    // MARK: - Virtual Collection view for progress dialog
    func numberOfSectionsInCollectionView(collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        tasks.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = self.cvProcessFiles.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FileProgressViewItem"), for: indexPath)
        item.representedObject = tasks[indexPath.item]
        return item
    }
    
}
