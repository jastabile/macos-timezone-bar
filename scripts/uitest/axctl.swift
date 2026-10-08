// Tiny Accessibility CLI used by scripts/ui-test.sh to drive TimeZoneBar.
// Requires the calling terminal app to have Accessibility permission.
//
//   axctl open-panel                 click the menu bar item (opens/closes the panel)
//   axctl menubar                    print the status item frame
//   axctl window                     print the panel window frame (x y w h), or "none"
//   axctl dump                       print role | identifier | value for every element
//   (an <identifier> may be written id#n to mean its n-th child)
//   axctl get <identifier>           print the element's value (or title/description)
//   axctl set <identifier> <value>   set AXValue (number if numeric, otherwise string)
//   axctl press <identifier>         perform AXPress
//   axctl frame <identifier>         print x y w h
//   axctl drag x1 y1 x2 y2           real mouse drag (CGEvents) in global coordinates
//   axctl key return|escape          post a key press
//   axctl type <identifier> <text>   focus a text field and type text with real key events
//   axctl menu <identifier> <item>   open the context menu of an element and choose an item
import AppKit
import ApplicationServices

let bundleID = "com.timezonebar.TimeZoneBar"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard AXIsProcessTrusted() else { fail("Accessibility permission missing for this terminal") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("TimeZoneBar is not running")
}
let appElement = AXUIElementCreateApplication(app.processIdentifier)

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

func describe(_ e: AXUIElement) -> String {
    for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let v = attr(e, key) {
            let s = "\(v)"
            if !s.isEmpty { return s }
        }
    }
    return ""
}

func frame(_ e: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}

func walk(_ e: AXUIElement, depth: Int = 0, _ visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(e, depth) { return true }
    for c in children(e) where walk(c, depth: depth + 1, visit) { return true }
    return false
}

/// The panel window, ignoring windows parked off-screen (SwiftUI may keep a hidden one around).
func panelWindow() -> AXUIElement? {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let screens = NSScreen.screens.map { s in
        CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
    }
    return ((attr(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first { w in
        screens.contains { $0.intersects(frame(w)) }
    }
}

/// Finds an element by AXIdentifier; "id#2" means the 2nd child of that element.
func find(_ spec: String) -> AXUIElement {
    let parts = spec.split(separator: "#")
    if parts.count == 2, let n = Int(parts[1]) {
        let kids = children(find(String(parts[0])))
        guard n >= 1, n <= kids.count else { fail("\(spec): no child \(n)") }
        return kids[n - 1]
    }
    let identifier = spec
    guard let window = panelWindow() else { fail("panel is not open") }
    var found: AXUIElement?
    _ = walk(window) { e, _ in
        if (attr(e, "AXIdentifier") as? String) == identifier { found = e; return true }
        return false
    }
    guard let f = found else { fail("no element with identifier \(identifier)") }
    return f
}

func statusItem() -> AXUIElement {
    guard let bar = attr(appElement, "AXExtrasMenuBar"), let item = children(bar as! AXUIElement).first else {
        fail("no menu bar item")
    }
    return item
}

func mouse(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}

func printFrame(_ r: CGRect) { print(Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)) }

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "open-panel":
    AXUIElementPerformAction(statusItem(), kAXPressAction as CFString)
case "menubar":
    printFrame(frame(statusItem()))
case "window":
    if let w = panelWindow() { printFrame(frame(w)) } else { print("none") }
case "dump":
    guard let window = panelWindow() else { fail("panel is not open") }
    _ = walk(window) { e, depth in
        let role = attr(e, kAXRoleAttribute) as? String ?? "?"
        let id = attr(e, "AXIdentifier") as? String ?? ""
        print(String(repeating: "  ", count: depth) + "\(role) | \(id) | \(describe(e).replacingOccurrences(of: "\n", with: " "))")
        return false
    }
case "get" where args.count == 2:
    print(describe(find(args[1])))
case "set" where args.count == 3:
    let e = find(args[1])
    let value: CFTypeRef = Double(args[2]).map { NSNumber(value: $0) } ?? args[2] as NSString
    let err = AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, value)
    if err != .success { fail("set failed: \(err.rawValue)") }
case "press" where args.count == 2:
    let err = AXUIElementPerformAction(find(args[1]), kAXPressAction as CFString)
    if err != .success { fail("press failed: \(err.rawValue)") }
case "frame" where args.count == 2:
    printFrame(frame(find(args[1])))
case "drag" where args.count == 5:
    let n = args[1...].map { CGFloat(Double($0)!) }
    let from = CGPoint(x: n[0], y: n[1]), to = CGPoint(x: n[2], y: n[3])
    mouse(.mouseMoved, from); usleep(150_000)
    mouse(.leftMouseDown, from); usleep(300_000)
    let steps = 40
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(30_000)
    }
    usleep(300_000)
    mouse(.leftMouseUp, to)
case "key" where args.count == 2:
    let code: CGKeyCode = args[1] == "escape" ? 53 : 36
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!.post(tap: .cghidEventTap)
        usleep(30_000)
    }
case "type" where args.count == 3:
    AXUIElementSetAttributeValue(find(args[1]), kAXFocusedAttribute as CFString, kCFBooleanTrue)
    usleep(200_000)
    for scalar in args[2].utf16 {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            var c = scalar
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e.post(tap: .cghidEventTap)
            usleep(15_000)
        }
    }
case "menu" where args.count == 3:
    let e = find(args[1])
    AXUIElementPerformAction(e, kAXShowMenuAction as CFString)
    usleep(400_000)
    var chosen = false
    _ = walk(appElement) { m, _ in
        if (attr(m, kAXRoleAttribute) as? String) == kAXMenuItemRole, (attr(m, kAXTitleAttribute) as? String) == args[2] {
            AXUIElementPerformAction(m, kAXPressAction as CFString)
            chosen = true
            return true
        }
        return false
    }
    if !chosen { fail("menu item \(args[2]) not found") }
default:
    fail("usage: see header of axctl.swift")
}
