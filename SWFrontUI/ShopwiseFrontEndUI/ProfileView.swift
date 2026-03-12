import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        List {
            Section("Account") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text(auth.userEmail ?? "No email")
                            .font(.headline)

                        Text("Signed in")
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

            Section {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign Out")
                }
            }
        }
        .navigationTitle("Profile")
    }
}
