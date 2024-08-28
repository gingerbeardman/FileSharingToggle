import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
	
	private var statusItem: NSStatusItem!
	private var isFileShareEnabled = false

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		print("Application did finish launching")
		
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
		
		setupMenu()
		setupPowerNotifications()
		
		// Ensure the app doesn't show up in the Dock
		NSApp.setActivationPolicy(.accessory)
		
		print("Setup complete")
	}

	func setupMenu() {
		let menu = NSMenu()
		
		menu.addItem(NSMenuItem(title: "Toggle File Sharing", action: #selector(toggleFileSharingManually), keyEquivalent: "t"))
		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
		
		statusItem.menu = menu
		print("Menu setup complete")
	}

	func setupPowerNotifications() {
		let notificationCenter = NSWorkspace.shared.notificationCenter
		notificationCenter.addObserver(self, selector: #selector(onWillPowerOff), name: NSWorkspace.willPowerOffNotification, object: nil)
		notificationCenter.addObserver(self, selector: #selector(onDidWake), name: NSWorkspace.didWakeNotification, object: nil)
	}
	
	@objc func onWillPowerOff() {
		toggleFileSharing(enable: false)
	}
	
	@objc func onDidWake() {
		toggleFileSharing(enable: true)
	}
	
	@objc func toggleFileSharingManually() {
		toggleFileSharing(enable: !isFileShareEnabled)
	}
	
	func toggleFileSharing(enable: Bool) {
		let task = Process()
		task.launchPath = "/bin/launchctl"
		task.arguments = enable ? ["load", "-w", "/System/Library/LaunchDaemons/com.apple.smbd.plist"]
								: ["unload", "-w", "/System/Library/LaunchDaemons/com.apple.smbd.plist"]
		
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
