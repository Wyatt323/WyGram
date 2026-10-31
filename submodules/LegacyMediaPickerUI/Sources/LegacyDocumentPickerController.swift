import Foundation
import UIKit
import UniformTypeIdentifiers

public enum LegacyICloudFilePickerMode {
    case `default`
    case `import`
    case `export`

    var documentPickerMode: UIDocumentPickerMode {
        switch self {
        case .default:
            return .open
        case .import:
            return .import
        case .export:
            return .exportToService
        }
    }
}

// Keep the delegate on the UIKit controller itself: UIDocumentPicker's delegate
// is weak, while the surrounding LegacyController has a separate lifetime.
final class LegacyDocumentPickerController: UIDocumentPickerViewController, UIDocumentPickerDelegate {
    var forceDarkTheme = false
    var completed: (([URL]) -> Void)?
    private var didComplete = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
        if #available(iOS 13.0, *), self.forceDarkTheme {
            self.overrideUserInterfaceStyle = .dark
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // File providers and previews may temporarily cover the picker. Only a
        // real dismissal should cancel the surrounding attachment operation.
        if self.isBeingDismissed || self.presentingViewController == nil {
            DispatchQueue.main.async {
                self.complete(with: [])
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.complete(with: [])
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.complete(with: urls)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        self.complete(with: [url])
    }

    private func complete(with urls: [URL]) {
        guard !self.didComplete else {
            return
        }
        self.didComplete = true
        let completion = self.completed
        self.completed = nil

        // Release the native sheet before the caller dismisses the legacy
        // wrapper or presents an upload/limit dialog on the same window.
        if self.presentingViewController != nil {
            if self.isBeingDismissed, let transition = self.transitionCoordinator {
                transition.animate(alongsideTransition: nil, completion: { _ in
                    completion?(urls)
                })
            } else {
                self.dismiss(animated: true, completion: {
                    completion?(urls)
                })
            }
        } else {
            completion?(urls)
        }
    }
}

func makeLegacyDocumentPicker(mode: LegacyICloudFilePickerMode, url: URL?, documentTypes: [String], hasMultiselection: Bool, forceDarkTheme: Bool) -> LegacyDocumentPickerController {
    let controller: LegacyDocumentPickerController
    if case .export = mode, let url {
        if #available(iOS 14.0, *) {
            controller = LegacyDocumentPickerController(forExporting: [url], asCopy: true)
        } else {
            controller = LegacyDocumentPickerController(url: url, in: mode.documentPickerMode)
        }
    } else if #available(iOS 14.0, *), mode != .export {
        let contentTypes = documentTypes.compactMap { UTType($0) }
        if !contentTypes.isEmpty && contentTypes.count == documentTypes.count {
            controller = LegacyDocumentPickerController(forOpeningContentTypes: contentTypes, asCopy: mode == .import)
        } else {
            // Preserve custom document types which are not registered with UTType.
            controller = LegacyDocumentPickerController(documentTypes: documentTypes, in: mode.documentPickerMode)
        }
    } else {
        controller = LegacyDocumentPickerController(documentTypes: documentTypes, in: mode.documentPickerMode)
    }
    controller.forceDarkTheme = forceDarkTheme
    controller.delegate = controller
    if #available(iOS 11.0, *) {
        controller.allowsMultipleSelection = hasMultiselection
    }
    return controller
}
