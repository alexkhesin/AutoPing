// TODO: draw the two lines using some other mechanism so that
//  (a) don't have to do cheezy shift-bounds-by-3
//  (b) can center the single-line case properly
// TODO: allow specifying IPv6
// TODO: in IPV6 case, remove ip and ICMP headers in validatePing6ResponsePacket
// TODO: how to publish in appstore
// TODO: better colors https://developer.apple.com/design/human-interface-guidelines/macos/visual-design/color/
// TODO: instead of try?, show errors from SMAppService.mainApp.register
// TODO: make TextField in SettingsView be focused and respond to Cmd+A

// Need to worry about multithreading? https://lists.apple.com/archives/macnetworkprog/2009/Feb/msg00047.html can be interpreted as saying that CFSocket polls on a single thread and thus all (most? non-error?) SimpePing calbacks should be delivered on a single thread

// 2025-05-04: evaluated SwiftyPing library. Critical flaw is that it only allows one outstanding ping at a time because
//  it keeps ping start time (sequenceStart) in a local variable instead of sending it with ICMP packets. This
//  causes pings to be sent at irregular intervals, messing up statistical observations.

import SwiftUI
import SwiftData
import OSLog
import ServiceManagement

@main
struct autopingApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {}
}

// A lot of this came from https://nilcoalescing.com/blog/LaunchAtLoginSetting/
struct SettingsView: View {
  @Environment(\.appearsActive) private var appearsActive
  @AppStorage("hostName") static var hostName = "8.8.8.8"
  // This is not AppStorage because it is "stored" via System Settings vis SMAppService
  @State private var launchAtLogin = false
  
  var body: some View {
    Form {
      TextField("Host or IP", text: SettingsView.$hostName)
      Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.switch)
    }
    .padding()
    .frame(minWidth: 300) // Set a minimum size for the window
    .onChange(of: launchAtLogin) { _, newValue in
      if newValue == true {
        try? SMAppService.mainApp.register()
      } else {
        try? SMAppService.mainApp.unregister()
      }
    }
    .onAppear {
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    // Update in case user changed this through System Settings
    .onChange(of: appearsActive) { _, newValue in
      guard newValue else { return }
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
#Preview { SettingsView() }

class AppDelegate : NSObject, NSApplicationDelegate {
  static let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "default")
  
  private let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Preferences", action: #selector(preferencesAction(_:)), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction(_:)), keyEquivalent: ""))
    
    statusBarItem.menu = menu
    
    showPingData(avg: -1, percentFailed: 0)  // draw infinity at first
    start()
  }
  
  @objc private func preferencesAction(_ sender: Any?) {
    showPreferences()
  }
  
  @objc private func quitAction(_ sender: Any?) {
    stop()
    NSApplication.shared.terminate(self)
  }
  
  private var pingManager: PingManager?
  
  func start() {
    pingManager = PingManager(self, SettingsView.hostName)
  }
  
  func stop() {
    pingManager?.stop()
    pingManager = nil
    AppDelegate.log.info("stopped")
  }
  
  // for NSWindowDelegate extension below
  private var settingsWindowController: NSWindowController?
  private var settingsWindowHostingController: NSHostingController<SettingsView>?
}

protocol PingDisplay {
  func showPingData(avg : Int, percentFailed : Int)
}

extension AppDelegate : PingDisplay {
  func showPingData(avg : Int, percentFailed : Int) {
    var s: String
    var singleLine = true
    enum Level { case ok, warning, broken }
    var level = Level.ok
    if avg == -1 {
      s = "\u{221e}"  // infinity sigb
      level = Level.broken
    } else {
      s = "\(avg) ms"
      if (avg > 200) {
        level = Level.warning
      }
      if percentFailed > 0 {
        s += "\n\(percentFailed)%"
        singleLine = false
        if (percentFailed > 5) {
          level = Level.warning
        }
      }
    }
    
    // Orange looks better than red or yellow on my screen, but really
    // TODO: how do I do it properly?
    let color : NSColor = {
      switch level {
      case .ok: return NSColor.controlTextColor
      case .warning: return NSColor.systemOrange
      case .broken: return NSColor.systemRed
      }
    }()
    
    let button = statusBarItem.button!
    button.attributedTitle = NSAttributedString(
      string: s,
      attributes: [
        NSAttributedString.Key.font: singleLine ? AppDelegate.fontOneLine : AppDelegate.fontTwoLines,
        NSAttributedString.Key.foregroundColor : color,
        NSAttributedString.Key.paragraphStyle : singleLine ? AppDelegate.styleOneLine : AppDelegate.styleTwoLines,
        // TODO: No idea why -4 happens to work, and whether it may break
        // in future versions. Something complicated about autolayout.
        NSAttributedString.Key.baselineOffset: singleLine ? 0 : -4])
  }
  
  static let fontOneLine = NSFont.menuBarFont(ofSize:0)  // default size
  static let fontTwoLines : NSFont = {
    let height = NSStatusBar.system.thickness
    // leave 2 points margin on both sides and divide the rest between the two lines
    return NSFont.menuBarFont(ofSize: (height - 4)/2)
  }()
  static let styleOneLine = NSParagraphStyle.default
  static let styleTwoLines : NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    // No descenders or ascenders, do not leave space for them
    style.maximumLineHeight = fontTwoLines.pointSize
    style.lineSpacing = 1  // but do leave a bit of space between the two lines
    return style
  }()
}

// AI generated code (vua Gemini), in response to the prompt:
// "in swiftui, how do I show a window from appdelegate", which initially led
// to EXC_BAD_ACCESS, and after a few interactions asking to fix it, this came
// out.
extension AppDelegate : NSWindowDelegate {
  func showPreferences() {
    // Check if the window controller's window already exists and is visible
    if let existingWindow = settingsWindowController?.window, existingWindow.isVisible {
      existingWindow.makeKeyAndOrderFront(nil)
      return
    }
    
    // Create an NSHostingController to host SettingsView
    self.settingsWindowHostingController = NSHostingController(rootView: SettingsView())
    
    let window = NSWindow(
      // contentRect does not seem to matter, the size appears to be determined by
      // frame dimensions in SettingsView
      contentRect: CGRect(),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    // window.setFrameAutosaveName("MyNewSwiftUIWindow") // Optional: Save window position
    window.contentViewController = self.settingsWindowHostingController // Set the hosting controller
    window.title = "Preferences"
    
    // Crucially, set isReleasedWhenClosed to false because we are managing its lifecycle.
    window.isReleasedWhenClosed = false
    
    // Set AppDelegate as the window's delegate
    window.delegate = self
    
    // Create and store the window controller
    self.settingsWindowController = NSWindowController(window: window)
    
    window.level = NSWindow.Level.tornOffMenu // makes it system-modal
    // Does not seem to work
    window.center() // Center the window on the screen
    self.settingsWindowController!.showWindow(nil) // This also makes it key and orders front.
  }
  
  func windowWillClose(_ notification: Notification) {
    // This method is called when the window is about to close.
    // We check if the closing window is the one managed by our windowController.
    if let closingWindow = notification.object as? NSWindow, closingWindow == self.settingsWindowController?.window {
      self.settingsWindowController = nil
      self.settingsWindowHostingController = nil
      stop()
      start()
    }
  }
}
