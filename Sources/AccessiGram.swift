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
    var elements: [AnyHashable: ActionElement] = [:]
}
private var tabCacheKey: UInt8 = 0

private func tabIdentity(_ item: Any) -> AnyHashable? {
    guard let content = field(item, "content"),
          let payload = Mirror(reflecting: content).children.first?.value else { return nil }
    if let tab = payload as? UITabBarItem { return AnyHashable(ObjectIdentifier(tab)) }
    return field(payload, "id") as? AnyHashable
}

private func tabElements(_ view: UIView) -> NSArray? {
    guard let component = field(view, "component") else { return nil }
    let cache: TabCache
    if let existing = objc_getAssociatedObject(view, &tabCacheKey) as? TabCache { cache = existing }
    else { cache = TabCache(); objc_setAssociatedObject(view, &tabCacheKey, cache, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    // itemViews excludes the duplicate selected-item rendering layer and measuring views.
    var rendered: [AnyHashable: UIView] = [:]
    for pair in list(field(view, "itemViews")) {
        let values = Array(Mirror(reflecting: pair).children)
        guard values.count == 2, let itemView = field(values[1].value, "view") as? UIView,
              let itemComponent = field(itemView, "component"),
              let item = field(itemComponent, "item") as AnyObject? else { continue }
        if let key = tabIdentity(item) { rendered[key] = itemView }
    }
    var result: [Any] = []
    var active: Set<AnyHashable> = []
    for raw in list(field(component, "items")) {
        guard let key = tabIdentity(raw) else { continue }
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
    attachedNode(controller.view)
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
    let name = className(controller)
    if name == "_TtC9GalleryUI17GalleryController", send(controller, "donePressed") { return true }
    let animated = !UIAccessibility.isReduceMotionEnabled
    if let presented = controller.presentedViewController, !presented.isBeingDismissed {
        controller.dismiss(animated: animated)
        return true
    }
    if let nav = controller as? UINavigationController ?? controller.navigationController,
       nav.viewControllers.count > 1, nav === controller || nav.topViewController === controller {
        return nav.popViewController(animated: animated) != nil
    }
    if controller.presentingViewController != nil && !controller.isBeingDismissed {
        controller.dismiss(animated: animated)
        return true
    }
    return false
}
private func installEscape() {
    for name in ["_TtC7Display14ViewController", "_TtC7Display20NavigationController", "TGNavigationController"] {
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
            let mapped: Int
            if UIAccessibility.isVoiceOverRunning, let chat = chatController(view),
               let node = objectField(view, "target"), isMainHistory(node, chat: chat) {
                switch UIAccessibilityScrollDirection(rawValue: direction) {
                case .next: mapped = UIAccessibilityScrollDirection.down.rawValue
                case .previous: mapped = UIAccessibilityScrollDirection.up.rawValue
                default: mapped = direction
                }
            } else { mapped = direction }
            return original(view, scrollSel, mapped)
        }
        replace(cls, "accessibilityScroll:", scroll, "B@:q")
        let elementsSel = NSSelectorFromString("accessibilityElements")
        let oldElements = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, elementsSel)!), to: (@convention(c) (UIView, Selector) -> NSArray?).self)
        let elements: @convention(block) (UIView) -> NSArray? = { view in
            if UIAccessibility.isVoiceOverRunning, let listNode = field(view, "target"),
               let elements = chatListElements(view, listNode: listNode, chat: chatController(view)) {
                return elements
            }
            return oldElements(view, elementsSel)
        }
        replace(cls, "accessibilityElements", elements, "@@:")
    }
}

@_cdecl("AGStart")
public func AGStart() {
    installTabs()
    installButtons()
    installEscape()
    installNavigationControls()
    installOverlayViews()
    installSupplementalControls()
    installChat()
    installHistoryReading()
    NSLog("[Accessi gram] 0.2.2 loaded; installed %ld target hooks", installed.count)
}

private func objectField(_ object: Any, _ name: String) -> NSObject? {
    field(object, name) as? NSObject
}
private func viewField(_ object: Any, _ name: String) -> UIView? {
    objectField(object, name).flatMap(nodeView)
}
private func attachedNode(_ view: UIView) -> NSObject? {
    let selector = NSSelectorFromString("asyncdisplaykit_node")
    if view.responds(to: selector) { return view.perform(selector)?.takeUnretainedValue() as? NSObject }
    return objectField(view, "node")
}
private func send(_ object: NSObject, _ name: String) -> Bool {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector) else { return false }
    object.perform(selector)
    return true
}
private func className(_ object: NSObject) -> String { NSStringFromClass(type(of: object)) }

private func visible(_ view: UIView, in root: UIView) -> Bool {
    var current: UIView? = view
    while let item = current {
        if item.isHidden || item.alpha <= 0.01 { return false }
        if item === root { return true }
        current = item.superview
    }
    return false
}
private func descendants(_ root: UIView, excluding excluded: UIView? = nil) -> [UIView] {
    var pending = root.subviews
    var result: [UIView] = []
    while let view = pending.popLast() {
        if view === excluded || view.isHidden || view.alpha <= 0.01 { continue }
        result.append(view)
        pending.append(contentsOf: view.subviews)
    }
    return result
}
private func expose(_ view: UIView?, _ label: String, enabled: Bool = true) {
    guard let view else { return }
    view.isAccessibilityElement = true
    view.accessibilityLabel = label
    view.accessibilityTraits.insert(.button)
    if enabled { view.accessibilityTraits.remove(.notEnabled) }
    else { view.accessibilityTraits.insert(.notEnabled) }
}
private func enumCase(_ value: Any?) -> String {
    guard let value else { return "" }
    let mirror = Mirror(reflecting: value)
    return mirror.children.first?.label ?? String(describing: value)
}

private func installNavigationControls() {
    for (name, label) in [
        ("_TtCC19BackButtonComponent19BackButtonComponent4View", "返回"),
        ("_TtCC23ChatListHeaderComponent23ChatListHeaderComponentP33_B8406A80C8FCC8C73D5F3E2E5FB1D7EA14BackButtonView", "返回"),
        ("_TtC10CallScreen14BackButtonView", "返回"),
        ("_TtC10CallScreen15CloseButtonView", "關閉"),
        ("_TtCC30ReactionListContextMenuContent30ReactionListContextMenuContentP33_2EA3F147AC869BE7D75C4A094FF8DBD814BackButtonNode", "返回"),
        ("_TtCC38TranslationLanguagesContextMenuContent38TranslationLanguagesContextMenuContentP33_1DA968BE2B894F7BE6334EFE392759DB14BackButtonNode", "返回")
    ] {
        installButton(name, action: { send($0, "pressed") }, label: { _ in label })
    }
    installButton("_TtC7Display24NavigationBackButtonNode", action: { invoke($0, "pressed") }, label: { _ in "返回" })
    installButton("_TtC21ContextControllerImpl17ContextActionNode", action: { send($0, "buttonPressed") },
                  label: { text(field($0, "textNode")) })
    installButton("_TtC21ContextControllerImpl42ContextControllerActionsListActionItemNode", action: { send($0, "pressed") },
                  label: { text(field($0, "titleLabelNode")) ?? (field($0, "balancedTitleLabel") as? UILabel)?.text })

    target("_TtC17NavigationBarImpl17NavigationBarImpl") { cls in
        let sel = NSSelectorFromString("accessibilityElements")
        let original = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, sel)!), to: (@convention(c) (NSObject, Selector) -> NSArray?).self)
        let getter: @convention(block) (NSObject) -> NSArray? = { bar in
            let existing = original(bar, sel)
            guard UIAccessibility.isVoiceOverRunning, let view = nodeView(bar),
                  let button = viewField(bar, "backButtonNodeImpl"), visible(button, in: view),
                  !button.bounds.isEmpty, field(bar, "backPressed") is () -> Void else { return existing }
            let element = navElement(view, button: button, label: "返回") { [weak bar] in
                guard let bar else { return false }
                return invoke(bar, "backPressed")
            }
            // Prefer the real button's frame over the adjacent title and transition snapshots.
            let remaining = (existing as? [Any] ?? []).filter {
                guard let object = $0 as? NSObject else { return true }
                if object === button || object === objectField(bar, "backButtonNodeImpl") { return false }
                if let item = nodeView(object), item.isDescendant(of: button) { return false }
                return true
            }
            return ([element] as [Any] + remaining) as NSArray
        }
        replace(cls, "accessibilityElements", getter, "@@:")
    }
}

private var navElementKey: UInt8 = 0
private func navElement(_ container: UIView, button: UIView, label: String, action: @escaping () -> Bool) -> ActionElement {
    let element = (objc_getAssociatedObject(container, &navElementKey) as? ActionElement) ?? ActionElement(accessibilityContainer: container)
    objc_setAssociatedObject(container, &navElementKey, element, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    element.accessibilityLabel = label
    element.accessibilityTraits = .button
    element.accessibilityFrameInContainerSpace = container.convert(button.bounds, from: button)
    element.activate = action
    return element
}
private func isModalNode(_ node: NSObject) -> Bool {
    let name = className(node)
    return name == "_TtC7Display24NavigationModalContainer" ||
        name == "_TtC9GalleryUI21GalleryControllerNode" ||
        name == "_TtC7Display19AlertControllerNode" ||
        name == "_TtC15ShareController19ShareControllerNode" ||
        name == "_TtC27ChatEntityKeyboardInputNode27ChatEntityKeyboardInputNode" ||
        name == "_TtC21ContextControllerImpl21ContextControllerNode" ||
        name == "_TtC21ContextControllerImpl42ContextControllerExtractedPresentationNode" ||
        name == "_TtC21ContextControllerImpl18PeekControllerNode" ||
        (name.hasPrefix("_TtCC12AttachmentUI20AttachmentController") && name.hasSuffix("4Node"))
}
private func overlayEscape(_ node: NSObject) -> Bool {
    switch className(node) {
    case "_TtC7Display24NavigationModalContainer":
        guard field(node, "isDismissed") as? Bool != true,
              field(node, "isInteractiveDimissEnabled") as? Bool != false,
              let dismiss = field(node, "interactivelyDismissed") as? (Bool) -> Void else { return false }
        dismiss(false)
        return true
    case "_TtC15ShareController19ShareControllerNode":
        return send(node, "cancelButtonPressed")
    case "_TtC7Display19AlertControllerNode":
        if let dismiss = field(node, "dismiss") as? (Bool) -> Void { dismiss(true); return true }
        return invoke(node, "dismiss")
    case "_TtC27ChatEntityKeyboardInputNode27ChatEntityKeyboardInputNode":
        return invoke(node, "switchToTextInput")
    case "_TtC21ContextControllerImpl21ContextControllerNode":
        return send(node, "dimNodeTapped")
    case "_TtC21ContextControllerImpl18PeekControllerNode":
        return invoke(node, "requestDismiss")
    case "_TtC9GalleryUI21GalleryControllerNode":
        return objectField(node, "galleryController").map { send($0, "donePressed") } ?? false
    default: return false
    }
}
private func installOverlayViews() {
    target("_ASDisplayView") { cls in
        let movedSel = NSSelectorFromString("didMoveToWindow")
        let original = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, movedSel)!), to: (@convention(c) (UIView, Selector) -> Void).self)
        let moved: @convention(block) (UIView) -> Void = { view in
            original(view, movedSel)
            if let node = attachedNode(view), isModalNode(node) {
                view.accessibilityViewIsModal = view.window != nil
            }
        }
        replace(cls, "didMoveToWindow", moved, "v@:")
        let old = originalBool(cls, "accessibilityPerformEscape")
        let escape: @convention(block) (UIView) -> Bool = { view in
            if old?(view) == true { return true }
            guard UIAccessibility.isVoiceOverRunning, let node = attachedNode(view), isModalNode(node) else { return false }
            return overlayEscape(node)
        }
        replace(cls, "accessibilityPerformEscape", escape, "B@:")
    }
}

private func updateInput(_ panel: NSObject) {
    if let attachment = viewField(panel, "attachmentButton") {
        expose(attachment, "附件", enabled: !attachment.accessibilityTraits.contains(.notEnabled))
    }
    let input = viewField(panel, "richTextInputNode")
    if let editor = input.flatMap({ root in
        (root as? UITextView) ?? descendants(root).compactMap { $0 as? UITextView }.first
    }) {
        editor.accessibilityLabel = "訊息輸入框"
    }
    for pair in list(field(panel, "accessoryItemButtons")) {
        let values = Array(Mirror(reflecting: pair).children)
        guard values.count == 2, let button = values[1].value as? UIView else { continue }
        let item = values[0].value
        let kind = enumCase(item)
        switch kind {
        case "input", "botInput":
            let data = Mirror(reflecting: item).children.first?.value
            let parts = list(data)
            switch enumCase(parts.last) {
            case "keyboard": expose(button, "切換到鍵盤")
            case "stickers": expose(button, "貼圖")
            case "emoji": expose(button, "表情符號")
            case "bot": expose(button, "機器人鍵盤")
            default: break
            }
        case "commands": expose(button, "指令")
        case "scheduledMessages": expose(button, "排程訊息")
        case "gift": expose(button, "送禮")
        case "messageAutoremoveTimeout": expose(button, "自動刪除時間")
        case "silentPost": expose(button, "切換靜音傳送")
        default: break
        }
    }
    for name in ["sendActionButtons", "mediaActionButtons"] {
        guard let actions = objectField(panel, name) else { continue }
        let sendLabel = field(actions, "sendButtonHasApplyIcon") as? Bool == true ? "確認編輯" : "傳送訊息"
        expose(viewField(actions, "sendButton"), sendLabel, enabled: field(actions, "isSendDisabled") as? Bool != true)
        if let mic = objectField(actions, "micButton") {
            let video = enumCase(field(mic, "mode")).lowercased().contains("video")
            if let micView = nodeView(mic) {
                expose(micView, video ? "錄製視訊訊息" : "錄製語音訊息")
                let name = video ? "切換到語音錄製" : "切換到視訊錄製"
                if micView.accessibilityCustomActions?.first?.name != name {
                    micView.accessibilityCustomActions = [UIAccessibilityCustomAction(name: name) { [weak mic] _ in
                        guard let mic else { return false }
                        return invoke(mic, "switchMode")
                    }]
                }
            }
        }
    }
}

private let messageMenuLabels: [(String, Set<String>)] = [
    ("複製", ["複製", "复制", "copy", "複製文字", "复制文本", "copy text"]),
    ("轉發", ["轉發", "轉傳", "转发", "forward", "forward message"]),
    ("刪除", ["刪除", "删除", "delete", "delete message"])
]
private var menuRequestKey: UInt8 = 0
private final class MenuRequest: NSObject {}
private func menuRows(_ window: UIWindow) -> [(UIView, NSObject, String)] {
    descendants(window).compactMap { view in
        guard let node = attachedNode(view) else { return nil }
        let name = className(node)
        guard name == "_TtC21ContextControllerImpl17ContextActionNode" ||
            name == "_TtC21ContextControllerImpl42ContextControllerActionsListActionItemNode" else { return nil }
        let title = text(field(node, "titleLabelNode")) ?? text(field(node, "textNode")) ?? view.accessibilityLabel ?? ""
        return (view, node, title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
private func performMenuAction(_ names: Set<String>, area: UIView, item: NSObject, options: UIAccessibilityCustomAction) -> Bool {
    guard let window = area.window else { return false }
    let previous = Set(menuRows(window).map { ObjectIdentifier($0.0) })
    let request = MenuRequest()
    objc_setAssociatedObject(window, &menuRequestKey, request, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    item.perform(NSSelectorFromString("performLocalAccessibilityCustomAction:"), with: options)
    func complete(_ retries: Int) {
        guard objc_getAssociatedObject(window, &menuRequestKey) as? MenuRequest === request else { return }
        let rows = menuRows(window).filter { !previous.contains(ObjectIdentifier($0.0)) }
        if let match = rows.first(where: { names.contains($0.2) }) {
            objc_setAssociatedObject(window, &menuRequestKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            _ = send(match.1, "pressed") || send(match.1, "buttonPressed")
        } else if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { complete(retries - 1) }
        } else {
            objc_setAssociatedObject(window, &menuRequestKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    complete(8)
    return true
}
private func updateMessage(_ item: NSObject) {
    guard let area = viewField(item, "messageAccessibilityArea"), let data = field(item, "accessibilityData") else { return }
    if let label = field(data, "label") as? String, !label.isEmpty {
        let author = text(field(item, "nameNode"))
        let reply = field(item, "replyInfoNode")
        let quote = reply.flatMap { text(field($0, "textNode")) }
        let content = field(data, "value") as? String
        let date = field(item, "dateAndStatusNode") ?? list(field(item, "contentNodes")).compactMap { field($0, "dateAndStatusNode") }.first
        let time = date.flatMap { text(field($0, "dateNode")) }
        if let author, !author.isEmpty, !label.hasPrefix(author) {
            area.accessibilityLabel = "\(author)，\(label)"
        }
        if let quote, !quote.isEmpty, !(content?.contains(quote) ?? false), !label.contains(quote) {
            let sender = author.flatMap { $0.isEmpty ? nil : $0 }
            let body = sender == label ? nil : label
            area.accessibilityLabel = [sender, "引用：\(quote)", body].compactMap { $0 }.joined(separator: "，")
        }
        if let time, !time.isEmpty, !(content?.contains(time) ?? false) {
            area.accessibilityValue = [content, time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
        }
    }
    for name in ["shadowNode", "backgroundWallpaperNode", "ephemeralBadgeIconNode", "replyBackgroundNode"] {
        viewField(item, name)?.accessibilityElementsHidden = true
    }
    let existing = (area.accessibilityCustomActions ?? []).filter { action in !messageMenuLabels.contains { $0.0 == action.name } }
    guard let options = existing.first(where: { enumCase(field($0, "action")) == "options" }),
          item.responds(to: NSSelectorFromString("performLocalAccessibilityCustomAction:")) else { return }
    area.accessibilityCustomActions = existing + messageMenuLabels.map { name, titles in
        UIAccessibilityCustomAction(name: name) { [weak area, weak item] _ in
            guard let area, let item else { return false }
            return performMenuAction(titles, area: area, item: item, options: options)
        }
    }
}

private enum HistoryDirection {
    case older, newer
}

private final class HistoryReading: NSObject {
    weak var focusedRow: UIView?
    var direction: HistoryDirection?
    var generation = 0
    var lastFrame: CGRect?
}
private var historyReadingKey: UInt8 = 0

private func installHistoryReading() {
    NotificationCenter.default.addObserver(
        forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main
    ) { notification in
        guard UIAccessibility.isVoiceOverRunning else { return }
        let element = notification.userInfo?[UIAccessibility.focusedElementUserInfoKey]
        guard let focus = element as? UIView ?? (element as? UIAccessibilityElement)?.accessibilityContainer as? UIView,
              let view = historyBackingView(focus), let chat = chatController(view),
              let listNode = objectField(view, "target"), isMainHistory(listNode, chat: chat),
              let row = list(field(listNode, "itemNodes")).compactMap({ ($0 as? NSObject).flatMap(nodeView) }).first(where: {
                  focus === $0 || focus.isDescendant(of: $0)
              }) else { return }
        let reading = (objc_getAssociatedObject(view, &historyReadingKey) as? HistoryReading) ?? HistoryReading()
        objc_setAssociatedObject(view, &historyReadingKey, reading, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        guard let window = view.window, row !== reading.focusedRow else { return }

        let bounds = historyBounds(view, chat: chat)
        let frame = window.convert(row.bounds, from: row)
        let rows = historyRows(view, listNode, bounds)
        if let previous = reading.focusedRow, previous.window === window, previous.isDescendant(of: view) {
            let previousY = window.convert(previous.bounds, from: previous).midY
            if abs(frame.midY - previousY) > 1 {
                reading.direction = frame.midY < previousY ? .older : .newer
            }
        } else if !rows.isEmpty {
            if row === rows.first?.1 { reading.direction = .older }
            else if row === rows.last?.1 { reading.direction = .newer }
            else { reading.direction = nil }
        }
        reading.focusedRow = row
        reading.generation += 1
        reading.lastFrame = nil
        state(chat).pendingLatest = false

        guard let direction = reading.direction else { return }
        let generation = reading.generation
        DispatchQueue.main.async { [weak view, weak chat, weak row, weak reading] in
            guard let view, let chat, let row, let reading else { return }
            bufferHistory(view, chat: chat, row: row, reading: reading, direction: direction,
                          generation: generation, previousWindow: nil, deadline: ProcessInfo.processInfo.systemUptime + 12)
        }
    }
}

private func historyBackingView(_ focus: UIView) -> UIView? {
    var view: UIView? = focus
    while let current = view {
        if className(current) == "_TtC7Display19ListViewBackingView" { return current }
        view = current.superview
    }
    return nil
}

private func isMainHistory(_ listNode: NSObject, chat: UIViewController) -> Bool {
    guard let node = chatNode(chat), let history = field(node, "historyNode") else { return false }
    return objectField(history, "listView") === listNode
}

private struct HistoryWindow: Equatable {
    let location: Int?
    let count: Int
    let first: ObjectIdentifier?
    let last: ObjectIdentifier?
}

private func bufferHistory(_ view: UIView, chat: UIViewController, row: UIView,
                           reading: HistoryReading, direction: HistoryDirection,
                           generation: Int, previousWindow: HistoryWindow?, deadline: TimeInterval) {
    guard reading.generation == generation, reading.focusedRow === row,
          UIAccessibility.isVoiceOverRunning, let window = view.window, visible(row, in: view),
          let focused = UIAccessibility.focusedElement(using: .notificationVoiceOver),
          let focus = focused as? UIView ?? (focused as? UIAccessibilityElement)?.accessibilityContainer as? UIView,
          focus === row || focus.isDescendant(of: row),
          let listNode = objectField(view, "target"), isMainHistory(listNode, chat: chat),
          let scroller = objectField(listNode, "scroller") as? UIScrollView,
          !scroller.isTracking, !scroller.isDragging, !scroller.isDecelerating,
          let node = chatNode(chat), let history = field(node, "historyNode") else { return }

    let bounds = historyBounds(view, chat: chat)
    let frame = window.convert(row.bounds, from: row)
    let distanceToEdge = direction == .older ? frame.minY - bounds.minY : bounds.maxY - frame.maxY
    guard frame.intersects(bounds), distanceToEdge < bounds.height * 0.30 else { return }

    let items = field(listNode, "items") as? [Any] ?? []
    let rows = historyRows(view, listNode, bounds)
    let rowPosition = rows.firstIndex { $0.1 === row }
    let neighbors = rowPosition.map { direction == .older ? $0 : rows.count - $0 - 1 } ?? 0
    let historyView = field(history, "historyView")
    let original = historyView.flatMap { field($0, "originalView") }
    let hasMore = original.map {
        field($0, direction == .older ? "earlierId" : "laterId") != nil ||
        field($0, direction == .older ? "holeEarlier" : "holeLater") as? Bool == true
    } ?? false
    let item = attachedNode(row)
    let index = item.flatMap { field($0, "index") as? Int }
    let rotated = field(listNode, "rotated") as? Bool == true
    let towardHigherIndex = (direction == .older) == rotated
    let hasLoadedNeighbor = index.map { towardHigherIndex ? $0 + 1 < items.count : $0 > 0 } ?? false
    guard hasLoadedNeighbor || hasMore else { return }
    let mounted = list(field(listNode, "itemNodes")).compactMap { $0 as? NSObject }
    let currentWindow = HistoryWindow(
        location: field(history, "chatHistoryLocationValue").flatMap { field($0, "id") as? Int },
        count: items.count,
        first: mounted.first.map(ObjectIdentifier.init),
        last: mounted.last.map(ObjectIdentifier.init)
    )

    if currentWindow != previousWindow || reading.lastFrame != frame {
        reading.lastFrame = frame
        // Move by part of a screen and keep the focused bubble on screen.
        // ListView's UIScrollView delegate updates native visible ranges and requests history.
        let retained = min(52, frame.height * 0.5)
        let available = direction == .older ? bounds.maxY - frame.minY - retained : frame.maxY - bounds.minY - retained
        let needed = direction == .older ? bounds.minY + bounds.height * 0.36 - frame.minY : frame.maxY - (bounds.maxY - bounds.height * 0.36)
        let distance = min(max(bounds.height * 0.36, needed), available)
        let sign: CGFloat = towardHigherIndex ? 1 : -1
        let offset = scroller.contentOffset
        let minimum = -scroller.adjustedContentInset.top
        let maximum = max(minimum, scroller.contentSize.height - scroller.bounds.height + scroller.adjustedContentInset.bottom)
        let target = min(maximum, max(minimum, offset.y + sign * distance))
        if distance > 1, abs(target - offset.y) > 1 {
            scroller.setContentOffset(CGPoint(x: offset.x, y: target), animated: false)
        }
    }
    // While the focused message still borders an unloaded window, give Telegram time
    // to apply it. The notification for the next real message cancels this wait.
    if neighbors < 2, ProcessInfo.processInfo.systemUptime < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak view, weak chat, weak row, weak reading] in
            guard let view, let chat, let row, let reading else { return }
            bufferHistory(view, chat: chat, row: row, reading: reading, direction: direction,
                          generation: generation, previousWindow: currentWindow, deadline: deadline)
        }
    }
}

private func historyBounds(_ view: UIView, chat: UIViewController?) -> CGRect {
    var bounds = view.window?.convert(view.bounds, from: view) ?? view.bounds
    if let chat, let node = chatNode(chat) {
        for name in ["textInputPanelNode", "inputPanelNode", "inputNode", "inputPanelContainerNode"] {
            guard let panel = viewField(node, name), visible(panel, in: chat.view) else { continue }
            let frame = view.window?.convert(panel.bounds, from: panel) ?? .zero
            if frame.height > 0, frame.minY > bounds.midY, frame.minY < bounds.maxY { bounds.size.height = frame.minY - bounds.minY }
        }
    } else if let window = view.window {
        for bar in descendants(window, excluding: view) where bar is UITabBar || className(bar) == "_TtCC15TabBarComponent15TabBarComponent4View" {
            let frame = window.convert(bar.bounds, from: bar)
            if frame.intersects(bounds), frame.minY > bounds.midY { bounds.size.height = frame.minY - bounds.minY }
        }
    }
    return bounds
}
private func historyRows(_ view: UIView, _ listNode: Any, _ bounds: CGRect) -> [(NSObject, UIView, CGRect)] {
    list(field(listNode, "itemNodes")).compactMap { raw -> (NSObject, UIView, CGRect)? in
        guard let item = raw as? NSObject, let row = nodeView(item), visible(row, in: view) else { return nil }
        let rect = view.window?.convert(row.bounds, from: row) ?? view.convert(row.bounds, from: row)
        guard !rect.isEmpty, rect.intersects(bounds) else { return nil }
        let exposedHeight = rect.intersection(bounds).height
        guard rect.midY >= bounds.minY && rect.midY < bounds.maxY ||
                (rect.height >= bounds.height && exposedHeight >= bounds.height * 0.5) else { return nil }
        return (item, row, rect)
    }.sorted { $0.2.minY < $1.2.minY }
}
private func chatListElements(_ view: UIView, listNode: Any, chat: UIViewController?) -> NSArray? {
    if let chat, let listNode = listNode as? NSObject, !isMainHistory(listNode, chat: chat) { return nil }
    let bounds = historyBounds(view, chat: chat)
    let rows = historyRows(view, listNode, bounds)
    guard let chat else {
        let isChatList = list(field(listNode, "itemNodes")).contains { item in
            (item as? NSObject).map { className($0).hasSuffix("ChatListItemNode") } ?? false
        }
        return isChatList ? rows.map { $0.1 } as NSArray : nil
    }
    if let scroller = objectField(listNode, "scroller") as? UIScrollView {
        scroller.isAccessibilityElement = false
        scroller.accessibilityElementsHidden = true
    }
    if let node = chatNode(chat) {
        if let panel = objectField(node, "inputNode"), let front = nodeView(panel), isModalNode(panel), visible(front, in: chat.view) {
            front.accessibilityViewIsModal = true
            return [] as NSArray
        }
        if let input = objectField(node, "textInputPanelNode") { updateInput(input) }
        if let navigation = objectField(node, "navigateButtons"), let buttons = nodeView(navigation), let container = buttons.superview {
            buttons.accessibilityElementsHidden = false
            buttons.accessibilityElements = ["downButton", "upButton", "mentionsButton", "reactionsButton", "pollVotesButton"].compactMap { name in
                viewField(navigation, name)
            }.filter { visible($0, in: container) && !$0.bounds.isEmpty }
        }
    }
    guard !rows.isEmpty else { return [] as NSArray }
    for row in rows { updateMessage(row.0) }
    return rows.map { $0.1 } as NSArray
}

private func nearestNode(_ view: UIView?, matching name: String) -> NSObject? {
    var current = view
    while let view = current {
        if let node = attachedNode(view), className(node) == name { return node }
        current = view.superview
    }
    return nil
}
private func browserButtonLabel(_ object: NSObject) -> String? {
    guard let view = object as? UIView else { return nil }
    for image in descendants(view) where className(image) == "_TtCC19BundleIconComponent19BundleIconComponent4View" {
        guard let component = field(image, "component"), let icon = field(component, "name") as? String else { continue }
        switch icon {
        case "Navigation/Close", "Instant View/Close": return "關閉"
        case "Instant View/Back": return "返回上一頁"
        case "Instant View/Forward": return "前往下一頁"
        default: continue
        }
    }
    return nil
}
private func installSupplementalControls() {
    target("_TtCC20PlainButtonComponent20PlainButtonComponent4View") { cls in
        let oldElement = originalBool(cls, "isAccessibilityElement")
        let oldActivate = originalBool(cls, "accessibilityActivate")
        let isElement: @convention(block) (NSObject) -> Bool = { object in
            if UIAccessibility.isVoiceOverRunning, browserButtonLabel(object) != nil { return true }
            return oldElement?(object) ?? false
        }
        let activate: @convention(block) (NSObject) -> Bool = { object in
            if UIAccessibility.isVoiceOverRunning, browserButtonLabel(object) != nil {
                if let component = field(object, "component"), field(component, "isEnabled") as? Bool == false { return false }
                return send(object, "pressed")
            }
            return oldActivate?(object) ?? false
        }
        let labelSel = NSSelectorFromString("accessibilityLabel")
        let labelOriginal = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, labelSel)!), to: (@convention(c) (NSObject, Selector) -> NSString?).self)
        let label: @convention(block) (NSObject) -> NSString? = { object in
            if UIAccessibility.isVoiceOverRunning, let value = browserButtonLabel(object) { return value as NSString }
            return labelOriginal(object, labelSel)
        }
        let traitsSel = NSSelectorFromString("accessibilityTraits")
        let traitsOriginal = unsafeBitCast(method_getImplementation(class_getInstanceMethod(cls, traitsSel)!), to: (@convention(c) (NSObject, Selector) -> UInt64).self)
        let traits: @convention(block) (NSObject) -> UInt64 = { object in
            var result = UIAccessibilityTraits(rawValue: traitsOriginal(object, traitsSel))
            if UIAccessibility.isVoiceOverRunning, browserButtonLabel(object) != nil {
                result.insert(.button)
                if let component = field(object, "component"), field(component, "isEnabled") as? Bool == false { result.insert(.notEnabled) }
            }
            return result.rawValue
        }
        replace(cls, "isAccessibilityElement", isElement, "B@:")
        replace(cls, "accessibilityActivate", activate, "B@:")
        replace(cls, "accessibilityLabel", label, "@@:")
        replace(cls, "accessibilityTraits", traits, "Q@:")
    }
    installButton("_TtC7Display26TextAlertContentActionNode", action: {
        field($0, "actionEnabled") as? Bool != false && send($0, "pressed")
    }, label: {
        guard let action = field($0, "action") else { return nil }
        return field(action, "title") as? String
    })
    installButton("_TtC15ShareControllerP33_8BC0A62A8A0E545842FF4152006F0A2216CancelButtonNode", action: {
        nearestNode(nodeView($0), matching: "_TtC15ShareController19ShareControllerNode").map { send($0, "cancelButtonPressed") } ?? false
    }, label: { text(field($0, "labelNode")) ?? "關閉分享" })
    installButton("_TtC15ShareController21ShareActionButtonNode", action: {
        nearestNode(nodeView($0), matching: "_TtC15ShareController19ShareControllerNode").map { send($0, "actionButtonPressed") } ?? false
    }, label: { text(field($0, "badgeLabel")) ?? "分享" })
    installButton("_TtC10TelegramUI31ChatHistoryNavigationButtonNode", action: {
        field($0, "isEnabled") as? Bool != false && invoke($0, "tapped")
    }, label: { object in
        switch enumCase(field(object, "type")) {
        case "down": return "跳到最新訊息"
        case "up": return "上一筆搜尋結果"
        case "mentions": return "跳到提及你的訊息"
        case "reactions": return "跳到新回應"
        case "pollVotes": return "跳到新投票"
        default: return nil
        }
    })
    installButton("_TtC33ChatTextInputMediaRecordingButton33ChatTextInputMediaRecordingButton", action: { object in
        if field(object, "hasRecorder") as? Bool == true { return send(object, "handleStopTap") }
        guard send(object, "micButtonInteractionBegan") else { return false }
        _ = send(object, "micButtonInteractionLocked")
        return true
    }, label: { object in
        if field(object, "hasRecorder") as? Bool == true { return "停止錄製" }
        return enumCase(field(object, "mode")).lowercased().contains("video") ? "錄製視訊訊息" : "錄製語音訊息"
    })
}
