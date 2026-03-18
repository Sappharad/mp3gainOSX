import AppKit

final class FileProgressViewItem: NSCollectionViewItem {
    override var nibName: NSNib.Name? { "FileProgressViewItem" }
    @IBOutlet weak var lblFilename: NSTextField!
    @IBOutlet weak var pbStatus: NSProgressIndicator!
    @IBOutlet weak var pbStatusOld: NSLevelIndicator!

    var itemTask: MP3GainTask?
    @objc dynamic var isStarted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        if representedObject != nil {
            let current = representedObject
            representedObject = current
        }
    }

    override var representedObject: Any? {
        didSet {
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
                        if NSAppKitVersion.current.rawValue >= NSAppKitVersion.macOS10_10.rawValue {
                            self.pbStatus.startAnimation(self)
                        }
                        self.isStarted = true
                    }

                    if percentComplete == 100.0 && task.files.count > 1 {
                        // Go back to indeterminate at the end of Album gain because it takes a few seconds to apply
                        // changes to all files after the scanning has finished.
                        self.pbStatus.isIndeterminate = true
                    } else if NSAppKitVersion.current.rawValue < NSAppKitVersion.macOS10_10.rawValue {
                        self.pbStatusOld.doubleValue = percentComplete
                    } else {
                        self.pbStatus.doubleValue = percentComplete
                    }
                }
            }

            lblFilename.stringValue = task.taskDescription
        }
    }
}
