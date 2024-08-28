import SwiftUI

@main
struct FileSharingToggleApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	var body: some Scene {
		Settings {
			EmptyView()
		}
	}
}
