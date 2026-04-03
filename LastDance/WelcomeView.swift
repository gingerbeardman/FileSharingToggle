import SwiftUI

struct WelcomeFeature {
	let icon: String
	let title: String
	let description: String
}

struct WelcomeView: View {
	var features: [WelcomeFeature]
	var onDismiss: (() -> Void)?

	private var appName: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
			?? "EQer"
	}

	var body: some View {
		VStack(spacing: 0) {
			Spacer()
				.frame(height: 12)

			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 96, height: 96)

			Text(appName)
				.font(.system(size: 24, weight: .bold))
				.padding(.top, 16)

			VStack(alignment: .leading, spacing: 16) {
				ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
					featureRow(icon: feature.icon, title: feature.title, description: feature.description)
				}
			}
			.padding(.top, 28)
			.padding(.horizontal, 8)

			Spacer()
				.frame(minHeight: 32)

			Button("Get Started") {
				onDismiss?()
			}
			.keyboardShortcut(.defaultAction)
			.controlSize(.large)

			Spacer()
				.frame(height: 32)
		}
		.padding(.horizontal, 36)
		.frame(width: 400)
	}

	private func featureRow(icon: String, title: String, description: String) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: icon)
				.font(.system(size: 18))
				.foregroundColor(.accentColor)
				.frame(width: 28, alignment: .center)
				.padding(.top, 2)
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(.body).weight(.semibold))
				Text(description)
					.font(.callout)
					.foregroundColor(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}
