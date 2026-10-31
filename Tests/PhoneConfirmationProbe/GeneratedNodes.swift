import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import SolidRoundedButtonNode
import PresentationDataUtils
import SwiftSignalKit

    final class LegacyPhoneConfirmationNode: ASDisplayNode {
        private let theme: PresentationTheme
        private let strings: PresentationStrings
        
        private let code: String
        private let number: String
        
        private let dimNode: ASDisplayNode
        private let backgroundNode: ASDisplayNode
        
        private let codeSourceNode: ImmediateTextNode
        private let phoneSourceNode: ImmediateTextNode
        
        private let codeTargetNode: ImmediateTextNode
        private let phoneTargetNode: ImmediateTextNode
        private let measureTargetNode: ImmediateTextNode
        
        private let textNode: ImmediateTextNode
        private let textActivateAreaNode: AccessibilityAreaNode
        
        private let cancelButton: HighlightableButtonNode
        fileprivate let proceedNode: SolidRoundedButtonNode
        
        var proceed: () -> Void = {}
        var cancel: () -> Void = {}
        
        private var validLayout: ContainerViewLayout?
        
        init(theme: PresentationTheme, strings: PresentationStrings, code: String, number: String) {
            self.theme = theme
            self.strings = strings
            
            self.code = code
            self.number = number
            
            self.dimNode = ASDisplayNode()
            self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
            
            self.backgroundNode = ASDisplayNode()
            self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
            self.backgroundNode.cornerRadius = 42.0
            
            self.textNode = ImmediateTextNode()
            self.textNode.displaysAsynchronously = false
            self.textNode.attributedText = NSAttributedString(string: strings.Login_PhoneNumberConfirmation, font: Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor)
            self.textNode.textAlignment = .center
            
            self.textActivateAreaNode = AccessibilityAreaNode()
            self.textActivateAreaNode.accessibilityTraits = .staticText
            
            self.cancelButton = HighlightableButtonNode()
            self.cancelButton.setTitle(strings.Login_Edit, with: Font.regular(19.0), with: theme.list.itemAccentColor, for: .normal)
            self.cancelButton.accessibilityTraits = [.button]
            self.cancelButton.accessibilityLabel = strings.Login_Edit
            
            self.proceedNode = SolidRoundedButtonNode(title: strings.Login_Continue, theme: SolidRoundedButtonTheme(theme: theme), glass: false, height: 50.0, cornerRadius: 50.0 * 0.5)
            self.proceedNode.progressType = .embedded
            self.proceedNode.accessibilityIdentifier = "Auth.PhoneConfirm.ContinueButton"

            let font = Font.with(size: 20.0, design: .regular, traits: [.monospacedNumbers])
            let largeFont = Font.with(size: 34.0, design: .regular, weight: .bold, traits: [.monospacedNumbers])
            
            self.codeSourceNode = ImmediateTextNode()
            self.codeSourceNode.alpha = 0.0
            self.codeSourceNode.displaysAsynchronously = false
            self.codeSourceNode.attributedText = NSAttributedString(string: code, font: font, textColor: theme.list.itemPrimaryTextColor)
            
            self.phoneSourceNode = ImmediateTextNode()
            self.phoneSourceNode.alpha = 0.0
            self.phoneSourceNode.displaysAsynchronously = false
            
            let sourceString = NSMutableAttributedString(string: number, font: font, textColor: theme.list.itemPrimaryTextColor)
            sourceString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: sourceString.length))
            self.phoneSourceNode.attributedText = sourceString
            
            self.codeTargetNode = ImmediateTextNode()
            self.codeTargetNode.displaysAsynchronously = false
            self.codeTargetNode.attributedText = NSAttributedString(string: code, font: largeFont, textColor: theme.list.itemPrimaryTextColor)
            
            self.phoneTargetNode = ImmediateTextNode()
            self.phoneTargetNode.displaysAsynchronously = false
            
            self.measureTargetNode = ImmediateTextNode()
            self.measureTargetNode.displaysAsynchronously = false
            self.measureTargetNode.maximumNumberOfLines = 1
            
            let targetString = NSMutableAttributedString(string: number, font: largeFont, textColor: theme.list.itemPrimaryTextColor)
            targetString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: sourceString.length))
            self.phoneTargetNode.attributedText = targetString
            
            super.init()
            
            self.clipsToBounds = false
            
            self.addSubnode(self.dimNode)
            self.addSubnode(self.backgroundNode)
            
            self.addSubnode(self.codeSourceNode)
            self.addSubnode(self.phoneSourceNode)
            
            self.addSubnode(self.codeTargetNode)
            self.addSubnode(self.phoneTargetNode)
            
            self.addSubnode(self.textNode)
            self.addSubnode(self.textActivateAreaNode)
            
            self.addSubnode(self.cancelButton)
            self.addSubnode(self.proceedNode)
            
            self.cancelButton.addTarget(self, action: #selector(self.cancelPressed), forControlEvents: .touchUpInside)
            self.proceedNode.pressed = { [weak self] in
                self?.proceed()
            }
        }
        
        override func didLoad() {
            super.didLoad()
            
            self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        }
        
        @objc private func dimTapped() {
            self.cancelPressed()
        }
        
        @objc private func cancelPressed() {
            self.dimNode.isUserInteractionEnabled = false
            self.cancel()
        }
        
        func animateIn(codeNode: ASDisplayNode, numberNode: ASDisplayNode, buttonNode: ASDisplayNode) {
            guard let layout = self.validLayout else {
                return
            }
            let codeFrame = codeNode.convert(codeNode.bounds, to: nil)
            let numberFrame = numberNode.convert(numberNode.bounds, to: nil)
            let buttonFrame = buttonNode.convert(buttonNode.bounds, to: nil)
            
            codeNode.isHidden = true
            numberNode.isHidden = true
            buttonNode.isHidden = true
            
            self.dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            
            let duration: Double = 0.25
            
            let codeSize = self.codeSourceNode.updateLayout(layout.size)
            self.codeSourceNode.frame = CGRect(origin: CGPoint(x: codeFrame.midX - codeSize.width / 2.0, y: codeFrame.midY - codeSize.height / 2.0), size: codeSize)
            
            let numberSize = self.phoneSourceNode.updateLayout(layout.size)
            self.phoneSourceNode.frame = CGRect(origin: CGPoint(x: numberFrame.minX, y: numberFrame.midY - numberSize.height / 2.0), size: numberSize)
            
            let targetScale = codeSize.height / self.codeTargetNode.frame.height
            let sourceScale = self.codeTargetNode.frame.height / codeSize.height
            
            self.codeSourceNode.layer.animateScale(from: 1.0, to: sourceScale, duration: duration)
            self.codeSourceNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration)
            self.codeSourceNode.layer.animatePosition(from: self.codeSourceNode.position, to: self.codeTargetNode.position, duration: duration)
            
            self.phoneSourceNode.layer.animateScale(from: 1.0, to: sourceScale, duration: duration)
            self.phoneSourceNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration)
            self.phoneSourceNode.layer.animatePosition(from: self.phoneSourceNode.position, to: self.phoneTargetNode.position, duration: duration)
            
            self.codeTargetNode.layer.animateScale(from: targetScale, to: 1.0, duration: duration)
            self.codeTargetNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.codeTargetNode.layer.animatePosition(from: self.codeSourceNode.position, to: self.codeTargetNode.position, duration: duration)
            
            self.phoneTargetNode.layer.animateScale(from: targetScale, to: 1.0, duration: duration)
            self.phoneTargetNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.phoneTargetNode.layer.animatePosition(from: self.phoneSourceNode.position, to: self.phoneTargetNode.position, duration: duration)
            
            self.backgroundNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
            
            self.backgroundNode.layer.animateFrame(from: CGRect(origin: CGPoint(x: self.backgroundNode.frame.origin.x + 6.0, y: codeFrame.minY), size: CGSize(width: self.backgroundNode.frame.width - 12.0, height: buttonFrame.maxY + 18.0 - codeFrame.minY)), to: self.backgroundNode.frame, duration: duration)
            
            self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.textNode.layer.animateScale(from: 0.5, to: 1.0, duration: duration)
            self.textNode.layer.animatePosition(from: CGPoint(x: -100.0, y: -45.0), to: CGPoint(), duration: duration, additive: true)
            
            self.cancelButton.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.cancelButton.layer.animateScale(from: 0.5, to: 1.0, duration: duration)
            self.cancelButton.layer.animatePosition(from: CGPoint(x: -100.0, y: -70.0), to: CGPoint(), duration: duration, additive: true)
            
            self.proceedNode.layer.animatePosition(from: buttonFrame.center, to: self.proceedNode.position, duration: duration)
        }
        
        func animateOut(codeNode: ASDisplayNode, numberNode: ASDisplayNode, buttonNode: ASDisplayNode, completion: @escaping () -> Void) {
            let codeFrame = codeNode.convert(codeNode.bounds, to: nil)
            let numberFrame = numberNode.convert(numberNode.bounds, to: nil)
            let buttonFrame = buttonNode.convert(buttonNode.bounds, to: nil)
            
            self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            
            let duration: Double = 0.25
            
            let codeSize = self.codeSourceNode.updateLayout(self.frame.size)
            self.codeSourceNode.frame = CGRect(origin: CGPoint(x: codeFrame.midX - codeSize.width / 2.0, y: codeFrame.midY - codeSize.height / 2.0), size: codeSize)
            
            let numberSize = self.phoneSourceNode.updateLayout(self.frame.size)
            self.phoneSourceNode.frame = CGRect(origin: CGPoint(x: numberFrame.minX, y: numberFrame.midY - numberSize.height / 2.0), size: numberSize)
            
            let targetScale = codeSize.height / self.codeTargetNode.frame.height
            let sourceScale = self.codeTargetNode.frame.height / codeSize.height
            
            self.codeSourceNode.layer.animateScale(from: sourceScale, to: 1.0, duration: duration)
            self.codeSourceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.codeSourceNode.layer.animatePosition(from: self.codeTargetNode.position, to: self.codeSourceNode.position, duration: duration)
            
            self.phoneSourceNode.layer.animateScale(from: sourceScale, to: 1.0, duration: duration)
            self.phoneSourceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.phoneSourceNode.layer.animatePosition(from: self.phoneTargetNode.position, to: self.phoneSourceNode.position, duration: duration)
            
            self.codeTargetNode.layer.animateScale(from: 1.0, to: targetScale, duration: duration)
            self.codeTargetNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
            self.codeTargetNode.layer.animatePosition(from: self.codeTargetNode.position, to: self.codeSourceNode.position, duration: duration)
            
            Queue.mainQueue().after(0.2) {
                codeNode.isHidden = false
                numberNode.isHidden = false
                buttonNode.isHidden = false
            }
            
            self.phoneTargetNode.layer.animateScale(from: 1.0, to: targetScale, duration: duration)
            self.phoneTargetNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false, completion: { _ in
                completion()
            })
            self.phoneTargetNode.layer.animatePosition(from: self.phoneTargetNode.position, to: self.phoneSourceNode.position, duration: duration)
            
            self.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, delay: 0.1, removeOnCompletion: false)
            self.backgroundNode.layer.animateFrame(from: self.backgroundNode.frame, to: CGRect(origin: CGPoint(x: self.backgroundNode.frame.origin.x + 6.0, y: codeFrame.minY), size: CGSize(width: self.backgroundNode.frame.width - 12.0, height: buttonFrame.maxY + 18.0 - codeFrame.minY)), duration: duration)
                        
            self.textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.textNode.layer.animateScale(from: 1.0, to: 0.5, duration: duration, removeOnCompletion: false)
            self.textNode.layer.animatePosition(from: CGPoint(), to: CGPoint(x: -100.0, y: -45.0), duration: duration, removeOnCompletion: false, additive: true)
            
            self.cancelButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.cancelButton.layer.animateScale(from: 1.0, to: 0.5, duration: duration, removeOnCompletion: false)
            self.cancelButton.layer.animatePosition(from: CGPoint(), to: CGPoint(x: -100.0, y: -70.0), duration: duration, removeOnCompletion: false, additive: true)
            
            self.proceedNode.layer.animatePosition(from: self.proceedNode.position, to: buttonFrame.center, duration: duration, removeOnCompletion: false)
        }
        
        func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
            let hadLayout = self.validLayout != nil
            self.validLayout = layout
            
            let sideInset: CGFloat = 8.0
            let innerInset: CGFloat = 18.0
            
            let maximumWidth: CGFloat = min(430.0, layout.size.width)
            
            transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(x: -layout.size.width, y: 0.0), size: CGSize(width: layout.size.width * 3.0, height: layout.size.height)))
            
            let backgroundSize = CGSize(width: maximumWidth - sideInset * 2.0, height: 243.0)
            
            let originY: CGFloat
            if case .regular = layout.metrics.widthClass {
                originY = floorToScreenPixels((layout.size.height - backgroundSize.height) / 2.0)
            } else {
                let hasOnScreenNavigation = layout.deviceMetrics.onScreenNavigationHeight(inLandscape: false, systemOnScreenNavigationHeight: nil) != nil
                if hasOnScreenNavigation || layout.deviceMetrics.hasTopNotch || layout.deviceMetrics.hasDynamicIsland {
                    originY = layout.size.height - backgroundSize.height - 260.0
                } else {
                    originY = floorToScreenPixels((layout.size.height - backgroundSize.height) / 2.0)
                }
            }
            
            let backgroundFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((layout.size.width - backgroundSize.width) / 2.0), y: originY), size: backgroundSize)
            transition.updateFrame(node: self.backgroundNode, frame: backgroundFrame)
              
            let maxWidth = layout.size.width - 20.0
            if !hadLayout {
                var fontSize = 34.0
                if layout.size.width < 375.0 {
                    fontSize = 30.0
                }
              
                self.measureTargetNode.attributedText = NSAttributedString(string: self.code + " " + self.number, font: Font.with(size: fontSize, design: .regular, weight: .bold, traits: [.monospacedNumbers]), textColor: self.theme.list.itemPrimaryTextColor)
                let measuredSize = self.measureTargetNode.updateLayout(CGSize(width: 1000.0, height: .greatestFiniteMagnitude))
                if measuredSize.width > maxWidth {
                    fontSize = floor(0.8 * fontSize)
                }
                
                let largeFont = Font.with(size: fontSize, design: .regular, weight: .bold, traits: [.monospacedNumbers])
                
                self.codeTargetNode.attributedText = NSAttributedString(string: self.code, font: largeFont, textColor: self.theme.list.itemPrimaryTextColor)
                let targetString = NSMutableAttributedString(string: self.number, font: largeFont, textColor: self.theme.list.itemPrimaryTextColor)
                targetString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: targetString.length))
                self.phoneTargetNode.attributedText = targetString
            }
            
            let spacing: CGFloat = 10.0
            
            let codeSize = self.codeTargetNode.updateLayout(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            let numberSize = self.phoneTargetNode.updateLayout(CGSize(width: maxWidth - codeSize.width - spacing, height: .greatestFiniteMagnitude))
            
            let totalWidth = codeSize.width + numberSize.width + spacing
            
            let codeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - totalWidth) / 2.0), y: 30.0), size: codeSize)
            transition.updateFrame(node: self.codeTargetNode, frame: codeFrame.offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let numberFrame = CGRect(origin: CGPoint(x: codeFrame.maxX + spacing, y: 30.0), size: numberSize)
            transition.updateFrame(node: self.phoneTargetNode, frame: numberFrame.offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let textSize = self.textNode.updateLayout(backgroundSize)
            transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - textSize.width) / 2.0), y: 88.0), size: textSize).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            self.textActivateAreaNode.frame = self.textNode.frame
            self.textActivateAreaNode.accessibilityLabel = "\(self.code) \(self.number). \(self.strings.Login_PhoneNumberConfirmation)"
            
            let proceedWidth = backgroundSize.width - innerInset * 2.0
            let proceedHeight = self.proceedNode.updateLayout(width: proceedWidth, transition: transition)
            transition.updateFrame(node: self.proceedNode, frame: CGRect(origin: CGPoint(x: innerInset, y: backgroundSize.height - proceedHeight - innerInset), size: CGSize(width: proceedWidth, height: proceedHeight)).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let cancelSize = self.cancelButton.measure(layout.size)
            transition.updateFrame(node: self.cancelButton, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - cancelSize.width) / 2.0), y: backgroundSize.height - proceedHeight - innerInset - cancelSize.height - 25.0), size: cancelSize).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
        }
    }
    

    final class FixedPhoneConfirmationNode: ASDisplayNode {
        private let theme: PresentationTheme
        private let strings: PresentationStrings
        
        private let code: String
        private let number: String
        
        private let dimNode: ASDisplayNode
        private let backgroundNode: ASDisplayNode
        
        private let codeSourceNode: ImmediateTextNode
        private let phoneSourceNode: ImmediateTextNode
        
        private let codeTargetNode: ImmediateTextNode
        private let phoneTargetNode: ImmediateTextNode
        private let measureTargetNode: ImmediateTextNode
        
        private let textNode: ImmediateTextNode
        private let textActivateAreaNode: AccessibilityAreaNode
        
        private let cancelButton: HighlightableButtonNode
        fileprivate let proceedNode: SolidRoundedButtonNode
        
        var proceed: () -> Void = {}
        var cancel: () -> Void = {}
        
        private var validLayout: ContainerViewLayout?
        
        init(theme: PresentationTheme, strings: PresentationStrings, code: String, number: String) {
            self.theme = theme
            self.strings = strings
            
            self.code = code
            self.number = number
            
            self.dimNode = ASDisplayNode()
            self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
            
            self.backgroundNode = ASDisplayNode()
            self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
            self.backgroundNode.cornerRadius = 42.0
            
            self.textNode = ImmediateTextNode()
            self.textNode.displaysAsynchronously = false
            self.textNode.attributedText = NSAttributedString(string: strings.Login_PhoneNumberConfirmation, font: Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor)
            self.textNode.textAlignment = .center
            
            self.textActivateAreaNode = AccessibilityAreaNode()
            self.textActivateAreaNode.accessibilityTraits = .staticText
            
            self.cancelButton = HighlightableButtonNode()
            self.cancelButton.setTitle(strings.Login_Edit, with: Font.regular(19.0), with: theme.list.itemAccentColor, for: .normal)
            self.cancelButton.accessibilityTraits = [.button]
            self.cancelButton.accessibilityLabel = strings.Login_Edit
            
            self.proceedNode = SolidRoundedButtonNode(title: strings.Login_Continue, theme: SolidRoundedButtonTheme(theme: theme), glass: false, height: 50.0, cornerRadius: 50.0 * 0.5)
            self.proceedNode.progressType = .embedded
            self.proceedNode.accessibilityIdentifier = "Auth.PhoneConfirm.ContinueButton"

            let font = Font.with(size: 20.0, design: .regular, traits: [.monospacedNumbers])
            let largeFont = Font.with(size: 34.0, design: .regular, weight: .bold, traits: [.monospacedNumbers])
            
            self.codeSourceNode = ImmediateTextNode()
            self.codeSourceNode.alpha = 0.0
            self.codeSourceNode.displaysAsynchronously = false
            self.codeSourceNode.attributedText = NSAttributedString(string: code, font: font, textColor: theme.list.itemPrimaryTextColor)
            
            self.phoneSourceNode = ImmediateTextNode()
            self.phoneSourceNode.alpha = 0.0
            self.phoneSourceNode.displaysAsynchronously = false
            
            let sourceString = NSMutableAttributedString(string: number, font: font, textColor: theme.list.itemPrimaryTextColor)
            sourceString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: sourceString.length))
            self.phoneSourceNode.attributedText = sourceString
            
            self.codeTargetNode = ImmediateTextNode()
            self.codeTargetNode.displaysAsynchronously = false
            self.codeTargetNode.attributedText = NSAttributedString(string: code, font: largeFont, textColor: theme.list.itemPrimaryTextColor)
            
            self.phoneTargetNode = ImmediateTextNode()
            self.phoneTargetNode.displaysAsynchronously = false
            
            self.measureTargetNode = ImmediateTextNode()
            self.measureTargetNode.displaysAsynchronously = false
            self.measureTargetNode.maximumNumberOfLines = 1
            
            let targetString = NSMutableAttributedString(string: number, font: largeFont, textColor: theme.list.itemPrimaryTextColor)
            targetString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: sourceString.length))
            self.phoneTargetNode.attributedText = targetString
            
            super.init()
            
            self.clipsToBounds = false
            
            self.addSubnode(self.dimNode)
            self.addSubnode(self.backgroundNode)
            
            self.addSubnode(self.codeSourceNode)
            self.addSubnode(self.phoneSourceNode)
            
            self.addSubnode(self.codeTargetNode)
            self.addSubnode(self.phoneTargetNode)
            
            self.addSubnode(self.textNode)
            self.addSubnode(self.textActivateAreaNode)
            
            self.addSubnode(self.cancelButton)
            self.addSubnode(self.proceedNode)
            
            self.cancelButton.addTarget(self, action: #selector(self.cancelPressed), forControlEvents: .touchUpInside)
            self.proceedNode.pressed = { [weak self] in
                self?.proceed()
            }
        }
        
        override func didLoad() {
            super.didLoad()
            
            self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        }
        
        @objc private func dimTapped() {
            self.cancelPressed()
        }
        
        @objc private func cancelPressed() {
            self.dimNode.isUserInteractionEnabled = false
            self.cancel()
        }
        
        func animateIn(codeNode: ASDisplayNode, numberNode: ASDisplayNode, buttonNode: ASDisplayNode) {
            guard let layout = self.validLayout else {
                return
            }
            let codeFrame = codeNode.convert(codeNode.bounds, to: nil)
            let numberFrame = numberNode.convert(numberNode.bounds, to: nil)
            let buttonFrame = buttonNode.convert(buttonNode.bounds, to: nil)
            
            codeNode.isHidden = true
            numberNode.isHidden = true
            buttonNode.isHidden = true
            
            self.dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            
            let duration: Double = 0.25
            
            let codeSize = self.codeSourceNode.updateLayout(layout.size)
            self.codeSourceNode.frame = CGRect(origin: CGPoint(x: codeFrame.midX - codeSize.width / 2.0, y: codeFrame.midY - codeSize.height / 2.0), size: codeSize)
            
            let numberSize = self.phoneSourceNode.updateLayout(layout.size)
            self.phoneSourceNode.frame = CGRect(origin: CGPoint(x: numberFrame.minX, y: numberFrame.midY - numberSize.height / 2.0), size: numberSize)
            
            let targetScale = codeSize.height / self.codeTargetNode.frame.height
            let sourceScale = self.codeTargetNode.frame.height / codeSize.height
            
            self.codeSourceNode.layer.animateScale(from: 1.0, to: sourceScale, duration: duration)
            self.codeSourceNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration)
            self.codeSourceNode.layer.animatePosition(from: self.codeSourceNode.position, to: self.codeTargetNode.position, duration: duration)
            
            self.phoneSourceNode.layer.animateScale(from: 1.0, to: sourceScale, duration: duration)
            self.phoneSourceNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration)
            self.phoneSourceNode.layer.animatePosition(from: self.phoneSourceNode.position, to: self.phoneTargetNode.position, duration: duration)
            
            self.codeTargetNode.layer.animateScale(from: targetScale, to: 1.0, duration: duration)
            self.codeTargetNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.codeTargetNode.layer.animatePosition(from: self.codeSourceNode.position, to: self.codeTargetNode.position, duration: duration)
            
            self.phoneTargetNode.layer.animateScale(from: targetScale, to: 1.0, duration: duration)
            self.phoneTargetNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.phoneTargetNode.layer.animatePosition(from: self.phoneSourceNode.position, to: self.phoneTargetNode.position, duration: duration)
            
            self.backgroundNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
            
            self.backgroundNode.layer.animateFrame(from: CGRect(origin: CGPoint(x: self.backgroundNode.frame.origin.x + 6.0, y: codeFrame.minY), size: CGSize(width: self.backgroundNode.frame.width - 12.0, height: buttonFrame.maxY + 18.0 - codeFrame.minY)), to: self.backgroundNode.frame, duration: duration)
            
            self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.textNode.layer.animateScale(from: 0.5, to: 1.0, duration: duration)
            self.textNode.layer.animatePosition(from: CGPoint(x: -100.0, y: -45.0), to: CGPoint(), duration: duration, additive: true)
            
            self.cancelButton.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.cancelButton.layer.animateScale(from: 0.5, to: 1.0, duration: duration)
            self.cancelButton.layer.animatePosition(from: CGPoint(x: -100.0, y: -70.0), to: CGPoint(), duration: duration, additive: true)
            
            self.proceedNode.layer.animatePosition(from: buttonFrame.center, to: self.proceedNode.position, duration: duration)
        }
        
        func animateOut(codeNode: ASDisplayNode, numberNode: ASDisplayNode, buttonNode: ASDisplayNode, completion: @escaping () -> Void) {
            let codeFrame = codeNode.convert(codeNode.bounds, to: nil)
            let numberFrame = numberNode.convert(numberNode.bounds, to: nil)
            let buttonFrame = buttonNode.convert(buttonNode.bounds, to: nil)
            
            self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            
            let duration: Double = 0.25
            
            let codeSize = self.codeSourceNode.updateLayout(self.frame.size)
            self.codeSourceNode.frame = CGRect(origin: CGPoint(x: codeFrame.midX - codeSize.width / 2.0, y: codeFrame.midY - codeSize.height / 2.0), size: codeSize)
            
            let numberSize = self.phoneSourceNode.updateLayout(self.frame.size)
            self.phoneSourceNode.frame = CGRect(origin: CGPoint(x: numberFrame.minX, y: numberFrame.midY - numberSize.height / 2.0), size: numberSize)
            
            let targetScale = codeSize.height / self.codeTargetNode.frame.height
            let sourceScale = self.codeTargetNode.frame.height / codeSize.height
            
            self.codeSourceNode.layer.animateScale(from: sourceScale, to: 1.0, duration: duration)
            self.codeSourceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.codeSourceNode.layer.animatePosition(from: self.codeTargetNode.position, to: self.codeSourceNode.position, duration: duration)
            
            self.phoneSourceNode.layer.animateScale(from: sourceScale, to: 1.0, duration: duration)
            self.phoneSourceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
            self.phoneSourceNode.layer.animatePosition(from: self.phoneTargetNode.position, to: self.phoneSourceNode.position, duration: duration)
            
            self.codeTargetNode.layer.animateScale(from: 1.0, to: targetScale, duration: duration)
            self.codeTargetNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
            self.codeTargetNode.layer.animatePosition(from: self.codeTargetNode.position, to: self.codeSourceNode.position, duration: duration)
            
            Queue.mainQueue().after(0.2) {
                codeNode.isHidden = false
                numberNode.isHidden = false
                buttonNode.isHidden = false
            }
            
            self.phoneTargetNode.layer.animateScale(from: 1.0, to: targetScale, duration: duration)
            self.phoneTargetNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false, completion: { _ in
                completion()
            })
            self.phoneTargetNode.layer.animatePosition(from: self.phoneTargetNode.position, to: self.phoneSourceNode.position, duration: duration)
            
            self.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, delay: 0.1, removeOnCompletion: false)
            self.backgroundNode.layer.animateFrame(from: self.backgroundNode.frame, to: CGRect(origin: CGPoint(x: self.backgroundNode.frame.origin.x + 6.0, y: codeFrame.minY), size: CGSize(width: self.backgroundNode.frame.width - 12.0, height: buttonFrame.maxY + 18.0 - codeFrame.minY)), duration: duration)
                        
            self.textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.textNode.layer.animateScale(from: 1.0, to: 0.5, duration: duration, removeOnCompletion: false)
            self.textNode.layer.animatePosition(from: CGPoint(), to: CGPoint(x: -100.0, y: -45.0), duration: duration, removeOnCompletion: false, additive: true)
            
            self.cancelButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.cancelButton.layer.animateScale(from: 1.0, to: 0.5, duration: duration, removeOnCompletion: false)
            self.cancelButton.layer.animatePosition(from: CGPoint(), to: CGPoint(x: -100.0, y: -70.0), duration: duration, removeOnCompletion: false, additive: true)
            
            self.proceedNode.layer.animatePosition(from: self.proceedNode.position, to: buttonFrame.center, duration: duration, removeOnCompletion: false)
        }
        
        func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
            let hadLayout = self.validLayout != nil
            self.validLayout = layout
            
            let sideInset: CGFloat = 8.0
            let innerInset: CGFloat = 18.0
            
            let maximumWidth: CGFloat = min(430.0, layout.size.width)
            
            transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(x: -layout.size.width, y: 0.0), size: CGSize(width: layout.size.width * 3.0, height: layout.size.height)))
            
            let backgroundSize = CGSize(width: maximumWidth - sideInset * 2.0, height: 243.0)
            let insets = layout.insets(options: [.statusBar, .input])
            let availableTop = insets.top + 8.0
            let availableBottom = layout.size.height - max(insets.bottom, layout.safeInsets.bottom) - 12.0
            let originY: CGFloat
            if case .regular = layout.metrics.widthClass {
                originY = max(availableTop, floorToScreenPixels((availableTop + availableBottom - backgroundSize.height) / 2.0))
            } else {
                originY = max(availableTop, availableBottom - backgroundSize.height)
            }
            
            let backgroundFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((layout.size.width - backgroundSize.width) / 2.0), y: originY), size: backgroundSize)
            transition.updateFrame(node: self.backgroundNode, frame: backgroundFrame)
              
            let maxWidth = layout.size.width - 20.0
            if !hadLayout {
                var fontSize = 34.0
                if layout.size.width < 375.0 {
                    fontSize = 30.0
                }
              
                self.measureTargetNode.attributedText = NSAttributedString(string: self.code + " " + self.number, font: Font.with(size: fontSize, design: .regular, weight: .bold, traits: [.monospacedNumbers]), textColor: self.theme.list.itemPrimaryTextColor)
                let measuredSize = self.measureTargetNode.updateLayout(CGSize(width: 1000.0, height: .greatestFiniteMagnitude))
                if measuredSize.width > maxWidth {
                    fontSize = floor(0.8 * fontSize)
                }
                
                let largeFont = Font.with(size: fontSize, design: .regular, weight: .bold, traits: [.monospacedNumbers])
                
                self.codeTargetNode.attributedText = NSAttributedString(string: self.code, font: largeFont, textColor: self.theme.list.itemPrimaryTextColor)
                let targetString = NSMutableAttributedString(string: self.number, font: largeFont, textColor: self.theme.list.itemPrimaryTextColor)
                targetString.addAttribute(NSAttributedString.Key.kern, value: 1.6, range: NSRange(location: 0, length: targetString.length))
                self.phoneTargetNode.attributedText = targetString
            }
            
            let spacing: CGFloat = 10.0
            
            let codeSize = self.codeTargetNode.updateLayout(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            let numberSize = self.phoneTargetNode.updateLayout(CGSize(width: maxWidth - codeSize.width - spacing, height: .greatestFiniteMagnitude))
            
            let totalWidth = codeSize.width + numberSize.width + spacing
            
            let codeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - totalWidth) / 2.0), y: 30.0), size: codeSize)
            transition.updateFrame(node: self.codeTargetNode, frame: codeFrame.offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let numberFrame = CGRect(origin: CGPoint(x: codeFrame.maxX + spacing, y: 30.0), size: numberSize)
            transition.updateFrame(node: self.phoneTargetNode, frame: numberFrame.offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let textSize = self.textNode.updateLayout(backgroundSize)
            transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - textSize.width) / 2.0), y: 88.0), size: textSize).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            self.textActivateAreaNode.frame = self.textNode.frame
            self.textActivateAreaNode.accessibilityLabel = "\(self.code) \(self.number). \(self.strings.Login_PhoneNumberConfirmation)"
            
            let proceedWidth = backgroundSize.width - innerInset * 2.0
            let proceedHeight = self.proceedNode.updateLayout(width: proceedWidth, transition: transition)
            transition.updateFrame(node: self.proceedNode, frame: CGRect(origin: CGPoint(x: innerInset, y: backgroundSize.height - proceedHeight - innerInset), size: CGSize(width: proceedWidth, height: proceedHeight)).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
            
            let cancelSize = self.cancelButton.measure(layout.size)
            transition.updateFrame(node: self.cancelButton, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundSize.width - cancelSize.width) / 2.0), y: backgroundSize.height - proceedHeight - innerInset - cancelSize.height - 25.0), size: cancelSize).offsetBy(dx: backgroundFrame.minX, dy: backgroundFrame.minY))
        }
    }
    
