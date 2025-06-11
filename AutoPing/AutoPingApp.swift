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
import Sparkle
import UserNotifications

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
  private var updaterController: SPUStandardUpdaterController!

  override init() {
    super.init()
    // Initialize the updater controller, which handles the Sparkle updater
    updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Preferences",
                            action: #selector(preferencesAction(_:)),
                            keyEquivalent: ""))
    let m = NSMenuItem(title: "Check for Updates",
                       action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                       keyEquivalent: "")
    m.target = updaterController
    menu.addItem(m)
    menu.addItem(NSMenuItem(title: "Quit",
                            action: #selector(quitAction(_:)),
                            keyEquivalent: ""))
    
    statusBarItem.menu = menu
    
    // Make the app run in the background
    NSApp.setActivationPolicy(.accessory)
    UNUserNotificationCenter.current().delegate = self
    
    showPingData(avg: -1, percentFailed: 0)  // draw infinity at first
    start()
  }
  
  @objc private func preferencesAction(_ sender: Any?) {
    showPreferences()
  }

  @objc private func updatesAction(_ sender: Any?) {
    // showPreferences()
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

let UPDATE_NOTIFICATION_IDENTIFIER = "UpdateCheck"

// From https://sparkle-project.org/documentation/gentle-reminders/
extension AppDelegate : SPUUpdaterDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
  // MARK: SPUStandardUserDriverDelegate
  
  // Declares that we support gentle scheduled update reminders to Sparkle's standard user driver
  var supportsGentleScheduledUpdateReminders: Bool {
    return true
  }
  
  func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
    // If the standard user driver will show the update in immediate focus (e.g. near app launch),
    // then let Sparkle take care of showing the update.
    // Otherwise we will handle showing any other scheduled updates
    AppDelegate.log.info(">>> standardUserDriverShouldHandleShowingScheduledUpdate: \(immediateFocus)")
    return immediateFocus
  }

  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    AppDelegate.log.info(">>> standardUserDriverWillHandleShowingUpdate: \(handleShowingUpdate), \(state.userInitiated)")
    /*
    // We will ignore updates that the user driver will handle showing
    // This includes user initiated (non-scheduled) updates
    guard !handleShowingUpdate else {
      return
    }
     
    // Attach a gentle UI indicator on our window
    do {
      let updateButton = NSButton(frame: NSMakeRect(0, 0, 120, 100))
      updateButton.title = "v\(update.displayVersionString) Available"
      updateButton.bezelStyle = .recessed
      updateButton.target = updaterController
      updateButton.action = #selector(updaterController.checkForUpdates(_:))
          
      let accessoryViewController = NSTitlebarAccessoryViewController()
      accessoryViewController.layoutAttribute = .right
      accessoryViewController.view = updateButton
          
      self.window.addTitlebarAccessoryViewController(accessoryViewController)
          
      titlebarAccessoryViewController = accessoryViewController
    }
    */

    // When an update alert will be presented, place the app in the foreground
    // We will do this for updates the user initiated themselves too for consistency
    // When we later post a notification, the act of clicking a notification will also change the app
    // to have a regular activation policy. For consistency, we should do this if the user
    // does not click on the notification too.
    NSApp.setActivationPolicy(.regular)
    
    if (!state.userInitiated) {
      // And add a badge to the app's dock icon indicating one alert occurred
      NSApp.dockTile.badgeLabel = "1"
      
      // Post a user notification
      // For banner style notification alerts, this may only trigger when the app is currently inactive.
      // For alert style notification alerts, this will trigger when the app is active or inactive.
      do {
        let content = UNMutableNotificationContent()
        content.title = "A new update is available"
        content.body = "Version \(update.displayVersionString) is now available"
          
        let request = UNNotificationRequest(identifier: UPDATE_NOTIFICATION_IDENTIFIER, content: content, trigger: nil)
          
        UNUserNotificationCenter.current().add(request)
      }
    }
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    // Clear the dock badge indicator for the update
    NSApp.dockTile.badgeLabel = ""
      
    // Dismiss active update notifications if the user has given attention to the new update
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [UPDATE_NOTIFICATION_IDENTIFIER])
  }
  
  func standardUserDriverWillFinishUpdateSession() {
    AppDelegate.log.info(" >>> standardUserDriverWillFinishUpdateSession")
    // We will dismiss our gentle UI indicator if the user session for the update finishes
    /*
    titlebarAccessoryViewController?.removeFromParent()
    titlebarAccessoryViewController = nil
     */
    // Put app back in background when the user session for the update finished.
    // We don't have a convenient reason for the user to easily activate the app now.
    // Note this assumes there's no other windows for the app to show
    NSApp.setActivationPolicy(.accessory)
  }
  
  // MARK: SPUUpdaterDelegate
  
  // Request for permissions to publish notifications for update alerts
  // This delegate method will be called when Sparkle schedules an update check in the future,
  // which may be a good time to request for update permission. This will be after the user has allowed
  // Sparkle to check for updates automatically. If you need to publish notifications for other reasons,
  // then you may have a more ideal time to request for notification authorization unrelated to update checking.
  func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { granted, error in
      AppDelegate.log.info("Notification granted \(granted), error \(error)")
      // Examine granted outcome and error if desired...
    }
  }

  // MARK: UNUserNotificationCenterDelegate
  
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier == UPDATE_NOTIFICATION_IDENTIFIER && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      // If the notificaton is clicked on, make sure we bring the update in focus
      // If the app is terminated while the notification is clicked on,
      // this will launch the application and perform a new update check.
      // This can be more likely to occur if the notification alert style is Alert rather than Banner
      updaterController.checkForUpdates(nil)
    }
      
    completionHandler()
  }
}
