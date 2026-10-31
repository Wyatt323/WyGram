import Foundation
import UIKit
import Display
import TelegramPresentationData
import LegacyUI

public func legacyICloudFilePicker(theme: PresentationTheme, mode: LegacyICloudFilePickerMode = .default, hasMultiselection: Bool = false, url: URL? = nil, documentTypes: [String] = ["public.item"], forceDarkTheme: Bool = false, dismissed: @escaping () -> Void = {}, completion: @escaping ([URL]) -> Void) -> ViewController {
    let legacyController = LegacyController(presentation: .modal(animateIn: true), theme: theme)
    let controller = makeLegacyDocumentPicker(mode: mode, url: url, documentTypes: documentTypes, hasMultiselection: hasMultiselection, forceDarkTheme: forceDarkTheme || theme.overallDarkAppearance)
    controller.completed = { [weak legacyController] urls in
        legacyController?.dismiss()
        dismissed()
        completion(urls)
    }
    legacyController.statusBar.statusBarStyle = .Black
    
    legacyController.presentationCompleted = { [weak legacyController] in
        if let legacyController = legacyController {
            if let window = legacyController.view.window {
                legacyController.presentationCompleted = nil
                controller.popoverPresentationController?.sourceView = window
                controller.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
                window.rootViewController?.present(controller, animated: true)
            }
        }
    }
    
    legacyController.bind(controller: UIViewController())
    return legacyController
}
