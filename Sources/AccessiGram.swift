import UIKit
import ObjectiveC.runtime

// Turrit 1.5.5 (10387). Swift reflection reads named fields, never fixed offsets.
private func unwrap(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional { return mirror.children.first.flatMap { unwrap($0.value) } }
    return value
}
private func field(_ object: Any, _ name: String) -> Any? {
    var mirror: Mirror? = Mirror(reflecting: object)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == name }) { return unwrap(child.value) }
        mirror = current.superclassMirror
    }
    return nil
}
private func list(_ value: Any?) -> [Any] {
    value.map { Mirror(reflecting: $0).children.map(\.value) } ?? []
}
private func nodeView(_ object: NSObject) -> UIView? {
    if let view = object as? UIView { return view }
    let selector = NSSelectorFromString("view")
    return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() as? UIView : nil
}
private func text(_ object: Any?) -> String? {
    if let label = object as? UILabel { return label.text }
    if let object = object as? NSObject, object.responds(to: NSSelectorFromString("attributedText")) {
        return (object.perform(NSSelectorFromString("attributedText"))?.takeUnretainedValue() as? NSAttributedString)?.string
    }
    return nil
}
private func replace(_ cls: AnyClass, _ name: String, _ block: Any, _ types: String) {
    let sel = NSSelectorFromString(name)
    let imp = imp_implementationWithBlock(block)
    class_replaceMethod(cls, sel, imp, types)
}
private func originalBool(_ cls: AnyClass, _ selector: String) -> ((NSObject) -> Bool)? {
    let sel = NSSelectorFromString(selector)
    guard let method = class_getInstanceMethod(cls, sel) else { return nil }
    let fn = unsafeBitCast(method_getImplementation(method), to: (@convention(c) (NSObject, Selector) -> Bool).self)
    return { fn($0, sel) }
}
private var installed: [String] = []
private func target(_ name: String, _ apply: (AnyClass) -> Void) {
    if let cls = NSClassFromString(name) { apply(cls); installed.append(name) }
}

private final class ActionElement: UIAccessibilityElement {
    var activate: () -> Bool = { false }
    override func accessibilityActivate() -> Bool { activate() }
}
private final class TabCache: NSObject {
    var elements: [ObjectIdentifier: ActionElement] = [:]
}
private var tabCacheKey: UInt8 = 0

private func tabElements(_ view: UIView) -> NSArray? {
    guard let component = field(view, "component") else { return nil }
    let cache: TabCache
    if let existing = objc_getAssociatedObject(view, &tabCacheKey) as? TabCache { cache = existing }
    else { cache = TabCache(); objc_setAssociatedObject(view, &tabCacheKey, cache, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    // itemViews excludes the duplicate selected-item rendering layer and measuring views.
    var rendered: [ObjectIdentifier: UIView] = [:]
    for pair in list(field(view, "itemViews")) {
        let values = Array(Mirror(reflecting: pair).children)
        guard values.count == 2, let itemView = field(values[1].value, "view") as? UIView,
              let itemComponent = field(itemView, "component"),
              let item = field(itemComponent, "item") as AnyObject? else { continue }
        rendered[ObjectIdentifier(item)] = itemView
    }
    var result: [Any] = []
    var active: Set<ObjectIdentifier> = []
    for raw in list(field(component, "items")) {
        let item = raw as AnyObject
        let key = ObjectIdentifier(item)
        guard let itemView = rendered[key], !itemView.isHidden, itemView.alpha > 0.01,
              let content = field(raw, "content"),
              let payload = Mirror(reflecting: content).children.first?.value,
              let action = field(raw, "action") as? (Bool) -> Void else { continue }
        let element = cache.elements[key] ?? ActionElement(accessibilityContainer: view)
        cache.elements[key] = element
        active.insert(key)
        let barItem = payload as? UITabBarItem
        element.accessibilityLabel = barItem?.accessibilityLabel ?? barItem?.title ?? field(payload, "title") as? String
        element.accessibilityValue = barItem?.accessibilityValue ?? barItem?.badgeValue ?? field(payload, "badge") as? String
        element.accessibilityTraits = [.button]
        if let itemComponent = field(itemView, "component"), field(itemComponent, "isSelected") as? Bool == true {
            element.accessibilityTraits.insert(.selected)
        }
        element.accessibilityFrameInContainerSpace = view.convert(itemView.bounds, from: itemView)
        element.activate = { action(false); return true }
        result.append(element)
    }
    cache.elements = cache.elements.filter { active.contains($0.key) }
    if let search = field(view, "searchView") as? UIView, !search.isHidden, search.alpha > 0.01 { result.append(search) }
    return result.isEmpty ? nil : result as NSArray
}

private func installTabs() {
    target("_TtCC15TabBarComponent15TabBarComponent4View") { cls in
        let method = class_getInstanceMethod(cls, NSSelectorFromString("accessibilityElements"))!
        let old = unsafeBitCast(method_getImplementation(method), to: (@convention(c) (NSObject, Selector) -> NSArray?).self)
        let getter: @convention(block) (UIView) -> NSArray? = { view in
            if UIAccessibility.isVoiceOverRunning, let result = tabElements(view) { return result }
            return old(view, NSSelectorFromString("accessibilityElements"))
        }
        replace(cls, "accessibilityElements", getter, "@@:")
    }
    // Legacy tab bar: the supplied build uses an incorrect screen-space AX frame.
    target("_TtC8TabBarUIP33_0A65A3DF6B07431C569BC18C5E7B56CC14TabBarItemNode") { cls in
        let getter: @convention(block) (NSObject) -> CGRect = { object in
            guard let view = nodeView(object) else { return .zero }
            return UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
        }
        replace(cls, "accessibilityFrame", getter, "{CGRect={CGPoint=dd}{CGSize=dd}}@:")
    }
}

private func installButton(_ name: String, action: @escaping (NSObject) -> Bool,
                           label: ((NSObject) -> String?)? = nil,
                           selected: ((NSObject) -> Bool)? = nil) {
    target(name) { cls in
        let oldActivate = originalBool(cls, "accessibilityActivate")
        let activate: @convention(block) (NSObject) -> Bool = { object in
            if UIAccessibility.isVoiceOverRunning, action(object) { return true }
            return oldActivate?(object) ?? false
        }
        replace(cls, "accessibilityActivate", activate, "B@:")
        let oldElement = originalBool(cls, "isAccessibilityElement")
        let element: @convention(block) (NSObject) -> Bool = { object in
            UIAccessibility.isVoiceOverRunning || (oldElement?(object) ?? false)
        }
        replace(cls, "isAccessibilityElement", element, "B@:")
        if let label {
            let sel = NSSelectorFromString("accessibilityLabel")
            let method = class_getInstanceMethod(cls, sel)!
            let old = unsafeBitCast(method_getImplementation(method), to: (@convention(c) (NSObject, Selector) -> NSString?).self)
            let getter: @convention(block) (NSObject) -> NSString? = { object in
                if UIAccessibility.isVoiceOverRunning, let value = label(object) { return value as NSString }
                return old(object, sel)
            }
            replace(cls, "accessibilityLabel", getter, "@@:")
        }
        let sel = NSSelectorFromString("accessibilityTraits")
        let method = class_getInstanceMethod(cls, sel)!
        let old = unsafeBitCast(method_getImplementation(method), to: (@convention(c) (NSObject, Selector) -> UInt64).self)
        let traits: @convention(block) (NSObject) -> UInt64 = { object in
            var result = UIAccessibilityTraits(rawValue: old(object, sel))
            if UIAccessibility.isVoiceOverRunning {
                result.insert(.button)
                if let selected {
                    result.remove(.selected)
                    if selected(object) { result.insert(.selected) }
                }
            }
            return result.rawValue
        }
        replace(cls, "accessibilityTraits", traits, "Q@:")
    }
}
private func invoke(_ object: NSObject, _ fieldName: String) -> Bool {
    if let action = field(object, fieldName) as? () -> Void { action(); return true }
    return false
}
private func installButtons() {
    installButton("_TtC17NavigationBarImplP33_2ABB6CC4B7F241513FE7442B3C027B4224NavigationButtonItemNode", action: { invoke($0, "pressed") })
    for name in ["_TtC14PeerInfoScreen30PeerInfoHeaderNavigationButton", "_TtC19PeerNameColorScreen30PeerInfoHeaderNavigationButton", "_TtC12StatisticsUI30PeerInfoHeaderNavigationButton", "_TtCC23ChatListHeaderComponent25NavigationButtonComponent4View"] {
        installButton(name, action: { object in
            object.perform(NSSelectorFromString("pressed")); return true
        }, label: { text(field($0, "textNode")) ?? text(field($0, "textView")) })
    }
    installButton("_TtC18SelectablePeerNode18SelectablePeerNode", action: { object in
        guard let toggle = field(object, "toggleSelection") as? (Bool) -> Void else { return false }
        toggle(field(object, "requiresPremiumForMessaging") as? Bool ?? false)
        return true
    }, label: { text(field($0, "textNode")) }, selected: { field($0, "currentSelected") as? Bool == true })
}

private func chatNode(_ controller: UIViewController) -> NSObject? {
    field(controller.view as Any, "node") as? NSObject
}
private func chatController(_ view: UIView) -> UIViewController? {
    var responder: UIResponder? = view
    while let current = responder {
        if let vc = current as? UIViewController,
           NSStringFromClass(type(of: vc)) == "_TtC10TelegramUI18ChatControllerImpl" { return vc }
        responder = current.next
    }
    return nil
}
private func back(_ controller: UIViewController) -> Bool {
    if let nav = controller.navigationController, nav.viewControllers.count > 1 {
        nav.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        return true
    }
    if controller.presentingViewController != nil {
        controller.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        return true
    }
    return false
}
private func installEscape() {
    // Only Telegram's controller family; UIKit dialogs retain their own escape handling.
    for name in ["_TtC10TelegramUI18ChatControllerImpl", "_TtC7Display20ViewController", "_TtC7Display20NavigationController"] {
        target(name) { cls in
            let old = originalBool(cls, "accessibilityPerformEscape")
            let escape: @convention(block) (UIViewController) -> Bool = { controller in
                if old?(controller) == true { return true }
                return UIAccessibility.isVoiceOverRunning && back(controller)
            }
            replace(cls, "accessibilityPerformEscape", escape, "B@:")
        }
    }
}
private final class ChatState: NSObject {
    var pendingLatest = true
    var actionsInstalled = false
}
private var chatStateKey: UInt8 = 0
private func state(_ controller: UIViewController) -> ChatState {
    if let state = objc_getAssociatedObject(controller, &chatStateKey) as? ChatState { return state }
    let state = ChatState()
    objc_setAssociatedObject(controller, &chatStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return state
}
private func latest(_ controller: UIViewController) -> Bool {
    guard let node = chatNode(controller), let buttons = field(node, "navigateButtons") as? NSObject else { return false }
    return invoke(buttons, "downPressed")
}
private func configureChat(_ controller: UIViewController) {
    guard UIAccessibility.isVoiceOverRunning, controller.view.window != nil,
          let node = chatNode(controller), let history = field(node, "historyNode"),
          let listNode = field(history, "listView") as? NSObject else { return }
    let current = state(controller)
    if !current.actionsInstalled {
        current.actionsInstalled = true
        // A persistent rotor action works even when Telegram hides its down-arrow view.
        let latestAction = UIAccessibilityCustomAction(name: "跳到最新訊息") { [weak controller] _ in
            guard let controller else { return false }
            state(controller).pendingLatest = false
            return latest(controller)
        }
        controller.view.accessibilityCustomActions = (controller.view.accessibilityCustomActions ?? []) + [latestAction]
        if let historyView = nodeView(listNode) {
            historyView.accessibilityCustomActions = (historyView.accessibilityCustomActions ?? []) + [latestAction]
        }
    }
    // Wait for actual loaded items, not a fixed delay. Never move again after the first entry.
    if current.pendingLatest, !list(field(listNode, "itemNodes")).isEmpty {
        current.pendingLatest = false
        _ = latest(controller)
    }
}
private func installChat() {
    target("_TtC10TelegramUI18ChatControllerImpl") { cls in
        let sel = NSSelectorFromString("viewDidAppear:")
        let old = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, sel)!), to: (@convention(c) (UIViewController, Selector, Bool) -> Void).self)
        let appeared: @convention(block) (UIViewController, Bool) -> Void = { vc, animated in
            old(vc, sel, animated)
            DispatchQueue.main.async { [weak vc] in if let vc { configureChat(vc) } }
        }
        replace(cls, "viewDidAppear:", appeared, "v@:B")
    }
    target("_TtC7Display19ListViewBackingView") { cls in
        let sel = NSSelectorFromString("layoutSubviews")
        let old = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, sel)!), to: (@convention(c) (UIView, Selector) -> Void).self)
        let layout: @convention(block) (UIView) -> Void = { view in
            old(view, sel)
            if UIAccessibility.isVoiceOverRunning, let vc = chatController(view), state(vc).pendingLatest {
                DispatchQueue.main.async { [weak vc] in if let vc { configureChat(vc) } }
            }
        }
        replace(cls, "layoutSubviews", layout, "v@:")
        let scrollSel = NSSelectorFromString("accessibilityScroll:")
        let original = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, scrollSel)!), to: (@convention(c) (UIView, Selector, Int) -> Bool).self)
        let scroll: @convention(block) (UIView, Int) -> Bool = { view, direction in
            if let vc = chatController(view) { state(vc).pendingLatest = false }
            // The native ListView handles inverted history, async page loading and pageScrolled.
            return original(view, scrollSel, direction)
        }
        replace(cls, "accessibilityScroll:", scroll, "B@:q")
        let elementsSel = NSSelectorFromString("accessibilityElements")
        let oldElements = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, elementsSel)!), to: (@convention(c) (UIView, Selector) -> NSArray?).self)
        let elements: @convention(block) (UIView) -> NSArray? = { view in
            guard UIAccessibility.isVoiceOverRunning, chatController(view) != nil,
                  let listNode = field(view, "target") else { return oldElements(view, elementsSel) }
            let visible = list(field(listNode, "itemNodes")).compactMap { ($0 as? NSObject).flatMap(nodeView) }.filter {
                !$0.isHidden && $0.alpha > 0.01 && view.convert($0.bounds, from: $0).intersects(view.bounds)
            }.sorted { view.convert($0.bounds, from: $0).minY < view.convert($1.bounds, from: $1).minY }
            // Keep native message containers/actions and stable UIView identities.
            return visible.isEmpty ? oldElements(view, elementsSel) : visible as NSArray
        }
        replace(cls, "accessibilityElements", elements, "@@:")
    }
}

@_cdecl("AGStart")
public func AGStart() {
    installTabs()
    installButtons()
    installEscape()
    installChat()
    NSLog("[Accessi gram] 0.1.0 loaded; installed %ld target hooks", installed.count)
}
