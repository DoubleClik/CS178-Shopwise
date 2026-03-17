import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject private var cartStore: CartStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Account") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text(greetingText)
                            .font(.headline)

                        Text(auth.userEmail ?? "No email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Preferences") {
                NavigationLink {
                    OnboardingSurveyView()
                } label: {
                    Label("Edit Diet & Allergies", systemImage: "slider.horizontal.3")
                }
            }

            Section("Settings") {
                Button("Location Services") {
                    openAppSettings()
                }
            }

            Section("App Info") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign Out")
                }
            }
        }
        .navigationTitle("Account & Settings")
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let version, let build {
            return "\(version) (\(build))"
        }
        return version ?? "1.0"
    }

    private var greetingText: String {
        if let name = auth.userName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Hello"
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
