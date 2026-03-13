//
//  AuthManagerGate.swift
//  ShopwiseFrontEndUI
//
//  Created by Nicholas Castellanos on 2/2/26.
//

import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var isCheckingPreferences = false
    @State private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !auth.isSignedIn {
                AuthView()
            } else if isCheckingPreferences {
                ProgressView("Loading...")
            } else if hasCompletedOnboarding {
                ContentView()
            } else {
                NavigationStack {
                    OnboardingSurveyView {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .task {
            await auth.restoreSession()
        }
        .task(id: auth.isSignedIn) {
            await checkOnboardingStatus()
        }
    }

    private func checkOnboardingStatus() async {
        guard auth.isSignedIn else {
            hasCompletedOnboarding = false
            isCheckingPreferences = false
            return
        }

        isCheckingPreferences = true
        defer { isCheckingPreferences = false }

        do {
            let prefs = try await auth.fetchUserPreferences()
            hasCompletedOnboarding = (prefs != nil)
        } catch {
            hasCompletedOnboarding = false
        }
    }
}
