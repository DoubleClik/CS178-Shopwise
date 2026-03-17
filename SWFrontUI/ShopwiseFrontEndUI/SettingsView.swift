import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Preferences") {
                Button("Notification Settings") {
                    openAppSettings()
                }

                Button("Location Services") {
                    openAppSettings()
                }
            }

            Section("Support") {
                Button("Help Center") {
                    // placeholder
                }

                Button("About ShopWise") {
                    // placeholder
                }
            }

            Section("App Info") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
