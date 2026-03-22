import AppKit

struct WindowModel {
    var pid: pid_t
    var windowElement: AXUIElement
    var title: String
    var frame: CGRect
    var screen: NSScreen
    var appName: String
}
