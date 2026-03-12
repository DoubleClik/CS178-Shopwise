import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("locationEnabled") private var locationEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false

    var body: some View {
        List {
            Section("Preferences") {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                Toggle("Use Location Services", isOn: $locationEnabled)
                Toggle("Dark Mode", isOn: $darkModeEnabled)
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
}
