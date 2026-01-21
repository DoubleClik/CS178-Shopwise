//
//  ContentView.swift
//  ShopwiseFrontEndUI
//
//  Created by James Chang on 1/13/26.
//

import SwiftUI
import SwiftData


struct HomeView: View {
    var body: some View {
            VStack(spacing: 16) {
                Text("Home")
                    .font(.largeTitle)
                    .bold()

                NavigationLink("Go to Profile") {
                    ProfileView()
                }

                NavigationLink("Go to Settings") {
                    SettingsView()
                }
            }
            .padding()
            .navigationTitle("Home")
        }
}

struct ProfileView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Profile")
                .font(.largeTitle)
                .bold()

            Text("This is the Profile screen.")
        }
        .padding()
        .navigationTitle("Profile")
    }
}


struct SettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.largeTitle)
                .bold()

            Text("This is the Settings screen.")
        }
        .padding()
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack{
        HomeView()
            .modelContainer(for: Item.self, inMemory: true)
    }
}
