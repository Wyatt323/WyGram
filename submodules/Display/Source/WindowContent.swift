import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import SGSimpleSettings

private struct WindowLayout: Equatable {
    let size: CGSize
    let metrics: LayoutMetrics
    let statusBarHeight: CGFloat?
    let forceInCallStatusBarText: String?
    let inputHeight: CGFloat?
    let safeInsets: UIEdgeInsets
    let onScreenNavigationHeight: CGFloat?
    let upperKeyboardInputPositionBound: CGFloat?
    let inVoiceOver: Bool
}

private struct UpdatingLayout {
    var layout: WindowLayout
    var transition: ContainedViewLayoutTransition
    
    mutating func update(transition: ContainedViewLayoutTransition, override: Bool) {
        var update = false
        if case .immediate = self.transition {
            update = true
        } else if override {
            update = true
        }
        if update {
            self.transition = transition
        }
    }
    
    mutating func update(size: CGSize, metrics: LayoutMetrics, safeInsets: UIEdgeInsets, forceInCallStatusBarText: String?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: size, metrics: metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    
    mutating func update(forceInCallStatusBarText: String?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: self.layout.safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    mutating func update(statusBarHeight: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: statusBarHeight, forceInCallStatusBarText: self.layout.forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: self.layout.safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    mutating func update(inputHeight: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: self.layout.forceInCallStatusBarText, inputHeight: inputHeight, safeInsets: self.layout.safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    mutating func update(safeInsets: UIEdgeInsets, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: self.layout.forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    mutating func update(onScreenNavigationHeight: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: self.layout.forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: self.layout.safeInsets, onScreenNavigationHeight: onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    mutating func update(upperKeyboardInputPositionBound: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.update(transition: transition, override: overrideTransition)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: self.layout.forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: self.layout.safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: upperKeyboardInputPositionBound, inVoiceOver: self.layout.inVoiceOver)
    }
    
    mutating func update(inVoiceOver: Bool) {
        self.update(transition: transition, override: false)
        
        self.layout = WindowLayout(size: self.layout.size, metrics: self.layout.metrics, statusBarHeight: self.layout.statusBarHeight, forceInCallStatusBarText: self.layout.forceInCallStatusBarText, inputHeight: self.layout.inputHeight, safeInsets: self.layout.safeInsets, onScreenNavigationHeight: self.layout.onScreenNavigationHeight, upperKeyboardInputPositionBound: self.layout.upperKeyboardInputPositionBound, inVoiceOver: inVoiceOver)
    }
}

private let defaultStatusBarHeight: CGFloat = 20.0
private let statusBarHiddenInLandscape: Bool = UIDevice.current.userInterfaceIdiom == .phone

private func inputHeightOffsetForLayout(_ layout: WindowLayout) -> CGFloat {
    if let inputHeight = layout.inputHeight, let upperBound = layout.upperKeyboardInputPositionBound {
        return max(0.0, upperBound - (layout.size.height - inputHeight))
    }
    return 0.0
}

private func containedLayoutForWindowLayout(_ layout: WindowLayout, deviceMetrics: DeviceMetrics) -> ContainerViewLayout {
    let resolvedStatusBarHeight: CGFloat?
    if let statusBarHeight = layout.statusBarHeight {
        if layout.forceInCallStatusBarText != nil {
            resolvedStatusBarHeight = max(40.0, layout.safeInsets.top)
        } else {
            resolvedStatusBarHeight = statusBarHeight
        }
    } else {
        resolvedStatusBarHeight = nil
    }
    
    var updatedInputHeight = layout.inputHeight
    if let inputHeight = updatedInputHeight, let _ = layout.upperKeyboardInputPositionBound {
        updatedInputHeight = inputHeight - inputHeightOffsetForLayout(layout)
    }
    
    let isLandscape = layout.size.width > layout.size.height
    var resolvedSafeInsets = layout.safeInsets
    if layout.safeInsets.left.isZero {
        resolvedSafeInsets = deviceMetrics.safeInsets(inLandscape: isLandscape)
    }
    
    return ContainerViewLayout(size: layout.size, metrics: layout.metrics, deviceMetrics: deviceMetrics, intrinsicInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: layout.onScreenNavigationHeight ?? 0.0, right: 0.0), safeInsets: resolvedSafeInsets, additionalInsets: UIEdgeInsets(), statusBarHeight: resolvedStatusBarHeight, inputHeight: updatedInputHeight, inputHeightIsInteractivellyChanging: layout.upperKeyboardInputPositionBound != nil && layout.upperKeyboardInputPositionBound != layout.size.height && layout.inputHeight != nil, inVoiceOver: layout.inVoiceOver)
}

public func doesViewTreeDisableInteractiveTransitionGestureRecognizer(_ view: UIView, keyboardOnly: Bool = false) -> Bool {
    if view.disablesInteractiveTransitionGestureRecognizer && !keyboardOnly {
        return true
    }
    if view.disablesInteractiveKeyboardGestureRecognizer {
        return true
    }
    if let f = view.disablesInteractiveTransitionGestureRecognizerNow, f() {
        return true
    }
    if let superview = view.superview {
        return doesViewTreeDisableInteractiveTransitionGestureRecognizer(superview, keyboardOnly: keyboardOnly)
    }
    return false
}

public func getFirstResponderAndAccessoryHeight(_ view: UIView, _ accessoryHeight: CGFloat? = nil) -> (UIView?, CGFloat?) {
    if view.isFirstResponder {
        return (view, accessoryHeight)
    } else {
        var updatedAccessoryHeight = accessoryHeight
        if let view = view as? WindowInputAccessoryHeightProvider {
            updatedAccessoryHeight = view.getWindowInputAccessoryHeight()
        }
        for subview in view.subviews {
            let (result, resultHeight) = getFirstResponderAndAccessoryHeight(subview, updatedAccessoryHeight)
            if let result = result {
                return (result, resultHeight)
            }
        }
        return (nil, nil)
    }
}

public final class WindowHostView {
    public let containerView: UIView
    public let eventView: UIView
    public let isRotating: () -> Bool
    public let systemUserInterfaceStyle: Signal<WindowUserInterfaceStyle, NoError>
    public let currentInterfaceOrientation: () -> UIInterfaceOrientation
    
    let updateSupportedInterfaceOrientations: (UIInterfaceOrientationMask) -> Void
    let updateDeferScreenEdgeGestures: (UIRectEdge) -> Void
    let updatePrefersOnScreenNavigationHidden: (Bool) -> Void
    let updateStatusBar: (UIStatusBarStyle, Bool, ContainedViewLayoutTransition) -> Void
    
    var present: ((ContainableController, PresentationSurfaceLevel, Bool, @escaping () -> Void) -> Void)?
    var presentInGlobalOverlay: ((_ controller: ContainableController) -> Void)?
    var addGlobalPortalHostViewImpl: ((PortalSourceView) -> Void)?
    var presentNative: ((UIViewController) -> Void)?
    var nativeController: (() -> UIViewController?)?
    var updateSize: ((CGSize, Double, UIInterfaceOrientation) -> Void)?
    var layoutSubviews: (() -> Void)?
    var keyboardHeightUpdated: ((CGFloat) -> Void)?
    var updateToInterfaceOrientation: ((UIInterfaceOrientation) -> Void)?
    var isUpdatingOrientationLayout = false
    var hitTest: ((CGPoint, UIEvent?) -> UIView?)?
    var invalidateDeferScreenEdgeGesture: (() -> Void)?
    var invalidatePrefersOnScreenNavigationHidden: (() -> Void)?
    var invalidateSupportedOrientations: (() -> Void)?
    var cancelInteractiveKeyboardGestures: (() -> Void)?
    var forEachController: (((ContainableController) -> Void) -> Void)?
    var getAccessibilityElements: (() -> [Any]?)?
    
    init(containerView: UIView, eventView: UIView, isRotating: @escaping () -> Bool, systemUserInterfaceStyle: Signal<WindowUserInterfaceStyle, NoError>, currentInterfaceOrientation: @escaping () -> UIInterfaceOrientation, updateSupportedInterfaceOrientations: @escaping (UIInterfaceOrientationMask) -> Void, updateDeferScreenEdgeGestures: @escaping (UIRectEdge) -> Void, updatePrefersOnScreenNavigationHidden: @escaping (Bool) -> Void, updateStatusBar: @escaping (UIStatusBarStyle, Bool, ContainedViewLayoutTransition) -> Void) {
        self.containerView = containerView
        self.eventView = eventView
        self.isRotating = isRotating
        self.systemUserInterfaceStyle = systemUserInterfaceStyle
        self.currentInterfaceOrientation = currentInterfaceOrientation
        self.updateSupportedInterfaceOrientations = updateSupportedInterfaceOrientations
        self.updateDeferScreenEdgeGestures = updateDeferScreenEdgeGestures
        self.updatePrefersOnScreenNavigationHidden = updatePrefersOnScreenNavigationHidden
        self.updateStatusBar = updateStatusBar
    }
    
    fileprivate var onScreenNavigationHeight: CGFloat? {
        return self.eventView.safeAreaInsets.bottom.isLessThanOrEqualTo(0.0) ? nil : self.eventView.safeAreaInsets.bottom
    }
}

public protocol WindowHost {
    func forEachController(_ f: (ContainableController) -> Void)
    func present(_ controller: ContainableController, on level: PresentationSurfaceLevel, blockInteraction: Bool, completion: @escaping () -> Void)
    func presentInGlobalOverlay(_ controller: ContainableController)
    func addGlobalPortalHostView(sourceView: PortalSourceView)
    func invalidateDeferScreenEdgeGestures()
    func invalidatePrefersOnScreenNavigationHidden()
    func invalidateSupportedOrientations()
    func cancelInteractiveKeyboardGestures()
}

public extension UIView {
    var windowHost: WindowHost? {
        if let window = self.window as? WindowHost {
            return window
        } else if let result = findWindow(self) {
            return result
        } else {
            return nil
        }
    }
    
    func findFirstResponder() -> UIView? {
        if self.isFirstResponder {
            return self
        }
        for subview in self.subviews {
            if let result = subview.findFirstResponder() {
                return result
            }
        }
        return nil
    }
}

private func layoutMetricsForScreenSize(size: CGSize, orientation: UIInterfaceOrientation?) -> LayoutMetrics {
    if size.width > 690.0 && size.height > 650.0 {
        return LayoutMetrics(widthClass: .regular, heightClass: .regular, orientation: orientation)
    } else {
        return LayoutMetrics(widthClass: .compact, heightClass: .compact, orientation: orientation)
    }
}

public final class WindowKeyboardGestureRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = gestureRecognizer.view {
            let location = touch.location(in: gestureRecognizer.view)
            if location.y > view.bounds.height - 44.0 {
                return false
            }
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

public class Window1 {
    public let hostView: WindowHostView
    public let badgeView: UIImageView
    
    private(set) var deviceMetrics: DeviceMetrics
    
    public let statusBarHost: StatusBarHost?
    private let keyboardManager: KeyboardManager?
    private let keyboardViewManager: KeyboardViewManager?
    private var statusBarChangeObserver: AnyObject?
    private var keyboardRotationChangeObserver: AnyObject?
    private var keyboardFrameChangeObserver: AnyObject?
    private var keyboardFrameDidChangeObserver: AnyObject?
    private var keyboardWillHideObserver: AnyObject?
    private var keyboardTypeChangeObserver: AnyObject?
    private var voiceOverStatusObserver: AnyObject?
    
    private var windowLayout: WindowLayout
    private var updatingLayout: UpdatingLayout?
    private var updatedContainerLayout: ContainerViewLayout?
    private var upperKeyboardInputPositionBound: CGFloat?
    
    private let presentationContext: PresentationContext
    private let overlayPresentationContext: GlobalOverlayPresentationContext
    private let topPresentationContext: PresentationContext
    
    private var tracingStatusBarsInvalidated = false
    private var shouldUpdateDeferScreenEdgeGestures = false
    private var shouldInvalidatePrefersOnScreenNavigationHidden = false
    private var shouldInvalidateSupportedOrientations = false
    
    private var statusBarHidden = false
        
    private var shouldNotAnimateLikelyKeyboardAutocorrectionSwitch: Bool = false
    
    public private(set) var forceInCallStatusBarText: String? = nil
    public var inCallNavigate: (() -> Void)?

    private var debugTapCounter: (Double, Int) = (0.0, 0)
    private var debugTapRecognizer: UITapGestureRecognizer?
    public var debugAction: (() -> Void)? {
        didSet {
            if self.debugAction != nil {
                if self.debugTapRecognizer == nil {
                    let debugTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.debugTapGesture(_:)))
                    self.debugTapRecognizer = debugTapRecognizer
                    self.hostView.containerView.addGestureRecognizer(debugTapRecognizer)
                }
            } else if let debugTapRecognizer = self.debugTapRecognizer {
                self.debugTapRecognizer = nil
                self.hostView.containerView.removeGestureRecognizer(debugTapRecognizer)
            }
        }
    }
    @objc private func debugTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            let timestamp = CACurrentMediaTime()
            if self.debugTapCounter.0 < timestamp - 0.4 {
                self.debugTapCounter.0 = timestamp
                self.debugTapCounter.1 = 0
            }

            if self.debugTapCounter.0 >= timestamp - 0.4 {
                self.debugTapCounter.0 = timestamp
                self.debugTapCounter.1 += 1
            }

            if self.debugTapCounter.1 >= 10 {
                self.debugTapCounter.1 = 0

                self.debugAction?()
            }
        }
    }
    
    public let systemUserInterfaceStyle: Signal<WindowUserInterfaceStyle, NoError>
    
    private var windowPanRecognizer: WindowPanRecognizer?
    private let keyboardGestureRecognizerDelegate = WindowKeyboardGestureRecognizerDelegate()
    private var keyboardGestureBeginLocation: CGPoint?
    private var keyboardGestureAccessoryHeight: CGFloat?
    
    private var keyboardTypeChangeTimer: SwiftSignalKit.Timer?
    
    private var isInteractionBlocked = false
    
    public init(hostView: WindowHostView, statusBarHost: StatusBarHost?) {
        self.hostView = hostView
        self.badgeView = UIImageView()
        self.badgeView.image = UIImage(bundleImageName: "Components/AppBadge")
        self.badgeView.isHidden = true
        
        self.systemUserInterfaceStyle = hostView.systemUserInterfaceStyle
        
        let boundsSize = self.hostView.eventView.bounds.size
        self.deviceMetrics = DeviceMetrics(screenSize: UIScreen.main.bounds.size, scale: UIScreen.main.scale, statusBarHeight: statusBarHost?.statusBarFrame.height ?? 0.0, onScreenNavigationHeight: self.hostView.onScreenNavigationHeight)
        
        self.statusBarHost = statusBarHost
        let statusBarHeight: CGFloat
        if let statusBarHost = statusBarHost {
            statusBarHeight = statusBarHost.statusBarFrame.size.height
            self.keyboardManager = KeyboardManager(host: statusBarHost)
            self.keyboardViewManager = KeyboardViewManager(host: statusBarHost)
        } else {
            statusBarHeight = 0.0
            self.keyboardManager = nil
            self.keyboardViewManager = nil
        }
        
        let isLandscape = boundsSize.width > boundsSize.height
        let safeInsets = self.deviceMetrics.safeInsets(inLandscape: isLandscape)
        let onScreenNavigationHeight = self.deviceMetrics.onScreenNavigationHeight(inLandscape: isLandscape, systemOnScreenNavigationHeight: self.hostView.onScreenNavigationHeight)
        
        let orientation: UIInterfaceOrientation = self.hostView.currentInterfaceOrientation()
        
        self.windowLayout = WindowLayout(size: boundsSize, metrics: layoutMetricsForScreenSize(size: boundsSize, orientation: orientation), statusBarHeight: statusBarHeight, forceInCallStatusBarText: self.forceInCallStatusBarText, inputHeight: 0.0, safeInsets: safeInsets, onScreenNavigationHeight: onScreenNavigationHeight, upperKeyboardInputPositionBound: nil, inVoiceOver: UIAccessibility.isVoiceOverRunning)
        self.updatingLayout = UpdatingLayout(layout: self.windowLayout, transition: .immediate)
        self.presentationContext = PresentationContext()
        self.overlayPresentationContext = GlobalOverlayPresentationContext(statusBarHost: statusBarHost, parentView: self.hostView.containerView)
        self.topPresentationContext = PresentationContext()
        
        self.presentationContext.topLevelSubview = { [weak self] in
            guard let strongSelf = self else {
                return nil
            }
            if let first = strongSelf.topPresentationContext.controllers.first {
                return first.0.displayNode.view
            }
            if let first = strongSelf._topLevelOverlayControllers.first {
                return first.view
            }
            return nil
        }
        
        self.presentationContext.updateIsInteractionBlocked = { [weak self] value in
            self?.isInteractionBlocked = value
        }
        self.presentationContext.updateStatusBar = { [weak self] transition in
            self?.updateStatusBar(transition: transition)
        }
        
        let updateOpaqueOverlays: () -> Void = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf._rootController?.displayNode.accessibilityElementsHidden = strongSelf.presentationContext.hasOpaqueOverlay || strongSelf.topPresentationContext.hasOpaqueOverlay
        }
        self.presentationContext.updateHasOpaqueOverlay = { value in
            updateOpaqueOverlays()
        }
        self.topPresentationContext.updateHasOpaqueOverlay = { value in
            updateOpaqueOverlays()
        }
        self.topPresentationContext.updateStatusBar = { [weak self] transition in
            self?.updateStatusBar(transition: transition)
        }
        
        self.hostView.present = { [weak self] controller, level, blockInteraction, completion in
            self?.present(controller, on: level, blockInteraction: blockInteraction, completion: completion)
        }
        
        self.hostView.presentInGlobalOverlay = { [weak self] controller in
            self?.presentInGlobalOverlay(controller)
        }
        
        self.hostView.addGlobalPortalHostViewImpl = { [weak self] sourceView in
            self?.addGlobalPortalHostView(sourceView: sourceView)
        }
        
        self.hostView.presentNative = { [weak self] controller in
            self?.presentNative(controller)
        }
        
        self.hostView.updateSize = { [weak self] size, duration, orientation in
            self?.updateSize(size, duration: duration, orientation: orientation)
        }
        
        self.hostView.layoutSubviews = { [weak self] in
            self?.layoutSubviews(force: false)
        }

        self.hostView.keyboardHeightUpdated = { [weak self] height in
            guard let self, self.deviceMetrics.type != .tablet,
                  self.windowLayout.upperKeyboardInputPositionBound == nil,
                  abs((self.windowLayout.inputHeight ?? 0.0) - height) > 0.5 else {
                return
            }
            self.updateLayout { $0.update(inputHeight: height > 0.0 ? height : nil, transition: .immediate, overrideTransition: false) }
        }
        
        self.hostView.updateToInterfaceOrientation = { [weak self] orientation in
            self?.updateToInterfaceOrientation(orientation)
        }
        
        self.hostView.hitTest = { [weak self] point, event in
            return self?.hitTest(point, with: event)
        }
        
        self.hostView.invalidateDeferScreenEdgeGesture = { [weak self] in
            self?.invalidateDeferScreenEdgeGestures()
        }
        
        self.hostView.invalidatePrefersOnScreenNavigationHidden = { [weak self] in
            self?.invalidatePrefersOnScreenNavigationHidden()
        }
        
        self.hostView.invalidateSupportedOrientations = { [weak self] in
            self?.invalidateSupportedOrientations()
        }
        
        self.hostView.cancelInteractiveKeyboardGestures = { [weak self] in
            self?.cancelInteractiveKeyboardGestures()
        }
        
        self.hostView.forEachController = { [weak self] f in
            self?.forEachViewController({ controller in
                f(controller)
                return true
            })
        }
        
        self.presentationContext.view = self.hostView.containerView
        self.topPresentationContext.view = self.hostView.containerView
        self.presentationContext.containerLayoutUpdated(containedLayoutForWindowLayout(self.windowLayout, deviceMetrics: self.deviceMetrics), transition: .immediate)
        self.topPresentationContext.containerLayoutUpdated(containedLayoutForWindowLayout(self.windowLayout, deviceMetrics: self.deviceMetrics), transition: .immediate)
        self.overlayPresentationContext.containerLayoutUpdated(containedLayoutForWindowLayout(self.windowLayout, deviceMetrics: self.deviceMetrics), transition: .immediate)
        
        //TODO:release check old iOS
        /*self.statusBarChangeObserver = NotificationCenter.default.addObserver(forName: UIApplication.willChangeStatusBarFrameNotification, object: nil, queue: OperationQueue.main, using: { [weak self] notification in
            if let strongSelf = self, strongSelf.statusBarHost != nil {
                let statusBarHeight: CGFloat = max(defaultStatusBarHeight, (notification.userInfo?[UIApplication.statusBarFrameUserInfoKey] as? NSValue)?.cgRectValue.height ?? defaultStatusBarHeight)
                
                let transition: ContainedViewLayoutTransition = .animated(duration: 0.35, curve: .easeInOut)
                strongSelf.updateLayout { $0.update(statusBarHeight: statusBarHeight, transition: transition, overrideTransition: false) }
            }
        })*/
        
        self.keyboardRotationChangeObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("UITextEffectsWindowDidRotateNotification"), object: nil, queue: nil, using: { [weak self] notification in
            if let strongSelf = self {
                if !strongSelf.hostView.isUpdatingOrientationLayout {
                    return
                }
                var keyboardHeight = max(0.0, strongSelf.keyboardManager?.getCurrentKeyboardHeight() ?? 0.0)
                if strongSelf.deviceMetrics.type == .tablet, abs(strongSelf.windowLayout.size.height - UIScreen.main.bounds.height) > 41.0 {
                    keyboardHeight = max(0.0, keyboardHeight - 24.0)
                }
                
                //print("rotation keyboardHeight: \(keyboardHeight)")
                
                var duration: Double = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0
                if duration > Double.ulpOfOne {
                    duration = 0.5
                }
                let curve: UInt = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
                
                let transitionCurve: ContainedViewLayoutTransitionCurve
                if curve == 7 {
                    transitionCurve = .spring
                } else {
                    transitionCurve = .easeInOut
                }
                
                strongSelf.updateLayout { $0.update(inputHeight: keyboardHeight.isLessThanOrEqualTo(0.0) ? nil : keyboardHeight, transition: .animated(duration: duration, curve: transitionCurve), overrideTransition: false) }
            }
        })
        
        #if DEBUG && false
        let testView = UIView()
        testView.backgroundColor = .blue
        testView.layer.zPosition = 1000.0
        self.hostView.containerView.addSubview(testView)
        #endif
        let updateKeyboardFrame: (Notification) -> Void = { [weak self] notification in
            guard let self,
                  let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
                return
            }
            if let local = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber, !local.boolValue {
                return
            }
            let eventView = self.hostView.eventView
            guard let window = (eventView as? UIWindow) ?? eventView.window else {
                return
            }
            let screen = (notification.object as? UIScreen) ?? window.screen
            guard screen === window.screen else {
                return
            }
            // The notification is the target frame. A keyboard view still contains
            // the previous frame while showing, hiding or switching input methods.
            let frame = screen.coordinateSpace.convert(value.cgRectValue, to: eventView)
            var height = dockedKeyboardHeight(frame: frame, in: eventView.bounds, safeBottom: eventView.safeAreaInsets.bottom)
            if self.hostView.containerView is ChildWindowHostView, self.deviceMetrics.type != .tablet, height > 0.0 {
                height += 27.0
            }
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0
            let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
            var transition: ContainedViewLayoutTransition = duration > 0.0 ? .animated(duration: duration, curve: curve == 7 ? .spring : .easeInOut) : .immediate
            if notification.name == UIResponder.keyboardDidChangeFrameNotification {
                transition = .immediate
            } else if self.shouldNotAnimateLikelyKeyboardAutocorrectionSwitch, let inputHeight = self.windowLayout.inputHeight, abs(inputHeight - height) <= 44.1 {
                transition = .immediate
            }
            self.updateLayout {
                // A system keyboard can disappear from the legacy view lookup
                // during an input-mode switch. Do not retain its old drag bound.
                if self.keyboardManager?.canControlInteractiveKeyboard != true {
                    $0.update(upperKeyboardInputPositionBound: nil, transition: transition, overrideTransition: false)
                }
                $0.update(inputHeight: height > 0.0 ? height : nil, transition: transition, overrideTransition: false)
            }
        }
        self.keyboardFrameChangeObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main, using: updateKeyboardFrame)
        self.keyboardFrameDidChangeObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main, using: updateKeyboardFrame)
        self.keyboardWillHideObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil, using: { [weak self] notification in
            guard let self else {
                return
            }
            let _ = self
        })
        
        if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
            self.keyboardTypeChangeObserver = NotificationCenter.default.addObserver(forName: UITextInputMode.currentInputModeDidChangeNotification, object: nil, queue: OperationQueue.main, using: { [weak self] notification in
                if let strongSelf = self, let initialInputHeight = strongSelf.windowLayout.inputHeight, let firstResponder = getFirstResponderAndAccessoryHeight(strongSelf.hostView.eventView).0 {
                    if firstResponder.textInputMode?.primaryLanguage != nil {
                        return
                    }
                    
                    strongSelf.keyboardTypeChangeTimer?.invalidate()
                    let timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: false, completion: {
                        if let strongSelf = self, let firstResponder = getFirstResponderAndAccessoryHeight(strongSelf.hostView.eventView).0 {
                            if firstResponder.textInputMode?.primaryLanguage != nil {
                                return
                            }
                            
                            let updatedKeyboardHeight: CGFloat
                            if #available(iOS 15.0, *), strongSelf.deviceMetrics.type != .tablet,
                               let view = strongSelf.hostView.nativeController?()?.view {
                                let frame = view.convert(view.keyboardLayoutGuide.layoutFrame, to: strongSelf.hostView.eventView)
                                updatedKeyboardHeight = frame.height > view.safeAreaInsets.bottom + 1.0
                                    ? dockedKeyboardHeight(frame: frame, in: strongSelf.hostView.eventView.bounds, safeBottom: view.safeAreaInsets.bottom) : 0.0
                            } else if let keyboardManager = strongSelf.keyboardManager {
                                var height = keyboardManager.getCurrentKeyboardHeight()
                                if strongSelf.deviceMetrics.type == .tablet, abs(strongSelf.windowLayout.size.height - UIScreen.main.bounds.height) > 41.0 {
                                    height = max(0.0, height - 24.0)
                                }
                                updatedKeyboardHeight = height
                            } else {
                                return
                            }
                            if !updatedKeyboardHeight.isEqual(to: initialInputHeight) {
                                strongSelf.updateLayout({ $0.update(inputHeight: updatedKeyboardHeight > 0.0 ? updatedKeyboardHeight : nil, transition: .immediate, overrideTransition: false) })
                            }
                        }
                    }, queue: Queue.mainQueue())
                    strongSelf.keyboardTypeChangeTimer = timer
                    timer.start()
                }
            })
        }
        
        if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
            self.voiceOverStatusObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: OperationQueue.main, using: { [weak self] _ in
                if let strongSelf = self {
                    strongSelf.updateLayout { $0.update(inVoiceOver: UIAccessibility.isVoiceOverRunning) }
                }
            })
        }
        
        let recognizer = WindowPanRecognizer(target: self, action: #selector(self.panGesture(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self.keyboardGestureRecognizerDelegate
        recognizer.isEnabled = self.deviceMetrics.type == .phone
        recognizer.began = { [weak self] point in
            self?.panGestureBegan(location: point)
        }
        recognizer.moved = { [weak self] point in
            self?.panGestureMoved(location: point)
        }
        recognizer.ended = { [weak self] point, velocity in
            self?.panGestureEnded(location: point, velocity: velocity)
        }
        self.windowPanRecognizer = recognizer
        self.hostView.containerView.addGestureRecognizer(recognizer)
        self.hostView.containerView.addSubview(self.badgeView)
    }
            
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let statusBarChangeObserver = self.statusBarChangeObserver {
            NotificationCenter.default.removeObserver(statusBarChangeObserver)
        }
        if let keyboardRotationChangeObserver = self.keyboardRotationChangeObserver {
            NotificationCenter.default.removeObserver(keyboardRotationChangeObserver)
        }
        if let keyboardFrameChangeObserver = self.keyboardFrameChangeObserver {
            NotificationCenter.default.removeObserver(keyboardFrameChangeObserver)
        }
        if let keyboardFrameDidChangeObserver = self.keyboardFrameDidChangeObserver {
            NotificationCenter.default.removeObserver(keyboardFrameDidChangeObserver)
        }
        if let keyboardWillHideObserver = self.keyboardWillHideObserver {
            NotificationCenter.default.removeObserver(keyboardWillHideObserver)
        }
        if let keyboardTypeChangeObserver = self.keyboardTypeChangeObserver {
            NotificationCenter.default.removeObserver(keyboardTypeChangeObserver)
        }
        if let voiceOverStatusObserver = self.voiceOverStatusObserver {
            NotificationCenter.default.removeObserver(voiceOverStatusObserver)
        }
    }
    
    private var forceBadgeHidden = true
    public func setForceBadgeHidden(_ hidden: Bool) {
        guard hidden != self.forceBadgeHidden else {
            return
        }
        self.forceBadgeHidden = hidden
        self.updateBadgeVisibility()
    }
    
    private var proximityDimController: CustomDimController?
    public func setProximityDimHidden(_ hidden: Bool) {
        if !hidden {
            if self.proximityDimController == nil {
                let proximityDimController = CustomDimController(navigationBarPresentationData: nil)
                self.proximityDimController = proximityDimController
                (self.viewController as? NavigationController)?.presentOverlay(controller: proximityDimController, inGlobal: true, blockInteraction: false)
            }
        } else if let proximityDimController = self.proximityDimController {
            self.proximityDimController = nil
            proximityDimController.dismiss()
        }
    }
    
    private func updateBadgeVisibility() {
        let badgeIsHidden = !self.deviceMetrics.showAppBadge || self.forceBadgeHidden || self.windowLayout.size.width > self.windowLayout.size.height
        if badgeIsHidden != self.badgeView.isHidden && !badgeIsHidden {
            Queue.mainQueue().after(0.4) {
                let badgeShouldBeHidden = !self.deviceMetrics.showAppBadge || self.forceBadgeHidden || self.windowLayout.size.width > self.windowLayout.size.height
                if badgeShouldBeHidden == badgeIsHidden {
                    self.badgeView.isHidden = badgeIsHidden
                }
            }
        } else {
            self.badgeView.isHidden = badgeIsHidden
        }
    }
    
    public func setForceInCallStatusBar(_ forceInCallStatusBarText: String?, transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)) {
        if self.forceInCallStatusBarText != forceInCallStatusBarText {
            self.forceInCallStatusBarText = forceInCallStatusBarText
            
            self.updateLayout { $0.update(forceInCallStatusBarText: self.forceInCallStatusBarText, transition: transition, overrideTransition: true) }
            
            self.invalidateTracingStatusBars()
        }
    }
    
    private func invalidateTracingStatusBars() {
        self.tracingStatusBarsInvalidated = true
        self.hostView.eventView.setNeedsLayout()
    }
    
    public func invalidateDeferScreenEdgeGestures() {
        self.shouldUpdateDeferScreenEdgeGestures = true
        self.hostView.eventView.setNeedsLayout()
    }
    
    public func invalidatePrefersOnScreenNavigationHidden() {
        self.shouldInvalidatePrefersOnScreenNavigationHidden = true
        self.hostView.eventView.setNeedsLayout()
    }
    
    public func invalidateSupportedOrientations() {
        self.shouldInvalidateSupportedOrientations = true
        self.hostView.eventView.setNeedsLayout()
    }
    
    public func cancelInteractiveKeyboardGestures() {
        self.windowPanRecognizer?.isEnabled = false
        self.windowPanRecognizer?.isEnabled = true
        
        if self.windowLayout.upperKeyboardInputPositionBound != nil {
            self.updateLayout {
                $0.update(upperKeyboardInputPositionBound: nil, transition: .animated(duration: 0.25, curve: .spring), overrideTransition: false)
            }
        }
        
        if self.keyboardGestureBeginLocation != nil {
            self.keyboardGestureBeginLocation = nil
        }
    }
    
    public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.isInteractionBlocked {
            return nil
        }
                
        if let result = self.topPresentationContext.hitTest(view: self.hostView.containerView, point: point, with: event) {
            return result
        }
        
        if let coveringView = self.coveringView, !coveringView.isHidden, coveringView.superview != nil, coveringView.frame.contains(point) {
            return coveringView.hitTest(point, with: event)
        }
        
        for view in self.hostView.eventView.subviews.reversed() {
            let classString = NSStringFromClass(type(of: view))
            // The system edit menu is inserted as a top-level subview of the window (== eventView) and must
            // be hit-tested here, otherwise its touches fall through to the content below. Pre-iOS-16 this is
            // a `UICalloutBar`/`...ContextMenuContainerView`; on iOS 16+ `UIEditMenuInteraction` hosts it in a
            // `_UIEditMenuContainerView` (matched via "EditMenu"). Without the iOS-16 case, tapping any item
            // in a UIEditMenuInteraction menu does nothing and the tap passes through to the content.
            if classString == "UITransitionView" || classString.contains("ContextMenuContainerView") || classString.contains("EditMenu") {
                if let result = view.hitTest(point, with: event) {
                    return result
                }
            }
        }
        
        if let result = self.overlayPresentationContext.hitTest(point, with: event) {
            return result
        }
        
        for controller in self._topLevelOverlayControllers.reversed() {
            if let result = controller.view.hitTest(point, with: event) {
                return result
            }
        }
        
        if let result = self.presentationContext.hitTest(view: self.hostView.containerView, point: point, with: event) {
            return result
        }
        return self.viewController?.view.hitTest(point, with: event)
    }
    
    func updateSize(_ value: CGSize, duration: Double, orientation: UIInterfaceOrientation) {
        let transition: ContainedViewLayoutTransition
        if !duration.isZero {
            transition = .animated(duration: duration, curve: .easeInOut)
        } else {
            transition = .immediate
        }
        self.updateLayout { $0.update(size: value, metrics: layoutMetricsForScreenSize(size: value, orientation: orientation), safeInsets: self.deviceMetrics.safeInsets(inLandscape: value.width > value.height), forceInCallStatusBarText: self.forceInCallStatusBarText, transition: transition, overrideTransition: true) }
        if let statusBarHost = self.statusBarHost, !statusBarHost.isApplicationInForeground {
            self.layoutSubviews(force: true)
        }
    }
    
    private var _rootController: ContainableController?
    public var viewController: ContainableController? {
        get {
            return _rootController
        }
        set(value) {
            if let rootController = self._rootController {
                rootController.view.removeFromSuperview()
            }
            self._rootController = value
            
            if let rootController = self._rootController {
                if let rootController = rootController as? NavigationController {
                    rootController.statusBarHost = self.statusBarHost
                    rootController.updateSupportedOrientations = { [weak self] in
                        guard let strongSelf = self else {
                            return
                        }
                        
                        var supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .all)
                        let orientationToLock: UIInterfaceOrientationMask
                        if strongSelf.windowLayout.size.width < strongSelf.windowLayout.size.height {
                            orientationToLock = .portrait
                        } else {
                            orientationToLock = .landscape
                        }
                        if let _rootController = strongSelf._rootController {
                            supportedOrientations = supportedOrientations.intersection(_rootController.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
                        }
                        supportedOrientations = supportedOrientations.intersection(strongSelf.presentationContext.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
                        supportedOrientations = supportedOrientations.intersection(strongSelf.overlayPresentationContext.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
                        
                        var resolvedOrientations: UIInterfaceOrientationMask
                        switch strongSelf.windowLayout.metrics.widthClass {
                        case .regular:
                            resolvedOrientations = supportedOrientations.regularSize
                        case .compact:
                            resolvedOrientations = supportedOrientations.compactSize
                        }
                        if resolvedOrientations.isEmpty {
                            resolvedOrientations = [.portrait]
                        }
                        strongSelf.hostView.updateSupportedInterfaceOrientations(resolvedOrientations)
                    }
                    rootController.updateStatusBar = { [weak self] transition in
                        guard let self else {
                            return
                        }
                        self.updateStatusBar(transition: transition)
                    }
                    rootController.keyboardViewManager = self.keyboardViewManager
                    rootController.inCallNavigate = { [weak self] in
                        self?.inCallNavigate?()
                    }
                }
                
                self.hostView.containerView.insertSubview(rootController.view, at: 0)
                if !self.windowLayout.size.width.isZero && !self.windowLayout.size.height.isZero {
                    rootController.displayNode.frame = CGRect(origin: CGPoint(), size: self.windowLayout.size)
                    rootController.containerLayoutUpdated(containedLayoutForWindowLayout(self.windowLayout, deviceMetrics: self.deviceMetrics), transition: .immediate)
                }
            }
            
            self.hostView.eventView.setNeedsLayout()
        }
    }
    
    private var _topLevelOverlayControllers: [ContainableController] = []
    public var topLevelOverlayControllers: [ContainableController] {
        get {
            return _topLevelOverlayControllers
        }
        set(value) {
            for controller in self._topLevelOverlayControllers {
                if let controller = controller as? ViewController {
                    controller.statusBar.alphaUpdated = nil
                }
                controller.view.removeFromSuperview()
            }
            self._topLevelOverlayControllers = value
            
            let layout = containedLayoutForWindowLayout(self.windowLayout, deviceMetrics: self.deviceMetrics)
            for controller in self._topLevelOverlayControllers {
                controller.displayNode.frame = CGRect(origin: CGPoint(), size: self.windowLayout.size)
                controller.containerLayoutUpdated(layout, transition: .immediate)
                
                if let coveringView = self.coveringView {
                    self.hostView.containerView.insertSubview(controller.view, belowSubview: coveringView)
                } else {
                    self.hostView.containerView.insertSubview(controller.view, belowSubview: self.badgeView)
                }
                
                if let controller = controller as? ViewController {
                    controller.statusBar.alphaUpdated = { [weak self] transition in
                        guard let strongSelf = self, let navigationController = strongSelf._rootController as? NavigationController else {
                            return
                        }
                        var isStatusBarHidden: Bool = false
                        for controller in strongSelf._topLevelOverlayControllers {
                            if let controller = controller as? ViewController {
                                if case .Hide = controller.statusBar.statusBarStyle {
                                    isStatusBarHidden = true
                                }
                            }
                        }
                        
                        navigationController.updateExternalStatusBarHidden(isStatusBarHidden, transition: .animated(duration: 0.3, curve: .easeInOut))
                    }
                }
            }
        }
    }
    
    public var coveringView: WindowCoveringView? {
        didSet {
            if self.coveringView !== oldValue {
                if let oldValue = oldValue {
                    oldValue.layer.allowsGroupOpacity = true
                    oldValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak oldValue] _ in
                        oldValue?.removeFromSuperview()
                    })
                }
                if let coveringView = self.coveringView {
                    coveringView.layer.removeAnimation(forKey: "opacity")
                    coveringView.layer.allowsGroupOpacity = false
                    coveringView.alpha = 1.0
                    if let controller = self.topPresentationContext.controllers.first {
                        self.hostView.containerView.insertSubview(coveringView, belowSubview: controller.0.displayNode.view)
                    } else {
                        self.hostView.containerView.insertSubview(coveringView, belowSubview: self.badgeView)
                    }
                    if !self.windowLayout.size.width.isZero {
                        coveringView.frame = CGRect(origin: CGPoint(), size: self.windowLayout.size)
                        coveringView.updateLayout(self.windowLayout.size)
                    }
                }
            }
        }
    }
    
    private func updateStatusBar(transition: ContainedViewLayoutTransition) {
        var style: UIStatusBarStyle = .default
        var isHidden = false
        
        if let rootController = self._rootController as? NavigationController {
            let statusBar = rootController.statusBar
            style = statusBar.style
            isHidden = statusBar.isHidden
        }
        
        if let statusBar = self.presentationContext.statusBar {
            style = statusBar.style
            isHidden = statusBar.isHidden
        }
        
        if let statusBar = self.topPresentationContext.statusBar {
            style = statusBar.style
            isHidden = statusBar.isHidden
        }
        
        self.hostView.updateStatusBar(style, isHidden, transition)
    }
    
    private func layoutSubviews(force: Bool) {
        if self.tracingStatusBarsInvalidated, let _ = keyboardManager {
            self.tracingStatusBarsInvalidated = false
            
            var supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .all)
            let orientationToLock: UIInterfaceOrientationMask
            if self.windowLayout.size.width < self.windowLayout.size.height {
                orientationToLock = .portrait
            } else {
                orientationToLock = .landscape
            }
            if let _rootController = self._rootController {
                supportedOrientations = supportedOrientations.intersection(_rootController.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
            }
            supportedOrientations = supportedOrientations.intersection(self.presentationContext.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
            supportedOrientations = supportedOrientations.intersection(self.overlayPresentationContext.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
            
            var resolvedOrientations: UIInterfaceOrientationMask
            switch self.windowLayout.metrics.widthClass {
                case .regular:
                    resolvedOrientations = supportedOrientations.regularSize
                case .compact:
                    resolvedOrientations = supportedOrientations.compactSize
            }
            if resolvedOrientations.isEmpty {
                resolvedOrientations = [.portrait]
            }
            self.hostView.updateSupportedInterfaceOrientations(resolvedOrientations)
            
            self.hostView.updateDeferScreenEdgeGestures(self.collectScreenEdgeGestures())
            self.hostView.updatePrefersOnScreenNavigationHidden(self.collectPrefersOnScreenNavigationHidden())
            
            self.shouldUpdateDeferScreenEdgeGestures = false
            self.shouldInvalidatePrefersOnScreenNavigationHidden = false
            self.shouldInvalidateSupportedOrientations = false
        } else if self.shouldUpdateDeferScreenEdgeGestures || self.shouldInvalidatePrefersOnScreenNavigationHidden || self.shouldInvalidateSupportedOrientations {
            self.hostView.updateDeferScreenEdgeGestures(self.collectScreenEdgeGestures())
            self.hostView.updatePrefersOnScreenNavigationHidden(self.collectPrefersOnScreenNavigationHidden())
            
            self.shouldUpdateDeferScreenEdgeGestures = false
            self.shouldInvalidatePrefersOnScreenNavigationHidden = false
            
            if self.shouldInvalidateSupportedOrientations {
                var supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .all)
                let orientationToLock: UIInterfaceOrientationMask
                if self.windowLayout.size.width < self.windowLayout.size.height {
                    orientationToLock = .portrait
                } else {
                    orientationToLock = .landscape
                }
                if let _rootController = self._rootController {
                    supportedOrientations = supportedOrientations.intersection(_rootController.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
                }
                supportedOrientations = supportedOrientations.intersection(self.presentationContext.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
                supportedOrientations = supportedOrientations.intersection(self.overlayPresentationContext.combinedSupportedOrientations(currentOrientationToLock: orientationToLock))
                
                var resolvedOrientations: UIInterfaceOrientationMask
                switch self.windowLayout.metrics.widthClass {
                    case .regular:
                        resolvedOrientations = supportedOrientations.regularSize
                    case .compact:
                        resolvedOrientations = supportedOrientations.compactSize
                }
                if resolvedOrientations.isEmpty {
                    resolvedOrientations = [.portrait]
                }
                self.hostView.updateSupportedInterfaceOrientations(resolvedOrientations)
                
                self.shouldInvalidateSupportedOrientations = false
            }
        }
        
        if force {
            self.commitUpdatingLayout()
        } else if !UIWindow.isDeviceRotating() {
            if !self.hostView.isUpdatingOrientationLayout {
                self.commitUpdatingLayout()
            } else {
                self.addPostUpdateToInterfaceOrientationBlock(f: { [weak self] in
                    if let strongSelf = self {
                        strongSelf.hostView.eventView.setNeedsLayout()
                    }
                })
            }
        } else {
            UIWindow.addPostDeviceOrientationDidChange({ [weak self] in
                if let strongSelf = self {
                    strongSelf.hostView.eventView.setNeedsLayout()
                }
            })
        }
    }
    
    var postUpdateToInterfaceOrientationBlocks: [() -> Void] = []
    
    private func updateToInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        let blocks = self.postUpdateToInterfaceOrientationBlocks
        self.postUpdateToInterfaceOrientationBlocks = []
        for f in blocks {
            f()
        }
        self._rootController?.updateToInterfaceOrientation(orientation)
        self.presentationContext.updateToInterfaceOrientation(orientation)
        self.overlayPresentationContext.updateToInterfaceOrientation(orientation)
        
         self.topPresentationContext.updateToInterfaceOrientation(orientation)
        
        for controller in self.topLevelOverlayControllers {
            controller.updateToInterfaceOrientation(orientation)
        }
    }
    
    public func addPostUpdateToInterfaceOrientationBlock(f: @escaping () -> Void) {
        postUpdateToInterfaceOrientationBlocks.append(f)
    }
    
    private func updateLayout(_ update: (inout UpdatingLayout) -> ()) {
        if self.updatingLayout == nil {
            var updatingLayout = UpdatingLayout(layout: self.windowLayout, transition: .immediate)
            update(&updatingLayout)
            if updatingLayout.layout != self.windowLayout {
                self.updatingLayout = updatingLayout
                self.hostView.eventView.setNeedsLayout()
            }
        } else {
            update(&self.updatingLayout!)
            self.hostView.eventView.setNeedsLayout()
        }
    }
    
    private var isFirstLayout = true
    
    private func commitUpdatingLayout() {
        if let updatingLayout = self.updatingLayout {
            self.updatingLayout = nil
            if updatingLayout.layout != self.windowLayout || self.isFirstLayout {
                self.isFirstLayout = false
                
                let boundsSize = updatingLayout.layout.size
                let isLandscape = boundsSize.width > boundsSize.height
                var statusBarHeight: CGFloat? = self.deviceMetrics.statusBarHeight(for: boundsSize)
                if let statusBarHeightValue = statusBarHeight, let statusBarHost = self.statusBarHost {
                    statusBarHeight = max(statusBarHeightValue, statusBarHost.statusBarFrame.size.height)
                } else {
                    statusBarHeight = nil
                }
                
                if self.deviceMetrics.type == .tablet, let onScreenNavigationHeight = self.hostView.onScreenNavigationHeight, onScreenNavigationHeight != self.deviceMetrics.onScreenNavigationHeight(inLandscape: false, systemOnScreenNavigationHeight: self.hostView.onScreenNavigationHeight) {
                    self.deviceMetrics = DeviceMetrics(screenSize: UIScreen.main.bounds.size, scale: UIScreen.main.scale, statusBarHeight: statusBarHeight ?? 0.0, onScreenNavigationHeight: onScreenNavigationHeight)
                }
                
                let statusBarWasHidden = self.statusBarHidden
                if statusBarHiddenInLandscape && isLandscape {
                    statusBarHeight = nil
                    self.statusBarHidden = true
                } else {
                    self.statusBarHidden = false
                }
                if self.statusBarHidden != statusBarWasHidden {
                    self.tracingStatusBarsInvalidated = true
                    self.hostView.eventView.setNeedsLayout()
                }
                let previousInputOffset = inputHeightOffsetForLayout(self.windowLayout)
                
                self.windowLayout = WindowLayout(size: updatingLayout.layout.size, metrics: layoutMetricsForScreenSize(size: updatingLayout.layout.size, orientation: updatingLayout.layout.metrics.orientation), statusBarHeight: statusBarHeight, forceInCallStatusBarText: updatingLayout.layout.forceInCallStatusBarText, inputHeight: updatingLayout.layout.inputHeight, safeInsets: updatingLayout.layout.safeInsets, onScreenNavigationHeight: self.deviceMetrics.onScreenNavigationHeight(inLandscape: isLandscape, systemOnScreenNavigationHeight: self.hostView.onScreenNavigationHeight), upperKeyboardInputPositionBound: updatingLayout.layout.upperKeyboardInputPositionBound, inVoiceOver: updatingLayout.layout.inVoiceOver)
                
                let childLayout = containedLayoutForWindowLayout(self.windowLayout, deviceMetrics: self.deviceMetrics)
                let childLayoutUpdated = self.updatedContainerLayout != childLayout
                self.updatedContainerLayout = childLayout
                
                if childLayoutUpdated {
                    var rootLayout = childLayout
                    let rootTransition = updatingLayout.transition
                    if self.presentationContext.isCurrentlyOpaque {
                        rootLayout.inputHeight = nil
                    }
                    if let rootController = self._rootController {
                        rootTransition.updateFrame(node: rootController.displayNode, frame: CGRect(origin: CGPoint(), size: self.windowLayout.size))
                        rootController.containerLayoutUpdated(rootLayout, transition: rootTransition)
                    }
                    self.presentationContext.containerLayoutUpdated(childLayout, transition: updatingLayout.transition)
                    self.overlayPresentationContext.containerLayoutUpdated(childLayout, transition: updatingLayout.transition)
                    
                    self.topPresentationContext.containerLayoutUpdated(childLayout, transition: updatingLayout.transition)
                
                    for controller in self.topLevelOverlayControllers {
                        updatingLayout.transition.updateFrame(node: controller.displayNode, frame: CGRect(origin: CGPoint(), size: self.windowLayout.size))
                        controller.containerLayoutUpdated(childLayout, transition: updatingLayout.transition)
                    }
                }
                
                let updatedInputOffset = inputHeightOffsetForLayout(self.windowLayout)
                if !previousInputOffset.isEqual(to: updatedInputOffset) {
                    let hide = updatingLayout.transition.isAnimated && updatingLayout.layout.upperKeyboardInputPositionBound == updatingLayout.layout.size.height
                    if hide {
                        print("hide with \(updatingLayout.transition)")
                    }
                    self.keyboardManager?.updateInteractiveInputOffset(updatedInputOffset, transition: updatingLayout.transition, completion: { [weak self] in
                        if let strongSelf = self, hide {
                            strongSelf.updateLayout {
                                $0.update(upperKeyboardInputPositionBound: nil, transition: .immediate, overrideTransition: false)
                            }
                            strongSelf.hostView.eventView.endEditing(true)
                        }
                    })
                }
                
                if let coveringView = self.coveringView {
                    coveringView.frame = CGRect(origin: CGPoint(), size: self.windowLayout.size)
                    coveringView.updateLayout(self.windowLayout.size)
                }
                
                if let image = self.badgeView.image {
                    self.updateBadgeVisibility()
                    self.badgeView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((self.windowLayout.size.width - image.size.width) / 2.0), y: self.deviceMetrics.sgAppBadgeOffset(statusBarHeight: self.windowLayout.statusBarHeight)), size: image.size)
                }
            }
        }
    }
    
    public func present(_ controller: ContainableController, on level: PresentationSurfaceLevel, blockInteraction: Bool = false, completion: @escaping () -> Void = {}) {
        if level.rawValue <= 3, let controller = controller as? ViewController {
            for presentedController in self.presentationContext.controllers.reversed() {
                if let navigationController = presentedController.0 as? NavigationController {
                    navigationController.presentOverlay(controller: controller, inGlobal: false, blockInteraction: blockInteraction)
                    return
                }
            }
            
            if let navigationController = self._rootController as? NavigationController {
                navigationController.presentOverlay(controller: controller, inGlobal: false, blockInteraction: blockInteraction)
            } else {
                self.presentationContext.present(controller, on: level, blockInteraction: blockInteraction, completion: completion)
            }
        } else {
            if let controller = controller as? ViewController, controller.presentedOverCoveringView {
                self.topPresentationContext.present(controller, on: level, completion: completion)
            } else {
                self.presentationContext.present(controller, on: level, blockInteraction: blockInteraction, completion: completion)
            }
        }
    }
    
    public func presentInGlobalOverlay(_ controller: ContainableController) {
        if let controller = controller as? ViewController {
            if let navigationController = self._rootController as? NavigationController {
                navigationController.presentOverlay(controller: controller, inGlobal: true)
                return
            }
        }
        self.overlayPresentationContext.present(controller)
    }
    
    public func addGlobalPortalHostView(sourceView: PortalSourceView) {
        self.overlayPresentationContext.addGlobalPortalHostView(sourceView: sourceView)
    }
    
    public func presentNative(_ controller: UIViewController) {
        if let nativeController = self.hostView.nativeController?() {
            nativeController.present(controller, animated: true, completion: nil)
        }
    }
    
    private func panGestureBegan(location: CGPoint) {
        if self.windowLayout.upperKeyboardInputPositionBound != nil {
            return
        }
        
        let keyboardGestureBeginLocation = location
        let view = self.hostView.containerView
        let (firstResponder, accessoryHeight) = getFirstResponderAndAccessoryHeight(view)
        if let inputHeight = self.windowLayout.inputHeight, !inputHeight.isZero, keyboardGestureBeginLocation.y < self.windowLayout.size.height - inputHeight - (accessoryHeight ?? 0.0) {
            var enableGesture = true
            if let view = self.hostView.containerView.hitTest(location, with: nil) {
                if doesViewTreeDisableInteractiveTransitionGestureRecognizer(view, keyboardOnly: true) {
                    enableGesture = false
                }
            }
            if enableGesture, let _ = firstResponder {
                self.keyboardGestureBeginLocation = keyboardGestureBeginLocation
                self.keyboardGestureAccessoryHeight = accessoryHeight
            }
        }
    }
    
    private func panGestureMoved(location: CGPoint) {
        if let keyboardGestureBeginLocation = self.keyboardGestureBeginLocation {
            guard self.keyboardManager?.canControlInteractiveKeyboard == true else {
                // Without a controllable keyboard surface, moving only the
                // composer puts it underneath the stationary system keyboard.
                self.updateLayout {
                    $0.update(upperKeyboardInputPositionBound: nil, transition: .immediate, overrideTransition: false)
                }
                return
            }
            let currentLocation = location
            let deltaY = keyboardGestureBeginLocation.y - location.y
            if deltaY * deltaY >= 3.0 * 3.0 || self.windowLayout.upperKeyboardInputPositionBound != nil {
                self.updateLayout {
                    $0.update(upperKeyboardInputPositionBound: currentLocation.y + (self.keyboardGestureAccessoryHeight ?? 0.0), transition: .immediate, overrideTransition: false)
                }
            }
        }
    }
    
    public func simulateKeyboardDismiss(transition: ContainedViewLayoutTransition) {
        var simulate = false
        for controller in self.overlayPresentationContext.controllers {
            if controller.isViewLoaded {
                if controller.view.window != self.hostView.containerView.window {
                    simulate = true
                    break
                }
            }
        }
        if simulate, self.keyboardManager?.canControlInteractiveKeyboard == true {
            self.updateLayout {
                $0.update(upperKeyboardInputPositionBound: self.windowLayout.size.height, transition: transition, overrideTransition: false)
            }
        } else {
            self.hostView.containerView.findFirstResponder()?.resignFirstResponder()
        }
    }
    
    private func panGestureEnded(location: CGPoint, velocity: CGPoint?) {
        if self.keyboardGestureBeginLocation == nil {
            return
        }
        
        self.keyboardGestureBeginLocation = nil
        let currentLocation = location
        
        let accessoryHeight = (self.keyboardGestureAccessoryHeight ?? 0.0)

        if self.keyboardManager?.canControlInteractiveKeyboard != true {
            self.updateLayout {
                $0.update(upperKeyboardInputPositionBound: nil, transition: .immediate, overrideTransition: false)
            }
            if let inputHeight = self.windowLayout.inputHeight,
               currentLocation.y + accessoryHeight > self.windowLayout.size.height - inputHeight,
               currentLocation.y + accessoryHeight >= self.windowLayout.size.height - accessoryHeight || (velocity?.y ?? 0.0) > 100.0 {
                // UIKit owns both the keyboard animation and its frame updates.
                self.hostView.eventView.endEditing(true)
            }
            return
        }
        
        var canDismiss = false
        if let upperKeyboardInputPositionBound = self.windowLayout.upperKeyboardInputPositionBound, upperKeyboardInputPositionBound >= self.windowLayout.size.height - accessoryHeight {
            canDismiss = true
        } else if let velocity = velocity, velocity.y > 100.0 {
            canDismiss = true
        }
        
        if canDismiss, let inputHeight = self.windowLayout.inputHeight, currentLocation.y + (self.keyboardGestureAccessoryHeight ?? 0.0) > self.windowLayout.size.height - inputHeight {
            let springDuration: CGFloat
            if #available(iOS 26.0, *) {
                springDuration = 0.3832
            } else {
                springDuration = 0.25
            }
            self.updateLayout {
                $0.update(upperKeyboardInputPositionBound: self.windowLayout.size.height, transition: .animated(duration: springDuration, curve: .spring), overrideTransition: false)
            }
        } else {
            self.updateLayout {
                $0.update(upperKeyboardInputPositionBound: nil, transition: .animated(duration: 0.25, curve: .spring), overrideTransition: false)
            }
        }
    }
    
    @objc func panGesture(_ recognizer: WindowPanRecognizer) {
        switch recognizer.state {
            case .began:
                self.panGestureBegan(location: recognizer.location(in: recognizer.view))
            case .changed:
                self.panGestureMoved(location: recognizer.location(in: recognizer.view))
            case .ended:
                self.panGestureEnded(location: recognizer.location(in: recognizer.view), velocity: recognizer.velocity(in: recognizer.view))
            case .cancelled:
                self.panGestureEnded(location: recognizer.location(in: recognizer.view), velocity: nil)
            default:
                break
        }
    }
    
    private func collectScreenEdgeGestures() -> UIRectEdge {
        var edges: UIRectEdge = []
        if let navigationController = self._rootController as? NavigationController, let overlayController = navigationController.topOverlayController {
            edges = edges.union(overlayController.deferScreenEdgeGestures)
        }
        edges = edges.union(self.presentationContext.combinedDeferScreenEdgeGestures())
        
        for controller in self.topLevelOverlayControllers {
            if let controller = controller as? ViewController {
                edges = edges.union(controller.deferScreenEdgeGestures)
            }
        }
        
        return edges
    }
    
    private func collectPrefersOnScreenNavigationHidden() -> Bool {
        var hidden = false
        if let navigationController = self._rootController as? NavigationController, let overlayController = navigationController.topOverlayController {
            hidden = hidden || overlayController.prefersOnScreenNavigationHidden
        }
        hidden = hidden || self.presentationContext.combinedPrefersOnScreenNavigationHidden()
        
        for controller in self.topLevelOverlayControllers {
            if let controller = controller as? ViewController {
                hidden = hidden || controller.prefersOnScreenNavigationHidden
            }
        }
        
        return hidden
    }
    
    public func forEachViewController(_ f: (ContainableController) -> Bool, excludeNavigationSubControllers: Bool = false) {
        if let navigationController = self._rootController as? NavigationController {
            if !excludeNavigationSubControllers {
                for case let controller as ContainableController in navigationController.viewControllers {
                    let _ = f(controller)
                }
            }
            if let controller = navigationController.topOverlayController {
                let _ = f(controller)
            }
        }
        for (controller, _) in self.presentationContext.controllers {
            if !f(controller) {
                break
            }
        }
        
        for controller in self.topLevelOverlayControllers {
            if !f(controller) {
                break
            }
        }
        for (controller, _) in self.topPresentationContext.controllers {
            if !f(controller) {
                break
            }
        }
    }
    
    public func doNotAnimateLikelyKeyboardAutocorrectionSwitch() {
        self.shouldNotAnimateLikelyKeyboardAutocorrectionSwitch = true
        DispatchQueue.main.async {
            self.shouldNotAnimateLikelyKeyboardAutocorrectionSwitch = false
        }
    }
}

private class CustomDimController: ViewController {
    class Node: ASDisplayNode {
        override init() {
            super.init()
            
            self.backgroundColor = .black
        }
    }
    override init(navigationBarPresentationData: NavigationBarPresentationData?) {
        super.init(navigationBarPresentationData: nil)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadDisplayNode() {
        let node = Node()
        self.displayNode = node
        
        
        
        
    }
}
