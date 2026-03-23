import AppKit

final class FileProgressViewItem: NSCollectionViewItem {
    @IBOutlet weak var lblFilename: NSTextField!
    @IBOutlet weak var pbStatus: NSProgressIndicator!
    var itemTask: MP3GainTask?
    @objc dynamic var isStarted = false

    override var representedObject: Any? {
        didSet {
            if representedObject as? MP3GainTask != itemTask && itemTask != nil {
                itemTask!.onStatusUpdate = nil //We're reusing this row, unhook it from the previous events
            }
            guard isViewLoaded else { return }
            isStarted = false
            pbStatus.minValue = 0.0
            pbStatus.maxValue = 100.0
            pbStatus.usesThreadedAnimation = true

            guard let task = representedObject as? MP3GainTask else {
                itemTask = nil
                return
            }

            itemTask = task
            pbStatus.doubleValue = itemTask?.statusValue ?? 0.0
            if task.files.count > 1 {
                pbStatus.isIndeterminate = true
            }

            task.onStatusUpdate = { [weak self] percentComplete in
                DispatchQueue.main.async {
                    guard let self, self.pbStatus != nil else { return }
                    if !self.isStarted {
                        if task.files.count > 1 {
                            self.pbStatus.isIndeterminate = false
                        }
                        self.pbStatus.startAnimation(self)
                        self.isStarted = true
                    }

                    if percentComplete == 100.0 && task.files.count > 1 {
                        // Go back to indeterminate at the end of Album gain because it takes a few seconds to apply
                        // changes to all files after the scanning has finished.
                        self.pbStatus.isIndeterminate = true
                    } else {
                        self.pbStatus.doubleValue = percentComplete
                    }
                }
            }

            lblFilename.stringValue = task.taskDescription
        }
    }
}
