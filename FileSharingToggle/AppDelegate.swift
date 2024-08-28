import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

	private var statusItem: NSStatusItem!
	private var isFileShareEnabled = false

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		print("Application did finish launching")

		setupStatusItem()
		setupMenu()
		setupNotificationHandlers()

		// Ensure the app doesn't show up in the Dock
		NSApp.setActivationPolicy(.accessory)

		// Enable file sharing on launch
		toggleFileSharing(enable: true)

		print("Setup complete")
	}

	func setupStatusItem() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

		if let button = statusItem.button {
			print("Setting up status item button")
			if let image = NSImage(systemSymbolName: "network", accessibilityDescription: "File Sharing Status") {
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

		menu.addItem(NSMenuItem(title: "Toggle File Sharing", action: #selector(toggleFileSharingManually), keyEquivalent: "f"))
		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

		statusItem.menu = menu
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
		toggleFileSharing(enable: false)
	}

	@objc func onPowerUp() {
		print("Power up event detected")
		toggleFileSharing(enable: true)
	}

	@objc func toggleFileSharingManually() {
		toggleFileSharing(enable: !isFileShareEnabled)
	}

	func toggleFileSharing(enable: Bool) {
		let task = Process()
		task.launchPath = "/bin/sh"
		task.arguments = ["-c", enable ? "sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist" : "sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist"]

		let pipe = Pipe()
		task.standardOutput = pipe
		task.standardError = pipe

		do {
			try task.run()
			task.waitUntilExit()

			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			if let output = String(data: data, encoding: .utf8) {
				print("Command output: \(output)")
			}

			if task.terminationStatus == 0 {
				isFileShareEnabled = enable
				updateMenuBarIcon()
				print("File sharing \(enable ? "enabled" : "disabled") successfully")
			} else {
				print("Error toggling file sharing")
			}
		} catch {
			print("Error running command: \(error)")
		}
	}

	func updateMenuBarIcon() {
		if let button = statusItem.button {
			if isFileShareEnabled {
				button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "File Sharing Enabled")
			} else {
				button.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "File Sharing Disabled")
			}
		}
	}
}
