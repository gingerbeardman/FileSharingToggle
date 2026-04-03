import Cocoa
import Security
import ServiceManagement
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

	private var statusItem: NSStatusItem!
	private var isFileShareEnabled = false
	private var isToggling = false
	private var toggleMenuItem: NSMenuItem!
	private var helperConnection: NSXPCConnection?
	private var helperReady = false
	private var welcomeWindow: NSWindow?

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		print("Application did finish launching")

		registerLoginItemIfNeeded()
		setupStatusItem()
		setupMenu()
		setupNotificationHandlers()

		// Ensure the app doesn't show up in the Dock
		NSApp.setActivationPolicy(.accessory)

		#if DEBUG
		showWelcomeWindow()
		#else
		if !UserDefaults.standard.bool(forKey: "has_seen_welcome") {
			showWelcomeWindow()
		}
		#endif

		// Enable file sharing on launch
		toggleFileSharing(enable: true)

		print("Setup complete")
	}

	func applicationWillTerminate(_ notification: Notification) {
		print("Application will terminate")
		toggleFileSharing(enable: false, shouldBlock: true, showAlerts: false)
	}

	func setupStatusItem() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

		if let button = statusItem.button {
			print("Setting up status item button")
			if let image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Starting...") {
				button.image = image
				print("Status item image set successfully")
			} else {
				print("Failed to create system symbol image")
				button.title = "FS" // Fallback to text if image fails
			}
		} else {
			print("Failed to get status item button")
		}
	}

	func setupMenu() {
		let menu = NSMenu()

		toggleMenuItem = NSMenuItem(title: "Enable File Sharing", action: #selector(toggleFileSharingManually), keyEquivalent: "")
		menu.addItem(toggleMenuItem)
		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem(title: "Sharing Settings...", action: #selector(openSharingSettings), keyEquivalent: ""))
		menu.addItem(NSMenuItem.separator())
		let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
		menu.addItem(NSMenuItem(title: "About \(appName)…", action: #selector(showAbout), keyEquivalent: ""))
		menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

		statusItem.menu = menu
		updateMenuUI()
		print("Menu setup complete")
	}

	func setupNotificationHandlers() {
		let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
		let defaultNotificationCenter = NotificationCenter.default
		
		[
//			(workspaceNotificationCenter, NSWorkspace.willSleepNotification, #selector(onPowerDown)),
//			(workspaceNotificationCenter, NSWorkspace.didWakeNotification, #selector(onPowerUp)),
			(workspaceNotificationCenter, NSWorkspace.willPowerOffNotification, #selector(onPowerDown)),
			(defaultNotificationCenter, NSApplication.didFinishLaunchingNotification, #selector(onPowerUp))
		].forEach { (center, name, selector) in
			center.addObserver(self, selector: selector, name: name, object: nil)
		}
		
		print("Notification handlers setup complete")
	}

	@objc func onPowerDown() {
		print("Power down event detected")
		toggleFileSharing(enable: false, shouldBlock: true, showAlerts: false)
	}

	@objc func onPowerUp() {
		print("Power up event detected")
		toggleFileSharing(enable: true)
	}

	@objc func toggleFileSharingManually() {
		toggleFileSharing(enable: !isFileShareEnabled)
	}

	@objc func showAbout() {
		NSApp.activate(ignoringOtherApps: true)
		NSApp.orderFrontStandardAboutPanel(nil)
	}

	@objc func openSharingSettings() {
		if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension?Services_PersonalFileSharing") {
			NSWorkspace.shared.open(url)
		}
	}

	func toggleFileSharing(enable: Bool, shouldBlock: Bool = false, showAlerts: Bool = true) {
		guard !isToggling else { return }
		isToggling = true
		setWorkingIcon()

		let work = {
			let helperInstalled: Bool
			if showAlerts, !Thread.isMainThread {
				var result = false
				DispatchQueue.main.sync {
					result = self.ensureHelperInstalled(showAlerts: showAlerts)
				}
				helperInstalled = result
			} else {
				helperInstalled = self.ensureHelperInstalled(showAlerts: showAlerts)
			}

			guard helperInstalled else {
				DispatchQueue.main.async {
					self.isToggling = false
					self.updateMenuUI()
				}
				return
			}

			let semaphore = shouldBlock ? DispatchSemaphore(value: 0) : nil
			self.toggleViaHelper(enable: enable) { success, output in
				// Signal semaphore first (before dispatching to main) to avoid deadlock during quit
				semaphore?.signal()
				DispatchQueue.main.async {
					self.isToggling = false
					if success {
						self.isFileShareEnabled = enable
						print("File sharing \(enable ? "enabled" : "disabled") successfully")
					} else {
						self.handleCommandFailure(output: output, showAlert: showAlerts)
					}
					self.updateMenuUI()
				}
			}

			if let semaphore {
				_ = semaphore.wait(timeout: .now() + 5)
			}
		}

		if shouldBlock {
			// Flush the run loop so the icon update renders before blocking
			RunLoop.current.run(mode: .default, before: Date())
			work()
		} else {
			DispatchQueue.global(qos: .utility).async(execute: work)
		}
	}

	func updateMenuUI() {
		toggleMenuItem.title = isFileShareEnabled ? "Disable File Sharing" : "Enable File Sharing"
		if let button = statusItem.button {
			if isFileShareEnabled {
				button.image = NSImage(systemSymbolName: "folder.badge.person.crop", accessibilityDescription: "File Sharing Enabled")
			} else {
				button.image = NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: "File Sharing Disabled")
			}
		}
	}

	private func setWorkingIcon() {
		if let button = statusItem.button {
			button.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Working...")
		}
	}

	private func registerLoginItemIfNeeded() {
		if #available(macOS 13.0, *) {
			guard SMAppService.mainApp.status != .enabled else { return }
			do {
				try SMAppService.mainApp.register()
				print("Login item registered")
			} catch {
				print("Failed to register login item: \(error)")
			}
		} else {
			print("Login item registration requires macOS 13 or later")
		}
	}

	private func ensureHelperInstalled(showAlerts: Bool) -> Bool {
		if helperReady || isHelperInstalled() {
			helperReady = true
			return true
		}

		guard showAlerts else {
			return false
		}

		NSApp.activate(ignoringOtherApps: true)

		guard let authRef = createAuthorization(showAlerts: showAlerts) else {
			return false
		}

		var error: Unmanaged<CFError>?
		let blessed = SMJobBless(kSMDomainSystemLaunchd, HelperConstants.label as CFString, authRef, &error)
		AuthorizationFree(authRef, [])

		if blessed {
			helperReady = true
			return true
		}

		let message = error?.takeRetainedValue().localizedDescription ?? "Unknown error."
		handleCommandFailure(output: "SMJobBless failed: \(message)", showAlert: showAlerts)
		return false
	}

	private func isHelperInstalled() -> Bool {
		let helperPath = "/Library/PrivilegedHelperTools/\(HelperConstants.label)"
		return FileManager.default.fileExists(atPath: helperPath)
	}

	private func createAuthorization(showAlerts: Bool) -> AuthorizationRef? {
		var authRef: AuthorizationRef?
		let status = AuthorizationCreate(nil, nil, [], &authRef)
		guard status == errAuthorizationSuccess, let authRef else {
			handleCommandFailure(output: "AuthorizationCreate failed: \(status)", showAlert: showAlerts)
			return nil
		}

		var flags: AuthorizationFlags = [.extendRights, .preAuthorize]
		if showAlerts {
			flags.insert(.interactionAllowed)
		}
		var copyStatus: OSStatus = errAuthorizationInternal

		kSMRightBlessPrivilegedHelper.withCString { cString in
			var authItem = AuthorizationItem(name: cString, valueLength: 0, value: nil, flags: 0)
			withUnsafeMutablePointer(to: &authItem) { itemPointer in
				var authRights = AuthorizationRights(count: 1, items: itemPointer)
				copyStatus = AuthorizationCopyRights(authRef, &authRights, nil, flags, nil)
			}
		}

		guard copyStatus == errAuthorizationSuccess else {
			AuthorizationFree(authRef, [])
			if copyStatus == errAuthorizationDenied {
				handleCommandFailure(output: "Authorization was denied or canceled. (code \(copyStatus))", showAlert: showAlerts)
			} else {
				handleCommandFailure(output: "AuthorizationCopyRights failed: \(copyStatus)", showAlert: showAlerts)
			}
			return nil
		}

		return authRef
	}

	private func toggleViaHelper(enable: Bool, completion: @escaping (Bool, String) -> Void) {
		let connection = helperConnection ?? makeHelperConnection()
		let proxy = connection.remoteObjectProxyWithErrorHandler { error in
			completion(false, "XPC error: \(error)")
		} as? LastDanceHelperProtocol

		guard let proxy else {
			completion(false, "Failed to create XPC proxy.")
			return
		}

		proxy.toggleFileSharing(enable: enable, withReply: completion)
	}

	private func makeHelperConnection() -> NSXPCConnection {
		let connection = NSXPCConnection(machServiceName: HelperConstants.label, options: .privileged)
		connection.remoteObjectInterface = NSXPCInterface(with: LastDanceHelperProtocol.self)
		connection.invalidationHandler = { [weak self] in
			self?.helperConnection = nil
		}
		connection.resume()
		helperConnection = connection
		return connection
	}

	private func handleCommandFailure(output: String, showAlert: Bool) {
		print("Error toggling file sharing: \(output)")

		guard showAlert else { return }

		let presentAlert = {
			let alert = NSAlert()
			alert.messageText = "File Sharing change requires administrator privileges"
			alert.informativeText = """
This app needs a privileged helper (SMJobBless) to toggle File Sharing at login/shutdown.

Command output:
\(output.isEmpty ? "No output." : output)
"""
			alert.alertStyle = .warning
			alert.addButton(withTitle: "OK")
			alert.runModal()
		}

		if Thread.isMainThread {
			presentAlert()
		} else {
			DispatchQueue.main.async(execute: presentAlert)
		}
	}

	private func showWelcomeWindow() {
		let features = [
			WelcomeFeature(
				icon: "folder.badge.person.crop",
				title: "Automatic File Sharing",
				description: "Toggles Samba file sharing on and off automatically to fix macOS connectivity issues."
			),
			WelcomeFeature(
				icon: "folder.badge.gearshape",
				title: "Lives in the Menu Bar",
				description: "The folder icon in the menu bar shows the current sharing status."
			),
			WelcomeFeature(
				icon: "lock.shield",
				title: "One-Time Authorization",
				description: "Authorize once and Last Dance handles sharing toggling on shutdown and restart."
			),
		]

		let view = WelcomeView(features: features) { [weak self] in
			self?.welcomeWindow?.close()
		}

		let window = NSWindow(
			contentRect: .zero,
			styleMask: [.titled, .closable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden
		window.isMovableByWindowBackground = true
		window.contentView = NSHostingView(rootView: view)
		window.setContentSize(window.contentView!.fittingSize)
		window.center()
		window.isReleasedWhenClosed = false
		window.delegate = self

		NSApp.setActivationPolicy(.regular)
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)

		welcomeWindow = window
	}
}

extension AppDelegate: NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		guard (notification.object as? NSWindow) === welcomeWindow else { return }
		UserDefaults.standard.set(true, forKey: "has_seen_welcome")
		NSApp.setActivationPolicy(.accessory)
		welcomeWindow = nil
	}
}
